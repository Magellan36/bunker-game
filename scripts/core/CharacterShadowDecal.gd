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
##
## Aug 2026 fix v3 (true cone, not trapezoid): v2 tightened and calibrated
## the near edge's width but it was still fundamentally a flat line
## (finite width) at the character's end — narrower/softer, but still a
## discernible boundary. Replaced the whole taper with a single smooth
## falloff starting at the centerline itself (u=0) and widening
## continuously toward the far end — genuinely converges to a point at
## v=0 rather than a narrow-but-nonzero-width line. See
## _get_shared_texture() below.

## Fixed target length for the un-clipped shadow — same "art-directed, not
## derived from real light distance" philosophy as the old proxy's
## PROXY_DISTANCE, just applied to a shadow shape instead of a light
## position. Actual length is this, UNLESS a raycast hits something
## closer (see _process()).
const TARGET_LENGTH: float = 3.5
const MIN_LENGTH:     float = 0.4   ## never shrink to a degenerate sliver right up against a wall

## Aug 2026 fix — the shape used to be vertex-colored geometry (a 6-vertex
## trapezoid), which only faded alpha along its LENGTH — the left/right
## edges were a hard, unblended straight cut, which is exactly what read
## as a "flat wall of shadow" instead of something soft sourced from the
## character. Vertex-color gradients across a handful of straight
## triangles can't give a genuinely soft, round falloff in every
## direction — replaced with a small procedurally-generated alpha texture
## (see _get_shared_texture()) mapped onto a plain rectangle, so the shape
## itself carries a smooth gradient on all sides instead of relying on
## mesh geometry for any part of the taper. RECT_WIDTH is just the
## rectangle's bounding size — the texture's own alpha reaches 0 well
## before this edge, so the rectangle's true silhouette is never visible.
const RECT_WIDTH: float = 2.0

## Aug 2026 fix v3 — replaces NEAR_WIDTH_FRAC/FAR_WIDTH_FRAC/
## EDGE_SOFTNESS_NEAR/EDGE_SOFTNESS_FAR entirely. Those defined a "solid
## core, then a fade band at its edge" — even tightened, that's still a
## shape with SOME nonzero width at v=0, i.e. still a line. CONE_TIP_EXTENT/
## CONE_BASE_EXTENT instead define a single smoothstep fade that starts at
## the centerline itself (u=0) and completes by `extent` — see
## _get_shared_texture() below. At v=0, extent is tiny (CONE_TIP_EXTENT),
## so nearly the whole row is already fading out right from center — reads
## as a point, not a line. extent grows toward CONE_BASE_EXTENT as v
## increases, forming the cone's widening body. Every row is a single
## continuous gradient — no "flat plateau then fade" anywhere, keeping the
## fully-soft-edges property from the earlier fix intact.
const CONE_TIP_EXTENT:  float = 0.06
const CONE_BASE_EXTENT: float = 0.85
## Where along the length the fade-to-nothing begins (0=at the character,
## 1=the far tip) — staying solid through roughly the first half, then
## easing out smoothly rather than an abrupt cut at the raycast-clipped end.
const LENGTH_FADE_START: float = 0.5

const NEAR_ALPHA: float = 0.35   ## modest, soft tint — never a hard black shape, baked into the texture below
const SHADOW_Y_OFFSET: float = 0.02   ## tiny lift above the floor to avoid z-fighting
const TEX_WIDTH:  int = 64
const TEX_HEIGHT: int = 128   ## 2:1 aspect, matches this shape's roughly length:width proportions

const SMOOTH_RATE: float = 3.0   ## still used for opacity/weight fade only — NOT direction, see _process()
const MIN_TOTAL_WEIGHT: float = 0.05   ## below this, no meaningful nearby light — hide the shadow

## Raycast height above the character's own origin — roughly waist height,
## so it doesn't clip on the floor itself or pass over low obstacles.
const RAY_HEIGHT: float = 0.8

## Aug 2026 fix v3 — baseline for _shadow_width_scale's proportional
## sizing. Player's own default CapsuleShape3D.radius (Godot's default,
## unset in Player.tscn) — see _compute_character_dimensions() below.
const PLAYER_REFERENCE_RADIUS: float = 0.5

