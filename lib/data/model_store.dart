import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Téléchargement interrompu. Une reprise est possible.';
}

class QwenModelPack {
  const QwenModelPack({
    required this.id,
    required this.title,
    required this.repository,
    required this.revision,
    required this.bytes,
    required this.modelBytes,
    required this.speechTokenizerBytes,
    required this.minimumMemoryBytes,
  });

  final String id, title, repository, revision;
  final int bytes, modelBytes, speechTokenizerBytes, minimumMemoryBytes;
}

class ModelStore extends ChangeNotifier {
  ModelStore(this.root);
  final Directory root;
  static const repository = 'supertone-oss-archive/supertonic-3';
  static const revision = 'aafc6e32416a594460b32413efc49d7fe4ce6d46';
  static const kokoroRepository = 'onnx-community/Kokoro-82M-ONNX';
  static const kokoroRevision = 'f46687f7e41512228ae953af24a11b2640ea0f22';
  static const qwenRepository =
      'mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit';
  static const qwenRevision = '08c72cad5e2fd0f41730c8bd1f28149585e46361';
  static const qwenPacks = <QwenModelPack>[
    QwenModelPack(
      id: 'compact',
      title: 'Qwen 0.6B',
      repository: 'mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit',
      revision: '08c72cad5e2fd0f41730c8bd1f28149585e46361',
      bytes: 1693604738,
      modelBytes: 1006772520,
      speechTokenizerBytes: 682293092,
      minimumMemoryBytes: 8 * 1024 * 1024 * 1024,
    ),
    QwenModelPack(
      id: 'quality',
      title: 'Qwen Qualité',
      repository: 'mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit',
      revision: '049ef77fe8816b536193c0c25f9a214d17921282',
      bytes: 1973575388,
      modelBytes: 1286743170,
      speechTokenizerBytes: 682293092,
      minimumMemoryBytes: 12 * 1024 * 1024 * 1024,
    ),
    QwenModelPack(
      id: 'max',
      title: 'Qwen Max',
      repository: 'mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit',
      revision: 'f35faf19b0cc2160865af64ecf0f22f83d335135',
      bytes: 2312059416,
      modelBytes: 1625226859,
      speechTokenizerBytes: 682293092,
      minimumMemoryBytes: 16 * 1024 * 1024 * 1024,
    ),
  ];
  static const translationRegistry =
      'https://storage.googleapis.com/moz-fx-translations-data--303e-prod-translations-data/db/models.json';
  static const _translationMethods = MethodChannel('lisiere/translation');
  static const _qwenMethods = MethodChannel('lisiere/qwen_tts');
  bool busy = false,
      cancelled = false,
      neuralInstalled = false,
      kokoroInstalled = false,
      qwenInstalled = false,
      qwenQualityInstalled = false,
      qwenMaxInstalled = false,
      qwenCompactDownloaded = false,
      qwenQualityDownloaded = false,
      qwenMaxDownloaded = false,
      qwenSupported = false,
      alignmentInstalled = false,
      translationInstalled = false;
  int received = 0, total = 0;
  String? error;
  String qwenUnavailableReason = 'Qwen Studio nécessite iOS 17 ou plus récent.';
  int qwenPhysicalMemoryBytes = 0;
  String? activeDownload;
  String status = '';
  String get neuralPath => p.join(root.path, 'models', 'supertonic-3');
  String get kokoroPath => p.join(root.path, 'models', 'kokoro-82m');
  String get qwenPath => p.join(root.path, 'models', 'qwen3-tts-06b-4bit');
  String get qwenQualityPath =>
      p.join(root.path, 'models', 'qwen3-tts-06b-4bit-full');
  String get qwenMaxPath => p.join(root.path, 'models', 'qwen3-tts-17b-4bit');
  String qwenPathFor(String modelId) => switch (modelId) {
    'quality' => qwenQualityPath,
    'max' => qwenMaxPath,
    _ => qwenPath,
  };
  bool qwenInstalledFor(String modelId) => switch (modelId) {
    'quality' => qwenQualityInstalled,
    'max' => qwenMaxInstalled,
    _ => qwenInstalled,
  };
  bool qwenDownloadedFor(String modelId) => switch (modelId) {
    'quality' => qwenQualityDownloaded,
    'max' => qwenMaxDownloaded,
    _ => qwenCompactDownloaded,
  };
  QwenModelPack qwenPackFor(String modelId) => qwenPacks.firstWhere(
    (pack) => pack.id == modelId,
    orElse: () => qwenPacks.first,
  );
  bool qwenPackSupported(String modelId) {
    final pack = qwenPackFor(modelId);
    return qwenSupported && qwenPhysicalMemoryBytes >= pack.minimumMemoryBytes;
  }

  String qwenPackUnavailableReason(String modelId) {
    if (!qwenSupported) return qwenUnavailableReason;
    final gib = qwenPackFor(modelId).minimumMemoryBytes ~/ (1024 * 1024 * 1024);
    return 'Ce modèle nécessite un appareil avec au moins $gib Go de mémoire.';
  }

