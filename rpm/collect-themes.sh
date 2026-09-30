#!/usr/bin/env bash
# Build the BookOS theme source tarballs (Qt colors/Kvantum + GTK) into
# ~/rpmbuild/SOURCES.
#
#   bash collect-themes.sh [version]      (default 0.6)
set -euo pipefail

VERSION="${1:-0.6}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"          # …/BookOS
PLASMA_SRC="$ROOT/BookOS-Plasma-Theme"
GTK_SRC="$ROOT/BookOS-GTK-Theme"

USER_HOME="${SUDO_USER:+/home/$SUDO_USER}"; USER_HOME="${USER_HOME:-$HOME}"
SOURCES="${RPM_TOPDIR:-$USER_HOME/rpmbuild}/SOURCES"
mkdir -p "$SOURCES"
say(){ printf '  %s\n' "$*"; }

# ── Qt look: color-schemes + kvantum (sin tema de Plasma ni Aurorae) ────────
if [ -d "$PLASMA_SRC" ]; then
    STAGE="$(mktemp -d)/bookos-plasma-theme-${VERSION}"
    mkdir -p "$STAGE"
    for d in color-schemes kvantum; do
        [ -d "$PLASMA_SRC/$d" ] && cp -r "$PLASMA_SRC/$d" "$STAGE/"
    done
    # drop generator scripts so they don't ship
    find "$STAGE" -name '*.py' -delete
    OUT="$SOURCES/bookos-plasma-theme-${VERSION}.tar.gz"
    tar -C "$(dirname "$STAGE")" -czf "$OUT" "bookos-plasma-theme-${VERSION}"
    rm -rf "$(dirname "$STAGE")"
    say "plasma-theme: $OUT"
else
    echo "  ⚠ no existe $PLASMA_SRC" >&2
fi

# ── GTK theme: themes/BookOS-*-* ────────────────────────────────────────────
if [ -d "$GTK_SRC/themes" ]; then
    STAGE="$(mktemp -d)/bookos-gtk-theme-${VERSION}"
    mkdir -p "$STAGE/themes"
    cp -r "$GTK_SRC/themes/"* "$STAGE/themes/"
    OUT="$SOURCES/bookos-gtk-theme-${VERSION}.tar.gz"
    tar -C "$(dirname "$STAGE")" -czf "$OUT" "bookos-gtk-theme-${VERSION}"
    rm -rf "$(dirname "$STAGE")"
    say "gtk-theme: $OUT"
else
    echo "  ⚠ no existe $GTK_SRC/themes" >&2
fi

echo "[✓] Tarballs en $SOURCES. Build:"
echo "    rpmbuild -bb $(dirname "$0")/bookos-plasma-theme.spec"
echo "    rpmbuild -bb $(dirname "$0")/bookos-gtk-theme.spec"
