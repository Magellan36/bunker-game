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
## Sep 2026 — swapped to the hand-made Tinkercad can models (food can / food
## can empty). Same 0.0228 uniform scale as the CanCase's 12 overlay cans, so
## an ejected can matches the cans visible in the case exactly (dia 0.114,
## height 0.172). The GLB's mesh children carry a baked 90° X rotation from
## the OBJ→GLB export — _update_can_visual() adds a -90° X counter-rotation
## via CAN_MODEL_BASE_ROT so the can stands upright (height on Y).
const CAN_MODEL_PATH_FULL:  String = "res://assets/models/food_can_model.glb"
const CAN_MODEL_PATH_EMPTY: String = "res://assets/models/food_can_empty_model.glb"
const CAN_MODEL_SCALE: Vector3 = Vector3(0.0228, 0.0228, 0.0228)
## Counter-rotate the baked 90° X export rotation (see header).
const CAN_MODEL_BASE_ROT: Vector3 = Vector3(-90.0, 0.0, 0.0)
## Scaled model heights (measured): the full can is 0.172 tall, the empty can
## (open lid) is ~0.214. Used by _update_collision_for_model() to keep the
## collision cylinder matching whichever model is currently shown.
const CAN_HEIGHT_FULL:  float = 0.172
const CAN_HEIGHT_EMPTY: float = 0.214

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
## Swaps the visual model between the full hand-made can
## (assets/models/food_can_model.glb) and the empty variant
## (assets/models/food_can_empty_model.glb — taller, open lid). Same 0.0228
## uniform scale as the CanCase's 12 overlay cans, so an ejected can matches
## the cans in the case exactly. Called once at _ready() (full) and once from
## _become_empty() (empty). FoodCan only ever transitions one-way — full to
## empty, never back — so unlike CookingPot's _update_pot_visual() this
## doesn't need a last-built-state guard against redundant reloads; it's only
## ever called twice per can, total, across its whole lifetime.
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
	model.rotation_degrees = CAN_MODEL_BASE_ROT
	_recenter_glb_mesh(model)
	_strip_model_collision(model)
	add_child(model)
	_model_node = model
	## Sep 2026 — keep the collision shape in sync with the visual model: the
	## empty can (open lid) is taller than the full can, so the fixed-height
	## collision from the .tscn would leave the top of an empty can
	## uncollidable. Re-tune it here to match whichever model is current.
	_update_collision_for_model()

## Tunes the CollisionShape3D's cylinder to the current visual model's height
## (full 0.172, empty ~0.214). Position is nudged so the cylinder's base stays
## at the same point the model's base renders at.
func _update_collision_for_model() -> void:
	var col_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape == null or not (col_shape.shape is CylinderShape3D):
		return
	var cyl: CylinderShape3D = col_shape.shape as CylinderShape3D
	cyl.height = CAN_HEIGHT_EMPTY if _is_empty else CAN_HEIGHT_FULL
	## The cylinder is centered on the shape's position; the visual model's
	## base sits at the same origin, so shift the shape up by half its height
	## to keep the base aligned (mirrors the .tscn's authored offset for full).
	col_shape.position = Vector3(0.0, cyl.height * 0.5, 0.0)

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
## explanation. The food can GLBs' mesh children carry a baked 90° X
## rotation from the OBJ→GLB export (cancelled by CAN_MODEL_BASE_ROT's
## -90° X on the model node), and their translation is zero — so this is a
## defensive no-op here, not a required fix — kept for consistency with
## every other model-load site in this codebase.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false
