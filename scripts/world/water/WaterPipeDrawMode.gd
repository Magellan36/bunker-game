extends Node
class_name WaterPipeDrawMode
## WaterPipeDrawMode.gd
## ─────────────────────────────────────────────────────────────────────────────
## The pipe placement tool. Instantiated/owned by BuildModeController the same
## way WireDrawMode is (see BuildModeController._setup_water_pipe_draw_mode()),
## activated while TOOL_WATER_PIPE is selected.
##
## ══════════════════════════════════════════════════════════════════════════
## ROUTING MODEL (rewritten per playtest feedback, July 2026):
## Pipes run along the "ceiling" (WATER_CEILING_Y — see that constant) in
## strictly axis-aligned (Manhattan/right-angle) segments — NO diagonal runs,
## ever. Every bend is exactly 90°. When a run reaches a connectable object
## that sits below ceiling height (e.g. WaterTestSink, registered at its own
## physical connection point — see WaterGraph node roles), the path runs
## horizontally at ceiling height directly above that object, then adds one
## final VERTICAL segment straight down into it — simulating a pipe dropping
## from the ceiling into the top of a floor-standing fixture. This ALSO keeps
## every angle exactly 90° (a vertical drop is still a right angle relative
## to the horizontal run before it).
##
## IMPLEMENTATION NOTE — FALLBACK INTERACTION MODEL (flagged per the
## groundwork plan's own explicit allowance, §5): one confirm per click, up
## to the next destination (existing node or a fresh mid-air waypoint), not
## the full single continuous-drag "paint the whole run" experience. Each
## confirm auto-inserts however many WaterPipeElbow corner nodes the
## Manhattan path needs (0–2 today: one horizontal bend, one drop-transition
## bend). Chaining several clicks end-to-end is how a player routes a run
## around multiple corners today. Upgrading to the full continuous-paint
## experience remains flagged follow-up work — see docs/systems/water/README.md.
## ══════════════════════════════════════════════════════════════════════════

## elbow_nodes: every WaterPipeElbow spawned for this confirmed segment (NOT
## included in seg_nodes, which is WaterPipeSegment only) — undo needs both
## lists to fully clean up the run. midpoint: for the undo refund float label
## (mirrors WireDrawMode.wire_placed's own midpoint arg).
signal pipe_placed(seg_nodes: Array, edge_ids: Array, cost: int, elbow_nodes: Array, midpoint: Vector3)
signal pipe_tool_exit_requested()

# ─── Config ───────────────────────────────────────────────────────────────────
## Height every horizontal pipe run travels at — near the ceiling (walls are
## 3.0m tall, see tile_set.tscn), above wall-light height (2.5m). MUST be kept
## equal to BuildModeController.WATER_HOOKUP_PLACEMENT_Y (see that constant's
## own comment) — two independent constants, same value, since this system
## stays standalone with zero dependency on BuildModeController's internals.
const WATER_CEILING_Y: float = 2.9

## Snap radius for picking an existing graph node (hookup/joint/corner) as the
## run's SOURCE point (phase 0) — mirrors WireDrawMode.SNAP_RADIUS.
const SOURCE_SNAP_RADIUS: float = 2.5

## Snap radius for picking an existing graph node as the run's DESTINATION
## (phase 1) — tighter than the source radius so casual corner-placement
## clicks don't accidentally snap onto a distant node. Checked in XZ only
## (ignores Y) since ground-level objects like WaterTestSink register well
## below WATER_CEILING_Y — see _get_nearest_water_node_xz().
const DEST_SNAP_RADIUS: float = 1.2

## Below this, two points are treated as the same point (degenerate segment
## skipped) — guards against zero-length pipe segments from floating-point
## noise or a click landing exactly on the source.
const MIN_POINT_GAP: float = 0.05

## Pricing (July 2026 playtest pass): 3x WireDrawMode.COST_PER_M ($8/m) per
## Brannon's explicit request — pipes are the pricier utility to run.
## Keep in sync manually if WireDrawMode.COST_PER_M ever changes (two
## independent constants, same reasoning as WATER_CEILING_Y above — the
## water system stays standalone with zero cross-file dependency).
const COST_PER_M: float = 24.0

## Ghost preview colours (July 2026 playtest pass) — mirrors
## BuildModeController._mat_valid/_mat_invalid's red-for-invalid convention.
## Applied to WaterPipeSegment's own `_material` (accessed via `.get()`, same
## way WireDrawMode._update_ghost_wire() swaps its ghost material's color).
const GHOST_COLOR_VALID:   Color = Color(0.55, 0.80, 0.90, 1.0)  ## light blue — normal preview
const GHOST_COLOR_INVALID: Color = Color(0.90, 0.20, 0.15, 1.0)  ## red — out of bounds / overlaps an existing pipe

