import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:lisiere_native_tts/lisiere_native_tts.dart';

import '../domain/book.dart';
import 'pdf_ocr_strategy.dart';

class PdfImportException implements Exception {
  const PdfImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Converts a text PDF into the same reflowable model used by EPUB books.
/// The original page number is retained as the chapter id/title, while the
/// reader remains free to repaginate long pages for the current screen size.
class PdfImporter {
  static const maxFileBytes = 100 * 1024 * 1024;
  static const maxPages = 3000;
  static const maxExtractedCharacters = 16 * 1024 * 1024;

  Future<ReadingBook> parse(
    String path, {
    required String coverDirectory,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const PdfImportException('Ce PDF n’est plus accessible.');
    }
    final length = await file.length();
    if (length > maxFileBytes) {
      throw const PdfImportException('PDF trop volumineux (maximum 100 Mo).');
    }

    final id = (await sha256.bind(file.openRead()).first).toString();
    await pdfrxFlutterInitialize();
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      if (document.pages.isEmpty) {
        throw const PdfImportException('Ce PDF ne contient aucune page.');
      }
      if (document.pages.length > maxPages) {
        throw const PdfImportException(
          'Ce PDF contient trop de pages pour être importé.',
        );
      }

      final layouts = <_PdfPageLayout>[];
      var unreadablePages = 0;
      for (final page in document.pages) {
        try {
          layouts.add(await _PdfLayoutAnalyzer.extract(page));
        } on PdfImportException {
          rethrow;
        } catch (_) {
          unreadablePages++;
        }
      }

      final repeatedMargins = _PdfLayoutAnalyzer.repeatedMargins(layouts);
      final chapters = <BookChapter>[];
      final languageSample = StringBuffer();
      var extractedCharacters = 0;
      var imageOnlyPages = 0;
      var ocrPages = 0;
      for (final layout in layouts) {
        var blocks = _PdfLayoutAnalyzer.blocks(
          layout,
          repeatedMargins: repeatedMargins,
        );
        if (blocks.isEmpty) {
          try {
            final recognized = await _recognizeScannedPage(
              document.pages[layout.pageNumber - 1],
              id,
              layout.pageNumber,
              coverDirectory,
            );
            blocks = _blocks(recognized);
            if (blocks.isNotEmpty) ocrPages++;
          } catch (_) {
            // Keep importing all readable pages when a single scan fails.
          }
          if (blocks.isEmpty) {
            imageOnlyPages++;
            continue;
          }
        }
        extractedCharacters += blocks.fold<int>(
          0,
          (total, block) => total + block.text.length,
        );
        if (extractedCharacters > maxExtractedCharacters) {
          throw const PdfImportException(
            'Le texte de ce PDF est trop volumineux pour être importé.',
          );
        }
        if (languageSample.length < 12000) {
          for (final block in blocks) {
            languageSample.write(' ${block.text}');
            if (languageSample.length >= 12000) break;
          }
        }
        chapters.add(
          BookChapter(
            id: 'pdf-page-${layout.pageNumber}',
            title: 'Page ${layout.pageNumber}',
            blocks: blocks,
          ),
        );
      }
      if (chapters.isEmpty) {
        throw PdfImportException(PdfOcrStrategy.unavailableMessage);
      }

      final coverPath = await _writeCover(
        document.pages.first,
        id,
        coverDirectory,
      );
      final warnings = <String>[
        if (unreadablePages > 0)
          '$unreadablePages page${unreadablePages > 1 ? 's' : ''} n’a pas pu être lue.',
        if (imageOnlyPages > 0)
          '$imageOnlyPages page${imageOnlyPages > 1 ? 's' : ''} sans texte sélectionnable nécessite${imageOnlyPages > 1 ? 'nt' : ''} l’OCR.',
        if (ocrPages > 0)
          '$ocrPages page${ocrPages > 1 ? 's scannées ont' : ' scannée a'} été reconnue${ocrPages > 1 ? 's' : ''} sur cet appareil.',
      ];
      return ReadingBook(
        id: id,
        title: _titleFromPath(path),
        author: 'Auteur inconnu',
        language: _detectLanguage(languageSample.toString()),
        format: DocumentFormat.pdf,
        chapters: chapters,
        coverPath: coverPath,
        warnings: warnings,
      );
    } on PdfImportException {
      rethrow;
    } catch (_) {
      throw const PdfImportException(
        'Ce PDF ne peut pas être ouvert. Il est peut-être protégé par un mot de passe ou endommagé.',
      );
    } finally {
      await document?.dispose();
    }
  }

