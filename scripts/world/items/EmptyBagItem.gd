extends PickupableItem
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

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "empty_bag"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return "Empty Bag"

func get_prompt_text() -> String:
	return "[F] Pick up  Empty Bag"

## No use prompt — junk/decorative, no on_use() at all (plan §1).

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