# ─── External refs (set by BuildModeController, mirrors WireDrawMode) ────────
var camera:     Camera3D = null
var world_node: Node     = null
var build_hud:  CanvasLayer = null
var ray_length: float    = 50.0
## Back-reference to the owning BuildModeController — needed for
## _is_inside_bunker() (bounds check, July 2026 playtest pass). Set by
## BuildModeController._update_water_pipe_draw_refs(). Distinct from
## world_node (MainWorld) — this is the build controller itself.
var build_controller: BuildModeController = null

# ─── State ────────────────────────────────────────────────────────────────────
var _active:     bool    = false
var _phase:      int     = 0   ## 0 = picking source, 1 = dragging toward destination
var _source_key: String  = ""
var _source_pos: Vector3 = Vector3.ZERO

var _ghost_segs: Array[Node3D] = []   ## ghost WaterPipeSegments for the current preview

func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(false)

func activate() -> void:
	_active = true
	_phase  = 0
	_source_key = ""
	set_process(true)

func deactivate() -> void:
	_active = false
	_phase  = 0
	_source_key = ""
	_clear_ghost()

func _process(_delta: float) -> void:
	if not _active:
		return
	if _phase == 1:
		_update_ghost_preview()

## Called by BuildModeController._unhandled_input() while TOOL_WATER_PIPE is
## active — same delegation pattern as WireDrawMode.handle_input(). Returns
## true if the event was consumed.
func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _phase == 0:
				_try_pick_source()
			else:
				_try_confirm_segment()
			return true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			## RMB always exits the tool entirely now, regardless of phase —
			## matches E/Escape (July 2026 playtest pass: player should be
			## able to press E, RMB, or Escape to exit wire/pipe mode,
			## consistently, mirrors the identical WireDrawMode change).
			_phase = 0
			_source_key = ""
			_clear_ghost()
			pipe_tool_exit_requested.emit()
			return true

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			_phase = 0
			_source_key = ""
			_clear_ghost()
			pipe_tool_exit_requested.emit()
			return true

	return false


# ─── Phase 0: pick source ──────────────────────────────────────────────────────
func _try_pick_source() -> bool:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return false

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	var nearest: Dictionary = _get_nearest_water_node_xz(wm, cursor_pos, SOURCE_SNAP_RADIUS)
	if nearest.is_empty():
		_show_warning("Must start a pipe from the hookup or an existing pipe run")
		return false

	_source_key = nearest["key"]
	_source_pos = nearest["pos"]
	_phase = 1
	return true


# ─── Phase 1: drag + confirm ───────────────────────────────────────────────────
func _update_ghost_preview() -> void:
	_clear_ghost()

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	var dest: Dictionary = _resolve_destination(cursor_pos)
	if dest.is_empty():
		return

	var path: Array = _build_manhattan_path(_source_pos, dest["pos"])
	if path.size() < 2:
		return

	## Validity check (July 2026 playtest pass) — red preview + blocked
	## confirm if the path leaves the bunker or re-traces an existing pipe.
	var valid: bool = _is_path_valid(_get_wm(), path)

	for i in range(path.size() - 1):
		var seg: Node3D = WaterPipeSegment.make_ghost_pipe(_get_scene_root(), path[i], path[i + 1])
		var mat: StandardMaterial3D = seg.get("_material")
		if mat != null:
			mat.albedo_color = GHOST_COLOR_VALID if valid else GHOST_COLOR_INVALID
		_ghost_segs.append(seg)

