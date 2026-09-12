import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import '../audio/native_speech_engine.dart';
import '../audio/neural_speech_engine.dart';
import '../audio/speech_engine.dart';
import '../data/library_store.dart';
import '../data/model_store.dart';
import '../domain/book.dart';
import '../domain/narration.dart';
import '../domain/settings.dart';

/// One owner for playback intent, focus, progress and engine switching.
/// Long inference never holds the command queue: stop/pause remain responsive.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.library,
    required this.models,
    required this.native,
    required this.neural,
  }) {
    _subscriptions.add(
      native.events.listen((e) => _onEvent(VoiceEngine.system, e)),
    );
    _subscriptions.add(
      neural.events.listen((e) => _onEvent(VoiceEngine.neural, e)),
    );
  }
  final LibraryStore library;
  final ModelStore models;
  final NativeSpeechEngine native;
  final NeuralSpeechEngine neural;
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
  bool previewing = false,
      _intent = false,
      _acceptEvents = false,
      _resumeAfterInterruption = false;
  bool loadingVoices = false;
  ReaderSettings get settings => library.settings;
  SpeechEngine get _engine =>
      settings.engine == VoiceEngine.system ? native : neural;
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
    if (settings.engine == VoiceEngine.neural) {
      return 'Supertonic · ${settings.neuralVoice}';
    }
    final matches = systemVoices.where((v) => v.id == settings.systemVoice);
    return matches.isEmpty ? 'Voix du téléphone' : matches.first.name;
  }

  String get syncLabel => switch (quality) {
    SyncQuality.nativeWord => 'Mot à mot · système',
    SyncQuality.acousticWord => 'Mot à mot · audio aligné',
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
      if (settings.systemVoice != null &&
          !systemVoices.any((v) => v.id == settings.systemVoice)) {
        settings.systemVoice = null;
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
    chapterIndex =
        position.chapter.clamp(0, selected.chapters.length - 1).toInt();
    _plan();
    segmentIndex =
        segments.isEmpty
            ? 0
            : position.segment.clamp(0, segments.length - 1).toInt();
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
  }

  void _save() {
    final current = book;
    if (current != null && !previewing) {
      library.positions[current.id] = ReadingPosition(
        chapter: chapterIndex,
        segment: segmentIndex,
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
    _acceptEvents = false;
    await _engine.stop();
    native.voiceId = settings.systemVoice;
    await _engine.setSpeed(settings.speed);
    if (!await _activate()) return;
    _intent = true;
    previewing = false;
    _acceptEvents = true;
    phase = SpeechPhase.preparing;
    quality = SyncQuality.sentence;
    message = null;
    readingTick.value = SpeechEvent(phase: phase);
    _save();
    notifyListeners();
    unawaited(
      _engine.speak(next.narration).catchError((Object e) {
        _fail(e);
      }),
    );
  }

  Future<void> pause({bool fromInterruption = false}) => _enqueue(() async {
    if (!fromInterruption) _resumeAfterInterruption = false;
    _intent = false;
    if (active) {
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
    if (!_acceptEvents || source != settings.engine) return;
    final oldPhase = phase, oldQuality = quality, oldMessage = message;
    phase = event.phase;
    if (event.phase == SpeechPhase.playing) quality = event.quality;
    if (event.message != null) message = event.message;
    readingTick.value = event;
    if (event.phase == SpeechPhase.error) {
      _intent = false;
      _acceptEvents = false;
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
        unawaited(
          _enqueue(() async {
            if (_intent) await _advance(1, autoplay: true);
          }),
        );
      }
    }
    if (oldPhase != phase || oldQuality != quality || oldMessage != message) {
      notifyListeners();
    }
    if (event.phase == SpeechPhase.playing &&
        oldPhase != SpeechPhase.playing &&
        !previewing &&
        settings.engine == VoiceEngine.neural &&
        segmentIndex + 1 < segments.length) {
      unawaited(neural.prefetch(segments[segmentIndex + 1].narration));
    }
  }

  Future<void> next() => _enqueue(() => _advance(1, autoplay: _intent));
  Future<void> previous() => _enqueue(() => _advance(-1, autoplay: _intent));
  Future<void> _advance(int delta, {required bool autoplay}) async {
    if (book == null || previewing) return;
    _acceptEvents = false;
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
    await _startSegment();
  });
  Future<void> setEngine(VoiceEngine value) => _enqueue(() async {
    await _stop();
    settings.engine = value;
    _save();
    notifyListeners();
  });
  Future<void> selectVoice({String? nativeId, String? neuralId}) =>
      _enqueue(() async {
        await _stop();
        if (neuralId != null) {
          settings.neuralVoice = neuralId;
          settings.engine = VoiceEngine.neural;
        }
        if (nativeId != null) {
          settings.systemVoice = nativeId;
          settings.engine = VoiceEngine.system;
        }
        _save();
        notifyListeners();
      });
  Future<void> audition() => _enqueue(() async {
    await _stop();
    if (!await _activate()) return;
    previewing = true;
    _intent = true;
    _acceptEvents = true;
    native.voiceId = settings.systemVoice;
    await _engine.setSpeed(settings.speed);
    phase = SpeechPhase.preparing;
    notifyListeners();
    final sample = FrenchNarration.normalize(
      'La lumière traversait le jardin. « Prenons le temps », dit-elle. Chaque livre ouvre un chemin, et chaque voix nous invite à le parcourir.',
    );
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

  void setFollow(bool value) {
    settings.followText = value;
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
    _save();
    notifyListeners();
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
    await neural.clearCache();
  });
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
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await native.dispose();
    await neural.dispose();
    readingTick.dispose();
    super.dispose();
  }
}
