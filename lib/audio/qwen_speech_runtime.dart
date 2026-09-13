import 'package:flutter/services.dart';

/// Main-isolate bridge to the MLX Qwen3-TTS runtime on compatible Apple devices.
class QwenSpeechRuntime {
  static const _methods = MethodChannel('lisiere/qwen_tts');

  Future<Map<String, dynamic>> generate({
    required String modelPath,
    required String text,
    required String speaker,
    required String language,
    required String wavePath,
  }) async {
    return Map<String, dynamic>.from(
      await _methods.invokeMapMethod<String, dynamic>('generate', {
            'modelPath': modelPath,
            'text': text,
            'speaker': speaker,
            'language': language,
            'wavePath': wavePath,
          }) ??
          const <String, dynamic>{},
    );
  }

  Future<void> reset() async {
    try {
      await _methods.invokeMethod<void>('reset');
    } on MissingPluginException {
      // Qwen is an optional Apple-only runtime.
    } on PlatformException {
      // Releasing an optional model must never interrupt engine switching.
    }
  }
}
