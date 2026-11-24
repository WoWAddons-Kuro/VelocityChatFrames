-- Velocity Chat Frames: entry point. Loads last; wires modules together on PLAYER_LOGIN.
local ADDON_NAME, NS = ...
local Util = NS.Util

local function Status()
  local s = NS.Settings.Get()
  local info = Util.ClientInfo()
  local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"
  Util.Print("version %s, client %s (%s), flavour %s", version, info.Version, info.Interface, NS.Client.flavour)
  Util.Print("enabled=%s fade=%ds timestamps=%s tags=%s level=%s windows=%d known players=%d",
    tostring(s.Enabled), s.LineFadeSeconds, tostring(s.Timestamps), tostring(s.ShortChannelTags), tostring(s.ShowLevelInName),
    #NS.Windows.All(), NS.PlayerData.Count())
end

local function SlashHandler(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "status" then Status()
  elseif msg:match("^copy") then
    NS.CopyText.SlashToggle(msg:match("^copy%s*(%d*)"))
  elseif msg:match("^test") then
    NS.TestWindow.Toggle(msg:match("^test%s*(%S*)"))
  elseif msg == "on" or msg == "off" then
    NS.Settings.Get().Enabled = (msg == "on"); NS.OnSettingChanged("Enabled"); Util.Print("enabled=%s", msg)
  else
    NS.Options.Open()
  end
end

local function OnLogin()
  NS.Settings.Init()
  NS.PlayerData.Init()
  NS.Windows.Init()
  NS.Reveal.Init()
  NS.Fading.Init()
  NS.Sticky.Init()
  NS.LineFormat.Init()
  NS.HideButtons.Init()
  NS.EditModeLayout.Init()
  NS.EditBox.Init()
  NS.TabMenu.Init()
  NS.CopyText.Init()
  NS.Options.Create()

  SLASH_VELOCITYCHATFRAMES1 = "/vcf"
  SlashCmdList["VELOCITYCHATFRAMES"] = SlashHandler
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    local ok, err = pcall(OnLogin)
    if not ok then Util.Raise("OnLogin", err) end
  end
end)