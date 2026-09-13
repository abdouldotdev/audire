import 'dart:async';
import 'package:lisiere_native_tts/lisiere_native_tts.dart';
import '../domain/narration.dart';
import 'speech_engine.dart';

class _NativeItem {
  _NativeItem(this.id, this.item);
  String id;
  final SpeechQueueItem item;
  int base = 0, lastStart = 0, lastEnd = 0;
  bool submitted = false;
}

class NativeSpeechEngine implements SpeechEngine {
  NativeSpeechEngine() {
    _subscription = _native.events.listen(
      _onEvent,
      onError:
          (Object e) =>
              _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e')),
    );
  }
  final _native = LisiereNativeTts();
  final _events = StreamController<SpeechEvent>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final _queue = <_NativeItem>[];
  SpeechQueueSource? _source;
  int _serial = 0, _generation = 0;
  Future<void>? _filling;
  String? voiceId;
  String language = 'fr';
  double _speed = 1;
  bool _paused = false, _ended = false;
  bool _nativePaused = false;
  Object? _failure;
  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  SpeechEngineCapabilities get capabilities => const SpeechEngineCapabilities(
    offline: true,
    seek: false,
    persistentAudio: false,
    batchPreparation: false,
    wordAlignment: true,
  );
  Future<List<LocalVoice>> voices() async =>
      (await _native.voices()).map(LocalVoice.fromJson).toList();

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
    _source = source;
    _ended = false;
    _failure = null;
    _events.add(const SpeechEvent(phase: SpeechPhase.preparing));
    await _fill(_generation);
  }

  Future<void> _fill(int token) async {
    if (_filling != null) return;
    final operation = () async {
      try {
        while (token == _generation &&
            !_ended &&
            _queue.length < 20 &&
            _queue.fold<int>(
                  0,
                  (sum, entry) =>
                      sum + entry.item.narration.spoken.length - entry.base,
                ) <
                6000) {
          final item = await _source!();
          if (token != _generation) return;
          if (item == null) {
            _ended = true;
            break;
          }
          _queue.add(_NativeItem('${++_serial}', item));
          // Submit immediately, then continue resolving translations ahead of
          // the synthesizer. Waiting for the whole reserve caused long starts.
          await _submit(token);
        }
        if (token != _generation) return;
        _completeIfEmpty();
      } catch (e) {
        if (token == _generation) {
          _failure = e;
          _ended = true;
          _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e'));
          unawaited(_native.stop());
        }
      }
    }();
    _filling = operation;
    try {
      await operation;
    } finally {
      if (identical(_filling, operation)) _filling = null;
    }
  }

  Future<void> _submit(int token) async {
    for (final entry in List<_NativeItem>.of(_queue)) {
      if (token != _generation || _paused) return;
      if (entry.submitted) continue;
      entry.submitted = true;
      await _native.speak(
        id: entry.id,
        text: entry.item.narration.spoken.substring(entry.base),
        language: language,
        voiceId: voiceId,
        speed: _speed,
        enqueue: true,
      );
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (_paused) return;
    final matches = _queue.where((entry) => entry.id == event['id']);
    if (matches.isEmpty) return;
    final entry = matches.first, text = entry.item.narration;
    switch (event['type']) {
      case 'start':
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.playing,
            item: entry.item,
            range: text.displayRange(entry.base, text.spoken.length),
          ),
        );
      case 'range':
        final start = (event['start'] as int) + entry.base;
        final end = (event['end'] as int) + entry.base;
        entry.lastStart = start;
        entry.lastEnd = end;
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.playing,
            item: entry.item,
            quality: SyncQuality.nativeWord,
            spokenRange: SourceRange(start, end),
            range: text.displayRange(start, end),
          ),
        );
      case 'done':
        _queue.remove(entry);
        if (_queue.isEmpty && !_ended) {
          _events.add(const SpeechEvent(phase: SpeechPhase.preparing));
        }
        _completeIfEmpty();
        if (!_ended) unawaited(_fill(_generation));
      case 'error':
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.error,
            message:
                event['message'] as String? ??
                'La voix du téléphone est indisponible.',
          ),
        );
    }
  }

  void _completeIfEmpty() {
    if (_queue.isNotEmpty || !_ended) return;
    _events.add(
      SpeechEvent(
        phase: _failure == null ? SpeechPhase.completed : SpeechPhase.error,
        message: _failure?.toString(),
      ),
    );
  }

  @override
  Future<void> pause() async {
    _paused = true;
    _nativePaused = await _native.pause();
    if (!_nativePaused) {
      for (final entry in _queue) {
        entry.id = '${++_serial}';
        // Range callbacks arrive at word boundaries. Continuing after the last
        // delivered range avoids the duplicated syllable caused by replaying
        // lastStart after Android's stop-based pause.
        entry.base = entry.lastEnd.clamp(0, entry.item.narration.spoken.length);
        entry.lastStart = entry.base;
        entry.lastEnd = entry.base;
        entry.submitted = false;
      }
    }
    _events.add(const SpeechEvent(phase: SpeechPhase.paused));
  }

  @override
  Future<void> resume() async {
    _paused = false;
    if (_nativePaused && await _native.resume()) {
      _nativePaused = false;
      return;
    }
    _nativePaused = false;
    await _submit(_generation);
    if (_source != null && !_ended) unawaited(_fill(_generation));
  }

  @override
  Future<void> seek(Duration position) async {
    // Native TTS does not expose a stable time axis. The controller should
    // restart at a selected passage instead of pretending an inaccurate seek.
  }

  @override
  Future<void> stop() async {
    _generation++;
    _source = null;
    _queue.clear();
    _filling = null;
    _paused = false;
    _nativePaused = false;
    await _native.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_queue.isNotEmpty && !_paused) {
      await pause();
      await resume();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _subscription.cancel();
    await _events.close();
  }
}
