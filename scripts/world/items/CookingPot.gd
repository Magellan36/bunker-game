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
var _dish_hydration: float = 0.0
var _dish_name:     String = "Cooked Dish"

const POT_MODEL_PATH_EMPTY:  String = "res://assets/models/pot.glb"
const POT_MODEL_PATH_STEW_1: String = "res://assets/models/pot-stew-1.glb"
const POT_MODEL_PATH_STEW_2: String = "res://assets/models/pot-stew-2.glb"
const POT_MODEL_PATH_STEW_3: String = "res://assets/models/pot-stew-3.glb"
const POT_MODEL_SCALE: Vector3 = Vector3(0.8315, 0.8315, 0.8315)

var _mesh: MeshInstance3D = null
var _model_node: Node3D = null
## Last count_filled() the visual was actually built for. -1 = not built
## yet. Lets _update_pot_visual() skip a needless reload when called after
## something that doesn't change the fill count (e.g. a save/load restore
## that lands on the same count).
var _visual_state: int = -1

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

## Water restores HYDRATION (a completely separate stat from every other
## ingredient's hunger-restoring Filling value), so it deliberately
## contributes only a SMALL amount here — its real role is as a
## recipe-enabling ingredient (broths/soups/stews), not a calorie source.
## Scales with how full the bottle actually is, same "remaining value only"
## convention already established for Food Cans. Confirmed Aug 2026.
const WATER_COOK_VALUE: float = 5.0

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
	{"name": "Boiled Water",                    "ingredients": ["water_bottle"]},
	# ── Preserve / Compote (fruit-only) ──
	{"name": "Blueberry Compote",               "ingredients": ["produce_blueberry"]},
	{"name": "Strawberry Preserve",             "ingredients": ["produce_strawberry"]},
	{"name": "Mixed Berry Preserve",            "ingredients": ["produce_blueberry", "produce_strawberry"]},
	{"name": "Pumpkin Berry Compote",           "ingredients": ["produce_pumpkin", "produce_blueberry"]},
	{"name": "Strawberry Pumpkin Preserve",     "ingredients": ["produce_strawberry", "produce_pumpkin"]},
	# ── Water-based additions (Aug 2026) — see design note above on why
	# water contributes a small amount rather than a large one.
	{"name": "Vegetable Broth",                 "ingredients": ["water_bottle", "produce_carrot", "produce_onion"]},
	{"name": "Clear Tomato Broth",               "ingredients": ["water_bottle", "produce_tomato"]},
	{"name": "Garlic Water Broth",               "ingredients": ["water_bottle", "produce_garlic"]},
	{"name": "Spicy Chili Broth",                "ingredients": ["water_bottle", "produce_chili_pepper"]},
	{"name": "Basil Water Broth",                "ingredients": ["water_bottle", "produce_basil"]},
	{"name": "Canned Ration Water Soup",         "ingredients": ["water_bottle", "food_can"]},
	{"name": "Water Vegetable Stew",             "ingredients": ["water_bottle", "produce_potato", "produce_bell_pepper"]},
	{"name": "Garlic Water Stew",                "ingredients": ["water_bottle", "produce_garlic", "produce_potato"]},
	{"name": "Corn Water Stew",                  "ingredients": ["water_bottle", "produce_corn", "produce_onion"]},
	{"name": "Garlic Water Chowder",             "ingredients": ["water_bottle", "produce_garlic", "produce_corn"]},
	{"name": "Carrot Water Chowder",             "ingredients": ["water_bottle", "produce_carrot", "produce_corn"]},
	{"name": "Water Garden Gumbo",               "ingredients": ["water_bottle", "produce_onion", "produce_tomato"]},
	{"name": "Spicy Water Gumbo",                "ingredients": ["water_bottle", "produce_chili_pepper", "produce_tomato"]},
	{"name": "Water Potato Porridge",            "ingredients": ["water_bottle", "produce_potato"]},
	{"name": "Water Pumpkin Porridge",           "ingredients": ["water_bottle", "produce_pumpkin"]},
	# ── Additional non-water recipes (Aug 2026) ──
	{"name": "Three Pepper Soup",                "ingredients": ["produce_bell_pepper", "produce_chili_pepper", "produce_garlic"]},
	{"name": "Chili Garden Stew",                "ingredients": ["produce_chili_pepper", "produce_tomato", "produce_onion"]},
	{"name": "Tomato Basil Casserole",           "ingredients": ["produce_tomato", "produce_basil", "produce_potato"]},
	{"name": "Spicy Pepper Casserole",           "ingredients": ["produce_bell_pepper", "produce_chili_pepper", "produce_potato"]},
	{"name": "Chili Garlic Sauté",               "ingredients": ["produce_chili_pepper", "produce_garlic"]},
	{"name": "Corn & Onion Sauté",               "ingredients": ["produce_corn", "produce_onion"]},
	{"name": "Smoky Garden Paella",              "ingredients": ["produce_bell_pepper", "produce_chili_pepper", "produce_tomato"]},
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
		_build_collision()
		_update_pot_visual()

