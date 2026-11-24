-- Velocity Chat Frames: scrollback restore. See SPECS\04_ScrollbackRestore.md.
--
-- Capture on PLAYER_LOGOUT (fires on /reload too): per non-combat-log window, the newest
-- ScrollbackLines lines as {text, r, g, b, visible} + savedAt. Restore from Init, before any live
-- CHAT_MSG line lands, then one grey boundary marker.
--
-- Fade state is carried across the gap by writing the SMF history entry's `timestamp` field
-- (the field RefreshDisplay reads; entries are plain Lua tables): a line that was visible at logout
-- gets `now` when you are back within ScrollbackGraceMinutes, everything else gets a timestamp far
-- enough in the past that it is alpha 0 at once (history only: wheel / hover / scroll shows it).
--
-- Whisper journal: whispers' already-formatted display text (captured from the receiving window's
-- AddMessage in the same tick as the CHAT_MSG event) is kept per Client.WhisperScopeKey() and
-- merged into every window that shows the WHISPER / BN_WHISPER groups; own-character entries
-- are skipped (they are already in that window's own scrollback).
local ADDON_NAME, NS = ...
local Util, Client, Settings, Windows = NS.Util, NS.Client, NS.Settings, NS.Windows
local IsSecret = Util.IsSecret

local Scrollback = {}
NS.Scrollback = Scrollback

local MARKER_RGB = { 0.5, 0.5, 0.5 }
local PLAIN_RGB  = { 0.6, 0.6, 0.6 }
local WHISPER_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }

-- SavedVariables -------------------------------------------------------------------------

local function DB()
  local db = NS.db
  db.scrollback = db.scrollback or {}   -- [playerGUID] = { savedAt, windows = { [id] = { line... } } }
  db.whispers   = db.whispers   or {}   -- [scopeKey]   = { {t, text, r, g, b, visible, ownerKey}, ... }
  return db
end

-- Entry access ---------------------------------------------------------------------------

-- Newest history entry of a ScrollingMessageFrame (the one AddMessage just pushed).
local function NewestEntry(frame)
  local found
  frame:ForEachMessage(function(entry) found = entry; return true end)
  return found
end

-- Is this history entry currently drawn with alpha > 0 (or would be, if the frame is not fading)?
local function EntryVisible(frame, entry)
  if not entry then return false end
  -- SMF has no IsFading getter; SetFading writes shouldFadeAfterInactivity and UpdateFading only
  -- runs when CanEffectivelyFade(). A non-fading frame shows every line at alpha 1.
  local fading = frame.CanEffectivelyFade and frame:CanEffectivelyFade() or frame.shouldFadeAfterInactivity
  if not fading then return true end
  local stamp = entry.timestamp or 0
  if frame.overrideFadeTimestamp and frame.overrideFadeTimestamp > stamp then stamp = frame.overrideFadeTimestamp end
  local age = GetTime() - stamp
  return age <= (frame:GetTimeVisible() or 0)
end

-- Markup stripping (links / colours / textures) for colourless restore.
local function StripMarkup(text)
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]-:", ""):gsub("|c%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  return text
end
Scrollback.StripMarkup = StripMarkup

-- Capture --------------------------------------------------------------------------------

