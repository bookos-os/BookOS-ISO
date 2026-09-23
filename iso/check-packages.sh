#!/usr/bin/env bash
# Run inside a disposable Fedora 44 container with the source family at /sources
# and a writable, isolated output directory at /work. Does not install a target OS.
set -euo pipefail
export RPM_TOPDIR=/work/rpmbuild
mkdir -p "$RPM_TOPDIR"/{SOURCES,RPMS,SRPMS,BUILD,BUILDROOT,SPECS} /work/repo
project=/sources/BookOS-ISO
remote_exclusions=$(python3 - "$project/iso/app-catalog.py" <<'PY'
import runpy, sys
print(','.join(app[1] for app in runpy.run_path(sys.argv[1])['APPS']))
PY
)
# Cada Source0 es <nombre>-<versión>.tar.gz con la versión de SU spec, y no
# tienen por qué coincidir (0.6.2: branding sube, integración sigue en 0.6.1).
spec_version() { awk '/^Version:/ {print $2; exit}' "$project/rpm/$1.spec"; }
bash "$project/rpm/collect-branding.sh" "$(spec_version bookos-branding)"
integration="bookos-desktop-integration-$(spec_version bookos-desktop-integration)"
tar --transform "s,^\.,$integration," \
    -czf "$RPM_TOPDIR/SOURCES/$integration.tar.gz" \
    -C "$project/rpm/bookos-desktop-integration" .
desktop="bookos-desktop-$(spec_version bookos-desktop)"
tar --transform "s,^\.,$desktop," -czf "$RPM_TOPDIR/SOURCES/$desktop.tar.gz" \
    --exclude='./target' --exclude='./.git' --exclude='./.claude' \
    -C /sources/bookos-desktop .
cp "$project/rpm/RPM-GPG-KEY-bookos" "$project/rpm/bookos.repo" "$RPM_TOPDIR/SOURCES/"
python3 "$project/iso/collect-visuals.py" /sources "$RPM_TOPDIR/SOURCES"
for package in bookos-branding bookos-desktop-integration bookos-desktop bookos-meta bookos-keyring bookos-icons bookos-widgets; do
    rpmbuild --define "_topdir $RPM_TOPDIR" -bb "$project/rpm/$package.spec"
done
cp "$RPM_TOPDIR"/RPMS/*/*.rpm /work/repo/
python3 "$project/iso/app-catalog.py" verify /work/repo
createrepo_c /work/repo
python3 "$project/iso/profile.py" --check
mapfile -t packages < <(python3 - "$project/iso" <<'PY'
import sys
import json
sys.path.insert(0, sys.argv[1])
import profile
h = profile.validate(profile.render())
with open('/work/repo/bookos-apps.json') as manifest:
    versions = {entry['name']: entry['nevra'] for entry in json.load(manifest)}
print(*(versions.get(name, name) for name in h.packages.packageList), sep="\n")
print(*("@" + g.name for g in h.packages.groupList), sep="\n")
PY
)
mapfile -t exclusions < <(python3 - "$project/iso" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import profile
print(*("--exclude=" + p for p in profile.validate(profile.render()).packages.excludedList), sep="\n")
PY
)
# Assumeno resolves the real Fedora dependency transaction but installs nothing.
# Local packages are unsigned build candidates, so signature validation is a
# separate check before publication; production systems keep GPG enforcement.
#
# El installroot se borra antes de resolver. dnf cachea los metadatos de los
# repos DENTRO de él (var/cache/libdnf5/bookos-candidate-*), y /work sobrevive
# entre ejecuciones: sin esto, tras recompilar un RPM la resolución sigue viendo
# el índice viejo y elige la versión anterior. Pasó de verdad — un branding
# recién construido se resolvía a la release anterior sin avisar de nada.
rm -rf /work/target
set +e
dnf --releasever=44 --installroot=/work/target --use-host-config \
    --setopt=install_weak_deps=False --setopt=logdir=/work/logs \
    --repofrompath=bookos-candidate,file:///work/repo \
    --repofrompath=bookos-apps,https://bookos.es/store-files/ \
    --setopt="bookos-apps.excludepkgs=$remote_exclusions" \
    "${exclusions[@]}" --assumeno install "${packages[@]}" > /work/dependency-resolution.log 2>&1
status=$?
set -e
cat /work/dependency-resolution.log
if [ "$status" -ne 0 ] && ! grep -Eq 'Operation aborted|Is this ok.*N' /work/dependency-resolution.log; then
    exit "$status"
fi
if grep -Eq '^ (konsole|openssh-server|plasma-discover|kwrite|kcalc|kmail|kontact|elisa-player|dragon|bookos-viewer|bookos-voice-recorder)[[:space:]]' /work/dependency-resolution.log; then
    echo 'Unexpected application in resolved minimal profile' >&2
    exit 1
fi
# Dos paquetes con la misma ruta y distinto contenido rompen la transacción de
# rpm, y anaconda solo dice "The transaction process has ended with errors": son
# ~30 minutos de build para un error que no señala el fichero. Se comprueba aquí,
# donde ya está resuelta la transacción de verdad.
# Solo los paquetes de BookOS: son los que publicamos nosotros, y comparar
# digests exige el RPM entero — bajar los 1285 serían 1,5 GiB por comprobación.
# Se piden por NEVRA exacta, no por nombre: pedirlos por nombre trae la ÚLTIMA
# del repo, que no tiene por qué ser la que la transacción eligió (una dependencia
# puede fijar una anterior). Comprobar unos RPM distintos de los que se van a
# instalar da un "sin conflictos" falso, que es peor que no comprobar nada.
# Columnas de la tabla de dnf: nombre arch epoch:version-release repo tamaño.
# Se exige arch en $2 y epoch en $3 para no confundir una fila de la tabla con
# las barras de progreso de los repos, que también empiezan por " bookos-"
# (" bookos-apps  100% | 281.8 KiB/s | ...") y producían NEVRAs inventadas.
mapfile -t bookos_packages < <(
    awk '/^ (bookos-|book-os-|libfprint-bookos)/ &&
         $2 ~ /^(noarch|x86_64|i686)$/ && $3 ~ /^[0-9]+:/ {
             evr = $3; sub(/^[0-9]+:/, "", evr); print $1 "-" evr "." $2
         }' /work/dependency-resolution.log | sort -u
)
if [ "${#bookos_packages[@]}" -eq 0 ]; then
    echo 'No BookOS package in the resolved transaction; the log format changed' >&2
    exit 1
fi
# Se vacía en cada pasada: /work sobrevive entre ejecuciones, y un RPM de una
# resolución anterior aquí dentro hace que se comparen dos versiones del mismo
# paquete y salga un conflicto que ya no existe.
rm -rf /work/conflict-check
mkdir -p /work/conflict-check
dnf --releasever=44 --use-host-config --setopt=logdir=/work/logs \
    --repofrompath=bookos-candidate,file:///work/repo \
    --repofrompath=bookos-apps,https://bookos.es/store-files/ \
    --setopt="bookos-apps.excludepkgs=$remote_exclusions" \
    download --destdir=/work/conflict-check "${bookos_packages[@]}"
python3 "$project/iso/check-file-conflicts.py" /work/conflict-check
# Keep the resolved transaction (repository and size included) beside the RPMs.
echo 'Candidate RPMs built; dependency transaction resolved without installing.'
