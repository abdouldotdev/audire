#!/usr/bin/env python3
"""Build a Lisière EN→FR local translation bundle.

This does not convert a Bergamot/Marian model. It packages already compatible
native runtime artifacts into the strict archive contract consumed by the app.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True, type=Path, help='Bergamot/Marian native model blob')
    ap.add_argument('--vocab', required=True, type=Path, help='SentencePiece vocabulary/model')
    ap.add_argument('--lex', type=Path, help='Optional lexical shortlist blob')
    ap.add_argument('--license', dest='license_file', type=Path)
    ap.add_argument('--revision', default='local')
    ap.add_argument('--output', type=Path, default=Path('translation-en-fr.zip'))
    args = ap.parse_args()

    files = {'model.bin': args.model, 'vocab.spm': args.vocab}
    if args.lex:
        files['lex.bin'] = args.lex
    if args.license_file:
        files['LICENSE.txt'] = args.license_file
    for name, path in files.items():
        if not path.is_file():
            raise SystemExit(f'{name}: fichier introuvable: {path}')

    config = {
        'format': 'lisiere-bergamot-en-fr-v1',
        'source': 'en',
        'target': 'fr',
        'runtime': 'bergamot-native',
    }
    hashes = {name: digest(path) for name, path in files.items()}
    config_bytes = json.dumps(config, ensure_ascii=False, indent=2).encode()
    hashes['config.json'] = hashlib.sha256(config_bytes).hexdigest()
    manifest = {'revision': args.revision, 'sha256': hashes}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.output, 'w', compression=ZIP_DEFLATED) as z:
        for name, path in files.items():
            z.write(path, name)
        z.writestr('config.json', config_bytes)
        z.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2).encode())
    print(args.output)


if __name__ == '__main__':
    main()
