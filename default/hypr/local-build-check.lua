-- Debian port: Hyprland is a local build with
-- debian/hyprland/local-clip-sliding-workspace.patch (version ending in +local1).
-- An apt upgrade replaces it with the stock package, which brings back off-screen
-- scrolling columns sliding over the next workspace. Say so once per version.

hl.on("hyprland.start", function()
  local query = io.popen("dpkg-query -W -f='${Version}' hyprland 2>/dev/null")
  local version = query and query:read("*l") or ""
  if query then
    query:close()
  end
  if version == "" or version:find("+local", 1, true) then
    return
  end

  local state = (os.getenv("HOME") or "") .. "/.local/state/omarchy/hyprland-stock-version-noticed"
  local file = io.open(state, "r")
  local noticed = file and file:read("*l")
  if file then
    file:close()
  end
  if noticed == version then
    return
  end

  file = io.open(state, "w")
  if file then
    file:write(version, "\n")
    file:close()
  end
  hl.exec_cmd(o.notify("Hyprland " .. version .. " is the stock build: the sliding-workspace clip patch is gone. See debian/hyprland/README.md in the Omarchy port."))
end)
