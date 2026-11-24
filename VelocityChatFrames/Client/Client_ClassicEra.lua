-- Velocity Chat Frames: Classic Era (1.15.x).
local ADDON_NAME, NS = ...

local impl = {}
NS.ClientFlavours.classic_era = impl

function impl.PlayerKey() return UnitGUID("player") end
function impl.PlayerDisplayName() return UnitName("player") end
function impl.PlayerFirstName() return UnitName("player") end

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