extends PickupableItem
class_name DishItem
## DishItem.gd
## Cooking System Part G. The finished product of a completed cook — created
## by InteractionSystem._try_take_dish() (Part G4) when the player presses
## [E] on a pot with a ready dish. One-bite consumable, eaten like
## FarmProduceItem (no partial-bite tracking like FoodCan). Cannot be
## re-cooked — not in "cookpot_storable" — but can be stored in a Basket.

var fill_value: float = 0.0
var bonus_pct:  float = 0.0

var _mesh: MeshInstance3D = null
var _player_stats: Node = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return "Cooked Dish"

func get_prompt_text() -> String:
	return "[F] Pick up  Cooked Dish"

func get_use_prompt() -> String:
	return "[E] Eat  Cooked Dish  (%.1f)" % fill_value

func on_use() -> void:
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("DishItem: _player_stats not found.")
		return
	_player_stats.replenish_food(consume_as_food())

## Consumes this dish (frees the node) and returns the food restored.
## Shared mutation for player + NPCs (NPC Pass 2, Part 3).
func consume_as_food() -> float:
	queue_free()
	return fill_value * (1.0 + bonus_pct)

## Simple placeholder — shallow plate + a food mound. No per-ingredient
## color-blending in this pass; flat warm color regardless of what went in.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var plate: CylinderMesh = CylinderMesh.new()
	plate.top_radius    = 0.18
	plate.bottom_radius = 0.20
	plate.height        = 0.02
	_mesh.mesh = plate
	_mesh.position = Vector3(0.0, 0.01, 0.0)
	var plate_mat: StandardMaterial3D = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.85, 0.85, 0.82, 1.0)
	plate_mat.roughness    = 0.4
	_mesh.set_surface_override_material(0, plate_mat)
	add_child(_mesh)

	var mound_mi: MeshInstance3D = MeshInstance3D.new()
	var mound: SphereMesh = SphereMesh.new()
	mound.radius = 0.10
	mound.height = 0.12
	mound_mi.mesh = mound
	mound_mi.position = Vector3(0.0, 0.06, 0.0)
	var mound_mat: StandardMaterial3D = StandardMaterial3D.new()
	mound_mat.albedo_color = Color(0.55, 0.35, 0.18, 1.0)   ## warm stew-brown, generic
	mound_mat.roughness    = 0.8
	mound_mi.set_surface_override_material(0, mound_mat)
	add_child(mound_mi)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.12
	shape.shape = sph
	shape.position = Vector3(0.0, 0.05, 0.0)
	add_child(shape)