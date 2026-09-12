import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lisiere/data/epub_importer.dart';
import 'package:lisiere/domain/narration.dart';

Uint8List epub({bool encrypted = false, bool traversal = false}) {
  final a = Archive();
  void file(String name, String data) {
    final bytes = utf8.encode(data);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  file(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  );
  file(
    'OPS/book.opf',
    '''<package><metadata><title>Test</title><creator>Auteur</creator><language>fr</language></metadata>
    <manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>
    <spine><itemref idref="two"/><itemref idref="nav"/><itemref idref="one"/></spine></package>''',
  );
  file(
    'OPS/one.xhtml',
    '<html><body><h1>Premier</h1><p>Un texte.</p></body></html>',
  );
  file(
    'OPS/two.xhtml',
    '<html><body><h1>Deuxième</h1><p>Un autre texte.</p></body></html>',
  );
  file('OPS/nav.xhtml', '<html><body><nav>À ignorer</nav></body></html>');
  if (encrypted) {
    file(
      'META-INF/encryption.xml',
      '<encryption><CipherReference URI="OPS/one.xhtml"/></encryption>',
    );
  }
  if (traversal) file('../outside.xhtml', 'Invalid');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('EPUB follows the spine, not archive or table-of-contents order', () {
    final book = EpubImporter().parse(epub());
    expect(book.title, 'Test');
    expect(book.chapters.map((c) => c.title), ['Deuxième', 'Premier']);
  });
  test('Encrypted text is rejected without attempting DRM removal', () {
    expect(
      () => EpubImporter().parse(epub(encrypted: true)),
      throwsA(isA<EpubImportException>()),
    );
  });
  test('Archive path traversal is rejected', () {
    expect(
      () => EpubImporter().parse(epub(traversal: true)),
      throwsA(isA<EpubImportException>()),
    );
  });
  test('Technical and hidden content is not narrated', () {
    final blocks = EpubImporter.cleanHtml(
      '''<body><nav>Sommaire</nav><script>ignore()</script>
      <p>Bonjour <em>tout le monde</em>.<a epub:type="noteref">1</a></p>
      <p hidden>secret</p><div style="display: none">non</div><span role="doc-pagebreak">42</span>
      <aside epub:type="footnote"><p>La note.</p></aside></body>''',
    );
    expect(blocks.map((b) => b.text), ['Bonjour tout le monde.', 'La note.']);
    expect(blocks.last.note, isTrue);
  });
  test('Original bundled book is readable and notes are opt-in', () {
    final book = EpubImporter().parse(
      File('assets/demo.epub').readAsBytesSync(),
    );
    expect(book.title, 'Le jardin des heures');
    expect(book.chapters.length, 3);
    final speech = NarrationPlanner()
        .plan(book.chapters.first)
        .map((s) => s.display)
        .join(' ');
    expect(speech, isNot(contains('Cette note sert')));
    expect(speech, isNot(contains('mention technique')));
    expect(speech, contains('Le jardin gardait son secret.'));
  });
}
