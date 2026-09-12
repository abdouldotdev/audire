# Sources techniques consultées

Consultation : **11 septembre 2026**. Sources primaires : documentation des packages, fournisseurs de plateformes, dépôts et cartes de modèles. Le fait qu’une source documente une API ne prouve pas que cette intégration a été exécutée.

## Interface et exécution native

- Adaptive Platform UI, version retenue **0.1.111**, widgets et configuration de localisation : https://pub.dev/packages/adaptive_platform_ui
- API du package : https://pub.dev/documentation/adaptive_platform_ui/latest/
- Flutter ONNX Runtime, version retenue **1.8.5**, modèles locaux, sessions, contraintes iOS : https://pub.dev/packages/flutter_onnxruntime
- `OrtValue` et tenseurs : https://pub.dev/documentation/flutter_onnxruntime/latest/flutter_onnxruntime/OrtValue-class.html
- Audio Service, configuration de fond et commandes média : https://pub.dev/packages/audio_service
- Audio Session, focus et interruptions : https://pub.dev/packages/audio_session
- Just Audio, lecture locale et position média : https://pub.dev/packages/just_audio
- Android, callbacks TTS dont `onRangeStart` : https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener
- Android, propriétés d’une voix : https://developer.android.com/reference/android/speech/tts/Voice
- Apple, plage de parole : https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:willspeakrangeofspeechstring:utterance:)

## Voix neuronale

- Dépôt de référence Supertonic : https://github.com/supertone-oss-archive/supertonic
- Implémentation Flutter de référence, contrat des modèles et prétraitement : https://raw.githubusercontent.com/supertone-oss-archive/supertonic/main/flutter/lib/helper.dart
- Carte du modèle Supertonic 3, français et autres langues, exécution locale et licences : https://huggingface.co/supertone-oss-archive/supertonic-3
- Arborescence et volume du dépôt : https://huggingface.co/supertone-oss-archive/supertonic-3/tree/main
- Révision fixée dans le code : `aafc6e32416a594460b32413efc49d7fe4ce6d46`.
- Licence des poids : fichier `LICENSE` du snapshot ; carte distinguant poids **OpenRAIL-M** et code **MIT**. Voir aussi https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE

## Alignement

- Checkpoint français entraîné pour CTC, fréquence 16 kHz et licence Apache-2.0 : https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-french
- Tutoriel officiel PyTorch d’alignement CTC : https://docs.pytorch.org/audio/stable/tutorials/ctc_forced_alignment_api_tutorial.html

Le tutoriel CTC sert de référence conceptuelle. Le projet n’appelle pas l’ancienne API `torchaudio.functional.forced_align` : l’alignement Viterbi est implémenté en Dart et le script d’export utilise Transformers/ONNX. La disponibilité historique d’une API ne doit pas être confondue avec sa disponibilité dans une version actuelle.

## EPUB et traitement de données

- Archive, API ZIP : https://pub.dev/packages/archive
- XML : https://pub.dev/packages/xml
- HTML : https://pub.dev/packages/html
- Normalisation Unicode : https://pub.dev/packages/unorm_dart

Les dépendances transitives seront résolues par le premier `flutter pub get`. Les URLs `latest` peuvent évoluer : conserver le lockfile et consulter la documentation de la version effectivement résolue lors de la validation.
