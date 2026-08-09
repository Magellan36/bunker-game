extends PickupableItem
class_name CookingPot
## CookingPot.gd
## Cooking System Parts C/D/E/F. Pickupable container, holds up to CAPACITY
## individual food items (no stacking). Same physical size class as Basket,
## same "always upright while held" lock.
##
## While HELD:
##   E — if an open Stove is in range, place this pot on top of it.
##       Otherwise, stash the nearest world item in the "cookpot_storable"
##       group into the first open slot. Both handled by InteractionSystem's
##       is_cookpot_container duck-type branch (Part D) — mirrors Basket's
##       is_basket_container mechanism exactly.
## Not in the "inventory_item" group — same reasoning as Basket (too big for
## a pocket slot).

const CAPACITY: int = 3

## Diversity Bonus tiers, keyed by number of DISTINCT ingredient types
## currently in the pot. 1 unique = no bonus (same-ingredient dish — values
## just add up). 2 unique = +15%. 3 unique = +30%. Confirmed Aug 2026.
const DIVERSITY_BONUS: Dictionary = {
	1: 0.0,
	2: 0.15,
	3: 0.30,
}

@export var item_name: String = "Cooking Pot"

## Duck-typed marker InteractionSystem checks for ("is_cookpot_container" in
## held_item) — mirrors Basket's "is_basket_container".
var is_cookpot_container: bool = true

## Shelf stacking — bulky, one pot per slot, same convention as Basket.
var shelf_stack_limit: int  = 1
var shelf_item_type: String = "cooking_pot"

## CAPACITY slots. null = empty. Each filled slot is a Dictionary:
##   { "node": Node, "restore_value": float, "ingredient_key": String }
## restore_value/ingredient_key are SNAPSHOT at the moment the item is
## added — e.g. a partially-eaten Food Can's remaining value is captured
## then, not recomputed later.
var slots: Array = []

## Set by Stove.try_place_pot()/try_remove_pot(). Read every frame by
## _process() below to decide whether to accrue or decay cook progress.
var _host_stove: Node = null

## ─── Cook progress state (Part G) ──────────────────────────────────────────
const COOK_TIME_BASE:           float = 60.0
const COOK_TIME_PER_EXTRA_ITEM: float = 10.0
## Confirmed assumption — progress decays at the same rate it accrues.
const COOK_DECAY_RATE: float = 1.0

var _cook_progress: float = 0.0
var _is_cooked:     bool  = false
var _dish_value:    float = 0.0
var _dish_bonus_pct: float = 0.0
var _dish_name:     String = "Cooked Dish"

var _mesh: MeshInstance3D = null

signal item_added(slot_index: int, item: Node)
signal item_removed(slot_index: int, item: Node)

# ─── Recipe system (Aug 2026) ──────────────────────────────────────────────
## "Best fit" matching: EVERY recipe is scored against whatever's actually
## in the pot, and the highest-scoring recipe wins — even if the pot has
## extra ingredients the recipe doesn't call for. Confirmed spec:
## {Chili Pepper, Onion, Pumpkin} should still resolve to "Spicy Chili
## Sauté" (which only needs {Chili Pepper, Onion}) rather than matching
## nothing just because Pumpkin is also present.
##
## score = (2 × shared) − (1 × extras in pot not in recipe) − (1 × misses
## the recipe needs but the pot doesn't have). Highest score wins; ties
## break on more shared ingredients, then alphabetically by name
## (deterministic, no randomness). Falls back to "Cooked Dish" if nothing
## clears RECIPE_MIN_SCORE — long-term goal is for every combination to
## resolve to SOMETHING that at least loosely fits, but that's future
## recipe-list expansion, not a change to this matching logic.
const RECIPE_MIN_SCORE: float = 1.0

