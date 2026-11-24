# SPEC-VCF-01: Line formatting (timestamps, short channel tags, level in name)

- **Status:** Draft
- **Parent:** `00_VelocityChatFrames_Overview.md`
- **Replaces from Prat:** `Timestamps.lua`, `ChannelNames.lua` (short names only), `PlayerNames.lua` (level + class colour only).
- **Target output** (owner's screenshot): `[03:24] [G] [3:Kuro Ragemane]: hey folks`

- [x] Timestamps (stock `showTimestamps` CVar)
- [x] Short channel tags (`CHAT_<TYPE>_GET` rewrite; bracket-less stock formats such as `%s says:` are rebuilt as `[S] %s:`)
- [x] Player data store (level, class) from stock events (`Core\PlayerData.lua`)
- [x] `[level:Name]` rendering via `ChatFrameUtil.AddSenderNameFilter` (official, secret-safe, both clients) — own-line level still to confirm in play
- [x] Class colour on **every** message regardless of the per-type `colorNameByClass` setting: if stock did not wrap the name (`|c` absent), the filter wraps it from `GetPlayerInfoByGUID(arg12)` → `PlayerData.ClassFor(name)` → `RAID_CLASS_COLORS`. Level missing still yields a class-coloured `[Name]`. (2026-11-24, Era reported plain names)
- [ ] Secret-value safety on Forever verified in an instance

## Where the text is shaped

Both clients build a chat line in `ChatFrame_MessageEventHandler` / `ChatFrameMixin:MessageEventHandler` from format globals and then call `frame:AddMessage(text, r, g, b, ...)`. VCF does not re-implement the handler (Prat does, which is most of its complexity). Instead it uses the three hooks the stock code already exposes:

| What | Hook | Why it is enough |
|---|---|---|
| Timestamp | `hooksecurefunc`-free: wrap `frame.AddMessage` per window (`rec.origAddMessage = frame.AddMessage; frame.AddMessage = function(self, text, ...) return orig(self, stamp .. text, ...) end`) | Same technique as the stock `CHAT_TIMESTAMP_FORMAT` CVar path; ours only adds a prefix |
| Channel tag | Overwrite the `CHAT_<TYPE>_GET` format globals (`CHAT_GUILD_GET = "|Hchannel:GUILD|h[G]|h %s:\32"` etc.) | The handler reads them at message time; no hook at all |
| Level in name | `hooksecurefunc` on `GetColoredName` (Era) / wrap `ChatFrameUtil.GetColoredName` (Forever: it is a table field, so replace the field and call the original) | Returns the display string for the sender; we prepend `level:` inside the same `|Hplayer:...|h[...]|h` the handler wraps around it |

**Timestamps:** stock already supports timestamps via the `showTimestamps` CVar / `CHAT_TIMESTAMP_FORMAT`. Phase 1 sets that CVar to `%H:%M `-style format instead of hooking, if the stock output is acceptable (`[03:24] ` with the frame's colour). Hook only if the owner wants a different colour or bracket style. Decide on first build.

**Channel tags:** full list to override, Forever and Era share the names:
`CHAT_SAY_GET`, `CHAT_YELL_GET`, `CHAT_GUILD_GET`, `CHAT_OFFICER_GET`, `CHAT_PARTY_GET`, `CHAT_PARTY_LEADER_GET`, `CHAT_PARTY_GUIDE_GET`, `CHAT_RAID_GET`, `CHAT_RAID_LEADER_GET`, `CHAT_RAID_WARNING_GET`, `CHAT_INSTANCE_CHAT_GET`, `CHAT_INSTANCE_CHAT_LEADER_GET`, `CHAT_WHISPER_GET` (`[W From]`), `CHAT_WHISPER_INFORM_GET` (`[W To]`), `CHAT_BN_WHISPER_GET`, `CHAT_BN_WHISPER_INFORM_GET`, `CHAT_MONSTER_*` left alone. Numbered channels: the handler produces `[1. General]`; override `CHAT_CHANNEL_GET = "|Hchannel:%s|h[%s]|h %s:\32"` is not enough because the channel name is inserted by the handler; keep stock for numbered channels in Phase 1 and shorten later via the `AddMessage` wrapper with a `^%[(%d+)%. [^%]]+%]` gsub (text is not secret outside instances; skip when `issecretvalue(text)`).

Tags per type (Prat defaults, owner-confirmed `[G]`): S, Y, G, O, P, PL, R, RL, RW, I, IL, W From, W To.

## Player data store (`Core\PlayerData.lua`)

Copied from Prat `PlayerNames.lua` 291–568. In-memory tables keyed by lowercase sender name as chat events deliver it (first name on Forever; `Ambiguate(name, "none")` first). *This is display cache about other players, not our per-character data, so the GUID-key directive in `PROJECT_STRUCTURE.md` does not apply; our own entry uses `Client.PlayerFirstName()`.*

```
VCF_PlayerLevelByName  : { [nameLower] = level }
VCF_PlayerClassByName  : { [nameLower] = classToken }
```

| Event | Fill | API |
|---|---|---|
| `PLAYER_LOGIN`, `PLAYER_LEVEL_UP` | self | `UnitLevel("player")`, `UnitClass` |
| `GUILD_ROSTER_UPDATE` (request `C_GuildInfo.GuildRoster()` at login and on `CHAT_MSG_GUILD` from an unknown sender) | guild | `GetGuildRosterInfo(i)` → name, _, _, level, _, _, _, _, _, _, classToken |
| `FRIENDLIST_UPDATE` | friends | `C_FriendList.GetFriendInfoByIndex(i)` → `.name .level .className` |
| `GROUP_ROSTER_UPDATE` | party / raid | `UnitLevel("partyN")`+`UnitClass`; `GetRaidRosterInfo(i)` |
| `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT` | friendly players | `UnitIsPlayer`, `UnitIsFriend`, `UnitLevel`, `UnitClass` |
| `WHO_LIST_UPDATE` | passive `/who` only | `C_FriendList.GetWhoInfo(i)` → `.fullName .level .classStr` |
| per message, class only | `GetPlayerInfoByGUID(guid)` when class unknown | arg12 of `CHAT_MSG_*` |

Every write is guarded: `if issecretvalue(name) or issecretvalue(level) or issecretvalue(class) then return end`. No LibWho, no active querying, no persistence in Phase 1 (Prat's `keep` for guild/friends can be added later as a setting).

## Rendering

`GetColoredName(event, arg1..arg12)` returns the sender string, already class-coloured when `ChatTypeInfo[type].colorNameByClass` is set. Our wrapper:

```
-- pseudocode
function VCF_GetColoredName(event, ...)
    local name = Orig(event, ...)
    local arg2 = select(2, ...)                  -- sender
    if issecretvalue(arg2) or issecretvalue(name) then return name end
    local level = PlayerData.LevelFor(Ambiguate(arg2, "none"))
    if not level or not settings.ShowLevelInName then return name end
    local lvlText = settings.LevelColorByDifficulty and DifficultyColor(level):WrapTextInColorCode(level) or tostring(level)
    return lvlText .. ":" .. name
end
```

The handler wraps the result in `|Hplayer:name:lineID:type|h[...]|h`, so the brackets come for free and the link still carries the raw name. Difficulty colour: `GetQuestDifficultyColor(level)` (both clients), desaturated 40 % like Prat so it does not shout.

On Forever `ChatFrameUtil.GetColoredName` is the function; on Era the global `GetColoredName`. Put the swap in `Client\Client_*.lua` as `Client.WrapGetColoredName(fn)`.

## Open Questions

- Brackets colour: Prat paints `[` `]` grey (0.85). Stock paints them in the channel colour. Start with stock; add if missed.
- Raid subgroup `[3:Name:4]` — not ported until missed.
- Short tag for numbered channels (`[1]` vs `[1. General]`) — Phase 1 keeps stock, see above.