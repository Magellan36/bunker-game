extends PickupableItem
## CanCase.gd
## A case of 16 food cans. Pickupable and carriable like a crate.
## While PLACED: press E to eject one can from the case.
## While HELD:   E does nothing (interact blocked while carrying).

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Can Case"
@export var can_count: int     = 16

## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
var shelf_item_type: String  = "can_case"

const CAN_SCENE: String = "res://scenes/world/FoodCan.tscn"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor — sets where cans eject from.
@onready var spawn_point: Node3D = $SpawnPoint

var _player_stats: Node = null  ## Injected by MainWorld

func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

func get_interact_prompt() -> String:
	if can_count <= 0:
		return ""
	return "[E] Take can (%d)" % can_count

# ─── Interact: eject a can — works both placed and while held ─────────────────
func on_interact() -> void:
	if can_count <= 0:
		return

	var can_res: Resource = load(CAN_SCENE)
	if can_res == null:
		push_error("CanCase: Could not load FoodCan.tscn at '%s'" % CAN_SCENE)
		return

	var can: RigidBody3D = can_res.instantiate()

	if "_player_stats" in can:
		can._player_stats = _player_stats if _player_stats != null \
			else get_tree().get_first_node_in_group("player_stats")

	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("CanCase: No node in group 'world' found.")
		return

	world.add_child(can)
	can.global_position = spawn_point.global_position
	can.freeze = true
	can.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	can.call_deferred("_unfreeze_after_spawn")
	can.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	can_count -= 1