## Static recipe table. Each entry: { "name": String, "ingredients": Array[String] }.
## ingredients are ingredient_key values (see _get_item_ingredient_key()).
## Every ingredient set below is verified unique — no two recipes share the
## exact same set (verified by hand; if you add a new recipe, re-check this).
const RECIPES: Array[Dictionary] = [
	# ── Porridge ──
	{"name": "Potato Porridge",                "ingredients": ["produce_potato"]},
	{"name": "Pumpkin Porridge",                "ingredients": ["produce_pumpkin"]},
	{"name": "Corn & Potato Porridge",          "ingredients": ["produce_corn", "produce_potato"]},
	# ── Soup ──
	{"name": "Tomato Basil Soup",               "ingredients": ["produce_tomato", "produce_basil"]},
	{"name": "Garden Vegetable Soup",           "ingredients": ["produce_carrot", "produce_onion", "produce_potato"]},
	{"name": "Roasted Garlic Soup",             "ingredients": ["produce_garlic", "produce_onion", "produce_potato"]},
	{"name": "Canned Ration Soup",              "ingredients": ["food_can", "produce_onion"]},
	# ── Stew ──
	{"name": "Root Vegetable Stew",             "ingredients": ["produce_potato", "produce_carrot", "produce_garlic"]},
	{"name": "Hearty Garden Stew",               "ingredients": ["produce_potato", "produce_bell_pepper", "produce_onion"]},
	{"name": "Canned Ration Stew",               "ingredients": ["food_can", "produce_potato", "produce_onion"]},
	# ── Casserole ──
	{"name": "Potato, Corn & Pepper Casserole", "ingredients": ["produce_potato", "produce_corn", "produce_bell_pepper"]},
	{"name": "Garden Casserole",                "ingredients": ["produce_potato", "produce_carrot", "produce_corn"]},
	{"name": "Canned Ration Casserole",         "ingredients": ["food_can", "produce_potato", "produce_corn"]},
	# ── Sauté ──
	{"name": "Garlic Basil Sauté",              "ingredients": ["produce_garlic", "produce_basil"]},
	{"name": "Pepper & Onion Sauté",            "ingredients": ["produce_bell_pepper", "produce_onion"]},
	{"name": "Spicy Chili Sauté",                "ingredients": ["produce_chili_pepper", "produce_onion"]},
	{"name": "Tomato Basil Garlic Sauté",       "ingredients": ["produce_tomato", "produce_basil", "produce_garlic"]},
	# ── Chowder ──
	{"name": "Corn Chowder",                    "ingredients": ["produce_corn", "produce_potato", "produce_onion"]},
	{"name": "Garden Chowder",                  "ingredients": ["produce_corn", "produce_bell_pepper", "produce_carrot"]},
	# ── Gumbo ──
	{"name": "Vegetable Gumbo",                 "ingredients": ["produce_onion", "produce_bell_pepper", "produce_tomato"]},
	{"name": "Spicy Garden Gumbo",               "ingredients": ["produce_bell_pepper", "produce_chili_pepper", "produce_onion"]},
	# ── Paella ──
	{"name": "Garden Paella",                   "ingredients": ["produce_bell_pepper", "produce_tomato", "produce_garlic"]},
	# ── Baseline (early game) ──
	{"name": "Canned Ration",                   "ingredients": ["food_can"]},
	# ── Preserve / Compote (fruit-only) ──
	{"name": "Blueberry Compote",               "ingredients": ["produce_blueberry"]},
	{"name": "Strawberry Preserve",             "ingredients": ["produce_strawberry"]},
	{"name": "Mixed Berry Preserve",            "ingredients": ["produce_blueberry", "produce_strawberry"]},
	{"name": "Pumpkin Berry Compote",           "ingredients": ["produce_pumpkin", "produce_blueberry"]},
	# Pemmican intentionally has NO recipes yet — needs a meat/protein item
	# that doesn't exist in the game. Do not approximate it with berries
	# alone; leave it fully locked until a real meat item is added.
]

