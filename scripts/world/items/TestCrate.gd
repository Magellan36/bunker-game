extends RigidBody3D
## TestCrate.gd
## Carriable crate. While held, stays in world tree and lerps to hold point
## every physics frame — no reparenting during carry.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var item_name: String = "Crate"
@export var knock_distance: float     = 1.6
@export var follow_speed: float       = 18.0

## Shelf stacking — 1 crate per slot (too large to stack)
var shelf_stack_limit: int   = 1
var shelf_item_type: String  = "test_crate"
@export var inv_follow_speed: float   = 40.0
@export var pickup_grace: float       = 0.6

# ─── Signals ──────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()

# ─── State ────────────────────────────────────────────────────────────────────
var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _world_root: Node3D     = null
var _grace_timer: float     = 0.0
var _out_of_range_time: float = 0.0
const KNOCK_LINGER_TIME: float = 0.35

func _ready() -> void:
	add_to_group("pickup")
	contact_monitor = true
	max_contacts_reported = 4
	## Scale to match ~half the previous size.
	## plastic_crate.glb native dims: 0.298 x 0.264 x 0.408 m (real-world scale).
	## Child model node carries 0.6x scale; this root scale of 3.0 gives
	## final visual size: ~0.54 x 0.48 x 0.73 m — a sensible carry crate.
	## CollisionShape3D box in TestCrate.tscn is pre-calculated to match exactly.
	scale = Vector3(3.0, 3.0, 3.0)

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > knock_distance:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_knock_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

# ─── Pickup ───────────────────────────────────────────────────────────────────
func pickup(hold_point: Node3D) -> void:
	is_held = true
	_hold_point = hold_point
	_grace_timer = pickup_grace
	_out_of_range_time = 0.0
	_world_root = get_tree().get_first_node_in_group("world")
	freeze = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask = 1
	_set_held_culling(true)
	picked_up.emit()

# ─── Knock out ────────────────────────────────────────────────────────────────
func _knock_out() -> void:
	is_held = false
	_hold_point = null
	gravity_scale = 1.0
	freeze = false
	collision_layer = 1
	collision_mask = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

# ─── Drop ─────────────────────────────────────────────────────────────────────
func drop(world_parent: Node3D, drop_position: Vector3) -> void:
	is_held = false
	_hold_point = null
	global_position = drop_position
	gravity_scale = 1.0
	freeze = false
	collision_layer = 1
	collision_mask = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

# ─── Place ────────────────────────────────────────────────────────────────────
func place(world_parent: Node3D, place_position: Vector3, place_rotation: Vector3 = Vector3.ZERO) -> void:
	is_held = false
	_hold_point = null
	global_position = place_position
	rotation = place_rotation
	gravity_scale = 1.0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 1
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

# ─── Culling helper ───────────────────────────────────────────────────────────
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin

