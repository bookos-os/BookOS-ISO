Name:           bookos-branding
Version:        0.6.2
Release:        6%{?dist}
Summary:        BookOS branding (logos, wallpapers, SDDM/Plymouth themes)
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz
# Sin Requires: sddm. El tema de SDDM es un directorio más; quien instala SDDM
# es bookos-meta (y el kickstart de cada edición con escritorio). Pedirlo aquí
# metía Qt y SDDM en la edición servidor, que no tiene pantalla gráfica.
Requires:       plymouth

Provides:       system-logos
Conflicts:      fedora-logos
Conflicts:      generic-logos
# OJO: NO declarar «Provides: system-release». dnf deduce $releasever del paquete
# que provee system-release, y fedora-release lo hace versionado —system-release(44)—.
# Al proveerlo aquí sin versión, dnf tomaba la versión de este paquete y resolvía
# $releasever=0.6.1, con lo que Fedora y RPM Fusion devolvían 404 y el sistema se
# quedaba SIN actualizaciones de seguridad. El branding solo debe proveer system-logos.

%description
BookOS branding: replaces Fedora default logos, wallpapers, login screen,
boot splash and OS metadata with BookOS identity.

%prep
%setup -q

%install
# OS logos / icons
install -Dm644 logos/bookos-symbolic.svg       %{buildroot}/usr/share/icons/hicolor/scalable/apps/start-here.svg
install -Dm644 logos/bookos.svg                %{buildroot}/usr/share/pixmaps/bookos.svg
install -Dm644 logos/bookos.png                %{buildroot}/usr/share/pixmaps/bookos.png
# Icono del lanzador "Instalar BookOS" (liveinst)
if [ -f anaconda/pixmaps/bookos-install.svg ]; then
    install -Dm644 anaconda/pixmaps/bookos-install.svg %{buildroot}/usr/share/pixmaps/bookos-install.svg
fi

