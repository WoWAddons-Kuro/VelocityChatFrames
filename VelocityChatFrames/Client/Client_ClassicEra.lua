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