import 'dart:async';
import 'package:lisiere_native_tts/lisiere_native_tts.dart';
import '../domain/narration.dart';
import 'speech_engine.dart';

class NativeSpeechEngine implements SpeechEngine {
  NativeSpeechEngine() {
    _subscription = _native.events.listen(
      _onEvent,
      onError: (Object e) {
        _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e'));
      },
    );
  }
  final _native = LisiereNativeTts();
  final _events = StreamController<SpeechEvent>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  NarrationText? _text;
  int _serial = 0, _base = 0, _lastStart = 0;
  String? _utteranceId, voiceId;
  double _speed = 1;
  bool _hasRange = false, _paused = false;
  @override
  Stream<SpeechEvent> get events => _events.stream;

  Future<List<LocalVoice>> voices() async =>
      (await _native.voices()).map(LocalVoice.fromJson).toList();

  @override
  Future<void> speak(NarrationText text) async {
    await stop();
    _text = text;
    _base = 0;
    _lastStart = 0;
    _paused = false;
    await _start();
  }

  Future<void> _start() async {
    final text = _text;
    if (text == null) return;
    final id = '${++_serial}';
    _utteranceId = id;
    _hasRange = false;
    _events.add(const SpeechEvent(phase: SpeechPhase.preparing));
    try {
      await _native.speak(
        id: id,
        text: text.spoken.substring(_base),
        voiceId: voiceId,
        speed: _speed,
      );
    } catch (e) {
      if (_utteranceId == id) {
        _events.add(SpeechEvent(phase: SpeechPhase.error, message: '$e'));
      }
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['id'] != _utteranceId || _text == null) return;
    switch (event['type']) {
      case 'start':
        // Until a genuine boundary arrives, show a phrase, not fake word timings.
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.playing,
            range: _text!.displayRange(_base, _text!.spoken.length),
          ),
        );
      case 'range':
        final start = (event['start'] as int) + _base;
        final end = (event['end'] as int) + _base;
        _lastStart = start;
        _hasRange = true;
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.playing,
            quality: SyncQuality.nativeWord,
            range: _text!.displayRange(start, end),
          ),
        );
      case 'done':
        _utteranceId = null;
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.completed,
            quality: _hasRange ? SyncQuality.nativeWord : SyncQuality.sentence,
          ),
        );
      case 'error':
        _utteranceId = null;
        _events.add(
          SpeechEvent(
            phase: SpeechPhase.error,
            message:
                event['message'] as String? ??
                'La voix système est indisponible.',
          ),
        );
    }
  }

  @override
  Future<void> pause() async {
    if (_text == null) return;
    _utteranceId = null;
    _base = _lastStart;
    _paused = true;
    await _native.stop();
    _events.add(const SpeechEvent(phase: SpeechPhase.paused));
  }

  @override
  Future<void> resume() async {
    if (!_paused || _text == null) return;
    _paused = false;
    await _start();
  }

  @override
  Future<void> stop() async {
    _utteranceId = null;
    _text = null;
    _paused = false;
    await _native.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (_utteranceId != null) {
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
