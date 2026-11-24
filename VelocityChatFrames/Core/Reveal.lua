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

-- What every piece of this window should look like at rest. Phase 2 (states) and Phase 3 (theme)
-- will consult NS.State / NS.Theme here; Phase 0 reproduces the stock no-mouse look exactly.
function Reveal.ApplyChrome(rec)
  if not rec then return end
  local bgAlpha = UserBackgroundAlpha(rec)
  for _, tex in ipairs(rec.texturePieces) do SetAlphaQuiet(tex, bgAlpha) end

  if rec.tab then
    -- TabsMatchWindowAlpha: tabs sit at the window's own background alpha, so a near-invisible
    -- window has near-invisible tabs. Off = the stock per-tab no-mouse alpha.
    local tabAlpha = Settings.Get().TabsMatchWindowAlpha and bgAlpha or Client.TabRestAlpha(rec.tab, IsSelectedTab(rec))
    SetAlphaQuiet(rec.tab, tabAlpha)
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
    if rec.frame:IsShown() then Reveal.ApplyChrome(rec) end
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
  if FCF_DockUpdate then hooksecurefunc("FCF_DockUpdate", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end) end
  Windows.OnNewRecord(function(rec) if Settings.IsEnabled() then Reveal.ApplyChrome(rec) end end)
  if Settings.IsEnabled() then Reveal.ApplyAll() end
end

-- Global disable: hand the look back to the stock code.
function Reveal.Restore()
  for _, rec in ipairs(Windows.All()) do
    if rec.frame:IsShown() and FCF_FadeOutChatFrame then FCF_FadeOutChatFrame(rec.frame) end
  end
end

NS.Settings.OnChange("Enabled", function()
  if Settings.IsEnabled() then Reveal.ApplyAll() else Reveal.Restore() end
end)
NS.Settings.OnChange("TabsMatchWindowAlpha", function() if Settings.IsEnabled() then Reveal.ApplyAll() end end)