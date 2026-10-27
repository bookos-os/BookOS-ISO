# BookOS — kickstart base (shared by stable/beta/dev and by every edition)
# Builds a live ISO. What the image carries on top of this common part comes
# from edicion-<completa|minima|servidor>.ks, which profile.py inserts in the
# «Edición» block below.

# Primary locale = Spanish (BookOS target market): the live session AND the
# Anaconda installer boot in Spanish. --addsupport keeps extra locales
# installed so the installer language list offers them too.
lang es_ES.UTF-8 --addsupport=en_US.UTF-8
keyboard --vckeymap=es --xlayouts='es'
# Default sensato para es_ES; la página de fecha/hora del WebUI queda VISIBLE
# (es la única que BookOS Welcome no cubre) por si el usuario está en otra zona.
timezone Europe/Madrid
selinux --enforcing
network --bootproto=dhcp --device=link --activate --onboot=on

bootloader --location=mbr --append="rhgb quiet rd.live.image"
# Live image rootfs sizing for livemedia-creator. This is the SIZE OF THE LIVE
# IMAGE being built, not the installed system — Anaconda chooses the target
# disk layout at install time (Fedora's automatic install defaults to btrfs,
# which is what we want for snapshots).
part / --size=20000 --fstype="ext4"

# Root account locked (no direct root login). Anaconda still requires the Root
# password spoke to be "completed" in non-interactive mode, so this line must
# be present even though we disable the account.
rootpw --lock

# Live user is created at the END of %post (not here) so it is added AFTER the
# RPMs have populated /etc/skel — useradd -m then copies the FULL BookOS config
# (theme, autostart, launchers) into its home. Creating it
# here (the old `user` directive) ran before skel existed, which is why every
# skel write needed a manual /home/liveuser copy and why widgets/theme kept
# going missing. See the "Live user" block at the bottom of %post.

reboot --eject

# ── Repos ─────────────────────────────────────────────────────────────────
# Base install source — must be declared with `url` (not `repo`), or lorax
# errors: "repo can only be used within the url install method".
url --mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
repo --name=fedora --mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
repo --name=rpmfusion-free --mirrorlist=https://mirrors.rpmfusion.org/metalink?repo=free-fedora-$releasever&arch=$basearch
# BookOS apps (calc, clock, notepad, settings, store…) live in the store-files
# repo. They must be available AT INSTALL TIME — bookos-meta Requires them — so
# declare the repo here, not only in %post (which only configures the installed
# system). Without this anaconda errors "No match for argument: bookos-calc".
repo --name=bookos-apps --baseurl=https://bookos.es/store-files/
# BookOS OS repo is defined by the per-channel kickstart (stable/beta/dev.ks),
# not here, to avoid a duplicate "bookos" repo definition.

# ── Packages ──────────────────────────────────────────────────────────────
# Lo que lleva toda edición: arranque, instalador, identidad y firma. Cada
# edicion-*.ks añade su propia %packages; pykickstart las junta en una lista,
# pero las opciones de la cabecera las decide la ÚLTIMA sección (medido con
# pykickstart de F44: una segunda sección sin --exclude-weakdeps lo apaga para
# todas). Por eso todas la repiten, y test_profile lo comprueba.
# Missing requested packages must fail the compose.
%packages --exclude-weakdeps
@core
@hardware-support
NetworkManager
firewalld
chrony
sudo
dnf5
btrfs-progs
dosfstools
e2fsprogs
cryptsetup
less
nano
unzip
tar
curl
grub2-pc
grub2-tools
grub2-tools-minimal
kernel
kernel-modules-extra
# ── Languages ───────────────────────────────────────────────────────────────
# Ship English + Spanish so the installer and the live session can switch
# language (and KDE/apps show translated UI). langpacks-XX pull the matching
# glibc locale, hunspell dict, fonts and app translations. Add more lines
# (langpacks-fr, -pt, -de…) to bundle further languages.
langpacks-en
langpacks-es
glibc-langpack-en
glibc-langpack-es
# SELinux: `selinux --enforcing` makes anaconda run load_policy during install.
# Without these it dies: "No such file or directory: '/usr/sbin/load_policy'".
policycoreutils
selinux-policy-targeted
# Required by livemedia-creator to produce a bootable live ISO
dracut-live
dracut-config-generic
# ISO bootloader bits (lorax builds the El Torito BIOS + UEFI boot at compose
# time; these provide the grub2 modules it needs, mirroring Fedora's own live
# kickstarts). Without grub2-pc-modules: "cannot open .../i386-pc/moddep.lst".
grub2-pc-modules
grub2-efi-x64
grub2-efi-x64-cdboot
shim-x64
syslinux
# grub2-tools-extra trae los módulos gráficos que necesita el tema de GRUB
# (gfxterm/gfxmenu/png/jpeg) además de grub2-mkfont. Sin él, GRUB_THEME apunta a
# un theme.txt que nadie sabe pintar y el menú cae a texto plano en silencio.
grub2-tools-extra
# os-prober: SIN ESTE PAQUETE, GRUB_DISABLE_OS_PROBER=false (que ponemos en el
# post-script de Anaconda) no hace absolutamente nada — grub2-mkconfig salta la
# detección de otros sistemas sin decir ni pío y Windows nunca sale en el menú.
# Es exactamente la queja del usuario en el dual-boot del Galaxy Book.
os-prober
# Anaconda ejecuta efibootmgr chrooteado en el destino al instalar el gestor
# de arranque; anaconda-install-env-deps 44.30 (F44) ya NO lo arrastra como
# dependencia dura → sin esto la instalación muere con
# "[Errno 2] No existe el fichero o el directorio: 'efibootmgr'".
efibootmgr

# Snapshot / rollback stack (btrfs) — lets BookOS Settings snapshot before
# every release upgrade and roll back from GRUB if something breaks.
# (No dnf snapper plugin: it isn't packaged on Fedora/dnf5; BookOS Settings
#  takes the snapshot itself in apply_bookos_release.)
snapper
inotify-tools

# Plymouth: el tema BookOS es ModuleName=script — sin este plugin el splash
# cae al spinner/texto de Fedora (bug #7).
plymouth-plugin-script

# Clave de firma + definición de repos. Va PRIMERO: sin ella los repos con
# gpgcheck=1 no tienen con qué verificar y dnf pediría confirmación de clave.
bookos-keyring
bookos-branding
# Optional apps — substituted by build-iso.sh when "all apps" is requested.
__BOOKOS_OPTIONAL_APPS__

# Anaconda installer for live media install-to-disk. La interfaz (WebUI o
# texto) la elige cada edición; anaconda-live arrastra la WebUI igualmente.
anaconda-live
anaconda-install-env-deps

# NOTE: we DON'T exclude fedora-logos/generic-logos here. They provide
# `system-logos`, required by breeze-icon-theme and the whole KDE stack; while
# the bookos repo isn't yet pulled into the build, excluding them breaks the
# entire dependency tree. BookOS identity is applied in %post (os-release etc.).
# Once bookos-branding installs from the repo (it Provides system-logos and
# Conflicts fedora-logos), re-add the exclusions.
%end

