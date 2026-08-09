extends PickupableItem
## WaterCase.gd
## A case of 24 water bottles (visual model: 24 Bottle_01..Bottle_24 nodes
## in VisualRoot). Can be picked up and carried like a crate.
## While PLACED: press E to eject one bottle from the case.
## While HELD:   E does nothing (interact is blocked when carried).
## Each ejection also hides one visible bottle mesh under VisualRoot so the
## case model visually empties out in sync with bottle_count — see
## _hide_next_bottle_visual().

# ─── Exports ─────────────────────────────────────────────────────────────────
@export var item_name: String  = "Water Case"
@export var bottle_count: int  = 24   ## Matches the 24 visible Bottle_01..Bottle_24 nodes in WaterCase.tscn

## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
var shelf_item_type: String  = "water_case"

## Preloaded bottle scene — must exist at this path
const BOTTLE_SCENE: String = "res://scenes/world/WaterBottle.tscn"
const VISUAL_BOTTLE_PREFIX: String = "Bottle_"   ## VisualRoot child name prefix, e.g. "Bottle_01"

# ─── Node refs ───────────────────────────────────────────────────────────────
## Add a Node3D child named "SpawnPoint" in the editor; positions where bottles eject from.
@onready var spawn_point: Node3D = $SpawnPoint
@onready var visual_root: Node3D = get_node_or_null("VisualRoot")

var _player_stats: Node = null  ## Injected by MainWorld (scans "interactable" group)
var _bottle_visuals: Array[Node3D] = []   ## Populated in _ready(), depleted highest-numbered-first
var _cap_visuals: Array[Node3D] = []      ## Matching Cap_XX nodes, hidden alongside bottles

func _ready() -> void:
	super._ready()
	add_to_group("interactable")
	## Scale down by 1/4
	scale = Vector3(0.75, 0.75, 0.75)
	_collect_bottle_visuals()

## Builds _bottle_visuals in ascending name order (Bottle_01 .. Bottle_24) from
## VisualRoot's children so _hide_next_bottle_visual() can pop from the end
## (Bottle_24 hidden first). Also collects matching Cap_XX nodes so caps hide
## with their bottles.
func _collect_bottle_visuals() -> void:
	_bottle_visuals.clear()
	_cap_visuals.clear()
	if visual_root == null:
		push_warning("WaterCase: no 'VisualRoot' node found — visual bottle depletion disabled.")
		return
	var found_bottles: Array[Node3D] = []
	var found_caps: Array[Node3D] = []
	for child in visual_root.get_children():
		if child is Node3D and String(child.name).begins_with(VISUAL_BOTTLE_PREFIX):
			found_bottles.append(child)
		elif child is Node3D and String(child.name).begins_with("Cap_"):
			found_caps.append(child)
	found_bottles.sort_custom(func(a, b): return String(a.name) < String(b.name))
	found_caps.sort_custom(func(a, b): return String(a.name) < String(b.name))
	_bottle_visuals = found_bottles
	_cap_visuals = found_caps

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
	bottle.linear_velocity = -global_transform.basis.z * 2.5 + Vector3(0, 1.5, 0)

	bottle_count -= 1
	_hide_next_bottle_visual()

## Hides the next remaining visible bottle mesh (highest-numbered first) so
## the case model visually empties in sync with bottle_count. Also hides the
## matching Cap_XX node. Safe no-op once visuals are empty.
func _hide_next_bottle_visual() -> void:
	if _bottle_visuals.is_empty():
		return
	var next_bottle: Node3D = _bottle_visuals.pop_back()
	next_bottle.visible = false
	if not _cap_visuals.is_empty():
		var next_cap: Node3D = _cap_visuals.pop_back()
		next_cap.visible = false