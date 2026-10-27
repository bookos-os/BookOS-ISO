Name:           bookos-browser
Version:        0.7.1
Release:        1%{?dist}
Summary:        Aether Browser, navegador de BookOS sobre Firefox
License:        MPL-2.0
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz
Requires:       firefox
Requires:       firefox-langpacks
Requires:       ImageMagick
Requires:       unzip
Requires:       zip
Requires:       procps-ng
Requires:       util-linux

%description
Interfaz, marca y preferencias de Aether Browser. El montaje privado de cada
usuario se regenera cuando cambia Firefox o se actualiza este paquete.

%prep
%setup -q

%install
install -dm755 %{buildroot}%{_datadir}/bookos-browser
cp -r construir.sh bookos-browser bookos.cfg defaults distribution marca bookos data \
    %{buildroot}%{_datadir}/bookos-browser/
chmod 755 %{buildroot}%{_datadir}/bookos-browser/construir.sh \
    %{buildroot}%{_datadir}/bookos-browser/bookos-browser
(cd %{buildroot}%{_datadir}/bookos-browser && \
    find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum > fuentes.sha256)
install -Dm644 data/bookos-browser.desktop %{buildroot}%{_datadir}/applications/bookos-browser.desktop
sed -i 's|^Icon=.*|Icon=bookos-browser|' %{buildroot}%{_datadir}/applications/bookos-browser.desktop
install -Dm644 data/bookos-browser.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/bookos-browser.svg
install -dm755 %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/bookos-browser <<'SH'
#!/usr/bin/bash
set -euo pipefail
fuentes=/usr/share/bookos-browser
cache=${XDG_CACHE_HOME:-$HOME/.cache}/bookos-browser
mkdir -p "$cache"
export BOOKOS_BROWSER_DIR="$cache/montaje"
exec 9>"$cache/montaje.lock"
flock 9
if ! cmp -s /usr/lib64/firefox/firefox "$BOOKOS_BROWSER_DIR/aether-browser" \
    || ! cmp -s "$fuentes/fuentes.sha256" "$cache/fuentes.sha256"; then
    if ! pgrep -f "$BOOKOS_BROWSER_DIR/aether-browser" >/dev/null; then
        "$fuentes/construir.sh" "$BOOKOS_BROWSER_DIR"
        cp "$fuentes/fuentes.sha256" "$cache/fuentes.sha256"
    fi
fi
flock -u 9
exec 9>&-
exec "$fuentes/bookos-browser" "$@"
SH
chmod 755 %{buildroot}%{_bindir}/bookos-browser

%files
%{_bindir}/bookos-browser
%{_datadir}/bookos-browser/
%{_datadir}/applications/bookos-browser.desktop
%{_datadir}/icons/hicolor/scalable/apps/bookos-browser.svg
