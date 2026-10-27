# Cargo elimina el debug en release; no hay fuentes de depuración que empaquetar.
%global debug_package %{nil}

Name:           bookos-desktop
Version:        0.1.1
Release:        2%{?dist}
Summary:        BookOS Rust Wayland compositor and desktop session
License:        LicenseRef-BookOS
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
BuildRequires:  libdisplay-info-devel
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(wlroots-0.20)
BuildRequires:  pkgconfig(wayland-protocols)
Requires:       xorg-x11-server-Xwayland
Requires:       libinput
Requires:       libseat
Requires:       pipewire
Requires:       xdg-desktop-portal
Requires:       xdg-desktop-portal-gtk
Requires:       fprintd-pam
# El compositor suena con pw-play y el OSD con canberra-gtk-play. Ninguno de
# los dos lo pedía nadie: llegaban, o no, por otras dependencias.
Requires:       /usr/bin/pw-play
Requires:       /usr/bin/canberra-gtk-play
BuildArch:      x86_64
Source0:        bookos-desktop-%{version}.tar.gz

%description
Escritorio Wayland de BookOS con compositor, panel, dock, lanzador, bloqueo
y servicios propios.

%package -n bookos-greeter
Summary:        Pantalla de acceso propia de BookOS sobre greetd
License:        LicenseRef-BookOS AND MIT
Provides:       user(bookos-greeter)
Provides:       group(bookos-greeter)
Requires:       %{name} = %{version}-%{release}
Requires:       greetd
Requires:       cage
Requires:       dbus-daemon
Requires:       accountsservice
Requires(pre):  shadow-utils

%description -n bookos-greeter
Acceso a la sesión BookOS con greetd y Cage con los ajustes de entrada de BookOS.

%package recovery
Summary:        BookOS session recovery screen
Requires:       %{name} = %{version}-%{release}
Requires:       /usr/bin/python3
Requires:       /usr/bin/kwin_wayland
Requires:       python3-pyside6

%description recovery
Recovery screen shown under KWin when the BookOS compositor fails to start:
retry BookOS or open another installed session.

%prep
%setup -q

%build
cargo build --release --locked --package bookos-comp --package bookos-system --package bookos-budsd --package bookos-greeter
meson setup build-cage bookos-cage --buildtype=release -Dman-pages=disabled
ninja -C build-cage

%install
install -Dm755 target/release/bookos-comp %{buildroot}%{_libexecdir}/bookos-comp
install -Dm755 target/release/bookos-system %{buildroot}%{_libexecdir}/bookos-system
install -Dm755 target/release/bookos-budsd %{buildroot}%{_libexecdir}/bookos-budsd
install -Dm755 session/bookos-session %{buildroot}%{_bindir}/bookos-session
install -Dm644 session/bookos-recovery.py %{buildroot}%{_libexecdir}/bookos-recovery.py
install -Dm644 session/bookos.pam %{buildroot}%{_sysconfdir}/pam.d/bookos
install -Dm644 session/bookos-fingerprint.pam %{buildroot}%{_sysconfdir}/pam.d/bookos-fingerprint
install -Dm644 session/bookos.desktop %{buildroot}%{_datadir}/wayland-sessions/bookos.desktop
install -Dm644 session/bookos-system.service %{buildroot}%{_prefix}/lib/systemd/user/bookos-system.service
install -Dm644 session/bookos-budsd.service %{buildroot}%{_prefix}/lib/systemd/user/bookos-budsd.service
install -Dm644 session/org.bookos.Buds.service %{buildroot}%{_datadir}/dbus-1/services/org.bookos.Buds.service
install -Dm644 session/bookos-session.target %{buildroot}%{_prefix}/lib/systemd/user/bookos-session.target
# Activación por D-Bus: sin este fichero, quien llame a org.bookos.System1
# antes de que la sesión arranque la unidad se queda sin servicio.
install -Dm644 session/org.bookos.System1.service %{buildroot}%{_datadir}/dbus-1/services/org.bookos.System1.service
install -Dm644 session/bookos.portal %{buildroot}%{_datadir}/xdg-desktop-portal/portals/bookos.portal
install -Dm644 session/bookos-portals.conf %{buildroot}%{_datadir}/xdg-desktop-portal/bookos-portals.conf
install -Dm644 session/70-bookos-camara.rules %{buildroot}%{_prefix}/lib/udev/rules.d/70-bookos-camara.rules
install -Dm644 session/71-bookos-serie.rules %{buildroot}%{_prefix}/lib/udev/rules.d/71-bookos-serie.rules
install -Dm755 target/release/bookos-greeter %{buildroot}%{_libexecdir}/bookos-greeter
install -Dm755 build-cage/cage %{buildroot}%{_libexecdir}/bookos-cage
install -Dm644 bookos-cage/LICENSE %{buildroot}%{_licensedir}/bookos-greeter/LICENSE.Cage
install -Dm755 session/greeter/bookos-greeter-start %{buildroot}%{_libexecdir}/bookos-greeter-start
sed -i 's|/usr/local/libexec/|/usr/libexec/|g; s|/usr/local/bin/bookos-session|/usr/bin/bookos-session|g' \
    %{buildroot}%{_libexecdir}/bookos-greeter-start
