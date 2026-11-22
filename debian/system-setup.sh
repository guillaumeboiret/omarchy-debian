#!/bin/bash
# Debian port of Omarchy — system part (run with sudo). Idempotent.
set -euo pipefail
# The user this machine is set up for (the one who ran sudo) and the port checkout this script lives in.
# pwd -P resolves the /usr/share/omarchy symlink, so OM is always the real checkout.
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || true)}
[[ -n $TARGET_USER && $TARGET_USER != "root" ]] || { echo "run with sudo from your own account"; exit 1; }
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
OM=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

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
  qml6-module-qtquick-pdf xournalpp git-delta librsvg2-bin ydotool acpi gawk \
  libonig-dev \
  libarchive-tools ostree patchelf  # bsdtar/ostree/patchelf: the Electron app recipes in Install (Slack, Notion, Cursor…)
# (libonig-dev: Ghostty's system oniguruma; GTK4/libadwaita/gtk4-layer-shell dev files come with the shell's)

# 7. Omarchy calls its screensaver at a fixed /usr/lib path; the built app lives in ~/.local/lib
if [ ! -e /usr/lib/omarchy-screensaver ] || [ -L /usr/lib/omarchy-screensaver ]; then
  ln -sfn "$USER_HOME/.local/lib/omarchy-screensaver" /usr/lib/omarchy-screensaver
fi

# 8. folio as the "Open/Save file" picker: xdg-desktop-portal only reads /usr/share/…/portals
if [ -f "$USER_HOME/.local/share/xdg-desktop-portal/portals/folio.portal" ]; then
  ln -sfn "$USER_HOME/.local/share/xdg-desktop-portal/portals/folio.portal" /usr/share/xdg-desktop-portal/portals/folio.portal
fi

# 9. Omarchy's scripts are written for GNU awk (Arch's awk); Debian defaults to mawk
update-alternatives --set awk /usr/bin/gawk
# …and for Lua 5.4 (Arch's lua; Debian's default `lua` is 5.1, which lacks -E)
update-alternatives --set lua-interpreter /usr/bin/lua5.4

# 10. Browser theme colour (Omarchy's narrow passwordless rule). A root-owned COPY, never a link
#     into the user-writable tree; the script pins PATH and accepts only a 6-hex-digit colour.
install -o root -g root -m 755 "$OM/bin/omarchy-theme-set-browser-policy" /usr/bin/omarchy-theme-set-browser-policy
#     Same for the Claude extension installer, which elevates only its packaged /usr/bin copy.
install -o root -g root -m 755 "$OM/bin/omarchy-install-chromium-claude" /usr/bin/omarchy-install-chromium-claude
sed 's/^%wheel /%sudo /' "$OM/etc/sudoers.d/omarchy-theme-browser" > /tmp/omarchy-theme-browser.sudoers
if visudo -cf /tmp/omarchy-theme-browser.sudoers >/dev/null; then
  install -o root -g root -m 440 /tmp/omarchy-theme-browser.sudoers /etc/sudoers.d/omarchy-theme-browser
fi
rm -f /tmp/omarchy-theme-browser.sudoers

# 11. Feature dependencies found by the manual audit
apt-get install -y rfkill v4l-utils libxkbcommon-tools systemd-coredump npm python3-nautilus fido2-tools \
  fcitx5 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt6 fcitx5-config-qt udiskie
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
[ -x "$USER_HOME/.local/lib/omarchy/speedtest" ] && ln -sfn "$USER_HOME/.local/lib/omarchy/speedtest" /usr/lib/omarchy/speedtest

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

# 20. Boot menu: start the default entry immediately, or 5 s after an unclean shutdown (normally 30 s)
sed -i -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' -e 's/^GRUB_RECORDFAIL_TIMEOUT=.*/GRUB_RECORDFAIL_TIMEOUT=5/' /etc/default/grub
grep -q '^GRUB_RECORDFAIL_TIMEOUT=' /etc/default/grub || echo 'GRUB_RECORDFAIL_TIMEOUT=5' >> /etc/default/grub
update-grub

