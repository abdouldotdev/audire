import 'dart:async';
import 'dart:ui' as ui;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import '../audio/audio_preparation.dart';
import '../audio/speech_engine.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import '../domain/narration.dart';
import 'design_system.dart';
import 'voices_page.dart';

class PlayerStrip extends StatelessWidget {
  const PlayerStrip({super.key, required this.reader, this.onOpen});
  final ReaderController reader;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    if (!reader.hasSession) return const SizedBox.shrink();
    final p = PaperColors.of(context), book = reader.book;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 7),
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.dark ? .22 : .08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            if (book != null && !reader.previewing)
              BookCover(book: book, width: 36, height: 48)
            else
              Icon(Icons.graphic_eq, color: p.accent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Semantics(
                  button: onOpen != null,
                  label: 'Ouvrir le lecteur',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reader.previewing ? 'Aperçu de la voix' : book!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        reader.phase == SpeechPhase.preparing
                            ? 'Préparation locale…'
                            : reader.previewing
                            ? reader.voiceLabel
                            : reader.chapter!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconAction(
              label: reader.active ? 'Mettre en pause' : 'Lire',
              icon:
                  reader.active
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
              prominent: true,
              onPressed:
                  () =>
                      reader.previewing
                          ? reader.toggle()
                          : playWithLanguageChoice(context, reader),
            ),
            if (reader.previewing) ...[
              const SizedBox(width: 6),
              IconAction(
                label: 'Arrêter l’aperçu',
                icon: Icons.close,
                onPressed: reader.stop,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FloatingReaderPlayer extends StatefulWidget {
  const FloatingReaderPlayer({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<FloatingReaderPlayer> createState() => _FloatingReaderPlayerState();
}

class _FloatingReaderPlayerState extends State<FloatingReaderPlayer> {
  bool _expanded = false;
  Timer? _collapse;
  void _scheduleCollapse() {
    _collapse?.cancel();
    if (!_expanded || MediaQuery.accessibleNavigationOf(context)) return;
    _collapse = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _expand() {
    setState(() => _expanded = true);
    _scheduleCollapse();
  }

  @override
  void dispose() {
    _collapse?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context), reader = widget.reader;
    return Align(
      alignment: Alignment.bottomRight,
      child: Listener(
        onPointerDown: (_) => _collapse?.cancel(),
        onPointerUp: (_) => _scheduleCollapse(),
        onPointerCancel: (_) => _scheduleCollapse(),
        child: AnimatedSize(
          alignment: Alignment.bottomRight,
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 260,
          ),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_expanded ? 28 : 32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_expanded ? 28 : 32),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        p.surface.withValues(alpha: .82),
                        p.surface.withValues(alpha: .62),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(_expanded ? 28 : 32),
                    border: Border.all(color: p.ink.withValues(alpha: .2)),
                  ),
                  child:
                      _expanded
                          ? ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 420,
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * .65,
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      tooltip: 'Réduire le lecteur',
                                      icon: const Icon(
                                        Icons.expand_more_rounded,
                                      ),
                                      onPressed: () {
                                        _collapse?.cancel();
                                        setState(() => _expanded = false);
                                      },
                                    ),
                                  ),
                                  ReaderPlayer(reader: reader, glass: true),
                                ],
                              ),
                            ),
                          )
                          : SizedBox(
                            width: 64,
                            height: 64,
                            child: IconButton(
                              tooltip: 'Afficher les commandes de lecture',
                              onPressed: _expand,
                              iconSize: 28,
                              color: p.accent,
                              icon: Icon(
                                reader.phase == SpeechPhase.preparing
                                    ? Icons.hourglass_top_rounded
                                    : reader.active
                                    ? Icons.graphic_eq_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReaderPlayer extends StatelessWidget {
  const ReaderPlayer({super.key, required this.reader, this.glass = false});
  final ReaderController reader;
  final bool glass;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    final remaining =
        reader.segments.isEmpty
            ? 0
            : reader.segments.length - reader.segmentIndex;
    return Container(
      decoration: BoxDecoration(
        color: glass ? Colors.transparent : p.surface,
        border: glass ? null : Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        bottom: !glass,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, glass ? 0 : 12, 16, glass ? 16 : 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reader.activeTranslation != null) ...[
                _SpokenTranslation(reader: reader),
                const SizedBox(height: 14),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:
                      reader.phase == SpeechPhase.completed
                          ? 1
                          : reader.chapterProgress,
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reader.phase == SpeechPhase.preparing
                          ? reader.bufferedPassages > 0
                              ? '${reader.bufferedPassages} passages prêts…'
                              : 'Préparation de la lecture…'
                          : reader.phase == SpeechPhase.completed
                          ? 'Lecture terminée'
                          : '$remaining passages restants',
                      style: TextStyle(fontSize: 11, color: p.muted),
                    ),
                  ),
                  Text(
                    'Ch. ${reader.chapterIndex + 1} / ${reader.book?.chapters.length ?? 0}',
                    style: TextStyle(fontSize: 11, color: p.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Semantics(
                    label: 'Vitesse de lecture',
                    child: GestureDetector(
                      onTap: () {
                        final rates = [.8, 1.0, 1.2, 1.5];
                        final next = rates.firstWhere(
                          (v) => v > reader.settings.speed + .01,
                          orElse: () => rates.first,
                        );
                        reader.setSpeed(next);
                      },
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${reader.settings.speed.toStringAsFixed(1)}×',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconAction(
                    label: 'Passage précédent',
                    icon: Icons.skip_previous_rounded,
                    onPressed: reader.previous,
                  ),
                  IconAction(
                    label: reader.active ? 'Mettre en pause' : 'Lire',
                    prominent: true,
                    large: true,
                    icon:
                        reader.active
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                    onPressed: () => playWithLanguageChoice(context, reader),
                  ),
                  IconAction(
                    label: 'Passage suivant',
                    icon: Icons.skip_next_rounded,
                    onPressed: reader.next,
                  ),
                  IconAction(
                    label: 'Réglages audio',
                    icon: Icons.tune_rounded,
                    onPressed:
                        () => openPage<void>(
                          context,
                          ReaderAudioSettingsPage(reader: reader),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                reader.bufferedPassages > 0 &&
                        reader.phase == SpeechPhase.playing
                    ? '${reader.syncLabel} · ${reader.bufferedPassages} passages prêts'
                    : reader.syncLabel,
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderAudioSettingsPage extends StatelessWidget {
  const ReaderAudioSettingsPage({super.key, required this.reader});
  final ReaderController reader;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return DefaultTabController(
      length: 2,
      child: AdaptiveScaffold(
        appBar: const AdaptiveAppBar(title: 'Réglages audio'),
        body: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: p.inset,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: p.dark ? .2 : .07,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    labelColor: p.ink,
                    unselectedLabelColor: p.muted,
                    tabs: const [Tab(text: 'Préparer'), Tab(text: 'Audio')],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _AudioPreparationTab(reader: reader),
                    VoicesPage(reader: reader, showSourceLanguage: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioPreparationTab extends StatefulWidget {
  const _AudioPreparationTab({required this.reader});
  final ReaderController reader;

  @override
  State<_AudioPreparationTab> createState() => _AudioPreparationTabState();
}

class _AudioPreparationTabState extends State<_AudioPreparationTab> {
  AudioPreparationEstimate? _chapterEstimate, _bookEstimate;
  bool _estimating = true;

  @override
  void initState() {
    super.initState();
    _refreshEstimates();
  }

  Future<void> _refreshEstimates() async {
    final results = await Future.wait([
      widget.reader.estimateAudioPreparation(AudioPreparationScope.chapter),
      widget.reader.estimateAudioPreparation(AudioPreparationScope.book),
    ]);
    if (!mounted) return;
    setState(() {
      _chapterEstimate = results[0];
      _bookEstimate = results[1];
      _estimating = false;
    });
  }

  Future<void> _prepare(AudioPreparationScope scope) async {
    await widget.reader.prepareAudio(scope);
    await _refreshEstimates();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.reader,
    builder: (context, _) {
      final reader = widget.reader;
      final p = PaperColors.of(context);
      final progress = reader.audioPreparation;
      final preparing = progress?.state == AudioPreparationState.preparing;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          const PageIntro(
            kicker: 'Hors ligne',
            title: 'Préparez votre écoute',
            subtitle:
                'Générez l’audio maintenant pour lire ensuite sans pause.',
          ),
          const SizedBox(height: 20),
          if (reader.activeEngine == VoiceEngine.system)
            const Notice(
              'Choisissez une voix téléchargée dans l’onglet Audio pour préparer la lecture.',
            ),
          _PreparationChoice(
            icon: Icons.menu_book_rounded,
            title: 'Ce chapitre',
            subtitle: _estimateLabel(_chapterEstimate, loading: _estimating),
            active:
                preparing &&
                progress!.request.scope == AudioPreparationScope.chapter,
            enabled: !preparing && reader.activeEngine != VoiceEngine.system,
            onPressed: () => _prepare(AudioPreparationScope.chapter),
          ),
          const SizedBox(height: 12),
          _PreparationChoice(
            icon: Icons.library_books_rounded,
            title: 'Tout le livre',
            subtitle: _estimateLabel(_bookEstimate, loading: _estimating),
            active:
                preparing &&
                progress!.request.scope == AudioPreparationScope.book,
            enabled: !preparing && reader.activeEngine != VoiceEngine.system,
            onPressed: () => _prepare(AudioPreparationScope.book),
          ),
          if (progress != null) ...[
            const SizedBox(height: 20),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _progressTitle(progress),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${((progress.fraction ?? 0) * 100).round()} %',
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: progress.fraction),
                  const SizedBox(height: 10),
                  Text(
                    '${progress.completedPassages} / ${progress.request.expectedPassages ?? '—'} passages · ${_formatBytes(progress.bytes)}',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  if (preparing) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: AdaptiveButton(
                        label: 'Arrêter',
                        onPressed: reader.cancelAudioPreparation,
                        color: p.inset,
                        textColor: p.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _PreparationChoice extends StatelessWidget {
  const _PreparationChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });
  final IconData icon;
  final String title, subtitle;
  final bool active, enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Material(
      color: active ? p.readingHighlight : p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                active ? Icons.downloading_rounded : icon,
                color: active ? p.onReadingHighlight : p.accent,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Préparation en cours' : title,
                      style: TextStyle(
                        color: active ? p.onReadingHighlight : p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            active
                                ? p.onReadingHighlight.withValues(alpha: .8)
                                : p.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _estimateLabel(
  AudioPreparationEstimate? estimate, {
  required bool loading,
}) {
  if (loading || estimate == null) return 'Calcul de la taille…';
  final ready = estimate.cachedPassages;
  final suffix = ready > 0 ? ' · $ready déjà prêts' : '';
  return '${estimate.passages} passages · ≈ ${_formatBytes(estimate.estimatedDownloadBytes)}$suffix';
}

String _progressTitle(AudioPreparationProgress progress) => switch (progress
    .state) {
  AudioPreparationState.preparing => 'Création de l’audio',
  AudioPreparationState.completed => 'Audio prêt',
  AudioPreparationState.cancelled => 'Préparation arrêtée',
  AudioPreparationState.failed => 'Préparation incomplète',
};

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} Kio';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} Mio';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Gio';
}

class _SpokenTranslation extends StatelessWidget {
  const _SpokenTranslation({required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SpeechEvent>(
    valueListenable: reader.readingTick,
    builder: (context, event, _) {
      final p = PaperColors.of(context), text = reader.activeTranslation ?? '';
      final spoken = event.spokenRange;
      final range =
          spoken == null
              ? null
              : FrenchNarration.normalize(
                text,
              ).displayRange(spoken.start, spoken.end);
      final start = range?.start.clamp(0, text.length) ?? 0;
      final end = range?.end.clamp(start, text.length) ?? 0;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.substring(0, start)),
            TextSpan(
              text: text.substring(start, end),
              style: TextStyle(
                backgroundColor: p.readingHighlight,
                color: p.onReadingHighlight,
              ),
            ),
            TextSpan(text: text.substring(end)),
          ],
        ),
        style: TextStyle(color: p.ink, fontSize: 16, height: 1.45),
      );
    },
  );
}

class _PlaybackLanguageChoice {
  const _PlaybackLanguageChoice(this.source, this.target);
  final ReaderLanguage source, target;
}

Future<void> playWithLanguageChoice(
  BuildContext context,
  ReaderController reader,
) async {
  if (reader.active || reader.previewing || !reader.needsLanguageChoice) {
    await reader.toggle();
    return;
  }
  final choice = await _askPlaybackLanguages(context, reader);
  if (choice == null) return;
  await reader.setPlaybackLanguages(
    source: choice.source,
    target: choice.target,
  );
  await reader.play();
}

Future<_PlaybackLanguageChoice?> _askPlaybackLanguages(
  BuildContext context,
  ReaderController reader,
) {
  final p = PaperColors.of(context);
  var source = reader.suggestedSourceLanguage;
  var target = reader.settings.targetLanguage;
  var checking = false;
  String? blocker;
  return showAdaptiveDialog<_PlaybackLanguageChoice>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog.adaptive(
                title: Text(
                  'Langues audio',
                  style: LisiereTheme.editorial(context, size: 26),
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LanguageSelector(
                          label: 'Source du livre',
                          value: source,
                          onChanged:
                              (v) => setState(() {
                                source = v;
                                blocker = null;
                              }),
                        ),
                        const SizedBox(height: 16),
                        _LanguageSelector(
                          label: 'Voix cible',
                          value: target,
                          onChanged:
                              (v) => setState(() {
                                target = v;
                                blocker = null;
                              }),
                        ),
                        if (blocker != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            blocker!,
                            style: TextStyle(
                              color: p.warning,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        checking ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed:
                        checking
                            ? null
                            : () async {
                              setState(() {
                                checking = true;
                                blocker = null;
                              });
                              final message = await reader.playbackBlocker(
                                source: source,
                                target: target,
                              );
                              if (!context.mounted) return;
                              if (message != null) {
                                setState(() {
                                  checking = false;
                                  blocker = message;
                                });
                                return;
                              }
                              Navigator.of(
                                context,
                              ).pop(_PlaybackLanguageChoice(source, target));
                            },
                    child: Text(checking ? 'Vérification…' : 'Continuer'),
                  ),
                ],
              ),
        ),
  );
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final language in ReaderLanguage.values) ...[
              ChoiceChip(
                label: Text(language.label),
                selected: value == language,
                onSelected: (_) => onChanged(language),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
