Name:           bookos-new
Version:        0.6.2
Release:        2%{?dist}
Summary:        BookOS "¿Qué hay nuevo?" — novedades de la versión al primer inicio
License:        LicenseRef-BookOS
URL:            https://bookos.es/
# Binario Tauri precompilado (webkit2gtk4.1). No noarch.
Source0:        bookos-new
Source1:        bookos-new.desktop
Source2:        bookos-new-autostart.desktop
Source3:        bookos-new-icon.png
Source4:        bookos-new-icon.svg
Requires:       webkit2gtk4.1
Requires:       gtk3
Requires:       libsoup3

%description
Ventana de bienvenida de BookOS: muestra las novedades de la versión
(es/en según el idioma). Se abre sola una vez en el primer inicio de sesión
de cada usuario y queda en el menú como "Novedades de BookOS".

%install
install -Dm755 %{SOURCE0} %{buildroot}%{_bindir}/bookos-new
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/applications/bookos-new.desktop
# Primer login: se muestra una vez por usuario (stamp por versión)
install -Dm644 %{SOURCE2} %{buildroot}/etc/skel/.config/autostart/bookos-new-autostart.desktop
install -Dm644 %{SOURCE3} %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/bookos-new.png
install -Dm644 %{SOURCE4} %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/bookos-new.svg

%files
%{_datadir}/icons/hicolor/512x512/apps/bookos-new.png
%{_datadir}/icons/hicolor/scalable/apps/bookos-new.svg
%{_bindir}/bookos-new
%{_datadir}/applications/bookos-new.desktop
/etc/skel/.config/autostart/bookos-new-autostart.desktop

%changelog
* Sun Jul 05 2026 BookOS <packages@bookos.es> - 0.6.1-2
- Icono propio (src-tauri/icons) en hicolor; antes usaba el logo generico
* Sat Jul 04 2026 BookOS <packages@bookos.es> - 0.6.1-1
- Primera versión empaquetada: novedades 0.6.1 (es/en), autostart run-once
