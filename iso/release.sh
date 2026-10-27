#!/usr/bin/env bash
# Publica una versión de BookOS de principio a fin, parando donde hace falta
# una persona.
#
#   bash iso/release.sh <canal> <versión> <notas.md> [--desde N]
#   bash iso/release.sh dev 0.7.0 notas-0.7.0.md
#   bash iso/release.sh dev 0.7.1 --solo-iso
#
#   1 paquetes     construye apps y paquetes de sistema desde el código
#   2 firmar       firma los RPM EN LOCAL, antes de meterlos en la ISO
#   3 iso          construye la ISO con esos RPM firmados       (pide sudo)
#   4 probar       arranca la ISO en QEMU y pregunta si funciona
#   5 firmar-iso   minisign de la ISO ya probada
#   6 paquetes-web publica los RPM nuevos en bookos.es          (pregunta)
#   7 comprobar    un Fedora limpio instala desde bookos.es sin preguntas
#   8 iso-web      sube la ISO y la registra en el manifiesto   (pregunta)
#   9 anunciar     entrada del blog; Discord lo avisa el servidor (pregunta)
#
# El orden importa: se firma ANTES de construir la ISO para que lo que pruebas
# en el paso 4 sea, byte a byte, lo que se publica en el 6. Firmar después
# cambiaría la cabecera de cada RPM y la ISO llevaría otros ficheros.
#
# Si algo falla, arregla y sigue desde ese paso con --desde N.
#
# Una sola vez antes de la primera versión (ver deploy/PUBLICAR.md):
#   - privada GPG F8D9…E64F importada y `sudo dnf install rpm-sign createrepo_c`
#   - `sudo dnf install minisign qemu-kvm edk2-ovmf`
#   - `minisign -G -p ~/.minisign/minisign.pub -s ~/.minisign/minisign.key` y
#     subir minisign.pub a /var/www/html/storage/minisign.pub
#   - API key del panel en ~/.config/bookos/apikey (chmod 600)
#   - webhook de Discord en el panel (Ajustes → Webhooks): lo dispara el
#     servidor al registrar la ISO, así la URL del webhook no sale de allí.
set -euo pipefail

CHANNEL="${1:?uso: $0 <canal> <versión> [notas.md] [--solo-iso] [--desde N] [--comprobar]}"
VERSION="${2:?falta la versión}"
shift 2
NOTES=""
FROM=1
SOLO_ISO=0
COMPROBAR=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --solo-iso) SOLO_ISO=1; shift ;;
        --comprobar) COMPROBAR=1; shift ;;
        --desde) FROM="${2:?falta el número de paso}"; shift 2 ;;
        --*) echo "✗ opción desconocida: $1" >&2; exit 1 ;;
        *) [ -z "$NOTES" ] || { echo '✗ solo se admite un fichero de notas' >&2; exit 1; }
           NOTES="$1"; shift ;;
    esac
done
[[ "$CHANNEL" =~ ^(stable|beta|dev)$ ]] || { echo "✗ canal: stable, beta o dev"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.]+)?$ ]] || { echo "✗ versión no válida: $VERSION"; exit 1; }
[[ "$FROM" =~ ^[1-9]$ ]] && { [ "$SOLO_ISO" = 0 ] || [ "$FROM" -le 3 ]; } \
    || { echo '✗ --desde debe ser un paso 1–9 (1–3 con --solo-iso)' >&2; exit 1; }
if [ "$SOLO_ISO" = 0 ]; then
    [[ -s "$NOTES" ]] || { echo "✗ faltan las notas; para construir sin publicar usa --solo-iso"; exit 1; }
    NOTES="$(realpath "$NOTES")"
