import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// The battery over the last 24 hours, the way a phone shows it: one bar per
// quarter hour at the level it ended on, a green band over the stretches on
// the charger, and the hours along the bottom. Point at a bar to read it.
// The history is UPower's own (Device.GetHistory), fetched when the panel
// opens and every couple of minutes while it stays open.
Column {
  id: history

  property bool active: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color fainter: Qt.darker(foreground, 2.1)
  // Literal, like the shell's other status colours: most themes have no green.
  readonly property color chargeColor: "#8CC88C"
  readonly property color lowColor: "#E5534B"

  readonly property int bucketCount: 96
  readonly property double bucketMs: 15 * 60 * 1000

  property var samples: []
  // The gauge right now, so the newest bar follows the plug before UPower
  // logs the change; -1 when unknown.
  property real liveLevel: -1
  property bool liveCharging: false
  property double endMs: 0
  readonly property var buckets: bucketize(liveLevel >= 0 && endMs > 0
    ? samples.concat([{ t: Math.min(Date.now(), endMs - 1), v: liveLevel, s: liveCharging ? 1 : 2 }])
    : samples, endMs)
  readonly property int hoverIndex: chartHover.hovered ? barAt(chartHover.point.position.x) : -1

  // 0..1, the bars growing in from the left on each open.
  property real grow: 1

  function refresh() {
    if (!fetch.running) fetch.running = true
  }

  onActiveChanged: if (active) { refresh(); growIn.restart() }

  // Samples arrive newest first as [time, percent, state]; state 1 is
  // charging and 4 fully charged, both on the charger.
  function parse(text) {
    var out = []
    try {
      var data = JSON.parse(text)
      var rows = data && data.data && data.data[0]
      for (var i = 0; rows && i < rows.length; i++) {
        var r = rows[i]
        // UPower logs a 0% "unknown" at boot before the gauge reports.
        if (r[2] === 0 && r[1] === 0) continue
        out.push({ t: r[0] * 1000, v: r[1], s: r[2] })
      }
    } catch (e) {}
    out.sort(function(a, b) { return a.t - b.t })
    return out
  }

  // Each quarter hour takes the last reading inside it, or carries the one
  // before it forward; nothing is drawn before the first reading.
  function bucketize(list, end) {
    var out = []
    if (end <= 0) return out
    var start = end - bucketCount * bucketMs
    var j = 0
    var last = null
    while (j < list.length && list[j].t < start) { last = list[j]; j++ }
    for (var b = 0; b < bucketCount; b++) {
      var t1 = start + (b + 1) * bucketMs
      var seen = false, charging = false
      while (j < list.length && list[j].t < t1) {
        last = list[j]
        if (last.s === 1) charging = true
        seen = true
        j++
      }
      if (!last) { out.push(null); continue }
      if (!seen) charging = last.s === 1 || last.s === 4
      out.push({ v: last.v, charging: charging, t: t1 })
    }
    return out
  }

  function barAt(x) {
    var w = plot.width
    if (w <= 0) return -1
    return Math.max(0, Math.min(bucketCount - 1, Math.floor(x / (w / bucketCount))))
  }

  readonly property var summary: {
    var low = 101, charges = 0, wasCharging = false, any = false
    for (var i = 0; i < buckets.length; i++) {
      var b = buckets[i]
      if (!b) continue
      any = true
      low = Math.min(low, b.v)
      if (b.charging && !wasCharging) charges++
      wasCharging = b.charging
    }
    return any ? { low: Math.round(low), charges: charges } : null
  }

  readonly property string caption: {
    if (hoverIndex >= 0) {
      var b = buckets[hoverIndex]
      var from = new Date(endMs - (bucketCount - hoverIndex) * bucketMs)
      var when = Qt.formatTime(from, "HH:mm")
      if (!b) return when + "  ·  no data"
      return when + "  ·  " + Math.round(b.v) + "%" + (b.charging ? "  ·  charging" : "")
    }
    if (!summary) return fetch.running ? "Loading…" : ""
    return "Lowest " + summary.low + "%"
      + (summary.charges > 0 ? "  ·  charged " + summary.charges + "×" : "")
  }

  spacing: Style.space(10)

  Process {
    id: fetch
    // The first battery that powers the machine, not a mouse or a keyboard.
    command: ["bash", "-c",
      "for d in $(upower -e | grep /battery_); do "
      + "if upower -i \"$d\" | grep -q 'power supply: *yes'; then "
      + "busctl --json=short call org.freedesktop.UPower \"$d\" org.freedesktop.UPower.Device GetHistory suu charge 90000 500; "
      + "break; fi; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The window ends on the next quarter hour, so the newest bar is now.
        history.endMs = Math.ceil(Date.now() / history.bucketMs) * history.bucketMs
        history.samples = history.parse(text)
      }
    }
  }

  Timer {
    interval: 120000
    running: history.active
    repeat: true
    onTriggered: history.refresh()
  }

  NumberAnimation {
    id: growIn
    target: history
    property: "grow"
    from: 0
    to: 1
    duration: Style.duration(900)
    easing.type: Easing.OutCubic
  }

  // ---- header: the title, and the day's summary or the bar pointed at
  Item {
    width: parent.width
    implicitHeight: Math.max(title.implicitHeight, captionText.implicitHeight)

    Text {
      id: title
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "LAST 24 HOURS"
      color: history.foreground
      opacity: 0.6
      font.family: history.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Text {
      id: captionText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: history.caption
      color: history.hoverIndex >= 0 ? history.foreground : history.dim
      font.family: history.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- the bars, with the level scale on the right
  Item {
    width: parent.width
    height: Style.space(118)

    readonly property real scaleWidth: Style.space(34)

    // The green band over time spent on the charger.
    Item {
      id: band
      anchors.left: parent.left
      anchors.top: parent.top
      width: plot.width
      height: Style.space(5)

      Repeater {
        model: history.bucketCount
        Rectangle {
          required property int index
          readonly property var b: history.buckets[index] || null
          readonly property real slot: band.width / history.bucketCount
          visible: b !== null && b.charging
          x: index * slot
          width: Math.ceil(slot)
          height: band.height
          color: Qt.rgba(history.chargeColor.r, history.chargeColor.g, history.chargeColor.b, 0.55)
          opacity: Util.clamp(history.grow * 1.6 - index / history.bucketCount * 0.6, 0, 1)
        }
      }
    }

    Canvas {
      id: plot
      // A fresh canvas shows as uninitialised (magenta on this GPU) for a frame
      // before its first paint; keep it hidden until then.
      property bool everPainted: false
      onPainted: everPainted = true
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.rightMargin: parent.scaleWidth
      anchors.top: band.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: parent.bottom
      antialiasing: true
      renderStrategy: Canvas.Cooperative
      opacity: everPainted ? 1 : 0

      Connections {
        target: history
        function onBucketsChanged() { plot.requestPaint() }
        function onGrowChanged() { plot.requestPaint() }
        function onHoverIndexChanged() { plot.requestPaint() }
        function onForegroundChanged() { plot.requestPaint() }
      }
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var fg = history.foreground
        var n = history.bucketCount
        var slot = width / n
        var gap = slot > 4 ? 1.5 : 1
        var barW = Math.max(1, slot - gap)

        // 0, 50 and 100%: faint rules behind the bars.
        ctx.lineWidth = 1
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.10)
        for (var k = 0; k <= 2; k++) {
          var gy = Math.round(k / 2 * (height - 1)) + 0.5
          ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
        }
        // Midnight and every six hours: dotted columns.
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.10)
        var start = history.endMs - n * history.bucketMs
        for (var b = 0; b < n; b++) {
          var t = start + b * history.bucketMs
          var d = new Date(t)
          if (d.getMinutes() === 0 && d.getHours() % 6 === 0) {
            var gx = Math.round(b * slot) + 0.5
            for (var y = 0; y < height; y += 4) {
              ctx.beginPath(); ctx.moveTo(gx, y); ctx.lineTo(gx, Math.min(y + 1.5, height)); ctx.stroke()
            }
          }
        }

        for (var i = 0; i < n; i++) {
          var bk = history.buckets[i]
          if (!bk) continue
          // Each bar rises a beat after the one to its left.
          var g = Util.clamp(history.grow * 1.6 - i / n * 0.6, 0, 1)
          g = 1 - Math.pow(1 - g, 3)
          var h = Math.max(1.5, bk.v / 100 * height * g)
          var c = bk.charging ? history.chargeColor : bk.v <= 20 ? history.lowColor : fg
          var a = history.hoverIndex < 0 || history.hoverIndex === i ? 1 : 0.45
          ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, (bk.charging || bk.v <= 20 ? 0.9 : 0.78) * a)
          var x = i * slot + gap / 2
          var r = Math.min(barW / 2, 1.5)
          var top = height - h
          ctx.beginPath()
          ctx.moveTo(x, height)
          ctx.lineTo(x, top + r)
          ctx.quadraticCurveTo(x, top, x + r, top)
          ctx.lineTo(x + barW - r, top)
          ctx.quadraticCurveTo(x + barW, top, x + barW, top + r)
          ctx.lineTo(x + barW, height)
          ctx.closePath()
          ctx.fill()
        }
      }

      HoverHandler { id: chartHover; cursorShape: Qt.CrossCursor }
    }

    Repeater {
      model: [100, 50, 0]
      Text {
        required property var modelData
        anchors.right: parent.right
        y: plot.y + (1 - modelData / 100) * (plot.height - 1) - height / 2
        textFormat: Text.PlainText
        text: modelData + "%"
        color: history.fainter
        font.family: history.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---- the hours along the bottom
  Item {
    width: parent.width - Style.space(34)
    height: hourMetrics.height

    FontMetrics {
      id: hourMetrics
      font.family: history.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: {
        var out = []
        if (history.endMs <= 0) return out
        var start = history.endMs - history.bucketCount * history.bucketMs
        for (var b = 0; b < history.bucketCount; b++) {
          var d = new Date(start + b * history.bucketMs)
          if (d.getMinutes() === 0 && d.getHours() % 6 === 0)
            out.push({ at: b / history.bucketCount, label: Qt.formatTime(d, "HH:mm") })
        }
        return out
      }
      Text {
        required property var modelData
        x: Util.clamp(modelData.at * parent.width - implicitWidth / 2, 0, parent.width - implicitWidth)
        textFormat: Text.PlainText
        text: modelData.label
        color: history.fainter
        font.family: history.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