  Future<String> _recognizeScannedPage(
    PdfPage page,
    String bookId,
    int pageNumber,
    String directory,
  ) async {
    PdfImage? rendered;
    ui.Image? image;
    File? temporary;
    try {
      final scale = (PdfOcrStrategy.renderDpi / 72).clamp(2.0, 4.0);
      rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) return '';
      image = await rendered.createImage(pixelSizeThreshold: 3200);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return '';
      final temporaryDirectory = Directory(p.join(directory, '.ocr'));
      await temporaryDirectory.create(recursive: true);
      temporary = File(
        p.join(temporaryDirectory.path, '$bookId-$pageNumber.png'),
      );
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return LisiereNativeTts().recognizeText(temporary.path);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      image?.dispose();
      rendered?.dispose();
    }
  }

  Future<String?> _writeCover(PdfPage page, String id, String directory) async {
    PdfImage? rendered;
    ui.Image? image;
    try {
      final longestSide = page.width > page.height ? page.width : page.height;
      final scale = (1200 / longestSide).clamp(1.0, 2.5);
      rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) return null;
      image = await rendered.createImage(pixelSizeThreshold: 1200);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      await Directory(directory).create(recursive: true);
      final coverPath = p.join(directory, '$id.png');
      await File(coverPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return coverPath;
    } catch (_) {
      // A missing preview must never prevent access to an otherwise valid PDF.
      return null;
    } finally {
      image?.dispose();
      rendered?.dispose();
    }
  }

  static List<BookBlock> _blocks(String source) {
    final normalized = source
        .replaceAll('\u0000', '')
        .replaceAll('\u00ad', '')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final paragraphs = <String>[];
    final current = StringBuffer();
    var endsWithHyphen = false;

    void flush() {
      final text = current.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      current.clear();
      endsWithHyphen = false;
      if (text.isNotEmpty && !RegExp(r'^\d{1,5}$').hasMatch(text)) {
        paragraphs.add(text);
      }
    }

    for (final rawLine in normalized.split('\n')) {
      final line = rawLine.replaceAll(RegExp(r'[\t ]+'), ' ').trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (current.isEmpty) {
        current.write(line);
        endsWithHyphen = line.endsWith('-');
        continue;
      }
      final joinsHyphenatedWord =
          endsWithHyphen && RegExp(r'^\p{Ll}', unicode: true).hasMatch(line);
      if (joinsHyphenatedWord) {
        final previous = current.toString();
        final joined = previous.substring(0, previous.length - 1);
        current
          ..clear()
          ..write(joined)
          ..write(line);
      } else {
        current
          ..write(' ')
          ..write(line);
      }
      endsWithHyphen = line.endsWith('-');
    }
    flush();

    return [
      for (final text in paragraphs)
        BookBlock(text: text, heading: _looksLikeHeading(text)),
    ];
  }

  static bool _looksLikeHeading(String text) {
    final words = RegExp(r'\S+').allMatches(text).length;
    if (words == 0 || words > 12 || text.length > 100) return false;
    if (RegExp(r'[.!?…][”»\"]?$').hasMatch(text)) return false;
    return true;
  }

  static String _titleFromPath(String path) {
    final raw = p
        .basenameWithoutExtension(path)
        .replaceAll(RegExp(r'[_-]+'), ' ');
    final title = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? 'Document sans titre' : title;
  }

  static String _detectLanguage(String text) {
    final words = text.toLowerCase();
    int score(Iterable<String> candidates) => candidates.fold(
      0,
      (total, word) =>
          total +
          RegExp('\\b${RegExp.escape(word)}\\b').allMatches(words).length,
    );
    final french = score(const [
      'le',
      'la',
      'les',
      'un',
      'une',
      'des',
      'de',
      'du',
      'et',
      'est',
      'dans',
      'pour',
      'que',
      'qui',
      'avec',
      'vous',
      'nous',
    ]);
    final english = score(const [
      'the',
      'a',
      'an',
      'of',
      'and',
      'is',
      'in',
      'to',
      'for',
      'that',
      'with',
      'you',
      'we',
      'this',
      'from',
    ]);
    return english > french ? 'en' : 'fr';
  }
}

