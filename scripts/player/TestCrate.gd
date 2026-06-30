extends RigidBody3D
## TestCrate.gd
## Carriable crate. While held, stays in world tree and lerps to hold point
## every physics frame — no reparenting during carry.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var item_name: String = "Crate"
@export var knock_distance: float = 1.6
@export var follow_speed: float = 12.0      ## Reduced — smoother travel to hand
@export var pickup_grace: float = 0.4       ## Seconds after pickup before knockout can trigger

# ─── Signals ──────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()

# ─── State ────────────────────────────────────────────────────────────────────
var is_held: bool = false
var _hold_point: Node3D = null
var _world_root: Node3D = null
var _grace_timer: float = 0.0

func _ready() -> void:
	add_to_group("pickup")
	contact_monitor = true
	max_contacts_reported = 4

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	# Count down grace period
	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	# Only knock out once grace period has expired
	if _grace_timer <= 0.0 and dist > knock_distance:
		_knock_out()
		return

	linear_velocity = (target - global_position) * follow_speed
	angular_velocity = Vector3.ZERO

# ─── Pickup ───────────────────────────────────────────────────────────────────
func pickup(hold_point: Node3D) -> void:
	is_held = true
	_hold_point = hold_point
	_grace_timer = pickup_grace
	_world_root = get_tree().get_first_node_in_group("world")
	freeze = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask = 1
	picked_up.emit()

# ─── Knock out ────────────────────────────────────────────────────────────────
func _knock_out() -> void:
	is_held = false
	_hold_point = null
	gravity_scale = 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	knocked_out.emit()

# ─── Drop ─────────────────────────────────────────────────────────────────────
func drop(world_parent: Node3D, drop_position: Vector3) -> void:
	is_held = false
	_hold_point = null
	global_position = drop_position
	gravity_scale = 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
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
	dropped.emit()

