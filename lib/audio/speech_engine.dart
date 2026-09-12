import 'dart:async';
import '../domain/narration.dart';

enum SpeechPhase { idle, preparing, playing, paused, completed, error }

enum SyncQuality { nativeWord, acousticWord, sentence }

class SpeechEvent {
  const SpeechEvent({
    required this.phase,
    this.range,
    this.quality = SyncQuality.sentence,
    this.message,
  });
  final SpeechPhase phase;
  final SourceRange? range;
  final SyncQuality quality;
  final String? message;
}

class LocalVoice {
  const LocalVoice({
    required this.id,
    required this.name,
    required this.language,
    required this.quality,
  });
  final String id, name, language;
  final int quality;
  factory LocalVoice.fromJson(Map<String, dynamic> j) => LocalVoice(
    id: j['id'] as String,
    name: j['name'] as String,
    language: j['language'] as String,
    quality: (j['quality'] as num? ?? 0).toInt(),
  );
}

abstract class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<void> speak(NarrationText text);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class WordCue {
  const WordCue({
    required this.startMs,
    required this.endMs,
    required this.start,
    required this.end,
  });
  final int startMs, endMs, start, end;
  Map<String, int> toJson() => {
    'startMs': startMs,
    'endMs': endMs,
    'start': start,
    'end': end,
  };
  factory WordCue.fromJson(Map<String, dynamic> j) => WordCue(
    startMs: j['startMs'] as int,
    endMs: j['endMs'] as int,
    start: j['start'] as int,
    end: j['end'] as int,
  );
}
