import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OverviewModel.js" as OverviewModel
import "../dock/DockModel.js" as DockModel

// Debian port: a macOS Mission Control style overview. Every window on a
// regular workspace, on every monitor, shows as a live thumbnail, grouped by
// app the way the dock names them, the app used last first. A click focuses
// the window, switching workspace and monitor as needed; Escape or a click on
// the dimmed background closes it unchanged. Arrows move, Enter focuses.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var dockConfig: shell && shell.shellConfig && shell.shellConfig.dock ? shell.shellConfig.dock : ({})
  readonly property var defaultDockConfig: shell && shell.defaultsConfig && shell.defaultsConfig.dock ? shell.defaultsConfig.dock : ({})

  property bool opened: false
  // True from opening until the closing fade has finished: the surface, the
  // thumbnails and their captures live this long, so nothing vanishes before
  // the overview has faded out.
  readonly property bool showing: opened || content.opacity > 0
  property int selectedIndex: 0
  // The layout as it stood when the overview opened, rebuilt when windows come
  // or go while it shows.
  property var arranged: ({ blocks: [], items: [], thumbHeight: 0, width: 0, height: 0 })

  // The background dims like the scratchpad and other special workspaces do:
  // black at Hyprland's decoration:dim_special, read at startup and on every
  // config reload.
  property real dimStrength: 0.6

  Process {
    id: dimProc
    command: ["hyprctl", "-j", "getoption", "decoration:dim_special"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var value = Number(JSON.parse(text).float)
          if (isFinite(value) && value >= 0 && value <= 1) root.dimStrength = value
        } catch (error) {}
      }
    }
  }

  Component.onCompleted: dimProc.running = true

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") dimProc.running = true
    }
  }

  readonly property int screenMargin: Style.space(48)
  readonly property int thumbGap: Style.space(18)
  readonly property int groupGap: Style.space(40)
  readonly property int iconSize: Math.round(22 * Style.fontScale)
  readonly property int headerHeight: iconSize + Style.spacing.lg * 2
  readonly property int titleHeight: Math.ceil(titleMetrics.height) + Style.spacing.md * 2
  readonly property int borderWidth: Math.max(2, Style.space(3))

  FontMetrics {
    id: titleMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  // The dock's window to app matching, so groups carry the dock's names and
  // icons: the desktop entry, a terminal entry that claims the window, then a
  // loose match on case or the last reverse-DNS part.
  readonly property var terminalEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0)
        out.push({ id: entry.id, execString: entry.execString, command: entry.command, runInTerminal: entry.runInTerminal })
    }
    return out
  }

  readonly property var looseEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) out.push({ id: values[i].id, startupClass: values[i].startupClass })
    return out
  }

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = DockModel.claimingEntryId(appId, root.terminalEntries)
    if (id) return DesktopEntries.byId(id)
    id = DockModel.looseEntryId(appId, root.looseEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  function iconSource(icon) {
    return root.appLibrary ? root.appLibrary.iconSource(icon) : Quickshell.iconPath(String(icon || "application-x-executable"), true)
  }

  function collectWindows() {
    var pinned = DockModel.pinnedIds(root.dockConfig, root.defaultDockConfig)
    var windows = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      var wayland = toplevel.wayland
      var ipc = toplevel.lastIpcObject || {}
      var appId = wayland && wayland.appId ? wayland.appId : String(ipc.class || "")
      if (!appId) continue
      var workspace = toplevel.workspace
      var entry = root.entryForAppId(appId)
      var key = entry ? DockModel.standInKey(entry.id, entry.categories, pinned) : appId
      var keyEntry = entry ? (DesktopEntries.byId(key) || entry) : null
      var size = Array.isArray(ipc.size) ? ipc.size : [0, 0]
      windows.push({
        address: String(toplevel.address || ""),
        appId: appId,
        key: key,
        name: keyEntry && keyEntry.name ? keyEntry.name : OverviewModel.fallbackName(appId),
        icon: keyEntry && keyEntry.icon ? keyEntry.icon : (OverviewModel.fallbackName(appId) !== appId ? "google-chrome" : appId),
        title: String(toplevel.title || ipc.title || ""),
        workspaceId: workspace ? workspace.id : -1,
        workspaceName: workspace ? String(workspace.name || workspace.id) : "",
        child: !!(wayland && wayland.parent),
        focusHistory: ipc.focusHistoryID !== undefined ? ipc.focusHistoryID : -1,
        width: size[0],
        height: size[1],
        toplevel: toplevel
      })
    }
    return windows
  }

  function rearrange() {
    if (!root.opened) return
    var groups = OverviewModel.groupWindows(root.collectWindows())
    // Laid out for the screen it opens on before the surface maps, so the
    // first frame already has every thumbnail in place.
    var screen = panel.targetScreen || panel.focusedScreen()
    var width = Math.max(1, (screen ? screen.width : 1200) - root.screenMargin * 2)
    var height = Math.max(1, (screen ? screen.height : 800) - root.screenMargin * 2)
    root.arranged = OverviewModel.layout(groups, width, height, {
      gap: root.thumbGap,
      groupGap: root.groupGap,
      headerHeight: root.headerHeight,
      titleHeight: root.titleHeight,
      minHeight: Style.space(60),
      maxHeight: Math.round(height * 0.45)
    })
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.arranged.items.length - 1))
  }

  // The window that had focus when the overview opened. Closing without
  // picking a window gives focus back to it: Hyprland otherwise refocuses by
  // its own rules once the overview lets go of the keyboard, and can land on
  // another window, such as one under a shown special workspace.
  property string returnAddress: ""

  function normalizedAddress(value) {
    var address = String(value || "")
    return address && address.indexOf("0x") !== 0 ? "0x" + address : address
  }

  Timer {
    id: restoreFocus
    interval: 80
    onTriggered: {
      var active = Hyprland.activeToplevel
      var current = active ? root.normalizedAddress(active.address) : ""
      if (!root.opened && root.returnAddress && current !== root.returnAddress)
        Util.execDetached("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:" + root.returnAddress + "\" })"))
    }
  }

  function open() {
    var active = Hyprland.activeToplevel
    root.returnAddress = active ? root.normalizedAddress(active.address) : ""
    // focusHistoryID and the window sizes come from Hyprland's client list,
    // which Quickshell only reads when asked.
    Hyprland.refreshToplevels()
    root.selectedIndex = 0
    root.opened = true
    root.rearrange()
    // Thumbnails show their capture, or the app icon if none came by now.
    captureGrace.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    restoreFocus.restart()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  Timer {
    id: captureGrace
    interval: 250
  }

  // Coalesce the bursts of change signals a refresh brings into one layout.
  Timer {
    id: rearrangeLater
    interval: 30
    onTriggered: root.rearrange()
  }

  Connections {
    target: Hyprland.toplevels
    enabled: root.opened
    function onValuesChanged() { rearrangeLater.restart() }
  }

  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "openwindow" || name === "closewindow" || name === "movewindow" || name === "movewindowv2") {
        Hyprland.refreshToplevels()
        rearrangeLater.restart()
      }
    }
  }

  // Focuses a window: Hyprland switches to its workspace and monitor, and a
  // floating one comes to the top.
  function activate(item) {
    if (!item || !item.window) return
    var address = String(item.window.address || "")
    root.returnAddress = ""
    root.close()
    if (!address) return
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var target = "window = \"address:" + address + "\""
    var steps = [
      "hl.dsp.focus({ " + target + " })",
      "hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })"
    ]
    Util.execDetached(steps.map(function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }).join(" && "))
  }

  function move(direction) {
    var items = root.arranged.items
    if (items.length === 0) return
    root.selectedIndex = OverviewModel.neighbor(items, root.selectedIndex, direction)
  }

  ShellIpc {
    target: "omarchy.overview"

    function toggle(): void { root.toggle() }
    function open(): void { if (!root.opened) root.open() }
    function close(): void { root.close() }
    // One line per app: its name and how many windows, the selected window
    // last, and whether the thumbnails capture live.
    function status(): string {
      var groups = root.arranged.blocks.map(function(block) {
        return { name: block.group.name, key: block.group.key, windows: block.items.length }
      })
      var live = 0
      for (var i = 0; i < thumbs.count; i++) {
        var thumb = thumbs.itemAt(i)
        if (thumb && thumb.captured) live++
      }
      var selected = root.arranged.items[root.selectedIndex]
      return JSON.stringify({
        opened: root.opened,
        thumbHeight: root.arranged.thumbHeight,
        groups: root.opened ? groups : [],
        captured: root.opened ? live : 0,
        windows: root.opened ? root.arranged.items.length : 0,
        selected: root.opened && selected ? selected.window.title : ""
      })
    }
  }

  OverlayWindow {
    id: panel
    shown: root.showing
    // Closing hands the keyboard back at once, while the overview fades out.
    shownKeyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-overview"

    // One fade in (the thumbnails also grow slightly), faster out (Hyprland's layer fade is off
    // for this surface). It starts once the surface has its final size and
    // scale, so the first visible frame is already laid out.
    Item {
      id: content
      anchors.fill: parent
      readonly property bool up: root.opened && panel.contentRevealed
      opacity: up ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(content.up ? 180 : 120); easing.type: Easing.OutCubic }
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dimStrength)
      }

      // A click on the background closes the overview without changing focus.
      MouseArea {
        anchors.fill: parent
        enabled: root.opened
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_LaunchA) root.close()
          else if (event.key === Qt.Key_Left) root.move("left")
          else if (event.key === Qt.Key_Right) root.move("right")
          else if (event.key === Qt.Key_Up) root.move("up")
          else if (event.key === Qt.Key_Down) root.move("down")
          else if (event.key === Qt.Key_Tab) root.move("right")
          else if (event.key === Qt.Key_Backtab) root.move("left")
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            root.activate(root.arranged.items[root.selectedIndex])
          else return
          event.accepted = true
        }
      }

      Flickable {
        id: stage
        anchors.fill: parent
        anchors.margins: root.screenMargin
        contentWidth: width
        contentHeight: root.arranged.height
        interactive: contentHeight > height
        clip: true
        // The thumbnails grow in slightly while the dim fades.
        scale: content.up ? 1 : 0.97
        Behavior on scale {
          NumberAnimation { duration: Style.duration(content.up ? 180 : 120); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }

        Text {
          anchors.centerIn: parent
          visible: root.opened && root.arranged.items.length === 0
          text: "No open windows"
          color: Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }

        // Group headers: the app's icon and name, as the dock shows it.
        Repeater {
          model: root.showing ? root.arranged.blocks : []

          delegate: Row {
            required property var modelData
            x: modelData.x + Math.max(0, (modelData.width - implicitWidth) / 2)
            y: modelData.y
            height: root.headerHeight
            spacing: Style.spacing.lg

            Image {
              anchors.verticalCenter: parent.verticalCenter
              width: root.iconSize
              height: root.iconSize
              sourceSize.width: root.iconSize * 2
              sourceSize.height: root.iconSize * 2
              source: root.iconSource(modelData.group.icon)
              asynchronous: true
              smooth: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.group.name + (modelData.items.length > 1 ? "  " + modelData.items.length : "")
              color: Commons.Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
            }
          }
        }

        Repeater {
          id: thumbs
          model: root.showing ? root.arranged.items : []

          delegate: Item {
            id: thumb
            required property var modelData
            required property int index
            readonly property bool selected: root.selectedIndex === index
            readonly property bool captured: view.hasContent

            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: root.arranged.thumbHeight + root.titleHeight

            Rectangle {
              id: frame
              width: parent.width
              height: root.arranged.thumbHeight
              radius: Style.cornerRadius
              color: Util.alpha(Commons.Color.menu.background, 0.92)
              border.width: thumb.selected ? root.borderWidth : 1
              border.color: thumb.selected ? Commons.Color.accent : Util.alpha(Commons.Color.menu.text, 0.15)
              scale: thumbMouse.pressed ? 0.98 : 1

              Behavior on scale { NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic } }

              ScreencopyView {
                id: view
                anchors.centerIn: parent
                captureSource: root.showing && thumb.modelData.window.toplevel ? thumb.modelData.window.toplevel.wayland : null
                live: true
                // The first frame fades in rather than popping over the frame.
                opacity: hasContent ? 1 : 0
                Behavior on opacity {
                  NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
                }
                paintCursor: false
                constraintSize: Qt.size(frame.width - root.borderWidth * 2, frame.height - root.borderWidth * 2)
                width: implicitWidth
                height: implicitHeight
              }

              // Without a capture (yet, or at all), the app's icon stands in.
              Image {
                anchors.centerIn: parent
                visible: !view.hasContent && !captureGrace.running
                width: Math.min(parent.width, parent.height) * 0.4
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: root.iconSource(thumb.modelData.window.icon)
                asynchronous: true
              }

              // The workspace the window lives on.
              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.spacing.md
                width: Math.max(height, wsLabel.implicitWidth + Style.spacing.md * 2)
                height: wsLabel.implicitHeight + Style.spacing.xs * 2
                radius: height / 2
                color: Util.alpha(Commons.Color.menu.background, 0.85)
                visible: thumb.modelData.window.workspaceName !== ""

                Text {
                  id: wsLabel
                  anchors.centerIn: parent
                  text: thumb.modelData.window.workspaceName
                  color: Commons.Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              anchors.top: frame.bottom
              anchors.topMargin: Style.spacing.md
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: thumb.modelData.window.title || thumb.modelData.window.name
              color: thumb.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: thumbMouse
              anchors.fill: frame
              hoverEnabled: true
              enabled: root.opened
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = thumb.index
              onClicked: root.activate(thumb.modelData)
            }
          }
        }
      }
    }
  }
}
