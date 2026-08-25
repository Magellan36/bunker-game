# Player-Model Animations (CURRENT)

**Read this before touching anything under `assets/models/player/`, the
`AdventurerModel` animation libraries, or `AdventurerModelController.gd`'s
animation logic.**

This is the CURRENT animation pipeline for the V1 Adventurer bodies
(Player + NPC, both genders). The companion `README.md` in this folder
documents the overall Player-Model system and the PACKED-AWAY
`PlayerModelController.gd` customization era; this file is specifically
about how animation clips get in, retargeted, and played today.

## Runtime body recap (one paragraph)

`scenes/player/AdventurerModel.tscn` → `AdventurerModelController.gd`
loads `Adventurer_Male.fbx` / `Adventurer_Female.fbx` at runtime (gender
from `CharacterCreationData` for the player, a per-NPC random roll for
NPCs), renames the root to **`MaleModel`** (both genders — load-bearing),
applies a static 180° Y rotation, and the skeleton retargets to
**`GeneralSkeleton`** with Godot **Humanoid** bone names. Every animation
library's track paths are therefore **`MaleModel/%GeneralSkeleton:<bone>`**.

## How a clip gets in (import → bake)

All source animation FBX files live under `assets/models/player/` (or a
named subfolder like `male_locomotion/`). The pipeline:

1. **Copy the FBX** into the project.
2. **Write the `.import` sidecar** with the retarget block (below), OR let
   Godot generate a default one then add the block. The sidecar is what
   drives the bone retarget — a plain default import does NOT retarget.
3. **Delete the stale imported scene, then `--import`:**
   `Remove-Item ".godot/imported/<name>-<md5>.scn"` then
   `Godot --headless --import --path <project>`.
   **Critical gotcha:** plain `--import` runs have been observed to NOT
   re-read edited `.import` params (cached). Deleting the cached `.scn`
   forces a fresh import with the current params. This bit the team twice
   (stale library extraction, retarget silently skipped) — always delete
   the `.scn` after editing an `.import` file.
4. **Bake the library** with a GDScript (pattern in `tools/`, and
   recreated ad-hoc in this session): load the imported `.scn`, grab the
   `mixamo_com` animation from its `AnimationPlayer`, then:
   - duplicate the `Animation`, set `loop_mode`
     (`LOOP_LINEAR` for locomotion/sit-loop, `LOOP_NONE` for the one-shot
     sit transitions),
   - **strip the armature-root root-motion tracks** (tracks whose
     concatenated names are `CharacterArmature` — position/rotation/scale
     on the root node; unresolvable at runtime and root motion is not
     consumed anyway),
   - rewrite every remaining track path to
     `MaleModel/%GeneralSkeleton:<bone>` (prefix the node path with
     `MaleModel/`; preserve the `:bone` subname),
   - save as an `AnimationLibrary` `.res` under
     `assets/models/player/anims/`.

The imported animation is always named `mixamo_com` regardless of source
file, so the bake renames it to the clip key used by the controller.

### The retarget `.import` block

```ini
_subresources={
"nodes": {
"PATH:CharacterArmature/Skeleton3D": {
"retarget/bone_map": Resource("res://assets/models/player/bone_map_maximo.tres"),
"retarget/bone_renamer/rename_bones": true,
"retarget/bone_renamer/unique_node/make_unique": true,
"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
"retarget/rest_fixer/apply_node_transforms": true,
"retarget/rest_fixer/keep_global_rest_on_leftovers": true,
"retarget/rest_fixer/normalize_position_tracks": true,
"retarget/rest_fixer/original_skeleton_name": "OriginalSkeleton",
"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
"retarget/rest_fixer/retarget_method": 1,
"retarget/rest_fixer/use_global_pose": true
}
}
}
```

- **`PATH:` key must match the skeleton's node path in the source FBX.**
  Mixamo-style files have the skeleton at the root (`PATH:Skeleton3D`);
  Quaternius/Adventurer and Maximo files nest it (`PATH:CharacterArmature/Skeleton3D`).
  A wrong/missing key silently skips the whole retarget (skeleton stays
  unrenamed, nothing resolves → T-pose).
- **Imported scene filename hash** = `md5("res://<source path>")`.

### Bone maps (`assets/models/player/`)

| File | Rig it maps | Used by |
|---|---|---|
| `bone_map_mixamo.tres` | `mixamorig_*` → Humanoid | walk/run/carry/sit (Mixamo-sourced) |
| `bone_map_adventurer.tres` | Adventurer (`Hips`/`Chest`/`UpperArm.L`) → Humanoid | Adventurer bodies |
| `bone_map_native.tres` | native Superhero → Humanoid | packed-away PlayerModel path |
| `bone_map_maximo.tres` | Maximo (`Abdomen`/`Torso`/`Chest`/`Shoulder.L`...) → Humanoid | the Maximo-sourced idle/locomotion clips |

