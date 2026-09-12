import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../audio/speech_engine.dart';
import '../core/reader_controller.dart';
import '../domain/book.dart';
import 'design_system.dart';
import 'player.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  bool _following = true;
  int _lastBlock = -1, _lastChapter = -1;
  @override
  void initState() {
    super.initState();
    widget.reader.addListener(_changed);
  }

  @override
  void dispose() {
    widget.reader.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final reader = widget.reader;
    if (_lastChapter != reader.chapterIndex) {
      _lastChapter = reader.chapterIndex;
      _lastBlock = -1;
      _following = true;
    }
    final block = reader.segment?.block ?? 0;
    if (_lastBlock != block &&
        reader.active &&
        reader.settings.followText &&
        _following) {
      _lastBlock = block;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow();
      });
    }
    if (mounted) setState(() {});
  }

  void _follow({bool force = false}) {
    if (!_scroll.isAttached) return;
    final target = (widget.reader.segment?.block ?? 0) + 1;
    final visible = _positions.itemPositions.value.any(
      (p) =>
          p.index == target &&
          p.itemLeadingEdge >= .02 &&
          p.itemTrailingEdge <= .86,
    );
    if (force || !visible) {
      if (MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(index: target, alignment: .15);
      } else {
        _scroll.scrollTo(
          index: target,
          alignment: .15,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader,
        chapter = reader.chapter,
        p = PaperColors.of(context);
    if (chapter == null) {
      return AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Lecture'),
        body: const Center(
          child: Text('Choisissez un livre dans la bibliothèque.'),
        ),
      );
    }
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: reader.book!.title,
        tintColor: p.accent,
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: 'list.bullet',
            icon: Icons.format_list_bulleted,
            onPressed:
                () => openPage<void>(context, ChapterPage(reader: reader)),
          ),
          AdaptiveAppBarAction(
            iosSymbol: 'textformat.size',
            icon: Icons.text_fields,
            onPressed:
                () => openPage<void>(
                  context,
                  ReadingAppearancePage(reader: reader),
                ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (reader.message != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 112),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Notice(reader.message!, onClose: reader.clearMessage),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      if (notification.dragDetails != null && _following) {
                        setState(() {
                          _following = false;
                        });
                      }
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      key: ValueKey('${reader.book!.id}:${chapter.id}'),
                      itemScrollController: _scroll,
                      itemPositionsListener: _positions,
                      initialScrollIndex:
                          ((reader.segment?.block ?? 0) + 1)
                              .clamp(0, chapter.blocks.length)
                              .toInt(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                      itemCount: chapter.blocks.length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
                            child: Text(
                              'CHAPITRE ${reader.chapterIndex + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                color: p.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        if (i > chapter.blocks.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text(
                                '⁂',
                                style: TextStyle(fontSize: 28, color: p.muted),
                              ),
                            ),
                          );
                        }
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: ReadingParagraph(
                            reader: reader,
                            block: chapter.blocks[i - 1],
                            index: i - 1,
                          ),
                        );
                      },
                    ),
                  ),
                  if (!_following && reader.settings.followText)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AdaptiveButton(
                          label: 'Revenir à la voix',
                          color: p.accent,
                          textColor: p.onAccent,
                          onPressed: () {
                            setState(() {
                              _following = true;
                            });
                            _follow(force: true);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ReaderPlayer(reader: reader),
          ],
        ),
      ),
    );
  }
}

