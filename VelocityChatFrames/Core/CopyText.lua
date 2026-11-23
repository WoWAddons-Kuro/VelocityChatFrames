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
  frame:HookScript("OnMouseUp", Touch)
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
  Util.Print("selection on for %s: drag to select, release to copy. Ends after %ds without touching the window.",
    frame.name or frame:GetName(), CopyText.SELECTION_IDLE_SECS)
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
  if reason == "idle" then Util.Print("selection off (idle)") end
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

local function OnCopied(frame, text, numCopied)
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