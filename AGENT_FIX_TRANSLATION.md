# Prompt de passation — correction/finition traduction EN→FR

Tu reprends le projet Flutter **Lisière**, un lecteur EPUB avec TTS local. Une première intégration de traduction locale anglais → français est déjà présente. Ne la remplace pas par une API cloud.

## Objectif

Rendre réellement fonctionnel le pipeline :

`EPUB anglais → traduction locale EN→FR → TTS français → lecture audio`, avec fonctionnement Android + iOS, cache local et interface Original / Français / Bilingue.

## Ce qui est déjà implémenté

- `TranslationMode { original, frenchAudio, bilingual }` persisté dans les réglages.
- Import sécurisé d’un bundle `lisiere-bergamot-en-fr-v1` dans `ModelStore`.
- `LocalTranslationEngine` avec cache SHA-256 et appel natif `translateEnFr`.
- `ReaderController` traduit chaque segment anglais avant TTS.
- Mode bilingue : affiche la traduction française du segment actif sous le texte anglais.
- Pendant une traduction, le suivi est volontairement limité à la phrase ; ne prétends pas avoir un mapping mot-à-mot FR↔EN.
- `tool/package_translation_bundle.py` produit le ZIP attendu à partir d’artefacts compatibles.

## À corriger / terminer en priorité

1. **Implémenter le runtime Bergamot/Marian natif** derrière `translateEnFr` dans :
   - `packages/lisiere_native_tts/android/.../LisiereNativeTtsPlugin.kt`
   - `packages/lisiere_native_tts/ios/Classes/LisiereNativeTtsPlugin.swift`
   Les stubs actuels retournent volontairement `BERGAMOT_NOT_LINKED`.
2. Ajouter les bindings C++/JNI/Objective-C++ nécessaires et les fichiers de build (Gradle/CMake/Podspec) sans dépendance cloud.
3. Charger le modèle une seule fois par `modelPath`, réutiliser tokenizer/session, exécuter la traduction hors du thread UI et libérer proprement les ressources.
4. Valider le contrat réel du modèle Bergamot choisi. Si ses artefacts ne correspondent pas à `model.bin` / `vocab.spm` / `lex.bin`, adapter **à la fois** le packager et le validateur `ModelStore`, sans affaiblir les contrôles d’intégrité.
5. Utiliser un modèle EN→FR quantifié réellement redistribuable et documenter sa **taille réelle sur disque**, RAM maximale et licence. Ne recopier aucun modèle sans vérifier les droits de redistribution.
6. Tester les cas : apostrophes, guillemets, nombres, noms propres, paragraphes longs, dialogues, accents, EPUB mal déclaré en langue, pause/reprise/changement de chapitre pendant une traduction.
7. Vérifier la concurrence : une traduction terminée après un `next`, `stop` ou changement de livre ne doit jamais être lue par erreur.
8. Ajouter prétraduction N+1/N+2 seulement après avoir rendu l’annulation/session correcte. Ne bloque jamais les commandes lecteur derrière une inférence longue.
9. En mode `original`, un EPUB anglais doit être lu avec une voix anglaise locale ou neuronale adaptée. Le plugin historique filtre aujourd’hui surtout les voix françaises : corriger ce point proprement.
10. Lancer `dart format`, `flutter analyze`, `flutter test`, puis compiler et tester Android/iOS sur appareils réels. Consigner ce qui a réellement été exécuté dans `docs/VALIDATION.md`.

## Contraintes de produit

- 100 % local après installation des modèles.
- Aucun texte du livre envoyé sur Internet.
- Pas de traduction factice, pas de fallback cloud silencieux.
- UI basée sur `adaptive_platform_ui` et design system existant.
- Préserver le texte source EPUB ; la traduction est une couche de lecture, pas une modification du livre.
- Si le modèle ne permet pas un suivi mot-à-mot fiable, conserver le suivi par phrase et l’indiquer honnêtement.

Commence par lire `docs/TRANSLATION_EN_FR.md`, `docs/ARCHITECTURE.md`, `lib/core/reader_controller.dart`, `lib/translation/local_translation_engine.dart` et `lib/data/model_store.dart`. Ensuite audite les changements existants avant d’écrire du code.
