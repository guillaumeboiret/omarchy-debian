#!/bin/bash
# Omarchy Debian port: move Mesa (Asahi GL + Honeykrisp Vulkan) from the Debian Asahi
# "bananas" snapshot (25.1.0~git20250425) to trixie-backports (26.x).
#   sudo ~/.local/share/omarchy/debian/mesa-backports.sh            upgrade
#   sudo ~/.local/share/omarchy/debian/mesa-backports.sh --rollback go back to bananas
#
# bananas is pinned at 1050 (above 1000, so apt even downgrades to it); the pin below
# gives backports' Mesa 1100 so it wins and stays on later upgrades.

set -euo pipefail

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 1
fi

pin=/etc/apt/preferences.d/mesa-backports.pref
packages=(libegl-mesa0 libegl1-mesa-dev libgbm-dev libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers)

if [[ ${1:-} == "--rollback" ]]; then
  rm -f "$pin"
  apt-get update -q
  apt-get install -y --allow-downgrades "${packages[@]/%//trixie-bananas}"
  echo "Back on the bananas Mesa. Log out and back in."
  exit 0
fi

cat >"$pin" <<'PIN'
# Mesa from trixie-backports beats the Asahi "bananas" snapshot (pinned 1050).
# Remove this file and run mesa-backports.sh --rollback to go back.
Package: /^(libegl-mesa0|libegl1-mesa-dev|libgbm1|libgbm-dev|libgl1-mesa-dri|libglx-mesa0|mesa-libgallium|mesa-va-drivers|mesa-vdpau-drivers|mesa-vulkan-drivers|mesa-opencl-icd|mesa-drm-shim)$/
Pin: release n=trixie-backports
Pin-Priority: 1100
PIN

apt-get update -q
apt-get install -y "${packages[@]}"

echo
dpkg-query -W -f='${Package} ${Version}\n' "${packages[@]}"
echo
echo "Done. Log out and back in (or reboot) so the desktop loads the new drivers."
