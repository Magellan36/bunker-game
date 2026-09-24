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

## Settle-to-sleep (Aug 2026) — a furnished bunker quickly fills with loose
## RigidBody3D items (produce, cans, bottles, …) and each AWAKE body is a
## per-tick physics cost. Godot's own auto-sleep (0.5 m/s) usually handles
## it, but stacked/jittering bodies can stay awake indefinitely. Once an
## unheld item is genuinely still for SETTLE_FRAMES, force `sleeping = true`
## to drop it out of the physics step entirely; pickup() wakes it again.
## Self-managing: any contact (player/NPC bump) wakes it and the counter
## restarts. Frozen (placed/shelved) bodies skip this entirely.
const SETTLE_VELOCITY: float = 0.06    ## m/s
const SETTLE_ANGULAR: float = 0.12     ## rad/s
const SETTLE_FRAMES: int = 25          ## ~0.4 s of stillness at 60 Hz

var _settle_frames: int = 0

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

## Whether CTRL-hold manual-upright (see _physics_process()'s CTRL branch
## below) applies to this item. True by default for every item;
## Flashlight.gd overrides this to false — a flashlight's own rotation IS
## its aim direction (it auto-aims along the player's facing), so forcing
## it upright while held would fight the entire point of holding one.
var allow_manual_upright: bool = true

## Set TRUE by preview systems (GhostModelBuilder.build_real_instance /
## BuildModeHUD's shop previews) BEFORE add_child(), so this instance builds
## its real visuals for a thumbnail but skips every world side-effect
## (joining the "pickup" group, creating a NavigationObstacle3D). Without
## it, preview instances run their full _ready() inside an isolated
## SubViewport yet still join tree-wide groups — and NPC/interaction group-
## scans treat them as real items at ~world origin. Same convention as
## Stove.gd/GeneratorObject.gd etc. — see GhostModelBuilder.gd's
## build_real_instance() doc.
var _is_preview_only: bool = false

func _ready() -> void:
	if not _is_preview_only:
		add_to_group("pickup")
		_maybe_create_nav_obstacle()
		## Procedural subclasses commonly create their collision shapes after
		## calling super._ready(). Re-measure once that construction stack ends.
		call_deferred("_refresh_nav_obstacle_radius")
		## Sep 2026 — apply the mass-based rest collision layer/mask AFTER the
		## whole _ready chain settles (deferred), so EVERY spawn path is
		## covered — not just drop()/place()/knocked-out, but direct
		## instantiation like WaterCase._spawn_one() adding a bottle straight
		## into the world, which previously left items on the default layer 1
		## and kept them physically colliding with the player/NPC. Items that
		## are immediately held get re-layered by the pickup path anyway.
		call_deferred("_apply_rest_collision")

## Applies the loose-item rest collision layer/mask (mass-based) to this item.
## Idempotent — safe to call on an item already in rest state.
func _apply_rest_collision() -> void:
	if not is_instance_valid(self):
		return
	collision_layer = rest_collision_layer()
	collision_mask  = _rest_collision_mask()

## Loose bodies at/above this mass are meaningful navigation blockers. Small
## items deliberately have no RVO obstacle: residents walk through a pile of
## cans, bottles, filters, medicine, etc. while the one-sided shove query below
## moves those objects out of their path. Cases, crates, pots, baskets, and
## similarly bulky bodies keep avoidance plus hard collision.
const HEAVY_OBSTACLE_MASS: float = 3.0
const OBSTACLE_MIN_RADIUS: float = 0.3   ## floor so a tiny/degenerate shape
										 ## never produces a near-zero obstacle

