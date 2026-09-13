import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Local EN→FR translation adapter.
///
/// The Flutter layer owns caching and lifecycle. The native side owns the
/// Bergamot/Marian runtime because the production models use SentencePiece
/// and optimized native kernels that should not be reimplemented in Dart.
class LocalTranslationEngine {
  LocalTranslationEngine({
    required this.modelDirectory,
    required this.cacheDirectory,
  });

  final Directory modelDirectory;
  final Directory cacheDirectory;
  static const _methods = MethodChannel('lisiere/translation');

  bool get installed =>
      File(p.join(modelDirectory.path, 'installed.json')).existsSync();

  Future<String?> enFrUnavailableReason() async {
    if (!installed) {
      return 'Le pack anglais → français n’est pas installé. Choisissez-le pendant l’onboarding ou retéléchargez-le depuis Profil.';
    }
    try {
      final status = await _methods.invokeMapMethod<String, dynamic>(
        'translationStatus',
      );
      if (status?['available'] == true) return null;
      return status?['message'] as String? ??
          'Le moteur de traduction locale n’est pas disponible dans cette build.';
    } on PlatformException catch (e) {
      return e.message ??
          'Le moteur de traduction locale n’est pas disponible.';
    } on MissingPluginException {
      return 'Le moteur de traduction locale n’est pas disponible dans cette build.';
    }
  }

  Future<String> translateEnToFr(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return text;
    if (!installed) {
      throw StateError(
        'Le pack de traduction anglais → français n’est pas installé.',
      );
    }
    await cacheDirectory.create(recursive: true);
    final revision = await _revision();
    final key = sha256.convert(utf8.encode('$revision\n$clean')).toString();
    final cache = File(p.join(cacheDirectory.path, '$key.txt'));
    if (await cache.exists()) return cache.readAsString();

    final unavailable = await enFrUnavailableReason();
    if (unavailable != null) throw StateError(unavailable);

    String? translated;
    try {
      translated = await _methods.invokeMethod<String>('translateEnFr', {
        'text': clean,
        'modelPath': modelDirectory.path,
      });
    } on PlatformException catch (e) {
      throw StateError(
        e.message ?? 'Le moteur de traduction locale n’est pas disponible.',
      );
    } on MissingPluginException {
      throw StateError(
        'Le runtime Bergamot natif n’est pas encore lié à cette build.',
      );
    }
    final result = translated?.trim();
    if (result == null || result.isEmpty) {
      throw StateError('Le moteur de traduction a renvoyé un texte vide.');
    }
    await cache.writeAsString(result, flush: true);
    return result;
  }

  Future<void> clearCache() async {
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  }

  Future<String> _revision() async {
    try {
      final installed = jsonDecode(
        await File(
          p.join(modelDirectory.path, 'installed.json'),
        ).readAsString(),
      );
      return (installed as Map<String, dynamic>)['revision'] as String? ??
          'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}
