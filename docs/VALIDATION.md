# Validation et état réel

État au **12 septembre 2026**. Ce document sépare les contrôles réalisés des travaux restant à exécuter. Il ne constitue pas un rapport de recette réussi.

## Contrôles réalisés dans cet environnement

- `flutter pub get` réussi.
- `flutter analyze` réussi, sans issue.
- `flutter test` réussi : 20 tests passés.
- `flutter run --release -d 00008130-000E35182861401C` réussi sur **Iphone 15 Pro - Abdoul**, iOS 26.5, avec signature automatique via l'équipe `HZ3366WY57`. L'application a été installée et lancée sur l'appareil réel sans crash immédiat observé.
- **8 tests Python réussis avec `/opt/homebrew/bin/python3.12`** : structure EPUB et spine ; reproduction du contenu de la démo ; empreinte de fichier ; distance de caractères ; patch Android idempotent sur fixture ; patch iOS/liaison statique idempotent sur fixture ; résolution des imports Dart relatifs ; empreinte du packager de traduction.
- Compilation syntaxique des scripts Python via `py_compile`.
- Analyse syntaxique du fichier Swift via `swiftc -frontend -parse`. Pas de SDK iOS, donc aucune vérification de types Flutter/AVFoundation, de liaison ou de signature.
- Contrôle lexical des délimiteurs dans les fichiers Dart : utile pour repérer une parenthèse manquante, mais ce n’est pas un parseur Dart, un analyseur de types ou un compilateur Flutter.

Le journal brut de ces contrôles est dans `VALIDATION_LOG.txt`. Les tests des patchs natifs utilisent des fichiers de test contrôlés ; ils ne démontrent pas qu’un modèle Flutter téléchargé ultérieurement a été compilé.

## Non exécuté

Build Android, runtime Bergamot/Marian réel, export/quantification du checkpoint, chargement d’un modèle dans ONNX Runtime, génération réelle de voix, validation audio à l’oreille, rendu Flutter inspecté manuellement, précision acoustique, arrière-plan, consommation mémoire, batterie et performance.

La lecture audio sur l’iPhone doit encore être validée manuellement sur l’appareil : depuis le terminal, la build release a seulement prouvé l’installation, le lancement et l’absence de crash immédiat.

Les répertoires de plateforme et le lockfile sont générés lors du bootstrap et du premier `pub get`. Le CI est fourni pour lancer une vérification réelle dans un environnement disposant de ces outils ; aucune exécution CI n’a été déclenchée ici.

## Parcours de recette prioritaire

| Domaine | Essai | Critère à vérifier |
|---|---|---|
| Lancement | Premier lancement et redémarrage | Démo importée une fois, pas de dépendance obligatoire au réseau. |
| EPUB | Spine différent de l’ordre des fichiers | Ordre narratif identique au spine. |
| Filtrage | Navigation, notes, numéros de page, texte caché | Retraits conformes au balisage ; pas de disparition d’un paragraphe de récit. |
| Français | « Mme Martin a 21 livres », nombres 71/80/81/200, dialogues et accents | Prononciation écoutée, source affichée inchangée, expansions rattachées au bon texte. |
| Système | Voix française en mode avion | Audio local ; plages réelles ou suivi par phrase, jamais timer inventé. |
| Neuronal | Installation, interruption, reprise | Empreintes vérifiées, aucune installation partielle déclarée complète. |
| Supertonic | Dix timbres sur un même extrait | Sorties audibles sans erreur ONNX ; qualité évaluée à l’oreille. |
| Alignement | Même WAV avec et sans pack | Phrase sans pack, repères plausibles avec pack ; échec explicite ou repli quand nécessaire. |
| Vitesse | 0,65×, 1×, 1,7×, pause/reprise | Mot rattaché au temps média ; pas de dérive cumulative. |
| Concurrence | Déplacements, stop, changement de voix rapides | Aucun audio obsolète lu ; mesurer le retard induit par un calcul déjà en cours. |
| Interruptions | Appel, casque retiré, autre audio | Pause appropriée, pas de reprise surprise après arrêt manuel. |
| Système média | Verrouillage, écoute en fond, notification | Commandes et métadonnées cohérentes sur chaque OS. |
| Accessibilité | TalkBack/VoiceOver, texte 160 % et 200 %, animations réduites | Navigation et actions utilisables, pas d’informations masquées. |
| Données | Cache, suppression, espace faible, préférences corrompues | Message explicite, original EPUB conservé, pas d’échec silencieux. |
| Robustesse | EPUB endommagés et grandes archives | Allocations bornées en pratique ; compléter par fuzzing avant production. |

## Mesures à consigner, pas à inventer

Pour chaque téléphone : modèle, RAM, OS, moteur/voix, révisions des poids, dimensions du texte, durée de l’audio, temps de synthèse et d’alignement, pic mémoire, cache, température et batterie. Le ratio temps de calcul/durée audio doit être mesuré sur plusieurs phrases ; la prélecture ne cache pas un traitement durablement trop lent.

Pour le suivi, annoter manuellement un petit corpus français avec accents, nombres, noms propres et pauses. Comparer débuts/fins de mots à une référence audio, rapporter médiane, valeurs hautes et taux de repli par phrase. Ne pas confondre la granularité de trames du CTC avec une garantie de précision égale à cette granularité.

Pour la qualité de voix, faire écouter à plusieurs francophones les mêmes passages et noter naturel, intelligibilité, erreurs, pauses et fatigue. Le support déclaré du français ne suffit pas à prouver que chaque timbre est satisfaisant pour un livre entier.

## Porte de sortie vers une version distribuable

Résoudre les erreurs de compilation/analyse et faire passer les tests Flutter ; enregistrer le lockfile et la version Flutter retenue ; valider un iPhone et un Android cibles ; mesurer les deux modèles ensemble ; vérifier les licences et les informations éditeur ; configurer les signatures et ressources de publication. Une version en production demanderait en plus un durcissement de l’import et des migrations de données testées.