# Wallpapers
# Nunito (OFL) — reemplaza SN Pro (restrictiva); alias fontconfig para configs viejas
if [ -d fonts/nunito ]; then
    install -dm755 %{buildroot}%{_datadir}/fonts/bookos-nunito
    install -m644 fonts/nunito/*.ttf %{buildroot}%{_datadir}/fonts/bookos-nunito/
    install -m644 fonts/nunito/OFL.txt %{buildroot}%{_datadir}/fonts/bookos-nunito/
    install -Dm644 fonts/60-bookos-snpro-alias.conf         %{buildroot}%{_sysconfdir}/fonts/conf.d/60-bookos-snpro-alias.conf
fi

install -dm755 %{buildroot}/usr/share/backgrounds/bookos
cp -r wallpapers/* %{buildroot}/usr/share/backgrounds/bookos/

# El compositor de bookos-desktop busca el fondo en
# /usr/share/wallpapers/BookOS/{Light,Dark}/<familia>[_dark].png (fondo.rs), que
# NO es el formato de paquete de Plasma de más abajo (BookOS-Blue/contents/…).
# Sin esta copia, el escritorio nuevo no encuentra ningún fondo instalado.
install -dm755 %{buildroot}/usr/share/wallpapers/BookOS/Light
install -dm755 %{buildroot}/usr/share/wallpapers/BookOS/Dark
install -m644 wallpapers/Light/*.png %{buildroot}/usr/share/wallpapers/BookOS/Light/
install -m644 wallpapers/Dark/*.png  %{buildroot}/usr/share/wallpapers/BookOS/Dark/

# Paquetes de wallpaper para el SELECTOR de Plasma (/usr/share/wallpapers).
# Los archivos sueltos de /usr/share/backgrounds NO salen en el selector —
# por eso solo se veia el azul. Cada paquete lleva la variante clara como
# images/ y la oscura como images_dark/ (Plasma 6 cambia solo con el tema).
for lp in wallpapers/Light/*.png; do
    name=$(basename "$lp" .png)
    Name="$(tr '[:lower:]' '[:upper:]' <<< ${name:0:1})${name:1}"
    pkg=%{buildroot}/usr/share/wallpapers/BookOS-$Name
    install -Dm644 "$lp" "$pkg/contents/images/2880x1800.png"
    [ -f "wallpapers/Dark/${name}_dark.png" ] &&         install -Dm644 "wallpapers/Dark/${name}_dark.png" "$pkg/contents/images_dark/2880x1800.png"
    install -Dm644 "$lp" "$pkg/contents/screenshot.png"
    cat > "$pkg/metadata.json" <<METAEOF
{
    "KPlugin": {
        "Id": "BookOS-$Name",
        "Name": "BookOS $Name",
        "License": "LicenseRef-BookOS",
        "Authors": [{ "Name": "BookOS" }]
    }
}
METAEOF
done

# SDDM theme
install -dm755 %{buildroot}/usr/share/sddm/themes/bookos
cp -r sddm-theme/* %{buildroot}/usr/share/sddm/themes/bookos/

# Plymouth boot splash
install -dm755 %{buildroot}/usr/share/plymouth/themes/bookos
cp -r plymouth-theme/* %{buildroot}/usr/share/plymouth/themes/bookos/

# Tema del menú de GRUB.
#
# La ruta /boot/grub2/themes NO es negociable: GRUB lee el tema ANTES de montar
# la raíz, así que tiene que estar bajo su $prefix. En /usr/share no lo
# encuentra y el menú cae a texto plano sin dar ningún error.
if [ -f grub-theme/theme.txt ]; then
    install -dm755 %{buildroot}/boot/grub2/themes/bookos
    cp -r grub-theme/* %{buildroot}/boot/grub2/themes/bookos/
fi

# KDE Plasma lockscreen QML (staged; activated by bookos-settings toggle)
install -dm755 %{buildroot}/usr/share/bookos-settings/lockscreen
cp lockscreen/*.qml %{buildroot}/usr/share/bookos-settings/lockscreen/

# Cockpit lo busca por el ID de os-release (bookos). Ver
# BookOS-ISO/rpm/cockpit-branding/branding.css.
install -dm755 %{buildroot}/usr/share/cockpit/branding/bookos
install -m644 cockpit/branding.css cockpit/logo.png cockpit/apple-touch-icon.png \
    cockpit/favicon.ico %{buildroot}/usr/share/cockpit/branding/bookos/

# Anaconda installer branding — kept under a bookos/ subdir so it never
# conflicts with files owned by the anaconda package itself.
if [ -d anaconda ]; then
    install -dm755 %{buildroot}/usr/share/anaconda/bookos
    cp -r anaconda/* %{buildroot}/usr/share/anaconda/bookos/
fi

# Anaconda product profile — THIS is what makes the installer default to btrfs
# (file_system_type + btrfs partitioning) and load the BookOS WebUI stylesheet.
# Anaconda reads it from /usr/share/anaconda/product.d/ at runtime.
if [ -f anaconda/product.d/bookos.conf ]; then
    # The installer title comes from [Product], not from the profile detector.
    # Keep older source trees from inheriting Fedora's product_name.
    if ! grep -q '^product_name[[:space:]]*=[[:space:]]*BookOS$' anaconda/product.d/bookos.conf; then
        sed -i '1i\[Product]\nproduct_name = BookOS\n\n[Base Product]\nproduct_name = Fedora\n' anaconda/product.d/bookos.conf
    fi
    install -Dm644 anaconda/product.d/bookos.conf \
        %{buildroot}/usr/share/anaconda/product.d/bookos.conf
    # anaconda F35+ SOLO lee profile.d/ (con [Profile Detection] os_id=bookos);
    # product.d se mantiene por compatibilidad.
    install -Dm644 anaconda/product.d/bookos.conf \
        %{buildroot}/usr/share/anaconda/profile.d/bookos.conf
    # F44: anaconda SOLO carga perfiles de /etc/anaconda/profile.d (verificado
    # con pyanaconda real; /usr/share/anaconda/profile.d ni existe).
    install -Dm644 anaconda/product.d/bookos.conf \
        %{buildroot}%{_sysconfdir}/anaconda/profile.d/bookos.conf

    # BUG /var: el perfil trae `must_not_be_on_root = /var` (heredado de un
    # perfil tipo atomic/ostree) A LA VEZ que `default_scheme = BTRFS`, que solo
    # crea subvolúmenes para / y /home — NUNCA para /var. El particionado
    # automático no puede cumplir su propia regla, así que el comprobador de
    # almacenamiento de Anaconda aborta siempre con "Su /var debe estar en una
    # partición separada o un LV". BookOS hace los snapshots con snapper sobre el
    # subvolumen raíz, no necesita /var aparte, así que vaciamos la restricción
    # en las TRES copias instaladas. El segundo sed borra posibles líneas de
    # continuación indentadas (formato INI multilínea) para no dejar valor
    # colgando; el rango se cierra en la primera línea no indentada.
    for _p in %{buildroot}/usr/share/anaconda/product.d/bookos.conf \
              %{buildroot}/usr/share/anaconda/profile.d/bookos.conf \
              %{buildroot}%{_sysconfdir}/anaconda/profile.d/bookos.conf; do
        [ -f "$_p" ] || continue
        sed -i -e 's/^\([[:space:]]*must_not_be_on_root[[:space:]]*=\).*/\1/' \
               -e '/^[[:space:]]*must_not_be_on_root[[:space:]]*=$/,/^[^[:space:]]/{/^[[:space:]]\+[^[:space:]]/d}' \
               "$_p"
        # Arranque del sistema INSTALADO: sin menu_auto_hide (menú GRUB visible;
        # heredarlo de fedora-workstation deja grubenv con menu_auto_hide=1 y el
        # menú no sale nunca) y entrada EFI en EFI/fedora, donde shim-x64 y
        # grub2-efi-x64 instalan los binarios de verdad. Solo se añade si el
        # perfil no define ya [Bootloader]; si lo define, lo corrige el %post
        # del kickstart de la ISO (reescribe el perfil con configparser).
        grep -q '^\[Bootloader\]' "$_p" || \
            printf '\n[Bootloader]\nmenu_auto_hide = False\nefi_dir = fedora\n' >> "$_p"
    done
