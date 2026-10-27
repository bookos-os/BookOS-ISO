Name:           libfprint-bookos
Version:        1.94.9
Release:        2%{?dist}
Summary:        BookOS libfprint with FMV ETU906AXX-E (SPI) fingerprint support
# Fork of upstream libfprint adding the Samsung Galaxy Book5 Pro SPI sensor
# (likeablob/libfprint-fmv-etu906axx-e, SDCP-v2 branch). Replaces the stock
# libfprint so fprintd/the login stack drive the sensor out of the box.
License:        LGPL-2.1-or-later
URL:            https://github.com/likeablob/libfprint-fmv-etu906axx-e
# Tarball of the fork's source tree, produced by make-libfprint-rpm.sh
# (git archive --prefix=NAME-VERSION/ into ~/rpmbuild/SOURCES).
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson >= 0.59.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gusb) >= 0.3.0
BuildRequires:  pkgconfig(nss)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  gobject-introspection-devel
BuildRequires:  gtk-doc
BuildRequires:  cairo-gobject-devel

# This IS libfprint (a fork): it provides the same sonames/files, so it must
# take the place of the stock package rather than coexist with it.
Provides:       libfprint = %{version}-%{release}
Provides:       libfprint%{?_isa} = %{version}-%{release}
Conflicts:      libfprint
Obsoletes:      libfprint < %{version}-%{release}

%description
A drop-in replacement for libfprint that adds support for the FMV
ETU906AXX-E SPI fingerprint reader found in the Samsung Galaxy Book5 Pro
(and related Book4/Book5 SPI sensors), on top of upstream libfprint
%{version}. Built from the SDCP-v2 fork. Install in place of the stock
libfprint; fprintd picks the new driver up automatically.

# Ship the -devel files inside this package too (BookOS doesn't split them) so
# anything that BuildRequires libfprint-devel on the build host is satisfied.
Provides:       libfprint-devel = %{version}-%{release}
Provides:       libfprint-devel%{?_isa} = %{version}-%{release}
Conflicts:      libfprint-devel
Obsoletes:      libfprint-devel < %{version}-%{release}

%prep
%autosetup -n %{name}-%{version}

%build
# Match Fedora's libfprint: build the udev/SPI drivers, no examples/docs/tests.
%meson \
    -Ddrivers=all \
    -Dgtk-examples=false \
    -Ddoc=false \
    -Dintrospection=true \
    -Dudev_rules=enabled \
    -Dudev_hwdb=enabled \
    -Dinstalled-tests=false
%meson_build

%install
%meson_install
# Auto-generate the file list (udev/hwdb paths vary across Fedora releases, so
# let find enumerate everything meson installed instead of hardcoding).
( cd %{buildroot}
  find . -mindepth 1 \( -type f -o -type l \) -printf '/%%P\n' \
    -o -type d -empty -printf '%%%%dir /%%P\n'
) | grep -v '^/usr/share/doc' > %{_builddir}/%{name}-files.list

%files -f %{_builddir}/%{name}-files.list
%license COPYING
%doc README.md NEWS

%ldconfig_scriptlets

%changelog
* Fri Oct 09 2026 BookOS <packages@bookos.es> - 1.94.9-2
- egismoc: informar del acierto sin esperar al reset del sensor (1,7 s menos)

* Fri Jun 19 2026 BookOS <packages@bookos.es> - 1.94.9-1
- Initial: libfprint fork with FMV ETU906AXX-E SPI sensor (Book5 Pro)
