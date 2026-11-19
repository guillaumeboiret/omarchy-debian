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

echo "System part done."
