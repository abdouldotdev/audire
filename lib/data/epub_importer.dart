import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../domain/book.dart';

class EpubImportException implements Exception {
  const EpubImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EpubImporter {
  static const maxArchiveBytes = 100 * 1024 * 1024;
  static const maxInflatedBytes = 300 * 1024 * 1024;
  static const maxDocumentBytes = 6 * 1024 * 1024;

  ReadingBook parse(Uint8List bytes, {String? coverDirectory}) {
    if (bytes.length > maxArchiveBytes) {
      throw const EpubImportException('EPUB trop volumineux (maximum 100 Mo).');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 12000) {
      throw const EpubImportException('Cet EPUB contient trop de fichiers.');
    }
    var total = 0;
    final entries = <String, ArchiveFile>{};
    for (final f in archive) {
      total += f.size;
      if (f.size < 0 || total > maxInflatedBytes) {
        throw const EpubImportException(
          'Archive EPUB décompressée trop volumineuse.',
        );
      }
      final name = _safePath(f.name);
      if (entries.containsKey(name)) {
        throw const EpubImportException('EPUB invalide : chemins dupliqués.');
      }
      entries[name] = f;
    }
    Uint8List binary(String path, {int limit = maxDocumentBytes}) {
      final f = entries[path];
      if (f == null || !f.isFile || f.size > limit) {
        throw EpubImportException(
          'Fichier EPUB absent ou trop volumineux : $path',
        );
      }
      final data = f.content;
      if (data.length > limit) {
        throw const EpubImportException('Document EPUB trop volumineux.');
      }
      return Uint8List.fromList(data);
    }

    String text(String path) =>
        utf8.decode(binary(path), allowMalformed: false);
    XmlDocument xml(String path) {
      final source = text(path);
      if (RegExp(r'<!ENTITY\s', caseSensitive: false).hasMatch(source)) {
        throw const EpubImportException(
          'Les entités XML personnalisées ne sont pas prises en charge.',
        );
      }
      return XmlDocument.parse(source);
    }

    final container = xml('META-INF/container.xml');
    final roots = container.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'rootfile',
    );
    if (roots.isEmpty) {
      throw const EpubImportException('Le manifeste EPUB est introuvable.');
    }
    final opfPath = _safePath(roots.first.getAttribute('full-path') ?? '');
    final opf = xml(opfPath);
    final base = p.posix.dirname(opfPath);
    String resolve(String href) {
      final uri = Uri.parse(href);
      if (uri.hasScheme || uri.hasAuthority) {
        throw const EpubImportException(
          'Ressource EPUB externe non autorisée.',
        );
      }
      return _safePath(p.posix.join(base, Uri.decodeComponent(uri.path)));
    }

    String metadata(String name, String fallback) {
      final nodes = opf.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == name,
      );
      return nodes.isEmpty || nodes.first.innerText.trim().isEmpty
          ? fallback
          : nodes.first.innerText.trim();
    }

