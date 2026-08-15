extends PickupableItem
class_name EmptyFertilizerBottleItem
## EmptyFertilizerBottleItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System — Fertilizer plan (Aug 2026 follow-up). Plain pickup, no
## on_use() — junk/decorative byproduct of using up a Fertilizer bottle
## (either tier). Dropped near the tray by FertilizerItem.on_use(), same
## "spawn near position, not auto-added to inventory" pattern as
## EmptyBagItem.spawn_at()/PurifierFilterItem.spawn_at().
##
## Replaces FertilizerItem's previous (mismatched) EmptyBagItem.spawn_at()
## call — a depleted fertilizer bottle was dropping a soil-bag-shaped prop.
## This shares FertilizerItem._build_placeholder_mesh()'s own body/shoulder/
## neck/cap cylinder proportions so the silhouette is recognizably "the same
## bottle, now empty," tinted with WaterBottle._update_empty_tint()'s exact
## grey/translucent values for a consistent "emptied consumable" look across
## the game. One shared look for both tiers — the color distinction (green/
## purple) stops mattering once it's empty, same reasoning EmptyBagItem uses
## for not preserving which specific consumable it came from.

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "empty_fertilizer_bottle"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("trash")   ## Aug 2026 — always trash by existence; see JobBoard._is_trash_item()
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return "Empty Fertilizer Bottle"

func get_prompt_text() -> String:
	return "[F] Pick up  Empty Fertilizer Bottle"

func get_trash_material() -> String:
	return "plastic"

## No use prompt — junk/decorative, no on_use() at all (mirrors EmptyBagItem).

## Same body/shoulder/neck/cap cylinder shape as FertilizerItem's bottle,
## single flat grey/translucent material instead of the tier body color —
## no label block (the label reads as removed/worn off once empty).
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.14, 0.0)

	## Same tint WaterBottle._update_empty_tint() applies to an emptied
	## water bottle — shared "emptied consumable" visual language.
	var empty_mat: StandardMaterial3D = StandardMaterial3D.new()
	empty_mat.albedo_color = Color(0.55, 0.55, 0.6, 0.7)
	empty_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	empty_mat.roughness    = 0.75
	empty_mat.metallic     = 0.05

	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.75, 0.75, 0.78, 0.7)
	cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cap_mat.roughness    = 0.60
	cap_mat.metallic     = 0.0

	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius    = 0.065
	body_mesh.bottom_radius = 0.065
	body_mesh.height        = 0.18
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.0, 0.0)
	body.set_surface_override_material(0, empty_mat)
	_mesh.add_child(body)

	var shoulder: MeshInstance3D = MeshInstance3D.new()
	var shoulder_mesh: CylinderMesh = CylinderMesh.new()
	shoulder_mesh.top_radius    = 0.025
	shoulder_mesh.bottom_radius = 0.065
	shoulder_mesh.height        = 0.04
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(0.0, 0.11, 0.0)
	shoulder.set_surface_override_material(0, empty_mat)
	_mesh.add_child(shoulder)

	var neck: MeshInstance3D = MeshInstance3D.new()
	var neck_mesh: CylinderMesh = CylinderMesh.new()
	neck_mesh.top_radius    = 0.025
	neck_mesh.bottom_radius = 0.025
	neck_mesh.height        = 0.035
	neck.mesh = neck_mesh
	neck.position = Vector3(0.0, 0.145, 0.0)
	neck.set_surface_override_material(0, empty_mat)
	_mesh.add_child(neck)

	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius    = 0.03
	cap_mesh.bottom_radius = 0.03
	cap_mesh.height        = 0.015
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 0.17, 0.0)
	cap.set_surface_override_material(0, cap_mat)
	_mesh.add_child(cap)

	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong there (no collider -> infinite fall, undetectable by the
	## interaction system). Same bounding cylinder FertilizerItem uses.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.065
	cyl_shape.height = 0.34
	shape.shape = cyl_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper — mirrors EmptyBagItem.spawn_at()'s shape.
static func spawn_at(parent: Node, base_pos: Vector3) -> EmptyFertilizerBottleItem:
	var item: EmptyFertilizerBottleItem = EmptyFertilizerBottleItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item