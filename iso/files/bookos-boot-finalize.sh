#!/usr/bin/bash
# Runs inside Anaconda's installed target, never against the build host.
set -Eeuo pipefail
exec >>/var/log/bookos-boot-finalize.log 2>&1
trap 'echo "ERROR: boot finalization failed at line $LINENO (status $?)"' ERR
fail() { echo "ERROR: $*"; exit 1; }
set_kv() {
    if grep -q "^$1=" /etc/default/grub; then
        sed -i "s|^$1=.*|$1=$2|" /etc/default/grub
    else
        printf '%s=%s\n' "$1" "$2" >> /etc/default/grub
    fi
}

echo "BookOS boot validation: $(date -u +%FT%TZ)"
findmnt /boot || fail '/boot must be a separate mounted filesystem'
[ -s /etc/default/grub ] || fail 'Anaconda did not write /etc/default/grub'
set_kv GRUB_TIMEOUT 5
set_kv GRUB_TIMEOUT_STYLE menu
set_kv GRUB_DISTRIBUTOR '"BookOS"'
set_kv GRUB_ENABLE_BLSCFG true
set_kv GRUB_DISABLE_OS_PROBER false
set_kv GRUB_TERMINAL_OUTPUT '"gfxterm"'
# GRUB no escala tipografías ni iconos según la densidad. En paneles HiDPI,
# `auto` elige la resolución nativa y deja el menú ilegiblemente pequeño. Se
# priorizan modos cercanos a 1920 px y se conserva `auto` como salida segura
# para firmware que solo exponga un modo GOP.
set_kv GRUB_GFXMODE 1920x1200,1920x1080,1680x1050,1440x900,1280x800,1024x768,800x600,auto
set_kv GRUB_GFXPAYLOAD_LINUX keep
if [ -f /boot/grub2/themes/bookos/theme.txt ]; then
    set_kv GRUB_THEME '"/boot/grub2/themes/bookos/theme.txt"'
fi

# Check the ESP before regenerating anything. An empty directory is not an ESP.
if [ -d /sys/firmware/efi ]; then
    [ "$(findmnt -nro FSTYPE --mountpoint /boot/efi)" = vfat ] || fail 'EFI system partition is not mounted as vfat at /boot/efi'
    for f in shimx64.efi grubx64.efi grub.cfg; do
        [ -s "/boot/efi/EFI/fedora/$f" ] || fail "Missing EFI/fedora/$f"
    done
    boot_uuid=$(findmnt -nro UUID --mountpoint /boot)
    [ -n "$boot_uuid" ] || fail 'Cannot identify the /boot UUID'
    grep -Fq "$boot_uuid" /boot/efi/EFI/fedora/grub.cfg || fail 'EFI stub points to another /boot UUID'
    grep -Eq 'configfile[[:space:]]' /boot/efi/EFI/fedora/grub.cfg || fail 'EFI stub does not redirect to grub.cfg'
fi

plymouth-set-default-theme bookos
# Anaconda ya escribió /etc/locale.conf: el dracut de abajo mete el splash en
# el idioma elegido al instalar.
/usr/libexec/bookos-plymouth-language
dracut -f --regenerate-all
/usr/libexec/bookos-apply-identity

