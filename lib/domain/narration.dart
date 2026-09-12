import 'dart:math' as math;
import 'book.dart';

/// All offsets are UTF-16, like Dart String, Android TTS and iOS NSRange.
class SourceRange {
  const SourceRange(this.start, this.end);
  final int start, end;
}

class NarrationText {
  const NarrationText(this.spoken, this.sourceStart, this.sourceEnd);
  final String spoken;
  final List<int> sourceStart, sourceEnd;
  SourceRange displayRange(int start, int end) {
    if (sourceStart.isEmpty) return const SourceRange(0, 0);
    final a = start.clamp(0, sourceStart.length - 1).toInt();
    final b = (end - 1).clamp(a, sourceEnd.length - 1).toInt();
    return SourceRange(sourceStart[a], sourceEnd[b]);
  }

  Map<String, Object> toJson() => {
    'spoken': spoken,
    'starts': sourceStart,
    'ends': sourceEnd,
  };
  factory NarrationText.fromJson(Map<String, dynamic> j) => NarrationText(
    j['spoken'] as String,
    (j['starts'] as List).cast<int>(),
    (j['ends'] as List).cast<int>(),
  );
}

class SpeechSegment {
  const SpeechSegment({
    required this.block,
    required this.start,
    required this.end,
    required this.display,
    required this.narration,
    required this.heading,
  });
  final int block, start, end;
  final String display;
  final NarrationText narration;
  final bool heading;
}

/// Conservative, deterministic French normalization. It never paraphrases.
/// Expansions retain a many-to-one map to the original displayed characters.
class FrenchNarration {
  static final _replacements = RegExp(
    r'\b(?:Mme\.?|Mlle\.?|Dr\.|Pr\.|M\.)\s|\b\d{1,9}\b',
    unicode: true,
  );
  static const _small = [
    'zéro',
    'un',
    'deux',
    'trois',
    'quatre',
    'cinq',
    'six',
    'sept',
    'huit',
    'neuf',
    'dix',
    'onze',
    'douze',
    'treize',
    'quatorze',
    'quinze',
    'seize',
  ];

  static String integer(int n) {
    if (n < 0) return 'moins ${integer(-n)}';
    if (n < 17) return _small[n];
    if (n < 20) return 'dix-${integer(n - 10)}';
    if (n < 70) {
      final tens =
          ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'][n ~/
              10];
      final r = n % 10;
      return r == 0
          ? tens
          : r == 1
          ? '$tens et un'
          : '$tens-${integer(r)}';
    }
    if (n < 80) {
      return n == 71 ? 'soixante et onze' : 'soixante-${integer(n - 60)}';
    }
    if (n < 100) {
      return n == 80 ? 'quatre-vingts' : 'quatre-vingt-${integer(n - 80)}';
    }
    if (n < 1000) {
      final hundreds = n ~/ 100;
      final root = hundreds == 1 ? 'cent' : '${integer(hundreds)} cent';
      return n % 100 == 0
          ? '$root${hundreds > 1 ? 's' : ''}'
          : '$root ${integer(n % 100)}';
    }
    if (n < 1000000) {
      final q = n ~/ 1000;
      // "cent" and "vingt" are invariable before "mille".
      var prefix =
          q == 1
              ? ''
              : integer(q)
                  .replaceAll(RegExp(r'cents$'), 'cent')
                  .replaceAll(RegExp(r'vingts$'), 'vingt');
      final root = prefix.isEmpty ? 'mille' : '$prefix mille';
      return n % 1000 == 0 ? root : '$root ${integer(n % 1000)}';
    }
    final q = n ~/ 1000000;
    final root = '${integer(q)} million${q == 1 ? '' : 's'}';
    return n % 1000000 == 0 ? root : '$root ${integer(n % 1000000)}';
  }

  static NarrationText normalize(String source) {
    final text = StringBuffer();
    final starts = <int>[], ends = <int>[];
    void append(String value, int start, int end, {bool identity = false}) {
      text.write(value);
      for (var i = 0; i < value.length; i++) {
        starts.add(identity ? start + i : start);
        ends.add(identity ? start + i + 1 : end);
      }
    }

    var cursor = 0;
    for (final m in _replacements.allMatches(source)) {
      append(
        source.substring(cursor, m.start),
        cursor,
        m.start,
        identity: true,
      );
      final token = m[0]!;
      final trimmed = token.trim();
      String replacement;
      if (int.tryParse(trimmed) != null) {
        // Decimal values, dates, identifiers and leading zeros are deliberately
        // left to the voice engine; do not invent a semantic interpretation.
        final before = m.start > 0 ? source[m.start - 1] : '';
        final after = m.end < source.length ? source[m.end] : '';
        final number = int.parse(trimmed);
        final contextual =
            RegExp(r'[\d.,/:]').hasMatch(before + after) ||
            (trimmed.length > 1 && trimmed.startsWith('0'));
        replacement = contextual ? token : integer(number);
      } else {
        replacement = switch (trimmed.replaceAll('.', '')) {
          'Mme' => 'Madame ',
          'Mlle' => 'Mademoiselle ',
          'Dr' => 'Docteur ',
          'Pr' => 'Professeur ',
          'M' => 'Monsieur ',
          _ => token,
        };
      }
      append(replacement, m.start, m.end);
      cursor = m.end;
    }
    append(source.substring(cursor), cursor, source.length, identity: true);
    return NarrationText(text.toString(), starts, ends);
  }
}

