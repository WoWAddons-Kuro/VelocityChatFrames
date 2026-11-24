# SPEC-VelocityChatFrames: Overview

- **Status:** Living (first draft 2026-11-23; state machine removed the same day after play, see *Alternatives Considered*)
- **Addon name / TOC / slash:** `VelocityChatFrames`, `/vcf`
- **Target:** WoW Forever (`_forever_`, 16001) primary; Classic Era verified. Stock chat code is Mainline-shaped on Forever and Classic-shaped on Era, but the message-frame Lua is identical on both (see ground truth).
- **Ground truth:** `_ref\blizzard\README-chat-api-notes.md` (sections *ScrollingMessageFrame*, *Stock mouseover reveal*, *Tabs*, *Uninteractable flag*, *Sticky*, *Sender name decoration*), with the source files beside it:
  `ScrollingMessageFrame.lua` (live = Era, byte-identical), `FloatingChatFrame.lua` (live), `classic_era\FloatingChatFrame.lua`, `ChatFrameOverrides.Mainline.lua`, `classic_era\ChatFrameOverrides.Classic.lua`, `ChatFrameUtil.live.lua`, `ChatFrameFilters.lua`, `FloatingChatFrame.Mainline.xml`, `forever\EditMode\EditModeSystemTemplates.lua`, `forever\EditMode\EditModeManager.lua`.
- **Sibling specs:**
  - `01_LineFormatting.md` — timestamps, short channel tags, level-in-name (the Prat features being replaced)
  - `02_Theme.md` — flat frame, flat tabs, zone-brightness adjustment (LibZoneBrightness); theme style selector
  - `03_Behaviour.md` — reveal kill-switch, wheel reveal, fade timers, hide buttons, edit box, tab menu, text selection, Edit Mode