var _owner_char: Node3D       = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D  = null
var _current_dir: Vector3     = Vector3.FORWARD
var _current_weight: float    = 0.0
## Distance from the character's own origin down to the actual floor —
## computed once in setup() from the character's own CapsuleShape3D rather
## than a hardcoded constant, since Player (height 2.0, Godot's default,
## unset in Player.tscn) and NPC (height 1.8, see scenes/npc/NPC.tscn) use
## different capsule heights. Both characters are centered on their
## capsule (no offset transform on CollisionShape3D/MeshInstance3D in
## either .tscn), so half the capsule height is the origin-to-floor
## distance. This is the fix for the shadow appearing at the character's
## midpoint instead of on the ground.
var _floor_offset: float = 1.0
## Aug 2026 fix v3 — simplified from a footprint-width-matching formula
## (which no longer makes sense now that the near end tapers to a true
## point, not a matched-width patch — see CONE_TIP_EXTENT above) to plain
## proportional sizing: Player's own capsule radius is the 1.0 baseline,
## everyone else scales relative to it. NPC (radius 0.4, see
## scenes/npc/NPC.tscn) gets a correspondingly smaller cone than Player
## (radius 0.5, Godot's default) — same intent (don't give a small
## character the same size shadow as a bigger one), simpler math, no
## dependency on the texture's internal constants.
var _shadow_width_scale: float = 1.0

## Shared across every instance — built once on first use, not per
## character. See _get_shared_mesh()/_get_shared_texture().
static var _shared_mesh: ArrayMesh = null
static var _shared_texture: ImageTexture = null

## Called once by Player._ready()/NPC._ready() immediately after
## instantiation, before add_child() finishes running this node's own
## _ready(). Stores the reference and computes both per-character
## dimensions — see _floor_offset/_shadow_width_scale above.
func setup(owner_char: Node3D) -> void:
	_owner_char = owner_char
	var dims: Dictionary = _compute_character_dimensions(owner_char)
	_floor_offset = dims["floor_offset"]
	_shadow_width_scale = dims["width_scale"]

## Reads the character's own CapsuleShape3D (height AND radius) rather
## than hardcoding constants — see _floor_offset's and
## _shadow_width_scale's comments for why. Falls back to Player's own
## defaults (height 2.0, radius 0.5) if the shape can't be found/isn't a
## capsule, so a structural change elsewhere degrades gracefully instead
## of erroring. Combined into one function (was two separate lookups) to
## avoid querying the same CollisionShape3D twice.
func _compute_character_dimensions(owner_char: Node3D) -> Dictionary:
	var collision_node: Node = owner_char.get_node_or_null("CollisionShape3D")
	if collision_node is CollisionShape3D:
		var shape: Shape3D = (collision_node as CollisionShape3D).shape
		if shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = shape as CapsuleShape3D
			return {
				"floor_offset": capsule.height * 0.5,
				"width_scale": capsule.radius / PLAYER_REFERENCE_RADIUS,
			}
	return {"floor_offset": 1.0, "width_scale": 1.0}

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _get_shared_mesh()

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Aug 2026 fix — texture-driven shape now (see the const block above
	## and _get_shared_texture() below), not vertex color. albedo_color
	## still works as a multiplier on top of the texture's own alpha —
	## _process() uses it exactly the same way it used to for the
	## aggregate-weight opacity fade.
	_material.albedo_texture = _get_shared_texture()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = _material

	## Critical — this decorative mesh must never cast a real shadow of its
	## own from any light. If it did, it would recreate exactly the
	## multi-shadow-clutter problem this whole plan exists to remove.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.gi_mode     = GeometryInstance3D.GI_MODE_DISABLED
	_mesh_instance.visible     = false
	add_child(_mesh_instance)

## Builds the canonical unit-length rectangle once and caches it — every
## character's decal reuses the same Mesh resource, only material/
## transform differ per-instance. Spans local Z=0 (character end) to Z=1
## (far end); _process() below non-uniformly scales this along Z each
## frame to the actual current shadow length, rather than rebuilding
## geometry every frame. Aug 2026 fix — this used to be a hand-tapered
## trapezoid with vertex-color alpha; the taper/softness now lives
## entirely in _get_shared_texture()'s generated gradient instead, so this
## mesh is just a plain flat rectangle with explicit UVs (0,0)-(1,1)
## mapping directly to the texture — no ambiguity about which mesh axis
## maps to which texture axis since both are authored here together.
static func _get_shared_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y: float = SHADOW_Y_OFFSET
	var hw: float = RECT_WIDTH * 0.5
	var v_near_l: Vector3 = Vector3(-hw, y, 0.0)
	var v_near_r: Vector3 = Vector3( hw, y, 0.0)
	var v_far_l:  Vector3 = Vector3(-hw, y, 1.0)
	var v_far_r:  Vector3 = Vector3( hw, y, 1.0)

	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v_near_l)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(v_near_r)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v_far_r)

	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(v_near_l)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(v_far_r)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(v_far_l)

	_shared_mesh = st.commit()
	return _shared_mesh

