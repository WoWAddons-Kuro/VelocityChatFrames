# SPEC-VCF-02: Theme (flat frame, flat tabs, zone-brightness adjustment)

- **Status:** Draft (Phase 3/4; built after 03 and 01)
- **Parent:** `00_VelocityChatFrames_Overview.md`
- **Ground truth:** `_ref\blizzard\FloatingChatFrame.lua` `FCFTab_UpdateColors` 1267 (Era 1126), `CHAT_FRAME_TEXTURES`, `FCF_StartAlertFlash`; `ScrollingMessageFrame.lua` `RefreshDisplay` 623; `LibZoneBrightness\README.md`.

- [ ] Phase 3: flat tab — active / inactive / alert as three steady tones, no glow, no yellow text
- [ ] Phase 3: flat frame — one background texture, no border pieces; alpha = `ZB:AdjustAlpha(bgAlpha)`
- [ ] Phase 3: re-theme on `ZB:RegisterCallback` band change
- [ ] Phase 4: text factor per band in the display-refresh callback
- [ ] Phase 4: outline/shadow strength per band

## Principle 5 restated

"Which tab is active?" must be answerable in one glance from any background. The stock answer is yellow text + an `ActiveLeft/Middle/Right` gradient + a flashing `glow` on alert — three things that need time to disambiguate over variable terrain. VCF uses one flat fill per tab state and never animates it.

## Tabs

`FCFTab_UpdateColors(tab, selected)` is the single stock entry point: it shows/hides `ActiveLeft/Middle/Right`, and sets the FontString to `tab.selectedColorTable` or `NORMAL_FONT_COLOR`. VCF:

```
-- pseudocode
hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
    if not enabled then return end
    HideStockArt(tab)      -- Left/Middle/Right, ActiveLeft/Middle/Right, HighlightLeft/Middle/Right :SetAlpha(0)  (hide, do not nil: stock code indexes them)
    EnsureFlatFill(tab)    -- one texture, SetAllPoints(tab), layer BACKGROUND
    tab.vcfFill:SetColorTexture(Theme.TabTone(selected and "active" or "inactive", band))
    tab:GetFontString():SetTextColor(Theme.TabText(selected, band))
end)
hooksecurefunc("FCF_StartAlertFlash", function(cf) tab(cf).vcfFill:SetColorTexture(Theme.TabTone("alert", band)); stop tab.glow anim end)
hooksecurefunc("FCF_StopAlertFlash",  function(cf) FCFTab_UpdateColors(tab(cf), tab(cf) == selected) end)
```

Starting tones (settings, to be tuned in play): active = white 25 % / inactive = black 35 % / alert = steady orange 60 %. Text: active white, inactive 70 % grey. Dark zone band inverts the light/dark choice (`Theme.TabTone` consults the band).

Tab alpha at rest is owned by `Reveal.ApplyChrome` (03); in Chrome state tabs show at 1.

## Frame

`CHAT_FRAME_TEXTURES` lists `Background` plus eight border pieces. VCF hides the border pieces (`SetAlpha(0)` via Reveal.ApplyChrome, which already owns their alpha) and keeps only `Background`, with `SetColorTexture(0,0,0, ZB:AdjustAlpha(settings.BackgroundAlpha))`. `FCF_SetWindowColor`/`FCF_SetWindowAlpha` are not called (Principle 6).

`ZB:RegisterCallback(function(band) Theme.Reapply(band) end)` re-tones every tab and background on zone change.

## Text (Phase 4)

Per-line colour factor applied in the same `AddOnDisplayRefreshedCallback` that Awake uses (Overview). `RefreshDisplay` has just called `SetTextColor(messageInfo.r, g, b)`; we read it back and multiply:

```
-- pseudocode
local factor = { dark = 1.00, normal = 0.92, bright = 0.78 }   -- settings
for _, line in ipairs(frame.visibleLines) do
    if line.messageInfo then
        local r, g, b = line:GetTextColor()
        line:SetTextColor(r * f, g * f, b * f)     -- plus optional saturation lift in bright
    end
end
```

Configured `ChatTypeInfo` colours are never written; the owner tunes them against the dark-zone look (factor 1.0). The callback does not read `messageInfo.message`. Outline/shadow: `frame:SetShadowOffset` / `SetShadowColor` per band; font flag `OUTLINE` in bright only if shadow is not enough.

Scroll-time cost: the callback runs only on display refresh (new line, scroll, resize), never per frame.

## Settings

- Flat theme on/off (off = stock art, hooks become no-ops)
- Background alpha (base, before zone adjustment)
- Tab tones: active / inactive / alert colour+alpha
- Zone adjustment: background on/off, text on/off, per-band text factors

## Open Questions

- Whether the edit box gets the flat treatment too (Prat Editbox module did). Likely yes, later.
- Dock overflow button and QuickJoin toast: hide at rest, flat in Chrome.