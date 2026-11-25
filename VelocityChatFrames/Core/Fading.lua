-- Velocity Chat Frames: how long a chat line stays before it fades.
--
-- Three timers on the same stock mechanism (SetFading / SetTimeVisible / ResetAllFadeTimes):
--   rest      LineFadeSeconds (15 s) on every non-combat-log window
--   hover     while the pointer is over a window, lines that are still VISIBLE are periodically
--             re-stamped so they do not run out; faded lines stay faded; nothing happens on leave.
--             Needs OnEnter/OnLeave while clicks still pass to the world: SetPropagateMouseMotion(true).
--   own input after a line YOU sent, only the window(s) that DISPLAYED it hold lines for
--             OwnInputFadeSeconds (30 s) and then fall back to the rest delay. Other windows and
--             already-faded lines are never touched (no ResetAllFadeTimes).
local ADDON_NAME, NS = ...
local Util, Client, Settings, Windows = NS.Util, NS.Client, NS.Settings, NS.Windows

local Fading = {}
NS.Fading = Fading

local STOCK_TIME_VISIBLE = 120

-- Per-window transient state
local VCF_OwnInputUntil = {}      -- rec -> GetTime() when the extended delay ends
local VCF_OwnInputTimer = {}      -- rec -> C_Timer handle

local function Editing()
  return NS.Reveal and NS.Reveal.InEditMode and NS.Reveal.InEditMode()
end

-- The delay this window should be using right now, or nil for "do not fade".
local function EffectiveDelay(rec)
  local s = Settings.Get()
  local rest = s.LineFadeSeconds or 15
  if NS.Reveal and NS.Reveal.IsWindowUnlocked(rec) then return nil end
  if rest <= 0 or Editing() then return nil end
  local untilT = VCF_OwnInputUntil[rec]
  if untilT and untilT > GetTime() then return math.max(rest, s.OwnInputFadeSeconds or 30) end
  return rest
end

function Fading.ApplyRest(rec)
  if rec.isCombatLog then return end
  local delay = EffectiveDelay(rec)
  local f = rec.frame
  if not delay then
    f:SetFading(false)
  else
    f:SetFading(true)
    f:SetTimeVisible(delay)
  end
  -- Force-set the fade-out duration EVERY pass. Other addons (ElvUI's chat module in particular)
  -- write their own SetFadeDuration / SetTimeVisible onto the stock frames and win by running last;
  -- re-asserting here makes ours the last word on every ApplyRest, which already runs on login,
  -- entering world, setting changes and new windows.
  local duration = Settings.Get().LineFadeDurationSeconds or 3
  Client.SetLineFadeDuration(f, math.max(duration, 0.01))   -- 0 in the UI = effectively instant
end

function Fading.ApplyAll()
  for _, rec in ipairs(Windows.All()) do Fading.ApplyRest(rec) end
end

function Fading.Restore()
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog then rec.frame:SetFading(true); rec.frame:SetTimeVisible(STOCK_TIME_VISIBLE) end
  end
end

-- Hover ---------------------------------------------------------------------------------------
-- The ONLY effect of the pointer being over a window: lines that are currently VISIBLE do not run
-- out of time. Nothing appears, nothing is revealed, nothing happens on leave. Implemented by
-- re-stamping each visible line's own messageInfo.timestamp (ScrollingMessageFrame.lua 776-786:
-- alpha is computed per line from max(messageInfo.timestamp, overrideFadeTimestamp)) on a ~1 s
-- ticker while hovered. ResetAllFadeTimes is never used: it bumps overrideFadeTimestamp, which
-- revives every already-faded line in the window.
local HOVER_RESTAMP_SECS = 1.0
local VCF_HoverTicker = {}        -- rec -> C_Timer ticker handle while the pointer is over the window

local function RestampVisibleLines(rec)
  local f = rec.frame
  if not (f.visibleLines and f.CalculateLineAlphaValueFromTimestamp) then return end
  local now = GetTime()
  local override = f.overrideFadeTimestamp or 0
  for _, line in ipairs(f.visibleLines) do
    local info = line.messageInfo
    if info and info.timestamp then
      local stamp = math.max(info.timestamp, override)
      if f:CalculateLineAlphaValueFromTimestamp(now, stamp) > 0 then
        info.timestamp = now     -- still visible: give it a full fresh delay...
        line:SetAlpha(1)         -- ...and back to full opacity now, rather than at the stock pass
        line:Show()
      end
    end
  end
  -- Stock UpdateFading skips the per-line pass until the oldest visible line is due; after a
  -- re-stamp that "due" time moved, so let it recompute.
  f.oldestFadingLineTimestamp = now
end

local function OnEnter(frame)
  local rec = Windows.Get(frame)
  if not rec or not Settings.IsEnabled() or not Settings.Get().HoverPausesFade then return end
  if VCF_HoverTicker[rec] then return end
  RestampVisibleLines(rec)
  VCF_HoverTicker[rec] = C_Timer.NewTicker(HOVER_RESTAMP_SECS, function() RestampVisibleLines(rec) end)
end

local function OnLeave(frame)
  local rec = Windows.Get(frame)
  if not rec then return end
  local t = VCF_HoverTicker[rec]
  if t then t:Cancel(); VCF_HoverTicker[rec] = nil end
  -- Nothing else: the visible lines keep the fresh delay from their last re-stamp and fade normally.
end

-- Motion sensing without taking clicks: how a frame gets OnEnter/OnLeave while the world beneath still
-- sees the pointer is client-specific and lives in Client.SetHoverSensing / Client.CanSenseHover. If the
-- client cannot do it the option is not offered: motion without pass-through would block world hover,
-- which is the one thing this addon exists to prevent.
Fading.canPauseOnHover = false

