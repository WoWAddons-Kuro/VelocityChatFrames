-- Velocity Chat Frames: in-memory level/class store for other players, keyed by lowercase first
-- name as chat events deliver it. Filled from the same stock events Prat PlayerNames.lua uses.
-- Display cache about OTHER players, not our per-character data (the GUID-key rule does not apply).
local ADDON_NAME, NS = ...
local Util, Client = NS.Util, NS.Client
local IsSecret = Util.IsSecret

local PlayerData = {}
NS.PlayerData = PlayerData

local VCF_LevelByNameLower = {}
local VCF_ClassByNameLower = {}

local function Key(name)
  if not name or IsSecret(name) or name == "" then return nil end
  if Ambiguate then name = Ambiguate(name, "none") end
  return name:lower()
end

local function Record(name, level, classToken)
  local key = Key(name)
  if not key then return end
  if level and not IsSecret(level) and type(level) == "number" and level > 0 then VCF_LevelByNameLower[key] = level end
  if classToken and not IsSecret(classToken) and classToken ~= "" and classToken ~= UNKNOWN then VCF_ClassByNameLower[key] = classToken end
end

function PlayerData.LevelFor(name)
  local key = Key(name)
  return key and VCF_LevelByNameLower[key] or nil
end

function PlayerData.ClassFor(name)
  local key = Key(name)
  return key and VCF_ClassByNameLower[key] or nil
end

-- Fill functions --------------------------------------------------------------------------

local function FillSelf()
  local _, classToken = UnitClass("player")
  Record(Client.PlayerFirstName(), UnitLevel("player"), classToken)
end

local function FillGuild()
  if not IsInGuild() then return end
  for i = 1, (GetNumGuildMembers() or 0) do
    local name, _, _, level, _, _, _, _, _, _, classToken = GetGuildRosterInfo(i)
    if name and not IsSecret(name) then Record(name:match("^([^%-]+)") or name, level, classToken) end
  end
end

local function FillFriends()
  if not (C_FriendList and C_FriendList.GetNumFriends) then return end
  for i = 1, (C_FriendList.GetNumFriends() or 0) do
    local info = C_FriendList.GetFriendInfoByIndex(i)
    if info and info.name then Record(info.name, info.level, info.className) end
  end
end

local function FillUnit(unit)
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
  local isFriend = UnitIsFriend("player", unit)
  if IsSecret(isFriend) or not isFriend then return end
  local _, classToken = UnitClass(unit)
  Record(UnitName(unit), UnitLevel(unit), classToken)
end

local function FillGroup()
  if IsInRaid() then
    for i = 1, (GetNumGroupMembers() or 0) do FillUnit("raid" .. i) end
  elseif IsInGroup() then
    for i = 1, (GetNumSubgroupMembers() or 0) do FillUnit("party" .. i) end
  end
end

local function FillWho()
  if not (C_FriendList and C_FriendList.GetNumWhoResults) then return end
  for i = 1, (C_FriendList.GetNumWhoResults() or 0) do
    local info = C_FriendList.GetWhoInfo(i)
    if info and info.fullName then Record(info.fullName:match("^([^%-]+)") or info.fullName, info.level, info.filename or info.classStr) end
  end
end

-- Class only, from the sender GUID on a message whose class we do not know yet.
function PlayerData.NoteSenderGUID(name, guid)
  if not guid or IsSecret(guid) or guid == "" or PlayerData.ClassFor(name) then return end
  local _, classToken = GetPlayerInfoByGUID(guid)
  if classToken then Record(name, nil, classToken) end
end

-- A guild message from someone we do not know: ask for a fresh roster (rate-limited).
local lastRosterRequest = 0
function PlayerData.RequestGuildRoster()
  local now = GetTime()
  if now - lastRosterRequest < 10 then return end
  lastRosterRequest = now
  if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

local events = CreateFrame("Frame")
local function Seed()
  FillSelf(); FillFriends(); FillGroup(); PlayerData.RequestGuildRoster()
end

events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    Seed()                                    -- also re-seeds after the PLAYER_LEAVING_WORLD wipe
  elseif event == "PLAYER_LEVEL_UP" then FillSelf()
  elseif event == "GUILD_ROSTER_UPDATE" then FillGuild()
  elseif event == "FRIENDLIST_UPDATE" then FillFriends()
  elseif event == "GROUP_ROSTER_UPDATE" then FillGroup()
  elseif event == "PLAYER_TARGET_CHANGED" then FillUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then FillUnit("mouseover")
  elseif event == "WHO_LIST_UPDATE" then FillWho()
  elseif event == "PLAYER_LEAVING_WORLD" then
    wipe(VCF_LevelByNameLower); wipe(VCF_ClassByNameLower)
  end
end)

-- Init runs FROM the addon's own PLAYER_LOGIN handler, so registering for PLAYER_LOGIN here
-- would wait for an event that has already fired this session: the store stayed empty, even of
-- ourselves (owner 2026-11-23: "known players=0"). Seed directly instead.
function PlayerData.Init()
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GROUP_ROSTER_UPDATE",
                       "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "WHO_LIST_UPDATE", "PLAYER_LEAVING_WORLD" }) do
    events:RegisterEvent(e)
  end
  Seed()
end

function PlayerData.Count()
  local n = 0
  for _ in pairs(VCF_LevelByNameLower) do n = n + 1 end
  return n
end