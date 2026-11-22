# The recipe installs the Electron app under /opt, which omarchy-debian doesn't relocate (it only moves
# usr/ into ~/.local). Move it to usr/lib/hermes-desktop so it lands in ~/.local/lib/hermes-desktop, and
# relocate() then rewrites the launcher's /usr/lib/hermes-desktop paths to match.
# Debian has no /usr/bin/python (only python3) unless python-is-python3 is installed.
f=hermes-desktop.sh
expect "$f" 'native=/opt/hermes-desktop/Hermes'
expect "$f" 'python=/usr/bin/python$'
sed -i -e 's#/opt/hermes-desktop/#/usr/lib/hermes-desktop/#g' -e 's#/usr/bin/python\b#/usr/bin/python3#g' "$f"

eval "$(declare -f package | sed '1s/^package/_upstream_package/')"
package() {
  _upstream_package
  mkdir -p "$pkgdir/usr/lib"
  mv "$pkgdir/opt/hermes-desktop" "$pkgdir/usr/lib/hermes-desktop"
  rmdir "$pkgdir/opt"
}
