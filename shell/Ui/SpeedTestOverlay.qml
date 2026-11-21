import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Centered speed test overlay shared by the network and disk speed tests.
// Drawn like the rest of the shell: a flat themed card with the popup border
// on a theme scrim, monospace figures, and a segmented meter per reading
// (btop-style blocks rather than a skeuomorphic dial). Esc or the scrim close
// it; Enter runs again. Callers name the meters, the unit, and the scale.
PanelWindow {
  id: root
  // Right-to-left languages read this window mirrored.
  Binding { target: root.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: root.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  required property string fontFamily
  required property bool running
  required property string leftLabel
  required property string rightLabel
  property string unit: "Mbps"
  property string title: ""
  property string layerNamespace: "omarchy-speed-test"
  property string runAgainTooltip: Commons.I18n.t("speedtest.measureAgain")
  property real leftValue: 0
  property real rightValue: 0
  property bool leftLive: false
  property bool rightLive: false
  property string error: ""
  property bool open: false
  // Full-scale latch points for the dials, smallest first. The first stop is
  // the base scale a fresh run starts from.
  property var scaleStops: [100, 250, 500, 1000, 2500, 5000, 10000]
  property real fullScale: scaleStops[0]

  signal closeRequested()
  signal runAgainRequested()

  readonly property bool failed: error !== ""

  function resetScale() {
    fullScale = scaleStops[0]
  }

  function expandScale(value) {
    // Either reading ranges the entire cluster upward. Keeping this latch on
    // the overlay ensures both dials always describe the same scale.
    for (var i = 0; i < scaleStops.length; i++) {
      if (value <= scaleStops[i] * 0.92) {
        if (scaleStops[i] > fullScale) fullScale = scaleStops[i]
        return
      }
    }
    fullScale = scaleStops[scaleStops.length - 1]
  }

  onRunningChanged: if (running) resetScale()
  onScaleStopsChanged: resetScale()
  onLeftValueChanged: expandScale(leftValue)
  onRightValueChanged: expandScale(rightValue)

  Behavior on fullScale {
    NumberAnimation { duration: Style.duration(400); easing.type: Easing.OutCubic }
  }

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Util.alpha(Commons.Color.popups.text, 0.55)
  readonly property color faint: Util.alpha(Commons.Color.popups.text, 0.1)
  readonly property color accent: Commons.Color.accent

  visible: open
  // The window is instantiated hidden, so re-acquire focus after mapping and
  // fire the power-on sweep once the surface is actually on screen.
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (!root.open) return
      keyCatcher.forceActiveFocus()
      leftMeter.ignite()
      rightMeter.ignite()
    })
  }
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: root.layerNamespace
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.scrim

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.closeRequested()
    Keys.onReturnPressed: if (!root.running) root.runAgainRequested()
    Keys.onEnterPressed: if (!root.running) root.runAgainRequested()

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(keyCatcher.width - Style.space(32), Style.space(460))
      height: content.implicitHeight + contentTopInset + contentBottomInset
      color: Commons.Color.popups.background
      borderSpec: Border.flat(Commons.Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.space(20)
      radius: Style.cornerRadius

      // Swallow clicks so only the scrim outside the card dismisses.
      MouseArea { anchors.fill: parent; onClicked: {} }

      ColumnLayout {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(18)

        // Header: what is being measured, and the run state.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: root.title
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Text {
            textFormat: Text.PlainText
            text: root.failed ? "✕" : (root.running ? "●" : "✓")
            color: root.failed ? Commons.Color.urgent : (root.running ? root.accent : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall

            SequentialAnimation on opacity {
              running: root.running && root.open
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: 0.25; duration: Style.duration(600); easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: Style.duration(600); easing.type: Easing.InOutSine }
            }
          }
        }

        Meter {
          id: leftMeter
          Layout.fillWidth: true
          label: root.leftLabel
          value: root.leftValue
          live: root.leftLive
        }

        Meter {
          id: rightMeter
          Layout.fillWidth: true
          label: root.rightLabel
          value: root.rightValue
          live: root.rightLive
        }

        Text {
          textFormat: Text.PlainText
          visible: root.failed
          text: root.error
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }

        // Footer: key hints left, action right. The button fades rather than
        // unmounts while a run is in flight, so the card never shifts.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "esc  close" + (root.running ? "" : "   ⏎  " + Commons.I18n.t("speedtest.runAgain").toLowerCase())
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Button {
            text: Commons.I18n.t("speedtest.runAgain")
            tooltipText: root.runAgainTooltip
            bordered: true
            enabled: !root.running
            opacity: root.running ? 0 : 1
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(4)
            onClicked: root.runAgainRequested()

            Behavior on opacity {
              NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }
  }

  // One reading: a label/figure line over a row of square segments, filled
  // in the accent up to the reading against the shared full scale. All
  // writes funnel through `shown` so the power-on sweep and live readings
  // share one animation.
  component Meter: ColumnLayout {
    id: meter

    required property string label
    required property real value
    required property bool live

    readonly property int segments: 32
    readonly property bool engaged: live || value > 0
    property real shown: 0
    // The figure stays on the real reading while the sweep drives the bar.
    readonly property real reading: ignition.running ? value : shown
    readonly property real fraction: root.fullScale > 0 ? Math.max(0, Math.min(1, shown / root.fullScale)) : 0
    readonly property int lit: Math.round(fraction * segments)

    spacing: Style.space(8)
    opacity: engaged ? 1 : 0.45

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
    }

    // Live readings land once a second; glide between them rather than snap.
    Behavior on shown {
      enabled: !ignition.running
      NumberAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic }
    }

    onValueChanged: if (!ignition.running) shown = value

    function ignite() {
      ignition.restart()
    }

    SequentialAnimation {
      id: ignition
      NumberAnimation { target: meter; property: "shown"; to: root.fullScale; duration: Style.duration(450); easing.type: Easing.InOutCubic }
      NumberAnimation { target: meter; property: "shown"; to: 0; duration: Style.duration(550); easing.type: Easing.OutCubic }
      onFinished: meter.shown = meter.value
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: meter.label.toLowerCase()
        color: meter.live ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignBaseline
      }

      Text {
        textFormat: Text.PlainText
        // Written in the interface language's decimal separator and digits.
        text: Commons.I18n.formatNumber(meter.reading, meter.reading < 10 ? 1 : 0)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        Layout.alignment: Qt.AlignBaseline
      }

      Text {
        textFormat: Text.PlainText
        text: root.unit
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignBaseline
      }
    }

    Row {
      id: bar
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(10)
      spacing: Math.max(1, Style.space(2))

      Repeater {
        model: meter.segments

        Rectangle {
          required property int index
          width: (bar.width - bar.spacing * (meter.segments - 1)) / meter.segments
          height: bar.height
          color: index < meter.lit ? root.accent : root.faint
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true

      Text {
        textFormat: Text.PlainText
        text: "0"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
      }

      Text {
        textFormat: Text.PlainText
        // The scale glides between stops; label the stop it is heading to.
        text: Commons.I18n.formatNumber(root.scaleStops.find(function(s) { return s >= root.fullScale - 0.5 }) || root.fullScale, 0)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