  String get alignmentPath => p.join(root.path, 'models', 'alignment-fr');
  String get translationPath =>
      p.join(root.path, 'models', 'translation-en-fr');
  String translationPathFor(String source, String target) =>
      p.join(root.path, 'models', 'translation-$source-$target');
  String alignmentRevision = 'none';
  double get progress =>
      total == 0 ? 0 : (received / total).clamp(0.0, 1.0).toDouble();
  Future<void> refresh() async {
    neuralInstalled = await File('$neuralPath/installed.json').exists();
    kokoroInstalled = await File('$kokoroPath/installed.json').exists();
    qwenInstalled = await File('$qwenPath/installed.json').exists();
    qwenQualityInstalled =
        await File('$qwenQualityPath/installed.json').exists();
    qwenMaxInstalled = await File('$qwenMaxPath/installed.json').exists();
    alignmentInstalled = await File('$alignmentPath/installed.json').exists();
    translationInstalled =
        await File('$translationPath/installed.json').exists();
    try {
      final status = Map<String, dynamic>.from(
        await _qwenMethods.invokeMapMethod<String, dynamic>('status') ??
            const <String, dynamic>{},
      );
      qwenSupported = status['available'] == true;
      qwenPhysicalMemoryBytes =
          (status['physicalMemoryBytes'] as num? ?? 0).toInt();
      qwenUnavailableReason =
          status['message'] as String? ?? qwenUnavailableReason;
    } on PlatformException {
      qwenSupported = false;
    } on MissingPluginException {
      qwenSupported = false;
    }
    qwenCompactDownloaded =
        qwenInstalled ||
        await _hasCompleteQwenStaging(qwenPath, qwenPackFor('compact'));
    qwenQualityDownloaded =
        qwenQualityInstalled ||
        await _hasCompleteQwenStaging(qwenQualityPath, qwenPackFor('quality'));
    qwenMaxDownloaded =
        qwenMaxInstalled ||
        await _hasCompleteQwenStaging(qwenMaxPath, qwenPackFor('max'));
    alignmentRevision = 'none';
    if (alignmentInstalled) {
      try {
        alignmentRevision =
            (await sha256
                    .bind(File('$alignmentPath/manifest.json').openRead())
                    .first)
                .toString();
      } on FileSystemException {
        alignmentInstalled = false;
        error = 'Le pack d’alignement est incomplet. Réimportez-le dans Voix.';
      }
    }
    notifyListeners();
  }

