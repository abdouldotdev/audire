import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lisiere/ui/design_system.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test(
    'Reading and highlighted text have readable contrast in both themes',
    () {
      for (final dark in [false, true]) {
        final p = PaperColors(dark);
        expect(contrast(p.ink, p.paper), greaterThanOrEqualTo(4.5));
        expect(contrast(p.muted, p.paper), greaterThanOrEqualTo(4.5));
        expect(
          contrast(p.highlightInk, p.highlight),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      }
    },
  );
  testWidgets('Editorial intro supports narrow width and enlarged text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LisiereTheme.material(false),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: PageIntro(
                    kicker: 'Bibliothèque',
                    title: 'Vos livres,\nà votre rythme.',
                    subtitle: 'Le plaisir de lire. La liberté d’écouter.',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Vos livres,\nà votre rythme.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
