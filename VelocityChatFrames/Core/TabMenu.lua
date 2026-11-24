-- Velocity Chat Frames: our items on the chat tab right-click menu (Menu.ModifyMenu "MENU_FCF_TAB").
--
--   Unlock Window / Lock Window   for ChatFrame1 (General). Stock locks it permanently and hands
--                                 position to Edit Mode (PrimaryChatFrameMixin:OnLoad, FCF_SetLocked(self, true)).
--                                 We make the frame movable by its tab while unlocked and remember the
--                                 position ourselves; Edit Mode keeps owning it otherwise.
--   Frame Fade Settings...        opens the VCF options panel.
--   Enable Selection              lives in Core\CopyText.lua and is added there.
local ADDON_NAME, NS = ...
local Util, Settings = NS.Util, NS.Settings

local TabMenu = {}
NS.TabMenu = TabMenu

local VCF_PrimaryUnlocked = false

local function Primary() return DEFAULT_CHAT_FRAME or ChatFrame1 end
local function PrimaryTab() local f = Primary(); return f and _G[f:GetName() .. "Tab"] end

local function SavePrimaryPosition()
  local f = Primary()
  local s = Settings.Get()
  s.PrimaryWindowX, s.PrimaryWindowY = f:GetLeft(), f:GetBottom()
  s.PrimaryWindowW, s.PrimaryWindowH = f:GetWidth(), f:GetHeight()
end

-- Re-place the General window where we last left it. Only when we have a saved spot.
function TabMenu.RestorePrimaryPosition()
  local s = Settings.Get()
  if not (Settings.IsEnabled() and s.PrimaryWindowX) then return end
  local f = Primary()
  if not f or (InCombatLockdown and InCombatLockdown()) then return end
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.PrimaryWindowX, s.PrimaryWindowY)
  if s.PrimaryWindowW and s.PrimaryWindowH then f:SetSize(s.PrimaryWindowW, s.PrimaryWindowH) end
  if FCF_DockUpdate then FCF_DockUpdate() end
end

local function OnTabDragStart(tab)
  if not VCF_PrimaryUnlocked then return end
  local f = Primary()
  f:SetMovable(true)
  f:StartMoving()
  tab.vcfDragging = true
end

local function OnTabDragStop(tab)
  if not tab.vcfDragging then return end
  tab.vcfDragging = nil
  local f = Primary()
  f:StopMovingOrSizing()
  SavePrimaryPosition()
  if FCF_DockUpdate then FCF_DockUpdate() end
  if NS.EditBox and NS.EditBox.Apply then NS.EditBox.Apply() end
end

function TabMenu.SetPrimaryUnlocked(on)
  VCF_PrimaryUnlocked = on and true or false
  local f, tab = Primary(), PrimaryTab()
  if not (f and tab) then return end
  f:SetMovable(VCF_PrimaryUnlocked)
  if VCF_PrimaryUnlocked then
    tab:RegisterForDrag("LeftButton")
    if not tab.vcfDragHooked then
      tab.vcfDragHooked = true
      tab:HookScript("OnDragStart", OnTabDragStart)
      tab:HookScript("OnDragStop", OnTabDragStop)
    end
    -- The tab must take mouse to be dragged, whatever its alpha.
    tab:EnableMouse(true)
    tab.vcfMouseOn = true
    Util.Print("General window unlocked: drag it by its tab. Lock again from the tab menu.")
  else
    if tab.vcfDragging then OnTabDragStop(tab) end
    if NS.Reveal then NS.Reveal.ApplyAll() end
  end
end

function TabMenu.IsPrimaryUnlocked() return VCF_PrimaryUnlocked end

function TabMenu.Init()
  if not (Menu and Menu.ModifyMenu) then
    Util.WarnOnce("tabmenu", "Menu.ModifyMenu not available; tab menu items disabled")
    return
  end
  Menu.ModifyMenu("MENU_FCF_TAB", function(owner, rootDescription)
    if not Settings.IsEnabled() then return end
    local frame = (FCF_GetChatFrameByID and FCF_GetChatFrameByID(owner:GetID())) or _G["ChatFrame" .. owner:GetID()]
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("Velocity Chat Frames")
    if frame == Primary() then
      local label = VCF_PrimaryUnlocked and (LOCK_WINDOW or "Lock Window") or (UNLOCK_WINDOW or "Unlock Window")
      rootDescription:CreateButton(label, function() TabMenu.SetPrimaryUnlocked(not VCF_PrimaryUnlocked) end)
    end
    rootDescription:CreateButton("Frame Fade Settings...", function() if NS.Options then NS.Options.Open() end end)
  end)

  -- Stock layout re-places ChatFrame1 during login; put ours back once after entering world.
  -- Edit Mode itself reads the frame's current anchors when opened (owner-verified 2026-11-23),
  -- so a drag here simply becomes the position Edit Mode works from; no re-apply after it closes.
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function() C_Timer.After(1, TabMenu.RestorePrimaryPosition) end)
end