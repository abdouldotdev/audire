# Lisière

**Vos livres, à votre rythme.** Lecteur EPUB en Flutter pour iOS et Android, avec synthèse vocale locale française et suivi du texte prononcé.

> **État de livraison — 11 septembre 2026 : prototype source, non compilé sur Flutter dans l’environnement de préparation.** L’archive contient l’implémentation, un plugin Swift/Kotlin, un EPUB original, les scripts et les tests. Elle ne contient ni APK/IPA, ni poids de modèles, ni `pubspec.lock` résolu. Les tests Flutter, l’export ONNX et la lecture sur appareil restent à exécuter. Voir `docs/VALIDATION.md`.

## Ce qui est implémenté

La bibliothèque importe les EPUB non chiffrés, affiche leurs couvertures et garde la dernière position. Le lecteur présente le texte, les chapitres, le passage courant et les commandes audio. L’onglet Voix permet de choisir une voix française installée sur le téléphone ou l’un des dix timbres Supertonic 3, d’écouter un extrait et de gérer les modèles. Les réglages couvrent les thèmes clair/sombre/système, la taille du texte, la vitesse, les titres, les notes et le défilement automatique.

Le design system réunit un fond papier, un vert forêt, des titres éditoriaux et une typographie de lecture à empattements avec repli sur les polices système. Navigation, boutons, dialogues, cartes et contrôles utilisent réellement `adaptive_platform_ui`, fixé à **0.1.111**. Aucune police propriétaire n’est distribuée.

Il n’y a ni compte, ni serveur applicatif, ni clé API, ni fonction de clonage vocal, ni accès au microphone. L’app produit la voix à partir du texte : c’est de la **synthèse vocale (TTS)**. Le modèle CTC optionnel analyse uniquement cet audio produit, pour retrouver les positions des mots.

## Démarrer le projet

### Prérequis

Utilisez Flutter stable avec Dart **3.9 ou supérieur**, Python 3 pour les scripts et les outils Android configurés (`flutter doctor`). Le projet fixe Android **API 26 minimum**. Pour iOS : un Mac, Xcode, CocoaPods et une cible **iOS 16 minimum** ; le wrapper ONNX utilisé demande une liaison CocoaPods statique.

Les répertoires `android/` et `ios/` ne sont pas des coquilles écrites à la main. Le bootstrap les génère à partir des modèles officiels de **votre** SDK Flutter, puis applique la configuration audio et ONNX. Il conserve `lib/`, les tests et le `pubspec.yaml` fournis. Ne lancez pas un `flutter create .` non maîtrisé sur le projet.

Depuis le dossier extrait `lisiere/` :

```sh
python3 tool/bootstrap.py
flutter pub get
dart format lib test packages/lisiere_native_tts/lib
flutter analyze --no-fatal-infos
flutter test
flutter run
```

Le bootstrap est conçu pour être relancé sans dupliquer la configuration. Il s’arrête explicitement lorsqu’un modèle natif attendu n’est pas reconnu. Sa compatibilité avec un nouveau modèle Flutter doit être vérifiée avant de modifier un projet déjà personnalisé. Il demande un modèle Android Gradle Kotlin DSL.

**iOS et gestion des dépendances :** ce projet est configuré pour CocoaPods. Si Swift Package Manager est activé dans votre installation Flutter et interfère avec ce parcours, désactivez-le pour cette configuration (`flutter config --no-enable-swift-package-manager`, commande qui modifie votre configuration Flutter), puis régénérez les dépendances. Dans `ios/Podfile`, conserver `use_frameworks! :linkage => :static`. Ne remplacez pas cela par des frameworks dynamiques sans revalider ONNX.

Un livre original de démonstration, *Le jardin des heures*, est ajouté au premier lancement. Pour le premier essai, choisissez **Voix → Téléphone**, puis une voix française déjà installée. Si la liste est vide, installez une voix française hors ligne dans les réglages de synthèse vocale/accessibilité du téléphone et rechargez la liste.

