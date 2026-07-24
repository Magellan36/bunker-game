extends RigidBody3D
class_name FarmProduceItem
## FarmProduceItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §7. ONE script for both tomato/onion produce via
## export var. Physics/pickup/drop/knockout scaffolding copied from
## FoodCan.gd — but deliberately NOT its multi-bite charge system (FoodCan is
## the wrong reference for the eating logic itself, only for the physics
## scaffolding): 1-charge, fully consumed in one on_use() call, no partial-
## bite tracking like WaterBottle's continuous-mL model.

signal picked_up()
signal dropped()
signal knocked_out()

const KNOCK_DISTANCE: float    = 2.2
const KNOCK_LINGER_TIME: float = 0.35

@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

@export var produce_type: String = "tomato"   ## "tomato" or "onion"

## Flat hunger restore per produce item — same order of magnitude as
## FoodCan's per-bite value (12.5), used whole here since this is a single
## 1-charge item rather than a 2-bite can.
const FOOD_RESTORE: float = 20.0

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "farm_produce"   ## Shared slot for both types —
## per-instance produce_type preserved by Shelving.gd's real-node-reference
## slots, same reasoning as PurifierFilterItem/SeedItem.

var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _player_stats: Node     = null
var _grace_timer: float       = 0.0
var _out_of_range_time: float = 0.0

var _mesh: MeshInstance3D = null

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	contact_monitor = true
	max_contacts_reported = 4
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

func get_display_name() -> String:
	return PlantDatabase.get_display_name(produce_type)

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

func get_use_prompt() -> String:
	return "[E] Eat  %s" % get_display_name()

## Fully consumed in one call — no charge tracking, no empty-state.
func on_use() -> void:
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FarmProduceItem: _player_stats not found.")
		return
	_player_stats.replenish_food(FOOD_RESTORE)
	queue_free()

func pickup(hold_point: Node3D) -> void:
	is_held       = true
	_hold_point   = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze        = false
	freeze_mode   = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask  = 1
	_set_held_culling(true)
	picked_up.emit()

func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin

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
	_mesh.create_trimesh_collision()
	for child in _mesh.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

## Spawn helper — mirrors PurifierFilterItem.spawn_at()'s small-random-offset
## scatter pattern (used by FarmPlant.harvest() to spawn 2× per harvest).
static func spawn_at(parent: Node, base_pos: Vector3, type: String) -> FarmProduceItem:
	var item: FarmProduceItem = FarmProduceItem.new()
	item.produce_type = type
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
