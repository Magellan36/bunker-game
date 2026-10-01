# Weapons foundation

One Webley Mk II revolver plus knife, hatchet, steel pipe, baseball bat and crowbar.
Who owns what and the API contract: `HANDOFF.md` in this folder. Open
`tools/tests/WeaponsTest.tscn` and run the current scene (F6) for a standalone room
using the real player, interaction, inventory, and game camera. Weapons lie on the
floor in front of the player. All six are sold in the Supply shop (Weapons department, placeholder $10 each).
They are not spawned into existing saves.

## Controls

- F / gamepad X picks up or drops using the existing interaction rules.
- Hold RMB to aim toward the cursor at weapon height; LMB press attacks. With empty
  hands the same input raises the fists and throws a jab/cross combo (`Fists.gd`).
- Right stick aims relative to the camera; right trigger press attacks.
- R (keyboard) / gamepad A reloads the revolver. On keyboard, E no longer reloads.
- G stores and mouse wheel selects inventory slots as usual.

Six rounds, twelve spare rounds initially. Semi-automatic: each press commits at most
one attack. With the revolver empty, each attack is a pistol whip (14 damage, 1.3 m reach),
with no ammunition, flash or case. Reload transfers
only available reserve after 1.25 seconds; switching, dropping, or a UI/job/seat/build
lock cancels it without creating ammunition. Ammo and reserve persist through the
existing ItemSaveData contract. Melee costs no ammunition. About 30% of melee attacks (never two in a row) are
flagged as the alternate swing (`attack_started(kind, 1)`) so animation can vary. A strike lands after 100ms,
checks reach/cone and line of sight, and damages each collider at most once per swing.

## Boundaries

`InteractionSystem` creates `WeaponController` and exposes `can_use_weapon()` as the
single UI/job/build/player-lock gate. No new autoloads or project input-map changes.
The controller runs after normal player movement and applies one smoothed aim yaw
from its own previous yaw, then weapon pose runs after that. Camera-relative movement
is preserved. Mouse aiming intersects a horizontal plane, avoiding floor/wall-height
jumps. WeaponItem extends PickupableItem and inherits pickup/drop/store/save behavior.
Held weapons use a stable frozen pose, not spring-follow physics. Gun raycasts first
check holder-to-muzzle obstruction, then muzzle-to-range; walls stop shots.

Damage receivers opt in with `receive_weapon_hit(context: Dictionary)` (damage,
position, direction, kind, source, collider). `hit_resolved` also broadcasts the hit.
This does **not** silently connect to NPC health/medical/social systems: those need
an agreed damage contract. Test targets already implement the receiver and count hits.

`attack_started`, `aim_changed`, and `dry_fired` are animation/audio integration hooks.
`grip_anchor` replaces the generic hold point. While the player holds the Webley,
`PistolAnimationLayer` (see "Animation" below) sets it to a marker on the animated
right hand. Melee weapons keep the generic hold point and the normal carry pose.
Optional attack/empty/reload AudioStream exports are ready for authored sound assets;
this pass does not include final weapon audio or mechanical cylinder/reload animation.

## Feel and feedback

Polish pass (2026-09-28):
- 0.18 s attack input buffer: a press during recovery fires the moment the weapon is
  ready, so combos never eat inputs.
- Gamepad aim assist (mouse is never assisted): a stick direction within 10°
  (firearm, 12 m) or 32° (melee/fists, reach + 0.6 m) of a hittable target with a
  clear line snaps to it.
- No hit-stop or melee screen shake: combat is a rare emergency in a colony sim,
  so feedback stays quiet (a reticle tick on a confirmed hit).
- Hits push loose RigidBody props (impulse ≈ damage × 0.08, clamped 0.3–3).
- The hover prompt shows only status: `[R] Reload  3 / 12`, `Reloading…`, rounds, or
  `Empty`. The reticle has no text; it turns amber when the revolver is dry.
- Mouse aim steers a direction, like the stick: raw mouse motion moves a point on a
  ring around the player (13% of screen height), and the reticle sits at the same
  tight ring position for mouse and pad (2.5 m from the weapon, or melee reach if
  shorter, kept on screen). You can't aim across the screen.
- Mouse aim follows the physical RMB: a brief block (UI blip, item swap) only pauses
  aiming, and it resumes while the button is still held.
- Only the player's own shots give full recoil shake; others' shots nearby give a
  faint distance-faded jolt.

24/s exponential aim smoothing, 0.32s revolver recovery, 0.34/0.65/0.48s knife/hatchet/
pipe recovery. Brief 45ms warm room-filling OmniLight3D muzzle flash (14 m range, cube shadows), 0.13 camera trauma through
GameCamera (quadratic scale: very small shake), visual recoil, reticle ammo count,
confirmed-receiver hit tick. `recoil_strength = 0` disables weapon camera shake.
Casings last four seconds, capped at sixteen. They never join pickup/save groups.
Per the requested effect, a case is dispensed on each shot; this is stylized behavior
for a Webley, whose real cases remain in its cylinder until extraction.

## Artwork status

Webley is the supplied textured model, normalized to 31cm and exported as GLB; source
provenance/conversion is in `assets/models/weapons/webley/README.md`. The original rig
and mechanical animation source are preserved in the user's model folder.
Bat (user-supplied OBJ + wood texture) and crowbar (Clint Bellanger, CC0) are authored
models; see their READMEs under `assets/models/weapons/`.
Temporary agent-authored graybox visuals (not final artwork): knife, hatchet, pipe,
procedural casing, impact dot, and test-room targets. Replace with authored meshes/
effects before release. Attack/reload animations, melee holding poses and sound are pending.

## Animation

Holding the Webley blends the player (both bodies) into the supplied human-made
Maximo pistol locomotion pack: a two-handed idle, walk/run forward and backward, and
both strafes, chosen by travel direction relative to facing so aiming while moving
sideways or backwards uses the matching clip. Feet are phase-locked to distance
travelled, as with the normal gait. The gun rides the final right-hand pose each
frame. Dropping, storing or switching to melee eases back to the normal tree in
~0.12 s. NPCs are untouched. Details: `docs/systems/player-model/ANIMATIONS.md`
("Pistol layer") and `assets/models/player/pistol/README.md`.

## Validation

Run with isolated user data (see `docs/AGENT_GIT_WORKFLOW.md`):

```
XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) /path/to/godot --headless --path . res://tools/tests/WeaponsTest.tscn --quit-after 120
```

Headless behavior checks (expects `WEAPONS_SMOKE: 48 checks, 0 failures`):

```
XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) /path/to/godot --headless --path . res://tools/tests/WeaponsSmoke.tscn
```

The rightmost room target is behind a wall. Check shots and melee against the exposed
targets, then attempt hits through that wall; check reload cancellation, empty fire,
switching and dropping, and free movement while aiming. The room never loads a save.
