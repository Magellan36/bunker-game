extends LightStorage
class_name Dresser
## Dresser.gd
## Tall 2×1 dresser with 6 hidden drawers — light-item storage, capacity 6.
## Furniture category, TILE 33, $150. Solid wood body with a beige top slab
## and a 2×3 grid of drawer faces + knobs on the +Z (back) side (flipped).
## Footprint 1.90×0.45, height 0.80.

const BODY_SIZE: Vector3 = Vector3(1.90, 0.75, 0.45)
const TOP_THICKNESS: float = 0.05
const TOP_SIZE: Vector3 = Vector3(1.96, TOP_THICKNESS, 0.51)
const TOP_Y: float = BODY_SIZE.y + TOP_THICKNESS * 0.5
const DRAWER_W: float = 0.60
const DRAWER_H: float = 0.18
const DRAWER_THICKNESS: float = 0.02

const COLOR_WOOD: Color = Color(0.55, 0.36, 0.22, 1.0)
const COLOR_TOP:  Color = Color(0.82, 0.74, 0.60, 1.0)   ## matches Table beige

func _init() -> void:
	capacity      = 6
	display_name  = "Dresser"
	prompt_height = 0.8
	grid_cols     = 2
	grid_rows     = 3

func _build_mesh() -> void:
	var wood_mat: StandardMaterial3D = StandardMaterial3D.new()
	wood_mat.albedo_color = COLOR_WOOD
	wood_mat.metallic  = 0.0
	wood_mat.roughness = 0.8

	var top_mat: StandardMaterial3D = StandardMaterial3D.new()
	top_mat.albedo_color = COLOR_TOP
	top_mat.metallic  = 0.0
	top_mat.roughness = 0.85

	## Main body with collision.
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = BODY_SIZE
	body_mi.mesh = body_mesh
	body_mi.position = Vector3(0.0, BODY_SIZE.y * 0.5, 0.0)
	body_mi.set_surface_override_material(0, wood_mat)
	add_child(body_mi)
	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Top slab.
	var top_mi: MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh = BoxMesh.new()
	top_mesh.size = TOP_SIZE
	top_mi.mesh = top_mesh
	top_mi.position = Vector3(0.0, TOP_Y, 0.0)
	top_mi.set_surface_override_material(0, top_mat)
	add_child(top_mi)

	## 2×3 drawer grid on the +Z face (flipped 180°).
	var face_z: float = BODY_SIZE.z * 0.5 + DRAWER_THICKNESS * 0.5
	var start_y: float = BODY_SIZE.y - 0.10
	var gap_x: float = DRAWER_W + 0.06
	var start_x: float = -gap_x * 0.5
	for row: int in 3:
		var y: float = start_y - row * (DRAWER_H + 0.04)
		for col: int in 2:
			var x: float = start_x + col * gap_x

			var drawer_mi: MeshInstance3D = MeshInstance3D.new()
			var drawer_mesh: BoxMesh = BoxMesh.new()
			drawer_mesh.size = Vector3(DRAWER_W, DRAWER_H, DRAWER_THICKNESS)
			drawer_mi.mesh = drawer_mesh
			drawer_mi.position = Vector3(x, y, face_z)
			drawer_mi.set_surface_override_material(0, top_mat)
			add_child(drawer_mi)

			var knob_mi: MeshInstance3D = MeshInstance3D.new()
			var knob_mesh: CylinderMesh = CylinderMesh.new()
			knob_mesh.top_radius = 0.02
			knob_mesh.bottom_radius = 0.02
			knob_mesh.height = 0.04
			knob_mi.mesh = knob_mesh
			knob_mi.position = Vector3(x, y, face_z + 0.03)
			knob_mi.set_surface_override_material(0, top_mat)
			add_child(knob_mi)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(TOP_SIZE.x, TOP_Y + TOP_THICKNESS * 0.5, TOP_SIZE.z)
	return box
