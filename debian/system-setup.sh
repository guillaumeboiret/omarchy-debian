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

echo "System part done."
