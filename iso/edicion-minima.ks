# BookOS — edición mínima: el escritorio BookOS y poco más, para equipos de
# 512 MB. La inserta profile.py en bookos-base.ks.
#
# Lo que manda es la RAM, no el disco. Medido en una sesión real (2880×1800):
# bookos-comp 91 MB de PSS; cada app Tauri (Ajustes, Notas, Shell, Archivos)
# suma 80 MB de proceso + 215–270 MB de WebKitWebProcess + 57 MB de
# WebKitNetworkProcess. Una sola app de esas ya no cabe junto al escritorio,
# así que aquí no va ninguna: se instalan después con dnf si el equipo puede.
# El terminal es foot (~1 MB instalado). Tampoco van Firefox, KWin ni PySide6
# (la recuperación), que solos ocupan más que todo lo demás.
#
# Sin SSH, igual que la completa: es un escritorio.
firewall --enabled --service=mdns
services --enabled=NetworkManager,bluetooth

%packages --exclude-weakdeps
# Sin bookos-desktop-recovery: si el compositor no arranca, bookos-session
# vuelve a SDDM en vez de abrir la pantalla de recuperación.
bookos-desktop
# El greeter de SDDM se resuelve con sddm-wayland-generic (Weston), no con el
# de Plasma: medido en la resolución de la completa.
sddm
foot
power-profiles-daemon
bluez
NetworkManager-wifi
pipewire-alsa
pipewire-pulseaudio
wireplumber
mesa-dri-drivers
udisks2
upower
google-noto-sans-fonts
exfatprogs
ntfs-3g
# Iconos del dock y del launchpad, tema GTK (diálogos) y sonidos del sistema.
bookos-icons
bookos-gtk-theme
bookos-sounds

-openssh-server

# Instalador en modo texto: la WebUI necesita Firefox, que no cabe.
anaconda-tui
%end

%post
# Meta+Return abre BOOKOS_TERMINAL (keybinds.rs) y el de serie es bookos-shell,
# que aquí no está. SDDM arranca la sesión con un shell de login
# (/usr/share/sddm/scripts/wayland-session), así que profile.d le llega.
cat > /etc/profile.d/bookos-minima.sh <<'EOF'
export BOOKOS_TERMINAL=foot
EOF

# El dock de serie (bookos-shell/config.rs) ancla Explorer, Firefox, Ajustes y
# Notas, que aquí no existen. Solo se escribe la clave dock: el resto del
# fichero sigue con sus valores por defecto y el shell reescribe solo las
# claves que cambia.
mkdir -p /etc/skel/.config/bookos
cat > /etc/skel/.config/bookos/panel.conf <<'EOF'
dock = launchpad:Aplicaciones:launchpad-cohete, foot:Terminal:utilities-terminal
EOF

# «Instalar en el disco duro» abre el instalador en modo texto dentro de foot.
# La %post común copia después este lanzador al escritorio de liveuser.
sed -i 's|^Exec=.*|Exec=foot /usr/local/bin/bookos-instalar|' /usr/share/applications/liveinst.desktop
%end

%post --erroronfail
set -euo pipefail
# zram-generator-defaults viene en @core: con 512 MB es la diferencia entre
# abrir una app más o que el OOM mate la sesión.
for p in bookos-desktop sddm foot anaconda-tui zram-generator-defaults; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "✗ falta en la edición mínima: $p"; exit 1; }
done
for p in firefox kwin python3-pyside6 qt6-qtwebengine kernel-devel gcc \
         bookos-desktop-recovery bookos-welcome bookos-meta openssh-server; do
    if rpm -q "$p" >/dev/null 2>&1; then
        echo "✗ la edición mínima no debe llevar $p (¿quién lo arrastra? dnf repoquery --installed --whatrequires $p)"; exit 1
    fi
done
grep -qx 'Exec=foot /usr/local/bin/bookos-instalar' /usr/share/applications/liveinst.desktop \
    || { echo "✗ el lanzador del instalador no abre el modo texto"; exit 1; }
%end
