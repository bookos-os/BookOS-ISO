Name:           bookos-oobe
Version:        0.6.1
# Release (no Version) sube con los añadidos: coherente con el resto de bookos-*.
Release:        1%{?dist}
Summary:        BookOS first-boot — asistente de primer arranque (crea el usuario)
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch
# Tarball topdir bookos-oobe-%%{version}/ with the staged tree.
Source0:        %{name}-%{version}.tar.gz

# Compositor kiosko para la pantalla del asistente (fallback: kwin_wayland).
Requires:       cage
# Host QML del asistente.
Requires:       python3-pyqt6
Requires:       qt6-qtdeclarative

%description
Asistente de primer arranque de BookOS (estilo gnome-initial-setup): con la
página de cuentas de Anaconda oculta (hidden_webui_pages en el perfil), este
asistente pide nombre, usuario, contraseña y nombre del equipo en el primer
arranque del sistema instalado y crea el usuario (wheel) antes de que arranque
SDDM. No corre en la sesión live (rd.live.image) ni si ya existe un usuario
real (instalaciones antiguas), y se desactiva solo con un marker en /var/lib.

%prep
%setup -q

%install
install -Dm755 bookos-oobe-session %{buildroot}%{_libexecdir}/bookos-oobe-session
install -Dm755 bookos-oobe-app     %{buildroot}%{_libexecdir}/bookos-oobe-app
install -Dm644 oobe.py             %{buildroot}%{_datadir}/bookos-oobe/oobe.py
install -Dm644 Main.qml            %{buildroot}%{_datadir}/bookos-oobe/Main.qml
install -Dm644 bookos-oobe.service %{buildroot}%{_prefix}/lib/systemd/system/bookos-oobe.service

%post
# Enable manual (sin preset). En el compose de la ISO queda habilitado y las
# condiciones de la unidad deciden en cada arranque si hay algo que hacer.
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf %{_prefix}/lib/systemd/system/bookos-oobe.service \
    /etc/systemd/system/multi-user.target.wants/bookos-oobe.service 2>/dev/null || :

%postun
if [ $1 -eq 0 ]; then
    rm -f /etc/systemd/system/multi-user.target.wants/bookos-oobe.service
fi

%files
%{_libexecdir}/bookos-oobe-session
%{_libexecdir}/bookos-oobe-app
%dir %{_datadir}/bookos-oobe
%{_datadir}/bookos-oobe/oobe.py
%{_datadir}/bookos-oobe/Main.qml
%{_prefix}/lib/systemd/system/bookos-oobe.service

%changelog
* Tue Jul 07 2026 BookOS <packages@bookos.es> - 0.6.1-1
- Initial: asistente de primer arranque (cage/kwin + PyQt6 QML) que crea el
  usuario con la página de cuentas de Anaconda oculta
