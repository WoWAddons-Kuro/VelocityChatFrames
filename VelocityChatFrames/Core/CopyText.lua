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
-- Forward declarations: these are defined below but referenced by closures created above them.
local OnMouseUpPre
local ShowToast

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
  if activeFrame ~= frame then
    frame.vcfSelectionMotionBefore = frame.IsMouseMotionEnabled and frame:IsMouseMotionEnabled()
    frame.vcfSelectionWheelBefore = frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled()
  end
  activeFrame = frame
  HookTouch(frame)
  frame:SetTextCopyable(true)
  if NS.CopySelect then NS.CopySelect.Attach(frame) end   -- multi-screen anchor + edge scroll
  -- Selection needs clicks; Phase 2 Rest turns them off, so force on while selecting.
  frame:EnableMouse(true)
  if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
  frame:SetFading(false)
  Touch()
  CancelTimer()
  idleTimer = C_Timer.NewTimer(CopyText.SELECTION_IDLE_SECS + 0.1, OnIdleTick)
  ShowToast(frame, string.format("selection on: drag to select. Ends after %ds idle", CopyText.SELECTION_IDLE_SECS))
end

-- Shared baseline: use the same reset at startup and at selection exit. Never reset a
-- window while selection is still active. Preserve wheel and motion independently.
function CopyText.ApplyClickThrough(frame, motion, wheel)
  if not frame or frame == activeFrame then return end
  if motion == nil and frame.IsMouseMotionEnabled then motion = frame:IsMouseMotionEnabled() end
  if wheel == nil and frame.IsMouseWheelEnabled then wheel = frame:IsMouseWheelEnabled() end
  frame:SetTextCopyable(false)
  frame:EnableMouse(false)
  if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
  if frame.SetMouseMotionEnabled and motion ~= nil then
    frame:SetMouseMotionEnabled(motion)
  end
  if frame.EnableMouseWheel and wheel ~= nil then
    frame:EnableMouseWheel(wheel)
  end
end

function CopyText.End(reason)
  CancelTimer()
  local frame = activeFrame
  activeFrame = nil
  if not frame then return end
  if NS.CopySelect then NS.CopySelect.Detach(frame) end
  CopyText.ApplyClickThrough(frame, frame.vcfSelectionMotionBefore, frame.vcfSelectionWheelBefore)
  frame.vcfSelectionMotionBefore, frame.vcfSelectionWheelBefore = nil, nil
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