## Resolves the best-fit dish name for a set of DISTINCT ingredient keys
## (duplicates in `keys` don't matter — pass unique keys). Falls back to
## "Cooked Dish" if nothing scores well enough.
static func resolve_dish_name(keys: Array) -> String:
	var pot_set: Dictionary = {}
	for k in keys:
		pot_set[k] = true

	var best_name: String = "Cooked Dish"
	var best_score: float = -INF
	var best_matches: int = -1

	for recipe: Dictionary in RECIPES:
		var recipe_keys: Array = recipe["ingredients"]
		var matches: int = 0
		var misses: int  = 0
		for rk in recipe_keys:
			if pot_set.has(rk):
				matches += 1
			else:
				misses += 1
		var extras: int = 0
		for pk in pot_set.keys():
			if not recipe_keys.has(pk):
				extras += 1

		var score: float = float(matches) * 2.0 - float(extras) - float(misses)

		var better: bool = false
		if score > best_score:
			better = true
		elif score == best_score and matches > best_matches:
			better = true
		elif score == best_score and matches == best_matches and String(recipe["name"]) < best_name:
			better = true

		if better:
			best_score   = score
			best_matches = matches
			best_name    = String(recipe["name"])

	if best_score < RECIPE_MIN_SCORE:
		return "Cooked Dish"
	return best_name

func _ready() -> void:
	super._ready()
	add_to_group("interactable")   ## so get_interact_prompt() (filling display) shows while nearby-not-held
	add_to_group("cooking_pot")    ## so food items can find this pot via find_nearest_open_pot()
	slots.resize(CAPACITY)
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return item_name

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % item_name

func get_interact_prompt() -> String:
	if _is_cooked:
		if _host_stove != null:
			return ""
		return "DONE  —  [E] Take Dish  (%s, %.1f Filling)" % [_dish_name, _dish_value]
	var totals: Dictionary = compute_dish_totals()
	if totals["item_count"] <= 0:
		return ""
	## Live best-fit preview of what this WOULD cook into right now, even
	## before the timer finishes — same resolver _finish_cooking() uses.
	var unique_keys: Array = []
	for entry in slots:
		if entry != null and not unique_keys.has(entry["ingredient_key"]):
			unique_keys.append(entry["ingredient_key"])
	var preview_name: String = resolve_dish_name(unique_keys)
	var bonus_txt: String = "" if totals["bonus_pct"] <= 0.0 else "  (+%d%% Diversity)" % int(round(totals["bonus_pct"] * 100.0))
	var base_txt: String = "%s  —  Filling: %.1f%s" % [preview_name, totals["total"], bonus_txt]
	if _host_stove != null and _host_stove.has_method("is_cooking") and _host_stove.is_cooking():
		return "%s  —  COOKING  (%.0f/%.0fs)" % [base_txt, _cook_progress, cook_time_required()]
	return base_txt

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Same upright lock as Basket.gd — never lean/tip while carried.
	if is_held and _hold_point != null:
		global_transform.basis = Basis.IDENTITY
		angular_velocity       = Vector3.ZERO

func _process(delta: float) -> void:
	if _is_cooked:
		return   ## A completed, un-taken dish does not decay — it just waits.

	var should_progress: bool = _host_stove != null \
		and _host_stove.has_method("is_cooking") \
		and _host_stove.is_cooking() \
		and count_filled() > 0

	if should_progress:
		_cook_progress += delta
		if _cook_progress >= cook_time_required():
			_finish_cooking()
	elif _cook_progress > 0.0:
		_cook_progress = max(0.0, _cook_progress - COOK_DECAY_RATE * delta)

## Recomputed live from CURRENT contents — adding a 2nd/3rd item mid-cook
## extends the target instead of locking it in at the start of cooking.
func cook_time_required() -> float:
	var n: int = count_filled()
	if n <= 0:
		return COOK_TIME_BASE
	return COOK_TIME_BASE + COOK_TIME_PER_EXTRA_ITEM * float(n - 1)

