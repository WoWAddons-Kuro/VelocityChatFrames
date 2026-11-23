-- Velocity Chat Frames: shared helpers. Loads first.
local ADDON_NAME, NS = ...
NS.ADDON_NAME = ADDON_NAME

local Util = {}
NS.Util = Util

local PREFIX = "|cffffcf4dVCF|r: "

function Util.Print(fmt, ...)
  if select("#", ...) > 0 then fmt = string.format(fmt, ...) end
  print(PREFIX .. tostring(fmt))
end

local warned = {}
function Util.WarnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  Util.Print("|cffff4040warning|r " .. tostring(msg))
end

-- Report a caught error through the client's error handler (BugSack etc. see it) without unwinding.
function Util.Raise(context, err)
  local msg = string.format("VelocityChatFrames: %s: %s", tostring(context), tostring(err))
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(msg) else error(msg, 0) end
end

-- Secret-value guard (Forever instances). Always available, false elsewhere.
Util.IsSecret = issecretvalue or function() return false end

-- Shallow copy of defaults into a table, only where missing (one level of nested tables).
function Util.ApplyDefaults(dst, defaults)
  for k, v in pairs(defaults) do
    if dst[k] == nil then
      if type(v) == "table" then
        local c = {}
        for kk, vv in pairs(v) do c[kk] = vv end
        dst[k] = c
      else
        dst[k] = v
      end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      for kk, vv in pairs(v) do if dst[k][kk] == nil then dst[k][kk] = vv end end
    end
  end
  return dst
end

function Util.Clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function Util.ClientInfo()
  local version, build, _, interface = GetBuildInfo()
  return { Version = version, Build = build, Interface = interface, Project = WOW_PROJECT_ID }
end