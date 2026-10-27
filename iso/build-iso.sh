#!/usr/bin/env bash
# BookOS ISO builder.
#
# Usage:
#   sudo bash build-iso.sh <os-name> <dev|beta|stable> <version> [outdir] [allapps:S/N]
#
# Examples:
#   sudo bash build-iso.sh BookOS dev 0.6.2
#   sudo bash build-iso.sh BookOS stable 1.0 ~/isos S
#   sudo bash build-iso.sh "BookOS Lite" beta 0.6.2-rc.1 /var/isos N
#
# Optional env overrides:
#   RELEASEVER=44                       Fedora base release (default 44)
#   EDITION=completa|minima|servidor    qué lleva la imagen (default completa);
#                                       ver iso/edicion-*.ks
#   APPS="bookos-player bookos-viewer"  explicit optional-app list (implies allapps=S)
#   SIGN=auto|0|1                       auto: sign if key exists; 1: require signing
#   WORKDIR=/var/tmp/...                build scratch dir
set -euo pipefail

# ── Args ────────────────────────────────────────────────────────────────
OS_NAME="${1:-}"
CHANNEL="${2:-}"
VERSION="${3:-}"
OUTDIR="${4:-$PWD}"
ALLAPPS="${5:-N}"

usage() {
    echo "Usage: sudo bash $0 <os-name> <dev|beta|stable> <version> [outdir] [allapps:S/N]"
    echo "  e.g. sudo bash $0 BookOS dev 0.6.2 ~/isos S"
    exit 1
}
[ -z "$OS_NAME" ] || [ -z "$CHANNEL" ] || [ -z "$VERSION" ] && usage
case "$CHANNEL" in stable|beta|dev) ;; *) echo "✗ canal inválido: '$CHANNEL' (usa dev|beta|stable)"; exit 1;; esac
case "$ALLAPPS" in S|s|Y|y|N|n) ;; *) echo "✗ allapps debe ser S o N"; exit 1;; esac
EDITION="${EDITION:-completa}"
case "$EDITION" in completa|minima|servidor) ;; *) echo "✗ edición inválida: '$EDITION' (usa completa|minima|servidor)"; exit 1;; esac
[ "$(id -u)" = "0" ] || { echo "✗ debe ejecutarse como root (lorax lo necesita)"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASEVER="${RELEASEVER:-44}"
WORKDIR="${WORKDIR:-/var/tmp/bookos-iso-${CHANNEL}}"

# ── Live-ISO kernel cmdline ────────────────────────────────────────────────
# Injected into the live boot menu via lmc --extra-boot-args (fills the lorax
# @EXTRA@ placeholder in BOTH the BIOS and EFI grub.cfg). NO ISO remaster, so
# the appended GPT/ESP partition stays intact.
#
# Generic images must use the kernel defaults on physical and virtual hardware.
# Machine-specific workarounds are opt-in through EXTRA_BOOT_ARGS="...".
# An explicitly empty value must also produce a generic boot command line.
EXTRA_BOOT_ARGS="${EXTRA_BOOT_ARGS:-}"

# ── Optional app set ──────────────────────────────────────────────────────
# "all apps" pulls the full BookOS app catalog on top of the core meta set.
# Override the list with APPS="...". Empty when allapps=N.
DEFAULT_OPTIONAL_APPS="bookos-viewer bookos-voicerecorder"
if [ -n "${APPS:-}" ]; then
    OPTIONAL_APPS="$APPS"
elif [ "$ALLAPPS" = "S" ] || [ "$ALLAPPS" = "s" ] || [ "$ALLAPPS" = "Y" ] || [ "$ALLAPPS" = "y" ]; then
    OPTIONAL_APPS="$DEFAULT_OPTIONAL_APPS"
else
    OPTIONAL_APPS=""
fi
# Newline-separate for the kickstart %packages section
OPTIONAL_APPS_KS="$(printf '%s\n' $OPTIONAL_APPS)"

# ── Tooling check ─────────────────────────────────────────────────────────
command -v livemedia-creator >/dev/null || { echo "✗ falta lorax: sudo dnf install lorax-lmc-novirt"; exit 1; }
# Anaconda calls this in the compose container as well as in the target.
command -v load_policy >/dev/null || { echo "✗ falta policycoreutils en el entorno de construcción"; exit 1; }

mkdir -p "$WORKDIR" "$WORKDIR/logs" "$WORKDIR/tmp" "$OUTDIR"
rm -rf "$WORKDIR"/results 2>/dev/null || true

# ── Materialize kickstart ──────────────────────────────────────────────────
# Markers live in bookos-base.ks (pulled in via %include), so we MUST flatten
# first and substitute on the merged result — otherwise the base's
# __BOOKOS_*__ placeholders would never be replaced.
KS_IN="$SCRIPT_DIR/bookos-$CHANNEL.ks"
[ -f "$KS_IN" ] || { echo "✗ no existe el kickstart: $KS_IN"; exit 1; }

# The same renderer is used by offline validation and production builds.
read -ra OPTIONAL_APP_ARRAY <<< "$OPTIONAL_APPS"
python3 "$SCRIPT_DIR/profile.py" --channel "$CHANNEL" --name "$OS_NAME" \
    --version "$VERSION" --release "$RELEASEVER" --edition "$EDITION" --apps "${OPTIONAL_APP_ARRAY[@]}" \
    > "$WORKDIR/bookos-flat.ks"

# ── Optional: LOCAL bookos repo ─────────────────────────────────────────────
# Test freshly-built RPMs without publishing to bookos.es. Point the build-time
# `repo --name=bookos` line at a local createrepo_c'd dir:
#   createrepo_c /path/to/rpms && BOOKOS_LOCAL_REPO=/path/to/rpms bash build-iso.sh …
# Local applications are mandatory and verified against the build manifest.
# Remote app packages are excluded so newer server versions cannot replace them.
if [ -n "${BOOKOS_LOCAL_REPO:-}" ]; then
    [ -f "$BOOKOS_LOCAL_REPO/repodata/repomd.xml" ] \
        || { echo "✗ $BOOKOS_LOCAL_REPO no es un repo (falta repodata/). Corre: createrepo_c $BOOKOS_LOCAL_REPO"; exit 1; }
    python3 "$SCRIPT_DIR/app-catalog.py" verify "$BOOKOS_LOCAL_REPO"
    python3 "$SCRIPT_DIR/app-catalog.py" pin "$BOOKOS_LOCAL_REPO" "$WORKDIR/bookos-flat.ks"
    echo "[i] Repo bookos LOCAL: file://$BOOKOS_LOCAL_REPO"
    sed -i -E "s#(repo --name=bookos )--baseurl=[^ ]+#\1--baseurl=file://$BOOKOS_LOCAL_REPO#" "$WORKDIR/bookos-flat.ks"
    # En modo LOCAL el repo local trae TODO lo de BookOS. El de apps del
    # servidor sobra, y si el servidor no tiene repo (vaciado el 2026-09-24,
    # 404) anaconda aborta entera con «Error al configurar los repositorios».
    # Contrapartida: las apps opcionales (ALLAPPS=S) tienen que estar también
    # en el repo local.
    sed -i '/^repo --name=bookos-apps /d' "$WORKDIR/bookos-flat.ks"
fi

# ── Plantillas de lorax parcheadas ─────────────────────────────────────────
# DOS cosas del menú de arranque del USB salen de aquí y no se pueden arreglar
# después:
#
#   1. EL TÍTULO. Las plantillas traen `menuentry 'Start @PRODUCT@ @VERSION@'`
#      y lorax sustituye @VERSION@ por product.version, que es lo que se pasa en
#      --releasever → «Start BookOS 44». Y --releasever NO se puede cambiar: es
#      el $releasever con el que dnf resuelve los repos de Fedora durante el
#      build; ponerle 0.6.1 da 404 en todo. Se quita @VERSION@ del todo: el
#      menú dice «Start BookOS» a secas (decisión de producto, 2026-09-11; la
#      versión ya va en el nombre del fichero .iso).
#
#      Antes esto se parcheaba remasterizando la ISO ya construida. NO FUNCIONA
#      en UEFI, que es como arranca cualquier portátil moderno desde un pendrive:
#      el firmware no lee el árbol ISO9660, monta la PARTICIÓN ESP ANEXADA
#      (images/efiboot.img, que efi.tmpl construye con mkefiboot ANTES de armar
#      la ISO) y GRUB lee el grub.cfg de dentro de esa imagen FAT. El remaster
#      reescribía las copias ISO9660 y dejaba la de la ESP intacta → BIOS decía
#      «BookOS 0.6.1» y UEFI seguía diciendo «BookOS 44». Reportado con un
#      pendrive real. Parchear la plantilla arregla las dos de una vez, porque
#      las dos salen del mismo fichero.
#
#   2. EL TEMA GRÁFICO. El menú del USB usaba el texto plano de GRUB mientras
#      que el del sistema instalado (GRUB_THEME, ver bookos-base.ks) sale con la
#      identidad de BookOS.
#
# NO se forkea el árbol de plantillas: se COPIA el de la lorax que haya
# instalada y se le aplica un parche mínimo. Así una actualización de lorax se
# hereda sola, y si algún día cambian los marcadores el build aborta en vez de
# producir una ISO mal etiquetada en silencio.
# `--lorax-templates` tiene que apuntar al árbol que contiene `live/` directo:
# make_livecd() de pylorax hace joinpaths(tpl, "live/config_files") a pelo, sin
# pasar por find_templates(). En Fedora ese árbol es …/templates.d/99-generic,
# NO …/templates.d — copiar el envoltorio dejaba `live/` un nivel más abajo y el
# build moría en `cp -a …/live/config_files/. …/tmp/config_files` (estado 1).
# Se replica la elección de find_templates(): subdirectorio de número más bajo
# dentro de templates.d/, o el propio dir si no hay templates.d/.
LORAX_TPL_SRC="${LORAX_TPL_SRC:-/usr/share/lorax}"
LORAX_TPL="$WORKDIR/lorax-templates"
LORAX_TPL_SET="$LORAX_TPL_SRC"
if [ -d "$LORAX_TPL_SRC/templates.d" ]; then
    for _d in "$LORAX_TPL_SRC"/templates.d/*/; do
        [ -d "$_d" ] || continue
        LORAX_TPL_SET="${_d%/}"
        break
    done
fi
[ -d "$LORAX_TPL_SET/live" ] || { echo "✗ no encuentro el árbol de plantillas de lorax ('$LORAX_TPL_SET/live')"; exit 1; }
rm -rf "$LORAX_TPL"
cp -a "$LORAX_TPL_SET" "$LORAX_TPL"

# 1) Título. Se deja @PRODUCT@ (lorax lo sustituye por --project) y se borra
#    @VERSION@. El `replace @VERSION@` posterior de lorax pasa a ser un no-op.
_patched=0
for _cfg in "$LORAX_TPL"/live/config_files/x86/grub2-bios.cfg \
            "$LORAX_TPL"/live/config_files/x86/grub2-efi.cfg; do
    [ -f "$_cfg" ] || continue
    grep -q '@PRODUCT@ @VERSION@' "$_cfg" || continue
    sed -i "s|@PRODUCT@ @VERSION@|@PRODUCT@|g" "$_cfg"
    # La clase de menuentry es lo que decide el icono del tema: `fedora` no
    # existe en el tema de BookOS, `bookos` sí (y casa con el grub_class que
    # bookos-apply-identity escribe en el sistema instalado).
    sed -i "s|--class fedora|--class bookos|g" "$_cfg"
    _patched=$((_patched + 1))
done
[ "$_patched" -ge 2 ] || {
    echo "✗ no pude parchear el título en las plantillas de lorax (parcheadas: $_patched, esperadas: 2)."
    echo "  ¿Cambió el formato de config_files/x86/grub2-*.cfg en esta versión de lorax?"
    echo "  Sin esto el menú del USB diría '$OS_NAME $RELEASEVER'. Abortando."
    exit 1
}

# 2) Tema gráfico en el menú del USB.
#
#    El tema vive en el rootfs del live (lo instala bookos-branding en
#    /boot/grub2/themes/bookos) y x86.tmpl ya injerta TODO ${GRUB2DIR} en la
#    ISO, así que basta con copiarlo ahí dentro: no hay que tocar los
#    graft-points ni engordar efiboot.img.
#
#    Las dos configs lo referencian como ($root)/boot/grub2/themes/… DESPUÉS de
#    la línea `search --set=root -l @ISOLABEL@`: en ese punto $root es el volumen
#    ISO9660 tanto en BIOS como en UEFI, así que la misma ruta vale para los dos
#    caminos. Las fuentes hay que cargarlas a mano con loadfont — el theme.txt
#    las nombra pero no las carga (en el sistema instalado eso lo hace solo
#    grub2-mkconfig a partir de GRUB_THEME).
for _tmpl in "$LORAX_TPL"/live/x86.tmpl; do
    [ -f "$_tmpl" ] || continue
    grep -q 'themes/bookos' "$_tmpl" && continue
    python3 - "$_tmpl" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "mkdir ${GRUB2DIR}\n"
## `runcmd cp -a` y no `install`: el `install` de lorax es un shutil.copy2 por
## fichero (pylorax/sysutils.py) y revienta con directorios, y el tema tiene
## icons/. Con cp -a tampoco hay que tocar esto al anadir ficheros.
add = anchor + """
## BookOS: tema grafico del menu de arranque (viene de bookos-branding).
%if exists("boot/grub2/themes/bookos/theme.txt"):
    mkdir ${GRUB2DIR}/themes
    runcmd cp -a ${inroot}/boot/grub2/themes/bookos ${outroot}/${GRUB2DIR}/themes/
%endif
"""
assert s.count(anchor) == 1, f"ancla 'mkdir ${{GRUB2DIR}}' encontrada {s.count(anchor)} veces"
open(p, "w").write(s.replace(anchor, add))
PY
done

_THEME_PREAMBLE='insmod gfxterm\ninsmod gfxmenu\ninsmod png\nif [ -f ($root)/boot/grub2/themes/bookos/theme.txt ]; then\n  loadfont ($root)/boot/grub2/themes/bookos/bookos-20.pf2\n  loadfont ($root)/boot/grub2/themes/bookos/bookos-20-b.pf2\n  loadfont ($root)/boot/grub2/themes/bookos/bookos-16.pf2\n  set theme=($root)/boot/grub2/themes/bookos/theme.txt\n  export theme\n  terminal_output gfxterm\nfi\n'
for _cfg in "$LORAX_TPL"/live/config_files/x86/grub2-bios.cfg \
            "$LORAX_TPL"/live/config_files/x86/grub2-efi.cfg; do
    [ -f "$_cfg" ] || continue
    grep -q 'themes/bookos' "$_cfg" && continue
    # Justo después de la línea `search …` — antes $root no está fijado.
    sed -i "/^search --no-floppy --set=root/a \\\n$_THEME_PREAMBLE" "$_cfg"
done
echo "[✓] Plantillas de lorax parcheadas en $LORAX_TPL (título 'Start $OS_NAME' + tema)"

# ── Build ──────────────────────────────────────────────────────────────────
# Slugify the OS name for the filename (spaces → -, lowercase).
SLUG="$(echo "$OS_NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9.-')"
# La completa conserva el nombre de siempre: release.sh y la web lo esperan así.
EDITION_SUFFIX=""
[ "$EDITION" = completa ] || EDITION_SUFFIX="-$EDITION"
ISO_NAME="${SLUG}-${VERSION}-${CHANNEL}${EDITION_SUFFIX}-x86_64.iso"
# Etiqueta del volumen: es el nombre con el que aparece el pendrive al
# conectarlo, así que va el nombre a secas («BookOS»), sin versión. Sin
# espacios (el arranque la busca como root=live:CDLABEL=…) y ≤32 (ISO 9660).
VOLID="$(echo "$OS_NAME" | tr -cd 'A-Za-z0-9_-' | cut -c1-32)"
SIGN="${SIGN:-auto}"
MINISIGN_SECRET_KEY="${MINISIGN_SECRET_KEY:-/etc/bookos/minisign.key}"
export MINISIGN_PUBKEY="${MINISIGN_PUBKEY:-/etc/bookos/minisign.pub}"
case "$SIGN" in auto|0|1) ;; *) echo 'SIGN must be auto, 0 or 1'; exit 1;; esac
if [ "$SIGN" = auto ]; then
    if [ -f "$MINISIGN_SECRET_KEY" ]; then SIGN=1; else SIGN=0; fi
fi
if [ "$SIGN" = 1 ]; then
    command -v minisign >/dev/null && [ -s "$MINISIGN_SECRET_KEY" ] && [ -s "$MINISIGN_PUBKEY" ] \
        || { echo 'Signing requires minisign and both configured key files'; exit 1; }
fi
if [ -e "$OUTDIR/$ISO_NAME" ] || [ -e "$OUTDIR/$ISO_NAME.minisig" ]; then
    echo 'Output already exists; choose a new version/output directory to avoid stale signatures'
    exit 1
fi

echo "──────────────────────────────────────────────"
echo "  OS        : $OS_NAME"
echo "  Channel   : $CHANNEL"
echo "  Edition   : $EDITION"
echo "  Version   : $VERSION"
echo "  Fedora    : $RELEASEVER"
echo "  All apps  : $ALLAPPS  ${OPTIONAL_APPS:+($OPTIONAL_APPS)}"
echo "  Output    : $OUTDIR/$ISO_NAME"
echo "  Boot args : $EXTRA_BOOT_ARGS"
echo "──────────────────────────────────────────────"

# --tmp: sin él, lmc usa /var/tmp para la imagen de disco (~20 GB) y el árbol
# del squashfs. En el contenedor podman eso caía en disco del host, pero en una
# sesión LIVE /var/tmp es el overlay en RAM → el build muere por espacio.
# Anclarlo bajo WORKDIR cumple la promesa de "WORKDIR = todo el scratch".
# Keep diagnostics for this compose separate from earlier builds. Lorax can
# return success despite Anaconda exit-handler or dracut-install failures.
BUILD_LOGDIR=$(mktemp -d "$WORKDIR/logs/compose-XXXXXXXX")
livemedia-creator \
    --logfile "$BUILD_LOGDIR/livemedia.log" \
    --tmp "$WORKDIR/tmp" \
    --make-iso \
    --no-virt \
    --ks "$WORKDIR/bookos-flat.ks" \
    --iso-only \
    --iso-name "$ISO_NAME" \
    --resultdir "$WORKDIR/results" \
    --project "$OS_NAME" \
    --lorax-templates "$LORAX_TPL" \
    --extra-boot-args "$EXTRA_BOOT_ARGS" \
    --releasever "$RELEASEVER" \
    --volid "$VOLID" \
    --compression zstd \
    --compress-arg=-Xcompression-level --compress-arg=15

bash "$SCRIPT_DIR/check-compose-logs.sh" "$BUILD_LOGDIR"

mv "$WORKDIR/results/$ISO_NAME" "$OUTDIR/"
echo "[✓] $OUTDIR/$ISO_NAME"

# ── Checksum ────────────────────────────────────────────────────────────────
# Publish a SHA256SUMS next to the ISO so users without minisign can still
# verify the download (sha256sum -c "$ISO_NAME.sha256").
( cd "$OUTDIR" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
echo "[✓] $OUTDIR/$ISO_NAME.sha256"

# ── Comprobación del menú de arranque ──────────────────────────────────────
# El título y el tema los fija el parche de plantillas de arriba, ANTES de
# construir. Aquí se verifica el resultado en la copia que lee el firmware al
# arrancar el pendrive por UEFI, que es justo la que el antiguo remaster
# post-build no tocaba (de ahí el «BookOS 44» que se veía en un portátil real
# mientras en BIOS se veía bien). Si aquí sale la versión de Fedora, está mal.
#
# Esa copia NO está en el árbol ISO9660: lorax la anexa como partición GPT de
# tipo EFI System (xorrisofs -append_partition). Antes se buscaba en
# /images/efiboot.img, que no existe dentro de la ISO, así que la comprobación
# se saltaba en todos los builds diciendo «no pude extraer». Se lee la
# partición anexada: sfdisk da el offset y strings basta para mirar el texto,
# sin necesidad de montar nada ni de herramientas de FAT.
ESP_START=""
if command -v sfdisk >/dev/null; then
    ESP_START=$(LC_ALL=C sfdisk --json "$OUTDIR/$ISO_NAME" 2>/dev/null | python3 -c '
import json, sys
try:
    tabla = json.load(sys.stdin)["partitiontable"]
except Exception:
    sys.exit(0)
for particion in tabla.get("partitions", []):
    # GUID de "EFI System Partition"
    if str(particion.get("type", "")).upper().startswith("C12A7328"):
        print(particion["start"], particion["size"])
        break
')
fi
if [ -n "$ESP_START" ]; then
    TMPB="$(mktemp -d)"
    # shellcheck disable=SC2086
    set -- $ESP_START
    dd if="$OUTDIR/$ISO_NAME" of="$TMPB/esp.img" bs=512 skip="$1" count="$2" status=none
    # `grep -a` sobre el fichero y NO `strings … | grep -q`: con pipefail, grep
    # corta la tubería al primer acierto, strings muere de SIGPIPE y el estado
    # de la tubería es 141. Acertar contaba como fallo.
    if grep -aq "$OS_NAME $RELEASEVER" "$TMPB/esp.img"; then
        echo "✗ el menú UEFI del pendrive dice '$OS_NAME $RELEASEVER' — el parche de plantillas no llegó a la partición EFI"
        rm -rf "$TMPB"; exit 1
    fi
    # Con la comilla de cierre: garantiza que no quedó nada tras el nombre.
    if grep -aq "Start $OS_NAME'" "$TMPB/esp.img"; then
        echo "[✓] Menú UEFI (partición EFI anexada): 'Start $OS_NAME'"
    else
        echo "[i] No encuentro el título en la partición EFI — revísalo a mano antes de publicar."
    fi
    rm -rf "$TMPB"
else
    echo "[i] Sin sfdisk o sin partición EFI anexada: no se comprueba el título del menú UEFI."
fi

# ── Sign (minisign) ──────────────────────────────────────────────────────
if [ "$SIGN" = 1 ]; then
    minisign -Sm "$OUTDIR/$ISO_NAME" -s "$MINISIGN_SECRET_KEY"
    bash "$SCRIPT_DIR/check-artifacts.sh" iso "$OUTDIR/$ISO_NAME"
    echo "[✓] Firmado: $OUTDIR/$ISO_NAME.minisig"
else
    echo '[i] Unsigned local candidate; sign and verify it before publishing.'
fi
