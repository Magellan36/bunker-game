extends RigidBody3D
class_name EmptyBagItem
## EmptyBagItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §1/§5.4. Plain pickup, no on_use() — junk/decorative
## byproduct of pouring a Bag of Soil into a tray. Dropped near the tray by
## BagOfSoilItem.on_use(), same "spawn near position, not auto-added to
## inventory" pattern as PurifierFilterItem.spawn_at().
##
## Deliberately flatter/lighter silhouette than BagOfSoilItem's full sack so
## players can tell the two apart on the ground at a glance before hovering.

signal picked_up()
signal dropped()
signal knocked_out()

const KNOCK_DISTANCE: float    = 2.2
const KNOCK_LINGER_TIME: float = 0.35

@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "empty_bag"

var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
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
	return "Empty Bag"

func get_prompt_text() -> String:
	return "[F] Pick up  Empty Bag"

## No use prompt — junk/decorative, no on_use() at all (plan §1).

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

## Flatter, lighter silhouette than BagOfSoilItem's full sack.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.24, 0.04, 0.16)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.02, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.62, 0.52, 1.0)
	mat.roughness    = 0.95
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper — mirrors PurifierFilterItem.spawn_at()'s shape.
static func spawn_at(parent: Node, base_pos: Vector3) -> EmptyBagItem:
	var item: EmptyBagItem = EmptyBagItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
