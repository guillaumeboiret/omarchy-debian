# Arch's post_install hook creates /usr/bin/voxtype → the CPU build (Apple Silicon has no CUDA/ROCm).
# The builder doesn't run .install hooks, so ship that link from package().
eval "$(declare -f package | sed '1s/^package/_voxtype_package/')"
package() {
  _voxtype_package
  mkdir -p "$pkgdir/usr/bin"
  ln -sf ../lib/voxtype/voxtype-cpu "$pkgdir/usr/bin/voxtype"
}
