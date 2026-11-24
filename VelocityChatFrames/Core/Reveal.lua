-- Velocity Chat Frames: Phase 0 kill-switch for the stock mouseover reveal.
--
-- FCF_OnUpdate polls IsMouseOver every frame and calls FCF_FadeInChatFrame / FCF_FadeOutChatFrame,
-- which queue UIFrameFadeIn/Out on the background pieces, tab, button column and scrollbar.
-- We let the stock function run, then cancel its fades and put every piece back to its rest alpha.
-- See SPECS\03_Behaviour.md "Phase 0" and _ref\blizzard\README-chat-api-notes.md.
local ADDON_NAME, NS = ...
local Util, Client, Settings, Windows = NS.Util, NS.Client, NS.Settings, NS.Windows

local Reveal = {}
NS.Reveal = Reveal

local hooked = false

local function CancelFade(region)
  if region and UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(region) end
end

local function SetAlphaQuiet(region, alpha)
  if not region then return end
  CancelFade(region)
  region:SetAlpha(alpha)
end

-- The alpha the user configured for this window's background (chat-cache, not ours to change).
local function UserBackgroundAlpha(rec)
  local _, _, _, _, _, alpha = GetChatWindowInfo(rec.id)
  if type(alpha) == "number" then return alpha end
  return DEFAULT_CHATFRAME_ALPHA or 0.25
end

local function IsSelectedTab(rec)
  if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
    return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) == rec.frame
  end
  return SELECTED_CHAT_FRAME == rec.frame
end

-- The alpha a tab should share: for a docked window, the alpha of the dock's SELECTED window
-- (the one actually displayed); for a floating window, its own.
local function TabAlphaSource(rec)
  if rec.frame.isDocked and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
    local selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local selRec = selected and Windows.Get(selected)
    if selRec then return UserBackgroundAlpha(selRec) end
  end
  return UserBackgroundAlpha(rec)
end

-- A tab that is transparent takes no mouse. Threshold: anything at or below this alpha is
-- treated as hidden. Stock code calls tab:EnableMouse(true) nowhere after creation, so we own
-- this bit; Phase 2 Chrome state and Phase 3 theme will call Reveal.SetTabInteractive directly.
local TAB_HIDDEN_ALPHA = 0.05

function Reveal.SetTabInteractive(rec, on)
  if not rec.tab then return end
  if rec.tab.vcfMouseOn == on then return end
  rec.tab.vcfMouseOn = on
  rec.tab:EnableMouse(on)
  -- The tab's text FontString and any child buttons do not take mouse on their own; the
  -- Button frame does. Dragging a tab (re-dock) also goes through the tab, so it is off too.
end

-- Wheel reveal: a mouse-wheel turn over a window shows its background and/or tabs. They appear
-- at once and then follow the SAME timing as the chat lines: fully shown for LineFadeSeconds,
-- then fading out over the stock line fade duration. Pointer motion never reveals (Principle 2);
-- the wheel is a deliberate act and is the one input the frame takes at rest.
local wheelRevealedAt = {}       -- rec -> GetTime() of the last wheel turn

local function LineFadeDurationSecs(rec)
  local d = rec.frame.GetFadeDuration and rec.frame:GetFadeDuration()
  return (type(d) == "number" and d > 0) and d or 3
end

local function WheelHoldSecs()
  local secs = Settings.Get().LineFadeSeconds or 15
  if secs <= 0 then secs = 15 end   -- "lines never fade" still needs a finite reveal
  return secs
end

-- Edit Mode: while the Edit Mode manager is shown every window is fully revealed and nothing
-- fades, so the layout you are dragging is the layout you can see.
local function InEditMode()
  local m = EditModeManagerFrame
  if not m then return false end
  if m.IsEditModeActive then return m:IsEditModeActive() end
  return m:IsShown()
end
Reveal.InEditMode = InEditMode

-- 0 = at rest, 1 = fully revealed, in between = fading out. Mirrors
-- ScrollingMessageFrameMixin:CalculateLineAlphaValueFromTimestamp.
local function WheelRevealLevel(rec)
  if InEditMode() then return 1 end
  local t0 = wheelRevealedAt[rec]
  if not t0 then return 0 end
  local age = GetTime() - t0
  local hold = WheelHoldSecs()
  if age <= hold then return 1 end
  local fade = LineFadeDurationSecs(rec)
  if age >= hold + fade then wheelRevealedAt[rec] = nil; return 0 end
  return 1 - (age - hold) / fade
end

-- Revealed background: user colour and alpha (defaults black at 30 % alpha = 30 % opaque).
-- The configured value is for normal/dark zones; on bright terrain (LibZoneBrightness band
-- "bright") RevealBrightZoneBoost is ADDED to the alpha so the text keeps a backing on sand.
local ZB = LibStub and LibStub("LibZoneBrightness-1.0", true)