## ─── Collision-layer separation for loose items (Sep 2026) ────────────────
## Small loose items (mass < HEAVY_OBSTACLE_MASS: food cans, water bottles,
## medical items, purifier filters, ...) rest on collision LAYER 4 (bit 3),
## which the player/NPC CharacterBody3D (mask 1) does NOT collide with — you
## walk straight through them instead of them launching you / shoving you
## around. Large items (mass >= 3: cases, crates, pots, ...) stay on layer 1
## and still physically block/slow the player like always. The DetectArea
## (player pickup) mask is widened to include bit 3 so small items remain
## grabbable. Layer 4 is deliberately NOT bit 2 (held-item layer).
const ITEM_LAYER_SMALL: int = 4   ## loose small items — pass-through to characters
const ITEM_LAYER_LARGE: int = 1   ## loose large items — block characters
## Small items still rest on / bounce off the floor, walls, and each other via
## their MASK (unchanged, still bit 1 + bit 3 so they interact with layer-1
## world geometry and other layer-4 items), while their LAYER (what they ARE)
## is what excludes them from character collision.
## Returns the layer a loose item should rest on, by mass.
func rest_collision_layer() -> int:
	return ITEM_LAYER_SMALL if mass < HEAVY_OBSTACLE_MASS else ITEM_LAYER_LARGE

## Returns the collision MASK a loose item should use while resting — bit 1
## (floor / walls / large items / characters' own layer) plus bit 3 (other
## small items, so dropped cans/bottles stack and bounce off each other).
## The mask is the same for small and large items; it's the LAYER that
## differs.
func _rest_collision_mask() -> int:
	return 1 | ITEM_LAYER_SMALL

## ─── Character walk-through shove (Sep 2026) ────────────────────────────────
## Small loose items rest on ITEM_LAYER_SMALL (bit 3), which the player/NPC
## CharacterBody3D (mask 1) does NOT collide with — so the character walks
## through them without tripping/being launched. But without collision there's
## also no natural push, so the bottle would just sit there. THIS provides the
## one-sided shove: a spatial query around the character's body finds nearby
## small loose items and applies a gentle outward impulse so they get shoved
## out of the way as the character walks through — the item is the only thing
## affected, the character is not.
const SHOVE_RADIUS: float = 0.72   ## reaches floor items beside/near the character's feet
const SHOVE_IMPULSE: float = 0.65  ## repeated walking nudge, not a launch
const SHOVE_MASS_CAP: float = 3.0  ## mirrors HEAVY_OBSTACLE_MASS / NPC HEAVY_PUSH_MASS
const SHOVE_COOLDOWN_MSEC: int = 200

## Static, shared by Player.gd and NPC.gd so both characters shove small
## items identically. `character` is the CharacterBody3D; a shove fires at
## most once per item per SHOVE_COOLDOWN_MSEC (tracked per character via the
## supplied dict so multiple characters can shove independently).
static func shove_small_items_near(character: CharacterBody3D, cooldown_by_item: Dictionary) -> void:
	if character == null or not is_instance_valid(character):
		return
	var travel := Vector3(character.velocity.x, 0.0, character.velocity.z)
	if travel.length_squared() < 0.01:
		return
	travel = travel.normalized()
	var space: PhysicsDirectSpaceState3D = character.get_world_3d().direct_space_state
	if space == null:
		return
	## Query a sphere around the character's LOWER body / feet, mask =
	## ITEM_LAYER_SMALL. The character body's origin sits at the capsule CENTER
	## (~y=0.8), while loose items rest near the FLOOR (~y=0.05–0.1), so the
	## query is dropped to the character's lower half (origin − ~0.45) where
	## floor items actually are — a query at center height would float ~0.8m
	## above the items and never overlap them.
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = SphereShape3D.new()
	(params.shape as SphereShape3D).radius = SHOVE_RADIUS
	params.transform = Transform3D(Basis.IDENTITY, character.global_position + Vector3(0.0, -0.45, 0.0))
	params.collision_mask = ITEM_LAYER_SMALL
	params.exclude = [character.get_rid()]
	var results: Array[Dictionary] = space.intersect_shape(params, 64)
	var now: int = Time.get_ticks_msec()
	for r: Dictionary in results:
		var collider: Object = r.get("collider")
		if collider == null or not (collider is RigidBody3D):
			continue
		var rb: RigidBody3D = collider as RigidBody3D
		if not rb.is_in_group("pickup"):
			continue
		if ("is_held" in rb) and bool(rb.get("is_held")):
			continue
		if rb.freeze:
			continue
		if rb.mass >= SHOVE_MASS_CAP:
			continue
		var item_id: int = rb.get_instance_id()
		if now - int(cooldown_by_item.get(item_id, -SHOVE_COOLDOWN_MSEC)) < SHOVE_COOLDOWN_MSEC:
			continue
		cooldown_by_item[item_id] = now
		## Primarily continue the character's travel direction so walking through
		## a pile parts it ahead instead of pulling pieces sideways/backward. A
		## small radial contribution prevents several items stacking perfectly.
		var away: Vector3 = rb.global_position - character.global_position
		away.y = 0.0
		if away.length() <= 0.01:
			away = -character.global_transform.basis.z
		away = away.normalized()
		var push_direction: Vector3 = (travel * 0.82 + away * 0.18).normalized()
		rb.sleeping = false
		rb.apply_central_impulse(push_direction * SHOVE_IMPULSE / maxf(1.0, rb.mass))

