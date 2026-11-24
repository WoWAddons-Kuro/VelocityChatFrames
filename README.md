# Velocity Chat Frames

Chat windows that stay out of the way. For WoW Forever and Classic Era.

- The stock windows no longer reveal their background, tabs and buttons whenever the pointer wanders near them.
- Lines fade 15 s after they arrive (setting).
- Short channel tags: `[G]`, `[P]`, `[W From]`.
- Sender names are class-coloured on every channel and carry their level when known: `[3:Kuro Ragemane]`.
- Sticky channels, chosen per type.
- **Scrollback restore.** Each window gets its recent lines back after a login or `/reload`, followed by a grey
  `-- previous session --` marker. Lines you could still see when you logged out stay visible if you are back
  within the grace period (default 10 min); otherwise the restored block is already faded and shows on wheel,
  hover or scroll like any older line. Recent whispers follow you across characters (same realm on Classic Era)
  into every window that shows whispers. Names in restored lines keep their links. Lines the game re-prints on
  every login (guild MOTD, disconnect notices) are not restored, so they never stack.

`/vcf` opens the settings. `/vcf status` prints version and state. `/vcf off` / `/vcf on` toggles everything.

Design notes live in `SPECS\`. Replaces the handful of Prat features the author actually used; see `SPECS\00_VelocityChatFrames_Overview.md`.

MIT.