#!/usr/bin/env python3
"""Collect shipped icon packs without reading the host desktop."""
from pathlib import Path
import re
import sys
import tarfile

root, sources = map(Path, sys.argv[1:])
project = root / 'BookOS-ISO'
sources.mkdir(parents=True, exist_ok=True)
version = re.search(r'^Version:\s+(\S+)', (project / 'rpm/bookos-icons.spec').read_text(), re.M)[1]
with tarfile.open(sources / f'bookos-icons-{version}.tar.gz', 'w:gz') as archive:
    for variant in ('Dark', 'Light', 'Tinted-Dark', 'Tinted-Light'):
        pack = root / 'Icons' / f'BookOS-Icon-Pack-{variant}'
        if not (pack / 'index.theme').is_file():
            raise SystemExit(f'Missing icon pack: {pack}')
        archive.add(pack, arcname=f'bookos-icons-{version}/{pack.name}')
