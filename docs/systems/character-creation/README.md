# Character Creation Screen (Aug 2026)

## Purpose
Bare-bones pre-game customization: pick **gender**, then **hairstyle + hair
color**, then start the game. Runs as the project's **boot scene**
(`project.godot`'s `run/main_scene`) — the real game (`MainWorld.tscn`)
doesn't load until the player presses **Start**. Every choice is written
into the `CharacterCreationData` autoload, which survives the scene change
and is read by the player's spawned model.

Out of scope for this "bare bones" pass (deliberate): no save/load of the
choice across sessions (picking again every boot until a save system hooks
`CharacterCreationData`), no eyes/body-proportion/skin-tone sliders beyond
the one default texture per gender, no back-navigation from the Hair step,
and no visual theming — plain default Godot controls throughout.

## Files
| File | Role |
|---|---|
| `scenes/ui/character_creation/CharacterCreation.tscn` | The screen: left half customization controls, right half live preview viewport. |
| `scripts/ui/character_creation/CharacterCreationScreen.gd` | Gender → Hair step flow, per-gender hairstyle button list, live color repaint, Start→MainWorld. |
| `scripts/ui/character_creation/CharacterPreviewViewport.gd` | Mouse-drag orbit / scroll-zoom on the right-half preview only. |
| `scripts/core/CharacterCreationData.gd` | Autoload holding `gender` / `hairstyle_key` / `hair_tint_color`. |
| `addons/jts_colorpickerkit/` | Vendored third-party runtime color picker (see below). |

## Flow
1. Gender step: **Male** / **Female**. Picking one hides the gender panel,
   shows the Hair panel, rebuilds the hairstyle button list for that
   gender, and swaps the preview body immediately.
2. Hair step: pick a hairstyle (rebuilds the preview), drag the color
   picker (repaints the preview's hair in place — no rebuild, no stutter),
   press **Start** → `change_scene_to_file("res://scenes/world/MainWorld.tscn")`.

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

## Vendored color picker
`addons/jts_colorpickerkit/` is **JT's Color Picker Kit**
(`github.com/JoenTNT/godot-jts-color-picker`), **Apache-2.0** — a runtime/
in-game color picker (real SV gradient + hue/alpha sliders + hex field,
custom shaders), used here as a plain instanced scene + script, not an
editor plugin. Apache-2.0 requires its `LICENSE`/`README.md` stay inside
the addon folder — do not strip them. Public API used by this screen:
`on_color_picked(Color)` signal, `get_picked_color()`,
`set_picked_color()` on the `UI_ColorPickerInstance` script. The addon's
own scene references one sprite by a UID that this project's import
assigns differently (a harmless warning on first load; the sprite resolves
by path).
