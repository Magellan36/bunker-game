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

## Shelf stacking — override in subclass
var shelf_stack_limit: int  = 6
var shelf_item_type: String = "generic"

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _grace_timer: float       = 0.0
var _out_of_range_time: float = 0.0

func _ready() -> void:
	add_to_group("pickup")
	contact_monitor = true
	max_contacts_reported = 4

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
