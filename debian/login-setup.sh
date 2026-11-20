#!/bin/bash
# Debian port of Omarchy — Omarchy login screen (SDDM) + boot progress bar (Plymouth).
# Run with sudo. Idempotent. Also called from system-setup.sh (step 23).
#
# Undo the login screen (e.g. from a TTY, Ctrl+Alt+F3):
#   sudo systemctl disable sddm && sudo systemctl enable gdm3 && sudo reboot
#   (on Debian: sudo dpkg-reconfigure gdm3 to pick gdm3 as the default display manager)
set -euo pipefail
# The user this machine is set up for (the one who ran sudo) and the port checkout this script lives in.
# pwd -P resolves the /usr/share/omarchy symlink, so OM is always the real checkout.
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || true)}
[[ -n $TARGET_USER && $TARGET_USER != "root" ]] || { echo "run with sudo from your own account"; exit 1; }
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
OM=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
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
install -m 644 "$USER_HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" /usr/local/share/fonts/omarchy/
fc-cache -f /usr/local/share/fonts/omarchy >/dev/null

# Unlock the GNOME login keyring with the login password. Upstream (install/login/sddm.sh) DELETES
# these lines because Omarchy's keyring is passwordless; this machine's keyring came from GDM and is
# password-protected (gh token, browser secrets), so without them every login pops "The login keyring
# did not get unlocked" and gh/git push fail. Debian's stock /etc/pam.d/sddm has both lines.
if ! grep -q '^-auth.*pam_gnome_keyring\.so' /etc/pam.d/sddm; then
  sed -i '0,/^@include common-auth/s//@include common-auth\n-auth   optional        pam_gnome_keyring.so/' /etc/pam.d/sddm
fi
if ! grep -q '^-password.*pam_gnome_keyring\.so' /etc/pam.d/sddm; then
  sed -i '0,/^@include common-password/s//@include common-password\n-password optional      pam_gnome_keyring.so use_authtok/' /etc/pam.d/sddm
fi

# Preselect the Omarchy (uwsm) session (the theme also picks the uwsm session itself).
install -d -m 755 -o sddm -g sddm /var/lib/sddm 2>/dev/null || install -d -m 755 /var/lib/sddm
printf '[Last]\nSession=/usr/share/wayland-sessions/omarchy.desktop\nUser=%s\n' "$TARGET_USER" > /var/lib/sddm/state.conf
chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true

# Switch display manager GDM -> SDDM (takes effect at next boot; GDM stays installed).
echo /usr/bin/sddm > /etc/X11/default-display-manager
systemctl disable gdm3.service 2>/dev/null || systemctl disable gdm.service 2>/dev/null || true
systemctl enable -f sddm.service
# `enable` alone left display-manager.service unlinked here (boot ended at a text login), so link it
# explicitly and refuse to finish if it still doesn't point at SDDM.
ln -sfn /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
systemctl daemon-reload
systemctl set-default graphical.target
if [[ $(readlink -f /etc/systemd/system/display-manager.service) != */sddm.service ]]; then
  echo "display-manager.service does not point at SDDM — aborting"
  exit 1
fi

# --- Boot progress bar ------------------------------------------------------------------------
# Omarchy's Plymouth theme (logo + progress bar). Shown only on normal boots: after a failed or
# unclean boot GRUB's recordfail flag is set and the boot falls back to the text log.
install -d -m 755 /usr/share/plymouth/themes/omarchy
cp -r "$OM"/default/plymouth/. /usr/share/plymouth/themes/omarchy/
chmod -R u=rwX,go=rX /usr/share/plymouth/themes/omarchy
plymouth-set-default-theme omarchy

# Normal boot = splash and nothing else, like macOS: kernel/udev/systemd messages and the blinking
# console cursor are silenced. Asahi's kernel has no simpledrm, only the simplefb framebuffer, which
# Plymouth ignores at boot by default (it waits for the Apple display driver and shows text instead),
# so force the framebuffer. plymouth.debug only writes /var/log/plymouth-debug.log, for diagnosis.
# fbcon=vc:2-63: no text console on tty1 (boot/greeter VT) - when the splash drops the display, the
# kernel would otherwise flash tty1's text before SDDM appears. Ctrl+Alt+F2..F6 still have consoles.
splash_args="splash loglevel=0 fbcon=vc:2-63 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0 plymouth.force-frame-buffer-on-boot plymouth.debug"
{
  echo '#!/bin/sh'
  echo '# Omarchy (Debian port): silent splash boot only when the previous boot succeeded;'
  echo '# after a failed/unclean boot (recordfail) the normal text log is shown.'
  echo "cat <<'EOF'"
  # GRUB itself prints to the firmware console (= serial only with the quiet U-Boot, so nothing on
  # screen); after a failed boot it switches to its graphical terminal so the menu is visible.
  echo "if [ \"\${recordfail}\" = 1 ]; then"
  echo "  set omarchy_splash="
  echo "  if loadfont unicode; then set gfxmode=auto; load_video; insmod gfxterm; terminal_output gfxterm; fi"
  echo "else"
  echo "  set omarchy_splash=\"$splash_args\""
  echo "fi"
  echo 'export omarchy_splash'
  echo 'EOF'
} > /etc/grub.d/05_omarchy_splash
chmod 755 /etc/grub.d/05_omarchy_splash
# $omarchy_splash is expanded by GRUB at boot time, not here.
if ! grep -q 'omarchy_splash' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 \\$omarchy_splash"/' /etc/default/grub
fi
# Normal boots: no GRUB menu, no wait, and GRUB draws nothing (text terminal = firmware console,
# not its graphical terminal + Debian background). After a failed boot the recordfail branch of
# GRUB's timeout code shows the menu for 5 s (graphical, see 05_omarchy_splash).
# To see the menu + log on purpose: sudo omarchy-boot-verbose-next, then reboot.
set_grub() {
  if grep -q "^$1=" /etc/default/grub; then
    sed -i "s|^$1=.*|$1=$2|" /etc/default/grub
  else
    echo "$1=$2" >> /etc/default/grub
  fi
}
set_grub GRUB_TIMEOUT 0
set_grub GRUB_TIMEOUT_STYLE hidden
set_grub GRUB_TERMINAL_OUTPUT console
install -m 755 "$OM/debian/bin/omarchy-boot-verbose-next" /usr/local/sbin/omarchy-boot-verbose-next
# Debian hardcodes quiet_boot=0 in this conffile (Ubuntu sets 1); a grub upgrade may ask about it.
sed -i 's/^quiet_boot="0"/quiet_boot="1"/' /etc/grub.d/10_linux

# Keep the last splash frame on screen until SDDM's compositor takes the display. Debian's
# plymouth-quit runs as soon as boot is done and SDDM is not ordered after it, so the text console
# showed for a few seconds while the greeter started (GDM does this handover itself).
install -d -m 755 /etc/systemd/system/plymouth-quit.service.d
printf '[Service]\nExecStart=\nExecStart=-/usr/bin/plymouth quit --retain-splash\n' > /etc/systemd/system/plymouth-quit.service.d/omarchy-retain-splash.conf
install -d -m 755 /etc/systemd/system/sddm.service.d
printf '[Unit]\nAfter=plymouth-quit.service\n' > /etc/systemd/system/sddm.service.d/omarchy-after-plymouth.conf
systemctl daemon-reload

update-grub
update-initramfs -u

echo "Login screen + boot splash installed. Reboot to see them."
