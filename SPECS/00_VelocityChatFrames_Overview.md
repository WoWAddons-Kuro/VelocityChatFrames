# SPEC-VelocityChatFrames: Overview

- **Status:** Draft (reviewed 2026-11-23)
- **Addon name / TOC / slash:** `VelocityChatFrames`, `/vcf`
- **Target:** WoW Forever (`_forever_`, 16001) primary; Classic Era verified. Stock chat code is Mainline-shaped on Forever and Classic-shaped on Era, but the message-frame Lua is identical on both (see ground truth).
- **Ground truth:** `_ref\blizzard\README-chat-api-notes.md` (sections *ScrollingMessageFrame*, *Stock mouseover reveal*, *Tabs*, *Uninteractable flag*, *Sticky*), with the source files beside it:
  `ScrollingMessageFrame.lua` (live = Era, byte-identical), `FloatingChatFrame.lua` (live), `classic_era\FloatingChatFrame.lua`, `ChatFrameOverrides.Mainline.lua`, `classic_era\ChatFrameOverrides.Classic.lua`.
- **Sibling specs:**
  - `01_LineFormatting.md` — timestamps, short channel tags, level-in-name (the Prat features being replaced)
  - `02_Theme.md` — flat frame, flat tabs, zone-brightness adjustment (LibZoneBrightness)
  - `03_Behaviour.md` — sticky channels, line fade delay, which windows