class NarrationPlanner {
  static const maxCharacters = 280;
  static const _abbreviations = {
    'm.',
    'mme.',
    'mlle.',
    'dr.',
    'pr.',
    'etc.',
    'p.',
    'pp.',
    'vol.',
    'av.',
    'ex.',
  };

  List<SpeechSegment> plan(
    BookChapter chapter, {
    bool readNotes = false,
    bool readHeadings = true,
  }) {
    final segments = <SpeechSegment>[];
    for (var b = 0; b < chapter.blocks.length; b++) {
      final block = chapter.blocks[b];
      if ((block.note && !readNotes) || (block.heading && !readHeadings)) {
        continue;
      }
      for (final r in split(block.text)) {
        final display = block.text.substring(r.start, r.end);
        segments.add(
          SpeechSegment(
            block: b,
            start: r.start,
            end: r.end,
            display: display,
            narration: FrenchNarration.normalize(display),
            heading: block.heading,
          ),
        );
      }
    }
    return segments;
  }

  List<SourceRange> split(String text) {
    final result = <SourceRange>[];
    var start = 0;
    void add(int end) {
      var a = start, z = end;
      while (a < z && text[a].trim().isEmpty) {
        a++;
      }
      while (z > a && text[z - 1].trim().isEmpty) {
        z--;
      }
      if (z > a) result.add(SourceRange(a, z));
      start = end;
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      var boundary = false;
      if ('.!?…'.contains(c)) {
        final next = i + 1 < text.length ? text[i + 1] : '';
        final prev = i > 0 ? text[i - 1] : '';
        final preceding = text.substring(start, i + 1);
        final lastWord = preceding.split(RegExp(r'\s+')).last.toLowerCase();
        final decimal =
            c == '.' &&
            RegExp(r'\d').hasMatch(prev) &&
            RegExp(r'\d').hasMatch(next);
        final initial = RegExp(
          r'^[A-ZÀ-ÖØ-Þ]\.$',
        ).hasMatch(preceding.split(RegExp(r'\s+')).last);
        boundary =
            !decimal &&
            !initial &&
            !_abbreviations.contains(lastWord) &&
            (next.isEmpty || RegExp(r'[\s»”"\)]').hasMatch(next));
      }
      if (boundary) {
        var end = i + 1;
        while (end < text.length && '»”")!?…'.contains(text[end])) {
          end++;
        }
        add(end);
        i = end - 1;
      } else if (i - start >= maxCharacters) {
        // Prefer punctuation, otherwise a word boundary. Never split a surrogate pair.
        final fragment = text.substring(start, i + 1);
        var cut = math.max(
          fragment.lastIndexOf(';'),
          fragment.lastIndexOf(','),
        );
        if (cut < maxCharacters ~/ 2) cut = fragment.lastIndexOf(' ');
        if (cut > 0) {
          add(start + cut + 1);
        }
      }
    }
    if (start < text.length) add(text.length);
    return result;
  }
}
