import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../domain/book.dart';
import '../domain/settings.dart';
import 'epub_importer.dart';
import 'pdf_importer.dart';

class LibraryStore {
  LibraryStore._(this.root);
  final Directory root;
  final List<ReadingBook> books = [];
  final Map<String, ReadingPosition> positions = {};
  final ReaderSettings settings = ReaderSettings();
  String? recoveryWarning;
  Future<void> _writes = Future.value();

  static Future<LibraryStore> open() async {
    final base = await getApplicationSupportDirectory();
    final store = LibraryStore._(Directory(p.join(base.path, 'lisiere')));
    await Directory(p.join(store.root.path, 'books')).create(recursive: true);
    await Directory(p.join(store.root.path, 'covers')).create(recursive: true);
    final config = File(p.join(store.root.path, 'preferences.json'));
    if (await config.exists()) {
      try {
        final j =
            jsonDecode(await config.readAsString()) as Map<String, dynamic>;
        store.settings.load(
          Map<String, dynamic>.from(j['settings'] as Map? ?? {}),
        );
        final positions = j['positions'] as Map? ?? {};
        for (final e in positions.entries) {
          store.positions[e.key as String] = ReadingPosition.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      } catch (_) {
        store.recoveryWarning =
            'Les préférences ont été réinitialisées. Vos livres sont conservés.';
      }
    }
    await for (final f in Directory(p.join(store.root.path, 'books')).list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final source = await f.readAsString();
        final book = await Isolate.run(
          () =>
              ReadingBook.fromJson(jsonDecode(source) as Map<String, dynamic>),
        );
        store.books.add(book);
      } catch (_) {
        store.recoveryWarning =
            'Un livre local est illisible. Réimportez le document original.';
      }
    }
    return store;
  }

  Future<ReadingBook> importBytes(Uint8List bytes) async {
    final covers = p.join(root.path, 'covers');
    final book = await Isolate.run(
      () => EpubImporter().parse(bytes, coverDirectory: covers),
    );
    final existing = books.where((b) => b.id == book.id);
    if (existing.isNotEmpty) return existing.first;
    final encoded = await Isolate.run(() => jsonEncode(book.toJson()));
    await _atomic(File(p.join(root.path, 'books', '${book.id}.json')), encoded);
    books.insert(0, book);
    return book;
  }

  Future<ReadingBook> importFile(String path) async {
    final f = File(path);
    final extension = p.extension(path).toLowerCase();
    if (extension == '.pdf') {
      if (await f.length() > PdfImporter.maxFileBytes) {
        throw const PdfImportException('PDF trop volumineux (maximum 100 Mo).');
      }
      final book = await PdfImporter().parse(
        path,
        coverDirectory: p.join(root.path, 'covers'),
      );
      final existing = books.where((candidate) => candidate.id == book.id);
      if (existing.isNotEmpty) return existing.first;
      final encoded = await Isolate.run(() => jsonEncode(book.toJson()));
      await _atomic(
        File(p.join(root.path, 'books', '${book.id}.json')),
        encoded,
      );
      books.insert(0, book);
      return book;
    }
    if (extension == '.epub') {
      if (await f.length() > EpubImporter.maxArchiveBytes) {
        throw const EpubImportException(
          'EPUB trop volumineux (maximum 100 Mo).',
        );
      }
      return importBytes(await f.readAsBytes());
    }
    throw const EpubImportException('Choisissez un document EPUB ou PDF.');
  }

  Future<void> remove(ReadingBook book) async {
    books.removeWhere((b) => b.id == book.id);
    positions.remove(book.id);
    final f = File(p.join(root.path, 'books', '${book.id}.json'));
    if (await f.exists()) await f.delete();
    if (book.coverPath != null) {
      final cover = File(book.coverPath!);
      if (await cover.exists()) await cover.delete();
    }
    await save();
  }

  Future<void> save() {
    final data = jsonEncode({
      'settings': settings.toJson(),
      'positions': positions.map((k, v) => MapEntry(k, v.toJson())),
    });
    final next = _writes.then(
      (_) => _atomic(File(p.join(root.path, 'preferences.json')), data),
    );
    _writes = next.catchError((Object _) {});
    return next;
  }

  static Future<void> _atomic(File destination, String source) async {
    final temp = File('${destination.path}.tmp');
    await temp.writeAsString(source, flush: true);
    await temp.rename(destination.path);
  }
}
