-- Velocity Chat Frames: multi-screen drag selection for the window CopyText has put in selection mode.
--
-- Stock ScrollingMessageFrame (ScrollingMessageFrame.lua 383-544) anchors a selection to a VISIBLE SLOT
-- (selectingVisibleLineIndex, 1 = the line nearest the insert edge) and, while selecting, OnPostUpdate skips
-- RefreshIfNecessary, so the viewport is frozen and GatherSelectedText can only read self.visibleLines.
-- Here the anchor is re-based to a MESSAGE INDEX (slot + scrollOffset; historyBuffer index 1 = newest), and
-- the two selection methods are shadowed on the frame instance (CopyText already taints it via SetTextCopyable):
--   UpdateSelectingText  - highlight the on-screen part of the range, anchor clamped to the visible edge
--   GatherSelectedText   - walk historyBuffer over the whole range, on- or off-screen
-- Dragging past the top/bottom edge auto-scrolls (rate ramps with distance); the wheel scrolls during a drag.
local ADDON_NAME, NS = ...

local CopySelect = {}
NS.CopySelect = CopySelect

local EDGE_SCROLL_SLOWEST_SECS = 0.16   -- one line per this many seconds just past the edge
local EDGE_SCROLL_FASTEST_SECS = 0.02   -- one line per this many seconds far past the edge
local EDGE_SCROLL_RAMP_PIXELS  = 300    -- distance past the edge at which the fastest rate is reached
local EDGE_WIGGLE_FULL_PIXELS    = 400  -- accumulated cursor motion (px) that counts as a "full" wiggle
local EDGE_WIGGLE_DECAY_PER_SEC  = 600  -- px of wiggle energy that drains away per second when the cursor is still
local EDGE_WIGGLE_MAX_BOOST      = 0.75 -- a full wiggle cuts the scroll interval by this fraction (4x faster)

-- Slot/line comparisons: visibleLines index grows away from the insert edge, so with BOTTOM insert mode a
-- larger index is higher on screen; with TOP insert mode a larger index is lower. messageIndex = slot +
-- scrollOffset keeps the same ordering, so every comparison below works on either axis.
local function IsTopInsert(frame)
  return frame:GetInsertMode() == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP
end

