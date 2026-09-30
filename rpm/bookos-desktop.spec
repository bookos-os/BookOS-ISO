Name:           bookos-desktop
Version:        0.1.0
Release:        9%{?dist}
Summary:        BookOS Rust Wayland compositor and desktop session
License:        GPL-3.0-or-later
URL:            https://github.com/bookos/bookos-desktop
BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  libinput-devel
BuildRequires:  libdrm-devel
BuildRequires:  libseat-devel
BuildRequires:  mesa-libgbm-devel
BuildRequires:  pipewire-devel
BuildRequires:  clang-devel
BuildRequires:  libxkbcommon-devel
BuildRequires:  wayland-devel
Requires:       xorg-x11-server-Xwayland
Requires:       libinput
Requires:       libseat
Requires:       pipewire
Requires:       xdg-desktop-portal
Requires:       xdg-desktop-portal-gtk
Requires:       /usr/bin/python3
Requires:       /usr/bin/kwin_wayland
Requires:       python3-pyside6
Requires:       fprintd-pam
BuildArch:      x86_64
Source0:        bookos-desktop-%{version}.tar.gz

%description
BookOS native Wayland desktop written in Rust with Smithay and iced. It
includes the compositor, panel, dock, launcher, lock screen and BookOS session
entry. Plasma remains available as a compatibility fallback.

%prep
%setup -q

%build
cargo build --release --workspace --package bookos-comp --package bookos-system

%install
install -Dm755 target/release/bookos-comp %{buildroot}%{_libexecdir}/bookos-comp
install -Dm755 target/release/bookos-system %{buildroot}%{_libexecdir}/bookos-system
install -Dm755 session/bookos-session %{buildroot}%{_bindir}/bookos-session
install -Dm644 session/bookos-recovery.py %{buildroot}%{_libexecdir}/bookos-recovery.py
install -Dm644 session/bookos.pam %{buildroot}%{_sysconfdir}/pam.d/bookos
install -Dm644 session/bookos-fingerprint.pam %{buildroot}%{_sysconfdir}/pam.d/bookos-fingerprint
install -Dm644 session/bookos.desktop %{buildroot}%{_datadir}/wayland-sessions/bookos.desktop
install -Dm644 session/bookos-system.service %{buildroot}%{_prefix}/lib/systemd/user/bookos-system.service
install -Dm644 session/bookos-session.target %{buildroot}%{_prefix}/lib/systemd/user/bookos-session.target
# Activación por D-Bus: sin este fichero, quien llame a org.bookos.System1
# antes de que la sesión arranque la unidad se queda sin servicio.
install -Dm644 session/org.bookos.System1.service %{buildroot}%{_datadir}/dbus-1/services/org.bookos.System1.service
install -Dm644 session/bookos.portal %{buildroot}%{_datadir}/xdg-desktop-portal/portals/bookos.portal
install -Dm644 session/bookos-portals.conf %{buildroot}%{_datadir}/xdg-desktop-portal/BookOS-portals.conf
install -Dm644 session/70-bookos-camara.rules %{buildroot}%{_prefix}/lib/udev/rules.d/70-bookos-camara.rules

%files
%config(noreplace) %{_sysconfdir}/pam.d/bookos
%config(noreplace) %{_sysconfdir}/pam.d/bookos-fingerprint
%{_libexecdir}/bookos-comp
%{_libexecdir}/bookos-system
%{_bindir}/bookos-session
%{_libexecdir}/bookos-recovery.py
%{_datadir}/wayland-sessions/bookos.desktop
%{_prefix}/lib/systemd/user/bookos-system.service
%{_prefix}/lib/systemd/user/bookos-session.target
%{_datadir}/dbus-1/services/org.bookos.System1.service
%{_datadir}/xdg-desktop-portal/portals/bookos.portal
%{_datadir}/xdg-desktop-portal/BookOS-portals.conf
%{_prefix}/lib/udev/rules.d/70-bookos-camara.rules

%changelog
* Tue Sep 29 2026 BookOS <packages@bookos.es> - 0.1.0-9
- Aviso en pantalla al bloquear o desbloquear la cámara del Galaxy Book: una
  regla de udev deja al usuario de la sesión leer el interruptor de su tapa.

* Fri Sep 25 2026 BookOS <packages@bookos.es> - 0.1.0-8
- bookos-system monta solo lo extraíble (USB, discos externos, SD) a través
  de udisks2, que en Plasma hacía kded y en la sesión BookOS no hacía nadie.

* Wed Sep 23 2026 BookOS <packages@bookos.es> - 0.1.0-7
- Se empaqueta /etc/pam.d/bookos: el bloqueo autentica con ese servicio y,
  sin él, PAM caía a «other» y denegaba siempre la contraseña.
- Se empaqueta bookos-session.target: sin él no se activa
  graphical-session.target y xdg-desktop-portal no llega a arrancar.
- Los lanzadores de data/applications siguen fuera: los de las aplicaciones
  chocarían con los que instala cada RPM, y bookos-captura y bookos-share no
  los proporciona ningún paquete.

* Wed Sep 16 2026 BookOS <packages@bookos.es> - 0.1.0-6
- Confirmaciones de energía, dock configurable en vivo y actualización de widgets.
- Servicio biométrico PAM independiente; la contraseña sigue disponible.

* Tue Sep 15 2026 BookOS <packages@bookos.es> - 0.1.0-5
- Opciones de ventana: siempre encima y traslado entre escritorios y monitores.
- Supervisor de sesión y diálogo HIG de recuperación independiente, con
  reintento explícito o entrada a Plasma/GNOME instalado tras un fallo.
- Incluye el asistente de recuperación y sus dependencias KWin y PySide6.

* Sun Sep 13 2026 BookOS <packages@bookos.es> - 0.1.0-4
- Cursores: la sesión fija XCURSOR_THEME al primer tema instalado de verdad.
  Sin él, el compositor caía a «BookOS-Dark», que es un tema de iconos y no
  trae cursores: salía la flecha de reserva y cada aplicación usaba otro.
* Sun Sep 13 2026 BookOS <packages@bookos.es> - 0.1.0-3
- La sesión lanza el autoarranque XDG (/etc/xdg/autostart y el del usuario),
  que es cosa del escritorio y el compositor no implementaba. BookOS cuenta
  con ello: por ahí salen el refresco de primer inicio y las novedades.
  Se respetan Hidden, OnlyShowIn/NotShowIn y TryExec, y se limpian los
  códigos %f %u %U… de Exec.

* Sun Sep 13 2026 BookOS <packages@bookos.es> - 0.1.0-2
- La sesión arranca con el paquete instalado. La entrada .desktop apuntaba a
  /usr/local/bin/bookos-session (la ruta de session/instalar.sh) y el RPM
  instala en /usr/bin: TryExec fallaba y el gestor de login escondía la sesión.
  Ahora va por PATH y sirve para las dos instalaciones.
- bookos-session busca el compositor también en /usr/libexec, que es donde lo
  deja el RPM; antes solo miraba /usr/local/bin y no lo encontraba.
- bookos-system.service apuntaba igualmente a /usr/local/libexec.
- Se empaqueta el servicio de activación por D-Bus, que no estaba.

* Sat Sep 12 2026 BookOS <packages@bookos.es> - 0.1.0-1
- Ship the native Rust Wayland desktop and selectable BookOS session.
