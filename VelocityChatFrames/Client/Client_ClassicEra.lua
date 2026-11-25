-- Velocity Chat Frames: Classic Era (1.15.x).
local ADDON_NAME, NS = ...

local impl = {}
NS.ClientFlavours.classic_era = impl

function impl.PlayerKey() return UnitGUID("player") end
function impl.PlayerDisplayName() return UnitName("player") end
function impl.PlayerFirstName() return UnitName("player") end
-- Whispers cannot cross realms on Era, so the shared journal is per realm.
function impl.WhisperScopeKey() return "realm:" .. ((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?") end


function impl.TabRestAlpha(tab, isSelected)
  if ChatFrameUtil and ChatFrameUtil.GetTabAlphas then
    local _, noMouse = ChatFrameUtil.GetTabAlphas(tab)
    if noMouse then return noMouse end
  end
  if tab and tab.noMouseAlpha then return tab.noMouseAlpha end
  return isSelected and CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA or CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA
end

-- Era: scroll arrows live in ChatFrameNButtonFrame, but the minimize button is a child of the chat
-- frame itself (FloatingChatFrameMinimizeButtonMixin:OnLoad uses self:GetParent() as the chat frame).
local ERA_BUTTON_SUFFIXES = { "ButtonFrameUpButton", "ButtonFrameDownButton", "ButtonFrameBottomButton", "MinimizeButton" }
function impl.ScrollColumnButtons(chatFrameName)
  local out = {}
  for _, suffix in ipairs(ERA_BUTTON_SUFFIXES) do
    local f = _G[chatFrameName .. suffix]; if f then table.insert(out, f) end
  end
  return out
end

-- Era 1.15.x ships the same live ScrollingMessageFrame.lua (byte-identical, see 00_Overview), so the
-- motion-propagation API is present too. Feature-detected in case a build drops it.
function impl.CanSenseHover()
  return ChatFrame1 ~= nil and ChatFrame1.SetPropagateMouseMotion ~= nil
end

function impl.SetHoverSensing(frame, on)
  if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(on) end
  if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(on) end
end

-- Era: ScrollingMessageFrameMixin:SetFadeDuration (ScrollingMessageFrame.lua 278).
function impl.SetLineFadeDuration(frame, secs)
  if frame.SetFadeDuration then frame:SetFadeDuration(secs) end
end