# A valid menu needs actual BLS entries, kernels and initramfs, not just grub.cfg.
entries=0
shopt -s nullglob
for entry in /boot/loader/entries/*.conf; do
    grep -q '^version 0-rescue-' "$entry" && continue
    for field in linux initrd; do
        value=$(awk -v key="$field" '$1 == key {for (i=2;i<=NF;i++) print $i}' "$entry")
        [ -n "$value" ] || fail "$entry has no $field"
        while IFS= read -r file; do
            [[ "$file" = /* && "$file" != *..* ]] || fail "Invalid BLS path: $file"
            [ -s "/boot$file" ] || fail "$entry references missing /boot$file"
        done <<< "$value"
    done
    grep -Eq '^options .*root=' "$entry" || fail "$entry has no root device"
    if grep -Eq '^options .*rd\.live\.' "$entry"; then
        fail "$entry still contains live-image parameters"
    fi
    entries=$((entries + 1))
done
[ "$entries" -gt 0 ] || fail 'No installed kernel BLS entries'
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-script-check /boot/grub2/grub.cfg
grep -Eq '^[[:space:]]*blscfg([[:space:]]|$)' /boot/grub2/grub.cfg || fail 'GRUB does not load BLS entries'
grub2-editenv - unset menu_auto_hide

if [ -d /sys/firmware/efi ]; then
    esp=$(readlink -f "$(findmnt -nro SOURCE --mountpoint /boot/efi)")
    part=$(lsblk -dnro PARTN "$esp")
    disk="/dev/$(lsblk -dnro PKNAME "$esp")"
    partuuid=$(lsblk -dnro PARTUUID "$esp")
    [ -b "$disk" ] && [ -n "$part" ] && [ -n "$partuuid" ] || fail 'Cannot identify ESP disk and partition'

    # EFI/fedora lo puede compartir otro Fedora del mismo disco; ver
    # bookos-efi-sync en bookos-base.ks.
    /usr/local/sbin/bookos-efi-sync
    for f in shimx64.efi grubx64.efi grub.cfg; do
        [ -s "/boot/efi/EFI/bookos/$f" ] || fail "Missing EFI/bookos/$f"
    done

    # Match label AND target partition/path, including normal efibootmgr suffixes.
    entry_ids() {
        local dir=${1:-bookos}
        # Por el entorno y no con -v: awk interpretaría «\b» como retroceso.
        loader="\\efi\\$dir\\shimx64.efi" awk -v uuid="$partuuid" '
            /^Boot[[:xdigit:]]{4}\*?[[:space:]]+BookOS([[:space:]]|$)/ {
                line=tolower($0)
                if (index(line,tolower(uuid)) && index(line,ENVIRON["loader"]))
                    print substr($1,5,4)
            }'
    }
    entries_output=$(efibootmgr -v) || fail 'Cannot read UEFI boot variables'
    # Las entradas «BookOS» de instalaciones anteriores apuntan a EFI/fedora,
    # que arranca lo que diga su stub, quizá otro sistema.
    for old in $(entry_ids fedora <<< "$entries_output"); do
        efibootmgr -q -b "$old" -B
    done
    entries_output=$(efibootmgr -v)
    ours=$(entry_ids <<< "$entries_output" | head -n1)
    if [ -z "$ours" ]; then
        efibootmgr -c -d "$disk" -p "$part" -L BookOS -l '\EFI\bookos\shimx64.efi'
        entries_output=$(efibootmgr -v)
        ours=$(entry_ids <<< "$entries_output" | head -n1)
    fi
    [ -n "$ours" ] || fail 'BookOS UEFI entry was not registered'
    order=$(awk '/^BootOrder:/ {print $2}' <<< "$entries_output")
    new_order="$ours"
    IFS=, read -ra old_order <<< "$order"
    for id in "${old_order[@]}"; do
        [ "${id^^}" = "${ours^^}" ] || new_order+=",$id"
    done
    efibootmgr -o "$new_order"

    # Only populate an absent fallback directory; preserve other operating systems.
    if [ ! -e /boot/efi/EFI/BOOT ]; then
        mkdir /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/fedora/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
        cp /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/grubx64.efi
        cp /boot/efi/EFI/fedora/grub.cfg /boot/efi/EFI/BOOT/grub.cfg
        if [ -f /boot/efi/EFI/fedora/mmx64.efi ]; then
            cp /boot/efi/EFI/fedora/mmx64.efi /boot/efi/EFI/BOOT/mmx64.efi
        fi
    fi
fi
echo 'BookOS boot validation completed'
