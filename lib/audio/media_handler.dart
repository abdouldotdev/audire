import 'package:audio_service/audio_service.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'speech_engine.dart';

class LisiereAudioHandler extends BaseAudioHandler {
  LisiereAudioHandler(this.reader) {
    reader.addListener(_publish);
    reader.readingTick.addListener(_onReadingTick);
    reader.neural.playback.addListener(_onReadingTick);
    _publish();
  }
  final ReaderController reader;
  String? _lastMedia;
  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);

  void _onReadingTick() {
    final now = DateTime.now();
    if (now.difference(_lastPositionPublish) <
        const Duration(milliseconds: 250)) {
      return;
    }
    _lastPositionPublish = now;
    _publish();
  }

  void _publish() {
    final book = reader.book;
    final tick =
        reader.activeEngine != VoiceEngine.system
            ? reader.neural.playback.value
            : reader.readingTick.value;
    final identity =
        reader.previewing ? 'audition' : '${book?.id}:${reader.chapterIndex}';
    if (identity != _lastMedia) {
      _lastMedia = identity;
      mediaItem.add(
        reader.previewing
            ? const MediaItem(
              id: 'audition',
              title: 'Aperçu de la voix',
              artist: 'Audire',
            )
            : book == null
            ? null
            : MediaItem(
              id: identity,
              title: reader.chapter!.title,
              album: book.title,
              artist: book.author,
              artUri: book.coverPath == null ? null : Uri.file(book.coverPath!),
              duration: tick.duration == Duration.zero ? null : tick.duration,
            ),
      );
      if (book != null && !reader.previewing) {
        queue.add([
          for (var index = 0; index < book.chapters.length; index++)
            MediaItem(
              id: '${book.id}:$index',
              title: book.chapters[index].title,
              album: book.title,
              artist: book.author,
              artUri: book.coverPath == null ? null : Uri.file(book.coverPath!),
            ),
        ]);
      }
    } else if (tick.duration != Duration.zero && mediaItem.value != null) {
      mediaItem.add(mediaItem.value!.copyWith(duration: tick.duration));
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          reader.active ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 2, 4],
        processingState: switch (reader.phase) {
          SpeechPhase.idle => AudioProcessingState.idle,
          SpeechPhase.preparing => AudioProcessingState.loading,
          SpeechPhase.playing ||
          SpeechPhase.paused => AudioProcessingState.ready,
          SpeechPhase.completed => AudioProcessingState.completed,
          SpeechPhase.error => AudioProcessingState.error,
        },
        playing: reader.wantsPlayback,
        updatePosition: tick.position,
        bufferedPosition:
            tick.bufferedPosition == Duration.zero
                ? tick.duration
                : tick.bufferedPosition,
        speed: reader.settings.speed,
        queueIndex: reader.chapterIndex,
        updateTime: DateTime.now(),
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
  Future<void> seek(Duration position) async {
    if (reader.activeEngine != VoiceEngine.system) {
      await reader.neural.seek(position);
    } else {
      await reader.selectSegment(reader.segmentIndex, autoplay: true);
    }
  }

  @override
  Future<void> rewind() async {
    if (reader.activeEngine == VoiceEngine.system) {
      await reader.previous();
      return;
    }
    await seek(reader.readingTick.value.position - const Duration(seconds: 15));
  }

  @override
  Future<void> fastForward() async {
    if (reader.activeEngine == VoiceEngine.system) {
      await reader.next();
      return;
    }
    await seek(reader.readingTick.value.position + const Duration(seconds: 15));
  }

  @override
  Future<void> skipToQueueItem(int index) {
    return reader.selectChapter(index, autoplay: reader.wantsPlayback);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'nextChapter':
        final index = reader.chapterIndex + 1;
        if (reader.book != null && index < reader.book!.chapters.length) {
          await reader.selectChapter(index, autoplay: reader.wantsPlayback);
        }
      case 'previousChapter':
        if (reader.chapterIndex > 0) {
          await reader.selectChapter(
            reader.chapterIndex - 1,
            autoplay: reader.wantsPlayback,
          );
        }
      case 'setPlaybackRate':
        final speed = extras?['speed'];
        if (speed is num) await reader.setSpeed(speed.toDouble());
      case 'setVoice':
        final engine = extras?['engine'];
        final voice = extras?['voiceId'];
        if (voice is String && voice.isNotEmpty) {
          await reader.selectVoice(
            nativeId: engine == 'system' ? voice : null,
            neuralId: engine == 'neural' ? voice : null,
            kokoroId: engine == 'kokoro' ? voice : null,
          );
        }
    }
  }

  @override
  Future<void> onNotificationDeleted() => reader.stop();
}
