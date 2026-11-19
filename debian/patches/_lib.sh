# Helpers for per-app Debian patches. Patches are sourced in $srcdir after the sources are
# fetched and the PKGBUILD is loaded, so they may also redefine build()/package().
# expect FILE PATTERN — fail the build if a patch no longer applies (upstream changed the code).
expect() { grep -q -- "$2" "$1" || { echo "Debian patch: '$2' not found in $1" >&2; return 1; }; }
