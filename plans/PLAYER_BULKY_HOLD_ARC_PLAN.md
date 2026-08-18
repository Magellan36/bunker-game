# Plan: Bulky Held-Item Head-Clearance Arc (Aug 2026)

**Owner:** Player subsystem (this plan) — one flagged file outside the
usual three (see note below).
**File touched:** `scripts/world/items/PickupableItem.gd` (the shared
hold-follow base class every carriable item extends — Crate/CanCase/
WaterCase included).
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

**Scope note:** `PickupableItem.gd` lives under `scripts/world/items/`,
which is normally Furniture/Objects-thread territory, not one of my
three core files. But the bug you're describing is entirely about the
hold-follow *mechanic* (the physics chase driven by `InteractionSystem`'s
`hold_point`), so I'm treating this the same way I did
`InventoryManager.clear_slot()` and `InteractPrompt.gd`'s type fix
earlier this session — investigated and fixed directly since it's a
small, contained, mechanically-scoped change, flagged clearly for
visibility rather than bounced to another thread.

---

## Your read on this is correct — here's what I found confirming it

Your diagnosis is exactly right, and I traced it to the precise physics
mechanism so the fix can be scoped tightly rather than guessed at.

**How the hold-follow actually works:** every carriable item is a real
`RigidBody3D` (not visually faked). While held, `PickupableItem.
_physics_process()` runs a simple proportional chase every physics tick:

```gdscript
var target: Vector3 = _hold_point.global_position
...
linear_velocity = (target - global_position) * speed
```

