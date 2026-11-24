-- Velocity Chat Frames: hides the stock chat buttons, one checkbox each. Pattern from Prat
-- Buttons.lua: Hide() and pin an OnShow script that re-hides, so stock code cannot bring them back.
-- With the scroll column hidden its frame is also collapsed to 0.1 px so nothing reserves its strip.
-- How ChatFrame1 presents itself to Edit Mode (Selection box, clamp) lives in Core\EditModeLayout.lua.
local ADDON_NAME, NS = ...
local Settings, Windows = NS.Settings, NS.Windows

local HideButtons = {}
NS.HideButtons = HideButtons

-- Each entry: setting key -> { label, tip, frames = function() -> list of frames }
HideButtons.ITEMS = {
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

-- True while the scroll column is hidden; EditModeLayout reads this to decide its insets.
function HideButtons.IsScrollColumnHidden()
  return Settings.IsEnabled() and Settings.Get().HideScrollButtons and true or false
end

function HideButtons.ApplyAll()
  local s = Settings.Get()
  local on = Settings.IsEnabled()
  for _, item in ipairs(HideButtons.ITEMS) do
    local hide = on and s[item.key]
    for _, f in ipairs(item.frames()) do
      if f then if hide then PinHidden(f) else Unpin(f) end end
    end
  end
  local collapse = HideButtons.IsScrollColumnHidden()
  for _, rec in ipairs(Windows.All()) do
    local bf = rec.buttonFrame
    if bf then
      if bf.vcfStockWidth == nil then bf.vcfStockWidth = bf:GetWidth() end
      if collapse then bf:SetWidth(0.1) else bf:SetWidth(bf.vcfStockWidth > 0 and bf.vcfStockWidth or 29) end
    end
  end
  if collapse and FCF_DockUpdate then FCF_DockUpdate() end
  if NS.EditModeLayout then NS.EditModeLayout.ApplyAll() end
end

function HideButtons.Init()
  Windows.OnNewRecord(function() HideButtons.ApplyAll() end)
  if FCF_SetButtonSide then hooksecurefunc("FCF_SetButtonSide", function() if Settings.IsEnabled() then HideButtons.ApplyAll() end end) end
  HideButtons.ApplyAll()
end

for _, item in ipairs(HideButtons.ITEMS) do Settings.OnChange(item.key, HideButtons.ApplyAll) end
Settings.OnChange("Enabled", HideButtons.ApplyAll)