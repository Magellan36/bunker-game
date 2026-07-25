extends PickupableItem
## WaterCase.gd
## A case of 24 water bottles. Can be picked up and carried like a crate.
## While PLACED: press E to eject one bottle from the case.
## While HELD:   E does nothing (interact is blocked when carried).

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Water Case"
@export var bottle_count: int  = 24

## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
var shelf_item_type: String  = "water_case"

## Preloaded bottle scene — must exist at this path
const BOTTLE_SCENE: String = "res://scenes/world/WaterBottle.tscn"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor; positions where bottles eject from.
@onready var spawn_point: Node3D = $SpawnPoint

var _player_stats: Node = null  ## Injected by MainWorld (scans "interactable" group)

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
	if bottle_count <= 0:
		return ""
	return "[E] Take water (%d)" % bottle_count

# ─── Interact: eject a bottle — works both placed and while held ──────────────
func on_interact() -> void:
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
	bottle.freeze = true
	bottle.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	bottle.call_deferred("_unfreeze_after_spawn")
	# Eject forward and slightly upward
	bottle.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	bottle_count -= 1
