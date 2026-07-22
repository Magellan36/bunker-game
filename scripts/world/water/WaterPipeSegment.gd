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
## Matches WaterHookup.STUB_RADIUS exactly (playtest feedback — pipes and the
## hookup's own stub must visually read as the same pipe, same diameter).
const PIPE_RADIUS:   float = 0.09
const PIPE_SEGMENTS: int   = 10

## Standing pipe colour — galvanized grey. No powered/burnt/overloaded state
## variants like WireSegment has (no flow/pressure sim this phase — see
## WaterGraph.gd header) — just one constant material.
const COLOR_PIPE: Color = Color(0.45, 0.47, 0.49, 1.0)

## Dual quality/purity arrow lanes (Jul 2026) — pushed to the arrow overlay
## shader's quality_color/purity_color uniforms by WaterManager
## ._process_purity_and_dual_arrows(). PURITY_COLOR_PURIFIED is deliberately
## light-blue rather than green so it never reads as identical to
## WaterQualityColor.QUALITY_GOOD_COLOR's green in the adjacent quality lane.
const PURITY_COLOR_RAW:       Color = Color(1.0, 1.0, 1.0, 1.0)
const PURITY_COLOR_PURIFIED:  Color = Color(0.55, 0.85, 1.00, 1.0)

# ─── State ────────────────────────────────────────────────────────────────────
## WaterGraph edge ID — stored so the draw mode can unregister it on deconstruct.
var edge_id: String = ""

## Cost paid to place THIS segment specifically (set at spawn time by
## WaterPipeDrawMode._try_confirm_segment(), same per-leg value derived from
## this segment's own length × COST_PER_M). Source of truth for any refund
## path that needs to know "what did this segment cost" outside of
## BuildUndoStack's own transient per-entry dict — e.g.
## WaterHookup._delete_and_refund_edge() on reposition (see
## docs/systems/water/README.md Known tradeoffs, July 2026).
var placement_cost: int = 0

var point_a: Vector3 = Vector3.ZERO
var point_b: Vector3 = Vector3.ZERO

var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D  = null

## Deconstruct-mode hover highlight (Jul 2026) — mirrors WireSegment.gd's
## set_highlight_delete() exactly, including reusing WireSegment.COLOR_DELETE's
## literal value (not a new, possibly-slightly-different red) so both systems'
## delete-hover reads as the exact same shade to the player.
var _delete_highlight: bool = false