func _finish_cooking() -> void:
	var totals: Dictionary = compute_dish_totals()
	_dish_value     = totals["total"]
	_dish_bonus_pct = totals["bonus_pct"]

	var unique_keys: Array = []
	for entry in slots:
		if entry != null and not unique_keys.has(entry["ingredient_key"]):
			unique_keys.append(entry["ingredient_key"])
	_dish_name = resolve_dish_name(unique_keys)

	for i: int in CAPACITY:
		var entry = slots[i]
		if entry != null:
			var node: Node = entry["node"]
			if is_instance_valid(node):
				node.queue_free()   ## consumed into the dish — no longer a separate item
			slots[i] = null
	_cook_progress = 0.0
	_is_cooked = true
	if _host_stove != null and _host_stove.has_method("notify_pot_contents_changed"):
		_host_stove.notify_pot_contents_changed()

func is_dish_ready() -> bool:
	return _is_cooked

## 0.0–1.0, for anything that wants a progress bar in a future pass.
func cook_progress_fraction() -> float:
	var required: float = cook_time_required()
	if required <= 0.0:
		return 0.0
	return clamp(_cook_progress / required, 0.0, 1.0)

## Called by InteractionSystem._try_take_dish() (Part G5). Clears the
## cooked state and hands back the values needed to spawn a DishItem.
## Returns {} if there's nothing ready.
func serve_dish() -> Dictionary:
	if not _is_cooked:
		return {}
	var result: Dictionary = {"value": _dish_value, "bonus_pct": _dish_bonus_pct, "name": _dish_name}
	_is_cooked      = false
	_dish_value     = 0.0
	_dish_bonus_pct = 0.0
	_dish_name      = "Cooked Dish"
	return result

# ─── Slot helpers ─────────────────────────────────────────────────────────────
func _first_empty_slot() -> int:
	for i: int in CAPACITY:
		if slots[i] == null:
			return i
	return -1

func is_full() -> bool:
	return _first_empty_slot() == -1

func count_filled() -> int:
	var n: int = 0
	for s in slots:
		if s != null:
			n += 1
	return n

func set_host_stove(stove: Node) -> void:
	_host_stove = stove

## Called by InteractionSystem when the player presses E near a
## "cookpot_storable" item while holding this pot, OR by a food item's own
## on_use() when the player presses E while holding THAT item near this pot.
func try_add_item(item: Node) -> bool:
	var slot: int = _first_empty_slot()
	if slot == -1:
		return false

	var restore: float = _get_item_restore_value(item)
	var key: String     = _get_item_ingredient_key(item)

	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector3.ZERO

	item.visible = false
	if item is RigidBody3D:
		var rb: RigidBody3D = item as RigidBody3D
		rb.freeze           = true
		rb.freeze_mode      = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer  = 0
		rb.collision_mask   = 0
		rb.linear_velocity  = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	if "is_held" in item:
		item.is_held = false
	if "_hold_point" in item:
		item._hold_point = null

	slots[slot] = {"node": item, "restore_value": restore, "ingredient_key": key}
	item_added.emit(slot, item)
	if _host_stove != null and _host_stove.has_method("notify_pot_contents_changed"):
		_host_stove.notify_pot_contents_changed()
	return true

## ─── Save/Load (Part J) ───────────────────────────────────────────────────
## Returns this pot's full cookable state as a JSON-friendly Dictionary.
## NOTE: raw ingredient scene nodes are NOT re-created on restore — only
## their restore_value/ingredient_key are preserved (everything the
## Filling/Diversity math and the icon-preview lookup actually need).
## Restored slots carry "node": null. The only method that would break on a
## null node (remove_item()) is guarded below — see its own comment.
func get_save_extra() -> Dictionary:
	var slots_out: Array = []
	for entry in slots:
		if entry == null:
			slots_out.append(null)
		else:
			slots_out.append({
				"restore_value":  entry["restore_value"],
				"ingredient_key": entry["ingredient_key"],
			})
	return {
		"slots":          slots_out,
		"cook_progress":  _cook_progress,
		"is_cooked":      _is_cooked,
		"dish_value":     _dish_value,
		"dish_bonus_pct": _dish_bonus_pct,
		"dish_name":      _dish_name,
	}

