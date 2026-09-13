import 'dart:io';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';
import 'library_page.dart';
import 'onboarding_page.dart';
import 'player.dart';
import 'reader_page.dart';
import 'settings_page.dart';
import 'voices_page.dart';

class LisiereApp extends StatelessWidget {
  const LisiereApp({super.key, required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: reader,
    builder: (context, _) {
      final mode = switch (reader.settings.theme) {
        PaperTheme.light => ThemeMode.light,
        PaperTheme.dark => ThemeMode.dark,
        PaperTheme.system => ThemeMode.system,
      };
      return AdaptiveApp(
        title: 'Audire',
        themeMode: mode,
        materialLightTheme: LisiereTheme.material(false),
        materialDarkTheme: LisiereTheme.material(true),
        cupertinoLightTheme: LisiereTheme.cupertino(false),
        cupertinoDarkTheme: LisiereTheme.cupertino(true),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        builder: (context, child) {
          final dark =
              mode == ThemeMode.dark ||
              (mode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          // Editorial widgets use a common semantic theme even inside CupertinoApp.
          // Material also supplies ink/selection plumbing without replacing native navigation.
          return Theme(
            data: LisiereTheme.material(dark),
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 16, color: PaperColors(dark).ink),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        home:
            reader.settings.onboardingCompleted
                ? HomeShell(reader: reader)
                : OnboardingPage(reader: reader),
      );
    },
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _pageStorage = PageStorageBucket();
  int _tab = 0;

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context), reader = widget.reader;
    return AdaptiveScaffold(
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: _tab,
        selectedItemColor: p.accent,
        unselectedItemColor: p.muted,
        onTap: _selectTab,
        items: [
          AdaptiveNavigationDestination(
            icon:
                Platform.isIOS ? 'books.vertical' : Icons.auto_stories_outlined,
            label: 'Bibliothèque',
          ),
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'waveform' : Icons.graphic_eq,
            label: 'Voix',
          ),
          AdaptiveNavigationDestination(
            icon: Platform.isIOS ? 'slider.horizontal.3' : Icons.tune,
            label: 'Profil',
          ),
        ],
      ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: PageStorage(
                bucket: _pageStorage,
                child: IndexedStack(
                  index: _tab,
                  sizing: StackFit.expand,
                  children: [
                    TickerMode(
                      enabled: _tab == 0,
                      child: LibraryPage(reader: reader),
                    ),
                    TickerMode(
                      enabled: _tab == 1,
                      child: VoicesPage(reader: reader),
                    ),
                    TickerMode(
                      enabled: _tab == 2,
                      child: SettingsPage(reader: reader),
                    ),
                  ],
                ),
              ),
            ),
            PlayerStrip(
              reader: reader,
              onOpen:
                  reader.book == null || reader.previewing
                      ? null
                      : () =>
                          openPage<void>(context, ReaderPage(reader: reader)),
            ),
          ],
        ),
      ),
    );
  }
}
