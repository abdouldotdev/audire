import 'dart:io';
import 'dart:math' as math;

class PrefetchTarget {
  const PrefetchTarget({
    required this.minimumPassages,
    required this.targetPassages,
    required this.targetDuration,
    required this.maximumPlaylistItems,
  });

  final int minimumPassages;
  final int targetPassages;
  final Duration targetDuration;
  final int maximumPlaylistItems;
}

/// Tunes the rolling reserve from observed synthesis cost and playback speed.
/// It deliberately reacts slowly so the target does not oscillate each phrase.
class AdaptivePrefetchPolicy {
  double _averagePassageMs = 6500;
  double _averageGenerationMs = 2500;
  int _underruns = 0;
  double _batteryLevel = 1;
  bool _lowPower = false;
  int _thermal = 0;

  void updateDeviceConditions({
    required double batteryLevel,
    required bool lowPower,
    required int thermal,
  }) {
    _batteryLevel = batteryLevel.clamp(0, 1);
    _lowPower = lowPower;
    _thermal = thermal;
  }

  void recordPrepared({
    required Duration audioDuration,
    required Duration generationTime,
  }) {
    _averagePassageMs = _smooth(
      _averagePassageMs,
      math.max(500, audioDuration.inMilliseconds).toDouble(),
    );
    _averageGenerationMs = _smooth(
      _averageGenerationMs,
      math.max(1, generationTime.inMilliseconds).toDouble(),
    );
    if (_underruns > 0 && _averageGenerationMs < _averagePassageMs * .5) {
      _underruns--;
    }
  }

  void recordUnderrun() => _underruns = math.min(8, _underruns + 1);

  PrefetchTarget target(double speed) {
    final safeSpeed = speed.clamp(.65, 1.7);
    final generationPressure =
        (_averageGenerationMs / (_averagePassageMs / safeSpeed)).clamp(.25, 4);
    final memoryPressure = _memoryPressure;
    var seconds = 75 + generationPressure * 35 + _underruns * 18;
    var passages = (seconds * 1000 / _averagePassageMs).ceil();
    if (memoryPressure > .82) {
      seconds *= .58;
      passages = math.min(passages, 12);
    } else if (memoryPressure > .68) {
      seconds *= .78;
      passages = math.min(passages, 18);
    }
    if (_lowPower || _batteryLevel < .2) {
      seconds *= .65;
      passages = math.min(passages, 12);
    }
    if (_thermal >= 2) {
      seconds *= .55;
      passages = math.min(passages, 8);
    }
    return PrefetchTarget(
      minimumPassages: math.min(8, 3 + _underruns),
      targetPassages: passages.clamp(6, 32),
      targetDuration: Duration(seconds: seconds.round().clamp(45, 240)),
      maximumPlaylistItems: memoryPressure > .82 ? 96 : 256,
    );
  }

  double _smooth(double previous, double value) => previous * .82 + value * .18;

  double get _memoryPressure {
    // Dart exposes RSS portably but not total RAM. These conservative bands
    // prevent aggressive buffering when ONNX plus decoded audio already occupy
    // substantial resident memory.
    final rss = ProcessInfo.currentRss;
    if (rss <= 0) return 0;
    return (rss / (900 * 1024 * 1024)).clamp(0, 1).toDouble();
  }
}