# ── Edición ────────────────────────────────────────────────────────────────
# Va ANTES de la %post común: lo que la edición cambie en los lanzadores y en
# /etc/skel tiene que estar hecho cuando esa %post los copia y crea liveuser.
__BOOKOS_EDITION__

# ── Post-install: branding overrides ──────────────────────────────────────
%post
# /etc/bookos-release identifies channel + version (read by Settings app y por
# /usr/libexec/bookos-apply-identity, de bookos-branding).
# Los valores van ENTRECOMILLADOS: sin comillas, `INSTALLED=BookOS 0.6.1` hace
# que cualquier `. /etc/bookos-release` intente ejecutar «0.6.1» como comando.
# Aun así, los consumidores lo parsean con sed en vez de sourcearlo, para no
# romperse en los equipos ya instalados que tienen la versión sin comillas.
cat > /etc/bookos-release <<'EOF'
NAME="__BOOKOS_NAME__"
VERSION="__BOOKOS_VERSION__"
CHANNEL="__BOOKOS_CHANNEL__"
INSTALLED="__BOOKOS_NAME__ __BOOKOS_VERSION__"
EOF

# /etc/os-release rewrite (overrides Fedora identity)
#
# OJO CON LA TOPOLOGÍA — aquí había un bug que dejaba os-release ILEGIBLE.
# fedora-release-common instala /etc/os-release como symlink relativo a
# ../usr/lib/os-release, así que un `cat > /etc/os-release` escribe A TRAVÉS del
# enlace, en /usr/lib/os-release. El `ln -sf /etc/os-release
# /usr/lib/os-release` que había aquí cerraba entonces el bucle:
#     /etc/os-release -> ../usr/lib/os-release -> /etc/os-release
# → ELOOP. Consecuencia: PRETTY_NAME vacío en TODO el sistema y, en particular,
# 90-loaderentry.install (systemd) cayendo a su fallback de la línea 78
# (`PRETTY_NAME="Linux $KERNEL_VERSION"`), con lo que el menú de GRUB mostraba
# «Linux 6.19.10-300.fc44.x86_64» en vez de «BookOS».
# Verificado en book5-pro sobre la instalación del 2026-07-06.
#
# Por eso: borrar el symlink PRIMERO y escribir un fichero REGULAR en /etc.
# /usr/lib/os-release se deja intacto (es de fedora-release-identity-basic); la
# especificación de os-release manda leer /etc antes que /usr/lib, y
# 90-loaderentry.install lo respeta (líneas 70-76).
#
# Esto NO es durable por sí solo: /etc/os-release lo posee
# fedora-release-common, así que el primer `dnf upgrade` que lo actualice
# restaura el symlink de Fedora y borra esta identidad (pasó en book5-pro el
# 2026-07-12 con fedora-release-common-44-18). Quien la reaplica después es el
# %transfiletriggerin de bookos-branding → /usr/libexec/bookos-apply-identity.
#
# PRETTY_NAME es el nombre a secas, sin versión ni canal (decisión de producto,
# 2026-09-11): es lo que enseña el instalador («BookOS installation», «To begin
# using BookOS, reboot…») y Plasma. La versión sigue en VERSION/VERSION_ID.
# Mismo formato que escribe bookos-apply-identity en el sistema instalado.
rm -f /etc/os-release
cat > /etc/os-release <<'EOF'
NAME="__BOOKOS_NAME__"
PRETTY_NAME="__BOOKOS_NAME__"
ID=bookos
ID_LIKE=fedora
VERSION="__BOOKOS_VERSION__"
VERSION_ID=__BOOKOS_VERSION__
ANSI_COLOR="0;38;2;10;132;255"
HOME_URL="https://bookos.es/"
DOCUMENTATION_URL="https://bookos.es/docs"
SUPPORT_URL="https://bookos.es/support"
BUG_REPORT_URL="https://bookos.es/bugs"
EOF

# Nombre de producto del instalador. liveinst lo saca de /etc/system-release,
# que es de Fedora («Fedora release 44») → ANACONDA_PRODUCTNAME=Fedora, y con
# ese nombre Anaconda crea la entrada UEFI del firmware (efi.py: efibootmgr -L
# <producto>): el menú de arranque del portátil listaba «Fedora» junto a la
# «BookOS» de bookos-boot-finalize. /.buildstamp es el mecanismo previsto para
# fijarlo (pyanaconda/core/product.py lo lee DESPUÉS del entorno y solo pisa
# las claves que trae): solo Product; versión y final siguen viniendo de
# liveinst. Con Product=BookOS la entrada ya nace «BookOS», bookos-boot-finalize
# la reconoce en vez de duplicarla, y efi.py al reinstalar solo borra entradas
# «BookOS» antiguas, nunca las de un Fedora de verdad. No tocamos
# /etc/system-release: es de fedora-release-common y un update lo restauraría.
# El sistema instalado no lo necesita: lo borra bookos-live-cleanup.
printf '[Main]\nProduct=__BOOKOS_NAME__\n' > /.buildstamp

# Hostname default (fallback; the model-detect service below overrides it on
# real Galaxy Book hardware so the installer shows e.g. "book5-pro").
echo "bookos" > /etc/hostname

# NOTE: the live user gets the FULL BookOS appearance automatically because it
# is created at the end of %post (useradd -m copies the finished /etc/skel). No
# manual /home/liveuser copies needed anymore.

# ── Model-based hostname ────────────────────────────────────────────────
# Derives the hostname from the Samsung DMI model code (book5-pro, book4-edge,
# …) so the installer's default — and thus the installed system — is named
# after the laptop. Runs once (stamp file); the live sets it before Anaconda,
# so the install inherits it. User renames in the installer still win.
cat > /usr/libexec/bookos-set-hostname <<'SH'
#!/bin/sh
STAMP=/var/lib/bookos/hostname-set
[ -f "$STAMP" ] && exit 0
code=$(cat /sys/class/dmi/id/product_name /sys/class/dmi/id/board_name 2>/dev/null | tr 'a-z' 'A-Z')
case "$code" in
  *QQHA*) h=book5-pro-360 ;;
  *XHA*)  h=book5-pro ;;
  *QHA*)  h=book5-360 ;;
  *XHD*)  h=book5 ;;
  *XGL*)  h=book4-ultra ;;
  *QKG*)  h=book4-edge ;;
  *QGK*)  case "$code" in *960*|*964*) h=book4-pro-360 ;; *) h=book4-360 ;; esac ;;
  *XGK*)  case "$code" in *940*|*944*|*960*) h=book4-pro ;; *) h=book4 ;; esac ;;
  *XGJ*)  h=book4 ;;
  *)      h="" ;;
esac
mkdir -p /var/lib/bookos
if [ -n "$h" ]; then
  # El unit corre con DefaultDependencies=no, antes de D-Bus → hostnamectl
  # normalmente falla ahí. El fallback escribe /etc/hostname Y aplica el
  # hostname al kernel para este boot (si no, el live seguiría como "bookos").
  hostnamectl set-hostname "$h" 2>/dev/null || {
    echo "$h" > /etc/hostname
    hostname "$h" 2>/dev/null || true
  }
fi
touch "$STAMP"
SH
chmod +x /usr/libexec/bookos-set-hostname

