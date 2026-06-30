extends RigidBody3D
## WaterCase.gd
## A case of 24 water bottles. Can be picked up and carried like a crate.
## While PLACED: press E to eject one bottle from the case.
## While HELD:   E does nothing (interact is blocked when carried).

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Water Case"
@export var bottle_count: int  = 24

@export var follow_speed: float = 12.0   ## Smooth travel to hold point
@export var pickup_grace: float = 0.4    ## Seconds after pickup before knockout triggers
@export var knock_distance: float = 1.6

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool       = false
var _hold_point: Node3D = null
var _grace_timer: float = 0.0
var _player_stats: Node = null  ## Injected by MainWorld (scans "interactable" group)

## Preloaded bottle scene — must exist at this path
const BOTTLE_SCENE: String = "res://scenes/world/WaterBottle.tscn"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor; positions where bottles eject from.
@onready var spawn_point: Node3D = $SpawnPoint

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("interactable")
	contact_monitor = true
	max_contacts_reported = 4

# ─── Physics: follow hold point while carried ─────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if _grace_timer <= 0.0 and dist > knock_distance:
		_do_knocked_out()
		return

	linear_velocity  = (target - global_position) * follow_speed
	angular_velocity = Vector3.ZERO

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

func get_interact_prompt() -> String:
	if is_held or bottle_count <= 0:
		return ""
	return "[E] Take water (%d)" % bottle_count

# ─── Interact: eject a bottle (only when placed, not held) ───────────────────
func on_interact() -> void:
	if is_held:
		return  # Can't dispense while carrying
	if bottle_count <= 0:
		return

	var bottle_res: Resource = load(BOTTLE_SCENE)
	if bottle_res == null:
		push_error("WaterCase: Could not load WaterBottle.tscn at '%s'" % BOTTLE_SCENE)
		return

	var bottle: RigidBody3D = bottle_res.instantiate()

	# Inject player stats so the bottle can restore water when drunk
	# Use our own reference, or fall back to tree search
	if "_player_stats" in bottle:
		bottle._player_stats = _player_stats if _player_stats != null \
			else get_tree().get_first_node_in_group("player_stats")

	# Add to world root, not to self — keeps it from inheriting our transform on pickup/drop
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("WaterCase: No node in group 'world' found.")
		return

	world.add_child(bottle)
	bottle.global_position = spawn_point.global_position
	# Eject forward and slightly upward
	bottle.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	bottle_count -= 1

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
func place(world_parent: Node3D, place_position: Vector3, place_rotation: Vector3 = Vector3.ZERO) -> void:
	is_held         = false
	_hold_point     = null
	global_position = place_position
	rotation        = place_rotation
	gravity_scale   = 1.0
	freeze          = true
	freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 1
	collision_mask  = 1
	add_to_group("pickup")
	dropped.emit()

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
