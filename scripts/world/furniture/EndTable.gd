extends LightStorage
class_name EndTable
## EndTable.gd
## Small 1×1 side table with a hidden drawer — light-item storage, capacity 2.
## Furniture category, TILE 32, $60. Legs + tabletop copied verbatim from
## Table.gd (so it reads as consistent furniture), plus a cabinet box with a
## single drawer face on the -Z side. Build/occupancy footprint matches
## Table (small): 0.90×0.90.

const LEG_HEIGHT: float          = 0.72   ## Matches Table.gd
const TABLETOP_THICKNESS: float  = 0.05   ## Matches Table.gd
const TABLETOP_Y: float          = LEG_HEIGHT + TABLETOP_THICKNESS * 0.5
const FOOTPRINT: Vector2         = Vector2(0.90, 0.90)
const CABINET_SIZE: Vector3      = Vector3(0.70, 0.40, 0.70)
const CABINET_Y: float           = 0.50

const COLOR_BEIGE: Color = Color(0.82, 0.74, 0.60, 1.0)   ## matches Table beige
const COLOR_WOOD:  Color = Color(0.55, 0.36, 0.22, 1.0)

func _init() -> void:
	capacity      = 2
	display_name  = "End Table"
	prompt_height = 1.2
	grid_cols     = 2
	grid_rows     = 1

func _build_mesh() -> void:
	var beige_mat: StandardMaterial3D = StandardMaterial3D.new()
	beige_mat.albedo_color = COLOR_BEIGE
	beige_mat.metallic  = 0.0
	beige_mat.roughness = 0.85

	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = COLOR_WOOD
	wood_mat.metallic  = 0.0
	wood_mat.roughness = 0.8

	## 4 legs at the footprint's corners — identical to Table.gd / FarmingTray.
	var leg_positions: Array[Vector2] = [
		Vector2(-FOOTPRINT.x * 0.5 + 0.05, -FOOTPRINT.y * 0.5 + 0.05),
		Vector2( FOOTPRINT.x * 0.5 - 0.05, -FOOTPRINT.y * 0.5 + 0.05),
		Vector2(-FOOTPRINT.x * 0.5 + 0.05,  FOOTPRINT.y * 0.5 - 0.05),
		Vector2( FOOTPRINT.x * 0.5 - 0.05,  FOOTPRINT.y * 0.5 - 0.05),
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
		leg_mi.set_surface_override_material(0, beige_mat)
		add_child(leg_mi)

	## Tabletop slab — identical to Table.gd.
	var top_mi:   MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh        = BoxMesh.new()
	top_mesh.size = Vector3(FOOTPRINT.x, TABLETOP_THICKNESS, FOOTPRINT.y)
	top_mi.mesh   = top_mesh
	top_mi.position = Vector3(0.0, TABLETOP_Y, 0.0)
	top_mi.set_surface_override_material(0, beige_mat)
	add_child(top_mi)

	## Cabinet box (the storage body) sitting between the legs, with collision.
	var cab_mi:    MeshInstance3D = MeshInstance3D.new()
	var cab_mesh:  BoxMesh        = BoxMesh.new()
	cab_mesh.size = CABINET_SIZE
	cab_mi.mesh   = cab_mesh
	cab_mi.position = Vector3(0.0, CABINET_Y, 0.0)
	cab_mi.set_surface_override_material(0, wood_mat)
	add_child(cab_mi)
	cab_mi.create_trimesh_collision()
	for child in cab_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Drawer face + knob on the -Z (front) side.
	var drawer_mi:  MeshInstance3D = MeshInstance3D.new()
	var drawer_mesh: BoxMesh       = BoxMesh.new()
	drawer_mesh.size = Vector3(0.52, 0.22, 0.02)
	drawer_mi.mesh   = drawer_mesh
	drawer_mi.position = Vector3(0.0, CABINET_Y, -CABINET_SIZE.z * 0.5 - 0.01)
	drawer_mi.set_surface_override_material(0, beige_mat)
	add_child(drawer_mi)

	var knob_mi:   MeshInstance3D = MeshInstance3D.new()
	var knob_mesh: CylinderMesh   = CylinderMesh.new()
	knob_mesh.top_radius = 0.02
	knob_mesh.bottom_radius = 0.02
	knob_mesh.height = 0.04
	knob_mi.mesh = knob_mesh
	knob_mi.position = Vector3(0.0, CABINET_Y, -CABINET_SIZE.z * 0.5 - 0.04)
	knob_mi.set_surface_override_material(0, beige_mat)
	add_child(knob_mi)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT.x, TABLETOP_Y + TABLETOP_THICKNESS * 0.5, FOOTPRINT.y)
	return box
