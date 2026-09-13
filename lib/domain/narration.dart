import 'dart:math' as math;
import 'book.dart';
import 'pronunciation_dictionary.dart';

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
    r'''\b(?:Mme\.?|Mlle\.?|Dr\.|Pr\.|M\.)\s|\b\d{1,2}/\d{1,2}/\d{2,4}\b|\b\d{1,2}[:h]\d{2}\b|\b\d{1,9}(?:[,.]\d{1,6})?\b|\b\d{1,9}(?:er|re|e|ème)\b|(?:[A-ZÀ-ÖØ-Þ]\.?){2,8}|[\p{L}][\p{L}\p{M}'’\-]*|[œŒæÆ&%€$£@+×÷=−]|[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]|[\u2300-\u27bf\u{1f000}-\u{1faff}]''',
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

  static const _letters = {
    'A': 'a',
    'B': 'bé',
    'C': 'cé',
    'D': 'dé',
    'E': 'e',
    'F': 'èf',
    'G': 'gé',
    'H': 'ache',
    'I': 'i',
    'J': 'ji',
    'K': 'ka',
    'L': 'elle',
    'M': 'ème',
    'N': 'èn',
    'O': 'o',
    'P': 'pé',
    'Q': 'cul',
    'R': 'erre',
    'S': 'ès',
    'T': 'té',
    'U': 'u',
    'V': 'vé',
    'W': 'double vé',
    'X': 'iks',
    'Y': 'i grec',
    'Z': 'zède',
  };

  static const _months = [
    '',
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
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

  static NarrationText normalize(
    String source, {
    PronunciationDictionary dictionary = PronunciationDictionary.french,
  }) {
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
      final date = RegExp(
        r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$',
      ).firstMatch(trimmed);
      final time = RegExp(r'^(\d{1,2})[:h](\d{2})$').firstMatch(trimmed);
      final decimal = RegExp(r'^(\d+)[,.](\d+)$').firstMatch(trimmed);
      final ordinal = RegExp(
        r'^(\d+)(er|re|e|ème)$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      final dictionaryValue = dictionary.replacementFor(trimmed);
      if (date != null) {
        final day = int.parse(date[1]!);
        final month = int.parse(date[2]!);
        final year = int.parse(date[3]!);
        replacement =
            day >= 1 && day <= 31 && month >= 1 && month <= 12
                ? '${day == 1 ? 'premier' : integer(day)} ${_months[month]} ${integer(year)}'
                : _spellDigits(trimmed);
      } else if (time != null) {
        final hour = int.parse(time[1]!);
        final minute = int.parse(time[2]!);
        replacement =
            hour <= 23 && minute <= 59
                ? '${integer(hour)} heure${hour > 1 ? 's' : ''}${minute == 0 ? '' : ' ${integer(minute)}'}'
                : _spellDigits(trimmed);
      } else if (decimal != null) {
        final parts = [decimal[1]!, decimal[2]!];
        replacement =
            '${integer(int.parse(parts[0]))} virgule ${parts[1].split('').map((d) => integer(int.parse(d))).join(' ')}';
      } else if (ordinal != null) {
        final value = int.parse(ordinal[1]!);
        replacement = value == 1 ? 'premier' : '${integer(value)}ième';
      } else if (int.tryParse(trimmed) != null) {
        final before = m.start > 0 ? source[m.start - 1] : '';
        final after = m.end < source.length ? source[m.end] : '';
        final number = int.parse(trimmed);
        final contextual =
            RegExp(
              r'[\p{L}\d._/@#-]',
              unicode: true,
            ).hasMatch(before + after) ||
            (trimmed.length > 1 && trimmed.startsWith('0'));
        replacement = contextual ? _spellDigits(trimmed) : integer(number);
      } else if (dictionaryValue != null) {
        replacement = dictionaryValue;
      } else if (_isInitialism(trimmed)) {
        replacement = _spellInitialism(trimmed);
      } else {
        replacement = switch (trimmed.replaceAll('.', '')) {
          'Mme' => 'Madame ',
          'Mlle' => 'Mademoiselle ',
          'Dr' => 'Docteur ',
          'Pr' => 'Professeur ',
          'M' => 'Monsieur ',
          'œ' => 'oe',
          'Œ' => 'OE',
          'æ' => 'ae',
          'Æ' => 'AE',
          '&' => ' et ',
          '%' => ' pour cent ',
          '€' => ' euros ',
          r'$' => ' dollars ',
          '£' => ' livres sterling ',
          '@' => ' arobase ',
          '+' => ' plus ',
          '×' => ' fois ',
          '÷' => ' divisé par ',
          '=' => ' égale ',
          '−' => ' moins ',
          '\u00ad' || '\u200b' || '\ufeff' => '',
          _ => token,
        };
      }
      append(replacement, m.start, m.end);
      cursor = m.end;
    }
    append(source.substring(cursor), cursor, source.length, identity: true);
    return NarrationText(text.toString(), starts, ends);
  }

  static bool _isInitialism(String token) {
    final compact = token.replaceAll('.', '');
    return compact.length >= 2 &&
        compact.length <= 8 &&
        RegExp(r'^[A-ZÀ-ÖØ-Þ]+$', unicode: true).hasMatch(compact);
  }

  static String _spellInitialism(String token) => token
      .replaceAll('.', '')
      .split('')
      .map((letter) => _letters[letter] ?? letter.toLowerCase())
      .join(' ');

  static String _spellDigits(String value) => value
      .split('')
      .where((character) => RegExp(r'\d').hasMatch(character))
      .map((digit) => integer(int.parse(digit)))
      .join(' ');
}

