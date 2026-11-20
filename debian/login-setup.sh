#!/bin/bash
# Debian port of Omarchy — Omarchy login screen (SDDM) + boot progress bar (Plymouth).
# Run with sudo. Idempotent. Also called from system-setup.sh (step 23).
#
# Undo the login screen (e.g. from a TTY, Ctrl+Alt+F3):
#   sudo systemctl disable sddm && sudo systemctl enable gdm3 && sudo reboot
#   (on Debian: sudo dpkg-reconfigure gdm3 to pick gdm3 as the default display manager)
set -euo pipefail
OM=/home/guillaume/.local/share/omarchy
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }

# --- Login screen -----------------------------------------------------------------------------
# Omarchy's SDDM theme, shown by SDDM's Wayland greeter running on a minimal Hyprland.
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sddm qml6-module-qtquick-window

install -d -m 755 /usr/share/sddm/themes/omarchy
install -m 644 "$OM"/default/sddm/omarchy/* /usr/share/sddm/themes/omarchy/

# Greeter compositor config: upstream's, plus the Retina panel at scale 2 like the desktop.
{ cat "$OM/default/sddm/hyprland.lua"
  printf '\n-- Debian port: Retina panel\nhl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })\n'
} > /usr/share/sddm/hyprland.lua
chmod 644 /usr/share/sddm/hyprland.lua

install -d -m 755 /etc/sddm.conf.d
install -m 644 "$OM"/etc/sddm.conf.d/10-theme.conf "$OM"/etc/sddm.conf.d/10-wayland.conf /etc/sddm.conf.d/
printf '[Users]\nRememberLastUser=true\nRememberLastSession=true\n' > /etc/sddm.conf.d/99-omarchy-login.conf

# The theme draws in JetBrainsMono Nerd Font; the user's copy in ~/.local is unreadable to sddm.
install -d -m 755 /usr/local/share/fonts/omarchy
install -m 644 /home/guillaume/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf /usr/local/share/fonts/omarchy/
fc-cache -f /usr/local/share/fonts/omarchy >/dev/null

# Same as upstream install/login/sddm.sh: no login keyring prompt clash.
if [ -f /etc/pam.d/sddm ]; then
  sed -i -e '/-auth.*pam_gnome_keyring\.so/d' -e '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi

# Preselect the Omarchy (uwsm) session (the theme also picks the uwsm session itself).
install -d -m 755 -o sddm -g sddm /var/lib/sddm 2>/dev/null || install -d -m 755 /var/lib/sddm
printf '[Last]\nSession=/usr/share/wayland-sessions/omarchy.desktop\nUser=guillaume\n' > /var/lib/sddm/state.conf
chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true

# Switch display manager GDM -> SDDM (takes effect at next boot; GDM stays installed).
echo /usr/bin/sddm > /etc/X11/default-display-manager
systemctl disable gdm3.service 2>/dev/null || systemctl disable gdm.service 2>/dev/null || true
systemctl enable -f sddm.service

# --- Boot progress bar ------------------------------------------------------------------------
# Omarchy's Plymouth theme (logo + progress bar). Shown only on normal boots: after a failed or
# unclean boot GRUB's recordfail flag is set and the boot falls back to the text log.
install -d -m 755 /usr/share/plymouth/themes/omarchy
cp -r "$OM"/default/plymouth/. /usr/share/plymouth/themes/omarchy/
chmod -R u=rwX,go=rX /usr/share/plymouth/themes/omarchy
plymouth-set-default-theme omarchy

cat > /etc/grub.d/05_omarchy_splash <<'GRUB'
#!/bin/sh
# Omarchy (Debian port): splash only when the previous boot succeeded.
cat <<'EOF'
if [ "${recordfail}" = 1 ]; then set omarchy_splash=; else set omarchy_splash=splash; fi
export omarchy_splash
EOF
GRUB
chmod 755 /etc/grub.d/05_omarchy_splash
# $omarchy_splash is expanded by GRUB at boot time, not here.
if ! grep -q 'omarchy_splash' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 \\$omarchy_splash"/' /etc/default/grub
fi
update-grub
update-initramfs -u

echo "Login screen + boot splash installed. Reboot to see them."
