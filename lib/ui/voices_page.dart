import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';

class VoicesPage extends StatefulWidget {
  const VoicesPage({
    super.key,
    required this.reader,
    this.showSourceLanguage = false,
  });
  final ReaderController reader;
  final bool showSourceLanguage;
  @override
  State<VoicesPage> createState() => _VoicesPageState();
}

class _VoicesPageState extends State<VoicesPage>
    with AutomaticKeepAliveClientMixin<VoicesPage> {
  String? _error;
  String? _previewingNativeId,
      _previewingNeuralId,
      _previewingKokoroId,
      _previewingQwenId;

  @override
  bool get wantKeepAlive => true;

  Future<void> _setSourceLanguage(ReaderLanguage source) {
    final target =
        source == ReaderLanguage.french &&
                widget.reader.settings.targetLanguage == ReaderLanguage.english
            ? ReaderLanguage.french
            : widget.reader.settings.targetLanguage;
    return widget.reader.setPlaybackLanguages(source: source, target: target);
  }

  Future<void> _setTargetLanguage(ReaderLanguage target) {
    final source =
        target == ReaderLanguage.english &&
                widget.reader.settings.sourceLanguage == ReaderLanguage.french
            ? ReaderLanguage.english
            : widget.reader.settings.sourceLanguage;
    return widget.reader.setPlaybackLanguages(source: source, target: target);
  }

  Future<void> _alignment() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (picked == null) return;
      final path = picked.files.single.path;
      if (path == null) {
        throw StateError('Copiez le pack dans Fichiers avant de l’importer.');
      }
      await widget.reader.releaseModels();
      await widget.reader.models.importAlignment(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    }
  }

  Future<void> _preview({
    String? nativeId,
    String? neuralId,
    String? kokoroId,
    String? qwenId,
  }) async {
    if (_isPreviewing(
      nativeId: nativeId,
      neuralId: neuralId,
      kokoroId: kokoroId,
      qwenId: qwenId,
    )) {
      await widget.reader.stop();
      if (mounted) {
        setState(() {
          _previewingNativeId = null;
          _previewingNeuralId = null;
          _previewingKokoroId = null;
          _previewingQwenId = null;
        });
      }
      return;
    }
    setState(() {
      _previewingNativeId = nativeId;
      _previewingNeuralId = neuralId;
      _previewingKokoroId = kokoroId;
      _previewingQwenId = qwenId;
    });
    await widget.reader.selectVoice(
      nativeId: nativeId,
      neuralId: neuralId,
      kokoroId: kokoroId,
      qwenId: qwenId,
      resumePlayback: false,
    );
    await widget.reader.audition();
  }

  bool _isPreviewing({
    String? nativeId,
    String? neuralId,
    String? kokoroId,
    String? qwenId,
  }) =>
      widget.reader.previewing &&
      widget.reader.active &&
      _previewingNativeId == nativeId &&
      _previewingNeuralId == neuralId &&
      _previewingKokoroId == kokoroId &&
      _previewingQwenId == qwenId;

  Future<void> _downloadSupertonic() async {
    await widget.reader.stop();
    await widget.reader.releaseModels();
    await widget.reader.models.installNeural();
    if (widget.reader.models.neuralInstalled) {
      await widget.reader.setEngine(VoiceEngine.neural);
    }
  }

  Future<void> _downloadKokoro() async {
    await widget.reader.stop();
    await widget.reader.releaseModels();
    await widget.reader.models.installKokoro();
    if (widget.reader.models.kokoroInstalled) {
      await widget.reader.setEngine(VoiceEngine.kokoro);
    }
  }

  Future<void> _downloadQwen(String modelId) async {
    await widget.reader.stop();
    await widget.reader.releaseModels();
    await widget.reader.models.installQwen(modelId);
    if (widget.reader.models.qwenInstalledFor(modelId)) {
      await widget.reader.setQwenModel(modelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: Listenable.merge([widget.reader, widget.reader.models]),
      builder: (context, _) {
        final reader = widget.reader,
            models = reader.models,
            p = PaperColors.of(context);
        final targetLanguage = reader.settings.targetLanguage;
        final localVoices = reader.voicesFor(targetLanguage).toList();
        final system = reader.activeEngine == VoiceEngine.system;
        final neural = reader.activeEngine == VoiceEngine.neural;
        final kokoro = reader.activeEngine == VoiceEngine.kokoro;
        final qwen = reader.activeEngine == VoiceEngine.qwen;
        return SafeArea(
          top: true,
          bottom: false,
          child: ListView(
            key: const PageStorageKey<String>('voices-tab-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            children: [
              const PageIntro(kicker: 'Voix', title: 'Moteur'),
              const SizedBox(height: 20),
              if (widget.showSourceLanguage) ...[
                Text(
                  'Langue du livre',
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                AdaptiveSegmentedControl(
                  labels: ReaderLanguage.values.map((l) => l.label).toList(),
                  selectedIndex: reader.settings.sourceLanguage.index,
                  onValueChanged:
                      (i) => _setSourceLanguage(ReaderLanguage.values[i]),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                'Langue de la voix',
                style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              AdaptiveSegmentedControl(
                labels: ReaderLanguage.values.map((l) => l.label).toList(),
                selectedIndex: targetLanguage.index,
                onValueChanged:
                    (i) => _setTargetLanguage(ReaderLanguage.values[i]),
              ),
              const SizedBox(height: 20),
              _VoiceEngineCard(
                title: 'Supertonic 3',
                subtitle: 'Recommandé · rapide · français et anglais',
                score: 5,
                size: '≈ 415 Mio',
                selected: neural,
                installed: models.neuralInstalled,
                busy: models.busy && models.activeDownload == 'supertonic',
                progress: models.progress,
                onPressed:
                    models.busy
                        ? null
                        : models.neuralInstalled
                        ? () => reader.setEngine(VoiceEngine.neural)
                        : _downloadSupertonic,
              ),
              const SizedBox(height: 10),
              _VoiceEngineCard(
                title: 'Qwen 0.6B',
                subtitle:
                    models.qwenPackSupported('compact')
                        ? 'Voix premium · français et anglais'
                        : 'Incompatible avec ce modèle détecté',
                score: 4,
                size: '≈ 1,7 Go',
                selected: qwen && reader.settings.qwenModel == 'compact',
                installed: models.qwenDownloadedFor('compact'),
                busy: models.busy && models.activeDownload == 'qwen-compact',
                progress: models.progress,
                onPressed:
                    models.busy
                        ? null
                        : !models.qwenPackSupported('compact')
                        ? null
                        : models.qwenInstalled
                        ? () => reader.setQwenModel('compact')
                        : () => _downloadQwen('compact'),
              ),
              if (models.qwenPackSupported('quality')) ...[
                const SizedBox(height: 10),
                _VoiceEngineCard(
                  title: 'Qwen Qualité',
                  subtitle: '0.6B 8-bit · plus de précision',
                  score: 5,
                  size: '≈ 2,0 Go',
                  selected: qwen && reader.settings.qwenModel == 'quality',
                  installed: models.qwenDownloadedFor('quality'),
                  busy: models.busy && models.activeDownload == 'qwen-quality',
                  progress: models.progress,
                  onPressed:
                      models.busy
                          ? null
                          : models.qwenQualityInstalled
                          ? () => reader.setQwenModel('quality')
                          : () => _downloadQwen('quality'),
                ),
              ],
              if (models.qwenPackSupported('max')) ...[
                const SizedBox(height: 10),
                _VoiceEngineCard(
                  title: 'Qwen Max 1.7B',
                  subtitle:
                      'Meilleur rendu · plus lent · français et anglais',
                  score: 5,
                  size: '≈ 2,3 Go',
                  selected: qwen && reader.settings.qwenModel == 'max',
                  installed: models.qwenDownloadedFor('max'),
                  busy: models.busy && models.activeDownload == 'qwen-max',
                  progress: models.progress,
                  onPressed:
                      models.busy
                          ? null
                          : models.qwenMaxInstalled
                          ? () => reader.setQwenModel('max')
                          : () => _downloadQwen('max'),
                ),
              ],
              if (!models.qwenPackSupported('quality') ||
                  !models.qwenPackSupported('max'))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(
                    [
                      if (!models.qwenPackSupported('quality'))
                        models.qwenPackUnavailableReason('quality'),
                      if (!models.qwenPackSupported('max'))
                        models.qwenPackUnavailableReason('max'),
                    ].join('\n'),
                  ),
                ),
              const SizedBox(height: 10),
              _VoiceEngineCard(
                title: 'Kokoro 82M',
                subtitle:
                    targetLanguage == ReaderLanguage.english
                        ? 'Très efficace · voix anglaises'
                        : 'Uniquement pour la voix anglaise',
                score: 5,
                size: '≈ 96 Mio',
                selected: kokoro,
                installed: models.kokoroInstalled,
                busy: models.busy && models.activeDownload == 'kokoro',
                progress: models.progress,
                onPressed:
                    models.busy || targetLanguage != ReaderLanguage.english
                        ? null
                        : models.kokoroInstalled
                        ? () => reader.setEngine(VoiceEngine.kokoro)
                        : _downloadKokoro,
              ),
              const SizedBox(height: 10),
              _VoiceEngineCard(
                title: 'Voix du téléphone',
                subtitle: 'Sans téléchargement · qualité variable',
                score: 3,
                size: '0 Mio',
                selected: system,
                installed: true,
                busy: false,
                onPressed: () => reader.setEngine(VoiceEngine.system),
              ),
              const SizedBox(height: 20),
              if (reader.message != null)
                Notice(reader.message!, onClose: reader.clearMessage),
              if (_error != null)
                Notice(
                  _error!,
                  onClose:
                      () => setState(() {
                        _error = null;
                      }),
                ),
              if (system) ...[
                AdaptiveButton(
                  label: reader.loadingVoices ? 'Recherche…' : 'Recharger',
                  onPressed: reader.loadingVoices ? null : reader.reloadVoices,
                  color: p.inset,
                  textColor: p.ink,
                ),
                SectionLabel('Voix locales ${targetLanguage.label}'),
                if (localVoices.isEmpty && !reader.loadingVoices)
                  Notice(
                    'Aucune voix ${targetLanguage == ReaderLanguage.english ? 'anglaise' : 'française'} hors ligne trouvée.',
                  ),
                for (final voice in localVoices)
                  ChoiceTile(
                    title: voice.name,
                    subtitle: '${voice.language} · locale',
                    selected:
                        reader.settings.systemVoiceFor(targetLanguage) ==
                            voice.id ||
                        (reader.settings.systemVoiceFor(targetLanguage) ==
                                null &&
                            localVoices.first.id == voice.id),
                    onPressed: () => reader.selectVoice(nativeId: voice.id),
                    leading: Icon(
                      Icons.record_voice_over_outlined,
                      color: p.accent,
                    ),
                    trailing: IconAction(
                      label: 'Écouter ${voice.name}',
                      icon:
                          _isPreviewing(nativeId: voice.id)
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                      onPressed:
                          reader.loadingVoices
                              ? null
                              : () => _preview(nativeId: voice.id),
                    ),
                  ),
              ] else if (neural) ...[
                SurfacePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(
                        models.neuralInstalled ? 'Installé' : 'À installer',
                        icon:
                            models.neuralInstalled
                                ? Icons.check_circle_outline
                                : Icons.download_outlined,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Voix françaises',
                        style: LisiereTheme.editorial(context, size: 26),
                      ),
                      if (!models.neuralInstalled && !models.busy) ...[
                        const SizedBox(height: 20),
                        Notice(
                          'Ce pack se choisit pendant l’onboarding. Une fois installé, il peut être retéléchargé depuis Profil.',
                        ),
                      ],
                      if (models.busy) ...[
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: models.total > 0 ? models.progress : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          models.status,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        if (models.total > 0) ...[
                          const SizedBox(height: 7),
                          Text(
                            '${(models.received / 1048576).toStringAsFixed(0)} / ${(models.total / 1048576).toStringAsFixed(0)} Mio',
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          AdaptiveButton(
                            label: 'Interrompre',
                            onPressed: models.cancel,
                            color: p.inset,
                            textColor: p.ink,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (models.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Notice(models.error!),
                  ),
                const SectionLabel('Féminines'),
                for (var i = 1; i <= 5; i++)
                  ChoiceTile(
                    title: 'Voix F$i',
                    subtitle: 'Voix française',
                    selected: reader.settings.neuralVoice == 'F$i',
                    onPressed:
                        models.busy
                            ? null
                            : () => reader.selectVoice(neuralId: 'F$i'),
                    leading: _VoiceMark(label: 'F$i'),
                    trailing: IconAction(
                      label: 'Écouter la voix F$i',
                      icon:
                          _isPreviewing(neuralId: 'F$i')
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                      onPressed:
                          models.busy || !models.neuralInstalled
                              ? null
                              : () => _preview(neuralId: 'F$i'),
                    ),
                  ),
                const SectionLabel('Masculines'),
                for (var i = 1; i <= 5; i++)
                  ChoiceTile(
                    title: 'Voix M$i',
                    subtitle: 'Voix française',
                    selected: reader.settings.neuralVoice == 'M$i',
                    onPressed:
                        models.busy
                            ? null
                            : () => reader.selectVoice(neuralId: 'M$i'),
                    leading: _VoiceMark(label: 'M$i'),
                    trailing: IconAction(
                      label: 'Écouter la voix M$i',
                      icon:
                          _isPreviewing(neuralId: 'M$i')
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                      onPressed:
                          models.busy || !models.neuralInstalled
                              ? null
                              : () => _preview(neuralId: 'M$i'),
                    ),
                  ),
                const SectionLabel('Alignement'),
                SurfacePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        models.alignmentInstalled
                            ? 'Pack installé'
                            : 'Pack requis pour le mot à mot',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryAction(
                        label:
                            models.alignmentInstalled
                                ? 'Remplacer le pack'
                                : 'Importer le pack',
                        onPressed: models.busy ? null : _alignment,
                      ),
                      if (models.alignmentInstalled)
                        SettingSwitch(
                          title: 'Aligner mot à mot',
                          subtitle:
                              'Un alignement incertain reste affiché par phrase.',
                          value: reader.settings.wordAlignment,
                          onChanged: models.busy ? null : reader.setAlignment,
                        ),
                    ],
                  ),
                ),
              ] else if (kokoro) ...[
                const SectionLabel('Voix Kokoro'),
                for (final voice in const [
                  'Bella',
                  'Nicole',
                  'Sarah',
                  'Default',
                  'Adam',
                  'Michael',
                ])
                  ChoiceTile(
                    title: voice == 'Default' ? 'Heart' : voice,
                    subtitle: 'Voix anglaise',
                    selected: reader.settings.kokoroVoice == voice,
                    onPressed:
                        models.busy
                            ? null
                            : () => reader.selectVoice(kokoroId: voice),
                    leading: _VoiceMark(
                      label:
                          const {
                            'Bella': 'B',
                            'Nicole': 'N',
                            'Sarah': 'S',
                            'Default': 'H',
                            'Adam': 'A',
                            'Michael': 'M',
                          }[voice]!,
                    ),
                    trailing: IconAction(
                      label: 'Écouter $voice',
                      icon:
                          _isPreviewing(kokoroId: voice)
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                      onPressed:
                          models.busy || !models.kokoroInstalled
                              ? null
                              : () => _preview(kokoroId: voice),
                    ),
                  ),
              ] else if (qwen) ...[
                SurfacePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(
                        models.qwenInstalledFor(reader.settings.qwenModel)
                            ? 'Installé'
                            : 'À installer',
                        icon:
                            models.qwenInstalledFor(reader.settings.qwenModel)
                                ? Icons.check_circle_outline
                                : Icons.download_outlined,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        models.qwenPackFor(reader.settings.qwenModel).title,
                        style: LisiereTheme.editorial(context, size: 26),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pour les appareils récents. La première phrase demande plus de préparation.',
                        style: TextStyle(color: p.muted, height: 1.4),
                      ),
                      if (models.busy &&
                          models.activeDownload?.startsWith('qwen-') ==
                              true) ...[
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: models.total > 0 ? models.progress : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          models.status,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        if (models.total > 0) ...[
                          const SizedBox(height: 7),
                          Text(
                            '${(models.received / 1048576).toStringAsFixed(0)} / ${(models.total / 1048576).toStringAsFixed(0)} Mio',
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          AdaptiveButton(
                            label: 'Interrompre',
                            onPressed: models.cancel,
                            color: p.inset,
                            textColor: p.ink,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SectionLabel('Voix Qwen'),
                for (final voice in const [
                  'Vivian',
                  'Serena',
                  'Aiden',
                  'Ryan',
                  'Dylan',
                  'Eric',
                  'Uncle Fu',
                  'Ono Anna',
                  'Sohee',
                ])
                  ChoiceTile(
                    title: voice,
                    subtitle: 'Français et anglais',
                    selected: reader.settings.qwenVoice == voice,
                    onPressed:
                        models.busy
                            ? null
                            : () => reader.selectVoice(qwenId: voice),
                    leading: _VoiceMark(label: voice.characters.first),
                    trailing: IconAction(
                      label: 'Écouter $voice',
                      icon:
                          _isPreviewing(qwenId: voice)
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                      onPressed:
                          models.busy ||
                                  !models.qwenInstalledFor(
                                    reader.settings.qwenModel,
                                  )
                              ? null
                              : () => _preview(qwenId: voice),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VoiceMark extends StatelessWidget {
  const _VoiceMark({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.paper, shape: BoxShape.circle),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: LisiereTheme.serif,
          fontSize: 17,
          color: p.ink,
        ),
      ),
    );
  }
}

class _VoiceEngineCard extends StatelessWidget {
  const _VoiceEngineCard({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.size,
    required this.selected,
    required this.installed,
    required this.busy,
    required this.onPressed,
    this.progress = 0,
  });

  final String title, subtitle, size;
  final int score;
  final bool selected, installed, busy;
  final double progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, efficacité $score sur 5, $size',
      child: Material(
        color: selected ? p.accent.withValues(alpha: .12) : p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? p.accent : p.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded, color: p.accent)
                    else if (installed)
                      Icon(Icons.download_done_rounded, color: p.muted)
                    else
                      Icon(Icons.download_rounded, color: p.muted),
                  ],
                ),
                const SizedBox(height: 5),
                Text(subtitle, style: TextStyle(color: p.muted, height: 1.35)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Efficacité',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (var i = 0; i < 5; i++)
                      Container(
                        width: 16,
                        height: 5,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: i < score ? p.accent : p.line,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      size,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