fi
[ "$(id -u)" != 0 ] || { echo '✗ ejecuta sin sudo; solo la composición pedirá privilegios' >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WEB="$(dirname "$ROOT")/Bookos-web"
BOOKOS_BUILD_ROOT="$(realpath -m "${BOOKOS_BUILD_ROOT:-$ROOT/.build}")"
export BOOKOS_BUILD_ROOT
REPO="$BOOKOS_BUILD_ROOT/package-check/repo"
OUT="$(realpath -m "${OUTDIR:-$BOOKOS_BUILD_ROOT/release/$VERSION}")"
ISO="$OUT/bookos-$VERSION-$CHANNEL-x86_64.iso"
MINISIGN_KEY="${MINISIGN_KEY:-$HOME/.minisign/minisign.key}"
export MINISIGN_PUBKEY="${MINISIGN_PUBKEY:-$HOME/.minisign/minisign.pub}"
API="${API:-https://bookos.es/api/admin.php}"
KEYFILE="${KEYFILE:-$HOME/.config/bookos/apikey}"

step() { echo; echo "══ $1 ═══════════════════════════════════════"; }
ask() { local r; read -rp "$1 [s/N] " r; [[ "$r" =~ ^[sS]$ ]]; }
run() { [[ "$1" -ge "$FROM" ]]; }

step 'Comprobaciones previas'
for programa in podman python3 sudo rpm rpmkeys rpmsign createrepo_c gpg rsync; do
    command -v "$programa" >/dev/null || { echo "✗ falta $programa" >&2; exit 1; }
done
python3 "$HERE/app-catalog.py" comprobar "$(dirname "$ROOT")"
mkdir -p "$BOOKOS_BUILD_ROOT" "$OUT"
python3 - "$BOOKOS_BUILD_ROOT" "$OUT" "$FROM" <<'PY'
from pathlib import Path
import shutil
import sys
trabajo, salida = map(Path, sys.argv[1:3])
# El espacio adicional depende de las cachés y de los archivos dispersos de
# lorax. Esta estimación sirve de aviso, no demuestra que el build no quepa.
fase = int(sys.argv[3])
necesarios = 60 if fase == 1 else 35 if fase <= 4 else 0
libres = shutil.disk_usage(trabajo).free / 1024**3
if libres < necesarios:
    print(f'Aviso: hay {libres:.1f} GiB libres en {trabajo}. '
          f'El margen estimado sin caché es {necesarios} GiB; se continúa con las cachés disponibles. '
          'Podman también consume espacio del disco anfitrión.', file=sys.stderr)
if trabajo.stat().st_dev != salida.stat().st_dev and shutil.disk_usage(salida).free < 10 * 1024**3:
    print(f'Aviso: hay menos de 10 GiB libres para la ISO en {salida}; se continúa.', file=sys.stderr)
PY
podman info >/dev/null
if run 2; then
    gpg --list-secret-keys F8D96833E35611130227335A9A8FA3B2E9E0E64F >/dev/null 2>&1 \
        || { echo '✗ falta la clave privada de firma de BookOS en el llavero del usuario' >&2; exit 1; }
fi
if run 3 && { [ -e "$ISO" ] || [ -e "$ISO.minisig" ]; }; then
    echo "✗ ya existe $ISO; usa OUTDIR para conservar la imagen anterior" >&2
    exit 1
fi
if [ "$COMPROBAR" = 1 ]; then
    echo "Fuentes y requisitos disponibles. Repositorio: $REPO"
    echo "Salida prevista: $ISO"
    exit 0
fi

if run 1; then
    step "1/9 Construyendo paquetes desde el código"
    bash "$HERE/build-apps-in-podman.sh"
    bash "$HERE/check-packages-in-podman.sh"
fi

if run 2; then
    step "2/9 Firmando los RPM en local"
    if [ -t 0 ]; then
        GPG_TTY="$(tty)"
        export GPG_TTY
        # La compilación puede durar horas y el agente conservar una terminal
        # antigua. Pedir aquí la clave evita 35 esperas de pinentry caducadas.
        comprobacion=$(mktemp -d)
        printf 'Comprobación local de firma de BookOS\n' > "$comprobacion/prueba"
        echo 'GPG puede pedir la contraseña de la clave de firma en esta terminal.'
        if ! gpg --pinentry-mode loopback --local-user F8D96833E35611130227335A9A8FA3B2E9E0E64F \
            --detach-sign --output "$comprobacion/prueba.sig" "$comprobacion/prueba"; then
            rm -rf -- "$comprobacion"
            echo '✗ no se ha podido desbloquear la clave; no se intenta firmar el lote de RPM' >&2
            exit 1
        fi
        rm -rf -- "$comprobacion"
    fi
    bash "$WEB/deploy/sign-and-publish.sh" --solo-firmar "$REPO"
    python3 "$HERE/app-catalog.py" resign "$REPO"
fi

if run 3; then
    step "3/9 Construyendo la ISO"
    mkdir -p "$OUT"
    bash "$HERE/check-artifacts.sh" rpm "$REPO"/*.rpm
    sudo env OUTDIR="$OUT" LOCALREPO="$REPO" NO_LOCAL_REPO= WORK="$BOOKOS_BUILD_ROOT/compose" \
        EDITION=completa SIGN=0 BOOKOS_UID="$(id -u)" BOOKOS_GID="$(id -g)" \
        bash -ec '
            bash "$@"
            # La autenticación de sudo puede caducar durante lorax. Devolver
            # los archivos al usuario dentro de esta misma sesión de root.
            chown -R "$BOOKOS_UID:$BOOKOS_GID" "$LOCALREPO" "$OUTDIR"
        ' -- "$HERE/build-in-podman.sh" "$CHANNEL" "$VERSION"
fi

if [ "$SOLO_ISO" = 1 ]; then
    (cd "$OUT" && sha256sum -c "$(basename "$ISO").sha256")
    cp "$REPO/bookos-apps.json" "$REPO/bookos-fuentes.json" "$OUT/"
    printf '\nISO para probar en un pendrive: %s\nChecksum: %s.sha256\n' "$ISO" "$ISO"
    echo 'Graba la imagen en el dispositivo completo con la herramienta de imágenes que uses.'
    exit 0
fi

if run 4; then
    step "4/9 Probando la ISO en QEMU"
    OVMF=/usr/share/edk2/ovmf/OVMF_CODE.fd
    [[ -f "$OVMF" ]] || { echo "✗ falta $OVMF: sudo dnf install edk2-ovmf qemu-kvm"; exit 1; }
    echo "Comprueba al menos: arranca, entra al escritorio, red, sonido e instalar a disco."
    echo "Cierra la ventana de QEMU cuando termines."
    # UEFI porque es como arrancan los portátiles objetivo; el disco vacío de
    # 30G deja probar el instalador de verdad y se borra al salir.
    DISK="$(mktemp --suffix=.qcow2)"; trap 'rm -f "$DISK"' EXIT
    qemu-img create -q -f qcow2 "$DISK" 30G
    qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 4096 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
        -drive file="$DISK",if=virtio -cdrom "$ISO" -boot d \
        -device virtio-vga -display gtk -nic user,model=virtio-net-pci \
        -audiodev pipewire,id=a -device intel-hda -device hda-duplex,audiodev=a
    ask "¿Funciona la ISO?" || { echo "✗ No se publica nada. Arregla y repite desde el paso 1."; exit 1; }
fi

if run 5; then
    step "5/9 Firmando la ISO (minisign)"
    [[ -s "$MINISIGN_KEY" ]] || { echo "✗ falta $MINISIGN_KEY (ver cabecera de este script)"; exit 1; }
    rm -f "$ISO.minisig"
    minisign -Sm "$ISO" -s "$MINISIGN_KEY"
    bash "$HERE/check-artifacts.sh" iso "$ISO"
fi

if run 6; then
    step "6/9 Publicando los paquetes en bookos.es"
    bash "$WEB/deploy/sign-and-publish.sh" --dry-run "$REPO"
    ask "¿Publicar estos paquetes?" || exit 1
    bash "$WEB/deploy/sign-and-publish.sh" "$REPO"
fi

if run 7; then
    step "7/9 Comprobando desde un Fedora limpio"
    # Lo que haría un equipo con BookOS: clave local importada, el .repo del
    # paquete bookos-keyring, y nada más. Falla si dnf pregunta por la clave,
    # si algún paquete no verifica o si el servidor no tiene lo que se probó.
    # Los RPM de Tauri declaran Epoch: 0 explícito y rpm lo imprime («0:0.6.2-1»);
    # dnf repoquery %{evr} omite la época 0. Sin quitarla, todas las apps salían
    # como «no está en el servidor» aunque sí estaban (2026-09-25).
    rpm -qp --qf '%{NAME}-%{EVR}\n' "$REPO"/*.rpm 2>/dev/null | sed 's/-0:/-/' | sort -u > "$OUT/esperado.txt"
    podman run --rm --security-opt label=disable \
        -v "$ROOT/rpm":/rpm:ro -v "$HERE":/iso:ro -v "$OUT":/out \
        registry.fedoraproject.org/fedora:44 bash -c '
            set -euo pipefail
            cp /rpm/RPM-GPG-KEY-bookos /etc/pki/rpm-gpg/
            cp /rpm/bookos.repo /etc/yum.repos.d/
            rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-bookos
            dnf -q --refresh repoquery --repo bookos --qf "%{name}-%{evr}\n" | sort -u > /out/servidor.txt
            mkdir /tmp/d && cd /tmp/d
            dnf -q download --repo bookos $(dnf -q repoquery --repo bookos --latest-limit 1 --qf "%{name}\n" | sort -u)
            bash /iso/check-artifacts.sh rpm *.rpm >/dev/null
            # La pregunta de la clave sale DESPUÉS de aceptar la transacción
            # (medido en fedora:44): se acepta con "y" y se niega la clave.
            out=$(dnf install --repo bookos bookos-keyring <<< $'"'"'y\nn'"'"' 2>&1 || true)
            grep -qi "importing" <<< "$out" && { echo "✗ dnf pregunta por la clave:"; echo "$out"; exit 1; }
            echo "  $(ls | wc -l) paquetes descargados y verificados, sin preguntas de clave"
        '
    missing=$(comm -23 "$OUT/esperado.txt" "$OUT/servidor.txt")
    [[ -z "$missing" ]] || { echo "✗ probado en la ISO pero no está en el servidor:"; echo "$missing"; exit 1; }
    echo "  el servidor tiene todo lo que lleva la ISO"
fi

if run 8; then
    step "8/9 Publicando la ISO"
    ask "¿Publicar $ISO como $VERSION ($CHANNEL)?" || exit 1
    bash "$HERE/publish-web.sh" "$ISO" "$VERSION" "$CHANNEL" "$(head -n1 "$NOTES" | sed 's/^#* *//')"
fi

if run 9; then
    step "9/9 Anunciando"
    ask "¿Publicar la entrada del blog (y avisar a los suscritos)?" || exit 1
    [[ -s "$KEYFILE" ]] || { echo "✗ falta $KEYFILE"; exit 1; }
    resp=$(curl -sS -w '\n%{http_code}' -X POST "$API?action=post_save" \
        -H "X-Api-Key: $(<"$KEYFILE")" \
        -F "slug=release-$VERSION" -F "tag=release" -F "published=1" -F "auto_translate=1" \
        -F "title_es=BookOS $VERSION" -F "body_es=<$NOTES")
    [[ "$(tail -n1 <<< "$resp")" == 200 ]] || { echo "✗ el blog respondió: $resp"; exit 1; }
    echo "  entrada: https://bookos.es/blog?p=release-$VERSION"
    echo "  Discord: lo avisó el servidor en el paso 8 si el webhook está configurado."
fi

echo; echo "✓ BookOS $VERSION ($CHANNEL) terminado."
