# Pistol locomotion sources

Human-authored source FBXs extracted verbatim from the user-supplied
`Pistol_Handgun Locomotion Pack_MALE.zip` and `_FEMALE.zip` in
`/mnt/storage/Bunker Game/models/player models/FINAL/`.

Seven clips per body: idle, walk/run forward, walk/run backward, and both strafes.
Original `pistol strafe.fbx` travels along source +X, which becomes runtime -X after
the Adventurer body's existing 180-degree turn: it is named `strafe_left.fbx`.
`pistol strafe (2).fbx` is `strafe_right.fbx`. Unused jump, kneel, and arc clips remain
in the original archives; no source animation is modified or procedurally authored.

Import uses the existing Maximo Humanoid rest-fix pipeline. Female finger numbering
starts at 1 instead of male 2; `bone_map_pistol_female.tres` maps those finger joints
explicitly. The extra unweighted/end thumb tips have no runtime-body counterpart.
The female FBXs carry identity rotations on the leaf bones (Head, Foot, distal
fingers): an export artifact of a rig without *_end bones. They are baked as-is (no
splicing, per the provenance rule in ANIMATIONS.md); corrections are runtime-only.

Run `tools/anim_pipeline/bake_pistol_anims.gd` using the same isolated-data command
as the canonical Adventurer bake. It reuses that tool's conversion and measurement
methods and writes only `pistol_male_lib.res` and `pistol_female_lib.res` here.
Both Hips and armature constant horizontal travel are removed for in-place playback;
authored vertical bob, sway, rotations, and finger poses are preserved. Measured
stride length and left-foot contact phase drive playback at runtime in every direction.
`grip_basis` is measured from the idle right-hand transform and only used as a runtime
attachment calibration; it is not an animation key.

The player's shared Adventurer controller adds `PistolAnimationLayer`, blending the
pistol layer before the existing furniture/death override. Unarmed and melee keep
the existing animation tree behavior; NPC trees are not expanded. The gun follows
the final right-hand skeleton pose after procedural foot/lean updates.
