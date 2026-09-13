# Third-party notices

The root MIT license covers original project code, not third-party dependencies, model weights, or imported books. The original demonstration story is supplied for reuse with this project.

## Supertonic

The ONNX integration follows the public model contract and processing approach documented by Supertone in the Supertonic reference repository. Credit: Supertone / supertone-oss-archive. Reference code is offered under MIT. **Supertonic 3 model weights use OpenRAIL-M, not MIT.** No weights are embedded in this source archive. The optional installer retrieves the pinned official snapshot and retains its LICENSE and model card when supplied. Preserve and review the actual model terms when redistributing or deploying weights.

Sources: https://github.com/supertone-oss-archive/supertonic and https://huggingface.co/supertone-oss-archive/supertonic-3

## Kokoro 82M

Le moteur anglais optionnel utilise le modèle ONNX Kokoro 82M publié sous licence Apache-2.0. Les poids ne sont pas intégrés à l’application : le téléchargement facultatif récupère une révision épinglée, vérifie chaque fichier et sélectionne réellement Kokoro comme moteur anglais. La conversion graphème-phonème utilise le package Dart `phonemize`, sous licence MIT.

Sources: https://huggingface.co/onnx-community/Kokoro-82M-ONNX et https://pub.dev/packages/phonemize

## Qwen Studio

Le moteur lourd optionnel utilise Qwen3-TTS 0.6B CustomVoice quantifié en 4 bits. Les poids, proposés sous licence MIT par AtomGradient, ne sont pas inclus dans le binaire : Audire télécharge une révision épinglée, vérifie les empreintes SHA-256 puis effectue une synthèse locale avant activation. L’exécution iOS repose sur `mlx-audio-swift` sous licence MIT et sur MLX Swift d’Apple sous licence MIT. Qwen Studio est réservé aux appareils iOS récents disposant d’au moins 6 Go de mémoire.

Sources: https://huggingface.co/AtomGradient/Qwen3-TTS-0.6B-CustomVoice-4bit-pruned-vocab-lite, https://github.com/Blaizzy/mlx-audio-swift et https://github.com/ml-explore/mlx-swift

## French CTC checkpoint

The optional exporter defaults to Jonatas Grosman's `wav2vec2-large-xlsr-53-french` checkpoint, whose model card declares Apache-2.0. No checkpoint is embedded here. The exporter records the actual resolved model revision and includes provenance and license information with the resulting pack. Review any alternative model's license independently.

Source: https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-french

## Flutter, native dependencies and Python tools

Le support PDF utilise `pdfrx` sous licence MIT et le moteur PDFium sous licence Apache-2.0/BSD-style avec ses dépendances. Les binaires PDFium sont embarqués dans l’application pour l’extraction locale du texte et le rendu de la couverture. Conserver les notices fournies par ces distributions lors de la publication.

L’OCR des pages scannées utilise Vision, fourni par iOS, et le modèle latin embarqué de ML Kit Text Recognition sur Android. Vérifier les notices Google ML Kit et les obligations de distribution de la version Gradle résolue avant publication.

Dependencies retain their individual licenses. Flutter's LicensePage is exposed in Settings for dependency notices registered by the resolved build. It is not a substitute for model-license notices. The exporter dependencies are installed separately on the workstation. Generate and review a dependency/license inventory after resolving pub, Gradle, CocoaPods and Python dependencies, before distribution.

There are no bundled proprietary fonts, remote stock images, third-party books or third-party voice recordings in this source archive. App-store identity, signing information and publisher coordinates remain to be configured by the distributor.
