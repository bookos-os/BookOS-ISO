#!/usr/bin/env bash
# Publica una versión de BookOS de principio a fin, parando donde hace falta
# una persona.
#
#   bash iso/release.sh <canal> <versión> <notas.md> [--desde N]
#   bash iso/release.sh dev 0.7.0 notas-0.7.0.md
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

CHANNEL="${1:?uso: $0 <canal> <versión> <notas.md> [--desde N]}"
VERSION="${2:?falta la versión}"
NOTES="${3:?falta el fichero de notas (markdown, en español)}"
FROM=1
[[ "${4:-}" == "--desde" ]] && FROM="${5:?falta N}"
[[ "$CHANNEL" =~ ^(stable|beta|dev)$ ]] || { echo "✗ canal: stable, beta o dev"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.]+)?$ ]] || { echo "✗ versión no válida: $VERSION"; exit 1; }
[[ -s "$NOTES" ]] || { echo "✗ no existe o está vacío: $NOTES"; exit 1; }
NOTES="$(realpath "$NOTES")"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WEB="$(dirname "$ROOT")/Bookos-web"
REPO="$ROOT/.build/package-check/repo"
OUT="$ROOT/.build/release/$VERSION"
ISO="$OUT/bookos-$VERSION-$CHANNEL-x86_64.iso"
MINISIGN_KEY="${MINISIGN_KEY:-$HOME/.minisign/minisign.key}"
export MINISIGN_PUBKEY="${MINISIGN_PUBKEY:-$HOME/.minisign/minisign.pub}"
API="${API:-https://bookos.es/api/admin.php}"
KEYFILE="${KEYFILE:-$HOME/.config/bookos/apikey}"

step() { echo; echo "══ $1 ═══════════════════════════════════════"; }
ask() { local r; read -rp "$1 [s/N] " r; [[ "$r" =~ ^[sS]$ ]]; }
run() { [[ "$1" -ge "$FROM" ]]; }

if run 1; then
    step "1/9 Construyendo paquetes desde el código"
    bash "$HERE/build-apps-in-podman.sh"
    bash "$HERE/check-packages-in-podman.sh"
fi

if run 2; then
    step "2/9 Firmando los RPM en local"
    bash "$WEB/deploy/sign-and-publish.sh" --solo-firmar "$REPO"
    python3 "$HERE/app-catalog.py" resign "$REPO"
fi

if run 3; then
    step "3/9 Construyendo la ISO"
    mkdir -p "$OUT"
    sudo OUTDIR="$OUT" bash "$HERE/build-in-podman.sh" "$CHANNEL" "$VERSION"
    # El contenedor corre como root: sin esto el repo y la ISO quedan de root y
    # los pasos siguientes, que van con tu usuario, no pueden escribir.
    sudo chown -R "$(id -u):$(id -g)" "$REPO" "$OUT"
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
