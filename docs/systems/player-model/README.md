# Player Model System

**Read this before opening `PlayerModelController.gd` or
`scenes/player/PlayerModel.tscn`.**

## Purpose
Owns the player's visual body: skeleton, skinned mesh, and locomotion
animation. Distinct from the Player subsystem (`docs/systems/player/
README.md`), which owns movement/stamina/interaction and does not know
this system exists beyond instancing `PlayerModel.tscn` as a child.

## Responsibilities
- `PlayerModelController.gd`: applies self-light-exclusion + no-cast-shadow
  to every visual `MeshInstance3D` under the model (generalized version of
  what used to be a single hardcoded line in `Player.gd`), sets the
  `AnimationPlayer`'s root motion track as a runtime fallback, and picks
  idle/walk/run based on the sibling `Player` node's real `velocity`.

## Non-responsibilities
- Does not own movement, stamina, or input — reads only already-public
  `CharacterBody3D.velocity` (engine builtin) and `Player.sprint_speed`
  (`@export`).
- Does not own the character's collision shape or the shadow stand-in —
  both remain on `Player.tscn`'s root `$CollisionShape3D`, read by
  `CharacterShadowStandIn.gd` (Graphics subsystem), untouched by this
  system.

## Files
| File | Role |
|---|---|
| `scenes/player/PlayerModel.tscn` | Instances the imported `male.fbx` body + `AnimationPlayer` with idle/walk/run libraries; instanced as a child of `Player.tscn`'s `CharacterBody3D` root. |
| `scripts/player/PlayerModelController.gd` | Attached to `PlayerModel.tscn`'s root — see Responsibilities above. |
| `assets/models/player/male.fbx` | Mixamo-rigged base male body (`mixamorig:` skeleton). Source: `assets/models/WIP/FINAL/Male Locomotion Pack/`, Quaternius, CC0. |
| `assets/models/player/idle.fbx` / `walk.fbx` / `run.fbx` | Matched Mixamo animation clips (same skeleton) for the body above. Imported as separate `AnimationLibrary` resources under `assets/models/player/anims/`. |

## Source asset selection (Aug 2026)
Three male-body candidates existed in `assets/models/WIP/`. Only
`FINAL/Male Locomotion Pack/male.fbx` shares its exact Mixamo skeleton
with a matched set of locomotion animations in the same folder —
confirmed by comparing `mixamorig:` bone names directly in each FBX, not
by filename. `FINAL/Farming Pack/male.fbx` is also Mixamo-rigged but from
a different retarget session (different skin-file UUID → different mesh/
proportions) — don't treat it as interchangeable with the Locomotion Pack
body without re-verifying. `Universal Base Characters[Standard]/.../
Superhero_Male_FullBody.fbx` is Quaternius's own native (non-Mixamo) rig
— it's the original source kit `FINAL` was curated from, has no matching
animations, and is not compatible with the Mixamo clips without a full
retargeting pass.

## Animation names
Confirmed strings registered in `PlayerModel.tscn`'s `AnimationPlayer`
(see `PlayerModelController.gd`'s `ANIMATION_NAMES` mapping):

- `idle_lib/idle` — idle, 8.33s loop
- `walk_lib/walk` — walk, 1.03s loop
- `run_lib/run` — run, 0.73s loop

Each clip library is a separate `AnimationLibrary` resource under
`assets/models/player/anims/`, so Godot prefixes the animation name with
its library name. All three were baked with `Animation.LOOP_LINEAR` so the
locomotion cycles repeat seamlessly. The animation track paths were
rebased from the clip FBX's own hierarchy (`Skeleton3D:bone`) to the
wrapper's (`MaleModel/Skeleton3D:bone`) — `AnimationMixer` resolves tracks
relative to the `AnimationPlayer`'s parent, not the `AnimationPlayer`
node itself.

## Common edits
- **New locomotion state (e.g. sprint-distinct animation, crouch):** add
  a new const/branch in `PlayerModelController._process()`'s state
  selection, following the existing walk/run pattern — reads
  `Player`'s public state only, no `Player.gd` changes needed unless the
  new state needs a Player-owned flag that isn't already public.
- **New mesh part (hair, clothing) attached to the skeleton:** add as a
  new `MeshInstance3D`/`BoneAttachment3D` under the existing `Skeleton3D`
  inside `PlayerModel.tscn` — `PlayerModelController._ready()`'s
  mesh-layer loop already picks up any `MeshInstance3D` found anywhere
  under the model root, no controller script changes needed.
- **`AnimationPlayer` must stay the FIRST child of the `PlayerModel`
  root.** `PlayerModelController._find_first_of_type()` searches
  depth-first, and the imported `male.fbx` scene carries its own internal
  `AnimationPlayer` (a 1-frame bind animation) — if the wrapper's
  `AnimationPlayer` falls after the `MaleModel` instance in child order,
  the controller would bind to the FBX's player instead and nothing would
  animate.

## Materials (Aug 2026 fix pass)
`male.fbx` ships with UV layers but no texture data (Mixamo auto-rig
exports never include textures). `PlayerModelController._build_skin_material()`
builds one `StandardMaterial3D` from `assets/models/player/textures/`
(copied from `WIP/FINAL/Textures/`) and applies it to every surface on
every `MeshInstance3D` found under the model — including eyes/eyebrows,
which will read as skin-colored rather than white/dark until a follow-up
assigns per-surface materials by name (would need to confirm surface
index-to-part mapping in-editor first).

## Known tradeoffs / tech debt
- No held-item hand-bone attachment yet — `InteractionSystem.gd`'s
  `HoldPoint` (Player-subsystem-owned) is still a fixed `Node3D` offset
  from the character root, not attached to a hand bone. Flagged as a
  likely future cross-thread touchpoint once arm-swing animation makes
  the fixed offset visually wrong, not addressed in this pass.
- Idle/walk/run only — no jump, sit, or NPC-shared reuse yet, despite
  `FINAL/` already containing matching poses (`Sit To Stand.fbx`,
  `Sleeping Idle.fbx`, etc.) and a female locomotion pack. Deliberately
  scoped to the minimum for this pass.
- The animation libraries' track paths are rebased to the wrapper's
  `MaleModel/Skeleton3D` hierarchy — renaming or moving that instance in
  `PlayerModel.tscn` requires regenerating the `.res` libraries
  (`tools/build_player_model.gd`).