func get_display_name() -> String:
	return item_name

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % item_name

func get_trash_material() -> String:
	return "metal"

## Always returns the "DONE — Take Dish" text regardless of whether this
## pot's own get_interact_prompt() is currently suppressing it (see below).
## Used by Stove.get_interact_prompt()'s delegation — calling
## get_interact_prompt() directly from there would return "" whenever the
## pot is hosted (that suppression exists so the POT's own candidate entry
## doesn't duplicate the STOVE's panel), which was exactly why the DONE
## prompt never appeared while the pot sat on a stove. Confirmed Aug 2026 fix.
func get_dish_ready_text() -> String:
	if not _is_cooked:
		return ""
	if _dish_hydration > 0.0:
		return "DONE  —  [E] Take Dish  (%s, %.1f Filling, %.1f Hydration)" % [_dish_name, _dish_value, _dish_hydration]
	return "DONE  —  [E] Take Dish  (%s, %.1f Filling)" % [_dish_name, _dish_value]


func get_interact_prompt() -> String:
	if _is_cooked:
		if _host_stove != null:
			return ""
		return get_dish_ready_text()
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
	## Aug 2026 — softened from an instant snap to a quick ease via
	## PickupableItem.slerp_to_upright(); see Basket.gd's own comment for
	## the full reasoning, identical here.
	if is_held and _hold_point != null:
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)

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

	## Hydration = the dish's final Filling total, scaled by how much of
	## the dish's PRE-bonus value came from water. Confirmed Aug 2026 —
	## water restores hydration, not hunger, so this is separate from (and
	## doesn't reduce) the Filling number itself.
	var water_sum: float = 0.0
	for w_entry in slots:
		if w_entry != null and w_entry["ingredient_key"] == "water_bottle":
			water_sum += w_entry["restore_value"]
	var water_fraction: float = 0.0
	if totals["base_sum"] > 0.0:
		water_fraction = water_sum / totals["base_sum"]
	_dish_hydration = _dish_value * water_fraction

	var unique_keys: Array = []
	for entry in slots:
		if entry != null and not unique_keys.has(entry["ingredient_key"]):
			unique_keys.append(entry["ingredient_key"])
	_dish_name = resolve_dish_name(unique_keys)

	## Confirmed Aug 2026 — the finished dish stays "in the pot": slot DATA
	## (ingredient_key/restore_value/charge_badge) is kept so the icon row
	## keeps showing what was used, all the way until the player actually
	## takes the dish (serve_dish() is where slots[] finally clears — see
	## below). Only lingering PRODUCE node references get freed here (they
	## were hidden inside the pot the whole time, visually "consumed" —
	## Food Can/Water Bottle ingredients never carry a node reference this
	## far, since they were emptied and ejected at ADD time instead).
	for i: int in CAPACITY:
		var entry = slots[i]
		if entry != null:
			var node: Node = entry["node"]
			if is_instance_valid(node):
				node.queue_free()
			entry["node"] = null
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
	var result: Dictionary = {
		"value":     _dish_value,
		"bonus_pct": _dish_bonus_pct,
		"name":      _dish_name,
		"hydration": _dish_hydration,
	}
	_is_cooked      = false
	_dish_value     = 0.0
	_dish_bonus_pct = 0.0
	_dish_name      = "Cooked Dish"
	_dish_hydration = 0.0
	## Confirmed Aug 2026 — the pot only actually empties once the dish is
	## taken. Before this point, slots[] intentionally stayed populated
	## (with node references already cleared in _finish_cooking()) so the
	## ingredient icons kept showing while the finished dish sat waiting to
	## be taken.
	for i: int in CAPACITY:
		slots[i] = null
	_update_pot_visual()
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

	## Confirmed Aug 2026 — an empty Food Can or Water Bottle has nothing
	## to contribute and can't be used as an ingredient. Single point of
	## enforcement here (rather than only in the callers) so ANY current or
	## future path that calls try_add_item() is covered, not just the two
	## known today (a food item's own on_use(), and the held-pot's
	## grab-nearest-item action).
	if is_item_empty(item):
		return false

	var restore: float = _get_item_restore_value(item)
	var key: String     = _get_item_ingredient_key(item)
	## Snapshotted NOW, while the live item still has its ORIGINAL
	## fill/bites state — a display-ready string like "1/2" or "67%", or ""
	## for a full/non-partial ingredient (produce always returns ""). Read
	## by get_slot_icon_descriptors() so the hover UI can show it without
	## needing the original node later (which won't exist post-cook, or
	## post-save/load restore).
	var badge: String = _get_item_charge_badge(item)

	## Confirmed Aug 2026 — a Food Can or Water Bottle used as an
	## ingredient gets EMPTIED and dropped beside the pot, exactly the same
	## state transition as normal consumption to 0%, rather than being
	## frozen and hidden inside the pot like produce. Only the abstract
	## ingredient data goes "into" the pot for these two types —
	## slots[slot]["node"] stays null for them (same shape a restored-from-
	## save slot already has).
	if ("_bites_left" in item) or ("current_fill_mL" in item):
		if item.has_method("_become_empty"):
			item._become_empty()
		elif "current_fill_mL" in item:
			item.current_fill_mL = 0.0
			if item.has_method("_update_empty_tint"):
				item._update_empty_tint()
		_eject_emptied_container(item)
		slots[slot] = {"node": null, "restore_value": restore, "ingredient_key": key, "charge_badge": badge}
		item_added.emit(slot, item)
		if _host_stove != null and _host_stove.has_method("notify_pot_contents_changed"):
			_host_stove.notify_pot_contents_changed()
		_update_pot_visual()
		return true

	## Produce (and anything else with no empty concept) — unchanged:
	## freeze, hide, reparent as a child of the pot.
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

	slots[slot] = {"node": item, "restore_value": restore, "ingredient_key": key, "charge_badge": badge}
	item_added.emit(slot, item)
	if _host_stove != null and _host_stove.has_method("notify_pot_contents_changed"):
		_host_stove.notify_pot_contents_changed()
	_update_pot_visual()
	return true

