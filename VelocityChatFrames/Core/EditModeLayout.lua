-- Velocity Chat Frames: how the chat frames present themselves to the game's Edit Mode.
--
-- One home for every Edit Mode interaction so it is not sprinkled across modules:
--   * ChatFrame1's Selection box and screen clamp when the button column is hidden (the "gutter")
--   * (next) a drag frame for the floating edit box while Edit Mode is open
--   * (next) drag frames for floating chat windows 2..N, which stock Edit Mode ignores
--   * (parked) VCF owning ChatFrame1's position/size outright instead of Edit Mode
--
-- Ground truth: _ref\blizzard\forever\EditMode\EditModeSystemTemplates.lua and the
-- EditModeChatFrameSystemTemplate in EditModeSystemTemplates.xml (Selection at TOPLEFT x=-32 y=+60,
-- BOTTOMRIGHT x=+25 y=-32; EditModeSystemMixin:UpdateClampOffsets derives SetClampRectInsets from it).
local ADDON_NAME, NS = ...
local Settings, Windows = NS.Settings, NS.Windows

local EditModeLayout = {}
NS.EditModeLayout = EditModeLayout

local function ColumnHidden()
  return NS.HideButtons and NS.HideButtons.IsScrollColumnHidden() or false
end

-- The "gutter": the Selection box (what the player drags in Edit Mode) extends 32 px left of the
-- frame for the button column. Edit Mode positions and saves the FRAME; drag the box flush left and
-- the frame lands 32 px in, and reload restores exactly that. Nothing occupies the strip. With the
-- column hidden we re-anchor the Selection to the frame's real horizontal edges, so the box IS the
-- frame and UpdateClampOffsets (derived from the Selection) follows for free.
function EditModeLayout.ApplySelectionInsets(rec, collapse)
  local f = rec.frame
  local sel = f.Selection
  if not sel then return end
  if sel.vcfStockPoints == nil then
    sel.vcfStockPoints = {}
    for i = 1, sel:GetNumPoints() do sel.vcfStockPoints[i] = { sel:GetPoint(i) } end
  end
  sel:ClearAllPoints()
  if collapse then
    -- keep the vertical slack (tabs above, edit box below); kill the horizontal slack
    sel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 60)
    sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -32)
  else
    for _, p in ipairs(sel.vcfStockPoints) do sel:SetPoint(unpack(p)) end
  end
  if f.UpdateClampOffsets then f:UpdateClampOffsets() end
end

-- Frames without a Selection (floating windows are not Edit Mode systems): zero the horizontal
-- clamp insets directly so they too can sit flush with the screen edge.
function EditModeLayout.ApplyClamp(rec, collapse)
  local f = rec.frame
  if f.Selection then EditModeLayout.ApplySelectionInsets(rec, collapse); return end
  if not f.SetClampRectInsets then return end
  if collapse then
    local _, _, top, bottom = f:GetClampRectInsets()
    f:SetClampRectInsets(0, 0, top or 0, bottom or 0)
  else
    f:SetClampRectInsets(0, 0, 0, 0)
  end
end

function EditModeLayout.ApplyAll()
  local collapse = ColumnHidden()
  for _, rec in ipairs(Windows.All()) do EditModeLayout.ApplyClamp(rec, collapse) end
end

-- LibEditMode placeholders ---------------------------------------------------------------
-- Stock Edit Mode only gives ChatFrame1 a drag box. For the floating edit box and for floating
-- chat windows 2..N we register a UIParent-parented placeholder with LibEditMode (pattern:
-- VelocityQuestTracker\UI\EditMode.lua). The placeholder is what Edit Mode moves; the live frame
-- follows it during the drag and on drop. Placement is read from / written to the same settings
-- the frames already use (EditBoxX/Y/W; FCF_SavePositionAndDimensions for floating windows), so
-- nothing new is persisted.
local lib                       -- LibEditMode, resolved in Init
local VCF_EditBoxPlaceholder    -- one, for ChatFrame1EditBox
local VCF_WindowPlaceholders = {}  -- rec -> placeholder, for floating chat windows
local editing = false

local function MakePlaceholder(globalName, label, w, h)
  local ph = CreateFrame("Frame", globalName, UIParent)
  ph:SetFrameStrata("HIGH")
  ph:SetClampedToScreen(true)
  ph:SetMovable(true)
  ph:SetSize(w, h)
  ph:Hide()
  local bg = ph:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
  local text = ph:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("CENTER"); text:SetText(label)
  ph.label = text
  return ph
end

-- Live-follow while dragging: the placeholder's OnUpdate copies its rect onto the live frame.
local function WireFollow(ph, onMove)
  local selection = lib.frameSelections and lib.frameSelections[ph]
  if not selection then return end
  selection:HookScript("OnDragStart", function() ph:SetScript("OnUpdate", function() onMove(ph, true) end) end)
  selection:HookScript("OnDragStop", function() ph:SetScript("OnUpdate", nil); onMove(ph, false) end)
end

-- Edit box --------------------------------------------------------------------------------
local function EditBoxFrame() return ChatFrame1EditBox end

