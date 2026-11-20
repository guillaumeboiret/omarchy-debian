#!/bin/bash
# Debian port of Omarchy — system part (run with sudo). Idempotent.
set -euo pipefail
OM=/home/guillaume/.local/share/omarchy

# 1. Omarchy expects to live in /usr/share/omarchy
if [ -e /usr/share/omarchy ] && [ ! -L /usr/share/omarchy ]; then echo "/usr/share/omarchy exists and is not a symlink — aborting"; exit 1; fi
ln -sfn "$OM" /usr/share/omarchy

# 2. Lock-screen password check, Debian style (Omarchy's uses Arch-only 'system-local-login')
cat > /etc/pam.d/omarchy-lock-password <<'PAM'
#%PAM-1.0
# Omarchy shell lock screen — Debian port
@include common-auth
@include common-account
PAM

# 3. "Omarchy" session on the GDM login screen
install -Dm644 "$OM/default/wayland-sessions/omarchy.desktop" /usr/share/wayland-sessions/omarchy.desktop

# 4. Omarchy's keyboard option (Shift+Caps Lock = Compose); Hyprland reads /etc/xkb
mkdir -p /etc/xkb && cp -a "$OM/etc/xkb/." /etc/xkb/ && chown -R root:root /etc/xkb

# 5. Debian packages the Omarchy shell needs beyond the main app list
apt-get install -y qt6-image-formats-plugins qml6-module-qtquick-effects qml6-module-qtmultimedia qml6-module-qt-labs-qmlmodels

# 6. Build tools for compiling Omarchy's own apps (debian/omarchy-debian apps)
apt-get install -y cargo rustc meson ninja-build extra-cmake-modules \
  qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-multimedia-dev \
  qt6-shadertools-dev qt6-svg-dev qt6-tools-dev qt6-wayland-dev layer-shell-qt liblayershellqtinterface-dev \
  libkf6colorscheme-dev libkf6config-dev libkf6iconthemes-dev libarchive-dev libpoppler-qt6-dev libqpdf-dev \
  libnss3-dev libpulse-dev libtesseract-dev libleptonica-dev libmpv-dev libsource-highlight-dev \
  libavcodec-dev libavformat-dev libswscale-dev libturbojpeg0-dev \
  qml6-module-qtquick-pdf xournalpp git-delta librsvg2-bin ydotool acpi gawk

# 7. Omarchy calls its screensaver at a fixed /usr/lib path; the built app lives in ~/.local/lib
if [ ! -e /usr/lib/omarchy-screensaver ] || [ -L /usr/lib/omarchy-screensaver ]; then
  ln -sfn /home/guillaume/.local/lib/omarchy-screensaver /usr/lib/omarchy-screensaver
fi

# 8. folio as the "Open/Save file" picker: xdg-desktop-portal only reads /usr/share/…/portals
if [ -f /home/guillaume/.local/share/xdg-desktop-portal/portals/folio.portal ]; then
  ln -sfn /home/guillaume/.local/share/xdg-desktop-portal/portals/folio.portal /usr/share/xdg-desktop-portal/portals/folio.portal
fi

# 9. Omarchy's scripts are written for GNU awk (Arch's awk); Debian defaults to mawk
update-alternatives --set awk /usr/bin/gawk
# …and for Lua 5.4 (Arch's lua; Debian's default `lua` is 5.1, which lacks -E)
update-alternatives --set lua-interpreter /usr/bin/lua5.4

# 10. Browser theme colour (Omarchy's narrow passwordless rule). A root-owned COPY, never a link
#     into the user-writable tree; the script pins PATH and accepts only a 6-hex-digit colour.
install -o root -g root -m 755 "$OM/bin/omarchy-theme-set-browser-policy" /usr/bin/omarchy-theme-set-browser-policy
sed 's/^%wheel /%sudo /' "$OM/etc/sudoers.d/omarchy-theme-browser" > /tmp/omarchy-theme-browser.sudoers
if visudo -cf /tmp/omarchy-theme-browser.sudoers >/dev/null; then
  install -o root -g root -m 440 /tmp/omarchy-theme-browser.sudoers /etc/sudoers.d/omarchy-theme-browser
fi
rm -f /tmp/omarchy-theme-browser.sudoers

# 11. Feature dependencies found by the manual audit
apt-get install -y rfkill v4l-utils libxkbcommon-tools systemd-coredump npm python3-nautilus fido2-tools \
  fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt6 fcitx5-config-qt