install -Dm644 session/greeter/bookos.toml %{buildroot}%{_sysconfdir}/greetd/bookos.toml
sed -i 's|/usr/local/libexec/|/usr/libexec/|g' %{buildroot}%{_sysconfdir}/greetd/bookos.toml
install -Dm644 session/greeter/50-bookos-greeter.rules %{buildroot}%{_datadir}/polkit-1/rules.d/50-bookos-greeter.rules
install -dm755 %{buildroot}%{_prefix}/lib/systemd/system/greetd.service.d
cat > %{buildroot}%{_prefix}/lib/systemd/system/greetd.service.d/bookos.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=/usr/bin/greetd --config /etc/greetd/bookos.toml
UNIT
install -d -m 1777 %{buildroot}/var/lib/bookos/apariencia
install -d -m 0755 %{buildroot}/var/lib/bookos-greeter

%pre -n bookos-greeter
getent group bookos-greeter >/dev/null || groupadd --system bookos-greeter
getent passwd bookos-greeter >/dev/null || useradd --system --gid bookos-greeter \
    --home-dir /var/lib/bookos-greeter --shell /usr/sbin/nologin bookos-greeter

%files
%config(noreplace) %{_sysconfdir}/pam.d/bookos
%config(noreplace) %{_sysconfdir}/pam.d/bookos-fingerprint
%{_libexecdir}/bookos-comp
%{_libexecdir}/bookos-system
%{_libexecdir}/bookos-budsd
%{_bindir}/bookos-session
%{_datadir}/wayland-sessions/bookos.desktop
%{_prefix}/lib/systemd/user/bookos-system.service
%{_prefix}/lib/systemd/user/bookos-budsd.service
%{_prefix}/lib/systemd/user/bookos-session.target
%{_datadir}/dbus-1/services/org.bookos.System1.service
%{_datadir}/dbus-1/services/org.bookos.Buds.service
%{_datadir}/xdg-desktop-portal/portals/bookos.portal
%{_datadir}/xdg-desktop-portal/bookos-portals.conf
%{_prefix}/lib/udev/rules.d/70-bookos-camara.rules
%{_prefix}/lib/udev/rules.d/71-bookos-serie.rules

%files recovery
%{_libexecdir}/bookos-recovery.py

%files -n bookos-greeter
%license %{_licensedir}/bookos-greeter/LICENSE.Cage
%{_libexecdir}/bookos-greeter
%{_libexecdir}/bookos-cage
%{_libexecdir}/bookos-greeter-start
%config(noreplace) %{_sysconfdir}/greetd/bookos.toml
%{_datadir}/polkit-1/rules.d/50-bookos-greeter.rules
%{_prefix}/lib/systemd/system/greetd.service.d/bookos.conf
%attr(1777,root,root) %dir /var/lib/bookos/apariencia
%attr(0755,bookos-greeter,bookos-greeter) %dir /var/lib/bookos-greeter

%changelog
* Mon Oct 26 2026 BookOS <packages@bookos.es> - 0.1.1-2
- Sin nodo de render (modo básico, simpledrm) se repinta la pantalla entera
  en cada fotograma: la edad de los buffers no se cumple y quedaba gris.

* Mon Oct 26 2026 BookOS <packages@bookos.es> - 0.1.1-1
- Compila el escritorio actual y empaqueta el acceso propio con Cage parcheado.

* Thu Oct 22 2026 BookOS <packages@bookos.es> - 0.1.0-12
- bookos-comp --kiosko <programa>: una sola aplicación a pantalla completa, sin
  shell, atajos (salvo cambiar de TTY) ni gestos, que sigue la distribución de
  systemd-localed y termina con el código del programa. Lo usa bookos-welcome
  en el primer arranque en lugar de kwin_wayland.
* Tue Oct 20 2026 BookOS <packages@bookos.es> - 0.1.0-11
- La pantalla de recuperación pasa a bookos-desktop-recovery: KWin y PySide6
  dejan de ser obligatorios para la sesión.

* Fri Oct 09 2026 BookOS <packages@bookos.es> - 0.1.0-10
- Sonidos del tema bookos (con freedesktop de reserva) y sonidos al bloquear,
  desbloquear, capturar e iniciar sesión, desactivables con sonidos_interfaz.
- Pide pw-play y canberra-gtk-play, con los que suena.

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
