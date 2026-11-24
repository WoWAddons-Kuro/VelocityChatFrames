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

-- Wheel reveal: a mouse-wheel turn over a window shows its background and/or tabs for
-- WHEEL_REVEAL_SECS, then they return to rest. Pointer motion never reveals (Principle 2);
-- the wheel is a deliberate act and is the one input the frame takes at rest.
local WHEEL_REVEAL_SECS = 3
local WHEEL_REVEAL_ALPHA = 1.0
local wheelRevealedUntil = {}    -- rec -> GetTime() deadline

local function IsWheelRevealed(rec)
  local t = wheelRevealedUntil[rec]
  return t and t > GetTime()
end

-- What every piece of this window should look like at rest. Phase 2 (states) and Phase 3 (theme)
-- will consult NS.State / NS.Theme here; Phase 0 reproduces the stock no-mouse look exactly.
function Reveal.ApplyChrome(rec)
  if not rec then return end
  local s = Settings.Get()
  local revealed = IsWheelRevealed(rec)
  local bgAlpha = (revealed and s.WheelRevealsBackground) and WHEEL_REVEAL_ALPHA or UserBackgroundAlpha(rec)
  for _, tex in ipairs(rec.texturePieces) do SetAlphaQuiet(tex, bgAlpha) end

  if rec.tab then
    -- TabsMatchWindowAlpha: every tab in a dock sits at the displayed window's background alpha,
    -- so a near-invisible window has near-invisible tabs. Off = the stock per-tab no-mouse alpha.
    local tabAlpha
    if revealed and s.WheelRevealsTabs then tabAlpha = WHEEL_REVEAL_ALPHA
    elseif s.TabsMatchWindowAlpha then tabAlpha = TabAlphaSource(rec)
    else tabAlpha = Client.TabRestAlpha(rec.tab, IsSelectedTab(rec)) end
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
  Windows.OnNewRecord(function(rec) if Settings.IsEnabled() then Reveal.ApplyChrome(rec) end end)
  if Settings.IsEnabled() then Reveal.ApplyAll() end
  -- Stock login layout (FCF_DockUpdate, UPDATE_CHAT_WINDOWS) lands after PLAYER_LOGIN; one more
  -- pass on entering world and a frame later catches whatever ran after us.
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("UPDATE_CHAT_WINDOWS")
  f:SetScript("OnEvent", function() if Settings.IsEnabled() then Reveal.ApplyAll(); C_Timer.After(0.5, Reveal.ApplyAll) end end)
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