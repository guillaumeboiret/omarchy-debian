# Qt 6.8: QImage::flipped() is 6.9+, mirrored(horizontal, vertical) is the older spelling.
f=$(echo omasnap-*/src/stitch.cpp)
expect "$f" '\.flipped(Qt::'
sed -i 's/\.flipped(Qt::Vertical)/.mirrored(false, true)/g; s/\.flipped(Qt::Horizontal)/.mirrored(true, false)/g' "$f"
# layer-shell-qt 6.3 (Debian 13) lacks setActivateOnShow; exclusive keyboard focus still applies.
f=$(echo omasnap-*/src/main.cpp)
expect "$f" 'setActivateOnShow(true);'
sed -i '/setActivateOnShow(true);/d' "$f"
# layer-shell-qt 6.3 has no Window::setScreen; it places the layer on QWindow::screen() by default.
expect "$f" 'layerWindow->setScreen(targetScreen);'
sed -i 's/layerWindow->setScreen(targetScreen);/window->setScreen(targetScreen);/' "$f"
