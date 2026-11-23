-- Velocity Chat Frames: drag-select text straight in the chat window, temporarily.
-- ScrollingMessageFrame has SetTextCopyable(bool): with it on, left-drag highlights lines and
-- mouse-up puts the plain text on the clipboard (ScrollingMessageFrame.lua 308, 383-410).
-- No overlay window needed; wrapping is the real wrapping. Entered from the tab menu
-- (Menu.ModifyMenu on tag "MENU_FCF_TAB", FloatingChatFrame.lua 381) and ends on its own
-- after SELECTION_IDLE_SECS without the mouse touching the window.
local ADDON_NAME, NS = ...
local Util, Settings, Windows = NS.Util, NS.Settings, NS.Windows

local CopyText = {}
NS.CopyText = CopyText

CopyText.SELECTION_IDLE_SECS = 10

local activeFrame = nil          -- the one window currently in selection mode
local idleTimer = nil            -- C_Timer handle for the timeout
local lastTouch = 0              -- GetTime() of the last mouse interaction

local function IsOn(frame) return frame == activeFrame end

local function CancelTimer()
  if idleTimer then idleTimer:Cancel(); idleTimer = nil end
end

local function Touch()
  lastTouch = GetTime()
end

local function OnIdleTick()
  idleTimer = nil
  if not activeFrame then return end
  local frame = activeFrame
  -- a drag in progress counts as interaction
  if frame.IsSelectingText and frame:IsSelectingText() then Touch() end
  if frame:IsMouseOver() then Touch() end
  local idle = GetTime() - lastTouch
  if idle >= CopyText.SELECTION_IDLE_SECS then
    CopyText.End("idle")
  else
    idleTimer = C_Timer.NewTimer(CopyText.SELECTION_IDLE_SECS - idle + 0.1, OnIdleTick)
  end
end

local function HookTouch(frame)
  if frame.vcfTouchHooked then return end
  frame.vcfTouchHooked = true
  frame:HookScript("OnMouseDown", Touch)
  -- OnMouseUp must run BEFORE the stock handler (which would call protected CopyToClipboard),
  -- so wrap the existing script rather than HookScript (which runs after).
  local orig = frame:GetScript("OnMouseUp")
  frame:SetScript("OnMouseUp", function(self, button)
    Touch()
    OnMouseUpPre(self, button)
    if orig then orig(self, button) end
  end)
  frame:HookScript("OnMouseWheel", Touch)
  frame:HookScript("OnEnter", Touch)
end

function CopyText.Begin(frame)
  if not frame or not frame.SetTextCopyable then return end
  if activeFrame and activeFrame ~= frame then CopyText.End("switched") end
  activeFrame = frame
  HookTouch(frame)
  frame:SetTextCopyable(true)
  -- Selection needs clicks; Phase 2 Rest turns them off, so force on while selecting.
  frame:EnableMouse(true)
  if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
  frame:SetFading(false)
  HoldFocus()
  Touch()
  CancelTimer()
  idleTimer = C_Timer.NewTimer(CopyText.SELECTION_IDLE_SECS + 0.1, OnIdleTick)
  ShowToast(frame, string.format("selection on: drag, then Ctrl+C. Esc or %ds idle ends it", CopyText.SELECTION_IDLE_SECS))
end

function CopyText.End(reason)
  CancelTimer()
  local frame = activeFrame
  activeFrame = nil
  if not frame then return end
  ReleaseFocus()
  frame:SetTextCopyable(false)
  local rec = Windows.Get(frame)
  if NS.Fading then NS.Fading.ApplyRest(rec or { frame = frame, isCombatLog = false }) end
  if NS.Reveal and rec then NS.Reveal.ApplyChrome(rec) end
  ShowToast(frame, "selection off")
end

function CopyText.Toggle(frame)
  if IsOn(frame) then CopyText.End("menu") else CopyText.Begin(frame) end
end

-- Toast: a small label centred in the chat window, shown for a moment after each copy.
local TOAST_SECS = 1.5

local function GetToast(frame)
  if frame.vcfCopyToast then return frame.vcfCopyToast end
  local toast = CreateFrame("Frame", nil, frame)
  toast:SetFrameStrata("TOOLTIP")
  toast:SetPoint("CENTER", frame, "CENTER", 0, 0)
  toast:SetSize(220, 28)
  toast:EnableMouse(false)
  local bg = toast:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(toast)
  bg:SetColorTexture(0, 0, 0, 0.75)
  local text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("CENTER")
  toast.text = text
  toast:Hide()
  frame.vcfCopyToast = toast
  return toast
end

local function ShowToast(frame, msg)
  local toast = GetToast(frame)
  toast.text:SetText(msg)
  toast:SetWidth(math.max(140, toast.text:GetStringWidth() + 24))
  toast:SetAlpha(1)
  toast:Show()
  if toast.hideTimer then toast.hideTimer:Cancel() end
  toast.hideTimer = C_Timer.NewTimer(TOAST_SECS, function()
    UIFrameFadeOut(toast, 0.4, 1, 0)
    C_Timer.After(0.45, function() toast:Hide() end)
  end)