  Future<void> importTranslation(String path) async {
    if (busy) return;
    busy = true;
    error = null;
    status = 'Import du pack anglais → français…';
    notifyListeners();
    try {
      await Isolate.run(() => _extractTranslation(path, translationPath));
      translationInstalled = true;
      status = 'Traduction anglais → français installée';
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> installTranslationEnFr() async {
    if (busy) return;
    busy = true;
    cancelled = false;
    error = null;
    received = 0;
    total = 0;
    status = 'Recherche du modèle Bergamot EN → FR…';
    activeDownload = 'translation';
    notifyListeners();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final target = translationPathFor('en', 'fr');
    final staging = Directory('$target.staging');
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final registry = await _registry(http);
      final baseUrl = registry['baseUrl'] as String;
      final models = Map<String, dynamic>.from(registry['models'] as Map);
      final entries =
          (models['en-fr'] as List? ?? const [])
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((m) => m['releaseStatus'] == 'Release')
              .toList();
      if (entries.isEmpty) {
        throw const FormatException('Aucun modèle Bergamot EN → FR publié.');
      }
      entries.sort((a, b) {
        final aMemory = a['architecture'] == 'base-memory' ? 0 : 1;
        final bMemory = b['architecture'] == 'base-memory' ? 0 : 1;
        return aMemory.compareTo(bMemory);
      });
      final entry = entries.first;
      final files = Map<String, dynamic>.from(entry['files'] as Map);
      await _downloadTranslationFile(
        http,
        Uri.parse('$baseUrl/${_filePath(files, 'model')}'),
        File(p.join(staging.path, 'model.bin')),
        maxBytes: 160 * 1024 * 1024,
        label: 'Modèle Bergamot',
      );
      final expectedModelHash =
          Map<String, dynamic>.from(files['model'] as Map)['uncompressedHash']
              as String?;
      if (expectedModelHash != null) {
        final actual =
            (await sha256
                    .bind(File(p.join(staging.path, 'model.bin')).openRead())
                    .first)
                .toString();
        if (actual != expectedModelHash) {
          throw const FormatException(
            'Empreinte du modèle Bergamot incorrecte.',
          );
        }
      }
      await _downloadTranslationFile(
        http,
        Uri.parse('$baseUrl/${_filePath(files, 'vocab')}'),
        File(p.join(staging.path, 'vocab.spm')),
        maxBytes: 32 * 1024 * 1024,
        label: 'Vocabulaire SentencePiece',
      );
      await _downloadTranslationFile(
        http,
        Uri.parse('$baseUrl/${_filePath(files, 'lexicalShortlist')}'),
        File(p.join(staging.path, 'lex.bin')),
        maxBytes: 32 * 1024 * 1024,
        label: 'Shortlist lexicale',
      );
      final config = {
        'format': 'lisiere-bergamot-en-fr-v1',
        'source': 'en',
        'target': 'fr',
        'runtime': 'bergamot-native',
      };
      final names = {'model.bin', 'vocab.spm', 'lex.bin', 'config.json'};
      await File(
        p.join(staging.path, 'config.json'),
      ).writeAsString(jsonEncode(config), flush: true);
      final hashes = <String, String>{};
      for (final name in names) {
        hashes[name] =
            (await sha256
                    .bind(File(p.join(staging.path, name)).openRead())
                    .first)
                .toString();
      }
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'revision': registry['generated'] ?? 'mozilla-registry',
          'source': translationRegistry,
          'sha256': hashes,
        }),
        flush: true,
      );
      await File(p.join(staging.path, 'installed.json')).writeAsString(
        jsonEncode({
          'format': config['format'],
          'revision': registry['generated'] ?? 'mozilla-registry',
        }),
        flush: true,
      );
      status = 'Vérification du modèle…';
      notifyListeners();
      await _validateTranslationRuntime(staging.path);
      final destination = Directory(target);
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(target);
      status = 'Modèle Bergamot EN → FR installé.';
    } catch (e) {
      if (await staging.exists()) await staging.delete(recursive: true);
      error = '$e';
      status = 'Installation non terminée.';
    } finally {
      http.close(force: true);
      busy = false;
      activeDownload = null;
      await refresh();
    }
  }

  Future<void> _validateTranslationRuntime(String modelPath) async {
    try {
      final translated = await _translationMethods.invokeMethod<String>(
        'validateEnFrModel',
        {'modelPath': modelPath},
      );
      final normalized = translated?.trim().toLowerCase() ?? '';
      if (normalized.isEmpty ||
          normalized == 'the book is open.' ||
          !normalized.contains('livre')) {
        throw const FormatException(
          'Le modèle téléchargé n’a pas réussi sa vérification.',
        );
      }
    } on MissingPluginException {
      throw const FormatException(
        'Ce moteur de traduction n’est pas compatible avec cet appareil.',
      );
    } on PlatformException catch (error) {
      throw FormatException(
        error.message ?? 'Le modèle téléchargé ne peut pas être chargé.',
      );
    }
  }

  void cancel() {
    cancelled = true;
  }

  void _check() {
    if (cancelled) throw DownloadCancelled();
  }

  Future<void> installNeural() async {
    if (busy) return;
    busy = true;
    cancelled = false;
    error = null;
    received = 0;
    total = 0;
    status = 'Vérification du catalogue officiel…';
    activeDownload = 'supertonic';
    notifyListeners();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final staging = Directory('$neuralPath.staging');
    try {
      await staging.create(recursive: true);
      final metadata = await _json(
        http,
        Uri.parse(
          'https://huggingface.co/api/models/$repository/revision/$revision?blobs=true',
        ),
      );
      if (metadata['sha'] != revision) {
        throw const FormatException(
          'La révision du modèle ne correspond pas au catalogue.',
        );
      }
      final requiredNames = <String>{
        'onnx/duration_predictor.onnx',
        'onnx/text_encoder.onnx',
        'onnx/vector_estimator.onnx',
        'onnx/vocoder.onnx',
        'onnx/tts.json',
        'onnx/unicode_indexer.json',
        for (final sex in ['F', 'M'])
          for (var i = 1; i <= 5; i++) 'voice_styles/$sex$i.json',
      };
      final siblings =
          (metadata['siblings'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
      // Include external tensor data, when present in the pinned model snapshot.
      final files =
          siblings.where((f) {
            final name = f['rfilename'] as String;
            return requiredNames.contains(name) ||
                (name.startsWith('onnx/') && name.endsWith('.onnx.data')) ||
                const ['LICENSE', 'LICENSE.txt', 'README.md'].contains(name);
          }).toList();
      final available = files.map((f) => f['rfilename'] as String).toSet();
      if (!available.containsAll(requiredNames)) {
        throw const FormatException(
          'Le pack officiel ne contient pas les fichiers attendus.',
        );
      }
      total = files.fold(0, (sum, f) => sum + (f['size'] as num).toInt());
      if (total <= 0 || total > 1500 * 1024 * 1024) {
        throw const FormatException('Taille de téléchargement inattendue.');
      }
      notifyListeners();
      for (final metadata in files) {
        _check();
        final relative = metadata['rfilename'] as String;
        if (relative.contains('..') ||
            p.posix.isAbsolute(relative) ||
            relative.contains('\\')) {
          throw const FormatException('Chemin du modèle invalide.');
        }
        final file = File(p.join(staging.path, relative));
        await file.parent.create(recursive: true);
        final size = (metadata['size'] as num).toInt();
        status = 'Installation · ${p.basename(relative)}';
        notifyListeners();
        if (await file.exists() &&
            await file.length() == size &&
            await _valid(file, metadata)) {
          received += size;
          notifyListeners();
          continue;
        }
        final partial = File('${file.path}.part');
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset > size) {
          await partial.delete();
          offset = 0;
        }
        if (offset < size) {
          final url = Uri.parse(
            'https://huggingface.co/$repository/resolve/$revision/$relative',
          );
          final request = await http.getUrl(url);
          if (offset > 0) {
            request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
          }
          final response = await request.close().timeout(
            const Duration(seconds: 45),
          );
          if (response.statusCode == HttpStatus.ok) {
            offset = 0;
          } else if (response.statusCode == HttpStatus.partialContent) {
            final range =
                response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
            if (!range.startsWith('bytes $offset-')) {
              throw const HttpException('Réponse de reprise invalide.');
            }
          } else {
            throw HttpException('Serveur de modèles : ${response.statusCode}');
          }
          final sink = partial.openWrite(
            mode: offset > 0 ? FileMode.append : FileMode.write,
          );
          final base = received;
          received += offset;
          var written = offset;
          var lastNotification = DateTime.now();
          try {
            await for (final bytes in response.timeout(
              const Duration(seconds: 60),
            )) {
              _check();
              written += bytes.length;
              if (written > size) {
                throw const FormatException(
                  'Le téléchargement dépasse la taille attendue.',
                );
              }
              sink.add(bytes);
              received += bytes.length;
              if (DateTime.now().difference(lastNotification).inMilliseconds >
                  150) {
                notifyListeners();
                lastNotification = DateTime.now();
              }
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (written != size) {
            received = base;
            throw const HttpException(
              'Téléchargement incomplet. Relancez pour reprendre.',
            );
          }
        } else {
          received += offset;
        }
        _check();
        status = 'Vérification · ${p.basename(relative)}';
        notifyListeners();
        if (!await _valid(partial, metadata)) {
          await partial.delete();
          throw const FormatException(
            'Empreinte du fichier incorrecte. Le fichier a été supprimé.',
          );
        }
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      }
      await File('${staging.path}/installed.json').writeAsString(
        jsonEncode({'repository': repository, 'revision': revision}),
        flush: true,
      );
      final target = Directory(neuralPath);
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(neuralPath);
      status = 'Les 10 voix sont installées sur cet appareil.';
    } catch (e) {
      error = '$e';
      status = 'Installation non terminée.';
    } finally {
      http.close(force: true);
      busy = false;
      activeDownload = null;
      await refresh();
    }
  }

  Future<void> installKokoro() async {
    if (busy) return;
    busy = true;
    cancelled = false;
    error = null;
    received = 0;
    total = 0;
    status = 'Préparation de Kokoro…';
    activeDownload = 'kokoro';
    notifyListeners();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final staging = Directory('$kokoroPath.staging');
    try {
      await staging.create(recursive: true);
      final metadata = await _json(
        http,
        Uri.parse(
          'https://huggingface.co/api/models/$kokoroRepository/revision/$kokoroRevision?blobs=true',
        ),
      );
      if (metadata['sha'] != kokoroRevision) {
        throw const FormatException(
          'La version de Kokoro ne correspond pas au catalogue.',
        );
      }
      const required = {
        'onnx/model_quantized.onnx',
        'voices/af.bin',
        'voices/af_bella.bin',
        'voices/af_nicole.bin',
        'voices/af_sarah.bin',
        'voices/am_adam.bin',
        'voices/am_michael.bin',
      };
      final files =
          (metadata['siblings'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where(
                (file) =>
                    required.contains(file['rfilename']) ||
                    file['rfilename'] == 'LICENSE',
              )
              .toList();
      if (!files
          .map((f) => f['rfilename'] as String)
          .toSet()
          .containsAll(required)) {
        throw const FormatException('Le pack Kokoro est incomplet.');
      }
      total = files.fold(0, (sum, f) => sum + (f['size'] as num).toInt());
      if (total < 80 * 1024 * 1024 || total > 140 * 1024 * 1024) {
        throw const FormatException('Taille du pack Kokoro inattendue.');
      }
      notifyListeners();
      for (final metadata in files) {
        _check();
        final remote = metadata['rfilename'] as String;
        if (remote.contains('..') ||
            p.posix.isAbsolute(remote) ||
            remote.contains('\\')) {
          throw const FormatException('Chemin Kokoro invalide.');
        }
        final relative =
            remote == 'onnx/model_quantized.onnx' ? 'model.onnx' : remote;
        final file = File(p.join(staging.path, relative));
        await file.parent.create(recursive: true);
        final size = (metadata['size'] as num).toInt();
        status = 'Kokoro · ${p.basename(relative)}';
        notifyListeners();
        if (await file.exists() &&
            await file.length() == size &&
            await _valid(file, metadata)) {
          received += size;
          notifyListeners();
          continue;
        }
        final partial = File('${file.path}.part');
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset > size) {
          await partial.delete();
          offset = 0;
        }
        if (offset == size && await _valid(partial, metadata)) {
          if (await file.exists()) await file.delete();
          await partial.rename(file.path);
          received += size;
          notifyListeners();
          continue;
        }
        final request = await http.getUrl(
          Uri.parse(
            'https://huggingface.co/$kokoroRepository/resolve/$kokoroRevision/$remote',
          ),
        );
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 45),
        );
        if (response.statusCode == HttpStatus.ok) {
          offset = 0;
        } else if (response.statusCode == HttpStatus.partialContent) {
          final range =
              response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          if (!range.startsWith('bytes $offset-')) {
            throw const HttpException('Réponse de reprise Kokoro invalide.');
          }
        } else {
          throw HttpException('Serveur Kokoro : ${response.statusCode}');
        }
        if (offset == 0 && await partial.exists()) await partial.delete();
        final sink = partial.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        received += offset;
        var written = offset;
        var lastNotification = DateTime.now();
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 60),
          )) {
            _check();
            written += bytes.length;
            if (written > size) {
              throw const FormatException(
                'Le téléchargement Kokoro dépasse la taille attendue.',
              );
            }
            sink.add(bytes);
            received += bytes.length;
            if (DateTime.now().difference(lastNotification).inMilliseconds >
                150) {
              notifyListeners();
              lastNotification = DateTime.now();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (written != size || !await _valid(partial, metadata)) {
          if (await partial.exists()) await partial.delete();
          throw const FormatException('Fichier Kokoro incomplet ou invalide.');
        }
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      }
      await File(p.join(staging.path, 'installed.json')).writeAsString(
        jsonEncode({
          'repository': kokoroRepository,
          'revision': kokoroRevision,
          'language': 'en',
        }),
        flush: true,
      );
      final destination = Directory(kokoroPath);
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(kokoroPath);
      status = 'Kokoro est installé et sélectionné.';
    } catch (e) {
      error = '$e';
      status = 'Installation de Kokoro non terminée.';
    } finally {
      http.close(force: true);
      busy = false;
      activeDownload = null;
      await refresh();
    }
  }

  Future<void> installQwen([String modelId = 'compact']) async {
    final pack = qwenPackFor(modelId);
    if (busy || !qwenPackSupported(pack.id)) {
      if (!qwenPackSupported(pack.id)) {
        error = qwenPackUnavailableReason(pack.id);
        notifyListeners();
      }
      return;
    }
    busy = true;
    cancelled = false;
    error = null;
    received = 0;
    total = 0;
    final destinationPath = qwenPathFor(pack.id);
    status = 'Préparation de ${pack.title}…';
    activeDownload = 'qwen-${pack.id}';
    notifyListeners();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    final staging = Directory('$destinationPath.staging');
    try {
      await staging.create(recursive: true);
      final metadata = await _json(
        http,
        Uri.parse(
          'https://huggingface.co/api/models/${pack.repository}/revision/${pack.revision}?blobs=true',
        ),
      );
      if (metadata['sha'] != pack.revision) {
        throw FormatException(
          'La version de ${pack.title} ne correspond pas au catalogue.',
        );
      }
      const required = {
        'config.json',
        'generation_config.json',
        'merges.txt',
        'model.safetensors',
        'preprocessor_config.json',
        'speech_tokenizer/config.json',
        'speech_tokenizer/model.safetensors',
        'tokenizer_config.json',
        'vocab.json',
      };
      const downloadable = {
        ...required,
        'model.safetensors.index.json',
        'speech_tokenizer/configuration.json',
        'speech_tokenizer/preprocessor_config.json',
        'tokenizer.json',
      };
      final files =
          (metadata['siblings'] as List)
              .map((value) => Map<String, dynamic>.from(value as Map))
              .where((file) => downloadable.contains(file['rfilename']))
              .toList();
      if (!files
          .map((file) => file['rfilename'] as String)
          .toSet()
          .containsAll(required)) {
        throw FormatException('Le pack ${pack.title} est incomplet.');
      }
      total = files.fold(0, (sum, file) => sum + (file['size'] as num).toInt());
      final delta = (total - pack.bytes).abs();
      if (delta > pack.bytes * .01) {
        throw FormatException('Taille du pack ${pack.title} inattendue.');
      }
      notifyListeners();
      for (final metadata in files) {
        await _downloadSnapshotFile(
          http,
          repository: pack.repository,
          revision: pack.revision,
          metadata: metadata,
          staging: staging,
          label: pack.title,
        );
      }
      status = 'Essai de la voix sur cet appareil…';
      notifyListeners();
      await _validateQwenRuntime(staging.path);
      await File(p.join(staging.path, 'installed.json')).writeAsString(
        jsonEncode({
          'repository': pack.repository,
          'revision': pack.revision,
          'model': pack.id,
          'languages': ['fr', 'en'],
          'runtime': 'qwen3-tts-mlx',
        }),
        flush: true,
      );
      final destination = Directory(destinationPath);
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(destinationPath);
      status = '${pack.title} est installé et sélectionné.';
    } catch (e) {
      error = '$e';
      status = 'Installation de ${pack.title} non terminée.';
    } finally {
      http.close(force: true);
      busy = false;
      activeDownload = null;
      await refresh();
    }
  }

  Future<bool> _hasCompleteQwenStaging(
    String destinationPath,
    QwenModelPack pack,
  ) async {
    final staging = Directory('$destinationPath.staging');
    if (!await staging.exists()) return false;
    final model = File(p.join(staging.path, 'model.safetensors'));
    final speech = File(
      p.join(staging.path, 'speech_tokenizer', 'model.safetensors'),
    );
    try {
      return await model.length() == pack.modelBytes &&
          await speech.length() == pack.speechTokenizerBytes;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _validateQwenRuntime(String modelPath) async {
    try {
      final result = Map<String, dynamic>.from(
        await _qwenMethods.invokeMapMethod<String, dynamic>('validateModel', {
              'modelPath': modelPath,
            }) ??
            const <String, dynamic>{},
      );
      if (result['valid'] != true || (result['durationMs'] as num? ?? 0) <= 0) {
        throw const FormatException(
          'Qwen Studio n’a pas réussi son essai audio.',
        );
      }
    } on MissingPluginException {
      throw FormatException(qwenUnavailableReason);
    } on PlatformException catch (platformError) {
      throw FormatException(
        platformError.message ??
            'Qwen Studio ne peut pas être chargé sur cet appareil.',
      );
    }
  }

  Future<void> _downloadSnapshotFile(
    HttpClient http, {
    required String repository,
    required String revision,
    required Map<String, dynamic> metadata,
    required Directory staging,
    required String label,
  }) async {
    _check();
    final relative = metadata['rfilename'] as String;
    if (relative.contains('..') ||
        p.posix.isAbsolute(relative) ||
        relative.contains('\\')) {
      throw const FormatException('Chemin de modèle invalide.');
    }
    final size = (metadata['size'] as num).toInt();
    final file = File(p.join(staging.path, relative));
    await file.parent.create(recursive: true);
    status = '$label · ${p.basename(relative)}';
    notifyListeners();
    if (await file.exists() &&
        await file.length() == size &&
        await _valid(file, metadata)) {
      received += size;
      notifyListeners();
      return;
    }
    final partial = File('${file.path}.part');
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > size) {
      await partial.delete();
      offset = 0;
    }
    if (offset == size) {
      if (await _valid(partial, metadata)) {
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
        received += size;
        notifyListeners();
        return;
      }
      await partial.delete();
      offset = 0;
    }
    final request = await http.getUrl(
      Uri.parse(
        'https://huggingface.co/$repository/resolve/$revision/$relative',
      ),
    );
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode == HttpStatus.ok) {
      offset = 0;
      if (await partial.exists()) await partial.delete();
    } else if (response.statusCode == HttpStatus.partialContent) {
      final range =
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      if (!range.startsWith('bytes $offset-')) {
        throw const HttpException('Réponse de reprise invalide.');
      }
    } else {
      throw HttpException('Serveur de modèles : ${response.statusCode}');
    }
    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    received += offset;
    var written = offset;
    var lastNotification = DateTime.now();
    try {
      await for (final bytes in response.timeout(const Duration(seconds: 60))) {
        _check();
        written += bytes.length;
        if (written > size) {
          throw const FormatException(
            'Le téléchargement dépasse la taille attendue.',
          );
        }
        sink.add(bytes);
        received += bytes.length;
        if (DateTime.now().difference(lastNotification).inMilliseconds > 150) {
          notifyListeners();
          lastNotification = DateTime.now();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (written != size || !await _valid(partial, metadata)) {
      if (await partial.exists()) await partial.delete();
      throw const FormatException('Fichier téléchargé incomplet ou invalide.');
    }
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);
  }

  Future<void> importAlignment(String path) async {
    if (busy) return;
    busy = true;
    error = null;
    status = 'Vérification du pack d’alignement…';
    notifyListeners();
    try {
      final target = alignmentPath;
      await Isolate.run(() => _extractAlignment(path, target));
      status = 'Le suivi acoustique mot à mot est installé.';
    } catch (e) {
      error = '$e';
      status = 'Import non terminé.';
    } finally {
      busy = false;
      await refresh();
    }
  }

  Future<void> removeModels() async {
    if (busy) return;
    for (final name in [
      neuralPath,
      kokoroPath,
      qwenPath,
      qwenQualityPath,
      qwenMaxPath,
      alignmentPath,
      translationPath,
      '$neuralPath.staging',
      '$kokoroPath.staging',
      '$qwenPath.staging',
      '$qwenQualityPath.staging',
      '$qwenMaxPath.staging',
      '$translationPath.staging',
    ]) {
      final d = Directory(name);
      if (await d.exists()) await d.delete(recursive: true);
    }
    alignmentRevision = 'none';
    await refresh();
  }

  Future<void> deleteNeural() async {
    await _deleteModelBundle(
      path: neuralPath,
      label: 'Supertonic 3',
    );
  }

  Future<void> deleteKokoro() async {
    await _deleteModelBundle(
      path: kokoroPath,
      label: 'Kokoro 82M',
    );
  }

  Future<void> deleteQwen(String modelId) async {
    final id = {'compact', 'quality', 'max'}.contains(modelId)
        ? modelId
        : 'compact';
    await _deleteModelBundle(
      path: qwenPathFor(id),
      label: qwenPackFor(id).title,
    );
  }

  Future<void> deleteTranslation() async {
    await _deleteModelBundle(
      path: translationPath,
      label: 'Traduction anglais → français',
    );
  }

  Future<void> _deleteModelBundle({
    required String path,
    required String label,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    status = 'Suppression de $label…';
    notifyListeners();
    try {
      final destination = Directory(path);
      if (await destination.exists()) await destination.delete(recursive: true);
      final staging = Directory('$path.staging');
      if (await staging.exists()) await staging.delete(recursive: true);
      status = '$label supprimé.';
    } catch (e) {
      error = '$e';
      status = 'Suppression de $label non terminée.';
    } finally {
      busy = false;
      activeDownload = null;
      await refresh();
    }
  }

  static Future<Map<String, dynamic>> _json(HttpClient http, Uri uri) async {
    final request = await http.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException('Catalogue indisponible (${response.statusCode}).');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      bytes.addAll(chunk);
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Catalogue trop volumineux.');
      }
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _registry(HttpClient http) async {
    final request = await http.getUrl(Uri.parse(translationRegistry));
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException(
        'Registre Bergamot indisponible (${response.statusCode}).',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 45))) {
      bytes.addAll(chunk);
      if (bytes.length > 8 * 1024 * 1024) {
        throw const FormatException('Registre Bergamot trop volumineux.');
      }
    }
    final source = utf8
        .decode(bytes)
        .replaceAll(RegExp(r':\s*NaN'), ': null')
        .replaceAll(RegExp(r':\s*-?Infinity'), ': null');
    return jsonDecode(source) as Map<String, dynamic>;
  }

  static String _filePath(Map<String, dynamic> files, String key) {
    final metadata = Map<String, dynamic>.from(files[key] as Map? ?? const {});
    final path = metadata['path'] as String?;
    if (path == null ||
        path.contains('..') ||
        path.startsWith('/') ||
        path.contains('\\') ||
        !path.endsWith('.gz')) {
      throw const FormatException('Chemin de modèle Bergamot invalide.');
    }
    return path;
  }

  Future<void> _downloadTranslationFile(
    HttpClient http,
    Uri uri,
    File destination, {
    required int maxBytes,
    required String label,
  }) async {
    _check();
    status = 'Téléchargement · $label';
    notifyListeners();
    final request = await http.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Téléchargement Bergamot : ${response.statusCode}');
    }
    final length = response.contentLength;
    if (length > 0) total += length;
    final compressed = <int>[];
    var lastNotification = DateTime.now();
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      _check();
      compressed.addAll(chunk);
      if (compressed.length > maxBytes) {
        throw const FormatException('Fichier Bergamot trop volumineux.');
      }
      received += chunk.length;
      if (DateTime.now().difference(lastNotification).inMilliseconds > 150) {
        notifyListeners();
        lastNotification = DateTime.now();
      }
    }
    status = 'Décompression · $label';
    notifyListeners();
    final decoded = gzip.decode(compressed);
    if (decoded.length > maxBytes) {
      throw const FormatException(
        'Fichier Bergamot décompressé trop volumineux.',
      );
    }
    await destination.writeAsBytes(decoded, flush: true);
  }

  static Future<bool> _valid(File file, Map<String, dynamic> metadata) async {
    final lfs = metadata['lfs'] as Map?;
    if (lfs != null && lfs['sha256'] is String) {
      return (await sha256.bind(file.openRead()).first).toString() ==
          lfs['sha256'];
    }
    final blob = metadata['blobId'] as String?;
    if (blob == null) return false;
    Stream<List<int>> gitBlob() async* {
      yield utf8.encode('blob ${await file.length()}\u0000');
      yield* file.openRead();
    }

    return (await sha1.bind(gitBlob()).first).toString() == blob;
  }
}