Après validation du code et du comportement :

```sh
flutter build apk --release
# Sur macOS, avec configuration de signature appropriée :
flutter build ios --release
```

La signature de production, l’identité éditeur, les identifiants d’application, les icônes définitives et les informations de publication ne sont pas configurés. La signature de développement d’un modèle Flutter n’est pas une signature de distribution. Le plugin local comporte volontairement des coordonnées éditeur `example.invalid` à remplacer avant toute publication indépendante.

## Installer les voix neuronales

Dans **Voix → Neuronales → Installer les 10 voix**, l’app télécharge les quatre modèles ONNX, le frontal texte et les styles de voix depuis le dépôt officiel archivé :

```text
supertone-oss-archive/supertonic-3
révision : aafc6e32416a594460b32413efc49d7fe4ce6d46
```

Le téléchargement est explicite, avec progression, fichiers partiels reprenables, vérification des empreintes annoncées par le dépôt et installation en répertoire temporaire. Une empreinte garantit l’intégrité par rapport au catalogue récupéré, pas un audit indépendant du modèle. Le code fixe une révision ; une migration de dépôt nécessite une mise à jour explicite de cette référence.

Prévoir plusieurs centaines de mégaoctets, plus l’espace de préparation et le cache audio. Le catalogue consulté affichait environ **415 MB** pour le dépôt complet ; l’app calcule le volume exact de sa sélection. La taille des poids n’est pas la consommation de RAM à l’exécution. Le téléchargement n’est pas un transfert natif persistant garanti lorsque l’app est suspendue : gardez-la ouverte, et reprenez l’installation si nécessaire.

Les styles sont F1–F5 et M1–M5. Le français est pris en charge par le modèle. Le bouton d’extrait permet de comparer les timbres : aucune promesse de voix indiscernable d’un narrateur humain ou de prononciation parfaite. Le traitement par phrases, la ponctuation conservée et les pauses du modèle évitent de synthétiser chaque mot isolément. Il n’y a pas d’attribution automatique d’une voix différente à chaque personnage.

**Après installation, la synthèse Supertonic n’envoie pas le texte à un service distant.** Il faut tout de même vérifier le comportement complet en mode avion sur chaque plateforme et version retenue.

## Le suivi mot à mot : trois états explicites

| Parcours | Source du surlignage | Condition |
|---|---|---|
| Voix du téléphone | Plages réellement signalées par `AVSpeechSynthesizer` / `TextToSpeech` | Le moteur et la voix doivent fournir ces événements ; leur granularité dépend du moteur. |
| Supertonic + pack d’alignement | Audio synthétisé → émissions CTC → alignement contraint du texte → positions audio | Pack installé, activé, sortie compatible et alignement accepté. |
| Supertonic sans pack, ou résultat incertain | Phrase en cours | L’interface dit **« Suivi par phrase »**. |

**Supertonic seul ne donne pas ici un suivi exact par mot.** Le lecteur ne répartit pas artificiellement une durée entre les caractères et ne fait pas passer une estimation pour une mesure. Les repères acoustiques suivent la position du lecteur audio, y compris après changement de vitesse et pause. Leur résolution et leur justesse restent limitées par le modèle, le rééchantillonnage, l’alignement et les événements du système.

La confiance de chemin et l’écart entre décodage CTC et texte attendu servent de garde-fous conservateurs. Les seuils présents sont des paramètres de prototype, **pas des seuils calibrés sur un corpus de validation**. Aucun résultat d’alignement n’a été mesuré sur téléphone dans cette livraison.

### Produire le pack français sur un ordinateur

Le pack n’est **pas fourni préexporté**. Le script utilise par défaut le checkpoint CTC français `jonatasgrosman/wav2vec2-large-xlsr-53-french`, et non un modèle uniquement préentraîné sans tête de reconnaissance. Ce checkpoint attend un signal à 16 kHz et annonce la licence Apache-2.0.