/// English normalization is available to the playback layer when an English
/// offline synthesizer is selected. System voices can keep handling their own
/// locale-specific pronunciation.
class EnglishNarration {
  static final _tokens = RegExp(
    r'''\b\d{1,9}(?:[.,]\d{1,6})?\b|(?:[A-Z]\.?){2,8}|[\p{L}][\p{L}\p{M}'’\-]*|[&%€$£@+=]''',
    unicode: true,
  );

  static const _small = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];

  static String integer(int value) {
    if (value < 0) return 'minus ${integer(-value)}';
    if (value < 20) return _small[value];
    if (value < 100) {
      final tens =
          const [
            '',
            '',
            'twenty',
            'thirty',
            'forty',
            'fifty',
            'sixty',
            'seventy',
            'eighty',
            'ninety',
          ][value ~/ 10];
      return value % 10 == 0 ? tens : '$tens-${integer(value % 10)}';
    }
    if (value < 1000) {
      final root = '${integer(value ~/ 100)} hundred';
      return value % 100 == 0 ? root : '$root ${integer(value % 100)}';
    }
    if (value < 1000000) {
      final root = '${integer(value ~/ 1000)} thousand';
      return value % 1000 == 0 ? root : '$root ${integer(value % 1000)}';
    }
    final root = '${integer(value ~/ 1000000)} million';
    return value % 1000000 == 0 ? root : '$root ${integer(value % 1000000)}';
  }

  static NarrationText normalize(
    String source, {
    PronunciationDictionary dictionary = PronunciationDictionary.english,
  }) {
    final text = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    void append(String value, int start, int end, {bool identity = false}) {
      text.write(value);
      for (var i = 0; i < value.length; i++) {
        starts.add(identity ? start + i : start);
        ends.add(identity ? start + i + 1 : end);
      }
    }

    var cursor = 0;
    for (final match in _tokens.allMatches(source)) {
      append(
        source.substring(cursor, match.start),
        cursor,
        match.start,
        identity: true,
      );
      final token = match[0]!;
      final dictionaryValue = dictionary.replacementFor(token);
      String replacement;
      final decimal = RegExp(r'^(\d+)[,.](\d+)$').firstMatch(token);
      if (decimal != null) {
        replacement =
            '${integer(int.parse(decimal[1]!))} point ${decimal[2]!.split('').map((digit) => integer(int.parse(digit))).join(' ')}';
      } else if (int.tryParse(token) case final value?) {
        replacement = integer(value);
      } else if (dictionaryValue != null) {
        replacement = dictionaryValue;
      } else if (RegExp(r'^(?:[A-Z]\.?){2,8}$').hasMatch(token)) {
        replacement = token.replaceAll('.', '').split('').join(' ');
      } else {
        replacement = switch (token) {
          '&' => ' and ',
          '%' => ' percent ',
          '€' => ' euros ',
          r'$' => ' dollars ',
          '£' => ' pounds ',
          '@' => ' at ',
          '+' => ' plus ',
          '=' => ' equals ',
          _ => token,
        };
      }
      append(replacement, match.start, match.end);
      cursor = match.end;
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