local function RevealBackgroundRGBA()
  local s = Settings.Get()
  local c = s.RevealBackground or { r = 0, g = 0, b = 0, a = 0.3 }
  local a = c.a or 0.3
  if ZB and ZB:GetBand() == "bright" then
    a = a + (s.RevealBrightZoneBoost or 0.3)
  end
  if a > 1 then a = 1 end
  return c.r or 0, c.g or 0, c.b or 0, a
end

-- Set the texture pieces to the revealed look blended toward the rest look by level (0..1).
-- Only the Background texture is painted. CHAT_FRAME_TEXTURES also holds eight border pieces
-- (corners, Left/Right/Top/Bottom) that sit OUTSIDE the frame rect; painting those at the reveal
-- alpha drew a 16 px dark strip beyond the text on every side and read as a "left gap".
local function ApplyBackgroundLevel(rec, level)
  local restAlpha = UserBackgroundAlpha(rec)
  local r, g, b, revealAlpha = RevealBackgroundRGBA()
  local alpha = restAlpha + (revealAlpha - restAlpha) * level
  for _, tex in ipairs(rec.texturePieces) do
    CancelFade(tex)
    if tex == rec.background then
      if level > 0 and tex.SetVertexColor then tex:SetVertexColor(r, g, b) end
      tex:SetAlpha(alpha)
    else
      -- Border art: stock rest alpha only, never lifted by the reveal. Phase 3 (flat theme)
      -- will hide these outright.
      tex:SetAlpha(restAlpha)
    end
  end
end

-- What every piece of this window should look like at rest. Phase 2 (states) and Phase 3 (theme)
-- will consult NS.State / NS.Theme here; Phase 0 reproduces the stock no-mouse look exactly.
function Reveal.ApplyChrome(rec)
  if not rec then return end
  local s = Settings.Get()
  local level = WheelRevealLevel(rec)
  local editing = InEditMode()
  if s.WheelRevealsBackground or editing then
    ApplyBackgroundLevel(rec, level)
  else
    ApplyBackgroundLevel(rec, 0)
  end

  if rec.tab then
    -- TabsMatchWindowAlpha: every tab in a dock sits at the displayed window's background alpha,
    -- so a near-invisible window has near-invisible tabs. Off = the stock per-tab no-mouse alpha.
    local restTabAlpha
    if s.TabsMatchWindowAlpha then restTabAlpha = TabAlphaSource(rec)
    else restTabAlpha = Client.TabRestAlpha(rec.tab, IsSelectedTab(rec)) end
    local tabAlpha = restTabAlpha
    if (s.WheelRevealsTabs or editing) and level > 0 then
      -- Active tab reveals to full; inactive tabs to half, so the active one reads as the
      -- brightest at a glance (Principle 5: flat tone difference, not a glow).
      local target = IsSelectedTab(rec) and 1 or (s.InactiveTabRevealAlpha or 0.5)
      if target < restTabAlpha then target = restTabAlpha end
      tabAlpha = restTabAlpha + (target - restTabAlpha) * level
    end
    SetAlphaQuiet(rec.tab, tabAlpha)
    Reveal.SetTabInteractive(rec, tabAlpha > TAB_HIDDEN_ALPHA)
  end
  if rec.buttonFrame and not rec.frame.isDocked then
    SetAlphaQuiet(rec.buttonFrame, CHAT_FRAME_BUTTON_FRAME_MIN_ALPHA or 0.2)
  end
  SetAlphaQuiet(rec.scrollBar, 0)
  if rec.scrollToBottom and not (rec.scrollToBottom.Flash and rec.scrollToBottom.Flash.FlashAnim
      and rec.scrollToBottom.Flash.FlashAnim:IsPlaying()) then
    SetAlphaQuiet(rec.scrollToBottom, 0)
  end
  if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.overflowButton then
    SetAlphaQuiet(GENERAL_CHAT_DOCK.overflowButton, CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA or 0.4)
  end
  -- Stock bookkeeping: pretend the frame is faded out so FCF_OnUpdate does not keep re-firing fade-in.
  rec.frame.hasBeenFaded = nil
end

function Reveal.ApplyAll()
  for _, rec in ipairs(Windows.All()) do
    -- Unselected docked windows are HIDDEN (FCF_DockUpdate) but their tabs are shown, so
    -- IsShown() alone skipped exactly the tabs that stayed visible at login.
    if rec.frame:IsShown() or rec.frame.isDocked then Reveal.ApplyChrome(rec) end
  end
end

-- A wheel turn over a window: reveal that window and, if docked, every tab in its dock.
local function DockMates(rec)
  if rec.frame.isDocked and FCFDock_GetChatFrames and GENERAL_CHAT_DOCK then
    local out = {}
    for _, f in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
      local r = Windows.Get(f)
      if r then table.insert(out, r) end
    end
    return out
  end
  return { rec }
end

-- One ticker drives the fade-out for every window that is currently revealed. It runs only
-- while something is fading (hold phase needs no ticks) and stops on its own.
local fadeTicker = nil

local function AnyWheelRevealed()
  for rec, t0 in pairs(wheelRevealedAt) do
    if t0 then return true end
  end
  return false