var _nav_obstacle: NavigationObstacle3D = null

func _maybe_create_nav_obstacle() -> void:
	if is_soft_navigation_clutter():
		return
	_nav_obstacle = NavigationObstacle3D.new()
	_nav_obstacle.name = "NavObstacle"
	_nav_obstacle.radius = _compute_obstacle_radius()
	_nav_obstacle.avoidance_enabled = true
	add_child(_nav_obstacle)


func _refresh_nav_obstacle_radius() -> void:
	if _nav_obstacle != null:
		_nav_obstacle.radius = _compute_obstacle_radius()

## Lets external code (an NPC actively approaching this item to grab it)
## temporarily suspend obstacle avoidance while it's still on the ground.
## pickup()/drop() already handle the held/dropped states correctly —
## this covers the gap in between: the walk-up itself, during which
## avoidance would otherwise prevent ever closing the final distance to
## a heavy item.
func set_nav_obstacle_enabled(enabled: bool) -> void:
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = enabled and not is_soft_navigation_clutter()


func is_soft_navigation_clutter() -> bool:
	return mass < HEAVY_OBSTACLE_MASS

## Debug-only readout used by the NPC navigation flight recorder. Keeping the
## obstacle's measured footprint beside the body's real physics state makes
## radius/state mismatches visible without exposing the obstacle to gameplay.
func get_navigation_obstacle_debug_info() -> Dictionary:
	return {
		"radius": _nav_obstacle.radius if _nav_obstacle != null else -1.0,
		"enabled": _nav_obstacle.avoidance_enabled if _nav_obstacle != null else false,
		"mass": mass,
		"sleeping": sleeping,
		"freeze": freeze,
		"held": is_held,
		"shelved": is_in_group("shelved"),
		"linear_velocity": linear_velocity,
	}

## ─── Deactivate / restore for stored & placed items (Aug 2026) ──────────────
## A frozen item (placed, shelved, basket-stashed, stove-resting, in an
## inventory slot, etc.) still burns CPU every frame even though its physics
## body isn't simulated: the per-item _physics_process callback and —
## most expensively — the NavigationObstacle3D avoidance (RVO) both keep
## running regardless of the frozen state. deactivate_dynamic_state() kills
## both for the item's stored lifetime; restore_dynamic_state() brings them
## back when it becomes dynamic again (pickup/drop/knockout handle the
## held-vs-loose avoidance split).
##
## contact_monitor is no longer touched here — no code anywhere connects to
## a PickupableItem's own body_shape_entered/exited, so it was pure physics-
## server overhead on every active item (not just stored ones) for no
## payoff. Removed entirely in _ready() rather than toggled.
func deactivate_dynamic_state(keep_navigation_obstacle: bool = false) -> void:
	set_physics_process(false)
	set_nav_obstacle_enabled(keep_navigation_obstacle)

