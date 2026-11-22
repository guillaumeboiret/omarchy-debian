-- Debian port: where a window dragged with SUPER + left click lands on a
-- scrolling workspace.
--
-- Hyprland 0.55's scrolling layout always stacks a dropped tiled window into
-- the column under the pointer (the window there is split in two, one above
-- the other), and a drop anywhere off a window becomes a new column at the far
-- end of the tape. So a window could not be moved to another place in the row.
-- Hyprland 0.57 makes the outer 30% of the window under the pointer open a new
-- column beside it; this does the same on 0.55:
--   - pointer on the left or right 30% of a window: new column on that side,
--     with the width the dragged column had;
--   - pointer on the middle of a window: stacked into its column (unchanged);
--   - pointer on no window (a gap, empty tape): new column beside the nearest
--     column, on the side the pointer is.
--
-- Hyprland has no drag event and ends the drag before any bind sees the button
-- release, when the layout has already placed the window. So a press bind
-- notes the dragged window, a timer notes where it would land while it is
-- dragged, and a release bind moves it there after Hyprland's drop. These are
-- registered before the "Move window" mouse bind, so the press bind still sees
-- the window tiled.

local EDGE = 0.3
local POLL_MS = 25
local MAX_TICKS = 120000 / POLL_MS

local drag

local function get(object, key)
  local ok, value = pcall(function()
    return object[key]
  end)
  if ok then
    return value
  end
end

local function contains(window, point)
  local at, size = get(window, "at"), get(window, "size")
  return at and size and point.x >= at.x and point.x < at.x + size.x and point.y >= at.y and point.y < at.y + size.y
end

-- The column a tiled window has on a scrolling workspace.
local function column(window)
  local layout = get(window, "layout")
  return layout and layout.name == "scrolling" and layout.column or nil
end

-- Where the dragged window would land, or nil where Hyprland's own drop is
-- already right (the middle of a window: stacked into its column).
local function drop_place(dragged)
  local cursor = hl.get_cursor_pos()
  local workspace = get(dragged, "workspace")
  if not cursor or not workspace then
    return nil
  end

  local dragged_address = get(dragged, "address")
  local nearest, nearest_distance
  for _, window in ipairs(hl.get_workspace_windows(workspace) or {}) do
    local col = get(window, "address") ~= dragged_address and not get(window, "floating") and column(window)
    if col and col.index then
      local at, size = window.at, window.size
      if contains(window, cursor) then
        local offset = (cursor.x - at.x) / size.x
        if offset < EDGE then
          return { index = col.index, side = "prev" }
        elseif offset > 1 - EDGE then
          return { index = col.index, side = "next" }
        end
        return nil
      end

      local distance = cursor.x < at.x and at.x - cursor.x or math.max(cursor.x - (at.x + size.x), 0)
      if not nearest_distance or distance < nearest_distance then
        nearest_distance = distance
        nearest = { index = col.index, side = cursor.x < at.x + size.x / 2 and "prev" or "next" }
      end
    end
  end

  return nearest
end

local function layout_msg(message)
  hl.dispatch(hl.dsp.layout(message))
end

-- Hyprland has dropped the window: stacked into the column it was over, or a
-- new column at the end. Put it in its own column at the noted place.
local function place(window, target)
  hl.dispatch(hl.dsp.focus({ window = window }))

  local col = column(window)
  if not col then
    return
  end
  if #(col.windows or {}) > 1 then
    layout_msg("consume_or_expel " .. target.side)
  end

  local index = target.side == "prev" and target.index or target.index + 1
  for _ = 1, 64 do
    col = column(window)
    local current = col and col.index
    if not current or current == index then
      break
    end
    layout_msg(current > index and "swapcol l" or "swapcol r")
    col = column(window)
    if not col or col.index == current then
      break
    end
  end

  if target.width then
    layout_msg("colresize " .. string.format("%.4f", target.width))
  end
end

local function stop()
  if drag and drag.timer then
    drag.timer:set_enabled(false)
  end
  drag = nil
end

local function tick()
  if not drag then
    return
  end

  drag.ticks = drag.ticks + 1
  if drag.ticks > MAX_TICKS or not get(drag.window, "mapped") then
    stop()
  elseif get(drag.window, "floating") then
    drag.floated = true
    drag.place = drop_place(drag.window)
  end
end

local function on_press()
  stop()

  local cursor = hl.get_cursor_pos()
  local workspace = hl.get_active_workspace()
  if not cursor or not workspace then
    return
  end

  -- Only a tiled window on a scrolling workspace, and not when a floating
  -- window over it is the one being dragged.
  local under
  for _, window in ipairs(hl.get_workspace_windows(workspace) or {}) do
    if get(window, "mapped") and contains(window, cursor) then
      if get(window, "floating") then
        return
      end
      under = under or window
    end
  end
  local col = under and column(under)
  if not col then
    return
  end

  drag = {
    window = under,
    -- A window alone in its column keeps that column's width when it moves.
    width = #(col.windows or {}) == 1 and col.width or nil,
    ticks = 0,
  }
  drag.timer = hl.timer(tick, { type = "repeat", timeout = POLL_MS })
end

local function on_release()
  if not drag then
    return
  end

  local window, target, width, floated = drag.window, drag.place, drag.width, drag.floated
  stop()

  if floated and target and get(window, "mapped") and not get(window, "floating") and column(window) then
    target.width = width
    place(window, target)
  end
end

hl.bind("SUPER + mouse:272", on_press, { non_consuming = true, transparent = true })
hl.bind("mouse:272", on_release, { release = true, ignore_mods = true, non_consuming = true, transparent = true })
