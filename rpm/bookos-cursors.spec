Name:           bookos-cursors
Version:        0.7.1
Release:        1%{?dist}
Summary:        Cursores claros y oscuros de BookOS
License:        LicenseRef-BookOS
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  librsvg2-tools
BuildRequires:  xcursorgen

%description
Cursores BookOS rasterizados desde sus SVG originales para las escalas del escritorio.

%prep
%setup -q

%build
bash scripts/build-cursors.sh Dark
bash scripts/build-cursors.sh Light

%install
for variante in Dark Light; do
    install -dm755 %{buildroot}%{_datadir}/icons/BookOS-$variante
    cp -r build/$variante/cursors %{buildroot}%{_datadir}/icons/BookOS-$variante/
done

%files
%{_datadir}/icons/BookOS-Dark/cursors/
%{_datadir}/icons/BookOS-Light/cursors/
