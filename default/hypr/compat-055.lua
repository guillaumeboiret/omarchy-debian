-- Debian port: Hyprland 0.55 compatibility shim.
-- Omarchy targets Hyprland 0.56+. Instead of crashing on APIs/events that 0.55
-- doesn't have, skip them and record what was skipped in /tmp/omarchy-compat.log.
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
