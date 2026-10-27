#!/usr/bin/env bash
# Resolve and check the exact local candidate transaction before ISO composition.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="${BOOKOS_BUILD_ROOT:-$ROOT/.build}/package-check"
mkdir -p "$WORK"
python3 "$HERE/app-catalog.py" verify "$WORK/repo"
podman run --rm --name bookos-iso-package-check --security-opt label=disable \
    -v "$(dirname "$ROOT")":/sources:ro -v "$WORK":/work \
    -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
    registry.fedoraproject.org/fedora:44 bash -c '
        set -e
        dnf -y install git rpm-build librsvg2-tools pykickstart createrepo_c dnf5-plugins gettext unzip ImageMagick \
            cargo rust gcc-c++ pkgconf-pkg-config clang-devel \
            libinput-devel libdrm-devel libseat-devel mesa-libgbm-devel \
            pipewire-devel libxkbcommon-devel wayland-devel
        dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm
        python3 -m unittest discover -s /sources/BookOS-ISO/iso/tests -v
        bash /sources/BookOS-ISO/iso/check-packages.sh
    '
