import 'package:flutter_test/flutter_test.dart';
import 'package:lisiere/domain/book.dart';
import 'package:lisiere/domain/narration.dart';

void main() {
  group('Conservative French normalization', () {
    test('French integers preserve special forms', () {
      expect(FrenchNarration.integer(71), 'soixante et onze');
      expect(FrenchNarration.integer(80), 'quatre-vingts');
      expect(FrenchNarration.integer(81), 'quatre-vingt-un');
      expect(FrenchNarration.integer(200), 'deux cents');
      expect(FrenchNarration.integer(201), 'deux cent un');
      expect(FrenchNarration.integer(80000), 'quatre-vingt mille');
      expect(FrenchNarration.integer(200000), 'deux cent mille');
      expect(FrenchNarration.integer(1000), 'mille');
    });
    test('Expanded words map back to displayed abbreviations and numbers', () {
      const source = 'M. Hugo a 21 livres.';
      final n = FrenchNarration.normalize(source);
      expect(n.spoken, 'Monsieur Hugo a vingt et un livres.');
      final monsieur = n.displayRange(0, 'Monsieur'.length);
      expect(source.substring(monsieur.start, monsieur.end).trim(), 'M.');
      final start = n.spoken.indexOf('vingt');
      final range = n.displayRange(start, start + 'vingt et un'.length);
      expect(source.substring(range.start, range.end), '21');
      expect(n.sourceStart.length, n.spoken.length);
      expect(n.sourceEnd.length, n.spoken.length);
    });
    test(
      'Dates, decimals and zero-prefixed identifiers are not reinterpreted',
      () {
        const source = '12/04/2025, 3,14 et 007 sont écrits ici.';
        expect(FrenchNarration.normalize(source).spoken, source);
      },
    );
    test('UTF-16 offsets survive emoji before French accented text', () {
      const source = '🌿 L’été revient.';
      final n = FrenchNarration.normalize(source);
      final offset = n.spoken.indexOf('été');
      final range = n.displayRange(offset, offset + 3);
      expect(source.substring(range.start, range.end), 'été');
    });
  });
  group('Narration planning', () {
    test('Titles and notes are independently selectable', () {
      const chapter = BookChapter(
        id: 'c',
        title: 'Un titre',
        blocks: [
          BookBlock(text: 'Un titre', heading: true),
          BookBlock(text: 'Le récit commence.'),
          BookBlock(text: 'Une note.', note: true),
        ],
      );
      final planner = NarrationPlanner();
      expect(planner.plan(chapter).map((s) => s.display), [
        'Un titre',
        'Le récit commence.',
      ]);
      expect(
        planner
            .plan(chapter, readHeadings: false, readNotes: true)
            .map((s) => s.display),
        ['Le récit commence.', 'Une note.'],
      );
    });
    test('Sentence boundaries do not split Monsieur or a decimal', () {
      const text = 'M. Hugo attend. La valeur est 3.14 ici. Puis il part.';
      final ranges = NarrationPlanner().split(text);
      expect(ranges.map((r) => text.substring(r.start, r.end)), [
        'M. Hugo attend.',
        'La valeur est 3.14 ici.',
        'Puis il part.',
      ]);
    });
    test('Long narration is cut at whitespace, never in a word', () {
      final text = List.filled(110, 'lumière').join(' ');
      final ranges = NarrationPlanner().split(text);
      expect(ranges.length, greaterThan(1));
      expect(ranges.map((r) => text.substring(r.start, r.end)).join(' '), text);
      for (final r in ranges) {
        expect(text.substring(r.start, r.end).startsWith('lumière'), isTrue);
        expect(text.substring(r.start, r.end).endsWith('lumière'), isTrue);
      }
    });
    test('Offsets remain inside original paragraph', () {
      const text = '  Bonjour ! « Tout va bien ? » Oui.  ';
      for (final r in NarrationPlanner().split(text)) {
        expect(r.start, greaterThanOrEqualTo(0));
        expect(r.end, lessThanOrEqualTo(text.length));
        expect(r.end, greaterThan(r.start));
      }
    });
  });
}
