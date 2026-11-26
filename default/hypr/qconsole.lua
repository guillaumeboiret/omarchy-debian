-- The Quake console: a dimmed overlay that drops down over whatever workspace
-- you are on. It is its own special workspace, separate from the full-size
-- scratchpad on Super + S. Its bindings live in bindings/tiling.lua, and its
-- slide is animated below.

-- How much of the usable screen the console covers, measured from the top.
local share = 0.5

-- A console holding a single window is boxed into a centered panel this many
-- times wider than it is tall, rather than stretched the width of the screen.
-- A second app on the console gets the full width back: two windows splitting
-- a half-width column is worse than the band this replaced.
local box = 2

local CONSOLE = "special:qconsole"

-- Debian port: the size a lone console was dragged to, as shares of the usable
-- screen ({ wide = , tall = }), or nil for the default panel above. It is kept
-- in a state file so a config reload or a new login opens it the same size.
local SIZE_FILE = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/omarchy/qconsole-size"
local sized = nil

do
  local file = io.open(SIZE_FILE, "r")
  if file then
    local wide, tall = (file:read("*l") or ""):match("^([%d.]+) ([%d.]+)$")
    file:close()
    if wide and tall then
      sized = { wide = tonumber(wide), tall = tonumber(tall) }
    end
  end
end

-- Seed the console with the default agent the first time it opens, rather than
-- at boot, so nothing is running until it is wanted. The exec rule has to pin
-- the workspace itself: Hyprland only tags a spawn with the workspace it came
-- from while misc.initial_workspace_tracking is on, and looknfeel turns it off.
-- Omarchy ships without a default agent, so --pick offers the choice instead
-- of an empty console that explains nothing. One that has to be installed
-- first does so in a floating terminal and then moves into the console; see
-- omarchy-default-agent. A console created by moving a window onto it is not
-- empty, and is left alone.
hl.on("workspace.created", function(ws)
  if ws and ws.name == CONSOLE and ws.is_empty then
    hl.exec_cmd("omarchy-agent --pick", { workspace = CONSOLE .. " silent" })
  end
end)

-- Dimming only applies while a special workspace is open, so the console gets
-- its separation from the workspace underneath without costing anything the
-- rest of the time.
hl.config({
  decoration = {
    dim_special = 0.6,
  },
})

-- The panel is always flush with the top and always centered, so two numbers
-- describe it: the gap down each side and the gap underneath.
--
-- Refitting replaces the rule in place rather than stacking a new one, but it
-- still schedules a monitor and window state refresh, and monitor.focused fires
-- on every hop between screens. Most of those hops do not change the gaps, so
-- only write the rule when it actually moves.
local beside, below = nil, nil

local function cover(side, bottom)
  if beside == side and below == bottom then
    return false
  end
  beside, below = side, bottom

  hl.workspace_rule({
    workspace = CONSOLE,
    gaps_in = 0,
    gaps_out = { top = 0, right = side, bottom = bottom, left = side },

    -- Nothing to highlight in a console that is only ever focused when it is
    -- open, and the active border reads as a stray frame around a panel that
    -- is already set apart by the dimming behind it.
    no_border = true,
  })

  return true
end

-- One window reads as a console and gets the panel. A second app has turned the
-- console into a workspace, and a workspace wants the whole width. Only tiled
-- windows count: the gaps are what size the panel, and a floating window on top
-- of the console is not laid out by them.
local function alone()
  local tiled = 0
  for _, window in ipairs(hl.get_workspace_windows(CONSOLE)) do
    if not window.floating then
      tiled = tiled + 1
    end
  end
  return tiled <= 1
end