# 21. ydotool (voxtype dictation "type" mode) needs /dev/uinput. Omarchy adds the user to the
#     `input` group, which also exposes every keyboard/mouse for reading; the logged-in seat
#     user only needs write access to uinput, so grant that via logind (uaccess) instead.
#     The module must be loaded at boot: /dev/uinput is only a static placeholder until it is,
#     and the rule has no device to tag.
echo 'KERNEL=="uinput", TAG+="uaccess"' > /etc/udev/rules.d/71-omarchy-uinput.rules
echo uinput > /etc/modules-load.d/omarchy-uinput.conf
udevadm control --reload
modprobe uinput
udevadm trigger --action=change --sysname-match=uinput

# 22. Mac-like lid: logind leaves the lid to Omarchy (omarchy-system-lid-close: lock + suspend 30 s
#     after closing, cancelled on open, skipped with Stay Awake). Docked stays ignored.
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' > /etc/systemd/logind.conf.d/30-omarchy-lid.conf
systemctl kill -s HUP systemd-logind

# 23. Omarchy login screen (SDDM, replaces GDM) + Omarchy boot progress bar (Plymouth, normal boots only)
bash "$OM/debian/login-setup.sh"

# 24. The machine's own name in /etc/hosts (Debian's installer convention). Without it, sudo
#     warns "unable to resolve host" once libnss-myhostname is gone.
host=$(hostname)
if ! grep -qE "^127\.0\.1\.1[[:space:]].*\b$host\b" /etc/hosts; then
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$host/" /etc/hosts
  else
    printf '127.0.1.1\t%s\n' "$host" >> /etc/hosts
  fi
fi

# 25. Memory pressure, as omarchy-settings ships it on Arch: swap on zram sized to RAM (zstd), reclaim
#     tuned for zram, and systemd-oomd killing only user apps (app.slice) so the compositor survives.
#     Without these, Debian's 4 GiB zram default fills, the kernel OOM killer fires too late, and
#     Hyprland aborts when the GPU (shared RAM on Apple Silicon) can't allocate buffers.
#     Debian's kernel already leaves zswap off, so Omarchy's zswap tmpfiles rule isn't needed.
apt-get install -y systemd-oomd
install -Dm644 "$OM/default/systemd/zram-generator.conf.d/90-omarchy.conf" /etc/systemd/zram-generator.conf.d/90-omarchy.conf
install -Dm644 "$OM/etc/sysctl.d/99-omarchy-sysctl.conf" /etc/sysctl.d/99-omarchy-sysctl.conf
install -Dm644 "$OM/etc/systemd/oomd.conf.d/10-omarchy.conf" /etc/systemd/oomd.conf.d/10-omarchy.conf
install -Dm644 "$OM/default/systemd/user/app.slice.d/10-oomd.conf" /usr/lib/systemd/user/app.slice.d/10-oomd.conf
sysctl --system >/dev/null
systemctl daemon-reload
# The new zram size applies at next boot: resizing a live device first swaps everything back into RAM.
systemctl enable --now systemd-oomd
systemctl restart systemd-oomd
systemctl --machine="$TARGET_USER@" --user daemon-reload

# 26. omarchy-mac's audio watchdog stops the shell before restarting PipeWire/WirePlumber (Quickshell
#     crashes under a vanishing PipeWire). On Debian, Quickshell 0.3 segfaults on a graceful kill and
#     its crash handler relaunches a second shell, so the watchdog never sees 0 instances, gives up
#     ("the shell could not be stopped") and the built-in mic stays dead after WirePlumber loses it
#     (dictation records silence). Kill the shell + crash handler outright, as omarchy-restart-shell does.
WD=/usr/local/bin/omarchy-audio-watchdog
if [[ -f $WD ]] && ! grep -q 'Debian port: SIGKILL' "$WD"; then
  python3 - "$WD" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """        if count == 0:
            return 'none'
        for _ in range(10):"""
