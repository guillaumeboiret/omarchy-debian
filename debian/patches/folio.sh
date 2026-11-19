# Qt 6.8: QDir::mkpath(path, permissions) is 6.9+; create, then set the permissions.
f=$(echo folio-*/src/fileops.cpp)
expect "$f" 'mkpath(trash + "/files", owner)'
perl -pi -e 's/QDir\(\)\.mkpath\(([^,()]+), owner\)/(QDir().mkpath($1) \&\& QFile::setPermissions($1, owner))/g' "$f"
# The test suite uses Qt 6.9+ APIs; it is not installed, so leave it out of the default build.
f=$(echo folio-*/CMakeLists.txt)
expect "$f" 'add_executable(folio_tests '
sed -i 's/add_executable(folio_tests /add_executable(folio_tests EXCLUDE_FROM_ALL /' "$f"
# Qt 6.8: Flickable has no acceptedButtons (6.9+); without it a drag on empty space scrolls.
for q in folio-*/src/FolderGrid.qml folio-*/src/FileListView.qml; do
  expect "$q" '^    acceptedButtons: Qt.NoButton'
  sed -i '/^    acceptedButtons: Qt.NoButton/d' "$q"
done
