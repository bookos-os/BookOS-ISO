# BookOS — edición completa: el escritorio con todas sus apps y el soporte de
# Samsung Galaxy Book. La inserta profile.py en bookos-base.ks.

# SSH is intentionally NOT enabled by default: a consumer laptop OS shouldn't
# ship a listening sshd / open firewall port on every install. Users who want
# remote access enable it themselves (systemctl enable --now sshd + open port).
firewall --enabled --service=mdns
services --enabled=NetworkManager,bluetooth

%packages --exclude-weakdeps
# Escritorio propio (bookos-desktop). Plasma ya no va en la imagen: el panel,
# dock, launchpad, bloqueo, red, sonido y Bluetooth los pinta bookos-desktop.
# polkit-kde permite que Ajustes y el instalador soliciten autorización.
bookos-desktop
bookos-greeter
greetd
polkit-kde
power-profiles-daemon
bluez
NetworkManager-wifi
pipewire-alsa
pipewire-pulseaudio
wireplumber
pulseaudio-utils
alsa-utils
mesa-dri-drivers
mesa-vulkan-drivers
xorg-x11-server-Xwayland
xdg-desktop-portal-gtk
xdg-utils
udisks2
upower
fprintd-pam
gnome-keyring
orca
at-spi2-core
qt6-qtwayland
google-noto-sans-fonts
google-noto-emoji-color-fonts
exfatprogs
ntfs-3g
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugin-libav

# BookOS umbrella package (Requires: pulls everything else)
bookos-meta
# Asistente de primer arranque (BookOS Welcome, C++/Qt6, estilo macOS Setup):
# idioma, teclado, Wi-Fi, cuenta (wheel), huella y tema. La página de cuentas
# del WebUI va oculta vía perfil. Verificado en el %post --erroronfail final.
# Sustituye al esqueleto bookos-oobe (rpm/bookos-oobe, ya no se incluye).
bookos-welcome
# Missing applications fail dependency resolution. The final post section
# also validates the resulting rootfs and desktop integration.
__BOOKOS_APPS__
# Iconos, colores/Kvantum de las apps Qt y tema GTK.
bookos-icons
bookos-plasma-theme
bookos-gtk-theme
# Tema de sonido: la sesión lo pone como tema GTK y el compositor suena con él.
bookos-sounds
bookos-cursors
# ServiceMenus de Dolphin (terminal / color de carpeta) y bookos-livestate.
bookos-desktop-integration

# ── Samsung Galaxy Book hardware enablement ─────────────────────────────────
# Fingerprint: libfprint fork with the FMV ETU906AXX-E SPI sensor (Book5 Pro).
# It Provides/Obsoletes libfprint, so dnf installs it in place of the stock one.
libfprint-bookos
# Speakers: MAX98390 HDA DKMS module (Book4/5 Pro/Ultra). Hardware-guarded, so
# it no-ops on other machines. dkms + kernel-devel + akmods let it build and
# sign at compose time / on kernel updates; alsa-sof-firmware carries the DSM.
bookos-galaxybook-audio
dkms
kernel-devel
akmods
alsa-sof-firmware

# Firefox proporciona el motor de Aether y la WebUI del instalador.
firefox
kde-partitionmanager

# ── BookOS debloat ──────────────────────────────────────────────────────────
# Apps/utilidades KDE sustituidas por las de BookOS o innecesarias para el
# modelo macOS. Solo LEAF packages (apps de hoja, nada de lo que dependa el
# stack) para no romper la resolución. Archivos y Terminal son los de BookOS.
-plasma-discover              # -> bookos-store
-plasma-discover-notifier
-plasma-welcome                # asistente de bienvenida KDE
-plasma-browser-integration    # integración navegador (bloat)
-plasma-workspace-wallpapers   # solo wallpapers BookOS en el selector
-kinfocenter                   # info del sistema
-khelpcenter                   # ayuda KDE
-plasma-firewall               # KCM -> cubierto por bookos-settings
-plasma-thunderbolt            # KCM -> cubierto por bookos-settings

# Remote access servers are optional in the minimal image.
-openssh-server
-sddm
-plasma-workspace
-dolphin
-kwin
-bookos-desktop-recovery

# Instalador gráfico (WebUI en Firefox).
anaconda
%end

