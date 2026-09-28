# Adventurer Animation System (CURRENT, rebuilt 2026-09-27)

**Read this before touching `scripts/player/AdventurerModelController.gd`,
`scripts/player/AdventurerProceduralPose.gd`, `scenes/player/AdventurerModel.tscn`,
`assets/models/player/anims/`, or `tools/anim_pipeline/`.**

This covers every animated body in the game: the player and all NPCs, both
genders (Quaternius "Adventurer" bodies, see `README.md` in this folder for the
body/model side).

## Provenance rule (Steam AI disclosure)

The shipped game must contain **no AI-generated animation**. Therefore:

- Every keyframe that plays comes from a **human-made source clip**
  (Mixamo / Maximo mocap FBX files under `assets/models/player/`).
- The bake tool only **re-expresses** those keys (rebase bone paths, change of
  basis for root motion, remove constant forward travel to make a loop "in
  place", the same thing Mixamo's own In-Place export does). It never creates,
  splices, edits or offsets poses.
- Everything that adapts motion to the game happens at **runtime in code**:
  playback rate, blending, alignment to furniture (motion warping), foot IK,
  lean, pillow head support. Code is not an asset.
- Do not add "hybrid" or hand-tweaked baked clips again. The Aug 2026
  `sit_hybrid` / `sleep_hybrid` libs (spliced by earlier agents with a baked
  20° head pitch) were deleted for this reason. If a clip needs adjusting, do it
  as a runtime modifier.

## Pipeline: source FBX → library

```
assets/models/player/<clip>.fbx  (+ .import with the retarget block)
        │  godot --headless --import   (retarget to Humanoid "GeneralSkeleton")
        ▼
tools/anim_pipeline/bake_adventurer_anims.gd
        ▼
assets/models/player/anims/adventurer_male_lib.res
assets/models/player/anims/adventurer_female_lib.res
```

Run the bake after changing any source clip or the manifest:

```bash
export XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d)
godot --headless --path . --script res://tools/anim_pipeline/bake_adventurer_anims.gd
```

The tool's `CLIPS` manifest (plus `GENDER_OVERRIDES`) is the single list of
what each body plays:

| Key | Source (male / female) | Kind |
|---|---|---|
| `idle` | `male_locomotion/idle.fbx` / `female_locomotion/idle.fbx` | loop |
| `walk`, `run` | `walk.fbx`, `run.fbx` (Mixamo, shared) | gait |
| `idle_carry` | `idle_carry.fbx` (arms only, see Carrying) | loop |
| `stand_to_sit`, `sit_to_stand` | `stand_to_sit_female.fbx`, `sit_to_stand_female.fbx` (Maximo, shared) | action |
| `sit` | `sitting.fbx` (shared) | loop |
| `lie_down` | `lying_down_male.fbx` / `lying_down_female.fbx` | action |
| `sleep` | `sleeping_male.fbx` / `sleeping_female.fbx` | loop |
| `dying` | `dying_male.fbx` / `dying_female.fbx` | action |
| `lean` | `leaning_male.fbx` / `leaning_female.fbx` (NPC-only wall lean) | lean |

What the bake does per clip:

1. Copies bone tracks verbatim, path → `MaleModel/%GeneralSkeleton:<bone>`
   (`MaleModel` is the runtime body root name, load-bearing). Maximo finger
   knuckles are renamed to Humanoid names; tracks for bones a body lacks are
   dropped (listed in the tool's output).
2. **Maximo root motion** lives on the FBX armature node, not the Hips. The
   importer's rest fixer bakes the armature's rest (`Rx(-90°)·Scale(100)`)
   into the skeleton but leaves the armature's own tracks relative to it, so
   the bake re-expresses them as `A(t) · A_rest⁻¹` on
   `MaleModel/CharacterArmature` (verified: the in-place idle comes out ≈
   identity). The old pipeline stripped these tracks, which threw away the
   whole-body motion of sit/lie/die and had to be faked with pivots.
3. **Gaits** (`walk`, `run`) get their constant horizontal hip travel removed
   (bob and sway kept).
4. **Analysis metadata** on each Animation, measured on the real runtime body
   (`Animation.get_meta(...)`): `hips`, `hips_forward`, `head`, `feet`,
   `feet_low` (61 samples over the clip, in body space), plus
   `stride_length` and `phase_offset` for gaits. These are measurements the
   controller reads, not keys.

Measured on the male body (world units = ×1.25 model scale): walk stride
1.88 m per 1.03 s cycle = 1.83 m/s native; run 3.63 m per 0.70 s = 5.19 m/s.

## Runtime: `AdventurerModelController`

Node layout (built in `_ready`; the scene file is just the script):

```
AdventurerModel (controller, child of Player/NPC, scale 1.25, y = -capsule/2)
├── Visual            ← its GLOBAL transform is set every frame
│   └── MaleModel     (body FBX, rotated π; GeneralSkeleton inside)
│       └── …/GeneralSkeleton/ProceduralPose  (AdventurerProceduralPose)
└── AnimationTree     (library "body", deterministic, advanced manually)
```

The tree:

```
idle ─────────────────────────┐
walk → walk_seek ─┐           ├─ loco (Blend2: move_w) ─┐
run  → run_seek  ─┴─ gait (run_w)                        ├─ carry (Blend2, arm-bone filter: carry_w) ─┐
idle_carry ──────────────────────────────────────────────┘                                          ├─ out (act_w) → output
act_a → act_a_seek ─┐                                                                                 │
act_b → act_b_seek ─┴─ act (Blend2: ab_w) ──────────────────────────────────────────────────────────┘
```

`deterministic = true` means a track a clip doesn't key blends toward rest, so
no pose ever leaks from a previous clip. (The Maximo idle has no Hips track;
the old AnimationPlayer let it inherit the last clip's hip tilt, which was the
"leaning after standing up" bug.)

### Locomotion (no foot sliding)

- One gait **phase** (0..1) is shared by walk and run. It advances by
  `leg_speed × dt / stride`, where stride is the walk/run stride blended by
  `run_w`, and `leg_speed = real ground speed + |yaw rate| × 0.18 m` (turning
  on the spot takes steps).
- `run_w` comes from where the real speed sits between the walk and run
  native speeds. At the player's 4 m/s "walk" that's a ~64 % run blend: a jog.
  The old controller played the walk clip at 1× at 4 m/s, so the planted foot
  slid at 54 % of body speed. It now slides ~3 % (with foot locking).
- Real speed is `get_real_velocity()`, so a blocked character never
  ghost-walks.

### Carrying

`carry` overlays `idle_carry`'s arm bones only (Blend2 filter built from the
skeleton's Shoulder/Arm/Hand/finger bones) on top of whatever the legs do.
`walk_carry`/`run_carry` exist as sources but hold two gait cycles per loop,
so they can't share the gait phase.

### Actions and furniture (motion warping)

Furniture use starts when the parent sets `seated_chair` or `sleeping_bed`
and ends when it clears it. The controller reads the chair/bed itself
(`get_seat_transform()`, bed transform + `SHEETS_SURFACE_Y`) and builds a
`FurniturePlan`. Callers do not pass anchors any more.

Stages: `APPROACH → PIVOT → SIT_DOWN → SEATED` (chair) or
`… → SIT_DOWN → LIE_DOWN → SLEEP` (bed); releasing the furniture runs
`GET_UP` (bed: the lie-down played backwards on the same path) and `STAND_UP`.

- **Approach/pivot.** The plan computes where `stand_to_sit` must *start* for
  its own hip travel to land the hips on the seat. The body walks there (feet
  synced) and turns on the spot, so the sit clip plays almost unwarped.
- **Warping.** Each action slot holds a start placement `base` plus end
  corrections `dp` (translation) and `dpsi` (yaw):
  `W(t) = T(dp·s(t)) · RotateAbout(hips(t), dpsi·y(t)) · base`.
  `s(t)` is the clip's normalised hip path length (so corrections only happen
  while the body is really moving). `y(t)` is the same, except for the
  lie-down where it's the normalised **rise of the feet**.
- **The lie-down clip lies straight back** (the actor straddles a bench). On a
  bed the body sits on the side edge facing out, so it needs a ≈90° turn. That
  turn is applied about the hips only while the legs are lifting, which reads
  as swinging the legs up onto the bed. Where along the edge to sit is solved
  so the clip's own backward travel lands the head on the pillow.
- **Slots and cross-fades.** Two slots (A/B) cross-fade with `ab_w`, and the
  action layer fades against locomotion with `act_w`. The final `Visual`
  placement blends the slots' world placements with the same weights as the
  poses, so a cross-fade never slides the body.
- **Sleep loop** is aligned to the lie-down's end hips and feet→head axis.
- **Hand-off.** When the stand-up finishes, the controller moves the capsule
  (player or NPC) to where the feet ended and sets its yaw, then emits
  `stand_animation_finished`. `get_stand_end_position()` is valid from the
  moment the plan exists; `NPC._physics_process` places the NPC there.
- **Interruptions.** Released mid-approach → stops. Released mid sit-down →
  finishes sitting, then stands. Released mid lie-down → plays the lie-down
  backwards from the current frame (e.g. sleep ends because the need is
  already full).

### Wall lean (NPC-only, added 2026-09-28)

Human-made Maximo loop (`Leaning_Male/Female.fbx` from the FINAL folder):
back against the wall, one sole flat on it, head down. There are no
enter/exit clips; the controller blends in over 0.75 s and out over 0.6 s.

The bake measures the pose's **wall plane**, `wall_back` meta = rear-most
point of the *skinned* body (CPU linear-blend skinning over the visible
meshes). The male body's is his back (the hidden backpack piece is
excluded); the female body's backpack is part of her mesh, so she leans on
it. The controller puts that plane exactly on the wall.