## Flow-direction arrow overlay (Jul 2026, build-mode only) — a second, thin
## MeshInstance3D layered on top of the pipe's own solid mesh, using
## pipe_flow.gdshader. Purely additive — the base pipe mesh/material above
## is NEVER touched by this (see file header "always visible" convention;
## this overlay's own visibility is build-mode-gated via the shader's
## build_mode_visible uniform, toggled by set_build_mode_visible(), NOT by
## hiding this whole node — matches WireSegment's group-based show/hide
## trigger point without altering the base pipe's own always-on visibility).
var _arrow_mesh_instance: MeshInstance3D = null
var _arrow_material: ShaderMaterial      = null
const _ARROW_SHADER_PATH: String = "res://assets/shaders/pipe_flow.gdshader"
const _ARROW_TEXTURE_PATH: String = "res://assets/textures/water/pipe_flow_arrow.png"
## Flat ribbon overlay (Jul 2026 rewrite, replaces the old wrap-around
## CylinderMesh + up-facing discard mask) — see docs/systems/water/README.md
## "Arrow shape distortion (kinked 'M' shapes)" section for the full
## root-cause writeup. A thin flat quad mounted just above the pipe's top
## surface instead of wrapped around its circumference: perfectly linear UV
## space by construction (no cosine distortion, no low-poly cylinder
## faceting), and cheaper to render (2 triangles vs. a 10-sided cylinder
## with 90%+ of its fragments discarded every frame).
const ARROW_RIBBON_WIDTH_SCALE: float = 2.2   ## ribbon width = PIPE_RADIUS * this
const ARROW_RIBBON_CLEARANCE:  float = 0.015  ## extra world-space gap above the pipe surface, avoids z-fighting
## Native content aspect ratio of pipe_flow_arrow.png's chevron drawing
## (Jul 2026 fix — "arrows stretched out lengthwise"). ROOT CAUSE: the
## texture-content-sub-range fix (see pipe_flow.gdshader's own comment)
## correctly cropped out the padding around each chevron, but nothing
## shrank `tile_world_length` to match — the arrow's actual ~35px-wide
## content was still being stretched across the FULL `tile_world_length`
## (a leftover arbitrary value from the old wrap-around-cylinder design,
## unrelated to this texture's real proportions), about 7.4x too long.
## `lane_v` (the shader's cross-width coordinate) maps the texture's FULL
## 64px height across the ribbon's entire physical width, so 1 texture
## pixel is worth `ribbon_width / 64` world units on EITHER axis for an
## undistorted arrow — this constant (measured content width ÷ full
## texture height, via direct pixel inspection) is used below to derive
## the correct, un-stretched `tile_world_length` from the ribbon's actual
## current width, rather than hardcoding a number that would silently go
## stale again if the ribbon's own dimensions ever change.
const ARROW_CONTENT_ASPECT: float = 35.0 / 64.0   ## content px width / full texture px height
## Ratio of the gap between one quality+purity PAIR and the next, relative
## to one arrow's own (now correctly-sized) length. Raised 0.225 -> 0.7
## (Jul 2026, Brannon's "more space between pairs" report) — the prior
## value read as too tight once the arrows themselves were correctly sized.
const ARROW_PAIR_GAP_RATIO: float = 0.7
## How much the purity tile's start is pulled EARLIER (closer to/slightly
## overlapping the quality tile), relative to one arrow's own length — see
## pipe_flow.gdshader's `intra_pair_gap` uniform comment for the exact
## math. New (Jul 2026, Brannon's "make quality/purity arrows closer to
## each other" report) — 0.0 would keep them flush (the size-fix's prior
## behavior); a modest positive value pulls them together without fully
## overlapping the two chevrons' opaque content.
const ARROW_INTRA_PAIR_GAP_RATIO: float = 0.3
## World-units/sec (NOT a UV-rate — see pipe_flow.gdshader's July 2026
## world-space-uniform rework: tile size and scroll speed are now both
## constant in world-space across all pipe lengths, so this value reads as
## "arrow travels this many meters per second" regardless of segment length).
## Slowed to 0.7x the original 1.2 (playtest feedback, July 2026) — the
## original speed read as too frantic at close range. Then sped back up
## 1.5x (same-day follow-up) once direction/continuity were confirmed fixed
## and the slower speed read as sluggish in practice.
const ARROW_SCROLL_SPEED: float = 1.2 * 0.7 * 1.5

## True for a temporary ghost/preview instance (see make_ghost_pipe()) — set
## BEFORE add_child() so _ready() can skip group registration for it.
##
## BUG FIX (July 2026, fourth playtest pass): ghost segments used to join
## "water_pipe_visual" unconditionally, same as real placed pipes — but
## WaterPipeDrawMode's avoidance/crossing logic (_avoid_existing_pipes()/
## _insert_crossings()) scans that exact group to mean "real, already-placed
## pipes to route around." _clear_ghost()'s queue_free() is deferred to the
## END of the frame, so the PREVIOUS frame's ghost segments were still alive
## (and still in the group) when the NEXT frame's _update_ghost_preview()
## ran its avoidance scan — the preview was detecting its OWN leftover ghost
## from a moment ago as a "conflict" and rerouting around it, then the next
## frame's ghost became the "conflict" for the frame after that, and so on —
## an oscillating feedback loop between two different reroutes every single
## frame. Symptoms exactly matched what was reported: rapidly changing
## "weird loop" layouts and a flickering cost label. FIX: ghost instances
## never join "water_pipe_visual" at all now.
var is_ghost: bool = false

func _ready() -> void:
	## Always visible — see file header. No group registration for the
	## WireSegment hide-on-exit-build-mode pattern (explicitly forbidden,
	## see docs/systems/water/README.md Forbidden edits).
	## "water_pipe_visual" is a DIFFERENT, additive-only group — pure
	## findability so WaterHookup.update_graph_node_position() and
	## WaterPipeDrawMode's avoidance/crossing logic can find REAL, placed
	## pipes — never used for show/hide, and (see is_ghost above) never
	## joined by a ghost/preview instance.
	visible = true
	if not is_ghost:
		add_to_group("water_pipe_visual")

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
	if _arrow_mesh_instance != null:
		_arrow_mesh_instance.queue_free()
		_arrow_mesh_instance = null

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

	if not is_ghost:
		_build_arrow_overlay(length)

	## Rebuild can happen while a delete-highlight is active (shouldn't in
	## practice — placed segments don't move — but stay consistent if it ever
	## does) — re-apply rather than silently losing the highlight.
	if _delete_highlight:
		_material.albedo_color = WireSegment.COLOR_DELETE
		_material.emission_enabled = true
		_material.emission = WireSegment.COLOR_DELETE
		_material.emission_energy_multiplier = 1.2