-- Sizing the console with a window rule would freeze it at whatever the screen
-- measured when it first opened, because Hyprland resolves those expressions
-- once, as the window maps. Rescaling the monitor afterwards would leave a
-- console that is no longer half of anything. Gaps are re-applied by the layout
-- instead, so the console is sized by the area left around it, and that area is
-- recomputed whenever the monitor it opens on changes.
local function fit(monitor)
  -- A monitor handle whose output has gone away answers nil to every field, and
  -- layout changes are exactly when that happens, so this also covers reading
  -- width, height and reserved below.
  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return false
  end

  -- Width and height are the panel's own pixels, so a monitor turned on its
  -- side still reports them the way the panel is built. The odd transforms are
  -- the quarter turns, and those are the ones that swap the work area.
  local width, height = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then
    width, height = height, width
  end

  -- Monitor dimensions are in physical pixels; gaps are logical, so the scale
  -- has to come out before the reserved area (already logical) comes off.
  local reserved = monitor.reserved or { top = 0, bottom = 0, left = 0, right = 0 }  -- Debian port: 0.55 has no monitor.reserved
  height = height / monitor.scale - reserved.top - reserved.bottom
  width = width / monitor.scale - reserved.left - reserved.right

  local tall = math.floor(height * (sized and sized.tall or share))
  local wide = width
  if alone() then
    wide = sized and math.floor(width * sized.wide) or math.min(width, tall * box)
  end

  return cover(math.floor((width - wide) / 2), math.floor(height - tall))
end

-- The console keeps the geometry of the output it is open on: a follow_mouse hop
-- onto another screen must not resize a console that is already showing. While
-- it is hidden there is nothing to size but the output that will show it next.
local function console_monitor()
  local ws = hl.get_workspace(CONSOLE)
  local mon = ws and ws.visible and ws.monitor

  if mon and mon.scale and mon.scale > 0 then
    return mon
  end

  return hl.get_active_monitor()
end

local function refit(monitor)
  if fit(monitor or console_monitor()) then
    -- Land the new gaps in this pass rather than a frame later, so the console
    -- does not visibly resize itself once it has already dropped down.
    if hl.exec_scheduled_prop_refresh_immediately then  -- Debian port: 0.56+ only; 0.55 applies it a frame later
      hl.exec_scheduled_prop_refresh_immediately()
    end
  end
end

-- Until a monitor can be read, cover the whole work area rather than leaving
-- the console unruled, so it is never seeded without its placement. A reload
-- runs this again with the console already on screen, so it starts from the
-- output the console is on rather than whichever one the pointer is over.
cover(0, 0)
fit(console_monitor())

hl.on("monitor.layout_changed", function()
  refit()
end)

hl.on("monitor.focused", function()
  refit()
end)

-- Special workspaces open on the monitor they are toggled on, not on whichever
-- output last happened to be focused when the rule was written, so these two
-- take the monitor they are handed rather than looking one up.
hl.on("workspace.special_active", function(ws, mon)
  if ws and ws.name == CONSOLE then
    refit(mon)
  end
end)

hl.on("workspace.move_to_monitor", function(ws, mon)
  if ws and ws.name == CONSOLE then
    refit(mon)
  end
end)

-- The panel is only centered while the console holds one tiled window, so the
-- count has to be rechecked as apps come and go: opened and closed, moved on or
-- off (Super+Shift+Grave, Super+Shift+1), and floated or tiled (Super+T, Super+O).
-- window.close is left out, since it still counts the window on its way out and
-- window.destroy follows it anyway. Measured on Hyprland 0.56.2, a move is
-- trailed by several window.update_rules, as is a float toggle, and the last of
-- those always reads the settled count; the earlier ones refit to what the rule
-- already is, which cover() skips.
--
-- Only while it is on screen, though. A hidden console is refitted on its way in
-- by workspace.special_active, and every window opened anywhere on the desktop
-- would otherwise rewrite the rule.
local function recount()
  local ws = hl.get_workspace(CONSOLE)
  if ws and ws.visible then
    refit()
  end
end

hl.on("window.open", recount)
hl.on("window.destroy", recount)
hl.on("window.move_to_workspace", recount)
hl.on("window.update_rules", recount)

