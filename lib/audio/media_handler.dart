import 'package:audio_service/audio_service.dart';
import '../core/reader_controller.dart';
import 'speech_engine.dart';

class LisiereAudioHandler extends BaseAudioHandler {
  LisiereAudioHandler(this.reader) {
    reader.addListener(_publish);
    _publish();
  }
  final ReaderController reader;
  String? _lastMedia;
  void _publish() {
    final book = reader.book;
    final identity =
        reader.previewing ? 'audition' : '${book?.id}:${reader.chapterIndex}';
    if (identity != _lastMedia) {
      _lastMedia = identity;
      mediaItem.add(
        reader.previewing
            ? const MediaItem(
              id: 'audition',
              title: 'Aperçu de la voix',
              artist: 'Lisière',
            )
            : book == null
            ? null
            : MediaItem(
              id: identity,
              title: reader.chapter!.title,
              album: book.title,
              artist: book.author,
              artUri: book.coverPath == null ? null : Uri.file(book.coverPath!),
            ),
      );
    }
    // A book is streamed phrase by phrase. Do not invent a whole-book duration,
    // or advertise a time seek operation that cannot be implemented accurately.
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          reader.active ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (reader.phase) {
          SpeechPhase.idle => AudioProcessingState.idle,
          SpeechPhase.preparing => AudioProcessingState.loading,
          SpeechPhase.playing ||
          SpeechPhase.paused => AudioProcessingState.ready,
          SpeechPhase.completed => AudioProcessingState.completed,
          SpeechPhase.error => AudioProcessingState.error,
        },
        playing: reader.wantsPlayback,
        updatePosition: Duration.zero,
        speed: reader.settings.speed,
        errorCode: reader.phase == SpeechPhase.error ? 1 : null,
        errorMessage: reader.phase == SpeechPhase.error ? reader.message : null,
      ),
    );
  }

  @override
  Future<void> play() => reader.play();
  @override
  Future<void> pause() => reader.pause();
  @override
  Future<void> stop() => reader.stop();
  @override
  Future<void> skipToNext() => reader.next();
  @override
  Future<void> skipToPrevious() => reader.previous();
  @override
  Future<void> setSpeed(double speed) => reader.setSpeed(speed);
  @override
  Future<void> onTaskRemoved() => reader.stop();
  @override
  Future<void> onNotificationDeleted() => reader.stop();
}
