# Qt 6.8: there is no separate GuiPrivate CMake component; Qt6::GuiPrivate comes with Gui.
f=$(echo omaview-*/CMakeLists.txt)
expect "$f" 'Gui GuiPrivate'
sed -i '/find_package(Qt6/,/)/ s/ GuiPrivate//' "$f"
# Qt 6.8 Multimedia has no pitch compensation (6.10+); playback speed changes will shift pitch.
f=$(echo omaview-*/src/backend.cpp)
expect "$f" 'pitchCompensationAvailability()'
perl -0pi -e 's/    if \(m_player->pitchCompensationAvailability\(\)[^\n]*\n[^\n]*setPitchCompensation\(true\);\n//' "$f"
! grep -q 'PitchCompensation' "$f"