cat > /etc/systemd/system/bookos-hostname.service <<'UNIT'
[Unit]
Description=Set BookOS hostname from laptop model
DefaultDependencies=no
After=local-fs.target
Before=anaconda.service sddm.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/bookos-set-hostname
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable bookos-hostname.service 2>/dev/null || true

# ── Persistent BookOS repos on the installed system ─────────────────────────
# (The kickstart `repo` lines above are build-time only; these .repo files are
#  what stays on disk so the system can update after install.)
# dnf expands $releasever / $basearch at runtime, so the same file works on any
# Fedora base. The active channel is enabled; the others are present but off so
# BookOS Settings (set_update_channel) can switch between them.
# Importar la clave de firma en la base de datos de rpm.
# Tiene que ser AQUÍ y no en un scriptlet de bookos-keyring: dentro de una
# transacción de rpm (tanto en %post como en %posttrans) la base de datos está
# bloqueada y `rpm --import` falla en silencio. Este %post del kickstart corre
# fuera de toda transacción, así que sí funciona.
# Sin esto dnf se las arregla igualmente —importa la clave sola desde el
# file:// la primera vez— pero suelta un "repomd.xml GPG signature verification
# error" antes de hacerlo, que asusta sin motivo.
if [ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-bookos ]; then
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-bookos || exit 1
fi

mkdir -p /etc/yum.repos.d
# OJO — los tres canales apuntan HOY al mismo repo (/store-files/), el único
# que existe en el servidor. La ruta anterior,
# https://bookos.es/repo/fedora/$releasever/$basearch/<canal>/, NUNCA se creó:
# devolvía 403/404 y, como todos llevan skip_if_unavailable=True, dnf los
# ignoraba en silencio. Resultado: los sistemas instalados no recibían ninguna
# actualización y no daban ni un error.
# Cuando se separen los canales de verdad en el servidor, basta con devolver a
# cada baseurl su ruta; los nombres de sección y el conmutador de
# BookOS Settings (set_update_channel) siguen siendo válidos.
cat > /etc/yum.repos.d/bookos-os.repo <<EOF
# BookOS system channels — bookos-meta + branding/themes (OS updates)
[bookos-stable]
name=BookOS (stable)
baseurl=https://bookos.es/store-files/
enabled=$([ "__BOOKOS_CHANNEL__" = "stable" ] && echo 1 || echo 0)
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-bookos
metadata_expire=6h
skip_if_unavailable=True

[bookos-beta]
name=BookOS (beta)
baseurl=https://bookos.es/store-files/
enabled=$([ "__BOOKOS_CHANNEL__" = "beta" ] && echo 1 || echo 0)
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-bookos
metadata_expire=6h
skip_if_unavailable=True

[bookos-dev]
name=BookOS (dev)
baseurl=https://bookos.es/store-files/
enabled=$([ "__BOOKOS_CHANNEL__" = "dev" ] && echo 1 || echo 0)
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-bookos
metadata_expire=6h
skip_if_unavailable=True
EOF

# El repo de apps (/etc/yum.repos.d/bookos.repo) lo instala bookos-keyring; no
# se reescribe aquí. Antes se sobrescribía con un heredoc idéntico: dos fuentes
# de verdad para el mismo fichero y `rpm -V bookos-keyring` lo daba por
# modificado.
#
# gpgcheck=1 verifica la firma de cada paquete. repo_gpgcheck=0 a propósito:
# probado con dnf5 5.4.5 (Fedora 44) en contenedor, con repo_gpgcheck=1 dnf
# pregunta "Importing OpenPGP key… Is this ok [y/N]" aunque la clave ya esté en
# la base de rpm, porque guarda la de metadatos en /var/cache/libdnf5/<repo>/
# pubring, y vuelve a preguntar si esa caché se borra o cambia la baseurl.
# Con repo_gpgcheck=0 y la clave importada abajo, no pregunta nada.
#
# gpgkey apunta a un fichero LOCAL que instala bookos-keyring, no a una URL:
# descargar la clave del mismo servidor que sirve los paquetes es circular —
# quien controlase ese servidor serviría su clave junto a sus paquetes y todo
# verificaría. Al venir en la ISO, la confianza se establece una sola vez.
#
# Publicar SIEMPRE con Bookos-web/deploy/sign-and-publish.sh, que firma fuera
# del servidor. Un paquete subido sin firmar deja de instalarse.

# ── First-boot system update (installed system only) ────────────────────────
# A freshly-installed image is as old as the ISO. This one-shot brings it
# current on the first boot AFTER install, using the .repo channels written
# above. Guards:
#   ConditionKernelCommandLine=!rd.live.image  → NEVER runs in the live session
#     (the live ISO always boots with rd.live.image; the installed disk does not),
#     so the live user never sees an update running.
#   Gated on a stamp file → runs once on success; if there's no network yet it
#     leaves no stamp and simply retries on the next boot until one run succeeds.
# It does not block graphical login (oneshot under multi-user.target, after
# network-online). Unavailable repositories must leave the stamp absent so
# the update is retried instead of being incorrectly marked complete.
install -d -m755 /usr/libexec/bookos
cat > /usr/libexec/bookos/firstboot-update <<'UPD'
#!/bin/bash
# Bring the freshly-installed system up to date, once.
set -u
STAMP=/var/lib/bookos/firstboot-update.done
[ -e "$STAMP" ] && exit 0
install -d -m755 /var/lib/bookos
# --refresh: don't trust cached metadata from the ISO build.
if dnf -y --refresh --setopt='*.skip_if_unavailable=False' upgrade; then
    date -u +%FT%TZ > "$STAMP"
else
    echo 'BookOS first-boot update failed; retrying on the next boot' >&2
    exit 1
fi
exit 0
UPD
chmod +x /usr/libexec/bookos/firstboot-update

cat > /etc/systemd/system/bookos-firstboot-update.service <<'UNIT'
[Unit]
Description=BookOS first-boot system update
# Live ISO always carries rd.live.image on the kernel cmdline; the installed
# system does not — this keeps the update out of the live session entirely.
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/var/lib/bookos/firstboot-update.done
Wants=network-online.target
After=network-online.target
# Don't fight the store / a manual dnf run.
After=dnf-makecache.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/bookos/firstboot-update
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable bookos-firstboot-update.service 2>/dev/null || true

# ── Escritorio, autologin del live y lanzador del instalador ────────────────
# El servidor conserva el acceso de consola de edicion-servidor.ks.
# Sin sangría dentro del if: los heredocs no la admiten.
if rpm -q --quiet bookos-desktop; then
# La edición mínima conserva SDDM; la completa usa el greeter propio.
if rpm -q --quiet sddm; then
# SDDM default theme (assuming bookos-branding installs theme files)
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/bookos-theme.conf <<'EOF'
[Theme]
Current=bookos
EOF
fi

