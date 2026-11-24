-- Velocity Chat Frames: how long a chat line stays before it fades.
--
-- Three timers on the same stock mechanism (SetFading / SetTimeVisible / ResetAllFadeTimes):
--   rest      LineFadeSeconds (15 s) on every non-combat-log window
--   hover     while the pointer is over a window nothing fades; on leave every line gets a fresh
--             rest delay (ResetAllFadeTimes = overrideFadeTimestamp := now). Needs OnEnter/OnLeave
--             while clicks still pass to the world: SetPropagateMouseMotion(true), feature-detected.
--   own input after a line YOU sent, only the window(s) that DISPLAYED it hold lines for
--             OwnInputFadeSeconds (30 s) and then fall back to the rest delay. Other windows and
--             already-faded lines are never touched (no ResetAllFadeTimes).
local ADDON_NAME, NS = ...
local Util, Client, Settings, Windows = NS.Util, NS.Client, NS.Settings, NS.Windows

local Fading = {}
NS.Fading = Fading

local STOCK_TIME_VISIBLE = 120

-- Per-window transient state
local VCF_HoverHeld = {}          -- rec -> true while the pointer is over the window
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
  if s.HoverPausesFade and VCF_HoverHeld[rec] then return nil end
  local untilT = VCF_OwnInputUntil[rec]
  if untilT and untilT > GetTime() then return math.max(rest, s.OwnInputFadeSeconds or 30) end
  return rest
end

function Fading.ApplyRest(rec)
  if rec.isCombatLog then return end
  local delay = EffectiveDelay(rec)
  if not delay then
    rec.frame:SetFading(false)
  else
    rec.frame:SetFading(true)
    rec.frame:SetTimeVisible(delay)
  end
end

function Fading.ApplyAll()
  for _, rec in ipairs(Windows.All()) do Fading.ApplyRest(rec) end
end

function Fading.Restore()
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog then rec.frame:SetFading(true); rec.frame:SetTimeVisible(STOCK_TIME_VISIBLE) end
  end
end

-- Hover --------------------------------------------------------------------------------------
local function OnEnter(frame)
  local rec = Windows.Get(frame)
  if not rec or not Settings.IsEnabled() or not Settings.Get().HoverPausesFade then return end
  VCF_HoverHeld[rec] = true
  Fading.ApplyRest(rec)
end

local function OnLeave(frame)
  local rec = Windows.Get(frame)
  if not rec or not VCF_HoverHeld[rec] then return end
  VCF_HoverHeld[rec] = nil
  -- Everything that was on screen while you read gets a fresh delay instead of vanishing at once.
  if frame.ResetAllFadeTimes then frame:ResetAllFadeTimes() end
  Fading.ApplyRest(rec)
end

-- Motion sensing without taking clicks: the frame must have motion enabled to get OnEnter/OnLeave,
-- and SetPropagateMouseMotion(true) lets the world beneath still see the pointer (hover cursor,
-- tooltips). Without that API the pause is not offered: enabling motion would block world hover,
-- which is the one thing this addon exists to prevent.
Fading.canPauseOnHover = false

local function WireHover(rec)
  local f = rec.frame
  if rec.isCombatLog or f.vcfHoverWired then return end
  if not f.SetPropagateMouseMotion then return end
  f.vcfHoverWired = true
  Fading.canPauseOnHover = true
  f:HookScript("OnEnter", OnEnter)
  f:HookScript("OnLeave", OnLeave)
  Fading.ApplyHoverSensing(rec)
end

function Fading.ApplyHoverSensing(rec)
  local f = rec.frame
  if not f.SetPropagateMouseMotion then return end
  local want = Settings.IsEnabled() and Settings.Get().HoverPausesFade and true or false
  if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(want) end
  f:SetPropagateMouseMotion(want)
  if not want and VCF_HoverHeld[rec] then VCF_HoverHeld[rec] = nil; Fading.ApplyRest(rec) end
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
Settings.OnChange("OwnInputFadeSeconds", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("OwnInputExtendsFade", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("HoverPausesFade", function() for _, rec in ipairs(Windows.All()) do Fading.ApplyHoverSensing(rec) end; if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("Enabled", function()
  for _, rec in ipairs(Windows.All()) do Fading.ApplyHoverSensing(rec) end
  if Settings.IsEnabled() then Fading.ApplyAll() else Fading.Restore() end
end)