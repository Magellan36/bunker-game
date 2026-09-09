extends Node3D
class_name WireSegment
## Build-only wire presentation. Exact endpoints remain authoritative.
## Shared unit geometry and pooled pieces avoid mesh allocation during drag.
const WIRE_RADIUS: float = 0.025
const WIRE_SEGMENTS: int = 10
const COLOR_GHOST := Color(0.35, 0.80, 1.0, 0.55)
const COLOR_LIVE := Color(0.40, 0.90, 1.0, 0.70)
const COLOR_DEAD := Color(0.30, 0.40, 0.55, 0.50)
const COLOR_OVER := Color(1.0, 0.55, 0.10, 0.80)
const COLOR_BURNT := Color(0.45, 0.10, 0.10, 0.60)
const COLOR_DELETE := Color(1.0, 0.15, 0.10, 0.90)
static var _unit_tube: CylinderMesh
static var _unit_cap: SphereMesh
var edge_id: String = ""
var point_a := Vector3.ZERO
var point_b := Vector3.ZERO
var is_ghost: bool = false
var player_placed: bool = false
var run_id: String = ""
var _powered: bool = false
var _burnt: bool = false
var _overloaded: bool = false
var _zone_color := Color.TRANSPARENT
var _delete_highlight: bool = false
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _tubes: Array[MeshInstance3D] = []
var _caps: Array[MeshInstance3D] = []
var _target_color := COLOR_GHOST
var _appearance: float = 1.0

func _ready() -> void:
	if not is_ghost:
		add_to_group("wire_segment")
	visible = is_ghost
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR_GHOST
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.render_priority = 1
	set_process(false)

func set_endpoints(a: Vector3, b: Vector3) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if point_a.is_equal_approx(a) and point_b.is_equal_approx(b) and not _tubes.is_empty():
		return
	point_a = a
	point_b = b
	_rebuild_mesh()

func _piece(mesh: Mesh) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = _material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	return piece

func _rebuild_mesh() -> void:
	if _unit_tube == null:
		_unit_tube = CylinderMesh.new()
		_unit_tube.top_radius = WIRE_RADIUS
		_unit_tube.bottom_radius = WIRE_RADIUS
		_unit_tube.height = 1.0
		_unit_tube.radial_segments = WIRE_SEGMENTS
		_unit_tube.rings = 1
		_unit_cap = SphereMesh.new()
		_unit_cap.radius = WIRE_RADIUS
		_unit_cap.height = WIRE_RADIUS * 2.0
		_unit_cap.radial_segments = WIRE_SEGMENTS
		_unit_cap.rings = 4
	var path: PackedVector3Array = WireRoute.points(point_a, point_b)
	while _tubes.size() < path.size() - 1:
		_tubes.append(_piece(_unit_tube))
	while _caps.size() < path.size():
		_caps.append(_piece(_unit_cap))
	global_transform = Transform3D(Basis.IDENTITY, (point_a + point_b) * 0.5)
	for i: int in _tubes.size():
		var tube: MeshInstance3D = _tubes[i]
		tube.visible = i < path.size() - 1
		if not tube.visible:
			continue
		var direction: Vector3 = path[i + 1] - path[i]
		var length: float = direction.length()
		if length <= WireRoute.EPSILON:
			tube.visible = false
			continue
		var y: Vector3 = direction / length
		var reference: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.99 else Vector3.UP
		var x: Vector3 = reference.cross(y).normalized()
		tube.global_transform = Transform3D(Basis(x, y * length, x.cross(y)), (path[i] + path[i + 1]) * 0.5)
	for i: int in _caps.size():
		_caps[i].visible = path.size() > 1 and i < path.size()
		if _caps[i].visible:
			_caps[i].global_position = path[i]
	_mesh_instance = _tubes[0] if not _tubes.is_empty() else null

func set_powered(on: bool) -> void:
	_powered = on
	_update_color()

func set_burnt(on: bool) -> void:
	_burnt = on
	_update_color()

func set_overloaded(on: bool) -> void:
	_overloaded = on
	_update_color()

func set_zone_color(color: Color) -> void:
	_zone_color = color
	_update_color()

func set_highlight_delete(on: bool) -> void:
	_delete_highlight = on
	_update_color()

func set_preview_color(color: Color) -> void:
	_target_color = color
	set_process(true)

func play_placement() -> void:
	_appearance = 1.0 if UIMotion.reduced() else 0.35
	_material.albedo_color.a *= _appearance
	set_process(true)

func _update_color() -> void:
	_target_color = COLOR_DELETE if _delete_highlight else (COLOR_BURNT if _burnt else (
		COLOR_OVER if _overloaded else (_zone_color if _zone_color.a > 0.0 else (
		COLOR_LIVE if _powered else COLOR_GHOST))))
	if _material != null:
		if UIMotion.reduced() or not visible:
			_material.albedo_color = _target_color
		else:
			set_process(true)

func _process(delta: float) -> void:
	_appearance = move_toward(_appearance, 1.0, delta / UIMotion.ENTER) if not UIMotion.reduced() else 1.0
	var target: Color = _target_color
	target.a *= _appearance
	_material.albedo_color = _material.albedo_color.lerp(target, UIMotion.weight(delta, 24.0))
	if _appearance == 1.0 and _material.albedo_color.is_equal_approx(target):
		_material.albedo_color = target
		set_process(false)

static func make_ghost_wire(parent: Node, a: Vector3, b: Vector3) -> Node3D:
	var wire := WireSegment.new()
	wire.is_ghost = true
	parent.add_child(wire)
	wire.set_endpoints(a, b)
	return wire
