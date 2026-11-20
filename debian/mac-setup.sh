#!/bin/bash
# Omarchy Debian port: the root-only pieces Omarchy installs on an Apple Silicon Mac.
#   sudo ~/.local/share/omarchy/debian/mac-setup.sh
#
#  1. apt: x86 emulation for containers (qemu-user-binfmt) and fcitx5 CJK input methods
#  2. Widevine DRM for Firefox and Chromium (library built from Omarchy's widevine recipe
#     into ~/.cache/omarchy-debian/widevine)
#  3. The useful part of Omarchy's omarchy-mac add-on (source in ~/.cache/omarchy-debian/omarchy-mac):
#     platform root (notch cutouts, key names, display + audio hints), notch shown (apple_dcp),
#     battery charge limit, Asahi audio tweaks + mic mapper + audio watchdog, Wi-Fi resume fix,
#     moon key no longer suspends.
#     Left out: Touch ID, the iwd Wi-Fi backend, Arch keyrings/pacman hooks, SDDM/boot bits.
set -euo pipefail
(( EUID == 0 )) || { echo "Run with sudo" >&2; exit 1; }
user=${SUDO_USER:?run via sudo from your account}
home=$(getent passwd "$user" | cut -d: -f6)
cache=$home/.cache/omarchy-debian
mac=$cache/omarchy-mac
wv=$cache/widevine
hw='/usr/share/omarchy/bin/omarchy-hw-apple-silicon'

echo "==> 1/3 Packages"
apt-get install -y qemu-user-binfmt fcitx5-mozc fcitx5-chinese-addons fcitx5-hangul fcitx5-chewing fcitx5-table-extra

echo "==> 2/3 Widevine"
cdm=/opt/WidevineCdm/chromium
ver=4.10.2891.0; major=4; minor=10
install -Dm755 "$wv/libwidevinecdm.so" "$cdm/_platform_specific/linux_arm64/libwidevinecdm.so"
install -Dm644 /dev/null "$cdm/_platform_specific/linux_x64/libwidevinecdm.so"   # Chromium wants both dirs
cat > "$cdm/manifest.json" <<JSON
{
   "name": "WidevineCdm",
   "description": "Widevine Content Decryption Module",
   "version": "$ver",
   "x-cdm-codecs": "vp8,vp9.0,avc1,av01",
   "x-cdm-host-versions": "$minor",
   "x-cdm-interface-versions": "$minor",
   "x-cdm-module-versions": "$major",
   "x-cdm-persistent-license-support": true
}
JSON
install -Dm644 "$wv/LICENSE.widevine" "$cdm/LICENSE"
ln -sfn "$cdm" /usr/lib/chromium/WidevineCdm
gmp=/opt/WidevineCdm/firefox/gmp-widevinecdm/system-installed
install -d "$gmp"
ln -sfn ../../../chromium/manifest.json "$gmp/manifest.json"
ln -sfn ../../../chromium/_platform_specific/linux_arm64/libwidevinecdm.so "$gmp/libwidevinecdm.so"
install -d /usr/lib/firefox/browser/defaults/preferences   # Mozilla's .deb doesn't ship this dir
cat > /usr/lib/firefox/browser/defaults/preferences/widevine.js <<JS
// Omarchy Debian port: load the system Widevine CDM (MOZ_GMP_PATH points at $gmp)
pref("media.gmp-widevinecdm.version", "$ver");
pref("media.gmp-widevinecdm.visible", true);
pref("media.gmp-widevinecdm.enabled", true);
pref("media.gmp-widevinecdm.autoupdate", false);
pref("media.eme.enabled", true);
pref("media.eme.encrypted-media-encryption-scheme.enabled", true);
JS
printf '%s\n' "MOZ_GMP_PATH=\"\$MOZ_GMP_PATH\${MOZ_GMP_PATH:+:}$gmp\"" 'export MOZ_GMP_PATH' > /etc/profile.d/firefox_widevine.sh

echo "==> 3/3 Omarchy Mac add-on"
# Platform root Omarchy reads (skip keyrings + fingerprint-readers: Arch repo / Touch ID only)
for f in audio.json display-cutouts.json displays.conf key-names; do
  install -Dm644 "$mac/share/omarchy-platform/$f" "/usr/share/omarchy-platform/$f"
done
# Commands, with the Apple check pointed at Omarchy's copy
install -d /usr/lib/omarchy-mac
for f in omarchy-battery-charge-limit omarchy-audio-watchdog omarchy-audio-asahi-mic-map omarchy-wifi-resume-fix; do
  install -Dm755 "$mac/bin/$f" "/usr/local/bin/$f"
done
printf '#!/bin/bash -p\nexec %s "$@"\n' "${hw%apple-silicon}aarch64-apple" > /usr/local/bin/omarchy-hw-apple-silicon
chmod 755 /usr/local/bin/omarchy-hw-apple-silicon
for f in battery-charge-limit-restore wifi-supported; do
  install -Dm755 "$mac/lib/$f" "/usr/lib/omarchy-mac/$f"
done
sed -i 's#^\(\s*\)omarchy-hw-apple-silicon#\1/usr/local/bin/omarchy-hw-apple-silicon#' /usr/lib/omarchy-mac/*
# Audio: macOS-style device names, headset mic not preferred, no speaker pop, stereo mic mapper
install -Dm644 "$mac/share/pipewire/pipewire.conf.d/asahi-device-names.conf" /usr/share/pipewire/pipewire.conf.d/asahi-device-names.conf
install -Dm644 -t /usr/share/wireplumber/wireplumber.conf.d "$mac"/share/wireplumber/wireplumber.conf.d/*.conf
for u in omarchy-audio-watchdog omarchy-asahi-mic; do
  sed -e 's#/usr/bin/#/usr/local/bin/#g' "$mac/vendor/systemd/user/$u.service" > "/etc/systemd/user/$u.service"
done
# Battery charge limit survives reboots
install -Dm644 "$mac/vendor/udev/rules.d/94-omarchy-mac-battery-charge-limit.rules" /etc/udev/rules.d/94-omarchy-mac-battery-charge-limit.rules
udevadm control --reload
# Wi-Fi: reload brcmfmac when it comes back wedged after sleep
sed 's#/usr/bin/#/usr/local/bin/#g' "$mac/vendor/systemd/system/omarchy-wifi-resume-fix.service" > /etc/systemd/system/omarchy-wifi-resume-fix.service
# The moon key is Do Not Disturb, not suspend
install -Dm644 "$mac/vendor/systemd/logind.conf.d/20-omarchy-mac-sleep-key.conf" /etc/systemd/logind.conf.d/20-omarchy-mac-sleep-key.conf
systemctl daemon-reload
systemctl enable omarchy-wifi-resume-fix.service
# Show the notch area (full panel height); the bar uses display-cutouts.json to dodge it
echo 'options apple_dcp show_notch=1' > /etc/modprobe.d/asahi-notch.conf
update-initramfs -u

echo
echo "Done. Reboot for the notch, Widevine in Firefox and the sleep key; then run as yourself:"
echo "  systemctl --user enable --now omarchy-asahi-mic omarchy-audio-watchdog"
echo "  omarchy-battery-charge-limit 80     # optional"