## Applies a Dictionary from get_save_extra() onto a freshly-instantiated
## pot. Called by Stove.restore_saved_state() right after try_place_pot().
func restore_saved_state(extra: Dictionary) -> void:
	var slots_in: Array = extra.get("slots", [])
	for i: int in CAPACITY:
		if i < slots_in.size() and slots_in[i] != null:
			var s: Dictionary = slots_in[i]
			slots[i] = {
				"node":           null,
				"restore_value":  float(s.get("restore_value", 0.0)),
				"ingredient_key": String(s.get("ingredient_key", "unknown")),
			}
	_cook_progress  = float(extra.get("cook_progress", 0.0))
	_is_cooked      = bool(extra.get("is_cooked", false))
	_dish_value     = float(extra.get("dish_value", 0.0))
	_dish_bonus_pct = float(extra.get("dish_bonus_pct", 0.0))
	_dish_name      = String(extra.get("dish_name", "Cooked Dish"))


## ─── Ingredient icon previews (Part K) ────────────────────────────────────
## Returns exactly 3 entries (one per CAPACITY slot, left-to-right in
## insertion order), each either null (empty slot — renders as an empty
## circle) or a small icon descriptor consumed by InteractPrompt.gd to
## render a live 3D preview, using the exact same technique BuildModeHUD's
## shop/construct menus already use.
func get_slot_icon_descriptors() -> Array:
	var out: Array = [null, null, null]
	for i: int in CAPACITY:
		var entry = slots[i]
		if entry != null:
			out[i] = _icon_descriptor_for_key(entry["ingredient_key"])
	return out

## Maps a stored ingredient_key back to a renderable icon source. Add a new
## branch here whenever a new cookable item type is added — mirrors
## _get_item_restore_value()/_get_item_ingredient_key()'s own
## "add a branch here" convention.
static func _icon_descriptor_for_key(key: String) -> Dictionary:
	if key.begins_with("produce_"):
		return {
			"is_script":    true,
			"scene":        "res://scripts/world/items/FarmProduceItem.gd",
			"produce_type": key.substr(8),   ## strip "produce_" prefix
		}
	if key == "food_can":
		## Aug 2026 fix — FoodCan.gd expects a pre-built MeshInstance3D CHILD
		## node (get_node_or_null("MeshInstance3D") in its own _ready()),
		## unlike FarmProduceItem which builds its mesh procedurally in code.
		## is_script mode instantiates a bare Script.new() with no children,
		## so FoodCan rendered as a fully invisible/empty preview before this
		## fix. Pointing at the actual scene (which has that mesh child
		## authored) instead of the script directly fixes it.
		return {"scene": "res://scenes/world/FoodCan.tscn"}
	return {}


## Pops an item back out to full physics/visibility. Nothing calls this yet
## in this pass (no CookingPotUI) — included for parity with Basket and for
## whatever consumes the pot's contents in a future "finish cooking" pass.
func remove_item(slot_idx: int) -> Node:
	if slot_idx < 0 or slot_idx >= CAPACITY:
		return null
	var entry = slots[slot_idx]
	if entry == null:
		return null
	var item: Node = entry["node"]
	if item == null or not is_instance_valid(item):
		## Restored-from-save slot — no real scene node to eject, just clear it.
		slots[slot_idx] = null
		return null
	slots[slot_idx] = null

	var world_root: Node = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	item.visible = true
	if item is RigidBody3D:
		var rb: RigidBody3D = item as RigidBody3D
		rb.freeze           = false
		rb.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.gravity_scale    = 1.0
		rb.collision_layer  = 1
		rb.collision_mask   = 1
		rb.linear_velocity  = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	item.global_position = global_position + Vector3(0.0, 0.3, 0.0)

	item_removed.emit(slot_idx, item)
	if _host_stove != null and _host_stove.has_method("notify_pot_contents_changed"):
		_host_stove.notify_pot_contents_changed()
	return item

