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
const GHOST_COLOR_INVALID: Color = Color(0.90, 0.20, 0.15, 1.0)  ## red — out of bounds

## T-split-anywhere + no-overlap routing (July 2026, third playtest pass).
## Radius for snapping to a POINT along an existing pipe's mid-span (not
## just its two endpoints) when picking a source or destination — lets a
## player start/end a run anywhere on a placed pipe, not only at a
## registered node. Tighter than DEST_SNAP_RADIUS so it doesn't compete with
## real node snapping.
const SPLIT_SNAP_RADIUS: float = 0.6
## A mid-span candidate this close to either of the segment's own endpoints
## is treated as "that endpoint" instead — real node-snapping already
## handles that case, no need to split right next to an existing node.
const SPLIT_ENDPOINT_EXCLUDE: float = 0.2
## Sidestep distance when routing around a collinear/overlapping existing
## pipe (see _avoid_existing_pipes()) — one full grid tile plus a bit, so
## the detour reads as a deliberate loop, not a graze.
const DETOUR_OFFSET: float = 0.5
## Lateral tolerance for "same line" in _leg_collinear_overlaps() (July
## 2026, sixth playtest pass) — widened from the old MIN_POINT_GAP (0.05m)
## to 2x the pipe's own physical radius (WaterPipeSegment.PIPE_RADIUS).
## Two pipes laterally offset by less than this still visually touch/clip
## into each other given their real tube thickness, even when they're not
## on the mathematically EXACT same line — the old tight tolerance let a
## new pipe run right alongside (and visually cross) an existing one that
## was off by just a few centimeters, most commonly traced back to the
## hookup's own non-grid-aligned wall-snap position propagating a slightly
## off-grid line (see WaterHookup._grid_snap_along_wall(), added this pass).
const COLLINEAR_LATERAL_TOLERANCE: float = WaterPipeSegment.PIPE_RADIUS * 2.0

# ─── Debug (July 2026, seventh playtest pass) ────────────────────────────────
## Flip false to silence all [PipeDebug] prints. Kept ON per Brannon's
## explicit request to nail down why pipes are still being routed/placed
## oddly after the last fix — matches the project's standing WIRE_DEBUG
## convention (see WireDrawMode.gd/BuildModeController.gd), don't strip
## until he explicitly asks for this stable.
const PIPE_DEBUG: bool = true
func _pdbg(msg: String) -> void:
	if PIPE_DEBUG:
		print(msg)

## ─── Continuous paint-along-wall mode (Part B, combined refactor pass) ──────
## Flip false to instantly fall back to the old "one confirm per click, one
## leg at a time" model above (_try_confirm_segment()/_update_ghost_preview
## body, kept fully intact and callable — see _update_ghost_preview_single_leg()
## and the early-return in _try_confirm_full_path()). Per the original plan's
## own explicit recommendation (§A.6) given this is the most complex change
## in this pass — flip to false first if the paint UX has rough edges, no
## code deletion needed to recover the old behavior.
const PAINT_MODE_ENABLED: bool = true

## Defensive cap on how many existing-node hops _trace_wall_hugging_path()
## will chain through in one frame/click — guards against a pathological
## graph (a long chain of tightly-packed nodes) ever hanging the tool.
const MAX_TRACE_LEGS: int = 20

## ─── Wall-locked pipe routing (Jul 2026) ────────────────────────────────────
## Default routing mode for a run whose destination resolves to open floor
## space (see _resolve_destination() — no existing node, no mid-span split):
## route along the bunker's wall perimeter (_trace_wall_locked_path(), via
## WallPerimeterRegistry) instead of a raw diagonal-shortest Manhattan cut
## across the room. Hold CTRL to fall back to the pre-existing freeform
## routing (_trace_wall_hugging_path()) for either mode — see the two call
## sites in _update_ghost_preview()/_try_confirm_full_path(). An anchored
## destination (existing node / mid-span split) always keeps using the
## freeform trace regardless of this flag — it's already a valid real
## connection point, wall-locking only applies to fresh open-floor runs.
## Flip to false to instantly disable wall-locking everywhere (falls back
## to freeform unconditionally), no code deletion needed to recover.
const WALL_LOCKED_ROUTING_ENABLED: bool = true

## Dumps every currently-registered REAL pipe segment (via "water_pipe_visual"
## — ghosts never join that group, see WaterPipeSegment.is_ghost) so a debug
## session has full context on what the tool thinks already exists,
## alongside a fresh placement attempt's own log lines.
func _dump_pipe_network() -> void:
	_pdbg("[PipeDebug] ── current water_pipe_visual network ──")
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		count += 1
		_pdbg("[PipeDebug]   seg edge_id=%s  a=%s  b=%s" % [seg.edge_id, seg.point_a, seg.point_b])
	_pdbg("[PipeDebug] ── %d real segment(s) total ──" % count)

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

## Live cost label — Label3D floating at path midpoint during phase 1 drag.
## Mirrors WireDrawMode._cost_label exactly (same reuse-not-recreate
## pattern) — added July 2026 per Brannon's request for pipes to get the
## same live cost preview wires already have.
var _cost_label: Label3D = null

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
	_clear_cost_label()

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
				_try_confirm_full_path()
			return true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			## Cancels the in-progress placement and stays IN the pipe tool
			## (July 2026 correction — a prior pass wrongly made this exit
			## all the way back to Construct tool; Brannon flagged that E
			## "isn't working" because it was really just leaving pipe mode
			## entirely, which was never the ask). Does NOT emit
			## pipe_tool_exit_requested — that signal now only fires from
			## an actual tool-switch elsewhere (toolbar button).
			_phase = 0
			_source_key = ""
			_clear_ghost()
			_clear_cost_label()
			return true

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			## Same correction as RMB above — cancels the current
			## drag/placement, stays in the pipe tool. No tool-exit.
			_phase = 0
			_source_key = ""
			_clear_ghost()
			_clear_cost_label()
			return true

	return false


# ─── Phase 0: pick source ──────────────────────────────────────────────────────
func _try_pick_source() -> bool:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return false

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	_pdbg("[PipeDebug] ══════ pick source ══════  cursor_pos=%s" % cursor_pos)
	_dump_pipe_network()
	var nearest: Dictionary = _get_nearest_water_node_xz(wm, cursor_pos, SOURCE_SNAP_RADIUS)
	if not nearest.is_empty():
		_source_key = nearest["key"]
		_source_pos = nearest["pos"]
		_phase = 1
		_pdbg("[PipeDebug] source = existing node key=%s pos=%s" % [_source_key, _source_pos])
		return true

	## T-split anywhere (July 2026, third playtest pass): no existing NODE
	## nearby, but the cursor might be hovering an existing pipe's mid-span
	## — split it right there and start the new branch from that point.
	## Extends the pre-existing "start from any existing node (hookup/
	## joint/corner)" T-split support to "start from any POINT on a placed
	## pipe run" per Brannon's explicit request.
	var split: Dictionary = _find_split_candidate(wm, cursor_pos, true)
	if not split.is_empty():
		var new_key: String = _split_pipe_at(wm, split)
		_pdbg("[PipeDebug] source = split at %s -> new_key=%s" % [split.get("pos", Vector3.ZERO), new_key])
		if not new_key.is_empty():
			_source_key = new_key
			_source_pos = split["pos"]
			_phase = 1
			return true

	_pdbg("[PipeDebug] source pick FAILED — no node or splittable pipe within range")
	_show_warning("Must start a pipe from the hookup or an existing pipe run")
	return false


