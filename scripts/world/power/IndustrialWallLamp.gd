extends Node3D
## IndustrialWallLamp.gd
## Procedural industrial wall lamp — arm + shade style.
## Saved as a standalone model for future use by other agents.

const LAMP_Y_OFFSET: float = 1.5

func _ready() -> void:
	_build_fixture()

func _build_fixture() -> void:
	## Dark industrial metal material
	var metal_mat: StandardMaterial3D = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.15, 0.15, 0.18, 1.0)
	metal_mat.roughness    = 1.0
	metal_mat.metallic     = 0.0
	metal_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	metal_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	## Wall mounting plate (flat box against wall)
	var plate_mi: MeshInstance3D = MeshInstance3D.new()
	var plate: BoxMesh = BoxMesh.new()
	plate.size = Vector3(0.18, 0.22, 0.025)
	plate_mi.mesh = plate
	plate_mi.position = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
	plate_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	plate_mi.set_surface_override_material(0, metal_mat)
	add_child(plate_mi)

	## Horizontal arm extending outward from plate
	var arm_mi: MeshInstance3D = MeshInstance3D.new()
	var arm: CylinderMesh = CylinderMesh.new()
	arm.top_radius = 0.015
	arm.bottom_radius = 0.015
	arm.height = 0.18
	arm.radial_segments = 8
	arm_mi.mesh = arm
	arm_mi.position = Vector3(0.0, LAMP_Y_OFFSET + 0.08, -0.10)
	arm_mi.rotation.x = PI * 0.5
	arm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	arm_mi.set_surface_override_material(0, metal_mat)
	add_child(arm_mi)

	## Vertical connector from arm to shade
	var conn_mi: MeshInstance3D = MeshInstance3D.new()
	var conn: CylinderMesh = CylinderMesh.new()
	conn.top_radius = 0.012
	conn.bottom_radius = 0.012
	conn.height = 0.06
	conn.radial_segments = 8
	conn_mi.mesh = conn
	conn_mi.position = Vector3(0.0, LAMP_Y_OFFSET + 0.05, -0.18)
	conn_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	conn_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	conn_mi.set_surface_override_material(0, metal_mat)
	add_child(conn_mi)

	## Lamp shade (cone/housing pointing downward)
	var shade_mi: MeshInstance3D = MeshInstance3D.new()
	var shade: CylinderMesh = CylinderMesh.new()
	shade.top_radius = 0.01
	shade.bottom_radius = 0.07
	shade.height = 0.10
	shade.radial_segments = 12
	shade_mi.mesh = shade
	shade_mi.position = Vector3(0.0, LAMP_Y_OFFSET - 0.02, -0.18)
	shade_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shade_mi.set_surface_override_material(0, metal_mat)
	add_child(shade_mi)

	## Bulb (small emissive sphere inside shade)
	var bulb_mi: MeshInstance3D = MeshInstance3D.new()
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.02
	bulb.height = 0.04
	bulb_mi.mesh = bulb
	bulb_mi.position = Vector3(0.0, LAMP_Y_OFFSET - 0.01, -0.18)
	var bulb_mat: StandardMaterial3D = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.90, 0.70, 1.0)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.50, 1.0)
	bulb_mat.emission_energy_multiplier = 0.5
	bulb_mat.roughness = 0.3
	bulb_mi.set_surface_override_material(0, bulb_mat)
	add_child(bulb_mi)

static func build_ghost_mesh() -> Mesh:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.18, 0.22, 0.20)
	return bm
