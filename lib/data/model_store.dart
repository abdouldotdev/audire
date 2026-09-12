import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Téléchargement interrompu. Une reprise est possible.';
}

class ModelStore extends ChangeNotifier {
  ModelStore(this.root);
  final Directory root;
  static const repository = 'supertone-oss-archive/supertonic-3';
  static const revision = 'aafc6e32416a594460b32413efc49d7fe4ce6d46';
  bool busy = false,
      cancelled = false,
      neuralInstalled = false,
      alignmentInstalled = false;
  int received = 0, total = 0;
  String? error;
  String status = '';
  String get neuralPath => p.join(root.path, 'models', 'supertonic-3');
  String get alignmentPath => p.join(root.path, 'models', 'alignment-fr');
  String alignmentRevision = 'none';
  double get progress =>
      total == 0 ? 0 : (received / total).clamp(0.0, 1.0).toDouble();
  Future<void> refresh() async {
    neuralInstalled = await File('$neuralPath/installed.json').exists();
    alignmentInstalled = await File('$alignmentPath/installed.json').exists();
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
      await refresh();
    }
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
    for (final name in [neuralPath, alignmentPath, '$neuralPath.staging']) {
      final d = Directory(name);
      if (await d.exists()) await d.delete(recursive: true);
    }
    alignmentRevision = 'none';
    await refresh();
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
