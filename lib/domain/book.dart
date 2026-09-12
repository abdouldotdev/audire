class BookBlock {
  const BookBlock({
    required this.text,
    this.heading = false,
    this.note = false,
  });
  final String text;
  final bool heading;
  final bool note;
  Map<String, Object?> toJson() => {
    'text': text,
    'heading': heading,
    'note': note,
  };
  factory BookBlock.fromJson(Map<String, dynamic> j) => BookBlock(
    text: j['text'] as String,
    heading: j['heading'] == true,
    note: j['note'] == true,
  );
}

class BookChapter {
  const BookChapter({
    required this.id,
    required this.title,
    required this.blocks,
  });
  final String id;
  final String title;
  final List<BookBlock> blocks;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
  factory BookChapter.fromJson(Map<String, dynamic> j) => BookChapter(
    id: j['id'] as String,
    title: j['title'] as String,
    blocks:
        (j['blocks'] as List)
            .map((b) => BookBlock.fromJson(Map<String, dynamic>.from(b as Map)))
            .toList(),
  );
}

class ReadingBook {
  const ReadingBook({
    required this.id,
    required this.title,
    required this.author,
    required this.chapters,
    this.language = 'fr',
    this.coverPath,
    this.warnings = const [],
  });
  final String id, title, author, language;
  final String? coverPath;
  final List<BookChapter> chapters;
  final List<String> warnings;
  int get wordCount => chapters.fold(
    0,
    (sum, chapter) =>
        sum +
        chapter.blocks.fold(
          0,
          (n, b) => n + RegExp(r'\S+').allMatches(b.text).length,
        ),
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'language': language,
    'coverPath': coverPath,
    'warnings': warnings,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };
  factory ReadingBook.fromJson(Map<String, dynamic> j) => ReadingBook(
    id: j['id'] as String,
    title: j['title'] as String,
    author: j['author'] as String,
    language: j['language'] as String? ?? 'fr',
    coverPath: j['coverPath'] as String?,
    warnings: (j['warnings'] as List? ?? []).cast<String>(),
    chapters:
        (j['chapters'] as List)
            .map(
              (c) => BookChapter.fromJson(Map<String, dynamic>.from(c as Map)),
            )
            .toList(),
  );
}

class ReadingPosition {
  const ReadingPosition({this.chapter = 0, this.segment = 0});
  final int chapter, segment;
  Map<String, int> toJson() => {'chapter': chapter, 'segment': segment};
  factory ReadingPosition.fromJson(Map<String, dynamic> j) => ReadingPosition(
    chapter: j['chapter'] as int? ?? 0,
    segment: j['segment'] as int? ?? 0,
  );
}
