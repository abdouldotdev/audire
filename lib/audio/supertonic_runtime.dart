import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Local Supertonic 3 ONNX inference. The public four-model contract is
/// documented by supertone-oss-archive/supertonic (see docs/SOURCES.md).
/// No network calls, text rewrites, cloning, or remote phonemization here.
class SupertonicRuntime {
  SupertonicRuntime._(this.root, this.config, this.indexer, this.sessions);
  final String root;
  final Map<String, dynamic> config;
  final Map<int, int> indexer;
  final Map<String, OrtSession> sessions;
  final Map<String, List<OrtValue>> _styles = {};
  int get sampleRate => (config['ae']['sample_rate'] as num).toInt();

  static Future<SupertonicRuntime> load(String root) async {
    final config =
        jsonDecode(await File('$root/onnx/tts.json').readAsString())
            as Map<String, dynamic>;
    final raw = jsonDecode(
      await File('$root/onnx/unicode_indexer.json').readAsString(),
    );
    final indexer = <int, int>{};
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        if (raw[i] is int && raw[i] >= 0) indexer[i] = raw[i] as int;
      }
    } else if (raw is Map) {
      for (final e in raw.entries) {
        indexer[int.parse(e.key as String)] = e.value as int;
      }
    } else {
      throw const FormatException('Index de caractères invalide.');
    }
    final ort = OnnxRuntime();
    final sessions = <String, OrtSession>{};
    try {
      for (final name in [
        'duration_predictor',
        'text_encoder',
        'vector_estimator',
        'vocoder',
      ]) {
        sessions[name] = await ort.createSession(
          '$root/onnx/$name.onnx',
          options: OrtSessionOptions(
            intraOpNumThreads: 2,
            interOpNumThreads: 1,
          ),
        );
      }
    } catch (_) {
      for (final s in sessions.values) {
        await s.close();
      }
      rethrow;
    }
    return SupertonicRuntime._(root, config, indexer, sessions);
  }

  static String preprocess(String text) {
    // Preserve accents through NFKD, as expected by the published frontend.
    var value = unorm.nfkd(text).replaceAll('\u00ad', '');
    const replacements = {
      '–': '-',
      '‑': '-',
      '—': '-',
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
      '´': "'",
      '`': "'",
      '[': ' ',
      ']': ' ',
      '|': ' ',
      '\\': ' ',
    };
    for (final e in replacements.entries) {
      value = value.replaceAll(e.key, e.value);
    }
    value = value.replaceAll(
      RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true),
      '',
    );
    // Text from EPUB is plain text. Never interpret book content as expression tags.
    value =
        value
            .replaceAll('<', ' ')
            .replaceAll('>', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (value.isEmpty) throw const FormatException('Phrase vide.');
    if (!RegExp(r'''[.!?;:,)'"…»]$''').hasMatch(value)) value += '.';
    return '<fr>$value</fr>';
  }

  Future<List<OrtValue>> _style(String voice) async {
    if (_styles[voice] != null) return _styles[voice]!;
    if (!RegExp(r'^[FM][1-5]$').hasMatch(voice)) {
      throw ArgumentError('Voix inconnue.');
    }
    final j =
        jsonDecode(await File('$root/voice_styles/$voice.json').readAsString())
            as Map<String, dynamic>;
    final tensors = <OrtValue>[];
    try {
      for (final key in ['style_ttl', 'style_dp']) {
        final shape = (j[key]['dims'] as List).cast<int>();
        tensors.add(
          await OrtValue.fromList(
            Float32List.fromList(flatten(j[key]['data'])),
            shape,
          ),
        );
      }
    } catch (_) {
      for (final t in tensors) {
        await t.dispose();
      }
      rethrow;
    }
    _styles[voice] = tensors;
    return tensors;
  }

  Future<Float32List> generate(
    String text, {
    required String voice,
    int steps = 5,
  }) async {
    final input = preprocess(text);
    if (input.runes.length > 650) {
      throw const FormatException(
        'Phrase trop longue pour la synthèse locale.',
      );
    }
    final style = await _style(voice);
    final owned = <OrtValue>[];
    Future<OrtValue> tensor(List data, List<int> shape) async {
      final t = await OrtValue.fromList(data, shape);
      owned.add(t);
      return t;
    }

    Future<Map<String, OrtValue>> run(
      String name,
      Map<String, OrtValue> inputs,
    ) async {
      final out = await sessions[name]!.run(inputs);
      owned.addAll(out.values);
      return out;
    }

    try {
      final runes = input.runes.toList();
      // Unknown symbols must not silently become unrelated characters.
      final ids = Int64List.fromList(
        runes.map((r) {
          final id = indexer[r];
          if (id == null) {
            throw FormatException(
              'Caractère non pris en charge par cette voix : U+${r.toRadixString(16)}. Essayez une voix système.',
            );
          }
          return id;
        }).toList(),
      );
      final textIds = await tensor(ids, [1, ids.length]);
      final textMask = await tensor(
        Float32List(ids.length)..fillRange(0, ids.length, 1),
        [1, 1, ids.length],
      );
      final durationOut = await run('duration_predictor', {
        'text_ids': textIds,
        'style_dp': style[1],
        'text_mask': textMask,
      });
      final duration = flatten(await durationOut.values.first.asList()).first;
      if (!duration.isFinite || duration <= 0 || duration > 55) {
        throw const FormatException('Durée de synthèse invalide.');
      }
      final textOut = await run('text_encoder', {
        'text_ids': textIds,
        'style_ttl': style[0],
        'text_mask': textMask,
      });
      final ae = config['ae'] as Map, ttl = config['ttl'] as Map;
      final chunk =
          (ae['base_chunk_size'] as int) *
          (ttl['chunk_compress_factor'] as int);
      final channels =
          (ttl['latent_dim'] as int) * (ttl['chunk_compress_factor'] as int);
      final length = (duration * sampleRate / chunk).ceil();
      final shape = [1, channels, length];
      final random = math.Random(42); // Reproducible cache for the same inputs.
      final noise = Float32List(channels * length);
      for (var i = 0; i < noise.length; i++) {
        final u = math.max(1e-10, random.nextDouble());
        noise[i] =
            math.sqrt(-2 * math.log(u)) *
            math.cos(2 * math.pi * random.nextDouble());
      }
      var latent = await tensor(noise, shape);
      final mask = await tensor(Float32List(length)..fillRange(0, length, 1), [
        1,
        1,
        length,
      ]);
      final total = await tensor(Float32List.fromList([steps.toDouble()]), [1]);
      for (var step = 0; step < steps; step++) {
        final current = await tensor(Float32List.fromList([step.toDouble()]), [
          1,
        ]);
        final output = await run('vector_estimator', {
          'noisy_latent': latent,
          'text_emb': textOut.values.first,
          'style_ttl': style[0],
          'text_mask': textMask,
          'latent_mask': mask,
          'total_step': total,
          'current_step': current,
        });
        // Keep tensors on the native side between diffusion steps.
        final previous = latent;
        latent = output.values.first;
        owned.remove(previous);
        await previous.dispose();
        owned.remove(current);
        await current.dispose();
      }
      final audioOut = await run('vocoder', {'latent': latent});
      final audio = flatten(await audioOut.values.first.asList());
      final n = math.min(audio.length, (duration * sampleRate).floor());
      if (n < sampleRate ~/ 10) throw const FormatException('Audio vide.');
      return Float32List.fromList(audio.take(n).toList());
    } finally {
      for (final t in owned.toSet()) {
        await t.dispose();
      }
    }
  }

  Future<void> close() async {
    for (final style in _styles.values) {
      for (final t in style) {
        await t.dispose();
      }
    }
    for (final s in sessions.values) {
      await s.close();
    }
  }
}

List<double> flatten(dynamic value) {
  if (value is num) return [value.toDouble()];
  if (value is List) return value.expand((v) => flatten(v)).toList();
  throw const FormatException('Tenseur numérique invalide.');
}

Future<void> writeWave(String path, Float32List samples, int sampleRate) async {
  final bytes = ByteData(44 + samples.length * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i].isFinite ? samples[i].clamp(-1.0, 1.0) : 0.0;
    bytes.setInt16(44 + 2 * i, (s * 32767).round(), Endian.little);
  }
  final f = File('$path.part');
  await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  await f.rename(path);
}
