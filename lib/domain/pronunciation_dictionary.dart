/// Small, deterministic pronunciation lexicon used before local synthesis.
///
/// This is deliberately data-only: replacing a token never changes the text
/// displayed by the reader, and narration keeps a mapping back to the source.
class PronunciationDictionary {
  const PronunciationDictionary(this.entries);

  final Map<String, String> entries;

  String? replacementFor(String token) {
    final key = token
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'[.\s]+$'), '');
    return entries[key];
  }

  static const french = PronunciationDictionary({
    'adn': 'a dé èn',
    'api': 'a pé i',
    'bbc': 'bé bé cé',
    'cnn': 'cé èn èn',
    'epub': 'i pub',
    'html': 'ache té ème elle',
    'http': 'ache té té pé',
    'https': 'ache té té pé ès',
    'ia': 'i a',
    'ibm': 'i bé ème',
    'isbn': 'i ès bé èn',
    'nasa': 'naza',
    'pdf': 'pé dé èf',
    'qr': 'cul erre',
    'sms': 'ès ème ès',
    'tgv': 'té gé vé',
    'tv': 'té vé',
    'ue': 'u e',
    'unesco': 'unesco',
    'unicef': 'unicef',
    'url': 'u erre elle',
    'usa': 'u ès a',
    'usb': 'u ès bé',
    'wifi': 'oui-fi',
    'wi-fi': 'oui-fi',
    'apple': 'apeul',
    'chatgpt': 'tchat gé pé té',
    'google': 'gougueul',
    'iphone': 'aïe faune',
    'openai': 'opeune aïe',
    'youtube': 'you tube',
  });

  static const english = PronunciationDictionary({
    'epub': 'e pub',
    'html': 'H T M L',
    'http': 'H T T P',
    'https': 'H T T P S',
    'isbn': 'I S B N',
    'pdf': 'P D F',
    'qr': 'Q R',
    'url': 'U R L',
    'usb': 'U S B',
  });
}

/// Language hints for mixed passages. This detector is conservative so a
/// proper name alone never switches the whole sentence to another voice.
enum NarrationLanguageHint { french, english, unknown }

class NarrationLanguageDetector {
  const NarrationLanguageDetector._();

  static NarrationLanguageHint detect(String text) {
    final normalized = text.toLowerCase().replaceAll('’', "'");
    int score(Iterable<String> words) => words.fold(
      0,
      (total, word) =>
          total +
          RegExp(
            "(?<![\\p{L}])${RegExp.escape(word)}(?![\\p{L}])",
            unicode: true,
          ).allMatches(normalized).length,
    );

    final french = score(const [
      'avec',
      'dans',
      'des',
      'est',
      'les',
      'mais',
      'nous',
      'pour',
      'que',
      'qui',
      'une',
      'vous',
    ]);
    final english = score(const [
      'and',
      'are',
      'for',
      'from',
      'is',
      'that',
      'the',
      'this',
      'to',
      'was',
      'were',
      'with',
      'you',
    ]);
    if (french >= 2 && french >= english * 2) {
      return NarrationLanguageHint.french;
    }
    if (english >= 2 && english >= french * 2) {
      return NarrationLanguageHint.english;
    }
    return NarrationLanguageHint.unknown;
  }
}
