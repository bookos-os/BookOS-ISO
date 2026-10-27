#!/usr/bin/env bash
# Build current app sources against Fedora 44, without modifying sibling repos.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SOURCES="$(dirname "$ROOT")"
WORK="${APP_WORK:-${BOOKOS_BUILD_ROOT:-$ROOT/.build}/apps}"
mkdir -p "$WORK"
nombre=bookos-app-build-0.7.1
if podman container exists "$nombre"; then
    estado=$(podman inspect --format '{{.State.Status}}' "$nombre")
    case "$estado" in
        exited|created|configured) podman rm "$nombre" >/dev/null ;;
        *)
            echo "Ya hay una compilación de aplicaciones en curso (estado: $estado)." >&2
            echo "Continúa en la terminal original. Para ver el registro: podman logs -f $nombre" >&2
            exit 1
            ;;
    esac
fi
podman run --rm --name "$nombre" --security-opt label=disable \
    -v "$SOURCES":/sources:ro -v "$WORK":/work \
    -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
    registry.fedoraproject.org/fedora:44 \
    bash /sources/BookOS-ISO/iso/build-apps-fedora.sh "$@"
# Only import after every app succeeds and the manifest has been verified.
python3 "$HERE/app-catalog.py" verify "$WORK/repo"
DEST="${BOOKOS_BUILD_ROOT:-$ROOT/.build}/package-check/repo"
mkdir -p "$DEST"
python3 - "$WORK/repo" "$DEST" <<'PY'
import json, shutil, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:])
entries = json.loads((src / 'bookos-apps.json').read_text())
for entry in entries:
    # Delete only artifacts previously recorded by this builder.
    old_manifest = dst / 'bookos-apps.json'
    if old_manifest.exists():
        for old in json.loads(old_manifest.read_text()):
            if old['name'] == entry['name'] and Path(old['file']).name == old['file']:
                (dst / old['file']).unlink(missing_ok=True)
    shutil.copy2(src / entry['file'], dst / entry['file'])
shutil.copy2(src / 'bookos-apps.json', dst / 'bookos-apps.json')
shutil.copy2(src / 'bookos-fuentes.json', dst / 'bookos-fuentes.json')
PY
printf 'Fresh application RPMs: %s\n' "$DEST"