local function WireHover(rec)
  local f = rec.frame
  if rec.isCombatLog or f.vcfHoverWired then return end
  if not Client.CanSenseHover() then return end
  f.vcfHoverWired = true
  Fading.canPauseOnHover = true
  f:HookScript("OnEnter", OnEnter)
  f:HookScript("OnLeave", OnLeave)
  Fading.ApplyHoverSensing(rec)
end

function Fading.ApplyHoverSensing(rec)
  local f = rec.frame
  if not Client.CanSenseHover() then return end
  local want = Settings.IsEnabled() and Settings.Get().HoverPausesFade and true or false
  Client.SetHoverSensing(f, want)
  -- Sensing turned off while hovered: stop the re-stamp ticker, same as OnLeave would.
  if not want then OnLeave(f) end
end

-- Own input -----------------------------------------------------------------------------------
-- Which windows actually DISPLAYED the line you just sent? Stock routing (message groups,
-- channel lists, filters) is not re-implemented; instead every window's AddMessage is hooked and
-- stamped with GetTime(). GetTime() is constant within one frame tick, so a window stamped with
-- the tick of our CHAT_MSG_* event received that very message. The check runs a tick later
-- (C_Timer.After(0)) so it does not matter whether the chat frames' handlers ran before ours.
local VCF_LastAddMessageTick = {}   -- rec -> GetTime() of the window's most recent AddMessage

local function WireAddMessageStamp(rec)
  local f = rec.frame
  if rec.isCombatLog or f.vcfAddMessageStamped or not f.AddMessage then return end
  f.vcfAddMessageStamped = true
  hooksecurefunc(f, "AddMessage", function() VCF_LastAddMessageTick[rec] = GetTime() end)
end

-- Hold lines in ONE window: SetTimeVisible(OwnInputFadeSeconds) for that long, then back to rest.
-- Deliberately no ResetAllFadeTimes: that re-stamps every existing line as "shown now" and was
-- what un-hid all lines in all windows on every sent message.
local function ExtendWindowForOwnInput(rec, secs)
  VCF_OwnInputUntil[rec] = GetTime() + secs
  Fading.ApplyRest(rec)
  if VCF_OwnInputTimer[rec] then VCF_OwnInputTimer[rec]:Cancel() end
  VCF_OwnInputTimer[rec] = C_Timer.NewTimer(secs + 0.1, function()
    VCF_OwnInputTimer[rec] = nil
    VCF_OwnInputUntil[rec] = nil
    Fading.ApplyRest(rec)
  end)
end

local function ExtendForOwnInput()
  local s = Settings.Get()
  if not (Settings.IsEnabled() and s.OwnInputExtendsFade) then return end
  local secs = s.OwnInputFadeSeconds or 30
  local eventTick = GetTime()
  C_Timer.After(0, function()
    for _, rec in ipairs(Windows.All()) do
      if not rec.isCombatLog and VCF_LastAddMessageTick[rec] == eventTick then
        ExtendWindowForOwnInput(rec, secs)
      end
    end
  end)
end

-- CHAT_MSG_* arg2 is the sender's name (first name on Forever). Compare against ours; secret
-- values in instances are skipped (they can never equal a plain string anyway).
local OWN_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, sender)
  if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
    ExtendForOwnInput(); return                           -- _INFORM is by definition ours
  end
  if Util.IsSecret(sender) or not sender then return end
  local me = Client.PlayerFirstName()
  if Ambiguate then sender = Ambiguate(sender, "none") end
  if sender == me then ExtendForOwnInput() end
end)

-- Init -----------------------------------------------------------------------------------------
-- /vcf fadedebug: report every ResetAllFadeTimes (the only thing that un-fades a whole window)
-- with the caller, so an unexplained whole-window reveal can be traced to stock or to us.
Fading.debug = false
local function WireFadeDebug(rec)
  local f = rec.frame
  if rec.isCombatLog or f.vcfFadeDebugWired or not f.ResetAllFadeTimes then return end
  f.vcfFadeDebugWired = true
  hooksecurefunc(f, "ResetAllFadeTimes", function(frame)
    if not Fading.debug then return end
    local who = debugstack(3, 1, 0):match("^%s*(.-)%s*$") or "?"
    Util.Print("%s ResetAllFadeTimes <- %s", frame:GetName() or "?", who)
  end)
end
function Fading.ToggleDebug()
  Fading.debug = not Fading.debug
  for _, rec in ipairs(Windows.All()) do WireFadeDebug(rec) end
  Util.Print("fade debug=%s (prints who resets fade times per window)", tostring(Fading.debug))
end

function Fading.Init()
  Windows.OnNewRecord(function(rec)
    WireHover(rec)
    WireAddMessageStamp(rec)
    if Settings.IsEnabled() then Fading.ApplyRest(rec) end
  end)
  for _, rec in ipairs(Windows.All()) do WireHover(rec); WireAddMessageStamp(rec) end
  for _, e in ipairs(OWN_EVENTS) do events:RegisterEvent(e) end
  if Settings.IsEnabled() then Fading.ApplyAll() end
end

Settings.OnChange("LineFadeSeconds", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("LineFadeDurationSeconds", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("OwnInputFadeSeconds", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("OwnInputExtendsFade", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("HoverPausesFade", function() for _, rec in ipairs(Windows.All()) do Fading.ApplyHoverSensing(rec) end; if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("Enabled", function()
  for _, rec in ipairs(Windows.All()) do Fading.ApplyHoverSensing(rec) end
  if Settings.IsEnabled() then Fading.ApplyAll() else Fading.Restore() end
end)