# wl-copy --sensitive (emoji picker, QR capture, "copy code") needs wl-clipboard ≥ 2.3 (backports)
apt-get install -y -t trixie-backports wl-clipboard

# 12. Lazy-installed agent CLIs and tools (codex, opencode, amp, ghui…) are declared in mise's system config
install -d /etc/mise/conf.d
install -m 644 "$OM"/etc/mise/conf.d/*.toml /etc/mise/conf.d/

# 13. Chromium: theme colour policy dir, and make Debian's chromium read ~/.config/chromium-flags.conf
#     (Omarchy's extensions — Copy URL, Download Video — are loaded through those flags)
install -d /etc/chromium/policies/managed
cat > /etc/chromium.d/omarchy-flags <<'FLAGS'
# Omarchy (Debian port): apply the user's ~/.config/chromium-flags.conf like Arch's chromium does
if [ -r "$HOME/.config/chromium-flags.conf" ]; then
  CHROMIUM_FLAGS="$CHROMIUM_FLAGS $(grep -v '^[[:space:]]*#' "$HOME/.config/chromium-flags.conf" | tr '\n' ' ')"
fi
FLAGS

# 14. Branded About screen (fastfetch)
install -d /etc/fastfetch
cp -r "$OM"/etc/fastfetch/. /etc/fastfetch/

# 15. Timezone changes from the menu / world clock: Omarchy's narrow rule (timedatectl set-timezone only)
sed 's/^%wheel /%sudo /' "$OM/etc/sudoers.d/omarchy-tzupdate" > /tmp/omarchy-tzupdate.sudoers
if visudo -cf /tmp/omarchy-tzupdate.sudoers >/dev/null; then
  install -o root -g root -m 440 /tmp/omarchy-tzupdate.sudoers /etc/sudoers.d/omarchy-tzupdate
fi
rm -f /tmp/omarchy-tzupdate.sudoers

# 16. Network speed test binary at the path Omarchy expects (built by omarchy-debian)
install -d /usr/lib/omarchy
[ -x /home/guillaume/.local/lib/omarchy/speedtest ] && ln -sfn /home/guillaume/.local/lib/omarchy/speedtest /usr/lib/omarchy/speedtest

# 17. Power button: short press = Omarchy power menu (Hyprland XF86PowerOff bind), long press (≥5 s) = power off.
#     Omarchy's drop-in only ignores the key; on Debian we also keep a long-press shutdown.
install -d /etc/systemd/logind.conf.d
printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\n' > /etc/systemd/logind.conf.d/10-ignore-power-button.conf
systemctl kill -s HUP systemd-logind   # reload config without ending sessions

# 18. Firefox: Omarchy's policy (no "make default" nag, VA-API, fractional scaling, swipe nav).
#     Needed here: http/https go through omarchy-browser.desktop (~/.config/hyprland-mimeapps.list),
#     so Firefox never sees itself as the default and would ask on every launch.
install -d -m 755 /usr/lib/firefox/distribution
install -o root -g root -m 644 "$OM/default/firefox/policies.json" /usr/lib/firefox/distribution/policies.json

# 19. Readable boot/TTY text on the Retina panel: kernel console font Terminus 16x32 from the first
#     boot message (fbcon=), and the same size for the TTYs once console-setup runs.
if ! grep -q 'fbcon=font:TER16x32' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 fbcon=font:TER16x32"/' /etc/default/grub
  update-grub
fi
sed -i -e 's/^FONTFACE=.*/FONTFACE="Terminus"/' -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' /etc/default/console-setup
setupcon --save-only 2>/dev/null || true

# 20. Boot menu: start the default entry after 1 s, or 5 s after an unclean shutdown (normally 30 s)
sed -i -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' -e 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=5/' /etc/default/grub
grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub || echo 'GRUB_RECORDFAIL_TIMEOUT=5' >> /etc/default/grub
update-grub

# 21. ydotool (voxtype dictation "type" mode) needs /dev/uinput. Omarchy adds the user to the
#     `input` group, which also exposes every keyboard/mouse for reading; the logged-in seat
#     user only needs write access to uinput, so grant that via logind (uaccess) instead.
echo 'KERNEL=="uinput", TAG+="uaccess"' > /etc/udev/rules.d/71-omarchy-uinput.rules
udevadm control --reload
udevadm trigger --name-match=uinput

echo "System part done."
