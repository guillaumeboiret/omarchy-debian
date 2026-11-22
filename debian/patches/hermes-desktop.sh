# Debian has no /usr/bin/python (only python3) unless python-is-python3 is installed.
# (Its /opt/hermes-desktop app is moved to ~/.local/lib by omarchy-debian's relocate().)
f=hermes-desktop.sh
expect "$f" 'python=/usr/bin/python$'
sed -i 's#/usr/bin/python\b#/usr/bin/python3#g' "$f"