Sur un poste Python **3.11**, avec suffisamment de mémoire et plusieurs gigaoctets d’espace temporaire :

```sh
python3.11 -m venv .venv-align
source .venv-align/bin/activate
python -m pip install -r tool/requirements-alignment.txt
python tool/export_alignment.py --output alignment-fr.zip
```

Sous Windows, activer l’environnement avec `.venv-align\Scripts\activate`. Les versions de dépendances sont explicitement renseignées, mais leur installation commune et l’export complet **n’ont pas été exécutés ici**.

Pour documenter une vérification supplémentaire avec un enregistrement français mono à 16 kHz, de moins de 55 secondes :

```sh
python tool/export_alignment.py --output alignment-fr.zip \
  --validation-wav essai-fr-16k.wav \
  --validation-text "Bonjour, nous lisons un livre en français."
```

Le script résout et enregistre la révision du checkpoint, exporte les émissions CTC à longueur dynamique, quantifie les opérations MatMul en INT8 en conservant les convolutions en flottant, vérifie les dimensions ONNX à deux durées, puis génère un ZIP plat avec manifeste d’empreintes. Ces contrôles structurels ne prouvent pas la qualité perceptuelle, ni une faible consommation sur mobile.

Copier `alignment-fr.zip` sur le téléphone et ouvrir **Voix → Neuronales → Importer le pack d’alignement**. Activer **Aligner mot à mot**. L’importeur vérifie les fichiers autorisés, la taille, le format et les empreintes, puis installe le pack. N’importez que des modèles de confiance : une archive structurellement valide ne rend pas un modèle arbitraire sûr à exécuter.

Le checkpoint français retenu est plus lourd que le modèle de voix et peut être trop coûteux sur certains appareils. Mesurez la RAM et le délai de préparation ; le mode sans alignement et les voix système restent disponibles. Le code n’affirme pas que ce parcours est suffisamment rapide sur tous les téléphones.

## Lire ce qui est utile

L’import suit l’ordre de lecture déclaré par le **spine EPUB**, pas l’ordre alphabétique des fichiers. Les documents de navigation et éléments non linéaires sont exclus. Scripts, formulaires, navigation HTML, éléments explicitement cachés, repères de pages et appels de notes balisés sont retirés de la narration. Titres et corps de notes reconnus sont classés ; les titres sont lus par défaut, les notes ne le sont pas.

Les corps de notes présents uniquement dans un document non linéaire ne sont pas rapatriés quand on active les notes. Un sommaire ordinaire sans balisage de navigation ou une mention légale en texte courant peut rester : le prototype ne devine pas librement ce qui est « inutile » au risque d’amputer le livre.

Quelques abréviations françaises et entiers simples sont développés avant la narration. Une table de correspondance par unité UTF-16 rattache les mots développés au texte original affiché : par exemple « vingt et un » peut rester rattaché à « 21 ». Les dates, décimaux et formes ambiguës sont conservés au lieu de subir une transformation hasardeuse. Les noms propres et contextes complexes doivent être testés ; aucun LLM ne réécrit le livre.

Ce n’est pas un moteur complet de rendu EPUB : styles CSS externes, mises en page fixes, images racontées, mathématiques, tableaux complexes et lecture multilingue automatique ne sont pas pris en charge. Un contenu de chapitre chiffré est refusé ; le projet ne contourne pas les DRM. N’importez que des livres que vous êtes autorisé à utiliser.

## Audio et données locales

L’implémentation comprend lecture/pause, passage précédent/suivant, sélection de chapitre, double toucher sur un paragraphe, vitesse, reprise au début du dernier passage et commandes média. `audio_service` et `audio_session` relient les commandes système et les interruptions. **Le fonctionnement en arrière-plan, sous verrouillage et après interruption téléphonique reste à valider sur de vrais appareils.**

