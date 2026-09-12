import 'package:flutter/services.dart';

/// Speech synthesis only. No microphone, transcription or network TTS API.
class LisiereNativeTts {
  static const _methods = MethodChannel('lisiere/native_tts');
  static const _channel = EventChannel('lisiere/native_tts/events');
  static final _events = _channel.receiveBroadcastStream().map(
    (dynamic value) => Map<String, dynamic>.from(value as Map),
  );
  Stream<Map<String, dynamic>> get events => _events;
  Future<List<Map<String, dynamic>>> voices() async {
    final result = await _methods.invokeListMethod<dynamic>('voices') ?? [];
    return result
        .map((dynamic v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<void> speak({
    required String id,
    required String text,
    String? voiceId,
    required double speed,
  }) => _methods.invokeMethod<void>('speak', {
    'id': id,
    'text': text,
    'voice': voiceId,
    'speed': speed,
  });
  Future<void> stop() => _methods.invokeMethod<void>('stop');
  Future<void> excludeFromBackup(String path) =>
      _methods.invokeMethod<void>('excludeFromBackup', {'path': path});
}