Future<void> _extractAlignment(String path, String target) async {
  if (await File(path).length() > 800 * 1024 * 1024) {
    throw const FormatException('Pack trop volumineux (800 Mo maximum).');
  }
  final staging = Directory('$target.staging');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  const allowed = {
    'model.onnx',
    'vocab.json',
    'alignment.json',
    'manifest.json',
    'LICENSE.txt',
  };
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    if (archive.length > allowed.length) {
      throw const FormatException('Contenu du pack inattendu.');
    }
    var total = 0;
    final names = <String>{};
    for (final entry in archive) {
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          !allowed.contains(entry.name) ||
          !names.add(entry.name)) {
        throw const FormatException('Fichier du pack non autorisé.');
      }
      total += entry.size;
      if (entry.size < 0 ||
          total > 1500 * 1024 * 1024 ||
          (entry.name != 'model.onnx' && entry.size > 5 * 1024 * 1024)) {
        throw const FormatException('Taille du pack invalide.');
      }
      final output = OutputFileStream('${staging.path}/${entry.name}');
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
      if (await File('${staging.path}/${entry.name}').length() != entry.size) {
        throw const FormatException('Fichier extrait incomplet.');
      }
    }
    if (!names.containsAll({
      'model.onnx',
      'vocab.json',
      'alignment.json',
      'manifest.json',
    })) {
      throw const FormatException('Pack incomplet.');
    }
    final manifest =
        jsonDecode(await File('${staging.path}/manifest.json').readAsString())
            as Map<String, dynamic>;
    for (final name in names.where((n) => n != 'manifest.json')) {
      final expected = (manifest['sha256'] as Map)[name];
      final actual =
          (await sha256.bind(File('${staging.path}/$name').openRead()).first)
              .toString();
      if (expected != actual) {
        throw const FormatException('Empreinte du pack incorrecte.');
      }
    }
    final cfg =
        jsonDecode(await File('${staging.path}/alignment.json').readAsString())
            as Map<String, dynamic>;
    if (cfg['format'] != 'lisiere-ctc-v1' || cfg['sampleRate'] != 16000) {
      throw const FormatException('Format d’alignement incompatible.');
    }
    await File(
      '${staging.path}/installed.json',
    ).writeAsString(jsonEncode({'format': cfg['format']}), flush: true);
    final destination = Directory(target);
    if (await destination.exists()) await destination.delete(recursive: true);
    await staging.rename(target);
  } catch (_) {
    if (await staging.exists()) await staging.delete(recursive: true);
    rethrow;
  } finally {
    await input.close();
  }
}