## Deconstruct-mode hover highlight — set/cleared by
## BuildModeController._process()'s deconstruct-tool hover scan, same
## pattern as WireSegment.set_highlight_delete().
func set_highlight_delete(on: bool) -> void:
	_delete_highlight = on
	if _material == null:
		return
	if on:
		_material.albedo_color = WireSegment.COLOR_DELETE
		_material.emission_enabled = true
		_material.emission = WireSegment.COLOR_DELETE
		_material.emission_energy_multiplier = 1.2
	else:
		_material.albedo_color = COLOR_PIPE
		_material.emission_enabled = false
		_material.emission_energy_multiplier = 0.0

## Flow-direction arrow overlay (Jul 2026 rewrite — flat ribbon, not a
## wrap-around cylinder). PRIOR approach: a thin CylinderMesh matching the
## pipe's orientation, with a per-fragment "is this facing up" discard mask
## in pipe_flow.gdshader restricting visibility to a ceiling-facing band.
## That band's cross-section coordinate was a raw normal-dot-up value (a
## COSINE of the angle around the pipe, non-linear) sampled across only ~3
## of the cylinder's 10 flat faces (PIPE_SEGMENTS) within the visible band —
## both effects combined to visibly warp/kink the arrow texture into a
## zigzag "M" shape instead of a clean chevron (reported Jul 2026).
##
## FIX: build a small flat quad ("ribbon") instead — perfectly linear UV
## space by construction (no cosine term, no faceting), mounted just above
## the pipe's top surface via a plain world-space Y offset (see
## ARROW_RIBBON_CLEARANCE), oriented along the pipe using the EXACT SAME
## look_at()+90-degree-local-X-rotate trick as the main pipe mesh (proven
## correct already by every prior arrow-continuity fix — same local-Y-is-
## length-axis convention, so pipe_flow.gdshader's VERTEX.y-based tiling/
## phase math needs zero changes for this rewrite).
## Ghost/preview pipes never get one (see is_ghost check above).
func _build_arrow_overlay(length: float) -> void:
	var arrow_shader: Shader = load(_ARROW_SHADER_PATH)
	var arrow_tex: Texture2D = load(_ARROW_TEXTURE_PATH)
	if arrow_shader == null or arrow_tex == null:
		## TEMP debug (Jul 2026, arrow-regression investigation) — if this
		## fires, _arrow_material stays null forever and every later
		## set_has_flow()/set_flow_sign()/set_phase_offset() call silently
		## no-ops (see their own `if _arrow_material != null` guards).
		print("[FlowDebug] _build_arrow_overlay ABORT edge_id=%s shader_ok=%s tex_ok=%s" % [
			edge_id, arrow_shader != null, arrow_tex != null])
		return

	## Flat quad, built directly rather than via a PrimitiveMesh — local Y
	## is the length axis (-length/2..+length/2, centered on origin, same
	## convention CylinderMesh.height used before), local X is the width
	## axis. UV.x (width) feeds pipe_flow.gdshader's lane_v directly; UV.y
	## isn't used by the shader (the along-pipe coordinate comes from
	## VERTEX.y, not mesh UV) but is still filled in for correctness.
	var half_width: float = PIPE_RADIUS * ARROW_RIBBON_WIDTH_SCALE * 0.5
	var half_len: float = length * 0.5
	var verts: PackedVector3Array = PackedVector3Array([
		Vector3(-half_width, -half_len, 0.0),
		Vector3( half_width, -half_len, 0.0),
		Vector3( half_width,  half_len, 0.0),
		Vector3(-half_width,  half_len, 0.0),
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	var normals: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX]  = indices

	var ribbon_mesh: ArrayMesh = ArrayMesh.new()
	ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_arrow_material = ShaderMaterial.new()
	_arrow_material.shader = arrow_shader
	_arrow_material.set_shader_parameter("arrow_texture", arrow_tex)
	_arrow_material.set_shader_parameter("scroll_speed", ARROW_SCROLL_SPEED)
	_arrow_material.set_shader_parameter("flow_sign", 1.0)
	## Defaults to no flow — a freshly-placed segment shows no water motion
	## until WaterManager.recompute_flow_directions() (fired right after
	## placement/every graph mutation) confirms this edge is actually
	## reachable from a hookup and calls set_has_flow(true). Prevents a
	## brand-new, still-disconnected pipe run from animating as if water
	## were already flowing through it (July 2026 fix).
	_arrow_material.set_shader_parameter("has_flow", false)
	## This segment's own real length — lets the shader keep arrow tile size
	## constant in world-space regardless of segment length (July 2026 fix).
	_arrow_material.set_shader_parameter("pipe_length", length)
	## Default to whatever build mode is doing RIGHT NOW, not always false —
	## pipes placed while already in build mode (the only time pipes ever get
	## placed) previously stayed dark until the player exited/re-entered build
	## mode, because nothing re-fires enter_build_mode()'s one-time group
	## broadcast for a segment that didn't exist yet when it fired. A fresh
	## segment now asks the current BuildModeController state directly instead
	## of waiting for the next broadcast.
	_arrow_material.set_shader_parameter("build_mode_visible", _is_build_mode_active())
	## Dual quality/purity lanes default to white/white (no visible tint
	## difference) until the first recompute_flow_directions() push — a
	## brand-new segment shouldn't flash a color guess before the graph has
	## actually resolved its quality/purity state.
	_arrow_material.set_shader_parameter("quality_color", PURITY_COLOR_RAW)
	_arrow_material.set_shader_parameter("purity_color", PURITY_COLOR_RAW)
	## Explicit named tunable, derived from the ribbon's ACTUAL current
	## width (Jul 2026 fix — "arrows stretched out lengthwise"; see
	## ARROW_CONTENT_ASPECT's own comment for the root cause). Both
	## `tile_world_length` (one arrow's own correctly-proportioned length)
	## and `gap_world_length` (spacing between pairs, kept proportional to
	## that corrected length rather than a now-mismatched fixed value) are
	## computed here instead of relying on the shader's own defaults, so
	## they can never silently drift out of sync with the ribbon's
	## dimensions again.
	var ribbon_width: float = PIPE_RADIUS * ARROW_RIBBON_WIDTH_SCALE
	var arrow_tile_length: float = ribbon_width * ARROW_CONTENT_ASPECT
	var arrow_pair_gap: float = arrow_tile_length * ARROW_PAIR_GAP_RATIO
	var arrow_intra_pair_gap: float = arrow_tile_length * ARROW_INTRA_PAIR_GAP_RATIO
	_arrow_material.set_shader_parameter("tile_world_length", arrow_tile_length)
	_arrow_material.set_shader_parameter("gap_world_length", arrow_pair_gap)
	_arrow_material.set_shader_parameter("intra_pair_gap", arrow_intra_pair_gap)

	_arrow_mesh_instance = MeshInstance3D.new()
	_arrow_mesh_instance.mesh = ribbon_mesh
	_arrow_mesh_instance.set_surface_override_material(0, _arrow_material)
	add_child(_arrow_mesh_instance)

	## Sit just above the pipe's top surface — a plain WORLD-space Y offset
	## (not a radial one, unlike the old cylinder's uniform ARROW_RADIUS_SCALE
	## scale-up) because this segment's own root position (`global_position`,
	## set to the segment midpoint earlier in _rebuild_mesh()) has zero
	## rotation — its local axes ARE world axes, just translated. A constant
	## +Y offset here therefore sits directly above the entire straight run
	## uniformly, correct for the horizontal pipe runs the ceiling-strip
	## look is meant for (see known vertical-riser limitation in the README).
	_arrow_mesh_instance.position = Vector3(0.0, PIPE_RADIUS + ARROW_RIBBON_CLEARANCE, 0.0)

	var arrow_dir: Vector3 = (point_b - point_a).normalized()
	var arrow_up: Vector3 = Vector3.UP
	if absf(arrow_dir.dot(arrow_up)) > 0.999:
		arrow_up = Vector3.RIGHT
	## Target computed from the ribbon's OWN (already vertically-offset)
	## global position, not the segment's — using the segment's un-offset
	## position here would introduce a slight tilt proportional to the
	## vertical offset, since the look_at direction wouldn't be exactly
	## `arrow_dir` anymore.
	_arrow_mesh_instance.look_at(_arrow_mesh_instance.global_position + arrow_dir, arrow_up)
	_arrow_mesh_instance.rotate_object_local(Vector3.RIGHT, PI * 0.5)

## Called by WaterManager.recompute_flow_directions() after any pipe-graph
## mutation. `a_is_upstream` true = scroll arrows from a->b (downstream),
## false = b->a.
func set_flow_sign(a_is_upstream: bool) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("flow_sign", 1.0 if a_is_upstream else -1.0)

## Called by WaterManager.recompute_flow_directions() alongside set_flow_sign()
## — `value` is this segment's upstream endpoint's cumulative REAL-WORLD
## distance from the hookup (world units, from WaterGraph.
## compute_flow_directions()'s phase_offset). Keeps the scrolling arrow
## texture's phase continuous across joints instead of restarting at 0 on
## every segment (July 2026 arrow continuity fix).
func set_phase_offset(value: float) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("phase_offset", value)

## Called by WaterManager.recompute_flow_directions() — true only when this
## segment's edge_id is present in WaterGraph.compute_flow_directions()'s
## result for the live hookup, i.e. this pipe run is actually reachable from
## a hookup and therefore has real water in it. False (no arrows at all, see
## pipe_flow.gdshader's has_flow discard) for any segment on a dead/orphaned
## run not connected to a hookup — no water, no flow, no arrows (July 2026).
func set_has_flow(value: bool) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("has_flow", value)

## Called by WaterManager._process_purity_and_dual_arrows() (Jul 2026, dual
## quality/purity arrow lanes) — tints the FRONT (quality) lane. `color` is
## already resolved via WaterQualityColor.get_color() by the caller; this
## setter doesn't re-derive it, matching the project's "managers own graph
## state, node scripts own their own visuals" split (the manager decides
## WHAT color, the segment just displays it).
func set_quality_color(color: Color) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("quality_color", color)

## Called alongside set_quality_color() — tints the BACK (purity) lane.
## `purified` true -> PURITY_COLOR_PURIFIED (light blue), false -> raw white.
func set_purified(purified: bool) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("purity_color",
			PURITY_COLOR_PURIFIED if purified else PURITY_COLOR_RAW)

## Reads BuildModeController's live is_active flag at the moment this segment
## spawns — same "get()" pattern WireGraphBuilder already uses for this exact
## check (see WireGraphBuilder.gd's `bc.get("is_active")` calls). Returns
## false (not just silently defaulting) if no controller is found so a
## missing/renamed node fails safe rather than lighting up outside build mode.
func _is_build_mode_active() -> bool:
	if not is_inside_tree():
		return false
	var bc: Node = get_tree().get_first_node_in_group("build_mode_controller")
	if bc == null:
		return false
	return bc.get("is_active") == true

## Toggled by BuildModeController.enter_build_mode()/exit_build_mode() via
## call_group("water_pipe_visual", "set_build_mode_visible", ...) — mirrors
## WireSegment's group-based visibility toggle, but only ever touches this
## overlay's shader uniform, never the base pipe mesh's own always-on
## visibility (see file header "Forbidden edits").
func set_build_mode_visible(value: bool) -> void:
	if _arrow_material != null:
		_arrow_material.set_shader_parameter("build_mode_visible", value)

## Creates a temporary visual pipe (no edge_id) for the drag/preview ghost —
## same static-helper convention as WireSegment.make_ghost_wire(). Caller must
## free it when done.
static func make_ghost_pipe(parent: Node, a: Vector3, b: Vector3) -> Node3D:
	var seg: Node3D = Node3D.new()
	var script: GDScript = load("res://scripts/world/water/WaterPipeSegment.gd")
	if script != null:
		seg.set_script(script)
	## MUST be set before add_child() — _ready() (which fires synchronously
	## during add_child()) reads this to decide whether to join
	## "water_pipe_visual". See is_ghost's own comment for the bug this fixes.
	seg.set("is_ghost", true)
	parent.add_child(seg)
	if seg.has_method("set_endpoints"):
		seg.call("set_endpoints", a, b)
	return seg
