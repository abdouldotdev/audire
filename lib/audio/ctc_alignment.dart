import 'dart:math' as math;
import 'dart:typed_data';

/// Viterbi alignment of an already-known transcript against acoustic logits.
/// Includes blank states and the repeat-label rule: "ll" requires a blank.
/// No proportional / word-length-based synthetic timings are used.
class CtcPath {
  const CtcPath(this.firstFrames, this.lastFrames, this.confidence);
  final List<int> firstFrames, lastFrames;
  final double confidence;
}

CtcPath? alignCtc({
  required Float32List logits,
  required int frames,
  required int vocabularySize,
  required List<int> tokens,
  required int blank,
}) {
  if (tokens.isEmpty ||
      frames <= 0 ||
      vocabularySize <= 1 ||
      logits.length != frames * vocabularySize ||
      blank < 0 ||
      blank >= vocabularySize ||
      tokens.any((t) => t < 0 || t >= vocabularySize || t == blank)) {
    return null;
  }
  var repeats = 0;
  for (var i = 1; i < tokens.length; i++) {
    if (tokens[i] == tokens[i - 1]) repeats++;
  }
  if (frames < tokens.length + repeats) return null;
  final states = 2 * tokens.length + 1;
  if (frames * states > 16000000) return null; // Bound backtrace memory.
  final labels = List<int>.generate(
    states,
    (s) => s.isEven ? blank : tokens[s ~/ 2],
  );
  final trace = Uint8List(frames * states);
  var previous = Float64List(states)
    ..fillRange(0, states, double.negativeInfinity);
  final normalized = Float32List(logits.length);
  for (var t = 0; t < frames; t++) {
    final offset = t * vocabularySize;
    var maxLogit = double.negativeInfinity;
    for (var v = 0; v < vocabularySize; v++) {
      maxLogit = math.max(maxLogit, logits[offset + v]);
    }
    if (!maxLogit.isFinite) return null;
    var sum = 0.0;
    for (var v = 0; v < vocabularySize; v++) {
      sum += math.exp(logits[offset + v] - maxLogit);
    }
    final z = maxLogit + math.log(sum);
    for (var v = 0; v < vocabularySize; v++) {
      normalized[offset + v] = logits[offset + v] - z;
    }
    final current = Float64List(states)
      ..fillRange(0, states, double.negativeInfinity);
    if (t == 0) {
      current[0] = normalized[blank];
      current[1] = normalized[tokens.first];
    } else {
      for (var s = 0; s < states; s++) {
        var best = previous[s], jump = 0;
        if (s > 0 && previous[s - 1] > best) {
          best = previous[s - 1];
          jump = 1;
        }
        if (s > 1 &&
            s.isOdd &&
            labels[s] != labels[s - 2] &&
            previous[s - 2] > best) {
          best = previous[s - 2];
          jump = 2;
        }
        if (best.isFinite) {
          current[s] = best + normalized[offset + labels[s]];
          trace[t * states + s] = jump;
        }
      }
    }
    previous = current;
  }
  var state =
      previous[states - 1] > previous[states - 2] ? states - 1 : states - 2;
  if (!previous[state].isFinite) return null;
  final first = List<int>.filled(tokens.length, -1),
      last = List<int>.filled(tokens.length, -1);
  var score = 0.0, count = 0;
  for (var t = frames - 1; t >= 0; t--) {
    if (state.isOdd) {
      final token = state ~/ 2;
      first[token] = t;
      if (last[token] < 0) last[token] = t;
      score += normalized[t * vocabularySize + labels[state]];
      count++;
    }
    if (t > 0) state -= trace[t * states + state];
  }
  if (first.any((f) => f < 0) || count == 0) return null;
  return CtcPath(first, last, math.exp(score / count));
}

/// Windowed-sinc low-pass resampling before the 16 kHz acoustic model.
/// A linear interpolator alone aliases high-frequency vocoder output.
Float32List resample16k(Float32List samples, int sampleRate) {
  if (sampleRate == 16000) return Float32List.fromList(samples);
  if (sampleRate <= 0 || samples.isEmpty) return Float32List(0);
  final ratio = 16000 / sampleRate;
  final output = Float32List((samples.length * ratio).floor());
  final cutoff = math.min(1.0, ratio) * 0.94;
  const radius = 24;
  for (var i = 0; i < output.length; i++) {
    final x = i / ratio, center = x.floor();
    var value = 0.0, weightSum = 0.0;
    for (var k = center - radius; k <= center + radius; k++) {
      if (k < 0 || k >= samples.length) continue;
      final d = x - k;
      final sinc =
          d.abs() < 1e-8
              ? cutoff
              : math.sin(math.pi * cutoff * d) / (math.pi * d);
      final window = 0.5 + 0.5 * math.cos(math.pi * d / (radius + 1));
      final weight = sinc * window;
      value += samples[k] * weight;
      weightSum += weight;
    }
    output[i] = weightSum.abs() < 1e-8 ? 0 : value / weightSum;
  }
  return output;
}