class _PdfPageLayout {
  const _PdfPageLayout({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.lines,
    required this.rawText,
  });

  final int pageNumber;
  final double width;
  final double height;
  final List<_PdfLine> lines;
  final String rawText;
}

class _PdfWord {
  const _PdfWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left, top, right, bottom;
  double get height => top - bottom;
  double get centerY => (top + bottom) / 2;
}

class _PdfLine {
  const _PdfLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left, top, right, bottom;
  double get width => right - left;
  double get height => top - bottom;
  double get centerY => (top + bottom) / 2;
}

class _PdfRow {
  _PdfRow(_PdfWord first)
    : words = [first],
      top = first.top,
      bottom = first.bottom;

  final List<_PdfWord> words;
  double top, bottom;
  double get height => top - bottom;
  double get centerY => (top + bottom) / 2;

  void add(_PdfWord word) {
    words.add(word);
    top = math.max(top, word.top);
    bottom = math.min(bottom, word.bottom);
  }
}

class _PdfLayoutAnalyzer {
  const _PdfLayoutAnalyzer._();

  static Future<_PdfPageLayout> extract(PdfPage page) async {
    final structured = await page.loadStructuredText();
    final words = <_PdfWord>[];
    final text = structured.fullText;
    for (final match in RegExp(r'\S+', unicode: true).allMatches(text)) {
      var left = double.infinity;
      var right = double.negativeInfinity;
      var top = double.negativeInfinity;
      var bottom = double.infinity;
      final end = math.min(match.end, structured.charRects.length);
      for (var index = match.start; index < end; index++) {
        final rect = structured.charRects[index];
        if (rect.isEmpty ||
            !rect.left.isFinite ||
            !rect.right.isFinite ||
            !rect.top.isFinite ||
            !rect.bottom.isFinite) {
          continue;
        }
        left = math.min(left, rect.left);
        right = math.max(right, rect.right);
        top = math.max(top, rect.top);
        bottom = math.min(bottom, rect.bottom);
      }
      if (left.isFinite && right > left && top > bottom) {
        words.add(
          _PdfWord(
            text: match[0]!,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
          ),
        );
      }
    }

    words.sort((a, b) {
      final vertical = b.centerY.compareTo(a.centerY);
      return vertical != 0 ? vertical : a.left.compareTo(b.left);
    });
    final rows = <_PdfRow>[];
    for (final word in words) {
      _PdfRow? closest;
      var closestDistance = double.infinity;
      for (final row in rows.reversed.take(8)) {
        final distance = (row.centerY - word.centerY).abs();
        final tolerance = math.max(row.height, word.height) * .62;
        if (distance <= tolerance && distance < closestDistance) {
          closest = row;
          closestDistance = distance;
        }
      }
      if (closest == null) {
        rows.add(_PdfRow(word));
      } else {
        closest.add(word);
      }
    }

    final lines = <_PdfLine>[];
    for (final row in rows) {
      row.words.sort((a, b) => a.left.compareTo(b.left));
      var chunk = <_PdfWord>[];
      void flush() {
        if (chunk.isEmpty) return;
        final value = chunk.map((word) => word.text).join(' ').trim();
        if (value.isNotEmpty) {
          lines.add(
            _PdfLine(
              text: value,
              left: chunk.first.left,
              top: chunk.map((word) => word.top).reduce(math.max),
              right: chunk.last.right,
              bottom: chunk.map((word) => word.bottom).reduce(math.min),
            ),
          );
        }
        chunk = <_PdfWord>[];
      }

      for (final word in row.words) {
        if (chunk.isNotEmpty) {
          final gap = word.left - chunk.last.right;
          final threshold = math.max(page.width * .035, row.height * 2.25);
          if (gap > threshold) flush();
        }
        chunk.add(word);
      }
      flush();
    }
    lines.sort(_topThenLeft);
    return _PdfPageLayout(
      pageNumber: page.pageNumber,
      width: page.width,
      height: page.height,
      lines: lines,
      rawText: text,
    );
  }

