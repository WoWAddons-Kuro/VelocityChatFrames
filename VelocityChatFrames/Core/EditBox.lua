-- Velocity Chat Frames: one edit box, always ChatFrame1's, at a fixed screen position.
-- Prat Editbox "Free-floating, Locked": the box is anchored to UIParent, not to whichever window
-- happens to be selected. Unlock to drag it; lock saves the position.
local ADDON_NAME, NS = ...
local Settings = NS.Settings

local EditBox = {}
NS.EditBox = EditBox

local function Box() return ChatFrame1EditBox end

local function SavePosition(box)
  local s = Settings.Get()
  s.EditBoxX, s.EditBoxY, s.EditBoxW = box:GetLeft(), box:GetTop(), box:GetWidth()
end

local function StockAnchor(box)
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", box.chatFrame or ChatFrame1, "BOTTOMLEFT", -5, -2)
  if box.chatFrame and box.chatFrame.ScrollBar then box:SetPoint("RIGHT", box.chatFrame.ScrollBar, "RIGHT", 5, 0)
  else box:SetPoint("TOPRIGHT", box.chatFrame or ChatFrame1, "BOTTOMRIGHT", 5, -2) end
end

-- IM chooses a box per window. Share its location, not its channel/recipient state.
local sharedPlacementOriginals = {}
local function ApplySharedPlacement()
  local main, s = Box(), Settings.Get()
  local useMain = Settings.IsEnabled() and s.EditBoxFloat and s.AlwaysMainInputLocation
  for _, rec in ipairs(NS.Windows.All()) do
    local box = rec.frame.editBox or _G[rec.name .. "EditBox"]
    if box and box ~= main then
      if useMain and main:GetLeft() and main:GetTop() then
        if not sharedPlacementOriginals[box] then
          local saved = { points = {}, width = box:GetWidth(), height = box:GetHeight() }
          for i = 1, box:GetNumPoints() do saved.points[i] = { box:GetPoint(i) } end
          sharedPlacementOriginals[box] = saved
        end
        local scale = main:GetEffectiveScale() / box:GetEffectiveScale()
        box:ClearAllPoints()
        box:SetWidth(main:GetWidth() * scale)
        box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", main:GetLeft() * scale, main:GetTop() * scale)
      elseif sharedPlacementOriginals[box] then
        local saved = sharedPlacementOriginals[box]
        sharedPlacementOriginals[box] = nil
        box:ClearAllPoints()
        box:SetSize(saved.width, saved.height)
        for _, point in ipairs(saved.points) do box:SetPoint(unpack(point)) end
      end
    end
  end
end

function EditBox.Apply()
  local box = Box()
  if not box then return end
  local s = Settings.Get()
  if not (Settings.IsEnabled() and s.EditBoxFloat) then
    box:SetMovable(false); box:SetScript("OnDragStart", nil); box:SetScript("OnDragStop", nil)
    if box.vcfFloating then StockAnchor(box); box.vcfFloating = nil end
    ApplySharedPlacement()
    return
  end
  local x = s.EditBoxX or box:GetLeft() or 0
  local y = s.EditBoxY or box:GetTop() or 0
  local w = s.EditBoxW or box:GetWidth() or 300
  if w < 60 then w = 300 end
  box:ClearAllPoints()
  box:SetWidth(w)
  box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  box.vcfFloating = true

  if s.EditBoxLocked then
    box:SetMovable(false); box:RegisterForDrag(); box:SetScript("OnDragStart", nil); box:SetScript("OnDragStop", nil)
  else
    box:SetMovable(true); box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(self) self:StartMoving() end)
    box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self) end)
  end
  ApplySharedPlacement()
end

-- Hide when idle --------------------------------------------------------------------------
-- Why the box "flashed" on a window click: in classic chatStyle the box lives under each window
-- and ChatFrameUtil.SetLastActiveWindow / the click-anywhere button Show() it before our deferred
-- hide ran. Three things fix it:
--   1. chatStyle = "im": one box at a time, owned by the last-active window, never auto-shown by
--      a window click (ChatFrameUtil.lua 577-586).
--   2. The idle look is applied synchronously (no C_Timer.After(0) gap).
--   3. editBox:Show() is pre-hooked: a box without focus stays at alpha 0 / mouse off, so even a
--      stock Show() between frames draws nothing.
local STOCK_CHAT_STYLE = nil      -- captured once so disable can restore it

