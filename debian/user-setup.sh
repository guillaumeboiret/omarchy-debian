#!/bin/bash
# Debian port of Omarchy — user part. Idempotent; backs up anything it replaces.
set -euo pipefail
OM="$HOME/.local/share/omarchy"
BK="$HOME/.config/backup-before-omarchy-$(date +%Y%m%d-%H%M)"
export OMARCHY_PATH=/usr/share/omarchy
export PATH="$OMARCHY_PATH/bin:$OM/debian/bin:$PATH"
mkdir -p "$BK"

# 1. Configs from Omarchy's config/ (what Arch puts in /etc/skel). Replace + back up these:
for d in hypr btop ghostty lazygit tmux starship.toml omarchy xdg-desktop-portal hyprland-mimeapps.list chromium-flags.conf; do
  [ -e "$OM/config/$d" ] || continue
  if [ -e "$HOME/.config/$d" ]; then mv "$HOME/.config/$d" "$BK/"; fi
  cp -a "$OM/config/$d" "$HOME/.config/$d"
done
# Terminal: Ghostty (built by omarchy-debian), GNOME Terminal as the fallback
printf '%s\n' '# Terminal emulator preference order for xdg-terminal-exec' \
  '# The first found and valid terminal will be used' \
  com.mitchellh.ghostty.desktop org.gnome.Terminal.desktop > "$HOME/.config/xdg-terminals.list"
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
LUA
grep -q 'require("hypr.debian")' "$HOME/.config/hypr/hyprland.lua" || echo 'require("hypr.debian")' >> "$HOME/.config/hypr/hyprland.lua"
# Retina panel default in hypr/monitors.lua: it loads before the display panel's
# saved layout, so that layout wins (in debian.lua it loaded last and pinned eDP-1).
grep -q 'output = "eDP-1"' "$HOME/.config/hypr/monitors.lua" ||
  printf '\n-- Debian port: Retina panel default (the display panel'"'"'s saved choices win).\nhl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })\n' >> "$HOME/.config/hypr/monitors.lua"

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

# 10. GNOME Terminal and Firefox follow Omarchy themes and fonts (no Omarchy templates of their own)
for d in theme-set.d font-set.d; do
  mkdir -p "$HOME/.config/omarchy/hooks/$d"
  for hook in gnome-terminal firefox; do
    ln -sfn "$OM/debian/hooks/$hook" "$HOME/.config/omarchy/hooks/$d/$hook"
  done
done
bash "$OM/debian/hooks/firefox"
# 11. Omarchy's logo glyph font (installed system-wide by the Omarchy package on Arch)
mkdir -p "$HOME/.local/share/fonts/omarchy"
ln -sfn "$OM/default/fonts/omarchy/omarchy.ttf" "$HOME/.local/share/fonts/omarchy/omarchy.ttf"
fc-cache -f "$HOME/.local/share/fonts" >/dev/null
# 12. Colour emoji before DejaVu's monochrome ones in font fallback (Arch's noto-fonts-emoji does this)
mkdir -p "$HOME/.config/fontconfig/conf.d"
cp "$OM/debian/60-omarchy-emoji.conf" "$OM/debian/61-text-symbols-not-emoji.conf" "$HOME/.config/fontconfig/conf.d/"
fc-cache -f >/dev/null
# 13. Launchers for Omarchy's lazy mise tools (codex, opencode, amp, ghui…) — they install on first run
command -v mise >/dev/null && mise reshim

# 14. Debian's desktop-wide autostart entries that don't belong in Omarchy: X11-only tools (picom,
#     xbindkeys, PulseAudio — PipeWire serves it), tray applets Omarchy's bar replaces, and
#     im-launch, which exports IBus settings over Omarchy's fcitx5. Hidden for Hyprland only, and
#     only for entries that are installed.
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
# mako and hypridle, if installed: Omarchy's shell does notifications and idle, and Debian enables
# both globally; mask is the per-user off switch
for unit in mako.service hypridle.service hyprpaper.service; do
  [[ -f /usr/lib/systemd/user/$unit ]] && systemctl --user mask "$unit"
