# Debian extra: Symfony CLI (Arch packages it, Debian 13 doesn't) → official arm64 release
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=symfony-cli
pkgver=$(_latest symfony-cli/symfony-cli); pkgrel=1
source_aarch64=("symfony-cli-$pkgver.tar.gz::https://github.com/symfony-cli/symfony-cli/releases/download/v$pkgver/symfony-cli_linux_arm64.tar.gz")
package() { install -Dm755 "$srcdir/symfony" "$pkgdir/usr/bin/symfony"; }