end

local function FadeTick()
  if not Settings.IsEnabled() then
    if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
    return
  end
  for rec in pairs(wheelRevealedAt) do Reveal.ApplyChrome(rec) end   -- ApplyChrome clears finished ones
  if not AnyWheelRevealed() then
    if fadeTicker then fadeTicker:Cancel(); fadeTicker = nil end
  end
end

local function EnsureFadeTicker(rec)
  -- Sleep through the hold phase, then tick ~20 Hz during the fade.
  local delay = WheelHoldSecs()
  C_Timer.After(delay, function()
    if fadeTicker then return end
    if not AnyWheelRevealed() then return end
    fadeTicker = C_Timer.NewTicker(0.05, FadeTick)
  end)
end

local function OnWheel(frame)
  if not Settings.IsEnabled() then return end
  local s = Settings.Get()
  if not (s.WheelRevealsBackground or s.WheelRevealsTabs) then return end
  local rec = Windows.Get(frame)
  if not rec then return end
  local now = GetTime()
  for _, r in ipairs(DockMates(rec)) do wheelRevealedAt[r] = now; Reveal.ApplyChrome(r) end
  EnsureFadeTicker(rec)
end

local function OnStockFade(chatFrame)
  if not Settings.IsEnabled() then return end
  Reveal.ApplyChrome(Windows.Get(chatFrame))
end

function Reveal.Init()
  if hooked then return end
  hooked = true
  hooksecurefunc("FCF_FadeInChatFrame", OnStockFade)
  hooksecurefunc("FCF_FadeOutChatFrame", OnStockFade)
  -- FCFTab_UpdateAlpha sets the tab alpha directly (dock update, tab select, alert); it runs
  -- after our pass at login, which left background tabs visible until the next re-apply.
  if FCFTab_UpdateAlpha then hooksecurefunc("FCFTab_UpdateAlpha", OnStockFade) end
  if FCFDock_UpdateTabs then hooksecurefunc("FCFDock_UpdateTabs", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end) end
  if FCF_DockUpdate then hooksecurefunc("FCF_DockUpdate", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end) end
  -- Selecting another tab changes which window's alpha the dock's tabs follow.
  if FCFDock_SelectWindow then hooksecurefunc("FCFDock_SelectWindow", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end) end
  -- A window alpha change in the stock menu must re-flow to the tabs too.
  if FCF_SetWindowAlpha then hooksecurefunc("FCF_SetWindowAlpha", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end) end
  local function hookWheel(rec)
    if rec.frame.vcfWheelHooked then return end
    rec.frame.vcfWheelHooked = true
    rec.frame:HookScript("OnMouseWheel", OnWheel)
  end
  for _, rec in ipairs(Windows.All()) do hookWheel(rec) end
  Windows.OnNewRecord(function(rec) hookWheel(rec); if Settings.IsEnabled() then Reveal.ApplyChrome(rec) end end)
  if Settings.IsEnabled() then Reveal.ApplyAll() end
  -- Stock login layout (FCF_DockUpdate, UPDATE_CHAT_WINDOWS) lands after PLAYER_LOGIN; one more
  -- pass on entering world and a frame later catches whatever ran after us.
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("UPDATE_CHAT_WINDOWS")
  f:SetScript("OnEvent", function() if Settings.IsEnabled() then Reveal.ApplyAll(); C_Timer.After(0.5, Reveal.ApplyAll) end end)
  -- Edit Mode enter / exit: reveal everything on enter, back to rest on exit. Line fading is
  -- suspended too (Fading.lua listens to the same hooks) so the text stays put while editing.
  if EditModeManagerFrame and EditModeManagerFrame.HookScript then
    EditModeManagerFrame:HookScript("OnShow", function()
      if Settings.IsEnabled() then Reveal.ApplyAll(); if NS.Fading then NS.Fading.ApplyAll() end end
    end)
    EditModeManagerFrame:HookScript("OnHide", function()
      if Settings.IsEnabled() then Reveal.ApplyAll(); if NS.Fading then NS.Fading.ApplyAll() end end
    end)
  end
end

-- Global disable: hand the look back to the stock code.
function Reveal.Restore()
  for _, rec in ipairs(Windows.All()) do
    Reveal.SetTabInteractive(rec, true)
    if rec.frame:IsShown() and FCF_FadeOutChatFrame then FCF_FadeOutChatFrame(rec.frame) end
  end
end

NS.Settings.OnChange("Enabled", function()
  if Settings.IsEnabled() then Reveal.ApplyAll() else Reveal.Restore() end
end)
NS.Settings.OnChange("TabsMatchWindowAlpha", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)
NS.Settings.OnChange("RevealBackground", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)
NS.Settings.OnChange("RevealBrightZoneBoost", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)
NS.Settings.OnChange("InactiveTabRevealAlpha", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)
-- Zone band changed: a reveal in progress re-reads its alpha on the next tick; nothing to do at rest.
if ZB and ZB.RegisterCallback then
  ZB:RegisterCallback(function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)
end