`hold_point` is a child of `InteractionSystem`, which sits at the
player's own origin — so when the player's yaw changes, `hold_point`'s
position updates **instantly** (no lag; it's a plain transform child).
The physics body then has to physically travel from wherever it
currently is to that new target, still going through full collision
detection the entire way (`collision_mask = 1` while held — confirmed in
`pickup()`).

**The actual collision:** the player's own `CollisionShape3D`
(`CapsuleShape3D`, default Godot sizing — radius 0.5, height 2.0,
centered on the player's origin) is on collision layer 1 — the same
layer every held item's `collision_mask` checks against. During a fast
180°, the straight-line path from "in front of the player" to "behind
the player" passes directly through that capsule. For a small item, the
brief overlap is either negligible or resolved by the physics engine in
a single frame with no visible artifact. For a large one, the RigidBody
genuinely collides with the player's own body and gets physically
blocked/wedged — which is exactly "stuck on their head," since the
capsule's rounded top is where a blocked object sliding along its
surface tends to end up.

**Why Crate/CanCase/WaterCase specifically, and not Basket/CookingPot
(which are also "heavy" by mass):** I checked. Mass isn't the right
signal — Basket (mass 7) and Cooking Pot (mass 9) are heavier than
CanCase/WaterCase (mass 5) by that metric, yet you didn't report them as
affected. The actual differentiator is **collision-shape footprint**,
which I computed directly from each item's real collision geometry:

| Item | Collision shape | Horizontal bounding radius |
|---|---|---|
| Basket | Cylinder, r=0.28 | ~0.28 m |
| Cooking Pot | Cylinder, r=0.28 | ~0.28 m |
| Can Case | Box 0.54×0.19×0.42 | ~0.34 m |
| Water Case | Box 0.54×0.19×0.42 | ~0.34 m |
| Crate | Box 0.179×0.159×0.245, ×3.0 scale | ~0.46 m |

There's a clean gap between ~0.28 (fine) and ~0.34+ (the three you
named) — that's the actual gating signal, not mass. This matters because
it means the fix should be **geometry-driven, not a hardcoded item
list** — any future bulky item (a footlocker, a large generator you can
carry, whatever comes later) gets the fix automatically without anyone
remembering to add it to a list, and nothing that already feels correct
today (Basket, Cooking Pot, every small item) is at any risk of changing
behavior.

---

## The fix

Matches your description almost exactly: while a bulky item's actual
position and its target position are on meaningfully different sides of
the player (large angular gap), temporarily raise the **chase target's**
height — never the true hold point used for the knockout-distance check,
just the point this item is currently steering toward — so the physics
body's own velocity naturally carries it up and over instead of through.
As the item catches up and the angular gap closes, the boost fades back
to zero on its own — no separate "settle" step needed, no state machine,
just one continuous formula, so it self-corrects however fast or slow
the actual turn ends up being.

**Deliberately geometric, not "detect a fast turn":** the boost amount
is driven purely by the angle between (a) the item's current bearing
from the player and (b) the target's bearing from the player — not by
tracking rotation speed over time. This is more robust (works
identically for a snappy mouse-flick 180 or a slower deliberate one,
and for any angle, not just exactly 180°) and needs no extra frame-to-
frame state.

### Change 1 — new tuning constants

**Anchor:** verified current lines 27–29 (top Config block).

```gdscript
old_str:
@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

new_str:
@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

## Bulky-carry head-clearance arc (Aug 2026) — see _carry_arc_height_boost()
## doc comment for the full mechanism. Items whose real collision-shape
## footprint (_carry_bulk_radius, computed lazily on first pickup — see
## pickup() below) is at or above this radius get an upward chase-target
## boost during a large-angle carry transition, so their RigidBody doesn't
## physically collide with the player's own CapsuleShape3D (layer 1, same
## layer every held item's collision_mask checks) while sweeping from one
## side of the player to the other. Empirically: Basket/Cooking Pot sit at
## ~0.28 (unaffected today, stay unaffected), Can Case/Water Case at ~0.34,
## Crate at ~0.46 (all three affected today) — 0.30 cleanly separates them
## by actual geometry rather than a hardcoded item list, so any future
## bulky item gets this automatically.
const BULKY_CARRY_RADIUS_THRESHOLD: float = 0.30
## Angular gap (item's current bearing from player vs. its target's
## bearing) past which the boost starts ramping in. Below this, no boost —
## an ordinary deliberate turn where the item is already tracking its
## target closely never triggers this at all.
const CARRY_ARC_START_ANGLE_DEG: float = 60.0
## Max upward boost (meters) applied to the CHASE target at a full 180°
## angular gap, ramping linearly from 0 at CARRY_ARC_START_ANGLE_DEG.
## hold_point sits at hold_height (0.8, see InteractionSystem.gd) with the
## player capsule's top at ~1.0 above origin — 0.6 comfortably clears it.
## Tune in-editor if it doesn't look right at your actual camera angle.
const CARRY_ARC_MAX_HEIGHT: float = 0.6
```

### Change 2 — new state var (lazy-computed bulk radius)

**Anchor:** verified current line 34 (existing state block).

```gdscript
old_str:
var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _grace_timer: float       = 0.0
var _out_of_range_time: float = 0.0

new_str:
var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _grace_timer: float       = 0.0
var _out_of_range_time: float = 0.0

## Real collision-shape footprint, computed lazily on first pickup() (see
## below) rather than in _ready() — Basket/CookingPot build their
## CollisionShape3D procedurally AFTER their own _ready() calls super()
## first, so computing this in the base _ready() would run too early and
## silently fall back to OBSTACLE_MIN_RADIUS (0.3) for them — dangerously
## close to BULKY_CARRY_RADIUS_THRESHOLD itself, which would have wrongly
## classified both as "bulky." By first pickup(), every item's shape
## (procedural or authored) is guaranteed to already exist. -1.0 = not yet
## computed; _physics_process() only reads this while is_held is true, so
## the sentinel is never actually consulted before pickup() sets it.
var _carry_bulk_radius: float = -1.0
```

### Change 3 — compute it lazily in `pickup()`

**Anchor:** verified current lines 128–143.

```gdscript
old_str:
func pickup(hold_point: Node3D) -> void:
	is_held            = true
	_hold_point        = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze             = false
	freeze_mode        = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale      = 0.0
	collision_layer    = 2
	collision_mask     = 1
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = false   ## don't drag a moving
		                                          ## "wall" around while carried
	_set_held_culling(true)
	_on_pickup_extra()
	picked_up.emit()

new_str:
func pickup(hold_point: Node3D) -> void:
	is_held            = true
	_hold_point        = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze             = false
	freeze_mode        = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale      = 0.0
	collision_layer    = 2
	collision_mask     = 1
	if _carry_bulk_radius < 0.0:
		## First pickup ever — safe to measure now, see _carry_bulk_radius's
		## own doc comment for why this can't happen in _ready() instead.
		_carry_bulk_radius = _compute_obstacle_radius()
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = false   ## don't drag a moving
		                                          ## "wall" around while carried
	_set_held_culling(true)
	_on_pickup_extra()
	picked_up.emit()
```

### Change 4 — apply the boost in `_physics_process()`, and the helper
   that computes it

**Anchor:** verified current lines 92–115 (the whole function).

```gdscript
old_str:
# ─── Physics: follow hold point + knockout check ─────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_out_of_range_time = 0.0
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

new_str:
# ─── Physics: follow hold point + knockout check ─────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_out_of_range_time = 0.0
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	## Bulky-carry head-clearance arc (Aug 2026) — only affects the CHASE
	## target's height below, never `target`/`dist` above. The knockout
	## check must keep measuring against the TRUE hold point — boosting
	## `target` itself before that check would make the arc maneuver risk
	## spuriously triggering a knockout mid-turn, which is the opposite of
	## what this is for.
	var chase_target: Vector3 = target
	if _carry_bulk_radius >= BULKY_CARRY_RADIUS_THRESHOLD:
		chase_target.y += _carry_arc_height_boost(target)

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (chase_target - global_position) * speed
	angular_velocity = Vector3.ZERO

## Continuous (no state machine) head-clearance boost for bulky held items.
## Compares the item's ACTUAL current bearing from the player against its
## TARGET bearing — the angular gap between them is large exactly when a
## fast turn has left the item physically lagging far behind on the
## opposite side of where it needs to be, regardless of how fast the turn
## itself was. Ramps linearly from 0 at CARRY_ARC_START_ANGLE_DEG up to
## CARRY_ARC_MAX_HEIGHT at a full 180° gap, and back down to 0 as the item
## catches up — the arc and its settle are the same formula, not two steps.
## `_hold_point.get_parent()` is `InteractionSystem`, which sits at the
## player's own origin with no transform offset (confirmed against
## Player.tscn) — its global_position IS the player's position, no separate
## player reference needed.
func _carry_arc_height_boost(target: Vector3) -> float:
	var player_pos: Vector3 = _hold_point.get_parent().global_position
	var to_current: Vector2 = Vector2(global_position.x - player_pos.x, global_position.z - player_pos.z)
	var to_target: Vector2  = Vector2(target.x - player_pos.x, target.z - player_pos.z)
	if to_current.length() < 0.05 or to_target.length() < 0.05:
		return 0.0
	var angle: float = absf(to_current.normalized().angle_to(to_target.normalized()))
	var start: float = deg_to_rad(CARRY_ARC_START_ANGLE_DEG)
	if angle <= start:
		return 0.0
	var t: float = (angle - start) / (PI - start)
	return CARRY_ARC_MAX_HEIGHT * clampf(t, 0.0, 1.0)
```

---

## Why this is safe for everything else

- **Every other item is completely unaffected.** `_carry_bulk_radius` is
  computed from real geometry per item; only Crate/Can Case/Water Case
  clear the 0.30 threshold today. Basket and Cooking Pot go through the
  exact same code path (both call `super._physics_process()` first) but
  their own radius (~0.28) keeps the boost at a permanent 0.0 — verified
  by the actual numbers above, not assumed.
- **The knockout system is untouched.** `dist`/`KNOCK_DISTANCE` still
  measure against the true, unboosted `target` — the arc only ever
  changes what `linear_velocity` chases, never what triggers a knockout.
- **Inventory-follow (`from_inventory`) items are unaffected in practice**
  even though the code path is shared — nothing you pull from a slot is
  one of the three bulky items' size class, and if it ever were, the same
  geometry-driven gate would apply consistently rather than needing a
  separate carve-out.
- **No new per-frame allocations or lookups** beyond two `Vector2`s and
  an angle — negligible cost, and only computed at all for the ~3 items
  in the game that clear the radius gate.

---

## Verification checklist

1. Pick up a Water Bottle or Food Can, spin the player 180° rapidly —
   confirm behavior is completely unchanged (small item, radius well
   under threshold).
2. Pick up the Basket or Cooking Pot, spin rapidly — confirm still
   unchanged (both measured just under threshold; this is the case most
   worth double-checking in-editor since they're closest to the line).
3. Pick up a Crate, spin the player 180° rapidly — confirm it now visibly
   arcs up and over instead of getting stuck against the player's head/
   capsule.
4. Same test for Can Case and Water Case.
5. Slow, deliberate 180° turn while holding a Crate — confirm little to
   no visible arc (the item should already be tracking closely enough
   that the angular gap never crosses `CARRY_ARC_START_ANGLE_DEG`) —
   this should look like normal carrying, not an unnecessary hop.
6. While holding a Crate, get the item's held position knocked out
   (obstruct it / exceed `KNOCK_DISTANCE`) mid-arc if you can time it —
   confirm knockout still triggers correctly and isn't affected by the
   temporary height boost.
7. Full 360° continuous spin while holding a Crate — confirm it arcs
   smoothly rather than snapping or stuttering (this exercises the
   continuous ramp at its largest sustained angle).
8. General regression: pickup/drop/store/scroll cycle for all five items
   discussed here, unaffected by this change in every other respect.

---

## Documentation updates (apply alongside the code change above)

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the existing "E-dispatch shelf
fairness (Aug 2026)" entry and the supersession/cooking-pot entries
added in the prior plan:

```markdown
- **Bulky held-item head-clearance arc (Aug 2026, `PickupableItem.gd`
  — flagged: `scripts/world/items/`, not one of the three core files,
  but the hold-follow mechanic itself is Player-subsystem scope).**
  Fixes Crate/Can Case/Water Case visibly getting stuck against the
  player's head during a fast 180° turn while held. Root cause: held
  items are real `RigidBody3D`s with `collision_mask = 1`, the same
  layer as the player's own `CapsuleShape3D` — during a fast turn, the
  straight-line chase path from one side of the player to the other
  passes through that capsule, and large enough items physically
  collide with it instead of passing through cleanly. Gated by a
  lazily-computed real collision-shape radius
  (`_carry_bulk_radius`, `BULKY_CARRY_RADIUS_THRESHOLD = 0.30`) rather
  than a hardcoded item list or mass — mass doesn't correlate (Basket/
  Cooking Pot are heavier by mass than Can Case/Water Case but have a
  smaller footprint, and are correctly unaffected). While a bulky
  item's actual position and its target are far enough apart
  angularly (`CARRY_ARC_START_ANGLE_DEG`), the CHASE target's height
  (never the true hold point used for the knockout check) ramps
  upward continuously, driving the physics body up and over the
  player's capsule instead of through it, and back down as the item
  catches up — one continuous formula, no state machine.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Bulky Held-Item Head-Clearance Arc (Aug 2026)

## What changed this session
Fixed Crate/Can Case/Water Case getting visibly stuck against the
player's head during a fast 180° turn while held. Root cause: held
items are real, fully-collidable `RigidBody3D`s (`collision_mask = 1`,
same layer as the player's own `CapsuleShape3D`) chasing `hold_point`
via a simple proportional-velocity controller in
`PickupableItem._physics_process()`. `hold_point` jumps to its new
position instantly on player rotation; the item's straight-line
physical path to catch up passes through the player's own capsule, and
large enough items collide with it instead of sliding past.

Traced the actual differentiator empirically rather than assuming mass:
computed each carriable item's real collision-shape horizontal radius —
Basket/Cooking Pot ~0.28 (unaffected, correctly so despite being
"heavier" by mass), Can Case/Water Case ~0.34, Crate ~0.46 (all three
reported-affected). Added a lazily-computed `_carry_bulk_radius`
(computed on first `pickup()`, not in `_ready()`, since Basket/
CookingPot build their `CollisionShape3D` procedurally AFTER their own
`_ready()` calls `super()` — computing it any earlier would've silently
fallen back to a generic minimum radius dangerously close to the new
threshold and misclassified both). Items at or above
`BULKY_CARRY_RADIUS_THRESHOLD` (0.30) get a continuous, angle-driven
upward boost applied only to their physics CHASE target (never the true
hold point the knockout-distance check measures against) whenever their
actual position and target are far enough apart angularly — ramping in
and back out smoothly as the item catches up, no separate settle step.

### Files modified
- `scripts/world/items/PickupableItem.gd` — new tuning consts, lazy
  `_carry_bulk_radius` computation in `pickup()`, chase-target height
  boost + new `_carry_arc_height_boost()` helper in `_physics_process()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_BULKY_HOLD_ARC_PLAN.md` for the full 8-item checklist)
```
