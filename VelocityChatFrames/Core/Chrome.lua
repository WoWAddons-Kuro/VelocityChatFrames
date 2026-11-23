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
end

function Chrome.Init()
  Windows.OnNewRecord(function() Chrome.ApplyAll() end)
  if FCF_SetButtonSide then hooksecurefunc("FCF_SetButtonSide", function() if Settings.IsEnabled() then Chrome.ApplyAll() end end) end
  Chrome.ApplyAll()
end

for _, item in ipairs(Chrome.ITEMS) do Settings.OnChange(item.key, Chrome.ApplyAll) end
Settings.OnChange("Enabled", Chrome.ApplyAll)