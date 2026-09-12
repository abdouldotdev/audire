import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:just_audio/just_audio.dart';
import '../data/model_store.dart';
import '../domain/narration.dart';
import '../domain/settings.dart';
import 'neural_worker.dart';
import 'speech_engine.dart';

class NeuralSpeechEngine implements SpeechEngine {
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
    _state = _player.playerStateStream.listen((state) {
      if (_active &&
          _ready &&
          !_paused &&
          state.processingState == ProcessingState.completed) {
        _active = false;
        _events.add(const SpeechEvent(phase: SpeechPhase.completed));
      }
    });
  }
  final ModelStore models;
  final ReaderSettings settings;
  final Directory cache;
  final _worker = NeuralWorker();
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  final _events = StreamController<SpeechEvent>.broadcast();
  final _pending = <String, Future<Map<String, dynamic>>>{};
  late final StreamSubscription<Duration> _position;
  late final StreamSubscription<PlayerState> _state;
  List<WordCue> _cues = [];
  NarrationText? _text;
  String? _wavePath;
  int _generation = 0, _lastCue = -2;
  bool _active = false, _paused = false, _ready = false;
  String? warning;
  @override
  Stream<SpeechEvent> get events => _events.stream;

  Future<Map<String, dynamic>> _prepare(NarrationText text) async {
    if (!models.neuralInstalled) {
      throw StateError('Installez les voix neuronales dans l’onglet Voix.');
    }
    await cache.create(recursive: true);
    final align = settings.wordAlignment && models.alignmentInstalled;
    final digest =
        sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'v': 'supertonic3-lisiere-v1',
                  'model': ModelStore.revision,
                  'voice': settings.neuralVoice,
                  'steps': settings.neuralSteps,
                  'narration': text.toJson(),
                  'alignment': align ? models.alignmentRevision : 'none',
                }),
              ),
            )
            .toString();
    final path = '${cache.path}/$digest.wav';
    if (await File(path).exists() && await File('$path.json').exists()) {
      try {
        final j =
            jsonDecode(await File('$path.json').readAsString())
                as Map<String, dynamic>;
        j['path'] =
            path; // Container path may change after restoring an app backup.
        await File(path).setLastModified(DateTime.now());
        return j;
      } catch (_) {
        /* Rebuild a corrupt cache entry. */
      }
    }
    final existing = _pending[digest];
    if (existing != null) return existing;
    final future = _worker.request({
      'op': 'generate',
      'modelPath': models.neuralPath,
      'narration': text.toJson(),
      'voice': settings.neuralVoice,
      'steps': settings.neuralSteps,
      'wavePath': path,
      'alignmentPath': align ? models.alignmentPath : null,
      'alignmentRevision': models.alignmentRevision,
    });
    _pending[digest] = future;
    try {
      return await future;
    } finally {
      _pending.remove(digest);
    }
  }

  Future<void> prefetch(NarrationText text) async {
    // At most one look-ahead job. Never create an unbounded book-sized queue.
    if (_pending.isNotEmpty) return;
    try {
      await _prepare(text);
    } catch (_) {
      /* The foreground request reports errors. */
    }
  }

  @override
  Future<void> speak(NarrationText text) async {
    await stop();
    final token = ++_generation;
    _text = text;
    _active = true;
    _ready = false;
    _paused = false;
    warning = null;
    _events.add(const SpeechEvent(phase: SpeechPhase.preparing));
    try {
      final rendered = await _prepare(text);
      if (token != _generation) return;
      _cues =
          (rendered['cues'] as List)
              .map((v) => WordCue.fromJson(Map<String, dynamic>.from(v as Map)))
              .toList();
      warning = rendered['warning'] as String?;
      _wavePath = rendered['path'] as String;
      await _player.setFilePath(_wavePath!);
      if (token != _generation) return;
      await _player.setSpeed(settings.speed);
      _ready = true;
      if (!_paused) {
        _emitPlaying();
        unawaited(_play(token));
      }
      unawaited(_prune());
    } catch (e) {
      if (token == _generation) {
        _active = false;
        _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e'));
      }
    }
  }

  Future<void> _play(int token) async {
    try {
      await _player.play();
    } catch (e) {
      if (token == _generation) {
        _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e'));
      }
    }
  }

  void _emitPlaying() {
    if (_text == null) return;
    _events.add(
      SpeechEvent(
        phase: SpeechPhase.playing,
        quality:
            _cues.isEmpty ? SyncQuality.sentence : SyncQuality.acousticWord,
        range:
            _cues.isEmpty ? _text!.displayRange(0, _text!.spoken.length) : null,
        message: warning,
      ),
    );
  }

  void _onPosition(Duration time) {
    if (!_active || _paused || !_ready || _cues.isEmpty) return;
    final ms = time.inMilliseconds;
    // Binary search by media time, not wall time. Playback speed and pauses
    // therefore cannot accumulate drift against the generated audio.
    var lo = 0, hi = _cues.length - 1, index = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_cues[mid].startMs <= ms) {
        index = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (index >= 0 && ms >= _cues[index].endMs) index = -1;
    if (index == _lastCue) return;
    _lastCue = index;
    _events.add(
      SpeechEvent(
        phase: SpeechPhase.playing,
        quality: SyncQuality.acousticWord,
        range:
            index < 0
                ? null
                : SourceRange(_cues[index].start, _cues[index].end),
      ),
    );
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _player.pause();
    _events.add(const SpeechEvent(phase: SpeechPhase.paused));
  }

  @override
  Future<void> resume() async {
    if (!_active) return;
    _paused = false;
    if (_ready) {
      _emitPlaying();
      unawaited(_play(_generation));
    } else {
      _events.add(const SpeechEvent(phase: SpeechPhase.preparing));
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _active = false;
    _paused = false;
    _ready = false;
    _lastCue = -2;
    await _player.stop();
    _text = null;
    _cues = [];
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> releaseModels() async {
    await stop();
    await _worker.reset();
  }

  Future<void> clearCache() async {
    await stop();
    await _worker.reset();
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
      for (final f in files) {
        final stat = await f.stat();
        stats[f.path] = stat;
        bytes += stat.size;
      }
      files.sort(
        (a, b) => stats[a.path]!.modified.compareTo(stats[b.path]!.modified),
      );
      for (final f in files) {
        if (bytes <= 256 * 1024 * 1024) break;
        if (f.path == _wavePath || _pending.isNotEmpty) continue;
        bytes -= stats[f.path]!.size;
        await f.delete();
        final j = File('${f.path}.json');
        if (await j.exists()) await j.delete();
      }
    } catch (_) {
      /* Cache eviction is best-effort; never interrupts audio. */
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _position.cancel();
    await _state.cancel();
    await _player.dispose();
    await _worker.close();
    await _events.close();
  }
}
