-- Velocity Chat Frames: enumerates the stock chat windows and keeps one record per window with
-- handles to every piece the stock reveal touches. See SPECS\03_Behaviour.md "Window enumeration".
local ADDON_NAME, NS = ...
local Util = NS.Util

local Windows = {}
NS.Windows = Windows

-- VCF_WindowRecord: { frame, id, name, tab, buttonFrame, scrollBar, scrollToBottom, resizeButton,
--                     texturePieces = { Texture... }, background = Texture, isCombatLog = bool }
local recordsByFrame = {}      -- frame -> VCF_WindowRecord
local recordList = {}          -- ordered array of records
local onNewRecord = {}         -- callbacks fn(rec)

function Windows.OnNewRecord(fn) table.insert(onNewRecord, fn) end

local function IsCombatLogFrame(frame)
  if IsCombatLog then return IsCombatLog(frame) end
  return frame == _G.ChatFrame2 and frame.name == COMBAT_LOG
end

local function BuildRecord(frame)
  local name = frame:GetName()
  local rec = {
    frame = frame, id = frame:GetID(), name = name,
    tab = _G[name .. "Tab"],
    buttonFrame = frame.buttonFrame or _G[name .. "ButtonFrame"],
    scrollBar = frame.ScrollBar,
    scrollToBottom = frame.ScrollToBottomButton,
    resizeButton = frame.ResizeButton,
    texturePieces = {},
    background = _G[name .. "Background"],
    isCombatLog = IsCombatLogFrame(frame),
  }
  for _, piece in ipairs(CHAT_FRAME_TEXTURES or {}) do
    local tex = _G[name .. piece]
    if tex then table.insert(rec.texturePieces, tex) end
  end
  return rec
end

function Windows.Get(frame) return frame and recordsByFrame[frame] end
function Windows.All() return recordList end

function Windows.Refresh()
  local max = NUM_CHAT_WINDOWS or 10
  for i = 1, max do
    local frame = _G["ChatFrame" .. i]
    if frame and not recordsByFrame[frame] then
      local rec = BuildRecord(frame)
      recordsByFrame[frame] = rec
      table.insert(recordList, rec)
      for _, fn in ipairs(onNewRecord) do
        local ok, err = pcall(fn, rec)
        if not ok then Util.Raise("Windows.OnNewRecord", err) end
      end
    else
      local rec = recordsByFrame[frame]
      if rec then rec.isCombatLog = IsCombatLogFrame(frame) end
    end
  end
end

-- Windows that are open and shown (CHAT_FRAMES holds names of existing windows; temporary
-- windows are created on demand and picked up by the hooks below).
function Windows.Init()
  Windows.Refresh()
  if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", Windows.Refresh) end
  if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", Windows.Refresh) end
end