# ─── Filling value / Diversity Bonus math (Part F) ────────────────────────────
## Sums the CURRENT contents. base_sum = raw restore values added together.
## bonus_pct comes from DIVERSITY_BONUS keyed by how many DISTINCT
## ingredient_keys are present (1/2/3). total = base_sum * (1 + bonus_pct).
func compute_dish_totals() -> Dictionary:
	var base_sum: float  = 0.0
	var keys: Dictionary  = {}
	var count: int        = 0
	for entry in slots:
		if entry != null:
			base_sum += entry["restore_value"]
			keys[entry["ingredient_key"]] = true
			count += 1
	var unique_count: int = keys.size()
	var bonus_pct: float  = DIVERSITY_BONUS.get(unique_count, 0.0) if unique_count > 0 else 0.0
	return {
		"total": base_sum * (1.0 + bonus_pct),
		"bonus_pct": bonus_pct,
		"unique_count": unique_count,
		"item_count": count,
		"base_sum": base_sum,
	}

## Simulates adding `item` WITHOUT mutating state — used by a held food
## item's get_use_prompt() to preview what the resulting dish would total.
## Returns {} if the pot is already full.
func preview_add(item: Node) -> Dictionary:
	if is_full():
		return {}
	var restore: float = _get_item_restore_value(item)
	var key: String     = _get_item_ingredient_key(item)
	var base_sum: float = restore
	var keys: Dictionary = {key: true}
	for entry in slots:
		if entry != null:
			base_sum += entry["restore_value"]
			keys[entry["ingredient_key"]] = true
	var unique_count: int = keys.size()
	var bonus_pct: float  = DIVERSITY_BONUS.get(unique_count, 0.0)
	return {"total": base_sum * (1.0 + bonus_pct), "bonus_pct": bonus_pct}

## Ingredient identity/value lookup — duck-typed since FoodCan.gd has no
## class_name. "produce_type" only exists on FarmProduceItem instances;
## "_bites_left" only exists on FoodCan instances. Add more branches here
## if/when new cookable item types are introduced.
static func _get_item_restore_value(item: Node) -> float:
	if "produce_type" in item:
		return item.FOOD_RESTORE
	if "_bites_left" in item:
		## Confirmed Aug 2026 — a partially-eaten can contributes only its
		## REMAINING value, not its original full value.
		return float(item._bites_left) * item.FOOD_PER_BITE
	return 0.0

static func _get_item_ingredient_key(item: Node) -> String:
	if "produce_type" in item:
		return "produce_%s" % item.produce_type
	if "_bites_left" in item:
		return "food_can"   ## FoodCan has no species/flavor variation — always the same ingredient
	return "unknown"

# ─── Cross-system hand-off helper (used by Part E) ────────────────────────────
## Called by a food item's on_use() immediately after pot.try_add_item(self)
## succeeds, to cleanly release it from the player's hand. Mirrors
## InteractionSystem._quick_drop()'s cleanup exactly, minus the drop-physics
## steps (the item is now living inside the pot, not world space). Same
## "reach into InteractionSystem" convention already used by
## GrowLight/HeavyConsumerTest's _get_interaction_system() for build_mode_active.
static func release_from_player_hand(tree: SceneTree, item: Node) -> void:
	var is_node: Node = _find_interaction_system(tree)
	if is_node == null or not ("held_item" in is_node):
		return
	if is_node.held_item != item:
		return
	if item.has_signal("knocked_out") and is_node.has_method("_on_item_knocked_out"):
		if item.knocked_out.is_connected(is_node._on_item_knocked_out):
			item.knocked_out.disconnect(is_node._on_item_knocked_out)
	is_node.held_item = null
	if "_held_from_slot" in is_node:
		is_node._held_from_slot = -1
	if "_is_holding_e" in is_node:
		is_node._is_holding_e = false

static func _find_interaction_system(tree: SceneTree) -> Node:
	var root: Node = tree.get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			for sub: Node in (child as Node3D).get_children():
				if sub is CharacterBody3D:
					for s2: Node in sub.get_children():
						if s2.get_script() != null and str(s2.get_script().resource_path).contains("InteractionSystem"):
							return s2
	return null

