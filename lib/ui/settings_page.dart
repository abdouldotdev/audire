import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import '../core/reader_controller.dart';
import '../domain/settings.dart';
import 'design_system.dart';
import 'reader_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.reader});
  final ReaderController reader;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
      children: [
        const PageIntro(
          kicker: 'Les détails qui comptent',
          title: 'À votre\nmesure.',
          subtitle:
              'Une lecture qui respecte le texte et votre façon de l’écouter.',
        ),
        const SectionLabel('Ambiance'),
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
        const SectionLabel('Ne lire que l’essentiel'),
        SurfacePanel(
          child: Column(
            children: [
              SettingSwitch(
                title: 'Lire les titres',
                subtitle:
                    'Conserver les titres de chapitres et de sections dans la narration.',
                value: reader.settings.readHeadings,
                onChanged: (v) => reader.setContent(headings: v),
              ),
              Divider(color: p.line),
              SettingSwitch(
                title: 'Lire les notes',
                subtitle:
                    'Inclure les notes identifiées dans le fil du livre. Désactivé par défaut.',
                value: reader.settings.readNotes,
                onChanged: (v) => reader.setContent(notes: v),
              ),
              Divider(color: p.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Les menus de navigation, scripts, appels de notes et numéros de page balisés sont écartés. Le texte n’est ni résumé ni réécrit par une IA.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: p.muted),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Sur cet appareil'),
        SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: p.accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Pas de compte. Pas de cloud vocal.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'L’import, la narration et l’alignement sont conçus pour rester locaux. Internet est utilisé seulement lors de l’installation des modèles. Aucun microphone n’est nécessaire.',
                style: TextStyle(color: p.muted, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 18),
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
                          'Les voix neuronales et l’alignement seront supprimés. Les livres et les voix système resteront disponibles.',
                          () async {
                            await reader.releaseModels();
                            await reader.models.removeModels();
                            await reader.setEngine(VoiceEngine.system);
                          },
                        ),
              ),
            ],
          ),
        ),
        const SectionLabel('Lisière · 0.1.0'),
        Text(
          'Prototype de lecteur EPUB sans DRM. La mise en page est réadaptée pour la lecture : ce n’est pas une reproduction exacte de l’édition imprimée. Les limites et la recette de validation sont documentées dans le projet.',
          style: TextStyle(color: p.muted, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 14),
        AdaptiveButton(
          label: 'Licences des composants',
          color: p.inset,
          textColor: p.ink,
          onPressed:
              () => openPage<void>(
                context,
                const LicensePage(
                  applicationName: 'Lisière',
                  applicationVersion: '0.1.0',
                ),
              ),
        ),
        const SizedBox(height: 32),
        Text(
          'LIRE · ÉCOUTER · RESPIRER',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 10, letterSpacing: 2),
        ),
      ],
    );
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
