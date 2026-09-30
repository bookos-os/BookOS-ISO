Name:           bookos-meta
Version:        0.6.1
Release:        5%{?dist}
Summary:        BookOS umbrella package — pulls the full BookOS stack
License:        GPL-3.0
URL:            https://bookos.es/
BuildArch:      noarch

# ── System identity / look: PINNED to this exact release (macOS model) ──
# A version bump forces every visual piece to the SAME version atomically,
# so upgrading 0.5 → 0.6 brings the whole redesign in one dnf transaction.
Requires:       bookos-branding      >= 0.6.1-11
Requires:       bookos-icons         = %{version}
Requires:       bookos-icons         >= 0.6.1-2
Requires:       bookos-plasma-theme  = %{version}
Requires:       bookos-gtk-theme     = %{version}
# Integración de escritorio (ServiceMenus de Dolphin, livestate).
Requires:       bookos-desktop-integration >= 0.6.1-8
Requires:       bookos-desktop >= 0.1.0
# (sddm + wallpapers se entregan dentro de bookos-branding)

# ── Apps: con versión propia, solo necesitan un mínimo (no atadas al salto) ──
# Mínimos alineados con lo realmente publicado en store-files (subir cuando se
# publique una versión mayor de la app correspondiente).
Requires:       bookos-settings   >= 0.6.2
Requires:       bookos-store      >= 0.6.2
Requires:       bookos-calc       >= 0.6.2
Requires:       bookos-clock      >= 0.6.2
Requires:       bookos-notepad    >= 0.6.2
Requires:       bookos-shell      >= 0.6.2
Requires:       bookos-player     >= 0.6.2
Requires:       bookos-new        >= 0.6.2
Requires:       bookos-explorer   >= 0.6.2
Requires:       bookos-welcome
Requires:       bookos-keyring
# Plasma ya no forma parte de BookOS: el escritorio es bookos-desktop. Los
# paquetes que solo configuraban Plasma se retiran en las actualizaciones.
Obsoletes:      bookos-widgets < 0.6.2
Obsoletes:      bookos-look-and-feel < 0.6.2
Obsoletes:      bookos-desktop-defaults < 0.6.2
Requires:       sddm
Requires:       dolphin
Requires:       firefox
Requires:       kde-partitionmanager

%description
Umbrella package for the BookOS desktop. Installing or upgrading bookos-meta
brings the rest of the BookOS stack to the matching release version.

This RPM contains no files — it only defines Requires.

%files
# (empty)

%changelog
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
