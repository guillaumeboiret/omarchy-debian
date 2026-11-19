-- Debian port: persistent Lua error log for the Hyprland config.
--
-- Hyprland 0.55 only shows load errors in its on-screen overlay (gone after the
-- next reload) and silently drops errors raised inside callbacks (hl.on events,
-- hl.timer, function keybinds). This module records both, with tracebacks, in
--   ~/.local/state/omarchy/lua-errors.log      (view: omarchy-lua-errorlog)
-- Errors are still re-raised, so Hyprland's own behaviour doesn't change.
-- Loaded first from bootstrap.lua; the Lua state survives reloads, so wrap once.
if rawget(_G, "__omarchy_errorlog") then return end

local dir = os.getenv("HOME") .. "/.local/state/omarchy"
local path = dir .. "/lua-errors.log"
local max_bytes = 1024 * 1024
local recent = {} -- message -> last time logged (suppress floods from per-event callbacks)

local function rotate()
  local f = io.open(path, "r")
  if not f then return end
  local size = f:seek("end")
  f:close()
  if size and size > max_bytes then os.rename(path, path .. ".1") end
end

local function log(kind, msg, trace)
  msg = tostring(msg)
  local now = os.time()
  if recent[msg] and now - recent[msg] < 30 then return end
  recent[msg] = now

  rotate()
  local f = io.open(path, "a")
  if not f then
    os.execute("mkdir -p '" .. dir .. "'")
    f = io.open(path, "a")
    if not f then return end
  end
  f:write(os.date("%Y-%m-%d %H:%M:%S"), " [", kind, "] ", msg, "\n")
  if trace then f:write("    ", (trace:gsub("\n", "\n    ")), "\n") end
  f:close()
end

local function protect(kind, fn, ...)
  local trace
  local results = table.pack(xpcall(fn, function(err)
    trace = debug.traceback("", 2):gsub("^\n", "")
    return err
  end, ...))
  if not results[1] then
    log(kind, results[2], trace)
    error(results[2], 0)
  end
  return table.unpack(results, 2, results.n)
end

-- Load-time errors in modules (require/dofile). The innermost failing module
-- logs it; the re-raised copies up the chain are suppressed as duplicates.
local real_require, real_dofile = require, dofile
require = function(name)
  return protect("load " .. tostring(name), real_require, name)
end
dofile = function(file)
  return protect("load " .. tostring(file), real_dofile, file)
end

-- Runtime errors in callbacks: wrap every function handed to an hl.* function.
-- hl.* errors raised through the wrapper would point at this file, so they are
-- re-raised with the caller's file:line (what Hyprland showed before).
local here = debug.getinfo(1, "S").short_src:gsub("%p", "%%%0")
local function relocate(err)
  if type(err) ~= "string" then return err end
  err = err:gsub("^" .. here .. ":%d+: ", "", 1)
  if err:find("^[^\n]-:%-?%d+: ") then return err end -- already has a location
  local info = debug.getinfo(3, "Sl")
  if info and info.currentline and info.currentline > 0 then
    return info.short_src .. ":" .. info.currentline .. ": " .. err
  end
  return err
end

local function wrap_callbacks(owner, fname, fn)
  return function(...)
    local args = table.pack(...)
    for i = 1, args.n do
      if type(args[i]) == "function" then
        local cb = args[i]
        args[i] = function(...) return protect("callback " .. owner .. fname, cb, ...) end
      end
    end
    local results = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    if not results[1] then error(relocate(results[2]), 0) end
    return table.unpack(results, 2, results.n)
  end
end

local function wrap_table(t, owner, seen)
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    if type(v) == "function" then
      t[k] = wrap_callbacks(owner, tostring(k), v)
    elseif type(v) == "table" then
      wrap_table(v, owner .. tostring(k) .. ".", seen)
    end
  end
end

wrap_table(hl, "hl.", {})

-- Errors Hyprland collects itself (bad option values, top-level config errors):
-- snapshot `hyprctl configerrors` after start and every reload. Run async — a
-- synchronous hyprctl from inside the config would deadlock on Hyprland's socket.
local function snapshot_configerrors()
  hl.exec_cmd("sh -c 'sleep 2; exec omarchy-lua-errorlog --snapshot'")
end
hl.on("hyprland.start", snapshot_configerrors)
hl.on("config.reloaded", snapshot_configerrors)

_G.__omarchy_errorlog = { log = log, path = path }
