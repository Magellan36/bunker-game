# Player Model System

**Read this before opening `PlayerModelController.gd` or
`scenes/player/PlayerModel.tscn`.**

## Native-rig rebuild (Aug 2026, IN PROGRESS)

**Status: retarget complete (headless), visual checkpoint outstanding.**
This section supersedes the Mixamo-era sections below where they conflict.
Plan: `PLAYER_MODEL_NATIVE_RIG_REBUILD_PLAN.md` (since removed; the
surviving record is this README section). The mechanical retarget is done
and verified headlessly; the remaining items are in-editor visual checks
(forward-facing, hair bind-pose placement, material rendering) that cannot
be confirmed without rendering.

### What's being replaced
The base body is switching from the Mixamo-retargeted `male.fbx`/
`female.fbx` to Quaternius's native rigs
`assets/models/player/Superhero_Male_FullBody.gltf` /
`Superhero_Female_FullBody.gltf` (copied from
`assets/models/WIP/Universal Base Characters[Standard]/.../Godot - UE/`,
which the editor has already imported in place). Reason: the recurring
cross-skeleton friction with every Quaternius-sourced asset since — hair
placement first, then this outfit pack — traces back to the body being on
Mixamo's `mixamorig:` skeleton while everything else is native UE4/UE5
Mannequin-named. Putting the body on the same skeleton the hairstyles were
always rigged for is the actual fix that the manual per-style hair offsets
were papering over.

**Retargeted (not dropped):** `walk`, `run`, `idle_carry`, `walk_carry`,
`run_carry`, and `idle` — `idle` only as a placeholder until a replacement
is picked from UAL1/UAL2 or elsewhere; do NOT mistake the current idle for
a deliberate choice.

### Bone-name convention change
`mixamorig:*` → profile names. The Part-2 retarget renames BOTH the native
skeleton and every Mixamo clip onto Godot's built-in Humanoid profile, so
both pipelines end up on the same bone names (`Hips`, `Spine`, `Chest`,
`UpperChest`, `Neck`, `Head`, `LeftUpperArm`, ...). The root/hip bone is
`Hips` in both — `PlayerModelController.gd`'s `_find_bone_path(..., "Hips")`
fallback resolves identically for the Mixamo and native pipelines. The
native `root` bone is intentionally left unmapped (keeps its baked −90° X
rotation that orients the body Z-up). Full Mixamo→native mapping lives in
the two BoneMap resources (`bone_map_mixamo.tres` / `bone_map_native.tres`).

### How the retarget was done (headless, not manual editor clicks)
Godot's built-in scene importer exposes per-node retarget options through
the `_subresources.nodes` block of each `.import` file (the same block the
Advanced Import Settings dialog writes). `tools/apply_retarget_imports.gd`
writes that block for all 8 files: `retarget/bone_map` (one of the two
BoneMap resources above) plus the renamer/rest-fixer defaults. On reimport
the import pipeline renames the skeleton node to `GeneralSkeleton`
(unique-name flag set), renames bones to profile names, and retargets the
animation tracks to `%GeneralSkeleton:<profile bone>`. The track paths in
the rebuilt `.res` libraries are `MaleModel/%GeneralSkeleton:Hips` etc. —
the `%` unique-name prefix resolves through the body's `Armature` wrapper
node, so no path change was needed in the build tooling.

**Verified headlessly (no rendering needed):** all 52 tracks in each of the
six rebuilt `.res` libraries resolve to the real skeleton on both the male
and female native bodies (`UNRESOLVED_TRACK_NODES=0`); idle playback moves
the legs ~0.002 rad/s (healthy subtle idle), run moves them ~0.58 rad; the
Hips position track is removed as before (sink fix), so no root motion.

