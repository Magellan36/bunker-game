extends StaticBody3D
class_name Table
## Table.gd
## Basic 4-legged table, metallic grey. Two sizes via cell_count (1 = small 1×1,
## 2 = medium 2×1) — same footprint numbers as FarmingTray (0.90×0.90 /
## 1.90×0.90) so it reads as visually consistent furniture at the same scale.
## Not interactable yet — pure static decoration/placement object for now.
## Cell_count = 2 loads table01.glb model.

const LEG_HEIGHT: float        = 0.72   ## Matches FarmingTray.LEG_HEIGHT
const TABLETOP_THICKNESS: float = 0.05
const TABLETOP_Y: float        = LEG_HEIGHT + TABLETOP_THICKNESS * 0.5

const COLOR_METAL: Color = Color(0.60, 0.62, 0.65, 1.0)

const TABLE_GLB_PATH: String = "res://assets/models/table01.glb"

@export var cell_count: int = 1   ## 1 = small table, 2 = medium table (GLB)

## Full-fidelity preview mode (see Bed.gd / Shelving.gd for the full
## convention writeup) — set TRUE by BuildModeHUD's construct-tab preview
## code BEFORE add_child(). Skips group membership only (this object has no
## PowerManager/WaterManager registration to skip, but the guard is kept for
## consistency with every other furniture/device script in this codebase).
var _is_preview_only: bool = false

func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	if not _is_preview_only:
		add_to_group("interactable_static")  ## reserved for future use (see Part 4 note); NOT added to "interactable" — table has no on_interact() yet
	collision_layer = 5   ## Matches wall/pillar/shelving/tray convention
	collision_mask  = 0
	_build_mesh()

func _footprint() -> Vector2:
	var x: float = 0.90 if cell_count == 1 else 1.90
	return Vector2(x, 0.90)

func _build_mesh() -> void:
	## Cell_count = 2: load GLB model
	if cell_count == 2:
		var packed: PackedScene = load(TABLE_GLB_PATH) if ResourceLoader.exists(TABLE_GLB_PATH) else null
		if packed != null:
			var model: Node3D = packed.instantiate() as Node3D
			if model != null:
				model.position = Vector3(0.0, 0.0, 0.0)
				_remove_collision_recursive(model)
				add_child(model)
				## Add collision from the model's bounds
				var aabb: AABB = _get_model_bounds(model)
				var cshape: CollisionShape3D = CollisionShape3D.new()
				var box: BoxShape3D = BoxShape3D.new()
				box.size = aabb.size
				cshape.shape = box
				cshape.position = Vector3(0.0, aabb.size.y * 0.5, 0.0)
				cshape.collision_layer = 5
				cshape.collision_mask = 0
				add_child(cshape)
				return
		## Fallback if GLB fails: procedural box
		var mi: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(1.90, LEG_HEIGHT + TABLETOP_THICKNESS, 0.90)
		mi.mesh = bm
		mi.position = Vector3(0.0, (LEG_HEIGHT + TABLETOP_THICKNESS) * 0.5, 0.0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = COLOR_METAL
		mat.metallic = 0.5
		mat.roughness = 0.4
		mi.set_surface_override_material(0, mat)
		add_child(mi)
		mi.create_trimesh_collision()
		for child in mi.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 5
				(child as StaticBody3D).collision_mask = 0
		return

	## Cell_count = 1: procedural mesh (original behavior)
	var fp: Vector2 = _footprint()
	var footprint_x: float = fp.x
	var footprint_z: float = fp.y

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_METAL
	mat.metallic  = 0.5
	mat.roughness = 0.4

	## 4 legs at the footprint's corners — identical geometry/positions to
	## FarmingTray._build_mesh()'s leg loop.
	var leg_positions: Array[Vector2] = [
		Vector2(-footprint_x * 0.5 + 0.05, -footprint_z * 0.5 + 0.05),
		Vector2( footprint_x * 0.5 - 0.05, -footprint_z * 0.5 + 0.05),
		Vector2(-footprint_x * 0.5 + 0.05,  footprint_z * 0.5 - 0.05),
		Vector2( footprint_x * 0.5 - 0.05,  footprint_z * 0.5 - 0.05),
	]
	for p: Vector2 in leg_positions:
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.03
		leg_mesh.bottom_radius = 0.03
		leg_mesh.height = LEG_HEIGHT
		leg_mesh.radial_segments = 8
		leg_mi.mesh = leg_mesh
		leg_mi.position = Vector3(p.x, LEG_HEIGHT * 0.5, p.y)
		leg_mi.set_surface_override_material(0, mat)
		add_child(leg_mi)

	## Flat tabletop slab (this replaces FarmingTray's open basin+walls).
	var top_mi:   MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh        = BoxMesh.new()
	top_mesh.size = Vector3(footprint_x, TABLETOP_THICKNESS, footprint_z)
	top_mi.mesh   = top_mesh
	top_mi.position = Vector3(0.0, TABLETOP_Y, 0.0)
	top_mi.set_surface_override_material(0, mat)
	add_child(top_mi)
	top_mi.create_trimesh_collision()
	for child in top_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

## Helper: get AABB bounds of a model
func _get_model_bounds(model: Node3D) -> AABB:
	var bounds: AABB = AABB()
	for child in model.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.mesh != null:
				var aabb: AABB = mi.get_aabb()
				bounds = bounds.merge(aabb)
	if bounds == AABB():
		bounds = AABB(Vector3(-0.95, 0.0, -0.45), Vector3(1.90, 0.80, 0.90))
	return bounds

## Helper: strip collision nodes from GLB import
func _remove_collision_recursive(node: Node) -> void:
	var children: Array = []
	for child in node.get_children():
		children.append(child)
	for child in children:
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.queue_free()
		elif child is StaticBody3D or child is RigidBody3D or child is Area3D:
			child.queue_free()
		else:
			_remove_collision_recursive(child)

static func build_ghost_mesh(cell_count: int = 1) -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	var x: float = 0.90 if cell_count == 1 else 1.90
	box.size = Vector3(x, TABLETOP_Y + TABLETOP_THICKNESS * 0.5, 0.90)
	return box