end

-- Clipboard ---------------------------------------------------------------------------------
-- CopyToClipboard() is a protected API: addons cannot call it, and because our SetTextCopyable
-- call taints the frame, the stock OnPostMouseUp path is forbidden too (ADDON_ACTION_FORBIDDEN).
-- The only clipboard route open to addons is an EditBox with focus + Ctrl+C. So for the whole
-- selection session an invisible EditBox holds keyboard focus; each drag release puts the
-- selected text in it and highlights it, so Ctrl+C at any moment copies the last selection.
-- While the session is on, keys go to that box (you cannot move); Escape ends the session.
local VCF_CopyEditBox

local function GetCopyBox()
  if VCF_CopyEditBox then return VCF_CopyEditBox end
  local box = CreateFrame("EditBox", "VelocityChatFramesCopyBox", UIParent)
  box:SetSize(1, 1)
  box:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)   -- off screen
  box:SetAutoFocus(false)
  box:SetMultiLine(true)
  box:SetFontObject(ChatFontNormal)
  box:SetAlpha(0)
  box:EnableMouse(false)
  box:SetScript("OnEscapePressed", function() CopyText.End("escape") end)
  -- Something else took focus (chat Enter, a dialog): the session is over.
  box:SetScript("OnEditFocusLost", function(self) self:SetText(""); if activeFrame then CopyText.End("focus") end end)
  -- Ctrl+C in a focused EditBox is handled by the client; nothing to do here.
  VCF_CopyEditBox = box
  return box
end

local function HoldFocus()
  local box = GetCopyBox()
  box:SetText("")
  box:Show()
  box:SetFocus()
end

local function ReleaseFocus()
  if not VCF_CopyEditBox then return end
  local box = VCF_CopyEditBox
  box:SetScript("OnEditFocusLost", nil)       -- do not re-enter End from the ClearFocus below
  box:ClearFocus()
  box:SetText("")
  box:SetScript("OnEditFocusLost", function(self) self:SetText(""); if activeFrame then CopyText.End("focus") end end)
end

local function StageForClipboard(frame, text)
  local box = GetCopyBox()
  box:SetText(text)
  if not box:HasFocus() then box:SetFocus() end
  box:HighlightText()
  Touch()
  ShowToast(frame, string.format("%d chars selected - Ctrl+C copies", #text))
end

-- Replace the stock mouse-up (which calls the protected CopyToClipboard) for the active frame:
-- pre-hook OnMouseUp, gather the text ourselves, then cancel the stock selection so its own
-- handler finds nothing to copy.
local function OnMouseUpPre(frame, button)
  if button ~= "LeftButton" or not IsOn(frame) then return end
  if not (frame.IsSelectingText and frame:IsSelectingText()) then return end
  local x, y = frame:GetScaledCursorPosition()
  local ok, text = pcall(frame.GatherSelectedText, frame, x, y)
  frame:ResetSelectingText()        -- stock OnPostMouseUp now sees IsSelectingText() == false
  if ok and text and text ~= "" then
    -- strip |c..|r colour codes and |H..|h links like REMOVE_MARKUP would
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    StageForClipboard(frame, text)
  end
end

local function OnCopied(frame, text, numCopied)
  -- Reached only if the stock path ever becomes allowed; harmless.
  Touch()
  ShowToast(frame, string.format("copied to clipboard (%d chars)", numCopied or #text))
end

function CopyText.Init()
  local function attach(rec)
    if rec.frame.SetOnTextCopiedCallback then rec.frame:SetOnTextCopiedCallback(OnCopied) end
  end
  Windows.OnNewRecord(attach)
  for _, rec in ipairs(Windows.All()) do attach(rec) end

  if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_FCF_TAB", function(owner, rootDescription)
      if not Settings.IsEnabled() then return end
      local frame = (FCF_GetChatFrameByID and FCF_GetChatFrameByID(owner:GetID())) or _G["ChatFrame" .. owner:GetID()]
      if not frame or not frame.SetTextCopyable then return end
      rootDescription:CreateDivider()
      local label = IsOn(frame) and "Disable Selection" or string.format("Enable Selection (temporary, %ds)", CopyText.SELECTION_IDLE_SECS)
      rootDescription:CreateButton(label, function() CopyText.Toggle(frame) end)
    end)
  else
    Util.WarnOnce("copymenu", "Menu.ModifyMenu not available; use /vcf copy to toggle selection on the active window")
  end
end

-- /vcf copy [n]  -- toggle on window n (default: the selected docked window)
function CopyText.SlashToggle(arg)
  local n = tonumber(arg)
  local frame = (n and _G["ChatFrame" .. n]) or (FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)) or SELECTED_CHAT_FRAME or ChatFrame1
  CopyText.Toggle(frame)
end