  static Set<String> repeatedMargins(List<_PdfPageLayout> pages) {
    final counts = <String, int>{};
    final textPages = pages.where((page) => page.lines.isNotEmpty).toList();
    for (final page in textPages) {
      final onThisPage = <String>{};
      for (final line in page.lines) {
        final inHeader = line.top >= page.height * .88;
        final inFooter = line.bottom <= page.height * .1;
        if (!inHeader && !inFooter) continue;
        final signature = _marginSignature(line.text);
        if (signature.length >= 3) onThisPage.add(signature);
      }
      for (final signature in onThisPage) {
        counts.update(signature, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final threshold = math.max(3, (textPages.length * .34).ceil());
    return {
      for (final entry in counts.entries)
        if (entry.value >= threshold) entry.key,
    };
  }

  static List<BookBlock> blocks(
    _PdfPageLayout page, {
    required Set<String> repeatedMargins,
  }) {
    if (page.lines.isEmpty) return PdfImporter._blocks(page.rawText);
    var lines =
        page.lines.where((line) {
          final text = line.text.trim();
          if (RegExp(
            r'^(?:\d{1,5}|[ivxlcdm]{1,8})$',
            caseSensitive: false,
          ).hasMatch(text)) {
            return false;
          }
          final inMargin =
              line.top >= page.height * .88 || line.bottom <= page.height * .1;
          return !inMargin || !repeatedMargins.contains(_marginSignature(text));
        }).toList();
    if (lines.isEmpty) return const [];
    lines = _readingOrder(lines, 0, page.width, depth: 0);
    final sortedHeights = lines.map((line) => line.height).toList()..sort();
    final normalLineHeight = sortedHeights[sortedHeights.length ~/ 2];

    final result = <BookBlock>[];
    var paragraph = StringBuffer();
    _PdfLine? previous;
    bool paragraphHeading = false;

    void flush() {
      final value = paragraph.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      paragraph = StringBuffer();
      if (value.isEmpty) return;
      result.add(BookBlock(text: value, heading: paragraphHeading));
      paragraphHeading = false;
    }

    for (final line in lines) {
      final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final heading = _lineLooksLikeHeading(
        text,
        line,
        normalLineHeight: normalLineHeight,
      );
      if (previous != null &&
          (_startsNewParagraph(previous, line) ||
              heading ||
              paragraphHeading)) {
        flush();
      }
      if (paragraph.isEmpty) paragraphHeading = heading;
      final joinsHyphenatedWord =
          paragraph.isNotEmpty &&
          paragraph.toString().endsWith('-') &&
          RegExp(r'^\p{Ll}', unicode: true).hasMatch(text);
      if (joinsHyphenatedWord) {
        final current = paragraph.toString();
        paragraph
          ..clear()
          ..write(current.substring(0, current.length - 1))
          ..write(text);
      } else {
        if (paragraph.isNotEmpty) paragraph.write(' ');
        paragraph.write(text);
      }
      previous = line;
    }
    flush();
    return result;
  }

  static bool _lineLooksLikeHeading(
    String text,
    _PdfLine line, {
    required double normalLineHeight,
  }) {
    final words = RegExp(r'\p{L}+', unicode: true).allMatches(text).length;
    if (words == 0 || words > 14 || text.length > 120) return false;
    if (RegExp(r'[.!?…][”»"]?$').hasMatch(text)) return false;
    final letters = text.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
    final upperCase = letters.length >= 2 && letters == letters.toUpperCase();
    final labelled = RegExp(
      r'^(?:chapitre|chapter|partie|part|livre|book|section)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
    return upperCase || labelled || line.height > normalLineHeight * 1.24;
  }

  static bool _startsNewParagraph(_PdfLine previous, _PdfLine next) {
    final jumpedUp = next.centerY > previous.centerY + previous.height;
    final horizontalOverlap =
        math.min(previous.right, next.right) -
        math.max(previous.left, next.left);
    final changedColumn =
        horizontalOverlap <= 0 &&
        (previous.left - next.left).abs() >
            math.max(previous.height, next.height) * 2;
    if (jumpedUp || changedColumn) return true;
    final verticalGap = previous.bottom - next.top;
    final lineHeight = math.max(previous.height, next.height);
    if (verticalGap > lineHeight * 1.05) return true;
    final indented = next.left - previous.left > lineHeight * 1.25;
    return indented && RegExp(r'[.!?…:;][”»"]?$').hasMatch(previous.text);
  }

  static List<_PdfLine> _readingOrder(
    List<_PdfLine> lines,
    double regionLeft,
    double regionRight, {
    required int depth,
  }) {
    if (lines.length < 6 || depth >= 3) {
      return [...lines]..sort(_topThenLeft);
    }
    final gutter = _bestGutter(lines, regionLeft, regionRight);
    if (gutter == null) return [...lines]..sort(_topThenLeft);
    final regionWidth = regionRight - regionLeft;
    final spanning = <_PdfLine>[];
    final left = <_PdfLine>[];
    final right = <_PdfLine>[];
    for (final line in lines) {
      final crosses = line.left < gutter - 3 && line.right > gutter + 3;
      final centered =
          line.width > regionWidth * .34 &&
          ((line.left + line.right) / 2 - gutter).abs() < regionWidth * .12;
      if (crosses || centered) {
        spanning.add(line);
      } else if ((line.left + line.right) / 2 < gutter) {
        left.add(line);
      } else {
        right.add(line);
      }
    }
    if (left.length < 2 || right.length < 2) {
      return [...lines]..sort(_topThenLeft);
    }
    if (spanning.isEmpty) {
      return [
        ..._readingOrder(left, regionLeft, gutter, depth: depth + 1),
        ..._readingOrder(right, gutter, regionRight, depth: depth + 1),
      ];
    }

    spanning.sort(_topThenLeft);
    final output = <_PdfLine>[];
    var upperBoundary = double.infinity;
    for (final divider in spanning) {
      final bandLeft =
          left
              .where(
                (line) =>
                    line.centerY < upperBoundary &&
                    line.centerY > divider.centerY,
              )
              .toList();
      final bandRight =
          right
              .where(
                (line) =>
                    line.centerY < upperBoundary &&
                    line.centerY > divider.centerY,
              )
              .toList();
      output
        ..addAll(_readingOrder(bandLeft, regionLeft, gutter, depth: depth + 1))
        ..addAll(
          _readingOrder(bandRight, gutter, regionRight, depth: depth + 1),
        )
        ..add(divider);
      upperBoundary = divider.centerY;
    }
    output
      ..addAll(
        _readingOrder(
          left.where((line) => line.centerY < upperBoundary).toList(),
          regionLeft,
          gutter,
          depth: depth + 1,
        ),
      )
      ..addAll(
        _readingOrder(
          right.where((line) => line.centerY < upperBoundary).toList(),
          gutter,
          regionRight,
          depth: depth + 1,
        ),
      );
    // Malformed PDFs may place a side note on exactly the same baseline as a
    // spanning heading. Preserve every line even if no strict band caught it.
    final missing =
        lines.where((line) => !output.contains(line)).toList()
          ..sort(_topThenLeft);
    output.addAll(missing);
    return output;
  }

  static double? _bestGutter(
    List<_PdfLine> lines,
    double regionLeft,
    double regionRight,
  ) {
    final width = regionRight - regionLeft;
    double? best;
    var bestScore = double.negativeInfinity;
    for (var step = 3; step <= 17; step++) {
      final candidate = regionLeft + width * step / 20;
      var left = 0, right = 0, crossing = 0;
      var clearance = width;
      for (final line in lines) {
        if (line.right <= candidate) {
          left++;
          clearance = math.min(clearance, candidate - line.right);
        } else if (line.left >= candidate) {
          right++;
          clearance = math.min(clearance, line.left - candidate);
        } else {
          crossing++;
          clearance = 0;
        }
      }
      if (left < 2 || right < 2) continue;
      if (crossing > math.max(2, (lines.length * .14).floor())) continue;
      final balance = math.min(left, right) / math.max(left, right);
      final score =
          balance * 8 - crossing * 1.8 + (clearance / width).clamp(0, .2) * 10;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return bestScore >= 1.3 ? best : null;
  }

  static int _topThenLeft(_PdfLine a, _PdfLine b) {
    final vertical = b.centerY.compareTo(a.centerY);
    return vertical != 0 ? vertical : a.left.compareTo(b.left);
  }

  static String _marginSignature(String source) =>
      source
          .toLowerCase()
          .replaceAll(RegExp(r'\d+'), '#')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^\p{L}# ]', unicode: true), '')
          .trim();
}
