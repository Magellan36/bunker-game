extends Node3D
class_name WaterPipeElbow
## WaterPipeElbow.gd
## Corner-joint piece — spawned automatically whenever a placed pipe run
## crosses a wall corner (see WaterPipeDrawMode.gd). A REAL graph node (role
## "corner" in WaterGraph), not just a visual — so a future T-split placement
## can start a new branch from a corner exactly the same way it could from any
## other joint, without retrofitting corners into being real nodes later (see
## the groundwork plan §2/§6).
##
## Visual: a simple rounded elbow fitting — sphere-ish joint ball at the
## corner, matching WaterPipeSegment's pipe radius/material so the run reads
## as one continuous fixture.

## Slightly larger than WaterPipeSegment.PIPE_RADIUS (0.09) so the corner
## reads as a fitting, not a kink — kept in sync manually, same as
## WaterHookup.STUB_RADIUS/WaterPipeSegment.PIPE_RADIUS already are.
const JOINT_RADIUS: float = 0.105
const JOINT_SEGMENTS: int = 10

const COLOR_JOINT: Color = Color(0.40, 0.42, 0.44, 1.0)   ## matches WaterPipeSegment.COLOR_PIPE family, slightly darker

## Graph node key this elbow is registered under.
var node_key: String = ""

func _ready() -> void:
	visible = true   ## Always visible — same reasoning as WaterPipeSegment, see its file header.
	_build_mesh()

func _build_mesh() -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = JOINT_RADIUS
	sphere.height = JOINT_RADIUS * 2.0
	sphere.radial_segments = JOINT_SEGMENTS
	sphere.rings = JOINT_SEGMENTS / 2
	mi.mesh = sphere

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_JOINT
	mat.roughness     = 0.45
	mat.metallic      = 0.65
	mi.set_surface_override_material(0, mat)
	add_child(mi)