**API for NPC code** (on `CharacterModel`, an `AdventurerModelController`):

```gdscript
model.begin_lean(wall_point: Vector3, wall_normal: Vector3) -> bool
model.end_lean()
model.is_leaning() -> bool   # true once settled in the loop
```

- `wall_point`: any point on the wall surface (e.g. a raycast hit). Its
  floor projection is where the back rests.
- `wall_normal`: the outward normal (into the room).
- The body walks there, turns its back to the wall and settles into the lean.
  Returns `false` if busy (furniture, dying, another sequence).
- The capsule is placed at the hips' floor point but never closer to the
  wall than its radius + 2 cm, so leaving never gets pushed by physics.
- While leaning, `is_sit_sequence_active()` is true, so NPC physics stays
  frozen (`NPC.in_sit_sequence()`). When it ends, `stand_animation_finished`
  is emitted and `get_stand_end_position()` is the capsule's spot.
- Loop start times are randomised so neighbours don't breathe in sync, and
  the head look-at still works while leaning.
- Needs ~0.5 m of clear floor in front of the wall (the raised knee pokes
  forward). Pick a flat wall stretch: the pose assumes a vertical wall from
  floor to shoulder height.

### Procedural pose (`AdventurerProceduralPose`, a SkeletonModifier3D)

