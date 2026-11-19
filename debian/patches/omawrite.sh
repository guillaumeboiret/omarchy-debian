# Qt 6.8: there is no separate GuiPrivate CMake component; Qt6::GuiPrivate comes with Gui.
f=$(echo omawrite-*/CMakeLists.txt)
expect "$f" 'Test GuiPrivate)'
sed -i '/find_package(Qt6/,/)/ s/ GuiPrivate//' "$f"