    final manifest = <String, XmlElement>{};
    for (final e in opf.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'item',
    )) {
      final id = e.getAttribute('id');
      if (id != null) manifest[id] = e;
    }
    if (entries.containsKey('META-INF/encryption.xml')) {
      final encryption = xml('META-INF/encryption.xml');
      for (final e in encryption.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'CipherReference',
      )) {
        final uri = e.getAttribute('URI') ?? '';
        if (RegExp(
          r'\.(xhtml|html|htm|opf)(?:$|[?#])',
          caseSensitive: false,
        ).hasMatch(uri)) {
          throw const EpubImportException(
            'Le texte de cet EPUB est chiffré. Importez une copie sans DRM.',
          );
        }
      }
    }
    final warnings = <String>[];
    final chapters = <BookChapter>[];
    final seen = <String>{};
    for (final ref in opf.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'itemref',
    )) {
      if (ref.getAttribute('linear') == 'no') continue;
      final item = manifest[ref.getAttribute('idref')];
      if (item == null) continue;
      final properties = (item.getAttribute('properties') ?? '').split(
        RegExp(r'\s+'),
      );
      if (properties.contains('nav')) continue;
      final media = item.getAttribute('media-type') ?? '';
      if (!media.contains('html')) continue;
      final path = resolve(item.getAttribute('href') ?? '');
      if (!seen.add(path)) continue;
      try {
        final blocks = cleanHtml(text(path));
        if (blocks.isEmpty) continue;
        final headings = blocks.where((b) => b.heading);
        final title =
            headings.isNotEmpty
                ? headings.first.text
                : 'Chapitre ${chapters.length + 1}';
        chapters.add(BookChapter(id: path, title: title, blocks: blocks));
      } catch (e) {
        // Missing/inaccessible chapters are not silently omitted from the UI.
        warnings.add('$path : $e');
      }
    }
    if (chapters.isEmpty) {
      throw const EpubImportException(
        'Aucun texte lisible trouvé. Cet EPUB peut être chiffré ou composé uniquement d’images.',
      );
    }
    final id = sha256.convert(bytes).toString();
    String? coverPath;
    if (coverDirectory != null) {
      final covers = manifest.values.where(
        (e) => (e.getAttribute('properties') ?? '')
            .split(' ')
            .contains('cover-image'),
      );
      XmlElement? cover = covers.isEmpty ? null : covers.first;
      if (cover == null) {
        final metas = opf.descendants.whereType<XmlElement>().where(
          (e) => e.name.local == 'meta' && e.getAttribute('name') == 'cover',
        );
        if (metas.isNotEmpty) {
          cover = manifest[metas.first.getAttribute('content')];
        }
      }
      if (cover != null) {
        final type = cover.getAttribute('media-type');
        if (type == 'image/jpeg' || type == 'image/png') {
          try {
            final data = binary(
              resolve(cover.getAttribute('href')!),
              limit: 10 * 1024 * 1024,
            );
            final ext = type == 'image/png' ? 'png' : 'jpg';
            coverPath = p.join(coverDirectory, '$id.$ext');
            File(coverPath).writeAsBytesSync(data, flush: true);
          } catch (_) {
            coverPath = null;
          }
        }
      }
    }
    return ReadingBook(
      id: id,
      title: metadata('title', 'Livre sans titre'),
      author: metadata('creator', 'Auteur inconnu'),
      language: metadata('language', 'fr'),
      chapters: chapters,
      coverPath: coverPath,
      warnings: warnings,
    );
  }

  static String _safePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        p.posix.isAbsolute(value)) {
      throw const EpubImportException('Chemin EPUB non autorisé.');
    }
    final normalized = p.posix.normalize(value);
    if (normalized == '..' || normalized.startsWith('../')) {
      throw const EpubImportException('Chemin EPUB hors de l’archive.');
    }
    return normalized;
  }

  /// Reading order is the EPUB spine; markup is never executed or spoken.
  /// Keep notes as classified blocks so the user can opt in later.
  static List<BookBlock> cleanHtml(String source) {
    final document = html.parse(source);
    final body = document.body;
    if (body == null) return [];
    for (final node in body.querySelectorAll(
      'script,style,nav,iframe,object,embed,svg,canvas,form,button,input,select,textarea',
    )) {
      node.remove();
    }
    String attr(dom.Element e, String name) {
      for (final a in e.attributes.entries) {
        if (a.key.toString() == name || a.key.toString().endsWith(':$name')) {
          return a.value;
        }
      }
      return '';
    }

    for (final e in body.querySelectorAll('*').toList()) {
      final role = attr(e, 'role');
      final type = attr(e, 'type');
      final style = attr(e, 'style').toLowerCase().replaceAll(' ', '');
      if (e.attributes.containsKey('hidden') ||
          attr(e, 'aria-hidden') == 'true' ||
          style.contains('display:none') ||
          style.contains('visibility:hidden') ||
          role == 'doc-pagebreak' ||
          role == 'doc-noteref' ||
          type
              .split(' ')
              .any(
                (t) => const [
                  'pagebreak',
                  'noteref',
                  'toc',
                  'landmarks',
                  'page-list',
                ].contains(t),
              )) {
        e.remove();
      }
    }
    const containers = {
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'blockquote',
      'pre',
      'div',
      'section',
      'article',
      'aside',
      'figure',
      'figcaption',
      'tr',
      'dt',
      'dd',
    };
    final blocks = <BookBlock>[];
    final buffer = StringBuffer();
    bool activeNote = false, activeHeading = false;
    void flush() {
      final text =
          buffer
              .toString()
              .replaceAll('\u00ad', '')
              .replaceAll('\u00a0', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      buffer.clear();
      if (text.isNotEmpty) {
        blocks.add(
          BookBlock(text: text, heading: activeHeading, note: activeNote),
        );
      }
    }

    void visit(dom.Node node, {bool note = false, bool heading = false}) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if (tag == 'br') {
        buffer.write(' ');
        return;
      }
      final type = attr(node, 'type').split(' ');
      final ownNote =
          note ||
          type.any(
            (t) => const [
              'footnote',
              'endnote',
              'rearnote',
              'footnotes',
              'endnotes',
            ].contains(t),
          ) ||
          const [
            'doc-footnote',
            'doc-endnote',
            'doc-endnotes',
          ].contains(attr(node, 'role'));
      final ownHeading = heading || RegExp(r'^h[1-6]$').hasMatch(tag ?? '');
      final block = containers.contains(tag);
      if (block) {
        flush();
        activeNote = ownNote;
        activeHeading = ownHeading;
      }
      if (tag == 'img') {
        return;
      } // Decorative cover/alt text is not narration.
      for (final child in node.nodes) {
        visit(child, note: ownNote, heading: ownHeading);
      }
      if (block) {
        flush();
        activeNote = note;
        activeHeading = heading;
      }
      if (tag == 'td' || tag == 'th') buffer.write(' ');
    }

    visit(body);
    flush();
    return blocks;
  }
}
