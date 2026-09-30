#!/usr/bin/env bash
# Resolve and check the exact local candidate transaction before ISO composition.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
mkdir -p "$ROOT/.build/package-check"
python3 "$HERE/app-catalog.py" verify "$ROOT/.build/package-check/repo"
podman run --rm --name bookos-iso-package-check --security-opt label=disable \
    -v "$(dirname "$ROOT")":/sources:ro -v "$ROOT/.build/package-check":/work \
    registry.fedoraproject.org/fedora:44 bash -c '
        set -e
        dnf -y install git rpm-build librsvg2-tools pykickstart createrepo_c dnf5-plugins gettext unzip \
            cargo rust gcc-c++ pkgconf-pkg-config clang-devel \
            libinput-devel libdrm-devel libseat-devel mesa-libgbm-devel \
            pipewire-devel libxkbcommon-devel wayland-devel
        bash /sources/BookOS-ISO/iso/check-packages.sh
    '