fi
# WebUI stylesheet at the path referenced by bookos.conf's webui_stylesheet key.
if [ -f anaconda/theme/anaconda-webui-bookos.css ]; then
    install -Dm644 anaconda/theme/anaconda-webui-bookos.css \
        %{buildroot}/usr/share/anaconda/cockpit/anaconda-webui/preload/bookos.css
fi
# GTK custom_stylesheet path referenced by bookos.conf (legacy fallback UI).
if [ -f anaconda/theme/anaconda-bookos.css ]; then
    install -Dm644 anaconda/theme/anaconda-bookos.css \
        %{buildroot}/usr/share/anaconda/pixmaps/bookos/anaconda-bookos.css
fi
# BookOS Welcome runs after installation. Do not ship the legacy Anaconda
# addon: it renames mounted Btrfs subvolumes behind Anaconda's storage model.

# ── Identidad del sistema: os-release + títulos del menú de arranque ────────
# Se generan aquí con heredoc en vez de venir en el tarball a propósito: así el
# arreglo vive en un único fichero y no depende de volver a correr
# rpm/collect-branding.sh para que el tarball los incluya.
install -dm755 %{buildroot}/usr/libexec
cat > %{buildroot}/usr/libexec/bookos-apply-identity <<'IDENT'
#!/bin/sh
# BookOS: reaplica la identidad del sistema (os-release + títulos de las
# entradas del menú de arranque) a partir de /etc/bookos-release.
#
# ¿Por qué hay que REAPLICARLA y no basta con escribirla al instalar?
# /etc/os-release lo posee fedora-release-common (como symlink a
# ../usr/lib/os-release) y /usr/lib/os-release lo posee
# fedora-release-identity-basic. Cualquier actualización de esos paquetes
# restaura la identidad de Fedora y borra la nuestra. Verificado en book5-pro:
# instalado el 2026-07-06 con el os-release de BookOS, perdido el 2026-07-12 al
# actualizar a fedora-release-common-44-18 (`rpm -V` limpio, es decir, los
# ficheros volvieron exactamente a los del RPM de Fedora). De ahí el
# %%transfiletriggerin del spec, que llama a este script.
#
# Nunca debe hacer fallar una transacción de rpm: todo va con guardas y sale 0.

set -u

REL=/etc/bookos-release
[ -r "$REL" ] || exit 0

# Se parsea con sed y NO con `.` a propósito: las instalaciones anteriores a
# 0.6.1-8 traen este fichero sin comillas (`INSTALLED=BookOS 0.6.1`), y
# sourcearlo intentaría ejecutar «0.6.1» como comando.
val() { sed -n "s/^$1=//p" "$REL" | head -n1 | sed -e 's/^"//' -e 's/"$//'; }

NAME="$(val NAME)"
VERSION="$(val VERSION)"
[ -n "$NAME" ] && [ -n "$VERSION" ] || exit 0

# El nombre visible es el del sistema a secas («BookOS»): sin versión ni canal
# (decisión de producto, 2026-09-11). Es lo que enseñan Plasma, el instalador y
# cualquier «acerca de»; la versión sigue en VERSION/VERSION_ID y en Ajustes, y
# el canal en /etc/bookos-release.
PRETTY="$NAME"

# ── os-release ─────────────────────────────────────────────────────────────
# Fichero REGULAR en /etc, no un symlink: la especificación de os-release manda
# leer /etc antes que /usr/lib, así que este gana sin tocar el fichero de
# Fedora. NO hacer `ln -sf /etc/os-release /usr/lib/os-release`: /etc/os-release
# es un symlink a ../usr/lib/os-release y eso cierra un bucle (ELOOP) que deja
# PRETTY_NAME vacío en todo el sistema.
rm -f /etc/os-release
cat > /etc/os-release <<EOF
NAME="$NAME"
PRETTY_NAME="$PRETTY"
ID=bookos
ID_LIKE=fedora
VERSION="$VERSION"
VERSION_ID=$VERSION
ANSI_COLOR="0;38;2;10;132;255"
HOME_URL="https://bookos.es/"
DOCUMENTATION_URL="https://bookos.es/docs"
SUPPORT_URL="https://bookos.es/support"
BUG_REPORT_URL="https://bookos.es/bugs"
EOF