-- Lines the client re-emits itself on every login (GMOTD, disconnect/reconnect notices, welcome
-- text). Restoring them stacks one copy per reload, so they are never captured.
local function LoginBoilerplatePatterns()
  local out = {}
  local function add(globalFmt)
    if type(globalFmt) ~= "string" or globalFmt == "" then return end
    -- "%s" -> ".*", escape magic chars, anchor at start (a timestamp prefix may precede: allow it)
    local pat = globalFmt:gsub("%%%d?%$?[sd]", "\0"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%z", ".*")
    out[#out + 1] = pat
  end
  add(GUILD_MOTD_TEMPLATE)                      -- "Guild Message of the Day: %s"
  add(CHAT_SERVER_DISCONNECTED_MESSAGE)
  add(CHAT_SERVER_RECONNECTED_MESSAGE)
  add(WELCOME_TO_WORLD_OF_WARCRAFT)
  return out
end
local boilerplate = nil
local function IsLoginBoilerplate(text)
  boilerplate = boilerplate or LoginBoilerplatePatterns()
  local plain = StripMarkup(text):gsub("^%[?%d%d:%d%d:?%d?%d?%]?%s*", "")   -- drop a leading timestamp
  for _, pat in ipairs(boilerplate) do if plain:find("^" .. pat) then return true end end
  return false
end

local function CaptureWindow(rec, maxLines)
  local frame = rec.frame
  local lines = {}
  local n = 0
  -- ForEachMessage enumerates newest first; collect then reverse so stored order is oldest first.
  frame:ForEachMessage(function(entry)
    if n >= maxLines then return true end
    local text = entry.message
    if type(text) == "string" and not IsSecret(text) and not entry.vcfMarker and not IsLoginBoilerplate(text) then
      n = n + 1
      lines[n] = { text = text, r = entry.r, g = entry.g, b = entry.b, visible = EntryVisible(frame, entry) }
    end
  end)
  local out = {}
  for i = n, 1, -1 do out[#out + 1] = lines[i] end
  return out
end

function Scrollback.Capture()
  if not NS.db then return end
  local s = Settings.Get()
  local db = DB()
  local key = Client.PlayerKey()
  if not key then return end
  -- Only the current character's scrollback is kept (whispers are the only cross-character data).
  wipe(db.scrollback)
  if not (Settings.IsEnabled() and s.ScrollbackRestore) then return end
  local entry = { savedAt = time(), windows = {} }
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog and rec.frame.ForEachMessage then
      local lines = CaptureWindow(rec, s.ScrollbackLines or 100)
      if #lines > 0 then entry.windows[rec.id] = lines end
    end
  end
  db.scrollback[key] = entry
end

-- Whisper journal ------------------------------------------------------------------------

local VCF_WhisperTick = nil          -- GetTime() of the CHAT_MSG_*WHISPER* event being handled
local VCF_WhisperAdded = {}         -- frame -> true once the journal got this event's line (one window is enough)

local function JournalPush(text, r, g, b, visibleFrame)
  local s = Settings.Get()
  local db = DB()
  local scope = Client.WhisperScopeKey()
  db.whispers[scope] = db.whispers[scope] or {}
  local list = db.whispers[scope]
  list[#list + 1] = { t = time(), text = text, r = r, g = g, b = b, visible = true, ownerKey = Client.PlayerKey() }
  local max = s.WhisperLines or 20
  while #list > max do table.remove(list, 1) end
end

local function WireWhisperCapture(rec)
  local f = rec.frame
  if rec.isCombatLog or f.vcfWhisperWired or not f.AddMessage then return end
  f.vcfWhisperWired = true
  hooksecurefunc(f, "AddMessage", function(frame, text, r, g, b)
    if not VCF_WhisperTick or VCF_WhisperTick ~= GetTime() or VCF_WhisperAdded.done then return end
    if type(text) ~= "string" or IsSecret(text) then return end
    local s = Settings.Get()
    if not (Settings.IsEnabled() and s.ScrollbackRestore and s.ScrollbackWhispers) then return end
    VCF_WhisperAdded.done = true
    JournalPush(text, r, g, b, frame)
  end)
end

local whisperEvents = CreateFrame("Frame")
whisperEvents:SetScript("OnEvent", function()
  -- Stamp the tick; whichever window's AddMessage fires this tick captures the formatted line.
  VCF_WhisperTick = GetTime()
  VCF_WhisperAdded.done = nil
end)

-- At logout, mark which journal entries were still visible: those belong to this character's
-- windows, so reuse the per-window visibility. Entries from other characters keep their flag.
local function UpdateJournalVisibility()
  local db = DB()
  local list = db.whispers[Client.WhisperScopeKey()]
  if not list then return end
  local me = Client.PlayerKey()
  -- Build a set of currently visible whisper texts from any window.
  local visibleTexts = {}
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog and rec.frame.ForEachMessage then
      rec.frame:ForEachMessage(function(entry)
        if type(entry.message) == "string" and EntryVisible(rec.frame, entry) then visibleTexts[entry.message] = true end
      end)
    end
  end
  for _, w in ipairs(list) do
    if w.ownerKey == me then w.visible = visibleTexts[w.text] and true or false end
  end
end

-- Restore --------------------------------------------------------------------------------

local function WindowShowsWhispers(rec)
  if not GetChatWindowMessages then return rec.frame == DEFAULT_CHAT_FRAME end
  for _, group in ipairs({ GetChatWindowMessages(rec.id) }) do
    if group == "WHISPER" or group == "BN_WHISPER" then return true end
  end
  return false
end

-- Push one line and stamp its fade state. `visibleNow` true = fresh LineFadeSeconds from now.
local function PushRestored(frame, text, r, g, b, visibleNow, isMarker)
  frame:AddMessage(text, r, g, b)
  local entry = NewestEntry(frame)
  if not entry then return end
  if isMarker then entry.vcfMarker = true end
  if visibleNow then
    entry.timestamp = GetTime()
  else
    local past = (frame:GetTimeVisible() or 120) + ((frame.GetFadeDuration and frame:GetFadeDuration()) or 3) + 1
    entry.timestamp = GetTime() - past
  end
end

local function RestoreWindow(rec, ownLines, journal, savedAt, withinGrace, inColor)
  local frame = rec.frame
  -- Merge: own lines are in order already (no per-line time); journal entries from other
  -- characters are appended before the marker in time order. Own-character journal entries
  -- are skipped -- they are in ownLines.
  local me = Client.PlayerKey()
  local foreign = {}
  if journal then
    for _, w in ipairs(journal) do if w.ownerKey ~= me then foreign[#foreign + 1] = w end end
    table.sort(foreign, function(a, b) return a.t < b.t end)
  end
  local count = 0
  local function push(line)
    local text, r, g, b = line.text, line.r, line.g, line.b
    if not inColor then text = StripMarkup(text); r, g, b = PLAIN_RGB[1], PLAIN_RGB[2], PLAIN_RGB[3] end
    PushRestored(frame, text, r, g, b, withinGrace and line.visible, false)
    count = count + 1
  end
  -- Foreign whispers older than this character's save go first, the rest after (best effort:
  -- own lines carry no timestamps, so split on savedAt).
  for _, w in ipairs(foreign) do if savedAt and w.t <= savedAt then push(w) end end
  if ownLines then for _, line in ipairs(ownLines) do push(line) end end
  for _, w in ipairs(foreign) do if not savedAt or w.t > savedAt then push(w) end end
  if count > 0 then
    local when = savedAt or (foreign[#foreign] and foreign[#foreign].t) or time()
    local marker = string.format("-- previous session (%s) --", date("%H:%M, %b %d", when))
    PushRestored(frame, marker, MARKER_RGB[1], MARKER_RGB[2], MARKER_RGB[3], withinGrace, true)
  end
  if frame.MarkDisplayDirty then frame:MarkDisplayDirty() end
end

function Scrollback.Restore()
  local s = Settings.Get()
  if not (Settings.IsEnabled() and s.ScrollbackRestore) then return end
  local db = DB()
  local saved = db.scrollback[Client.PlayerKey()]
  local journal = s.ScrollbackWhispers and db.whispers[Client.WhisperScopeKey()] or nil
  local savedAt = saved and saved.savedAt
  local graceSecs = (s.ScrollbackGraceMinutes or 10) * 60
  local withinGrace = savedAt and (time() - savedAt) <= graceSecs or false
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog and rec.frame.ForEachMessage then
      local own = saved and saved.windows[rec.id]
      local j = WindowShowsWhispers(rec) and journal or nil
      if own or (j and #j > 0) then
        RestoreWindow(rec, own, j, savedAt, withinGrace, s.ScrollbackInColor)
      end
    end
  end
  -- Consumed: a second login without a logout (crash) must not restore stale lines twice.
  wipe(db.scrollback)
end

-- Init -----------------------------------------------------------------------------------

function Scrollback.Init()
  for _, rec in ipairs(Windows.All()) do WireWhisperCapture(rec) end
  Windows.OnNewRecord(WireWhisperCapture)
  for _, e in ipairs(WHISPER_EVENTS) do whisperEvents:RegisterEvent(e) end

  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGOUT")
  f:SetScript("OnEvent", function()
    local ok, err = pcall(function() UpdateJournalVisibility(); Scrollback.Capture() end)
    if not ok then Util.Raise("Scrollback.Capture", err) end
  end)

  local ok, err = pcall(Scrollback.Restore)
  if not ok then Util.Raise("Scrollback.Restore", err) end
end