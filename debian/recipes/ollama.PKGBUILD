# Debian extra: Ollama (Arch packages it, Debian 13 doesn't) → official arm64 release, CPU/Vulkan
# runners only: the CUDA/JetPack libraries are for NVIDIA hardware and are most of the 1.6 GB archive.
source "${BASH_SOURCE[0]%/*}/_latest.sh"
pkgname=ollama
pkgver=$(_latest ollama/ollama); pkgrel=1
source_aarch64=("ollama-$pkgver.tar.zst::https://github.com/ollama/ollama/releases/download/v$pkgver/ollama-linux-arm64.tar.zst")
package() {
  install -Dm755 "$srcdir/bin/ollama" "$pkgdir/usr/bin/ollama"
  mkdir -p "$pkgdir/usr/lib/ollama"
  (cd "$srcdir/lib/ollama" && find . -mindepth 1 -maxdepth 1 ! -iname '*cuda*' ! -iname '*jetpack*' ! -iname '*rocm*' -exec cp -a {} "$pkgdir/usr/lib/ollama/" \;)
}
