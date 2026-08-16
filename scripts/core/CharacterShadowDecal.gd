extends Node3D
class_name CharacterShadowDecal
## CharacterShadowDecal.gd
## Aug 2026 — replaces the reverted CharacterShadowProxy system (see
## docs/systems/graphics/README.md "Character shadow decal" and
## "Aggregated character shadows" for the postmortem on why the old
## Light3D-based approach was abandoned). This is deliberately NOT a
## light — it's a flat, soft-edged, tapered mesh laid on the floor that
## fakes one blended "cone" shadow instead of the multiple sharp real
## shadows a character used to cast from every nearby real light. Because
## there's no Light3D involved, this cannot affect how the character is
## lit — only how their fake shadow looks. Real per-light illumination and
## real shadow-casting/receiving on the character's own body are both back
## to being completely untouched/default — see Player.gd/NPC.gd (mesh no
## longer has any special light_cull_mask exclusion beyond Flashlight's
## original narrow one) and GeometryInstance3D.cast_shadow = OFF on the
## character mesh itself, which is what actually stops the multiple real
## shadows from appearing at all.
##
## Instantiated dynamically by Player._ready()/NPC._ready(), same pattern
## as everything else in this file family — never needs a .tscn edit.

## Fixed target length for the un-clipped shadow — same "art-directed, not
## derived from real light distance" philosophy as the old proxy's
## PROXY_DISTANCE, just applied to a shadow shape instead of a light
## position. Actual length is this, UNLESS a raycast hits something
## closer (see _process()).
const TARGET_LENGTH: float = 3.5
const MIN_LENGTH:     float = 0.4   ## never shrink to a degenerate sliver right up against a wall

const NEAR_WIDTH: float = 0.6   ## roughly the character's own footprint
const FAR_WIDTH:  float = 1.8   ## wider at the far end — the actual "cone" shape

const NEAR_ALPHA: float = 0.35   ## modest, soft tint — never a hard black shape
const SHADOW_Y_OFFSET: float = 0.02   ## tiny lift above the floor to avoid z-fighting

const SMOOTH_RATE: float = 3.0   ## same framerate-independent exponential smoothing the old proxy used
const MIN_TOTAL_WEIGHT: float = 0.05   ## below this, no meaningful nearby light — hide the shadow

## Raycast height above the character's own origin — roughly waist height,
## so it doesn't clip on the floor itself or pass over low obstacles.
const RAY_HEIGHT: float = 0.8

var _owner_char: Node3D       = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D  = null
var _current_dir: Vector3     = Vector3.FORWARD
var _current_weight: float    = 0.0

## Shared across every instance — built once on first use, not per
## character. See _get_shared_mesh().
static var _shared_mesh: ArrayMesh = null

## Called once by Player._ready()/NPC._ready() immediately after
## instantiation, before add_child() finishes running this node's own
## _ready(). Just stores the reference — _ready() below does the rest.
func setup(owner_char: Node3D) -> void:
	_owner_char = owner_char

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _get_shared_mesh()

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = _material

	## Critical — this decorative mesh must never cast a real shadow of its
	## own from any light. If it did, it would recreate exactly the
	## multi-shadow-clutter problem this whole plan exists to remove.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.gi_mode     = GeometryInstance3D.GI_MODE_DISABLED
	_mesh_instance.visible     = false
	add_child(_mesh_instance)

