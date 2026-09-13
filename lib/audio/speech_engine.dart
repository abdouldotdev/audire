import 'dart:async';
import '../domain/narration.dart';

enum SpeechPhase { idle, preparing, playing, paused, completed, error }

enum SyncQuality { nativeWord, acousticWord, estimatedWord, sentence }

class SpeechEngineCapabilities {
  const SpeechEngineCapabilities({
    required this.offline,
    required this.seek,
    required this.persistentAudio,
    required this.batchPreparation,
    required this.wordAlignment,
  });

  final bool offline;
  final bool seek;
  final bool persistentAudio;
  final bool batchPreparation;
  final bool wordAlignment;
}

/// A lazy source is consumed in order, including across chapter boundaries.
typedef SpeechQueueSource = Future<SpeechQueueItem?> Function();

class SpeechQueueItem {
  const SpeechQueueItem({
    required this.narration,
    this.chapter = -1,
    this.segment = -1,
    this.translation,
    this.bookId,
    this.cacheId,
    this.audioSignature = '',
  });
  final NarrationText narration;
  final int chapter, segment;
  final String? translation;
  final String? bookId;
  final String? cacheId;

  /// Voice/language/translation revision used to reject stale checkpoints.
  final String audioSignature;

  String get stableId => cacheId ?? '$chapter:$segment';
}

class SpeechEvent {
  const SpeechEvent({
    required this.phase,
    this.range,
    this.quality = SyncQuality.sentence,
    this.message,
    this.item,
    this.spokenRange,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
  });
  final SpeechPhase phase;
  final SourceRange? range;
  final SyncQuality quality;
  final String? message;
  final SpeechQueueItem? item;
  final SourceRange? spokenRange;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
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
  SpeechEngineCapabilities get capabilities => const SpeechEngineCapabilities(
    offline: true,
    seek: false,
    persistentAudio: false,
    batchPreparation: false,
    wordAlignment: false,
  );
  Stream<SpeechEvent> get events;
  Future<void> speak(NarrationText text);
  Future<void> startQueue(
    SpeechQueueSource source, {
    Duration initialPosition = Duration.zero,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
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
