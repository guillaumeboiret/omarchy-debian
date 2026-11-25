#!/bin/bash
# Debian port of Omarchy — boot and shutdown logging, to diagnose boots that hang.
# Run with sudo (or pkexec). Idempotent. Also called from system-setup.sh (step 31).
# Nothing here changes what the boot looks like: the extra messages go to the journal only.
# Read them with `omarchy-boot-report` (no root needed once your account is in systemd-journal).
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "run with sudo"; exit 1; }
# The user this machine is set up for (sudo or pkexec caller) and the port checkout this script lives in.
TARGET_USER=${SUDO_USER:-}
[[ -z $TARGET_USER && -n ${PKEXEC_UID:-} ]] && TARGET_USER=$(id -nu "$PKEXEC_UID")
[[ -n $TARGET_USER ]] || TARGET_USER=$(logname 2>/dev/null || true)
[[ -n $TARGET_USER && $TARGET_USER != "root" ]] || { echo "run with sudo from your own account"; exit 1; }
OM=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# a. Read the system journal (journalctl -b -1, -k, …) without root. adm is not needed: it only
#    adds /var/log text files, and Debian 13 logs everything to the journal.
gpasswd -a "$TARGET_USER" systemd-journal >/dev/null

# b. journald: flush to disk every 15 s instead of every 5 min, so a hang ended by holding the power
#    button keeps its last messages; kernel messages and every level up to debug are kept (journald's
#    defaults, written out so they stay that way). Capped at 1 GiB: / has little free space.
install -d /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-omarchy-boot-logging.conf <<'EOF'
[Journal]
Storage=persistent
SyncIntervalSec=15s
ReadKMsg=yes
MaxLevelStore=debug
SystemMaxUse=1G
EOF
systemctl restart systemd-journald

# c. Kernel: report a task stuck in a driver after 20 s instead of 120 s, with its stack, so a hang
#    (e.g. the HDMI display controller stalling at boot) is explained before the power button is held.
#    At most 10 reports per boot (kernel default). log_buf_len=4M: the kernel log keeps the whole boot
#    (128 KiB by default), for journald at start and the shutdown hook at the end.
cat > /etc/sysctl.d/60-omarchy-boot-logging.conf <<'EOF'
kernel.hung_task_timeout_secs = 20
EOF
sysctl -q --load=/etc/sysctl.d/60-omarchy-boot-logging.conf
if ! grep -q 'log_buf_len=' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 log_buf_len=4M"/' /etc/default/grub
  update-grub
fi

# d. systemd (PID 1) logs at debug level during boot: which job waits for which device or unit.
#    Debug messages go to the journal only (below the console log level). 3 min after boot the timer
#    sets it back to info; a boot that hangs keeps debugging. Set here rather than with
#    systemd.log_level= on the kernel command line, which every systemd daemon (logind, user
#    managers…) would also pick up for the whole session.
install -d /etc/systemd/system.conf.d
printf '[Manager]\nLogLevel=debug\n' > /etc/systemd/system.conf.d/60-omarchy-boot-debug.conf
cat > /etc/systemd/system/omarchy-boot-log-level.service <<'EOF'
[Unit]
Description=Omarchy: systemd back to info logging once the boot is over

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl log-level info
EOF
cat > /etc/systemd/system/omarchy-boot-log-level.timer <<'EOF'
[Unit]
Description=Omarchy: systemd back to info logging 3 min after boot

[Timer]
OnBootSec=3min
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable omarchy-boot-log-level.timer
systemctl start omarchy-boot-log-level.timer   # daemon-reload just applied LogLevel=debug; past 3 min this resets it at once

# e. Shutdown hook: saves the kernel log tail at the very end of every shutdown/reboot (after journald
#    has stopped) to /var/log/omarchy-boot/shutdown-<date>.log, last 10 kept, readable by the
#    systemd-journal group. A root-owned copy, never a link into the user-writable checkout.
install -d -m 0755 /usr/lib/systemd/system-shutdown
install -o root -g root -m 0755 "$OM/debian/system-shutdown/omarchy-shutdown-log" /usr/lib/systemd/system-shutdown/
install -d -o root -g systemd-journal -m 2750 /var/log/omarchy-boot

echo "Boot logging installed. Log out and back in (or reboot) for journal access without root."
