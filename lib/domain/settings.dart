enum VoiceEngine { system, neural }

enum PaperTheme { light, dark, system }

class ReaderSettings {
  VoiceEngine engine = VoiceEngine.system;
  PaperTheme theme = PaperTheme.system;
  String? systemVoice;
  String neuralVoice = 'F1';
  double speed = 1.0;
  double fontSize = 22;
  bool readNotes = false;
  bool readHeadings = true;
  bool followText = true;
  bool wordAlignment = true;
  int neuralSteps = 5;

  Map<String, Object?> toJson() => {
    'engine': engine.name,
    'theme': theme.name,
    'systemVoice': systemVoice,
    'neuralVoice': neuralVoice,
    'speed': speed,
    'fontSize': fontSize,
    'readNotes': readNotes,
    'readHeadings': readHeadings,
    'followText': followText,
    'wordAlignment': wordAlignment,
    'neuralSteps': neuralSteps,
  };
  void load(Map<String, dynamic> j) {
    engine = j['engine'] == 'neural' ? VoiceEngine.neural : VoiceEngine.system;
    theme = PaperTheme.values.firstWhere(
      (e) => e.name == j['theme'],
      orElse: () => PaperTheme.system,
    );
    systemVoice = j['systemVoice'] as String?;
    final voice = j['neuralVoice'] as String? ?? 'F1';
    neuralVoice = RegExp(r'^[FM][1-5]$').hasMatch(voice) ? voice : 'F1';
    speed = (j['speed'] as num? ?? 1).toDouble().clamp(0.65, 1.7).toDouble();
    fontSize =
        (j['fontSize'] as num? ?? 22).toDouble().clamp(17, 32).toDouble();
    readNotes = j['readNotes'] == true;
    readHeadings = j['readHeadings'] != false;
    followText = j['followText'] != false;
    wordAlignment = j['wordAlignment'] != false;
    neuralSteps = (j['neuralSteps'] as int? ?? 5).clamp(3, 10).toInt();
  }
}
