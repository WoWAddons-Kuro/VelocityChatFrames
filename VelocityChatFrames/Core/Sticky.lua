-- Velocity Chat Frames: sticky chat types. ChatTypeInfo[TYPE].sticky = 1|0 is the whole mechanism
-- (Prat ChannelSticky.lua:162). On Forever ChatTypeInfo is a proxy table: index by key, never pairs().
local ADDON_NAME, NS = ...
local Settings = NS.Settings

local Sticky = {}
NS.Sticky = Sticky

Sticky.TYPES = { "SAY", "YELL", "PARTY", "RAID", "RAID_WARNING", "INSTANCE_CHAT", "GUILD", "OFFICER",
                 "WHISPER", "BN_WHISPER", "CHANNEL", "EMOTE" }

local stockSticky = {}   -- TYPE -> original value, captured once so disable can restore it

local function Apply(chatType, on)
  local info = ChatTypeInfo and ChatTypeInfo[chatType]
  if not info then return end
  if stockSticky[chatType] == nil then stockSticky[chatType] = info.sticky or 0 end
  info.sticky = on and 1 or 0
end

function Sticky.ApplyAll()
  local cfg = Settings.Get().Sticky
  for _, t in ipairs(Sticky.TYPES) do Apply(t, cfg[t]) end
end

function Sticky.Restore()
  for t, v in pairs(stockSticky) do
    local info = ChatTypeInfo and ChatTypeInfo[t]
    if info then info.sticky = v end
  end
end

function Sticky.Init()
  if Settings.IsEnabled() then Sticky.ApplyAll() end
end

Settings.OnChange("Sticky", function() if Settings.IsEnabled() then Sticky.ApplyAll() end end)
Settings.OnChange("Enabled", function() if Settings.IsEnabled() then Sticky.ApplyAll() else Sticky.Restore() end end)