- **Related:** `VelocityQuestTracker\SPECS\SPEC-VelocityQuestTracker.md` (shared principles), `LibZoneBrightness\README.md`, `Prat-3.0\modules\` (reference for what is being replaced)

## Goal

Replace Prat with a small addon that does only what the owner actually uses, and fix the two things the stock chat frames do wrong over a world view:
they reveal themselves whenever the pointer wanders near them, and they occupy input over a large rectangle of the screen. The owner runs several
chat windows spread over the screen, so both problems scale with window count.

Delivery order is fixed by tolerance: the owner must be able to switch off Prat on day one.

- [x] **Phase 0 — Reveal kill-switch.** Stock mouseover reveal does nothing on any chat window. (`03_Behaviour.md`) — `1e7d68f`, tab follow-ups `bbd772c` `ce68eb5` `0997b33` `9e889a7` `696eea4`
- [x] **Phase 1 — Prat replacement minimum.** Timestamps, `[G]`-style channel tags, `[level:Name]`, sticky channels, 15 s line fade. (`01_LineFormatting.md`, `03_Behaviour.md`) — `1e7d68f`/`18773ac`. `[level:Name]` is **not yet appearing in play** (todo 13); numbered-channel tags still stock (todo 14).
- [x] **Phase 1b — Everything Prat did that the owner used, beyond the list.** Hide-button checkboxes, floating/locked edit box hidden when idle, in-window text selection with review window, wheel reveal, revealed background colour/opacity with bright-zone boost, tabs at window alpha and dead when transparent, Edit Mode full reveal, Unlock/Lock Window + resize grip, Friends List and Frame Fade Settings on the tab menu, Edit Mode drag frames for the input box and floating windows. (`03_Behaviour.md`) — `18773ac` … `5d0d534`
- [ ] **Phase 2 — Fade timers.** Hover pauses fading (passes motion through to the world); a line you sent holds every window's lines for a longer, configurable time. (`03_Behaviour.md`) — edited, awaiting confirmation (todo 12)
- [ ] **Phase 3 — Theme.** Force-transparent backgrounds; progressive top-to-bottom line fade; theme style selector (Automatic / Classic / Velocity Modern); flat tabs; zone-brightness text factor. (`02_Theme.md`) — todos 15–17

## Principles

1. **Absent at rest.** At rest the chat area passes hover and clicks to the world as if no frame were there. Transparent chrome takes no mouse.
2. **Wake on intent.** Passing the pointer over the area never *reveals* anything. The mouse wheel does; it is the one deliberate input a resting frame takes. Hovering may *hold* what is already visible (Phase 2) without blocking the world beneath.
3. **Text is not chrome.** Incoming lines are information and always show. Background, tabs and scroll controls are chrome and show only on request.
4. **No sampling.** State changes come from input events and from the message frame's own refresh callback. The only ticker is the wheel-reveal fade-out, and it runs only while something is fading.
5. **Instant-read indicators.** Anything that answers "which one is active?" is a flat tone change, never a glow or a gradient. Pulsing is reserved for things understood over time (alerts).
6. **Never touch stock persisted settings.** `SetChatWindowUninteractable`, `FCF_SetWindowAlpha`, `ChatTypeInfo` colours stay as the user set them. VCF drives frame properties directly and restores them on disable. (Exceptions, each deliberate and restored on disable: `chatStyle` = `im` while the edit box floats; `showTimestamps` when timestamps are on.)
7. **Commit only what the owner has confirmed in game.** One commit per confirmed change; git history is the CurseForge changelog. (`AddonManagement\PROJECT_STRUCTURE.md`.)

## Why the stock reveal fires "for no reason"

`FCF_OnUpdate` runs every frame and tests `chatFrame:IsMouseOver(28, -2, -2, 2)` plus the tab, button column, scrollbar and QuickJoin button. It is a geometry test:
it fires with mouse input off, at alpha 0, and over a rectangle 28 px taller than the visible window. After `CHAT_TAB_SHOW_DELAY` (0.2 s on Forever, **0 s on Era**) it calls
`FCF_FadeInChatFrame`, which fades the background pieces, tab, button frame and scrollbar up. Prat's "default alpha on mouseover" only lowers the target alpha; it never stops the reveal.

**Kill-switch:** `hooksecurefunc("FCF_FadeInChatFrame", Reveal.ApplyChrome)` and immediately set our own alphas on every piece it touched; likewise `FCF_FadeOutChatFrame`, `FCFTab_UpdateAlpha`, `FCFDock_UpdateTabs`, `FCF_DockUpdate`, `FCFDock_SelectWindow`, `FCF_SetWindowAlpha`. No taint: the stock function runs to completion, then we overwrite the alphas. Unselected docked windows are *hidden* while their tabs are shown, so every pass must include docked windows regardless of `IsShown()`.

## The rest model (what replaced the state machine)

There is one state. Every window is at rest unless one of three things is true, each of which ends by itself:

| Trigger | What shows | Ends |
|---|---|---|
| **Mouse wheel over a window** | That window's background at the configured colour/opacity and every tab in its dock (active at 100 %, inactive at 50 %) | Follows the line-fade curve exactly: held for `LineFadeSeconds`, then fades over the stock 3 s |
| **Pointer over a window** (Phase 2) | Nothing new; lines already visible stop fading | On leave every line gets a fresh delay (`ResetAllFadeTimes`) |
| **A line you sent** (Phase 2) | Nothing new; every window holds its lines for `OwnInputFadeSeconds` | Timer |
| **Edit Mode open** | Everything, nothing fades | Edit Mode closes |

Chat frame mouse: clicks and motion off at rest; `EnableMouseWheel(true)` always. Transparent tabs (≤ 5 % alpha) are `EnableMouse(false)`. Hover sensing for Phase 2 uses `SetPropagateMouseMotion(true)` so the world still receives the pointer; where that API is absent the hover-pause setting is greyed out rather than enabled at the cost of world hover.

### Line visibility (the display-refresh hook)

`ScrollingMessageFrame.lua` (identical on both clients) recomputes every visible line's text, colour and alpha in `RefreshDisplay()`, then calls the callbacks registered with
`chatFrame:AddOnDisplayRefreshedCallback(fn)`. Its own `UpdateFading()` only runs when `SetFading(true)`. The callback is where Phase 3's per-line work lives (progressive top-to-bottom fade, zone-brightness colour factor). It never reads `messageInfo.message`, so secret values in instances do not matter.

## API surface

Verified against `_ref\blizzard\`.

**Frame input** — `EnableMouse`, `EnableMouseWheel`, `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetHyperlinksEnabled`, `SetPropagateMouseMotion` (feature-detected), `SetClampRectInsets`, scripts `OnMouseWheel`, `OnEnter`, `OnLeave`.

**Chat frames** — `ChatFrame1..N`, `NUM_CHAT_WINDOWS`, `CHAT_FRAMES`, `FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)`, `FCFDock_GetSelectedWindow`; per window `_G[name.."Tab"]`, `.buttonFrame`, `.ScrollBar`, `.ScrollToBottomButton`, `.ResizeButton`, `.Selection` (ChatFrame1 only, Edit Mode), the pieces in `CHAT_FRAME_TEXTURES` (only `Background` is painted by the reveal; the eight border pieces sit outside the frame rect); `GENERAL_CHAT_DOCK.overflowButton`.
Stock reveal: `FCF_FadeInChatFrame`, `FCF_FadeOutChatFrame`, `FCFTab_UpdateAlpha`, `ChatFrameUtil.GetTabAlphas/SetTabAlphas`, `DEFAULT_CHATFRAME_ALPHA`.

**Message lines** — `SetFading`, `SetTimeVisible`, `SetFadeDuration`, `GetFadeDuration`, `ResetAllFadeTimes`, `SetTextCopyable`, `GatherSelectedText`, `ScrollToBottom`, `AtBottom`, `MarkDisplayDirty`, `AddOnDisplayRefreshedCallback(fn)`, `frame.visibleLines[i].messageInfo = { message, r, g, b, timestamp }`.

**Sender names** — `ChatFrameUtil.AddSenderNameFilter(fn(event, decoratedName, ...))`, secret-safe on both clients. Channel prefixes via `CHAT_<TYPE>_GET` globals; numbered channels are prefixed separately inside the handler.

**Tab menu** — `Menu.ModifyMenu("MENU_FCF_TAB", fn(owner, rootDescription))`.

**Edit Mode** — `EditModeManagerFrame:IsEditModeActive()`, `EditModeChatFrameSystemTemplate` (Selection at TOPLEFT x=-32 y=+60 / BOTTOMRIGHT x=+25 y=-32), `EditModeSystemMixin:UpdateClampOffsets`, `AnchorSelectionFrame`; LibEditMode (vendored) for placeholders.

**Protected / unavailable to addons** — `CopyToClipboard` (hence the review window + Ctrl+C).

**Forever** — chat frames are not protected. Chat text reaches addons as secret values inside instances; VCF never reads `messageInfo.message` in its hooks. Sender/level lookups are guarded with `issecretvalue`.

## Open Questions

- **Whispers.** Whether an incoming whisper should count like own input and hold lines.
- **Return to rest after a wheel reveal.** Lines that were older than the fade delay vanish at once when the hold ends; whether they should share one fade-out (`ResetAllFadeTimes` on reveal would do it).
- **ChatFrame1 and Edit Mode (parked).** Edit Mode commits `GetWidth()` on every drag, so any width VCF adds is persisted and stacks. Options: VCF owns ChatFrame1's position/size outright (re-apply after `RefreshSystemPosition` / `UpdateSystemSettingWidth/Height`), or leave as is. Owner: acceptable as is for now.
- ~~**Intermittent lost hover/clicks over chat rects**~~ — cause found: stock chat tabs are `EnableMouse(true)` Buttons at any alpha; every invisible docked tab was a dead strip. `696eea4` turns mouse off on any tab at or below 5 % alpha. Resolved.

## Alternatives Considered

- **A Rest → Awake → Review → Chrome state machine driven by modifier clicks** (the original draft). Removed 2026-11-23 after the first days of play: the mouse wheel already reveals, and that is the more natural gesture; modifier clicks on a transparent area were a solution to a problem the wheel had solved. What remained worth keeping from that design is in *The rest model* above: hover holds, own input holds.
- **Wake on hover with a delay, or from a hot zone.** Needs the frame to sense motion. With `SetPropagateMouseMotion` the sensing is possible without blocking the world, but revealing on hover is still the wrong gesture (Principle 2); hover only *holds*.
- **Stock "Make Non-Interactive" alone.** Gives hover-through, but kills links and scrolling until changed back by hand, and it is a persisted user setting. VCF never writes the flag.
- **Replacing the chat frame.** Far more work; Forever restricts what addons can do with chat content. Changing the stock frame's behaviour is enough.
- **Alpha wash over the text to darken it in dark zones.** A texture over the chat rect darkens the world behind the text too; there is no text-only blend. Per-line colour factor in the refresh callback achieves the goal without touching configured colours.
- **Widening ChatFrame1 by the Edit Mode gutter.** Edit Mode saves `GetWidth()` on every drag; the extra width stacked. Removed.
- **Holding keyboard focus in a hidden EditBox for Ctrl+C during text selection.** Blocked movement keys for the whole session. Replaced by a review window that appears on each drag release.