func restore_dynamic_state() -> void:
	set_physics_process(true)
	set_nav_obstacle_enabled(true)

## Generic, shape-agnostic bounding-circle radius computed from this item's
## ACTUAL collision geometry (every CollisionShape3D child, compound shapes
## included) rather than a hardcoded per-item guess — same "trust the real
## physics data" principle that fixed navigation in Part 9. Works for any
## Shape3D type via Shape3D.get_debug_mesh(), which is available at runtime
## (not editor-only).
func _compute_obstacle_radius() -> float:
	return get_navigation_footprint_radius()

## World-space XZ footprint. Unlike the old local-space estimate, this includes
## body rotation and scale, so a long object that tips onto its side publishes
## the space it actually occupies instead of its original upright radius.
func get_navigation_footprint_radius() -> float:
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
			var world_corner: Vector3 = cs.global_transform * corner
			var offset: Vector3 = world_corner - global_position
			max_r = maxf(max_r, Vector2(offset.x, offset.z).length())
	return max_r

# ─── Physics: follow hold point + knockout check ─────────────────────────────
func _physics_process(delta: float) -> void:
	if _nav_obstacle != null:
		## RVO needs the obstacle's actual motion to predict where it will be;
		## position alone only produces late, reactive sidestepping.
		_nav_obstacle.velocity = linear_velocity
	if not is_held or _hold_point == null:
		_apply_settle_sleep()
		return
	_settle_frames = 0

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

	## CTRL manual-upright hold (Aug 2026) — while CTRL is held, ease
	## ANY held item toward upright, same slerp_to_upright() the Basket/
	## Cooking Pot always-on lock uses. Excludes Flashlight.gd
	## (allow_manual_upright = false there) and Basket/Cooking Pot
	## specifically (they already do this unconditionally via their own
	## _physics_process() override, immediately after this base call
	## returns — calling it twice in the same frame would be harmless but
	## pointless). Stops the instant CTRL is released: this only ever
	## takes one interpolation step per call, so the item simply keeps
	## whatever orientation it had on the last frame CTRL was held.
	if allow_manual_upright and not ("is_basket_container" in self) and not ("is_cookpot_container" in self) \
			and Input.is_key_pressed(KEY_CTRL):
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)

## Loose, at-rest item → force it to sleep so it stops costing a physics
## step every tick. Only genuinely-settled, unheld, unfrozen bodies apply;
## moving bodies just reset the counter. Once asleep, a real contact wakes
## it and the cycle restarts automatically.
func _apply_settle_sleep() -> void:
	if freeze or sleeping:
		return
	if linear_velocity.length() < SETTLE_VELOCITY \
			and angular_velocity.length() < SETTLE_ANGULAR:
		_settle_frames += 1
		if _settle_frames >= SETTLE_FRAMES:
			_settle_frames = 0
			_refresh_nav_obstacle_radius()
			sleeping = true
	else:
		_settle_frames = 0

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

# ─── Heavy / Light classification (Aug 2026) ─────────────────────────────────
## The standing "Heavy" vs "Light" split for held items, going forward —
## mirrors the exact rule NPCJobQueries.classify_organizable_item() already
## uses for cleaning-destination routing (that file is NPC-thread-owned,
## not touched here — flagged as a future consolidation opportunity once
## coordinated across threads, rather than duplicated silently). "Light" =
## inventory_item group (whatever fits the player's 4-slot inventory);
## "Heavy" = everything else (Crate, Basket, Cooking Pot, Can Case, Water
## Case, etc.). Consumed by Player.gd's heavy-carry stamina drain — see
## its _handle_movement() drain block — and available to any future
## system (Medical, etc.) that needs the same classification.
func is_heavy_item() -> bool:
	return not is_in_group("inventory_item")

