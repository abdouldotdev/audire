import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lisiere_native_tts/lisiere_native_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'audio/media_handler.dart';
import 'audio/native_speech_engine.dart';
import 'audio/neural_speech_engine.dart';
import 'core/reader_controller.dart';
import 'data/library_store.dart';
import 'data/model_store.dart';
import 'ui/app.dart';
import 'ui/design_system.dart';
import 'translation/local_translation_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupScreen());
  try {
    final library = await LibraryStore.open();
    // Best-effort explicit OS backup exclusion. Never lose books on failure.
    try {
      await LisiereNativeTts().excludeFromBackup(library.root.path);
    } catch (_) {
      library.recoveryWarning =
          'L’exclusion des sauvegardes système n’a pas pu être confirmée. Vérifiez les sauvegardes de l’appareil.';
    }
    final firstRunMarker = File('${library.root.path}/initialized');
    if (!await firstRunMarker.exists()) {
      final bytes = await rootBundle.load('assets/demo.epub');
      await library.importBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      await firstRunMarker.writeAsString('1');
    }
    final models = ModelStore(library.root);
    await models.refresh();
    final temporary = await getTemporaryDirectory();
    final cache = Directory('${library.root.path}/audio-cache');
    final translationCache = Directory(
      '${library.root.path}/translation-cache',
    );
    // Migrate the former temporary caches once. Future launches reuse the files
    // in Application Support, including after process termination/app updates.
    for (final migration in [
      (Directory('${temporary.path}/lisiere-audio'), cache),
      (Directory('${temporary.path}/lisiere-translation'), translationCache),
    ]) {
      if (!await migration.$2.exists() && await migration.$1.exists()) {
        await migration.$1.rename(migration.$2.path);
      }
      await migration.$2.create(recursive: true);
    }
    final translator = LocalTranslationEngine(
      modelDirectory: Directory(models.translationPath),
      cacheDirectory: translationCache,
    );
    final reader = ReaderController(
      library: library,
      models: models,
      translator: translator,
      native: NativeSpeechEngine(),
      neural: NeuralSpeechEngine(
        models: models,
        settings: library.settings,
        cache: cache,
      ),
    );
    await AudioService.init<LisiereAudioHandler>(
      builder: () => LisiereAudioHandler(reader),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'lisiere_playback',
        androidNotificationChannelName: 'Lecture Audire',
        androidStopForegroundOnPause: false,
        androidNotificationOngoing: false,
      ),
    );
    await reader.initialize();
    runApp(LisiereApp(reader: reader));
  } catch (error) {
    runApp(StartupScreen(error: '$error'));
  }
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, this.error});
  final String? error;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: LisiereTheme.material(false),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Audire',
                  style: TextStyle(
                    fontFamily: LisiereTheme.serif,
                    fontSize: 44,
                  ),
                ),
                const SizedBox(height: 24),
                if (error == null)
                  const CircularProgressIndicator.adaptive()
                else ...[
                  const Text(
                    'Le lecteur n’a pas pu démarrer.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  const Text(
                    'Consultez README.md et vérifiez la configuration native du projet.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
