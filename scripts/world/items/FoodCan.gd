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
	add_to_group("basket_storable")
	add_to_group("cookpot_storable")
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
		return ""   ## No use prompt when empty — nothing left to eat or cook
	var pot: CookingPot = CookingPot.find_nearest_open_pot(global_position, get_tree())
	if pot != null:
		var preview: Dictionary = pot.preview_add(self)
		if not preview.is_empty():
			var bonus_txt: String = "" if preview["bonus_pct"] <= 0.0 else "  (+%d%% Diversity)" % int(round(preview["bonus_pct"] * 100.0))
			return "[E] Add to Pot  →  %.1f Filling%s" % [preview["total"], bonus_txt]
	return "[E] Eat  (%d/%d)" % [_bites_left, TOTAL_BITES]

# ─── Use / Eat / Add to Pot ─────────────────────────────────────────────────
func on_use() -> void:
	if _is_empty:
		return

	var pot: CookingPot = CookingPot.find_nearest_open_pot(global_position, get_tree())
	if pot != null:
		if pot.try_add_item(self):
			CookingPot.release_from_player_hand(get_tree(), self)
			return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FoodCan: _player_stats not found.")
		return

	_player_stats.replenish_food(take_bite())

## Deducts one bite and returns the food it restores. Shared mutation for
## player + NPCs (NPC Pass 2, Part 3).
func take_bite() -> float:
	if _is_empty or _bites_left <= 0:
		return 0.0
	_bites_left -= 1
	charge_changed.emit()
	if _bites_left <= 0:
		_become_empty()
	return FOOD_PER_BITE

func has_bites_left() -> bool:
	return not _is_empty and _bites_left > 0

## Aug 2026 — Cleaning's generic trash convention (see JobBoard._is_trash_item()'s
## own comment for the two-mechanism contract this satisfies). An empty
## can persists as the same node rather than spawning a separate "empty"
## item, so this is a live state check, not a one-time group tag.
func is_trash() -> bool:
	return not has_bites_left()

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
