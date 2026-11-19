# Debian extra: Omarchy ships lazydocker (Docker TUI, Super+Shift+D); not packaged by Debian → official arm64 release
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=lazydocker
pkgver=$(_latest jesseduffield/lazydocker); pkgrel=1
source_aarch64=("https://github.com/jesseduffield/lazydocker/releases/download/v$pkgver/lazydocker_${pkgver}_Linux_arm64.tar.gz")
package() { install -Dm755 "$srcdir/lazydocker" "$pkgdir/usr/bin/lazydocker"; }