La pause du moteur système est implémentée par arrêt/reprise à la dernière plage signalée ; le dernier mot peut être répété. La pause neuronale utilise la position du fichier audio. La progression affichée représente des passages du chapitre, pas une fausse durée totale en minutes. La prélecture ne prépare normalement qu’un passage d’avance. Stop/jump rendent les anciens résultats inutilisables, mais ne préemptent pas instantanément un calcul ONNX déjà lancé ; des changements rapides peuvent retarder la prochaine préparation.

Livres parsés, couvertures, positions, préférences et modèles restent dans le stockage privé de l’app. Le cache WAV est temporaire, avec éviction au-delà d’un objectif de **256 Mio**, hors fichier actif et opérations en cours. Les sauvegardes sont explicitement découragées/désactivées dans la configuration native, mais le comportement des sauvegardes/transferts propres à un appareil doit être vérifié. Le bouton de suppression d’un livre retire la copie de bibliothèque, pas le fichier original choisi dans Fichiers.

Les voix Android sont filtrées sur les métadonnées de disponibilité locale et d’absence d’exigence réseau. Cela ne constitue pas un audit d’un moteur TTS tiers installé par l’utilisateur. Aucun engagement réseau d’un moteur tiers ne peut être déduit de ses seules métadonnées.

## Structure

```text
lib/domain/           Livres, paramètres, normalisation et segmentation française
lib/data/             Import EPUB, stockage local, installation des modèles
lib/audio/            TTS système, Supertonic ONNX, CTC, worker, lecteur et média
lib/core/             Propriétaire unique des commandes de lecture et interruptions
lib/ui/               Design system, bibliothèque, lecteur, voix et réglages
packages/lisiere_native_tts/
                      Pont Dart ↔ Kotlin/Swift et événements de plages prononcées
assets/demo.epub      Livre original de démonstration, trois chapitres
test/                 20 tests Flutter rédigés ; non exécutés ici
tool/bootstrap.py     Génération et configuration des plateformes
tool/export_alignment.py
                      Export du checkpoint français en pack ONNX local
tool/test_tooling.py  7 tests Python hors ligne
docs/                 Architecture, design system, validation et sources
```

## Validation et limites de livraison

Exécuté ici : les **7 tests Python** des outils et du fichier de démonstration ; compilation syntaxique Python ; analyse syntaxique seule du fichier Swift. Un contrôle lexical complémentaire des délimiteurs Dart ne remplace pas l’analyseur Dart. Non exécuté : `flutter pub get`, `flutter analyze`, les **20 tests Flutter fournis**, compilation Android/iOS, export effectif du checkpoint, chargement ONNX, rendu UI, mesures vocales et tests sur appareil. Aucun résultat non exécuté n’est présenté comme réussi.

Le workflow CI inclus est une **configuration à exécuter**, pas une preuve de build passé. Résolvez et conservez `pubspec.lock` après le premier `flutter pub get`, puis fixez une version Flutter dans votre environnement de livraison. Examinez aussi les limites de taille EPUB, l’usage mémoire des bibliothèques volumineuses et les erreurs de dépendances sur votre environnement.

## Licences

Le code original de ce projet et le plugin local sont fournis sous MIT. Le texte de démonstration est original et réutilisable avec ce projet. Les dépendances, modèles et livres conservent leurs licences respectives.

**Les poids Supertonic 3 sont sous OpenRAIL-M ; leur code de référence est sous MIT.** Ne présentez pas les poids comme MIT et conservez leurs conditions/attributions lors d’une distribution. Le checkpoint CTC français par défaut annonce Apache-2.0 ; le pack embarque sa provenance et sa notice. Pour une distribution commerciale, examiner les licences effectives des versions retenues et les obligations applicables ; ce projet n’est pas une consultation juridique.

Voir `THIRD_PARTY_NOTICES.md` et `docs/SOURCES.md` pour les sources officielles consultées.
