import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Voxtype's own panel. It stands in for Voxtype's tray item (TrayModel.js),
// whose generic menu looked nothing like the other bar panels. The dictation
// state comes from that tray item's tooltip, which Voxtype updates as it goes,
// so nothing polls; the model and meeting details are read once per opening.
Panel {
  id: root
  moduleName: "omarchy.voxtype"
  ipcTarget: "omarchy.voxtype"
  manageIpc: false

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The tray item Voxtype publishes, or null while its daemon is not running.
  readonly property var trayItem: {
    var items = SystemTray.items ? SystemTray.items.values : []
    for (var i = 0; i < items.length; i++)
      if (items[i] && items[i].id === "voxtype") return items[i]
    return null
  }
  readonly property bool running: trayItem !== null
  readonly property string trayTitle: trayItem ? String(trayItem.tooltipTitle || "") : ""
  // "idle", "recording", "transcribing" or "stopped".
  readonly property string voxState: !running ? "stopped"
    : (trayTitle.indexOf("Recording") !== -1 ? "recording"
      : (trayTitle.indexOf("Transcribing") !== -1 ? "transcribing" : "idle"))
  readonly property bool recording: voxState === "recording"
  readonly property bool transcribing: voxState === "transcribing"
  readonly property bool busy: recording || transcribing

  // Read from `voxtype status --extended` and `voxtype config get`.
  property string model: ""
  property string backend: ""
  property string device: ""
  property bool meetingsEnabled: false
  property bool meetingActive: false
  property string meetingStatus: "idle"
  property bool meetingsBusy: false
  property string actionError: ""

  // Keyboard cursor over the action rows, in display order.
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var actions: {
    var list = []
    if (running) list.push("record")
    if (running && busy) list.push("cancel")
    if (running && meetingsEnabled) list.push("meeting")
    list.push("meetings")
    list.push("settings")
    return list
  }
  readonly property string cursorAction: cursorActive && cursorIndex < actions.length ? actions[cursorIndex] : ""

  readonly property string barGlyph: !running ? "󰍭" : (recording ? "󰑊" : (transcribing ? "󰔟" : "󰍬"))
  readonly property string heroGlyph: !running ? "󰍭" : (recording ? "󰑊" : (transcribing ? "󰔟" : "󰍬"))
  readonly property string stateText: {
    if (!running) return Commons.I18n.t("voxtype.stopped")
    if (recording) return Commons.I18n.t("voxtype.listening")
    if (transcribing) return Commons.I18n.t("voxtype.transcribing")
    if (meetingActive) return Commons.I18n.t("voxtype.meetingInProgress")
    return Commons.I18n.t("voxtype.ready")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function moveCursor(dy) {
    if (!cursorActive) { cursorActive = true; cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(actions.length - 1, cursorIndex + dy))
  }

  function setCursor(name) {
    var index = actions.indexOf(name)
    if (index < 0) return
    cursorActive = true
    cursorIndex = index
  }

  function trigger(name) {
    actionError = ""
    if (name === "record") run(["voxtype", "record", recording ? "stop" : "start"])
    else if (name === "cancel") run(["voxtype", "record", "cancel"])
    else if (name === "meeting") {
      run(["voxtype", "meeting", meetingActive ? "stop" : "start"])
      meetingActive = !meetingActive
      refreshLater.restart()
    } else if (name === "meetings") toggleMeetings()
    else if (name === "settings") {
      close()
      run(["omarchy-voxtype-config"])
    }
  }

  // Meetings are a config switch the daemon reads at start, so flipping it
  // restarts the voxtype service, as Voxtype's own tray item does.
  function toggleMeetings() {
    if (meetingsBusy) return
    meetingsBusy = true
    meetingsEnabled = !meetingsEnabled
    meetingsProc.command = ["bash", "-c",
      "voxtype config set meeting.enabled " + (meetingsEnabled ? "true" : "false")
      + " && systemctl --user restart voxtype"]
    meetingsProc.running = true
  }

  function run(command) {
    Quickshell.execDetached(command)
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!meetingConfigProc.running) meetingConfigProc.running = true
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    actionError = ""
    refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }
  onVoxStateChanged: if (opened) refreshLater.restart()
  onActionsChanged: if (cursorIndex >= actions.length) cursorIndex = Math.max(0, actions.length - 1)

  Timer {
    id: refreshLater
    interval: 600
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["voxtype", "status", "--format", "json", "--extended"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var s = JSON.parse(text)
          root.model = String(s.model || "")
          root.backend = String(s.backend || "")
          root.device = String(s.device || "")
          root.meetingActive = s.meeting_active === true
          root.meetingStatus = String(s.meeting_status || "idle")
        } catch (e) {}
      }
    }
  }

  Process {
    id: meetingConfigProc
    command: ["voxtype", "config", "get", "meeting.enabled"]
    stdout: StdioCollector {
      onStreamFinished: if (!root.meetingsBusy) root.meetingsEnabled = text.trim() === "true"
    }
  }

  Process {
    id: meetingsProc
    stderr: StdioCollector { id: meetingsErr }
    onExited: function(code) {
      root.meetingsBusy = false
      if (code !== 0) {
        root.meetingsEnabled = !root.meetingsEnabled
        root.actionError = meetingsErr.text.trim() || Commons.I18n.t("voxtype.meetingsFailed")
      }
      refreshLater.restart()
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return root.voxState }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    active: root.busy
    tooltipText: root.trayTitle !== "" ? root.trayTitle : Commons.I18n.t("voxtype.title")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.trigger("record")
      else if (b === Qt.RightButton && root.busy) root.trigger("cancel")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      property alias panelFlick: panelFlick
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.trigger(root.cursorAction)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.trigger("record")
        else if (t === "c" || t === "C") { if (root.busy) root.trigger("cancel") }
        else if (t === "m" || t === "M") { if (root.meetingsEnabled) root.trigger("meeting") }
        else if (t === "s" || t === "S") root.trigger("settings")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: Commons.I18n.t("voxtype.title")
            meta: root.stateText
            detail: root.meetingActive ? Commons.I18n.t("voxtype.meeting") : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.running ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.heroGlyph
                color: root.recording ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display

                SequentialAnimation on opacity {
                  running: root.recording
                  loops: Animation.Infinite
                  onRunningChanged: if (!running) parent.opacity = 1
                  NumberAnimation { to: 0.35; duration: Style.duration(700); easing.type: Easing.InOutSine }
                  NumberAnimation { to: 1.0; duration: Style.duration(700); easing.type: Easing.InOutSine }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.running || root.actionError !== ""
            width: parent.width
            text: root.actionError !== "" ? root.actionError : Commons.I18n.t("voxtype.notRunning")
            color: root.actionError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.running
            width: parent.width
            spacing: Style.space(6)

            ActionRow {
              name: "record"
              glyph: root.recording ? "󰓛" : "󰑊"
              glyphColor: root.recording ? root.urgent : root.foreground
              label: root.recording ? Commons.I18n.t("voxtype.stopRecording") : Commons.I18n.t("voxtype.startRecording")
              hint: root.recording ? Commons.I18n.t("voxtype.stopHint") : Commons.I18n.t("voxtype.startHint")
              enabled: !root.transcribing
            }

            ActionRow {
              name: "cancel"
              visible: root.busy
              glyph: "󰜺"
              label: Commons.I18n.t("voxtype.cancel")
              hint: Commons.I18n.t("voxtype.cancelHint")
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: Commons.I18n.t("voxtype.meetings")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleRow {
              name: "meetings"
              label: Commons.I18n.t("voxtype.meetingMode")
              hint: Commons.I18n.t("voxtype.meetingModeHint")
            }

            ActionRow {
              name: "meeting"
              visible: root.running && root.meetingsEnabled
              glyph: root.meetingActive ? "󰓛" : "󰐊"
              label: root.meetingActive ? Commons.I18n.t("voxtype.stopMeeting") : Commons.I18n.t("voxtype.startMeeting")
              hint: root.meetingActive ? root.meetingStatus : Commons.I18n.t("voxtype.startMeetingHint")
              enabled: !root.meetingsBusy
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            visible: root.running && root.model !== ""
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: Commons.I18n.t("voxtype.model"); value: root.model.replace(/\.gguf$/, "") }
            InfoPair { label: Commons.I18n.t("voxtype.backend"); value: root.backend }
            InfoPair { label: Commons.I18n.t("voxtype.input"); value: root.device }
          }

          ActionRow {
            name: "settings"
            width: parent.width
            glyph: "󰒓"
            label: Commons.I18n.t("voxtype.settings")
            hint: Commons.I18n.t("voxtype.settingsHint")
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: row
    property string name: ""
    property string glyph: ""
    property color glyphColor: root.foreground
    property string label: ""
    property string hint: ""

    width: parent ? parent.width : 0
    hasCursor: root.cursorAction === name
    foreground: root.foreground
    opacity: enabled ? 1 : 0.5
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.enabled
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(row.name)
      onClicked: root.trigger(row.name)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: row.glyph
        color: row.glyphColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.font.icon * 1.4
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: row.hint !== ""
          text: row.hint
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component ToggleRow: CursorSurface {
    id: toggleRow
    property string name: ""
    property string label: ""
    property string hint: ""

    width: parent ? parent.width : 0
    hasCursor: root.cursorAction === name
    foreground: root.foreground
    implicitHeight: toggleContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(toggleRow.name)
      onClicked: root.trigger(toggleRow.name)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "󰤙"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.font.icon * 1.4
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        id: toggleContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: toggleRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: toggleRow.hint
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      ToggleSwitch {
        checked: root.meetingsEnabled
        busy: root.meetingsBusy
        cursorRing: false
        foreground: root.foreground
        onHovered: function(on) { if (on) root.setCursor(toggleRow.name) }
        onToggled: root.trigger(toggleRow.name)
      }
    }
  }

  component InfoPair: RowLayout {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    visible: value !== ""
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }
  }
}