## Aug 2026 — new. Procedurally builds the soft shadow shape as an alpha
## gradient image, once, cached and reused by every character (same
## sharing philosophy as _get_shared_mesh()). No external art asset —
## generated pixel-by-pixel in code, same as the rest of this codebase's
## procedural-content conventions.
##
## Aug 2026 fix v3 — true cone, not trapezoid. For each row (v = 0 at the
## character's end, 1 at the far tip):
##   - length_falloff fades the whole row to 0 alpha starting at
##     LENGTH_FADE_START and finishing by v=1 — the far tip vanishes
##     smoothly instead of an abrupt cut where the raycast clips it.
##   - extent grows from CONE_TIP_EXTENT (v=0, tiny — see that const's
##     comment) to CONE_BASE_EXTENT (v=1, the cone's widening body).
## For each column (u = 0 at center, 1 at the rectangle's own edge):
##   - width_falloff is ONE smoothstep spanning u=0 (the centerline
##     itself) to `extent` — not a separate "solid core then edge fade."
##     At v=0 this means nearly the entire row is already fading out right
##     from center, reading as a point rather than a line — this is the
##     actual fix for the persistent "hard line at the origin" complaint
##     that survived the v2 tightening pass.
## Final per-pixel alpha = NEAR_ALPHA * length_falloff * width_falloff.
static func _get_shared_texture() -> ImageTexture:
	if _shared_texture != null:
		return _shared_texture
	var img: Image = Image.create(TEX_WIDTH, TEX_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(TEX_HEIGHT):
		var v: float = float(y) / float(TEX_HEIGHT - 1)
		var length_falloff: float = 1.0 - smoothstep(LENGTH_FADE_START, 1.0, v)
		var extent: float = lerp(CONE_TIP_EXTENT, CONE_BASE_EXTENT, smoothstep(0.0, 1.0, v))
		for x: int in range(TEX_WIDTH):
			var u: float = absf((float(x) / float(TEX_WIDTH - 1)) * 2.0 - 1.0)
			var width_falloff: float = 1.0 - smoothstep(0.0, extent, u)
			var a: float = clamp(length_falloff * width_falloff, 0.0, 1.0) * NEAR_ALPHA
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	_shared_texture = ImageTexture.create_from_image(img)
	return _shared_texture

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
		## Snaps instantly rather than lerping — real shadows track light
		## position with no lag at all; the smoothing here previously made
		## the shadow visibly slide into position instead of matching real
		## shadow movement timing. Only weight/opacity above still smooths
		## (avoids single-frame flicker from noisy raycast/weight changes),
		## direction does not.
		_current_dir = accum.normalized()

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

	## Aug 2026 fix v4 — replaces the earlier rotate-then-scale composition
	## (Basis(Vector3.UP, yaw).scaled(...)), which produced shadows that
	## were long/thin when the light was roughly north-south of the
	## character and stubby/perpendicular-stretched when it was roughly
	## east-west. That pattern (length and width effectively swapping
	## depending on orientation) doesn't match camera-projection
	## foreshortening — a fixed-pitch camera does compress one ground-plane
	## axis relative to the other, but in the opposite direction from what
	## was observed, and it wouldn't swap length/width like this. It reads
	## as an axis-composition bug — most likely in how Basis.scaled()
	## interacts with a rotation already baked into the same Basis, which
	## isn't something I could fully verify by hand without running the
	## engine.
	##
	## Rather than keep debugging that composition, this builds the
	## transform directly from two independently-computed, already-scaled
	## direction vectors — no rotate-then-scale step for an axis mix-up to
	## hide in:
	##   - `forward` = the shadow's own direction, scaled to the actual
	##     (possibly raycast-clipped) length. This is local +Z in
	##     _get_shared_mesh() (the mesh's length axis).
	##   - `right` = forward rotated 90° in the horizontal plane, scaled to
	##     the width. This is local +X (the mesh's width axis). Verified by
	##     hand: at dir=(1,0,0), the old atan2(dir.x,dir.z) formula gave
	##     yaw=90°, and a 90° yaw rotation of local +X should land at
	##     world (0,0,-1) — (dir.z, 0, -dir.x) gives exactly that.
	## Basis(x_axis, y_axis, z_axis) builds a basis directly from its three
	## column vectors — each already carries its own correct scale, so
	## there's no separate scale step that could apply to the wrong axis.
	var forward: Vector3 = _current_dir * actual_length
	var right: Vector3 = Vector3(_current_dir.z, 0.0, -_current_dir.x) * _shadow_width_scale
	var basis: Basis = Basis(right, Vector3.UP, forward)
	## char_pos is the character's own origin (capsule center, NOT the
	## floor) — subtract _floor_offset to place the shadow at actual
	## ground level instead of the character's midpoint.
	var floor_pos: Vector3 = char_pos - Vector3(0.0, _floor_offset, 0.0)
	global_transform = Transform3D(basis, floor_pos)