func _try_confirm_segment() -> void:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	var dest: Dictionary = _resolve_destination(cursor_pos)
	if dest.is_empty():
		_show_warning("No valid pipe destination here")
		return

	var dest_pos: Vector3 = dest["pos"]
	var path: Array = _build_manhattan_path(_source_pos, dest_pos)
	if path.size() < 2:
		_show_warning("Pipe segment too short")
		return

	## Validity check (July 2026 playtest pass) — same test the ghost preview
	## uses (see _update_ghost_preview()), re-run here so a confirm click
	## can't slip through on a stale/last-good-frame ghost.
	if not _is_path_in_bounds(path):
		_show_warning("Cannot place pipe outside the bunker")
		return
	if _path_overlaps_existing(wm, path):
		_show_warning("A pipe is already placed there")
		return

	var total_length: float = 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))

	if world_node != null:
		if not world_node.spend_cash(cost):
			_show_warning("Not enough cash for this pipe run")
			return

	## ── Register a graph node for every intermediate bend + the final point ──
	## Every point in `path` except the first (the source, already has a key)
	## becomes a node: intermediate points are always "corner" bends (a
	## WaterPipeElbow is spawned for each); the LAST point re-uses an existing
	## node's key if the destination snapped onto one (see
	## _resolve_destination()), otherwise a fresh "pipe_joint".
	var keys: Array[String] = [_source_key]
	var elbow_nodes: Array = []
	for i in range(1, path.size()):
		var is_last: bool = (i == path.size() - 1)
		if is_last and not dest.get("existing_key", "").is_empty():
			keys.append(dest["existing_key"])
		elif is_last:
			keys.append(wm.register_node(path[i], "pipe_joint"))
		else:
			var corner_key: String = wm.register_node(path[i], "corner")
			var elbow: WaterPipeElbow = WaterPipeElbow.new()
			_get_scene_root().add_child(elbow)
			elbow.global_position = path[i]
			elbow.node_key = corner_key
			keys.append(corner_key)
			elbow_nodes.append(elbow)

	## ── Register edges + spawn real segments for each leg of the path ──
	var seg_nodes: Array = []
	var edge_ids:  Array = []
	for i in range(keys.size() - 1):
		var edge_id: String = wm.register_edge(keys[i], keys[i + 1])
		if edge_id.is_empty():
			continue
		var seg: WaterPipeSegment = WaterPipeSegment.new()
		_get_scene_root().add_child(seg)
		seg.edge_id = edge_id
		seg.set_endpoints(path[i], path[i + 1])
		seg_nodes.append(seg)
		edge_ids.append(edge_id)

	var undo_midpoint: Vector3 = (path[0] + path[path.size() - 1]) * 0.5
	## Floating "-$X" label at the moment of spend — mirrors the "+$X" refund
	## label BuildUndoStack's "pipe" case already shows on undo (July 2026
	## playtest pass; see docs/systems/water/README.md).
	_spawn_float_label(undo_midpoint, cost, false)
	pipe_placed.emit(seg_nodes, edge_ids, cost, elbow_nodes, undo_midpoint)

	## Chain the next segment from this destination — matches the "click
	## again to keep extending the run" flow implied by the fallback model.
	## If the destination was an existing node's connection point (e.g. a
	## sink's top), further extension isn't really meaningful — but there's
	## no harm allowing it (mirrors a real plumbing T-off point).
	_source_key = keys[keys.size() - 1]
	_source_pos = path[path.size() - 1]
	_clear_ghost()


## Builds the strictly-axis-aligned (90°-only) world-space point list from
## `from_pos` to `to_pos`. `from_pos` is assumed to already be at
## WATER_CEILING_Y (true for the hookup and every existing joint/corner
## node) — clamped defensively anyway. Produces, in order:
##   1. start (at ceiling height)
##   2. an optional single horizontal bend, if the destination isn't already
##      directly north/south/east/west of the source
##   3. the point directly above the destination, at ceiling height
##   4. an optional final vertical drop, if the destination isn't itself at
##      ceiling height (i.e. it's a floor-standing connectable object)
## Degenerate/coincident points are skipped via _append_if_distinct(), so a
## perfectly axis-aligned or already-ceiling-height destination correctly
## collapses to a shorter list rather than emitting zero-length segments.
func _build_manhattan_path(from_pos: Vector3, to_pos: Vector3) -> Array:
	var path: Array = []
	var start: Vector3 = Vector3(from_pos.x, WATER_CEILING_Y, from_pos.z)
	_append_if_distinct(path, start)

	var ceiling_to: Vector3 = Vector3(to_pos.x, WATER_CEILING_Y, to_pos.z)
	var dx: float = absf(ceiling_to.x - start.x)
	var dz: float = absf(ceiling_to.z - start.z)
	if dx > MIN_POINT_GAP and dz > MIN_POINT_GAP:
		## Shorter-axis-first heuristic (July 2026 playtest pass — flipped
		## from the original "longer leg first"). Rationale: the source is
		## usually the wall-mounted hookup (or a run chained from it), where
		## the axis PERPENDICULAR to the wall (into the room) is typically
		## the larger of the two distances to a far destination, and the
		## axis PARALLEL to the wall is typically the smaller one. Long-leg-
		## first therefore put the perpendicular "jut straight out into the
		## room" leg FIRST most of the time — exactly the "hangs outward"
		## look Brannon flagged. Short-leg-first instead runs the (usually
		## small, usually wall-parallel) leg first and saves the long
		## (usually wall-perpendicular) leg for last, so the run hugs close
		## to the source wall for as long as possible before cutting across
		## the room. No explicit wall-orientation data needed — this is a
		## generic heuristic that happens to match the common case; it's
		## never wrong (still a valid 90°-only Manhattan path either way),
		## just a different aesthetic default when the source isn't
		## wall-mounted (e.g. chaining from a mid-room corner/joint).
		var corner: Vector3
		if dx <= dz:
			corner = Vector3(ceiling_to.x, WATER_CEILING_Y, start.z)
		else:
			corner = Vector3(start.x, WATER_CEILING_Y, ceiling_to.z)
		_append_if_distinct(path, corner)
	_append_if_distinct(path, ceiling_to)

	if absf(to_pos.y - WATER_CEILING_Y) > MIN_POINT_GAP:
		_append_if_distinct(path, to_pos)

	return path

