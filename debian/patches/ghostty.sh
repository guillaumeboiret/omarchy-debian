# Upstream splits Ghostty into ghostty + -shell-integration + -terminfo + -nautilus packages.
# The builder installs one package per app, so ghostty ships all four: without the terminfo
# (xterm-ghostty) and shell integration the terminal is half broken.
expect "$srcdir/$_archive/build.zig" 'ghostty'
declare -F package_ghostty-terminfo >/dev/null
package_ghostty() {
  cd "$srcdir/$_archive"
  cp -a build/* "$pkgdir/"
  install -Dm0644 LICENSE "$pkgdir/usr/share/licenses/ghostty/LICENSE"
  # Its desktop file, D-Bus and systemd units call a bare `ghostty`; systemd and D-Bus activation
  # don't search ~/.local/bin, so name /usr/bin (the builder relocates that to ~/.local/bin).
  sed -i -E 's#^(Exec|ExecStart)=ghostty #\1=/usr/bin/ghostty #' \
    "$pkgdir/usr/share/applications/com.mitchellh.ghostty.desktop" \
    "$pkgdir/usr/share/dbus-1/services/com.mitchellh.ghostty.service" \
    "$pkgdir"/usr/{lib,share}/systemd/user/app-com.mitchellh.ghostty.service 2>/dev/null || true
  grep -q '^ExecStart=/usr/bin/ghostty ' "$pkgdir"/usr/*/systemd/user/app-com.mitchellh.ghostty.service
}

# Ghostty 1.4 needs HarfBuzz ≥ 11 (HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES); Debian 13 has 10.2 →
# build its bundled HarfBuzz instead (the sources are already fetched by prepare's --fetch=all).
declare -f build | grep -q -- '--system "$srcdir/zig-pkg"'
eval "$(declare -f build | sed 's#--system "$srcdir/zig-pkg"#--system "$srcdir/zig-pkg" -fno-sys=harfbuzz#')"
