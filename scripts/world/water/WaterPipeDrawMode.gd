extends Node
class_name WaterPipeDrawMode
## WaterPipeDrawMode.gd
## ─────────────────────────────────────────────────────────────────────────────
## The pipe placement tool. Instantiated/owned by BuildModeController the same
## way WireDrawMode is (see BuildModeController._setup_water_pipe_draw_mode()),
## activated while TOOL_WATER_PIPE is selected.
##
## ══════════════════════════════════════════════════════════════════════════
## IMPLEMENTATION NOTE — FALLBACK INTERACTION MODEL (flagged per the
## groundwork plan's own explicit allowance, §5):
##
## The plan's primary vision is a single continuous drag that "paints" an
## entire multi-corner wall-hugging pipe run in one click-to-confirm gesture.
## That full experience needs a live multi-segment path preview that walks
## around however many corners the cursor's projected position happens to
## cross, confirmed all at once. Building AND verifying that correctly with
## zero in-editor testing available this pass (headless compile-check only —
## see tools/godot_check.sh) was judged too high-risk to responsibly ship in
## one go.
##
## IMPLEMENTED INSTEAD (the plan's own pre-approved fallback): one
## wall-hugging segment per click, up to the NEXT corner. If the destination
## the player clicks is on a different wall than the source (i.e. crosses
## exactly one corner), the tool auto-inserts a WaterPipeElbow graph node at
## that corner and spawns two segments in a single confirm — still satisfies
## "auto-insert elbow at corners" without the full single-drag experience.
## Chaining several of these clicks end-to-end is how a player routes a run
## around multiple corners today. Upgrading this to the full continuous-paint
## experience is flagged as follow-up work, not attempted in this pass.
## ══════════════════════════════════════════════════════════════════════════

signal pipe_placed(seg_nodes: Array, edge_ids: Array, cost: int)
signal pipe_tool_exit_requested()

# ─── Config ───────────────────────────────────────────────────────────────────
## Independent tuning knob — same STARTING number as LIGHT_WALL_SNAP_RANGE
## (1.5 m), NOT literally shared/coupled to it (per the plan's explicit note).
const PIPE_WALL_SNAP_RANGE: float = 1.5

## How far to pull the pipe off the wall plane so it visibly hugs the wall
## rather than floating in open room space — matches
## WaterPipeSegment.WALL_HUG_OFFSET (kept in sync manually; both are small,
## rarely-tuned placeholder constants for this groundwork pass).
const WALL_HUG_OFFSET: float = 0.06

## Snap radius for picking an existing graph node (hookup/joint/corner) as the
## run's source point — mirrors WireDrawMode.SNAP_RADIUS.
const SOURCE_SNAP_RADIUS: float = 2.5

## Placeholder economics — the groundwork plan does not specify pipe/hookup
## pricing (out of scope for this pass); these are deliberately conservative
## placeholders for a future balance pass, not a considered game-design cost.
const COST_PER_M: float = 5.0

const PIPE_Y: float = 1.0   ## world Y pipes are drawn/placed at — matches BuildModeController.PLACEMENT_Y

# ─── External refs (set by BuildModeController, mirrors WireDrawMode) ────────
var camera:     Camera3D = null
var world_node: Node     = null
var build_hud:  CanvasLayer = null
var ray_length: float    = 50.0

# ─── State ────────────────────────────────────────────────────────────────────
var _active:     bool    = false
var _phase:      int     = 0   ## 0 = picking source, 1 = dragging toward destination
var _source_key: String  = ""
var _source_pos: Vector3 = Vector3.ZERO

var _ghost_segs: Array[Node3D] = []   ## 1 or 2 ghost WaterPipeSegments for the current preview

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
			if _phase == 1:
				## Cancel the current drag, stay in the tool.
				_phase = 0
				_source_key = ""
				_clear_ghost()
			else:
				pipe_tool_exit_requested.emit()
			return true

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			pipe_tool_exit_requested.emit()
			return true

	return false


# ─── Phase 0: pick source ──────────────────────────────────────────────────────
func _try_pick_source() -> bool:
	var wm: WaterManager = _get_wm()
	if wm == null:
		return false

	var cursor_pos: Vector3 = _get_cursor_world_pos()
	var nearest: Dictionary = _get_nearest_water_node(wm, cursor_pos)
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

	var path: Array = _build_path(_source_pos, dest["pos"], dest.get("corner", null))
	for i in range(path.size() - 1):
		var seg: Node3D = WaterPipeSegment.make_ghost_pipe(_get_scene_root(), path[i], path[i + 1])
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
	var corner_pos = dest.get("corner", null)   ## Vector3 or null

	var path: Array = _build_path(_source_pos, dest_pos, corner_pos)
	var total_length: float = 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	var cost: int = int(ceil(total_length * COST_PER_M))

	if world_node != null:
		if not world_node.spend_cash(cost):
			_show_warning("Not enough cash for this pipe run")
			return

	## ── Register the corner elbow node first (if any) ──
	var mid_key: String = ""
	if corner_pos != null:
		mid_key = wm.register_node(corner_pos, "corner")
		var elbow: WaterPipeElbow = WaterPipeElbow.new()
		_get_scene_root().add_child(elbow)
		elbow.global_position = corner_pos
		elbow.node_key = mid_key

	## ── Register the destination node ──
	## Re-uses an existing node key if the destination snapped onto one
	## (e.g. a future T-split start point); otherwise a fresh "pipe_joint".
	var dest_key: String = dest.get("existing_key", "")
	if dest_key.is_empty():
		dest_key = wm.register_node(dest_pos, "pipe_joint")

	## ── Register edges + spawn real segments for each leg of the path ──
	var seg_nodes: Array = []
	var edge_ids:  Array = []
	var keys: Array[String] = [_source_key]
	if not mid_key.is_empty():
		keys.append(mid_key)
	keys.append(dest_key)

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

	pipe_placed.emit(seg_nodes, edge_ids, cost)

	## Chain the next segment from this destination — matches the "click
	## again to keep extending the run" flow implied by the fallback model.
	_source_key = dest_key
	_source_pos = dest_pos
	_clear_ghost()


