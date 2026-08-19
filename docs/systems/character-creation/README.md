# Character Creation Screen (Aug 2026)

## Purpose
Bare-bones pre-game customization: pick **gender**, then **hairstyle + hair
color**, then complete. Runs as the project's **boot scene**
(`project.godot`'s `run/main_scene`) — the real game (`MainWorld.tscn`)
doesn't load until the player presses **Complete**. Every choice is written
into the `CharacterCreationData` autoload, which survives the scene change
and is read by the player's spawned model.

Out of scope for this "bare bones" pass (deliberate): no save/load of the
choice across sessions (picking again every boot until a save system hooks
`CharacterCreationData`), no eyes/body-proportion/skin-tone sliders beyond
the one default texture per gender, no "any color" picker (curated swatch
palette only for now — the vendored full picker is still in the addon,
see below), and no visual theming — plain default Godot controls
throughout.

## Files
| File | Role |
|---|---|
| `scenes/ui/character_creation/CharacterCreation.tscn` | The screen: narrow sidebar (categories + Randomise/Complete), fixed-width category panel, preview filling the rest. |
| `scripts/ui/character_creation/CharacterCreationScreen.gd` | Sidebar category switching (Body/Hair real, rest disabled), per-gender hairstyle thumbnails, swatch color, Randomise, Complete→MainWorld. |
| `scripts/ui/character_creation/CharacterPreviewViewport.gd` | Mouse-drag orbit / scroll-zoom on the preview area only. |
| `scripts/core/CharacterCreationData.gd` | Autoload holding `gender` / `hairstyle_key` / `hair_tint_color`. |
| `addons/jts_colorpickerkit/` | Vendored third-party color picker — present but currently **unreferenced** by this screen (see "Swatch palette" below). |

## Flow
Persistent sidebar, one category panel swapped in/out on the right of it:
1. **Body** — Male / Female (toggle pair). Picking one rebuilds the
   hairstyle list and swaps the preview body immediately.
2. **Hair** — hairstyle thumbnails (GridContainer) + color swatches
   (GridContainer). Clicking either repaints the live preview (style
   rebuild / in-place tint repaint).
3. **Randomise** — rolls gender + a valid hairstyle for that gender + a
   palette color in one click, UI toggles included.
4. **Complete** → `change_scene_to_file("res://scenes/world/MainWorld.tscn")`.

**Face / Features / Accessories** sidebar buttons are laid out and visible
per request but `disabled = true` ("Coming soon" tooltip) — there is no
underlying system behind them yet, this is scaffolding, not a stub
implementation.

`CharacterCreationScreen.gd`'s `HAIRSTYLE_OPTIONS` maps UI labels to
`PlayerModelController.gd`'s `HAIRSTYLES` dictionary keys and filters per
gender (`Hair_Beard` → male only, `Hair_BuzzedFemale` → female only; the
rest offered to either).

## Who reads CharacterCreationData
Only `PlayerModelController` instances with
`use_character_creation_data = true`:
- `Player.tscn`'s `PlayerModel` and `PlayerModelShadow` nodes, and
- the creation screen's own live preview instance.

NPCs and any other `PlayerModel.tscn` instance leave the flag at its
default `false` and keep the hardcoded male / buzzed / dark-brown look,
regardless of what the player picked. Nothing about NPC appearance is
affected by the player's choices.

## Hairstyle placement caveat
Each entry in `PlayerModelController.gd`'s `HAIRSTYLES` carries a
`position_offset`. Only `"buzzed"`'s value (`(0.0, -1.576469, 0.057)`) is
actually playtested-correct — it took three real tuning passes. The other
five styles default to that same offset as a starting guess; expect most
to need their own quick Inspector nudge on first playtest (on any
`PlayerModel` instance's `hair_position_offset`, which now applies as an
ADDITIONAL delta on top of the style's base offset — both it and
`hair_rotation_offset_deg` default to zero). This is expected, not a bug.

`Hair_Beard` is a beard, not scalp hair — it's in the selectable list
since the source folder contains it, but flagged for a possible future
separate "facial hair" slot.

## Vendored color picker (currently unused by this screen)
`addons/jts_colorpickerkit/` is **JT's Color Picker Kit**
(`github.com/JoenTNT/godot-jts-color-picker`), **Apache-2.0** — a runtime/
in-game color picker (real SV gradient + hue/alpha sliders + hex field,
custom shaders). It powered the previous pass's Hair step; the swatch
palette now replaces it on this screen, but the addon is **kept vendored
and intact** — a fuller "any color" picker behind something like an
"Advanced" toggle is a reasonable thing to bring back in the customization
pass, so this isn't an oversight. Apache-2.0 requires its
`LICENSE`/`README.md` stay inside the addon folder — do not strip them.
Its public API (if re-wired): `on_color_picked(Color)` signal,
`get_picked_color()`, `set_picked_color()` on the `UI_ColorPickerInstance`
script. The addon's own scene references one sprite by a UID that this
project's import assigns differently (a harmless warning on first load;
the sprite resolves by path).

## Sidebar category layout, thumbnails & swatch palette (Aug 2026)
The linear Gender→Hair wizard was replaced with a persistent sidebar
(Body/Face/Hair/Features/Accessories) + a category panel that swaps on
selection — see "Flow" above. Only Body and Hair are real; the other
three are visible-but-disabled scaffolding with a "Coming soon" tooltip,
wired up (or unwired) in `CharacterCreationScreen._ready()`.

**Hairstyle thumbnails** render via `ItemPreviewKit.gd`
(`scripts/ui/common/` — the project's ONE shared live-3D-preview tool,
same one InventoryHUD/StorageUI use), NOT a separate implementation:
each button is a `Button` with a full-rect `SubViewportContainer` layered
on top (`mouse_filter = MOUSE_FILTER_IGNORE` — otherwise the container
eats the click before the Button sees it) wrapping a `SubViewport` from
`ItemPreviewKit.build_viewport()`, fed a standalone `Node3D` built by
`CharacterCreationScreen._build_hair_preview_node()` (hair mesh + tinted
material built the same way `PlayerModelController._build_hair_material()`
builds the real one — no skeleton, thumbnail only). Rebuilding the
buttons is cheap (six small static meshes).

**Hair color** is now `HAIR_COLOR_SWATCHES` — a curated realistic palette
(black→white, browns, blonde, auburn, ginger, grey) as solid `StyleBoxFlat`
swatch buttons in a `GridContainer`, not the reference's rainbow grid
(grounded survival game, not a stylized vampire game — the list is just
data, extend freely). Selected swatch gets a white 3px border. Picking a
swatch repaints the live preview's hair material in place AND rebuilds
the six thumbnails so they pick up the new tint too.

**Randomise** rolls gender + a valid hairstyle for that gender + a swatch
color together and syncs every UI control (gender toggle, thumbnail
pressed-state, swatch border) to the result, not just the 3D preview.
