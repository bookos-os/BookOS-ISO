Name:           bookos-desktop-integration
Version:        0.6.1
# Release (no Version) sube con los añadidos: bookos-meta pinea `= %%{version}`.
Release:        10%{?dist}
Summary:        BookOS desktop integration — ServiceMenus (terminal, folder colors), default apps, WebKit env
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch
# Tarball topdir bookos-desktop-integration-%%{version}/ with:
#   bin/ servicemenus/ applications/ xdg/ environment/ cleanup/
Source0:        %{name}-%{version}.tar.gz

# Terminal ServiceMenu prefers bookos-shell, falls back to konsole.
Requires:       bookos-shell
# Folder colors reuse Papirus folder-<color> icons (already pulled by bookos-icons).
Requires:       papirus-icon-theme
# Desde 0.6.1-9 sin runners de KRunner, gestos (libinput-gestures) ni Live
# States: solo servían a Plasma, que ya no va en BookOS; los gestos los hace
# bookos-comp. La regla udev de los gestos daba a cualquier app de la sesión
# lectura directa de /dev/input (teclado incluido) y se va con ellos.

%description
BookOS integration bits for KDE apps that stay in BookOS (Dolphin):

 * ServiceMenus (right-click on a folder in Dolphin):
     - "Abrir terminal aquí"  -> bookos-shell or konsole in that folder
     - "Color de carpeta"     -> writes .directory Icon=folder-<color> (Papirus)
 * Default apps (terminal wrapper, mimeapps) and the WebKitGTK environment
   that Tauri apps need on Wayland.

Pulled by bookos-meta so it tracks the release version.

%prep
%setup -q

%install
# helper scripts
install -dm755 %{buildroot}%{_bindir}
install -m755 bin/bookos-open-terminal.sh   %{buildroot}%{_bindir}/bookos-open-terminal.sh
install -m755 bin/bookos-folder-color.sh    %{buildroot}%{_bindir}/bookos-folder-color.sh

# Dolphin / FolderView ServiceMenus
install -dm755 %{buildroot}%{_datadir}/kio/servicemenus
install -m644 servicemenus/*.desktop        %{buildroot}%{_datadir}/kio/servicemenus/

# Apps por defecto BookOS: terminal wrapper (Ctrl+Alt+T) + mimeapps del sistema
install -Dm644 applications/bookos-terminal.desktop %{buildroot}%{_datadir}/applications/bookos-terminal.desktop
install -Dm644 xdg/mimeapps.list %{buildroot}/etc/xdg/mimeapps.list

# WebKitGTK/Wayland: sin esto las apps Tauri mueren con "Error 71" (DMABUF)
install -Dm644 environment/60-bookos-webkit.conf %{buildroot}%{_prefix}/lib/environment.d/60-bookos-webkit.conf
install -dm755 %{buildroot}/etc/profile.d
printf 'export WEBKIT_DISABLE_DMABUF_RENDERER=1\n' > %{buildroot}/etc/profile.d/bookos-webkit.sh

# Limpieza de restos live (liveuser/autologin) en instalaciones EXISTENTES:
# unidad firstboot que llega vía dnf update; no corre en la sesión live
# (ConditionKernelCommandLine=!rd.live.image) y se marca hecha en /var/lib.
install -Dm755 cleanup/bookos-live-cleanup %{buildroot}%{_libexecdir}/bookos-live-cleanup
install -Dm644 cleanup/bookos-live-cleanup.service %{buildroot}%{_prefix}/lib/systemd/system/bookos-live-cleanup.service

%post
# ── Reparación de instalaciones EXISTENTES (llega vía dnf update) ────────────
# 1) Restos de 0.6.1-8: puentes de Live States habilitados para todas las
#    sesiones y el autostart de libinput-gestures copiado a cada home. Sus
#    ficheros ya no existen; sin esto quedarían enlaces y lanzadores rotos.
rm -f /etc/systemd/user/*/bookos-livestate-media.service \
      /etc/systemd/user/*/bookos-livestate-battery.service 2>/dev/null || :
rm -f /home/*/.config/autostart/libinput-gestures.desktop 2>/dev/null || :
# 2) Limpieza live firstboot: enable manual (los presets la dejarían apagada).
#    En el compose de la ISO es no-op hasta el siguiente arranque instalado.
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf %{_prefix}/lib/systemd/system/bookos-live-cleanup.service \
    /etc/systemd/system/multi-user.target.wants/bookos-live-cleanup.service 2>/dev/null || :

%files
%{_prefix}/lib/environment.d/60-bookos-webkit.conf
/etc/profile.d/bookos-webkit.sh
%{_bindir}/bookos-open-terminal.sh
%{_bindir}/bookos-folder-color.sh
%{_datadir}/kio/servicemenus/bookos-open-terminal.desktop
%{_datadir}/kio/servicemenus/bookos-folder-color.desktop
%{_libexecdir}/bookos-live-cleanup
%{_prefix}/lib/systemd/system/bookos-live-cleanup.service
%{_datadir}/applications/bookos-terminal.desktop
%config(noreplace) /etc/xdg/mimeapps.list
%changelog
* Thu Sep 24 2026 BookOS <josrebe333@gmail.com> - 0.6.1-9
- Fuera runners de KRunner, libinput-gestures y Live States (solo Plasma).
- Fuera la regla que hacía legible el número de serie y la de acceso a
  /dev/input de los gestos.
- Limpia los enlaces y autostarts que dejaba la versión anterior.

* Tue Jul 07 2026 BookOS <packages@bookos.es> - 0.6.1-7
- Gestos touchpad: qdbus6 (binario Arch, inexistente en Fedora) → gdbus call
- %%post repara homes existentes (conf qdbus6 o ausente) + conf fallback en /etc
- Limpieza liveuser/autologin post-instalación como unidad firstboot (viaja vía update)
* Sun Jul 05 2026 BookOS <packages@bookos.es> - 0.6.1-6
- WEBKIT_DISABLE_DMABUF_RENDERER=1 global: las apps Tauri crasheaban en Wayland (Error 71)
* Sat Jul 04 2026 BookOS <packages@bookos.es> - 0.6.1-5
- Apps por defecto: mimeapps.list (notepad/viewer), bookos-terminal.desktop
- KRunner: runners acciones/clima habilitados por defecto (EnabledByDefault)
* Sat Jul 04 2026 BookOS <packages@bookos.es> - 0.6.1-4
- Gestos de touchpad: libinput-gestures + config BookOS + autostart + udev uaccess
* Fri Jul 03 2026 BookOS <packages@bookos.es> - 0.6.1-3
- tmpfiles.d: DMI product_serial legible (0444) para el serial en "Acerca de este PC"
* Thu Jul 02 2026 BookOS <packages@bookos.es> - 0.6.1-2
- Live States: broker org.bookos.LiveStates + puentes MPRIS/UPower + CLI + lib
* Wed Jul 01 2026 BookOS <packages@bookos.es> - 0.6.1-1
- Initial: terminal + folder-color ServiceMenus; KRunner actions + weather runners
