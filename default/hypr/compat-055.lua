-- Debian port: Hyprland 0.55 compatibility shim.
-- Omarchy targets Hyprland 0.56+. Instead of crashing on APIs/events that 0.55
-- doesn't have, skip them and record what was skipped in /tmp/omarchy-compat.log.
-- hl.dsp.workspace.change_id (0.56) renumbers a workspace in place; monitor-workspaces.lua
-- uses it to fold an unplugged monitor's workspaces into the remaining one. 0.55 has
-- no equivalent dispatcher, so emulate it: move the windows to the new id, put that
-- workspace on the same monitor, and show it there if the old one was showing.
-- hl.dispatch only takes real dispatchers, so it learns to run these stand-ins.
-- Separately guarded so `hyprctl reload` picks it up without a re-login.
if not rawget(_G, "__omarchy_compat_055_change_id") and hl.dsp.workspace.change_id == nil then
  _G.__omarchy_compat_055_change_id = true
  local STANDIN = {}

  hl.dsp.workspace.change_id = function(args)
    return { [STANDIN] = function()
      local old, new = tonumber(args.workspace), tonumber(args.id)
      local workspace = old and new and hl.get_workspace(old)
      if not workspace or hl.get_workspace(new) then
        return
      end

      local monitor = workspace.monitor and hl.get_monitor(workspace.monitor.name)
      local showing = monitor and monitor.active_workspace and monitor.active_workspace.id == old

      for _, window in ipairs(hl.get_windows()) do
        if window.workspace and window.workspace.id == old then
          hl.dispatch(hl.dsp.window.move({ workspace = tostring(new), follow = false, window = "address:" .. window.address }))
        end
      end

      if monitor and hl.get_workspace(new) then
        hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(new), monitor = monitor.name }))
        if showing then
          hl.dispatch(hl.dsp.focus({ workspace = tostring(new) }))
        end
      end
    end }
  end

  local real_dispatch = hl.dispatch
  hl.dispatch = function(dispatcher, ...)
    if type(dispatcher) == "table" and dispatcher[STANDIN] then
      return dispatcher[STANDIN]()
    end
    return real_dispatch(dispatcher, ...)
  end
end

if rawget(_G, "__omarchy_compat_055") then return end
_G.__omarchy_compat_055 = true

local function note(msg)
  local f = io.open("/tmp/omarchy-compat.log", "a")
  if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end

-- Events Hyprland 0.55 knows (from its own error message)
local KNOWN = {}
for e in ([[hyprland.start config.reloaded workspace.active monitor.layout_changed hyprland.shutdown
  workspace.move_to_monitor monitor.removed monitor.added keybinds.submap layer.opened window.open
  window.open_early window.urgent monitor.focused window.close layer.closed window.destroy
  screenshare.state workspace.removed workspace.created window.kill window.active window.pin
  window.title window.fullscreen window.class window.update_rules window.move_to_workspace]]):gmatch("%S+") do
  KNOWN[e] = true
end

local DUMMY = { remove = function() end, is_active = function() return false end }
local real_on = hl.on
hl.on = function(event, cb)
  if not KNOWN[event] then
    note("hl.on skipped unknown event: " .. tostring(event))
    return DUMMY
  end
  return real_on(event, cb)
end
