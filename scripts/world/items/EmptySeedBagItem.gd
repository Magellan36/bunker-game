extends PickupableItem
class_name EmptySeedBagItem
## EmptySeedBagItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Aug 2026 — Empty Seed Bag, dropped by SeedItem when its last charge is
## used. Mirrors EmptyFertilizerBottleItem.gd's pattern exactly — plain
## pickup, no on_use() (junk/decorative byproduct of using up a consumable).
## One shared design for every seed species (tomato/onion/etc.) — species is
## irrelevant once empty, per design direction.
##
## Dropped near the tray by SeedItem.on_use()/apply_at_cell(), same
## "spawn near position, not auto-added to inventory" pattern as
## EmptyBagItem.spawn_at()/PurifierFilterItem.spawn_at().

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "empty_seed_bag"

func get_trash_material() -> String:
	return "paper"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("trash")   ## always trash by existence; see JobBoard._is_trash_item()
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return "Empty Seed Bag"

func get_prompt_text() -> String:
	return "[F] Pick up  Empty Seed Bag"

## No use prompt — junk/decorative, no on_use() at all (mirrors EmptyBagItem).

## Small flat packet silhouette, same proportions as SeedItem's packet
## placeholder but a single flat grey "emptied packet" look — matches the
## shared "emptied consumable" visual language EmptyFertilizerBottleItem uses.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.10, 0.02, 0.14)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.01, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.6, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness    = 0.75
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — same bounding box
	## SeedItem uses (see its _build_placeholder_mesh() comment for why).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(0.10, 0.02, 0.14)
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper — mirrors EmptyBagItem.spawn_at()'s shape.
static func spawn_at(parent: Node, base_pos: Vector3) -> EmptySeedBagItem:
	var item: EmptySeedBagItem = EmptySeedBagItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item