**Maximo ≠ Mixamo.** The Maximo rig (used by `NEW_Idle` and the
locomotion packs) names bones `Abdomen`, `Torso`, `Chest`,
`Shoulder.L`, `UpperArm.L`, `Index2.L`... and has no `mixamorig_*`
prefixes, so `bone_map_mixamo.tres` does NOT match it (the retarget
silently skips → skeleton stays `Skeleton3D` → tracks unresolvable →
**T-pose**). `bone_map_maximo.tres` was added for it. Always check a new
clip's rig (inspect the imported skeleton's bone names) before choosing
the bone map. "Some animations have different skeletons than others."

## Clip registry (current state, Aug 2026)

Libraries in `assets/models/player/anims/` wired into
`AdventurerModel.tscn`'s `AnimationPlayer`:

| Library | Clip | Len | Loop | Used by |
|---|---|---|---|---|
| `idle_lib` | `idle` | 6.0s | yes | (unused directly — see gender overrides) |
| `walk_lib` | `walk` | 1.03s | yes | both genders (shared) |
| `run_lib` | `run` | 0.73s | yes | both genders (shared) |
| `idle_carry_lib` / `walk_carry_lib` / `run_carry_lib` | `*_carry` | — | yes | carry states, both genders |
| `idle_male_lib` | `idle_male` | 8.33s | yes | male idle (Male Locomotion Pack) |
| `idle_female_lib` | `idle_female` | 6.0s | yes | female idle (Female Basic Locomotion Pack) |
| `stand_to_sit_lib` | `stand_to_sit` | 2.23s | no | sit-down |
| `sit_lib` | `sit` | 1.15s | yes | seated anchor |
| `sit_to_stand_lib` | `sit_to_stand` | 2.25s | no | stand-up |

### Gender-specific selection (`AdventurerModelController.gd`)

`ANIMATION_NAMES` is the shared/default set (walk/run/carry/sit).
`MALE_ANIMATION_NAMES` and `FEMALE_ANIMATION_NAMES` override per-gender;
`_resolve_anim_name()` picks by `_gender` (set in `_ready()`). Current
state: **male and female each override only `idle`** (the locomotive packs'
idle clips); walk/run/carry/sit are the shared clips for both. Adding a
gender-specific clip = add the library to `AdventurerModel.tscn` + one
line in the matching dict.

## Sit animation sequence

When a character sits in a chair, the controller drives
`stand_to_sit → sit (looped) → sit_to_stand`, advanced on
`AnimationPlayer.animation_finished`. Seated state comes from the parent's
`seated_chair` (Player and NPC both expose it — see
`docs/systems/furniture-items/README.md` "Chair sitting"). While in the
sit sequence the model faces 180° from the character (toward the chair
backrest). Chair positioning (`SEAT_RAISE`/`SEAT_FORWARD`/`STAND_DIST`)
lives in `scripts/world/furniture/Chair.gd`.

**Known outstanding issue (Blender task):** the sit clips carry BAKED
root offsets that don't align to the model origin — the seated pose's
hip root sits at local z≈−0.25 (sit) to −0.49 (end of stand-to-sit),
so the model appears off-center / behind the chair. `SEAT_RAISE`(0.40)/
`SEAT_FORWARD`(0.15) partially mask it. The clean fix is re-exporting
the three clips in Blender so the skeleton root sits at the character
origin during the seated pose, identical across all three clips. Once
that lands, re-tune (likely near-zero) `SEAT_RAISE`/`SEAT_FORWARD`.

## Crossfade smoothing

`AdventurerModelController.gd`:
- `BLEND_TIME = 0.3` — default crossfade (carry + sit transitions).
- `LOCOMOTION_BLEND_TIME = 0.5` — used for transitions between the base
  locomotion states (`LOCOMOTION_STATES = ["idle","walk","run"]`), i.e.
  idle↔walk↔run. The gender-specific poses differ noticeably from the
  locomotion poses, so the standard blend read as a snap; the 0.5s ease
  applies to both genders automatically.

## Replacing a clip (playbook)

1. Copy the new FBX over the old (or a new path + update the
   `AdventurerModel.tscn` library reference).
2. Confirm the rig (import once, inspect the skeleton's bone names), pick
   the right bone map.
3. Write/update the `.import` retarget block (correct `PATH:` key).
4. Delete the stale `.scn`, `--import`.
5. Bake the `.res` (rename clip, loop flag, strip armature root tracks,
   rewrite paths).
6. Wire into `AdventurerModel.tscn` + the controller dicts as needed.
7. Verify headlessly (library loads, tracks resolve, bones move from rest
   — instantiate `AdventurerModel` and check `get_bone_global_pose`
   changes over a few frames), then playtest.