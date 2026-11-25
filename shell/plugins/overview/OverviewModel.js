// The window overview's state that does not need Quickshell: which windows it
// shows, how they group by app, where each thumbnail goes on the screen, and
// which thumbnail an arrow key moves to.

// Only windows on regular workspaces show. Special workspaces (the scratchpad,
// the Quake console, the pinned Claude panel, minimized windows) have
// negative ids and stay out, as do child windows such as dialogs.
function isOverviewWindow(window) {
  if (!window || !window.address) return false
  if (window.child === true) return false
  return window.workspaceId >= 1
}

// Windows grouped by app, the app that had focus last first. Each window is
// { key, name, focusHistory, ... } where key names the app (the desktop id the
// dock would give it) and focusHistory is Hyprland's focusHistoryID: 0 is the
// window focused last. Within a group the windows follow the same order.
function groupWindows(windows) {
  var list = (windows || []).filter(isOverviewWindow)
  var byKey = {}
  var groups = []
  for (var i = 0; i < list.length; i++) {
    var window = list[i]
    var key = String(window.key || window.appId || "?")
    if (!byKey[key]) {
      byKey[key] = { key: key, name: String(window.name || key), icon: String(window.icon || ""), windows: [] }
      groups.push(byKey[key])
    }
    byKey[key].windows.push(window)
  }

  function recency(window) {
    var value = Number(window.focusHistory)
    return isFinite(value) && value >= 0 ? value : 1e9
  }

  for (var g = 0; g < groups.length; g++) {
    groups[g].windows.sort(function(a, b) {
      return recency(a) - recency(b) || (a.workspaceId - b.workspaceId) || String(a.address).localeCompare(String(b.address))
    })
    groups[g].recency = recency(groups[g].windows[0])
  }
  groups.sort(function(a, b) {
    return a.recency - b.recency || a.name.toLowerCase().localeCompare(b.name.toLowerCase())
  })
  return groups
}

// A name for a window whose class no desktop entry claims. Chromium names an
// app window after its site (chrome-claude.ai__path-Default), so the site
// stands in; anything else keeps its class.
function fallbackName(appId) {
  var id = String(appId || "")
  var match = /^(?:chrome|chromium|brave|msedge)-([^_]+)__/.exec(id)
  return match ? match[1] : id
}

// A window's width over its height, kept within reason so a very tall or very
// wide window still gets a usable thumbnail.
function aspectOf(window) {
  var w = Number(window && window.width)
  var h = Number(window && window.height)
  var ratio = w > 0 && h > 0 ? w / h : 16 / 10
  return Math.max(0.5, Math.min(2.4, ratio))
}

