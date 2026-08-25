# Player Model System

**Read this before opening `PlayerModelController.gd` or
`scenes/player/PlayerModel.tscn`.**

## V1 simplification — Adventurer models (Aug 2026, CURRENT)

**This is the current live system. Everything else in this document
(Native-rig rebuild, Outfit/Peasant, Hairstyles, character-creation
customization) describes the PACKED-AWAY system — preserved exactly as
it stood, not deleted, not currently wired into any scene. Read this
section first; treat the rest of the doc as historical/reference
material for when customization is reintroduced.**

**Why:** the full customization system below (swappable outfits,
hairstyles, hair color, beard, the native-rig retarget work) hit
diminishing returns for a V1 — a long chain of clipping/texture/rigging
fixes for character assets that don't match the game's intended
aesthetic in the first place, while free-model constraints meant
continued fighting with mismatched asset packs. Decision: ship V1 with
two complete, pre-made models — one per gender — and revisit real
customization once dedicated art/scope is available for a later version.

**What changed:**
- **New models:** Quaternius's "Ultimate Modular Men" (Feb 2022) and
  "Ultimate Modular Women" (April 2022) packs, specifically each pack's
  pre-assembled "Adventurer" character (grey hair/beige clothes/backpack
  for male; brown hair/green clothes/backpack for female) — copied from
  `F:\Bunker Game\models\player models\FINAL\` into
  `assets/models/player/adventurer/Adventurer_Male.fbx` /
  `Adventurer_Female.fbx`. Each is ONE complete, self-contained body —
  no per-piece swapping, no separate outfit/hair meshes to attach. Flat
  per-part material colors (no texture files at all — confirmed directly
  against the source pack), so none of the texture-pipeline issues the
  Peasant outfit had apply here.
- **New rig, same animations, verified working:** this pack uses a
  DIFFERENT bone-naming convention (`Hips`/`Chest`/`UpperArm.L`/`Hand.L`,
  CamelCase-dot) than the existing native skeleton
  (`pelvis`/`spine_03`/`upperarm_l`, lowercase-underscore). Rather than
  hand-retargeting the animation library, this project's EXISTING Godot
  Humanoid-retarget infrastructure was reused: a new
  `assets/models/player/adventurer/bone_map_adventurer.tres` (same
  `BoneMap`/`SkeletonProfileHumanoid` format as `bone_map_native.tres`)
  maps this rig's bones onto Godot's Humanoid profile, and both
  `Adventurer_Male.fbx.import`/`Adventurer_Female.fbx.import` carry the
  same `retarget/bone_renamer` + `rest_fixer` `_subresources` block as
  every other body/animation file in this project (see "How the retarget
  was done" below for the mechanism) — so the skeleton renames to the
  same shared `GeneralSkeleton` convention the existing idle/walk/run/
  `*_carry` animation library already targets. **Verified directly in
  the Godot editor** (not just headlessly): both the male and female
  Adventurer bodies play the existing `idle` animation correctly,
  natural standing pose, no broken/twisted limbs — confirmed by direct
  playtest.
- **Scale:** verified near-identical to the previous native body
  (Adventurer ~1.856m tall vs. the old body's ~1.810m, ~2.5% difference)
  — no rescaling needed.
- **New, simpler controller:** `scripts/player/AdventurerModelController.gd`
  + `scenes/player/AdventurerModel.tscn` REPLACE
  `PlayerModelController.gd`/`PlayerModel.tscn` in `Player.tscn`. Reuses
  the same proven floor-alignment, visual-turn-smoothing, animation-state
  (idle/walk/run/`*_carry`), and root-motion-track-resolution logic, but
  drops everything outfit/hairstyle-related — the model is complete on
  its own, nothing to attach. Gender still comes from
  `CharacterCreationData.gender` (the creation screen's Body category is
  still functional); nothing else on that autoload is read.
- **Character creation UI:** `CharacterCreationScreen.gd`'s Hair category
  joined Features/Accessories as disabled with a "Coming soon" tooltip
  (same pattern those two already used). Body/gender selection still
  works and drives which Adventurer model loads. The hairstyle/color/
  beard-picking code is left in the file, entirely unused (Hair category
  is unreachable) — packed away, not deleted, per the same reasoning
  above.
- **NOT touched:** `PlayerModelController.gd`, `PlayerModel.tscn`, the
  outfit assets, the hairstyle assets, `bone_map_native.tres` — all
  preserved exactly as they stood. No NPC scene exists in the project
  yet, so nothing NPC-side needed updating.

**To bring the old system back later:** point `Player.tscn`'s
`PlayerModel`/`PlayerModelShadow` nodes at `PlayerModel.tscn` again
(instead of `AdventurerModel.tscn`), and re-enable
`CharacterCreationScreen.gd`'s `category_hair_button` (remove its
`disabled = true` / tooltip lines). Everything else in this document
still describes that system accurately.

## Sit animation root-offset fix (Aug 2026, CURRENT)

**Builds on the V1 Adventurer system above — read that section first.**
Adds a full stand/sit/stand-up sequence (`stand_to_sit`/`sit`/
`sit_to_stand` clips) to `AdventurerModelController.gd`, driven by
`MainWorld.gd`'s `_wire_chair()`. The clips themselves needed a real
fix at the source; this section documents what was actually wrong and
how it was fixed, since it took several wrong turns to get right and
the final approach isn't obvious from the code alone.

**Source files:** `assets/models/player/stand_to_sit.fbx` / `sitting.fbx`
/ `sit_to_stand.fbx`, originally copied from `F:\Bunker Game\models\
player models\FINAL\Stand To Sit.fbx` / `Sitting.fbx` / `Sit To
Stand.fbx` (same source location as the rest of this pack). Extracted
into `assets/models/player/anims/stand_to_sit_lib.res` / `sit_lib.res` /
`sit_to_stand_lib.res` via `tools/build_sit_animations.gd` (same
track-rebase + Hips-position-track-removal pattern
`tools/build_player_model.gd` already established for the other six
clips — root motion is never consumed anywhere in this project, so no
clip should carry a baked Hips position track at all).

**The original problem:** the handed-off clips had a baked Hips
position offset that didn't correspond to the game's own anchor point,
so the character rendered sunk into/behind the chair.

**First fix attempt (WRONG — left in git history, not repeated here in
detail): recentering Hips to REST position was the wrong target.**
The first pass measured the Hips bone's position at the seated frame
and shifted the whole clip so Hips landed exactly at the skeleton's own
REST pose position — reasoning that rest position is what every other
animation (idle/walk/run, which have no Hips position track at all)
implicitly uses. This was wrong: REST position is *standing* hip
height, not seated hip height. Forcing seated Hips up to standing
height while the clip's own (untouched) leg-bend rotations still
expected a much lower hip position meant the legs could no longer reach
the floor — confirmed directly in Blender: with this fix, seated
`LeftFoot` sat at world Z≈0.005 vs. its true rest/floor value of
Z≈0.0009 (in the source file's native scale), i.e. visibly floating.
Symptom in-game: feet lifting off the ground, hips reading too high,
and (because the game code's horizontal chair-approach slide was ALSO
timed against this same wrong data) a "hovering" quality to the whole
sit-down motion.

**Correct fix: calibrate against the FEET at each clip's own genuine
STANDING frame, not the Hips at the seated frame.**

- `stand_to_sit.fbx`: frame 1 is a real standing pose. Shifted the whole
  clip (a constant delta on the Hips position curve — preserves all
  relative motion, just recenters it) so `LeftFoot`/`RightFoot`'s
  average world position at frame 1 exactly matches their REST-pose
  position (residual confirmed at ~1e-7, effectively exact). The seated
  endpoint (frame 135) is NOT independently forced to anything — it's
  whatever this single correction naturally produces, which turned out
  physically correct: seated Hip-above-foot height (~half the standing
  value) matches a normal bent-knee sitting posture (thigh
  ~horizontal, shin ~vertical) almost exactly.
- `sit_to_stand.fbx`: mirror approach, calibrated against its OWN
  genuine standing frame (the LAST frame, since this clip runs
  seated→standing). Also revealed real baked forward-stepping motion
  (a large depth/Y-axis component in the correction) — i.e. the
  original clip has the character genuinely walk forward as they stand
  up. Fully corrected out, consistent with this project's root-motion-
  never-consumed convention — the game's own code decides how far the
  character travels after standing (`Chair.get_stand_position()`), not
  the clip.
- `sitting.fbx`: no standing frame of its own (it's a pure held seated
  loop) — calibrated instead against `stand_to_sit.fbx`'s own
  (already-corrected) exported seated-frame foot position, so all three
  clips agree on the exact same seated pose for a seamless handoff.
  Confirmed: seated Hip Z across all three clips lands within ~0.0005 of
  each other (in the source file's native scale) after this pass.

**Verification method:** all three fixes were verified the same way —
sample a bone's world position via Blender's own evaluated depsgraph
(`arm_obj.evaluated_get(depsgraph)`, NOT the raw pose bone matrix, which
caches stale values across frame changes unless the depsgraph is
explicitly re-evaluated), compare against a known-good reference
(REST pose for the bone in question), confirm near-zero residual, THEN
export and independently re-import the exported file fresh to confirm
the fix actually survived the FBX export/reimport round-trip (it
didn't, twice, for reasons below) before considering a clip done.

**Non-obvious pitfalls hit along the way (all now avoided, listed for
next time this kind of fix is needed):**
- **Blender pose evaluation caches stale results after editing keyframe
  data directly via the F-Curve API**, even after calling `frame_set()`
  again on the SAME frame number (Blender treats it as a no-op and
  skips re-evaluation) — a `scene.frame_set(0)` "dummy" frame change
  before setting the real target frame forces a genuine re-evaluation.
  A HARD refresh (`arm_obj.animation_data.action = None` then
  reassigning the action) was needed after bulk keyframe edits
  specifically — confirmed the raw keyframe data WAS correctly edited
  in cases where the evaluated pose still read stale, isolating this as
  a pose-cache issue, not a data-write bug.
- **World axis ≠ intuitive index.** This rig's vertical axis is world
  Z, not Y (confirmed unambiguously via Head-bone-minus-Foot-bone
  position, which is large only in Z — the bounding-box "largest
  extent" test is NOT reliable for this because a T-pose's arm span is
  a similar magnitude to standing height, so X and Z both come out
  large). Pose-space bone `.location` axes are ALSO permuted relative
  to world axes for this specific rig (empirically verified via a
  perturb-one-axis-and-observe-world-effect Jacobian, not assumed):
  local X → world X (negated), local Y → world Z, local Z → world Y.
  Any correction computed in world space needs this Jacobian applied
  before writing it back to a bone's local `.location` curve, or the
  correction lands on the wrong axis entirely (produced a very visibly
  wrong result once, caught by comparing residual magnitude against the
  original error rather than assuming a small residual = success).
- **FBX export bakes the SCENE's frame_start/frame_end, not the
  action's own frame_range.** After a `bpy.ops.wm.read_homefile()`
  reset (used partway through to clear accumulating cross-file state
  confusion), the scene's frame range reverts to Blender's default
  (1-250) — if not explicitly re-synced to the imported action's real
  range before export, the exported clip silently gets the WRONG
  duration (produced exactly 1.15s for every clip regardless of its
  true length, since 250 frames at whatever stale fps happened to
  divide out that way). Always set `scene.frame_start`/`frame_end` from
  `action.frame_range` explicitly, immediately before every export —
  don't rely on import-time auto-sync surviving a reset.
- **The retarget `.import` config's `PATH:` key must match the ACTUAL
  node hierarchy of the file being imported, exactly.** Re-exporting
  from Blender added an extra `Armature` wrapper node the original
  handoff's `.import` files didn't expect (`PATH:Skeleton3D` — the
  skeleton at the scene root — vs. the re-exported file's real
  `PATH:Armature/Skeleton3D`). Godot doesn't error when this key
  doesn't match anything; it silently skips retargeting entirely,
  leaving raw `mixamorig_*` bone names and non-Humanoid track paths in
  the imported animation — which reads exactly like a "broken/no
  animation" bug (confirmed this was the direct cause of an earlier
  reported "freeze, no animation plays" symptom). If a clip is ever
  re-exported from Blender, re-verify the node hierarchy matches what
  the `.import` file's retarget block expects — don't assume it's
  unchanged.
- **Always delete the cached `.godot/imported/<file>-<hash>.scn` before
  reimporting after an `.import` config change** — plain reimport has
  been observed to not reliably re-read edited `.import` params.
- **When the editor is open, prefer `godot --headless --path <project>
  --import` / `--script <path>` via a direct subprocess call over
  driving the same actions through the editor's own MCP connection** —
  a separate headless process while the editor has the project open can
  hang indefinitely (project lock contention), and driving actions
  through the editor while a person is also actively using it races
  against whatever scene tab they currently have focused. The headless
  subprocess path avoids both classes of problem entirely, provided the
  editor is closed first.

**Positioning/timing (`AdventurerModelController.gd` +
`MainWorld.gd`'s `_wire_chair()`), now that the clip data itself is
correct:**

- Root anchor stays at **floor level for the entire sequence** — this
  now works correctly because the fix above means the clips' own baked
  Hip motion ALREADY shows the full, physically-correct standing↔seated
  height change relative to a fixed floor anchor (mirroring exactly how
  idle/walk/run already have zero baked Hips position data and rely
  entirely on a fixed anchor + the skeleton's own rest/posed geometry).
  No code-side Y adjustment is needed or applied anywhere in the
  sequence — two earlier attempts at a code-side Y correction (documented
  and then removed from this file's own git history) were band-aids for
  the wrong root cause and are no longer present.
- **Horizontal (X/Z) motion** eases between a FIXED approach point
  (`t.origin + t.basis.z * APPROACH_OFFSET`, ~half a chair width in
  front of the seat — NOT the player's actual position when E was
  pressed, which made the slide's distance/timing inconsistent) and the
  chair's seat center, via `_lerp_sit_xz()`. The interpolation follows
  `SIT_DOWN_CURVE`/`STAND_UP_CURVE` — 21-point lookup tables sampled
  directly from each clip's own baked Hip vertical-motion shape in
  Blender, NOT raw animation time — because the real motion is strongly
  non-linear (e.g. `stand_to_sit` stays essentially standing for the
  first ~10% of the clip, does almost the entire drop across the next
  ~55%, then holds for the remaining ~35%) and driving the horizontal
  slide by raw time put it badly out of sync with the vertical motion,
  reading as "hovering" rather than settling into the chair.
- Both `PlayerModel` and `PlayerModelShadow` are separate
  `AdventurerModelController` instances under the same player node,
  both independently reaching the sit-phase logic every frame (it only
  checks the shared `seated_chair`) — the XZ-lerp calls are explicitly
  guarded to `not is_shadow_only`, since without that guard the shadow
  instance's own (never externally set) anchor points fought the real
  instance over the same shared `player.global_position` every frame,
  snapping the player to world origin.
- The player's position/physics stay anchored at the chair (not
  released to `Chair.get_stand_position()`) until
  `AdventurerModelController.stand_animation_finished` actually fires
  — i.e. until the sit_to_stand clip genuinely completes, not the
  instant E is pressed to stand up.
- The chair remembers the player's exact seated-facing yaw
  (`the_chair.set_meta("_seated_facing_y", ...)`, set in
  `seat_requested`) and re-applies it once `stand_animation_finished`
  fires, protecting against anything (camera-look sync, etc.) nudging
  rotation while seated.

**Known gap:** all of the above is wired in `MainWorld.gd`'s
`_wire_chair()`, which only handles the PLAYER. NPCs sit via a separate
path (`scripts/npc/activities/SitActivity.gd`/`RelaxSitActivity.gd`)
that was not touched by this pass — if NPC sitting shows the same
fixed-approach-point or facing-restoration gaps the player had before
this fix, that file needs the analogous treatment.

### Seat-height correction (Aug 2026, 5th pass — the actual final fix)

Everything above this subsection made the sit animation *internally
consistent* (feet genuinely grounded during standing frames, a
physically-natural knee-bend when seated) — but internal consistency
and matching THIS SPECIFIC CHAIR's actual seat height are two different
problems, and fixing the first does not automatically fix the second.
After the feet-calibration fix above, the character still rendered
sitting well above the chair's actual seat surface — confirmed by
measuring the REAL, running Godot result directly (not a Blender-space
assumption): the seated Hips bone's actual world Y sat **0.3316m above
`Chair.SEAT_Y`** for the male body, **0.4398m above** for the female
(different skeleton proportions between the two Adventurer bodies).
Both numbers are large — confirming this was a real, substantial gap,
not a rounding-level issue.

**Why the earlier Blender-only verification missed this:** every check
in the "Sit animation root-offset fix" section above was done entirely
within Blender's own coordinate space — confirming the CLIP's internal
consistency (feet-to-rest residual near zero, etc.), never cross-checked
against the actual live Godot result. The clip's own natural
standing→seated hip drop is a property of the skeleton's own geometry
alone (knee-bend on a fixed floor anchor); it has zero awareness of any
particular chair's `SEAT_Y`. Those two numbers only happen to match if
you verify it — which hadn't been done until this pass.

**Measurement method:** a temporary headless diagnostic
(`tools/_ground_truth_sit_check.gd`, since deleted — reconstructable
from this description if ever needed again) loaded the real
`Adventurer_Male.fbx`/`Adventurer_Female.fbx` body directly (bypassing
`AdventurerModelController.gd`, since that script needs the
`CharacterCreationData` autoload, unavailable in bare `godot --headless
--script` execution), attached the actual `sit_lib.res` library, forced
the pose to the middle of the seated loop via `AnimationPlayer.seek()`
(synchronous, no real-time frame waiting needed — `await process_frame`
does not pump in bare `--script` mode, confirmed by a timeout on the
first attempt), then read the real `Skeleton3D.get_bone_global_pose()`
for `Hips` and compared directly against `Chair.SEAT_Y`.

**The fix:** `SEAT_HEIGHT_CORRECTION` (`AdventurerModelController.gd`),
a gender-keyed dictionary of the exact measured gaps above. Applied
inside `_lerp_sit_position()` (the same function driving the X/Z
approach↔seat slide) as a THIRD, curve-synced lerp on
`player.global_position.y` — eases in over `SIT_DOWN_CURVE` while
sitting down, eases back out over `STAND_UP_CURVE` while standing, using
the exact same per-clip motion-shape timing already established for the
horizontal slide (see the section above) rather than an instant snap.
The correction is relative to `_chair_approach_pos.y` (the floor height
captured at the moment the player pressed E, itself already correct
since the whole sequence's floor anchor never otherwise moves), so it
composes correctly regardless of the actual floor height the interaction
happened at.

**If this ever needs re-measuring** (chair `SEAT_Y` changes, a body's
rig changes, a third gender/body variant is added): reconstruct the
deleted diagnostic script from the method description above — the key
points are (1) bypass `AdventurerModelController.gd` and load the body +
`sit_lib.res` directly to avoid the autoload dependency, (2) use
`AnimationPlayer.seek()` not real-time waiting, (3) read
`Skeleton3D.get_bone_global_pose(skeleton.find_bone("Hips"))` for the
real world position, not a Blender-space measurement.

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
- [x] VISUAL: Peasant outfit renders on both genders, covers
      torso/arms/legs/feet (REWORKED Aug 2026 — base body now hidden
      entirely below the head/neck per the asset's own documented design,
      see "Peasant outfit clip fix" above; the previous per-garment
      geometry-matching approach is superseded). Deformation through
      idle/walk/run/carry is a non-issue now since the split no longer
      depends on live pose at all — confirmed by a real play-test
      (script-validate clean, no runtime errors, expected mesh count).
      Still wants one more direct visual look-over to confirm the
      seam at the neck/collar reads naturally.
- [ ] VISUAL: male exposed hand/forearm skin (`MI_Regular_Male` part of
      Arms) shows the skin texture, not a missing/default material
- [ ] VISUAL: outfit tracks scale/floor/facing like the body; no
      pokes/z-fighting vs. the body (REWORKED Aug 2026 — no longer a
      geometry-matching problem at all now that the base body is hidden
      below the head/neck outright, see "Peasant outfit clip fix" above;
      visual confirmation of the neck/collar seam still outstanding)
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

**Peasant outfit clip fix (Aug 2026, REWORKED — supersedes "option B"
below the checklist mention of it):** the previous approach (per-vertex
band/radius/poke-allowance heuristic trying to geometrically guess which
body triangles a garment covers) was solving a problem this asset was
never designed to have, and kept surfacing new gaps no matter how it was
tuned (collar, hip/waistband, then the hands). Root cause found by
reading the asset pack's own documentation instead of continuing to
guess from geometry: Quaternius's "Modular Character Outfits - Fantasy"
Readme.txt states plainly, "When using the clothing, only the head of
the model is required. Using the full body will result in clipping."
The outfit's modular pieces (Body/Legs/Feet/Arms) are meant to BE the
entire visible torso/limbs/hands on their own, not to align precisely
with the base body's silhouette — confirmed further by the pack's own
itch.io changelog (v2.0): the Arms piece deliberately bakes in its own
skin-toned arm/hand geometry ("included the human arms on Peasant_Male,
now all models work with just the head") specifically so the base
body's real arm/hand is never needed. The reported "double hands" during
testing was the real bare hand still rendering underneath the outfit's
own correctly-designed one — not a duplicate node, and not a bug in the
glove mesh's geometry (which legitimately contains two intentionally-
layered surfaces: a fabric cuff + a skin-toned insert).

The fix in `_setup_outfit()` is now a single synchronous function,
`_hide_body_below_head()`: every body vertex is hidden UNLESS its
dominant bone matches `HEAD_REGION_BONE_MARKERS` (`"head"`/`"neck"`
substrings). No per-garment geometry comparison, no band/radius/
poke-allowance tuning, no live-pose sampling across idle/walk/run/carry
states — since which bone a vertex is skinned to never changes with
animation, the split is pose-INDEPENDENT and runs once, right when the
outfit is attached, with no `await`. This replaced roughly 250 lines
across `OUTFIT_BAND_HEIGHT`, `OUTFIT_POKE_ALLOWANCE`,
`OUTFIT_BEHIND_ALLOWANCE`, `OUTFIT_CAP_Z_ALLOWANCE`, `OUTFIT_BONE_MARKERS`,
`OUTFIT_PIECE_TYPES`, `OUTFIT_BAND_DILATION`, `OUTFIT_POSE_SAMPLES`,
`OUTFIT_CARRY_STATES_TO_SAMPLE`, and the functions `_split_at_live_pose`,
`_outfit_piece_profile`, `_deformed_piece_positions`,
`_body_mesh_covered_flags` — all now deleted. `_rewrite_outfit_skin_binds()`
(bind-pose realignment, a separate concern about the OUTFIT rendering in
the right place, not about what body skin stays visible) is unchanged
and still runs first, same as before.

**Lesson for future asset integration on this project:** before building
any from-scratch geometric workaround for a clipping/fit problem with a
third-party asset pack, read that pack's own README/changelog first —
this one was sitting on disk (and echoed on the publisher's itch.io page)
the entire time this system was being built and re-tuned.

_Superseded section below, kept for history:_

The nude body mesh no longer stays fully rendered underneath the outfit. Diagnosis (headless,
geometry-level): the outfit is a TIGHT garment over the fully-rendered
nude body, so the body skin sits 1-5cm proud of (and sometimes
coincident with) the garment surface — the body pokes through and
z-fights with the clothes on BOTH genders. Separately, the male outfit
gltf was baked against a different rest pose than the male body (56/65
bones differ 2-3.4cm, confirmed by comparing the two gltf rest poses), so
at runtime the male outfit was also displaced 2-4cm outward. Two changes
in `_setup_outfit()` fix both:

1. **Bind-pose realignment (male):** every outfit piece's skin bind pose
   is rewritten to `skeleton.get_bone_global_rest(bone).affine_inverse()`
   (identity skinning) so the piece renders exactly at its authored
   coordinates on the body's rest pose while still following animations.
   The female gltf already ships `rest⁻¹`, so this is a verified no-op
   there; a fresh `Skin` is built so the shared imported resource is
   never mutated.
2. **Body-region split (both genders):** after realignment, each piece's
   per-height envelope (radial `[r_min, r_max]`, `z` extent per
   `OUTFIT_BAND_HEIGHT` band) is computed from the piece's own deformed
   vertices, and each body vertex is hidden when ALL of: its height band
   has garment geometry, its radius falls inside the piece's envelope
   plus a PER-PIECE-TYPE poke allowance (`OUTFIT_POKE_ALLOWANCE`:
   arms 5cm / body 6cm / legs 10cm / feet 12cm — sized to the measured
   ankle/thigh pokes, see the follow-up below), AND its dominant bone is
   in that piece's hide-set. The bone-region gate is what keeps genuinely
   bare skin safe: torso pieces may only hide `hips/spine/chest`-weighted
   vertices, legs pieces `hips/upperleg/lowerleg`, feet pieces
   `lowerleg/foot/toes/ball`, and the (flat outer-arm) Arms panels
   `shoulder/upperarm/lowerarm` (the hand/finger bones are deliberately
   EXCLUDED — in the idle pose the flat sleeve panel and the hanging hand
   share the same band/radius/z, so hiding hand-bone skin would eat the
   visible hand). Because the armpit/shoulder and hand are deliberately
   NOT in the torso/legs sets, a tight garment's enlarged envelope can
   never swallow them even though they sit right at the garment's edge.
   Covered triangles are then dropped from the body mesh (conservative: a
   triangle is dropped if any vertex is covered) — head, neck, inner arms,
   and hands stay visible; torso/legs/feet and outer-arm skin under the
   garment vanish.

   **Split runs at the LIVE pose, not rest:** the body always plays the
   idle loop (auto-started), and the idle pose holds the legs slightly
   apart — kept shin/ankle skin moves ~10cm outward vs. the T-pose rest,
   so a rest-pose split leaves idle-visible pokes. `_split_at_live_pose()`
   awaits `OUTFIT_POSE_SAMPLES = 8` frames of the playing idle loop,
   unions the per-frame covered-vertex flags, then splits once — the
   `get_bone_global_pose()` path (`use_live_pose = true`) is threaded
   through `_outfit_piece_profile()` and `_body_mesh_covered_flags()`.

   **Piece-type bug (the actual root cause of the persisting leg pokes):**
   `_outfit_piece_type()` originally used `mesh_name.get_slice("_", -1)`.
   Godot's `get_slice()` does not index from the end with -1, so every
   piece fell back to `"body"` — the legs/feet/arms hide-sets were never
   consulted and ALL leg/ankle skin pokes survived the split. Fixed with
   `mesh_name.substr(mesh_name.rfind("_") + 1)`. This is why the first
   verification pass looked "male slightly better, female just as bad":
   the torso-only split (all pieces typed "body") removed chest skin under
   the blouse but never touched the legs/feet.

   **Verified headlessly on a real Player.tscn boot for both genders:**
   after the split, body vertex counts drop to male 3936 / female 3770
   (from ~6600/6400), every bare region (head, neck, hands, inner arms,
   armpits, inner ankles) survives, and a full-animation poke probe
   (idle/walk/run, 6 poses each, correct all-garment coverage check)
   reports **0 real pokes for both genders**. The only remaining
   "3.6cm" reading from the naive per-band radius comparison is the
   hanging hand beside the thigh (finger bones) — the hand itself, not a
   garment poke.

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
