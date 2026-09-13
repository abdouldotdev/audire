enum VoiceEngine { system, neural, kokoro, qwen }

enum PaperTheme { light, dark, system }

enum TranslationMode { original, frenchAudio, bilingual }

enum ReaderLanguage { french, english }

extension ReaderLanguageLabel on ReaderLanguage {
  String get code => switch (this) {
    ReaderLanguage.french => 'fr',
    ReaderLanguage.english => 'en',
  };

  String get label => switch (this) {
    ReaderLanguage.french => 'Français',
    ReaderLanguage.english => 'Anglais',
  };

  static ReaderLanguage fromCode(String? code) =>
      (code ?? '').toLowerCase().startsWith('en')
          ? ReaderLanguage.english
          : ReaderLanguage.french;
}

class ReaderSettings {
  VoiceEngine engine = VoiceEngine.system;
  PaperTheme theme = PaperTheme.system;
  TranslationMode translationMode = TranslationMode.original;
  ReaderLanguage sourceLanguage = ReaderLanguage.french;
  ReaderLanguage targetLanguage = ReaderLanguage.french;
  String? frenchSystemVoice, englishSystemVoice, languagePromptBookId;
  String neuralVoice = 'F1';
  String kokoroVoice = 'Bella';
  String qwenVoice = 'Vivian';
  String qwenModel = 'compact';
  double speed = 1.0;
  double fontSize = 22;
  bool readNotes = false;
  bool readHeadings = true;
  bool followText = true;
  bool wordAlignment = true;
  bool playerPinned = true;
  bool onboardingCompleted = false;
  int neuralSteps = 5;

  Map<String, Object?> toJson() => {
    'engine': engine.name,
    'theme': theme.name,
    'translationMode': translationMode.name,
    'sourceLanguage': sourceLanguage.code,
    'targetLanguage': targetLanguage.code,
    'frenchSystemVoice': frenchSystemVoice,
    'englishSystemVoice': englishSystemVoice,
    'languagePromptBookId': languagePromptBookId,
    'neuralVoice': neuralVoice,
    'kokoroVoice': kokoroVoice,
    'qwenVoice': qwenVoice,
    'qwenModel': qwenModel,
    'speed': speed,
    'fontSize': fontSize,
    'readNotes': readNotes,
    'readHeadings': readHeadings,
    'followText': followText,
    'wordAlignment': wordAlignment,
    'playerPinned': playerPinned,
    'onboardingCompleted': onboardingCompleted,
    'neuralSteps': neuralSteps,
  };
  void load(Map<String, dynamic> j) {
    engine = VoiceEngine.values.firstWhere(
      (e) => e.name == j['engine'],
      orElse: () => VoiceEngine.system,
    );
    theme = PaperTheme.values.firstWhere(
      (e) => e.name == j['theme'],
      orElse: () => PaperTheme.system,
    );
    translationMode = TranslationMode.values.firstWhere(
      (e) => e.name == j['translationMode'],
      orElse: () => TranslationMode.original,
    );
    sourceLanguage = ReaderLanguageLabel.fromCode(
      j['sourceLanguage'] as String?,
    );
    targetLanguage = ReaderLanguageLabel.fromCode(
      j['targetLanguage'] as String?,
    );
    frenchSystemVoice =
        j['frenchSystemVoice'] as String? ?? j['systemVoice'] as String?;
    englishSystemVoice = j['englishSystemVoice'] as String?;
    languagePromptBookId = j['languagePromptBookId'] as String?;
    final voice = j['neuralVoice'] as String? ?? 'F1';
    neuralVoice = RegExp(r'^[FM][1-5]$').hasMatch(voice) ? voice : 'F1';
    const kokoroVoices = {
      'Default',
      'Bella',
      'Nicole',
      'Sarah',
      'Adam',
      'Michael',
    };
    final kokoro = j['kokoroVoice'] as String? ?? 'Bella';
    kokoroVoice = kokoroVoices.contains(kokoro) ? kokoro : 'Bella';
    const qwenVoices = {
      'Vivian',
      'Serena',
      'Aiden',
      'Ryan',
      'Dylan',
      'Eric',
      'Uncle Fu',
      'Ono Anna',
      'Sohee',
    };
    final qwen = j['qwenVoice'] as String? ?? 'Vivian';
    qwenVoice = qwenVoices.contains(qwen) ? qwen : 'Vivian';
    const qwenModels = {'compact', 'quality', 'max'};
    final qwenPack = j['qwenModel'] as String? ?? 'compact';
    qwenModel = qwenModels.contains(qwenPack) ? qwenPack : 'compact';
    speed = (j['speed'] as num? ?? 1).toDouble().clamp(0.65, 1.7).toDouble();
    fontSize =
        (j['fontSize'] as num? ?? 22).toDouble().clamp(17, 32).toDouble();
    readNotes = j['readNotes'] == true;
    readHeadings = j['readHeadings'] != false;
    followText = j['followText'] != false;
    wordAlignment = j['wordAlignment'] != false;
    playerPinned = j['playerPinned'] != false;
    onboardingCompleted = j['onboardingCompleted'] == true;
    neuralSteps = (j['neuralSteps'] as int? ?? 5).clamp(3, 10).toInt();
  }

  String? systemVoiceFor(ReaderLanguage language) => switch (language) {
    ReaderLanguage.french => frenchSystemVoice,
    ReaderLanguage.english => englishSystemVoice,
  };

  void setSystemVoice(ReaderLanguage language, String? id) {
    switch (language) {
      case ReaderLanguage.french:
        frenchSystemVoice = id;
      case ReaderLanguage.english:
        englishSystemVoice = id;
    }
  }
}
