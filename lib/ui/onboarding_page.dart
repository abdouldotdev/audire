import 'dart:async';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';
import 'l10n.dart';
import 'onboarding_art.dart';

/// Downloads are opt-in here; the reader never starts an installation.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _useFrenchPack = false, _downloadTranslation = false, _working = false;
  bool _automaticDownloadsStarted = false;
  String? _downloadingPack;
  bool _reduceMotion = false;
  String? _error;
  late ReaderLanguage _source, _target;
  late final AnimationController _motion;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final settings = widget.reader.settings;
    _source = settings.sourceLanguage;
    _target = settings.targetLanguage;
    _useFrenchPack =
        settings.engine == VoiceEngine.neural &&
        widget.reader.models.neuralInstalled;
    _downloadTranslation = widget.reader.models.translationInstalled;
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    widget.reader.addListener(_syncMotion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  void _syncMotion() {
    final animate = !_reduceMotion && _step == 0;
    if (animate && !_motion.isAnimating) _motion.repeat();
    if (!animate) _motion.stop();
  }

  @override
  void dispose() {
    widget.reader.removeListener(_syncMotion);
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _syncMotion();
  }

  Future<void> _back() async {
    await widget.reader.stop();
    if (mounted) _go(_step - 1);
  }

  Future<void> _continue() async {
    final reader = widget.reader, models = reader.models;
    if (_working || models.busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await reader.stop();
      if (!mounted) return;
      if (_step == 0) {
        _go(1);
      } else if (_step == 1) {
        await reader.setPlaybackLanguages(source: _source, target: _target);
        if (!mounted) return;
        _useFrenchPack = _target == ReaderLanguage.french;
        if (_source == ReaderLanguage.english &&
            _target == ReaderLanguage.french &&
            !models.translationInstalled) {
          _downloadTranslation = true;
        } else if (_source != ReaderLanguage.english ||
            _target != ReaderLanguage.french) {
          _downloadTranslation = false;
        }
        _automaticDownloadsStarted = false;
        _go(2);
        unawaited(_downloadSelectedPacks());
      } else {
        final ready = await _downloadSelectedPacks(retry: true);
        if (!mounted || !ready) return;
        await reader.setEngine(
          _useFrenchPack ? VoiceEngine.neural : VoiceEngine.system,
        );
        if (mounted) reader.completeOnboarding();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible de terminer. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _downloadSelectedPacks({bool retry = false}) async {
    final models = widget.reader.models;
    if (_step != 2 || models.busy) return false;
    if (_automaticDownloadsStarted && !retry) {
      return models.translationInstalled ||
          !(_source == ReaderLanguage.english &&
              _target == ReaderLanguage.french);
    }
    _automaticDownloadsStarted = true;

    var complete = true;
    Future<void> install(
      String pack,
      Future<void> Function() action,
      bool Function() installed,
      String failure,
    ) async {
      if (installed()) return;
      if (mounted) setState(() => _downloadingPack = pack);
      await action();
      if (!installed()) {
        complete = false;
        if (mounted) {
          setState(
            () =>
                _error =
                    models.cancelled
                        ? 'Téléchargement annulé. Touchez pour réessayer.'
                        : failure,
          );
        }
      }
    }

    try {
      if (_source == ReaderLanguage.english &&
          _target == ReaderLanguage.french &&
          _downloadTranslation) {
        await install(
          'translation',
          models.installTranslationEnFr,
          () => models.translationInstalled,
          'La traduction n’a pas pu être téléchargée. Touchez pour réessayer.',
        );
      }
      if (_useFrenchPack) {
        await install(
          'voices',
          models.installNeural,
          () => models.neuralInstalled,
          'Les voix françaises n’ont pas pu être téléchargées. Touchez pour réessayer.',
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingPack = null);
    }
    return complete;
  }

  String _actionLabel(BuildContext context) {
    if (_step == 0) return 'Commencer mon voyage'.tr(context);
    if (_step == 1) {
      return 'Choisir mes téléchargements'.tr(context);
    }
    if (_working) return 'Préparation en cours…'.tr(context);
    if (widget.reader.models.busy || _downloadingPack != null) {
      return 'Téléchargement en cours…'.tr(context);
    }
    final needsDownload =
        (_useFrenchPack && !widget.reader.models.neuralInstalled) ||
        (_downloadTranslation && !widget.reader.models.translationInstalled);
    if (needsDownload) {
      return _error == null
          ? 'Télécharger et commencer'.tr(context)
          : 'Réessayer le téléchargement'.tr(context);
    }
    return 'Ouvrir ma bibliothèque'.tr(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.reader, widget.reader.models]),
    builder: (context, _) {
      final p = PaperColors.of(context);
      final busy = _working || widget.reader.models.busy;
      return AdaptiveScaffold(
        body: ColoredBox(
          color: p.paper,
          child: SafeArea(
            top: true,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_step > 0)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconAction(
                                  label: 'Retour'.tr(context),
                                  icon: Icons.arrow_back_rounded,
                                  onPressed: busy ? null : _back,
                                ),
                              ),
                            Semantics(
                              label:
                                  AppCopy.of(context).english
                                      ? 'Step ${_step + 1} of 3'
                                      : 'Étape ${_step + 1} sur 3',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  3,
                                  (i) => AnimatedContainer(
                                    duration: Duration(
                                      milliseconds: _reduceMotion ? 0 : 250,
                                    ),
                                    width: i == _step ? 28 : 8,
                                    height: 4,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: i <= _step ? p.accent : p.line,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _InterfaceLanguageMenu(
                                reader: widget.reader,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              controller: _scroll,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        _step == 0
                                            ? MainAxisAlignment.center
                                            : MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: Duration(
                                          milliseconds: _reduceMotion ? 0 : 320,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        transitionBuilder:
                                            (child, animation) =>
                                                FadeTransition(
                                                  opacity: animation,
                                                  child: SlideTransition(
                                                    position: Tween(
                                                      begin: const Offset(
                                                        0,
                                                        .025,
                                                      ),
                                                      end: Offset.zero,
                                                    ).animate(animation),
                                                    child: child,
                                                  ),
                                                ),
                                        child: KeyedSubtree(
                                          key: ValueKey(_step),
                                          child: switch (_step) {
                                            0 => _welcome(context),
                                            1 => _languages(context),
                                            _ => _voices(context),
                                          },
                                        ),
                                      ),
                                      if (_error != null) ...[
                                        const SizedBox(height: 16),
                                        Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            _error!.tr(context),
                                            style: TextStyle(
                                              color: p.warning,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ContinueButton(
                        label: _actionLabel(context),
                        onPressed: busy ? null : _continue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _welcome(BuildContext context) {
    final p = PaperColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingBookScene(animation: _motion),
        const SizedBox(height: 12),
        Text(
          'Le plaisir de lire.\nLa liberté d’écouter.'.tr(context),
          textAlign: TextAlign.center,
          style: LisiereTheme.editorial(context, size: 36),
        ),
        const SizedBox(height: 14),
        Text(
          'Vos livres vous suivent.\nMême quand vos yeux font une pause.'.tr(
            context,
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            _Feature(icon: Icons.menu_book_rounded, label: 'Lire'.tr(context)),
            _Feature(
              icon: Icons.headphones_rounded,
              label: 'Écouter'.tr(context),
            ),
            _Feature(
              icon: Icons.translate_rounded,
              label: 'Traduire'.tr(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _languages(BuildContext context) {
    final p = PaperColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingLandscapeBanner(
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LanguageMedallion(
                  code: _source.code,
                  icon: Icons.menu_book_rounded,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: SizedBox(
                    width: 26,
                    child: Divider(color: Color(0xFFEEE9D9), thickness: 1),
                  ),
                ),
                _LanguageMedallion(
                  code: _target.code,
                  icon: Icons.headphones_rounded,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Dans votre langue.'.tr(context),
          style: LisiereTheme.editorial(context, size: 34),
        ),
        const SizedBox(height: 10),
        Text(
          'Un livre à lire. Une voix à retrouver.'.tr(context),
          style: TextStyle(fontSize: 15, color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 26),
        _LanguagePicker(
          label: 'La langue de vos livres'.tr(context),
          value: _source,
          onChanged: (value) => setState(() => _source = value),
        ),
        const SizedBox(height: 22),
        _LanguagePicker(
          label: 'La langue de votre écoute'.tr(context),
          value: _target,
          onChanged: (value) => setState(() => _target = value),
        ),
        const SizedBox(height: 20),
        Text(
          _source == _target
              ? 'Vous pourrez ajuster ces choix pour chaque livre.'.tr(context)
              : _source == ReaderLanguage.english
              ? 'Le pack de traduction pourra être téléchargé à l’étape suivante.'
                  .tr(context)
              : 'La lecture en anglais d’un livre français n’est pas encore disponible.'
                  .tr(context),
          style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
        ),
      ],
    );
  }

  Widget _voices(BuildContext context) {
    final p = PaperColors.of(context), models = widget.reader.models;
    final french = _target == ReaderLanguage.french;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingLandscapeBanner(
          height: 108,
          child: ExcludeSemantics(
            child: Row(
              children: [
                const Icon(
                  Icons.headphones_rounded,
                  size: 36,
                  color: Color(0xFFF6EBD1),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Une voix.\nTout un univers.'.tr(context),
                      style: TextStyle(
                        fontFamily: LisiereTheme.serif,
                        fontSize: 22,
                        height: 1.25,
                        color: Color(0xFFF6EBD1),
                      ),
                    ),
                  ),
                ),
                if (MediaQuery.textScalerOf(context).scale(1) < 1.3)
                  OnboardingWaveform(
                    animation: _motion,
                    color: const Color(0xFFF6EBD1),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Trouvez votre voix.'.tr(context),
          style: LisiereTheme.editorial(context, size: 32),
        ),
        const SizedBox(height: 8),
        Text(
          'L’écoute, à votre façon.'.tr(context),
          style: TextStyle(fontSize: 15, color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        if (!french)
          _VoiceChoice(
            key: const ValueKey('system-voice'),
            title: 'Voix anglaise du téléphone'.tr(context),
            subtitle: 'Utilise la voix intégrée à votre iPhone'.tr(context),
            icon: Icons.phone_iphone_rounded,
            selected: true,
            onTap: null,
          ),
        if (french) ...[
          _VoiceChoice(
            key: const ValueKey('french-voices'),
            title: 'Voix françaises'.tr(context),
            subtitle: '10 voix disponibles'.tr(context),
            icon: Icons.graphic_eq_rounded,
            detail:
                models.neuralInstalled
                    ? 'Prêtes à écouter'.tr(context)
                    : _downloadingPack == 'voices'
                    ? models.status
                    : 'Téléchargement inclus dans votre configuration'.tr(
                      context,
                    ),
            selected: true,
            installing: _downloadingPack == 'voices',
            progress: _downloadingPack == 'voices' ? models.progress : null,
            onTap: null,
          ),
        ],
        if (_source == ReaderLanguage.english &&
            _target == ReaderLanguage.french) ...[
          const SizedBox(height: 12),
          _VoiceChoice(
            key: const ValueKey('translation-en-fr'),
            title: 'Traduction anglais → français'.tr(context),
            subtitle: 'Lire et écouter vos livres anglais en français'.tr(
              context,
            ),
            icon: Icons.translate_rounded,
            detail:
                models.translationInstalled
                    ? 'Déjà téléchargée'.tr(context)
                    : _downloadingPack == 'translation'
                    ? models.status
                    : 'Téléchargement inclus dans votre configuration'.tr(
                      context,
                    ),
            selected: true,
            exclusive: false,
            installing: _downloadingPack == 'translation',
            progress:
                _downloadingPack == 'translation' ? models.progress : null,
            onTap: null,
          ),
        ],
        if (models.busy) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: AdaptiveButton(
              label:
                  models.cancelled
                      ? 'Annulation…'.tr(context)
                      : 'Annuler le téléchargement'.tr(context),
              onPressed:
                  models.cancelled
                      ? null
                      : () {
                        models.cancel();
                        setState(() {});
                      },
              enabled: !models.cancelled,
              style: AdaptiveButtonStyle.plain,
              color: p.paper,
              textColor: p.muted,
              minSize: const Size(48, 38),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: AdaptiveButton(
        onPressed: onPressed,
        label: label,
        enabled: onPressed != null,
        color: p.accent,
        textColor: p.onAccent,
        minSize: const Size(48, 58),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _InterfaceLanguageMenu extends StatelessWidget {
  const _InterfaceLanguageMenu({required this.reader});

  final ReaderController reader;

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.of(context);
    return PopupMenuButton<AppLanguage>(
      tooltip: 'Langue de l’app'.tr(context),
      onSelected: reader.setAppLanguage,
      itemBuilder:
          (context) =>
              AppLanguage.values
                  .map(
                    (language) => PopupMenuItem(
                      value: language,
                      child: Row(
                        children: [
                          Icon(
                            reader.settings.appLanguage == language
                                ? Icons.check_rounded
                                : Icons.language_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(copy.interfaceLanguage(language)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
      child: Semantics(
        button: true,
        label: 'Langue de l’app'.tr(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded, size: 18),
              const SizedBox(width: 4),
              Text(
                copy.interfaceLanguage(reader.settings.appLanguage),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: PaperColors.of(context).muted),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: PaperColors.of(context).muted),
        ),
      ),
    ],
  );
}

class _LanguageMedallion extends StatelessWidget {
  const _LanguageMedallion({required this.code, required this.icon});
  final String code;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 22, color: const Color(0xFFE4DCC4)),
      const SizedBox(height: 8),
      Text(
        code.toUpperCase(),
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontFamily: LisiereTheme.serif,
          fontSize: 38,
          height: 1,
          color: Color(0xFFF6EBD1),
        ),
      ),
    ],
  );
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final ReaderLanguage value;
  final ValueChanged<ReaderLanguage> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Row(
          children:
              ReaderLanguage.values.map((language) {
                final selected = value == language;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: language == ReaderLanguage.french ? 10 : 0,
                    ),
                    child: Semantics(
                      selected: selected,
                      inMutuallyExclusiveGroup: true,
                      child: AdaptiveButton.child(
                        onPressed: () => onChanged(language),
                        enabled: true,
                        style: AdaptiveButtonStyle.bordered,
                        color: selected ? p.accent : p.surface,
                        minSize: const Size(48, 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 16,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (selected) ...[
                              Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: p.onAccent,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                language.localized(context),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: selected ? p.onAccent : p.muted,
                                  fontWeight:
                                      selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _VoiceChoice extends StatelessWidget {
  const _VoiceChoice({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.detail,
    this.exclusive = true,
    this.installing = false,
    this.progress,
  });
  final String title, subtitle;
  final String? detail;
  final IconData icon;
  final bool selected;
  final bool exclusive;
  final bool installing;
  final double? progress;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: exclusive,
      child: Material(
        color: selected ? p.inset : p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? p.accent : p.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: p.accent, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: p.muted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          detail!,
                          style: TextStyle(
                            fontSize: 11,
                            color: p.muted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                      if (installing) ...[
                        const SizedBox(height: 10),
                        Semantics(
                          label: 'Téléchargement en cours'.tr(context),
                          value:
                              progress == null
                                  ? 'Préparation'.tr(context)
                                  : '${(progress! * 100).round()} %',
                          child: LinearProgressIndicator(
                            value: progress == 0 ? null : progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  installing
                      ? Icons.downloading_rounded
                      : selected
                      ? Icons.check_circle_rounded
                      : exclusive
                      ? Icons.radio_button_unchecked_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: selected || installing ? p.accent : p.line,
                  size: 23,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