# ── Títulos del menú de arranque (entradas BLS) ────────────────────────────
# Quien genera estas entradas en Fedora es /usr/lib/kernel/install.d/20-grub.install
# (NO el 90-loaderentry.install de systemd). Su función mkbls() hace, línea 52:
#     title ${NAME} (${kernelver}) ${VERSION}
#     grub_class ${ID}
# sourceando /etc/os-release. Con eso, N kernels instalados dan N entradas que
# empiezan todas por «BookOS» y solo se distinguen por la versión entre
# paréntesis. Es correcto —son el mismo sistema con distinto kernel— pero se lee
# como si hubiera varios BookOS instalados: reportado así por el usuario en
# book5-pro (2026-08-04, cuatro entradas «BookOS (<kver>) 0.6.1»).
#
# Lo que NO se puede hacer es agruparlos en un submenú al estilo de Ubuntu
# («Advanced options for Ubuntu ▸»): con BLS, /etc/grub.d/10_linux se limita a
# emitir `insmod blscfg` + `blscfg`, y el módulo blscfg no tiene ninguna noción
# de submenú (`strings /usr/lib/grub/*/blscfg.mod` no contiene submenu ni
# advanced). GRUB pinta las entradas planas y las ordena él por `version`.
# GRUB_DISABLE_SUBMENU solo afecta a lo que genera grub2-mkconfig, que con BLS
# no genera ninguna entrada de sistema.
#
# Así que lo único que controlamos es el TEXTO, y con eso basta: el kernel más
# nuevo se titula con el nombre del sistema a secas y los demás se etiquetan
# como alternativas suyas. El orden lo sigue decidiendo GRUB por `version`, con
# lo que el titulado «a secas» cae siempre en la primera entrada del menú.
#
# SIN LA VERSIÓN DE BookOS (decisión de producto, 2026-08-11). La entrada
# principal dice «BookOS» y punto. La versión es información del MEDIO —tiene
# sentido en el menú del USB, donde te dice qué estás a punto de instalar— pero
# en un equipo ya instalado solo es ruido: cambia con cada actualización, ya está
# en Ajustes, y obliga a releer la línea entera para distinguir dos entradas que
# solo se diferencian en el kernel. Con installonly_limit=1 el menú normal queda
# en dos líneas: «BookOS» y «BookOS (rescate)».
#
# Los acentos SÍ se pueden usar desde 0.6.1-10: /etc/default/grub pasó a
# GRUB_TERMINAL_OUTPUT="gfxterm" (lo pone zz-bookos-boot.ks, es requisito del
# tema gráfico) y la fuente .pf2 del tema cubre Latin-1. Antes era ASCII puro
# porque con "console" en EFI se usa la salida de texto de la firmware, que no
# garantiza UTF-8 y podía convertir una «ó» en basura. Si alguien vuelve a poner
# GRUB_TERMINAL_OUTPUT="console", hay que revertir «versión» → «version».
#
# El módulo blscfg pinta `title` tal cual y no lee el campo `version`
# (comprobado con `strings /usr/lib/grub/i386-pc/blscfg.mod`: las claves que
# parsea son linux, title, options, default_kernelopts, initrd, devicetree,
# grub_hotkey, grub_users, grub_class, grub_arg, early_initrd), así que el
# título es libre.
#
# Basta con reescribir el .conf: GRUB en Fedora escanea /boot/loader/entries en
# tiempo de arranque vía blscfg, así que no hace falta grub2-mkconfig.

# Kernel más nuevo. `sort -V` no es idéntico al vercmp de rpm que usa blscfg
# para ordenar, pero coincide en todo lo que produce Fedora (7.1.5-201 > 7.1.4-204
# > 6.19.10-300). Si alguna vez discrepara, el único efecto sería que el título
# «a secas» no cae en la primera entrada: cosmético, nunca impide arrancar.
# La de rescate queda fuera del cálculo — su `version` es 0-rescue-<machine-id>.
NEWEST="$(for e in /boot/loader/entries/*.conf; do
              [ -f "$e" ] || continue
              v="$(sed -n 's/^version[[:space:]]*//p' "$e" | head -n1)"
              case "$v" in ''|0-rescue-*) continue ;; esac
              echo "$v"
          done | sort -V | tail -n1)"

