# The aarch64 build extracts app.asar with `asar`, which Debian doesn't package (Arch's asar is
# @electron/asar). Run it through npx; 3.x still supports Debian 13's Node 20.
expect "$startdir/PKGBUILD" 'asar extract'
asar() { npx --yes @electron/asar@3 "$@"; }