# Live session auto-login: boot STRAIGHT to the BookOS desktop, no SDDM prompt.
# (The liveuser password is cleared in the "Live user" block at the end of %post;
#  here we only write the SDDM autologin config.) Select an installed session;
# fail the compose rather than shipping an autologin target that cannot start.
# zz- prefix so it wins over any other drop-in.
select_live_session() {
    if [ -f /usr/share/wayland-sessions/bookos.desktop ]; then
        printf '%s\n' bookos.desktop
    else
        echo 'ERROR: falta /usr/share/wayland-sessions/bookos.desktop (bookos-desktop)' >&2
        return 1
    fi
}
LIVE_SESSION=$(select_live_session) || exit 1
if rpm -q --quiet bookos-greeter; then
# initial_session solo entra una vez por arranque: al salir aparece nuestro greeter.
cp /etc/greetd/bookos.toml /etc/greetd/bookos-live.toml
cat >> /etc/greetd/bookos-live.toml <<'EOF'

[initial_session]
command = "/usr/bin/bookos-session"
user = "liveuser"
EOF
mkdir -p /etc/systemd/system/greetd.service.d
cat > /etc/systemd/system/greetd.service.d/zz-bookos-live.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/greetd --config /etc/greetd/bookos-live.toml
EOF
else
cat > /etc/sddm.conf.d/zz-live-autologin.conf <<EOF
[Autologin]
User=liveuser
# SDDM expects the session id without the .desktop suffix.
Session=${LIVE_SESSION%.desktop}
Relogin=false
EOF
fi

# ── Installer launcher on the live desktop ──────────────────────────────
# Without livesys-scripts nothing places the "Install to Hard Drive" icon on
# the live user's desktop. Copy anaconda's launcher there (and to /etc/skel so
# it survives the liveuser home copy), marked trusted so Plasma runs it.
for LAUNCH in /usr/share/applications/liveinst.desktop /usr/share/applications/anaconda.desktop; do
    [ -f "$LAUNCH" ] || continue
    # The stock launcher ships Fedora's icon — rebrand it (system-wide, so the
    # app menu / launchpad show BookOS too, and the Desktop copy inherits it).
    sed -i 's|^Icon=.*|Icon=/usr/share/pixmaps/bookos-install.svg|' "$LAUNCH" 2>/dev/null || true
    DESK=/etc/skel/Desktop
    mkdir -p "$DESK"
    cp -f "$LAUNCH" "$DESK/" 2>/dev/null || true
    # Plasma only offers "Open with…" for a non-executable .desktop file.
    # Preserve the executable bit explicitly; cp otherwise inherits the mode
    # of Anaconda's package file (0644).
    chmod 0755 "$DESK/$(basename "$LAUNCH")" 2>/dev/null || true
    # KDE: mark executable desktop files as trusted to skip the warning
    kwriteconfig6 --file "$DESK/$(basename "$LAUNCH")" --group "Desktop Entry" --key "X-KDE-AuthorizeExecution" "true" 2>/dev/null || true
done
fi

# ── Plymouth (splash de arranque) ──────────────────────────────────────────
# Plymouth NO lee el tema del disco al arrancar: lo lee de DENTRO del initramfs,
# porque cuando corre todavía no hay raíz montada. Así que hacen falta dos cosas
# y las dos tienen que llegar al equipo instalado:
#
#   1. /etc/plymouth/plymouthd.conf con Theme=bookos  ← esto lo hace la línea de
#      abajo, y como la instalación live copia este rootfs tal cual, viaja solo.
#   2. Un initramfs REGENERADO con ese tema dentro  ← esto NO viaja solo, y es
#      lo que faltaba: el `-R` de aquí corre en el compose, no en el equipo.
#      Lo hace ahora zz-bookos-boot.ks (`dracut -f --regenerate-all`).
#
# Esta config de dracut se escribe en el rootfs del live para que viaje al disco
# y valga también para los kernels que se instalen después:
#   · plymouth como módulo EXPLÍCITO — con hostonly, dracut a veces lo omite y el
#     arranque cae al texto de systemd.
#   · los drivers KMS metidos a la fuerza. En ultrabooks recientes (Core Ultra
#     Lunar Lake, que es el Galaxy Book del usuario) el panel es eDP y hasta que
#     `xe`/`i915` no hacen el modeset no hay nada que pintar: Plymouth se rinde y
#     deshabilita el splash. simpledrm cubre el hueco previo vía el framebuffer
#     de la firmware.
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/10-bookos-boot.conf <<'EOF'
# BookOS: splash de arranque temprano (ver bookos-base.ks).
add_dracutmodules+=" plymouth "
add_drivers+=" i915 xe "
early_microcode=yes
EOF

# El tema lo instala bookos-branding en /usr/share/plymouth/themes/bookos.
plymouth-set-default-theme bookos || true
# Plymouth elige escala 2 en paneles de más de 192 ppp (el del Galaxy Book:
# 2880×1800 en 30×19 cm, ~244 ppp) y amplía al doble cada fotograma del tema,
# que sale borroso. El tema ya se dimensiona según la altura de la pantalla.
# Va antes del -R: plymouthd.conf viaja dentro del initramfs.
grep -q '^DeviceScale=' /etc/plymouth/plymouthd.conf \
    || sed -i '/^\[Daemon\]/a DeviceScale=1' /etc/plymouth/plymouthd.conf || true
plymouth-set-default-theme bookos -R || true

# GRUB dice "BookOS", no "Fedora".
#
# OJO — GRUB_DISTRIBUTOR **NO gobierna las entradas del menú**. Fedora arranca
# con entradas BLS (/boot/loader/entries/*.conf) y quien las genera es
# /usr/lib/kernel/install.d/20-grub.install, cuya mkbls() escribe (línea 52):
#     title ${NAME} (${kernelver}) ${VERSION}
#     grub_class ${ID}
# sourceando /etc/os-release. Es decir: lo que pone «BookOS» en el menú es el
# /etc/os-release de arriba, y nada más. GRUB_DISTRIBUTOR solo afecta a lo que
# genera grub2-mkconfig (entradas de os-prober, submenús); se sigue poniendo por
# eso.
#
# Corolario importante: si os-release se revierte al de Fedora (lo hace cualquier
# actualización de fedora-release-*, ver arriba), los kernels que se instalen
# después salen como «Fedora Linux (7.1.4-204.fc44.x86_64) 44 (Forty Four)» y los
# de antes siguen diciendo BookOS. Verificado en book5-pro. Quien lo mantiene en
# su sitio es bookos-branding >= 0.6.1-8 (%transfiletriggerin →
# /usr/libexec/bookos-apply-identity).
if [ -f /etc/default/grub ]; then
    grep -q '^GRUB_DISTRIBUTOR=' /etc/default/grub \
        && sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="BookOS"|' /etc/default/grub \
        || echo 'GRUB_DISTRIBUTOR="BookOS"' >> /etc/default/grub
fi

# Keep the current and previous kernels. DNF does not support a limit of one.
if [ -f /etc/dnf/dnf.conf ]; then
    sed -i '/^installonly_limit=/d; /^install_weak_deps=/d' /etc/dnf/dnf.conf
    sed -i '/^localpkg_gpgcheck=/d' /etc/dnf/dnf.conf
    printf '\ninstallonly_limit=2\ninstall_weak_deps=False\nlocalpkg_gpgcheck=True\n' >> /etc/dnf/dnf.conf
fi