**Verified by direct inspection of both gltf files (not assumed):** both
have 69 nodes / 65 skin joints, identical structure; mesh nodes
`Superhero_Male`/`Superhero_Female`, `Eyes`, `Eyebrows` are direct
children of the `Armature` root; hierarchy is `Armature → root → pelvis →
spine_01…` (there IS a `root` node above `pelvis`, unlike Mixamo, where
`Hips` has no parent node — exactly what Godot's retarget system absorbs).

### Corrections to the plan (found during prep)
- **There is NO baked-in hair mesh in either native file.** Only three
  meshes exist (body, `Eyes`, `Eyebrows`). The `MI_Hair_1` (male) /
  `MI_Hair_2` (female) materials that the plan assumed were a baked-in
  hairstyle are actually assigned to the **`Eyebrows`** mesh geometry
  ("Face" in the male file). The plan's "hide the baked-in hair" step is
  therefore N/A — but the eyebrow mesh wearing a hair-texture material is
  exactly the sort of thing to eyeball at the Part-2 checkpoint; if the
  brows render oddly, our runtime material override (below) already
  replaces that material with the flat `hair_tint_color` eyebrow material.
- **Orientation:** the native file's `root` node carries a baked −90° X
  rotation (Blender Y-up→Z-up correction). Playtest VERIFIED that this does
  NOT fix the forward axis — the in-game body and all its animations
  rendered backwards until the same 180° Y flip the Mixamo body uses was
  applied to the body node. Both rigs now share that flip.
- **Skin material:** the native import's own materials reference the real
  textures (`T_Superhero_*`, `T_Eye_*`, `T_Hair_*` — confirmed in the gltf
  image list). The `_build_skin_material()` runtime override may no longer
  be needed; attempt removing it and verify the baked materials render —
  keep the function as fallback if not.
- **Hair placement:** with the body on the native skeleton the hairstyles
  were rigged for, the original automatic bind-pose placement (instead of
  the manual per-style `position_offset` system) should work for the first
  time. Plan Part 5: try that first, reset all manual offsets (including
  the female deltas) to zero, re-verify from scratch. The old numbers are
  tied to the Mixamo skeleton's geometry — do not carry them forward.

### Part-2 editor steps (DONE — done headlessly, not by manual clicks)
1. Both gltf files are in `assets/models/player/` and imported (the new
   copies import on the next scan).
2. Retarget mapping was authored as two BoneMap resources
   (`bone_map_native.tres` mapping the native skeleton onto the Humanoid
   profile with `root` unmapped; `bone_map_mixamo.tres` mapping
   `mixamorig_*` onto the same profile) and wired into the `_subresources`
   node settings of all 8 `.import` files (see "How the retarget was done"
   above). This is the same configuration the Advanced Import Settings →
   Retarget/Rest Pose section would produce by hand.
3. With both skeletons mapped onto the same Humanoid profile, the animation
   FBXs are reimported "retargeted to" the native skeleton — Godot computes
   the rest-pose correction, nothing here is pre-baked.
4. Checkpoint before continuing: native body stands correctly (no hover,
   forward-facing correct — checked fresh, not assumed) with idle playing.
   **Remaining visual check — do this in the editor/playtest now.**
5. Then re-check walk/run/carry individually. **Remaining visual check.**

### Part-4/5 code changes (prepared behind `native_rig`, default off)
All the controller-side switches are already in `PlayerModelController.gd`
behind a new `@export var native_rig: bool = false` (default = existing
Mixamo behavior, byte-for-byte unchanged): `NATIVE_BODY_SCENE_PATHS` (the
two gltf paths) selected when the flag is on; the root-motion fallback
looks for `"Hips"` (the retargeted profile name — this replaces the
plan-era `"pelvis"` note, see the bone-name section above); the body
instantiates with an identity transform (NO assumed 180° fix — forward-
facing flagged unverified); the runtime skin/eye material override is
skipped so the native import's own baked materials render — except the
eyebrow override, which applies on BOTH paths (see "Eyes & Eyebrows
materials"); and
`_setup_hair()` uses the source skin's own Head bind pose with ZERO manual
offsets (all Mixamo-era offsets — `position_offset`, `FEMALE_HAIR_DELTA`,
`FEMALE_HAIR_EXTRA_BACK_Z`, the female-beard +3cm — deliberately not
applied on native).

The flag is only the controller half. The other half: PlayerModel.tscn's
six `AnimationLibrary` references must point at RETARGETED `.res` resources
before the flag is flipped — with the old Mixamo-rebased libraries the
tracks won't resolve against the native skeleton and nothing animates.
Sequence: do the editor retarget (Part 2), get the retargeted resources,
wire them into PlayerModel.tscn, THEN flip `native_rig` on the Player/NPC/
preview instances and go through the checklist. Docs get updated with
whichever "should work, verify" items turn out true/false after testing.

**Current state (Aug 2026):** the retarget + rebuild are done (see above),
the six `.res` libraries are the retargeted ones, and `native_rig = true`
is now set on Player.tscn's `PlayerModel`/`PlayerModelShadow`, NPC.tscn's
`CharacterModel`/`CharacterModelShadow`, and the character-creation
preview. The remaining item is the visual checkpoint (forward-facing, hair
bind-pose placement, baked materials rendering) — everything mechanical is
verified headlessly.

### Part-3 build tooling
`tools/build_player_model.gd` still packages the retargeted clips: it loads
each retargeted `.scn`'s `mixamo_com` animation, rebases the track paths
(`%GeneralSkeleton:...` → `MaleModel/%GeneralSkeleton:...`), removes the
Hips position track (sink fix), and saves each as an `AnimationLibrary`.
Confirmed still needed — the `%` unique-name prefix keeps the rebase
resolving through the native body's `Armature` wrapper, so the tooling's
role is unchanged, just operating on profile-named bones now.
`tools/build_player_model_editor.gd` is the same logic as an EditorScript.

### Checklist (staged)
- [x] Retarget configuration authored (two BoneMap resources) and applied
      to all 8 `.import` files via `_subresources.nodes`
- [x] All 8 files reimported with retarget active (skeleton node renamed to
      `GeneralSkeleton`, bones renamed to profile names, tracks retargeted
      to `%GeneralSkeleton:*`)
- [x] Six `.res` animation libraries rebuilt from retargeted clips; all 52
      tracks per library resolve on both male and female native bodies
      (headless-verified, `UNRESOLVED_TRACK_NODES=0`); idle/run playback
      drives the skeleton sanely
- [x] `native_rig = true` set on Player, NPC, and preview instances
- [x] VISUAL CHECKPOINT: body stands correctly with `idle`; forward-facing
      corrected with the same 180° Y flip both rigs use (playtest-confirmed
      backwards before the fix)
- [ ] VISUAL: walk/run/carry each look right on the native body
- [ ] VISUAL: hair bind-pose placement (source skin's own Head bind pose,
      zero manual offsets) lands correctly; reset/re-derive if not
- [ ] VISUAL: baked body/eye materials render on native (no runtime
      override for those); eyebrow material now runtime-overridden on both
      paths — brows should match hair_tint_color at load and after a
      swatch change
- [ ] VISUAL: Peasant outfit renders on both genders, covers
      torso/arms/legs/feet, deforms naturally through idle/walk/run/carry
      (bind bones headless-verified 65/65; deformation is the real test)
- [ ] VISUAL: male exposed hand/forearm skin (`MI_Regular_Male` part of
      Arms) shows the skin texture, not a missing/default material
- [ ] VISUAL: outfit tracks scale/floor/facing like the body; note any
      serious z-fighting/clipping vs. the nude body underneath
- [ ] Female body same checks (mapping transfers from male — verified
      headlessly that its tracks resolve; visual only)
- [ ] NPC randomization + character-creation end-to-end with new body/animations

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
| `scenes/player/PlayerModel.tscn` | `AnimationPlayer` with idle/walk/run libraries + `PlayerModelController.gd`, which instantiates the body itself at runtime (see "Runtime body & character creation" below); instanced as a child of `Player.tscn`'s `CharacterBody3D` root. |
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
every `MeshInstance3D` found under the model, except `Eyes`/`Eyebrows`
— see "Eyes & Eyebrows materials" below.

**Hair tint (Aug 2026):** `T_Hair_1_BaseColor.png`/`T_Hair_2_BaseColor.png`
are both neutral/untinted strand-shading textures, not real hair color —
opened directly and confirmed pale grey/beige, and the source glTF
material doesn't set a `baseColorFactor` tint either. `hair_tint_color`
(exported on `PlayerModel`'s root node, default a dark brown) is
multiplied into the hair material's `albedo_color` to supply actual
pigment — change hair color by editing that one field, not the texture.

**Running animation (Aug 2026):** `assets/models/player/run.fbx` was
replaced with a different source clip (same Mixamo skeleton, same
`mixamo.com` internal stack name — fully compatible, no code changes).
`tools/build_player_model.gd` re-baked from it the same way it always
has; if the running animation ever needs swapping again, that's the only
step required (replace the file at that path, re-run the bake script).

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
to a plain static copy of the mesh instead. Swap hairstyles by copying the
new file's `.gltf`/`.bin`/textures into `assets/models/player/hair/` and
adding an entry to the `HAIRSTYLES` dictionary (key → scene path + mesh
node name + base `position_offset`) — the extraction logic is generic,
not specific to `Hair_Buzzed`. See "Runtime body & character creation"
below.

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
the real bone position) plus a per-style base offset carried in the
`HAIRSTYLES` dictionary (see "Runtime body & character creation" below).
`hair_position_offset`/`hair_rotation_offset_deg` (exported on
`PlayerModel`'s root node) remain as an ADDITIONAL nudge on top of the
style's base offset — both now default to `0.0`. The baked base offset
for `buzzed` is `Vector3(0.0, -1.576469, 0.057)` — because the
hair mesh's geometry is authored ~1.73 above its own origin in the
source frame and our Head bone's rest basis is identity, so the mesh
origin has to drop ~-1.55 to land the geometry on the crown (measured
hair center `y≈0.77` vs crown `y≈0.81` at rest). The `+0.057` Z is the
forward/back correction from the same headless pass (deformed skull
extents computed via `get_bone_global_pose` × bind pose): with only the
Y dropped, the cap's front edge sat ~6cm short of the forehead while
its back overhung the skull ~4cm; +0.057 centers the cap within the
skull's front-to-back extent (verified: cap front/back end up ~8mm
clear of the head band on both sides, hair center world
`(0.0, 0.78, -0.037)`). The `-1.576469` Y reflects small +/- adjustments
applied after in-game confirmation of how the hair sits on the skull
(hair center now `y≈0.75`). Adjust by eye in the
Inspector if a few centimeters off; degrees for rotation.

**Not done here (clothing):** researched Quaternius's catalog for a
matching modern/survival outfit pack — none exists for this rig yet,
only a medieval "Modular Character Outfits - Fantasy" set. The Peasant
outfit from that set is now attached always-on (see the "Outfit
(Peasant)" section below); no character-creation UI selection this pass,
same rollout order hair followed. Revisit direction (re-texture vs.
adapt the fantasy pack vs. source elsewhere) before a second outfit.

## Outfit (Peasant, Aug 2026)
`PlayerModelController._setup_outfit()` attaches
`assets/models/player/outfits/Male_Peasant.gltf` /
`Female_Peasant.gltf` (source: `WIP/FINAL/Modular Character Outfits -
Fantasy[Standard]/.../glTF (Godot-Unreal)/Outfits`; 4 pieces per gender:
Arms / Body / Feet / Legs) to the native body via DIRECT skin/skeleton
reassignment — the first piece of the character that could use proper
skin binding instead of the BoneAttachment3D/bind-pose tricks hair and
beard need.

**Why it binds directly:** the outfit's skin joints are an exact 65/65
match (same names, same order) for the native skeletons specifically —
verified by parsing both raw gltf files, and again headlessly against the
imported scenes. Two requirements make that true in the imported data:

1. The outfit gltf files are imported with the SAME `bone_map_native.tres`
   retarget as the native bodies (added to
   `Male_Peasant.gltf.import` / `Female_Peasant.gltf.import`
   `_subresources`), so the outfit scene's skeleton and skins use the
   Humanoid-profile bone names OUR skeleton has. Without this, the raw
   gltf names (`pelvis`, etc.) don't match the retargeted live skeleton
   (`Hips`, etc.) and nothing binds.
2. The mesh pieces are reparented directly under OUR skeleton at runtime
   with `skeleton = NodePath("..")`, discarding the outfit scene's own
   bundled skeleton. Each outfit mesh's `skin` resolves all 65 bind bones
   against our skeleton (headless-verified, 0 unresolved).

**Not a generic pattern:** only valid because of the exact joint match +
shared retarget. For any future asset that isn't bone-identical, use the
hair-style bind-pose/BoneAttachment3D approach instead.

**Materials:** the outfit's baked materials are used as-is (base
color/normal/ORM texture sets per material, including `MI_Regular_Male`
for the male's exposed hand/forearm skin) — no runtime material code, in
line with the native body's own baked materials precedent.

**Known cosmetic caveat (not a blocker this pass):** the nude body mesh
stays fully rendered underneath, so expect minor z-fighting/clipping
where the outfit overlaps the body at movement extremes. A later pass can
hide the covered body pieces when an outfit is worn.

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

## Overall scale (Aug 2026)
`PlayerModel` and `PlayerModelShadow` both carry a `1.25` uniform scale
in `Player.tscn` (the model was reported too small). Pure scene-level
change — `PlayerModelController.gd` never touches `.basis`/scale at
runtime, only `.position.y` for floor alignment, so this composes safely
with everything else in this doc. `PlayerModelShadow`'s existing `0.3`
Y-only squash (shortened-shadow look) is scaled proportionally alongside
it — `0.375 = 0.3 × 1.25` — if that ratio (not the `1.25` factor) is ever
retuned, keep the two scale values' ratio in sync manually, they're not
computed from each other. The collision capsule in `Player.tscn` is
intentionally left at its original size (hitbox is movement/physics
territory, not this subsystem's) — the character now renders ~25% bigger
than its capsule, which may look slightly off at close range and is a
known, flagged tradeoff.

## Shared with NPCs (Aug 2026)
`scenes/npc/NPC.tscn` now instances this exact same `PlayerModel.tscn` —
same model, same hair, same idle/walk/run animations, same `1.25` scale
as the player, replacing NPCs' old smaller placeholder capsule
(`radius 0.4`/`height 1.8` vs. Player's un-overridden `0.5`/`2.0` — that
size difference is gone; both now use the same defaults).
`PlayerModelController.gd` needed zero changes to support this — it was
already written generically against `get_parent()` as any
`CharacterBody3D`, not specifically `Player`, with safe fallbacks
anywhere it reads a Player-specific property (`sprint_speed`,
`PLAYER_SELF_LIGHT_LAYER_BIT`). No per-NPC customization yet (hairstyle
variety, body variation) — deliberately deferred to a later pass.
`class_name PlayerModelController` and this doc's own "Player-Model
subsystem" naming are now slightly inaccurate given NPCs share it too;
left as-is for this pass rather than a disruptive rename — worth
revisiting alongside the customization pass.

**Update (Aug 2026, shadow-parity follow-up):** NPCs have since been
upgraded to the same real-silhouette shadow system Player uses —
`NPC.tscn` gained a `CharacterModelShadow` sibling instance (same
`is_shadow_only = true` pattern as `Player.tscn`'s `PlayerModelShadow`,
same `1.25` scale composed with the `0.3` Y-only squash → `0.375`), and
`NPC.gd` no longer calls `CharacterShadowStandIn.attach(self)`. See
`docs/systems/graphics/README.md` "Player model-based shadow" (now
shared with NPCs) for the full mechanism — unchanged from the player's
version, since `PlayerModelController.gd`'s `is_shadow_only` export was
already generic over any parent `CharacterBody3D`.

## Carry-state animations (Aug 2026)
`idle_carry`/`walk_carry`/`run_carry` play instead of the plain
locomotion states whenever `_is_holding_item()` is true — checks
`Player.get_held_item()` where that method exists, falls back to a
plain `held_item` property read for NPC, no changes needed to either
file. Full parity across all three states (no fallback-to-plain-run
judgment call needed — a real carry-run clip was provided). Swapping any
one of the three carry clips later follows the exact same steps as
swapping the base run animation (see "Running animation" above) — just
substitute the `_carry`-suffixed filename/dict keys.

## Runtime body & character creation (Aug 2026)
`PlayerModel.tscn` no longer statically instances the `male.fbx` body —
`PlayerModelController._ready()` instantiates the body scene itself at
runtime and adds it under the root:

- **Which body:** `BODY_SCENE_PATHS[gender]`, where `gender` comes from
  `CharacterCreationData` (`"male"` default) only when
  `use_character_creation_data = true`; otherwise hardcoded male. The
  selected skin is applied per-gender from `SKIN_TEXTURES` (female →
  `T_Superhero_Female_Dark_BaseColor.png`, male → `T_Superhero_Male_...`).
- **Node name is load-bearing: `MaleModel`.** Every baked animation
  library's track paths are `MaleModel/Skeleton3D:mixamorig_*`, and the
  FBX's imported scene exposes its skeleton as a direct child literally
  named `Skeleton3D` for both male and female, so the runtime body must
  keep the exact name `MaleModel` or every animation track fails to
  resolve (hundreds of warnings, nothing animates). Do not rename.
- **Facing:** the runtime body is added with
  `Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)` — the 180° static Y
  rotation that used to live on the scene now happens in code because the
  body is dynamic. Note the 12-scalar `Transform3D(...)` literal is NOT
  callable from GDScript; use the `Basis`+`Vector3` form.
- **Female import override:** `female.fbx` imports at
  `root_scale = 100.0` to match `male.fbx` (Godot's default `1.0` left
  the female body ~100× too small); that override lives in
  `assets/models/player/female.fbx.import`.
- **Who reacts to `CharacterCreationData`:** only instances with
  `use_character_creation_data = true` (`Player.tscn`'s `PlayerModel` +
  `PlayerModelShadow`, and the creation screen's preview). Everything else
  (NPCs, default) keeps the identical hardcoded male/buzzed/dark-brown
  look as before — see `docs/systems/character-creation/README.md` for the
  full screen flow.

## Floor-offset guard (Aug 2026)
The floor-alignment offset in `_ready()` only applies when there's a
real `CharacterBody3D` parent with a `CapsuleShape3D` to align against
— it used to apply unconditionally, which sank the character-creation
screen's parentless preview instance by a meter for no reason. A
diagnostic print (gated off for the shadow instance to avoid doubling
console noise) reports `had_real_collision`/`capsule_height`/
`applied_position_y` for every real spawn — delete once nobody needs it
anymore.

## Hips-sink root cause (Aug 2026)
The "sinking" reports across this whole investigation were caused by the
baked animation clips' Hips position track, not the floor-offset math
(which was correct the entire time). Every clip pinned `mixamorig_Hips`
to ~y=0.01 (the FBX scene origin, floor level) versus its real skeleton
rest height (~1.044), sinking the animated body ~1.03m below where the
(correctly-computed) model root actually sat — during normal playback
the whole skeleton, not just the root, rode the baked value.

Fixed in `tools/build_player_model.gd`: the Hips **position** track is
stripped from all six clips at bake time, so the bone falls back to its
skeleton rest pose (correct standing height) while every other track
(including Hips' own rotation for hip sway) is untouched. Deleting the
track rather than baking a fixed +1.034 correction is deliberately
robust across genders — each skeleton falls back to its *own* rest
height rather than hardcoding one gender's number onto both. This also
removes the small Hips-Z forward drift flagged in walk/run.

Also corrects an earlier documented misunderstanding: `root_motion_track`
being set to the Hips bone does NOT exclude that track's translation
from posing the bone — it only exposes the motion via
`get_root_motion_position()` for code that chooses to consume it; the
bone is still posed with its full baked translation otherwise, and
`Player.gd` never cancels it back out (it moves via `move_and_slide()`,
no `get_root_motion_*()` calls). `_root_motion_track_valid()` only
checked that the NodePath resolved to a real bone, so it had no way to
catch that the bone's own keyframe values were the problem.

## Per-hairstyle position offsets (Aug 2026, 2nd pass)
Every `position_offset` in `HAIRSTYLES` is derived from the SOURCE
inverse-bind matrices, not the mesh geometry, using the formula
`style_offset = buzzed_offset + (head_world_buzzed − head_world_style)`
per axis, where `head_world` is the source armature's Head bone world
position (recovered from the `.gltf` `inverseBindMatrices` buffer for
the joint named "Head"). The mesh-geometry-center terms cancel out of
that derivation — only the head-bone world delta matters — so:

- The six assets actually span TWO different reference armatures, not
  one: `buzzed`/`simple_parted`/`beard` share armature A (Head bone
  world y ≈ 1.5998, ~−15.4° x-rot) and `buzzed_female`/`buns`/`long`
  share armature B (Head bone world y ≈ 1.5496, ~−23.6° x-rot).
- Armature A styles therefore reuse `buzzed`'s exact offset (identical
  head bone), which also correctly preserves the beard's geometry sitting
  ~11cm lower on the jaw than the scalp styles — a chin piece is *meant*
  to be lower, and normalizing its center up to the scalp anchor (the
  first pass) moved it up onto the face.
- Armature B styles get one shared delta `(+0.0502 y, −0.0065 z)`.

The first pass instead normalized each mesh's raw `POSITION`-accessor
AABB center onto `buzzed`'s anchor, which was internally consistent but
mathematically wrong: it lifted the beard ~11cm off the jaw and
mis-set every other style by 1–4cm. Caveat that remains: armature B's
head is also rotated ~8° more than armature A's, and placement is
translation-only today (`hair_rotation_offset_deg` defaults to 0), so a
perfect match there may still want a small per-style rotation nudge on
top of the corrected offset. If a new hairstyle is ever added, compute
its offset from the source bind matrices with the formula above, and
check which armature group it belongs to.

## Female body hair placement (Aug 2026)
The female body (`female.fbx`) uses the exact same `HAIRSTYLES` offsets
as the male — verified from both FBX `BindPose` matrices that the
`mixamorig:Head` bone has bit-identical world orientation across genders
(180° Y in FBX space; same `root_scale = 100.0` import), so the
bone-relative placement is equivalent and no per-style re-derivation was
needed. Live feedback still showed her hair reading slightly too high
and too forward, so a small uniform correction is applied at runtime:
`FEMALE_HAIR_DELTA` (`PlayerModelController.gd`, added to every style's
offset when gender is `"female"`). A follow-up pass brought every
non-long style onto the same effective z as `buns` via
`FEMALE_HAIR_EXTRA_BACK_Z` (per-style; `long` stays put). Uniform across
styles so relative placement between them is unchanged; the male is
unaffected.
If the female needs further tuning, edit those two constants rather than
the shared dict.

## Eyes & Eyebrows materials (Aug 2026)
`Eyes`/`Eyebrows` are separate sub-meshes within `male.fbx`/`female.fbx`
(own UV layers) — the material loop in `_ready()` must stay name-selective
for these two rather than reverting to a blanket "apply skin material to
every MeshInstance3D" loop, or this regresses. Eyes get a real texture
(`T_Eye_Brown`/`T_Eye_Normal`, copied from the source kit); eyebrows get
a flat color from `hair_tint_color` since no dedicated eyebrow texture
exists anywhere in the kit — the `Eyebrows_Regular`/`Eyebrows_Female`
assets are a separate *attachable* eyebrow-mesh system (parallel to
hairstyles) that would need its own selector if real eyebrow
variety/texture is wanted later, not a texture to bolt onto the body's
built-in eyebrow mesh.

On the native-rig path the baked eyebrow material is `MI_Hair_1` (male) /
`MI_Hair_2` (female) — the UNTINTED hair texture, because the source
kit's hair material is what the eyebrow sub-mesh is bound to in the gltf
(the male's `Eyebrows` node even references a mesh resource literally
named `Face`; harmless). That reads wrong next to `hair_tint_color`, so
the eyebrow override applies on BOTH paths (unlike skin/eyes, which keep
their baked materials on native): `_ready()` builds the flat eyebrow
material unconditionally and the mesh loop applies it to the `Eyebrows`
node via `set_surface_override_material()`. That override is also what
the creation screen's swatch repaint needs — it reads
`get_surface_override_material()` for `["Hair", "Beard", "Eyebrows"]`
and silently skips anything without an override, which is why eyebrows
never tinted on native before this fix.

## Beard as thumbnail toggle + NPC randomization (Aug 2026)
Beard is now a rendered thumbnail toggle in the creation screen,
reusing the hairstyle grid's thumbnail renderer (not a checkbox, not a
separate UI system). Unlike the hairstyle buttons it deliberately sits
in no `button_group`, so it toggles independently and combines with any
hairstyle; `CharacterCreationData.beard_enabled` drives the player
character only.

Female beard placement carries an additional +3cm Y correction on top of
the generic female-armature delta (`FEMALE_HAIR_DELTA`), applied
beard-only inside `_setup_hair()` — the generic delta was tuned for
scalp hair, not jaw placement, and the female beard read 3cm too low.

NPCs now randomize gender/hairstyle/color/beard per-instance via the
`randomize_appearance` export (distinct from
`use_character_creation_data`, which mirrors the player's choices) —
set on NPC.tscn's `CharacterModel`/`CharacterModelShadow` nodes. The two
instances per NPC synchronize through node metadata on their shared
parent (the NPC `CharacterBody3D`): whichever runs `_ready()` first
rolls and `set_meta()`s the result, the second reads it back, so a
body and its shadow always match. Female NPCs are never given a beard —
enforced with an explicit guard (`rolled_beard = false` after the
male-only roll), not just "didn't happen to roll it".