local function IsActive(box) return box:HasFocus() end

-- Never hide while Edit Mode is open: the box is being placed and must be seen.
local function Hiding()
  if NS.EditModeLayout and NS.EditModeLayout.IsEditing and NS.EditModeLayout.IsEditing() then return false end
  return Settings.IsEnabled() and Settings.Get().EditBoxHideWhenIdle
end

local function SetIdleLook(box)
  if not Hiding() then return end
  if IsActive(box) then return end
  box:SetAlpha(0)
  box:EnableMouse(false)
end

local function SetActiveLook(box)
  box:SetAlpha(1)
  box:EnableMouse(true)
end

local function ApplyChatStyle()
  if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
  if STOCK_CHAT_STYLE == nil then STOCK_CHAT_STYLE = C_CVar.GetCVar("chatStyle") or "classic" end
  if Settings.IsEnabled() and Settings.Get().EditBoxFloat then
    if C_CVar.GetCVar("chatStyle") ~= "im" then C_CVar.SetCVar("chatStyle", "im") end
  else
    if STOCK_CHAT_STYLE and C_CVar.GetCVar("chatStyle") ~= STOCK_CHAT_STYLE then C_CVar.SetCVar("chatStyle", STOCK_CHAT_STYLE) end
  end
  EditBox.ApplyClickAnywhere()
end

-- chatStyle "im" has a side effect that is the exact bug this addon exists to kill: every window
-- whose edit box is not the last-active one shows $parentClickAnywhereButton, a full-size
-- invisible Button that eats left and right click (FCFClickAnywhereButton_UpdateState,
-- FloatingChatFrame.lua 1740; it is gated on the wholeChatWindowClickable CVar). Keep it hidden
-- on every window while VCF is on; the CVar itself is the user's and is not written.
function EditBox.ApplyClickAnywhere()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    local btn = f and f.clickAnywhereButton
    if btn then
      if Settings.IsEnabled() then
        if not btn.vcfPinned then btn.vcfPinned = true; btn:HookScript("OnShow", function(self) if Settings.IsEnabled() then self:Hide() end end) end
        btn:Hide()
      elseif FCFClickAnywhereButton_UpdateState then
        FCFClickAnywhereButton_UpdateState(btn)    -- hand it back to stock
      end
    end
  end
end

function EditBox.ApplyIdle()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local box = _G["ChatFrame" .. i .. "EditBox"]
    if box then
      if Hiding() then SetIdleLook(box) else SetActiveLook(box) end
    end
  end
end

local function HookIdle()
  local onActivate = function(box) if box then EditBox.Apply(); SetActiveLook(box) end end
  local onDeactivate = function(box) if box then SetIdleLook(box) end end
  if ChatFrameUtil and ChatFrameUtil.ActivateChat then hooksecurefunc(ChatFrameUtil, "ActivateChat", onActivate) end
  if ChatFrameUtil and ChatFrameUtil.DeactivateChat then hooksecurefunc(ChatFrameUtil, "DeactivateChat", onDeactivate) end
  if ChatEdit_ActivateChat then hooksecurefunc("ChatEdit_ActivateChat", onActivate) end
  if ChatEdit_DeactivateChat then hooksecurefunc("ChatEdit_DeactivateChat", onDeactivate) end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local box = _G["ChatFrame" .. i .. "EditBox"]
    if box then
      if box.Deactivate then hooksecurefunc(box, "Deactivate", onDeactivate) end
      box:HookScript("OnEditFocusGained", onActivate)
      box:HookScript("OnEditFocusLost", onDeactivate)
      -- Stock Show() on an unfocused box (SetLastActiveWindow, click-anywhere) must not draw.
      box:HookScript("OnShow", function(self) if not IsActive(self) then SetIdleLook(self) end end)
    end
  end
end

-- Stock code re-anchors the box when the selected tab changes (ChatFrameUtil.SetLastActiveWindow,
-- FCF_SetButtonSide / FCF_DockUpdate). Re-apply after each.
-- Reposition only an edit box actually opened by a player-link click. Keep Blizzard's
-- chosen edit box and recipient; restore its previous anchors when focus leaves.
local usernamePlacements = {}

