#!/usr/bin/env bash
# Container entry point. All generated data stays under /work.
set -euo pipefail
PROJECT=/sources/BookOS-ISO
export CARGO_HOME=/work/cargo
export CARGO_TARGET_DIR=/work/target
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
export npm_config_cache=/work/npm-cache
# Fedora tooling avoids linking host-specific Arch libraries into release RPMs.
dnf -y install cargo rust gcc gcc-c++ make pkgconf-pkg-config openssl-devel \
    webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel \
    librsvg2-devel alsa-lib-devel libudev-devel protobuf-compiler rpm-build nodejs npm python3
mkdir -p /work/sources /work/logs /work/cli
npm install --prefix /work/cli @tauri-apps/cli@2.10.0
mapfile -t apps < <(python3 "$PROJECT/iso/app-catalog.py" list)
if [ "$#" -gt 0 ]; then
    for app in "$@"; do
        printf '%s\n' "${apps[@]}" | grep -Fxq "$app" || { echo "Unknown app: $app" >&2; exit 1; }
    done
    apps=("$@")
fi
for app in "${apps[@]}"; do
    # Replace only the isolated source snapshot, never the developer checkout.
    rm -rf "/work/sources/$app"
    mkdir -p "/work/sources/$app"
    tar -C "/sources/$app" --exclude=target --exclude=node_modules --exclude=.git \
        --exclude=dist -cf - . | tar -C "/work/sources/$app" -xf -
done
python3 "$PROJECT/iso/app-catalog.py" prepare /work/sources "${apps[@]}"
if [ "$#" -eq 0 ]; then rm -rf /work/repo; fi
mkdir -p /work/repo
for app in "${apps[@]}"; do
    echo ":: Building $app from current sources"
    cd "/work/sources/$app"
    if [ -f package-lock.json ]; then npm ci; fi
    # Shared compiler cache is useful, but bundles must never retain old RPMs.
    rm -rf "$CARGO_TARGET_DIR/release/bundle/rpm"
    /work/cli/node_modules/.bin/tauri build --bundles rpm 2>&1 | tee "/work/logs/$app.log"
    for artifact in "$CARGO_TARGET_DIR"/release/bundle/rpm/*.rpm; do
        package=$(command rpm -qp --qf '%{NAME}' "$artifact")
        name=$(command rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$artifact")
        # En una construcción parcial el repo conserva el resto; si esta app
        # sube de versión, su RPM anterior no puede quedarse al lado del nuevo.
        for old in /work/repo/*.rpm; do
            [ -e "$old" ] || continue
            [ "$(command rpm -qp --qf '%{NAME}' "$old")" = "$package" ] && rm -f -- "$old"
        done
        cp "$artifact" "/work/repo/$name.rpm"
    done
done
python3 "$PROJECT/iso/app-catalog.py" record /work/repo
python3 "$PROJECT/iso/app-catalog.py" verify /work/repo
