#!/usr/bin/env python3
"""Export a local French CTC alignment pack for Lisiere, on a workstation.

The phone never needs Python. Downloads the source model only during export.
Requires substantial RAM/disk for the FP32 intermediate. No API key is needed
for the default public checkpoint. Neural inference/export was not run while
this project was authored: validate on French speech before distributing.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
import zipfile

DEFAULT_MODEL = "jonatasgrosman/wav2vec2-large-xlsr-53-french"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--revision", default="main", help="Tag or commit; resolved and recorded as an immutable commit")
    parser.add_argument("--output", type=Path, default=Path("alignment-fr.zip"))
    parser.add_argument("--validation-wav", type=Path, help="Recommended: a French mono 16 kHz speech recording")
    parser.add_argument("--validation-text", help="Reference text for --validation-wav; prints a character error rate")
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"Refusing to overwrite {args.output}; select another output path.")
    if args.validation_text and not args.validation_wav:
        parser.error("--validation-text requires --validation-wav")

    import numpy as np
    import onnx
    import onnxruntime as ort
    import torch
    from huggingface_hub import HfApi
    from onnxruntime.quantization import QuantType, quantize_dynamic
    from transformers import AutoModelForCTC, AutoProcessor

    info = HfApi().model_info(args.model, revision=args.revision)
    revision = info.sha
    if not revision:
        raise ValueError("Could not resolve the model's immutable revision")
    license_id = (info.card_data.to_dict() if info.card_data else {}).get("license", "unspecified")
    print(f"Source: {args.model} @ {revision} (declared license: {license_id})")
    processor = AutoProcessor.from_pretrained(args.model, revision=revision, trust_remote_code=False)
    model = AutoModelForCTC.from_pretrained(args.model, revision=revision,
        trust_remote_code=False, attn_implementation="eager").eval().cpu()
    if model.config.model_type != "wav2vec2":
        raise ValueError("This exporter supports Wav2Vec2ForCTC checkpoints only, not pretraining-only models")
    if processor.feature_extractor.sampling_rate != 16000:
        raise ValueError("Expected a 16 kHz feature extractor")
    vocab = processor.tokenizer.get_vocab()
    blank_id = model.config.pad_token_id
    if blank_id is None or blank_id not in vocab.values():
        raise ValueError("The CTC blank/pad token is missing")
    if len(set(vocab.values())) != len(vocab):
        raise ValueError("Unexpected aliased tokenizer vocabulary")
    stride = math.prod(model.config.conv_stride)
    delimiter = processor.tokenizer.word_delimiter_token
    if delimiter not in vocab:
        raise ValueError("The word delimiter is missing")
    # This checkpoint uses uppercase tokens. Detect rather than assuming all
    # French models share one case convention.
    uppercase = sum(chr(i) in vocab for i in range(ord("A"), ord("Z") + 1))
    lowercase = sum(chr(i) in vocab for i in range(ord("a"), ord("z") + 1)) > uppercase

    class Emissions(torch.nn.Module):
        def __init__(self, acoustic_model: torch.nn.Module):
            super().__init__()
            self.acoustic_model = acoustic_model

        def forward(self, input_values: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
            return self.acoustic_model(input_values=input_values,
                attention_mask=attention_mask, return_dict=False)[0]

    wrapper = Emissions(model)
    torch.manual_seed(42)
    example = torch.randn(1, 32000, dtype=torch.float32)
    mask = torch.ones_like(example, dtype=torch.int64)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lisiere-align-", dir=args.output.parent) as directory:
        work = Path(directory)
        fp32 = work / "intermediate.onnx"
        packed = work / "pack"
        packed.mkdir()
        print("Exporting ONNX emissions with dynamic audio length…")
        with torch.inference_mode():
            torch.onnx.export(wrapper, (example, mask), str(fp32), opset_version=17,
                input_names=["input_values", "attention_mask"], output_names=["logits"],
                dynamic_axes={"input_values": {1: "samples"}, "attention_mask": {1: "samples"},
                    "logits": {1: "frames"}}, do_constant_folding=True, dynamo=False)
        onnx.checker.check_model(str(fp32))
        # Avoid ConvInteger: mobile execution-provider coverage varies. Keeping
        # convolutions float32 and quantizing MatMul is the conservative choice.
        quantize_dynamic(str(fp32), str(packed / "model.onnx"),
            weight_type=QuantType.QInt8, op_types_to_quantize=["MatMul"], per_channel=True)
        onnx.checker.check_model(str(packed / "model.onnx"))
        session = ort.InferenceSession(str(packed / "model.onnx"), providers=["CPUExecutionProvider"])
        expected = {"input_values", "attention_mask"}
        if {i.name for i in session.get_inputs()} != expected:
            raise ValueError("The exported ONNX inputs do not match the app contract")
        # Check a different length too: a merely renamed static dimension is not enough.
        for size in [16000, 48000]:
            values = np.random.default_rng(42).normal(size=(1, size)).astype(np.float32)
            logits = session.run(["logits"], {"input_values": values,
                "attention_mask": np.ones((1, size), dtype=np.int64)})[0]
            if logits.ndim != 3 or logits.shape[0] != 1 or logits.shape[2] != model.config.vocab_size:
                raise ValueError(f"Unexpected logits shape: {logits.shape}")
            if not np.isfinite(logits).all():
                raise ValueError("Non-finite quantized-model output")
            with torch.inference_mode():
                reference = wrapper(torch.from_numpy(values), torch.ones((1, size), dtype=torch.int64)).numpy()
            if logits.shape != reference.shape:
                raise ValueError("Quantized and source model output lengths differ")
            print(f"{size} samples -> {logits.shape[1]} frames; quantization mean absolute difference: {np.mean(np.abs(logits-reference)):.4f}")
        validation = "shape-and-finiteness only; no recorded-speech acceptance test"
        if args.validation_wav:
            import soundfile as sf
            samples, rate = sf.read(args.validation_wav, dtype="float32")
            if rate != 16000 or samples.ndim != 1:
                raise ValueError("Validation WAV must be mono 16 kHz; resample it with an antialiasing filter first")
            if len(samples) > 55 * 16000:
                raise ValueError("Validation sample must be at most 55 seconds")
            inputs = processor(samples, sampling_rate=16000, return_tensors="np", padding=True)
            values = inputs.input_values.astype(np.float32)
            emissions = session.run(["logits"], {"input_values": values,
                "attention_mask": np.ones_like(values, dtype=np.int64)})[0]
            predicted = processor.batch_decode(np.argmax(emissions, axis=-1))[0]
            print(f"French validation transcription: {predicted}")
            validation = {"wavSha256": sha256_file(args.validation_wav), "transcript": predicted}
            if args.validation_text:
                reference = args.validation_text.upper() if not lowercase else args.validation_text.lower()
                cer = edit_distance(predicted, reference) / max(1, len(reference))
                print(f"Unnormalized character error rate: {cer:.3f}")
                validation["reference"] = reference
                validation["cerIncludingPunctuation"] = cer
        write_json(packed / "vocab.json", vocab)
        write_json(packed / "alignment.json", {
            "format": "lisiere-ctc-v1", "sampleRate": 16000, "strideSamples": stride,
            "blankId": blank_id, "wordDelimiter": delimiter, "lowercase": lowercase,
            "normalize": bool(processor.feature_extractor.do_normalize),
            "source": args.model, "revision": revision, "license": license_id,
            "quantization": "dynamic-int8-matmul-per-channel", "validation": validation,
        })
        # Preserve attribution in the pack. Review the upstream license and
        # notices before redistribution; this export does not relicense weights.
        license_text = ("Lisiere local alignment pack\n\n"
            f"Original model: {args.model}\nRevision: {revision}\n"
            f"Declared upstream license: {license_id}\n"
            f"Model card and source: https://huggingface.co/{args.model}/tree/{revision}\n"
            "Conversion: ONNX emission graph with dynamic INT8 MatMul weights.\n"
            "The original authors retain their rights. Model weights are not covered by Lisiere's source-code license.\n")
        if license_id == "apache-2.0":
            from urllib.request import urlopen
            with urlopen("https://www.apache.org/licenses/LICENSE-2.0.txt", timeout=30) as response:
                license_text += "\n" + response.read(50000).decode("utf-8")
        (packed / "LICENSE.txt").write_text(license_text, encoding="utf-8")
        names = ["model.onnx", "vocab.json", "alignment.json", "LICENSE.txt"]
        write_json(packed / "manifest.json", {"sha256": {name: sha256_file(packed / name) for name in names}})
        destination = args.output.with_suffix(args.output.suffix + ".part")
        try:
            with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_STORED) as archive:
                for name in names + ["manifest.json"]:
                    archive.write(packed / name, name)
            if destination.stat().st_size > 800 * 1024 * 1024:
                raise ValueError("Pack exceeds the app's 800 MiB import limit; do not distribute it")
            destination.replace(args.output)
        finally:
            destination.unlink(missing_ok=True)
    print(f"Created: {args.output.resolve()} ({args.output.stat().st_size / 1048576:.1f} MiB)")
    print("Import this ZIP in Lisiere > Voix > Neuronales > Synchronisation du texte.")
    return 0


def edit_distance(a: str, b: str) -> int:
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a):
        row = [i + 1]
        for j, y in enumerate(b):
            row.append(min(row[-1] + 1, previous[j + 1] + 1, previous[j] + (x != y)))
        previous = row
    return previous[-1]


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Export failed: {error}", file=sys.stderr)
        raise SystemExit(1)
