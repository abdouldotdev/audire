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
    required String language,
    String? voiceId,
    required double speed,
    bool enqueue = false,
  }) => _methods.invokeMethod<void>('speak', {
    'id': id,
    'text': text,
    'language': language,
    'voice': voiceId,
    'speed': speed,
    'enqueue': enqueue,
  });
  Future<void> stop() => _methods.invokeMethod<void>('stop');
  Future<bool> pause() async =>
      await _methods.invokeMethod<bool>('pause') ?? false;
  Future<bool> resume() async =>
      await _methods.invokeMethod<bool>('resume') ?? false;
  Future<int?> beginAudioPreparation() =>
      _methods.invokeMethod<int>('beginAudioPreparation');
  Future<void> endAudioPreparation(int task) =>
      _methods.invokeMethod<void>('endAudioPreparation', {'task': task});
  Future<void> excludeFromBackup(String path) =>
      _methods.invokeMethod<void>('excludeFromBackup', {'path': path});
  Future<String> recognizeText(
    String imagePath, {
    List<String> languages = const ['fr-FR', 'en-US'],
  }) async =>
      await _methods.invokeMethod<String>('recognizeText', {
        'path': imagePath,
        'languages': languages,
      }) ??
      '';
  Future<Map<String, dynamic>> powerStatus() async => Map<String, dynamic>.from(
    await _methods.invokeMapMethod<String, dynamic>('powerStatus') ??
        const <String, dynamic>{},
  );
}
