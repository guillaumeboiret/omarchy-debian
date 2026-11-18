# Debian override: upstream recipe needs Rust 1.96 + zig 0.16 (Debian has Rust 1.85) → official arm64 binary
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=herdr
pkgver=$(_latest herdrdev/herdr); pkgrel=1
source_aarch64=("herdr-$pkgver::https://github.com/herdrdev/herdr/releases/download/v$pkgver/herdr-linux-aarch64")
noextract=("herdr-$pkgver")
package() { install -Dm755 "$srcdir/herdr-$pkgver" "$pkgdir/usr/bin/herdr"; }
