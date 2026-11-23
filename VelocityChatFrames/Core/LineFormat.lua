-- Velocity Chat Frames: timestamps, short channel tags, [level:Name]. See SPECS\01_LineFormatting.md
-- and _ref\blizzard\README-chat-api-notes.md "Sender name decoration and timestamps".
--
--   timestamps   -> the stock showTimestamps setting (no hook)
--   channel tags -> overwrite the CHAT_<TYPE>_GET format globals (no hook)
--   level in name-> ChatFrameUtil.AddSenderNameFilter (official, secret-safe, both clients)
local ADDON_NAME, NS = ...
local Util, Settings, PlayerData = NS.Util, NS.Settings, NS.PlayerData
local IsSecret = Util.IsSecret

local LineFormat = {}
NS.LineFormat = LineFormat

-- Channel tags ----------------------------------------------------------------------------

-- TYPE -> short tag. The stock format is "|Hchannel:TYPE|h[Long Name]|h %s:\32"; we keep the
-- channel link and the trailing "%s:\32" and swap only the bracket text.
LineFormat.SHORT_TAGS = {
  SAY = "S", YELL = "Y", GUILD = "G", OFFICER = "O",
  PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
  RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
  INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
  WHISPER = "W From", WHISPER_INFORM = "W To",
  BN_WHISPER = "W From", BN_WHISPER_INFORM = "W To",
}

local stockFormats = {}   -- TYPE -> original CHAT_<TYPE>_GET, captured once

local function ApplyTag(chatType, tag)
  local key = "CHAT_" .. chatType .. "_GET"
  local stock = stockFormats[chatType] or _G[key]
  if type(stock) ~= "string" then return end
  stockFormats[chatType] = stock
  -- Two stock shapes:
  --   "|Hchannel:GUILD|h[Guild]|h %s:\32"   -> swap the bracket text, keep the channel link
  --   "%s says:\32" / "%s yells:\32" / "%s whispers:\32" / "To %s:\32"  -> no brackets; rebuild as "[S] %s:\32"
  local replaced, n = stock:gsub("%[.-%]", "[" .. tag .. "]", 1)
  if n == 1 then
    _G[key] = replaced
  else
    _G[key] = "[" .. tag .. "] %s:\32"
  end
end

function LineFormat.ApplyTags()
  for chatType, tag in pairs(LineFormat.SHORT_TAGS) do ApplyTag(chatType, tag) end
end

function LineFormat.RestoreTags()
  for chatType, stock in pairs(stockFormats) do _G["CHAT_" .. chatType .. "_GET"] = stock end
end

-- Timestamps ------------------------------------------------------------------------------

local function ApplyTimestamps()
  local s = Settings.Get()
  if not (C_CVar and C_CVar.SetCVar) then return end
  if s.Timestamps then
    -- stock expects a trailing space in the format
    local fmt = (s.TimestampFormat or "%H:%M")
    if fmt:sub(-1) ~= " " then fmt = fmt .. " " end
    C_CVar.SetCVar("showTimestamps", fmt)
  else
    C_CVar.SetCVar("showTimestamps", "none")
  end
end

-- Level in name ---------------------------------------------------------------------------

local function DifficultyColorFor(level)
  local fn = GetQuestDifficultyColor or GetDifficultyColor
  if not fn then return nil end
  local c = fn(level)
  if not c then return nil end
  -- desaturate a little so the number does not shout
  local r, g, b = c.r, c.g, c.b
  local grey = (r + g + b) / 3
  local k = 0.6
  return r * k + grey * (1 - k), g * k + grey * (1 - k), b * k + grey * (1 - k)
end

local function SenderNameFilter(event, decoratedPlayerName, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)
  if not Settings.IsEnabled() then return nil end
  local s = Settings.Get()
  if not s.ShowLevelInName then return nil end
  if IsSecret(decoratedPlayerName) or IsSecret(arg2) or not arg2 or arg2 == "" then return nil end

  PlayerData.NoteSenderGUID(arg2, arg12)
  local level = PlayerData.LevelFor(arg2)
  if not level then
    if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then PlayerData.RequestGuildRoster() end
    return nil
  end

  local levelText = tostring(level)
  if s.LevelColorByDifficulty then
    local r, g, b = DifficultyColorFor(level)
    if r then levelText = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, levelText) end
  end
  return levelText .. ":" .. decoratedPlayerName
end

-- Init / settings -------------------------------------------------------------------------

local filterInstalled = false

function LineFormat.ApplyAll()
  local s = Settings.Get()
  if Settings.IsEnabled() and s.ShortChannelTags then LineFormat.ApplyTags() else LineFormat.RestoreTags() end
  if Settings.IsEnabled() then ApplyTimestamps() end
end

function LineFormat.Init()
  if not filterInstalled and ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
    ChatFrameUtil.AddSenderNameFilter(SenderNameFilter)
    filterInstalled = true
  elseif not filterInstalled then
    Util.WarnOnce("sendername", "ChatFrameUtil.AddSenderNameFilter not available; [level:Name] disabled")
  end
  LineFormat.ApplyAll()
  -- Global strings and the showTimestamps setting can be re-applied by stock code after login;
  -- re-assert ours on entering world and after settings load.
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("SETTINGS_LOADED")
  f:SetScript("OnEvent", function() LineFormat.ApplyAll() end)
end

for _, key in ipairs({ "Enabled", "ShortChannelTags", "Timestamps", "TimestampFormat" }) do
  Settings.OnChange(key, LineFormat.ApplyAll)
end