extends Node3D
class_name WaterPipeSegment
## WaterPipeSegment.gd
## Visual representation of one straight placed pipe between two world points.
## Mirrors WireSegment.gd's mesh-building approach, with ONE deliberate,
## explicitly-confirmed difference: pipes are ALWAYS VISIBLE, not hidden
## outside build mode. Physical plumbing reads as "always there" thematically,
## unlike electrical wiring which stays concealed — do NOT reuse WireSegment's
## visible=false-by-default / "wire_segment" group build-mode toggle pattern
## here (see the groundwork plan §5, confirmed explicitly rather than
## copy-pasted by habit).
##
## SETUP (called by WaterPipeDrawMode after WaterManager confirms the edge):
##   var seg := WaterPipeSegment.new()
##   parent.add_child(seg)
##   seg.set_endpoints(world_a, world_b)
##   seg.edge_id = edge_id   ## so the draw mode can unregister it later

# ─── Visual constants ─────────────────────────────────────────────────────────
const PIPE_RADIUS:   float = 0.045          ## slightly thicker than a wire — physical plumbing
const PIPE_SEGMENTS: int   = 10

## Standing pipe colour — galvanized grey. No powered/burnt/overloaded state
## variants like WireSegment has (no flow/pressure sim this phase — see
## WaterGraph.gd header) — just one constant material.
const COLOR_PIPE: Color = Color(0.45, 0.47, 0.49, 1.0)

## Slight offset off the wall plane so the pipe visibly hugs the wall it's
## snapped to, rather than floating in open room space — mirrors how
## BreakerBox/WallLight sit slightly proud of the wall surface. Applied by
## WaterPipeDrawMode when it computes wall-hugging endpoints, NOT by this
## file — this file only draws a straight tube between whatever two points
## it's given.
const WALL_HUG_OFFSET: float = 0.06

# ─── State ────────────────────────────────────────────────────────────────────
## WaterGraph edge ID — stored so the draw mode can unregister it on deconstruct.
var edge_id: String = ""

var point_a: Vector3 = Vector3.ZERO
var point_b: Vector3 = Vector3.ZERO

var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D  = null

func _ready() -> void:
	## Always visible — see file header. No group registration, no
	## build-mode-driven show/hide.
	visible = true

func set_endpoints(a: Vector3, b: Vector3) -> void:
	if not is_inside_tree():
		return
	point_a = a
	point_b = b
	_rebuild_mesh()

func _rebuild_mesh() -> void:
	if not is_inside_tree():
		return
	if _mesh_instance != null:
		_mesh_instance.queue_free()
		_mesh_instance = null

	var length: float = point_a.distance_to(point_b)
	if length < 0.01:
		return

	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = PIPE_RADIUS
	cyl.bottom_radius = PIPE_RADIUS
	cyl.height        = length
	cyl.radial_segments = PIPE_SEGMENTS
	cyl.rings = 1

	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR_PIPE
	_material.roughness    = 0.45
	_material.metallic     = 0.65
	## Normal depth test (unlike WireSegment) — this is a real physical object
	## meant to be occluded by walls/geometry like anything else in the room.

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = cyl
	_mesh_instance.set_surface_override_material(0, _material)
	add_child(_mesh_instance)

	var mid: Vector3 = (point_a + point_b) * 0.5
	global_position = mid

	var dir: Vector3 = (point_b - point_a).normalized()
	var up: Vector3 = Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	_mesh_instance.look_at(global_position + dir, up)
	_mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)

## Creates a temporary visual pipe (no edge_id) for the drag/preview ghost —
## same static-helper convention as WireSegment.make_ghost_wire(). Caller must
## free it when done.
static func make_ghost_pipe(parent: Node, a: Vector3, b: Vector3) -> Node3D:
	var seg: Node3D = Node3D.new()
	var script: GDScript = load("res://scripts/world/water/WaterPipeSegment.gd")
	if script != null:
		seg.set_script(script)
	parent.add_child(seg)
	if seg.has_method("set_endpoints"):
		seg.call("set_endpoints", a, b)
	return seg