## Static helper — used by FarmProduceItem/FoodCan's on_use()/get_use_prompt()
## to find a nearby pot with room. Scans the "cooking_pot" group (works
## whether the pot is held, resting on a stove, or just sitting on the
## ground) rather than detect_area — mirrors FarmProduceItem's own existing
## _find_nearest_plantable_tray() convention.
static func find_nearest_open_pot(pos: Vector3, tree: SceneTree, search_radius: float = 2.5) -> CookingPot:
	var best: CookingPot = null
	var best_dist: float = search_radius
	for node in tree.get_nodes_in_group("cooking_pot"):
		if node is CookingPot and not (node as CookingPot).is_full():
			var d: float = (node as Node3D).global_position.distance_to(pos)
			if d <= best_dist:
				best_dist = d
				best = node as CookingPot
	return best

# ─── Placeholder mesh ─────────────────────────────────────────────────────────
## Basic stock-pot silhouette: wide short cylinder body with an indented
## top opening, plus a darker rim ring and two small side handles. Same
## width class as Basket (top_radius 0.28).
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var body: CylinderMesh = CylinderMesh.new()
	body.top_radius    = 0.28
	body.bottom_radius = 0.26
	body.height        = 0.30
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.15, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.63, 0.65, 1.0)   ## brushed steel
	mat.metallic     = 0.75
	mat.roughness    = 0.35
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Rim ring — thin darker disc near the top edge, reads as the pot's lid line
	var rim_mi: MeshInstance3D = MeshInstance3D.new()
	var rim: CylinderMesh = CylinderMesh.new()
	rim.top_radius    = 0.285
	rim.bottom_radius = 0.285
	rim.height        = 0.02
	rim_mi.mesh = rim
	rim_mi.position = Vector3(0.0, 0.29, 0.0)
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.35, 0.36, 0.38, 1.0)
	rim_mat.metallic     = 0.60
	rim_mat.roughness    = 0.45
	rim_mi.set_surface_override_material(0, rim_mat)
	add_child(rim_mi)

	## Top indentation — deep cavity so the pot reads as open/hollow in-game.
	var cavity_mi: MeshInstance3D = MeshInstance3D.new()
	var cavity: CylinderMesh = CylinderMesh.new()
	cavity.top_radius    = 0.24
	cavity.bottom_radius = 0.22
	cavity.height        = 0.22
	cavity_mi.mesh = cavity
	cavity_mi.position = Vector3(0.0, 0.19, 0.0)
	var cavity_mat: StandardMaterial3D = StandardMaterial3D.new()
	cavity_mat.albedo_color = Color(0.09, 0.10, 0.11, 1.0)
	cavity_mat.metallic     = 0.40
	cavity_mat.roughness    = 0.78
	cavity_mi.set_surface_override_material(0, cavity_mat)
	add_child(cavity_mi)

	## Inner lip around the cavity to reinforce the rolled pot edge look.
	var inner_lip_mi: MeshInstance3D = MeshInstance3D.new()
	var inner_lip: TorusMesh = TorusMesh.new()
	inner_lip.inner_radius = 0.22
	inner_lip.outer_radius = 0.245
	inner_lip.rings = 22
	inner_lip.ring_segments = 10
	inner_lip_mi.mesh = inner_lip
	inner_lip_mi.position = Vector3(0.0, 0.286, 0.0)
	inner_lip_mi.set_surface_override_material(0, rim_mat)
	add_child(inner_lip_mi)

	## Two handle nubs, opposite sides
	for side in [-1.0, 1.0]:
		var handle_mi: MeshInstance3D = MeshInstance3D.new()
		var handle: BoxMesh = BoxMesh.new()
		handle.size = Vector3(0.05, 0.03, 0.03)
		handle_mi.mesh = handle
		handle_mi.position = Vector3(side * 0.31, 0.20, 0.0)
		handle_mi.set_surface_override_material(0, rim_mat)
		add_child(handle_mi)

	## Real collision shape on the RigidBody3D itself — matches Basket's
	## documented reasoning (a nested MeshInstance3D.create_trimesh_collision()
	## would leave this body with no collider and it would fall through the floor).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.28
	cyl_shape.height = 0.30
	shape.shape = cyl_shape
	shape.position = _mesh.position
	add_child(shape)
