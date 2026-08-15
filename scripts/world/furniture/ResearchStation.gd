extends StaticBody3D
class_name ResearchStation
## ResearchStation.gd
## Singleton, spawns at world start (see MainWorld._spawn_initial_research_station()),
## never purchasable, never deconstructable, movable only — identical treatment
## to BuildStation.gd. Opens ResearchStationUI on E; the UI itself is the
## substantial part of this feature and grows over future passes. This pass:
## object + UI shell + 3 selectable tabs with placeholder content only —
## no buttons, no timers, no feed logic. See HANDOVER for the full scope note.

var _research_ui: Node = null   ## Injected by MainWorld at spawn time, same pattern as BuildStation's _main_world

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()

func get_interact_prompt() -> String:
	return "[E] Open Research Station"

func on_interact() -> void:
	if _research_ui != null and _research_ui.has_method("open"):
		_research_ui.open(self)

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.1, 0.0)

# ─── Basic model — filled rectangle base + beakers/flasks, grey/steel to match Table/Chair ──
func _build_mesh() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.60, 0.62, 0.65, 1.0)   ## Table.gd/Chair.gd's COLOR_METAL, verified current value
	mat.metallic = 0.3
	mat.roughness = 0.55

	## Filled rectangle base — same 2×1 (1.90 × 0.90) footprint as Build
	## Station/Medium Table, but solid floor-to-top rather than four legs +
	## thin top, per design direction.
	const TOP_Y: float = 0.75
	var base_mi: MeshInstance3D = MeshInstance3D.new()
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(1.90, TOP_Y, 0.90)
	base_mi.mesh = base_mesh
	base_mi.position = Vector3(0.0, TOP_Y * 0.5, 0.0)
	base_mi.set_surface_override_material(0, mat)
	add_child(base_mi)
	base_mi.create_trimesh_collision()
	for child in base_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Beakers/flasks — a few simple primitives, tinted "liquid" glass look.
	var mat_glass: StandardMaterial3D = StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.55, 0.85, 0.75, 0.55)
	mat_glass.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.roughness = 0.1

	var flask_specs: Array = [
		{"pos": Vector3(-0.55, TOP_Y + 0.08, -0.15), "r": 0.055, "h": 0.16},
		{"pos": Vector3(-0.35, TOP_Y + 0.06, 0.15),  "r": 0.045, "h": 0.12},
		{"pos": Vector3(0.40, TOP_Y + 0.09, -0.05),  "r": 0.06,  "h": 0.18},
		{"pos": Vector3(0.60, TOP_Y + 0.05, 0.20),   "r": 0.04,  "h": 0.10},
	]
	for spec: Dictionary in flask_specs:
		var flask_mi: MeshInstance3D = MeshInstance3D.new()
		var flask_mesh: CylinderMesh = CylinderMesh.new()
		flask_mesh.top_radius = spec["r"] * 0.7
		flask_mesh.bottom_radius = spec["r"]
		flask_mesh.height = spec["h"]
		flask_mi.mesh = flask_mesh
		flask_mi.position = spec["pos"]
		flask_mi.set_surface_override_material(0, mat_glass)
		add_child(flask_mi)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.90, 0.95, 0.90)
	return box