done

# 15. Input method: Omarchy's fcitx5 environment (installed system-wide on Arch)
mkdir -p "$HOME/.config/environment.d"
cp "$OM/default/environment.d/10-omarchy-fcitx.conf" "$HOME/.config/environment.d/"

# 16. macOS cursors (github.com/ful1e5/apple_cursor), set for GTK/Firefox (gsettings), Xwayland/old
#     apps (~/.icons/default) and Hyprland/Qt (XCURSOR_* + setcursor in ~/.config/hypr/looknfeel.lua)
if [[ ! -d $HOME/.local/share/icons/macOS ]]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/macOS.tar.xz" https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz
  tar -xJf "$tmp/macOS.tar.xz" -C "$tmp"   # entries are ./macOS/ and ./macOS-White/
  mkdir -p "$HOME/.local/share/icons"
  mv "$tmp/macOS" "$HOME/.local/share/icons/"
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.icons/default"
printf '[Icon Theme]\nInherits=macOS\n' >"$HOME/.icons/default/index.theme"
gsettings set org.gnome.desktop.interface cursor-theme macOS
gsettings set org.gnome.desktop.interface cursor-size 24

# 17. Copy on select: selected text also goes to the clipboard (debian/bin/omarchy-copy-on-select)
mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/omarchy-copy-on-select.service" <<'UNIT'
[Unit]
Description=Copy selected text to the clipboard (copy on select)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/share/omarchy/debian/bin/omarchy-copy-on-select
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable omarchy-copy-on-select.service

# 18. Built-in microphone: asahi-audio's mic DSP targets the AOP array by its Arch/Fedora node name;
#     Debian's Asahi kernel names it differently, so rename the node (else the DSP records the
#     default source, i.e. itself, and dictation gets silence). Applies at the next WirePlumber start.
mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
install -m644 "$OM/debian/wireplumber/51-asahi-mic-node-name.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/"

# 19. Battery reserve: sleep at 5% (shown as 0%) instead of UPower powering off at 2%
#     (debian/bin/omarchy-battery-reserve; UPower's own action moves to 1% in system-setup.sh)
cat >"$HOME/.config/systemd/user/omarchy-battery-reserve.service" <<'UNIT'
[Unit]
Description=Sleep at the battery reserve (5%, shown as 0%) instead of powering off
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/share/omarchy/debian/bin/omarchy-battery-reserve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable omarchy-battery-reserve.service

# 20. Tailscale (installed by system-setup.sh step 28): Taildrop files land in ~/Downloads via Omarchy's
#     receive service, with ExecStart repointed from Arch's /usr/bin to the port checkout. The unit
#     waits for /usr/bin/tailscale (ConditionPathExists), so enabling it before the install is harmless.
sed 's|^ExecStart=/usr/bin/|ExecStart=/usr/share/omarchy/bin/|' "$OM/default/systemd/user/omarchy-tailscale-receive.service" \
  >"$HOME/.config/systemd/user/omarchy-tailscale-receive.service"
systemctl --user daemon-reload
systemctl --user enable omarchy-tailscale-receive.service

# 21. Weekly update check (debian/bin/omarchy-update-check): upstream is fetched on Saturdays only,
#     so the bar's update badge shows that week's update instead of a new one every day.
cat >"$HOME/.config/systemd/user/omarchy-update-check.service" <<'UNIT'
[Unit]
Description=Check for Omarchy updates (Saturdays)

[Service]
Type=oneshot
ExecStart=/usr/share/omarchy/debian/bin/omarchy-update-check
Restart=on-failure
RestartSec=15min
UNIT
cat >"$HOME/.config/systemd/user/omarchy-update-check.timer" <<'UNIT'
[Unit]
Description=Weekly Omarchy update check (Saturday 10:00)

[Timer]
OnCalendar=Sat *-*-* 10:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now omarchy-update-check.timer
