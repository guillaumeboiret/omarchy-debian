# libjpeg-turbo 2.1 (Debian 13) lacks the TurboJPEG 3 API; use a small mapping header.
f=$(echo monologue-*/src/writer.cpp)
expect "$f" '#include <turbojpeg.h>'
cp "$DEB/patches/monologue-tj3compat.h" "$(dirname "$f")/tj3compat.h"
sed -i 's|#include <turbojpeg.h>|#include "tj3compat.h"|' "$f"