%post --erroronfail
set -euo pipefail
# ── Keyboard backlight toggle (Fn+F9) ──────────────────────────────────────
# Samsung Galaxy Book exposes the keyboard backlight as an LED class device.
# Writing its `brightness` needs root, so Fn+F9 / the Control Station button do
# nothing for a normal user. Ship a cycler script, make the sysfs node writable
# by the `video` group via udev, and bind it to Fn+F9 for new users.
cat > /usr/libexec/bookos-kbd-backlight <<'SH'
#!/bin/sh
# Cycle the keyboard backlight one step (wraps to 0 at max).
LED=$(ls -d /sys/class/leds/*kbd_backlight 2>/dev/null | head -1)
[ -n "$LED" ] || exit 0
MAX=$(cat "$LED/max_brightness")
CUR=$(cat "$LED/brightness")
if [ "$CUR" -ge "$MAX" ]; then NEXT=0; else NEXT=$((CUR + 1)); fi
echo "$NEXT" > "$LED/brightness"
SH
chmod +x /usr/libexec/bookos-kbd-backlight
# udev: make the kbd backlight node writable without root. `uaccess` grants the
# user of the active graphical session a write ACL (covers the installer-created
# user regardless of group); the chgrp/chmod to `video` is a fallback for the
# pre-created liveuser. Re-applied on hotplug.
cat > /etc/udev/rules.d/90-bookos-kbd-backlight.rules <<'EOF'
ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="*kbd_backlight", \
  TAG+="uaccess", \
  RUN+="/bin/chgrp video /sys/class/leds/%k/brightness", \
  RUN+="/bin/chmod g+w /sys/class/leds/%k/brightness"
EOF

# Los valores de fábrica deben apuntar a las aplicaciones de esta imagen.
mkdir -p /etc/skel/.config/bookos /etc/skel/.local/share/applications
cat > /etc/skel/.config/bookos/panel.conf <<'EOF'
dock = launchpad:Aplicaciones:launchpad-cohete, bookos-explorer:Archivos:bookos-explorer, bookos-browser:Navegador:bookos-browser, bookos-settings:Ajustes:bookos-settings, bookos-notepad:Notas:bookos-notepad
EOF
for lanzador in firefox.desktop org.kde.kdeconnect.app.desktop org.kde.kdeconnect.sms.desktop org.kde.kdeconnect.nonplasma.desktop; do
# Firefox y las bibliotecas de Connect arrastran interfaces que sustituimos.
cat > "/etc/skel/.local/share/applications/$lanzador" <<'EOF'
[Desktop Entry]
Type=Application
Name=Componente del sistema
Hidden=true
EOF
done
# El autostart de Fedora solo anuncia KDE; BookOS también necesita el agente.
cp /etc/xdg/autostart/polkit-kde-authentication-agent-1.desktop /etc/xdg/autostart/bookos-polkit.desktop
sed -i 's/^OnlyShowIn=.*/OnlyShowIn=BookOS;/' /etc/xdg/autostart/bookos-polkit.desktop
# ── Galaxy Book speakers: pre-build the DKMS module into the image ──────────
# Build against the kernel shipped in the image (not the build host's running
# kernel) so the live session and fresh installs have working speakers without
# a first-boot compile. dkms.service still rebuilds on future kernel updates.
for KVER in $(ls /lib/modules 2>/dev/null); do
    [ -e "/lib/modules/$KVER/build" ] || continue
    dkms install -m max98390-hda -v 1.0 -k "$KVER" 2>/dev/null || true
done
systemctl enable dkms.service 2>/dev/null || true
%end

%post --erroronfail
set -euo pipefail
for p in bookos-meta bookos-desktop bookos-greeter greetd bookos-shell \
         bookos-desktop-integration bookos-welcome bookos-icons bookos-cursors bookos-sounds \
         __BOOKOS_APPS_SH__ firefox kde-partitionmanager; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "✗ paquete BookOS crítico ausente: $p (¿sin publicar en el repo?)"; exit 1; }
done
_welcome="$(rpm -q --qf '%{VERSION}-%{RELEASE}' bookos-welcome)"
[ "$(printf '%s\n' 1.0.0-10 "${_welcome%%.fc*}" | sort -V | head -n1)" = 1.0.0-10 ] \
    || { echo "✗ Bienvenida debe incluir el primer acceso con greetd (>= 1.0.0-10)"; exit 1; }
for f in /usr/bin/bookos-session /usr/libexec/bookos-comp /usr/libexec/bookos-greeter \
         /usr/libexec/bookos-greeter-start /usr/libexec/bookos-cage; do
    [ -x "$f" ] || { echo "✗ falta el ejecutable de la sesión: $f"; exit 1; }
done
# Una dependencia nueva no debe reintroducir otro escritorio.
for variant in Dark Light Tinted-Dark Tinted-Light; do
    test -s "/usr/share/bookos/icons/BookOS-Icon-Pack-$variant/index.theme" \
        || { echo "Falta el pack de iconos de Ajustes: $variant"; exit 1; }
done
for p in sddm plasma-workspace dolphin kwin bookos-desktop-recovery konsole plasma-discover kwrite kcalc kmail kontact elisa-player dragon openssh-server; do
    if rpm -q "$p" >/dev/null 2>&1; then
        echo "La imagen completa contiene una aplicación sustituida: $p"; exit 1
    fi
done
%end
