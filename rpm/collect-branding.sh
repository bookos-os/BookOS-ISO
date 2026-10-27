#!/usr/bin/env bash
# Assembles bookos-branding-<version>.tar.gz from the scattered asset repos
# into the layout that bookos-branding.spec expects, then drops it in
# ~/rpmbuild/SOURCES so `rpmbuild -bb bookos-branding.spec` works.
#
# Usage:  ./collect-branding.sh [version]   (default 0.6)
set -euo pipefail

VERSION="${1:-0.6}"
# Repo root = two levels up from this script (…/BookOS/BookOS-ISO/rpm → …/BookOS)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGE="$(mktemp -d)/bookos-branding-${VERSION}"
mkdir -p "$STAGE"/{logos,wallpapers,sddm-theme,plymouth-theme,grub-theme,lockscreen,anaconda,fonts}

say(){ printf '  %s\n' "$*"; }
warn(){ printf '  ⚠ %s\n' "$*" >&2; }

echo "[*] Collecting branding assets (v${VERSION}) from $ROOT"

# ── Logos ───────────────────────────────────────────────────────────────
if [ -f "$ROOT/BookOS-Anaconda/pixmaps/bookos-logo.svg" ]; then
    cp "$ROOT/BookOS-Anaconda/pixmaps/bookos-logo.svg" "$STAGE/logos/bookos.svg"
    cp "$ROOT/BookOS-Anaconda/pixmaps/bookos-logo.svg" "$STAGE/logos/bookos-symbolic.svg"
    say "logos: bookos.svg + symbolic (from Anaconda pixmaps)"
else
    warn "no logo found — spec needs logos/bookos.svg, .png, -symbolic.svg"
fi
# PNG: rasterize if a tool exists, else warn (spec installs bookos.png)
if [ -f "$STAGE/logos/bookos.svg" ] && command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 256 -h 256 "$STAGE/logos/bookos.svg" -o "$STAGE/logos/bookos.png"
    say "logos: rasterized bookos.png"
else
    warn "bookos.png NOT generated (install librsvg2-tools or add it by hand)"
fi

# ── Wallpapers ──────────────────────────────────────────────────────────
# Pick the highest-versioned Wallpapers-* dir (was hardcoded to 1.0, but the
# repo ships Wallpapers-0.6); fall back to a bare Wallpapers/ if present.
WP_DIR="$(ls -d "$ROOT"/BookOS-Wallpapers/Wallpapers-* 2>/dev/null | sort -V | tail -n1)"
[ -d "$WP_DIR" ] || WP_DIR="$ROOT/BookOS-Wallpapers/Wallpapers"
if [ -d "$WP_DIR" ]; then
    cp -r "$WP_DIR/." "$STAGE/wallpapers/"
    say "wallpapers: copied Dark + Light (from $(basename "$WP_DIR"))"
else
    warn "no wallpapers dir found"