## Builds the world-space point list for the (up to) 2-segment path from
## `from_pos` to `to_pos`, inserting `corner_pos` in the middle if given.
func _build_path(from_pos: Vector3, to_pos: Vector3, corner_pos) -> Array:
	if corner_pos != null:
		return [from_pos, corner_pos, to_pos]
	return [from_pos, to_pos]


## Resolves the cursor's projected destination this frame:
##   - Shift held → freehand, ignores wall snap entirely.
##   - Within PIPE_WALL_SNAP_RANGE of a wall → magnetic snap, wall-hugging
##     offset applied, "corner" key set if the destination wall differs from
##     the source's wall (see file header for the fallback corner-insertion
##     algorithm).
##   - Otherwise → freehand (snap naturally releases outside the range).
## Returns {} if no valid destination this frame (e.g. raycast missed everything).
func _resolve_destination(cursor_pos: Vector3) -> Dictionary:
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)

	if shift_held:
		return { "pos": cursor_pos }

	var wall_hit: Dictionary = _find_wall_hug_point(cursor_pos, PIPE_WALL_SNAP_RANGE)
	if wall_hit.is_empty():
		## Outside snap range of any wall — freehand by default (magnetic pull
		## only engages within range, see file header).
		return { "pos": cursor_pos }

	var source_wall: Dictionary = _find_wall_hug_point(_source_pos, PIPE_WALL_SNAP_RANGE * 4.0)
	if source_wall.is_empty() or source_wall["fixed_axis"] == wall_hit["fixed_axis"]:
		## Same wall run (or source has no detectable wall — e.g. it's a
		## mid-room joint) — straight segment, no corner.
		return { "pos": wall_hit["pos"] }

	## Different fixed axis → path crosses exactly one corner. Compute the
	## right-angle bend point: take the destination wall's fixed coordinate
	## and the source wall's fixed coordinate, combined — see file header
	## algorithm summary.
	var corner: Vector3
	if wall_hit["fixed_axis"] == "x":
		corner = Vector3(wall_hit["pos"].x, PIPE_Y, source_wall["pos"].z)
	else:
		corner = Vector3(source_wall["pos"].x, PIPE_Y, wall_hit["pos"].z)

	return { "pos": wall_hit["pos"], "corner": corner }


## Standalone wall-hug raycast — 4-cardinal directions, same technique
## WallSnapHelpers uses, but independently implemented here (this system has
## zero dependency on BuildModeController/WallSnapHelpers — see WaterHookup.gd
## header for the same design choice). Returns
## { "pos": Vector3 (pulled back off the wall), "fixed_axis": "x"|"z" } or {}.
func _find_wall_hug_point(base_pos: Vector3, snap_range: float) -> Dictionary:
	var scene_root: Node3D = _get_scene_root()
	if scene_root == null or not scene_root.is_inside_tree():
		return {}

	var origin: Vector3 = Vector3(base_pos.x, PIPE_Y, base_pos.z)
	var directions: Array[Dictionary] = [
		{ "dir": Vector3( 0, 0,  1), "axis": "z" },
		{ "dir": Vector3( 0, 0, -1), "axis": "z" },
		{ "dir": Vector3( 1, 0,  0), "axis": "x" },
		{ "dir": Vector3(-1, 0,  0), "axis": "x" },
	]

	var space: PhysicsDirectSpaceState3D = scene_root.get_world_3d().direct_space_state
	var best_dist: float = snap_range
	var best: Dictionary = {}

	for d: Dictionary in directions:
		var dir: Vector3 = d["dir"] as Vector3
		var to_pt: Vector3 = origin + dir * snap_range
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to_pt)
		query.collision_mask = 5   ## same wall/pillar mask WallSnapHelpers uses

		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		if hit_normal.dot(dir) >= 0.0:
			continue

		var hit_dist: float = origin.distance_to(hit["position"])
		if hit_dist < best_dist:
			best_dist = hit_dist
			var snapped: Vector3 = hit["position"] - dir * WALL_HUG_OFFSET
			best = { "pos": Vector3(snapped.x, PIPE_Y, snapped.z), "fixed_axis": d["axis"] }

	return best


## Finds the nearest registered water graph node (any role) within
## SOURCE_SNAP_RADIUS of `pos` — used only for picking the run's starting
## point (phase 0).
func _get_nearest_water_node(wm: WaterManager, pos: Vector3) -> Dictionary:
	var best_dist: float = SOURCE_SNAP_RADIUS
	var best: Dictionary = {}
	for key: String in wm.get_nodes():
		var data: Dictionary = wm.get_node_data(key)
		var node_pos: Vector3 = data.get("pos", Vector3.ZERO)
		var d: float = node_pos.distance_to(pos)
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
	## Intersect with the horizontal plane at PIPE_Y — same simple ground-
	## plane projection approach WireDrawMode uses for its own cursor point.
	if absf(dir.y) < 0.0001:
		return from
	var t: float = (PIPE_Y - from.y) / dir.y
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
