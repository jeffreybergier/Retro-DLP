#!/usr/bin/env python3
"""Provision pinned EJS build inputs before offline builds and tests."""
import hashlib
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
version = re.search(r'#define RDLP_EJS_ASSET_VERSION "([0-9.]+)"',
                    (ROOT / 'source/library/shared/include/retrodlp/assets.h').read_text()).group(1)
manifest = (ROOT / 'source/library/shared/rdlp_ejs_manifest.c').read_text()
assets = re.findall(r'\{"([^"/]+)",\s*"(https://[^"\s]+)"\s*'
                    r'RDLP_EJS_ASSET_VERSION "/"\s*"([^"/]+)",\s*'
                    r'(\d+)U,\s*"([0-9a-f]{64})"\}', manifest)
if len(assets) != 2:
    raise SystemExit('Expected exactly two pinned EJS assets')
destination = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'build/generated/ejs'
destination.mkdir(parents=True, exist_ok=True)
for filename, base_url, remote_name, size, digest in assets:
    target = destination / filename
    data = target.read_bytes() if target.exists() else b''
    if len(data) != int(size) or hashlib.sha256(data).hexdigest() != digest:
        with urllib.request.urlopen(base_url + version + '/' + remote_name, timeout=60) as response:
            data = response.read(int(size) + 1)
        if len(data) != int(size) or hashlib.sha256(data).hexdigest() != digest:
            raise SystemExit('Pinned EJS size/hash mismatch: ' + filename)
        temporary = target.with_suffix('.part')
        temporary.write_bytes(data)
        temporary.replace(target)
    target.chmod(0o644)
    print('Verified EJS ' + version + ': ' + filename)
