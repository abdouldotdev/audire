import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';

class VoicesPage extends StatefulWidget {
  const VoicesPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  State<VoicesPage> createState() => _VoicesPageState();
}

class _VoicesPageState extends State<VoicesPage> {
  String? _error;
  Future<void> _install() async {
    await widget.reader.releaseModels();
    await widget.reader.models.installNeural();
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.reader, widget.reader.models]),
    builder: (context, _) {
      final reader = widget.reader,
          models = reader.models,
          p = PaperColors.of(context);
      final neural = reader.settings.engine == VoiceEngine.neural;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
        children: [
          const PageIntro(
            kicker: 'L’atelier des voix',
            title: 'Trouvez\nvotre voix.',
            subtitle:
                'Écoutez un extrait. Choisissez le timbre qui vous donne envie de rester.',
          ),
          const SizedBox(height: 24),
          AdaptiveSegmentedControl(
            labels: const ['Téléphone', 'Neuronales'],
            selectedIndex: neural ? 1 : 0,
            onValueChanged:
                (i) => reader.setEngine(
                  i == 0 ? VoiceEngine.system : VoiceEngine.neural,
                ),
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
          if (!neural) ...[
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatusPill(
                    'Voix locales installées',
                    icon: Icons.phone_iphone_outlined,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Prêtes à lire',
                    style: LisiereTheme.editorial(context, size: 25),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'La qualité dépend des voix présentes sur votre appareil. Le suivi mot à mot s’active lorsque le moteur fournit les repères de parole.',
                    style: TextStyle(color: p.muted, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  AdaptiveButton(
                    label:
                        reader.loadingVoices
                            ? 'Recherche…'
                            : 'Recharger les voix',
                    onPressed:
                        reader.loadingVoices ? null : reader.reloadVoices,
                    color: p.inset,
                    textColor: p.ink,
                  ),
                ],
              ),
            ),
            const SectionLabel('Français · sur cet appareil'),
            if (reader.systemVoices.isEmpty && !reader.loadingVoices)
              const Notice(
                'Aucune voix française hors ligne trouvée. Installez-en une dans les réglages de synthèse vocale ou d’accessibilité du téléphone, puis rechargez cette liste. Les voix neuronales sont une autre option.',
              ),
            for (final voice in reader.systemVoices)
              ChoiceTile(
                title: voice.name,
                subtitle: '${voice.language} · locale',
                selected:
                    reader.settings.systemVoice == voice.id ||
                    (reader.settings.systemVoice == null &&
                        reader.systemVoices.first.id == voice.id),
                onPressed: () => reader.selectVoice(nativeId: voice.id),
                leading: Icon(
                  Icons.record_voice_over_outlined,
                  color: p.accent,
                ),
              ),
          ] else ...[
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusPill(
                    models.neuralInstalled
                        ? 'Installé · hors ligne'
                        : 'Installation à la demande',
                    icon:
                        models.neuralInstalled
                            ? Icons.check_circle_outline
                            : Icons.download_outlined,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Supertonic 3',
                    style: LisiereTheme.editorial(context, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '10 voix · français · synthèse sur le téléphone',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Le téléchargement vient du dépôt officiel. Après installation, aucun texte du livre n’est envoyé à un service vocal. Prévoyez de l’espace libre et une connexion Wi-Fi.',
                    style: TextStyle(color: p.muted, height: 1.5, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Poids sous licence OpenRAIL-M. Conditions et attribution conservées avec les modèles.',
                    style: TextStyle(color: p.muted, height: 1.4, fontSize: 12),
                  ),
                  if (!models.neuralInstalled && !models.busy) ...[
                    const SizedBox(height: 20),
                    PrimaryAction(
                      label: 'Installer les 10 voix',
                      onPressed: _install,
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
            const SectionLabel('Timbres féminins'),
            for (var i = 1; i <= 5; i++)
              ChoiceTile(
                title: 'Voix F$i',
                subtitle: 'Supertonic 3 · français',
                selected: reader.settings.neuralVoice == 'F$i',
                onPressed:
                    models.busy
                        ? null
                        : () => reader.selectVoice(neuralId: 'F$i'),
                leading: _VoiceMark(label: 'F$i'),
              ),
            const SectionLabel('Timbres masculins'),
            for (var i = 1; i <= 5; i++)
              ChoiceTile(
                title: 'Voix M$i',
                subtitle: 'Supertonic 3 · français',
                selected: reader.settings.neuralVoice == 'M$i',
                onPressed:
                    models.busy
                        ? null
                        : () => reader.selectVoice(neuralId: 'M$i'),
                leading: _VoiceMark(label: 'M$i'),
              ),
            const SectionLabel('Synchronisation du texte'),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    models.alignmentInstalled
                        ? 'Alignement acoustique installé'
                        : 'Ajouter le suivi mot à mot',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'La voix seule ne donne pas les horaires de chaque mot. Un second modèle local aligne le texte sur l’audio réellement produit. Sans ce pack, la phrase est surlignée.',
                    style: TextStyle(color: p.muted, height: 1.5, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Le script tool/export_alignment.py fourni avec le projet produit le fichier alignment-fr.zip à importer ici.',
                    style: TextStyle(color: p.muted, height: 1.5, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  PrimaryAction(
                    label:
                        models.alignmentInstalled
                            ? 'Remplacer le pack d’alignement'
                            : 'Importer le pack d’alignement',
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
          ],
          const SizedBox(height: 24),
          PrimaryAction(
            label:
                reader.previewing && reader.active
                    ? 'Arrêter l’extrait'
                    : 'Écouter la voix sélectionnée',
            onPressed:
                models.busy ||
                        reader.loadingVoices ||
                        (neural
                            ? !models.neuralInstalled
                            : reader.systemVoices.isEmpty)
                    ? null
                    : reader.previewing && reader.active
                    ? reader.stop
                    : reader.audition,
          ),
          const SizedBox(height: 14),
          Text(
            'La voix se choisit à l’oreille. Le naturel et la prononciation peuvent varier selon le texte et l’appareil.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, height: 1.5, fontSize: 12),
          ),
        ],
      );
    },
  );
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
