extends PickupableItem
class_name FarmProduceItem
## FarmProduceItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §7. ONE script for both tomato/onion produce via
## export var. 1-charge, fully consumed in one on_use() call, no partial-
## bite tracking like WaterBottle's continuous-mL model.
##
## Species whose produce can be planted back into a tray instead of eaten,
## in addition to being buyable as a packet. Mirrors SeedItem.gd's plant flow.
const REPLANTABLE_TYPES: Array[String] = ["potato", "onion"]

const TRAY_RANGE: float = 2.5   ## Matches SeedItem.gd's TRAY_RANGE

@export var produce_type: String = "tomato"   ## "tomato" or "onion"

## Flat hunger restore per produce item — same order of magnitude as
## FoodCan's per-bite value (12.5), used whole here since this is a single
## 1-charge item rather than a 2-bite can.
const FOOD_RESTORE: float = 20.0

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "farm_produce"   ## Shared slot for both types —
## per-instance produce_type preserved by Shelving.gd's real-node-reference
## slots, same reasoning as PurifierFilterItem/SeedItem.

var _player_stats: Node     = null
var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	add_to_group("cookpot_storable")
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return PlantDatabase.get_display_name(produce_type)

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

func _find_nearest_plantable_tray() -> FarmingTray:
	if not (produce_type in REPLANTABLE_TYPES):
		return null
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_plantable_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		return "[E] Plant %s" % get_display_name()
	return "[E] Eat  %s" % get_display_name()

## Fully consumed in one call — no charge tracking, no empty-state.
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		if tray.plant_first_open_cell(produce_type):
			queue_free()
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FarmProduceItem: _player_stats not found.")
		return
	_player_stats.replenish_food(FOOD_RESTORE)
	queue_free()

## Small SphereMesh — red matte for tomato, pearl/off-white glossier for onion
## (plan §7's exact material distinction), color/metallic/roughness pulled
## from PlantDatabase so balance stays in one config table.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.055, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = PlantDatabase.get_produce_color(produce_type)
	mat.metallic     = PlantDatabase.get_produce_metallic(produce_type)
	mat.roughness    = PlantDatabase.get_produce_roughness(produce_type)
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = sphere.radius
	shape.shape = sphere_shape
	shape.position = _mesh.position
	add_child(shape)

## Harvest pop-in tween constants (Polish Plan Group 3 item 8) — cosmetic only,
## no physics/gameplay effect. Scale-in overshoot mirrors WaterPurifier's
## play_clean_pulse() tween convention (create_tween, EASE_OUT/TRANS_BACK for
## the "pop" feel), just applied to the item's own scale instead of a ring.
const HARVEST_POP_START_SCALE: float = 0.1
const HARVEST_POP_DURATION:    float = 0.28

## Spawn helper — mirrors PurifierFilterItem.spawn_at()'s small-random-offset
## scatter pattern (used by FarmPlant.harvest() to spawn 2× per harvest).
static func spawn_at(parent: Node, base_pos: Vector3, type: String) -> FarmProduceItem:
	var item: FarmProduceItem = FarmProduceItem.new()
	item.produce_type = type
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset

	## Harvest pop-in (Group 3 item 8): starts tiny, scales up past full size
	## and settles — a quick "pop" so freshly-harvested produce reads clearly
	## instead of just appearing at full size.
	item.scale = Vector3.ONE * HARVEST_POP_START_SCALE
	var tween: Tween = item.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(item, "scale", Vector3.ONE, HARVEST_POP_DURATION)

	return item
