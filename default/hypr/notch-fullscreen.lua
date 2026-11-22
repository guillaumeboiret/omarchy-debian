-- Debian port (Apple Silicon): full screen below the camera notch, as on macOS.
--
-- With apple_dcp show_notch=1 the built-in panel includes the notch rows, and
-- Hyprland always sizes a fullscreen window to the whole output, so its top
-- disappears behind the camera. On that panel a window going full screen is
-- held maximized instead, while the app is still told it is fullscreen
-- (internal 1, client 2), on a workspace without outer gaps. It carries the tag
-- notch-fullscreen:<logical px>; the bar (shell/plugins/bar, Debian patch)
-- reads it and becomes a black band of that height, with that exclusive zone,
-- so the window starts right below the notch. External monitors, and special
-- workspaces, keep Hyprland's own fullscreen.
--
-- Leaving: SUPER + F again, SUPER + ALT + F, or the app leaving fullscreen
-- itself (Esc in a video, F11) all end up at a normal window.

local M = {}

local TAG = "notch-fullscreen:"

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

local function held_tag(window)
  for _, tag in ipairs(window.tags or {}) do
    if tag:sub(1, #TAG) == TAG then
      return (tag:gsub("%*$", ""))
    end
  end
  return nil
end

-- Outer gaps would leave a frame around a full screen window. The rule only
-- matches while the workspace holds a maximized window, so it needs no undoing;
-- leaving puts the workspace's own gaps back for a later maximize there.
local function set_gaps(workspace, gaps)
  if workspace and workspace.id then
    hl.workspace_rule({ workspace = "r[" .. workspace.id .. "-" .. workspace.id .. "]f[1]", gaps_out = gaps })
  end
end

local function hold(window, strip)
  set_gaps(window.workspace, 0)
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG .. strip, window = window }))
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 1, client = 2, window = window }))
end

local function release(window, tag, mode)
  set_gaps(window.workspace, hl.get_config(window.floating and "general:float_gaps" or "general:gaps_out"))
  hl.dispatch(hl.dsp.window.tag({ tag = "-" .. tag, window = window }))
  hl.dispatch(hl.dsp.window.fullscreen_state({ internal = mode, client = mode, window = window }))
end

local function eligible(window)
  return window.workspace and not window.workspace.special and M.strip(window.monitor) or 0
end

-- Hyprland suppresses a handler's own recursive calls, and every dispatch here
-- re-fires these events, so each handler only reacts to states it did not make.
local function on_fullscreen(window)
  local tag = held_tag(window)
  if tag then
    -- SUPER + F (internal 2) or a maximize toggle (internal 0) on a held window.
    if window.fullscreen ~= 1 then
      release(window, tag, 0)
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
    local tag = held_tag(window)
    if tag then
      release(window, tag, 0)
    end
  end
end

-- Moved to another workspace: held again there, or Hyprland's own fullscreen
-- on a monitor without a notch.
local function on_move(window, workspace)
  local tag = held_tag(window)
  if not tag then
    return
  end
  local strip = workspace and not workspace.special and M.strip(workspace.monitor) or 0
  if strip > 0 then
    set_gaps(workspace, 0)
    if tag ~= TAG .. strip then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. tag, window = window }))
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG .. strip, window = window }))
    end
  else
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. tag, window = window }))
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 2, client = 2, window = window }))
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

  -- A reload drops workspace rules; windows held across it get theirs back.
  for _, window in ipairs(hl.get_windows() or {}) do
    if held_tag(window) then
      set_gaps(window.workspace, 0)
    end
  end
end

return M
