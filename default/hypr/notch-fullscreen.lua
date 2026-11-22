-- Debian port (Apple Silicon): full screen below the camera notch, as on macOS.
--
-- With apple_dcp show_notch=1 the built-in panel includes the notch rows, and
-- Hyprland always sizes a fullscreen window to the whole output (the scrolling
-- layout too), so its top disappears behind the camera. On that panel a window
-- going full screen is held maximized instead, while the app is still told it
-- is fullscreen (internal 1, client 2), with no outer gaps. It carries the tag
-- notch-fullscreen:<logical px>; the bar (shell/plugins/bar, Debian patch)
-- reads it and becomes a black band of that height, with that exclusive zone,
-- so the window fills everything below the notch. External monitors, and
-- special workspaces, keep Hyprland's own fullscreen.
--
-- Maximized works for floating windows and the dwindle and master layouts. A
-- tiled window in any other layout (scrolling has no maximized state) is
-- floated while held, and put back afterwards: same column position, width
-- and column-mates on scrolling.
--
-- Leaving: SUPER + F again, SUPER + ALT + F, or the app leaving fullscreen
-- itself (Esc in a video, F11) all end up at the window as it was.

local M = {}

local TAG = "notch-fullscreen:"
local TILED_MAXIMIZE = { dwindle = true, master = true }

-- A window floated to be held carries notch-floated:<column>:<width>:<shared>
-- (column -1 outside scrolling), so it can be put back even after a config
-- reload, which starts a new Lua state but keeps window tags.
local FLOATED = "notch-floated:"

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("a")
  file:close()
  return data
end

-- The notch in physical rows, as the display controller's device tree node
-- gives it (apple,notch-height: what the kernel hides with show_notch=0, and
-- the band macOS keeps black in full screen). 0 when the notch rows are hidden
-- or the machine has none.
local function notch_rows()
  if (read("/sys/module/apple_dcp/parameters/show_notch") or ""):sub(1, 1) ~= "Y" then
    return 0
  end
  local node = (read("/proc/device-tree/aliases/dcp") or ""):gsub("%z.*$", "")
  local raw = node ~= "" and read("/proc/device-tree" .. node .. "/apple,notch-height")
  if not raw or #raw < 4 then
    return 0
  end
  return (string.unpack(">I4", raw))
end

M.rows = notch_rows()

-- The band to keep clear on a monitor, in logical px; 0 where there is none.
function M.strip(monitor)
  if M.rows <= 0 or not monitor or not monitor.name or not monitor.scale or monitor.scale <= 0 then
    return 0
  end
  if not tostring(monitor.name):match("^eDP") then
    return 0
  end
  return math.ceil(M.rows / monitor.scale)
end

