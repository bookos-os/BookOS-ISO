#!/usr/bin/env bash
# Verify release artifacts without changing the host RPM key database.
# Usage: bash iso/check-artifacts.sh rpm package.rpm [...]
#        MINISIGN_PUBKEY=/path/to/public.key bash iso/check-artifacts.sh iso image.iso
set -euo pipefail
kind="${1:?Choose rpm or iso}"
shift
[ "$#" -gt 0 ] || { echo 'No artifacts supplied' >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
case "$kind" in
    rpm)
        key="${RPM_PUBKEY:-$here/../rpm/RPM-GPG-KEY-bookos}"
        [ -s "$key" ] || { echo "Missing RPM public key: $key" >&2; exit 1; }
        task_tmp=$(mktemp -d)
        trap 'rm -rf -- "$task_tmp"' EXIT
        # rpmkeys y no `rpm --initdb`: /usr/bin/rpm corre en el dominio SELinux
        # rpm_t, que no puede escribir en $HOME ni en /tmp del usuario (medido
        # en Fedora 44: «no puede crear el bloqueo transacción … Permiso
        # denegado»). rpmkeys es bin_t y crea la base al importar.
        mkdir "$task_tmp/rpmdb"
        rpmkeys --dbpath "$task_tmp/rpmdb" --import "$key"
        for artifact in "$@"; do
            [ -s "$artifact" ] || { echo "Missing RPM: $artifact" >&2; exit 1; }
            if ! report=$(LC_ALL=C rpmkeys --dbpath "$task_tmp/rpmdb" --checksig --verbose "$artifact" 2>&1); then
                printf 'RPM verification failed: %s\n%s\n' "$artifact" "$report" >&2
                exit 1
            fi
            # A digest-only unsigned RPM can return success. Require a signature.
            if ! grep -Eiq 'Signature.*: OK' <<< "$report"; then
                printf 'RPM has no verified signature: %s\n%s\n' "$artifact" "$report" >&2
                exit 1
            fi
            printf 'Verified RPM: %s\n' "$artifact"
        done
        ;;
    iso)
        command -v minisign >/dev/null || { echo 'Missing minisign verifier' >&2; exit 1; }
        key="${MINISIGN_PUBKEY:-/etc/bookos/minisign.pub}"
        [ -s "$key" ] || { echo "Missing minisign public key: $key" >&2; exit 1; }
        for artifact in "$@"; do
            [ -s "$artifact.minisig" ] || { echo "Missing ISO signature: $artifact.minisig" >&2; exit 1; }
            minisign -Vm "$artifact" -x "$artifact.minisig" -p "$key" \
                || { echo "ISO signature does not match the file or trusted key: $artifact" >&2; exit 1; }
        done
        ;;
    *) echo 'Unknown artifact type; choose rpm or iso' >&2; exit 1 ;;
esac
