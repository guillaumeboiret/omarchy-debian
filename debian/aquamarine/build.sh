#!/bin/bash
# Rebuild Debian's libaquamarine10 0.11.0 with primary-no-renderer-hotplug.patch.
#
# Why: on Apple Silicon the KMS device ("apple") has no render node, so
# aquamarine's initMgpu() always fails. At login that's tolerated, but after a
# hotplug (monitor off/on, sleep, cable) the reconnect is dropped and the HDMI
# monitor never comes back until re-login. Upstream only fixed it for evdi.
#
# Builds without sudo (build deps unpacked into a scratch prefix; hyprutils
# 0.11.1 built from source so the result links libhyprutils.so.10 like the
# stock package). Install the result with:
#   sudo apt install ~/.cache/omarchy-debian/aquamarine/libaquamarine10_*omarchy*_arm64.deb
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=${WORK:-$HOME/.cache/omarchy-debian/aquamarine/build}
out=$HOME/.cache/omarchy-debian/aquamarine
pool=https://deb.debian.org/debian/pool/main
ver=0.11.0-2~bpo13+1
pf=$work/prefix
lib=$pf/usr/lib/aarch64-linux-gnu

rm -rf "$work" && mkdir -p "$work" "$pf" "$out"
cd "$work"

for f in "aquamarine_$ver.dsc" "aquamarine_$ver.debian.tar.xz" aquamarine_0.11.0.orig.tar.gz; do
  curl -sfLO "$pool/a/aquamarine/$f"
done
curl -sfLO "$pool/h/hyprwayland-scanner/hyprwayland-scanner_0.4.6-1~bpo13+1_arm64.deb"
curl -sfLO "$pool/s/seatd/libseat-dev_0.9.1-1_arm64.deb"
for f in *.deb; do dpkg-deb -x "$f" "$pf"; done
sed -i "s|^prefix=.*|prefix=$pf/usr|" "$lib/pkgconfig/libseat.pc"
ln -sf /usr/lib/aarch64-linux-gnu/libseat.so.1 "$lib/libseat.so.1"

git clone -q --depth 1 --branch v0.11.1 https://github.com/hyprwm/hyprutils hu
cmake -S hu -B hu/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$pf/usr" \
  -DCMAKE_INSTALL_LIBDIR=lib/aarch64-linux-gnu -DBUILD_TESTING=OFF >/dev/null
cmake --build hu/build -j"$(nproc)" >/dev/null
cmake --install hu/build >/dev/null

dpkg-source -x "aquamarine_$ver.dsc" src >/dev/null
mkdir -p src/debian/patches
cp "$here/primary-no-renderer-hotplug.patch" src/debian/patches/
echo primary-no-renderer-hotplug.patch > src/debian/patches/series
{
  printf 'aquamarine (%somarchy1) trixie-backports; urgency=medium\n\n' "$ver"
  printf '  * Keep hotplugged outputs when the primary KMS device has no renderer\n'
  printf '    (Apple Silicon HDMI reconnect).\n\n'
  printf ' -- Omarchy Debian port <omarchy@localhost>  %s\n\n' "$(date -R)"
  cat src/debian/changelog
} > src/debian/changelog.new
mv src/debian/changelog.new src/debian/changelog

(cd src && PATH="$pf/usr/bin:$PATH" PKG_CONFIG_PATH="$lib/pkgconfig" LIBRARY_PATH="$lib" \
  DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -us -uc -d >"$work/build.log" 2>&1) \
  || { echo "build failed, see $work/build.log" >&2; exit 1; }

cp libaquamarine10_*omarchy1_arm64.deb "$out/"
rm -rf "$work"
echo "Built: $(ls "$out"/libaquamarine10_*omarchy1_arm64.deb)"
