# Debian extra: Bitwarden CLI (Arch packages it, Debian 13 doesn't) → Bitwarden's official arm64
# build. Its repo releases every Bitwarden client, so take the newest cli-v* tag rather than "latest".
pkgname=bitwarden-cli
pkgver=$(curl -fsSL "https://api.github.com/repos/bitwarden/clients/releases?per_page=50" |
  sed -n 's/.*"tag_name": *"cli-v\([^"]*\)".*/\1/p' | head -1); pkgrel=1
source_aarch64=("https://github.com/bitwarden/clients/releases/download/cli-v$pkgver/bw-oss-linux-arm64-$pkgver.zip")
package() { install -Dm755 "$srcdir/bw" "$pkgdir/usr/bin/bw"; }
