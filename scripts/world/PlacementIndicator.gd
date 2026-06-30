extends Node3D
## PlacementIndicator.gd
## A flat visual ring/disc that shows where an item will be placed.
## Attach to: MeshInstance3D node named "PlacementIndicator" under InteractionSystem

@onready var mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_build_indicator()

func _build_indicator() -> void:
	# Flat cylinder disc as the placement ring
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.02       # Nearly flat
	cyl.radial_segments = 24

	# Glowing green semi-transparent material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.8, 0.2)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mesh.mesh = cyl
	mesh.material_override = mat

# Pulse the indicator scale for a subtle alive feel
var _t: float = 0.0
func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta * 3.0
	var pulse: float = 1.0 + sin(_t) * 0.06
	scale = Vector3(pulse, 1.0, pulse)