Future<void> _extractTranslation(String path, String target) async {
  if (await File(path).length() > 250 * 1024 * 1024) {
    throw const FormatException(
      'Pack de traduction trop volumineux (250 Mo maximum).',
    );
  }
  final staging = Directory('$target.staging');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  const required = {'model.bin', 'vocab.spm', 'config.json', 'manifest.json'};
  const allowed = {
    'model.bin',
    'vocab.spm',
    'lex.bin',
    'config.json',
    'manifest.json',
    'LICENSE.txt',
    'README.md',
  };
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    if (archive.length > allowed.length) {
      throw const FormatException('Contenu du pack de traduction inattendu.');
    }
    var total = 0;
    final names = <String>{};
    for (final entry in archive) {
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          !allowed.contains(entry.name) ||
          !names.add(entry.name)) {
        throw const FormatException(
          'Fichier du pack de traduction non autorisé.',
        );
      }
      total += entry.size;
      if (entry.size < 0 || total > 300 * 1024 * 1024) {
        throw const FormatException('Taille du pack de traduction invalide.');
      }
      final output = OutputFileStream('${staging.path}/${entry.name}');
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
      if (await File('${staging.path}/${entry.name}').length() != entry.size) {
        throw const FormatException('Fichier de traduction extrait incomplet.');
      }
    }
    if (!names.containsAll(required)) {
      throw const FormatException('Pack de traduction incomplet.');
    }
    final manifest =
        jsonDecode(await File('${staging.path}/manifest.json').readAsString())
            as Map<String, dynamic>;
    final hashes = Map<String, dynamic>.from(
      manifest['sha256'] as Map? ?? const {},
    );
    for (final name in names.where((n) => n != 'manifest.json')) {
      final expected = hashes[name];
      if (expected == null) {
        throw const FormatException('Manifeste de traduction incomplet.');
      }
      final actual =
          (await sha256.bind(File('${staging.path}/$name').openRead()).first)
              .toString();
      if (expected != actual) {
        throw const FormatException(
          'Empreinte du pack de traduction incorrecte.',
        );
      }
    }
    final cfg =
        jsonDecode(await File('${staging.path}/config.json').readAsString())
            as Map<String, dynamic>;
    if (cfg['format'] != 'lisiere-bergamot-en-fr-v1' ||
        cfg['source'] != 'en' ||
        cfg['target'] != 'fr') {
      throw const FormatException('Format de traduction incompatible.');
    }
    await File('${staging.path}/installed.json').writeAsString(
      jsonEncode({
        'format': cfg['format'],
        'revision': manifest['revision'] ?? 'unknown',
      }),
      flush: true,
    );
    final destination = Directory(target);
    if (await destination.exists()) await destination.delete(recursive: true);
    await staging.rename(target);
  } catch (_) {
    if (await staging.exists()) await staging.delete(recursive: true);
    rethrow;
  } finally {
    await input.close();
  }
}