- **Foot locking.** A foot whose ankle is within 7.5 cm of the floor and
  moving under 2.2 m/s in world space is pinned horizontally where it landed
  (height and heel-toe roll follow the clip; heading is kept). An analytic
  two-bone IK holds it, and it releases when the clip lifts the foot. Standing
  still with a foot pinned more than 12 cm from the idle stance triggers a
  small lifted **recovery step**. Off on the bed and while dying.
- **Look-at.** Neck and head (40/60 split) turn toward what the character is
  about to use: the player's interaction-prompt focus
  (`InteractionSystem.look_focus`), or an NPC activity's
  `attention_target(npc)`. Clamped to ~60° at 0.7 weight, only within 3.5 m
  and ~110° of facing, eased in/out, and only while free or seated.
- **Lean.** Spine banks into turns (`yaw rate × speed`) and tips with
  acceleration. Subtle: max ~7° / ~5°.
- **Pillow head support.** Neck + head nod up 9° + 9° while asleep (the sleep
  clip was performed flat).

## Adding or replacing a clip

1. Put the FBX under `assets/models/player/`, and give its `.import` the
   retarget block with the right bone map (`bone_map_mixamo.tres` for
   `mixamorig_*` rigs, `bone_map_maximo.tres` for Maximo `Abdomen`/`Torso`
   rigs). The `PATH:` key must match the skeleton node path in the FBX
   (`PATH:Skeleton3D`, `PATH:Armature/Skeleton3D`,
   `PATH:CharacterArmature/Skeleton3D`); a wrong key silently skips the
   retarget.
2. Delete the stale `.godot/imported/<name>-<md5>.scn` and run
   `godot --headless --import`.
3. Add a row to `CLIPS` (or `GENDER_OVERRIDES`) with its kind, then run the
   bake. Check the printed hips/feet summary: a standing clip's `feet_low`
   should be ≈0.02.
4. Use it from the controller: loops/one-shots go through `_push_slot()` with
   a placement; new locomotion-style clips need phase metadata like
   walk/run.
5. Verify in the real game (see "Seeing it" below), never just headless.

## Tuning knobs (top of the controller / modifier)

`SEAT_HIPS_CLEARANCE`, `SEAT_HIPS_BACK`, `LIE_HIPS_CLEARANCE`,
`BED_EDGE_HIPS_Z`, `BED_HEAD_X`, `APPROACH_SPEED`, `PIVOT_RATE`, the `*_RATE`
playback speeds and `XF_*` cross-fade times; in the modifier the `LOCK_*`,
`SETTLE_*`, lean and head-support constants.

## Seeing it (visual verification)

Headless numbers aren't enough; look at it. The pattern used for this
rebuild: a `SceneTree --script` (kept outside the repo) that changes scene to
`MainWorld.tscn`, waits for `startup_ready`, adds lights (the bunker is unlit
at game start), spawns a Bed/Chair with `main._wire_bed/_wire_chair`, triggers
`on_interact()`, drives the `GameCamera` (with `near` clipping walls), and
saves `root.get_texture()` every N frames with `--fixed-fps 60`. Open floor is
around x −13…3, z 4…12, floor y ≈ 0.5. Always isolate user data (see
`docs/AGENT_GIT_WORKFLOW.md`).

## Known limits / next steps

- Only one idle per gender; no idle variations or start/stop clips. Adding
  human-made "walk start", "walk stop" or turn-in-place clips would slot into
  the action layer.
- The lie-down source was performed on a higher bench, so during the first
  second on a low bed the dangling feet can dip ~5 cm into the floor.
- `stand_to_sit.fbx` / `sit_to_stand.fbx` (the male Mixamo pair) are no longer
  used. They were re-exported in Blender by an earlier agent with shifted hip
  data; consider removing them from the project.