for e in /boot/loader/entries/*.conf; do
    [ -f "$e" ] || continue
    kver="$(sed -n 's/^version[[:space:]]*//p' "$e" | head -n1)"
    # Sin `version` no se puede clasificar la entrada; mejor no tocarla.
    [ -n "$kver" ] || continue
    if [ "${kver#0-rescue-}" != "$kver" ]; then
        title="$NAME (rescate)"
    elif [ -n "$NEWEST" ] && [ "$kver" = "$NEWEST" ]; then
        title="$NAME"
    else
        # 7.1.4-204.fc44.x86_64 → 7.1.4-204: basta para distinguirlas y no
        # desborda la línea del menú. Se conserva el release (-204) porque dos
        # kernels pueden compartir 7.1.4 y diferir solo en él.
        #
        # Con sed y NO con ${kver%%.fc*}: rpm expande macros sobre TODO el
        # cuerpo del spec, incluido el interior de este heredoc, y convierte
        # «%%» en «%». El paquete instalaría entonces ${kver%.fc*} —recorte
        # más corto en vez del más largo—, que aquí da lo mismo de pura
        # casualidad (solo hay un «.fc» en la cadena) pero es una trampa
        # esperando a la primera versión que no lo cumpla.
        short="$(echo "$kver" | sed 's/\.fc[0-9]*\..*$//')"
        title="$NAME (versión anterior $short)"
    fi
    sed -i -e "s|^title[[:space:]].*|title $title|" \
           -e "s|^grub_class[[:space:]].*|grub_class bookos|" \
           "$e" 2>/dev/null || true
done

exit 0
IDENT
chmod 755 %{buildroot}/usr/libexec/bookos-apply-identity

# ── Idioma del splash de arranque ───────────────────────────────────────────
cat > %{buildroot}/usr/libexec/bookos-plymouth-language <<'LANGSH'
#!/bin/sh
# BookOS: pone el splash de arranque en el idioma del sistema.
#
# El script de Plymouth no puede averiguarlo solo: corre dentro del initramfs y
# su intérprete no expone ni el entorno ni ficheros. Así que el idioma va escrito
# en una línea del propio script (LANGUAGE = "es";) y este programa la reescribe
# según /etc/locale.conf. Español si LANG empieza por «es» o no está definido
# (es el idioma por defecto de BookOS); inglés en cualquier otro caso.
#
#   --regenerate   si el idioma cambió, regenera el initramfs para que el
#                  cambio llegue al próximo arranque (tarda unos segundos)
#
# Nunca debe hacer fallar una transacción de rpm.

set -u

SCRIPT=/usr/share/plymouth/themes/bookos/bookos.script
[ -w "$SCRIPT" ] || exit 0

lang="$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | head -n1 | tr -d '"')"
case "$lang" in
    ''|es*) want=es ;;
    *)      want=en ;;
esac

current="$(sed -n 's/^LANGUAGE = "\([a-z]*\)";$/\1/p' "$SCRIPT")"
[ "$current" = "$want" ] && exit 0

sed -i "s/^LANGUAGE = \"[a-z]*\";\$/LANGUAGE = \"$want\";/" "$SCRIPT" || exit 0

if [ "${1:-}" = --regenerate ]; then
    plymouth-set-default-theme -R bookos || :
fi
exit 0
LANGSH
chmod 755 %{buildroot}/usr/libexec/bookos-plymouth-language

install -dm755 %{buildroot}/usr/lib/systemd/system
cat > %{buildroot}/usr/lib/systemd/system/bookos-plymouth-language.path <<'UNIT'
[Unit]
Description=Vigila el idioma del sistema para el splash de arranque

[Path]
PathChanged=/etc/locale.conf

[Install]
WantedBy=paths.target
UNIT
cat > %{buildroot}/usr/lib/systemd/system/bookos-plymouth-language.service <<'UNIT'
[Unit]
Description=Pone el splash de arranque en el idioma del sistema

[Service]
Type=oneshot
ExecStart=/usr/libexec/bookos-plymouth-language --regenerate
UNIT

# El splash se queda en pantalla hasta que el siguiente toma el KMS: SDDM o, con
# autologin, bookos-comp. sddm.service va After=plymouth-quit.service, y el
# `plymouth quit` de Fedora borra la pantalla antes, así que entre el logo y el
# escritorio quedaba un negro. bookos-desktop pinta el panel en su primer frame
# precisamente para no tener ese corte al entrar.
install -dm755 %{buildroot}/usr/lib/systemd/system/plymouth-quit.service.d
cat > %{buildroot}/usr/lib/systemd/system/plymouth-quit.service.d/10-bookos-retain-splash.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=-/usr/bin/plymouth quit --retain-splash
UNIT