# ─── Phase 1: drag + confirm ───────────────────────────────────────────────────
## Pure computation for ONE leg's ghost/validity data, extracted verbatim
## from this function's old single-leg body (Part B, combined refactor
## pass) — no behavior change versus the pre-extraction version when
## PAINT_MODE_ENABLED is false (see _update_ghost_preview_single_leg(),
## which still calls the exact same three functions in the exact same
## order). `debug` forwards to _resolve_destination()/_avoid_existing_pipes()/
## _is_path_in_bounds() — MUST stay false for any per-frame caller.
## Returns {} on failure (no destination, or a degenerate <2-point path).
func _resolve_single_leg(from_pos: Vector3, cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	var dest: Dictionary = _resolve_destination(cursor_pos, debug)
	if dest.is_empty():
		return {}
	var raw_path: Array = _build_manhattan_path(from_pos, dest["pos"])
	if raw_path.size() < 2:
		return {}
	var path: Array = _avoid_existing_pipes(raw_path, debug)
	var valid: bool = _is_path_in_bounds(path, debug)
	return { "dest": dest, "path": path, "valid": valid }

func _get_pillar_registry() -> PillarRegistry:
	return get_tree().get_first_node_in_group("pillar_registry") as PillarRegistry

func _get_wall_perimeter_registry() -> WallPerimeterRegistry:
	return get_tree().get_first_node_in_group("wall_perimeter_registry") as WallPerimeterRegistry

## Small clearance buffer added on top of PillarRegistry.PILLAR_CLEARANCE_RADIUS
## for the dogleg's two jog segments below — the radius alone would put a new
## segment exactly tangent to the pillar (zero margin); this pushes it solidly
## clear instead.
const _PILLAR_DOGLEG_MARGIN: float = 0.12

## Root-cause fix (July 2026, corner-pillar clip investigation): a wall-
## hugging elbow that lands inside a pillar's clearance radius used to just
## get shoved radially away from the pillar's center — but that moves BOTH
## the incoming leg's shared axis AND the outgoing leg's shared axis at once,
## breaking the strict 90°-only routing this tool otherwise guarantees (the
## visible "diagonal clip" bug). Replaces that single corner with a small
## 3-point rectangular "step" detour around the pillar instead: extend the
## incoming leg a bit further along its own axis, jog sideways by one short
## perpendicular segment, then correct back onto the outgoing leg's axis.
## Every resulting segment stays axis-aligned; `prev_pt`/`next_pt` (the
## leg's real endpoints) are never touched. Returns `[corner]` unchanged
## when no pillar is actually violated there.
## Assumes `corner` already sits exactly on both prev_pt's shared axis and
## next_pt's shared axis — true for every corner _build_manhattan_path()
## produces (see that function's header for the two cases this mirrors).
func _dogleg_corner_around_pillars(prev_pt: Vector3, corner: Vector3, next_pt: Vector3, registry: PillarRegistry) -> Array:
	if registry == null:
		return [corner]

	## Find the pillar actually violated at this corner (first one found —
	## in practice a corner sits near at most one of the four registry
	## entries at a time given how far apart they are).
	var violated_center: Vector2 = Vector2.ZERO
	var found: bool = false
	for pillar_pos: Vector3 in registry.get_all_positions().values():
		var center: Vector2 = Vector2(pillar_pos.x, pillar_pos.z)
		if Vector2(corner.x, corner.z).distance_to(center) < PillarRegistry.PILLAR_CLEARANCE_RADIUS:
			violated_center = center
			found = true
			break
	if not found:
		return [corner]

	var offset: float = PillarRegistry.PILLAR_CLEARANCE_RADIUS + _PILLAR_DOGLEG_MARGIN
	var dir: Vector2 = Vector2(corner.x, corner.z) - violated_center
	dir = Vector2(1.0, 0.0) if dir.length() < 0.0001 else dir.normalized()
	var sign_x: float = 1.0 if dir.x >= 0.0 else -1.0
	var sign_z: float = 1.0 if dir.y >= 0.0 else -1.0

	## Incoming leg is vertical (prev_pt shares corner's X) in one
	## _build_manhattan_path() case, horizontal (prev_pt shares corner's Z)
	## in the other — mirror the step order accordingly so the detour
	## always ends back exactly on the axis the outgoing leg needs.
	var incoming_is_vertical: bool = absf(prev_pt.x - corner.x) < MIN_POINT_GAP

	var step1: Vector3
	var step2: Vector3
	var step3: Vector3
	if incoming_is_vertical:
		step1 = Vector3(corner.x, corner.y, corner.z + sign_z * offset)
		step2 = Vector3(corner.x + sign_x * offset, corner.y, corner.z + sign_z * offset)
		step3 = Vector3(corner.x + sign_x * offset, corner.y, corner.z)
	else:
		step1 = Vector3(corner.x + sign_x * offset, corner.y, corner.z)
		step2 = Vector3(corner.x + sign_x * offset, corner.y, corner.z + sign_z * offset)
		step3 = Vector3(corner.x, corner.y, corner.z + sign_z * offset)

	return [step1, step2, step3]

## True if the straight leg [a,b] never passes within
## PillarRegistry.PILLAR_CLEARANCE_RADIUS of any pillar's center, checked via
## the same closest-point-on-segment math used for pipe-vs-pipe checks
## (_closest_point_on_segment_xz). Vertical drops (into a floor device) are
## skipped — pillars are a ceiling-height horizontal-run concern only. A mid-
## leg clip is treated as an INVALID placement (red ghost / blocked confirm),
## explicitly NOT a pathfind-around — see this file's Part B header note.
func _leg_clears_all_pillars(a: Vector3, b: Vector3, registry: PillarRegistry) -> bool:
	if registry == null:
		return true
	if absf(a.y - b.y) > MIN_POINT_GAP:
		return true   ## vertical drop — not a pillar-relevant leg
	for pillar_pos: Vector3 in registry.get_all_positions().values():
		var closest: Vector3 = _closest_point_on_segment_xz(pillar_pos, a, b)
		var d: float = Vector2(closest.x, closest.z).distance_to(Vector2(pillar_pos.x, pillar_pos.z))
		if d < PillarRegistry.PILLAR_CLEARANCE_RADIUS:
			return false
	return true

## Continuous paint-along-wall tracing (Part B). Starting from
## `source_pos`/`source_key`, repeatedly resolves one leg toward
## `cursor_pos` via _resolve_single_leg(), chaining through an existing
## graph node's key when the resolved destination is itself an existing
## node that's still short of the true cursor position (i.e. the run is
## "hugging" through already-placed joints on the way there) — see this
## file's Part B header for the full documented interpretation call. Stops
## (does not chain further) as soon as a leg's destination is either a
## fresh mid-air waypoint (existing_key empty) or already within
## DEST_SNAP_RADIUS of the true cursor position, or after MAX_TRACE_LEGS
## hops (defensive cap). Applies pillar clearance per new corner point and
## per new leg (see _dogleg_corner_around_pillars()/_leg_clears_all_pillars())
## before appending — a mid-leg pillar clip marks the whole trace invalid
## (red ghost) rather than rerouting.
## Returns {"waypoints":Array[Vector3], "waypoint_keys":Array[String],
## "valid":bool, "final_key":String}. waypoint_keys[i] is "" for a fresh
## corner, or the existing graph node key for a point that already exists
## (index 0 is always source_key).
func _trace_wall_hugging_path(source_pos: Vector3, source_key: String, cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	var registry: PillarRegistry = _get_pillar_registry()
	var waypoints: Array = [source_pos]
	var waypoint_keys: Array = [source_key]
	var current_pos: Vector3 = source_pos
	var current_key: String = source_key
	var valid: bool = true

	## _resolve_destination() (called inside _resolve_single_leg()) excludes
	## whatever node currently sits in the `_source_key` member when
	## snapping to an existing node — save/restore it since we drive that
	## member directly as `current_key` advances through the chain.
	var saved_source_key: String = _source_key
	_source_key = current_key

	for _i in range(MAX_TRACE_LEGS):
		var leg: Dictionary = _resolve_single_leg(current_pos, cursor_pos, debug)
		if leg.is_empty():
			valid = false
			break
		var leg_path: Array = leg["path"]
		if not leg["valid"]:
			valid = false

		for j in range(1, leg_path.size()):
			var is_leg_last_point: bool = (j == leg_path.size() - 1)
			var raw_pt: Vector3 = leg_path[j]
			var prev_pt: Vector3 = waypoints[waypoints.size() - 1]

			if is_leg_last_point:
				if not _leg_clears_all_pillars(prev_pt, raw_pt, registry):
					valid = false
				waypoints.append(raw_pt)
				waypoint_keys.append(leg["dest"].get("existing_key", ""))
			else:
				## Root-cause fix (July 2026): a violating corner now gets
				## replaced with a small axis-aligned "step" detour instead
				## of a single radial nudge — see _dogleg_corner_around_
				## pillars()'s own header for why the old approach broke
				## 90°-only routing. leg_path[j+1] always exists here since
				## `is_leg_last_point` is false.
				var next_pt: Vector3 = leg_path[j + 1]
				var steps: Array = _dogleg_corner_around_pillars(prev_pt, raw_pt, next_pt, registry)
				for step_pt: Vector3 in steps:
					if not _leg_clears_all_pillars(prev_pt, step_pt, registry):
						valid = false
					waypoints.append(step_pt)
					waypoint_keys.append("")
					prev_pt = step_pt

		var dest: Dictionary = leg["dest"]
		var existing_key: String = dest.get("existing_key", "")
		var advanced: float = current_pos.distance_to(dest["pos"])
		var dist_to_cursor: float = Vector2(dest["pos"].x, dest["pos"].z).distance_to(Vector2(cursor_pos.x, cursor_pos.z))
		current_pos = dest["pos"]

		if not existing_key.is_empty() and dist_to_cursor > DEST_SNAP_RADIUS and advanced > MIN_POINT_GAP:
			current_key = existing_key
			_source_key = current_key
			continue
		else:
			current_key = existing_key
			break

	_source_key = saved_source_key
	return { "waypoints": waypoints, "waypoint_keys": waypoint_keys, "valid": valid, "final_key": current_key }

## Wall-locked routing (Jul 2026) — the new default for a run whose
## destination resolves to open floor space; see WALL_LOCKED_ROUTING_ENABLED's
## own comment for when this is used vs. the freeform _trace_wall_hugging_path()
## above. Returns the exact same dict shape so it plugs into the same
## downstream node/edge/segment spawning loop in _try_confirm_full_path()
## with zero duplication there.
##
## Shape: source_pos -> (Manhattan entry leg) -> BFS wall-perimeter path
## (WallPerimeterRegistry.find_path_along_wall(), reprojected from the
## registry's own electrical PLACEMENT_Y to WATER_CEILING_Y) -> (Manhattan
## exit leg) -> dest_pos. Every hop between consecutive raw points (source,
## each wall waypoint, dest) is individually re-run through the existing
## _build_manhattan_path() — this is what keeps every resulting segment
## strictly axis-aligned even where two consecutive registry wall-segment
## entries are diagonally adjacent at a convex corner (~0.707m apart, not
## collinear — see WallPerimeterRegistry.ADJACENCY_RADIUS's own comment);
## _build_manhattan_path() already inserts a corner point in that case, same
## as it does for any other diagonal source->dest pair.
## Pillar-clearance dogleg (_dogleg_corner_around_pillars()/
## _leg_clears_all_pillars()) is applied per corner exactly like the
## freeform trace above.
## Falls back to _trace_wall_hugging_path() (unchanged freeform routing)
## whenever wall-locking isn't applicable: an anchored destination (existing
## node / mid-span split — already a valid real connection point), no
## registry, an empty registry (e.g. before the first perimeter solve), or
## no nearest-segment/BFS-path found (shouldn't happen for a connected
## perimeter, but fails safe rather than producing an invalid trace).
## Known limitation (explicitly out of scope this pass, per plan): unlike
## the freeform trace, this does NOT run _avoid_existing_pipes() — a
## wall-locked run can still overlap an existing pipe run along the same
## wall. Flagged in docs/systems/water/README.md, not fixed here.
func _trace_wall_locked_path(source_pos: Vector3, source_key: String, cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	var dest: Dictionary = _resolve_destination(cursor_pos, debug)
	if dest.is_empty():
		return { "waypoints": [], "waypoint_keys": [], "valid": false, "final_key": "" }

	## Anchored destination — already a real connection point, keep using
	## the pre-existing freeform trace (see this function's header).
	if dest.has("existing_key") or dest.has("split_candidate"):
		return _trace_wall_hugging_path(source_pos, source_key, cursor_pos, debug)

	var registry: WallPerimeterRegistry = _get_wall_perimeter_registry()
	if registry == null or registry.is_empty():
		return _trace_wall_hugging_path(source_pos, source_key, cursor_pos, debug)

	var dest_pos: Vector3 = dest["pos"]
	var from_key: String = registry.get_nearest_segment_key(source_pos)
	var to_key: String = registry.get_nearest_segment_key(dest_pos)
	if from_key.is_empty() or to_key.is_empty():
		return _trace_wall_hugging_path(source_pos, source_key, cursor_pos, debug)

	var wall_raw: Array = registry.find_path_along_wall(from_key, to_key)
	if wall_raw.is_empty():
		return _trace_wall_hugging_path(source_pos, source_key, cursor_pos, debug)

	var wall_pts: Array = []
	for wp: Vector3 in wall_raw:
		wall_pts.append(Vector3(wp.x, WATER_CEILING_Y, wp.z))

	## Chain: source -> each wall waypoint in order -> dest. Re-run every
	## hop through _build_manhattan_path() so the whole thing stays
	## strictly axis-aligned (see header comment above).
	var chain_points: Array = [source_pos]
	chain_points.append_array(wall_pts)
	chain_points.append(dest_pos)

	var raw_points: Array = [source_pos]
	for i in range(1, chain_points.size()):
		var leg: Array = _build_manhattan_path(raw_points[raw_points.size() - 1], chain_points[i])
		for j in range(1, leg.size()):
			_append_if_distinct(raw_points, leg[j])

	if raw_points.size() < 2:
		return { "waypoints": [source_pos], "waypoint_keys": [source_key], "valid": false, "final_key": source_key }

	## Pillar clearance per corner/leg — identical approach to
	## _trace_wall_hugging_path()'s own loop above.
	var pillar_registry: PillarRegistry = _get_pillar_registry()
	var waypoints: Array = [raw_points[0]]
	var waypoint_keys: Array = [source_key]
	var valid: bool = true

	for i in range(1, raw_points.size()):
		var raw_pt: Vector3 = raw_points[i]
		var prev_pt: Vector3 = waypoints[waypoints.size() - 1]
		var is_last_point: bool = (i == raw_points.size() - 1)
		if is_last_point:
			if not _leg_clears_all_pillars(prev_pt, raw_pt, pillar_registry):
				valid = false
			waypoints.append(raw_pt)
			waypoint_keys.append(dest.get("existing_key", ""))
		else:
			var next_pt: Vector3 = raw_points[i + 1]
			var steps: Array = _dogleg_corner_around_pillars(prev_pt, raw_pt, next_pt, pillar_registry)
			for step_pt: Vector3 in steps:
				if not _leg_clears_all_pillars(prev_pt, step_pt, pillar_registry):
					valid = false
				waypoints.append(step_pt)
				waypoint_keys.append("")
				prev_pt = step_pt

	if not _is_path_in_bounds(waypoints, debug):
		valid = false

	return { "waypoints": waypoints, "waypoint_keys": waypoint_keys, "valid": valid, "final_key": "" }

## Picks freeform (_trace_wall_hugging_path()) vs. wall-locked
## (_trace_wall_locked_path()) routing for one trace call — CTRL held, or
## WALL_LOCKED_ROUTING_ENABLED flipped off, means freeform (today's
## pre-existing behavior); otherwise wall-locked is the default. Single
## shared chooser so _update_ghost_preview()'s per-frame call and
## _try_confirm_full_path()'s confirm-time call can never disagree about
## which mode a given click actually used.
func _trace_active_path(source_pos: Vector3, source_key: String, cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	if not WALL_LOCKED_ROUTING_ENABLED or Input.is_key_pressed(KEY_CTRL):
		return _trace_wall_hugging_path(source_pos, source_key, cursor_pos, debug)
	return _trace_wall_locked_path(source_pos, source_key, cursor_pos, debug)

func _update_ghost_preview() -> void:
	_clear_ghost()
	var cursor_pos: Vector3 = _get_cursor_world_pos()

	if not PAINT_MODE_ENABLED:
		_update_ghost_preview_single_leg(cursor_pos)
		return

	var trace: Dictionary = _trace_active_path(_source_pos, _source_key, cursor_pos, false)
	var waypoints: Array = trace["waypoints"]
	if waypoints.size() < 2:
		_clear_cost_label()
		return

	for i in range(waypoints.size() - 1):
		var seg: Node3D = WaterPipeSegment.make_ghost_pipe(_get_scene_root(), waypoints[i], waypoints[i + 1])
		var mat: StandardMaterial3D = seg.get("_material")
		if mat != null:
			mat.albedo_color = GHOST_COLOR_VALID if trace["valid"] else GHOST_COLOR_INVALID
		_ghost_segs.append(seg)

	## Live cost preview — single total across the whole traced run, not
	## per-leg (per plan; mirrors WireDrawMode's live "$X" label during drag).
	var total_length: float = 0.0
	for i in range(waypoints.size() - 1):
		total_length += waypoints[i].distance_to(waypoints[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))
	var midpoint: Vector3 = (waypoints[0] + waypoints[waypoints.size() - 1]) * 0.5
	_update_cost_label(midpoint, cost)

## Old single-leg ghost preview body, kept fully intact as the
## PAINT_MODE_ENABLED=false fallback (Part B toggle — see that const's
## comment).
func _update_ghost_preview_single_leg(cursor_pos: Vector3) -> void:
	var dest: Dictionary = _resolve_destination(cursor_pos)
	if dest.is_empty():
		_clear_cost_label()
		return

	var raw_path: Array = _build_manhattan_path(_source_pos, dest["pos"])
	if raw_path.size() < 2:
		_clear_cost_label()
		return

	var path: Array = _avoid_existing_pipes(raw_path)
	var valid: bool = _is_path_in_bounds(path)

	for i in range(path.size() - 1):
		var seg: Node3D = WaterPipeSegment.make_ghost_pipe(_get_scene_root(), path[i], path[i + 1])
		var mat: StandardMaterial3D = seg.get("_material")
		if mat != null:
			mat.albedo_color = GHOST_COLOR_VALID if valid else GHOST_COLOR_INVALID
		_ghost_segs.append(seg)

	var total_length: float = 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))
	var midpoint: Vector3 = (path[0] + path[path.size() - 1]) * 0.5
	_update_cost_label(midpoint, cost)

func _try_confirm_segment() -> void:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	_pdbg("[PipeDebug] ══════ confirm attempt ══════")
	_pdbg("[PipeDebug] cursor_pos=%s  source_key=%s  source_pos=%s" % [cursor_pos, _source_key, _source_pos])
	_dump_pipe_network()

	var dest: Dictionary = _resolve_destination(cursor_pos, true)
	_pdbg("[PipeDebug] resolve_destination -> %s" % [dest])
	if dest.is_empty():
		_pdbg("[PipeDebug] ABORT: dest empty")
		_show_warning("No valid pipe destination here")
		return

	## T-split anywhere (July 2026, third playtest pass): the destination
	## landed on an existing pipe's mid-span (detected read-only by
	## _resolve_destination()) — perform the actual split NOW, then treat
	## the new joint exactly like any other existing-node destination.
	if dest.has("split_candidate"):
		var split_key: String = _split_pipe_at(wm, dest["split_candidate"])
		_pdbg("[PipeDebug] split_candidate present -> _split_pipe_at() returned key=%s" % split_key)
		if split_key.is_empty():
			_pdbg("[PipeDebug] ABORT: split failed")
			_show_warning("Could not split pipe here")
			return
		dest = { "pos": dest["pos"], "existing_key": split_key }

	var dest_pos: Vector3 = dest["pos"]
	var raw_path: Array = _build_manhattan_path(_source_pos, dest_pos)
	_pdbg("[PipeDebug] dest_pos=%s  raw_path=%s" % [dest_pos, raw_path])
	if raw_path.size() < 2:
		_pdbg("[PipeDebug] ABORT: raw_path too short (size=%d)" % raw_path.size())
		_show_warning("Pipe segment too short")
		return

	## No-overlap routing — same reroute the ghost preview already showed
	## (see _update_ghost_preview()/_avoid_existing_pipes()), re-run here so
	## a confirm click always matches what was previewed. debug=true here
	## (unlike the preview's own call) — this is a one-off click, not a
	## 60fps per-frame call, so full verbose logging is safe.
	var path: Array = _avoid_existing_pipes(raw_path, true)
	_pdbg("[PipeDebug] avoided_path=%s  (%d point(s), raw had %d — %s)" %
		[path, path.size(), raw_path.size(),
		("DETOUR INSERTED" if path.size() != raw_path.size() else "no detour")])

	## Validity check — out-of-bounds only now; collinear overlap is
	## rerouted above rather than rejected (see docs/systems/water/README.md
	## Known tradeoffs).
	var bounds_ok: bool = _is_path_in_bounds(path, true)
	_pdbg("[PipeDebug] _is_path_in_bounds -> %s" % bounds_ok)
	if not bounds_ok:
		_pdbg("[PipeDebug] ABORT: out of bounds. Full path was: %s" % [path])
		_show_warning("Cannot place pipe outside the bunker")
		return

	var total_length: float = 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))
	_pdbg("[PipeDebug] total_length=%.3f  cost=%d" % [total_length, cost])

	if world_node != null:
		if not world_node.spend_cash(cost):
			_pdbg("[PipeDebug] ABORT: not enough cash")
			_show_warning("Not enough cash for this pipe run")
			return

	## Perpendicular "+"" crossings against existing pipes (July 2026, third
	## playtest pass) — explicitly ALLOWED, splits the crossed pipe and
	## shares a real joint node at the crossing point. MUTATES the graph —
	## only ever called here (confirm time), never from the read-only ghost
	## preview. See _insert_crossings()'s own comment for the full shape.
	var points: Array = _insert_crossings(wm, path, dest.get("existing_key", ""))
	_pdbg("[PipeDebug] points after _insert_crossings=%s" % [points])

	## ── Register a graph node for every point that doesn't already have a
	## key (crossings/source/an existing-node destination all arrive with
	## one already — see _insert_crossings()); everything else is a fresh
	## corner bend (gets a WaterPipeElbow) or, for the final point only, a
	## fresh "pipe_joint".
	var keys: Array[String] = []
	var elbow_nodes: Array = []
	for i in range(points.size()):
		var pt: Dictionary = points[i]
		var existing: String = pt.get("existing_key", "")
		if not existing.is_empty():
			keys.append(existing)
			continue
		var is_last: bool = (i == points.size() - 1)
		if is_last:
			keys.append(wm.register_node(pt["pos"], "pipe_joint"))
		else:
			var corner_key: String = wm.register_node(pt["pos"], "corner")
			var elbow: WaterPipeElbow = WaterPipeElbow.new()
			_get_scene_root().add_child(elbow)
			elbow.global_position = pt["pos"]
			elbow.node_key = corner_key
			keys.append(corner_key)
			elbow_nodes.append(elbow)
	_pdbg("[PipeDebug] final keys=%s" % [keys])

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
		seg.set_endpoints(points[i]["pos"], points[i + 1]["pos"])
		## Per-leg cost stashed directly on the segment (July 2026) — source
		## of truth for WaterHookup._delete_and_refund_edge() so a reposition
		## refund never has to re-derive/assume the pricing formula. Derived
		## from this segment's own length rather than splitting the combined
		## `cost` above, so it stays correct even if a future change makes
		## per-leg pricing non-uniform.
		var leg_length: float = points[i]["pos"].distance_to(points[i + 1]["pos"])
		seg.placement_cost = int(ceil(leg_length * COST_PER_M))
		seg_nodes.append(seg)
		edge_ids.append(edge_id)
		_pdbg("[PipeDebug] PLACED segment edge_id=%s  a=%s  b=%s" % [edge_id, points[i]["pos"], points[i + 1]["pos"]])

	var undo_midpoint: Vector3 = (points[0]["pos"] + points[points.size() - 1]["pos"]) * 0.5
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
	_source_pos = points[points.size() - 1]["pos"]
	_clear_ghost()


