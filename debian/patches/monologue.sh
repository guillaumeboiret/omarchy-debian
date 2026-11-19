# libjpeg-turbo 2.1 (Debian 13) lacks the TurboJPEG 3 API; use a small mapping header.
f=$(echo monologue-*/src/writer.cpp)
expect "$f" '#include <turbojpeg.h>'
cp "$DEB/patches/monologue-tj3compat.h" "$(dirname "$f")/tj3compat.h"
sed -i 's|#include <turbojpeg.h>|#include "tj3compat.h"|' "$f"
# Qt 6.8: VideoOutput has no mirrored property (6.9+); flip the preview with a transform.
q=$(echo monologue-*/src/Main.qml)
expect "$q" 'mirrored: backend.mirror }'
sed -i 's/mirrored: backend.mirror }/transform: Scale { origin.x: width \/ 2; xScale: backend.mirror ? -1 : 1 } }/' "$q"
# Qt 6.8: VideoOutput has no endOfStreamPolicy (6.9+); a finished clip shows black instead of its last frame.
expect "$q" 'endOfStreamPolicy: VideoOutput.KeepLastFrame; '
sed -i 's/endOfStreamPolicy: VideoOutput.KeepLastFrame; //' "$q"
