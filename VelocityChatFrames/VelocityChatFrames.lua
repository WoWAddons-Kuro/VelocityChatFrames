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
  elseif msg == "copydebug" then
    NS.CopyText.debug = not NS.CopyText.debug
    Util.Print("copy debug=%s", tostring(NS.CopyText.debug))
  elseif msg == "fadedebug" then NS.Fading.ToggleDebug()
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
  local other = NS.Conflict.Detect()
  if other then NS.Conflict.Enter(other); return end

  NS.Settings.Init()
  NS.Windows.Init()
  -- Each module is isolated: one failing Init is reported and the rest still run. Order:
  -- LineFormat before Scrollback so restored lines are added after the formatter hooks exist.
  local inits = {
    { "PlayerData", NS.PlayerData.Init }, { "Reveal", NS.Reveal.Init }, { "Fading", NS.Fading.Init },
    { "Sticky", NS.Sticky.Init }, { "LineFormat", NS.LineFormat.Init },
    { "Scrollback", NS.Scrollback.Init },     -- restores saved lines before any live CHAT_MSG line lands
    { "HideButtons", NS.HideButtons.Init }, { "EditModeLayout", NS.EditModeLayout.Init },
    { "EditBox", NS.EditBox.Init }, { "TabMenu", NS.TabMenu.Init }, { "CopyText", NS.CopyText.Init },
    { "Options", NS.Options.Create },
  }
  for _, m in ipairs(inits) do
    local ok, err = pcall(m[2])
    if not ok then Util.Raise(m[1] .. ".Init", err) end
  end

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