function ShowToast(frame, msg)
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
  box:SetMaxLetters(0)   -- unlimited. The default cap silently DROPS a longer SetText (GetText() -> ""), which
                         -- is why long selections showed an empty box while short ones worked.
  -- Smaller than the chat font: this is a review pane, so more lines on screen beats legibility at
  -- distance. Fall back to the chat font if the small one is missing on a client.
  box:SetFontObject(ChatFontSmall or GameFontHighlightSmall or ChatFontNormal)
  box:SetWidth(scroll:GetWidth() > 0 and scroll:GetWidth() or 500)
  box:SetScript("OnEscapePressed", function() win:Hide() end)
  -- Report-only. This handler never writes to the box: the OnTextChanged for a SetText arrives AFTER the
  -- caller returns, so any "restore here" logic re-triggers itself without bound. The bounded Watchdog in
  -- ShowCopyWindow is the only thing allowed to re-stage text.
  box:SetScript("OnTextChanged", function(self, userInput)
    if CopyText.debug then
      Util.Print("copy: OnTextChanged userInput=%s have=%d want=%d", tostring(userInput), #(self:GetText() or ""), #(self.vcfText or ""))
    end
  end)
  scroll:SetScrollChild(box)
  scroll:SetScript("OnSizeChanged", function(self, w) box:SetWidth(w) end)
  win.box = box
  win.scroll = scroll
  -- Explicit minimum height: a multi-line EditBox with derived height can be 0 on its first
  -- layout pass, and a 0-height scroll child draws nothing. Also pin width now (the scroll frame
  -- has a real size by the time this runs on first use).
  local function FitBox()
    local w, h = scroll:GetWidth(), scroll:GetHeight()
    if w and w > 0 then box:SetWidth(w) end
    if h and h > 0 and (box:GetHeight() or 0) < h then box:SetHeight(h) end
  end
  scroll:SetScript("OnSizeChanged", function() FitBox() end)
  FitBox()

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
  win:SetScript("OnHide", function(self)
    box:ClearFocus()
    local source = self.vcfSelectionFrame
    self.vcfSelectionFrame = nil
    if source and activeFrame == source then CopyText.End("popup closed") end
  end)
  win.SelectAll = SelectAll
  win:Hide()
  tinsert(UISpecialFrames, "VelocityChatFramesCopyWindow")   -- Esc closes it even without focus
  VCF_CopyWindow = win
  return win
end

local function ShowCopyWindow(frame, text)
  local win = GetCopyWindow()
  win.vcfSelectionFrame = frame
  win.box.vcfText = text
  win.scroll:SetVerticalScroll(0)
  win.box:SetText(text)
  local lineCount = select(2, text:gsub("\n", "")) + 1
  -- An explicitly sized multi-line EditBox does not grow with its text, and SetText parks the cursor at
  -- the end, so a selection taller than the scroll frame rendered as blank space. Size the box to the
  -- text (line count x line height, generous for wraps) so every line has room and the scroll frame scrolls.
  local _, fontHeight = win.box:GetFont()
  fontHeight = (fontHeight and fontHeight > 0) and fontHeight or 14
  local wrapAllowance = 1.6   -- long chat lines wrap in the review box; over-allocate rather than clip
  local neededHeight = lineCount * fontHeight * wrapAllowance + 24
  win.box:SetHeight(math.max(win.scroll:GetHeight() or 0, neededHeight))
  win.count:SetText(string.format("%d characters, %d lines", #text, lineCount))
  win.title:SetText(string.format("Selected text from %s", frame.name or frame:GetName()))
  win.vcfShowSerial = (win.vcfShowSerial or 0) + 1
  local serial = win.vcfShowSerial
  if not win:IsShown() then win:Show() end   -- OnShow also schedules SelectAll; harmless twice
  win.SelectAll()
  -- Re-assert next frame: SetText on a multi-line EditBox lays out asynchronously, and anything
  -- that took keyboard focus in between (chat edit box activation etc.) would leave us unfocused.
  C_Timer.After(0, function()
    if win.vcfShowSerial ~= serial or not win:IsShown() then return end
    win.SelectAll()
  end)
  -- Watchdog: the ONE writer that may re-stage the text after ShowCopyWindow. Exactly MAX_RETRIES tries at
  -- RETRY_SECS, then gives up. (Root cause of the empty box was the EditBox default max-letters cap, fixed
  -- at creation with SetMaxLetters(0); this remains as a bounded safety net for anything else that clears it.)
  local RETRY_SECS, MAX_RETRIES = 0.5, 3
  local function Watchdog(attempt)
    if win.vcfShowSerial ~= serial or not win:IsShown() then return end
    local have = win.box:GetText() or ""
    if have == text then return end
    if attempt > MAX_RETRIES then
      if CopyText.debug then Util.Print("copy: watchdog gave up after %d tries - box has %d chars, expected %d", MAX_RETRIES, #have, #text) end
      return
    end
    if CopyText.debug then
      Util.Print("copy: watchdog %d/%d - box has %d chars, expected %d; re-staging", attempt, MAX_RETRIES, #have, #text)
    end
    win.box.vcfText = text
    win.box:SetText(text)
    win.box:SetHeight(math.max(win.scroll:GetHeight() or 0, neededHeight))
    win.SelectAll()
    C_Timer.After(RETRY_SECS, function() Watchdog(attempt + 1) end)   -- attempt MAX+1 only reports and stops
  end
  C_Timer.After(RETRY_SECS, function() Watchdog(1) end)
  if CopyText.debug then
    C_Timer.After(0.15, function()
      if win.vcfShowSerial ~= serial then return end
      local box = win.box
      local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
      Util.Print("copy: shown=%s boxText=%d focus=%s height=%.0f/%.0f scroll=%.0f alpha=%.2f",
        tostring(win:IsShown()), #(box:GetText() or ""),
        focus and ((focus.GetName and focus:GetName()) or "unnamed") or "none",
        box:GetHeight() or 0, win.scroll:GetHeight() or 0, win.scroll:GetVerticalScroll() or 0, box:GetAlpha() or 1)
    end)
  end
  Touch()
end

local function StageForClipboard(frame, text)
  ShowCopyWindow(frame, text)
end

-- Replace the stock mouse-up (which calls the protected CopyToClipboard) for the active frame:
-- pre-hook OnMouseUp, gather the text ourselves, then cancel the stock selection so its own
-- handler finds nothing to copy.
-- Markup strip, link-first: a chat line nests |cff..|Hitem:..|h[Name]|h|r, so resolve links
-- before colours; a colour code that survives is rendered live by the EditBox and, lacking its
-- |r, bleeds into the following lines. Handles |cffRRGGBB, |cnNAME: and |cAARRGGBB forms.
--
-- Then the DANGLING-FRAGMENT pass. The selection anchor/cursor are byte offsets into the RAW line
-- (markup included), so a drag that starts or ends mid-line can cut inside an escape: "|cff8", a
-- "|H..." with no "|h", a bare "|h", or a lone "|". The complete-pattern pass above cannot match
-- those, and a single malformed escape makes the EditBox reject the WHOLE string (SetText lands,
-- GetText() returns "" - observed as the 1089-char empty box on Forever while 372 chars worked).
local function StripMarkup(text)
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|K.-|k", "")                                   -- Battle.net protected names (Forever)
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]-:", ""):gsub("|c%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  -- Dangling fragments left by a mid-escape cut:
  text = text:gsub("|H[^|]*|h", "")                                -- "|Hlink|h" whose closing "|h" was cut off: drop link data, keep what follows
  text = text:gsub("|H[^|]*$", "")                                 -- "|H..." running to end of string
  text = text:gsub("|[HKTA][^|]*", "")                             -- any other open "|H/|K/|T/|A" with its payload but no terminator
  text = text:gsub("|[hkta]", "")                                  -- bare terminators
  text = text:gsub("|c%x*", "")                                    -- truncated colour open ("|c", "|cf", "|cff8...")
  text = text:gsub("|cn[^:|]*", "")                                -- truncated named colour
  text = text:gsub("|n", "\n")                                     -- newline escape -> real newline
  -- Anything still introduced by "|" is unknown or malformed; a lone pipe is what poisons the box. Make it
  -- literal ("||" renders as "|") so the user still sees the character and the string stays valid.
  text = text:gsub("|([^|])", "||%1"):gsub("|$", "||")
  return text
end
CopyText.StripMarkup = StripMarkup

-- Debug: list any "|" sequences that survived StripMarkup so a new escape form shows up in the log.
local function ReportResidualEscapes(text)
  if not CopyText.debug then return end
  local seen, n = {}, 0
  for seq in text:gmatch("|[^|]?[^|]?[^|]?") do
    if not seen[seq] then seen[seq] = true; n = n + 1; if n <= 8 then Util.Print("copy: residual escape %q", seq) end end
  end
  if n > 8 then Util.Print("copy: ... %d distinct residual escapes", n) end
end

function OnMouseUpPre(frame, button)
  if button ~= "LeftButton" or not IsOn(frame) then return end
  if not (frame.IsSelectingText and frame:IsSelectingText()) then return end
  local x, y = frame:GetScaledCursorPosition()
  local ok, text = pcall(frame.GatherSelectedText, frame, x, y)
  frame:ResetSelectingText()        -- stock OnPostMouseUp now sees IsSelectingText() == false
  if not ok then
    if CopyText.debug then Util.Print("copy: GatherSelectedText failed: %s", tostring(text)) end
    return
  end
  if Util.IsSecret(text) then
    ShowToast(frame, "selected text is protected on this client")
    return
  end
  local rawLen = type(text) == "string" and #text or -1
  text = type(text) == "string" and StripMarkup(text) or ""
  if text:match("^%s*$") then
    -- Empty / whitespace-only selection: click without drag, or drag across blank space.
    if CopyText.debug then Util.Print("copy: empty selection (raw %d chars)", rawLen) end
    return
  end
  if CopyText.debug then Util.Print("copy: gathered raw %d -> stripped %d chars", rawLen, #text) end
  ReportResidualEscapes(text)
  StageForClipboard(frame, text)
end

local function OnCopied(frame, text, numCopied)
  -- Reached only if the stock path ever becomes allowed; harmless.
  Touch()
  ShowToast(frame, string.format("copied to clipboard (%d chars)", numCopied or #text))
end

function CopyText.Init()
  local function attach(rec)
    if rec.frame.SetOnTextCopiedCallback then rec.frame:SetOnTextCopiedCallback(OnCopied) end
    if Settings.IsEnabled() then CopyText.ApplyClickThrough(rec.frame) end
  end
  Windows.OnNewRecord(attach)
  for _, rec in ipairs(Windows.All()) do attach(rec) end
  -- Login/world initialization can configure the stock windows after our Init call.
  local inputEvents = CreateFrame("Frame")
  inputEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  inputEvents:SetScript("OnEvent", function()
    C_Timer.After(0, function()
      if not Settings.IsEnabled() then return end
      for _, rec in ipairs(Windows.All()) do CopyText.ApplyClickThrough(rec.frame) end
    end)
  end)

  if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_FCF_TAB", function(owner, rootDescription)
      if not Settings.IsEnabled() then return end
      local frame = (FCF_GetChatFrameByID and FCF_GetChatFrameByID(owner:GetID())) or _G["ChatFrame" .. owner:GetID()]
      if not frame or not frame.SetTextCopyable then return end
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