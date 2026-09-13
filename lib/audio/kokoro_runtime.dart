import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:phonemize/phonemize.dart' as g2p;

/// English-only Kokoro 82M inference. Text never leaves the device.
class KokoroRuntime {
  KokoroRuntime._(this.root, this._session);

  static const sampleRate = 24000;
  static const _maxTokens = 500;
  final String root;
  final OrtSession _session;
  final Map<String, Float32List> _voices = {};

  static Future<KokoroRuntime> load(String root) async {
    final session = await OnnxRuntime().createSession(
      '$root/model.onnx',
      options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
    );
    g2p.initDefaultProcessors();
    return KokoroRuntime._(root, session);
  }

  static const _voiceFiles = {
    'Default': 'af.bin',
    'Bella': 'af_bella.bin',
    'Nicole': 'af_nicole.bin',
    'Sarah': 'af_sarah.bin',
    'Adam': 'am_adam.bin',
    'Michael': 'am_michael.bin',
  };

  Future<Float32List> _voice(String id) async {
    final cached = _voices[id];
    if (cached != null) return cached;
    final name = _voiceFiles[id];
    if (name == null) throw ArgumentError.value(id, 'voice', 'Voix inconnue');
    final bytes = await File('$root/voices/$name').readAsBytes();
    if (bytes.lengthInBytes % 4 != 0) {
      throw const FormatException('Style vocal Kokoro invalide.');
    }
    final value = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    _voices[id] = value;
    return value;
  }

  Future<Float32List> generate(
    String text, {
    required String voice,
    double speed = 1,
  }) async {
    final clean = _normalizeEnglish(text);
    if (clean.isEmpty) throw const FormatException('Phrase vide.');
    final phonemes = g2p.phonemize(
      clean,
      language: 'en-us',
      stripStress: false,
      format: 'ipa',
      separator: ' ',
    );
    final tokens = _encode(phonemes);
    if (tokens.length > _maxTokens) {
      final chunks = _split(clean);
      if (chunks.length == 1) {
        throw const FormatException('Phrase trop longue pour Kokoro.');
      }
      final audio = <double>[];
      for (final chunk in chunks) {
        audio.addAll(await generate(chunk, voice: voice, speed: speed));
      }
      return Float32List.fromList(audio);
    }

    final allStyles = await _voice(voice);
    const styleWidth = 256;
    final rows = allStyles.length ~/ styleWidth;
    if (rows == 0) throw const FormatException('Style vocal Kokoro vide.');
    final row = tokens.length.clamp(0, rows - 1);
    final style = Float32List.sublistView(
      allStyles,
      row * styleWidth,
      (row + 1) * styleWidth,
    );
    final owned = <OrtValue>[];
    try {
      final ids = await OrtValue.fromList(
        Int64List.fromList([0, ...tokens, 0]),
        [1, tokens.length + 2],
      );
      owned.add(ids);
      final styleTensor = await OrtValue.fromList(style, [1, styleWidth]);
      owned.add(styleTensor);
      final speedTensor = await OrtValue.fromList(
        Float32List.fromList([(speed * .8).clamp(.45, 1.7)]),
        [1],
      );
      owned.add(speedTensor);
      final outputs = await _session.run({
        'input_ids': ids,
        'style': styleTensor,
        'speed': speedTensor,
      });
      owned.addAll(outputs.values);
      OrtValue? selected;
      var selectedLength = 0;
      for (final output in outputs.values) {
        final length = output.shape.fold<int>(1, (a, b) => a * b);
        if (length > selectedLength) {
          selected = output;
          selectedLength = length;
        }
      }
      if (selected == null || selectedLength < sampleRate ~/ 10) {
        throw const FormatException('Audio Kokoro vide.');
      }
      final flattened = _flatten(await selected.asList());
      // Keep only a tiny safety tail; the queue applies its own edge treatment.
      final length = math.max(1, flattened.length - 600);
      return Float32List.fromList(flattened.take(length).toList());
    } finally {
      for (final value in owned.toSet()) {
        await value.dispose();
      }
    }
  }

  Future<void> close() => _session.close();

  static String _normalizeEnglish(String value) {
    const replacements = {
      '’': "'",
      '‘': "'",
      '“': '"',
      '”': '"',
      '—': ', ',
      '–': ', ',
      '…': '...',
      '\u00ad': '',
    };
    var text = value;
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    text =
        text
            .replaceAll(
              RegExp(
                r'[\u{1F000}-\u{1FAFF}\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFE00-\uFE0F\uFEFF]',
                unicode: true,
              ),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (text.isNotEmpty && !RegExp(r'''[.!?;:,)'"…]$''').hasMatch(text)) {
      text += '.';
    }
    return text;
  }

  static List<String> _split(String text) {
    final sentences = text.split(RegExp(r'(?<=[.!?;:])\s+'));
    if (sentences.length > 1) {
      return sentences.where((s) => s.isNotEmpty).toList();
    }
    final words = text.split(' ');
    final middle = words.length ~/ 2;
    if (middle == 0) return [text];
    return [words.take(middle).join(' '), words.skip(middle).join(' ')];
  }

  static List<int> _encode(String phonemes) {
    const pad = r'$';
    const punctuation = ';:,.!?¡¿—…«»" ';
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    const ipa =
        "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘'̩'ᵻ";
    final symbols = <String>[
      pad,
      ...punctuation.runes.map(String.fromCharCode),
      ...letters.runes.map(String.fromCharCode),
      ...ipa.runes.map(String.fromCharCode),
    ];
    final vocabulary = <int, int>{};
    for (var i = 0; i < symbols.length; i++) {
      vocabulary[symbols[i].runes.first] = i;
    }
    final encoded = <int>[];
    for (final rune in phonemes.runes) {
      final id = vocabulary[rune];
      if (id != null) encoded.add(id);
    }
    return encoded;
  }

  static List<double> _flatten(dynamic value) {
    if (value is num) return [value.toDouble()];
    if (value is List) {
      return value.expand<double>((part) => _flatten(part)).toList();
    }
    throw const FormatException('Sortie Kokoro invalide.');
  }
}
