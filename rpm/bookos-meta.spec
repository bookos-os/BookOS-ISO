Name:           bookos-meta
Version:        0.7.1
Release:        1%{?dist}
Summary:        BookOS umbrella package — pulls the full BookOS stack
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch

# Los recursos tienen versiones propias. El manifiesto de construcción fija
# los RPM concretos de la ISO; igualar aquí sus versiones impedía instalar el
# tema de sonidos 0.6.5 junto al metapaquete 0.7.1.
Requires:       bookos-branding      >= 0.6.2-5
Requires:       bookos-icons         >= 0.6.1-2
Requires:       bookos-plasma-theme  >= 0.6.1-2
Requires:       bookos-gtk-theme     >= 0.6.1
Requires:       bookos-sounds        >= 0.6.5
Requires:       bookos-cursors       >= 0.7.1
# Asociaciones de archivos y entorno de las aplicaciones.
Requires:       bookos-desktop-integration >= 0.6.1-8
Requires:       bookos-desktop >= 0.1.1
Requires:       bookos-greeter >= 0.1.1

# ── Apps: con versión propia, solo necesitan un mínimo (no atadas al salto) ──
# Los mínimos distinguen las implementaciones GPUI de sus versiones Tauri anteriores.
Requires:       bookos-settings   >= 0.6.2
Requires:       bookos-store      >= 0.6.2
Requires:       bookos-calc       >= 0.6.2
Requires:       bookos-clock      >= 0.6.2
Requires:       bookos-notepad    >= 0.7.0
Requires:       bookos-shell      >= 0.6.2
Requires:       bookos-player     >= 0.6.2
Requires:       bookos-new        >= 0.6.2
Requires:       bookos-explorer   >= 0.7.0
Requires:       bookos-welcome    >= 1.0.0-10
Requires:       bookos-system-monitor
Requires:       bookos-fonts
Requires:       bookos-audio
Requires:       bookos-viewer
Requires:       bookos-voicerecorder
Requires:       bookos-calendar
Requires:       bookos-camera
Requires:       bookos-connect
Requires:       bookos-lumina
Requires:       bookos-teclas
Requires:       bookos-browser
Requires:       bookos-keyring
# Plasma ya no forma parte de BookOS: el escritorio es bookos-desktop. Los
# paquetes que solo configuraban Plasma se retiran en las actualizaciones.
Obsoletes:      bookos-widgets < 0.6.2
Obsoletes:      bookos-look-and-feel < 0.6.2
Obsoletes:      bookos-desktop-defaults < 0.6.2
Requires:       firefox
Requires:       kde-partitionmanager

%description
Umbrella package for the BookOS desktop. Installing or upgrading bookos-meta
brings the rest of the BookOS stack to the matching release version.

This RPM contains no files — it only defines Requires.

%files
# (empty)

%changelog
* Mon Oct 26 2026 BookOS <packages@bookos.es> - 0.7.1-1
- Todas las aplicaciones propias, escritorio actual y acceso con greetd.
- Los recursos conservan sus versiones propias; sonidos exige el tema actual.

* Tue Oct 20 2026 BookOS <packages@bookos.es> - 0.6.1-7
- Arrastra bookos-desktop-recovery, que sale de bookos-desktop.

* Fri Oct 09 2026 BookOS <packages@bookos.es> - 0.6.1-6
- Arrastra bookos-sounds, el tema de sonido propio.

* Thu Sep 24 2026 BookOS <josrebe333@gmail.com> - 0.6.1-5
- Fuera Plasma: sin plasma-workspace, bookos-widgets, bookos-look-and-feel
  ni bookos-desktop-defaults; los tres últimos se marcan como obsoletos.

* %(LC_ALL=C date "+%a %b %d %Y") BookOS <packages@bookos.es> - 0.6.1-2
- Rebuild from current spec: drop bogus bookos-clock>=1.0.0 / bookos-libfprint
  deps (stale rpm) that made 0.6.1-1 uninstallable and blocked widget upgrades.

* %(LC_ALL=C date "+%a %b %d %Y") BookOS <packages@bookos.es> - 0.6.1-1
- 0.6.1: corrected panel layout (live capture, no dev paths), widgets reliably
  installed, signed repos (gpgcheck), Spanish installer + assorted fixes.

* Fri Jun 19 2026 BookOS <packages@bookos.es> - 0.6-1
- 0.6: widgets pinned into the release set (macOS-style cohesive upgrade)
