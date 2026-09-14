import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import '../audio/native_speech_engine.dart';
import '../audio/neural_speech_engine.dart';
import '../audio/audio_cache_manifest.dart';
import '../audio/audio_preparation.dart';
import '../audio/speech_engine.dart';
import '../data/library_store.dart';
import '../data/model_store.dart';
import '../domain/book.dart';
import '../domain/narration.dart';
import '../domain/settings.dart';
import '../translation/local_translation_engine.dart';

/// One owner for playback intent, focus, progress and engine switching.
/// Long inference never holds the command queue: stop/pause remain responsive.
class ReaderController extends ChangeNotifier with WidgetsBindingObserver {
  ReaderController({
    required this.library,
    required this.models,
    required this.translator,
    required this.native,
    required this.neural,
  }) {
    _subscriptions.add(
      native.events.listen((e) => _onEvent(VoiceEngine.system, e)),
    );
    _subscriptions.add(
      neural.events.listen(
        (e) => _onEvent(
          settings.engine == VoiceEngine.kokoro
              ? VoiceEngine.kokoro
              : settings.engine == VoiceEngine.qwen
              ? VoiceEngine.qwen
              : VoiceEngine.neural,
          e,
        ),
      ),
    );
    neural.reserve.addListener(_bufferChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final LibraryStore library;
  final ModelStore models;
  final NativeSpeechEngine native;
  final NeuralSpeechEngine neural;
  final LocalTranslationEngine translator;
  final readingTick = ValueNotifier<SpeechEvent>(
    const SpeechEvent(phase: SpeechPhase.idle),
  );
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _planner = NarrationPlanner();
  AudioSession? _session;
  Future<void> _commands = Future.value();
  ReadingBook? book;
  List<SpeechSegment> segments = [];
  List<LocalVoice> systemVoices = [];
  int chapterIndex = 0, segmentIndex = 0;
  SpeechPhase phase = SpeechPhase.idle;
  SyncQuality quality = SyncQuality.sentence;
  String? message;
  String? activeTranslation;
  AudioPreparationProgress? audioPreparation;
  AudioBookCacheInfo? activeBookCache;
  AudioPreparationCancellation? _preparationCancellation;
  bool previewing = false,
      _intent = false,
      _acceptEvents = false,
      _resumeAfterInterruption = false;
  int _speechTicket = 0;
  Duration _audioPosition = Duration.zero;
  DateTime _lastCheckpoint = DateTime.now();
  int get bufferedPassages =>
      activeEngine != VoiceEngine.system ? neural.reserve.value.passages : 0;
  int get bufferedSeconds =>
      activeEngine != VoiceEngine.system ? neural.reserve.value.seconds : 0;
  String get _audioKey =>
      'v5:${activeEngine.name}:${switch (activeEngine) {
        VoiceEngine.kokoro => settings.kokoroVoice,
        VoiceEngine.qwen => '${settings.qwenModel}:${settings.qwenVoice}',
        _ => settings.neuralVoice,
      }}:${settings.neuralSteps}:${settings.sourceLanguage.code}:${settings.targetLanguage.code}';
  void _bufferChanged() => notifyListeners();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _save();
  }

  bool loadingVoices = false;
  ReaderSettings get settings => library.settings;
  VoiceEngine get activeEngine {
    if (settings.engine == VoiceEngine.kokoro &&
        settings.targetLanguage != ReaderLanguage.english) {
      return VoiceEngine.system;
    }
    if (settings.engine == VoiceEngine.qwen &&
        (!models.qwenSupported ||
            !models.qwenPackSupported(settings.qwenModel) ||
            !models.qwenInstalledFor(settings.qwenModel))) {
      return VoiceEngine.system;
    }
    return settings.engine;
  }

  SpeechEngine get _engine =>
      activeEngine == VoiceEngine.system ? native : neural;
  BookChapter? get chapter =>
      book == null ? null : book!.chapters[chapterIndex];
  SpeechSegment? get segment =>
      segments.isEmpty ? null : segments[segmentIndex];
  bool get active =>
      phase == SpeechPhase.playing || phase == SpeechPhase.preparing;
  bool get hasSession => book != null || previewing;
  bool get wantsPlayback => _intent;
  double get chapterProgress =>
      segments.isEmpty
          ? 0
          : (segmentIndex / segments.length).clamp(0, 1).toDouble();
  String get voiceLabel {
    if (activeEngine == VoiceEngine.neural) {
      return 'Supertonic · ${settings.neuralVoice}';
    }
    if (activeEngine == VoiceEngine.kokoro) {
      return 'Kokoro · ${settings.kokoroVoice}';
    }
    if (activeEngine == VoiceEngine.qwen) {
      return '${models.qwenPackFor(settings.qwenModel).title} · ${settings.qwenVoice}';
    }
    final selected = settings.systemVoiceFor(settings.targetLanguage);
    final matches = systemVoices.where((v) => v.id == selected);
    return matches.isEmpty ? 'Voix du téléphone' : matches.first.name;
  }

  ReaderLanguage get suggestedSourceLanguage =>
      ReaderLanguageLabel.fromCode(book?.language);

  bool get needsLanguageChoice =>
      book != null && settings.languagePromptBookId != book!.id;

  Future<String?> playbackBlocker({
    required ReaderLanguage source,
    required ReaderLanguage target,
  }) async {
    if (source == target) return null;
    if (source == ReaderLanguage.english && target == ReaderLanguage.french) {
      return translator.enFrUnavailableReason();
    }
    return 'La traduction français → anglais n’est pas encore disponible. Choisissez une voix française pour un livre français, ou une voix anglaise pour un livre anglais.';
  }

  Iterable<LocalVoice> voicesFor(ReaderLanguage language) => systemVoices.where(
    (v) => v.language.toLowerCase().startsWith(language.code),
  );

  String get syncLabel => switch (quality) {
    SyncQuality.nativeWord => 'Mot à mot · système',
    SyncQuality.acousticWord => 'Mot à mot · audio aligné',
    SyncQuality.estimatedWord => 'Suivi mot à mot · estimé',
    SyncQuality.sentence => 'Suivi par phrase',
  };

  Future<void> initialize() async {
    _session = await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.speech());
    _subscriptions.add(
      _session!.interruptionEventStream.listen((event) {
        if (event.begin) {
          _resumeAfterInterruption = _intent;
          unawaited(pause(fromInterruption: true));
        } else {
          final resume =
              _resumeAfterInterruption &&
              event.type != AudioInterruptionType.unknown;
          _resumeAfterInterruption = false;
          if (resume) unawaited(play());
        }
      }),
    );
    _subscriptions.add(
      _session!.becomingNoisyEventStream.listen((_) {
        unawaited(pause());
      }),
    );
    await reloadVoices();
  }

  Future<void> reloadVoices() async {
    loadingVoices = true;
    notifyListeners();
    try {
      systemVoices = await native.voices().timeout(const Duration(seconds: 15));
      for (final language in ReaderLanguage.values) {
        final selected = settings.systemVoiceFor(language);
        if (selected != null && !systemVoices.any((v) => v.id == selected)) {
          settings.setSystemVoice(language, null);
        }
      }
    } catch (e) {
      message = '$e';
    } finally {
      loadingVoices = false;
      notifyListeners();
    }
  }

  Future<void> _enqueue(Future<void> Function() command) {
    final result = _commands.then((_) => command());
    _commands = result.catchError((Object e) {
      _fail(e);
    });
    // Handle each failure once, and keep the queue usable after an error.
    return _commands;
  }

  void _fail(Object error) {
    _intent = false;
    _acceptEvents = false;
    phase = SpeechPhase.error;
    message = error.toString().replaceFirst(
      RegExp(r'^(Bad state:|Exception:)\s*'),
      '',
    );
    readingTick.value = SpeechEvent(phase: phase, message: message);
    unawaited(_deactivate());
    notifyListeners();
  }

  Future<void> _deactivate() async {
    try {
      await _session?.setActive(false);
    } catch (_) {
      /* OS may already have revoked focus. */
    }
  }

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  void libraryChanged() => notifyListeners();

  Future<void> open(
    ReadingBook selected, {
    bool autoplay = false,
  }) => _enqueue(() async {
    if (book?.id == selected.id && !previewing) {
      if (autoplay && !active) await _play();
      return;
    }
    await _stop();
    book = selected;
    previewing = false;
    final position = library.positions[selected.id] ?? const ReadingPosition();
    final audioCheckpoint =
        activeEngine == VoiceEngine.system
            ? null
            : await neural.restoreCheckpoint(
              selected.id,
              audioSignature: _audioKey,
            );
    chapterIndex =
        (audioCheckpoint?.chapter ?? position.chapter)
            .clamp(0, selected.chapters.length - 1)
            .toInt();
    _plan();
    segmentIndex =
        segments.isEmpty
            ? 0
            : (audioCheckpoint?.segment ?? position.segment)
                .clamp(0, segments.length - 1)
                .toInt();
    _audioPosition =
        audioCheckpoint?.position ??
        (position.audioKey == _audioKey
            ? Duration(milliseconds: position.audioMs)
            : Duration.zero);
    activeBookCache = await neural.bookCacheInfo(selected.id);
    message = selected.warnings.isEmpty ? null : selected.warnings.join('\n');
    notifyListeners();
    if (autoplay) await _startSegment();
  });
  void _plan() {
    segments =
        chapter == null
            ? []
            : _planner.plan(
              chapter!,
              readNotes: settings.readNotes,
              readHeadings: settings.readHeadings,
            );
    segmentIndex =
        segments.isEmpty
            ? 0
            : segmentIndex.clamp(0, segments.length - 1).toInt();
    readingTick.value = const SpeechEvent(phase: SpeechPhase.idle);
    activeTranslation = null;
  }

  void _save() {
    final current = book;
    if (current != null && !previewing) {
      library.positions[current.id] = ReadingPosition(
        chapter: chapterIndex,
        segment: segmentIndex,
        audioMs: _audioPosition.inMilliseconds,
        audioKey: _audioKey,
      );
    }
    unawaited(
      library.save().catchError((Object e) {
        message = 'La position n’a pas pu être enregistrée : $e';
        notifyListeners();
      }),
    );
  }

  Future<void> toggle() => active ? pause() : play();
  Future<void> play() => _enqueue(_play);
  Future<void> _play() async {
    if (active) return;
    if (phase == SpeechPhase.paused && _acceptEvents) {
      if (!await _activate()) return;
      _intent = true;
      phase = SpeechPhase.preparing;
      notifyListeners();
      await _engine.resume();
    } else if (!previewing) {
      await _startSegment();
    }
  }

  Future<bool> _activate() async {
    if (_session == null || !await _session!.setActive(true)) {
      _fail(
        StateError(
          'La sortie audio est occupée. Réessayez après l’appel ou l’autre lecture.',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _startSegment() async {
    // Empty chapters (only excluded notes/headings) are skipped safely.
    while (segments.isEmpty &&
        book != null &&
        chapterIndex + 1 < book!.chapters.length) {
      chapterIndex++;
      segmentIndex = 0;
      _plan();
    }
    final next = segment;
    if (next == null) {
      phase = SpeechPhase.completed;
      _intent = false;
      notifyListeners();
      return;
    }
    _intent = true;
    previewing = false;
    _acceptEvents = false;
    phase = SpeechPhase.preparing;
    quality = SyncQuality.sentence;
    message = null;
    activeTranslation = null;
    readingTick.value = SpeechEvent(phase: phase);
    _save();
    notifyListeners();

    _acceptEvents = false;
    await _engine.stop();
    native.language = settings.targetLanguage.code;
    native.voiceId = settings.systemVoiceFor(settings.targetLanguage);
    await _engine.setSpeed(settings.speed);
    if (!await _activate()) return;
    _acceptEvents = true;
    final ticket = ++_speechTicket;
    unawaited(_prepareAndSpeak(ticket));
  }

  Future<void> _prepareAndSpeak(int ticket) async {
    // Capture the book/options; a later seek cancels this provider by ticket.
    final queuedBook = book!;
    final notes = settings.readNotes, headings = settings.readHeadings;
    var queuedChapter = chapterIndex, queuedSegment = segmentIndex;
    var planned = segments;
    try {
      await _engine.startQueue(() async {
        if (ticket != _speechTicket) return null;
        while (true) {
          while (queuedSegment >= planned.length) {
            if (++queuedChapter >= queuedBook.chapters.length) return null;
            queuedSegment = 0;
            planned = _planner.plan(
              queuedBook.chapters[queuedChapter],
              readNotes: notes,
              readHeadings: headings,
            );
          }
          final index = queuedSegment++;
          // Ornament-only paragraphs remain visible but do not become speech.
          if (!RegExp(
            r'[\p{L}\p{N}]',
            unicode: true,
          ).hasMatch(planned[index].display)) {
            continue;
          }
          final prepared = await _narrationFor(planned[index]);
          if (ticket != _speechTicket) return null;
          return SpeechQueueItem(
            narration: prepared.narration,
            chapter: queuedChapter,
            segment: index,
            translation: prepared.translation,
            bookId: queuedBook.id,
            cacheId: '$queuedChapter:$index',
            audioSignature: _audioKey,
          );
        }
      }, initialPosition: _audioPosition);
    } catch (e) {
      if (ticket == _speechTicket && _acceptEvents) _fail(e);
    }
  }

  bool get _translateCurrentBook =>
      settings.sourceLanguage == ReaderLanguage.english &&
      settings.targetLanguage == ReaderLanguage.french;

  Future<({NarrationText narration, String? translation})> _narrationFor(
    SpeechSegment source,
  ) async {
    if (settings.sourceLanguage != settings.targetLanguage &&
        !_translateCurrentBook) {
      throw StateError(
        'La traduction ${settings.sourceLanguage.label} → ${settings.targetLanguage.label} n’est pas encore disponible.',
      );
    }
    if (!_translateCurrentBook) {
      if (settings.targetLanguage == ReaderLanguage.english) {
        return (
          narration: EnglishNarration.normalize(source.display),
          translation: null,
        );
      }
      return (narration: source.narration, translation: null);
    }
    final translated = await translator.translateEnToFr(source.display);
    final normalized = FrenchNarration.normalize(translated);
    // A translated word has no exact character identity in the English source.
    // Map every spoken character to the full source sentence so the UI never
    // pretends to offer word-accurate highlighting on the untranslated text.
    return (
      narration: NarrationText(
        normalized.spoken,
        List<int>.filled(normalized.spoken.length, 0),
        List<int>.filled(normalized.spoken.length, source.display.length),
      ),
      translation: translated,
    );
  }

  Future<void> pause({bool fromInterruption = false}) => _enqueue(() async {
    if (!fromInterruption) _resumeAfterInterruption = false;
    _intent = false;
    if (active) {
      // Keep the prepared reserve and the in-flight generation on pause.
      await _engine.pause();
      phase = SpeechPhase.paused;
      notifyListeners();
    }
    if (!fromInterruption) await _deactivate();
    _save();
  });
  Future<void> stop() => _enqueue(_stop);
  Future<void> _stop() async {
    _intent = false;
    _acceptEvents = false;
    _resumeAfterInterruption = false;
    _speechTicket++;
    await Future.wait([native.stop(), neural.stop()]);
    phase = SpeechPhase.idle;
    quality = SyncQuality.sentence;
    previewing = false;
    readingTick.value = const SpeechEvent(phase: SpeechPhase.idle);
    await _deactivate();
    _save();
    notifyListeners();
  }

  void _onEvent(VoiceEngine source, SpeechEvent event) {
    if (!_acceptEvents || source != activeEngine) return;
    final item = event.item;
    var moved = false;
    if (item != null &&
        item.chapter >= 0 &&
        !previewing &&
        (event.phase == SpeechPhase.playing ||
            event.phase == SpeechPhase.paused)) {
      moved = chapterIndex != item.chapter || segmentIndex != item.segment;
      if (chapterIndex != item.chapter) {
        chapterIndex = item.chapter;
        _plan();
      }
      segmentIndex = item.segment;
      activeTranslation = item.translation;
      _audioPosition = event.position;
      if (moved || DateTime.now().difference(_lastCheckpoint).inSeconds >= 2) {
        _lastCheckpoint = DateTime.now();
        _save();
      }
    }
    final oldPhase = phase, oldQuality = quality, oldMessage = message;
    phase = event.phase;
    if (event.phase == SpeechPhase.playing) {
      quality = event.quality;
    }
    if (event.message != null) message = event.message;
    readingTick.value =
        _translateCurrentBook && event.phase == SpeechPhase.playing
            ? SpeechEvent(
              phase: event.phase,
              range: event.range,
              quality: SyncQuality.sentence,
              message: event.message,
              item: event.item,
              spokenRange: event.spokenRange,
              position: event.position,
            )
            : event;
    if (event.phase == SpeechPhase.error) {
      _intent = false;
      _acceptEvents = false;
      _speechTicket++;
      unawaited(_engine.stop());
      unawaited(_deactivate());
    }
    if (event.phase == SpeechPhase.completed) {
      if (previewing) {
        previewing = false;
        _intent = false;
        _acceptEvents = false;
        phase = SpeechPhase.idle;
        unawaited(_deactivate());
      } else if (_intent) {
        // Per-passage transitions are owned by the continuous native queue.
        // This event now means the entire source (including chapters) ended.
        _intent = false;
        _acceptEvents = false;
        _audioPosition = Duration.zero;
        _save();
        unawaited(_deactivate());
      }
    }
    if (moved ||
        oldPhase != phase ||
        oldQuality != quality ||
        oldMessage != message) {
      notifyListeners();
    }
  }

  Future<void> next() => _enqueue(() => _advance(1, autoplay: _intent));
  Future<void> previous() => _enqueue(() => _advance(-1, autoplay: _intent));
  Future<void> _advance(int delta, {required bool autoplay}) async {
    if (book == null || previewing) return;
    _audioPosition = Duration.zero;
    _acceptEvents = false;
    _speechTicket++;
    await _engine.stop();
    if (delta > 0 && segmentIndex + 1 >= segments.length) {
      if (chapterIndex + 1 >= book!.chapters.length) {
        _intent = false;
        phase = SpeechPhase.completed;
        readingTick.value = SpeechEvent(phase: phase);
        await _deactivate();
        _save();
        notifyListeners();
        return;
      }
      chapterIndex++;
      segmentIndex = 0;
      _plan();
    } else if (delta < 0 && segmentIndex == 0 && chapterIndex > 0) {
      chapterIndex--;
      _plan();
      segmentIndex = segments.isEmpty ? 0 : segments.length - 1;
    } else {
      segmentIndex =
          segments.isEmpty
              ? 0
              : (segmentIndex + delta).clamp(0, segments.length - 1).toInt();
    }
    phase = SpeechPhase.idle;
    readingTick.value = SpeechEvent(phase: phase);
    _save();
    notifyListeners();
    if (autoplay) await _startSegment();
  }

  Future<void> selectChapter(int index, {bool autoplay = false}) =>
      _enqueue(() async {
        if (book == null || index < 0 || index >= book!.chapters.length) return;
        await _stop();
        chapterIndex = index;
        segmentIndex = 0;
        _audioPosition = Duration.zero;
        _plan();
        _save();
        notifyListeners();
        if (autoplay) await _startSegment();
      });
  Future<void> selectBlock(int block) => _enqueue(() async {
    final index = segments.indexWhere((s) => s.block == block);
    if (index < 0) return;
    await _stop();
    segmentIndex = index;
    _audioPosition = Duration.zero;
    await _startSegment();
  });
  Future<void> selectSegment(int index, {bool autoplay = false}) => _enqueue(
    () async {
      if (book == null || previewing || index < 0 || index >= segments.length) {
        return;
      }
      if (index == segmentIndex && !autoplay) return;
      _acceptEvents = false;
      _speechTicket++;
      await _engine.stop();
      segmentIndex = index;
      _audioPosition = Duration.zero;
      activeTranslation = null;
      phase = SpeechPhase.idle;
      readingTick.value = SpeechEvent(phase: phase);
      _save();
      notifyListeners();
      if (autoplay) await _startSegment();
    },
  );
  Future<void> setEngine(VoiceEngine value) => _enqueue(() async {
    final resume = _intent && !previewing;
    await _stop();
    if (value == VoiceEngine.kokoro &&
        settings.targetLanguage != ReaderLanguage.english) {
      message = 'Kokoro est disponible pour la voix anglaise.';
      notifyListeners();
      return;
    }
    if (value == VoiceEngine.kokoro && !models.kokoroInstalled) {
      message = 'Téléchargez Kokoro avant de le sélectionner.';
      notifyListeners();
      return;
    }
    if (value == VoiceEngine.neural && !models.neuralInstalled) {
      message = 'Téléchargez Supertonic avant de le sélectionner.';
      _save();
      notifyListeners();
      return;
    }
    if (value == VoiceEngine.qwen && !models.qwenSupported) {
      message = models.qwenUnavailableReason;
      notifyListeners();
      return;
    }
    if (value == VoiceEngine.qwen &&
        !models.qwenInstalledFor(settings.qwenModel)) {
      message =
          'Téléchargez ${models.qwenPackFor(settings.qwenModel).title} avant de le sélectionner.';
      notifyListeners();
      return;
    }
    settings.engine = value;
    _audioPosition = Duration.zero;
    _save();
    notifyListeners();
    if (resume && book != null) await _startSegment();
  });
  Future<void> setQwenModel(String modelId) => _enqueue(() async {
    if (!models.qwenPackSupported(modelId)) {
      message = models.qwenPackUnavailableReason(modelId);
      notifyListeners();
      return;
    }
    if (!models.qwenInstalledFor(modelId)) {
      message =
          'Téléchargez ${models.qwenPackFor(modelId).title} avant de le sélectionner.';
      notifyListeners();
      return;
    }
    final resume = _intent && !previewing;
    await _stop();
    settings.qwenModel = modelId;
    settings.engine = VoiceEngine.qwen;
    _audioPosition = Duration.zero;
    _save();
    notifyListeners();
    if (resume && book != null) await _startSegment();
  });
  Future<void> selectVoice({
    String? nativeId,
    String? neuralId,
    String? kokoroId,
    String? qwenId,
    bool resumePlayback = true,
  }) => _enqueue(() async {
    final resume = resumePlayback && _intent && !previewing;
    await _stop();
    _audioPosition = Duration.zero;
    if (neuralId != null) {
      settings.neuralVoice = neuralId;
      settings.engine = VoiceEngine.neural;
    }
    if (kokoroId != null) {
      settings.kokoroVoice = kokoroId;
      settings.engine = VoiceEngine.kokoro;
    }
    if (qwenId != null) {
      settings.qwenVoice = qwenId;
      settings.engine = VoiceEngine.qwen;
    }
    if (nativeId != null) {
      settings.setSystemVoice(settings.targetLanguage, nativeId);
      settings.engine = VoiceEngine.system;
    }
    _save();
    notifyListeners();
    if (resume && book != null) await _startSegment();
  });
  Future<void> audition() => _enqueue(() async {
    await _stop();
    if (!await _activate()) return;
    previewing = true;
    _intent = true;
    _acceptEvents = true;
    native.language = settings.targetLanguage.code;
    native.voiceId = settings.systemVoiceFor(settings.targetLanguage);
    await _engine.setSpeed(settings.speed);
    phase = SpeechPhase.preparing;
    notifyListeners();
    final sampleText =
        settings.targetLanguage == ReaderLanguage.english
            ? 'The light crossed the garden. Let us take our time. Every book opens a path, and every voice invites us to follow it.'
            : 'La lumière traversait le jardin. « Prenons le temps », dit-elle. Chaque livre ouvre un chemin, et chaque voix nous invite à le parcourir.';
    final sample =
        settings.targetLanguage == ReaderLanguage.english
            ? NarrationText(
              sampleText,
              List.generate(sampleText.length, (i) => i),
              List.generate(sampleText.length, (i) => i + 1),
            )
            : FrenchNarration.normalize(sampleText);
    unawaited(
      _engine.speak(sample).catchError((Object e) {
        _fail(e);
      }),
    );
  });
  Future<void> setSpeed(double value) => _enqueue(() async {
    settings.speed = value.clamp(.65, 1.7).toDouble();
    await _engine.setSpeed(settings.speed);
    _save();
    notifyListeners();
  });
  void setFontSize(double value) {
    settings.fontSize = value.clamp(17, 32).toDouble();
    _save();
    notifyListeners();
  }

  void setTheme(PaperTheme value) {
    settings.theme = value;
    _save();
    notifyListeners();
  }

  void setAppLanguage(AppLanguage value) {
    settings.appLanguage = value;
    _save();
    notifyListeners();
  }

  void setFollow(bool value) {
    settings.followText = value;
    _save();
    notifyListeners();
  }

  void setPlayerPinned(bool value) {
    settings.playerPinned = value;
    _save();
    notifyListeners();
  }

  void completeOnboarding() {
    settings.onboardingCompleted = true;
    _save();
    notifyListeners();
  }

  Future<void> setContent({bool? notes, bool? headings}) => _enqueue(() async {
    final currentBlock = segment?.block ?? 0;
    await _stop();
    if (notes != null) settings.readNotes = notes;
    if (headings != null) settings.readHeadings = headings;
    _plan();
    final i = segments.indexWhere((s) => s.block >= currentBlock);
    segmentIndex = i < 0 ? 0 : i;
    _audioPosition = Duration.zero;
    _save();
    notifyListeners();
  });
  Future<void> setTranslationMode(TranslationMode value) => _enqueue(() async {
    final wasActive = _intent;
    await _stop();
    settings.translationMode = value;
    activeTranslation = null;
    _save();
    notifyListeners();
    if (wasActive && book != null) await _startSegment();
  });

  Future<void> setPlaybackLanguages({
    required ReaderLanguage source,
    required ReaderLanguage target,
  }) => _enqueue(() async {
    final wasActive = _intent;
    await _stop();
    settings.sourceLanguage = source;
    settings.targetLanguage = target;
    _audioPosition = Duration.zero;
    settings.languagePromptBookId = book?.id;
    if (target != ReaderLanguage.english &&
        settings.engine == VoiceEngine.kokoro) {
      settings.engine =
          models.neuralInstalled ? VoiceEngine.neural : VoiceEngine.system;
    }
    if (source == target) {
      settings.translationMode = TranslationMode.original;
    } else if (source == ReaderLanguage.english &&
        target == ReaderLanguage.french &&
        settings.translationMode == TranslationMode.original) {
      settings.translationMode = TranslationMode.frenchAudio;
    }
    activeTranslation = null;
    _save();
    notifyListeners();
    if (wasActive && book != null) await _startSegment();
  });

  Future<void> setAlignment(bool enabled) => _enqueue(() async {
    await _stop();
    settings.wordAlignment = enabled;
    _save();
    notifyListeners();
  });
  Future<void> releaseModels() => _enqueue(() async {
    await _stop();
    await neural.releaseModels();
  });
  Future<void> clearCache() => _enqueue(() async {
    await _stop();
    await Future.wait([neural.clearCache(), translator.clearCache()]);
  });

  Future<AudioPreparationEstimate?> estimateAudioPreparation(
    AudioPreparationScope scope,
  ) async {
    final selected = book;
    if (selected == null) return null;
    final expected = _preparationPassageCount(selected, scope);
    return neural.estimatePreparation(
      AudioPreparationRequest(
        bookId: selected.id,
        scope: scope,
        chapter: scope == AudioPreparationScope.chapter ? chapterIndex : null,
        expectedPassages: expected,
      ),
    );
  }

  Future<void> prepareAudio(AudioPreparationScope scope) async {
    final selected = book;
    if (selected == null ||
        audioPreparation?.state == AudioPreparationState.preparing) {
      return;
    }
    if (activeEngine == VoiceEngine.system) {
      message = 'Choisissez une voix téléchargée pour préparer l’audio.';
      notifyListeners();
      return;
    }
    final request = AudioPreparationRequest(
      bookId: selected.id,
      scope: scope,
      chapter: scope == AudioPreparationScope.chapter ? chapterIndex : null,
      expectedPassages: _preparationPassageCount(selected, scope),
    );
    final cancellation = AudioPreparationCancellation();
    _preparationCancellation = cancellation;
    final source = _preparationSource(selected, request);
    audioPreparation = AudioPreparationProgress(
      request: request,
      state: AudioPreparationState.preparing,
      completedPassages: 0,
      preparedDuration: Duration.zero,
      bytes: 0,
      cachedPassages: 0,
    );
    notifyListeners();
    await for (final progress in neural.prepareQueue(
      source,
      request: request,
      cancellation: cancellation,
    )) {
      if (!identical(_preparationCancellation, cancellation)) break;
      audioPreparation = progress;
      notifyListeners();
    }
    if (identical(_preparationCancellation, cancellation)) {
      _preparationCancellation = null;
      activeBookCache = await neural.bookCacheInfo(selected.id);
      notifyListeners();
    }
  }

  void cancelAudioPreparation() {
    _preparationCancellation?.cancel();
  }

  int _preparationPassageCount(
    ReadingBook selected,
    AudioPreparationScope scope,
  ) {
    final chapters =
        scope == AudioPreparationScope.chapter
            ? <int>[chapterIndex]
            : List<int>.generate(selected.chapters.length, (i) => i);
    var count = 0;
    for (final chapter in chapters) {
      count +=
          _planner
              .plan(
                selected.chapters[chapter],
                readNotes: settings.readNotes,
                readHeadings: settings.readHeadings,
              )
              .where(
                (segment) => RegExp(
                  r'[\p{L}\p{N}]',
                  unicode: true,
                ).hasMatch(segment.display),
              )
              .length;
    }
    return count;
  }

  SpeechQueueSource _preparationSource(
    ReadingBook selected,
    AudioPreparationRequest request,
  ) {
    var queuedChapter =
        request.scope == AudioPreparationScope.chapter ? request.chapter! : 0;
    var queuedSegment = 0;
    var planned = _planner.plan(
      selected.chapters[queuedChapter],
      readNotes: settings.readNotes,
      readHeadings: settings.readHeadings,
    );
    return () async {
      while (true) {
        while (queuedSegment >= planned.length) {
          if (request.scope == AudioPreparationScope.chapter ||
              ++queuedChapter >= selected.chapters.length) {
            return null;
          }
          queuedSegment = 0;
          planned = _planner.plan(
            selected.chapters[queuedChapter],
            readNotes: settings.readNotes,
            readHeadings: settings.readHeadings,
          );
        }
        final index = queuedSegment++;
        if (!RegExp(
          r'[\p{L}\p{N}]',
          unicode: true,
        ).hasMatch(planned[index].display)) {
          continue;
        }
        final prepared = await _narrationFor(planned[index]);
        return SpeechQueueItem(
          narration: prepared.narration,
          chapter: queuedChapter,
          segment: index,
          translation: prepared.translation,
          bookId: selected.id,
          cacheId: '$queuedChapter:$index',
          audioSignature: _audioKey,
        );
      }
    };
  }

  Future<void> refreshActiveBookCache() async {
    final selected = book;
    if (selected == null) return;
    activeBookCache = await neural.bookCacheInfo(selected.id);
    notifyListeners();
  }

  Future<void> setActiveBookCachePinned(bool pinned) async {
    final selected = book;
    if (selected == null) return;
    await neural.setBookCachePinned(selected.id, pinned);
    await refreshActiveBookCache();
  }

  Future<void> clearActiveBookCache() async {
    final selected = book;
    if (selected == null) return;
    await neural.clearBookCache(selected.id);
    audioPreparation = null;
    await refreshActiveBookCache();
  }

  Future<List<AudioBookCacheInfo>> listBookCaches() => neural.listBookCaches();
  Future<void> removeBook(ReadingBook selected) => _enqueue(() async {
    if (book?.id == selected.id) {
      await _stop();
      book = null;
      segments = [];
    }
    await library.remove(selected);
    notifyListeners();
  });
  Future<void> shutdown() async {
    await stop();
    WidgetsBinding.instance.removeObserver(this);
    neural.reserve.removeListener(_bufferChanged);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await native.dispose();
    await neural.dispose();
    readingTick.dispose();
    super.dispose();
  }
}
