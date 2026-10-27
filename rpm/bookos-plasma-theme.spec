Name:           bookos-plasma-theme
Version:        0.6.1
Release:        2%{?dist}
Summary:        BookOS Qt look — color schemes and Kvantum styles
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

%description
Color schemes and Kvantum styles that give the Qt/KDE apps kept in BookOS
(Dolphin, Partition Manager) the BookOS look. Since 0.6.1-2 it no longer ships
the Plasma desktop theme or Aurorae decorations: Plasma is not part of BookOS.
Shipped as part of the BookOS release (pinned by bookos-meta) so the whole look
updates in lockstep.

%prep
%setup -q

%install
# color-schemes/*.colors -> /usr/share/color-schemes/
if [ -d color-schemes ]; then
    install -dm755 %{buildroot}/usr/share/color-schemes
    cp -r color-schemes/* %{buildroot}/usr/share/color-schemes/
fi
# kvantum/* -> /usr/share/Kvantum/
if [ -d kvantum ]; then
    install -dm755 %{buildroot}/usr/share/Kvantum
    cp -r kvantum/* %{buildroot}/usr/share/Kvantum/
fi

%files
/usr/share/color-schemes/*
%dir /usr/share/Kvantum
/usr/share/Kvantum/*

%changelog
* Thu Sep 24 2026 BookOS <josrebe333@gmail.com> - 0.6.1-2
- Fuera el tema de escritorio de Plasma y las decoraciones Aurorae.

* %(LC_ALL=C date "+%a %b %d %Y") BookOS <packages@bookos.es> - 0.6-1
- 0.6: BookOS Plasma theme packaged
