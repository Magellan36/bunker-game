extends PickupableItem
class_name DishItem
## DishItem.gd
## Cooking System Part G. The finished product of a completed cook — created
## by InteractionSystem._try_take_dish() (Part G4) when the player presses
## [E] on a pot with a ready dish. One-bite consumable, eaten like
## FarmProduceItem (no partial-bite tracking like FoodCan). Cannot be
## re-cooked — not in "cookpot_storable" — but can be stored in a Basket.

var fill_value:      float  = 0.0
var bonus_pct:       float  = 0.0
var dish_name:       String = "Cooked Dish"
var hydration_value: float  = 0.0

const MODEL_SCALE: Vector3      = Vector3(0.4261, 0.4261, 0.4261)   ## plate-dinner / plate-sauerkraut / skewer / skewer-vegetables
const BOWL_SOUP_SCALE: Vector3  = Vector3(0.7024, 0.7024, 0.7024)   ## bowl-soup.glb — separate asset pack, computed from its own dimensions

const MODEL_BOWL_SOUP: String = "res://assets/models/bowl-soup.glb"

## Checked FIRST, overrides the water/no-water pool entirely — a dish
## whose name contains any of these (case-sensitive, matches the actual
## recipe-name capitalization used throughout CookingPot.gd's recipe
## table) always uses bowl-soup.glb, no randomness. Several Soup-named
## recipes (e.g. "Tomato Basil Soup") don't use a water_bottle ingredient
## and so have hydration_value == 0.0 — name is the correct signal here,
## not hydration, which is why this check happens before and independent
## of the hydration-based pool below.
const SOUP_LIKE_NAME_KEYWORDS: Array[String] = ["Soup", "Broth", "Stew", "Chowder"]

## Both non-override pools include the two plates — skewers/bowl-soup are
## ADDITIONAL options layered on top, not replacement sets.
const MODELS_WITH_WATER: Array[String] = [
	"res://assets/models/plate-dinner.glb",
	"res://assets/models/plate-sauerkraut.glb",
	"res://assets/models/bowl-soup.glb",
]
const MODELS_WITHOUT_WATER: Array[String] = [
	"res://assets/models/plate-dinner.glb",
	"res://assets/models/plate-sauerkraut.glb",
	"res://assets/models/skewer.glb",
	"res://assets/models/skewer-vegetables.glb",
]

var _mesh: MeshInstance3D = null
var _model_node: Node3D = null
var _player_stats: Node = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	_build_collision()
	_build_dish_visual()

## Picks and loads this dish's visual model, once, at spawn. Soup-like
## names (see SOUP_LIKE_NAME_KEYWORDS) always win regardless of hydration
## — checked first. Otherwise falls through to the water/no-water pool.
func _build_dish_visual() -> void:
	var path: String
	var scale: Vector3

	var is_soup_like: bool = false
	for kw: String in SOUP_LIKE_NAME_KEYWORDS:
		if dish_name.contains(kw):
			is_soup_like = true
			break

	if is_soup_like:
		path  = MODEL_BOWL_SOUP
		scale = BOWL_SOUP_SCALE
	else:
		var pool: Array[String] = MODELS_WITH_WATER if hydration_value > 0.0 else MODELS_WITHOUT_WATER
		path  = pool[randi() % pool.size()]
		scale = BOWL_SOUP_SCALE if path == MODEL_BOWL_SOUP else MODEL_SCALE

	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("DishItem.gd: model missing at %s — falling back to no visual mesh" % path)
		return
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		return
	model.position = Vector3.ZERO
	model.scale    = scale
	_recenter_glb_mesh(model)
	_strip_model_collision(model)
	add_child(model)
	_model_node = model

func get_display_name() -> String:
	return dish_name

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % dish_name

func get_trash_material() -> String:
	return "organic"

func get_use_prompt() -> String:
	if hydration_value > 0.0:
		return "[E] Eat  %s  (%.1f Filling, %.1f Hydration)" % [dish_name, fill_value, hydration_value]
	return "[E] Eat  %s  (%.1f)" % [dish_name, fill_value]

func on_use() -> void:
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("DishItem: _player_stats not found.")
		return
	## Read BEFORE consume_as_food() — it frees this node.
	var hydration: float = hydration_value
	_player_stats.replenish_food(consume_as_food())
	if hydration > 0.0 and _player_stats.has_method("replenish_water"):
		_player_stats.replenish_water(hydration)

## Consumes this dish (frees the node) and returns the food restored.
## Shared mutation for player + NPCs (NPC Pass 2, Part 3) — return type/
## contract UNCHANGED (still a plain float, hunger only) since NPC.gd and
## NPCItemUser.gd both call this directly and only use it for hunger; NPCs
## do not receive hydration from eating a dish in this pass.
##
## Aug 2026 fix: removed an erroneous "* (1.0 + bonus_pct)" — fill_value is
## already the FINAL post-Diversity-Bonus total (computed once in
## CookingPot._finish_cooking() via compute_dish_totals()["total"]), so
## re-applying the bonus here was double-counting it for every dish eaten,
## player and NPC alike.
func consume_as_food() -> float:
	queue_free()
	return fill_value

## Collision is built once, independent of which of the 4 models got
## randomly picked — same physical size the placeholder used, unchanged:
## SphereShape3D radius 0.12 at (0, 0.05, 0).
func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.12
	shape.shape = sph
	shape.position = Vector3(0.0, 0.05, 0.0)
	add_child(shape)

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model. Duplicated per-file, matching the existing
## Table.gd/Chair.gd/BuildStation.gd/CookingPot.gd/FoodCan.gd convention.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node — see Table.gd's identical helper for the full
## explanation. Finds the FIRST MeshInstance3D and zeros only its local
## position, then stops — deliberately does NOT recurse further once
## found. All 5 of this file's models have an identity-transform root
## node already (no wrapper bug to fix, confirmed via direct inspection),
## so this is inert here — kept for consistency. IMPORTANT: skewer.glb /
## skewer-vegetables.glb are multi-part models (a stick node with
## "meat"/"vegetables" children, each individually positioned by the
## artist) — the stop-after-first-match behavior is what keeps this safe
## to call on them; a version that recursed into every MeshInstance3D
## instead would zero out those children's legitimate relative positions
## and visibly break the models. Do not "improve" this into a
## recurse-and-zero-everything helper.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false