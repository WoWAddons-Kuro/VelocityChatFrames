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
  Touch()
  CancelTimer()
  idleTimer = C_Timer.NewTimer(CopyText.SELECTION_IDLE_SECS + 0.1, OnIdleTick)
  ShowToast(frame, string.format("selection on: drag to select. Ends after %ds idle", CopyText.SELECTION_IDLE_SECS))
end

function CopyText.End(reason)
  CancelTimer()
  local frame = activeFrame
  activeFrame = nil
  if not frame then return end
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
-- The only clipboard route open to addons is an EditBox with focus + the client's own Ctrl+C;
-- no button can write the clipboard. So each drag release opens a small review window showing
-- exactly what was selected, already highlighted and focused: Ctrl+C copies it. "Select all"
-- re-highlights if you clicked around; Escape or Close dismisses it.
local VCF_CopyWindow

local function GetCopyWindow()
  if VCF_CopyWindow then return VCF_CopyWindow end
  local win = CreateFrame("Frame", "VelocityChatFramesCopyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  win:SetSize(560, 240)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  if win.SetBackdrop then
    win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    win:SetBackdropColor(0, 0, 0, 0.9); win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Selected text")
  win.title = title

  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
  hint:SetText("|cffaaaaaapress Ctrl+C to copy, Esc to close|r")

  local scroll = CreateFrame("ScrollFrame", "VelocityChatFramesCopyWindowScroll", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -32)
  scroll:SetPoint("BOTTOMRIGHT", -30, 40)

  local box = CreateFrame("EditBox", "VelocityChatFramesCopyWindowEditBox", scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(scroll:GetWidth() > 0 and scroll:GetWidth() or 500)
  box:SetScript("OnEscapePressed", function() win:Hide() end)
  box:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(self.vcfText or "") end end) -- read-only
  scroll:SetScrollChild(box)
  scroll:SetScript("OnSizeChanged", function(self, w) box:SetWidth(w) end)
  win.box = box

  local function SelectAll()
    box:SetFocus()
    box:HighlightText()
    box:SetCursorPosition(0)
  end

  local selectAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  selectAll:SetSize(100, 22); selectAll:SetText("Select all")
  selectAll:SetPoint("BOTTOMLEFT", 12, 10)
  selectAll:SetScript("OnClick", SelectAll)

  local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  close:SetSize(80, 22); close:SetText(CLOSE or "Close")
  close:SetPoint("BOTTOMRIGHT", -12, 10)
  close:SetScript("OnClick", function() win:Hide() end)

  local count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetPoint("LEFT", selectAll, "RIGHT", 10, 0)
  win.count = count

  win:SetScript("OnShow", function() C_Timer.After(0, SelectAll) end)
  win:SetScript("OnHide", function() box:ClearFocus() end)
  win.SelectAll = SelectAll
  win:Hide()
  tinsert(UISpecialFrames, "VelocityChatFramesCopyWindow")   -- Esc closes it even without focus
  VCF_CopyWindow = win
  return win
end

local function ShowCopyWindow(frame, text)
  local win = GetCopyWindow()
  win.box.vcfText = text
  win.box:SetText(text)
  win.count:SetText(string.format("%d characters, %d lines", #text, select(2, text:gsub("\n", "")) + 1))
  win.title:SetText(string.format("Selected text from %s", frame.name or frame:GetName()))
  if win:IsShown() then win.SelectAll() else win:Show() end
  Touch()
end

local function StageForClipboard(frame, text)
  ShowCopyWindow(frame, text)
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