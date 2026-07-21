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
const ARROW_RADIUS_SCALE: float = 1.03   ## just outside the pipe's own radius, avoids z-fighting
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

## Flow-direction arrow overlay (Jul 2026) — a thin cylinder, same length as
## the pipe, matching orientation, drawn just outside the pipe's own radius.
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

	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = PIPE_RADIUS * ARROW_RADIUS_SCALE
	cyl.bottom_radius = PIPE_RADIUS * ARROW_RADIUS_SCALE
	cyl.height        = length
	cyl.radial_segments = PIPE_SEGMENTS

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

	var arrow_dir: Vector3 = (point_b - point_a).normalized()
	var arrow_up: Vector3 = Vector3.UP
	if absf(arrow_dir.dot(arrow_up)) > 0.999:
		arrow_up = Vector3.RIGHT

	_arrow_mesh_instance = MeshInstance3D.new()
	_arrow_mesh_instance.mesh = cyl
	_arrow_mesh_instance.set_surface_override_material(0, _arrow_material)
	add_child(_arrow_mesh_instance)
	_arrow_mesh_instance.look_at(global_position + arrow_dir, arrow_up)
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