// Places every group on a width x height area. Thumbnails share one height,
// as large as lets everything fit, each as wide as its window's shape asks.
// A group is a block: its header, then its thumbnails in rows. Blocks flow
// left to right and wrap into lines, and each line is centered, as is the
// whole. When even the smallest thumbnails overflow, the result is taller
// than the area and the overview scrolls.
//
// opts: gap (between thumbnails), groupGap (between blocks), headerHeight,
// titleHeight (the title under a thumbnail), minHeight, maxHeight.
// Returns { thumbHeight, width, height, blocks: [{ x, y, width, height, group,
// items: [{ x, y, width, height, window, index }] }], items: flat list in
// reading order }. Item positions are relative to the area.
function layout(groups, width, height, opts) {
  var o = opts || {}
  var gap = o.gap || 0
  var groupGap = o.groupGap || 0
  var headerHeight = o.headerHeight || 0
  var titleHeight = o.titleHeight || 0
  var minHeight = Math.max(1, o.minHeight || 40)
  var maxHeight = Math.max(minHeight, o.maxHeight || height)
  var areaWidth = Math.max(1, width)
  var list = groups || []

  function measure(thumbHeight) {
    var blocks = []
    for (var g = 0; g < list.length; g++) {
      var windows = list[g].windows || []
      var rows = []
      var row = { width: 0, items: [] }
      for (var i = 0; i < windows.length; i++) {
        var w = Math.min(areaWidth, thumbHeight * aspectOf(windows[i]))
        var next = row.items.length > 0 ? row.width + gap + w : w
        if (row.items.length > 0 && next > areaWidth) {
          rows.push(row)
          row = { width: w, items: [] }
        } else {
          row.width = next
        }
        row.items.push({ width: w, window: windows[i] })
      }
      if (row.items.length > 0) rows.push(row)
      var blockWidth = 0
      for (var r = 0; r < rows.length; r++) blockWidth = Math.max(blockWidth, rows[r].width)
      var cellHeight = thumbHeight + titleHeight
      blocks.push({
        group: list[g],
        rows: rows,
        width: blockWidth,
        height: headerHeight + rows.length * cellHeight + Math.max(0, rows.length - 1) * gap
      })
    }

    var lines = []
    var line = { width: 0, height: 0, blocks: [] }
    for (var b = 0; b < blocks.length; b++) {
      var block = blocks[b]
      var wider = line.blocks.length > 0 ? line.width + groupGap + block.width : block.width
      if (line.blocks.length > 0 && wider > areaWidth) {
        lines.push(line)
        line = { width: block.width, height: block.height, blocks: [block] }
      } else {
        line.width = wider
        line.height = Math.max(line.height, block.height)
        line.blocks.push(block)
      }
    }
    if (line.blocks.length > 0) lines.push(line)

    var total = 0
    for (var l = 0; l < lines.length; l++) total += lines[l].height
    total += Math.max(0, lines.length - 1) * groupGap
    return { thumbHeight: thumbHeight, lines: lines, height: total }
  }

  // The largest thumbnail height that fits, found by bisection.
  var best = measure(minHeight)
  if (best.height <= height) {
    var lo = minHeight
    var hi = maxHeight
    var top = measure(hi)
    if (top.height <= height) {
      best = top
    } else {
      for (var step = 0; step < 24 && hi - lo > 0.5; step++) {
        var mid = (lo + hi) / 2
        var tried = measure(mid)
        if (tried.height <= height) {
          lo = mid
          best = tried
        } else {
          hi = mid
        }
      }
    }
  }

  var thumbHeight = Math.floor(best.thumbHeight)
  var result = { thumbHeight: thumbHeight, width: areaWidth, height: Math.max(height, best.height), blocks: [], items: [] }
  var y = Math.max(0, Math.round((height - best.height) / 2))
  for (var li = 0; li < best.lines.length; li++) {
    var current = best.lines[li]
    var x = Math.round((areaWidth - current.width) / 2)
    for (var bi = 0; bi < current.blocks.length; bi++) {
      var measured = current.blocks[bi]
      var placed = { x: x, y: y, width: Math.round(measured.width), height: Math.round(measured.height), group: measured.group, items: [] }
      var rowY = y + headerHeight
      for (var ri = 0; ri < measured.rows.length; ri++) {
        var rowItems = measured.rows[ri]
        var itemX = x + (measured.width - rowItems.width) / 2
        for (var ii = 0; ii < rowItems.items.length; ii++) {
          var cell = rowItems.items[ii]
          var item = {
            x: Math.round(itemX),
            y: Math.round(rowY),
            width: Math.floor(cell.width),
            height: thumbHeight,
            window: cell.window,
            index: result.items.length
          }
          placed.items.push(item)
          result.items.push(item)
          itemX += cell.width + gap
        }
        rowY += thumbHeight + titleHeight + gap
      }
      result.blocks.push(placed)
      x += measured.width + groupGap
    }
    y += current.height + groupGap
  }
  return result
}

// The thumbnail an arrow key moves to from the one at index: the nearest one
// whose center lies that way, preferring those in line with it. Left and
// right also step to the previous or next one in reading order at the ends of
// a row. Items are { x, y, width, height }; direction is "left", "right", "up"
// or "down". Returns index itself when nothing lies that way.
function neighbor(items, index, direction) {
  var list = items || []
  if (list.length === 0) return -1
  if (index < 0 || index >= list.length) return 0
  var from = list[index]
  var fx = from.x + from.width / 2
  var fy = from.y + from.height / 2
  var best = -1
  var bestScore = Infinity
  for (var i = 0; i < list.length; i++) {
    if (i === index) continue
    var cx = list[i].x + list[i].width / 2
    var cy = list[i].y + list[i].height / 2
    var dx = cx - fx
    var dy = cy - fy
    var along, across
    if (direction === "left") { along = -dx; across = dy }
    else if (direction === "right") { along = dx; across = dy }
    else if (direction === "up") { along = -dy; across = dx }
    else if (direction === "down") { along = dy; across = dx }
    else return index
    if (along <= 1) continue
    var score = along + Math.abs(across) * 2
    if (score < bestScore) {
      bestScore = score
      best = i
    }
  }
  if (best >= 0) return best
  if (direction === "left") return index > 0 ? index - 1 : index
  if (direction === "right") return index < list.length - 1 ? index + 1 : index
  return index
}

if (typeof module !== "undefined") {
  module.exports = {
    isOverviewWindow: isOverviewWindow,
    groupWindows: groupWindows,
    aspectOf: aspectOf,
    fallbackName: fallbackName,
    layout: layout,
    neighbor: neighbor
  }
}
