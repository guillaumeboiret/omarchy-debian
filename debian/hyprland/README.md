# Local Hyprland build: clip sliding workspaces

Hyprland 0.55.2 (Debian `0.55.2+ds-1~bpo13+1`) draws every window of a sliding workspace at its position plus the slide offset, with no clip to that workspace's own area of the monitor. On a scrolling workspace, the columns that sit off-screen then slide in over the neighbouring workspace during a workspace switch or a three/four-finger swipe. Upstream: hyprwm/Hyprland#15725 (closed, not planned), PR #14054 (hide off-screen columns, unmerged).

`local-clip-sliding-workspace.patch` (quilt patch, DEP-3 header) fixes it in the renderer:

- `src/render/SlideClip.hpp` (new): `Render::slidingWorkspaceClip()` gives the clip box for a window whose regular workspace is sliding on its own monitor (render offset not zero), and nothing otherwise.
- `src/render/Renderer.cpp`, `IHyprRenderer::renderWindow()`: skips a window entirely outside that box, and clips the surface of the others to it.
- `src/render/gl/GLElementRenderer.cpp`, border draw, and `src/render/decorations/CHyprDropShadowDecoration.cpp`, `render()`: clip the border and the shadow the same way.

At rest (offset zero), on special workspaces and for pinned windows, nothing changes. No header used by plugins changes layout.

## Build

```bash
debian/hyprland/build.sh   # no sudo; output in ~/.cache/omarchy-debian/hyprland/
```

The build dependencies are unpacked into a scratch prefix at the exact versions of the stock build (from its `.buildinfo`); the ones the archive has dropped come from snapshot.debian.org, checked by SHA-1. Nothing is installed system-wide.

## Install

```bash
sudo dpkg -i ~/.cache/omarchy-debian/hyprland/hyprland_0.55.2+ds-1~bpo13+1+local1_arm64.deb
```

Then log out and back in (the running compositor keeps the old binary until then; SDDM's greeter also runs Hyprland).

## Roll back

The stock package is kept in `~/.local/share/omarchy-port/hyprland-rollback/`. From a TTY (Ctrl+Alt+F3) if the session or login screen does not come up:

```bash
sudo dpkg -i ~/.local/share/omarchy-port/hyprland-rollback/hyprland_0.55.2+ds-1~bpo13+1_arm64.deb
sudo systemctl restart sddm
```

## When apt replaces it

The local version sorts above the stock `0.55.2+ds-1~bpo13+1` and below any newer Debian upload, so an official update replaces it cleanly (it is not held). `default/hypr/local-build-check.lua` then shows a notification once per Hyprland version. On a new version, check whether upstream fixed the slide clipping; if not, port the patch, update `ver` and the dependency list in `build.sh` (from the new `.buildinfo`), rebuild and reinstall.