class ReadingParagraph extends StatelessWidget {
  const ReadingParagraph({
    super.key,
    required this.reader,
    required this.block,
    required this.index,
  });
  final ReaderController reader;
  final BookBlock block;
  final int index;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SpeechEvent>(
    valueListenable: reader.readingTick,
    builder: (context, event, _) {
      final p = PaperColors.of(context), segment = reader.segment;
      final selected = !reader.previewing && segment?.block == index;
      final excluded =
          (block.note && !reader.settings.readNotes) ||
          (block.heading && !reader.settings.readHeadings);
      final show =
          selected && event.range != null && event.phase == SpeechPhase.playing;
      final base = TextStyle(
        fontFamily: LisiereTheme.serif,
        fontFamilyFallback: LisiereTheme.serifFallback,
        fontSize:
            block.heading
                ? reader.settings.fontSize + 8
                : reader.settings.fontSize,
        height: block.heading ? 1.25 : 1.7,
        fontWeight: FontWeight.w400,
        color: block.note ? p.muted : p.ink,
        letterSpacing: block.heading ? -.5 : 0,
      );
      final spans = <InlineSpan>[];
      if (show) {
        final start =
            (segment!.start + event.range!.start)
                .clamp(0, block.text.length)
                .toInt();
        final end =
            (segment.start + event.range!.end)
                .clamp(start, block.text.length)
                .toInt();
        spans.add(TextSpan(text: block.text.substring(0, start)));
        spans.add(
          TextSpan(
            text: block.text.substring(start, end),
            style: TextStyle(
              backgroundColor:
                  event.quality == SyncQuality.sentence ? p.inset : p.highlight,
              color:
                  event.quality == SyncQuality.sentence
                      ? p.ink
                      : p.highlightInk,
            ),
          ),
        );
        spans.add(TextSpan(text: block.text.substring(end)));
      } else {
        spans.add(TextSpan(text: block.text));
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: GestureDetector(
            onDoubleTap: excluded ? null : () => reader.selectBlock(index),
            child: Semantics(
              onTap: excluded ? null : () => reader.selectBlock(index),
              hint:
                  excluded
                      ? 'Passage exclu de la narration'
                      : 'Touchez deux fois pour écouter ce paragraphe',
              child: Container(
                margin: EdgeInsets.only(
                  bottom: block.heading ? 24 : 18,
                  top: block.heading ? 20 : 0,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color:
                          selected && reader.active
                              ? p.accent
                              : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (block.note)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          excluded ? 'NOTE · NON LUE' : 'NOTE',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.3,
                            color: p.muted,
                          ),
                        ),
                      ),
                    Text.rich(
                      TextSpan(style: base, children: spans),
                      textAlign: TextAlign.start,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ChapterPage extends StatelessWidget {
  const ChapterPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    appBar: const AdaptiveAppBar(title: 'Chapitres'),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            reader.book!.title,
            style: LisiereTheme.editorial(context, size: 30),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < reader.book!.chapters.length; i++)
            ChoiceTile(
              title: reader.book!.chapters[i].title,
              subtitle: 'Chapitre ${i + 1}',
              selected: i == reader.chapterIndex,
              onPressed: () async {
                final autoplay = reader.active;
                await reader.selectChapter(i, autoplay: autoplay);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  );
}

class ReadingAppearancePage extends StatelessWidget {
  const ReadingAppearancePage({super.key, required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: reader,
    builder: (context, _) {
      final p = PaperColors.of(context);
      return AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Confort de lecture'),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SurfacePanel(
                child: Text(
                  'Chaque livre ouvre un chemin. Prenons le temps de le parcourir.',
                  style: LisiereTheme.editorial(
                    context,
                    size: reader.settings.fontSize,
                  ).copyWith(height: 1.65),
                ),
              ),
              SectionLabel(
                'Taille du texte',
                trailing: Text(
                  '${reader.settings.fontSize.round()} pt',
                  style: TextStyle(color: p.muted),
                ),
              ),
              AdaptiveSlider(
                value: reader.settings.fontSize,
                min: 17,
                max: 32,
                onChanged: reader.setFontSize,
              ),
              const SectionLabel('Vitesse de la voix'),
              Text(
                '${reader.settings.speed.toStringAsFixed(2)}×',
                textAlign: TextAlign.center,
              ),
              AdaptiveSlider(
                value: reader.settings.speed,
                min: .65,
                max: 1.7,
                onChanged: reader.setSpeed,
              ),
              const SizedBox(height: 16),
              SettingSwitch(
                title: 'Suivre la voix',
                subtitle:
                    'Le texte avance avec la narration. Un défilement manuel reste possible.',
                value: reader.settings.followText,
                onChanged: reader.setFollow,
              ),
              const SizedBox(height: 24),
              Text(
                'Un double toucher sur un paragraphe lance la lecture à cet endroit. La reprise après fermeture se fait au début du dernier passage.',
                style: TextStyle(color: p.muted, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
    },
  );
}