local function RestoreUsernamePlacement(box)
  local saved = usernamePlacements[box]
  if not saved then return end
  usernamePlacements[box] = nil
  box:ClearAllPoints()
  box:SetSize(saved.width, saved.height)
  for _, point in ipairs(saved.points) do box:SetPoint(unpack(point)) end
end

function EditBox.InitUsernamePlacement()
  local function attach(rec)
    local frame = rec.frame
    frame:HookScript("OnHyperlinkClick", function(source, link, _, button)
      if not Settings.IsEnabled() or button ~= "LeftButton" or NS.Util.IsSecret(link) then return end
      if type(link) ~= "string" or not (link:match("^player:") or link:match("^BNplayer:")) then return end
      -- Modified clicks can insert links or perform other actions; leave them stock.
      if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then return end
      local box = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
      if not box or not box:HasFocus() then return end
      RestoreUsernamePlacement(box)
      local s = Settings.Get()
      if s.AlwaysMainInputLocation and s.EditBoxFloat then EditBox.Apply(); return end
      local main = Box()
      local left, top, width
      if s.UsernameInputPlacement == "main" and main then
        -- Convert between effective scales for a secondary window's edit box.
        local scale = main:GetEffectiveScale() / box:GetEffectiveScale()
        left, top, width = main:GetLeft(), main:GetTop(), main:GetWidth()
        if not left or not top then return end
        if s.EditBoxFloat then left, top, width = s.EditBoxX or left, s.EditBoxY or top, s.EditBoxW or width end
        left, top, width = left * scale, top * scale, width * scale
      end
      local saved = { points = {}, width = box:GetWidth(), height = box:GetHeight() }
      for i = 1, box:GetNumPoints() do saved.points[i] = { box:GetPoint(i) } end
      usernamePlacements[box] = saved
      if not box.vcfUsernameFocusHook then
        box.vcfUsernameFocusHook = true
        box:HookScript("OnEditFocusLost", RestoreUsernamePlacement)
      end
      box:ClearAllPoints()
      if left then
        box:SetWidth(width)
        box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      else
        box:SetPoint("TOPLEFT", source, "BOTTOMLEFT", -5, -2)
        box:SetPoint("TOPRIGHT", source, "BOTTOMRIGHT", 5, -2)
      end
    end)
  end
  for _, rec in ipairs(NS.Windows.All()) do attach(rec) end
  NS.Windows.OnNewRecord(attach)
  Settings.OnChange("Enabled", function()
    if not Settings.IsEnabled() then
      for box in pairs(usernamePlacements) do RestoreUsernamePlacement(box) end
    end
  end)
end

function EditBox.Init()
  EditBox.InitUsernamePlacement()
  ApplyChatStyle()
  HookIdle()
  EditBox.ApplyIdle()
  if ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow then hooksecurefunc(ChatFrameUtil, "SetLastActiveWindow", EditBox.Apply) end
  if ChatEdit_SetLastActiveWindow then hooksecurefunc("ChatEdit_SetLastActiveWindow", EditBox.Apply) end
  if FCF_DockUpdate then hooksecurefunc("FCF_DockUpdate", EditBox.Apply) end
  if FCF_SetButtonSide then hooksecurefunc("FCF_SetButtonSide", EditBox.Apply) end
  -- Stock re-evaluates the click-anywhere buttons on every last-active change and CVAR_UPDATE.
  if FCFClickAnywhereButton_UpdateState then hooksecurefunc("FCFClickAnywhereButton_UpdateState", function() if Settings.IsEnabled() then EditBox.ApplyClickAnywhere() end end) end
  EditBox.ApplyClickAnywhere()
  EditBox.Apply()
end

for _, k in ipairs({ "Enabled", "EditBoxFloat", "EditBoxLocked" }) do Settings.OnChange(k, function() ApplyChatStyle(); EditBox.Apply() end) end
Settings.OnChange("AlwaysMainInputLocation", EditBox.Apply)
for _, k in ipairs({ "Enabled", "EditBoxHideWhenIdle" }) do Settings.OnChange(k, EditBox.ApplyIdle) end