# Character Creation Screen

## Purpose

New game → **Your survivor**. In V1 the player chooses the survivor's **male
or female Adventurer body**, can randomise that choice, and continues through
`LoadingScreen.tscn` to the world (or back to the main menu). The choice lives
in the `CharacterCreationData` autoload and is consumed by Adventurer model
instances that opt into it.

Hair, facial hair, colour, feature and accessory code remains packed away in
`CharacterCreationScreen.gd`; it is deliberately unused (not referenced by any
scene) rather than deleted.

## Design (Sep 2026, quiet redesign Pass 2B / decision D3)

Built in the main menu's composition and the quiet language
(`docs/ui/QUIET_DESIGN_SYSTEM.md`): **text left, subject right**.

- Near-black canvas; the survivor stands in the right half on a faint warm
  floor glow, under one warm key light (the bunker-lamp motif) with a cool
  rim. The key light "switches on" as the screen opens.
- Left column (x ≈ 8.5%): `NEW GAME` eyebrow, "Your survivor" title, brass
  rule (draws in), one functional line, a `BODY` eyebrow, then text-only
  `MainMenuItem` rows — Male / Female / Randomise / Begin — with the shared
  `FocusRail` in `ACCENT`. The chosen body carries a "Selected" caption in
  `ACCENT`; both body rows reserve the caption line so selection never
  shifts the layout.
- Footer: `ENTER Select` + `ESC Main menu` (the Esc hint is also the pointer
  path back) bottom-left; `DRAG Rotate` + `WHEEL Zoom` bottom-right. Hints
  swap to controller glyphs (A/B, LB/RB, LT/RT) with `InputMode`.
- Motion: curtain lift, column fade, rail snap, staggered rows, key-light
  ramp; a body change cross-fades the stage while the real model is rebuilt.
  The preview idles with a slow ±9° sway after 2.5 s without input.
  `UIMotion.reduced()` removes every animation.
- No icons, no panels, no AI art.

## Files

| File | Role |
|---|---|
| `scenes/ui/character_creation/CharacterCreation.tscn` | Background, floor glow, 3D preview stage (SubViewport, lights, camera), curtain. |
| `scripts/ui/character_creation/SurvivorScreen.gd` | Builds the column/footers, selection state, preview rebuild, intro and exits. |
| `scripts/ui/character_creation/CharacterPreviewViewport.gd` | Mouse orbit/zoom/pan, shoulder/trigger controls, idle sway, GPU safeguards. |
| `scripts/ui/character_creation/CharacterCreationScreen.gd` | Packed-away hair/feature system (unreferenced). |
| `tools/tests/test_character_creation_ui.gd` (`CharacterCreationUITest.tscn`) | Multi-resolution layout, input and state regression checks. |

## Runtime flow

1. `_ready()` restores `CharacterCreationData.gender`, builds one Adventurer
   preview (scaled 1.25, as in `Player.tscn`) and focuses the restored body.
2. Male/Female (ButtonGroup) updates the autoload, caption and preview. The
   old model is `remove_child()` + `free()`d synchronously so two survivors
   never coexist (see docs/systems/player-model).
3. Randomise picks one of those bodies through the same path.
4. Begin sets `WorldManager.pending_new_game` (the loading screen then shows
   the survivor selection, `docs/systems/new-game/README.md`). Begin / Esc /
   B / the Esc hint curtain to black and change scene. A failed
   change restores the screen and shows a red line under the actions.

## Layout and performance contract

UI scale is `min(h/1080, w/1920·1.15)` clamped 0.66–1.4, as on the main menu.
The preview container is capped near the old 960×1080 render target and
centred in the right region (RX 580 `RENDER_LIST_OPAQUE` mitigation, see
`CharacterPreviewViewport._apply_graphics_settings`). Rows never fall below
40 px (56 px with a caption).

## Validation

```bash
godot --headless --path . res://tools/tests/CharacterCreationUITest.tscn
godot --headless --path . --script res://tools/tests/quiet_ui_lint.gd
```

The test covers 1280×720 → 3440×1440 plus live resize, column/stage
separation, footer collisions, selection restore (male and female), native
accept, focus wrap, stable row heights and a single preview after rapid
randomising. Live look: `tools/ui_capture/capture_scene.gd` with the `female`
/ `randomise` actions.

## Future work

- Reintroduce packed-away appearance choices only when their gameplay and
  (human-made) art are approved — as further quiet rows, not panels.
