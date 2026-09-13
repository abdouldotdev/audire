# Traduction locale anglais → français

## État de l’intégration

Le pipeline Flutter est intégré : mode Original / Français / Bilingue, cache local, import d’un bundle signé par empreintes SHA-256, traduction juste avant synthèse et affichage de la traduction du passage courant en mode bilingue.

Le runtime natif Bergamot/Marian **n’est pas lié dans cette livraison**. Les méthodes Android/iOS retournent volontairement `BERGAMOT_NOT_LINKED` au lieu de simuler une traduction. Le point d’entrée à implémenter est `translateEnFr` sur le channel `lisiere/native_tts`.

## Contrat du bundle

Archive ZIP plate, format `lisiere-bergamot-en-fr-v1` :

- `model.bin` — poids compatibles avec le runtime natif choisi ;
- `vocab.spm` — modèle/vocabulaire SentencePiece ;
- `lex.bin` — shortlist lexicale optionnelle ;
- `config.json` — source `en`, cible `fr`, runtime `bergamot-native` ;
- `manifest.json` — révision + SHA-256 de chaque fichier hors manifeste ;
- `LICENSE.txt` — optionnel mais recommandé.

Le ZIP est refusé au-delà de 250 Mio et l’extraction refuse chemins, liens symboliques, doublons et fichiers inattendus.

`tool/package_translation_bundle.py` construit ce format à partir d’artefacts déjà compatibles avec Bergamot. Il ne convertit pas un checkpoint Hugging Face.

## Pipeline

```text
EPUB anglais
   ↓
SpeechSegment anglais
   ↓
LocalTranslationEngine
   ├─ cache SHA-256 (révision + texte)
   └─ channel natif translateEnFr
   ↓
texte français
   ↓
FrenchNarration.normalize
   ↓
TTS français
```

La traduction est calculée par passage au moment de la lecture. Le cache permet une reprise immédiate sur les passages déjà traduits.

## Synchronisation

La traduction détruit l’identité caractère-à-caractère avec le texte source anglais. En conséquence, Audire force volontairement `SyncQuality.sentence` pendant une lecture traduite. Le texte anglais est surligné par phrase entière. En mode bilingue, la traduction française du passage actif est affichée sous l’anglais.

Pour obtenir un vrai suivi mot-à-mot en français, il faudra afficher une vue française complète avec ses propres offsets, et non mapper artificiellement les mots français sur l’anglais.

## Travail natif restant

1. Lier Bergamot translator ou un runtime Marian équivalent sur Android (CMake/JNI) et iOS (C++/Objective-C++/Swift bridge).
2. Charger `model.bin`, `vocab.spm` et `lex.bin` depuis `modelPath` une seule fois et réutiliser la session.
3. Implémenter `translateEnFr(text, modelPath)` hors du thread UI.
4. Borner longueur/temps/mémoire, gérer UTF-8 et annulation.
5. Tester sur vrais appareils avec plusieurs tailles de modèles quantifiés.
6. Confirmer licences et redistribution du modèle choisi avant de l’embarquer dans l’application.
