# Qt 6.8 works (upstream gates its 6.9-only bits); build only the Qt6 plugin.
expect "$_archive/CMakeLists.txt" 'QT6_MIN_VERSION 6.9'
sed -i 's/QT6_MIN_VERSION 6.9/QT6_MIN_VERSION 6.8/' "$_archive/CMakeLists.txt"
build() {
  cmake -B build-qt6 -S "$_archive" -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr \
    -D "CMAKE_INSTALL_RPATH=\$ORIGIN/../../../aarch64-linux-gnu;\$ORIGIN" -D CMAKE_REQUIRE_FIND_PACKAGE_Qt6QuickControls2=ON \
    -D BUILD_QT5=OFF -D QT6_PLUGINDIR=lib/qt6/plugins
  cmake --build build-qt6
}
# Debian 13 ships KDE Frameworks 6.13; qtengine only uses long-stable KF6 APIs.
sed -i 's/set(KF6_MIN_VERSION "6.20.0")/set(KF6_MIN_VERSION "6.13.0")/' "$_archive/CMakeLists.txt"
# Qt 6.8 has no lowercase qjsonparseerror.h header; the class lives in qjsondocument.h.
grep -rl '#include <qjsonparseerror.h>' "$_archive/src" | xargs -r sed -i 's/#include <qjsonparseerror.h>/#include <qjsondocument.h>/'
