import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lisiere/core/reader_controller.dart';
import 'package:lisiere/data/model_store.dart';
import 'package:lisiere/domain/settings.dart';
import 'package:lisiere/ui/design_system.dart';
import 'package:lisiere/ui/onboarding_page.dart';

class TestModels extends ModelStore {
  TestModels() : super(Directory.systemTemp);
  int downloads = 0;
  bool fail = false;
  Completer<void>? transfer;
  @override
  Future<void> installNeural() async {
    downloads++;
    busy = true;
    cancelled = false;
    error = null;
    received = 5 * 1048576;
    total = 20 * 1048576;
    notifyListeners();
    await transfer?.future;
    neuralInstalled = !fail && !cancelled;
    if (fail) error = 'Simulated transport failure';
    busy = false;
    notifyListeners();
  }

  @override
  void cancel() {
    super.cancel();
    transfer?.complete();
  }
}

class TestReader extends ChangeNotifier implements ReaderController {
  @override
  final ReaderSettings settings = ReaderSettings();
  @override
  final TestModels models = TestModels();
  @override
  bool previewing = false;
  @override
  String? message;
  int auditions = 0;
  @override
  Future<void> stop() async {
    previewing = false;
    notifyListeners();
  }

  @override
  Future<void> audition() async {
    auditions++;
    previewing = true;
    notifyListeners();
  }

  @override
  Future<void> setEngine(VoiceEngine value) async {
    settings.engine = value;
    notifyListeners();
  }

  @override
  Future<void> setPlaybackLanguages({
    required ReaderLanguage source,
    required ReaderLanguage target,
  }) async {
    settings.sourceLanguage = source;
    settings.targetLanguage = target;
    notifyListeners();
  }

  @override
  void completeOnboarding() {
    settings.onboardingCompleted = true;
    notifyListeners();
  }

  @override
  void clearMessage() {
    message = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  TestReader reader, {
  Size size = const Size(393, 852),
  bool dark = false,
  double scale = 1,
  bool reduced = true,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: LisiereTheme.material(dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 59, bottom: 34),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: RepaintBoundary(
          key: captureKey,
          child: OnboardingPage(reader: reader),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> advance(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    for (final config in [
      (const Size(393, 852), 1.0),
      (const Size(320, 568), 1.6),
      (const Size(852, 393), 1.0),
    ]) {
      testWidgets(
        'All steps fit ${config.$1}, scale ${config.$2}, dark=$dark',
        (tester) async {
          final reader = TestReader();
          await mount(
            tester,
            reader,
            size: config.$1,
            scale: config.$2,
            dark: dark,
          );
          for (var step = 0; step < 3; step++) {
            expect(tester.takeException(), isNull);
            expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
            if (step < 2) await advance(tester);
          }
          expect(reader.models.downloads, 0);
        },
      );
    }
  }
  testWidgets('Preview is explicit and stops when advancing', (tester) async {
    final reader = TestReader();
    await mount(tester, reader);
    expect(reader.auditions, 0);
    await tester.tap(find.text('Écouter un extrait'));
    await tester.pumpAndSettle();
    expect(reader.previewing, isTrue);
    expect(find.text('Arrêter l’extrait'), findsOneWidget);
    await advance(tester);
    expect(reader.previewing, isFalse);
  });
  testWidgets(
    'Native voice finishes without any download, even after an old error',
    (tester) async {
      final reader = TestReader()..models.error = 'Old failure';
      await mount(tester, reader);
      await advance(tester);
      await advance(tester);
      await advance(tester);
      expect(reader.settings.onboardingCompleted, isTrue);
      expect(reader.models.downloads, 0);
      expect(reader.settings.engine, VoiceEngine.system);
    },
  );
  testWidgets(
    'Selecting pack does not download until CTA, then uses installed voices',
    (tester) async {
      final reader = TestReader();
      await mount(tester, reader);
      await advance(tester);
      await advance(tester);
      await tester.tap(find.byKey(const ValueKey('french-voices')));
      await tester.pumpAndSettle();
      expect(reader.models.downloads, 0);
      expect(find.text('Télécharger et commencer'), findsOneWidget);
      await advance(tester);
      expect(reader.models.downloads, 1);
      expect(reader.settings.engine, VoiceEngine.neural);
      expect(reader.settings.onboardingCompleted, isTrue);
    },
  );
  testWidgets('Failure stays on setup and supports retry', (tester) async {
    final reader = TestReader()..models.fail = true;
    await mount(tester, reader);
    await advance(tester);
    await advance(tester);
    await tester.tap(find.byKey(const ValueKey('french-voices')));
    await tester.pumpAndSettle();
    await advance(tester);
    expect(reader.settings.onboardingCompleted, isFalse);
    expect(find.text('Réessayer le téléchargement'), findsOneWidget);
    expect(find.textContaining('Simulated'), findsNothing);
    reader.models.fail = false;
    await advance(tester);
    expect(reader.models.downloads, 2);
    expect(reader.settings.onboardingCompleted, isTrue);
  });
  testWidgets('Cancellation keeps setup open and native voice can be used', (
    tester,
  ) async {
    final reader = TestReader()..models.transfer = Completer<void>();
    await mount(tester, reader);
    await advance(tester);
    await advance(tester);
    await tester.tap(find.byKey(const ValueKey('french-voices')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.ensureVisible(find.text('Annuler'));
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(reader.settings.onboardingCompleted, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('system-voice')));
    await tester.tap(find.byKey(const ValueKey('system-voice')));
    await tester.pumpAndSettle();
    await advance(tester);
    expect(reader.settings.onboardingCompleted, isTrue);
    expect(reader.settings.engine, VoiceEngine.system);
  });
  testWidgets(
    'Unsupported pair offers explicit original-language continuation',
    (tester) async {
      final reader = TestReader();
      await mount(tester, reader);
      await advance(tester);
      await tester.tap(find.text('Anglais').first);
      await tester.pumpAndSettle();
      expect(reader.settings.sourceLanguage, ReaderLanguage.french);
      expect(find.text('Continuer en anglais'), findsOneWidget);
      await advance(tester);
      expect(reader.settings.sourceLanguage, ReaderLanguage.english);
      expect(reader.settings.targetLanguage, ReaderLanguage.english);
      expect(find.byKey(const ValueKey('french-voices')), findsNothing);
    },
  );

  // Opt-in visual artifacts. Real fonts are loaded locally, never bundled.
  testWidgets(
    'Export onboarding previews',
    (tester) async {
      final serif = FontLoader('Georgia')..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Georgia.ttf',
        ).readAsBytes().then((v) => ByteData.sublistView(v)),
      );
      final sans = FontLoader('Roboto')..addFont(
        File(
          '/System/Library/Fonts/Supplemental/Arial.ttf',
        ).readAsBytes().then((v) => ByteData.sublistView(v)),
      );
      await serif.load();
      await sans.load();
      for (final dark in [false, true]) {
        final key = GlobalKey();
        await mount(tester, TestReader(), dark: dark, captureKey: key);
        for (var step = 0; step < 3; step++) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await tester.runAsync(() async {
            final file = File(
              'build/onboarding-previews/${dark ? 'dark' : 'light'}-${step + 1}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          image.dispose();
          if (step < 2) await advance(tester);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
    skip: !const bool.fromEnvironment('ONBOARDING_PREVIEWS'),
  );
}