local function MoveEditBoxTo(ph, live)
  local box = EditBoxFrame()
  if not box then return end
  local left, top, w = ph:GetLeft(), ph:GetTop(), ph:GetWidth()
  if not (left and top) then return end
  box:ClearAllPoints()
  box:SetWidth(w)
  box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  if not live then
    local s = Settings.Get()
    s.EditBoxX, s.EditBoxY, s.EditBoxW = left, top, w
    s.EditBoxFloat = true          -- a placed box is a floating box
    if NS.EditBox and NS.EditBox.Apply then NS.EditBox.Apply() end
  end
end

local function EnsureEditBoxPlaceholder()
  if VCF_EditBoxPlaceholder then return VCF_EditBoxPlaceholder end
  local box = EditBoxFrame()
  local w, h = (box and box:GetWidth()) or 300, (box and box:GetHeight()) or 32
  VCF_EditBoxPlaceholder = MakePlaceholder("VelocityChatFramesEditBoxPlaceholder", "Chat Input Box", w, h)
  lib:AddFrame(VCF_EditBoxPlaceholder, function(ph) MoveEditBoxTo(ph, false) end,
    { point = "TOPLEFT", x = 32, y = -600 }, "Chat Input Box")
  WireFollow(VCF_EditBoxPlaceholder, MoveEditBoxTo)
  return VCF_EditBoxPlaceholder
end

-- Floating chat windows 2..N ---------------------------------------------------------------
local function MoveWindowTo(ph, live)
  local rec = ph.vcfRec
  if not rec then return end
  local f = rec.frame
  local left, bottom, w, h = ph:GetLeft(), ph:GetBottom(), ph:GetWidth(), ph:GetHeight()
  if not (left and bottom) then return end
  f:ClearAllPoints()
  f:SetSize(w, h)
  f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
  if not live then
    f:SetUserPlaced(true)
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(f) end   -- stock persistence for floating windows
    if FCF_DockUpdate then FCF_DockUpdate() end
  end
end

local function EnsureWindowPlaceholder(rec)
  if VCF_WindowPlaceholders[rec] then return VCF_WindowPlaceholders[rec] end
  local f = rec.frame
  local ph = MakePlaceholder("VelocityChatFramesWindowPlaceholder" .. rec.id, f.name or rec.name, f:GetWidth(), f:GetHeight())
  ph.vcfRec = rec
  lib:AddFrame(ph, function(p) MoveWindowTo(p, false) end, { point = "BOTTOMLEFT", x = 100, y = 100 }, f.name or rec.name)
  WireFollow(ph, MoveWindowTo)
  VCF_WindowPlaceholders[rec] = ph
  return ph
end

local function IsFloatingWindow(rec)
  return rec.frame ~= DEFAULT_CHAT_FRAME and not rec.frame.isDocked and rec.frame:IsShown()
end

-- Enter / exit ----------------------------------------------------------------------------
local function OnEnter()
  editing = true
  if not Settings.IsEnabled() then return end
  -- Edit box: show it and park the placeholder on it.
  local box = EditBoxFrame()
  if box then
    local ph = EnsureEditBoxPlaceholder()
    box:SetAlpha(1); box:EnableMouse(false)   -- visible, but the placeholder takes the mouse
    ph:SetSize(box:GetWidth(), box:GetHeight())
    ph:ClearAllPoints()
    ph:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", box:GetLeft() or 0, box:GetTop() or 0)
    ph:Show()
  end
  -- Floating windows: one placeholder each, sized and placed on the window.
  for _, rec in ipairs(Windows.All()) do
    if IsFloatingWindow(rec) then
      local ph = EnsureWindowPlaceholder(rec)
      ph.label:SetText(rec.frame.name or rec.name)
      ph:SetSize(rec.frame:GetWidth(), rec.frame:GetHeight())
      ph:ClearAllPoints()
      ph:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rec.frame:GetLeft() or 0, rec.frame:GetBottom() or 0)
      ph:Show()
    elseif VCF_WindowPlaceholders[rec] then
      VCF_WindowPlaceholders[rec]:Hide()
    end
  end
end

local function OnExit()
  editing = false
  if VCF_EditBoxPlaceholder then VCF_EditBoxPlaceholder:Hide() end
  for _, ph in pairs(VCF_WindowPlaceholders) do ph:Hide() end
  if NS.EditBox then
    if NS.EditBox.Apply then NS.EditBox.Apply() end
    if NS.EditBox.ApplyIdle then NS.EditBox.ApplyIdle() end   -- back to hidden-when-idle
  end
end

function EditModeLayout.IsEditing() return editing end

function EditModeLayout.Init()
  -- Edit Mode may re-anchor the Selection on enter (AnchorSelectionFrame); re-apply ours after.
  if ChatFrame1 and ChatFrame1.AnchorSelectionFrame then
    hooksecurefunc(ChatFrame1, "AnchorSelectionFrame", function(frame)
      local rec = Windows.Get(frame)
      if rec and ColumnHidden() then EditModeLayout.ApplySelectionInsets(rec, true) end
    end)
  end
  lib = LibStub and LibStub("LibEditMode", true)
  if lib and type(lib.AddFrame) == "function" and type(lib.RegisterCallback) == "function" then
    lib:RegisterCallback("enter", OnEnter)
    lib:RegisterCallback("exit", OnExit)
  else
    NS.Util.WarnOnce("libeditmode", "LibEditMode not found; edit box and floating windows have no Edit Mode drag frames")
  end
  EditModeLayout.ApplyAll()
end