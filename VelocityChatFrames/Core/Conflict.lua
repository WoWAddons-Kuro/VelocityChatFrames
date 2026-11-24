-- Velocity Chat Frames: conflict guard. Prat rewrites the same chat frames we do; both running at once
-- produces broken reveal/tabs. If Prat is loaded we initialise nothing and offer the user a choice.
-- C_AddOns.Disable/EnableAddOn only writes the addon-list state; a ReloadUI makes it take effect.
local ADDON_NAME, NS = ...
local Util = NS.Util

local Conflict = {}
NS.Conflict = Conflict

local CONFLICTS = { "Prat-3.0" }

local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local DisableAddOn = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn

-- Returns the folder name of the first conflicting addon that is loaded, or nil.
function Conflict.Detect()
  if not IsLoaded then return nil end
  for _, name in ipairs(CONFLICTS) do
    if IsLoaded(name) then return name end
  end
  return nil
end

local dialog

local function Apply(addonToDisable, thisCharacterOnly)
  if thisCharacterOnly then
    DisableAddOn(addonToDisable, UnitName("player"))
  else
    DisableAddOn(addonToDisable)
  end
  ReloadUI()
end

local function Build(other)
  local W, PAD = 440, 16
  local f = CreateFrame("Frame", "VelocityChatFramesConflict", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
  f:SetWidth(W)
  f:SetPoint("CENTER", 0, 120)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
  f:EnableMouse(true)

  local y = -PAD - 4
  local function Text(template, text, justify)
    local fs = f:CreateFontString(nil, "ARTWORK", template)
    fs:SetPoint("TOPLEFT", PAD, y); fs:SetWidth(W - 2 * PAD); fs:SetJustifyH(justify or "CENTER")
    fs:SetText(text)
    y = y - fs:GetStringHeight() - 8
    return fs
  end
  local function Button(label, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(W - 2 * PAD - 24, 24); b:SetPoint("TOP", 0, y)
    b:SetText(label); b:SetScript("OnClick", onClick)
    y = y - 28
    return b
  end

  local shortOther = other:gsub("%-[%d%.]+$", "")  -- "Prat-3.0" -> "Prat"
  Text("GameFontNormalLarge", "Velocity Chat Frames")
  Text("GameFontHighlight", string.format("Velocity Chat Frames and %s both rewrite the chat frames and can NOT run together.", shortOther))
  y = y - 6

  Text("GameFontNormal", "-- For ALL Characters --")
  Button(string.format("Use Velocity Chat Frames, disable %s", shortOther), function() Apply(other, false) end)
  Button(string.format("Use %s, disable Velocity Chat Frames", shortOther), function() Apply(ADDON_NAME, false) end)
  y = y - 10

  Text("GameFontNormal", "-- For THIS Character Only --")
  Button(string.format("Use Velocity Chat Frames, disable %s", shortOther), function() Apply(other, true) end)
  Button(string.format("Use %s, disable Velocity Chat Frames", shortOther), function() Apply(ADDON_NAME, true) end)
  y = y - 10

  Text("GameFontHighlightSmall", "NOTE: you can turn either addon back on in Main Menu -> AddOns.\nThe UI reloads after you choose.")
  y = y - 4

  local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  later:SetSize(120, 22); later:SetPoint("TOP", 0, y)
  later:SetText("Decide later"); later:SetScript("OnClick", function() f:Hide() end)
  y = y - 26

  f:SetHeight(-y + PAD)
  tinsert(UISpecialFrames, f:GetName())
  return f
end

function Conflict.ShowDialog(other)
  if not dialog then
    local ok, res = pcall(Build, other)
    if not ok then Util.Print("|cffff4040conflict dialog failed:|r %s", tostring(res)); return end
    dialog = res
  end
  dialog:Show()
end

-- Called from the entry point instead of normal init. Leaves the addon dormant for this session.
-- The dialog is in UISpecialFrames, and UIParent runs CloseAllWindows() on PLAYER_ENTERING_WORLD,
-- which would hide it straight away; so the first show waits until after that event.
function Conflict.Enter(other)
  Util.Print("|cffff4040%s is running|r - Velocity Chat Frames is dormant this session. /vcf to choose which one to keep.", other)
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0.5, function() Conflict.ShowDialog(other) end)
  end)
  SLASH_VELOCITYCHATFRAMES1 = "/vcf"
  SlashCmdList["VELOCITYCHATFRAMES"] = function() Conflict.ShowDialog(other) end
end