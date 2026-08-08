extends RigidBody3D
class_name PickupableItem
## PickupableItem.gd
## Base class for all physics-based pickupable items in the game.
## Handles the shared scaffolding: hold-follow physics, knockout distance check,
## pickup/drop/place lifecycle, culling margin, and group registration.
##
## Subclasses override only what differs:
##   - get_display_name(), get_prompt_text(), get_use_prompt() — prompt contract
##   - on_use() — what E does while held
##   - _on_pickup_extra() / _on_drop_extra() — item-specific side effects
##   - _build_placeholder_mesh() — procedural mesh if no .tscn scene
##
## NOT for the old reparent-based PickupItem.gd items (TestCrate, the original
## PickupItem pattern). Those stay on their existing base.

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()

# ─── Config (override per-item via @export or const) ─────────────────────────
const KNOCK_DISTANCE: float    = 2.2
const KNOCK_LINGER_TIME: float = 0.35

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

# ─── State ───────────────────────────────────────────────────────────────────
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

func _ready() -> void:
	add_to_group("pickup")
	contact_monitor = true
	max_contacts_reported = 4
	_maybe_create_nav_obstacle()

## NPC Pass 2, Part 11 — heavy loose items (mass >= HEAVY_OBSTACLE_MASS)
## get a NavigationObstacle3D child so every NavigationAgent3D in the world
## (i.e. every NPC) routes around their CURRENT position continuously via
## real-time avoidance, instead of only reacting after physically colliding.
## Light items (below the threshold) get none — they're meant to be walked
## through, not routed around (see NPC.gd's _handle_physics_pushes).
## Threshold matches NPC.gd's HEAVY_MASS_THRESHOLD (kept as a separate literal
## rather than a cross-class const reference, to avoid any parse-order risk
## between the two classes — keep both values in sync if either changes).
const HEAVY_OBSTACLE_MASS: float = 3.0
const OBSTACLE_MIN_RADIUS: float = 0.3   ## floor so a tiny/degenerate shape
                                         ## never produces a near-zero obstacle

var _nav_obstacle: NavigationObstacle3D = null

func _maybe_create_nav_obstacle() -> void:
	if mass < HEAVY_OBSTACLE_MASS:
		return
	_nav_obstacle = NavigationObstacle3D.new()
	_nav_obstacle.name = "NavObstacle"
	_nav_obstacle.radius = _compute_obstacle_radius()
	_nav_obstacle.avoidance_enabled = true
	add_child(_nav_obstacle)

## Lets external code (an NPC actively approaching this item to grab it)
## temporarily suspend obstacle avoidance while it's still on the ground.
## pickup()/drop() already handle the held/dropped states correctly —
## this covers the gap in between: the walk-up itself, during which
## avoidance would otherwise prevent ever closing the final distance to
## a heavy item.
func set_nav_obstacle_enabled(enabled: bool) -> void:
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = enabled

## Generic, shape-agnostic bounding-circle radius computed from this item's
## ACTUAL collision geometry (every CollisionShape3D child, compound shapes
## included) rather than a hardcoded per-item guess — same "trust the real
## physics data" principle that fixed navigation in Part 9. Works for any
## Shape3D type via Shape3D.get_debug_mesh(), which is available at runtime
## (not editor-only).
func _compute_obstacle_radius() -> float:
	var max_r: float = OBSTACLE_MIN_RADIUS
	for child: Node in get_children():
		if not (child is CollisionShape3D):
			continue
		var cs: CollisionShape3D = child as CollisionShape3D
		if cs.shape == null:
			continue
		var aabb: AABB = cs.shape.get_debug_mesh().get_aabb()
		for i: int in range(8):
			var corner: Vector3 = aabb.position + Vector3(
				aabb.size.x * float(i & 1),
				aabb.size.y * float((i >> 1) & 1),
				aabb.size.z * float((i >> 2) & 1))
			var local: Vector3 = cs.transform * corner
			max_r = maxf(max_r, Vector2(local.x, local.z).length())
	return max_r

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

# ─── Prompt interface (override in subclass) ─────────────────────────────────
func get_display_name() -> String:
	return "Item"

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

func get_use_prompt() -> String:
	return ""

# ─── Pickup ──────────────────────────────────────────────────────────────────
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

## Override for item-specific pickup side effects (e.g. finding player ref).
func _on_pickup_extra() -> void:
	pass

# ─── Drop ────────────────────────────────────────────────────────────────────
func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = true   ## back on the floor — resume
		                                         ## acting as a real obstacle
	add_to_group("pickup")
	_set_held_culling(false)
	_on_drop_extra()
	dropped.emit()

## Override for item-specific drop side effects.
func _on_drop_extra() -> void:
	pass

# ─── Place (precise) ─────────────────────────────────────────────────────────
func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	is_held         = false
	_hold_point     = null
	global_position = place_position
	rotation        = _rot
	gravity_scale   = 1.0
	freeze          = true
	freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask  = 1
	add_to_group("pickup")
	_set_held_culling(false)
	_on_drop_extra()
	dropped.emit()

# ─── Knocked out ─────────────────────────────────────────────────────────────
func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

# ─── Culling helper ──────────────────────────────────────────────────────────
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin

## Shared spawn helper — see FarmingShopHelper.spawn_scene_settled()
## for the convention: freeze this body for exactly one physics frame right
## after spawning (so it doesn't fall through a floor that physics hasn't
## "seen" yet), then call this deferred to unfreeze it.
func _unfreeze_after_spawn() -> void:
	freeze = false
