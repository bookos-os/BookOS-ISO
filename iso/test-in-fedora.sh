#!/usr/bin/env bash
# Build the visual RPMs and run packaging tests in an isolated Fedora root.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
mkdir -p "$ROOT/.build/visual-check"
podman run --rm --name bookos-visual-check --security-opt label=disable \
    -v "$(dirname "$ROOT")":/sources:ro -v "$ROOT/.build/visual-check":/work \
    registry.fedoraproject.org/fedora:44 bash -c '
        set -e
        dnf -y install rpm-build gettext unzip pykickstart
        python3 /sources/BookOS-ISO/iso/collect-visuals.py /sources /work/rpmbuild/SOURCES
        rpmbuild --define "_topdir /work/rpmbuild" -bb /sources/BookOS-ISO/rpm/bookos-icons.spec
        python3 -m unittest discover -s /sources/BookOS-ISO/iso/tests -v
    '