local function find_tag(window, prefix)
  for _, tag in ipairs(window.tags or {}) do
    if tag:sub(1, #prefix) == prefix then
      return (tag:gsub("%*$", ""))
    end
  end
  return nil
end

local function held_tag(window)
  return find_tag(window, TAG)
end

local function tag(window, change)
  hl.dispatch(hl.dsp.window.tag({ tag = change, window = window }))
end

local function eligible(window)
  local workspace = window.workspace
  return workspace and not workspace.special and M.strip(window.monitor) or 0
end

local function dispatch(dsp)
  hl.dispatch(dsp)
end

local function state(window, internal, client)
  dispatch(hl.dsp.window.fullscreen_state({ internal = internal, client = client, window = window }))
end

local function set_floating(window, floating)
  dispatch(hl.dsp.window.float({ action = floating and "enable" or "disable", window = window }))
end

-- Outer gaps would leave a frame around a full screen window. The rule only
-- matches while the workspace holds a maximized window, so it needs no undoing;
-- leaving puts back the gaps a later maximize there would get.
local function set_gaps(workspace_id, gaps)
  if workspace_id then
    hl.workspace_rule({ workspace = "r[" .. workspace_id .. "-" .. workspace_id .. "]f[1]", gaps_out = gaps })
  end
end

local function layout_msg(message)
  dispatch(hl.dsp.layout(message))
end

-- Where a window sits in a scrolling layout, as the floated tag records it.
local function floated_tag(window)
  local layout = window.layout
  local column = layout and layout.name == "scrolling" and layout.column
  if not column then
    return FLOATED .. "-1:0:0"
  end
  return string.format("%s%d:%.4f:%d", FLOATED, column.index, column.width, #(column.windows or {}) > 1 and 1 or 0)
end

local function parse_place(floated)
  local index, width, shared = floated:sub(#FLOATED + 1):match("^(-?%d+):([%d.]+):(%d)$")
  index = tonumber(index)
  if not index or index < 0 then
    return nil
  end
  return { index = index, width = tonumber(width), shared = shared == "1" }
end

local function hold(window, strip)
  if not window.floating and not find_tag(window, FLOATED) then
    local layout = window.layout and window.layout.name
    if not TILED_MAXIMIZE[layout] then
      -- Leave the layout's own fullscreen first, so the column is back at its
      -- width before it is noted.
      if window.fullscreen ~= 0 then
        state(window, 0, 0)
      end
      tag(window, "+" .. floated_tag(window))
      set_floating(window, true)
    end
  end

  set_gaps(window.workspace.id, 0)
  tag(window, "+" .. TAG .. strip)
  state(window, 1, 2)
end

-- Back into its scrolling column: re-tiling adds a column next to whatever is
-- under the pointer, so walk it back to its index, then rejoin the column it
-- shared or restore its width.
local function restore_place(window, place)
  local function index()
    local layout = window.layout
    return layout and layout.column and layout.column.index
  end

  local target = place.shared and place.index + 1 or place.index
  dispatch(hl.dsp.focus({ window = window }))
  for _ = 1, 64 do
    local current = index()
    if not current or current == target then
      break
    end
    layout_msg(current > target and "swapcol l" or "swapcol r")
    if index() == current then
      break
    end
  end

  if place.shared then
    layout_msg("consume_or_expel prev")
  elseif place.width then
    layout_msg("colresize " .. string.format("%.4f", place.width))
  end
end

-- mode: the fullscreen state to leave it in (0, or 2 for Hyprland's own).
local function release(window, held, mode)
  local floated = find_tag(window, FLOATED)

  set_gaps(window.workspace and window.workspace.id, hl.get_config(window.floating and "general:float_gaps" or "general:gaps_out"))
  tag(window, "-" .. held)
  state(window, 0, 0)

  if floated then
    tag(window, "-" .. floated)
    set_floating(window, false)
    local place = parse_place(floated)
    if place and window.layout and window.layout.name == "scrolling" then
      restore_place(window, place)
    end
  end

  if mode == 2 then
    state(window, 2, 2)
  end
end

-- Hyprland suppresses a handler's own recursive calls, and every dispatch here
-- re-fires these events, so each handler only reacts to states it did not make.
local function on_fullscreen(window)
  local held = held_tag(window)
  if held then
    -- SUPER + F (internal 2) or a maximize toggle (internal 0) on a held window.
    if window.fullscreen ~= 1 then
      release(window, held, 0)
    end
  elseif window.fullscreen == 2 then
    local strip = eligible(window)
    if strip > 0 then
      hold(window, strip)
    end
  end
end

-- The app leaving fullscreen on its own changes only the client state, which
-- Hyprland reports as a rules update, not a fullscreen event.
local function on_update_rules(window)
  if window.fullscreen_client == 0 and window.fullscreen == 1 then
    local held = held_tag(window)
    if held then
      release(window, held, 0)
    end
  end
end

-- Moved to another workspace: held again there, or Hyprland's own fullscreen
-- on a monitor without a notch.
local function on_move(window, workspace)
  local held = held_tag(window)
  if not held then
    return
  end
  -- Its column belonged to the old workspace: it goes back as a new one.
  local floated = find_tag(window, FLOATED)
  if floated and floated ~= FLOATED .. "-1:0:0" then
    tag(window, "-" .. floated)
    tag(window, "+" .. FLOATED .. "-1:0:0")
  end
  local strip = workspace and not workspace.special and M.strip(workspace.monitor) or 0
  if strip > 0 then
    set_gaps(workspace.id, 0)
    if held ~= TAG .. strip then
      tag(window, "-" .. held)
      tag(window, "+" .. TAG .. strip)
    end
  else
    release(window, held, 2)
  end
end

-- After a reload: held windows get their workspace rule back, and one whose
-- state the reload changed is held again or put back.
local function repair()
  for _, window in ipairs(hl.get_windows() or {}) do
    local held = held_tag(window)
    if held then
      local strip = eligible(window)
      if window.fullscreen == 1 and window.fullscreen_client == 2 then
        set_gaps(window.workspace.id, 0)
      elseif window.fullscreen_client == 2 and strip > 0 then
        tag(window, "-" .. held)
        hold(window, strip)
      else
        release(window, held, 0)
      end
    elseif find_tag(window, FLOATED) then
      local floated = find_tag(window, FLOATED)
      tag(window, "-" .. floated)
      set_floating(window, false)
    end
  end
end

if M.rows > 0 then
  -- A held window is full screen to its app: no border, shadow or rounding.
  hl.window_rule({
    name = "notch-fullscreen",
    match = { fullscreen_state_internal = 1, fullscreen_state_client = 2 },
    decorate = false,
    rounding = 0,
  })

  -- hyprctl eval of this file again replaces the handlers instead of doubling
  -- them; a config reload clears them anyway.
  for _, sub in ipairs(_G.omarchy_notch_fullscreen_subs or {}) do
    sub:remove()
  end
  _G.omarchy_notch_fullscreen_subs = {
    hl.on("window.fullscreen", on_fullscreen),
    hl.on("window.update_rules", on_update_rules),
    hl.on("window.move_to_workspace", on_move),
  }

  -- Once the reload has settled (rules re-applied, layouts restored).
  hl.timer(repair, { type = "oneshot", timeout = 200 })
end

return M
