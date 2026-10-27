# BookOS — edición servidor: sin escritorio. Consola, SSH y Cockpit (panel web
# en el puerto 9090) con el tema de BookOS. La inserta profile.py en
# bookos-base.ks.
#
# Aquí SSH sí va activo y con el puerto abierto, al revés que en las ediciones
# de escritorio: un servidor sin pantalla que no se puede administrar en
# remoto no sirve. Cockpit va por socket: cockpit-ws solo corre mientras hay
# alguien conectado.
firewall --enabled --service=ssh,cockpit
services --enabled=NetworkManager,sshd,cockpit.socket

%packages --exclude-weakdeps
openssh-server
# Cockpit sin cockpit-packagekit: las actualizaciones van por dnf, como en
# el resto de BookOS, y PackageKit es otro demonio residente.
cockpit-ws
cockpit-bridge
cockpit-system
cockpit-networkmanager
cockpit-storaged
cockpit-selinux
cockpit-podman
podman
bash-completion

# Instalador en modo texto: sin escritorio no hay dónde abrir la WebUI.
anaconda-tui
%end

%post
# Live: entra solo como liveuser en tty1, como el autologin de SDDM en las
# ediciones de escritorio. bookos-live-cleanup lo borra en el sistema instalado.
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/zz-bookos-live-autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin liveuser --noclear %I $TERM
EOF

# Lo primero que ve quien arranca el USB. Solo en el live (rd.live.image) y
# también lo borra bookos-live-cleanup.
cat > /etc/profile.d/bookos-live.sh <<'EOF'
if grep -qw rd.live.image /proc/cmdline && [ "$(tty)" = /dev/tty1 ]; then
    printf '\n  BookOS Server (sesión live)\n\n'
    printf '  Para instalar en el disco:  bookos-instalar\n'
    printf '  Administración web tras instalar:  https://<ip>:9090\n\n'
fi
EOF

# El disco instalado es copia del live, instalador incluido, y anaconda-live
# exige zenity → gtk4 → GStreamer → Mesa + LLVM. Fuera del live no sirve para
# nada. Medido en fedora:44 con el conjunto de esta edición: 208 paquetes,
# 530 MiB; se quedan Cockpit, SSH, podman, NetworkManager y Python. Sin red
# hace falta --disable-repo: dnf no necesita metadatos para quitar.
# zzz-: Anaconda los ejecuta en orden alfabético (kickstart.py,
# appendPostScripts) y esto tiene que ir tras zz-bookos-boot.ks, que usa
# herramientas de arranque. Sin --erroronfail: si falla, el sistema solo pesa
# más, y la instalación no debe abortar por eso.
mkdir -p /usr/share/anaconda/post-scripts
{
    printf '%s\n' '%post --log=/var/log/bookos-servidor-sin-instalador.log'
    printf '%s\n' "dnf -y remove --disable-repo='*' anaconda-live anaconda-tui anaconda-install-env-deps anaconda-webui anaconda-core zenity"
    printf '%s\n' '%end'
} > /usr/share/anaconda/post-scripts/zzz-bookos-servidor-sin-instalador.ks
%end

%post --erroronfail
set -euo pipefail
for p in openssh-server cockpit-ws cockpit-system podman anaconda-tui; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "✗ falta en la edición servidor: $p"; exit 1; }
done
# Ni rastro de escritorio. sddm llegaba por un Requires de bookos-branding
# (< 0.6.2-5); si vuelve, es que alguien lo pide otra vez. Mesa sí está en el
# live (zenity → gtk4); se va del disco con el instalador, ver arriba.
for p in sddm bookos-desktop xorg-x11-server-Xwayland xorg-x11-server-Xorg \
         firefox kwin qt6-qtbase-gui webkit2gtk4.1; do
    if rpm -q "$p" >/dev/null 2>&1; then
        echo "✗ la edición servidor no debe llevar $p (¿quién lo arrastra? dnf repoquery --installed --whatrequires $p)"; exit 1
    fi
done
[ -s /usr/share/anaconda/post-scripts/zzz-bookos-servidor-sin-instalador.ks ] \
    || { echo "✗ falta el post-script que retira el instalador del disco"; exit 1; }
# Cockpit busca su tema por el ID de os-release; sin este fichero sale el de
# Fedora (branding/fedora, por ID_LIKE).
[ -s /usr/share/cockpit/branding/bookos/branding.css ] \
    || { echo "✗ falta el tema de Cockpit: bookos-branding es anterior a 0.6.2-5"; exit 1; }
%end
