# SPEC-VCF-03: Behaviour (reveal, fade timers, windows, chrome, edit box, tab menu, selection, Edit Mode)

- **Status:** Draft
- **Parent:** `00_VelocityChatFrames_Overview.md`
- **Ground truth:** `_ref\blizzard\README-chat-api-notes.md` sections *Stock mouseover reveal*, *Sticky*; `_ref\blizzard\FloatingChatFrame.lua` (live) `FCF_OnUpdate` 1120, `FCF_FadeInChatFrame` 1052, `FCF_FadeOutChatFrame` 1085, `FCFTab_UpdateAlpha` 1307; Era `classic_era\FloatingChatFrame.lua` 979 / 915.
- **Replaces from Prat:** `Fading.lua`, `ChannelSticky.lua` (minus SmartGroup), Frames "default alpha on mouseover".

- [x] Phase 0: reveal kill-switch on every window (`Core\Reveal.lua`; also hooks `FCFTab_UpdateAlpha`, `FCFDock_UpdateTabs`, `FCFDock_SelectWindow`, `FCF_SetWindowAlpha`)
- [x] Phase 0: settings DB, `/vcf`, options page with global Enable
- [x] Phase 1: sticky channels
- [x] Phase 1: line fade delay
- [x] Disable path restores stock behaviour without reload
- [x] Tabs at rest take the displayed window's background alpha (`TabsMatchWindowAlpha`; docked tabs follow the dock's selected window)
- [x] Hide chat buttons, one checkbox each (`Core\Chrome.lua`); floating/locked edit box hidden when idle (`Core\EditBox.lua`)
- [x] In-window text selection from the tab menu, 10 s idle timeout, review window + Ctrl+C (`Core\CopyText.lua`). `CopyToClipboard` is protected; no addon button can write the clipboard.
- [x] Wheel reveal: background at configured colour/opacity (+bright-zone boost), tabs (active 100 %, inactive 50 %), timed to the line fade; Edit Mode = full reveal, no fade (`Core\Reveal.lua`)
- [x] Tab menu: Unlock/Lock Window + resize grip for General, Friends List (with binding) when the social button is hidden, Frame Fade Settings… (`Core\TabMenu.lua`)
- [x] Edit Mode: ChatFrame1 Selection re-anchored to the frame's horizontal edges while the column is hidden; drag frames for the input box and floating windows via vendored LibEditMode (`Core\EditModeLayout.lua`)
- [ ] **Phase 2 — fade timers** (`Core\Fading.lua`, edited, awaiting confirmation):
  - Hover pauses fading: `SetMouseMotionEnabled(true)` + `SetPropagateMouseMotion(true)` so `OnEnter`/`OnLeave` fire while the world beneath still gets the pointer. While over: `SetFading(false)`. On leave: `ResetAllFadeTimes()` then the rest delay, so what you were reading gets a fresh 15 s instead of vanishing. If `SetPropagateMouseMotion` is absent the option is greyed out — motion without propagation would block world hover, which is the one thing this addon exists to prevent.
  - Own input holds lines: on any `CHAT_MSG_*` whose sender is `Client.PlayerFirstName()` (or any `*_INFORM`), **only the window(s) that displayed that line** get `SetTimeVisible(OwnInputFadeSeconds)` for that long, then fall back. Receiving windows are detected by a `hooksecurefunc(frame, "AddMessage")` stamp compared against the event's `GetTime()` tick (checked one tick later via `C_Timer.After(0)`), so stock routing/filters are honoured without re-implementing them. **Never `ResetAllFadeTimes()`** — that re-stamped every line in every window as "shown now" and un-hid everything on each sent message (bug fixed 2026-11-24). Secret senders are skipped (they never equal a plain string).
  - Settings: `HoverPausesFade` (on), `OwnInputExtendsFade` (on), `OwnInputFadeSeconds` (30; 5–180).

## Click-through baseline and pending interactions

- **Confirmed, committed `e1a5c19`:** reset whole-frame mouse/click input at startup, on new windows, and after selection ends. Preserve wheel and motion settings separately.
- **Confirmed by owner:** native username hyperlinks remain clickable with whole-frame clicks disabled. No Shift requirement and no mirror-window rewrite are needed. The standalone SMF remains a diagnostic only.
- Selection stays active across repeated drags; timeout or closing the copy popup relinquishes click input.
- **Implemented, awaiting explicit test confirmation:** username-click input placement radio options: bottom of clicked window (default), or main placed input position. Preserve the stock recipient; temporarily reposition the opened edit box and restore its anchors on focus loss.
- **Implemented, awaiting explicit test confirmation:** unlocked windows keep text, background and tabs visible until locked. General's VCF unlock and floating windows' stock lock state are both considered.
- **Implemented, awaiting explicit test confirmation:** dragging a chat tab over a visible window reveals its background and dock tabs as a drop target, then releases the temporary hold when the drag ends.
- These operations must not turn whole-frame click capture back on outside explicit selection.

## Module map (as built)

```
Core\Reveal.lua         kill-switch, wheel reveal, tab alpha/mouse, Edit Mode full reveal
Core\Fading.lua         rest / hover / own-input fade timers
Core\HideButtons.lua    the hide-button checkboxes, column collapse
Core\EditModeLayout.lua everything Edit Mode: Selection insets, clamp, LibEditMode placeholders
Core\EditBox.lua        floating/locked box, hidden when idle, chatStyle=im
Core\TabMenu.lua        our items on MENU_FCF_TAB
Core\CopyText.lua       in-window selection + review window
Core\Sticky.lua, Core\Windows.lua, Core\Settings.lua, UI\Options.lua
```

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
    alpha = CurrentRevealAlpha(rec) -- rest value or timed wheel reveal
    for piece in rec.texturePieces: UIFrameFadeRemoveFrame(piece); piece:SetAlpha(rec.userBgAlpha)   -- user's window alpha, not 0, in Phase 0
    UIFrameFadeRemoveFrame(rec.tab); rec.tab:SetAlpha(tabRestAlpha)
    if rec.buttonFrame then UIFrameFadeRemoveFrame(rec.buttonFrame); rec.buttonFrame:SetAlpha(CHAT_FRAME_BUTTON_FRAME_MIN_ALPHA) end
    scrollbar / scrollToBottom -> 0
    GENERAL_CHAT_DOCK.overflowButton -> CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA

hooksecurefunc("FCF_FadeInChatFrame",  function(cf) if enabled then Reveal.ApplyChrome(rec(cf)) end end)
hooksecurefunc("FCF_FadeOutChatFrame", function(cf) if enabled then Reveal.ApplyChrome(rec(cf)) end end)
```

- `UIFrameFadeRemoveFrame` cancels the in-flight `UIFrameFadeIn` the stock function just queued; without it the fade animation would continue over our value.
- At rest use the user's configured window background alpha. Wheel reveal temporarily uses the configured reveal colour/opacity plus the additive bright-zone boost; no modifier-click states are involved.
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
- Applied to every non-combat-log window at login, on new window, and on setting change. No modifier-click state machine is planned.
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