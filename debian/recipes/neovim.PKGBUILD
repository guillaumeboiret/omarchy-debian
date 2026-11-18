# Debian override: Debian's Neovim 0.10 is too old for Omarchy's LazyVim setup → official arm64 build
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=neovim
pkgver=$(_latest neovim/neovim); pkgrel=1
source_aarch64=("nvim-$pkgver.tar.gz::https://github.com/neovim/neovim/releases/download/v$pkgver/nvim-linux-arm64.tar.gz")
package() { mkdir -p "$pkgdir/usr"; cp -a "$srcdir/nvim-linux-arm64/." "$pkgdir/usr/"; }