## Click handler for the continuous paint-along-wall mode (Part B) —
## replaces _try_confirm_segment() above as the LMB confirm while
## PAINT_MODE_ENABLED is true (_try_confirm_segment() itself is untouched
## and still fully callable — see the early-return fallback below).
## Traces the whole run to the cursor in one go (_trace_wall_hugging_path()),
## spends ONE total cost up front, then walks the traced waypoints leg by
## leg, reusing _insert_crossings()'s existing per-leg crossing-split logic
## and the exact node/edge/segment registration shape _try_confirm_segment()
## already used per-click (generalized to run once per leg across the whole
## traced path instead of once per confirm). Emits a single pipe_placed
## signal covering every leg placed this click.
func _try_confirm_full_path() -> void:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return

	if not PAINT_MODE_ENABLED:
		_try_confirm_segment()
		return

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	_pdbg("[PipeDebug] ══════ confirm full path (paint mode) ══════  cursor_pos=%s source_key=%s source_pos=%s" % [cursor_pos, _source_key, _source_pos])
	_dump_pipe_network()

	var trace: Dictionary = _trace_active_path(_source_pos, _source_key, cursor_pos, true)
	var waypoints: Array = trace["waypoints"]
	var waypoint_keys: Array = trace["waypoint_keys"]
	_pdbg("[PipeDebug] trace waypoints=%s valid=%s" % [waypoints, trace["valid"]])

	if waypoints.size() < 2:
		_pdbg("[PipeDebug] ABORT: trace too short")
		_show_warning("Pipe segment too short")
		return
	if not trace["valid"]:
		_pdbg("[PipeDebug] ABORT: trace invalid (out of bounds or pillar clip)")
		_show_warning("Cannot place pipe there")
		return

	var total_length: float = 0.0
	for i in range(waypoints.size() - 1):
		total_length += waypoints[i].distance_to(waypoints[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))
	_pdbg("[PipeDebug] total_length=%.3f  cost=%d" % [total_length, cost])

	if world_node != null:
		if not world_node.spend_cash(cost):
			_pdbg("[PipeDebug] ABORT: not enough cash")
			_show_warning("Not enough cash for this pipe run")
			return

	## _insert_crossings() reads the current source point's key from the
	## `_source_key` member directly (see that function's own comment) —
	## drive it per-leg as `running_source_key` advances, same
	## save/restore-free approach _trace_wall_hugging_path() uses since we
	## own this member for the whole duration of this click.
	var running_source_key: String = waypoint_keys[0]
	var all_seg_nodes: Array = []
	var all_edge_ids: Array = []
	var all_elbow_nodes: Array = []

	for leg_i in range(waypoints.size() - 1):
		var a_pos: Vector3 = waypoints[leg_i]
		var b_pos: Vector3 = waypoints[leg_i + 1]
		var b_key_hint: String = waypoint_keys[leg_i + 1]

		_source_key = running_source_key
		var points: Array = _insert_crossings(wm, [a_pos, b_pos], b_key_hint)
		_pdbg("[PipeDebug] leg %d points after _insert_crossings=%s" % [leg_i, points])

		var keys: Array[String] = []
		for i in range(points.size()):
			var pt: Dictionary = points[i]
			var existing: String = pt.get("existing_key", "")
			if not existing.is_empty():
				keys.append(existing)
				continue
			var is_last: bool = (i == points.size() - 1)
			if is_last:
				keys.append(wm.register_node(pt["pos"], "pipe_joint"))
			else:
				var corner_key: String = wm.register_node(pt["pos"], "corner")
				var elbow: WaterPipeElbow = WaterPipeElbow.new()
				_get_scene_root().add_child(elbow)
				elbow.global_position = pt["pos"]
				elbow.node_key = corner_key
				keys.append(corner_key)
				all_elbow_nodes.append(elbow)

		for i in range(keys.size() - 1):
			var edge_id: String = wm.register_edge(keys[i], keys[i + 1])
			if edge_id.is_empty():
				continue
			var seg: WaterPipeSegment = WaterPipeSegment.new()
			_get_scene_root().add_child(seg)
			seg.edge_id = edge_id
			seg.set_endpoints(points[i]["pos"], points[i + 1]["pos"])
			var leg_length: float = points[i]["pos"].distance_to(points[i + 1]["pos"])
			seg.placement_cost = int(ceil(leg_length * COST_PER_M))
			all_seg_nodes.append(seg)
			all_edge_ids.append(edge_id)
			_pdbg("[PipeDebug] PLACED segment edge_id=%s  a=%s  b=%s" % [edge_id, points[i]["pos"], points[i + 1]["pos"]])

		running_source_key = keys[keys.size() - 1]

	var undo_midpoint: Vector3 = (waypoints[0] + waypoints[waypoints.size() - 1]) * 0.5
	_spawn_float_label(undo_midpoint, cost, false)
	pipe_placed.emit(all_seg_nodes, all_edge_ids, cost, all_elbow_nodes, undo_midpoint)

	_source_key = running_source_key
	_source_pos = waypoints[waypoints.size() - 1]
	_clear_ghost()
	_clear_cost_label()


