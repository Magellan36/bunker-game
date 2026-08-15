extends StaticBody3D
class_name BuildStation
## BuildStation.gd
## Singleton object — spawns once at world-center at game start (see
## MainWorld._spawn_initial_build_station()), never purchasable, never
## deconstructable, movable only via the Move tool. The in-fiction entry
## point into Build Mode (F1 remains a dev/admin shortcut alongside it,
## unchanged).
##
## Uses the plain "interactable" contract (get_interact_prompt/on_interact)
## for ENTERING build mode — completely standard E-dispatch, same as any
## other interactable. EXITING build mode is a different mechanism entirely,
## owned by BuildModeController itself (see that file) — InteractionSystem's
## whole dispatch pipeline is disabled while build mode is active, so this
## script has no role in the exit interaction at all.

## Injected directly by MainWorld at spawn time (this object is never routed
## through BuildModeController.spawn_structure()'s generic injection block,
## since it's exclusively spawned by MainWorld's own dedicated function).
var _main_world: Node = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()

func get_interact_prompt() -> String:
	return "[E] Enter Build Mode"

func on_interact() -> void:
	if _main_world != null and _main_world.has_method("_toggle_build_mode"):
		_main_world._toggle_build_mode()

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.1, 0.0)

# ─── Basic model — 2×1 tabletop + rolled blueprints, simple per design direction ──
func _build_mesh() -> void:
	var mat_wood: StandardMaterial3D = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.42, 0.30, 0.20, 1.0)
	mat_wood.roughness = 0.85

	## Legs — mirrors Table.gd's leg convention (4 cylinders), scaled to a
	## 2×1 (1.90 × 0.90) footprint, same as Medium Table.
	const LEG_HEIGHT: float = 0.72
	var leg_positions: Array[Vector2] = [
		Vector2(-0.85, -0.35), Vector2(0.85, -0.35),
		Vector2(-0.85,  0.35), Vector2(0.85,  0.35),
	]
	for p: Vector2 in leg_positions:
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.035
		leg_mesh.bottom_radius = 0.035
		leg_mesh.height = LEG_HEIGHT
		leg_mi.mesh = leg_mesh
		leg_mi.position = Vector3(p.x, LEG_HEIGHT * 0.5, p.y)
		leg_mi.set_surface_override_material(0, mat_wood)
		add_child(leg_mi)

	## Tabletop, with collision (mirrors Table.gd's create_trimesh_collision pattern)
	var top_mi: MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh = BoxMesh.new()
	top_mesh.size = Vector3(1.90, 0.05, 0.90)
	top_mi.mesh = top_mesh
	top_mi.position = Vector3(0.0, LEG_HEIGHT + 0.025, 0.0)
	top_mi.set_surface_override_material(0, mat_wood)
	add_child(top_mi)
	top_mi.create_trimesh_collision()
	for child in top_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	var top_y: float = LEG_HEIGHT + 0.05

	## Rolled blueprints — a few flattened cylinders laid on their sides,
	## off-white/tan, loosely stacked. Simple primitives per design direction.
	var mat_paper: StandardMaterial3D = StandardMaterial3D.new()
	mat_paper.albedo_color = Color(0.88, 0.83, 0.68, 1.0)
	mat_paper.roughness = 0.95

	var roll_specs: Array = [
		{"pos": Vector3(-0.45, top_y + 0.05, -0.10), "rot_z": 90.0, "len": 0.55, "r": 0.05},
		{"pos": Vector3(-0.45, top_y + 0.13, 0.08),  "rot_z": 90.0, "len": 0.50, "r": 0.045},
		{"pos": Vector3(0.35, top_y + 0.045, 0.15),  "rot_z": 80.0, "len": 0.40, "r": 0.04},
	]
	for spec: Dictionary in roll_specs:
		var roll_mi: MeshInstance3D = MeshInstance3D.new()
		var roll_mesh: CylinderMesh = CylinderMesh.new()
		roll_mesh.top_radius = spec["r"]
		roll_mesh.bottom_radius = spec["r"]
		roll_mesh.height = spec["len"]
		roll_mi.mesh = roll_mesh
		roll_mi.position = spec["pos"]
		roll_mi.rotation_degrees = Vector3(0.0, 0.0, spec["rot_z"])
		roll_mi.set_surface_override_material(0, mat_paper)
		add_child(roll_mi)

	## A small toolbox-like box, other side of the table — one more "basic
	## shape object" per the request, simple grey box.
	var mat_metal: StandardMaterial3D = StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.35, 0.36, 0.38, 1.0)
	mat_metal.metallic = 0.3
	mat_metal.roughness = 0.6
	var box_mi: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(0.30, 0.16, 0.20)
	box_mi.mesh = box_mesh
	box_mi.position = Vector3(0.55, top_y + 0.08, -0.15)
	box_mi.set_surface_override_material(0, mat_metal)
	add_child(box_mi)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.90, 0.85, 0.90)
	return box