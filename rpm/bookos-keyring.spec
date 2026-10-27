Name:           bookos-keyring
Version:        0.6.1
Release:        5%{?dist}
Summary:        BookOS release signing key and repository definitions
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch

Source0:        RPM-GPG-KEY-bookos
Source1:        bookos.repo

# DNF imports this local key outside an RPM transaction. ISO composition
# imports it explicitly; no recursive RPM invocation in package scriptlets.

%description
Clave pública con la que se firman los paquetes y los metadatos de BookOS,
más la definición de los repositorios.

La clave viaja DENTRO de la ISO, no se descarga. Descargar la clave del mismo
servidor que sirve los paquetes sería circular: quien controlase ese servidor
serviría su propia clave junto a sus propios paquetes y todo verificaría. Al
venir en el medio de instalación, la confianza se establece una sola vez, en
el momento en que el usuario decide instalar BookOS.

Por eso las actualizaciones no preguntan nada: dnf ya tiene la clave y
verifica cada paquete en silencio, hablando solo si algo no cuadra.

Huella: F8D9 6833 E356 1113 0227  335A 9A8F A3B2 E9E0 E64F

%prep
# Sin fuentes que desempaquetar.

%install
install -Dm644 %{SOURCE0} %{buildroot}/etc/pki/rpm-gpg/RPM-GPG-KEY-bookos
install -Dm644 %{SOURCE1} %{buildroot}/etc/yum.repos.d/bookos.repo

%files
%config(noreplace) /etc/yum.repos.d/bookos.repo
/etc/pki/rpm-gpg/RPM-GPG-KEY-bookos

%changelog
* Sat Aug 01 2026 BookOS <josrebe333@gmail.com> - 0.6.1-1
- Primer empaquetado de la clave de firma y los repos.
- La clave se instala desde la ISO; deja de descargarse del servidor.