new = """        if count == 0:
            return 'none'
        if os.path.exists('/etc/debian_version'):
            # Debian port: SIGKILL the shell and its crash handler (Quickshell 0.3 segfaults on a
            # graceful kill and the crash handler relaunches a second shell).
            listing = self.output('quickshell', 'list', '-a', '-j', timeout=5) or ''
            try:
                pids = [i['pid'] for i in json.loads(listing[listing.find('['):]) if i.get('config_path') == os.environ['OMARCHY_PATH'] + '/shell/shell.qml']
            except (ValueError, TypeError, KeyError):
                pids = []
            for pid in pids:
                children = self.output('pgrep', '-P', str(pid), timeout=5) or ''
                for victim in children.split() + [str(pid)]:
                    with contextlib.suppress(ProcessLookupError, ValueError):
                        os.kill(int(victim), 9)
            self.sleep(0.5)
            if self.shell_instances() == 0:
                return 'stopped'
        for _ in range(10):"""
if s.count(old) != 1:
    sys.exit('omarchy-audio-watchdog changed upstream: stop_shell patch no longer applies')
open(p, 'w').write(s.replace(old, new))
PY
fi

# 27. Battery: omarchy-battery-reserve (user unit) puts the Mac to sleep at 5%. UPower's critical
#     action asks for HybridSleep, which Asahi can't do, so it powered off at 2% with no warning;
#     keep it only as a last resort at 1%.
sed -i -E 's/^PercentageCritical=.*/PercentageCritical=3.0/; s/^PercentageAction=.*/PercentageAction=1.0/; s/^CriticalPowerAction=.*/CriticalPowerAction=PowerOff/' /etc/UPower/UPower.conf
systemctl restart upower

# 28. Tailscale from Tailscale's own apt repo (Omarchy installs it from Arch's repos). The user is made
#     operator so the bar widget (omarchy.tailscale) can bring it up/down and log in without sudo.
#     Logging in is left to the user: `tailscale up` prints the auth URL, or click the bar icon.
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
systemctl enable --now tailscaled.service
tailscale set --operator="$TARGET_USER"

# 29. Passwordless sudo (Omarchy menu > Setup > Security > Passwordless Sudo, and the bar's red lock).
#     omarchy-sudo-passwordless runs its root side via sudo from /usr/bin, as Omarchy's package puts it
#     on Arch. Those are root-owned copies, never symlinks into the checkout: the checkout is
#     user-writable, so a link would hand root to anything running as the user. Arch's ALPM hook
#     revokes every grant before the package replaces the helper; on Debian this step does that before
#     it replaces a changed copy (and stops if revoking fails). The tmpfiles rule clears grants at boot.
if ! cmp -s "$OM/bin/omarchy-sudo-passwordless" /usr/bin/omarchy-sudo-passwordless ||
  ! cmp -s "$OM/bin/omarchy-security-functions" /usr/bin/omarchy-security-functions; then
  if [[ -x /usr/bin/omarchy-sudo-passwordless ]]; then
    /usr/bin/omarchy-sudo-passwordless __cleanup-all
  fi
  install -o root -g root -m 0755 "$OM/bin/omarchy-security-functions" "$OM/bin/omarchy-sudo-passwordless" /usr/bin/
fi
install -o root -g root -m 0644 "$OM/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf" /etc/tmpfiles.d/

# 30. Ghostty (built by omarchy-debian) is the terminal, GNOME Terminal the fallback. The other
#     terminals go: foot and xterm (gnome-terminal still provides x-terminal-emulator for xorg/xinit
#     and xdg-terminal-exec). foot-terminfo stays, ncurses-term depends on it.
apt-get purge -y foot xterm

echo "System part done."
