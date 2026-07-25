extends PickupableItem
## FoodCan.gd
## Pickupable consumable. Two bites (E twice) — each restores 12.5% hunger.
## After 2 uses becomes an empty can (kept in world, no queue_free).

# ─── Config ───────────────────────────────────────────────────────────────────
const FOOD_PER_BITE: float  = 12.5   ## 25 / 2 — half the can per eat
const TOTAL_BITES: int      = 2

## Shelf stacking — 6 cans per slot, stand upright in two rows of 3
var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "food_can"

# ─── State ───────────────────────────────────────────────────────────────────
var _player_stats: Node     = null
var _bites_left: int    = TOTAL_BITES   ## Counts down 2 → 1 → 0 (empty)
var _is_empty: bool     = false

# ─── Node refs ────────────────────────────────────────────────────────────────
var _mesh: MeshInstance3D = null   ## For tinting when empty

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	_mesh = get_node_or_null("MeshInstance3D")

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Food Can"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Can (Empty)"
	return "[F] Pick up  Food Can"

func get_use_prompt() -> String:
	if _is_empty:
		return ""   ## No use prompt when empty — nothing left to eat
	return "[E] Eat  (%d/%d)" % [_bites_left, TOTAL_BITES]

# ─── Use / Eat ────────────────────────────────────────────────────────────────
func on_use() -> void:
	if _is_empty:
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FoodCan: _player_stats not found.")
		return

	_player_stats.replenish_food(FOOD_PER_BITE)
	_bites_left -= 1
	charge_changed.emit()

	if _bites_left <= 0:
		_become_empty()

# ─── Empty state ──────────────────────────────────────────────────────────────
func _become_empty() -> void:
	_is_empty   = true
	_bites_left = 0

	# Tint mesh to washed-out grey — signals empty to the player
	if _mesh != null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.55, 0.55, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mesh.material_override = mat
