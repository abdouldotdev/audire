import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/book.dart';
import 'design_system.dart';
import 'l10n.dart';
import 'reader_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with AutomaticKeepAliveClientMixin<LibraryPage> {
  bool _importing = false;
  String _search = '';
  String? _error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf'],
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
      title: 'Retirer ce livre ?'.tr(context),
      message:
          '« ${book.title} » et sa position seront retirés d’Audire. Votre document original ne sera pas modifié.',
      actions: [
        AlertAction(
          title: 'Annuler'.tr(context),
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: 'Retirer'.tr(context),
          onPressed: () {
            widget.reader.removeBook(book);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reader = widget.reader, p = PaperColors.of(context);
    final books =
        reader.library.books
            .where(
              (b) => '${b.title} ${b.author}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
            )
            .toList();
    return SafeArea(
      top: true,
      bottom: false,
      child: ListView(
        key: const PageStorageKey<String>('library-tab-scroll'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        children: [
          PageIntro(
            kicker: 'Bibliothèque'.tr(context),
            title: 'Vos livres'.tr(context),
          ),
          const SizedBox(height: 20),
          PrimaryAction(
            label: (_importing ? 'Import du document…' : 'Importer un document')
                .tr(context),
            subtitle: 'EPUB ou PDF'.tr(context),
            onPressed: _importing ? null : _import,
          ),
          const SizedBox(height: 20),
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
              placeholder: 'Un titre, un auteur…'.tr(context),
              prefixIcon: const Icon(Icons.search, size: 20),
              onChanged:
                  (v) => setState(() {
                    _search = v;
                  }),
            ),
          SectionLabel(
            'Livres'.tr(context),
            trailing: Text(
              '${books.length}',
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
                        ? 'Aucun livre ne correspond.'.tr(context)
                        : 'Aucun livre importé.'.tr(context),
                    textAlign: TextAlign.center,
                    style: LisiereTheme.editorial(context, size: 24),
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
                                style: LisiereTheme.editorial(
                                  context,
                                  size: 23,
                                ),
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
                            '${book.chapters.length} ${(book.format == DocumentFormat.pdf ? 'pages' : 'chapitres').tr(context)} · ${book.language.toUpperCase()}',
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
                                          ? 'Reprendre'.tr(context)
                                          : 'Ouvrir'.tr(context),
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
        ],
      ),
    );
  }
}