## Builds the strictly-axis-aligned (90°-only) world-space point list from
## `from_pos` to `to_pos`. Produces, in order:
##   1. an optional initial vertical rise, if the source isn't already at
##      ceiling height (i.e. it's a floor-standing connectable object like a
##      sink/dispenser rather than the wall-mounted hookup or an existing
##      joint/corner, which already sit at ceiling height)
##   2. start (at ceiling height)
##   3. an optional single horizontal bend, if the destination isn't already
##      directly north/south/east/west of the source
##   4. the point directly above the destination, at ceiling height
##   5. an optional final vertical drop, if the destination isn't itself at
##      ceiling height (i.e. it's a floor-standing connectable object)
## Degenerate/coincident points are skipped via _append_if_distinct(), so a
## perfectly axis-aligned or already-ceiling-height destination correctly
## collapses to a shorter list rather than emitting zero-length segments.
func _build_manhattan_path(from_pos: Vector3, to_pos: Vector3) -> Array:
	var path: Array = []

	## Generic vertical-rise leg (Jul 2026) — symmetric with the vertical-
	## drop leg at the destination end below. Was previously only correct
	## for the hookup/joint/corner nodes this function's own header assumed
	## as the source (all already at ceiling height), so starting a run from
	## any floor-standing consumer device (sink, dispenser, future devices —
	## generic capability, not device-specific) collapsed straight to
	## ceiling height with no rise segment at all. Any source not already at
	## ceiling height now gets its real position as the first path point.
	if absf(from_pos.y - WATER_CEILING_Y) > MIN_POINT_GAP:
		_append_if_distinct(path, from_pos)

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
## `debug` gates verbose split-candidate logging — MUST be false for the
## per-frame ghost preview call (_update_ghost_preview()) or PIPE_DEBUG
## would flood the console at 60fps; only _try_confirm_segment() (a one-off
## click) passes true. See _find_split_candidate()'s own comment.
func _resolve_destination(cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return {}

	var cursor_xz: Vector3 = Vector3(cursor_pos.x, WATER_CEILING_Y, cursor_pos.z)
	var nearest: Dictionary = _get_nearest_water_node_xz(wm, cursor_xz, DEST_SNAP_RADIUS)
	if not nearest.is_empty() and nearest["key"] != _source_key:
		return { "pos": nearest["pos"], "existing_key": nearest["key"] }

	## T-split anywhere (July 2026, third playtest pass): destination might
	## land on an existing pipe's mid-span. READ-ONLY here (this runs every
	## frame during the ghost preview) — do NOT mutate the graph yet, just
	## report the candidate so the ghost can route to it; the actual split
	## only happens in _try_confirm_segment() once the player clicks.
	var split: Dictionary = _find_split_candidate(wm, cursor_xz, debug)
	if not split.is_empty():
		return { "pos": split["pos"], "split_candidate": split }

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


# ─── T-split anywhere + no-overlap routing (July 2026, third playtest pass) ──
## Closest point to `p` on the line segment [a, b], compared in the XZ plane
## only (Y taken from `a` — callers only use this for horizontal, ceiling-
## height segments, see the "vertical drop" guards in the functions below).
func _closest_point_on_segment_xz(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var az: Vector2 = Vector2(a.x, a.z)
	var bz: Vector2 = Vector2(b.x, b.z)
	var pz: Vector2 = Vector2(p.x, p.z)
	var ab: Vector2 = bz - az
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return a
	var t: float = clampf((pz - az).dot(ab) / len_sq, 0.0, 1.0)
	var closest_xz: Vector2 = az + ab * t
	return Vector3(closest_xz.x, a.y, closest_xz.y)

## Builds the {"pos","edge_id","seg_node","key_a","key_b"} shape
## _split_pipe_at() needs, from an already-known segment + point on it.
## Shared by _find_split_candidate() (search by proximity) and
## _insert_crossings() (already knows exactly which segment/point).
func _split_candidate_for_segment(wm: WaterManager, seg: WaterPipeSegment, pos: Vector3) -> Dictionary:
	if seg.edge_id.is_empty() or not wm.has_edge(seg.edge_id):
		return {}
	var edge_data: Dictionary = wm.get_edges().get(seg.edge_id, {})
	if edge_data.is_empty():
		return {}
	return {
		"pos":      pos,
		"edge_id":  seg.edge_id,
		"seg_node": seg,
		"key_a":    edge_data.get("a", ""),
		"key_b":    edge_data.get("b", ""),
	}

## Searches every live WaterPipeSegment (via the "water_pipe_visual" group —
## see that file's own comment) for the closest mid-span point to `cursor_pos`
## within SPLIT_SNAP_RADIUS, excluding points too close to either endpoint
## (SPLIT_ENDPOINT_EXCLUDE — real node-snapping already covers that case).
## Only horizontal (ceiling-height) segments are considered — a vertical
## drop into a floor device has no meaningful "mid-air branch point" on the
## ceiling plane the cursor is projected onto. READ-ONLY — does not mutate
## anything; see _split_pipe_at() for the actual mutating step.
## `debug` gates the verbose per-candidate print — MUST be false for the
## per-frame ghost preview / _resolve_destination() call, else PIPE_DEBUG
## would flood the console at 60fps while dragging (this was a real bug —
## see docs/systems/water/README.md Known tradeoffs "debug logging spam").
## Only _try_pick_source() (a one-off click) passes true.
func _find_split_candidate(wm: WaterManager, cursor_pos: Vector3, debug: bool = false) -> Dictionary:
	if wm == null:
		return {}
	var cursor_xz: Vector2 = Vector2(cursor_pos.x, cursor_pos.z)
	var best_dist: float = SPLIT_SNAP_RADIUS
	var best: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		if absf(seg.point_a.y - seg.point_b.y) > MIN_POINT_GAP:
			continue
		var raw_closest: Vector3 = _closest_point_on_segment_xz(cursor_pos, seg.point_a, seg.point_b)
		## Grid-snap the split point onto the same 0.25m grid every other
		## pipe waypoint uses (July 2026, fourth playtest pass — per
		## Brannon's explicit request; also fixes the "little legs" bug:
		## an un-grid-snapped split point meant any pipe continuing from it
		## almost never lined up with the grid, leaving a tiny sub-grid-tile
		## jog right at the joint — see _grid_snap_split_point()'s own
		## comment). Only the axis running ALONG the segment is snapped; the
		## fixed lateral coordinate is copied exactly from the segment so
		## the point stays precisely on the pipe's line.
		var closest: Vector3 = _grid_snap_split_point(raw_closest, seg)
		var d: float = Vector2(closest.x, closest.z).distance_to(cursor_xz)
		if d >= best_dist:
			continue
		if closest.distance_to(seg.point_a) < SPLIT_ENDPOINT_EXCLUDE:
			continue
		if closest.distance_to(seg.point_b) < SPLIT_ENDPOINT_EXCLUDE:
			continue
		var candidate: Dictionary = _split_candidate_for_segment(wm, seg, closest)
		if candidate.is_empty():
			continue
		best_dist = d
		best = candidate
		if debug: _pdbg("[PipeDebug] _find_split_candidate: raw_closest=%s -> grid_snapped=%s (seg edge_id=%s a=%s b=%s)" %
			[raw_closest, closest, seg.edge_id, seg.point_a, seg.point_b])
	return best

## Grid-snaps a split point along `seg`'s own line to the same 0.25m grid
## (`_PIPE_GRID`) every other pipe waypoint already uses. Only the VARYING
## axis (the one the segment actually runs along) is snapped and then
## clamped strictly between the segment's own two endpoints; the fixed
## lateral coordinate is copied exactly from the segment (never
## independently snapped) so the returned point is always precisely ON the
## pipe's line, never off to one side.
func _grid_snap_split_point(pos: Vector3, seg: WaterPipeSegment) -> Vector3:
	var seg_is_x: bool = absf(seg.point_a.x - seg.point_b.x) > absf(seg.point_a.z - seg.point_b.z)
	if seg_is_x:
		var lo: float = minf(seg.point_a.x, seg.point_b.x)
		var hi: float = maxf(seg.point_a.x, seg.point_b.x)
		var snapped_x: float = clampf(roundf(pos.x / _PIPE_GRID) * _PIPE_GRID, lo, hi)
		return Vector3(snapped_x, pos.y, seg.point_a.z)
	else:
		var lo2: float = minf(seg.point_a.z, seg.point_b.z)
		var hi2: float = maxf(seg.point_a.z, seg.point_b.z)
		var snapped_z: float = clampf(roundf(pos.z / _PIPE_GRID) * _PIPE_GRID, lo2, hi2)
		return Vector3(seg.point_a.x, pos.y, snapped_z)

## MUTATES the graph: splits an existing pipe edge at `candidate["pos"]`
## (assumed already precisely ON the segment's line). Tears down the old
## edge + its one WaterPipeSegment visual, registers a new "corner" node at
## the split point (+ a WaterPipeElbow, same as any other corner bend), and
## re-creates two edges (old_a<->new, new<->old_b) with two new
## WaterPipeSegments. Returns the new node's key, or "" on failure
## (defensive — shouldn't happen for a candidate this function's own callers
## already validated).
func _split_pipe_at(wm: WaterManager, candidate: Dictionary) -> String:
	var old_edge_id: String  = candidate["edge_id"]
	var key_a:       String  = candidate["key_a"]
	var key_b:       String  = candidate["key_b"]
	var seg_node:    WaterPipeSegment = candidate["seg_node"]
	var split_pos:   Vector3 = candidate["pos"]

	if not (wm.has_water_node(key_a) and wm.has_water_node(key_b)):
		return ""

	var pos_a: Vector3 = wm.get_node_data(key_a).get("pos", Vector3.ZERO)
	var pos_b: Vector3 = wm.get_node_data(key_b).get("pos", Vector3.ZERO)

	wm.unregister_edge(old_edge_id)
	if is_instance_valid(seg_node):
		seg_node.queue_free()

	var new_key: String = wm.register_node(split_pos, "corner")
	var elbow: WaterPipeElbow = WaterPipeElbow.new()
	_get_scene_root().add_child(elbow)
	elbow.global_position = split_pos
	elbow.node_key = new_key

	var edge_a: String = wm.register_edge(key_a, new_key)
	if not edge_a.is_empty():
		var seg_a: WaterPipeSegment = WaterPipeSegment.new()
		_get_scene_root().add_child(seg_a)
		seg_a.edge_id = edge_a
		seg_a.set_endpoints(pos_a, split_pos)

	var edge_b: String = wm.register_edge(new_key, key_b)
	if not edge_b.is_empty():
		var seg_b: WaterPipeSegment = WaterPipeSegment.new()
		_get_scene_root().add_child(seg_b)
		seg_b.edge_id = edge_b
		seg_b.set_endpoints(split_pos, pos_b)

	return new_key

## True if leg [a,b] runs COLLINEAR with `seg` (same axis, same lateral
## coordinate) AND their ranges overlap along that axis — i.e. the new leg
## would literally run on top of the existing pipe. Perpendicular crossings
## are a SEPARATE, explicitly ALLOWED case — see _find_perpendicular_crossing().
## `debug` gates the verbose per-check prints — MUST be false for the
## per-frame ghost preview call (else PIPE_DEBUG would flood the console at
## 60fps) and true only for the actual confirm-click call, see
## _avoid_existing_pipes()'s own `debug` param.
func _leg_collinear_overlaps(a: Vector3, b: Vector3, seg: WaterPipeSegment, debug: bool = false) -> bool:
	if absf(seg.point_a.y - seg.point_b.y) > MIN_POINT_GAP:
		if debug: _pdbg("[PipeDebug]     -> false: seg is a vertical drop (seg.point_a.y=%.3f seg.point_b.y=%.3f)" % [seg.point_a.y, seg.point_b.y])
		return false   ## Vertical drop — not a ceiling-height run, ignore.
	if absf(a.y - b.y) > MIN_POINT_GAP:
		if debug: _pdbg("[PipeDebug]     -> false: leg itself is a vertical drop (a.y=%.3f b.y=%.3f)" % [a.y, b.y])
		return false
	## Both individually horizontal, but at DIFFERENT heights from each
	## other (July 2026, sixth playtest pass — a real gap: this was never
	## checked before). Different Y means no real 3D overlap regardless of
	## XZ alignment — e.g. an older pipe placed before WATER_CEILING_Y was
	## raised from 2.8 to 2.9 sitting right below a new one; they'd look
	## coincident from directly above but aren't actually the same line.
	if absf(a.y - seg.point_a.y) > MIN_POINT_GAP:
		if debug: _pdbg("[PipeDebug]     -> false: different height (leg.y=%.3f seg.y=%.3f, diff=%.4f)" % [a.y, seg.point_a.y, absf(a.y - seg.point_a.y)])
		return false

	var leg_is_x: bool = absf(a.x - b.x) > absf(a.z - b.z)
	var seg_is_x: bool = absf(seg.point_a.x - seg.point_b.x) > absf(seg.point_a.z - seg.point_b.z)
	if leg_is_x != seg_is_x:
		if debug: _pdbg("[PipeDebug]     -> false: different axis (leg_is_x=%s seg_is_x=%s)" % [leg_is_x, seg_is_x])
		return false   ## Different axis — perpendicular or non-interacting, not an overlap.

	if leg_is_x:
		var lateral_diff: float = absf(a.z - seg.point_a.z)
		if lateral_diff > COLLINEAR_LATERAL_TOLERANCE:
			if debug: _pdbg("[PipeDebug]     -> false: lateral offset %.4f exceeds tolerance %.4f (leg.z=%.3f seg.z=%.3f)" %
				[lateral_diff, COLLINEAR_LATERAL_TOLERANCE, a.z, seg.point_a.z])
			return false   ## Different lateral offset — parallel, not the same line.
		var lo: float  = minf(a.x, b.x)
		var hi: float  = maxf(a.x, b.x)
		var slo: float = minf(seg.point_a.x, seg.point_b.x)
		var shi: float = maxf(seg.point_a.x, seg.point_b.x)
		var range_overlap: bool = lo < shi and hi > slo
		if debug: _pdbg("[PipeDebug]     -> X-axis, lateral_diff=%.4f (ok), leg_x=[%.3f,%.3f] seg_x=[%.3f,%.3f] range_overlap=%s" %
			[lateral_diff, lo, hi, slo, shi, range_overlap])
		return range_overlap
	else:
		var lateral_diff2: float = absf(a.x - seg.point_a.x)
		if lateral_diff2 > COLLINEAR_LATERAL_TOLERANCE:
			if debug: _pdbg("[PipeDebug]     -> false: lateral offset %.4f exceeds tolerance %.4f (leg.x=%.3f seg.x=%.3f)" %
				[lateral_diff2, COLLINEAR_LATERAL_TOLERANCE, a.x, seg.point_a.x])
			return false
		var lo2: float  = minf(a.z, b.z)
		var hi2: float  = maxf(a.z, b.z)
		var slo2: float = minf(seg.point_a.z, seg.point_b.z)
		var shi2: float = maxf(seg.point_a.z, seg.point_b.z)
		var range_overlap2: bool = lo2 < shi2 and hi2 > slo2
		if debug: _pdbg("[PipeDebug]     -> Z-axis, lateral_diff=%.4f (ok), leg_z=[%.3f,%.3f] seg_z=[%.3f,%.3f] range_overlap=%s" %
			[lateral_diff2, lo2, hi2, slo2, shi2, range_overlap2])
		return range_overlap2

func _find_collinear_conflict(a: Vector3, b: Vector3, debug: bool = false) -> WaterPipeSegment:
	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		var overlaps: bool = _leg_collinear_overlaps(a, b, seg, debug)
		if debug:
			_pdbg("[PipeDebug]   collinear-check leg[%s -> %s] vs seg edge_id=%s a=%s b=%s => %s" %
				[a, b, seg.edge_id, seg.point_a, seg.point_b, overlaps])
		if overlaps:
			return seg
	return null

## Post-processes a Manhattan path (from _build_manhattan_path()) so no leg
## ever runs collinear/overlapping on top of an already-placed pipe — per
## Brannon's explicit "pipes should never double over" request. Any leg
## found to collinear-overlap an existing WaterPipeSegment is replaced with
## a detour: jog sideways by DETOUR_OFFSET, run parallel past the conflict —
## a real loop around the obstruction, not a rejection. The detoured point
## only jogs back to the exact original coordinate when it's the path's
## FINAL point (has to land precisely on the real destination anchor —
## an existing hookup/sink/pipe node). Every other point is a free-floating
## corner (see _try_confirm_segment()), so mid-route detours just carry the
## offset forward instead of jogging back to the un-offset corner — jogging
## back there too used to spawn a pointless zero-purpose extra stub/"leg"
## at the corner (fixed July 2026, seventh playtest pass).
## Perpendicular crossings are UNCHANGED here — they're allowed, and handled
## separately at confirm time by _insert_crossings().
## KNOWN LIMITATIONS (documented rather than over-engineered away):
## - Detours around the FULL leg span, not just the overlapping sub-range —
##   simpler/safer than precise partial-overlap geometry; occasionally a
##   slightly wider detour than strictly necessary, never wrong.
## - Single avoidance pass — doesn't recursively re-check the detour itself
##   against yet another pipe. A rare nested-conflict case; workable by the
##   player routing around it manually if it ever comes up.
## - Fixed sidestep direction (+Z for an X-axis leg, +X for a Z-axis leg) —
##   doesn't check which side actually has clearance. A future pass could
##   pick the side with more room; not attempted here to keep this
##   contained.
## `debug` gates verbose per-leg/per-segment prints — pass true only from
## the actual confirm-click path (_try_confirm_segment()), false (default)
## from the per-frame ghost preview (_update_ghost_preview()) so PIPE_DEBUG
## doesn't flood the console at 60fps while dragging.
func _avoid_existing_pipes(path: Array, debug: bool = false) -> Array:
	var out: Array = [path[0]]
	## Running "current" point — starts as path[0] but, once a mid-route leg
	## gets detoured, carries the OFFSET point forward instead of the raw
	## path[i] coordinate. This matters because every point in the final
	## path except the very last becomes a free-floating "corner" node (see
	## _try_confirm_segment()) — nothing downstream needs a mid-route bend
	## to sit at its original un-offset coordinate. Only the path's true
	## final point has to land exactly on the real destination anchor
	## (an existing hookup/sink/pipe node), so that's the only case that
	## still jogs back to the exact original `b` below.
	var current: Vector3 = path[0]
	for i in range(path.size() - 1):
		var a: Vector3 = current
		var b: Vector3 = path[i + 1]
		var is_last_leg: bool = (i == path.size() - 2)
		if debug: _pdbg("[PipeDebug] _avoid_existing_pipes: checking leg %d [%s -> %s]" % [i, a, b])
		var conflict: WaterPipeSegment = _find_collinear_conflict(a, b, debug)
		if conflict == null:
			if debug: _pdbg("[PipeDebug]   no conflict for this leg")
			out.append(b)
			current = b
			continue

		var leg_is_x: bool = absf(a.x - b.x) > absf(a.z - b.z)
		## Sidestep DIRECTION (July 2026, eighth playtest pass): used to be a
		## fixed +Z (for an X-axis leg) / +X (for a Z-axis leg) regardless of
		## which way the route actually continues — so detouring toward a
		## destination on the "wrong" side made the pipe visibly backtrack
		## (e.g. dip south before finally turning north). Fixed by looking
		## ahead to the point AFTER this corner (path[i+2], the real next
		## waypoint) and sidestepping toward it instead. Falls back to the
		## old fixed +1 direction only when there's no lookahead point (the
		## conflicting leg is the path's very last leg — it jogs back to the
		## exact destination afterward regardless, so the initial bulge
		## direction there is cosmetic only).
		var sign_val: float = 1.0
		if i + 2 < path.size():
			var lookahead: Vector3 = path[i + 2]
			var diff: float = (lookahead.z - b.z) if leg_is_x else (lookahead.x - b.x)
			if diff < 0.0:
				sign_val = -1.0
			elif diff > 0.0:
				sign_val = 1.0
		var offset: Vector3 = Vector3(0.0, 0.0, DETOUR_OFFSET * sign_val) if leg_is_x else Vector3(DETOUR_OFFSET * sign_val, 0.0, 0.0)
		if debug: _pdbg("[PipeDebug]   CONFLICT vs edge_id=%s -> detour offset=%s (leg_is_x=%s) is_last_leg=%s" % [conflict.edge_id, offset, leg_is_x, is_last_leg])
		out.append(a + offset)
		if is_last_leg:
			## Must still land exactly on the real destination — jog back.
			out.append(b + offset)
			out.append(b)
			current = b
		else:
			## Mid-route corner — no anchor to preserve, so just keep
			## running from the offset point. Skips the pointless
			## "jog back to the un-offset corner" that produced the small
			## stub/extra-leg artifact Brannon flagged.
			out.append(b + offset)
			current = b + offset
	return out

## Finds the single interior crossing point (if any) between leg [a,b] and
## `seg`, when they're PERPENDICULAR (different axis) and both ranges
## actually include that coordinate — a true "+" intersection, explicitly
## ALLOWED per Brannon's request (unlike a collinear overlap). Returns
## Vector3.INF if there's no such crossing.
func _find_perpendicular_crossing(a: Vector3, b: Vector3, seg: WaterPipeSegment) -> Vector3:
	if absf(seg.point_a.y - seg.point_b.y) > MIN_POINT_GAP:
		return Vector3.INF
	if absf(a.y - b.y) > MIN_POINT_GAP:
		return Vector3.INF

	var leg_is_x: bool = absf(a.x - b.x) > absf(a.z - b.z)
	var seg_is_x: bool = absf(seg.point_a.x - seg.point_b.x) > absf(seg.point_a.z - seg.point_b.z)
	if leg_is_x == seg_is_x:
		return Vector3.INF   ## Same axis — that's _leg_collinear_overlaps()'s job, never a "crossing" here.

	var cross: Vector3
	if leg_is_x:
		cross = Vector3(seg.point_a.x, a.y, a.z)
		if cross.x < minf(a.x, b.x) - MIN_POINT_GAP or cross.x > maxf(a.x, b.x) + MIN_POINT_GAP:
			return Vector3.INF
		if cross.z < minf(seg.point_a.z, seg.point_b.z) - MIN_POINT_GAP or cross.z > maxf(seg.point_a.z, seg.point_b.z) + MIN_POINT_GAP:
			return Vector3.INF
	else:
		cross = Vector3(a.x, a.y, seg.point_a.z)
		if cross.z < minf(a.z, b.z) - MIN_POINT_GAP or cross.z > maxf(a.z, b.z) + MIN_POINT_GAP:
			return Vector3.INF
		if cross.x < minf(seg.point_a.x, seg.point_b.x) - MIN_POINT_GAP or cross.x > maxf(seg.point_a.x, seg.point_b.x) + MIN_POINT_GAP:
			return Vector3.INF

	## Exclude crossings essentially AT one of the leg's own endpoints —
	## that's just a normal node join, not a mid-span "+" crossing.
	if cross.distance_to(a) < SPLIT_ENDPOINT_EXCLUDE or cross.distance_to(b) < SPLIT_ENDPOINT_EXCLUDE:
		return Vector3.INF
	return cross

## MUTATES the graph — called only from _try_confirm_segment(), never from
## the read-only ghost preview. Walks the (already detour-avoided) `path`
## leg by leg; for each leg, finds every existing pipe it perpendicularly
## crosses, splits that existing pipe at the crossing (_split_pipe_at() —
## creates a real shared joint, exactly the "+"" formation Brannon asked to
## allow), and inserts the crossing as a waypoint carrying that joint's key.
## Multiple crossings on one leg are ordered along the leg before insertion.
## Returns Array[Dictionary] of {"pos": Vector3, "existing_key": String} for
## EVERY point in the (possibly longer) path — index 0 always carries
## `_source_key`, the last point carries `dest_existing_key` (may be empty,
## meaning "register a fresh pipe_joint there").
func _insert_crossings(wm: WaterManager, path: Array, dest_existing_key: String) -> Array:
	var points: Array = [{ "pos": path[0], "existing_key": _source_key }]
	for i in range(path.size() - 1):
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]

		var crossings: Array = []
		for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
			if not is_instance_valid(node) or not (node is WaterPipeSegment):
				continue
			var seg: WaterPipeSegment = node as WaterPipeSegment
			var cross: Vector3 = _find_perpendicular_crossing(a, b, seg)
			if cross == Vector3.INF:
				continue
			crossings.append({ "pos": cross, "t": a.distance_to(cross), "seg": seg })
		crossings.sort_custom(func(x, y): return x["t"] < y["t"])

		for c: Dictionary in crossings:
			var candidate: Dictionary = _split_candidate_for_segment(wm, c["seg"] as WaterPipeSegment, c["pos"])
			if candidate.is_empty():
				continue
			var new_key: String = _split_pipe_at(wm, candidate)
			if new_key.is_empty():
				continue
			points.append({ "pos": c["pos"], "existing_key": new_key })

		var is_last_leg: bool = (i == path.size() - 2)
		points.append({ "pos": b, "existing_key": dest_existing_key if is_last_leg else "" })
	return points


# ─── Helpers ──────────────────────────────────────────────────────────────────
func _clear_ghost() -> void:
	for seg: Node3D in _ghost_segs:
		if is_instance_valid(seg):
			seg.queue_free()
	_ghost_segs.clear()

## Shows a floating "$X" label at the path midpoint during phase 1 drag.
## Updated every frame — same create-once/reuse pattern as
## WireDrawMode._update_cost_label() (see that function's own comment).
## font_size=56 is 2x WireDrawMode's own (also bumped to 56 in this pass) —
## per Brannon's "a bit small" feedback, July 2026.
func _update_cost_label(midpoint: Vector3, cost: int) -> void:
	if _cost_label == null:
		var lbl: Label3D = Label3D.new()
		lbl.font_size        = 56
		lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test    = true
		lbl.render_priority  = 5
		lbl.double_sided     = true
		lbl.fixed_size       = false
		lbl.pixel_size       = 0.005
		lbl.outline_size     = 6
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.90)
		lbl.modulate         = Color(1.0, 0.88, 0.15, 1.0)   ## bright yellow — matches WireDrawMode
		var parent: Node = world_node if world_node != null else _get_scene_root()
		parent.add_child(lbl)
		_cost_label = lbl

	_cost_label.text            = "$%d" % cost
	## Raise above midpoint so it clears the pipe/ceiling and any floor
	## geometry — pipes sit higher than wires (WATER_CEILING_Y vs WIRE_Y),
	## so this offset is smaller than WireDrawMode's 0.70m equivalent.
	_cost_label.global_position = midpoint + Vector3(0.0, 0.30, 0.0)
	_cost_label.visible         = true

func _clear_cost_label() -> void:
	if _cost_label != null:
		_cost_label.queue_free()
		_cost_label = null

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

## `debug` gates the verbose failure print — MUST be false for the
## per-frame ghost preview call, else PIPE_DEBUG would flood the console at
## 60fps while dragging (this was a real bug, see docs/systems/water/
## README.md Known tradeoffs "debug logging spam"). Only
## _try_confirm_segment() (a one-off click) passes true.
func _is_path_in_bounds(path: Array, debug: bool = false) -> bool:
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
			if debug: _pdbg("[PipeDebug] _is_path_in_bounds: FAILED at point %s (tightened rect x=[%.3f,%.3f] z=[%.3f,%.3f], and _is_inside_bunker() also said false)" %
				[p, min_x, max_x, min_z, max_z])
			return false
	return true

## NOTE (July 2026, third playtest pass): the old exact-duplicate-edge
## rejection (_path_overlaps_existing()/_is_path_valid()) was removed —
## overlapping an existing pipe is no longer a rejection case, it's rerouted
## around instead (see _avoid_existing_pipes()). Bounds-checking
## (_is_path_in_bounds() above) is the only remaining validity gate.
