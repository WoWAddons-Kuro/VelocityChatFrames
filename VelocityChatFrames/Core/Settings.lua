-- Velocity Chat Frames: saved settings (account-wide, VelocityChatFramesDB.settings) and the
-- change-dispatch that modules subscribe to. See SPECS\03_Behaviour.md "Settings".
local ADDON_NAME, NS = ...
local Util = NS.Util

local Settings = {}
NS.Settings = Settings

Settings.DEFAULTS = {
  Enabled = true,

  -- 03_Behaviour
  LineFadeSeconds = 15,                      -- 0 = never fade
  LineFadeDurationSeconds = 3,               -- how long the fade-out itself takes once a line is due (stock 3; 0 = instant)
  HoverPausesFade = true,                    -- pointer over a window: nothing fades; on leave, fresh delay
  OwnInputExtendsFade = true,                -- after a line you sent, hold lines longer
  OwnInputFadeSeconds = 30,                  -- how long (5..180)
  Sticky = {
    SAY = true, YELL = false, PARTY = true, RAID = true, RAID_WARNING = true,
    INSTANCE_CHAT = false, GUILD = false, OFFICER = true, WHISPER = false,
    BN_WHISPER = false, CHANNEL = false, EMOTE = false,
  },

  -- 04_ScrollbackRestore
  ScrollbackRestore = true,                  -- lines survive login / reload
  ScrollbackWhispers = true,                 -- recent whispers follow you across characters (per realm on Era)
  ScrollbackInColor = true,                  -- keep colours/links; off = grey plain text
  ScrollbackLines = 100,                     -- per window (50..500)
  WhisperLines = 20,                         -- shared journal size (10..50)
  ScrollbackGraceMinutes = 10,               -- lines visible at logout stay visible if back within this (5..60)

  -- 01_LineFormatting
  Timestamps = true,
  TimestampFormat = "%H:%M",
  ShortChannelTags = true,
  ShowLevelInName = true,
  LevelColorByDifficulty = true,

  -- Chrome (03_Behaviour)
  TabsMatchWindowAlpha = true,
  WheelRevealsBackground = true,
  WheelRevealsTabs = true,
  -- Revealed background: black at 0.3 alpha (= 30 % opaque, 70 % see-through)
  RevealBackground = { r = 0, g = 0, b = 0, a = 0.3 },
  -- Added to the alpha above when LibZoneBrightness says the terrain is "bright"
  RevealBrightZoneBoost = 0.3,
  -- Unselected tabs reveal to this alpha (selected tab goes to 1.0) so active reads at a glance
  InactiveTabRevealAlpha = 0.5,
  HideMenuButton = true,
  HideSocialButton = true,
  HideChannelButton = true,
  HideVoiceButtons = true,
  HideScrollButtons = true,

  -- Edit box
  EditBoxFloat = true,
  AlwaysMainInputLocation = true,
  EditBoxLocked = true,
  EditBoxHideWhenIdle = true,
  UsernameInputPlacement = "clicked",       -- clicked window bottom, or "main" placed input position
  EditBoxX = nil, EditBoxY = nil, EditBoxW = nil,
}

-- Listeners: key -> { fn, fn, ... }. "*" receives every change.
local listeners = {}

function Settings.OnChange(key, fn)
  listeners[key] = listeners[key] or {}
  table.insert(listeners[key], fn)
end

function NS.OnSettingChanged(key)
  local function fire(list) if list then for _, fn in ipairs(list) do fn(key) end end end
  fire(listeners[key])
  fire(listeners["*"])
end

function Settings.Init()
  VelocityChatFramesDB = VelocityChatFramesDB or {}
  VelocityChatFramesDB.settings = Util.ApplyDefaults(VelocityChatFramesDB.settings or {}, Settings.DEFAULTS)
  NS.db = VelocityChatFramesDB
  return NS.db.settings
end

function Settings.Get() return NS.db.settings end
function Settings.IsEnabled() return NS.db and NS.db.settings.Enabled end