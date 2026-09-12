import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lisiere/audio/ctc_alignment.dart';

Float32List emissions(List<int> labels, int vocabulary) {
  final result = Float32List(labels.length * vocabulary)
    ..fillRange(0, labels.length * vocabulary, -8);
  for (var i = 0; i < labels.length; i++) {
    result[i * vocabulary + labels[i]] = 8;
  }
  return result;
}

void main() {
  test('Alignment follows actual frames, including pauses', () {
    final path =
        alignCtc(
          logits: emissions([0, 1, 1, 0, 2, 2, 0], 3),
          frames: 7,
          vocabularySize: 3,
          tokens: [1, 2],
          blank: 0,
        )!;
    expect(path.firstFrames, [1, 4]);
    expect(path.lastFrames, [2, 5]);
    expect(path.confidence, greaterThan(.99));
  });
  test('Repeated labels require a separating blank', () {
    final path =
        alignCtc(
          logits: emissions([1, 0, 1], 2),
          frames: 3,
          vocabularySize: 2,
          tokens: [1, 1],
          blank: 0,
        )!;
    expect(path.firstFrames, [0, 2]);
    expect(
      alignCtc(
        logits: emissions([1, 1], 2),
        frames: 2,
        vocabularySize: 2,
        tokens: [1, 1],
        blank: 0,
      ),
      isNull,
    );
  });
  test('Malformed or impossible input returns no alignment', () {
    expect(
      alignCtc(
        logits: Float32List(0),
        frames: 0,
        vocabularySize: 2,
        tokens: [1],
        blank: 0,
      ),
      isNull,
    );
    expect(
      alignCtc(
        logits: Float32List(4),
        frames: 2,
        vocabularySize: 2,
        tokens: [0],
        blank: 0,
      ),
      isNull,
    );
    expect(
      alignCtc(
        logits: Float32List.fromList([double.nan, double.nan]),
        frames: 1,
        vocabularySize: 2,
        tokens: [1],
        blank: 0,
      ),
      isNull,
    );
  });
  test('Windowed-sinc downsampling keeps length and a low-frequency tone', () {
    final input = Float32List.fromList(
      List.generate(44100, (i) => math.sin(2 * math.pi * 400 * i / 44100)),
    );
    final output = resample16k(input, 44100);
    expect(output.length, 16000);
    var error = 0.0;
    for (var i = 100; i < output.length - 100; i++) {
      error += (output[i] - math.sin(2 * math.pi * 400 * i / 16000)).abs();
    }
    expect(error / (output.length - 200), lessThan(.01));
  });
  test('16 kHz input is copied, not mutated through an alias', () {
    final input = Float32List.fromList([1, 2, 3]);
    final output = resample16k(input, 16000);
    output[0] = 0;
    expect(input[0], 1);
  });
}
