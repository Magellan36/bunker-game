# Player-model probe scripts

Headless verification probes for the outfit body-region split
(`PlayerModelController._split_at_live_pose`) and the bind realignment.
Written for the Aug 2026 outfit clip fix; re-run them after any change to
`PlayerModelController.gd`'s split/classification logic to confirm the
split still (a) removes covered skin and (b) never eats the bare regions.

All probes boot a real `res://scenes/player/Player.tscn` instance
headlessly, wait 16 frames for the deferred split (8 idle-pose samples +
the mesh rebuild) to finish, then deform the post-split body and outfit
pieces the same way the renderer does:
`skel_global[bones] * skin.bind_pose * vertex`. No rendering needed.

## How to run

Godot headless with the script on the command line (a console build prints
`print()` output; a non-console build needs `--verbose` or a log file):

```
Godot_v4.x-stable_win64_console.exe --headless --path <repo> --script tools/probes/<script>.gd
```

Replace `<repo>` with the bunker-game checkout root and the exe with your
local Godot. Grep the output for the `[TAG]` prefixes below.

## Scripts

### post_split_check.gd — `[RESULT]`
Main post-split check. For each gender boots the player, at frame 16 and
frame 26 prints `body_verts`, the count of bands where the body's max
radius exceeds the outfit's max radius by > 1.2cm, and the worst gap (with
the offending `y` band). Caveat: this is a NAIVE per-band radius
comparison — the hanging hand beside the thigh reads as a ~3.6cm "poke"
because it sits further from the Y axis than the trouser at that height.
That is the hand, not a garment poke.

### bare_check.gd — `[BARE]`
Confirms the bare regions survive the split: prints per-band counts and
radius ranges of the remaining body verts, then `head_present` /
`hand_side_present`. Head occupies y 1.55-1.70; the hanging hand shows up
at y 0.5-0.95 with radius > 0.19 (idle pose — NOT the T-pose y 1.35-1.50,
which would false-negative). Also a quick sanity check that the torso/legs
bands are mostly emptied. Current baseline: male 3936 body verts, female
3770; head + hands + inner arms/armpits present.

### surf_check.gd — `[SURF]`
Prints each body/outfit mesh's surface count and total vertex count after
the split. Useful for confirming the split actually removed verts
(male ~6600 -> 3936, female ~6400 -> 3770) and that the mesh kept its
surface count. The body is single-surface, so poke probes can index
`surface_get_arrays(0)` directly with the global vertex index.

## Notes / gotchas (learned while building these)

- Probes `extends SceneTree` and defer `_run()` via `call_deferred`, then
  `await process_frame` — this is the pattern that lets a standalone
  script drive the real scene tree headlessly.
- Gender is set through `CharacterCreationData.gender` BEFORE instancing
  the player; the controller reads it when `use_character_creation_data`.
- Use `sqrt` (not `sqrtf`), explicit `: String` / `: Array` / `: bool`
  annotations, and `var e: Array = entry` after `dict.get()` (Variant) —
  Godot 4.7's type inference rejects `var x := variant_value`.
- ARRAY_BONES values are SKIN BIND INDICES, not skeleton indices — map
  them through `skin.get_bind_name(b)` before comparing bone names.
- The split is deferred and async (samples 8 frames of the idle loop); a
  probe that measures immediately after `add_child` sees the UNSLIT body.
  Wait ~16 frames.
- There are two `SuperHero_*` body meshes per player (real + shadow) —
  iterating `_all()` and taking the last `superhero` match is fine since
  both are split identically.