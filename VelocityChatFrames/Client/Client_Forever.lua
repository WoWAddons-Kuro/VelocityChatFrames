-- Velocity Chat Frames: WoW Forever (Mainline-shaped UI, 16001).
local ADDON_NAME, NS = ...

local impl = {}
NS.ClientFlavours.forever = impl

function impl.PlayerKey() return UnitGUID("player") end

function impl.PlayerDisplayName()
  local name, surname = UnitNameUnmodified("player")
  if surname and surname ~= "" then return name .. " " .. surname end
  return name
end

function impl.PlayerFirstName() return UnitName("player") end

-- Mainline stores per-tab alphas; GetTabAlphas returns mouseOver, noMouse.
function impl.TabRestAlpha(tab, isSelected)
  if ChatFrameUtil and ChatFrameUtil.GetTabAlphas then
    local _, noMouse = ChatFrameUtil.GetTabAlphas(tab)
    if noMouse then return noMouse end
  end
  return isSelected and CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA or CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA
end