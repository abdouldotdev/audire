import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/book.dart';
import 'design_system.dart';
import 'reader_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _importing = false;
  String _search = '';
  String? _error;
  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        allowMultiple: false,
        withData: false,
      );
      if (picked == null) return;
      final file = picked.files.single;
      if (file.path == null) {
        throw StateError(
          'Ce fichier n’est pas accessible. Copiez-le dans Fichiers puis réessayez.',
        );
      }
      final book = await widget.reader.library.importFile(file.path!);
      widget.reader.libraryChanged();
      if (mounted) await _open(book);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  Future<void> _open(ReadingBook book) async {
    await widget.reader.open(book);
    if (!mounted) return;
    await openPage<void>(context, ReaderPage(reader: widget.reader));
  }

  void _delete(ReadingBook book) {
    AdaptiveAlertDialog.show(
      context: context,
      title: 'Retirer ce livre ?',
      message:
          '« ${book.title} » et sa position seront retirés de Lisière. Votre fichier EPUB original ne sera pas modifié.',
      actions: [
        AlertAction(
          title: 'Annuler',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: 'Retirer',
          onPressed: () {
            widget.reader.removeBook(book);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader, p = PaperColors.of(context);
    final books =
        reader.library.books
            .where(
              (b) => '${b.title} ${b.author}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
            )
            .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
      children: [
        const PageIntro(
          kicker: 'La bibliothèque',
          title: 'Vos livres,\nà votre rythme.',
          subtitle: 'Le plaisir de lire. La liberté d’écouter.',
        ),
        const SizedBox(height: 24),
        PrimaryAction(
          label: _importing ? 'Import du livre…' : 'Importer un EPUB',
          onPressed: _importing ? null : _import,
        ),
        const SizedBox(height: 14),
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            'Livres conservés sur cet appareil',
            icon: Icons.phone_iphone_outlined,
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Notice(
            _error!,
            onClose:
                () => setState(() {
                  _error = null;
                }),
          ),
        if (reader.library.recoveryWarning != null)
          Notice(reader.library.recoveryWarning!),
        if (reader.library.books.length > 3)
          AdaptiveTextField(
            placeholder: 'Un titre, un auteur…',
            prefixIcon: const Icon(Icons.search, size: 20),
            onChanged:
                (v) => setState(() {
                  _search = v;
                }),
          ),
        SectionLabel(
          'À portée de voix',
          trailing: Text(
            '${books.length} livre${books.length > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
        ),
        if (books.isEmpty)
          SurfacePanel(
            child: Column(
              children: [
                Icon(Icons.auto_stories_outlined, size: 42, color: p.muted),
                const SizedBox(height: 16),
                Text(
                  _search.isNotEmpty
                      ? 'Aucun livre ne correspond.'
                      : 'Votre prochaine lecture commence ici.',
                  textAlign: TextAlign.center,
                  style: LisiereTheme.editorial(context, size: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  'Ajoutez un EPUB sans DRM. Les chapitres seront préparés pour la lecture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: p.muted),
                ),
              ],
            ),
          ),
        for (final book in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SurfacePanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _open(book),
                    child: BookCover(book: book, width: 78, height: 112),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _open(book),
                          child: Semantics(
                            button: true,
                            child: Text(
                              book.title,
                              style: LisiereTheme.editorial(context, size: 23),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          book.author,
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          '${book.chapters.length} chapitres · ${book.language.toUpperCase()}',
                          style: TextStyle(fontSize: 11, color: p.muted),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AdaptiveButton(
                                label:
                                    reader.library.positions.containsKey(
                                          book.id,
                                        )
                                        ? 'Reprendre'
                                        : 'Ouvrir',
                                color: p.inset,
                                textColor: p.ink,
                                onPressed: () => _open(book),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconAction(
                              label: 'Retirer ${book.title}',
                              icon: Icons.more_horiz,
                              onPressed: () => _delete(book),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Un espace calme.\nPas de compte, pas de fil d’actualité.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: LisiereTheme.serif,
            fontStyle: FontStyle.italic,
            height: 1.6,
            fontSize: 16,
            color: p.muted,
          ),
        ),
      ],
    );
  }
}