# Hook de kernel-install: red de seguridad. Con os-release correcto,
# 20-grub.install ya titula bien las entradas nuevas él solo; este hook cubre el
# caso de que os-release estuviera revertido al de Fedora en el momento de
# instalar un kernel (entre una actualización de fedora-release y el trigger).
# Corre en el rango 95: después de 20-grub.install y 90-loaderentry.install (que
# crean/reescriben la entrada) y de 51-dracut-rescue.install (la de rescate), y
# antes de 99-grub-mkconfig.install.
install -dm755 %{buildroot}/usr/lib/kernel/install.d
cat > %{buildroot}/usr/lib/kernel/install.d/95-bookos-loaderentry.install <<'HOOK'
#!/bin/sh
# BookOS: retitula las entradas BLS tras instalar un kernel.
# Ver /usr/libexec/bookos-apply-identity para el por qué.
[ "$1" = add ] || exit 0
[ "${KERNEL_INSTALL_LAYOUT:-}" = bls ] || exit 0
[ -x /usr/libexec/bookos-apply-identity ] || exit 0
/usr/libexec/bookos-apply-identity || :
exit 0
HOOK
chmod 755 %{buildroot}/usr/lib/kernel/install.d/95-bookos-loaderentry.install

%files
# /usr/libexec y /usr/lib/kernel/install.d ya los poseen filesystem y
# systemd-udev, así que aquí solo van los ficheros.
/usr/libexec/bookos-apply-identity
/usr/lib/kernel/install.d/95-bookos-loaderentry.install
/usr/libexec/bookos-plymouth-language
/usr/lib/systemd/system/bookos-plymouth-language.path
/usr/lib/systemd/system/bookos-plymouth-language.service
%dir /usr/lib/systemd/system/plymouth-quit.service.d
/usr/lib/systemd/system/plymouth-quit.service.d/10-bookos-retain-splash.conf
/etc/anaconda/profile.d/bookos.conf
/usr/share/pixmaps/bookos-install.svg
/usr/share/fonts/bookos-nunito/
%config(noreplace) /etc/fonts/conf.d/60-bookos-snpro-alias.conf
/usr/share/wallpapers/BookOS-*/
/usr/share/wallpapers/BookOS/
/usr/share/icons/hicolor/scalable/apps/start-here.svg
/usr/share/pixmaps/bookos.svg
/usr/share/pixmaps/bookos.png
/usr/share/backgrounds/bookos/
/usr/share/sddm/themes/bookos/
/usr/share/plymouth/themes/bookos/
# Tema del menú de arranque. En /boot y no en /usr/share porque GRUB lo lee
# antes de montar la raíz (ver el %install).
/boot/grub2/themes/bookos/
/usr/share/bookos-settings/lockscreen/
/usr/share/anaconda/bookos/
/usr/share/anaconda/product.d/bookos.conf
/usr/share/anaconda/profile.d/bookos.conf
%dir /usr/share/anaconda/cockpit/anaconda-webui/preload
/usr/share/anaconda/cockpit/anaconda-webui/preload/bookos.css
/usr/share/anaconda/pixmaps/bookos/anaconda-bookos.css
/usr/share/cockpit/branding/bookos/

%post
# Antes del -R: actualizar el paquete deja bookos.script en español, y el
# initramfs regenerado tiene que llevar ya el idioma del sistema.
/usr/libexec/bookos-plymouth-language 2>/dev/null || true
plymouth-set-default-theme bookos -R 2>/dev/null || true
systemctl enable bookos-plymouth-language.path >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
# Identidad del sistema (os-release + títulos del menú de arranque).
/usr/libexec/bookos-apply-identity 2>/dev/null || true

# ── Apply BookOS look to the Anaconda WebUI installer ───────────────────
# The WebUI (Cockpit/React) lives in a versioned path that differs across
# Fedora releases, so we locate index.html at runtime instead of hardcoding.
# Adding bookos.css beside it + a <link> is non-destructive and re-applies
# cleanly if anaconda-webui updates.
THEME=/usr/share/anaconda/bookos/theme
if [ -f "$THEME/anaconda-webui-bookos.css" ]; then
    for idx in $(find /usr/share/cockpit/anaconda-webui /usr/share/anaconda -name index.html -path '*anaconda-webui*' 2>/dev/null); do
        dir=$(dirname "$idx")
        cp -f "$THEME/anaconda-webui-bookos.css" "$dir/bookos.css" 2>/dev/null || true
        # theme-aware brand marks referenced by the CSS
        cp -f "$THEME/bookos-logo-light.svg" "$dir/bookos-logo-light.svg" 2>/dev/null || true
        cp -f "$THEME/bookos-logo-dark.svg"  "$dir/bookos-logo-dark.svg"  2>/dev/null || true
        # light/dark toggle script (default light, choice persists in localStorage)
        cp -f "$THEME/bookos-theme.js" "$dir/bookos-theme.js" 2>/dev/null || true
        # inject the stylesheet link once
        if ! grep -q 'bookos.css' "$idx" 2>/dev/null; then
            sed -i 's#</head>#    <link rel="stylesheet" href="bookos.css">\n</head>#' "$idx" 2>/dev/null || true
        fi
        # inject the toggle script once (in <head>, no defer, so the theme
        # class is applied before first paint — no light/dark flash)
        if ! grep -q 'bookos-theme.js' "$idx" 2>/dev/null; then
            sed -i 's#</head>#    <script src="bookos-theme.js"></script>\n</head>#' "$idx" 2>/dev/null || true
        fi
    done
