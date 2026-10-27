Name:           bookos-shell
Version:        0.6.2
Release:        1%{?dist}
Summary:        BookOS Shell — terminal de BookOS
License:        LicenseRef-BookOS
URL:            https://bookos.es/
Source0:        bookos-shell
Source1:        bookos-shell.desktop
Requires:       webkit2gtk4.1
Requires:       gtk3
Requires:       libsoup3

%description
Terminal de BookOS (Tauri). Es el terminal por defecto del sistema:
Ctrl+Alt+T y "Abrir terminal aquí" lo lanzan (con konsole de reserva).

%install
install -Dm755 %{SOURCE0} %{buildroot}%{_bindir}/bookos-shell
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/applications/bookos-shell.desktop

%files
%{_bindir}/bookos-shell
%{_datadir}/applications/bookos-shell.desktop

%changelog
* Sun Jul 05 2026 BookOS <packages@bookos.es> - 0.6.1-1
- Primer empaquetado RPM (antes no estaba en ningún repo)
