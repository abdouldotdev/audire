import 'dart:math' as math;
import 'dart:typed_data';
import 'speech_engine.dart';

/// Fallback only: these are estimated boundaries, never acoustic alignment.
/// Use the actual voiced timeline, so silence and playback speed do not drift
/// against a wall-clock timer. An installed aligner replaces these estimates.
List<WordCue> estimateWordCues(Float32List audio, int sampleRate, String text) {
  final words =
      RegExp(
        r"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*",
        unicode: true,
      ).allMatches(text).toList();
  if (words.isEmpty || audio.isEmpty) return const [];
  final frameSize = math.max(1, sampleRate ~/ 100);
  final energies = <double>[];
  for (var start = 0; start < audio.length; start += frameSize) {
    var sum = 0.0;
    final end = math.min(audio.length, start + frameSize);
    for (var i = start; i < end; i++) {
      sum += audio[i] * audio[i];
    }
    energies.add(math.sqrt(sum / (end - start)));
  }
  final peak = energies.reduce(math.max);
  final threshold = math.max(0.002, peak * 0.035);
  final timeline = <int>[];
  for (var i = 0; i < energies.length; i++) {
    if (energies[i] >= threshold) timeline.add(i * 10);
  }
  if (timeline.isEmpty) return const [];
  final weights =
      words.map((word) {
        final value = word[0]!.toLowerCase();
        final syllables =
            RegExp(r'[aeiouyàâäéèêëîïôöùûüœ]+').allMatches(value).length;
        return math.max(1.0, syllables.toDouble()) +
            math.min(value.length, 15) * .08;
      }).toList();
  final total = weights.reduce((a, b) => a + b);
  var cumulative = 0.0;
  return List.generate(words.length, (index) {
    final first = (cumulative / total * (timeline.length - 1)).round();
    cumulative += weights[index];
    final last = (cumulative / total * (timeline.length - 1)).round();
    return WordCue(
      startMs: timeline[first],
      endMs: timeline[last] + 10,
      start: words[index].start,
      end: words[index].end,
    );
  });
}

/// Timeline fallback for native generators that return a rendered duration.
List<WordCue> estimateWordCuesFromDuration(int durationMs, String text) {
  final words =
      RegExp(
        r"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*",
        unicode: true,
      ).allMatches(text).toList();
  if (words.isEmpty || durationMs <= 0) return const [];
  final weights =
      words.map((word) {
        final value = word[0]!.toLowerCase();
        final syllables =
            RegExp(r'[aeiouyàâäéèêëîïôöùûüœ]+').allMatches(value).length;
        return math.max(1.0, syllables.toDouble()) +
            math.min(value.length, 15) * .08;
      }).toList();
  final total = weights.reduce((a, b) => a + b);
  var cumulative = 0.0;
  return List.generate(words.length, (index) {
    final start = (cumulative / total * durationMs).round();
    cumulative += weights[index];
    final end = (cumulative / total * durationMs).round();
    return WordCue(
      startMs: start,
      endMs: math.max(start + 1, end).clamp(0, durationMs),
      start: words[index].start,
      end: words[index].end,
    );
  });
}

/// Remove only excess edge silence, retaining enough room for initial/final
/// consonants. A short fade prevents PCM discontinuities between playlist items.
Float32List trimSpeechEdges(Float32List audio, int sampleRate) {
  final frame = math.max(1, sampleRate ~/ 200);
  final energies = <double>[];
  for (var i = 0; i < audio.length; i += frame) {
    var energy = 0.0;
    final end = math.min(audio.length, i + frame);
    for (var j = i; j < end; j++) {
      energy += audio[j] * audio[j];
    }
    energies.add(math.sqrt(energy / (end - i)));
  }
  if (energies.isEmpty) return audio;
  final sorted = List<double>.of(energies)..sort();
  final noise = sorted[(sorted.length * .15).floor()];
  final peak = sorted.last;
  final threshold = math.max(.0012, math.max(noise * 3.2, peak * .018));
  int first = -1, last = -1;
  for (var i = 0; i < energies.length; i++) {
    final nearby =
        energies.skip(i).take(3).where((value) => value >= threshold).length;
    if (nearby >= 2 || energies[i] >= threshold * 1.8) {
      if (first < 0) first = i * frame;
      last = math.min(audio.length, (i + 1) * frame);
    }
  }
  if (first < 0) return audio;
  // Keep enough attack/release for plosives while removing the long synthetic
  // margins that otherwise become audible gaps between playlist entries.
  final start = math.max(0, first - (sampleRate * .055).round());
  final end = math.min(audio.length, last + (sampleRate * .075).round());
  final result = Float32List.fromList(audio.sublist(start, end));
  final fade = math.min(result.length ~/ 2, (sampleRate * .003).round());
  for (var i = 0; i < fade; i++) {
    final gain = i / fade;
    result[i] *= gain;
    result[result.length - 1 - i] *= gain;
  }
  return result;
}