func _append_if_distinct(path: Array, p: Vector3) -> void:
	if path.is_empty() or path[path.size() - 1].distance_to(p) > MIN_POINT_GAP:
		path.append(p)


## Resolves the cursor's destination this frame: snaps onto an existing water
## graph node (any role — hookup/joint/corner/endpoint) within
## DEST_SNAP_RADIUS of the cursor's XZ position if one exists and isn't the
## current source itself; otherwise a fresh mid-air waypoint directly above
## the cursor at ceiling height. No wall detection, no freehand/Shift
## override — every destination this phase produces is reachable via a
## strictly axis-aligned path (see _build_manhattan_path()).
func _resolve_destination(cursor_pos: Vector3) -> Dictionary:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return {}

	var cursor_xz: Vector3 = Vector3(cursor_pos.x, WATER_CEILING_Y, cursor_pos.z)
	var nearest: Dictionary = _get_nearest_water_node_xz(wm, cursor_xz, DEST_SNAP_RADIUS)
	if not nearest.is_empty() and nearest["key"] != _source_key:
		return { "pos": nearest["pos"], "existing_key": nearest["key"] }

	return { "pos": _grid_snap_xz(cursor_xz) }


## Same 0.25 m grid every other placeable in the game snaps to
## (BuildModeController.grid_size / PowerManager.SNAP_GRID / WireDrawMode's
## own _WIRE_GRID) — kept as its own constant here rather than a cross-file
## reference, matching how WATER_CEILING_Y/COST_PER_M are already handled
## in this file (water system stays standalone, values kept in sync by hand).
## Only X/Z are snapped — Y is always WATER_CEILING_Y already, set by the
## caller before this runs.
const _PIPE_GRID: float = 0.25

func _grid_snap_xz(pos: Vector3) -> Vector3:
	return Vector3(
		roundf(pos.x / _PIPE_GRID) * _PIPE_GRID,
		pos.y,
		roundf(pos.z / _PIPE_GRID) * _PIPE_GRID
	)

## Finds the nearest registered water graph node (any role) within `radius`
## of `pos`, compared in the XZ plane only (ignores Y) — ground-level
## connectable objects (e.g. WaterTestSink, registered at their own physical
## connection point, well below WATER_CEILING_Y) must still be findable while
## the cursor projection itself is always at ceiling height.
func _get_nearest_water_node_xz(wm: WaterManager, pos: Vector3, radius: float) -> Dictionary:
	var best_dist: float = radius
	var best: Dictionary = {}
	var flat_pos: Vector2 = Vector2(pos.x, pos.z)
	for key: String in wm.get_nodes():
		var data: Dictionary = wm.get_node_data(key)
		var node_pos: Vector3 = data.get("pos", Vector3.ZERO)
		var d: float = flat_pos.distance_to(Vector2(node_pos.x, node_pos.z))
		if d < best_dist:
			best_dist = d
			best = { "key": key, "pos": node_pos }
	return best


# ─── Helpers ──────────────────────────────────────────────────────────────────
func _clear_ghost() -> void:
	for seg: Node3D in _ghost_segs:
		if is_instance_valid(seg):
			seg.queue_free()
	_ghost_segs.clear()

func _get_wm() -> WaterManager:
	return get_tree().get_first_node_in_group("water_manager") as WaterManager

func _get_scene_root() -> Node3D:
	if world_node != null and world_node is Node3D:
		return world_node as Node3D
	return get_tree().get_first_node_in_group("world") as Node3D

func _get_cursor_world_pos() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir:  Vector3 = camera.project_ray_normal(mouse_pos)
	## Intersect with the horizontal plane at ceiling height — pipes are
	## routed/placed at this height, so the cursor's "world position" for
	## this tool means "where on the ceiling plane is the player pointing,"
	## same simple ground-plane-projection approach WireDrawMode uses (just
	## at a different fixed height).
	if absf(dir.y) < 0.0001:
		return from
	var t: float = (WATER_CEILING_Y - from.y) / dir.y
	if t < 0.0:
		return from
	return from + dir * t

