#!/bin/bash
# Debian port (Apple Silicon): no U-Boot text on screen at boot. Run with sudo. Idempotent.
#
# Recovery if the Mac no longer boots Linux: hold the power button -> Options -> macOS (or recovery),
# mount the EFI partition and copy m1n1/boot.bin.pre-quiet over m1n1/boot.bin.
# To undo from Linux: sudo rm /etc/default/update-m1n1 && sudo update-m1n1
set -euo pipefail
OM=/home/guillaume/.local/share/omarchy
[[ $EUID == 0 ]] || { echo "run with sudo"; exit 1; }

install -m 755 "$OM/debian/bin/omarchy-quiet-uboot" /usr/local/sbin/omarchy-quiet-uboot
/usr/local/sbin/omarchy-quiet-uboot >/dev/null   # fails loudly here if the patch doesn't apply

esp=/boot/efi/m1n1
[[ -e $esp/boot.bin.pre-quiet ]] || cp -p "$esp/boot.bin" "$esp/boot.bin.pre-quiet"

cat > /etc/default/update-m1n1 <<'CONF'
# Sourced by update-m1n1. Omarchy (Debian port): quiet U-Boot (no text on screen, no boot delay).
# Falls back to Debian's stock U-Boot if the patch no longer applies. Undo: delete this file and
# run update-m1n1.
U_BOOT=$(/usr/local/sbin/omarchy-quiet-uboot 2>/dev/null) || unset U_BOOT
CONF

update-m1n1
echo "Quiet firmware installed. Backup: $esp/boot.bin.pre-quiet. Reboot to see it."
