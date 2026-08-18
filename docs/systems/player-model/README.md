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
- Does not own the character's collision shape or the shadow stand-in.
  The collision shape remains on `Player.tscn`'s root `$CollisionShape3D`.
  The shadow itself (Aug 2026) comes from a second `PlayerModel.tscn`
  instance (`PlayerModelShadow` in `Player.tscn`, Graphics-owned) with
  `PlayerModelController.is_shadow_only = true` — see
  docs/systems/graphics/README.md "Player model-based shadow". That flag
  is the one Graphics-driven addition to this controller; default
  `false` leaves every other instance, including the real one, unaffected.

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

## Hair (Aug 2026)
`PlayerModelController._setup_hair()` attaches `assets/models/player/
hair/Hair_Buzzed.gltf` (source: `WIP/FINAL/Hairstyles/"Rigged to Head
Bone"/`) onto our Mixamo skeleton's own Head bone via a runtime-created
`BoneAttachment3D`. That source asset ships skinned to a *different*
(Quaternius-native) reference armature, not ours — confirmed by direct
binary inspection that it's 100% rigidly weighted to its own Head joint,
so rather than remapping skin weights onto our skeleton, the mesh's own
bind-pose transform for that joint (`Skin.get_bind_pose()`, read at
runtime, not hardcoded — differs slightly per hairstyle file) is applied
to a plain static copy of the mesh instead. Swap hairstyles by changing
`HAIR_SCENE_PATH`/`HAIR_MESH_NODE_NAME` and copying the new file's
`.gltf`/`.bin`/textures the same way — the extraction logic is generic,
not specific to `Hair_Buzzed`.

**Materials (Aug 2026 fix pass):** the imported hairstyle's own material
wasn't rendering (flat grey despite the source textures being present),
so `_build_hair_material()` builds and force-assigns a `StandardMaterial3D`
at runtime instead, same approach `_build_skin_material()` already uses
for the body.

**Position tuning (Aug 2026, second fix pass):** two automatic attempts
at computing the head-attach transform both landed wrong (feet/hips,
then mid-section) — the source hairstyle's skin data is authored against
a completely different reference skeleton than ours, and getting an
exact automatic mapping right would need a real cross-skeleton retarget,
not a one-line transform. Simplified instead: `_setup_hair()` now uses
plain `Transform3D.IDENTITY` (trusting `BoneAttachment3D` alone to track
the real bone position) and `hair_position_offset`/
`hair_rotation_offset_deg` (exported on `PlayerModel`'s root node) are
the ONLY placement mechanism. The position default is baked from
headless measurement — `Vector3(0.0, -1.546469, 0.005373)` — because the
hair mesh's geometry is authored ~1.73 above its own origin in the
source frame and our Head bone's rest basis is identity, so the mesh
origin has to drop ~-1.55 to land the geometry on the crown (measured
hair center `y≈0.77` vs crown `y≈0.81` at rest). Adjust by eye in the
Inspector if a few centimeters off; degrees for rotation.

**Not done here (clothing):** researched Quaternius's catalog for a
matching modern/survival outfit pack — none exists for this rig yet,
only a medieval "Modular Character Outfits - Fantasy" set. Deferred per
direct instruction; revisit direction (re-texture vs. adapt the fantasy
pack vs. source elsewhere) before attempting clothing.

## Floor alignment & facing (Aug 2026)
`PlayerModelController._ready()` offsets `PlayerModel`'s own position by
`-(capsule_height / 2)` to align the model's floor (Mixamo convention:
origin between the feet) with the `CharacterBody3D`'s real floor (which
sits below the capsule's center, where this node is instanced) — same
math `CharacterShadowStandIn.gd` uses for the shadow proxy, kept in sync
deliberately. `MODEL_FLOOR_FUDGE` is available if per-asset origin
variance ever needs a small additional correction; `0.0` until verified
needed. `MaleModel`'s `PlayerModel.tscn` transform carries a static 180°
Y rotation correcting Mixamo's forward-axis convention against Godot's
own `-Z` forward — a model-space fix, not a movement-code change;
`Player.gd`'s facing math is untouched.

**Smooth visual turning (Aug 2026):** `Player.gd`'s own `rotation.y`
still snaps instantly every frame — unchanged, out of Player-Model
scope. `PlayerModelController` decouples the *visible* model's rotation
from that: it tracks its own `_visual_yaw`, lerps it toward Player's
real rotation each frame (`turn_speed`, exported, exponential-decay
convergence — same convention as `PickupableItem.slerp_to_upright()`),
then sets its own local `rotation.y` so the composed global rotation
(`Player.rotation.y + PlayerModel.rotation.y`) lands on the smoothed
value. Only the rendered mesh eases into turns; the hold point, any
facing checks, and everything else reading `Player.rotation.y` directly
still sees the true instant value, untouched.

## Known false lead
The "green circle at the player's feet" reported during this pass was
**not** a Player-Model bug — it was `scripts/world/build/
PlacementIndicator.gd` (Build-Mode/Furniture-thread file), a
build-preview disc that had no show/hide wiring anywhere in the codebase
and defaulted to visible from game start, unrelated to and predating
this subsystem. Defaulted to hidden as a flagged one-line fix; real
show/hide wiring for Build Mode placement preview is that thread's task,
not covered here.

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