## Mirrors WireDrawMode._show_warning()'s exact lookup path — HUD.gd's
## show_soft_warning(), NOT anything on build_hud (BuildModeHUD has no
## generic warning-text API — see docs/systems/ui/README.md).
func _show_warning(msg: String) -> void:
	if world_node != null:
		var main_hud: Node = world_node.get_node_or_null("HUD")
		if main_hud != null and main_hud.has_method("show_soft_warning"):
			main_hud.show_soft_warning(msg)
			return
	push_warning("[WaterPipeDrawMode] " + msg)

## Floating "+$X"/"-$X" screen-space label — same HUD.spawn_float_label()
## call BuildModeController._spawn_float_label_at_pos() uses for tile
## place/remove, duplicated here rather than referenced (water system stays
## standalone from BuildModeController's internals, same reasoning as
## _show_warning() above). positive=true → green refund, false → red spend.
func _spawn_float_label(world_pos: Vector3, amount: int, positive: bool) -> void:
	if camera == null or amount == 0 or world_node == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	var main_hud: Node = world_node.get_node_or_null("HUD")
	if main_hud != null and main_hud.has_method("spawn_float_label"):
		main_hud.spawn_float_label(screen_pos, amount, positive)

# ─── Placement validity (July 2026 playtest pass) ────────────────────────────
## True if EVERY point in `path` lies within the bunker's valid placeable
## area, tightened inward by one full grid tile (_PIPE_GRID = 0.25m) versus
## the shared BuildModeController._is_inside_bunker() check.
## WHY the extra inset: _is_inside_bunker()'s own MARGIN is only 0.1m (less
## than half a grid cell) — fine for walls/lights which sit flush against the
## boundary by design, but it let a pipe run land right at/through the wall
## plane itself, reading as "placeable 1 tile too far out" (reported during
## playtest). Rather than loosen/change _is_inside_bunker() itself (many other
## placement systems depend on its exact current tuning), pipes get their own
## tighter rectangle check first; a point inside the tightened rectangle is
## always valid, and a point outside it still falls back to the shared
## dug-chunk check (expanded areas) since we can't cheaply apply the same
## per-tile inset to arbitrary dug-chunk shapes.
const _BOUNDS_INSET: float = _PIPE_GRID

func _is_path_in_bounds(path: Array) -> bool:
	if build_controller == null or build_controller.rock_surround == null:
		return true   ## No bounds data available — fail open, matches _is_inside_bunker()'s own fallback.
	var rs: Node = build_controller.rock_surround
	var ox: float = rs.OFFSET_X
	var oz: float = rs.OFFSET_Z
	var depth: int = rs.bunker_depth
	var width: int = rs.bunker_width
	var min_x: float = ox + _BOUNDS_INSET
	var max_x: float = ox + float(depth) - _BOUNDS_INSET
	var min_z: float = oz + _BOUNDS_INSET
	var max_z: float = oz + float(width) - _BOUNDS_INSET

	for p: Vector3 in path:
		if p.x >= min_x and p.x <= max_x and p.z >= min_z and p.z <= max_z:
			continue   ## Inside the tightened base rectangle — valid.
		## Outside the tightened rectangle — fall back to the shared, looser
		## check (handles dug/expanded chunks beyond the original rectangle).
		if not build_controller._is_inside_bunker(p):
			return false
	return true

## True if any leg of `path` exactly re-traces an already-registered pipe
## edge. Computed via WaterGraph's own static key/id functions directly on
## raw positions — deliberately does NOT require the positions to already be
## registered graph nodes, so this works as a pure preview-time lookup.
## KNOWN LIMITATION: only catches an exact endpoint-to-endpoint duplicate
## (re-tracing the same run) — a new pipe crossing an existing one at a
## perpendicular mid-span point is not detected (would need real segment-
## intersection math, out of scope for this pass).
func _path_overlaps_existing(wm: WaterManager, path: Array) -> bool:
	if wm == null:
		return false
	for i in range(path.size() - 1):
		var key_a: String = WaterGraph.make_node_key(path[i])
		var key_b: String = WaterGraph.make_node_key(path[i + 1])
		var candidate_id: String = WaterGraph.make_edge_id(key_a, key_b)
		if wm.has_edge(candidate_id):
			return true
	return false

func _is_path_valid(wm: WaterManager, path: Array) -> bool:
	if not _is_path_in_bounds(path):
		return false
	if _path_overlaps_existing(wm, path):
		return false
	return true
