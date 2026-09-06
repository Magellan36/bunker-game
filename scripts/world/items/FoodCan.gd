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
const CAN_MODEL_PATH_FULL:  String = "res://assets/models/can.glb"
const CAN_MODEL_PATH_EMPTY: String = "res://assets/models/can-empty.glb"
const CAN_MODEL_SCALE: Vector3 = Vector3(0.2667, 0.3750, 0.2667)

var _model_node: Node3D = null   ## Currently-instanced visual (full or empty variant)

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	add_to_group("cookpot_storable")
	_update_can_visual()

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Food Can"

func get_inventory_hud_state() -> Dictionary:
	if _is_empty:
		return {"kind": "none"}
	return {
		"kind": "charges",
		"current": _bites_left,
		"maximum": TOTAL_BITES,
		"unit": "serving",
	}

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Can (Empty)"
	return "[F] Pick up  Food Can"

func get_trash_material() -> String:
	return "metal" if _is_empty else "organic"

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
	_update_can_visual()

# ─── Real model swap (full ↔ empty) ────────────────────────────────────────
## Swaps the visual model between the full can (assets/models/can.glb)
## and the empty can (assets/models/can-empty.glb — same geometry, label
## replaced with a grey variant of the can's own existing palette colors;
## see PLAN_foodcan_glb_swap.md for exactly how that texture was derived).
## Called once at _ready() (full) and once from _become_empty() (empty).
## FoodCan only ever transitions one-way — full to empty, never back — so
## unlike CookingPot's _update_pot_visual() this doesn't need a
## last-built-state guard against redundant reloads; it's only ever
## called twice per can, total, across its whole lifetime.
func _update_can_visual() -> void:
	if _model_node != null and is_instance_valid(_model_node):
		_model_node.queue_free()
		_model_node = null

	var path: String = CAN_MODEL_PATH_EMPTY if _is_empty else CAN_MODEL_PATH_FULL
	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("FoodCan.gd: model missing at %s — falling back to no visual mesh" % path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return
	model.position = Vector3.ZERO
	model.scale    = CAN_MODEL_SCALE
	_recenter_glb_mesh(model)
	_strip_model_collision(model)
	add_child(model)
	_model_node = model

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model. Duplicated per-file, matching the existing
## Table.gd/Chair.gd/BuildStation.gd/CookingPot.gd convention.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node — see Table.gd's identical helper for the full
## explanation. can.glb/can-empty.glb's source nodes have NO baked
## translation (confirmed via direct inspection), so this is a defensive
## no-op here, not a required fix — kept for consistency with every other
## model-load site in this codebase.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false