## Drops a just-emptied Food Can / Water Bottle into the world right next
## to the pot, fully interactable (normal physics, pickup-able) — NOT
## reparented into the pot itself, unlike produce. Mirrors remove_item()'s
## existing "return to world" logic.
func _eject_emptied_container(item: Node) -> void:
	var world_root: Node = get_tree().get_root()
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	world_root.add_child(item)
	item.global_position = global_position + Vector3(0.2, 0.3, 0.2)
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
	if "is_held" in item:
		item.is_held = false
	if "_hold_point" in item:
		item._hold_point = null

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
				"charge_badge":   entry.get("charge_badge", ""),
			})
	return {
		"slots":          slots_out,
		"cook_progress":  _cook_progress,
		"is_cooked":      _is_cooked,
		"dish_value":     _dish_value,
		"dish_bonus_pct": _dish_bonus_pct,
		"dish_name":      _dish_name,
		"dish_hydration": _dish_hydration,
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
				"charge_badge":   String(s.get("charge_badge", "")),
			}
	_cook_progress  = float(extra.get("cook_progress", 0.0))
	_is_cooked      = bool(extra.get("is_cooked", false))
	_dish_value     = float(extra.get("dish_value", 0.0))
	_dish_bonus_pct = float(extra.get("dish_bonus_pct", 0.0))
	_dish_name      = String(extra.get("dish_name", "Cooked Dish"))
	_dish_hydration = float(extra.get("dish_hydration", 0.0))
	_update_pot_visual()


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
			var desc: Dictionary = _icon_descriptor_for_key(entry["ingredient_key"])
			if not desc.is_empty():
				var badge: String = String(entry.get("charge_badge", ""))
				if not badge.is_empty():
					desc["badge_text"] = badge
			out[i] = desc
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
	if key == "water_bottle":
		## Same reasoning as food_can above — WaterBottle.gd also expects a
		## pre-built MeshInstance3D child from its scene, not a procedural
		## mesh, so point at res://scenes/world/WaterBottle.tscn (confirmed
		## to exist) rather than is_script mode.
		return {"scene": "res://scenes/world/WaterBottle.tscn"}
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
	_update_pot_visual()
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
	if "current_fill_mL" in item:
		## Water contributes a small, fill-proportional amount — see
		## WATER_COOK_VALUE's own comment for why. A near-empty bottle
		## contributes almost nothing, same "remaining value only"
		## convention as Food Cans.
		var frac: float = clampf(float(item.current_fill_mL) / float(item.MAX_FILL_ML), 0.0, 1.0)
		return WATER_COOK_VALUE * frac
	return 0.0

