#!/usr/bin/env bash
# Vendor the Samsung Galaxy Book speaker-fix (MAX98390 HDA DKMS module) from
# Andycodeman/samsung-galaxy-book-linux-fixes into a source tarball that
# bookos-galaxybook-audio.spec consumes.
#
#   bash collect-galaxybook-fixes.sh [version]      (default 1.0)
#
# Env:
#   FIXES_SRC=/path   use a local checkout instead of cloning
#   FIXES_REF=main    branch/tag to clone
set -euo pipefail

VERSION="${1:-1.0}"
NAME="bookos-galaxybook-audio"
REF="${FIXES_REF:-main}"
REPO="https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes"

USER_HOME="${SUDO_USER:+/home/$SUDO_USER}"; USER_HOME="${USER_HOME:-$HOME}"
SOURCES="${RPM_TOPDIR:-$USER_HOME/rpmbuild}/SOURCES"
mkdir -p "$SOURCES"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${FIXES_SRC:-}" ]; then
    SRC="$FIXES_SRC"
    echo "→ Usando checkout local: $SRC"
else
    echo "→ Clonando $REPO ($REF)…"
    git clone --depth 1 --branch "$REF" "$REPO" "$TMP/repo"
    SRC="$TMP/repo"
fi

SPK="$SRC/speaker-fix"
[ -d "$SPK" ] || { echo "✗ no existe speaker-fix/ en $SRC"; exit 1; }

STAGE="$TMP/${NAME}-${VERSION}"
mkdir -p "$STAGE"
cp -a "$SPK/." "$STAGE/"
# Drop the upstream installer/uninstaller: the RPM owns install/enable, not them.
rm -f "$STAGE/install.sh" "$STAGE/uninstall.sh"

OUT="$SOURCES/${NAME}-${VERSION}.tar.gz"
tar -C "$TMP" -czf "$OUT" "${NAME}-${VERSION}"
echo "[✓] $OUT"
echo "    Build:  rpmbuild -bb $(cd "$(dirname "$0")" && pwd)/${NAME}.spec"
