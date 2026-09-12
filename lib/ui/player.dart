import 'package:flutter/material.dart';
import '../audio/speech_engine.dart';
import '../core/reader_controller.dart';
import 'design_system.dart';

class PlayerStrip extends StatelessWidget {
  const PlayerStrip({super.key, required this.reader, this.onOpen});
  final ReaderController reader;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    if (!reader.hasSession) return const SizedBox.shrink();
    final p = PaperColors.of(context), book = reader.book;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          if (book != null && !reader.previewing)
            BookCover(book: book, width: 36, height: 48)
          else
            Icon(Icons.graphic_eq, color: p.accent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Semantics(
                button: onOpen != null,
                label: 'Ouvrir le lecteur',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reader.previewing ? 'Aperçu de la voix' : book!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      reader.phase == SpeechPhase.preparing
                          ? 'Préparation locale…'
                          : reader.previewing
                          ? reader.voiceLabel
                          : reader.chapter!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconAction(
            label: reader.active ? 'Mettre en pause' : 'Lire',
            icon:
                reader.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
            prominent: true,
            onPressed: reader.toggle,
          ),
          if (reader.previewing) ...[
            const SizedBox(width: 6),
            IconAction(
              label: 'Arrêter l’aperçu',
              icon: Icons.close,
              onPressed: reader.stop,
            ),
          ],
        ],
      ),
    );
  }
}

class ReaderPlayer extends StatelessWidget {
  const ReaderPlayer({super.key, required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    final remaining =
        reader.segments.isEmpty
            ? 0
            : reader.segments.length - reader.segmentIndex;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  reader.phase == SpeechPhase.completed
                      ? 1
                      : reader.chapterProgress,
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  reader.phase == SpeechPhase.preparing
                      ? 'Préparation de la voix…'
                      : reader.phase == SpeechPhase.completed
                      ? 'Lecture terminée'
                      : '$remaining passages restants',
                  style: TextStyle(fontSize: 11, color: p.muted),
                ),
              ),
              Text(
                'Ch. ${reader.chapterIndex + 1} / ${reader.book?.chapters.length ?? 0}',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Semantics(
                label: 'Vitesse de lecture',
                child: GestureDetector(
                  onTap: () {
                    final rates = [.8, 1.0, 1.2, 1.5];
                    final next = rates.firstWhere(
                      (v) => v > reader.settings.speed + .01,
                      orElse: () => rates.first,
                    );
                    reader.setSpeed(next);
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${reader.settings.speed.toStringAsFixed(1)}×',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              IconAction(
                label: 'Passage précédent',
                icon: Icons.skip_previous_rounded,
                onPressed: reader.previous,
              ),
              IconAction(
                label: reader.active ? 'Mettre en pause' : 'Lire',
                prominent: true,
                large: true,
                icon:
                    reader.active
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                onPressed: reader.toggle,
              ),
              IconAction(
                label: 'Passage suivant',
                icon: Icons.skip_next_rounded,
                onPressed: reader.next,
              ),
              IconAction(
                label: 'Arrêter',
                icon: Icons.stop_rounded,
                onPressed: reader.stop,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reader.syncLabel,
            style: TextStyle(fontSize: 11, color: p.muted),
          ),
        ],
      ),
    );
  }
}
