# SPEC-VCF-03: Behaviour (Phase 0 kill-switch, windows, sticky, fade, settings)

- **Status:** Draft
- **Parent:** `00_VelocityChatFrames_Overview.md`
- **Ground truth:** `_ref\blizzard\README-chat-api-notes.md` sections *Stock mouseover reveal*, *Sticky*; `_ref\blizzard\FloatingChatFrame.lua` (live) `FCF_OnUpdate` 1120, `FCF_FadeInChatFrame` 1052, `FCF_FadeOutChatFrame` 1085; Era `classic_era\FloatingChatFrame.lua` 979 / 915.
- **Replaces from Prat:** `Fading.lua`, `ChannelSticky.lua` (minus SmartGroup), Frames "default alpha on mouseover".

- [ ] Phase 0: reveal kill-switch on every window
- [ ] Phase 0: settings DB, `/vcf`, options page with global Enable
- [ ] Phase 1: sticky channels
- [ ] Phase 1: line fade delay
- [ ] Disable path restores stock behaviour without reload

## Files

```
VelocityChatFrames\VelocityChatFrames\
  Core\Util.lua          print, table helpers
  Core\Settings.lua      VelocityChatFramesDB.settings defaults + NS.OnSettingChanged(key)
  Core\Windows.lua       enumerate chat windows, hooks for new/undocked windows, per-window record
  Core\Reveal.lua        Phase 0 kill-switch
  Core\Sticky.lua        ChatTypeInfo[type].sticky
  Core\Fading.lua        SetFading / SetTimeVisible on every window
  UI\Options.lua         settings page (pattern: VelocityQuestTracker\UI\Options.lua)
```

## Window enumeration (`Core\Windows.lua`)

- Source list: `CHAT_FRAMES` (names of windows that exist) is the stock authority; iterate `for i = 1, NUM_CHAT_WINDOWS do _G["ChatFrame"..i]`.
- A window record `VCF_WindowRecord` holds: `frame`, `tab = _G[name.."Tab"]`, `buttonFrame`, `scrollBar`, `scrollToBottom`, `resizeButton`, `texturePieces = {_G[name..piece] for piece in CHAT_FRAME_TEXTURES}`.
- New windows appear via `FCF_OpenNewWindow` / `FCF_OpenTemporaryWindow`; `hooksecurefunc` both and re-enumerate. Docking changes via `FCF_DockUpdate`; hook to re-apply.
- `IsCombatLog(frame)` is excluded from fade/line hooks (its contents are untouched) but its tab and chrome are included in Reveal and Theme.

## Phase 0: reveal kill-switch (`Core\Reveal.lua`)

The stock reveal fires from `FCF_OnUpdate` as a geometry poll (see Overview). The only non-taint suppression is to let it run and immediately undo it.

```
-- pseudocode
function Reveal.ApplyChrome(rec)        -- what every piece SHOULD look like right now
    alpha = NS.State.ChromeAlphaFor(rec) -- Phase 0: always the at-rest value
    for piece in rec.texturePieces: UIFrameFadeRemoveFrame(piece); piece:SetAlpha(rec.userBgAlpha)   -- user's window alpha, not 0, in Phase 0
    UIFrameFadeRemoveFrame(rec.tab); rec.tab:SetAlpha(tabRestAlpha)
    if rec.buttonFrame then UIFrameFadeRemoveFrame(rec.buttonFrame); rec.buttonFrame:SetAlpha(CHAT_FRAME_BUTTON_FRAME_MIN_ALPHA) end
    scrollbar / scrollToBottom -> 0
    GENERAL_CHAT_DOCK.overflowButton -> CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA

hooksecurefunc("FCF_FadeInChatFrame",  function(cf) if enabled then Reveal.ApplyChrome(rec(cf)) end end)
hooksecurefunc("FCF_FadeOutChatFrame", function(cf) if enabled then Reveal.ApplyChrome(rec(cf)) end end)
```

- `UIFrameFadeRemoveFrame` cancels the in-flight `UIFrameFadeIn` the stock function just queued; without it the fade animation would continue over our value.
- Phase 0 keeps the user's configured window background alpha (`rec.userBgAlpha` = alpha returned by `GetChatWindowInfo(id)`) so nothing changes except the hover reveal. Rest/Awake (Phase 2) and the zone band (Phase 3) take over this value later via `NS.State.ChromeAlphaFor`.
- Tab rest alpha: `select(2, ChatFrameUtil.GetTabAlphas(tab))` on Forever (noMouse alpha) — on Era the function may not exist; fall back to `CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA` / `CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA` by `tab == selected`. Put that in `Client\`.
- `FCF_FadeInChatFrame` recurses over the dock; hooking it per call is fine (idempotent).
- Disable: unhook is impossible with `hooksecurefunc`; the `enabled` guard is the switch. On disable call `FCF_FadeOutChatFrame` on every window once so the stock state is restored.

## Sticky (`Core\Sticky.lua`)

`ChatTypeInfo[TYPE].sticky = 1 or 0`, applied on `PLAYER_LOGIN` and on every setting change. Types offered, defaults = owner's Prat screenshot:

| Type | Default |
|---|---|
| SAY | on |
| YELL | off |
| PARTY | on |
| RAID | on |
| RAID_WARNING | on |
| INSTANCE_CHAT | off |
| GUILD | off |
| OFFICER | on |
| WHISPER (incoming reply) | off |
| BN_WHISPER | off |
| CHANNEL | off |
| EMOTE | off |

On Forever `ChatTypeInfo` is a proxy table (see notes) — index by key only, never `pairs`. SmartGroup is not ported.

## Fade delay (`Core\Fading.lua`)

- Setting `LineFadeSeconds` (default 15, range 1–240, 0 = never fade = `SetFading(false)`).
- Applied to every non-combat-log window at login, on new window, on setting change. Phase 2 state machine calls the same `Fading.ApplyRest(rec)` when entering Rest.
- `SetFadeDuration` left at stock (3 s).

## Settings (`Core\Settings.lua`, `UI\Options.lua`)

`VelocityChatFramesDB.settings` (account-wide; a per-character override is not needed). Defaults:

```
Enabled = true
LineFadeSeconds = 15
Sticky = { SAY=true, PARTY=true, RAID=true, RAID_WARNING=true, OFFICER=true, ... }
-- 01_LineFormatting
Timestamps = true, TimestampFormat = "%H:%M"
ShortChannelTags = true
ShowLevelInName = true, LevelColorByDifficulty = true
-- 02_Theme / Phase 2 (added when built)
```

Options page: copy of VQT's `Options.lua` pattern (scroll canvas, `Section`/`Check`/`Slider`, `Settings.RegisterCanvasLayoutCategory` with legacy fallback). First control under the intro is `Check("Enabled", "Enable Velocity Chat Frames")`. `NS.OnSettingChanged(key)` dispatches to the owning module. `/vcf` opens the page; `/vcf status` prints version and state.

Global disable must undo everything live: reveal guard off + one `FCF_FadeOutChatFrame` per window, sticky restored to stock (`sticky = ChatTypeInfo` original values captured at login), fading restored to 120 s, formatting hooks guarded by `enabled`.

## Open Questions

- Per-window fade delay (Prat had it per frame). Not ported until missed.
- Whether the Combat Log window should also get `LineFadeSeconds` (stock: it fades at 120 s like the others).