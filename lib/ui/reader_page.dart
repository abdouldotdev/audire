import 'dart:async';
import 'dart:math' as math;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../audio/speech_engine.dart';
import '../core/reader_controller.dart';
import '../domain/book.dart';
import '../domain/narration.dart';
import '../domain/settings.dart';
import 'design_system.dart';
import 'player.dart';
import 'selection_translation.dart';
import 'live_page_flip.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final LivePageFlipController _flipController;
  int _lastChapter = -1;
  bool _showChrome = true;
  bool _wasPlaying = false;
  bool _selectionActive = false;
  Timer? _chromeTimer;
  List<_ReadingPageSlice> _pages = const [];
  String? _paginationKey;
  bool _followScheduled = false;
  DateTime? _manualPageUntil;

  @override
  void initState() {
    super.initState();
    _flipController = LivePageFlipController();
    _lastChapter = widget.reader.chapterIndex;
    _wasPlaying = widget.reader.active;
    widget.reader.addListener(_changed);
    widget.reader.readingTick.addListener(_followWord);
  }

  @override
  void dispose() {
    widget.reader.removeListener(_changed);
    widget.reader.readingTick.removeListener(_followWord);
    _chromeTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    if (!_showChrome && mounted) setState(() => _showChrome = true);
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (_selectionActive) return;
    if (_showChrome) {
      _chromeTimer?.cancel();
      setState(() => _showChrome = false);
      return;
    }
    _showControls();
  }

  void _scheduleControlsHide() {
    _chromeTimer?.cancel();
    if (_selectionActive || !widget.reader.active) {
      return;
    }
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.reader.active) setState(() => _showChrome = false);
    });
  }

  void _changed() {
    final reader = widget.reader;
    if (_selectionActive) {
      if (mounted) setState(() {});
      return;
    }
    if (!_wasPlaying && reader.active) _scheduleControlsHide();
    if (_wasPlaying && !reader.active) {
      _chromeTimer?.cancel();
      _showChrome = true;
    }
    _wasPlaying = reader.active;
    if (_lastChapter != reader.chapterIndex) {
      _lastChapter = reader.chapterIndex;
      _paginationKey = null;
      _pages = const [];
    }
    _scheduleFollow();
    if (mounted) setState(() {});
  }

  void _followWord() {
    if (!mounted ||
        _selectionActive ||
        !widget.reader.settings.followText ||
        widget.reader.readingTick.value.phase != SpeechPhase.playing) {
      return;
    }
    _scheduleFollow();
  }

  void _scheduleFollow() {
    // Background audio may emit thousands of word events without a UI frame.
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (mounted &&
          _pages.isNotEmpty &&
          !_selectionActive &&
          widget.reader.settings.followText &&
          (_manualPageUntil == null ||
              DateTime.now().isAfter(_manualPageUntil!))) {
        _flipController.goToPage(_pageForSegment(widget.reader.segmentIndex));
      }
    });
  }

  void _pageFlipped(int index) {
    _manualPageUntil = DateTime.now().add(const Duration(seconds: 7));
    // The final page is a real turn into the following chapter. Previously
    // PageView ended at the current chapter, which made a book look as if it
    // contained only a few passages.
    if (index == _pages.length) {
      unawaited(
        widget.reader.selectChapter(
          widget.reader.chapterIndex + 1,
          autoplay: widget.reader.wantsPlayback,
        ),
      );
      return;
    }
    if (_selectionActive || index < 0 || index >= _pages.length) return;
    final segment = _pages[index].firstSegment;
    if (segment == widget.reader.segmentIndex) return;
    if (_pageForSegment(widget.reader.segmentIndex) == index) return;
    widget.reader.selectSegment(segment, autoplay: widget.reader.wantsPlayback);
    _scheduleControlsHide();
  }

  int _pageForSegment(int segment) {
    final offset = widget.reader.readingTick.value.range?.start ?? 0;
    final index = _pages.indexWhere((page) => page.contains(segment, offset));
    return index < 0 ? 0 : index;
  }

  void _ensurePagination(BuildContext context, BoxConstraints constraints) {
    final reader = widget.reader;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final textWidth = math.max(
      120.0,
      math.min(680.0, constraints.maxWidth - 56),
    );
    final textHeight = math.max(120.0, constraints.maxHeight - 150);
    final key = [
      reader.book?.id,
      reader.chapterIndex,
      reader.segments.length,
      reader.settings.fontSize,
      textWidth.round(),
      textHeight.round(),
      scale.toStringAsFixed(2),
    ].join(':');
    if (_paginationKey == key) return;
    _paginationKey = key;
    _pages = _paginateReading(
      segments: reader.segments,
      width: textWidth,
      height: textHeight,
      fontSize: reader.settings.fontSize,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  void _selectionChanged(bool active) {
    // Selection notifications may happen during a text/layout update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectionActive == active) return;
      setState(() => _selectionActive = active);
      if (active) {
        _chromeTimer?.cancel();
      } else {
        _scheduleControlsHide();
        _changed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader,
        chapter = reader.chapter,
        p = PaperColors.of(context);
    final hasNextChapter =
        chapter != null &&
        reader.chapterIndex + 1 < reader.book!.chapters.length;
    if (chapter == null) {
      return AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Lecture'),
        body: const Center(
          child: Text('Choisissez un livre dans la bibliothèque.'),
        ),
      );
    }
    final showControls = _showChrome;
    final readerPaper = p.paper;
    return AdaptiveScaffold(
      // Keep the bar's height stable so showing controls never repaginates or
      // makes the current paragraph jump. Its content fades with the player.
      appBar: AdaptiveAppBar(
        tintColor: p.accent,
        leading: showControls ? null : const SizedBox(width: 48, height: 48),
        actions:
            showControls
                ? [
                  AdaptiveAppBarAction(
                    iosSymbol: 'list.bullet',
                    icon: Icons.format_list_bulleted,
                    onPressed:
                        () => openPage<void>(
                          context,
                          ChapterPage(reader: reader),
                        ),
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
                ]
                : const [],
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (reader.segments.isEmpty) {
                      return const Center(
                        child: Text('Aucun passage à afficher.'),
                      );
                    }
                    _ensurePagination(context, constraints);
                    final initialPage = _pageForSegment(reader.segmentIndex);
                    return LivePageFlip(
                      key: ValueKey(
                        '${reader.book!.id}:${chapter.id}:$_paginationKey',
                      ),
                      controller: _flipController,
                      initialIndex: initialPage,
                      color: readerPaper,
                      gesturesEnabled: !_selectionActive,
                      onPageFlipped: _pageFlipped,
                      itemCount: _pages.length + (hasNextChapter ? 1 : 0),
                      itemBuilder:
                          (context, index) =>
                              index < _pages.length
                                  ? _ReadingContentPage(
                                    reader: reader,
                                    page: _pages[index],
                                    pageNumber: index + 1,
                                    bottomInset: 0,
                                    onSelectionActivityChanged:
                                        _selectionChanged,
                                  )
                                  : _ChapterTurnPage(
                                    nextTitle:
                                        reader
                                            .book!
                                            .chapters[reader.chapterIndex + 1]
                                            .title,
                                  ),
                    );
                  },
                ),
              ),
            ),
            if (showControls && reader.message != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 112),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Notice(
                      reader.message!,
                      onClose: reader.clearMessage,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12 + MediaQuery.paddingOf(context).bottom,
              child: FloatingReaderPlayer(reader: reader),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterTurnPage extends StatelessWidget {
  const _ChapterTurnPage({required this.nextTitle});
  final String nextTitle;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.paper),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 34, height: 1, color: p.line),
                const SizedBox(height: 22),
                Text(
                  'CHAPITRE SUIVANT',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.8,
                    color: p.muted,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nextTitle.isEmpty ? 'La suite' : nextTitle,
                  textAlign: TextAlign.center,
                  style: LisiereTheme.editorial(context, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingPageSlice {
  const _ReadingPageSlice(
    this.firstSegment,
    this.endSegment,
    this.firstOffset,
    this.lastOffset,
  );
  final int firstSegment, endSegment, firstOffset, lastOffset;
  bool contains(int segment, int offset) =>
      segment >= firstSegment &&
      segment < endSegment &&
      (segment != firstSegment || offset >= firstOffset) &&
      (segment != endSegment - 1 || offset < lastOffset);
}

TextStyle _segmentStyle(SpeechSegment segment, double fontSize, Color color) =>
    TextStyle(
      fontFamily: LisiereTheme.serif,
      fontFamilyFallback: LisiereTheme.serifFallback,
      fontSize: segment.heading ? fontSize + 7 : fontSize,
      height: segment.heading ? 1.28 : 1.55,
      fontWeight: segment.heading ? FontWeight.w700 : FontWeight.w400,
      color: color,
      letterSpacing: segment.heading ? -.45 : 0,
    );

String _segmentSeparator(SpeechSegment previous, SpeechSegment current) =>
    previous.block == current.block ? ' ' : '\n\n';

List<_ReadingPageSlice> _paginateReading({
  required List<SpeechSegment> segments,
  required double width,
  required double height,
  required double fontSize,
  required TextScaler textScaler,
}) {
  final pages = <_ReadingPageSlice>[];
  var index = 0, offset = 0;
  final base = TextStyle(
    fontFamily: LisiereTheme.serif,
    fontFamilyFallback: LisiereTheme.serifFallback,
    fontSize: fontSize,
    height: 1.55,
  );
  bool fits(List<InlineSpan> spans) {
    final painter = TextPainter(
      text: TextSpan(style: base, children: spans),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final result = painter.height <= height;
    painter.dispose();
    return result;
  }

  while (index < segments.length) {
    final first = index, firstOffset = offset;
    var endSegment = index + 1, lastOffset = offset;
    final spans = <InlineSpan>[];
    while (index < segments.length) {
      final segment = segments[index];
      final prefix = <InlineSpan>[
        ...spans,
        if (index > first)
          TextSpan(text: _segmentSeparator(segments[index - 1], segment)),
      ];
      final style = _segmentStyle(segment, fontSize, Colors.black);
      final rest = segment.display.substring(offset);
      if (fits([...prefix, TextSpan(text: rest, style: style)])) {
        spans
          ..clear()
          ..addAll(prefix)
          ..add(TextSpan(text: rest, style: style));
        endSegment = index + 1;
        lastOffset = segment.display.length;
        index++;
        offset = 0;
        continue;
      }
      // Split at a measured word boundary, even within a long speech segment.
      // The text remains complete at large accessibility sizes.
      final boundaries = <int>[offset];
      for (final character in rest.characters) {
        boundaries.add(boundaries.last + character.length);
      }
      var low = 0, high = boundaries.length - 1, accepted = 0;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (fits([
          ...prefix,
          TextSpan(
            text: segment.display.substring(offset, boundaries[mid]),
            style: style,
          ),
        ])) {
          accepted = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      if (accepted == 0 && spans.isNotEmpty) break;
      var cut =
          boundaries[math.max(1, accepted).clamp(0, boundaries.length - 1)];
      final wordEnd = segment.display.lastIndexOf(' ', cut - 1) + 1;
      if (wordEnd > offset) cut = wordEnd;
      endSegment = index + 1;
      lastOffset = cut;
      offset = cut;
      if (offset >= segment.display.length) {
        index++;
        offset = 0;
      }
      break;
    }
    pages.add(_ReadingPageSlice(first, endSegment, firstOffset, lastOffset));
  }
  return pages;
}

class _ReadingContentPage extends StatefulWidget {
  const _ReadingContentPage({
    required this.reader,
    required this.page,
    required this.pageNumber,
    required this.bottomInset,
    this.onSelectionActivityChanged,
  });
  final ReaderController reader;
  final _ReadingPageSlice page;
  final int pageNumber;
  final double bottomInset;
  final ValueChanged<bool>? onSelectionActivityChanged;

  @override
  State<_ReadingContentPage> createState() => _ReadingContentPageState();
}

class _ReadingContentPageState extends State<_ReadingContentPage> {
  final Map<int, TapGestureRecognizer> _sentenceTaps = {};

  TapGestureRecognizer _tapFor(int index) => _sentenceTaps.putIfAbsent(
    index,
    () =>
        TapGestureRecognizer()
          ..onTap = () {
            unawaited(widget.reader.selectSegment(index, autoplay: true));
          },
  );

  @override
  void dispose() {
    for (final recognizer in _sentenceTaps.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _wordSpans(
    String text, {
    required TapGestureRecognizer recognizer,
    TextStyle? style,
  }) => [
    for (final token in RegExp(r'\s+|\S+', unicode: true).allMatches(text))
      TextSpan(
        text: token[0],
        style: style,
        // Whitespace stays passive so a tap in the page margin only toggles
        // the chrome. Every visible word seeks to its owning sentence.
        recognizer: token[0]!.trim().isEmpty ? null : recognizer,
      ),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SpeechEvent>(
    valueListenable: widget.reader.readingTick,
    builder: (context, event, _) {
      final reader = widget.reader;
      final page = widget.page;
      final p = PaperColors.of(context);
      final paper = p.paper;
      final spans = <InlineSpan>[];
      for (var index = page.firstSegment; index < page.endSegment; index++) {
        final segment = reader.segments[index];
        final sliceStart = index == page.firstSegment ? page.firstOffset : 0;
        final sliceEnd =
            index == page.endSegment - 1
                ? page.lastOffset
                : segment.display.length;
        if (index > page.firstSegment) {
          spans.add(
            TextSpan(
              text: _segmentSeparator(reader.segments[index - 1], segment),
            ),
          );
        }
        final style = _segmentStyle(segment, reader.settings.fontSize, p.ink);
        final tap = _tapFor(index);
        final active = !reader.previewing && reader.segmentIndex == index;
        final show =
            active && event.range != null && event.phase == SpeechPhase.playing;
        if (!show) {
          spans.add(
            TextSpan(
              style: style,
              children: _wordSpans(
                segment.display.substring(sliceStart, sliceEnd),
                recognizer: tap,
              ),
            ),
          );
          continue;
        }
        final start = event.range!.start.clamp(sliceStart, sliceEnd).toInt();
        final end = event.range!.end.clamp(start, sliceEnd).toInt();
        spans.add(
          TextSpan(
            style: style,
            children: [
              TextSpan(
                children: _wordSpans(
                  segment.display.substring(sliceStart, start),
                  recognizer: tap,
                ),
              ),
              TextSpan(
                style: TextStyle(
                  backgroundColor: p.readingHighlight,
                  color: p.onReadingHighlight,
                ),
                children: _wordSpans(
                  segment.display.substring(start, end),
                  recognizer: tap,
                ),
              ),
              TextSpan(
                children: _wordSpans(
                  segment.display.substring(end, sliceEnd),
                  recognizer: tap,
                ),
              ),
            ],
          ),
        );
      }
      return DecoratedBox(
        decoration: BoxDecoration(color: paper),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, 20, 28, 20 + widget.bottomInset),
            child: Column(
              children: [
                Text(
                  reader.book!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 34),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: SelectionTranslationArea(
                        sourceLabel: reader.settings.sourceLanguage.label,
                        targetLabel:
                            reader.settings.sourceLanguage ==
                                    ReaderLanguage.english
                                ? 'Français'
                                : 'Anglais',
                        onSelectionActivityChanged:
                            widget.onSelectionActivityChanged,
                        translate: (text) async {
                          if (reader.settings.sourceLanguage !=
                              ReaderLanguage.english) {
                            throw const SelectionTranslationUnavailable(
                              'La traduction du français vers l’anglais n’est pas encore disponible.',
                            );
                          }
                          final unavailable =
                              await reader.translator.enFrUnavailableReason();
                          if (unavailable != null) {
                            throw SelectionTranslationUnavailable(
                              reader.models.translationInstalled
                                  ? 'La traduction n’est pas disponible sur cet appareil pour le moment.'
                                  : 'Téléchargez le pack de traduction depuis Profil.',
                            );
                          }
                          return reader.translator.translateEnToFr(text);
                        },
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontFamily: LisiereTheme.serif,
                              fontFamilyFallback: LisiereTheme.serifFallback,
                              fontSize: reader.settings.fontSize,
                              height: 1.55,
                            ),
                            children: spans,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${widget.pageNumber}',
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
      top: true,
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
              subtitle:
                  reader.book!.format == DocumentFormat.pdf
                      ? 'Page du document'
                      : 'Chapitre ${i + 1}',
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
          top: true,
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
                'Touchez un mot pour reprendre à sa phrase. Maintenez pour sélectionner et traduire. La reprise après fermeture se fait au début du dernier passage.',
                style: TextStyle(color: p.muted, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
    },
  );
}