## Builds the canonical unit-length trapezoid once and caches it — every
## character's decal reuses the same Mesh resource, only material/
## transform differ per-instance. Spans local Z=0 (narrow, at the
## character) to Z=1 (wide, far end); _process() below non-uniformly
## scales this along Z each frame to the actual current shadow length,
## rather than rebuilding geometry every frame.
static func _get_shared_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y: float = SHADOW_Y_OFFSET
	var hw_near: float = NEAR_WIDTH * 0.5
	var hw_far:  float = FAR_WIDTH * 0.5
	var v_near_l: Vector3 = Vector3(-hw_near, y, 0.0)
	var v_near_r: Vector3 = Vector3( hw_near, y, 0.0)
	var v_far_l:  Vector3 = Vector3(-hw_far,  y, 1.0)
	var v_far_r:  Vector3 = Vector3( hw_far,  y, 1.0)
	var c_near: Color = Color(0.0, 0.0, 0.0, NEAR_ALPHA)
	var c_far:  Color = Color(0.0, 0.0, 0.0, 0.0)

	st.set_color(c_near); st.add_vertex(v_near_l)
	st.set_color(c_near); st.add_vertex(v_near_r)
	st.set_color(c_far);  st.add_vertex(v_far_r)

	st.set_color(c_near); st.add_vertex(v_near_l)
	st.set_color(c_far);  st.add_vertex(v_far_r)
	st.set_color(c_far);  st.add_vertex(v_far_l)

	_shared_mesh = st.commit()
	return _shared_mesh

func _process(delta: float) -> void:
	if _owner_char == null or _mesh_instance == null:
		return
	if not GraphicsSettings.shadow_casting_enabled:
		_mesh_instance.visible = false
		return

	var char_pos: Vector3 = _owner_char.global_position
	var accum: Vector3    = Vector3.ZERO
	var total_weight: float = 0.0

	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("wall_lights"))
	candidates.append_array(get_tree().get_nodes_in_group("grow_light"))

	for light: Node in candidates:
		if not light.has_method("get_shadow_weight"):
			continue
		var w: float = light.call("get_shadow_weight", char_pos)
		if w <= 0.0:
			continue
		var dir: Vector3 = char_pos - (light as Node3D).global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			accum += dir.normalized() * w
		total_weight += w

	var smooth_t: float = 1.0 - exp(-SMOOTH_RATE * delta)
	_current_weight = lerp(_current_weight, total_weight, smooth_t)

	if _current_weight < MIN_TOTAL_WEIGHT:
		_mesh_instance.visible = false
		return

	if accum.length() > 0.001:
		var target_dir: Vector3 = accum.normalized()
		_current_dir = _current_dir.lerp(target_dir, smooth_t).normalized()

	## Raycast clip — stop the shadow at the first wall/furniture it would
	## otherwise stretch through, instead of ghosting across it. Only
	## clips LENGTH (a single hit distance), not per-pixel shape — the
	## decal will still visually cross over the top of whatever it's
	## clipped against up to that point; it just won't extend past it. See
	## the plan doc's "What this does NOT do" for the accepted tradeoff.
	var from: Vector3 = char_pos + Vector3(0.0, RAY_HEIGHT, 0.0)
	var to: Vector3   = from + _current_dir * TARGET_LENGTH
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	## Layer 3 bit = value 4 — "placed objects" (walls + furniture), same
	## convention BuildModeController.gd's own raycasts already use.
	## Deliberately excludes layer 1 (player/NPCs) so this ray never
	## self-hits the very character casting it.
	query.collision_mask = 4
	var hit: Dictionary = space.intersect_ray(query)
	var actual_length: float = TARGET_LENGTH
	if not hit.is_empty():
		actual_length = from.distance_to(hit["position"])
	actual_length = max(actual_length, MIN_LENGTH)

	_mesh_instance.visible = true
	## Fade opacity with aggregate weight too — a character barely lit by
	## one distant light shouldn't show as strong a shadow as one standing
	## under several. Purely cosmetic — no risk to actual lighting since
	## this is only ever multiplying this decorative mesh's own alpha.
	_material.albedo_color = Color(1.0, 1.0, 1.0, clamp(_current_weight, 0.0, 1.0))

	## atan2(x, z) aligns this node's local +Z (the mesh's authored "length"
	## direction, see _get_shared_mesh()) with world-space _current_dir.
	## VERIFY IN-EDITOR: if the shadow points toward the light instead of
	## away from it, negate _current_dir here or add PI to yaw.
	var yaw: float = atan2(_current_dir.x, _current_dir.z)
	var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, actual_length))
	global_transform = Transform3D(basis, char_pos)