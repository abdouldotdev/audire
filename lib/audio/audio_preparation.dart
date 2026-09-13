import 'audio_cache_manifest.dart';
import 'speech_engine.dart';

enum AudioPreparationScope { chapter, book }

enum AudioPreparationState { preparing, completed, cancelled, failed }

class AudioPreparationRequest {
  const AudioPreparationRequest({
    required this.bookId,
    required this.scope,
    this.chapter,
    this.expectedPassages,
  }) : assert(
         scope != AudioPreparationScope.chapter || chapter != null,
         'A chapter preparation requires a chapter index.',
       );

  final String bookId;
  final AudioPreparationScope scope;
  final int? chapter;
  final int? expectedPassages;
}

class AudioPreparationProgress {
  const AudioPreparationProgress({
    required this.request,
    required this.state,
    required this.completedPassages,
    required this.preparedDuration,
    required this.bytes,
    required this.cachedPassages,
    this.currentChapter,
    this.currentSegment,
    this.estimatedBytes,
    this.message,
  });

  final AudioPreparationRequest request;
  final AudioPreparationState state;
  final int completedPassages;
  final Duration preparedDuration;
  final int bytes;
  final int cachedPassages;
  final int? currentChapter;
  final int? currentSegment;
  final int? estimatedBytes;
  final String? message;

  double? get fraction {
    final total = request.expectedPassages;
    if (total == null || total <= 0) return null;
    return (completedPassages / total).clamp(0, 1).toDouble();
  }
}

class AudioPreparationEstimate {
  const AudioPreparationEstimate({
    required this.passages,
    required this.cachedPassages,
    required this.cachedBytes,
    required this.estimatedTotalBytes,
  });

  final int passages;
  final int cachedPassages;
  final int cachedBytes;
  final int estimatedTotalBytes;
  int get estimatedDownloadBytes =>
      (estimatedTotalBytes - cachedBytes).clamp(0, estimatedTotalBytes);
}

/// Cancellation is cooperative: an ONNX inference already running finishes,
/// but no following passage is generated.
class AudioPreparationCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Optional capability implemented by engines that render reusable audio.
/// A future English engine can implement this contract without adding another
/// model-specific branch to the preparation UI.
abstract interface class SpeechPreparationEngine {
  Future<AudioPreparationEstimate> estimatePreparation(
    AudioPreparationRequest request,
  );

  Stream<AudioPreparationProgress> prepareQueue(
    SpeechQueueSource source, {
    required AudioPreparationRequest request,
    AudioPreparationCancellation? cancellation,
  });

  Future<AudioPlaybackCheckpoint?> restoreCheckpoint(
    String bookId, {
    String? audioSignature,
  });

  Future<AudioBookCacheInfo> bookCacheInfo(String bookId);
  Future<List<AudioBookCacheInfo>> listBookCaches();
  Future<void> setBookCachePinned(String bookId, bool pinned);
  Future<void> clearBookCache(String bookId);
}
