extends RigidBody3D
## FuelCan.gd
## Pickupable fuel container. Hold it near a generator and hold E to refuel continuously.
## Carries FUEL_UNITS_TOTAL = 100 PM-units of fuel.
## Continuous refuel: FUEL_RATE units/sec transferred while E is held near a generator.
## Cannot be stored in inventory slots (can_store() → false).

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()   ## Emitted when fuel changes — HUD badge update

# ─── Config ───────────────────────────────────────────────────────────────────
const FUEL_UNITS_TOTAL: float = 100.0  ## Total fuel in a full can (PM units)
const FUEL_PER_POUR:    float =  25.0  ## PM units per legacy "pour" (badge display only)
const TOTAL_POURS:      int   =    4
const REFUEL_RANGE:     float =  2.5   ## Max distance to generator for refuelling
const KNOCK_DISTANCE:   float =  2.2
const KNOCK_LINGER_TIME:float =  0.35

## Continuous refuel rate — PM-units transferred per real second.
## At 8.0 u/s a full can takes ~12.5 s to empty into a generator.
const FUEL_RATE: float = 8.0

@export var follow_speed:     float = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace:     float = 0.6

## Shelf / inventory config (shelf_item_type used by shelving system)
var shelf_stack_limit: int    = 2
var shelf_item_type:   String = "fuel_can"

# ─── State ───────────────────────────────────────────────────────────────────
var is_held:           bool   = false
var from_inventory:    bool   = false
var _hold_point:       Node3D = null
var _grace_timer:      float  = 0.0
var _out_of_range_time:float  = 0.0

var _fuel_remaining:   float  = FUEL_UNITS_TOTAL
var _is_empty:         bool   = false
var _player_in_range:  bool   = false

func _unfreeze_after_spawn() -> void:
	freeze = false

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	add_to_group("interactable")
	contact_monitor       = true
	max_contacts_reported = 4

# ─── Inventory gate ──────────────────────────────────────────────────────────
## Returning false blocks InteractionSystem from storing this item into a slot.
## Fuel cans must stay in the world — you carry them by hand only.
func can_store() -> bool:
	return false

# ─── Proximity callback ───────────────────────────────────────────────────────
## Called by InteractionSystem when player enters/exits the DetectArea.
func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

# ─── Physics follow ───────────────────────────────────────────────────────────
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
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Jerry Can"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Jerry Can (Empty)"
	var pct: int = int((_fuel_remaining / FUEL_UNITS_TOTAL) * 100.0)
	return "[F] Pick up  Jerry Can (%d%%)" % pct

func get_use_prompt() -> String:
	if _is_empty:
		return ""
	var gen: Node3D = _find_nearest_generator()
	if gen == null:
		return ""
	## Line 1 — action + live generator fuel%
	## Line 2 — this can's own remaining fuel%
	var can_pct: int = int((_fuel_remaining / FUEL_UNITS_TOTAL) * 100.0)
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		var gen_id: String  = str(gen.get_instance_id())
		var gen_fuel: float = pm.get_generator_fuel(gen_id)
		var gen_pct: int    = int(clampf(gen_fuel, 0.0, 100.0))
		return "[Hold E] Refuel Generator  —  %d%%\nFuel: %d%%" % [gen_pct, can_pct]
	return "[Hold E] Refuel Generator\nFuel: %d%%" % can_pct

# ─── Continuous refuel tick (called by InteractionSystem._process each frame) ─
## Transfers FUEL_RATE * delta units from this can into the nearest in-range
## generator. Called externally — InteractionSystem detects E-held + generator.
func refuel_tick(delta: float) -> void:
	if _is_empty:
		return

	var gen: Node3D = _find_nearest_generator()
	if gen == null:
		return

	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	var gen_id: String  = str(gen.get_instance_id())
	var current: float  = pm.get_generator_fuel(gen_id)

	if current >= 100.0:
		return   ## Generator already full — nothing to do this tick

	var transfer: float  = minf(FUEL_RATE * delta, 100.0 - current)
	transfer             = minf(transfer, _fuel_remaining)

	if transfer <= 0.0:
		return

	pm.set_generator_fuel(gen_id, current + transfer)

	_fuel_remaining -= transfer
	_fuel_remaining  = maxf(0.0, _fuel_remaining)

	charge_changed.emit()

	if _fuel_remaining <= 0.0:
		_become_empty()

# ─── Legacy on_use — kept so existing callers don't break, but does nothing. ──
## Continuous refuel via refuel_tick() supersedes this.
func on_use() -> void:
	pass   ## No-op: InteractionSystem uses refuel_tick() instead

func _find_nearest_generator() -> Node3D:
	var best_node: Node3D = null
	var best_dist: float  = REFUEL_RANGE
	for node: Node in get_tree().get_nodes_in_group("generator"):
		if node is Node3D:
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best_node = node as Node3D
	return best_node

# ─── Empty state ──────────────────────────────────────────────────────────────
func _become_empty() -> void:
	_is_empty       = true
	_fuel_remaining = 0.0

# ─── Pickup / Drop / Place ────────────────────────────────────────────────────
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
	_set_held_culling(true)
	picked_up.emit()

func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

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
	for child: Node in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).extra_cull_margin = margin