# ── FIX instalador: /var + arranque del sistema instalado ───────────────────
# Dos bugs de instalación, corregidos con la mecánica REAL de Anaconda
# (verificada contra pyanaconda: grub2.py::write_defaults abre /etc/default/grub
# del destino con "w+" — lo REESCRIBE —, y anaconda.py::appendPostScripts corre
# incondicionalmente los fragmentos de /usr/share/anaconda/post-scripts/*ks):
#
# 1) /var: el perfil bookos.conf trae `must_not_be_on_root = /var` junto a
#    default_scheme=BTRFS (que jamás crea /var aparte) → el comprobador de
#    almacenamiento aborta SIEMPRE ("Su /var debe estar en una partición
#    separada"). Anaconda lee el perfil DEL ENTORNO LIVE al arrancar liveinst,
#    así que parchearlo aquí arregla la instalación aunque el RPM
#    bookos-branding venga sin corregir.
# 2) "No aparece GRUB / no sale BookOS": editar /etc/default/grub del live NO
#    sirve (Anaconda lo reescribe de cero en el destino). Lo que sí gobierna el
#    destino es (a) el perfil: menu_auto_hide=True hace que Anaconda marque
#    grubenv con menu_auto_hide=1 boot_success=1 → menú oculto para siempre; y
#    (b) la entrada NVRAM UEFI, que el firmware Samsung a veces ignora o pierde
#    → el portátil ni lista BookOS. Se corrige vía perfil + post-script.
python3 - <<'PYEOF'
import configparser, os
for p in ("/etc/anaconda/profile.d/bookos.conf",
          "/usr/share/anaconda/profile.d/bookos.conf",
          "/usr/share/anaconda/product.d/bookos.conf"):
    if not os.path.isfile(p):
        continue
    c = configparser.RawConfigParser(strict=False)
    c.optionxform = str
    c.read(p, encoding="utf-8")
    if c.has_section("Storage Constraints"):
        c.set("Storage Constraints", "must_not_be_on_root", "")  # (1) /var libre
    # (1b) /boot y /boot/efi los crea la plataforma como particiones. Si el
    # perfil los repite, con default_scheme = BTRFS salen como subvolúmenes y la
    # ESP queda dentro del btrfs, donde el firmware no la ve.
    if c.has_option("Storage", "default_partitioning"):
        lineas = c.get("Storage", "default_partitioning").splitlines()
        c.set("Storage", "default_partitioning", "\n".join(
            l for l in lineas if not l.strip().startswith("/boot")))
    if not c.has_section("Bootloader"):
        c.add_section("Bootloader")
    c.set("Bootloader", "menu_auto_hide", "False")   # (2a) menú GRUB visible
    c.set("Bootloader", "efi_dir", "fedora")         # (2b) shim/grub reales viven en EFI/fedora
    # (3) Ocultas TODAS las páginas que BookOS Welcome ya pregunta en el primer
    # arranque: idioma (ese screen incluye el teclado), cuentas y red (Wi-Fi).
    # Queda visible solo fecha/hora (Welcome no tiene página de zona horaria).
    # Mismo mecanismo y misma lista (menos date-time) que Fedora Workstation.
    if not c.has_section("User Interface"):
        c.add_section("User Interface")
    c.set("User Interface", "hidden_webui_pages",
          "anaconda-screen-language anaconda-screen-accounts anaconda-screen-network")
    # (4) Navegador del WebUI. El perfil base `fedora` de F44 trae
    # webui_web_engine = slitherer (el kiosko QtWebEngine de Fedora KDE), y
    # bookos hereda de él. slitherer NO está en la imagen: webui-desktop lo
    # lanza, muere al instante, y el backend de Anaconda se queda esperando una
    # interfaz que nunca llega — sin ventana, y liveinst retiene su flock, así
    # que el segundo clic dice «Installer already running». Firefox ya viene en
    # la ISO y es el motor que usa fedora-workstation con este mismo script.
    c.set("User Interface", "webui_web_engine", "firefox")
    with open(p, "w", encoding="utf-8") as f:
        c.write(f)
    print("perfil anaconda parcheado: " + p)
PYEOF
# Cinturón extra por si python fallara (cubre el caso una-línea del perfil):
for _p in /etc/anaconda/profile.d/bookos.conf \
          /usr/share/anaconda/profile.d/bookos.conf \
          /usr/share/anaconda/product.d/bookos.conf; do
    [ -f "$_p" ] && sed -i 's/^\([[:space:]]*must_not_be_on_root[[:space:]]*=\).*/\1/' "$_p" || true
done
grep -rn "must_not_be_on_root\|menu_auto_hide\|efi_dir" /etc/anaconda /usr/share/anaconda/profile.d /usr/share/anaconda/product.d 2>/dev/null || true

# The builder embeds the reviewed helper into the live rootfs. Anaconda runs
# it in the installed target, with failures propagated and a persistent log.
mkdir -p /usr/local/sbin /usr/share/anaconda/post-scripts
cat > /usr/local/sbin/bookos-boot-finalize <<'BOOKOS_BOOT_EOF'
__BOOKOS_BOOT_FINALIZE__
BOOKOS_BOOT_EOF
chmod 755 /usr/local/sbin/bookos-boot-finalize
{
    printf '%s\n' '%post --interpreter=/usr/bin/bash --erroronfail --log=/var/log/bookos-anaconda-boot.log'
    printf '%s\n' '/usr/local/sbin/bookos-boot-finalize'
    printf '%s\n' '%end'
} > /usr/share/anaconda/post-scripts/zz-bookos-boot.ks

# First boot only keeps the menu visible; it never rewrites the ESP or BootOrder.
cat > /usr/local/sbin/bookos-grub-firstboot <<'EOF'
#!/bin/sh
set -eu
grub2-editenv - unset menu_auto_hide
touch /var/lib/bookos-grub-firstboot.done
EOF
chmod 755 /usr/local/sbin/bookos-grub-firstboot
cat > /etc/systemd/system/bookos-grub-firstboot.service <<'EOF'
[Unit]
Description=BookOS: show the installed GRUB menu
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/var/lib/bookos-grub-firstboot.done
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bookos-grub-firstboot
[Install]
WantedBy=multi-user.target
EOF
systemctl enable bookos-grub-firstboot.service

# EFI/fedora no es nuestro: cualquier Fedora instalado en el mismo disco usa ese
# directorio, y su grub.cfg (el stub que dice qué /boot cargar) solo puede
# apuntar a uno de los dos. Visto en un Book5 Pro con Fedora 44 + BookOS: la
# entrada UEFI «BookOS» arrancaba el Fedora porque el stub señalaba su /boot.
# BookOS arranca desde EFI/bookos con copias firmadas de shim y GRUB (el GRUB de
# Fedora busca grub.cfg primero junto al binario, que es lo que ya permite
# EFI/BOOT). Las copias se refrescan en cada arranque: grub2-efi-x64 solo
# actualiza EFI/fedora, y un shim viejo acabaría revocado por SBAT.
cat > /usr/local/sbin/bookos-efi-sync <<'EFISYNC'
#!/usr/bin/bash
set -euo pipefail
src=/boot/efi/EFI/fedora
dst=/boot/efi/EFI/bookos
boot_uuid=$(findmnt -nro UUID --mountpoint /boot)
[ -n "$boot_uuid" ] || { echo 'no se identifica el UUID de /boot' >&2; exit 1; }
mkdir -p "$dst"
for f in shimx64.efi grubx64.efi mmx64.efi; do
    [ -s "$src/$f" ] || continue
    cmp -s "$src/$f" "$dst/$f" && continue
    cp "$src/$f" "$dst/$f.nuevo"
    mv -f "$dst/$f.nuevo" "$dst/$f"
