import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lisiere_native_tts/lisiere_native_tts.dart';
import '../data/model_store.dart';
import '../domain/narration.dart';
import '../domain/pronunciation_dictionary.dart';
import '../domain/settings.dart';
import 'adaptive_prefetch.dart';
import 'audio_cache_manifest.dart';
import 'audio_preparation.dart';
import 'estimated_word_cues.dart';
import 'neural_worker.dart';
import 'qwen_speech_runtime.dart';
import 'speech_engine.dart';

class AudioReserve {
  const AudioReserve(
    this.passages,
    this.seconds, {
    this.targetPassages = 0,
    this.targetSeconds = 0,
  });
  final int passages, seconds;
  final int targetPassages, targetSeconds;
}

class _PreparedAudio {
  _PreparedAudio(this.item, Map<String, dynamic> data)
    : path = data['path'] as String,
      digest = data['digest'] as String,
      bytes = (data['bytes'] as num? ?? 0).toInt(),
      wasCached = data['cached'] == true,
      duration = Duration(milliseconds: data['durationMs'] as int),
      quality =
          data['cueQuality'] == 'acoustic'
              ? SyncQuality.acousticWord
              : SyncQuality.estimatedWord,
      cues =
          (data['cues'] as List)
              .map((v) => WordCue.fromJson(Map<String, dynamic>.from(v as Map)))
              .toList();
  final SpeechQueueItem item;
  final String path;
  final String digest;
  final int bytes;
  final bool wasCached;
  final Duration duration;
  final SyncQuality quality;
  final List<WordCue> cues;
}

