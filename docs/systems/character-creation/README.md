# Character Creation Screen

## Purpose

Character creation is the project boot screen. In V1 the player chooses the
survivor's **male or female Adventurer body**, can randomise that choice, and
continues through `LoadingScreen.tscn` to the world. The choice lives in the
`CharacterCreationData` autoload and is consumed by Adventurer model instances
that opt into it.

Hair, facial hair, colour, feature and accessory code remains packed away in
`CharacterCreationScreen.gd`; it is deliberately unused rather than deleted.
The V1 screen does not expose controls for those systems.

## September 2026 redesign first pass

This subsystem is the isolated proving ground for the approved interface
direction. It does **not** modify the existing shared `UIKit` consumers or
`BunkerTheme.tres`.

- Warm near-black canvas and charcoal panel.
- Worn, darker brass for dividers and structural borders.
- Project blue for selection, hover and the primary action.
- Warm ivory text instead of pure white.
- Large, plainly worded buttons with prominent state icons.
- Left-side live survivor preview; right-side robust choice panel.
- Native Godot containers, `Theme`, `StyleBoxFlat`, focus neighbors and
  `ScrollContainer` behavior—no flattened UI background image.
- Keyboard/mouse and desktop controller hints switch with `InputMode`.
- Local responsive scaling from 720p through 1440p/ultrawide without changing
  project-wide stretch settings.

The screen's six SVG icons are explicitly AI-authored development placeholders.
They live under `assets/ui/placeholders/redesign/`, include
`_AI_PLACEHOLDER` in their names, and are release-blocked by the accompanying
manifest and `tools/tests/check_ui_placeholders.py`. The final game must contain
zero AI-authored artwork.

## Files

| File | Role |
|---|---|
| `scenes/ui/character_creation/CharacterCreation.tscn` | Native two-column screen, live 3D preview and choice panel. |
| `scripts/ui/character_creation/CharacterCreationScreen.gd` | Existing choice/preview flow plus selection synchronization, input hints and guarded loading transition. |
| `scripts/ui/character_creation/CharacterCreationLayout.gd` | Screen-local responsive metrics and icon/text clearances. |
| `scripts/ui/character_creation/CharacterPreviewViewport.gd` | Mouse orbit/zoom/pan and controller preview controls. |
| `assets/ui/themes/BunkerRedesignTheme.tres` | Opt-in redesign tokens and control states. |
| `assets/ui/placeholders/redesign/` | Tracked, release-blocking temporary icons. |
| `tools/tests/test_character_creation_ui.gd` | Headless multi-resolution, input and state regression checks. |

## Runtime flow

1. `_ready()` restores the current `CharacterCreationData.gender`, builds one
   Adventurer preview and focuses the restored body choice.
2. Male/Female selection updates the autoload, icon states and preview.
3. Randomise chooses one of those bodies and synchronizes the same state.
4. Complete disables actionable controls to prevent repeat submissions and
   requests `LoadingScreen.tscn`. If the transition fails, the buttons are
   restored and a visible error is shown.

The actual preview remains `scenes/player/AdventurerModel.tscn`, scaled exactly
as before. The redesign changes presentation, not the model pipeline or saved
character data contract.

## Responsive and input contract

`CharacterCreationLayout.gd` scales declared metadata relative to 1920×1080,
clamped to 0.667–1.333. Containers retain ownership of layout. At narrow desktop
resolutions the choice region scrolls; on ultrawide screens additional outer
margin prevents excessively stretched rows. Button focus is explicit and the
scroll container follows focus.

Opening the screen restores the selected body's focus without moving the
scrollbar: focus-following is briefly suppressed during initialization, the
scroll position starts at zero, and subsequent navigation follows focus as
normal. This is the only character-creation visual/behavior adjustment in the
generator-panel pass.

Mouse controls remain drag to orbit, wheel to zoom and middle-drag to pan. With
a controller, the right stick controls the preview and the left stick/D-pad
navigates buttons. The last input device controls the visible hint text.

## Validation

Development provenance check:

```bash
python3 tools/tests/check_ui_placeholders.py
```

Release gate (must fail while a placeholder or reference remains):

```bash
python3 tools/tests/check_ui_placeholders.py --release
```

Run `tools/tests/CharacterCreationUITest.tscn` headlessly or from Godot. The
test covers 1280×720, 1366×768, 1600×900, 1920×1080, 2560×1440 and 3440×1440,
plus live resize, selection restoration, native accept input, changing input
hints, preview count and focusability.

Visual approval still requires the project's target Godot 4.7/.NET editor and
the real font/import state. A passing headless test is not visual sign-off.

## Future work

- Replace every placeholder with human-authored or properly licensed artwork
  before release.
- Preserve the approved status-icon pattern in later inspector passes,
  including Running, Grid online and Stored water/water fill icons.
- Apply the token direction to other screens deliberately, one UI family at a
  time; do not make this theme global until those screens are migrated.
- Reintroduce packed-away appearance choices only when their underlying V1
  gameplay and art requirements are approved.