## Resolves the CharacterBody3D currently holding this item, or null when not
## held. Walks up from _hold_point until it finds one — Player: hold_point →
## InteractionSystem → Player; NPC: hold_point → NPC. Both face local -Z, so
## callers can use the returned body's `-global_transform.basis.z` as the
## holder's facing direction (used by CanCase/WaterCase ejection).
func _get_holder() -> CharacterBody3D:
	if _hold_point == null:
		return null
	var node: Node = _hold_point
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null

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
	sleeping           = false   ## wake from settle-to-sleep (Aug 2026)
	restore_dynamic_state()   ## undo a stored/placed item's deactivation (Aug 2026)
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
	collision_layer = rest_collision_layer()
	collision_mask  = _rest_collision_mask()
	linear_velocity = Vector3.ZERO
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = true   ## back on the floor — resume
	call_deferred("_refresh_nav_obstacle_radius")
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
	collision_layer = rest_collision_layer()
	collision_mask  = _rest_collision_mask()
	## A floor-placed RigidBody is excluded from static navmesh parsing. Keep
	## its avoidance footprint active even while its own physics tick sleeps.
	deactivate_dynamic_state(true)
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
	collision_layer = rest_collision_layer()
	collision_mask  = _rest_collision_mask()
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	restore_dynamic_state()   ## back to a live loose item (Aug 2026)
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
	restore_dynamic_state()   ## spawn freeze was transient — back to live (Aug 2026)
	freeze = false

# ─── Upright interpolation (Aug 2026) ─────────────────────────────────────────
## How quickly slerp_to_upright() converges — same role follow_speed plays
## for position-chase. Higher = snappier. 10.0 reaches ~99% converged in
## roughly a third of a second regardless of framerate (exponential decay,
## see slerp_to_upright()'s own comment) — visibly smooth but not sluggish.
## Shared by Basket/CookingPot's own always-on upright lock AND the CTRL
## manual-upright hold below; split into two separate consts if you want
## a different feel for the two cases after trying this in-editor.
const UPRIGHT_SLERP_SPEED: float = 10.0

## Smoothly rotates this item's CURRENT orientation toward perfectly
## upright (Basis.IDENTITY) using spherical interpolation, so the shortest
## rotational path is taken regardless of current tilt. `speed` controls
## convergence rate the same way follow_speed does for position (t =
## speed * delta each call — exponential decay, so it naturally slows down
## as it approaches upright rather than snapping then stopping). Call this
## every physics tick you want the behavior active; simply stop calling it
## to leave the item's rotation exactly wherever it currently is — this
## function holds no state of its own between calls, it only ever takes
## one step per call.
func slerp_to_upright(delta: float, speed: float) -> void:
	var t: float = clampf(speed * delta, 0.0, 1.0)
	## Aug 2026 fix — Basis.slerp() requires the STARTING basis to already
	## be a valid, orthonormal rotation (no scale/shear) to decompose into a
	## quaternion internally; feeding it anything else throws "must be
	## normalized" and returns a degenerate Quaternion(), which written back
	## into global_transform.basis corrupts it further — a feedback loop
	## that showed up live as the SAME error recurring with progressively
	## different (drifting) scale magnitudes across a session (confirmed via
	## two real error logs: ~0.977 and ~0.829 uniform scale on what should
	## be a scale-1.0 rotation). Orthonormalizing the CURRENT basis before
	## ever handing it to .slerp() sanitizes it every single call, so a
	## slightly-corrupted basis can never reach the failing call and the
	## loop can't start, regardless of how the drift originates upstream.
	var current_rotation: Basis = global_transform.basis.orthonormalized()
	global_transform.basis = current_rotation.slerp(Basis.IDENTITY, t).orthonormalized()
	angular_velocity = Vector3.ZERO