-- Debian port: dragging the console's left, right or bottom edge resizes it
-- about its center. It stays tiled, so it cannot be moved: the drag rewrites
-- the gaps that size it, the two sides together, and the top stays flush.
-- Hyprland has no resize event, and a lone tiled window ignores its own border
-- resize, so a press bind starts a timer that follows the pointer and a release
-- bind ends it and saves the size. Only a console holding one window has a
-- panel to resize; a second app has the full width (see alone()).
local GRAB = 14
local MIN_WIDE, MIN_TALL = 320, 160
local POLL_MS = 16
local MAX_TICKS = 120000 / POLL_MS

local resize

local function work_area(monitor)
  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return nil
  end
  local width, height = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then
    width, height = height, width
  end
  local reserved = monitor.reserved or { top = 0, bottom = 0, left = 0, right = 0 }
  return width / monitor.scale - reserved.left - reserved.right, height / monitor.scale - reserved.top - reserved.bottom
end

local function stop_resize()
  if resize and resize.timer then
    resize.timer:set_enabled(false)
  end
  resize = nil
end

local function follow()
  if not resize then
    return
  end
  resize.ticks = resize.ticks + 1
  local cursor = hl.get_cursor_pos()
  if resize.ticks > MAX_TICKS or not cursor then
    stop_resize()
    return
  end

  local wide = resize.wide
  if resize.sides then
    wide = math.max(MIN_WIDE, math.min(resize.width, 2 * math.abs(cursor.x - resize.center)))
  end
  local tall = resize.tall
  if resize.bottom then
    tall = math.max(MIN_TALL, math.min(resize.height, cursor.y - resize.top))
  end

  sized = { wide = wide / resize.width, tall = tall / resize.height }
  refit(resize.monitor)
end

local function start_resize()
  stop_resize()

  local ws = hl.get_workspace(CONSOLE)
  if not ws or not ws.visible or not alone() then
    return
  end
  local cursor = hl.get_cursor_pos()
  local window
  for _, w in ipairs(hl.get_workspace_windows(CONSOLE) or {}) do
    if not w.floating then
      window = w
    end
  end
  if not cursor or not window then
    return
  end

  local at, size = window.at, window.size
  local left, right, bottom = at.x, at.x + size.x, at.y + size.y
  local in_rows = cursor.y >= at.y and cursor.y <= bottom + GRAB
  local in_cols = cursor.x >= left - GRAB and cursor.x <= right + GRAB
  local sides = in_rows and (math.abs(cursor.x - left) <= GRAB or math.abs(cursor.x - right) <= GRAB)
  local below = in_cols and math.abs(cursor.y - bottom) <= GRAB
  if not sides and not below then
    return
  end

  local monitor = console_monitor()
  local width, height = work_area(monitor)
  if not width then
    return
  end

  resize = {
    monitor = monitor,
    width = width,
    height = height,
    center = at.x + size.x / 2,
    top = at.y,
    wide = size.x,
    tall = size.y,
    sides = sides,
    bottom = below,
    ticks = 0,
  }
  resize.timer = hl.timer(follow, { type = "repeat", timeout = POLL_MS })
end

local function end_resize()
  if not resize then
    return
  end
  stop_resize()
  if sized then
    os.execute("mkdir -p '" .. SIZE_FILE:match("^(.*)/") .. "'")
    local file = io.open(SIZE_FILE, "w")
    if file then
      file:write(string.format("%.4f %.4f\n", sized.wide, sized.tall))
      file:close()
    end
  end
end

hl.bind("mouse:272", start_resize, { ignore_mods = true, non_consuming = true, transparent = true })
hl.bind("mouse:272", end_resize, { release = true, ignore_mods = true, non_consuming = true, transparent = true })

-- The direction names the edge the offset is measured from, not where the
-- workspace goes: "slide top" drops it down into view, and "slide bottom"
-- retracts it back up the way a Quake console does.
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "easeOutQuint", style = "slide bottom" })
