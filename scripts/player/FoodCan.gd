extends RigidBody3D
## FoodCan.gd
## Pickupable consumable. Player picks up with F, eats with E.
## Restores a portion of the hunger meter on eat.

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()

# ─── Config ───────────────────────────────────────────────────────────────────
## A case holds 16 cans. Full hunger bar is 100.
## One can restores 1/16 of a full belly — roughly one meal's worth per 4 cans.
const FOOD_RESTORE: float   = 25.0   ## Fills ~1/4 of the hunger bar per can
const KNOCK_DISTANCE: float = 1.6

@export var follow_speed: float = 12.0
@export var pickup_grace: float = 0.4

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool       = false
var _hold_point: Node3D = null
var _player_stats: Node = null  ## Injected by CanCase on spawn, or MainWorld
var _grace_timer: float = 0.0

func _ready() -> void:
	add_to_group("pickup")
	contact_monitor = true
	max_contacts_reported = 4

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
		_do_knocked_out()
		return

	linear_velocity  = (target - global_position) * follow_speed
	angular_velocity = Vector3.ZERO

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_prompt_text() -> String:
	return "[F] Pick up"

func get_use_prompt() -> String:
	return "[E] Eat"

# ─── Pickup ───────────────────────────────────────────────────────────────────
func pickup(hold_point: Node3D) -> void:
	is_held       = true
	_hold_point   = hold_point
	_grace_timer  = pickup_grace
	freeze        = false
	freeze_mode   = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask  = 1
	picked_up.emit()

# ─── Use / Eat ────────────────────────────────────────────────────────────────
func on_use() -> void:
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FoodCan: _player_stats not found — cannot restore food.")
		return
	_player_stats.replenish_food(FOOD_RESTORE)
	queue_free()

# ─── Drop ─────────────────────────────────────────────────────────────────────
func drop(world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	dropped.emit()

# ─── Place ────────────────────────────────────────────────────────────────────
func place(world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(world_parent, place_position)

# ─── Knocked out ─────────────────────────────────────────────────────────────
func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	knocked_out.emit()