fi
# Kiosk-Firefox chrome tint (thin browser shell around the WebUI)
if [ -f "$THEME/userChrome.css" ]; then
    for fxdir in /usr/share/anaconda/firefox-theme/live/chrome /usr/share/anaconda/firefox-theme/default/chrome; do
        mkdir -p "$fxdir" 2>/dev/null && cp -f "$THEME/userChrome.css" "$fxdir/userChrome.css" 2>/dev/null || true
    done
fi
# Classic GTK Anaconda fallback CSS (older paths / non-WebUI)
[ -f "$THEME/anaconda-bookos.css" ] && cp -f "$THEME/anaconda-bookos.css" /usr/share/anaconda/anaconda-bookos.css 2>/dev/null || true
true

# ── Recuperar la identidad tras cada actualización de fedora-release ────────
# /etc/os-release lo posee fedora-release-common (symlink a
# ../usr/lib/os-release) y /usr/lib/os-release lo posee
# fedora-release-identity-basic: al actualizarse restauran la identidad de
# Fedora y borran la de BookOS. Este trigger corre AL FINAL de la transacción,
# cuando esos ficheros ya se han restaurado, y la vuelve a aplicar.
# Sin él, todo equipo BookOS se convierte en «Fedora Linux 44» en su primer
# `dnf upgrade` — y los kernels que se instalen después estrenan entradas de
# GRUB tituladas «Fedora Linux 44 (Forty Four)».
%transfiletriggerin -- /usr/lib/os-release /etc/os-release
/usr/libexec/bookos-apply-identity 2>/dev/null || true

%changelog
* Mon Oct 26 2026 BookOS <packages@bookos.es> - 0.6.2-6
- El perfil de Anaconda ya no pide /boot ni /boot/efi: con BTRFS salían como
  subvolúmenes y la partición EFI quedaba dentro del btrfs, sin GRUB arrancable.

* Tue Oct 20 2026 BookOS <packages@bookos.es> - 0.6.2-5
- Tema BookOS para Cockpit (login y panel), con el aspecto de la HIG.
- Ya no pide SDDM: lo trae bookos-meta. La edición servidor no lo instala.

* Mon Sep 28 2026 BookOS <packages@bookos.es> - 0.6.2-4
- Icono nuevo para «Instalar en el disco duro» (bookos-install.svg).

* Mon Sep 14 2026 BookOS <packages@bookos.es> - 0.6.2-3
- Splash de arranque nuevo: logo y barra fina; en actualizaciones, una línea
  con el progreso; al apagar, solo el logo. Se adapta a cualquier resolución.
- El splash sale en español o inglés según /etc/locale.conf. Lo aplica
  /usr/libexec/bookos-plymouth-language al instalar el paquete, y
  bookos-plymouth-language.path lo repite (regenerando el initramfs) cuando
  cambia el idioma del sistema.
- El splash sigue en pantalla hasta que SDDM o el compositor de BookOS pintan
  (plymouth quit --retain-splash): ya no hay un negro entre el logo y el
  escritorio.

* Sun Sep 13 2026 BookOS <packages@bookos.es> - 0.6.2-2
- Los fondos se instalan también en /usr/share/wallpapers/BookOS/{Light,Dark},
  que es donde los busca el compositor de bookos-desktop. Con solo el formato
  de paquete de Plasma, el escritorio nuevo arrancaba sin fondo.

* Fri Sep 11 2026 BookOS <packages@bookos.es> - 0.6.2-1
- 0.6.2. El sistema se llama «BookOS» a secas: PRETTY_NAME ya no lleva versión
  ni canal («BookOS 0.6.1 (dev)» → «BookOS»). La versión sigue en
  VERSION/VERSION_ID y en Ajustes; el canal, en /etc/bookos-release.

