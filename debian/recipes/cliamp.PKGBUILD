# Debian override: upstream recipe needs Go 1.26 (Debian has 1.24) → official arm64 binary
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=cliamp
pkgver=$(_latest bjarneo/cliamp); pkgrel=1
source=("cliamp-src-$pkgver.tar.gz::https://github.com/bjarneo/cliamp/archive/refs/tags/v$pkgver.tar.gz")
source_aarch64=("cliamp-linux-arm64-$pkgver::https://github.com/bjarneo/cliamp/releases/download/v$pkgver/cliamp-linux-arm64")
noextract=("cliamp-linux-arm64-$pkgver")
package() {
  install -Dm755 "$srcdir/cliamp-linux-arm64-$pkgver" "$pkgdir/usr/bin/cliamp"
  install -Dm644 "$srcdir/cliamp-$pkgver/cliamp.desktop" "$pkgdir/usr/share/applications/cliamp.desktop" 2>/dev/null || true
  install -Dm644 "$srcdir/cliamp-$pkgver/Cliamp.png" "$pkgdir/usr/share/icons/hicolor/512x512/apps/cliamp.png" 2>/dev/null || true
}
