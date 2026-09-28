# Weapons foundation

One Webley Mk II revolver plus knife, hatchet, and steel pipe. Open
`tools/tests/WeaponsTest.tscn` and run the current scene (F6) for a standalone room
using the real player, interaction, inventory, and game camera. Weapons lie on the
floor in front of the player. They are not automatically spawned into existing saves
or added to the shop; place `scenes/weapons/*.tscn` wherever desired in authored areas.

## Controls

- F / gamepad X picks up or drops using the existing interaction rules.
- Hold RMB to aim toward the cursor at weapon height; LMB press attacks.
- Right stick aims relative to the camera; right trigger press attacks.
- E / gamepad A reloads the revolver via the existing held-item use action.
- G stores and mouse wheel selects inventory slots as usual.

Six rounds, twelve spare rounds initially. Semi-automatic: each press commits at most
one attack. Empty fire never spends ammunition or emits flash/cases. Reload transfers
only available reserve after 1.25 seconds; switching, dropping, or a UI/job/seat/build
lock cancels it without creating ammunition. Ammo and reserve persist through the
existing ItemSaveData contract. Melee costs no ammunition. A strike lands after 100ms,
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
Set `grip_anchor` to a future hand BoneAttachment3D/Marker3D to replace the generic
hold point; no input rewrite is required. Current player carry animation is retained.
Optional attack/empty/reload AudioStream exports are ready for authored sound assets;
this pass does not include final weapon audio or mechanical cylinder/reload animation.

## Feel and feedback

24/s exponential aim smoothing, 0.32s revolver recovery, 0.34/0.65/0.48s knife/hatchet/
pipe recovery. Brief 45ms warm OmniLight3D muzzle flash, 0.13 camera trauma through
GameCamera (quadratic scale: very small shake), visual recoil, reticle ammo count,
confirmed-receiver hit tick. `recoil_strength = 0` disables weapon camera shake.
Casings last four seconds, capped at sixteen. They never join pickup/save groups.
Per the requested effect, a case is dispensed on each shot; this is stylized behavior
for a Webley, whose real cases remain in its cylinder until extraction.

## Artwork status

Webley is the supplied textured model, normalized to 31cm and exported as GLB; source
provenance/conversion is in `assets/models/weapons/webley/README.md`. The original rig
and mechanical animation source are preserved in the user's model folder.
Temporary agent-authored graybox visuals (not final artwork): knife, hatchet, pipe,
procedural casing, impact dot, and test-room targets. Replace with authored meshes/
effects before release. Custom player holding/attack animations and sound are pending.

## Validation

Run with isolated user data (see `docs/AGENT_GIT_WORKFLOW.md`):

```
XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) /path/to/godot --headless --path . res://tools/tests/WeaponsTest.tscn --quit-after 120
```

The rightmost room target is behind a wall. Check shots and melee against the exposed
targets, then attempt hits through that wall; check reload cancellation, empty fire,
switching and dropping, and free movement while aiming. The room never loads a save.
