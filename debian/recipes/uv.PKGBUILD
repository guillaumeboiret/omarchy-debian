# Debian extra: Omarchy ships uv (Python tooling); not packaged by Debian 13 → official arm64 release
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=uv
pkgver=$(_latest astral-sh/uv); pkgrel=1
source_aarch64=("https://github.com/astral-sh/uv/releases/download/$pkgver/uv-aarch64-unknown-linux-gnu.tar.gz")
package() {
  install -Dm755 "$srcdir/uv-aarch64-unknown-linux-gnu/uv" "$pkgdir/usr/bin/uv"
  install -Dm755 "$srcdir/uv-aarch64-unknown-linux-gnu/uvx" "$pkgdir/usr/bin/uvx"
}
