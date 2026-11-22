#!/bin/bash
# Rebuild Debian's hyprland 0.55.2+ds-1~bpo13+1 with local-clip-sliding-workspace.patch
# as 0.55.2+ds-1~bpo13+1+local1 (see README.md next to this script).
#
# Builds without sudo: the build dependencies are unpacked into a scratch prefix,
# at the exact versions the stock package links against (libhyprutils12 0.13.1,
# libaquamarine10 0.11.0 from snapshot.debian.org, which the archive no longer has).
# Output: ~/.cache/omarchy-debian/hyprland/hyprland_*+local1_arm64.deb
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=${WORK:-$HOME/.cache/omarchy-debian/hyprland/build}
out=$HOME/.cache/omarchy-debian/hyprland
pool=https://deb.debian.org/debian/pool/main
snapshot=https://snapshot.debian.org/file
ver=0.55.2+ds-1~bpo13+1
local_ver=$ver+local1
pf=$work/prefix
lib=$pf/usr/lib/aarch64-linux-gnu

rm -rf "$work" && mkdir -p "$work/debs" "$pf" "$out"
cd "$work"

for f in "hyprland_$ver.dsc" "hyprland_$ver.debian.tar.xz" hyprland_0.55.2+ds.orig.tar.xz; do
  curl -sfLO "$pool/h/hyprland/$f"
done

# Build dependencies at the versions the stock build used (its .buildinfo on
# buildinfos.debian.net). The ones the archive has dropped come from snapshot.debian.org.
(
  cd debs
  while read -r sha1 file; do
    curl -sfL -o "$file" "$snapshot/$sha1"
    echo "$sha1  $file" | sha1sum -c --quiet
  done <<'SNAPSHOT'
5caf70ac758a85cf158ce0d83f3473105132836c libaquamarine-dev_0.11.0-2~bpo13+1_arm64.deb
3694da8333b627317c59c8de87578a4490da456b libhyprutils-dev_0.13.1-2~bpo13+1_arm64.deb
b8118aa5944b9a9fe74d39bb27af0bce91652bcc hyprland-protocols_0.7.0-1~bpo13+1_all.deb
36f817c5207fa065cc6b98a81e75432dca06fd4f hyprwire-scanner_0.3.0-3~bpo13+1_arm64.deb
d64873b59f0904ea982bab7c91b18f59da62d2d9 libhyprwire-dev_0.3.0-3~bpo13+1_arm64.deb
8295ed6e8b401877f7d0a21cf6e716d529a5638f libglaze-dev_7.6.0-1~bpo13+1_all.deb
57fa9dcc71c946ed8625963f5947cefab898e98b libudis86-dev_0+20221013-1.1_arm64.deb
SNAPSHOT
  apt-get download -q \
    hyprwayland-scanner=0.4.6-1~bpo13+1 libhyprlang-dev=0.6.8-4~bpo13+1 libhyprcursor-dev=0.1.13-2~bpo13+1 \
    libhyprgraphics-dev=0.5.1-2~bpo13+1 wayland-protocols=1.47-1~bpo13+1 \
    glslang-dev glslang-tools spirv-tools liblua5.4-dev libmuparser-dev libre2-dev libabsl-dev libseat-dev \
    libtomlplusplus-dev libxcb-xfixes0-dev libxcb-icccm4-dev libxcb-composite0-dev libxcb-res0-dev \
    libxcb-errors-dev libxcb-shape0-dev >/dev/null
)
for f in debs/*.deb; do dpkg-deb -x "$f" "$pf"; done

# Point the unpacked -dev links at the installed runtime libraries, and pkg-config at the prefix.
find "$pf" -xtype l | while read -r link; do
  ln -sf "/usr/lib/aarch64-linux-gnu/$(basename "$(readlink "$link")")" "$(dirname "$link")/$(basename "$(readlink "$link")")"
done
find "$pf" -name '*.pc' -exec sed -i -e "s|^prefix=/usr|prefix=$pf/usr|" -e "s|=/usr/bin/|=$pf/usr/bin/|" {} +
# liblua5.4-dev's postinst makes lua.pc an alternative; CMakeLists.txt looks for "lua<5.6".
ln -sf lua5.4.pc "$lib/pkgconfig/lua.pc"
# The xcb extension headers include "xcb.h" from their own directory.
for header in /usr/include/xcb/*.h; do
  [[ -e $pf/usr/include/xcb/${header##*/} ]] || ln -s "$header" "$pf/usr/include/xcb/"
done

dpkg-source -x "hyprland_$ver.dsc" src >/dev/null
cp "$here/local-clip-sliding-workspace.patch" src/debian/patches/
echo local-clip-sliding-workspace.patch >> src/debian/patches/series
{
  printf 'hyprland (%s) trixie-backports; urgency=medium\n\n' "$local_ver"
  printf "  * Local build: clip windows of a sliding workspace to that workspace's\n"
  printf '    slot, so off-screen scrolling columns do not slide over the neighbouring\n'
  printf '    workspace (d/p/local-clip-sliding-workspace.patch).\n\n'
  printf ' -- Omarchy Debian port <omarchy@localhost>  %s\n\n' "$(date -R)"
  cat src/debian/changelog
} > src/debian/changelog.new
mv src/debian/changelog.new src/debian/changelog

(cd src && env PATH="$pf/usr/bin:$PATH" PKG_CONFIG_PATH="$lib/pkgconfig:$pf/usr/share/pkgconfig" \
  CMAKE_PREFIX_PATH="$pf/usr" LIBRARY_PATH="$lib" CPATH="$pf/usr/include:$pf/usr/include/aarch64-linux-gnu" \
  DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -us -uc -d >"$work/build.log" 2>&1) \
  || { echo "build failed, see $work/build.log" >&2; exit 1; }

cp "hyprland_${local_ver}_arm64.deb" "$out/"
rm -rf "$work"
echo "Built: $out/hyprland_${local_ver}_arm64.deb"