/// A persistent native playlist refilled while AVQueuePlayer/ExoPlayer plays.
class NeuralSpeechEngine implements SpeechEngine, SpeechPreparationEngine {
  NeuralSpeechEngine({
    required this.models,
    required this.settings,
    required this.cache,
  }) {
    _position = _player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 30),
          maxPeriod: const Duration(milliseconds: 60),
        )
        .listen(_onPosition);
    _index = _player.currentIndexStream.listen((_) {
      if (!_active || !_ready) return;
      final current = _current;
      if (current != null && current.item.bookId != null) {
        final now = DateTime.now();
        _lastCheckpoint = now;
        unawaited(_saveCheckpoint(current, Duration.zero, now));
      }
      _onPosition(Duration.zero);
      _publishReserve();
      unawaited(_refill(_generation));
    });
    _state = _player.playerStateStream.listen((state) {
      if (!_active || !_ready || _paused) return;
      if (state.processingState == ProcessingState.completed) {
        if (_sourceEnded) {
          _finish();
        } else {
          _prefetch.recordUnderrun();
          _waitingAtEnd = true;
          _emit(
            SpeechEvent(phase: SpeechPhase.preparing, item: _current?.item),
          );
          unawaited(_refill(_generation));
        }
      }
    });
  }
  final ModelStore models;
  final ReaderSettings settings;
  final Directory cache;
  final reserve = ValueNotifier<AudioReserve>(const AudioReserve(0, 0));
  final playback = ValueNotifier<SpeechEvent>(
    const SpeechEvent(phase: SpeechPhase.idle),
  );
  final _worker = NeuralWorker();
  final _qwen = QwenSpeechRuntime();
  final _prefetch = AdaptivePrefetchPolicy();
  late final AudioCacheManifestStore cacheManifests = AudioCacheManifestStore(
    cache,
  );
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  final _events = StreamController<SpeechEvent>.broadcast();
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _queue = <_PreparedAudio>[];
  late final StreamSubscription<Duration> _position;
  late final StreamSubscription<int?> _index;
  late final StreamSubscription<PlayerState> _state;
  SpeechQueueSource? _source;
  Future<({SpeechQueueItem? item, Object? error})>? _lookahead;
  Future<void>? _refilling;
  int _generation = 0;
  bool _active = false, _paused = false, _ready = false;
  bool _sourceEnded = false, _waitingAtEnd = false;
  Object? _preparationError;
  DateTime _lastCheckpoint = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDeviceConditions = DateTime.fromMillisecondsSinceEpoch(0);
  String? warning;
  _PreparedAudio? get _current {
    final index = _player.currentIndex ?? 0;
    return index < _queue.length ? _queue[index] : null;
  }

  @override
  SpeechEngineCapabilities get capabilities => const SpeechEngineCapabilities(
    offline: true,
    seek: true,
    persistentAudio: true,
    batchPreparation: true,
    wordAlignment: true,
  );

  @override
  Stream<SpeechEvent> get events => _events.stream;

  void _emit(SpeechEvent event) {
    playback.value = event;
    _events.add(event);
  }

  Future<void> _refreshDeviceConditions() async {
    final now = DateTime.now();
    if (now.difference(_lastDeviceConditions) < const Duration(seconds: 30)) {
      return;
    }
    _lastDeviceConditions = now;
    try {
      final status = await LisiereNativeTts().powerStatus();
      _prefetch.updateDeviceConditions(
        batteryLevel: (status['batteryLevel'] as num? ?? 1).toDouble(),
        lowPower: status['lowPower'] == true,
        thermal: (status['thermal'] as num? ?? 0).toInt(),
      );
    } catch (_) {
      // Platform telemetry is advisory; playback must remain available.
    }
  }

  Future<Map<String, dynamic>> _prepare(
    SpeechQueueItem item, {
    String? ownerBookId,
  }) async {
    final hint = NarrationLanguageDetector.detect(item.narration.spoken);
    final language = switch (hint) {
      NarrationLanguageHint.french => 'fr',
      NarrationLanguageHint.english => 'en',
      NarrationLanguageHint.unknown => settings.targetLanguage.code,
    };
    final kokoroRequested = settings.engine == VoiceEngine.kokoro;
    final kokoro = kokoroRequested && language == 'en';
    final qwen = settings.engine == VoiceEngine.qwen;
    if (kokoroRequested && !kokoro && !models.neuralInstalled) {
      throw StateError(
        'Ce passage est français. Téléchargez Supertonic pour le changement automatique de langue.',
      );
    }
    if (qwen && !models.qwenInstalledFor(settings.qwenModel)) {
      throw StateError(
        'Téléchargez ${models.qwenPackFor(settings.qwenModel).title} depuis Voix.',
      );
    }
    if (!qwen && (kokoro ? !models.kokoroInstalled : !models.neuralInstalled)) {
      throw StateError(
        kokoro
            ? 'Téléchargez Kokoro depuis Voix.'
            : 'Téléchargez Supertonic depuis Voix.',
      );
    }
    final voice =
        qwen
            ? settings.qwenVoice
            : kokoro
            ? settings.kokoroVoice
            : settings.neuralVoice;
    final steps = settings.neuralSteps;
    final align =
        !kokoro && !qwen && settings.wordAlignment && models.alignmentInstalled;
    final revision = models.alignmentRevision;
    final digest =
        sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'v':
                      qwen
                          ? 'qwen3tts-${settings.qwenModel}-audire-v1'
                          : kokoro
                          ? 'kokoro82m-lisiere-v1'
                          : 'supertonic3-lisiere-v5',
                  'model':
                      qwen
                          ? models.qwenPackFor(settings.qwenModel).revision
                          : kokoro
                          ? ModelStore.kokoroRevision
                          : ModelStore.revision,
                  'language': language,
                  'voice': voice,
                  'steps': steps,
                  'narration': item.narration.toJson(),
                  'alignment': align ? revision : 'estimated-energy-v1',
                }),
              ),
            )
            .toString();
    final existing = _pending[digest];
    if (existing != null) {
      final data = await existing;
      await _recordManifest(item, data, ownerBookId: ownerBookId);
      return data;
    }
    final future = () async {
      await cache.create(recursive: true);
      final path = '${cache.path}/$digest.wav';
      if (await File(path).exists() && await File('$path.json').exists()) {
        try {
          final data =
              jsonDecode(await File('$path.json').readAsString())
                  as Map<String, dynamic>;
          if (await File(path).length() > 44 &&
              (data['durationMs'] as int) > 0) {
            data['path'] = path;
            data['digest'] = digest;
            data['bytes'] = await File(path).length();
            data['cached'] = true;
            await _recordManifest(item, data, ownerBookId: ownerBookId);
            await File(path).setLastModified(DateTime.now());
            return data;
          }
        } catch (_) {
          /* Regenerate corrupt cache entries atomically. */
        }
      }
      final stopwatch = Stopwatch()..start();
      late final Map<String, dynamic> data;
      if (qwen) {
        data = await _qwen.generate(
          modelPath: models.qwenPathFor(settings.qwenModel),
          text: item.narration.spoken,
          speaker: voice,
          language: language == 'fr' ? 'french' : 'english',
          wavePath: path,
        );
        final durationMs = (data['durationMs'] as num? ?? 0).toInt();
        data['path'] = path;
        data['cues'] =
            estimateWordCuesFromDuration(
              durationMs,
              item.narration.spoken,
            ).map((cue) => cue.toJson()).toList();
        data['cueQuality'] = 'estimated';
        data['warning'] = null;
        final metadata = File('$path.json.part');
        await metadata.writeAsString(jsonEncode(data), flush: true);
        final destination = File('$path.json');
        if (await destination.exists()) await destination.delete();
        await metadata.rename(destination.path);
      } else {
        data = await _worker.request({
          'op': 'generate',
          'engine': kokoro ? 'kokoro' : 'supertonic',
          'modelPath': kokoro ? models.kokoroPath : models.neuralPath,
          'narration': item.narration.toJson(),
          'voice': voice,
          'steps': steps,
          'language': language,
          'wavePath': path,
          'alignmentPath': align ? models.alignmentPath : null,
          'alignmentRevision': revision,
        });
      }
      stopwatch.stop();
      data['digest'] = digest;
      data['bytes'] = await File(path).length();
      data['cached'] = false;
      _prefetch.recordPrepared(
        audioDuration: Duration(milliseconds: data['durationMs'] as int),
        generationTime: stopwatch.elapsed,
      );
      await _recordManifest(item, data, ownerBookId: ownerBookId);
      return data;
    }();
    _pending[digest] = future;
    try {
      return await future;
    } finally {
      _pending.remove(digest);
    }
  }

  Future<void> _recordManifest(
    SpeechQueueItem item,
    Map<String, dynamic> data, {
    String? ownerBookId,
  }) async {
    final bookId = ownerBookId ?? item.bookId;
    if (bookId == null || bookId.isEmpty) return;
    final quality =
        data['cueQuality'] == 'acoustic'
            ? SyncQuality.acousticWord
            : SyncQuality.estimatedWord;
    await cacheManifests.record(
      bookId,
      AudioCacheEntry(
        id: item.stableId,
        digest: data['digest'] as String,
        chapter: item.chapter,
        segment: item.segment,
        durationMs: data['durationMs'] as int,
        bytes: (data['bytes'] as num).toInt(),
        quality: quality,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> speak(NarrationText text) {
    var supplied = false;
    return startQueue(() async {
      if (supplied) return null;
      supplied = true;
      return SpeechQueueItem(narration: text);
    });
  }

  @override
  Future<void> startQueue(
    SpeechQueueSource source, {
    Duration initialPosition = Duration.zero,
  }) async {
    await stop();
    final token = _generation;
    _source = source;
    _active = true;
    _sourceEnded = false;
    _preparationError = null;
    warning = null;
    _emit(const SpeechEvent(phase: SpeechPhase.preparing));
    int? backgroundTask;
    try {
      if (Platform.isIOS) {
        backgroundTask = await LisiereNativeTts().beginAudioPreparation();
      }
      // Start with a safe floor. The rolling policy expands this reserve after
      // observing actual inference and narration durations on this device.
      await _refreshDeviceConditions();
      final target = _prefetch.target(settings.speed);
      var seconds = 0.0;
      while (token == _generation &&
          !_sourceEnded &&
          (_queue.length < target.minimumPassages + 1 || seconds < 24) &&
          _queue.length < 10) {
        final next = await _nextItem(token);
        if (token != _generation) return;
        if (next == null) {
          _sourceEnded = true;
          break;
        }
        final rendered = _PreparedAudio(next, await _prepare(next));
        if (token != _generation) return;
        _queue.add(rendered);
        seconds += rendered.duration.inMilliseconds / 1000;
        _publishReserve();
      }
      if (token != _generation) return;
      if (_queue.isEmpty) {
        _finish();
        return;
      }
      final resume =
          initialPosition < _queue.first.duration
              ? initialPosition
              : Duration.zero;
      await _player.setAudioSources([
        for (final entry in _queue) AudioSource.file(entry.path),
      ], initialPosition: resume);
      if (token != _generation) return;
      await _player.setSpeed(settings.speed);
      _ready = true;
      if (!_paused) {
        _onPosition(resume);
        unawaited(_play(token));
      }
      unawaited(_refill(token));
    } catch (e) {
      _fail(e, token);
    } finally {
      if (backgroundTask != null) {
        await LisiereNativeTts().endAudioPreparation(backgroundTask);
      }
    }
  }

  bool get _needsRefill {
    final ahead = _queue.skip((_player.currentIndex ?? 0) + 1).toList();
    final milliseconds = ahead.fold<int>(
      0,
      (sum, entry) => sum + entry.duration.inMilliseconds,
    );
    final target = _prefetch.target(settings.speed);
    return ahead.length < target.targetPassages &&
        (ahead.length < target.minimumPassages ||
            milliseconds <
                target.targetDuration.inMilliseconds * settings.speed);
  }

  Future<SpeechQueueItem?> _nextItem(int token) async {
    if (token != _generation) return null;
    Future<({SpeechQueueItem? item, Object? error})> request() async {
      try {
        return (item: await _source!(), error: null);
      } catch (e) {
        return (item: null, error: e);
      }
    }

    final result = await (_lookahead ?? request());
    if (token != _generation) return null;
    _lookahead = null;
    if (result.error != null) throw result.error!;
    // Translate N+1 while ONNX generates N. Only one translation is in flight.
    if (result.item != null) _lookahead = request();
    return result.item;
  }

  Future<void> _refill(int token) async {
    if (_refilling != null || token != _generation) return;
    final operation = _fill(token);
    _refilling = operation;
    try {
      await operation;
    } finally {
      if (identical(_refilling, operation)) _refilling = null;
    }
  }

  Future<void> _fill(int token) async {
    int? backgroundTask;
    try {
      await _refreshDeviceConditions();
      if (Platform.isIOS) {
        backgroundTask = await LisiereNativeTts().beginAudioPreparation();
      }
      while (token == _generation && _active && !_sourceEnded && _needsRefill) {
        final next = await _nextItem(token);
        if (token != _generation) return;
        if (next == null) {
          _sourceEnded = true;
          if (_waitingAtEnd) _finish();
          break;
        }
        final rendered = _PreparedAudio(next, await _prepare(next));
        if (token != _generation) return;
        await _compactPlaylist();
        final nextIndex = _queue.length;
        _queue.add(rendered);
        await _player.addAudioSource(AudioSource.file(rendered.path));
        if (token != _generation) return;
        if (_waitingAtEnd) {
          _prefetch.recordUnderrun();
          _waitingAtEnd = false;
          await _player.seek(Duration.zero, index: nextIndex);
          if (!_paused) unawaited(_play(token));
        }
        _publishReserve();
      }
    } catch (e) {
      if (token == _generation) {
        // Do not silently skip a failed passage or report the book as complete.
        _preparationError = e;
        _sourceEnded = true;
        warning =
            'La suite n’a pas pu être préparée. Relancez la lecture pour réessayer.';
        if (_waitingAtEnd) _fail(e, token);
      }
    } finally {
      if (backgroundTask != null) {
        await LisiereNativeTts().endAudioPreparation(backgroundTask);
      }
    }
  }

  Future<void> _compactPlaylist() async {
    if (!_ready) return;
    final target = _prefetch.target(settings.speed);
    final current = _player.currentIndex ?? 0;
    if (_queue.length < target.maximumPlaylistItems || current <= 12) return;
    final remove = math.min(
      current - 8,
      _queue.length - target.maximumPlaylistItems + 1,
    );
    if (remove <= 0) return;
    await _player.removeAudioSourceRange(0, remove);
    _queue.removeRange(0, remove);
  }

  void _finish() {
    if (_preparationError != null) {
      _fail(_preparationError!, _generation);
      return;
    }
    _active = false;
    _emit(const SpeechEvent(phase: SpeechPhase.completed));
    unawaited(_prune());
  }

  void _publishReserve() {
    final ahead = _queue.skip(_ready ? (_player.currentIndex ?? 0) + 1 : 0);
    final target = _prefetch.target(settings.speed);
    reserve.value = AudioReserve(
      ahead.length,
      ahead.fold<int>(0, (sum, entry) => sum + entry.duration.inSeconds),
      targetPassages: target.targetPassages,
      targetSeconds: target.targetDuration.inSeconds,
    );
  }

  Future<void> _play(int token) async {
    try {
      await _player.play();
    } catch (e) {
      _fail(e, token);
    }
  }

  void _fail(Object error, int token) {
    if (token != _generation) return;
    _active = false;
    unawaited(_player.pause());
    _emit(SpeechEvent(phase: SpeechPhase.error, message: '$error'));
  }

  void _onPosition(Duration time) {
    final current = _current;
    if (!_active || _paused || !_ready || current == null) return;
    final cues = current.cues, ms = time.inMilliseconds;
    var lo = 0, hi = cues.length - 1, index = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (cues[mid].startMs <= ms) {
        index = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // Keep the last word visible through natural punctuation pauses.
    final range =
        index < 0 ? null : SourceRange(cues[index].start, cues[index].end);
    final bookId = current.item.bookId;
    final now = DateTime.now();
    if (bookId != null &&
        now.difference(_lastCheckpoint) >= const Duration(seconds: 1)) {
      _lastCheckpoint = now;
      unawaited(_saveCheckpoint(current, time, now));
    }
    _emit(
      SpeechEvent(
        phase: SpeechPhase.playing,
        item: current.item,
        position: time,
        duration: current.duration,
        bufferedPosition: current.duration,
        quality: current.quality,
        spokenRange: range,
        range:
            range == null
                ? null
                : current.item.narration.displayRange(range.start, range.end),
        message: warning,
      ),
    );
  }

  Future<void> _saveCheckpoint(
    _PreparedAudio current,
    Duration position,
    DateTime updatedAt,
  ) async {
    final bookId = current.item.bookId;
    if (bookId == null) return;
    await cacheManifests.saveCheckpoint(
      AudioPlaybackCheckpoint(
        bookId: bookId,
        entryId: current.item.stableId,
        chapter: current.item.chapter,
        segment: current.item.segment,
        position: position,
        duration: current.duration,
        audioSignature: current.item.audioSignature,
        updatedAt: updatedAt.toUtc(),
      ),
    );
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _player.pause();
    final current = _current;
    if (current != null) {
      await _saveCheckpoint(current, _player.position, DateTime.now());
    }
    _emit(
      SpeechEvent(
        phase: SpeechPhase.paused,
        item: _current?.item,
        position: _player.position,
        duration: current?.duration ?? Duration.zero,
        bufferedPosition: current?.duration ?? Duration.zero,
      ),
    );
  }

  @override
  Future<void> resume() async {
    if (!_active) return;
    _paused = false;
    if (_ready) {
      _onPosition(_player.position);
      unawaited(_play(_generation));
    } else {
      _emit(const SpeechEvent(phase: SpeechPhase.preparing));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final current = _current;
    if (!_ready || current == null) return;
    final maximum =
        current.duration > const Duration(milliseconds: 20)
            ? current.duration - const Duration(milliseconds: 20)
            : Duration.zero;
    final target =
        position < Duration.zero
            ? Duration.zero
            : position > maximum
            ? maximum
            : position;
    await _player.seek(target);
    _onPosition(target);
  }

  @override
  Future<void> stop() async {
    final token = ++_generation;
    final current = _current;
    _active = false;
    if (current != null) {
      await _saveCheckpoint(current, _player.position, DateTime.now());
    }
    _paused = false;
    _ready = false;
    _waitingAtEnd = false;
    _refilling = null;
    _source = null;
    _lookahead = null;
    await _player.stop();
    if (token != _generation) return;
    _queue.clear();
    reserve.value = const AudioReserve(0, 0);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (_ready) unawaited(_refill(_generation));
  }

  @override
  Future<AudioPreparationEstimate> estimatePreparation(
    AudioPreparationRequest request,
  ) async {
    final current = await cacheManifests.info(request.bookId);
    final all = await cacheManifests.list();
    var knownBytes = 0;
    var knownPassages = 0;
    for (final info in all) {
      knownBytes += info.bytes;
      knownPassages += info.passages;
    }
    final averageBytes =
        knownPassages == 0 ? 320 * 1024 : knownBytes ~/ knownPassages;
    final expected = request.expectedPassages ?? current.passages;
    final cached = current.passages.clamp(0, expected);
    return AudioPreparationEstimate(
      passages: expected,
      cachedPassages: cached,
      cachedBytes: current.bytes,
      estimatedTotalBytes: current.bytes + (expected - cached) * averageBytes,
    );
  }

  /// Generates a chapter or an entire book without starting playback.
  /// The caller owns the source cursor and can expose this stream directly to
  /// a progress UI. Playback refill always receives priority between passages.
  @override
  Stream<AudioPreparationProgress> prepareQueue(
    SpeechQueueSource source, {
    required AudioPreparationRequest request,
    AudioPreparationCancellation? cancellation,
  }) async* {
    var completed = 0;
    var cached = 0;
    var bytes = 0;
    var duration = Duration.zero;
    int? backgroundTask;
    try {
      if (Platform.isIOS) {
        backgroundTask = await LisiereNativeTts().beginAudioPreparation();
      }
      while (cancellation?.isCancelled != true) {
        if (_active && _needsRefill) {
          await _refill(_generation);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          continue;
        }
        final supplied = await source();
        if (supplied == null) break;
        if (request.scope == AudioPreparationScope.chapter &&
            supplied.chapter != request.chapter) {
          continue;
        }
        final item = SpeechQueueItem(
          narration: supplied.narration,
          chapter: supplied.chapter,
          segment: supplied.segment,
          translation: supplied.translation,
          bookId: request.bookId,
          cacheId:
              supplied.cacheId ??
              (supplied.chapter >= 0 && supplied.segment >= 0
                  ? '${supplied.chapter}:${supplied.segment}'
                  : 'prepared:$completed'),
          audioSignature: supplied.audioSignature,
        );
        final data = await _prepare(item, ownerBookId: request.bookId);
        completed++;
        if (data['cached'] == true) cached++;
        final itemBytes = (data['bytes'] as num).toInt();
        final itemDuration = Duration(milliseconds: data['durationMs'] as int);
        bytes += itemBytes;
        duration += itemDuration;
        final expected = request.expectedPassages;
        yield AudioPreparationProgress(
          request: request,
          state: AudioPreparationState.preparing,
          completedPassages: completed,
          preparedDuration: duration,
          bytes: bytes,
          cachedPassages: cached,
          currentChapter: item.chapter,
          currentSegment: item.segment,
          estimatedBytes:
              expected == null || completed == 0
                  ? null
                  : (bytes / completed * expected).round(),
        );
      }
      yield AudioPreparationProgress(
        request: request,
        state:
            cancellation?.isCancelled == true
                ? AudioPreparationState.cancelled
                : AudioPreparationState.completed,
        completedPassages: completed,
        preparedDuration: duration,
        bytes: bytes,
        cachedPassages: cached,
        estimatedBytes: bytes,
      );
      unawaited(_prune());
    } catch (error) {
      yield AudioPreparationProgress(
        request: request,
        state: AudioPreparationState.failed,
        completedPassages: completed,
        preparedDuration: duration,
        bytes: bytes,
        cachedPassages: cached,
        message: '$error',
      );
    } finally {
      if (backgroundTask != null) {
        await LisiereNativeTts().endAudioPreparation(backgroundTask);
      }
    }
  }

  @override
  Future<AudioPlaybackCheckpoint?> restoreCheckpoint(
    String bookId, {
    String? audioSignature,
  }) async {
    final checkpoint = await cacheManifests.checkpoint(bookId);
    if (checkpoint == null) return null;
    if (audioSignature != null && checkpoint.audioSignature != audioSignature) {
      return null;
    }
    return checkpoint;
  }

  @override
  Future<AudioBookCacheInfo> bookCacheInfo(String bookId) {
    return cacheManifests.info(bookId);
  }

  @override
  Future<List<AudioBookCacheInfo>> listBookCaches() {
    return cacheManifests.list();
  }

  @override
  Future<void> setBookCachePinned(String bookId, bool pinned) {
    return cacheManifests.setPinned(bookId, pinned);
  }

  @override
  Future<void> clearBookCache(String bookId) async {
    if (_queue.any((entry) => entry.item.bookId == bookId)) await stop();
    await cacheManifests.removeBook(bookId);
  }

  Future<void> releaseModels() async {
    await stop();
    await _worker.reset();
    await _qwen.reset();
  }

  Future<void> clearCache() async {
    await stop();
    await _worker.reset();
    await cacheManifests.list();
    if (await cache.exists()) await cache.delete(recursive: true);
    await cache.create(recursive: true);
  }

  Future<void> _prune() async {
    try {
      final files =
          await cache
              .list()
              .where((e) => e is File && e.path.endsWith('.wav'))
              .cast<File>()
              .toList();
      final stats = <String, FileStat>{};
      var bytes = 0;
      for (final file in files) {
        final stat = await file.stat();
        stats[file.path] = stat;
        bytes += stat.size;
      }
      files.sort(
        (a, b) => stats[a.path]!.modified.compareTo(stats[b.path]!.modified),
      );
      final protected = {
        ..._queue.map((e) => e.path),
        for (final key in _pending.keys) '${cache.path}/$key.wav',
        for (final digest in await cacheManifests.referencedDigests(
          pinnedOnly: true,
        ))
          '${cache.path}/$digest.wav',
      };
      final evicted = <String>{};
      for (final file in files) {
        if (bytes <= 512 * 1024 * 1024) break;
        if (protected.contains(file.path)) continue;
        bytes -= stats[file.path]!.size;
        await file.delete();
        evicted.add(
          file.uri.pathSegments.last.replaceFirst(RegExp(r'\.wav$'), ''),
        );
        final metadata = File('${file.path}.json');
        if (await metadata.exists()) await metadata.delete();
      }
      await cacheManifests.forgetDigests(evicted);
    } catch (_) {
      /* Eviction cannot interrupt narration. */
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _position.cancel();
    await _index.cancel();
    await _state.cancel();
    await _player.dispose();
    await _worker.close();
    await _qwen.reset();
    await _events.close();
    reserve.dispose();
    playback.dispose();
  }
}