- **Related:** `VelocityQuestTracker\SPECS\SPEC-VelocityQuestTracker.md` (shared principles), `LibZoneBrightness\README.md`, `Prat-3.0\modules\` (reference for what is being replaced)

## Goal

Replace Prat with a small addon that does only what the owner actually uses, and fix the two things the stock chat frames do wrong over a world view:
they reveal themselves whenever the pointer wanders near them, and they occupy input over a large rectangle of the screen. The owner runs several
chat windows spread over the screen (see `Assets\Screenshots` once added), so both problems scale with window count.

Delivery order is fixed by tolerance: the owner must be able to switch off Prat on day one.

- [x] **Phase 0 — Reveal kill-switch.** Stock mouseover reveal does nothing on any chat window. Shippable alone. (`03_Behaviour.md`) — shipped `1e7d68f`; tab-alpha follow-ups `bbd772c` `ce68eb5` `0997b33`
- [x] **Phase 1 — Prat replacement minimum.** Timestamps, `[G]`-style channel tags, `[level:Name]`, sticky channels, 15 s line fade. (`01_LineFormatting.md`, `03_Behaviour.md`) — shipped `1e7d68f`/`18773ac`; `[level:` on own lines still to be confirmed in play. Also delivered beyond the original list: hide-buttons checkboxes, floating/locked edit box hidden when idle, in-window text selection with review window (`add5654`…`ed2b6d0`)
- [ ] **Phase 2 — Rest / Awake / Review / Chrome.** The input and visibility state machine below, with the Awake cutoff. (this file)
- [ ] **Phase 3 — Flat theme and tabs.** Single-tone active tab, no glow, flat background; background alpha follows zone brightness. (`02_Theme.md`)
- [ ] **Phase 4 — Zone-brightness text adjustment.** Per-line colour factor by band via the display-refresh hook. (`02_Theme.md`)
- [ ] Settings panel

## Principles

1. **Absent at rest.** At rest the chat area passes hover and clicks to the world as if no frame were there.
2. **Wake on intent.** Passing the pointer over the area never reveals anything. Deliberate acts do.
3. **Text is not chrome.** Incoming lines are information and always show. Background, tabs and scroll controls are chrome and show only on request.
4. **No sampling.** State changes come from input events and from the message frame's own refresh callback. No `OnUpdate` tickers.
5. **Instant-read indicators.** Anything that answers "which one is active?" is a flat tone change, never a glow or a gradient. Pulsing is reserved for things understood over time (alerts).
6. **Never touch stock persisted settings.** `SetChatWindowUninteractable`, `FCF_SetWindowAlpha`, `ChatTypeInfo` colours stay as the user set them. VCF drives frame properties directly and restores them on disable.

## Why the stock reveal fires "for no reason"

`FCF_OnUpdate` runs every frame and tests `chatFrame:IsMouseOver(28, -2, -2, 2)` plus the tab, button column, scrollbar and QuickJoin button. It is a geometry test:
it fires with mouse input off, at alpha 0, and over a rectangle 28 px taller than the visible window. After `CHAT_TAB_SHOW_DELAY` (0.2 s on Forever, **0 s on Era**) it calls
`FCF_FadeInChatFrame`, which fades the background pieces, tab, button frame and scrollbar up. Prat's "default alpha on mouseover" only lowers the target alpha; it never stops the reveal.

**Kill-switch:** `hooksecurefunc("FCF_FadeInChatFrame", VCF_ReapplyFrameChrome)` and immediately set our own alphas on every piece it touched. Also hook `FCF_FadeOutChatFrame` for symmetry. No taint: the stock function runs to completion, then we overwrite the alphas.

## States

| State | Background | Lines shown | Chrome (tab, scroll, buttons) | Chat frame mouse |
|---|---|---|---|---|
| **Rest** | None | New lines appear, fade after the fade delay (15 s) | None | Off, except the mouse wheel |
| **Awake** | Shown | Lines visible at the moment of waking stay; new lines stay; older lines remain hidden | None | On |
| **Review** | Shown | All lines, including older ones | None | On |
| **Chrome** | Shown | All lines | Tabs, scroll controls, button column | On |

### Transitions

| Input | Effect |
|---|---|
| Modifier + left click on the chat area | Step forward: Rest → Awake → Review → Chrome (stops at Chrome) |
| Modifier + right click on the chat area | Return to Rest |
| Mouse wheel over the chat area, in Rest or Awake | Go to Review |
| Mouse wheel in Review or Chrome | Scroll as normal |
| Pointer leaves the window for `restAfterLeaveSecs` (default 5, 0 = never) in any non-Rest state | Return to Rest |
| Press Enter to open the edit box | Rest → Awake (setting, default on) |

The modifier is a setting; Alt is the default (Shift and Ctrl clicks have stock meanings on links and world objects). While the modifier is held, the overlay blocks world hover over the chat rect; this is the accepted cost.

On return to Rest the frame scrolls to the bottom and lines resume their normal fade.

### Mouse input model

Three inputs are controlled separately.

- **Chat frame clicks and motion.** Off at Rest (`SetMouseClickEnabled(false)`, `SetMouseMotionEnabled(false)`, `SetHyperlinksEnabled(false)`). On in Awake, Review and Chrome so links and text selection work.
- **Chat frame mouse wheel.** `EnableMouseWheel(true)` in every state. At Rest this is the only input the frame takes; it is what lets a wheel movement open Review. Known side effect: the wheel does not zoom the camera over the chat rect (stock behaviour today).
- **Overlay.** One transparent frame per chat window, above the window, tab and button column (`SetFrameStrata` one above the chat frame, high frame level). `EnableMouse` is toggled by `MODIFIER_STATE_CHANGED` so it takes clicks only while the modifier is held. It catches the modifier clicks in every state.

Rest applies to **every** chat window, docked or floating. The dock's shared pieces (`GENERAL_CHAT_DOCK.overflowButton`) and each window's `buttonFrame`, `ScrollBar`, `ScrollToBottomButton`, `ResizeButton` and `ChatFrameNTab` are chrome and are hidden/mouse-off at Rest. The Combat Log window's *contents* are left alone; its tab is themed with the others.

```
-- pseudocode — illustrative only
state = REST

on MODIFIER_STATE_CHANGED:
    for each overlay: overlay:EnableMouse(ModifierIsDown())

on overlay OnMouseDown(button):
    if button == LEFT  then SetState(Next(state))
    if button == RIGHT then SetState(REST)

on chatFrame OnMouseWheel(delta):
    if state == REST or state == AWAKE then SetState(REVIEW) else ScrollNormally(delta) end

on chatFrame OnLeave:  StartRestTimer()   -- C_Timer.After, cancelled by OnEnter

function SetState(s):
    state = s
    if s == AWAKE then cutoffTimestamp = GetTime() end
    chatFrame:SetMouseClickEnabled(s ~= REST); chatFrame:SetMouseMotionEnabled(s ~= REST); chatFrame:SetHyperlinksEnabled(s ~= REST)
    chatFrame:SetFading(s == REST)
    background.alpha = (s ~= REST) and ZB:AdjustAlpha(bgAlpha) or 0
    chrome.alpha     = (s == CHROME) and 1 or 0
    if s == REST then chatFrame:ScrollToBottom() end
    chatFrame:MarkDisplayDirty()           -- forces RefreshDisplay -> our callback
```

### Line visibility (the display-refresh hook)

`ScrollingMessageFrame.lua` (identical on both clients) recomputes every visible line's text, colour and alpha in `RefreshDisplay()`, then calls the callbacks registered with
`chatFrame:AddOnDisplayRefreshedCallback(fn)`. Its own `UpdateFading()` only runs when `SetFading(true)`. So:

- **Rest:** `SetFading(true)`, `SetTimeVisible(fadeDelay)`. Stock per-line fading. Our callback does nothing to alpha.
- **Review, Chrome:** `SetFading(false)`. Every line shows at alpha 1.
- **Awake:** `SetFading(false)`; in the callback, for each `visibleLine` with `messageInfo`: `SetShown(messageInfo.timestamp >= cutoffTimestamp)`. New lines are always newer than the cutoff. Nothing fades while awake and no ticker is needed.

```
-- pseudocode — illustrative only
chatFrame:AddOnDisplayRefreshedCallback(function(frame)
    for _, line in ipairs(frame.visibleLines) do
        local info = line.messageInfo
        if info then
            if state == AWAKE then line:SetShown(info.timestamp >= cutoffTimestamp) end
            ApplyZoneTint(line, info)      -- 02_Theme.md, phase 4
        end
    end
end)
```

The same callback is where the zone-brightness text factor is applied (`02_Theme.md`), since `RefreshDisplay` resets each line's colour from `messageInfo.r,g,b` first. The callback never reads `messageInfo.message`, so secret values in instances do not matter.

## Spike (precedes Phase 2)

What is the least needed for the world to respond to hover and clicks through the stock chat windows, on each client.

1. **Baseline.** Stock frames, Prat off: a mob behind the chat area shows no tooltip and no cursor change.
2. **Stock switch (observation only).** Tab menu → "Make Non-Interactive". Does world hover work behind the frame? Do lines still appear and fade? This confirms the approach; the flag itself is not used (Principle 6).
3. **Same from code.** `SetMouseClickEnabled(false)` + `SetMouseMotionEnabled(false)` + `SetHyperlinksEnabled(false)` on every chat window at login. Check the same things.
4. **Child frames.** If hover is still blocked anywhere, `/fstack` to find what is taking input: tab, `buttonFrame`, edit box, `ResizeButton`, `ScrollBar`. Turn those off too.
5. **Wheel only.** With clicks and motion off, `EnableMouseWheel(true)`. Does the wheel reach the frame while world hover still works?
6. **In combat.** Repeat the switch during a fight (chat frames are not protected; expect no issue).
7. **Optional.** `SetPropagateMouseMotion(true)` — can a frame sense motion while passing it through? Decides whether a hover-pause for fading is ever possible.

| Result | Consequence |
|---|---|
| Step 2 restores hover | Approach confirmed |
| Step 3 works without taint or errors | Rest state is a few lines |
| Step 4 finds more input-taking frames | Rest state lists and switches each |
| Step 5: wheel works and hover still passes | Wheel-to-Review works as designed |
| Step 5: wheel-enabled frame blocks hover | Wheel-to-Review needs the modifier, or is dropped |
| Step 6 fails in combat | State changes are deferred until combat ends |

## API surface

Verified against `_ref\blizzard\` unless marked *verify*.

**Frame input** — `EnableMouse`, `EnableMouseWheel`, `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetHyperlinksEnabled`, `SetPropagateMouseMotion` (*verify on Era*), scripts `OnMouseDown`, `OnMouseWheel`, `OnEnter`, `OnLeave`.

**Modifier** — event `MODIFIER_STATE_CHANGED(key, down)`; `IsAltKeyDown()`, `IsControlKeyDown()`, `IsShiftKeyDown()`.

**Chat frames** — `ChatFrame1..N`, `NUM_CHAT_WINDOWS`; `CHAT_FRAMES` (names of active windows); `FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)`; per window `_G[name.."Tab"]`, `.buttonFrame`, `.ScrollBar`, `.ScrollToBottomButton`, `.ResizeButton`, and the pieces in `CHAT_FRAME_TEXTURES`; `GENERAL_CHAT_DOCK.overflowButton`.
Stock reveal: `FCF_FadeInChatFrame`, `FCF_FadeOutChatFrame`, `ChatFrameUtil.GetTabAlphas/SetTabAlphas`, `DEFAULT_CHATFRAME_ALPHA`.

**Message lines** — `SetFading`, `SetTimeVisible`, `SetFadeDuration`, `ScrollToBottom`, `AtBottom`, `MarkDisplayDirty`, `AddOnDisplayRefreshedCallback(fn)`, `frame.visibleLines[i].messageInfo = { message, r, g, b, timestamp }`.

**Forever** — chat frames are not protected. Chat text reaches addons as secret values inside instances; VCF never reads `messageInfo.message` in its hooks. Line formatting (`01_LineFormatting.md`) must guard sender/level lookups with `issecretvalue`.

## Settings

- Modifier key (Alt)
- Background opacity when awake (adjusted by zone band)
- Line fade delay (15 s)
- Wheel opens Review (on)
- Return to Rest after pointer leaves (5 s; 0 = never)
- Enter wakes the window (on)
- Zone-brightness adjustments: background (on), text (on)

## Open Questions

- **Whispers.** Whether an incoming whisper moves Rest to Awake.
- **Link in a fresh line.** At Rest a link cannot be clicked. Whether modifier + click on a link should wake the window and follow the link in one step.
- **Return to Rest.** Whether lines older than the fade delay vanish at once or share one fade-out (`ResetAllFadeTimes()` would give them a fresh 15 s instead).
- ~~**Intermittent lost hover/clicks over chat rects**~~ — probable cause found 2026-11-23: stock chat tabs are `EnableMouse(true)` Buttons at any alpha, so every invisible docked tab was a dead strip eating clicks and hover; with many windows that is a lot of screen. `696eea4` turns mouse off on any tab at or below 5 % alpha. Treat as resolved unless it recurs.

## Alternatives Considered

- **Wake on hover with a delay, or from a hot zone.** Needs the frame to sense motion, which blocks world hover.
- **Hover pauses line fading.** Same motion-sensing problem. Kept only as the optional spike step 7.
- **Stock "Make Non-Interactive" alone.** Gives hover-through, but kills links and scrolling until changed back by hand, and it is a persisted user setting. VCF is that switch made automatic, without writing the flag.
- **A key binding only.** Cannot conflict with clicks; can be added alongside the click states at little cost.
- **Replacing the chat frame.** Far more work; Forever restricts what addons can do with chat content. Changing the stock frame's behaviour is enough.
- **Alpha wash over the text to darken it in dark zones.** A texture over the chat rect darkens the world behind the text too; there is no text-only blend. Per-line colour factor in the refresh callback achieves the goal without touching configured colours.