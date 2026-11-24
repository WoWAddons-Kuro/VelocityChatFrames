-- Velocity Chat Frames: DIAGNOSTIC. A from-scratch chat window to answer one question: does a
-- ScrollingMessageFrame that is NOT part of the stock chat window stack block world clicks?
--
-- /vcf test        toggle it
-- /vcf test mirror toggle mirroring ChatFrame1's lines into it (default on)
--
-- Drag it by the title bar over a mob and click the mob through the text area. The title bar is
-- the ONLY mouse-enabled region; the message frame has no input at all. If the click lands, a
-- rewrite on our own SMF is safe. If it does not, the SMF type itself blocks world clicks when it
-- holds text, and the rewrite must use plain FontStrings instead.
local ADDON_NAME, NS = ...
local Util, Settings = NS.Util, NS.Settings

local TestWindow = {}
NS.TestWindow = TestWindow

local win, smf
local mirroring = true
local hooked = false

local function Build()
  if win then return win end
  win = CreateFrame("Frame", "VelocityChatFramesTestWindow", UIParent)
  win:SetSize(420, 180)
  win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 260)
  win:SetFrameStrata("LOW")
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:EnableMouse(false)              -- body takes nothing

  -- Title bar: the one draggable, mouse-enabled strip.
  local title = CreateFrame("Frame", nil, win)
  title:SetHeight(18)
  title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() win:StartMoving() end)
  title:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  local tbg = title:CreateTexture(nil, "BACKGROUND"); tbg:SetAllPoints(); tbg:SetColorTexture(0.1, 0.1, 0.1, 0.85)
  local tl = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); tl:SetPoint("LEFT", 6, 0)
  tl:SetText("VCF test window  -  drag here; click a mob THROUGH the text below")

  -- Faint body wash so you can see the rect; it is a Texture, takes no mouse.
  local body = win:CreateTexture(nil, "BACKGROUND")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT"); body:SetPoint("BOTTOMRIGHT")
  body:SetColorTexture(0, 0, 0, 0.15)

  -- 2 px orange border on all four sides so the rect is never lost against terrain.
  -- Textures, so no mouse.
  local function edge(p1, p2, w, h)
    local t = win:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(1, 0.55, 0.1, 1)
    t:SetPoint(p1); t:SetPoint(p2); if w then t:SetWidth(w) end; if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 2); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
  edge("TOPLEFT", "BOTTOMLEFT", 2, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)

  -- The message frame under test: no mouse of any kind.
  smf = CreateFrame("ScrollingMessageFrame", "VelocityChatFramesTestSMF", win)
  smf:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -2)
  smf:SetPoint("BOTTOMRIGHT", -4, 4)
  smf:SetFontObject(ChatFontNormal)
  smf:SetJustifyH("LEFT")
  smf:SetFading(false)
  smf:SetMaxLines(64)
  smf:EnableMouse(false)
  smf:EnableMouseWheel(false)
  if smf.SetMouseClickEnabled then smf:SetMouseClickEnabled(false) end
  if smf.SetMouseMotionEnabled then smf:SetMouseMotionEnabled(false) end
  if smf.SetHyperlinksEnabled then smf:SetHyperlinksEnabled(false) end
  if smf.SetPropagateMouseClicks then smf:SetPropagateMouseClicks(true) end
  if smf.SetPropagateMouseMotion then smf:SetPropagateMouseMotion(true) end
  if smf.FontStringContainer then
    local c = smf.FontStringContainer
    c:EnableMouse(false)
    if c.SetPropagateMouseClicks then c:SetPropagateMouseClicks(true) end
    if c.SetPropagateMouseMotion then c:SetPropagateMouseMotion(true) end
  end
  for i = 1, 8 do smf:AddMessage(string.format("test line %d - plain text, no links", i), 0.9, 0.9, 0.9) end
  return win
end

-- Mirror ChatFrame1's lines so the test rect has live, realistic content.
local function HookMirror()
  if hooked or not ChatFrame1 then return end
  hooked = true
  hooksecurefunc(ChatFrame1, "AddMessage", function(_, text, r, g, b)
    if mirroring and smf and win and win:IsShown() and type(text) == "string" and not Util.IsSecret(text) then
      smf:AddMessage(text, r or 1, g or 1, b or 1)
    end
  end)
end

function TestWindow.Toggle(arg)
  if arg == "mirror" then
    mirroring = not mirroring
    Util.Print("test window mirroring %s", mirroring and "ON" or "OFF")
    return
  end
  Build(); HookMirror()
  if win:IsShown() then win:Hide(); Util.Print("test window hidden")
  else win:Show(); Util.Print("test window shown - drag by the title bar, click a mob through the text") end
end