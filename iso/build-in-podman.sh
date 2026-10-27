#!/usr/bin/env bash
# BookOS — construir la ISO desde cualquier host (CachyOS/Arch…) vía podman.
# Ejecuta build-iso.sh dentro de un Fedora 44 desechable (lorax necesita
# tooling Fedora + acceso root a loop devices, que el host Arch no da directo).
#
# DOS MODOS:
#   LOCAL (por defecto): usa los RPMs de .build/package-check/repo SIN publicar
#                        (los que deja iso/check-packages.sh). Ideal para
#                        PROBAR la ISO antes de subir nada.
#       sudo bash build-in-podman.sh dev 0.6.2
#
#   SERVIDOR (oficial):  ignora el repo local; la ISO tira del canal ya
#                        publicado en bookos.es. Usa esto DESPUÉS de publicar.
#       sudo NO_LOCAL_REPO=1 bash build-in-podman.sh dev 0.6.2
#
# Extra:  ALLAPPS S incluye todas las apps opcionales (player, viewer, recorder)
#         LOCALREPO=/otra/ruta  fuerza otro repo local
#         EDITION=minima|servidor  otra edición (por defecto la completa)
#         EXTRA_BOOT_ARGS="..." parámetros opcionales para un equipo concreto;
#                               por defecto el arranque es genérico
#
# La ISO sale en la raíz de BookOS-ISO/  (bookos-<version>-<canal>-x86_64.iso).
set -euo pipefail

# livemedia-creator necesita loop devices reales: podman DEBE correr como root
# (rootless + --privileged no da acceso a /dev/loop-control).
[ "$(id -u)" = "0" ] || { echo "✗ ejecuta con sudo: sudo bash $0 $*"; exit 1; }

CHANNEL="${1:-dev}"
VERSION="${2:-0.7.1}"
ALLAPPS="${3:-N}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"          # …/BookOS-ISO/iso
ROOT="$(dirname "$SCRIPT_DIR")"                      # …/BookOS-ISO
WORK="${WORK:-$ROOT/.build/compose}"
OUTDIR="${OUTDIR:-$ROOT}"
IMG="${IMG:-registry.fedoraproject.org/fedora:44}"
[[ "$CHANNEL" =~ ^(stable|beta|dev)$ && "$VERSION" =~ ^[A-Za-z0-9._-]+$ && "$ALLAPPS" =~ ^[SsYyNn]$ ]] \
    || { echo 'Invalid channel, version or optional-app selection'; exit 1; }
mkdir -p "$WORK"
mkdir -p "$WORK/tmp"
mkdir -p "$OUTDIR"

# /sys/fs/selinux en SOLO LECTURA: --privileged lo deja escribible y el
# scriptlet de selinux-policy-targeted del destino hace load_policy, que carga
# la política de la ISO en el kernel del ANFITRIÓN. Pasó el 2026-09-10 y el
# 2026-09-25 (MAC_POLICY_LOAD en el journal, miles de denegaciones unlabeled_t;
# solo se arregla reiniciando). En solo lectura rpm sigue viendo SELinux
# activo y etiqueta los ficheros de la ISO; lo único que falla es ese
# load_policy, que en un chroot no hace falta.
# ── Modo SERVIDOR: sin repo local ──────────────────────────────────────────
if [ -n "${NO_LOCAL_REPO:-}" ]; then
    echo ":: modo SERVIDOR — la ISO tirará del repo publicado del canal '$CHANNEL'"
    exec podman run --rm --privileged --network=host --security-opt label=disable \
        -v /dev:/dev \
        -v /sys/fs/selinux:/sys/fs/selinux:ro \
        -v "$ROOT":/build \
        -v "$OUTDIR":/out \
        -v "$WORK":/work \
        -v "$WORK/tmp":/var/tmp \
        -e WORKDIR=/work \
        -e EXTRA_BOOT_ARGS \
        -e EDITION \
        -e SIGN \
        "$IMG" bash -c "
            set -e
            # La imagen fedora de contenedor trae %_install_langs en_US: rpm
            # DESPOJA todas las traducciones de lo que instala anaconda en la
            # ISO (sesion en ingles + instalador sin espanol). Fuera.
            rm -f /etc/rpm/macros.image-language-conf
            dnf -y install lorax-lmc-novirt util-linux pykickstart xorriso policycoreutils
            bash /build/iso/build-iso.sh BookOS $CHANNEL $VERSION /out $ALLAPPS
        "
fi

# ── Modo LOCAL (por defecto): RPMs de .build/package-check/repo ─────────────
# Antes el defecto era ../localrepo-<versión>: un nombre que ningún script
# rellena, así que acababa apuntando a un repo viejo a mano (localrepo-0.6.1 era
# de julio, con bookos-branding-0.6.1-5) y el build moría en la verificación
# del %post. Este es el que regenera iso/check-packages.sh.
LOCALREPO="${LOCALREPO:-$ROOT/.build/package-check/repo}"
[ -d "$LOCALREPO" ] || { echo "✗ no existe LOCALREPO=$LOCALREPO (o usa NO_LOCAL_REPO=1 para el repo del servidor)"; exit 1; }
echo ":: modo LOCAL — usando RPMs de $LOCALREPO (sin publicar)"

exec podman run --rm --privileged --network=host --security-opt label=disable \
        -v /dev:/dev \
        -v /sys/fs/selinux:/sys/fs/selinux:ro \
    -v "$ROOT":/build \
    -v "$OUTDIR":/out \
    -v "$LOCALREPO":/localrepo \
    -v "$WORK":/work \
    -v "$WORK/tmp":/var/tmp \
    -e BOOKOS_LOCAL_REPO=/localrepo \
    -e WORKDIR=/work \
    -e EXTRA_BOOT_ARGS \
    -e EDITION \
    -e SIGN \
    "$IMG" bash -c "
        set -e
        rm -f /etc/rpm/macros.image-language-conf
        dnf -y install lorax-lmc-novirt createrepo_c util-linux pykickstart xorriso policycoreutils
        createrepo_c --update /localrepo
        bash /build/iso/build-iso.sh BookOS $CHANNEL $VERSION /out $ALLAPPS
    "
