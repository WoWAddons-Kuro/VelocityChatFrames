-- Velocity Chat Frames: hides the stock chat doohickeys, one checkbox each. Pattern from Prat
-- Buttons.lua: Hide() and pin an OnShow script that re-hides, so stock code cannot bring them back.
local ADDON_NAME, NS = ...
local Settings, Windows = NS.Settings, NS.Windows

local Chrome = {}
NS.Chrome = Chrome

-- Each entry: setting key -> { label, tip, frames = function() -> list of frames }
Chrome.ITEMS = {
  { key = "HideMenuButton",    label = "Hide chat menu button (speech bubble)", tip = "The bubble button at the bottom-left that opens the chat menu.",
    frames = function() return { ChatFrameMenuButton } end },
  { key = "HideSocialButton",  label = "Hide social / quick-join button",      tip = "The friends / quick-join toast button above the chat tabs.",
    frames = function() return { QuickJoinToastButton, FriendsMicroButton } end },
  { key = "HideChannelButton", label = "Hide channel button",                 tip = "The channel list button in the chat button column.",
    frames = function() return { ChatFrameChannelButton } end },
  { key = "HideVoiceButtons",  label = "Hide voice chat buttons",             tip = "The voice mute and deafen buttons.",
    frames = function() return { ChatFrameToggleVoiceDeafenButton, ChatFrameToggleVoiceMuteButton } end },
  { key = "HideScrollButtons", label = "Hide scroll arrows / button column",  tip = "Each window's up / down / to-bottom arrows and the column that holds them. The mouse wheel still scrolls.",
    frames = function()
      local out = {}
      for _, rec in ipairs(Windows.All()) do
        local n = rec.name
        for _, suffix in ipairs({ "ButtonFrameUpButton", "ButtonFrameDownButton", "ButtonFrameBottomButton", "ButtonFrameMinimizeButton" }) do
          if _G[n .. suffix] then table.insert(out, _G[n .. suffix]) end
        end
        if rec.buttonFrame then table.insert(out, rec.buttonFrame) end
      end
      return out
    end },
}

local function PinHidden(f)
  if not f.vcfOrigOnShow then f.vcfOrigOnShow = f:GetScript("OnShow") or false end
  f:SetScript("OnShow", function(self) self:Hide() end)
  f:Hide()
end

local function Unpin(f)
  if f.vcfOrigOnShow == nil then return end
  f:SetScript("OnShow", f.vcfOrigOnShow or nil)
  f.vcfOrigOnShow = nil
  f:Show()
end

function Chrome.ApplyAll()
  local s = Settings.Get()
  local on = Settings.IsEnabled()
  for _, item in ipairs(Chrome.ITEMS) do
    local hide = on and s[item.key]
    for _, f in ipairs(item.frames()) do
      if f then if hide then PinHidden(f) else Unpin(f) end end
    end
  end
  -- With the scroll column hidden, collapse it to zero width AND remove the screen-clamp margin
  -- that Edit Mode reserves for it. EditModeChatFrameSystemTemplate anchors the Selection box
  -- at TOPLEFT x=-32 / BOTTOMRIGHT x=+25, and EditModeSystemMixin:UpdateClampOffsets turns that
  -- into SetClampRectInsets(-32, 25, 60, -32) on ChatFrame1. clampedToScreen then refuses to let
  -- the frame's left edge reach the screen edge: the 32 px for the (now hidden) column stays
  -- reserved. That is why neither Edit Mode nor Unlock could drag the window flush left.
  local collapse = on and s.HideScrollButtons
  for _, rec in ipairs(Windows.All()) do
    local bf = rec.buttonFrame
    if bf then
      if bf.vcfStockWidth == nil then bf.vcfStockWidth = bf:GetWidth() end
      if collapse then bf:SetWidth(0.1) else bf:SetWidth(bf.vcfStockWidth > 0 and bf.vcfStockWidth or 29) end
    end
    Chrome.ApplyClamp(rec, collapse)
  end
  if collapse and FCF_DockUpdate then FCF_DockUpdate() end
end

-- Zero the left/right clamp insets so the window can sit flush with the screen edge. The top
-- inset stays (tabs live above the frame); the bottom stays (edit box below it).
function Chrome.ApplyClamp(rec, collapse)
  local f = rec.frame
  if not f.SetClampRectInsets then return end
  if collapse then
    local _, _, top, bottom = f:GetClampRectInsets()
    f:SetClampRectInsets(0, 0, top or 0, bottom or 0)
  elseif f.UpdateClampOffsets then
    f:UpdateClampOffsets()       -- Edit Mode system: recompute from its Selection box
  else
    f:SetClampRectInsets(0, 0, 0, 0)
  end
end

function Chrome.Init()
  Windows.OnNewRecord(function() Chrome.ApplyAll() end)
  if FCF_SetButtonSide then hooksecurefunc("FCF_SetButtonSide", function() if Settings.IsEnabled() then Chrome.ApplyAll() end end) end
  -- Edit Mode recomputes the clamp from its Selection box on enter, on anchor change and on
  -- exit (UpdateClampOffsets). Re-apply ours after each so the margin never comes back.
  if EditModeSystemMixin and EditModeSystemMixin.UpdateClampOffsets and ChatFrame1 and ChatFrame1.UpdateClampOffsets then
    hooksecurefunc(ChatFrame1, "UpdateClampOffsets", function(frame)
      local rec = Windows.Get(frame)
      if rec and Settings.IsEnabled() and Settings.Get().HideScrollButtons then Chrome.ApplyClamp(rec, true) end
    end)
  end
  Chrome.ApplyAll()
end

for _, item in ipairs(Chrome.ITEMS) do Settings.OnChange(item.key, Chrome.ApplyAll) end
Settings.OnChange("Enabled", Chrome.ApplyAll)