done
stub="search --no-floppy --fs-uuid --set=dev $boot_uuid
set prefix=(\$dev)/grub2
export \$prefix
configfile \$prefix/grub.cfg"
[ "$(cat "$dst/grub.cfg" 2>/dev/null)" = "$stub" ] || printf '%s\n' "$stub" > "$dst/grub.cfg"
EFISYNC
chmod 755 /usr/local/sbin/bookos-efi-sync
cat > /etc/systemd/system/bookos-efi-sync.service <<'EOF'
[Unit]
Description=BookOS: sincronizar shim y GRUB en EFI/bookos
ConditionKernelCommandLine=!rd.live.image
ConditionPathIsDirectory=/sys/firmware/efi
RequiresMountsFor=/boot /boot/efi
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bookos-efi-sync
[Install]
WantedBy=multi-user.target
EOF
systemctl enable bookos-efi-sync.service

# ── FIX instalador: limpiar los restos de la sesión LIVE en el sistema ──────
# liveuser se crea con useradd DENTRO de esta imagen (no en runtime como hace
# livesys-scripts en Fedora), y la instalación live copia el rootfs TAL CUAL al
# disco. Resultado en el sistema instalado: sigue existiendo liveuser sin
# contraseña, zz-live-autologin.conf hace que SDDM entre directo a liveuser
# (Relogin=true) ignorando al usuario creado en Anaconda, y el icono
# "Instalar en el disco duro" reaparece en cada escritorio nuevo vía /etc/skel.
# Un solo script hace la limpieza; se ejecuta por DOS vías (igual que el fix
# de GRUB de arriba): el post-script de Anaconda chrooteado en el destino y,
# de respaldo, una unidad firstboot que no corre en live (rd.live.image) y se
# desactiva sola. liveuser solo se borra si Anaconda creó otro usuario real;
# si no, se bloquea (passwd -l) para que nunca quede una cuenta sin contraseña.
cat > /usr/local/sbin/bookos-live-cleanup <<'EOF'
#!/bin/sh
# BookOS: retirar autologin/liveuser/lanzador del instalador tras instalar.
rm -f /etc/sddm.conf.d/zz-live-autologin.conf
rm -f /etc/systemd/system/greetd.service.d/zz-bookos-live.conf /etc/greetd/bookos-live.toml
rm -f /etc/systemd/system/getty@tty1.service.d/zz-bookos-live-autologin.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
rm -f /etc/sudoers.d/zz-bookos-live /usr/local/bin/bookos-instalar
rm -f /etc/profile.d/bookos-live.sh
# Solo le servía al instalador del live (nombre de producto de Anaconda)
rm -f /.buildstamp
rm -f /etc/skel/Desktop/liveinst.desktop /etc/skel/Desktop/anaconda.desktop
rmdir /etc/skel/Desktop 2>/dev/null || true
for d in /home/*/Desktop; do
    rm -f "$d/liveinst.desktop" "$d/anaconda.desktop" 2>/dev/null || true
done
if id liveuser >/dev/null 2>&1; then
    OTHER=$(awk -F: '$3>=1000 && $3<65534 && $1!="liveuser"{print $1; exit}' /etc/passwd)
    if [ -n "$OTHER" ]; then
        userdel -r liveuser 2>/dev/null || userdel liveuser 2>/dev/null || true
        rm -rf /home/liveuser
    else
        passwd -l liveuser 2>/dev/null || true
    fi
fi
touch /var/lib/bookos-live-cleanup.done
EOF
chmod 755 /usr/local/sbin/bookos-live-cleanup
# Vía 1: post-script de Anaconda (corre chrooteado en el sistema instalado,
# donde el script ya existe porque viaja con la copia del rootfs). Generado
# con printf por el mismo hazard %post/%end que zz-bookos-boot.ks.
{
    printf '%s\n' '%post'
    printf '%s\n' '/usr/local/sbin/bookos-live-cleanup || true'
    printf '%s\n' '%end'
} > /usr/share/anaconda/post-scripts/zz-bookos-live-cleanup.ks
# Vía 2 (respaldo): primer arranque instalado, ANTES del display manager para
# que SDDM nunca llegue a autologuear a liveuser.
cat > /etc/systemd/system/bookos-live-cleanup.service <<'EOF'
[Unit]
Description=BookOS: limpiar liveuser/autologin en el primer arranque instalado
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/var/lib/bookos-live-cleanup.done
After=local-fs.target
Before=greetd.service sddm.service display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bookos-live-cleanup

[Install]
WantedBy=multi-user.target
EOF
systemctl enable bookos-live-cleanup.service 2>/dev/null || \
    ln -sf /etc/systemd/system/bookos-live-cleanup.service \
        /etc/systemd/system/multi-user.target.wants/bookos-live-cleanup.service

# ── Idioma: forzar español de forma explícita ───────────────────────────────
# La directiva `lang` de kickstart no siempre llega a la sesión live (livesys
# puede pisar locale.conf) — se vio la ISO del 4-jul en inglés pese a lang es_ES.
echo 'LANG=es_ES.UTF-8' > /etc/locale.conf
# ── FIX arranque: dracut 108 + systemd 259 pierde systemd-sysroot-fstab-check ─
# En systemd 259 /usr/lib/systemd/systemd-sysroot-fstab-check pasó a ser un
# SYMLINK a system-generators/systemd-fstab-generator. dracut-install (dracut
# 108, fc44) resuelve el symlink e instala SOLO el destino, nunca el symlink,
# así que el initramfs se queda sin el path que ejecuta
# initrd-parse-etc.service (ExecStart sin "-") → 203/EXEC → OnFailure=
# emergency.target → "Entering emergency mode" nada más montar /sysroot.
# Afecta al initrd del live (lorax) Y a los initramfs del sistema instalado
# (kernel updates), por eso el módulo se queda instalado en la imagen.
# Módulo dracut que recrea el symlink a mano dentro del initramfs:
mkdir -p /usr/lib/dracut/modules.d/99bookos-fstab-check
cat > /usr/lib/dracut/modules.d/99bookos-fstab-check/module-setup.sh <<'EOF'
#!/bin/bash
# Workaround dracut 108 + systemd 259: reinstala el symlink
# systemd-sysroot-fstab-check que dracut-install resuelve y omite.
check() { return 0; }
depends() { echo systemd; }
install() {
    inst "$systemdutildir"/system-generators/systemd-fstab-generator
    ln -sf system-generators/systemd-fstab-generator \
        "$initdir$systemdutildir"/systemd-sysroot-fstab-check
}
EOF
chmod 0755 /usr/lib/dracut/modules.d/99bookos-fstab-check/module-setup.sh

# ── Arranque más rápido ─────────────────────────────────────────────────────
# NetworkManager-wait-online bloquea network-online.target hasta tener red
# (~5-30s en portátil sin cable). Nada del escritorio lo necesita.
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
# El journal en disco crece sin límite razonable en un portátil.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/bookos.conf

# Solo wallpapers BookOS en el selector: borra los stock que queden (restos
# de Fedora).
for w in /usr/share/wallpapers/*; do
    case "$(basename "$w")" in BookOS-*) ;; *) rm -rf "$w";; esac
done

# Update icon cache after BookOS icons installed
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
kbuildsycoca6 --noincremental 2>/dev/null || true

# ── Theme the Anaconda WebUI installer (guaranteed: runs after every package
# is installed, unlike the RPM %post which may run before anaconda-webui). ──
THEME=/usr/share/anaconda/bookos/theme
if [ -f "$THEME/anaconda-webui-bookos.css" ]; then
  for idx in $(find /usr/share/cockpit/anaconda-webui /usr/share/anaconda -name index.html -path '*anaconda-webui*' 2>/dev/null); do
    d=$(dirname "$idx")
    cp -f "$THEME/anaconda-webui-bookos.css" "$d/bookos.css" || true
    # brand marks referenced by the CSS (theme-aware) must sit beside it
    cp -f "$THEME/bookos-logo-light.svg" "$d/bookos-logo-light.svg" 2>/dev/null || true
    cp -f "$THEME/bookos-logo-dark.svg"  "$d/bookos-logo-dark.svg"  2>/dev/null || true
    # light/dark toggle script (default light, persists in localStorage)
    cp -f "$THEME/bookos-theme.js" "$d/bookos-theme.js" 2>/dev/null || true
    grep -q bookos.css "$idx" || sed -i 's#</head>#<link rel="stylesheet" href="bookos.css">\n</head>#' "$idx" || true
    # script runs in <head> (no defer) so the theme class is set before paint
    grep -q bookos-theme.js "$idx" || sed -i 's#</head>#<script src="bookos-theme.js"></script>\n</head>#' "$idx" || true
  done
fi
[ -f "$THEME/userChrome.css" ] && for fx in /usr/share/anaconda/firefox-theme/live/chrome /usr/share/anaconda/firefox-theme/default/chrome; do mkdir -p "$fx" && cp -f "$THEME/userChrome.css" "$fx/userChrome.css"; done 2>/dev/null || true

# Snapper: create the root config so pre/post snapshots work out of the box.
# (|| true: harmless if the subvolume layout already has it.)
snapper -c root create-config / 2>/dev/null || true
# OJO — aquí había un `systemctl enable grub-btrfsd` y un grub2-mkconfig para
# que grub-btrfs añadiera un submenú «BookOS snapshots». Las dos líneas eran
# código muerto y se han quitado (2026-08-11):
#
#   · grub-btrfs NO EXISTE en los repos de Fedora (es un paquete de Arch/AUR y
#     de algún COPR). `dnf repoquery grub-btrfs` no devuelve nada en F44, así
#     que el enable siempre falló en silencio gracias al `|| true` y nunca hubo
#     tal submenú. Si algún día se quiere, hay que empaquetarlo en el repo de
#     BookOS primero.
#   · el grub2-mkconfig corría en el chroot del LIVE, donde /boot/grub2 no es el
#     del sistema que se va a instalar: no servía para nada. El que sí cuenta lo
#     hace zz-bookos-boot.ks, chrooteado en el disco.
#
# Los snapshots de snapper siguen funcionando (BookOS Settings los usa antes de
# cada actualización); lo que no hay es forma de arrancar uno desde GRUB.

# Default to the graphical target + SDDM (the `services` line can't enable a
# display-manager that isn't installed at parse time; do it here instead).
# Sin SDDM (servidor) se queda en consola.
if rpm -q --quiet bookos-greeter; then
    systemctl set-default graphical.target
    systemctl enable --force greetd.service
elif rpm -q --quiet sddm; then
    systemctl set-default graphical.target 2>/dev/null || true
    systemctl enable sddm.service 2>/dev/null || true
else
    systemctl set-default multi-user.target
fi

# ── Live user (created LAST, after /etc/skel is fully populated) ─────────────
# Doing this here — not via the kickstart `user` directive — means useradd -m
# copies the FINISHED /etc/skel (theme, autostart, launchers
# service, lockscreen toggle) into the live home in one shot. No per-file
# /home/liveuser copies, and nothing can be silently missed. Password cleared so
# SDDM autologin (zz-live-autologin.conf above) drops straight to the desktop.
if ! id liveuser >/dev/null 2>&1; then
    useradd -m -G wheel,audio,video -c "Live User" liveuser
fi
passwd -d liveuser 2>/dev/null || true
# El instalador en modo texto (bookos-instalar, ediciones mínima y servidor)
# corre con sudo desde un terminal, sin agente de polkit. liveuser no tiene
# clave, así que sin esto sudo pediría una que no existe. bookos-live-cleanup
# lo borra en el sistema instalado.
printf 'liveuser ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/zz-bookos-live
chmod 0440 /etc/sudoers.d/zz-bookos-live
# liveinst -T es la vía que propone el propio Anaconda cuando falta RAM para
# la gráfica (startup_utils.check_memory). En modo texto pide 320 MiB, y la
# WebUI más Firefox no caben en 512 MB. Como root, liveinst no pasa por
# pkexec, que sin agente de polkit no tendría a quién pedir permiso.
cat > /usr/local/bin/bookos-instalar <<'EOF'
#!/bin/sh
exec sudo /usr/bin/liveinst -T "$@"
EOF
chmod 0755 /usr/local/bin/bookos-instalar
# useradd copies /etc/skel, but make the final live-home permissions explicit.
# This also repairs images where the launcher package was mode 0644.
for launcher in /home/liveuser/Desktop/liveinst.desktop /home/liveuser/Desktop/anaconda.desktop; do
    [ -f "$launcher" ] || continue
    chmod 0755 "$launcher"
    chown liveuser:liveuser "$launcher"
done

# Cleanup
dnf clean all
%end

# ── Verificación: los bookos-* críticos DE VERDAD entraron ──────────────────
# Verify the composed image as well as successful dependency resolution.
%post --erroronfail
set -euo pipefail
for p in bookos-keyring bookos-branding \
         grub2-pc grub2-tools grub2-efi-x64 shim-x64 efibootmgr; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "✗ paquete BookOS crítico ausente: $p (¿sin publicar en el repo?)"; exit 1; }
done
# Los %post de la edición van antes del común que habilita el gestor. El
# enlace solo puede verificarse aquí, cuando esa configuración ha terminado.
if rpm -q --quiet bookos-greeter; then
    [ "$(readlink -f /etc/systemd/system/display-manager.service)" = /usr/lib/systemd/system/greetd.service ] \
        || { echo '✗ greetd no es el gestor de acceso predeterminado'; exit 1; }
fi
[ -s /etc/anaconda/profile.d/bookos.conf ] \
    && grep -q '^\[Product\]' /etc/anaconda/profile.d/bookos.conf \
    && grep -q '^product_name[[:space:]]*=[[:space:]]*BookOS$' /etc/anaconda/profile.d/bookos.conf \
    || { echo '✗ Anaconda product profile does not identify the system as BookOS'; exit 1; }

# Sin la clave importada, todo repo con gpgcheck=1 pediría confirmación en la
# primera actualización — justo lo que se quiere evitar. Se comprueba que el
# `rpm --import` del %post de este kickstart llegó a ejecutarse.
# Por huella y no por nombre: la clave vieja B21B3821… tiene el mismo uid
# «BookOS Release Signing» y con ella nada verifica. rpm 6 nombra la clave
# con la huella completa (medido en fedora:44), no con los 8 hex cortos.
rpm -q gpg-pubkey-f8d96833e35611130227335a9a8fa3b2e9e0e64f >/dev/null 2>&1 \
    || { echo "✗ la clave de firma de BookOS no está importada en la base de datos rpm"; exit 1; }

# El PRETTY_NAME del sistema INSTALADO no lo escribe este kickstart sino
# bookos-apply-identity (lo llama zz-bookos-boot.ks en el disco). Hasta 0.6.1-12
# ponía «BookOS <versión> (<canal>)»; el nombre a secas llega con 0.6.2-1. El
# servidor aún sirve la 0.6.1: si el repo local no entra, se colaría sin avisar.
_branding="$(rpm -q --qf '%{VERSION}-%{RELEASE}' bookos-branding)"
[ "$(printf '%s\n' 0.6.2-1 "${_branding%%.fc*}" | sort -V | head -n1)" = 0.6.2-1 ] \
    || { echo "✗ bookos-branding $_branding es anterior a 0.6.2-1: el sistema instalado se llamaría «BookOS <versión> (<canal>)»"; exit 1; }

# La identidad del sistema (os-release + títulos del menú de GRUB) la mantiene
# bookos-branding >= 0.6.1-8 con estos dos ficheros. Si el repo aún sirve un
# branding anterior, la ISO se construiría "bien" pero cada equipo instalado se
# convertiría en «Fedora Linux 44» en su primer `dnf upgrade` y el menú de
# arranque no diría BookOS — un fallo silencioso que solo se ve semanas después.
# Mejor abortar el build aquí.
for f in /usr/libexec/bookos-apply-identity \
         /usr/lib/kernel/install.d/95-bookos-loaderentry.install \
         /usr/local/sbin/bookos-boot-finalize; do
    [ -x "$f" ] || { echo "✗ falta $f — bookos-branding es anterior a 0.6.1-8; publícalo antes de construir la ISO"; exit 1; }
done
[ -s /usr/share/anaconda/post-scripts/zz-bookos-boot.ks ] \
    || { echo 'Missing Anaconda boot-finalization fragment'; exit 1; }

# Si el WebUI apunta a un navegador que no está en la imagen, «Instalar en el
# disco duro» no abre nada y bloquea los siguientes intentos (ver el punto (4)
# del parche del perfil). Se ve solo en el portátil: mejor abortar aquí.
grep -q '^webui_web_engine = firefox$' /etc/anaconda/profile.d/bookos.conf \
    || { echo "✗ el perfil de Anaconda no fija webui_web_engine = firefox (heredaría slitherer, que no está en la ISO)"; exit 1; }
! sed -n '/^default_partitioning/,/^[^[:space:]]/p' /etc/anaconda/profile.d/bookos.conf | grep -q '/boot' \
    || { echo "✗ default_partitioning pide /boot: con BTRFS la ESP saldría como subvolumen"; exit 1; }

# El tema gráfico de GRUB (bookos-branding >= 0.6.1-10). Sin él, el post-script
# de Anaconda no pone GRUB_THEME —la guarda es deliberada— y la ISO saldría
# "bien" pero con el menú de arranque en texto plano. Igual que arriba: mejor
# abortar el build que descubrirlo en el equipo del usuario.
[ -f /boot/grub2/themes/bookos/theme.txt ] \
    || { echo "✗ falta /boot/grub2/themes/bookos/theme.txt — bookos-branding es anterior a 0.6.1-10; publícalo antes de construir la ISO"; exit 1; }

# El tema de Plymouth: mismo razonamiento. Si el tarball se armó sin
# BookOS-Loading-System, collect-branding.sh genera un fallback y aquí no
# saltaría nada — pero si falta del todo, el arranque muestra el spinner de
# Fedora. El plugin script es lo que interpreta bookos.script.
[ -f /usr/share/plymouth/themes/bookos/bookos.plymouth ] \
    || { echo "✗ falta el tema de Plymouth de BookOS en el branding"; exit 1; }
rpm -q plymouth-plugin-script >/dev/null 2>&1 \
    || { echo "✗ falta plymouth-plugin-script — el tema es ModuleName=script y caería al spinner de Fedora"; exit 1; }

if [ -d /usr/share/anaconda/addons/org_bookos_welcome ]; then
    echo "Legacy Btrfs-renaming addon is still installed; rebuild bookos-branding"; exit 1
fi
install -d /usr/share/bookos
dnf -q --cacheonly repoquery --installed \
    --queryformat '%{name}\t%{evr}.%{arch}\t%{installsize}\t%{from_repo}' \
    | LC_ALL=C sort > /usr/share/bookos/packages.tsv
[ -s /usr/share/bookos/packages.tsv ] || { echo 'Package inventory is empty'; exit 1; }

# Y que la identidad quedó realmente aplicada: si os-release volviera a ser un
# bucle de symlinks (el bug de `ln -sf /etc/os-release /usr/lib/os-release`),
# PRETTY_NAME saldría vacío y el menú diría «Linux <versión>».
[ -r /etc/os-release ] || { echo "✗ /etc/os-release no es legible (¿bucle de symlinks?)"; exit 1; }
grep -qx 'PRETTY_NAME="__BOOKOS_NAME__"' /etc/os-release \
    || { echo "✗ PRETTY_NAME debe ser el nombre a secas: $(grep -s PRETTY_NAME /etc/os-release)"; exit 1; }
# Sin esto el instalador se presenta como Fedora y registra en el firmware una
# entrada UEFI «Fedora» (ver el /.buildstamp del %post de branding).
grep -qx 'Product=__BOOKOS_NAME__' /.buildstamp \
    || { echo "✗ /.buildstamp no fija Product=__BOOKOS_NAME__ para Anaconda"; exit 1; }
%end

# Relabel LAST: container builds can inherit the process role unconfined_r.
# Lorax's ordinary setfiles pass fixes types but preserves that invalid role.
# The resulting live system rejects udev, D-Bus and SDDM with 203/EXEC when
# SELinux loads its policy. -F restores the entire context, including the role.
%post --interpreter=/usr/bin/bash --erroronfail
set -euo pipefail
contexts=/etc/selinux/targeted/contexts/files/file_contexts
test -s "$contexts"
# Never traverse the container's bind-mounted kernel/runtime filesystems.
# -m also works when SELinux is disabled in the compose environment.
setfiles -F -m -e /proc -e /sys -e /dev -e /run "$contexts" /
matchpathcon -V -f "$contexts" \
    /etc/ld.so.cache /usr/bin/udevadm /usr/bin/dbus-broker-launch \
    /usr/lib/systemd/systemd-resolved
if rpm -q --quiet bookos-greeter; then
    matchpathcon -V -f "$contexts" /usr/bin/greetd /usr/libexec/bookos-greeter /usr/libexec/bookos-cage
elif rpm -q --quiet sddm; then
    matchpathcon -V -f "$contexts" /usr/bin/sddm
fi
%end
