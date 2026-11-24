-- Velocity Chat Frames: the settings panel. Pattern: GotJunk / VelocityQuestTracker UI\Options.lua
-- (Section / Check / Slider helpers on a scrolling canvas, Settings.RegisterCanvasLayoutCategory with
-- the legacy InterfaceOptions_AddCategory fallback). Settings live in VelocityChatFramesDB.settings.
local ADDON_NAME, NS = ...
local Util, Sticky = NS.Util, NS.Sticky

local Options = {}
NS.Options = Options

local optionsFrame, optionsCategory
local widgets = {}

local function db() return NS.db.settings end

function Options.Refresh()
  for _, w in ipairs(widgets) do if w.Update then w:Update() end end
end

function Options.Open()
  if Settings and Settings.OpenToCategory and optionsCategory then Settings.OpenToCategory(optionsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory and optionsFrame then InterfaceOptionsFrame_OpenToCategory(optionsFrame); InterfaceOptionsFrame_OpenToCategory(optionsFrame) end
end

function Options.Create()
  if optionsFrame then return end
  optionsFrame = CreateFrame("Frame", "VelocityChatFramesOptions", UIParent)
  optionsFrame.name = "Velocity Chat Frames"
  optionsFrame:Hide()

  local scroll = CreateFrame("ScrollFrame", "VelocityChatFramesOptionsScroll", optionsFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 900)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(math.max(620, w)) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Velocity Chat Frames")
  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Chat windows that stay out of the way. The stock windows no longer reveal themselves when the pointer wanders near them; lines fade after a short delay; channel tags are short and sender names carry their level.")

  local BOX_W, PAD = 580, 10
  local last, lastDy = sub, -14
  local function Place(w, dy, dx) w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", dx or 0, dy or lastDy); last = w; lastDy = -6 end

  -- Check(parent, key, label, tip [, getter, setter]) : getter/setter override the flat db()[key] path.
  local function Check(parent, key, label, tip, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb.tooltipText = tip
    cb:SetScript("OnClick", function(self)
      local v = self:GetChecked() and true or false
      if setter then setter(v) else db()[key] = v end
      NS.OnSettingChanged(key)
    end)
    cb.Update = function(self) self:SetChecked((getter and getter() or (not getter and db()[key])) and true or false) end
    widgets[#widgets + 1] = cb
    return cb
  end

  local function Slider(parent, name, key, default, minV, maxV, step, labelFn)
    local holder = CreateFrame("Frame", nil, parent); holder:SetSize(BOX_W - 2 * PAD, 44)
    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); label:SetPoint("TOPLEFT", 4, 0)
    local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6); s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minV)); _G[name .. "High"]:SetText(tostring(maxV)); _G[name .. "Text"]:SetText("")
    s:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / step + 0.5) * step
      if db()[key] == v then return end
      db()[key] = v; label:SetText(labelFn(v)); NS.OnSettingChanged(key)
    end)
    holder.Update = function() local v = db()[key] or default; s:SetValue(v); label:SetText(labelFn(v)) end
    widgets[#widgets + 1] = holder
    return holder
  end

  local function Section(header)
    local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetWidth(BOX_W)
    if box.SetBackdrop then
      box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      box:SetBackdropColor(0, 0, 0, 0.25); box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
    end
    local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); h:SetPoint("TOPLEFT", PAD, -PAD); h:SetText(header)
    box.inner_last, box.inner_h = h, PAD + 14
    function box:Add(w, height, dy, dx)
      dy = dy or -6
      w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
      self.inner_last, self.inner_h = w, self.inner_h - dy + height
      return w
    end
    function box:Finish() self:SetHeight(self.inner_h + PAD) end
    Place(box, -14)
    return box
  end

  -- Headline: the global enable.
  Place(Check(content, "Enabled", "Enable Velocity Chat Frames", "Untick to hand every chat window back to the stock behaviour: hover reveal, 120 s fade, long channel names, stock sticky channels."), -14)

  local lines = Section("Lines")
  lines:Add(Slider(lines, "VelocityChatFramesOptFade", "LineFadeSeconds", 15, 0, 240, 1,
    function(v) if v <= 0 then return "Lines never fade" end return string.format("Lines fade %d s after they arrive", v) end), 44, -10)
  lines:Add(Check(lines, "Timestamps", "Timestamps", "Prefix every line with the time it arrived (uses the game's own timestamp setting, HH:MM)."), 26, -10)
  lines:Add(Check(lines, "ShortChannelTags", "Short channel tags", "[G] instead of [Guild], [P] instead of [Party], [W From] / [W To] for whispers, and so on."), 26)
  lines:Add(Check(lines, "ShowLevelInName", "Show level in sender names", "[3:Kuro Ragemane] when the sender's level is known from your guild roster, friends list, group, target or mouseover."), 26)
  lines:Add(Check(lines, "LevelColorByDifficulty", "Colour the level by difficulty", "The level number takes the quest-difficulty colour relative to you (grey, green, yellow, orange, red), slightly desaturated."), 26)
  lines:Finish()

  local ch = Section("Hide chat buttons")
  ch:Add(Check(ch, "TabsMatchWindowAlpha", "Tabs use the window's background alpha", "Chat tabs are as transparent as their window's background. Unticked: the game's own per-tab alpha."), 26, -10)
  ch:Add(Check(ch, "WheelRevealsBackground", "Reveal window background on mouse wheel over window", "A wheel turn over a chat window shows its background for a few seconds. Moving the pointer never does."), 26)
  ch:Add(Check(ch, "WheelRevealsTabs", "Reveal window tabs on mouse wheel over window", "A wheel turn over a chat window shows its tabs (the whole dock's, if docked) for a few seconds so they can be clicked."), 26)

  -- Revealed background colour + opacity: a swatch that opens the stock colour picker, and an
  -- opacity slider. Stored as RevealBackground = { r, g, b, a } where a is alpha = opacity
  -- (0.3 means 30 % visible paint, 70 % world shows through).
  do
    local row = CreateFrame("Frame", nil, ch); row:SetSize(BOX_W - 2 * PAD, 24)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); label:SetPoint("LEFT", 4, 0)
    label:SetText("Revealed background colour")
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(20, 20); swatch:SetPoint("LEFT", label, "RIGHT", 10, 0)
    local border = swatch:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0.7, 0.7, 0.7, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local function cur() return db().RevealBackground or { r = 0, g = 0, b = 0, a = 0.3 } end
    local function paint() local c = cur(); fill:SetColorTexture(c.r, c.g, c.b, 1) end
    swatch:SetScript("OnClick", function()
      local c = cur()
      local prev = { r = c.r, g = c.g, b = c.b }
      local function apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        db().RevealBackground = { r = r, g = g, b = b, a = cur().a }
        paint(); NS.OnSettingChanged("RevealBackground")
      end
      local function cancel()
        db().RevealBackground = { r = prev.r, g = prev.g, b = prev.b, a = cur().a }
        paint(); NS.OnSettingChanged("RevealBackground")
      end
      if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = c.r, g = c.g, b = c.b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel })
      else
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc, ColorPickerFrame.hasOpacity = apply, cancel, false
        ColorPickerFrame:SetColorRGB(c.r, c.g, c.b); ColorPickerFrame:Show()
      end
    end)
    row.Update = paint
    widgets[#widgets + 1] = row
    ch:Add(row, 24, -8)

    local holder = CreateFrame("Frame", nil, ch); holder:SetSize(BOX_W - 2 * PAD, 44)
    local sl = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); sl:SetPoint("TOPLEFT", 4, 0)
    local s = CreateFrame("Slider", "VelocityChatFramesOptRevealAlpha", holder, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 2, -6); s:SetWidth(220)
    s:SetMinMaxValues(0, 100); s:SetValueStep(5); s:SetObeyStepOnDrag(true)
    _G[s:GetName() .. "Low"]:SetText("0"); _G[s:GetName() .. "High"]:SetText("100"); _G[s:GetName() .. "Text"]:SetText("")
    local function lbl(v) return string.format("Revealed background opacity: %d%% (0 = invisible, 100 = solid)", v) end
    s:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / 5 + 0.5) * 5
      local c = cur(); if math.floor(c.a * 100 + 0.5) == v then return end
      db().RevealBackground = { r = c.r, g = c.g, b = c.b, a = v / 100 }
      sl:SetText(lbl(v)); NS.OnSettingChanged("RevealBackground")
    end)
    holder.Update = function() local v = math.floor(cur().a * 100 + 0.5); s:SetValue(v); sl:SetText(lbl(v)) end
    widgets[#widgets + 1] = holder
    ch:Add(holder, 44, -6)

    ch:Add(Slider(ch, "VelocityChatFramesOptRevealBoost", "RevealBrightZoneBoost", 0.3, 0, 0.7, 0.05,
      function(v) return string.format("Opacity boost in bright zones: +%d%% (sand, snow, pale rock; LibZoneBrightness)", math.floor(v * 100 + 0.5)) end), 44, -6)
    ch:Add(Slider(ch, "VelocityChatFramesOptInactiveTab", "InactiveTabRevealAlpha", 0.5, 0.1, 1, 0.05,
      function(v) return string.format("Inactive tabs reveal to %d%% (active tab is always 100%%)", math.floor(v * 100 + 0.5)) end), 44, -6)
  end
  local first = false
  for _, item in ipairs(NS.HideButtons.ITEMS) do
    ch:Add(Check(ch, item.key, item.label, item.tip), 26, first and -10 or nil)
    first = false
  end
  ch:Finish()

  local eb = Section("Edit box")
  eb:Add(Check(eb, "EditBoxFloat", "Float the edit box at a fixed screen position", "The typing box stays where you put it instead of jumping under whichever window's tab is selected."), 26, -10)
  eb:Add(Check(eb, "AlwaysMainInputLocation", "Always use the main placed input location", "With floating input enabled, Enter, replies and username clicks use the main input location regardless of which window was last active. Keeps the chosen channel/recipient. Overrides the username placement choice below."), 26)
  eb:Add(Check(eb, "EditBoxLocked", "Lock position", "Unticked: drag the edit box with the left mouse button (open it with Enter first). Tick again to lock."), 26)
  eb:Add(Check(eb, "EditBoxHideWhenIdle", "Hide the edit box when not typing", "The box is invisible and ignores the mouse until you press Enter."), 26)
  local usernameLabel = eb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  usernameLabel:SetText("Clicking usernames opens chat input on:")
  eb:Add(usernameLabel, 14, -10, 4)
  for _, option in ipairs({
    { value = "clicked", label = "Bottom of clicked chat frame (default)" },
    { value = "main", label = "Main placed input frame" },
  }) do
    local value = option.value
    local radio = CreateFrame("CheckButton", nil, eb, "UIRadioButtonTemplate")
    radio:SetSize(16, 16)
    local label = radio:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", radio, "RIGHT", 5, 0); label:SetText(option.label)
    radio.Update = function(self) self:SetChecked((db().UsernameInputPlacement or "clicked") == value) end
    radio:SetScript("OnClick", function()
      db().UsernameInputPlacement = value
      NS.OnSettingChanged("UsernameInputPlacement")
      Options.Refresh()
    end)
    widgets[#widgets + 1] = radio
    eb:Add(radio, 18, -6, 4)
  end
  eb:Finish()

  local st = Section("Sticky channels")
  local note = st:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); note:SetWidth(BOX_W - 2 * PAD - 8); note:SetJustifyH("LEFT")
  note:SetText("A sticky channel stays selected in the edit box after you send to it, so the next Enter talks to the same place.")
  st:Add(note, 24, -8, 4)
  local labels = { SAY = "Say", YELL = "Yell", PARTY = "Party", RAID = "Raid", RAID_WARNING = "Raid Warning", INSTANCE_CHAT = "Instance",
                   GUILD = "Guild", OFFICER = "Officer", WHISPER = "Whisper", BN_WHISPER = "Battle.net Whisper", CHANNEL = "Numbered channel", EMOTE = "Emote" }
  local col, rowAnchor, rowH = 0, nil, 0
  for _, t in ipairs(Sticky.TYPES) do
    local info = ChatTypeInfo and ChatTypeInfo[t]
    local colour = info and string.format("|cff%02x%02x%02x", (info.r or 1) * 255, (info.g or 1) * 255, (info.b or 1) * 255) or "|cffffffff"
    local cb = Check(st, "Sticky", "Sticky " .. colour .. (labels[t] or t) .. "|r", "Keep " .. (labels[t] or t) .. " selected after sending to it.",
      function() return db().Sticky[t] end, function(v) db().Sticky[t] = v end)
    if col == 0 then
      st:Add(cb, 26, -4)
      rowAnchor = cb
    else
      cb:SetPoint("TOPLEFT", rowAnchor, "TOPLEFT", 280, 0)
    end
    col = (col + 1) % 2
  end
  st:Finish()

  StaticPopupDialogs["VELOCITYCHATFRAMES_RESET_ALL"] = {
    text = "Reset ALL Velocity Chat Frames settings?\n\nEvery setting goes back to its default and the UI reloads.",
    button1 = "Reset everything", button2 = CANCEL or "Cancel", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
    OnAccept = function() VelocityChatFramesDB = nil; ReloadUI() end,
  }
  local rs = Section("Reset")
  local resetAll = CreateFrame("Button", nil, rs, "UIPanelButtonTemplate"); resetAll:SetSize(160, 22); resetAll:SetText("Reset all settings...")
  resetAll:SetScript("OnClick", function() StaticPopup_Show("VELOCITYCHATFRAMES_RESET_ALL") end)
  rs:Add(resetAll, 22, -10, 4)
  rs:Finish()

  content:SetHeight(-select(5, last:GetPoint(1)) + last:GetHeight() + 60)
  optionsFrame:SetScript("OnShow", function()
    Options.Refresh()
    local top = content:GetTop(); local bottom = last:GetBottom()
    if top and bottom then content:SetHeight(top - bottom + 40) end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "Velocity Chat Frames")
    Settings.RegisterAddOnCategory(optionsCategory)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
  end
end