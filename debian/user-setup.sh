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
-- Omarchy's apps are built into ~/.local (omarchy-debian); put them on the session PATH.
-- uwsm-app launches through systemd, so its environment must get the same PATH.
local home = os.getenv("HOME")
-- mise's command-wrappers must come first (agent CLIs: claude/codex/grok dispatch per account),
-- and mise's shims last, matching Omarchy's default/bash/env-bootstrap.
local mise = home .. "/.local/share/mise"
local path = mise .. "/command-wrappers/bin:/usr/share/omarchy/bin:" .. home .. "/.local/bin:" .. home .. "/.cargo/bin:"
  .. home .. "/.local/share/omarchy/debian/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:"
  .. mise .. "/shims"
local qtplugins = home .. "/.local/lib/qt6/plugins"
hl.env("PATH", path)
hl.env("QT_PLUGIN_PATH", qtplugins)   -- qtengine theme
hl.on("hyprland.start", function()
  hl.exec_cmd("systemctl --user set-environment PATH='" .. path .. "' QT_PLUGIN_PATH='" .. qtplugins .. "'")
end)
-- GNOME Terminal counts as a terminal for Omarchy (⌘C/⌘V copy/paste, theme opacity)
o.window("org\\.gnome\\.Terminal", { tag = "+terminal" })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2 })
LUA
grep -q 'require("hypr.debian")' "$HOME/.config/hypr/hyprland.lua" || echo 'require("hypr.debian")' >> "$HOME/.config/hypr/hyprland.lua"

# 3. File chooser: folio (built by omarchy-debian) with GTK as fallback — Omarchy's default

# 4. uwsm session environment (OMARCHY_PATH + PATH)
mkdir -p "$HOME/.config/uwsm"
cat > "$HOME/.config/uwsm/env" <<UWSM
export OMARCHY_PATH=/usr/share/omarchy
export PATH="/usr/share/omarchy/bin:$HOME/.local/bin:$OM/debian/bin:\$PATH"
. /usr/share/omarchy/default/uwsm/env.d/10-omarchy
UWSM

# 5. Default apps: Omarchy's own (folio/omaview/omawrite, built by `omarchy-debian apps install`);
#    fall back to Debian apps for any that aren't built yet.
subst=()
command -v folio    >/dev/null || subst+=(-e 's/folio\.desktop/org.gnome.Nautilus.desktop/g')
command -v omaview  >/dev/null || subst+=(-e 's/omaview\.desktop/imv.desktop/g')
command -v omawrite >/dev/null || subst+=(-e 's/omawrite\.desktop/nvim.desktop/g')
sed "${subst[@]:-}" "$OM/default/applications/mimeapps.list" > "$HOME/.config/mimeapps.list.omarchy"
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

# 9. Login shells (bash -lc — how Omarchy's menu and bar run every action) get Omarchy's paths.
#    On Arch /etc/profile.d/omarchy.sh does this; Debian's /etc/profile resets PATH.
grep -q "Omarchy (Debian port): Omarchy" "$HOME/.profile" 2>/dev/null || cat >> "$HOME/.profile" <<'PROFILE'

# Omarchy (Debian port): Omarchy's menu, bar and scripts run commands through login
# shells (bash -lc). On Arch /etc/profile.d/omarchy.sh supplies these paths; here we do.
export OMARCHY_PATH=/usr/share/omarchy
for _d in "$HOME/.local/share/omarchy/debian/bin" "$HOME/.cargo/bin" "$HOME/.local/bin" "$OMARCHY_PATH/bin"; do
  PATH=$(printf '%s' ":$PATH:" | sed "s#:$_d:#:#g; s#^:##; s#:\$##")   # drop, then put in front
  [ -d "$_d" ] && PATH="$_d:$PATH"
done
unset _d
# Arch merges sbin into bin; Omarchy calls iw, rfkill… by bare name
case ":$PATH:" in *":/usr/sbin:"*) ;; *) PATH="$PATH:/usr/sbin:/sbin" ;; esac
export PATH
[ -r "$OMARCHY_PATH/default/bash/env-bootstrap" ] && . "$OMARCHY_PATH/default/bash/env-bootstrap"
PROFILE

# 10. GNOME Terminal follows Omarchy themes and fonts (it has no Omarchy template of its own)
for d in theme-set.d font-set.d; do
  mkdir -p "$HOME/.config/omarchy/hooks/$d"
  ln -sfn "$OM/debian/hooks/gnome-terminal" "$HOME/.config/omarchy/hooks/$d/gnome-terminal"
done
# 11. Omarchy's logo glyph font (installed system-wide by the Omarchy package on Arch)
mkdir -p "$HOME/.local/share/fonts/omarchy"
ln -sfn "$OM/default/fonts/omarchy/omarchy.ttf" "$HOME/.local/share/fonts/omarchy/omarchy.ttf"
fc-cache -f "$HOME/.local/share/fonts" >/dev/null
# 12. Colour emoji before DejaVu's monochrome ones in font fallback (Arch's noto-fonts-emoji does this)
mkdir -p "$HOME/.config/fontconfig/conf.d"
cp "$OM/debian/60-omarchy-emoji.conf" "$HOME/.config/fontconfig/conf.d/"
fc-cache -f >/dev/null
# 13. Launchers for Omarchy's lazy mise tools (codex, opencode, amp, ghui…) — they install on first run
command -v mise >/dev/null && mise reshim

# 14. Debian's desktop-wide autostart entries that don't belong in Omarchy: X11-only tools (picom,
#     xbindkeys, PulseAudio — PipeWire serves it), tray applets Omarchy's bar replaces, and
#     im-launch, which exports IBus settings over Omarchy's fcitx5. Hidden for Hyprland only, so
#     the GNOME fallback session keeps them.
mkdir -p "$HOME/.config/autostart"
for entry in picom xbindkeys pulseaudio im-launch blueman print-applet spice-vdagent xapp-sn-watcher; do
  src=/etc/xdg/autostart/$entry.desktop
  dst=$HOME/.config/autostart/$entry.desktop
  [[ -f $src && ! -f $dst ]] || continue
  if grep -q '^NotShowIn=' "$src"; then
    sed 's/^NotShowIn=\(.*\)/NotShowIn=\1;Hyprland;/; s/;;/;/g' "$src" >"$dst"
  else
    sed '/^\[Desktop Entry\]/a NotShowIn=Hyprland;' "$src" >"$dst"
  fi
done
# mako and hypridle came with the pre-Omarchy setup; Omarchy's shell does notifications and idle
systemctl --user mask mako.service hypridle.service   # Debian enables both globally; mask is the per-user off switch

# 15. Input method: Omarchy's fcitx5 environment (installed system-wide on Arch)
mkdir -p "$HOME/.config/environment.d"
cp "$OM/default/environment.d/10-omarchy-fcitx.conf" "$HOME/.config/environment.d/"

# 16. macOS cursors (github.com/ful1e5/apple_cursor), set for GTK/Firefox (gsettings), Xwayland/old
#     apps (~/.icons/default) and Hyprland/Qt (XCURSOR_* + setcursor in ~/.config/hypr/looknfeel.lua)
if [[ ! -d $HOME/.local/share/icons/macOS ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/macOS.tar.xz" https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz
  mkdir -p "$HOME/.local/share/icons"
  tar -xJf "$tmp/macOS.tar.xz" -C "$HOME/.local/share/icons" macOS
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.icons/default"
printf '[Icon Theme]\nInherits=macOS\n' >"$HOME/.icons/default/index.theme"
gsettings set org.gnome.desktop.interface cursor-theme macOS
gsettings set org.gnome.desktop.interface cursor-size 24
