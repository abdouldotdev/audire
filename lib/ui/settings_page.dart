import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import '../audio/audio_preparation.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';
import 'reader_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.reader});
  final ReaderController reader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin<SettingsPage> {
  AudioPreparationEstimate? _chapterEstimate, _bookEstimate;
  String? _estimateBookId;
  bool _estimating = false;

  @override
  void initState() {
    super.initState();
    widget.reader.models.addListener(_modelsChanged);
  }

  void _modelsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEstimates() async {
    final id = widget.reader.book?.id;
    if (id == null || _estimating) return;
    _estimating = true;
    final chapter = await widget.reader.estimateAudioPreparation(
      AudioPreparationScope.chapter,
    );
    final book = await widget.reader.estimateAudioPreparation(
      AudioPreparationScope.book,
    );
    if (!mounted) return;
    setState(() {
      _estimateBookId = id;
      _chapterEstimate = chapter;
      _bookEstimate = book;
      _estimating = false;
    });
  }

  @override
  void dispose() {
    widget.reader.models.removeListener(_modelsChanged);
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reader = widget.reader;
    final p = PaperColors.of(context);
    if (reader.book?.id != _estimateBookId && !_estimating) {
      unawaited(_loadEstimates());
    }
    return SafeArea(
      top: true,
      bottom: false,
      child: ListView(
        key: const PageStorageKey<String>('settings-tab-scroll'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        children: [
          const PageIntro(kicker: 'Profil', title: 'Préférences'),
          const SectionLabel('Lecture'),
          AdaptiveSegmentedControl(
            labels: const ['Claire', 'Sombre', 'Système'],
            selectedIndex: reader.settings.theme.index,
            onValueChanged: (i) => reader.setTheme(PaperTheme.values[i]),
          ),
          const SizedBox(height: 18),
          AdaptiveButton(
            label: 'Typographie et vitesse',
            color: p.inset,
            textColor: p.ink,
            onPressed:
                () => openPage<void>(
                  context,
                  ReadingAppearancePage(reader: reader),
                ),
          ),
          const SectionLabel('Langues'),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Langue source', style: TextStyle(color: p.muted)),
                const SizedBox(height: 10),
                AdaptiveSegmentedControl(
                  labels: ReaderLanguage.values.map((l) => l.label).toList(),
                  selectedIndex: reader.settings.sourceLanguage.index,
                  onValueChanged:
                      (i) => reader.setPlaybackLanguages(
                        source: ReaderLanguage.values[i],
                        target: reader.settings.targetLanguage,
                      ),
                ),
                const SizedBox(height: 14),
                Text('Langue de la voix', style: TextStyle(color: p.muted)),
                const SizedBox(height: 10),
                AdaptiveSegmentedControl(
                  labels: ReaderLanguage.values.map((l) => l.label).toList(),
                  selectedIndex: reader.settings.targetLanguage.index,
                  onValueChanged:
                      (i) => reader.setPlaybackLanguages(
                        source: reader.settings.sourceLanguage,
                        target: ReaderLanguage.values[i],
                      ),
                ),
                if (reader.settings.sourceLanguage == ReaderLanguage.english &&
                    reader.settings.targetLanguage == ReaderLanguage.french)
                  SettingSwitch(
                    title: 'Afficher le bilingue',
                    subtitle:
                        'Garder le texte anglais visible et afficher la traduction française du passage actif.',
                    value:
                        reader.settings.translationMode ==
                        TranslationMode.bilingual,
                    onChanged:
                        (v) => reader.setTranslationMode(
                          v
                              ? TranslationMode.bilingual
                              : TranslationMode.frenchAudio,
                        ),
                  ),
              ],
            ),
          ),
          const SectionLabel('Packs locaux'),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModelPackRow(
                  title: 'Supertonic 3',
                  subtitle:
                      reader.models.neuralInstalled
                          ? '10 voix françaises et anglaises · installé'
                          : '10 voix françaises et anglaises · environ 415 Mio',
                  installed: reader.models.neuralInstalled,
                  busy: reader.models.busy,
                  onPressed: () => _downloadNeural(reader),
                  onDelete:
                      reader.models.neuralInstalled
                          ? () {
                            _confirm(
                              context,
                              'Supprimer Supertonic',
                              'Supprimer le pack Supertonic 3 téléchargé ?',
                              () => _deleteNeural(reader),
                            );
                          }
                          : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: p.line),
                ),
                _ModelPackRow(
                  title: 'Kokoro 82M',
                  subtitle:
                      reader.models.kokoroInstalled
                          ? '6 voix anglaises · installé'
                          : 'Voix anglaises très naturelles · environ 96 Mio',
                  installed: reader.models.kokoroInstalled,
                  busy: reader.models.busy,
                  onPressed: () => _downloadKokoro(reader),
                  onDelete:
                      reader.models.kokoroInstalled
                          ? () {
                            _confirm(
                              context,
                              'Supprimer Kokoro',
                              'Supprimer le pack Kokoro 82M téléchargé ?',
                              () => _deleteKokoro(reader),
                            );
                          }
                          : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: p.line),
                ),
                _ModelPackRow(
                  title: 'Qwen 0.6B',
                  subtitle:
                      reader.models.qwenDownloadedFor('compact')
                          ? '9 voix françaises et anglaises · téléchargé'
                          : reader.models.qwenPackSupported('compact')
                          ? 'Voix premium · environ 1,7 Go'
                          : 'Indisponible sur cet appareil',
                  installed: reader.models.qwenDownloadedFor('compact'),
                  busy: reader.models.busy,
                  onPressed:
                      reader.models.qwenPackSupported('compact')
                          ? () => _downloadQwen(reader, 'compact')
                          : null,
                  onDelete:
                      reader.models.qwenDownloadedFor('compact')
                          ? () {
                            _confirm(
                              context,
                              'Supprimer Qwen compact',
                              'Supprimer le modèle Qwen 0.6B téléchargé ?',
                              () => _deleteQwen(reader, 'compact'),
                            );
                          }
                          : null,
                ),
                if (reader.models.qwenPackSupported('quality')) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1, color: p.line),
                  ),
                  _ModelPackRow(
                    title: 'Qwen Qualité',
                    subtitle:
                        reader.models.qwenDownloadedFor('quality')
                            ? 'Modèle 0.6B complet · téléchargé'
                            : reader.models.qwenPackSupported('quality')
                            ? '0.6B 8-bit · environ 2,0 Go'
                            : 'Indisponible sur cet appareil',
                    installed: reader.models.qwenDownloadedFor('quality'),
                    busy: reader.models.busy,
                    onPressed:
                        reader.models.qwenPackSupported('quality')
                            ? () => _downloadQwen(reader, 'quality')
                            : null,
                    onDelete:
                        reader.models.qwenDownloadedFor('quality')
                            ? () {
                              _confirm(
                                context,
                                'Supprimer Qwen Qualité',
                                'Supprimer le modèle Qwen Qualité 8-bit téléchargé ?',
                                () => _deleteQwen(reader, 'quality'),
                              );
                            }
                            : null,
                  ),
                ],
                if (reader.models.qwenPackSupported('max')) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1, color: p.line),
                  ),
                  _ModelPackRow(
                    title: 'Qwen Max 1.7B',
                    subtitle:
                        reader.models.qwenDownloadedFor('max')
                            ? 'Meilleur rendu local · téléchargé'
                            : reader.models.qwenPackSupported('max')
                            ? 'Plus riche et plus lent · environ 2,3 Go'
                            : 'Indisponible sur cet appareil',
                    installed: reader.models.qwenDownloadedFor('max'),
                    busy: reader.models.busy,
                    onPressed:
                        reader.models.qwenPackSupported('max')
                            ? () => _downloadQwen(reader, 'max')
                            : null,
                    onDelete:
                        reader.models.qwenDownloadedFor('max')
                            ? () {
                              _confirm(
                                context,
                                'Supprimer Qwen Max',
                                'Supprimer le modèle Qwen Max téléchargé ?',
                                () => _deleteQwen(reader, 'max'),
                              );
                            }
                            : null,
                  ),
                ],
                if (!reader.models.qwenPackSupported('quality') ||
                    !reader.models.qwenPackSupported('max'))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Notice(
                      [
                        if (!reader.models.qwenPackSupported('quality'))
                          reader.models.qwenPackUnavailableReason('quality'),
                        if (!reader.models.qwenPackSupported('max'))
                          reader.models.qwenPackUnavailableReason('max'),
                      ].join('\n'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: p.line),
                ),
                _ModelPackRow(
                  title: 'Traduction anglais → français',
                  subtitle:
                      reader.models.translationInstalled
                          ? 'Pack téléchargé sur cet appareil'
                          : 'Pour lire et écouter vos livres anglais en français',
                  installed: reader.models.translationInstalled,
                  busy: reader.models.busy,
                  onPressed: () => _downloadTranslation(reader),
                  onDelete:
                      reader.models.translationInstalled
                          ? () {
                            _confirm(
                              context,
                              'Supprimer traduction',
                              'Supprimer le pack traduction EN→FR téléchargé ?',
                              () => _deleteTranslation(reader),
                            );
                          }
                          : null,
                ),
                if (reader.models.busy) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value:
                        reader.models.total > 0 ? reader.models.progress : null,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          reader.models.total > 0
                              ? '${(reader.models.progress * 100).round()} %'
                              : 'Préparation…',
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                      ),
                      AdaptiveButton(
                        label:
                            reader.models.cancelled ? 'Annulation…' : 'Annuler',
                        style: AdaptiveButtonStyle.plain,
                        color: p.surface,
                        textColor: p.accent,
                        minSize: const Size(48, 44),
                        enabled: !reader.models.cancelled,
                        onPressed:
                            reader.models.cancelled
                                ? null
                                : reader.models.cancel,
                      ),
                    ],
                  ),
                ],
                if (reader.models.error != null && !reader.models.busy) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Le téléchargement n’a pas abouti. Vérifiez votre connexion et réessayez.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: p.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('Contenu'),
          SurfacePanel(
            child: Column(
              children: [
                SettingSwitch(
                  title: 'Lire les titres',
                  subtitle: 'Inclure les titres dans la narration.',
                  value: reader.settings.readHeadings,
                  onChanged: (v) => reader.setContent(headings: v),
                ),
                Divider(color: p.line),
                SettingSwitch(
                  title: 'Lire les notes',
                  subtitle: 'Inclure les notes identifiées.',
                  value: reader.settings.readNotes,
                  onChanged: (v) => reader.setContent(notes: v),
                ),
              ],
            ),
          ),
          if (reader.book != null) ...[
            const SectionLabel('Audio du livre'),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    reader.book!.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    reader.activeBookCache == null
                        ? 'Aucun passage préparé'
                        : '${reader.activeBookCache!.passages} passages · ${_fileSize(reader.activeBookCache!.bytes)}',
                    style: TextStyle(color: p.muted),
                  ),
                  if (reader.audioPreparation case final progress?) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      progress.state == AudioPreparationState.preparing
                          ? '${progress.completedPassages}/${progress.request.expectedPassages ?? '…'} passages · ${_fileSize(progress.estimatedBytes ?? progress.bytes)} estimés'
                          : progress.state == AudioPreparationState.completed
                          ? 'Préparation terminée · ${_fileSize(progress.bytes)}'
                          : progress.state == AudioPreparationState.cancelled
                          ? 'Préparation interrompue'
                          : 'Préparation incomplète',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AdaptiveButton(
                    label:
                        'Préparer ce chapitre · ${_estimateLabel(_chapterEstimate)}',
                    color: p.inset,
                    textColor: p.ink,
                    enabled:
                        reader.audioPreparation?.state !=
                        AudioPreparationState.preparing,
                    onPressed:
                        reader.audioPreparation?.state ==
                                AudioPreparationState.preparing
                            ? null
                            : () => reader.prepareAudio(
                              AudioPreparationScope.chapter,
                            ),
                  ),
                  const SizedBox(height: 10),
                  AdaptiveButton(
                    label:
                        'Préparer tout le livre · ${_estimateLabel(_bookEstimate)}',
                    color: p.inset,
                    textColor: p.ink,
                    enabled:
                        reader.audioPreparation?.state !=
                        AudioPreparationState.preparing,
                    onPressed:
                        reader.audioPreparation?.state ==
                                AudioPreparationState.preparing
                            ? null
                            : () =>
                                reader.prepareAudio(AudioPreparationScope.book),
                  ),
                  if (reader.audioPreparation?.state ==
                      AudioPreparationState.preparing) ...[
                    const SizedBox(height: 10),
                    AdaptiveButton(
                      label: 'Interrompre',
                      style: AdaptiveButtonStyle.plain,
                      color: p.surface,
                      textColor: p.accent,
                      onPressed: reader.cancelAudioPreparation,
                    ),
                  ],
                  SettingSwitch(
                    title: 'Toujours conserver',
                    subtitle: 'Protège ce livre du nettoyage automatique.',
                    value: reader.activeBookCache?.pinned ?? false,
                    onChanged: reader.setActiveBookCachePinned,
                  ),
                  AdaptiveButton(
                    label: 'Supprimer l’audio de ce livre',
                    style: AdaptiveButtonStyle.plain,
                    color: p.surface,
                    textColor: p.warning,
                    onPressed: reader.clearActiveBookCache,
                  ),
                  const SizedBox(height: 8),
                  AdaptiveButton(
                    label: 'Régénérer tout l’audio',
                    style: AdaptiveButtonStyle.plain,
                    color: p.surface,
                    textColor: p.accent,
                    onPressed:
                        reader.audioPreparation?.state ==
                                AudioPreparationState.preparing
                            ? null
                            : () async {
                              await reader.clearActiveBookCache();
                              await reader.prepareAudio(
                                AudioPreparationScope.book,
                              );
                            },
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('Stockage'),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveButton(
                  label: 'Vider le cache audio',
                  color: p.inset,
                  textColor: p.ink,
                  onPressed:
                      () => _confirm(
                        context,
                        'Vider le cache audio ?',
                        'Les livres et les voix seront conservés. La prochaine lecture régénérera ses passages.',
                        reader.clearCache,
                      ),
                ),
                const SizedBox(height: 12),
                AdaptiveButton(
                  label: 'Supprimer les modèles locaux',
                  color: p.inset,
                  textColor: p.ink,
                  onPressed:
                      reader.models.busy
                          ? null
                          : () => _confirm(
                            context,
                            'Supprimer les modèles ?',
                            'Les voix téléchargées seront supprimées. Les livres et les voix du téléphone resteront disponibles.',
                            () async {
                              await reader.releaseModels();
                              await reader.models.removeModels();
                              await reader.setEngine(VoiceEngine.system);
                            },
                          ),
                ),
                const SizedBox(height: 12),
                AdaptiveButton(
                  label: 'Licences',
                  color: p.inset,
                  textColor: p.ink,
                  onPressed:
                      () => openPage<void>(
                        context,
                        const LicensePage(
                          applicationName: 'Audire',
                          applicationVersion: '0.1.0',
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _estimateLabel(AudioPreparationEstimate? estimate) {
    if (estimate == null) return 'calcul…';
    return _fileSize(estimate.estimatedDownloadBytes);
  }

  String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} Kio';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} Mio';
  }

  Future<void> _downloadNeural(ReaderController reader) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.installNeural();
    if (reader.models.neuralInstalled) {
      await reader.setEngine(VoiceEngine.neural);
    }
    reader.libraryChanged();
  }

  Future<void> _downloadKokoro(ReaderController reader) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.installKokoro();
    if (reader.models.kokoroInstalled) {
      await reader.setPlaybackLanguages(
        source: reader.settings.sourceLanguage,
        target: ReaderLanguage.english,
      );
      await reader.setEngine(VoiceEngine.kokoro);
    }
    reader.libraryChanged();
  }

  Future<void> _downloadQwen(ReaderController reader, String modelId) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.installQwen(modelId);
    if (reader.models.qwenInstalledFor(modelId)) {
      await reader.setQwenModel(modelId);
    }
    reader.libraryChanged();
  }

  Future<void> _downloadTranslation(ReaderController reader) async {
    await reader.models.installTranslationEnFr();
    reader.libraryChanged();
  }

  Future<void> _deleteNeural(ReaderController reader) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.deleteNeural();
    if (reader.settings.engine == VoiceEngine.neural) {
      await reader.setEngine(VoiceEngine.system);
    }
    reader.libraryChanged();
  }

  Future<void> _deleteKokoro(ReaderController reader) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.deleteKokoro();
    if (reader.settings.engine == VoiceEngine.kokoro) {
      await reader.setEngine(VoiceEngine.system);
    }
    reader.libraryChanged();
  }

  Future<void> _deleteQwen(ReaderController reader, String modelId) async {
    await reader.stop();
    await reader.releaseModels();
    await reader.models.deleteQwen(modelId);
    if (reader.settings.engine == VoiceEngine.qwen) {
      await reader.setEngine(VoiceEngine.system);
    }
    reader.libraryChanged();
  }

  Future<void> _deleteTranslation(ReaderController reader) async {
    await reader.models.deleteTranslation();
    reader.libraryChanged();
  }

  void _confirm(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) {
    AdaptiveAlertDialog.show(
      context: context,
      title: title,
      message: message,
      actions: [
        AlertAction(
          title: 'Annuler',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: 'Confirmer',
          onPressed: () {
            action();
          },
        ),
      ],
    );
  }
}

class _ModelPackRow extends StatelessWidget {
  const _ModelPackRow({
    required this.title,
    required this.subtitle,
    required this.installed,
    required this.busy,
    required this.onPressed,
    this.onDelete,
  });

  final String title, subtitle;
  final bool installed, busy;
  final VoidCallback? onPressed;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (installed)
              Icon(Icons.check_circle_rounded, size: 20, color: p.accent),
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: p.muted, height: 1.45)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AdaptiveButton(
                label: installed ? 'Retélécharger' : 'Télécharger',
                color: p.inset,
                textColor: p.ink,
                enabled: !busy && onPressed != null,
                onPressed: busy ? null : onPressed,
              ),
            ),
            if (onDelete != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Colors.red,
                  tooltip: 'Supprimer',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
