extends Node3D
class_name WireSegment
## WireSegment.gd
## Visual representation of a placed power wire between two world points.
##
## BEHAVIOUR:
##   - Hidden by default (outside build mode).
##   - In Build Mode: shows as a semi-transparent light-blue tube.
##   - Renders THROUGH walls and objects (depth test disabled on material)
##     so the player can see the wire network at a glance.
##   - BuildModeController calls set_visible(true/false) via the
##     "wire_segment" group.
##   - PowerManager owns the logical edge; this node is purely cosmetic.
##
## SETUP (called by WireDrawMode after PowerManager confirms the edge):
##   var ws := WireSegment.new()
##   parent.add_child(ws)
##   ws.set_endpoints(world_a, world_b)
##   ws.edge_id = edge_id   ## so BuildModeController can unregister it
##
## WIRE COST: $8 per metre, charged at placement time by WireDrawMode.

# ─── Visual constants ─────────────────────────────────────────────────────────
const WIRE_RADIUS:     float = 0.025          ## tube radius in metres
const WIRE_SEGMENTS:   int   = 8              ## sides of the tube cylinder

## Build-mode ghost colour: light blue, semi-transparent
const COLOR_GHOST: Color = Color(0.35, 0.80, 1.0, 0.55)
## Powered wire colour: brighter blue
const COLOR_LIVE:  Color = Color(0.40, 0.90, 1.0, 0.70)
## Unpowered wire colour: dull grey-blue
const COLOR_DEAD:  Color = Color(0.30, 0.40, 0.55, 0.50)
## Overloaded wire: orange warning
const COLOR_OVER:  Color = Color(1.0, 0.55, 0.10, 0.80)
## Burnt wire: dark red
const COLOR_BURNT: Color = Color(0.45, 0.10, 0.10, 0.60)

# ─── State ────────────────────────────────────────────────────────────────────
## PowerManager edge ID — stored so caller can unregister on deconstruct.
var edge_id: String = ""

## World-space endpoints (set by set_endpoints)
var point_a: Vector3 = Vector3.ZERO
var point_b: Vector3 = Vector3.ZERO

## Set true on ghost instances so _ready() skips group registration and
## the "hide all wires" build-mode broadcast never kills the drag preview.
var is_ghost: bool = false

## Track powered / burnt state for colour update
var _powered: bool  = false
var _burnt:   bool  = false
var _overloaded: bool = false

var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D  = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if is_ghost:
		## Ghost wires are always visible during drag and must not be affected
		## by BuildModeController's group-wide show/hide broadcasts.
		visible = true
		return
	add_to_group("wire_segment")
	visible = false   ## Hidden until BuildModeController shows it

func set_endpoints(a: Vector3, b: Vector3) -> void:
	## Guard: deferred set_endpoints may arrive after queue_free() was called.
	if not is_inside_tree():
		return
	point_a = a
	point_b = b
	_rebuild_mesh()

## Called by BuildModeController / PowerManager to update visual state.
func set_powered(on: bool) -> void:
	_powered = on
	_update_color()

func set_burnt(on: bool) -> void:
	_burnt = on
	_update_color()

func set_overloaded(on: bool) -> void:
	_overloaded = on
	_update_color()

## Zone colour override — set by BuildModeController._recolor_wire_zones()
## while in build mode.  Pass Color.TRANSPARENT to revert to state colour.
## The override is stored so _update_color() can restore it after delete-
## highlight is cleared.
var _zone_color: Color = Color.TRANSPARENT

## Apply a zone colour to this wire segment (build-mode zone visualisation).
## Pass Color.TRANSPARENT to revert to the default state colour (light blue).
func set_zone_color(color: Color) -> void:
	_zone_color = color
	if _material == null:
		return
	if color.a > 0.0:
		_material.albedo_color = color
	else:
		_update_color()


## Highlight this segment red when the player hovers it in Deconstruct mode.
## Pass false to restore normal wire colour.
## BuildModeController calls this instead of showing a red box ghost so the
## entire segment glows red rather than a misplaced overlay box.
const COLOR_DELETE: Color = Color(1.0, 0.15, 0.10, 0.90)
var _delete_highlight: bool = false

func set_highlight_delete(on: bool) -> void:
	_delete_highlight = on
	if _material == null:
		return
	if on:
		_material.albedo_color       = COLOR_DELETE
		_material.emission_enabled   = true
		_material.emission           = COLOR_DELETE
		_material.emission_energy_multiplier = 1.2
	else:
		_material.emission_enabled   = false
		_material.emission_energy_multiplier = 0.0
		_update_color()   ## Restore the correct state colour

# ─── Mesh construction ────────────────────────────────────────────────────────
func _rebuild_mesh() -> void:
	## Guard: called via call_deferred — may fire after queue_free().
	if not is_inside_tree():
		return
	if _mesh_instance != null:
		_mesh_instance.queue_free()
		_mesh_instance = null

	var length: float = point_a.distance_to(point_b)
	if length < 0.01:
		return

	## Build a capsule-like cylinder aligned along local Y, then orient it.
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = WIRE_RADIUS
	cyl.bottom_radius = WIRE_RADIUS
	cyl.height        = length
	cyl.radial_segments = WIRE_SEGMENTS
	cyl.rings = 1

	_material = StandardMaterial3D.new()
	_material.albedo_color       = COLOR_GHOST
	## Depth test DISABLED — wire renders through everything while in build mode.
	## This lets you see the whole wire network even when walls are in the way.
	_material.no_depth_test      = true
	_material.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.render_priority    = 1    ## Draws on top of normal geometry

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = cyl
	_mesh_instance.set_surface_override_material(0, _material)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	## Position: midpoint between endpoints; orient: look from a → b along local +Y
	var mid: Vector3 = (point_a + point_b) * 0.5
	global_position = mid

	var dir: Vector3 = (point_b - point_a).normalized()
	## CylinderMesh is Y-aligned by default. We need to rotate local +Y → dir.
	var up: Vector3 = Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	global_transform.basis = Basis(up.cross(dir).normalized(), dir, up.cross(dir).normalized().cross(dir))
	## Simpler: use look_at style rotation
	_mesh_instance.look_at(global_position + dir, Vector3.UP if abs(dir.y) < 0.999 else Vector3.RIGHT)
	_mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	_update_color()

func _update_color() -> void:
	if _material == null:
		return
	## Delete-highlight overrides everything — handled by set_highlight_delete().
	if _delete_highlight:
		return
	## State colours (burnt/overloaded/powered) take priority over zone colour.
	if _burnt:
		_material.albedo_color = COLOR_BURNT
	elif _overloaded:
		_material.albedo_color = COLOR_OVER
	elif _powered:
		_material.albedo_color = COLOR_LIVE
	elif _zone_color.a > 0.0:
		## Zone colour assigned by BuildModeController — no breakers = default blue.
		_material.albedo_color = _zone_color
	else:
		_material.albedo_color = COLOR_GHOST

# ─── Static helper for ghost preview during wire drag ─────────────────────────
## Creates a temporary visual wire (no edge_id, no group) for the drag ghost.
## Caller must free it when done.
static func make_ghost_wire(parent: Node, a: Vector3, b: Vector3) -> Node3D:
	var ws: Node3D = Node3D.new()
	var script: GDScript = load("res://scripts/world/power/WireSegment.gd")
	if script != null:
		ws.set_script(script)
	## Set is_ghost BEFORE add_child so _ready() skips group registration
	## and leaves the node visible from the start.
	ws.set("is_ghost", true)
	parent.add_child(ws)
	if ws.has_method("set_endpoints"):
		ws.call("set_endpoints", a, b)
	return ws
