# Third-party notices

The root MIT license covers original project code, not third-party dependencies, model weights, or imported books. The original demonstration story is supplied for reuse with this project.

## Supertonic

The ONNX integration follows the public model contract and processing approach documented by Supertone in the Supertonic reference repository. Credit: Supertone / supertone-oss-archive. Reference code is offered under MIT. **Supertonic 3 model weights use OpenRAIL-M, not MIT.** No weights are embedded in this source archive. The optional installer retrieves the pinned official snapshot and retains its LICENSE and model card when supplied. Preserve and review the actual model terms when redistributing or deploying weights.

Sources: https://github.com/supertone-oss-archive/supertonic and https://huggingface.co/supertone-oss-archive/supertonic-3

## French CTC checkpoint

The optional exporter defaults to Jonatas Grosman's `wav2vec2-large-xlsr-53-french` checkpoint, whose model card declares Apache-2.0. No checkpoint is embedded here. The exporter records the actual resolved model revision and includes provenance and license information with the resulting pack. Review any alternative model's license independently.

Source: https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-french

## Flutter, native dependencies and Python tools

Dependencies retain their individual licenses. Flutter's LicensePage is exposed in Settings for dependency notices registered by the resolved build. It is not a substitute for model-license notices. The exporter dependencies are installed separately on the workstation. Generate and review a dependency/license inventory after resolving pub, Gradle, CocoaPods and Python dependencies, before distribution.

There are no bundled proprietary fonts, remote stock images, third-party books or third-party voice recordings in this source archive. App-store identity, signing information and publisher coordinates remain to be configured by the distributor.
