# Omarchy on Debian

An unofficial port of [Omarchy](https://github.com/basecamp/omarchy) (4.0 "Quattro" alpha) from Arch to Debian 13 "trixie". It's built and used daily on an Apple Silicon Mac running the [Debian Asahi](https://wiki.debian.org/InstallingDebianOn/Apple/M1) port. Not affiliated with Basecamp or the Omarchy project.

The goal is to run the real Omarchy, not a lookalike: its Hyprland config, Quickshell desktop (bar, menu, notifications, lock screen, wallpapers), theme switching and its own apps. Everything Debian-specific lives in this `debian/` folder and in small, commented patches to Omarchy's own files. Comparing this branch with upstream's `quattro` branch shows every change.

## Status

Works: the full Omarchy desktop and menu, theme and font switching, the SDDM login screen and Plymouth boot splash, lock screen, screenshots and recording, and Omarchy's own apps, compiled from their Arch recipes.

Not built (and why):
- `hype`: needs Qt 6.9 (Debian has 6.8)
- `omarchy-hyprland-titlebars`: needs Hyprland 0.56 (backports has 0.55)
- `superwhisper`: closed-source Arch binary
- `omarchy-local-ai` and `omarchy-power-profiles-daemon`: not attempted

Apple Silicon specifics (quiet U-Boot, the Mac function-row keys, brightness through logind, the Retina console font) are guarded or kept in separate scripts. On other hardware they're skipped or easy to leave out, but only Apple Silicon has been tested.

## Requirements

- Debian 13 (trixie) with `trixie-backports` enabled
- `hyprland` 0.55 and `quickshell` 0.3 from backports: `sudo apt install -t trixie-backports hyprland quickshell`
- A normal user account with sudo

## Install

The port expects to live at `~/.local/share/omarchy` (Omarchy also gets linked at `/usr/share/omarchy`).

```bash
git clone -b debian-port https://github.com/guillaumeboiret/omarchy-debian ~/.local/share/omarchy
cd ~/.local/share/omarchy/debian
sudo ./system-setup.sh        # packages, PAM, login screen, boot splash, system links
./user-setup.sh               # Omarchy configs into ~/.config (anything replaced is backed up)
./omarchy-debian apps install # build Omarchy's own apps into ~/.local (takes a while)
```

Then log out and choose the **Omarchy** session on the login screen. All three scripts are idempotent, so rerunning them is safe. Read `system-setup.sh` before running it: each numbered step says what it changes and why.

Optional:
- `sudo ./mesa-backports.sh`: newer Asahi Mesa from backports (`--rollback` undoes it)
- `sudo ./quiet-firmware-setup.sh`: Apple Silicon only. Hides U-Boot text at boot; the recovery steps are at the top of the file.

## Updating

```bash
omarchy-debian update
```

This rebases the Debian patches onto the latest upstream Omarchy, rebuilds the apps whose recipe changed, and updates Flatpaks and Neovim plugins. The "Update" entry in the Omarchy menu calls it too.

## What's in this folder

| Path | What it is |
| --- | --- |
| `system-setup.sh`, `user-setup.sh`, `login-setup.sh` | Install steps (root part, user part, login screen + boot splash) |
| `omarchy-debian` | Builds Omarchy's apps from their Arch recipes (a small makepkg-compatible runner) and runs updates |
| `recipes/`, `patches/` | Recipe overrides and per-app fixes for Debian's Qt 6.8 / Poppler / KF6 (they fail loudly if upstream changes) |
| `pkgmap` | Arch package names → Debian package names |
| `bin/` | Stand-ins for Arch-only commands, and Debian wrappers (e.g. `brightnessctl` through logind) |
| `hooks/` | Theme/font hooks for apps Omarchy has no template for: GNOME Terminal and Firefox (square corners, theme colors, Omarchy font) |

## License

MIT, same as Omarchy. See [`LICENSE`](../LICENSE).
