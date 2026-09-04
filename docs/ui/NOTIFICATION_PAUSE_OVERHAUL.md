# Notification and Pause UI Overhaul

## Presentation contract

- Live alerts are 520 × 48 px desktop cards anchored above the inventory bar.
- At most three full cards are drawn. Additional queued alerts are represented
  by a compact overflow count instead of covering the play space.
- Each card has a code-drawn domain icon, a domain/severity eyebrow, one clear
  event line, optional compact detail, and a duplicate count when applicable.
- The palette remains warm charcoal, worn brass and ivory, with project blue,
  amber, red, water blue and farming green used as semantic accents.
- No new bitmap artwork is required. Symbols are drawn by
  `BunkerSymbolTexture.gd` and remain easy to replace later.

## Queue and history behavior

`NotificationManager.notify()` retains its original first four parameters.
Existing gameplay callers therefore remain source-compatible. It now accepts
optional journal/detail parameters and also exposes `feedback()` for immediate
interaction acknowledgement that should not clutter Bunker Log.

Identical events inside the deduplication window refresh the live card and
increment its count. The matching history event is also collapsed. Timing,
severity-specific duration, the 20-entry live defensive cap, and the 20-entry
history retention cap remain bounded.

Power event copy resolves the registered world node into a player-facing name
(`Generator L`, `Battery M`, a zone-named breaker where available) instead of
showing raw instance/registry IDs.

## Pause workspace

The pause menu is a two-column desktop panel:

- Left rail: Continue, Save Game, Load Game, Settings, Exit to Desktop.
- Save and Load expand the existing three slot controls. Save/load authority,
  labels, disabled-empty-load behavior and confirmation flow are unchanged.
- Right: Bunker Log with All, Critical, Power, Water and Farming filters,
  newest-first event cards, relative time, duplicate counts and NEW state.
- Footer: keyboard and controller hints.

The game continues running behind the menu exactly as before. Player movement
is locked, the mouse is released, and the controller cancellation chain closes
the exit confirmation or slot chooser before closing the pause workspace.

## Verification

Static parsing and `git diff --check` cover every changed GDScript. When a
Godot executable is available, run:

```sh
godot --headless --path . --script res://tools/tests/notification_ui_smoke.gd
```

The smoke verifies compact geometry, stack cap, duplicate collapsing,
temporary-versus-journal behavior, and Bunker Log filters.
