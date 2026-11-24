# SPEC-VCF-04: Scrollback restore (lines survive login / reload; whispers follow you across characters)

- **Status:** Built, committed `64aed7a` (2026-11-24); awaiting play-test of clickable names in restored lines
- **Parent:** `00_VelocityChatFrames_Overview.md`
- **Ground truth:** `_ref\blizzard\ScrollingMessageFrame.lua` (byte-identical Era/live): `AddMessage` 10, `BackFillMessage` 20, `GetMessageInfo` 30, `ForEachMessage` 37, `historyBuffer` entries `{message, r, g, b, extraData, timestamp}`, `RefreshDisplay` alpha = `CalculateLineAlphaValueFromTimestamp(now, max(entry.timestamp, overrideFadeTimestamp))`.
- **Replaces from Prat:** `History.lua` (Prat keeps per-frame history in SavedVariables and re-adds on login).

- [x] Phase 1: per-window capture on `PLAYER_LOGOUT` + restore on login, with fade-state grace (`Core\Scrollback.lua`)
- [x] Phase 1: boundary marker line (ASCII `-- previous session (HH:MM, Mon DD) --`)
- [x] Phase 2: whisper journal shared across characters (realm-scoped on Era), merged into every WHISPER-group window
- [x] Settings + options section "Scrollback restore"
- [x] Clickable `|Hplayer:` names in restored lines (as-is with `ScrollbackInColor`; stale `lineID` only affects Report)
- [x] Login boilerplate never captured: lines matching `GUILD_MOTD_TEMPLATE`, `CHAT_SERVER_DISCONNECTED_MESSAGE`, `CHAT_SERVER_RECONNECTED_MESSAGE`, `WELCOME_TO_WORLD_OF_WARCRAFT` (patterns built from the globals, markup + leading timestamp stripped). The client re-prints these on every login, so restoring them stacked one copy per reload. Deliberately NOT a generic consecutive-duplicate dedupe: a player saying "lol" twice is real.

## Behaviour

**Capture** (`PLAYER_LOGOUT`, which also fires on `/reload`): for every non-combat-log window, walk `frame:GetMessageInfo(i)` newest→oldest up to `ScrollbackLines` and store `{ text, r, g, b, visible }` plus `savedAt = time()`. `visible` = the line's alpha at capture time > 0, i.e. `GetTime() - entry.timestamp <= frame:GetTimeVisible()` OR the frame is currently not fading (`hover` / unlocked / `LineFadeSeconds = 0` / own-input hold). `entry.timestamp` is read via `ForEachMessage` (entries are plain tables); `GetMessageInfo` returns `message, r, g, b, extraData...` without the timestamp.

**Restore** (login, after `UPDATE_CHAT_WINDOWS` has laid the windows out — same timing Reveal uses, one `C_Timer.After(0.5)` after `PLAYER_ENTERING_WORLD` is NOT enough if the stock `CHAT_MSG_*` backlog arrives first; restore runs from our `PLAYER_LOGIN` init, *before* any live line, then marks the boundary):

```
elapsed = time() - savedAt
withinGrace = elapsed <= ScrollbackGraceMinutes * 60
for line in oldest..newest:
    frame:AddMessage(text or stripped, r, g, b)     -- normal order, oldest first
    entry = newest history entry (ForEachMessage index 1)
    if withinGrace and line.visible then entry.timestamp = GetTime()        -- fresh LineFadeSeconds from now
    else                               entry.timestamp = GetTime() - frame:GetTimeVisible() - frame:GetFadeDuration() - 1   -- already past: alpha 0, SetShown(false)
marker = "── previous session (HH:MM, Mon DD) ──"  grey 0.5  -> same timestamp rule as a visible line (visible iff withinGrace)
```

`AddMessage` (not `BackFillMessage`) so the window's insert order and scroll offset behave as for fresh lines. Timestamps are mutated directly on the history entry — it is the field `RefreshDisplay` reads, there is no setter, and the entry is an ordinary Lua table we own a reference to. `MarkDisplayDirty()` after the batch.

**Colour:** `RestoreInColor` on → text stored verbatim (includes `|c`, `|H` links, textures). Off → `StripMarkup` (CopyText.lua already has it; move to Util) and `r,g,b` forced to 0.6 grey. Links in restored lines: `|Hplayer:` links still work (name-click opens whisper); `lineID`-dependent features (report, copy) do nothing for restored lines — acceptable.

