import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../domain/narration.dart';
import 'ctc_alignment.dart';
import 'speech_engine.dart';
import 'supertonic_runtime.dart' show flatten;

/// Consumes the explicit ONNX contract emitted by tool/export_alignment.py.
class AcousticAligner {
  AcousticAligner._(this.session, this.vocab, this.config);
  final OrtSession session;
  final Map<String, int> vocab;
  final Map<String, dynamic> config;
  static Future<AcousticAligner> load(String directory) async {
    final cfg =
        jsonDecode(await File('$directory/alignment.json').readAsString())
            as Map<String, dynamic>;
    if (cfg['format'] != 'lisiere-ctc-v1' || cfg['sampleRate'] != 16000) {
      throw const FormatException('Pack d’alignement incompatible.');
    }
    final vocab = (jsonDecode(
              await File('$directory/vocab.json').readAsString(),
            )
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
    final session = await OnnxRuntime().createSession(
      '$directory/model.onnx',
      options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
    );
    return AcousticAligner._(session, vocab, cfg);
  }

  Future<List<WordCue>> align(
    Float32List audio,
    int sampleRate,
    NarrationText text,
  ) async {
    final matches =
        RegExp(
          r"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*",
          unicode: true,
        ).allMatches(text.spoken).toList();
    if (matches.isEmpty) return [];
    final tokens = <int>[], wordTokenStarts = <int>[], wordTokenEnds = <int>[];
    final delimiter = vocab[config['wordDelimiter'] ?? '|'];
    for (final match in matches) {
      var word = unorm.nfc(
        match[0]!
            .replaceAll('’', "'")
            .replaceAll('œ', 'oe')
            .replaceAll('Œ', 'OE'),
      );
      word =
          config['lowercase'] == false
              ? word.toUpperCase()
              : word.toLowerCase();
      if (tokens.isNotEmpty && delimiter != null) tokens.add(delimiter);
      wordTokenStarts.add(tokens.length);
      for (final rune in word.runes) {
        var letter = String.fromCharCode(rune);
        if (letter == '-') {
          if (delimiter != null) tokens.add(delimiter);
          continue;
        }
        var id = vocab[letter];
        if (id == null) {
          letter = unorm.nfd(letter).replaceAll(RegExp(r'[\u0300-\u036f]'), '');
          id = vocab[letter];
        }
        if (id == null) {
          return []; // Unsupported number/symbol: honest phrase fallback.
        }
        tokens.add(id);
      }
      if (tokens.length == wordTokenStarts.last) return [];
      wordTokenEnds.add(tokens.length - 1);
    }
    final pcm = resample16k(audio, sampleRate);
    if (pcm.isEmpty || pcm.length > 16000 * 55) return [];
    if (config['normalize'] != false) {
      var mean = 0.0;
      for (final x in pcm) {
        mean += x;
      }
      mean /= pcm.length;
      var variance = 0.0;
      for (final x in pcm) {
        variance += (x - mean) * (x - mean);
      }
      variance /= pcm.length;
      final std = math.sqrt(variance + 1e-7);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (pcm[i] - mean) / std;
      }
    }
    final owned = <OrtValue>[];
    try {
      final values = await OrtValue.fromList(pcm, [1, pcm.length]);
      owned.add(values);
      final mask = await OrtValue.fromList(
        Int64List(pcm.length)..fillRange(0, pcm.length, 1),
        [1, pcm.length],
      );
      owned.add(mask);
      final outputs = await session.run({
        'input_values': values,
        'attention_mask': mask,
      });
      owned.addAll(outputs.values);
      final logits = outputs['logits'];
      if (logits == null || logits.shape.length != 3 || logits.shape[0] != 1) {
        return [];
      }
      final frames = logits.shape[1], v = logits.shape[2];
      final raw = Float32List.fromList(flatten(await logits.asList()));
      final blank = (config['blankId'] as num).toInt();
      final path = alignCtc(
        logits: raw,
        frames: frames,
        vocabularySize: v,
        tokens: tokens,
        blank: blank,
      );
      if (path == null || path.confidence < 0.08) return [];
      // A forced path exists even for wrong audio. Reject severe transcript mismatch.
      final greedy = <int>[];
      var previous = -1;
      for (var t = 0; t < frames; t++) {
        var best = 0;
        for (var j = 1; j < v; j++) {
          if (raw[t * v + j] > raw[t * v + best]) best = j;
        }
        if (best != blank && best != previous) greedy.add(best);
        previous = best;
      }
      if (_editDistance(greedy, tokens) / math.max(1, tokens.length) > 0.45) {
        return [];
      }
      final strideMs = (config['strideSamples'] as num).toDouble() / 16.0;
      final durationMs = (audio.length / sampleRate * 1000).round();
      final cues = <WordCue>[];
      for (var w = 0; w < matches.length; w++) {
        final range = text.displayRange(matches[w].start, matches[w].end);
        final start =
            (path.firstFrames[wordTokenStarts[w]] * strideMs)
                .round()
                .clamp(0, durationMs)
                .toInt();
        final end =
            ((path.lastFrames[wordTokenEnds[w]] + 1) * strideMs)
                .round()
                .clamp(start, durationMs)
                .toInt();
        if (end > start) {
          cues.add(
            WordCue(
              startMs: start,
              endMs: end,
              start: range.start,
              end: range.end,
            ),
          );
        }
      }
      return cues;
    } finally {
      for (final t in owned) {
        await t.dispose();
      }
    }
  }

  Future<void> close() => session.close();
}

int _editDistance(List<int> a, List<int> b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0);
    row[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      row[j + 1] = math.min(
        math.min(row[j] + 1, prev[j + 1] + 1),
        prev[j] + (a[i] == b[j] ? 0 : 1),
      );
    }
    prev = row;
  }
  return prev.last;
}