fi
# Extra wallpaper set (the blue/ember/pine/purple dark+light PNGs). Override the
# location with EXTRA_WALLPAPERS=/path. These get shipped alongside the repo set
# in /usr/share/backgrounds/bookos/ and are what the default desktop points at.
EXTRA_WP="${EXTRA_WALLPAPERS:-/home/evelyn/Descargas/Wallpapers}"
if [ -d "$EXTRA_WP" ] && compgen -G "$EXTRA_WP/*.png" >/dev/null; then
    cp -f "$EXTRA_WP"/*.png "$STAGE/wallpapers/"
    say "wallpapers: + $(ls "$EXTRA_WP"/*.png | wc -l) extra PNGs (from $EXTRA_WP)"
fi

# ── SDDM theme (login screen) ───────────────────────────────────────────
if [ -d "$ROOT/BookOS-SDDM/theme-sddm/bookos" ]; then
    cp -r "$ROOT/BookOS-SDDM/theme-sddm/bookos/." "$STAGE/sddm-theme/"
    say "sddm-theme: copied"
else
    warn "no SDDM theme found"
fi

# ── Lockscreen QML ──────────────────────────────────────────────────────
# bookos-branding es el ÚNICO dueño de /usr/share/bookos-settings/lockscreen/.
# bookos-settings los empaquetaba también, y en cuanto los dos dejaron de salir
# del mismo commit sus copias divergieron: rpm solo tolera un fichero duplicado
# si es byte a byte idéntico, así que la transacción entera de la ISO abortaba
# con "The transaction process has ended with errors".
EXTRA_QML="$ROOT/BookOS-Settings/src-tauri/extra"
if compgen -G "$EXTRA_QML/lockscreen/*.qml" >/dev/null; then
    cp "$EXTRA_QML"/lockscreen/*.qml "$STAGE/lockscreen/"
    say "lockscreen: copied QML"
else
    warn "no lockscreen QML found"
fi

# Los widgets (batería/tiempo/fecha) son EL MISMO componente que usa el tema
# SDDM, parametrizado por propiedades, y por eso viven en sddm-theme/ en vez de
# duplicarse en lockscreen/: dos copias divergen en cuanto se toca una.
# LockScreenUi.qml instancia GreeterWidgets{}, y QML resuelve los componentes por
# nombre de fichero DENTRO DEL MISMO DIRECTORIO — sin estos cuatro, el lockscreen
# no carga. Se aborta en vez de avisar: publicar un lockscreen que no arranca es
# peor que no publicar nada.
for w in GreeterWidgets WxIcon DeviceIcon GlyphIcon; do
    src="$EXTRA_QML/sddm-theme/$w.qml"
    [ -f "$src" ] || { warn "falta $src — el lockscreen no cargaría sin él"; exit 1; }
    cp -f "$src" "$STAGE/lockscreen/"
done
say "lockscreen: + widgets compartidos con el tema SDDM"

# ── Plymouth boot splash ────────────────────────────────────────────────
# NOTE: BookOS-Loading-System currently holds a Plasma *splash* (look-and-feel
# QML), which is NOT a Plymouth boot theme. A real Plymouth theme needs a
# bookos.plymouth + bookos.script + images. Until that exists, fall back to a
# minimal two-step theme so the boot doesn't show the Fedora logo.
if [ -f "$ROOT/BookOS-Loading-System/plymouth/bookos.plymouth" ]; then
    cp -r "$ROOT/BookOS-Loading-System/plymouth/." "$STAGE/plymouth-theme/"
    say "plymouth-theme: copied"
else
    warn "NO real Plymouth theme — generating a minimal fallback (logo on bg)"
    cat > "$STAGE/plymouth-theme/bookos.plymouth" <<EOF
[Plymouth Theme]
Name=BookOS
Description=BookOS boot splash
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/bookos
ScriptFile=/usr/share/plymouth/themes/bookos/bookos.script
EOF
    cat > "$STAGE/plymouth-theme/bookos.script" <<'EOF'
Window.SetBackgroundTopColor(0.04, 0.04, 0.05);
Window.SetBackgroundBottomColor(0.04, 0.04, 0.05);
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth()/2 - logo.image.GetWidth()/2);
logo.sprite.SetY(Window.GetHeight()/2 - logo.image.GetHeight()/2);
EOF
    [ -f "$STAGE/logos/bookos.png" ] && cp "$STAGE/logos/bookos.png" "$STAGE/plymouth-theme/logo.png" || true
fi

# ── Tema de GRUB (menú de arranque) ─────────────────────────────────────
# A diferencia del de Plymouth, aquí NO hay fallback generado: un theme.txt
# improvisado se ve peor que el texto plano de GRUB, y el post-script de
# Anaconda solo pone GRUB_THEME si el fichero existe. Sin BookOS-GRUB, el menú
# queda en texto —correcto, solo que sin diseño— y el %post --erroronfail del
# kickstart aborta el build de la ISO para que nadie lo publique sin querer.
if [ -f "$ROOT/BookOS-GRUB/theme.txt" ]; then
    cp -r "$ROOT/BookOS-GRUB/." "$STAGE/grub-theme/"
    # Los scripts generadores no pintan nada dentro del RPM.
    rm -f "$STAGE/grub-theme/build-assets.py" \
          "$STAGE/grub-theme/build-fonts.sh" \
          "$STAGE/grub-theme/README.md"
    rm -rf "$STAGE/grub-theme/.git"
    say "grub-theme: copied ($(find "$STAGE/grub-theme" -type f | wc -l) ficheros)"
else
    warn "NO hay tema de GRUB ($ROOT/BookOS-GRUB/theme.txt) — el menú de arranque saldrá en texto plano"
fi

# ── Fuentes (Nunito OFL, sustituye SN Pro) ──────────────────────────────
if [ -d "$ROOT/BookOS-Fonts" ]; then
    cp -r "$ROOT/BookOS-Fonts/." "$STAGE/fonts/"
    say "fonts: Nunito + alias fontconfig SN Pro"
fi

# ── Anaconda installer branding (pixmaps + WebUI CSS) ───────────────────
if [ -d "$ROOT/BookOS-Anaconda" ]; then
    [ -d "$ROOT/BookOS-Anaconda/pixmaps" ]   && cp -r "$ROOT/BookOS-Anaconda/pixmaps"   "$STAGE/anaconda/pixmaps"
    [ -d "$ROOT/BookOS-Anaconda/theme" ]     && cp -r "$ROOT/BookOS-Anaconda/theme"     "$STAGE/anaconda/theme"
    # product.d/bookos.conf drives the installer's btrfs default partitioning
    # AND the official WebUI stylesheet — without it Anaconda falls back to
    # ext4 + plain look.
    if [ -d "$ROOT/BookOS-Anaconda/product.d" ]; then
        cp -r "$ROOT/BookOS-Anaconda/product.d" "$STAGE/anaconda/product.d"
        # Anaconda uses [Product] for the visible installer name. Older
        # checkouts only had the profile/storage sections and inherited
        # "Fedora 44" from the base profile.
        profile="$STAGE/anaconda/product.d/bookos.conf"
        if ! grep -q '^product_name[[:space:]]*=[[:space:]]*BookOS$' "$profile"; then
            sed -i '1i\[Product]\nproduct_name = BookOS\n\n[Base Product]\nproduct_name = Fedora\n' "$profile"
        fi
    fi
    [ -d "$ROOT/BookOS-Anaconda/addon" ]     && cp -r "$ROOT/BookOS-Anaconda/addon"     "$STAGE/anaconda/addon"
    say "anaconda: pixmaps + theme CSS + product.d + addon"
else
    warn "no BookOS-Anaconda dir — installer keeps Fedora look"
fi

# ── Cockpit (administración web de la edición servidor) ─────────────────
# El CSS vive en BookOS-ISO; las imágenes salen del mismo logo que el resto.
# Sin favicon.ico propio, Cockpit serviría el de branding/fedora: busca cada
# fichero por ID y, si falta, por ID_LIKE.
mkdir -p "$STAGE/cockpit"
cp "$ROOT/BookOS-ISO/rpm/cockpit-branding/branding.css" "$STAGE/cockpit/"
if [ -f "$STAGE/logos/bookos.svg" ] && command -v rsvg-convert >/dev/null && command -v magick >/dev/null; then
    # El SVG deja medio lienzo de margen (el icono ocupa 96 de cada 192 px):
    # se recorta para que el logo llene la caja que le da el CSS.
    rsvg-convert -w 768 -h 768 "$STAGE/logos/bookos.svg" -o "$STAGE/cockpit/grande.png"
    magick "$STAGE/cockpit/grande.png" -trim +repage "$STAGE/cockpit/grande.png"
    magick "$STAGE/cockpit/grande.png" -resize 192x192 "$STAGE/cockpit/logo.png"
    magick "$STAGE/cockpit/grande.png" -resize 180x180 "$STAGE/cockpit/apple-touch-icon.png"
    magick "$STAGE/cockpit/grande.png" -define icon:auto-resize=64,32,16 "$STAGE/cockpit/favicon.ico"
    rm "$STAGE/cockpit/grande.png"
    say "cockpit: branding.css + logo, apple-touch-icon y favicon"
else
    warn "cockpit: faltan rsvg-convert o magick; el spec no encontrará logo.png ni favicon.ico"
fi

# ── Pack ────────────────────────────────────────────────────────────────
# Resolve the real user's home even under sudo, so the tarball lands where the
# non-root `rpmbuild` reads from (not /root/rpmbuild/SOURCES).
USER_HOME="${SUDO_USER:+/home/$SUDO_USER}"
OUT="${RPM_TOPDIR:-${USER_HOME:-$HOME}/rpmbuild}/SOURCES/bookos-branding-${VERSION}.tar.gz"
mkdir -p "$(dirname "$OUT")"
tar -C "$(dirname "$STAGE")" -czf "$OUT" "bookos-branding-${VERSION}"
rm -rf "$(dirname "$STAGE")"
echo "[✓] $OUT"
echo "    Build:  rpmbuild -bb $ROOT/BookOS-ISO/rpm/bookos-branding.spec"
