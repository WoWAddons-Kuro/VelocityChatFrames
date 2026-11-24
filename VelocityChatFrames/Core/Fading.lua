-- Velocity Chat Frames: how long a chat line stays before it fades. SetFading/SetTimeVisible on
-- every non-combat-log window. Phase 2 will call Fading.ApplyRest(rec) on entering Rest.
local ADDON_NAME, NS = ...
local Settings, Windows = NS.Settings, NS.Windows

local Fading = {}
NS.Fading = Fading

local STOCK_TIME_VISIBLE = 120

function Fading.ApplyRest(rec)
  if rec.isCombatLog then return end
  local secs = Settings.Get().LineFadeSeconds or 15
  -- In Edit Mode nothing fades, so the window you are placing shows its text.
  local editing = NS.Reveal and NS.Reveal.InEditMode and NS.Reveal.InEditMode()
  if secs <= 0 or editing then
    rec.frame:SetFading(false)
  else
    rec.frame:SetFading(true)
    rec.frame:SetTimeVisible(secs)
  end
end

function Fading.ApplyAll()
  for _, rec in ipairs(Windows.All()) do Fading.ApplyRest(rec) end
end

function Fading.Restore()
  for _, rec in ipairs(Windows.All()) do
    if not rec.isCombatLog then rec.frame:SetFading(true); rec.frame:SetTimeVisible(STOCK_TIME_VISIBLE) end
  end
end

function Fading.Init()
  Windows.OnNewRecord(function(rec) if Settings.IsEnabled() then Fading.ApplyRest(rec) end end)
  if Settings.IsEnabled() then Fading.ApplyAll() end
end

Settings.OnChange("LineFadeSeconds", function() if Settings.IsEnabled() then Fading.ApplyAll() end end)
Settings.OnChange("Enabled", function() if Settings.IsEnabled() then Fading.ApplyAll() else Fading.Restore() end end)