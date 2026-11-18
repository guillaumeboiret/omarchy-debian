#!/bin/bash
# Debian port of Omarchy — user part. Idempotent; backs up anything it replaces.
set -euo pipefail
OM="$HOME/.local/share/omarchy"
BK="$HOME/.config/backup-before-omarchy-$(date +%Y%m%d-%H%M)"
export OMARCHY_PATH=/usr/share/omarchy
export PATH="$OMARCHY_PATH/bin:$OM/debian/bin:$PATH"
mkdir -p "$BK"

# 1. Configs from Omarchy's config/ (what Arch puts in /etc/skel). Replace + back up these:
for d in hypr kitty alacritty btop foot ghostty lazygit tmux starship.toml omarchy xdg-desktop-portal hyprland-mimeapps.list chromium-flags.conf; do
  [ -e "$OM/config/$d" ] || continue
  if [ -e "$HOME/.config/$d" ]; then mv "$HOME/.config/$d" "$BK/"; fi
  cp -a "$OM/config/$d" "$HOME/.config/$d"
done
# git aliases only if the user has no git config of their own there
[ -e "$HOME/.config/git/config" ] || { mkdir -p "$HOME/.config/git"; cp "$OM/config/git/config" "$HOME/.config/git/config"; }

# 2. Debian/Mac tweaks loaded after Omarchy's defaults
cat > "$HOME/.config/hypr/debian.lua" <<'LUA'
-- Debian port overrides (loaded last)
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")   -- Omarchy's qtengine isn't packaged for Debian
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })
LUA
grep -q 'require("hypr.debian")' "$HOME/.config/hypr/hyprland.lua" || echo 'require("hypr.debian")' >> "$HOME/.config/hypr/hyprland.lua"

# 3. File chooser: folio isn't available → GTK
sed -i 's/FileChooser=folio;gtk/FileChooser=gtk/' "$HOME/.config/xdg-desktop-portal/"*.conf

# 4. uwsm session environment (OMARCHY_PATH + PATH)
mkdir -p "$HOME/.config/uwsm"
cat > "$HOME/.config/uwsm/env" <<UWSM
export OMARCHY_PATH=/usr/share/omarchy
export PATH="/usr/share/omarchy/bin:$HOME/.local/bin:$OM/debian/bin:\$PATH"
. /usr/share/omarchy/default/uwsm/env.d/10-omarchy
UWSM

# 5. Default apps (folio/omaview/omawrite → Debian apps)
sed -e 's/folio\.desktop/org.gnome.Nautilus.desktop/g; s/omaview\.desktop/imv.desktop/g; s/omawrite\.desktop/nvim.desktop/g' \
  "$OM/default/applications/mimeapps.list" > "$HOME/.config/mimeapps.list.omarchy"
[ -e "$HOME/.config/mimeapps.list" ] && cp "$HOME/.config/mimeapps.list" "$BK/"
cp "$HOME/.config/mimeapps.list.omarchy" "$HOME/.config/mimeapps.list"

# 6. Web apps + Omarchy launchers in the app menu
mkdir -p "$HOME/.local/share/applications/icons"
cp -a "$OM/applications/"*.desktop "$HOME/.local/share/applications/"
cp -a "$OM/applications/icons/." "$HOME/.local/share/applications/icons/"
rm -f "$HOME/.local/share/applications/"webapp-*.desktop   # the earlier non-Omarchy web apps
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# 7. Theme (generate only, don't reload the running session)
HYPRLAND_INSTANCE_SIGNATURE= omarchy-theme-set tokyo-night || true

# 8. Skip Omarchy's Arch first-run (audio tuning for other hardware, etc.); do the safe parts
omarchy-done mark first-run-user
bash "$OM/install/user/first-run/gnome-theme.sh" || true
bash "$OM/install/user/first-run/gtk-primary-paste.sh" || true

echo "User part done. Backups in: $BK"