static func _get_item_ingredient_key(item: Node) -> String:
	if "produce_type" in item:
		return "produce_%s" % item.produce_type
	if "_bites_left" in item:
		return "food_can"   ## FoodCan has no species/flavor variation — always the same ingredient
	if "current_fill_mL" in item:
		return "water_bottle"   ## WaterBottle has no species/flavor variation either
	return "unknown"

## Public — used by InteractionSystem to filter empty items OUT of a
## nearest-item search (so it finds the next ELIGIBLE item instead of just
## failing), and internally by try_add_item() as the actual enforcement
## point. Handles both current shapes: FoodCan's "_is_empty" is a plain
## bool VAR, WaterBottle's is a computed FUNC — duck-type both.
static func is_item_empty(item: Node) -> bool:
	if item.has_method("_is_empty"):
		return item._is_empty()
	if "_is_empty" in item:
		return bool(item._is_empty)
	return false   ## produce and anything else has no empty concept

## Computed ONCE at insertion time (see try_add_item()) while the live item
## node is still around — a ready-to-display string, or "" for a
## full/non-partial ingredient (nothing shown in that case). Food Cans show
## as a discrete fraction ("1/2") since they only ever have 2 states;
## Water Bottles show as a percentage ("67%") since fill is continuous.
static func _get_item_charge_badge(item: Node) -> String:
	if "_bites_left" in item:
		var total: int = int(item.TOTAL_BITES) if "TOTAL_BITES" in item else 2
		var left: int  = int(item._bites_left)
		if left >= total:
			return ""   ## full — no badge needed
		return "%d/%d" % [left, total]
	if "current_fill_mL" in item:
		var pct: int = int(round(100.0 * float(item.current_fill_mL) / float(item.MAX_FILL_ML)))
		if pct >= 100:
			return ""   ## full — no badge needed
		return "%d%%" % pct
	return ""

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

# ─── Real model + collision ────────────────────────────────────────────────
## Collision is built ONCE, independent of fill state — same physical size
## the placeholder used, unchanged: CylinderShape3D radius 0.28 / height
## 0.30. Matches Basket's documented reasoning for using a direct
## CollisionShape3D on this RigidBody3D rather than
## MeshInstance3D.create_trimesh_collision() (which would leave this body
## with no collider at all once the mesh is a swappable child instead of a
## permanent one).
func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.28
	cyl_shape.height = 0.30
	shape.shape = cyl_shape
	shape.position = Vector3(0.0, 0.15, 0.0)
	add_child(shape)

## Picks and (re)builds the pot's visual model to match the CURRENT
## count_filled() — empty / 1 / 2 / 3 ingredients, each a distinct GLB with
## the stew liquid at a different height (see PLAN_cookingpot_glb_swap.md
## for how the 3 stew levels were generated). No-ops if the visual is
## already correct for the current count, so callers can call this freely
## after every state change without worrying about redundant reloads.
func _update_pot_visual() -> void:
	var count: int = clampi(count_filled(), 0, CAPACITY)
	if count == _visual_state:
		return
	_visual_state = count

	if _model_node != null and is_instance_valid(_model_node):
		_model_node.queue_free()
		_model_node = null

	var path: String = POT_MODEL_PATH_EMPTY
	if count == 1:
		path = POT_MODEL_PATH_STEW_1
	elif count == 2:
		path = POT_MODEL_PATH_STEW_2
	elif count >= 3:
		path = POT_MODEL_PATH_STEW_3

	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("CookingPot.gd: model missing at %s — falling back to no visual mesh" % path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return
	model.position = Vector3.ZERO
	model.scale    = POT_MODEL_SCALE
	_recenter_glb_mesh(model)
	_strip_model_collision(model)
	add_child(model)
	_model_node = model

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model. Duplicated per-file, matching the existing
## Table.gd/Chair.gd/BuildStation.gd convention.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node — see Table.gd's identical helper for the full
## explanation. pot.glb/pot-stew-*.glb's source nodes have NO baked
## translation (confirmed via direct inspection, unlike table01.glb/
## chair01.glb), so this is a defensive no-op here, not a required fix —
## kept for consistency with every other model-load site in this codebase.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false
