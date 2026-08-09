extends PickupableItem
## CanCase.gd
## A case of food cans (visual model: 12 cans, 4×3 layout in VisualRoot).
## Pickupable and carriable like a crate.
## While PLACED: press E to eject one can from the case.
## While HELD:   E does nothing (interact blocked while carrying).
## Each ejection also hides one visible can mesh under VisualRoot so the case
## model visually empties out in sync with can_count — see _hide_next_can_visual().

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Can Case"
@export var can_count: int     = 12   ## Matches the 12 visible Can_01..Can_12 nodes in CanCase.tscn

## Shelf stacking — 2 cases stack vertically per slot (Aug 2026: was 4 lying
## flat in a 2×2 grid; now stands upright, one case on top of another)
var shelf_stack_limit: int   = 2
var shelf_item_type: String  = "can_case"

const CAN_SCENE: String = "res://scenes/world/FoodCan.tscn"
const VISUAL_CAN_PREFIX: String = "Can_"   ## VisualRoot child name prefix, e.g. "Can_01"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor — sets where cans eject from.
@onready var spawn_point: Node3D = $SpawnPoint
@onready var visual_root: Node3D = get_node_or_null("VisualRoot")

var _player_stats: Node = null  ## Injected by MainWorld
var _can_visuals: Array[Node3D] = []   ## Populated in _ready(), depleted highest-numbered-first

func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)
	_collect_can_visuals()

## Builds _can_visuals in ascending name order (Can_01 .. Can_12) from VisualRoot's
## children so _hide_next_can_visual() can pop from the end (Can_12 hidden first).
func _collect_can_visuals() -> void:
	_can_visuals.clear()
	if visual_root == null:
		push_warning("CanCase: no 'VisualRoot' node found — visual can depletion disabled.")
		return
	var found: Array[Node3D] = []
	for child in visual_root.get_children():
		if child is Node3D and String(child.name).begins_with(VISUAL_CAN_PREFIX):
			found.append(child)
	found.sort_custom(func(a, b): return String(a.name) < String(b.name))
	_can_visuals = found

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

## Aug 2026 — same gap as TestCrate.gd — see that file's comment.
func get_display_name() -> String:
	return item_name

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
	can.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	can_count -= 1
	_hide_next_can_visual()

## Hides the next remaining visible can mesh (highest-numbered first) so the
## case model visually empties in sync with can_count. Safe no-op once
## _can_visuals is empty (e.g. can_count configured higher than 12 elsewhere).
func _hide_next_can_visual() -> void:
	if _can_visuals.is_empty():
		return
	var next_can: Node3D = _can_visuals.pop_back()
	next_can.visible = false