**Marker:** one line after the restored block, `|cff808080── previous session (%s) ──|r` with `date("%H:%M, %b %d", savedAt)`. Same visibility rule as a visible line. Skipped when the window restored nothing.

## Fade-state grace (owner model)

"Whatever the fade state was at logout is honoured for `ScrollbackGraceMinutes`." Back within 10 min → the lines you were reading are still readable, then fade normally; later → the whole restored block is in history only (wheel / scroll / hover reveals it). Default 10 min, slider 5–60 min step 5.

## Whisper journal (Phase 2)

- Source: `CHAT_MSG_WHISPER`, `CHAT_MSG_WHISPER_INFORM`, `CHAT_MSG_BN_WHISPER`, `CHAT_MSG_BN_WHISPER_INFORM` on a hidden frame. Stored **pre-formatted display text** captured from the receiving window's `AddMessage` (same tick-stamp trick as Fading.lua), so the restored line looks identical (tags, level, class colour) — not re-run through the formatter.
- Store: `VelocityChatFramesDB.whispers[scopeKey] = { {t=time(), text, r, g, b, ownerKey=UnitGUID("player")}, ... }` capped at `WhisperLines` (10–50, default 20). `scopeKey` from `Client.WhisperScopeKey()`: Era = `GetNormalizedRealmName()` (whispers cannot cross realms); Forever = `"account"` (single realm, see PROJECT_STRUCTURE Forever notes). Owner-key is `UnitGUID` per workspace directive; it is used only to dedupe.
- Restore: every window whose `GetChatWindowMessages(id)` contains `WHISPER` or `BN_WHISPER`. Merge with that window's own scrollback by time; journal entries whose `ownerKey == current GUID` are dropped (already in the window's own scrollback). Journal lines are always restored *faded* unless within grace **and** they were visible on the owning character — simpler: journal entries carry `visible` too, captured the same way.
- Setting off → journal still recorded? **No** — off means neither record nor restore (privacy expectation).

## Settings (`Core\Settings.lua`)

```
ScrollbackRestore = true          -- Enable scrollback restore on login / reload
ScrollbackWhispers = true         -- Restore recent whispers across characters (same realm on Era)
ScrollbackInColor = true          -- restore scrollback in colour
ScrollbackLines = 100             -- 50..500 step 10
WhisperLines = 20                 -- 10..50 step 5
ScrollbackGraceMinutes = 10       -- 5..60 step 5
```

SavedVariables layout (account-wide `VelocityChatFramesDB`):

```
scrollback[playerGUID] = { savedAt = <time()>, windows = { [chatWindowId] = { {text,r,g,b,visible}, ... } } }
whispers[scopeKey]     = { {t, text, r, g, b, visible, ownerKey}, ... }
```

Keyed by `UnitGUID("player")` (directive). Window id = `frame:GetID()`; windows that no longer exist at login are dropped. Only the current character's `scrollback` entry is kept (others are pruned at capture) — ~500 lines × 10 windows of text is fine, but not per alt.

## Options (`UI\Options.lua`) — new Section "Scrollback restore" after "Lines"

| Control | Key |
|---|---|
| [x] Restore scrollback on login / reload | `ScrollbackRestore` |
| [x] Restore recent whispers across characters (same realm on Classic Era) | `ScrollbackWhispers` |
| [x] Restore scrollback in colour | `ScrollbackInColor` |
| Slider "Restore %d lines per window" 50–500 | `ScrollbackLines` |
| Slider "Restore %d recent whispers" 10–50 | `WhisperLines` |
| Slider "Lines you could see at logout stay visible if you are back within %d min" 5–60 | `ScrollbackGraceMinutes` |

## Module

`Core\Scrollback.lua` — `Scrollback.Init()` (called from VelocityChatFrames.lua after `Windows.Init` and `Fading.Init`, before anything else can `AddMessage`), `Scrollback.Capture()` on `PLAYER_LOGOUT`, `Scrollback.Restore()`. TOC after `Fading.lua`. `Client.WhisperScopeKey()` added to `Client.INTERFACE` and both flavours.

## Open Questions

- Combat Log is excluded (its lines are generated, not chat).
- Temporary whisper windows (`FCF_OpenTemporaryWindow`) are not recreated; their lines are lost. Not ported until missed.
- Restored `|Hplayer:` links carry the old `lineID`; report/copy on them is a no-op. Acceptable.