* Tue Aug 11 2026 BookOS <packages@bookos.es> - 0.6.1-10
- Tema gráfico del menú de arranque. Se instala en /boot/grub2/themes/bookos
  (no /usr/share: GRUB lee el tema antes de montar la raíz, así que tiene que
  estar bajo su $prefix). Fondo, marca de BookOS, iconos por clase de entrada
  —incluida la de Windows que genera os-prober— y Nunito convertida a .pf2.
  Lo activa zz-bookos-boot.ks con GRUB_THEME + GRUB_TERMINAL_OUTPUT=gfxterm;
  con el "console" que escribe Anaconda, GRUB ignora el tema en silencio.
- Las entradas del menú del sistema instalado ya no llevan la versión: dicen
  «BookOS» y «BookOS (rescate)» en vez de «BookOS 0.6.1 …». La versión es
  información del medio de instalación (el menú del USB sí la lleva), no del
  equipo, donde cambia en cada actualización y solo alarga la línea.
- Vuelven los acentos en los títulos («versión anterior»): con gfxterm y la
  fuente .pf2 del tema ya hay UTF-8 garantizado, que era el motivo del ASCII.

* Tue Aug 04 2026 BookOS <packages@bookos.es> - 0.6.1-9
- El menú de arranque ya no parece listar varios BookOS. Con el formato de
  Fedora, N kernels instalados daban N entradas «BookOS (<kver>) 0.6.1» que se
  leían como N sistemas distintos (reportado en book5-pro con cuatro). Ahora el
  kernel más nuevo se titula «BookOS 0.6.1» a secas, los anteriores
  «BookOS 0.6.1 (kernel anterior 7.1.4-204)» y la de rescate
  «BookOS 0.6.1 (rescate)». Los títulos son ASCII sin acentos porque
  GRUB_TERMINAL_OUTPUT=console no garantiza UTF-8 en EFI.
  No se usan submenús al estilo Ubuntu porque con BLS no existen: 10_linux solo
  emite `blscfg` y el módulo no tiene noción de submenú.

* Tue Aug 04 2026 BookOS <packages@bookos.es> - 0.6.1-8
- La identidad del sistema ya no se pierde al actualizar. /etc/os-release es de
  fedora-release-common y /usr/lib/os-release de fedora-release-identity-basic:
  al actualizarse restauraban «Fedora Linux 44» y borraban la identidad de
  BookOS. Diagnosticado en book5-pro: instalado el 2026-07-06, convertido en
  Fedora el 2026-07-12 por fedora-release-common-44-18. Se añade
  /usr/libexec/bookos-apply-identity y un %%transfiletriggerin que lo reaplica
  al final de esas transacciones.
- El menú de GRUB vuelve a decir «BookOS». Las entradas BLS las genera
  20-grub.install como «${NAME} (${kernelver}) ${VERSION}» con «grub_class ${ID}»
  leyendo /etc/os-release, así que al perderse la identidad los kernels nuevos
  salían como «Fedora Linux (7.1.4-204.fc44.x86_64) 44 (Forty Four)» mientras los
  viejos seguían diciendo BookOS — en book5-pro eso llevaba a arrancar a mano el
  kernel viejo por ser el único reconocible. bookos-apply-identity retitula las
  entradas ya existentes con ese mismo formato exacto, y el nuevo hook
  /usr/lib/kernel/install.d/95-bookos-loaderentry.install actúa de red de
  seguridad al instalar kernels.
  Nota: GRUB_DISTRIBUTOR de /etc/default/grub NO interviene en las entradas BLS;
  solo en lo que genera grub2-mkconfig (os-prober, submenús).

* Mon Jul 06 2026 BookOS <packages@bookos.es> - 0.6.1-6
- FIX /var: se vacía `must_not_be_on_root` en el perfil de Anaconda. Chocaba con
  default_scheme=BTRFS (que nunca crea /var aparte) y el instalador abortaba
  siempre pidiendo "/var en partición separada". Snapper no necesita /var aparte.
- FIX arranque instalado: perfil con menu_auto_hide=False (el heredado True
  dejaba grubenv con menu_auto_hide=1 → GRUB jamás mostraba menú) y
  efi_dir=fedora (entrada NVRAM apuntando donde shim/grub existen de verdad).
* Sun Jul 05 2026 BookOS <packages@bookos.es> - 0.6.1-5
- userChrome.css del instalador: restaura la regla :has() que colapsa TODA la
  barra de Firefox (antes se veia el chrome completo: VPN, extensiones, tabs)
* Sun Jul 05 2026 BookOS <packages@bookos.es> - 0.6.1-4
- Perfil anaconda en /etc/anaconda/profile.d (ruta real en F44) -> btrfs de verdad
- default_partitioning: free en GiB (60/40 se parseaban como bytes)
* %(LC_ALL=C date "+%a %b %d %Y") BookOS <packages@bookos.es> - 0.6-1
- 0.6: real Plymouth theme + Anaconda installer branding