-- Character index that makes the anchor line select WHOLE when the anchor itself is off-screen. Derived
-- from CalculateSelectingCharacterIndicesForVisibleLine (444-479): for the start line, TOP mode returns
-- startChar..end when the cursor line is beyond it, 1..startChar when before; BOTTOM mode is the mirror.
local function WholeLineAnchorChar(frame, cursorBeyondAnchor, lineText)
  local wantStart = IsTopInsert(frame) == cursorBeyondAnchor
  return wantStart and 1 or (#lineText + 1)
end

-- The mixin's OnPostMouseDown stores a SLOT anchor (selectingVisibleLineIndex / selectingCharacterIndex).
-- Convert it to a message anchor once per drag, lazily, from whichever selection method runs first.
local function EnsureAnchor(frame)
  if frame.vcfAnchorMessageIndex then return true end
  if not frame.selectingVisibleLineIndex then return false end
  frame.vcfAnchorMessageIndex = frame.selectingVisibleLineIndex + frame:GetScrollOffset()
  frame.vcfAnchorCharacterIndex = frame.selectingCharacterIndex
  frame.vcfEdgeScrollNextAt = 0
  return true
end

-- Anchor message index -> visible slot, clamped to the visible range; also the char index to use for it.
local function AnchorSlotForDisplay(frame, cursorSlot)
  local numVisible = frame:GetNumVisibleLines()
  local slot = frame.vcfAnchorMessageIndex - frame:GetScrollOffset()
  if slot >= 1 and slot <= numVisible then return slot, frame.vcfAnchorCharacterIndex end
  local clamped = slot < 1 and 1 or numVisible
  local text = frame.visibleLines[clamped]:GetText() or ""
  return clamped, WholeLineAnchorChar(frame, cursorSlot > clamped, text)
end

-- Shadow of ScrollingMessageFrameMixin:UpdateSelectingText (481-511) with the anchor re-derived per frame.
local function VCF_UpdateSelectingText(self)
  if self.highlightTexturePool then self.highlightTexturePool:ReleaseAll() end
  if not EnsureAnchor(self) then return end
  local x, y = self:GetScaledCursorPosition()
  local cursorChar, cursorSlot = self:FindCharacterAndLineIndexAtCoordinate(x, y)
  if not cursorChar then return end
  local anchorSlot, anchorChar = AnchorSlotForDisplay(self, cursorSlot)
  if anchorSlot == cursorSlot and anchorChar == cursorChar then return end
  for lineIndex = math.min(anchorSlot, cursorSlot), math.max(anchorSlot, cursorSlot) do
    local visibleLine = self.visibleLines[lineIndex]
    if visibleLine and visibleLine:GetText() then
      local s, e = self:CalculateSelectingCharacterIndicesForVisibleLine(lineIndex, anchorSlot, cursorSlot, anchorChar, cursorChar)
      local areas = visibleLine:CalculateScreenAreaFromCharacterSpan(s, e)
      if areas then
        for _, area in ipairs(areas) do
          local tex = self:AcquireHighlightTexture()
          tex:SetPoint("BOTTOMLEFT", visibleLine, "BOTTOMLEFT", area.left, area.bottom)
          tex:SetPoint("TOPRIGHT", visibleLine, "BOTTOMLEFT", area.left + area.width, area.bottom + area.height)
          tex:Show()
        end
      end
    end
  end
end

-- Per-message character span, the message-index twin of CalculateSelectingCharacterIndicesForVisibleLine.
local function MessageSpan(frame, msgIndex, anchorMsg, cursorMsg, anchorChar, cursorChar, text)
  local full = #text + 1
  if msgIndex == anchorMsg and msgIndex == cursorMsg then
    return math.min(anchorChar, cursorChar), math.max(anchorChar, cursorChar)
  end
  local top = IsTopInsert(frame)
  if msgIndex == anchorMsg then
    local beyond = cursorMsg > anchorMsg
    if top == beyond then return anchorChar, full else return 1, anchorChar end
  elseif msgIndex == cursorMsg then
    local beyond = cursorMsg > anchorMsg
    if top == beyond then return 1, cursorChar else return cursorChar, full end
  end
  return 1, full
end

-- Shadow of ScrollingMessageFrameMixin:GatherSelectedText (513-544) reading historyBuffer for the whole range.
local function VCF_GatherSelectedText(self, x, y)
  if not EnsureAnchor(self) then return nil end
  local cursorChar, cursorSlot = self:FindCharacterAndLineIndexAtCoordinate(x, y)
  if not cursorChar then return nil end
  local anchorMsg, anchorChar = self.vcfAnchorMessageIndex, self.vcfAnchorCharacterIndex
  local cursorMsg = cursorSlot + self:GetScrollOffset()
  if anchorMsg == cursorMsg and anchorChar == cursorChar then return nil end
  local endChar = cursorChar - 1
  local lo, hi = math.min(anchorMsg, cursorMsg), math.max(anchorMsg, cursorMsg)
  -- Output oldest line first: TOP mode has index 1 at the top, BOTTOM mode has it at the bottom.
  local first, last, step = hi, lo, -1
  if IsTopInsert(self) then first, last, step = lo, hi, 1 end
  local pending = {}
  for msgIndex = first, last, step do
    local entry = self.historyBuffer:GetEntryAtIndex(msgIndex)
    local text = entry and entry.message
    if text then
      local s, e = MessageSpan(self, msgIndex, anchorMsg, cursorMsg, anchorChar, endChar, text)
      table.insert(pending, text:sub(s, e))
    end
  end
  return table.concat(pending, "\n")
end

-- Mouse-down / up: bracket one drag. HookScript("OnMouseDown") runs BEFORE the mixin's OnPostMouseDown stores
-- its slot anchor, so we cannot convert it here; we only clear ours and let EnsureAnchor (called from the first
-- selection method of the drag) do the conversion.
local function OnMouseDownPost(frame, button)
  if button ~= "LeftButton" then return end
  frame.vcfAnchorMessageIndex, frame.vcfAnchorCharacterIndex = nil, nil
end

local function OnMouseUpPost(frame, button)
  if button ~= "LeftButton" then return end
  frame.vcfAnchorMessageIndex, frame.vcfAnchorCharacterIndex = nil, nil
end

-- Edge auto-scroll while the button is held: past the top -> older lines; past the bottom -> newer.
-- Speed has two inputs: distance past the edge (ramp), and wiggle - recent horizontal/vertical motion of the
-- cursor while it is past the edge. Wiggle is tracked as a decaying "energy": each tick adds the pixels moved
-- since the last tick, then the pool drains at EDGE_WIGGLE_DECAY_PER_SEC. One full wiggle pool shortens the
-- interval by up to EDGE_WIGGLE_MAX_BOOST (fraction of the current interval).
local function OnUpdatePost(frame)
  if not frame:IsSelectingText() or not EnsureAnchor(frame) then return end
  local x, y = frame:GetScaledCursorPosition()
  local top, bottom = frame:GetTop(), frame:GetBottom()
  if not (top and bottom) then return end
  local distance, direction
  if y > top then distance, direction = y - top, 1 elseif y < bottom then distance, direction = bottom - y, -1 else
    frame.vcfWiggleEnergy, frame.vcfWiggleLastX, frame.vcfWiggleLastY = 0, nil, nil
    return
  end
  local now = GetTime()
  -- Wiggle energy: accumulate motion every frame (not only on scroll ticks), drain continuously.
  local lastX, lastY, lastT = frame.vcfWiggleLastX, frame.vcfWiggleLastY, frame.vcfWiggleLastT or now
  local energy = frame.vcfWiggleEnergy or 0
  if lastX then energy = energy + math.abs(x - lastX) + math.abs(y - lastY) end
  energy = math.max(0, energy - EDGE_WIGGLE_DECAY_PER_SEC * (now - lastT))
  energy = math.min(energy, EDGE_WIGGLE_FULL_PIXELS)
  frame.vcfWiggleEnergy, frame.vcfWiggleLastX, frame.vcfWiggleLastY, frame.vcfWiggleLastT = energy, x, y, now
  if now < (frame.vcfEdgeScrollNextAt or 0) then return end
  local ramp = math.min(distance / EDGE_SCROLL_RAMP_PIXELS, 1)
  local interval = EDGE_SCROLL_SLOWEST_SECS - (EDGE_SCROLL_SLOWEST_SECS - EDGE_SCROLL_FASTEST_SECS) * ramp
  local wiggle = energy / EDGE_WIGGLE_FULL_PIXELS
  interval = interval * (1 - EDGE_WIGGLE_MAX_BOOST * wiggle)
  frame.vcfEdgeScrollNextAt = now + interval
  if IsTopInsert(frame) then direction = -direction end   -- TOP mode: older lines are at the top too, but slot 1 is the top
  if direction > 0 then frame:ScrollUp() else frame:ScrollDown() end
  frame:RefreshIfNecessary()
end

-- Wheel during a drag: stock FloatingChatFrame_OnMouseScroll already changed scrollOffset; redraw now
-- because OnPostUpdate will not while selecting.
local function OnMouseWheelPost(frame)
  if frame:IsSelectingText() then frame:RefreshIfNecessary() end
end

function CopySelect.Attach(frame)
  if not (frame.historyBuffer and frame.visibleLines and frame.FindCharacterAndLineIndexAtCoordinate) then return false end
  if not frame.vcfCopySelectHooked then
    frame.vcfCopySelectHooked = true
    frame:HookScript("OnMouseDown", OnMouseDownPost)
    frame:HookScript("OnMouseUp", OnMouseUpPost)
    frame:HookScript("OnUpdate", OnUpdatePost)
    frame:HookScript("OnMouseWheel", OnMouseWheelPost)
  end
  frame.UpdateSelectingText = VCF_UpdateSelectingText
  frame.GatherSelectedText = VCF_GatherSelectedText
  return true
end

function CopySelect.Detach(frame)
  frame.UpdateSelectingText = nil   -- falls back to the mixin method
  frame.GatherSelectedText = nil
  frame.vcfAnchorMessageIndex, frame.vcfAnchorCharacterIndex = nil, nil
end