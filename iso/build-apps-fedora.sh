#!/usr/bin/env bash
set -euo pipefail
PROJECT=/sources/BookOS-ISO
export CARGO_HOME=/work/cargo
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
export npm_config_cache=/work/npm-cache
dnf -y install cargo rust gcc gcc-c++ make cmake pkgconf-pkg-config openssl-devel \
    webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel \
    gstreamer1-devel gstreamer1-plugins-base-devel \
    librsvg2-devel alsa-lib-devel libudev-devel protobuf-compiler rpm-build nodejs npm python3 \
    clang-devel fontconfig-devel freetype-devel libxkbcommon-devel wayland-devel \
    libxcb-devel libX11-devel libXi-devel libXrandr-devel libXcursor-devel libXinerama-devel \
    libxkbcommon-x11-devel libdrm-devel mesa-libgbm-devel vulkan-loader-devel \
    libgit2-devel zlib-devel curl-devel libzstd-devel dbus-devel perl git cpio
pkg-config --atleast-version=1.14 gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0
mkdir -p /work/sources /work/logs /work/cli
npm install --prefix /work/cli @tauri-apps/cli@2.10.0
python3 "$PROJECT/iso/app-catalog.py" copiar /sources /work/sources "$@"
python3 "$PROJECT/iso/app-catalog.py" prepare /work/sources "$@"
if [ "$#" -eq 0 ]; then rm -rf /work/repo; fi
mkdir -p /work/repo
mapfile -t plan < <(python3 "$PROJECT/iso/app-catalog.py" plan)
for entrada in "${plan[@]}"; do
    IFS=$'\t' read -r app paquete tecnologia subdir <<< "$entrada"
    if [ "$#" -gt 0 ]; then
        seleccionada=0
        for elegida in "$@"; do [ "$app" != "$elegida" ] || seleccionada=1; done
        [ "$seleccionada" = 1 ] || continue
    fi
    echo ":: Compilando $paquete ($tecnologia) desde las fuentes actuales"
    cd "/work/sources/$app"
    unset CARGO_TARGET_DIR
    case "$tecnologia" in
        tauri)
            export CARGO_TARGET_DIR=/work/target
            if [ -f package-lock.json ]; then npm ci; fi
            if [ "$paquete" = bookos-teclas ]; then
                CARGO_TARGET_DIR="$PWD/teclasd/target" cargo build --release --locked --manifest-path teclasd/Cargo.toml
            fi
            rm -rf "$CARGO_TARGET_DIR/release/bundle/rpm"
            /work/cli/node_modules/.bin/tauri build --bundles rpm -- --locked 2>&1 | tee "/work/logs/$paquete.log"
            artefactos=("$CARGO_TARGET_DIR"/release/bundle/rpm/*.rpm)
            ;;
        gpui)
            cd "$subdir"
            # Los specs buscan target/ junto al manifest; el enlace permite
            # guardar los artefactos fuera de las copias de las fuentes.
            export CARGO_TARGET_DIR=/work/target-gpui
            mkdir -p "$CARGO_TARGET_DIR"
            ln -s "$CARGO_TARGET_DIR" target
            cargo build --release --locked --manifest-path Cargo.toml 2>&1 | tee "/work/logs/$paquete.log"
            temporal=$(mktemp -d /work/rpm-XXXXXXXX)
            rpmbuild -bb "$paquete.spec" --define "_topdir $temporal" --define "raiz $PWD" \
                2>&1 | tee -a "/work/logs/$paquete.log"
            artefactos=("$temporal"/RPMS/*/"$paquete"-*.rpm)
            ;;
        firefox)
            temporal=$(mktemp -d /work/rpm-XXXXXXXX)
            mkdir -p "$temporal/SOURCES"
            tar --transform 's,^\.,bookos-browser-0.7.1,' -czf "$temporal/SOURCES/bookos-browser-0.7.1.tar.gz" \
                -C /work/sources/bookos-browser .
            rpmbuild -bb "$PROJECT/rpm/bookos-browser.spec" --define "_topdir $temporal" \
                --define "_sourcedir $temporal/SOURCES" 2>&1 | tee "/work/logs/$paquete.log"
            artefactos=("$temporal"/RPMS/*/"$paquete"-*.rpm)
            ;;
    esac
    for anterior in /work/repo/*.rpm; do
        [ -e "$anterior" ] || continue
        if [ "$(rpm -qp --qf '%{NAME}' "$anterior")" = "$paquete" ]; then rm -f -- "$anterior"; fi
    done
    for artefacto in "${artefactos[@]}"; do
        nombre=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$artefacto")
        cp "$artefacto" "/work/repo/$nombre.rpm"
    done
    if [ "$tecnologia" != tauri ]; then rm -rf "$temporal"; fi
    # El RPM debe estar a salvo en el repo: cargo clean también borra los
    # bundles de Tauri que están dentro de target/.
    case "$tecnologia" in
        tauri)
            echo ":: Limpiando la compilación de $paquete; el RPM ya está guardado"
            cargo clean --manifest-path "/work/sources/$app/src-tauri/Cargo.toml"
            if [ "$paquete" = bookos-teclas ]; then
                CARGO_TARGET_DIR="$PWD/teclasd/target" cargo clean --manifest-path teclasd/Cargo.toml
            fi
            ;;
        gpui)
            echo ":: Limpiando la compilación de $paquete; el RPM ya está guardado"
            cargo clean --manifest-path Cargo.toml
            ;;
    esac
done
python3 "$PROJECT/iso/app-catalog.py" record /work/repo /work/sources
python3 "$PROJECT/iso/app-catalog.py" verify /work/repo
cp /work/sources/bookos-fuentes.json /work/repo/
