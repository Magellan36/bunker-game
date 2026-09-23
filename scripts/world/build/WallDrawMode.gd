extends Node
## WallDrawMode.gd (rewrite — single stretched wall, not N segments)
## Click-drag-click wall placement. Both anchors snap to nearby registered wall
## runs, otherwise they use the build grid. Dragging stretches ONE wall
## mesh/collision at a free 360° angle; click 2 confirms a StaticBody3D sized
## to the exact run length. Q/E cycle height tier at any time.

signal wall_placed(node: Node3D, tile_id: int, price: int, pos: Vector3, angle_deg: float)
signal wall_tool_exit_requested()

const DragMath = preload("res://scripts/world/build/DragPlacementMath.gd")

const WALL_CELL_SIZE:  float = 1.0    ## $/price-per-meter unit — confirmed real mesh cell size
const WALL_THICKNESS:  float = 0.3    ## Confirmed from tile_set.tscn's BoxMesh
const WALL_HEIGHT_FULL: float = 3.0   ## Matches BuildModeController.WALL_HEIGHT_M
const TRUE_FLOOR_Y:    float = 0.5    ## True floor Y in this coordinate frame

const IDLE_SLIVER_LENGTH: float = WALL_CELL_SIZE * 0.25   ## 1/4 of a normal 1m cell
const IDLE_WALL_PREVIEW_OFFSET: float = 0.28
const IDLE_PILLAR_PREVIEW_OFFSET: float = 0.16
const CONNECTION_DOT_RADIUS: float = 0.065
const CONNECTION_DOT_COLOR: Color = Color(0.45, 0.85, 1.0, 0.92)

const MIN_LENGTH: float = IDLE_SLIVER_LENGTH   ## Matches the idle sliver exactly — see class comment

var HEIGHT_TIERS: Array[int] = []
var _tier_index: int = 0

const GHOST_COLOR_VALID:   Color = Color(0.40, 1.00, 0.50, 0.55)
const GHOST_COLOR_INVALID: Color = Color(1.00, 0.35, 0.35, 0.55)

var camera:           Camera3D    = null
var world_node:       Node        = null
var build_hud:        CanvasLayer = null
var ray_length:       float       = 50.0
var build_controller: Node        = null

var _phase: int = 0   ## 0 = idle/armed, 1 = dragging
var _start_pos: Vector3 = Vector3.ZERO
var _end_pos:   Vector3 = Vector3.ZERO
var _run_angle_deg: float = 0.0
var _run_length: float = 0.0
var _start_snap: Dictionary = {}
var _end_snap: Dictionary = {}
var _idle_snap: Dictionary = {}

var _ghost_body: MeshInstance3D = null
var _cost_label: Label3D = null
var _pillar_connection_dots: Array[MeshInstance3D] = []

func _ready() -> void:
	set_process(false)

func activate() -> void:
	_phase = 0
	_run_angle_deg = 0.0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_start_snap = {}
	_end_snap = {}
	_idle_snap = {}
	_clear_ghost()
	_refresh_pillar_connection_dots()
	if build_controller != null:
		HEIGHT_TIERS = [
			build_controller.TILE_QUARTER_WALL,
			build_controller.TILE_HALF_WALL,
			build_controller.TILE_WALL,
		]
		if HEIGHT_TIERS.has(build_controller._selected_tile):
			_tier_index = HEIGHT_TIERS.find(build_controller._selected_tile)
	set_process(true)

func deactivate() -> void:
	set_process(false)
	_clear_ghost()
	_clear_pillar_connection_dots()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_cycle_tier(-1)
			return true
		if event.keycode == KEY_E:
			_cycle_tier(1)
			return true
		if event.keycode == KEY_ESCAPE:
			if _phase == 1:
				_cancel_drag()
			else:
				wall_tool_exit_requested.emit()
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _phase == 0:
				_start_drag()
			else:
				_confirm_wall()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _phase == 1:
				_cancel_drag()
			else:
				wall_tool_exit_requested.emit()
			return true
	return false

func _cycle_tier(delta: int) -> void:
	if HEIGHT_TIERS.is_empty():
		return
	_tier_index = posmod(_tier_index + delta, HEIGHT_TIERS.size())
	if build_controller != null:
		build_controller._selected_tile       = HEIGHT_TIERS[_tier_index]
		build_controller._selected_tile_price = build_controller._price_for_tile(HEIGHT_TIERS[_tier_index])
	if _phase == 1:
		_rebuild_ghost()

func _start_drag() -> void:
	if build_controller == null:
		return
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return
	_start_snap = _resolve_cursor(hit["position"])
	_start_pos = _start_snap["pos"]
	_end_pos     = _start_pos
	_end_snap = _start_snap.duplicate()
	_phase = 1

func _process(_delta: float) -> void:
	if build_controller == null:
		return
	if _phase == 0:
		_update_idle_ghost()
		return
	_refresh_drag_endpoint()

func _refresh_drag_endpoint() -> bool:
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return false
	_end_snap = _resolve_cursor(hit["position"])
	_end_pos = _end_snap["pos"]
	if Input.is_key_pressed(KEY_CTRL):
		_end_snap = _ctrl_constrained_snap(hit["position"], _end_snap)
		_end_pos = _end_snap["pos"]

	var dx: float = _end_pos.x - _start_pos.x
	var dz: float = _end_pos.z - _start_pos.z
	var raw_angle_deg: float = rad_to_deg(atan2(dx, dz))
	if raw_angle_deg < 0.0:
		raw_angle_deg += 360.0
	_run_angle_deg = raw_angle_deg
	_run_length = maxf(MIN_LENGTH, Vector2(dx, dz).length())
	_rebuild_ghost()
	return true

func _ctrl_constrained_snap(hit_pos: Vector3, candidate: Dictionary) -> Dictionary:
	var support: Node3D = candidate.get("wall") as Node3D
	if is_instance_valid(support) and candidate.get("target_kind", "wall") == "wall":
		var intersection: Vector3 = DragMath.snap_xz_octant_to_segment(
			_start_pos, hit_pos, candidate["run_start"], candidate["run_end"])
		if intersection.is_finite():
			intersection.y = TRUE_FLOOR_Y
			## Resolve again at the exact intersection so shared perimeter seams
			## retain every support node needed by collision exemptions.
			var exact_snap: Dictionary = build_controller._snap_wall_run_point(
				intersection, WallSnapHelpers.WALL_RUN_JUNCTION_EPSILON * 2.0)
			if not exact_snap.is_empty():
				return exact_snap
	## A discrete pillar socket or unreachable wall target may only keep its
	## snap if it already lies on the selected octant. Otherwise Ctrl wins.
	if is_instance_valid(support) and DragMath.is_xz_octant_aligned(
			_start_pos, candidate["pos"]):
		return candidate
	var free_pos: Vector3 = build_controller._snap_to_grid(hit_pos)
	free_pos.y = TRUE_FLOOR_Y
	free_pos = DragMath.snap_xz_to_octant(
		_start_pos, free_pos, float(build_controller.grid_size))
	return {"pos": free_pos, "wall": null, "walls": [], "at_cap": false}

## Wall placement has one cursor contract. Every visual and committed phase
## calls this resolver, so the idle marker cannot advertise a junction that the
## click or final placement later quantizes somewhere else.
func _resolve_cursor(hit_pos: Vector3) -> Dictionary:
	var wall_snap: Dictionary = build_controller._snap_wall_run_point(hit_pos)
	if not wall_snap.is_empty():
		var snapped: Vector3 = wall_snap["pos"]
		snapped.y = TRUE_FLOOR_Y
		wall_snap["pos"] = snapped
		return wall_snap
	var grid_pos: Vector3 = build_controller._snap_to_grid(hit_pos)
	grid_pos.y = TRUE_FLOOR_Y
	return {"pos": grid_pos, "wall": null, "walls": [], "at_cap": false}

func _snap_nodes(snap: Dictionary) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for value: Variant in snap.get("walls", []):
		var node: Node3D = value as Node3D
		if is_instance_valid(node) and not nodes.has(node):
			nodes.append(node)
	return nodes

func _junction_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = _snap_nodes(_start_snap)
	for node: Node3D in _snap_nodes(_end_snap):
		if not nodes.has(node):
			nodes.append(node)
	return nodes

## A run may branch from a wall at any angle or continue from an end cap. It
## may not lie along the middle of an existing run, and both endpoints may not
## resolve to the same wall segment; those cases are overlays, not junctions.
func _junctions_are_valid() -> bool:
	return build_controller._wall_run_junctions_are_valid(
		_start_snap, _end_snap, _end_pos - _start_pos)

func _current_tier_height(tile_id: int) -> float:
	if build_controller == null:
		return WALL_HEIGHT_FULL
	if tile_id == build_controller.TILE_HALF_WALL:
		return WALL_HEIGHT_FULL * 0.5
	if tile_id == build_controller.TILE_QUARTER_WALL:
		return WALL_HEIGHT_FULL * 0.25
	return WALL_HEIGHT_FULL

## The wall's actual cross-section footprint — thin, NOT scaled by run
## length. This was the bug: using _run_length here made every sample point
## check a box as wide as half the whole wall, not the wall's real
## thickness.
func _wall_footprint_half_extent() -> Vector2:
	return Vector2(WALL_THICKNESS, WALL_THICKNESS)

## The wall's full placement footprint: half-thickness across the width and
## HALF the run length along it — the real thin rectangle a wall occupies.
## The occupancy test uses this unrotated footprint + the run angle and does a
## precise OBB overlap, so a diagonal wall blocks only its actual wall, not a
## bounding square.
func _wall_run_footprint() -> Vector2:
	return Vector2(WALL_THICKNESS * 0.5, _run_length * 0.5)

## True when the wall run's full rectangle (dynamic length + width, at the
## current run angle) overlaps any other placed object — checked every frame
## for the ghost (red) and again on confirm (blocked).
func _wall_run_is_occupied() -> bool:
	if build_controller == null or HEIGHT_TIERS.is_empty():
		return false
	if not _junctions_are_valid():
		return true
	return build_controller._is_position_occupied(
		_midpoint(), HEIGHT_TIERS[_tier_index], null, _wall_run_footprint(),
		_run_angle_deg, _junction_nodes())

## Samples points evenly along the run (roughly one per WALL_CELL_SIZE, at
## least the two endpoints) so a bounds check actually covers the whole
## length instead of relying on 3 fixed points with an oversized radius.
func _sample_points_along_run() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var sample_count: int = maxi(2, int(ceil(_run_length / WALL_CELL_SIZE)) + 1)
	for i: int in sample_count:
		var t: float = float(i) / float(sample_count - 1)
		points.append(_start_pos.lerp(_end_pos, t))
	return points

func _wall_run_is_inside_bunker() -> bool:
	## Occupancy against the perimeter walls protects the wall's width. Bounds
	## validate the centre line only, allowing a snapped endpoint to meet the
	## registered perimeter centre line and overlap inside its thickness.
	for p: Vector3 in _sample_points_along_run():
		if not build_controller._is_inside_bunker(p):
			return false
	return true

## Builds (or resizes) one MeshInstance3D box sized to _run_length at the
## current tier's height, positioned/rotated to span _start_pos → _end_pos.
## Used for BOTH the ghost preview and (via a fresh instance) the real
## placed wall, so the two are guaranteed visually identical.
func _build_wall_mesh(length: float, height: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(WALL_THICKNESS, height, length)
	mi.mesh = box
	mi.position = Vector3(0.0, height * 0.5, 0.0)   ## Bottom-at-body-local-0 — see Part 1
	return mi

func _midpoint() -> Vector3:
	return (_start_pos + _end_pos) * 0.5

func _rebuild_ghost() -> void:
	_clear_ghost()
	if build_controller == null or HEIGHT_TIERS.is_empty():
		return
	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var height:  float = _current_tier_height(tile_id)
	_ghost_body = _build_wall_mesh(_run_length, height)
	add_child(_ghost_body)
	_ghost_body.global_position  = _midpoint() + Vector3(0.0, height * 0.5, 0.0)
	_ghost_body.rotation_degrees = Vector3(0.0, _run_angle_deg, 0.0)

	var valid: bool = _wall_run_is_inside_bunker() and not _wall_run_is_occupied()
	_apply_ghost_material(valid)

	var price: int = build_controller._price_for_tile(tile_id)
	var total_cost: int = int(round(price * (_run_length / WALL_CELL_SIZE)))
	_update_cost_label(total_cost)

func _apply_ghost_material(valid: bool) -> void:
	if _ghost_body == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = GHOST_COLOR_VALID if valid else GHOST_COLOR_INVALID
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_body.material_override = mat

## Phase-0 preview: a short sliver — same height and thickness as a real
## wall at the current tier, 1/4 the length of a normal cell — marking
## where a drag would start if clicked right now. Reuses _build_wall_mesh()
## so it's visually consistent with the real thing, just short.
func _update_idle_ghost() -> void:
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		_clear_ghost()
		return
	if HEIGHT_TIERS.is_empty():
		return
	_idle_snap = _resolve_cursor(hit["position"])
	var cursor: Vector3 = _idle_snap["pos"]
	var preview_cursor: Vector3 = _idle_preview_position(_idle_snap)

	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var height:  float = _current_tier_height(tile_id)

	_clear_ghost()
	_ghost_body = _build_wall_mesh(IDLE_SLIVER_LENGTH, height)
	add_child(_ghost_body)
	_ghost_body.global_position = preview_cursor + Vector3(0.0, height * 0.5, 0.0)
	## Idle is always neutral; the placed run's angle must not leak into the
	## next wall's start affordance.
	_ghost_body.rotation_degrees = Vector3.ZERO

	## A snapped anchor sits on the registered perimeter centre line by design.
	## Its support wall contains the sliver; unsnapped floor anchors still use
	## the conservative footprint-aware bounds check.
	var bounds_extent: Vector2 = (Vector2.ZERO if is_instance_valid(
		_idle_snap.get("wall") as Node3D) else _wall_footprint_half_extent())
	var valid: bool = build_controller._is_inside_bunker(cursor, bounds_extent)
	## Aug 2026 — also mark the idle sliver red if it would overlap an object.
	if valid:
		valid = not build_controller._is_position_occupied(cursor, tile_id, null,
			Vector2(WALL_THICKNESS * 0.5, IDLE_SLIVER_LENGTH * 0.5), _run_angle_deg,
			_snap_nodes(_idle_snap))
	_apply_ghost_material(valid)
	if _cost_label != null:
		_cost_label.visible = false

func _idle_preview_position(snap: Dictionary) -> Vector3:
	var position: Vector3 = snap.get("pos", Vector3.ZERO)
	var support: Node3D = snap.get("wall") as Node3D
	if not is_instance_valid(support):
		return position
	var normal: Vector3 = snap.get("normal", Vector3.ZERO)
	var offset: float = (
		IDLE_PILLAR_PREVIEW_OFFSET
		if snap.get("target_kind", "wall") == "pillar"
		else IDLE_WALL_PREVIEW_OFFSET)
	return position + normal.normalized() * offset

func _clear_ghost() -> void:
	if _ghost_body != null and is_instance_valid(_ghost_body):
		_ghost_body.queue_free()
	_ghost_body = null
	if _cost_label != null and is_instance_valid(_cost_label):
		_cost_label.visible = false

func _update_cost_label(total_cost: int) -> void:
	if _cost_label == null:
		_cost_label = Label3D.new()
		_cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_cost_label.font_size = 32
		add_child(_cost_label)
	_cost_label.visible = true
	_cost_label.text = "%s  (%.1fm)" % [UIFormat.money(total_cost), _run_length]
	_cost_label.global_position = _midpoint() + Vector3(0.0, 1.2, 0.0)

func _confirm_wall() -> void:
	if build_controller == null or HEIGHT_TIERS.is_empty():
		return
	## Re-evaluate Ctrl and the current cursor on the click frame so commit and
	## preview can never disagree if the modifier changed between frames.
	_refresh_drag_endpoint()
	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var height:  float = _current_tier_height(tile_id)
	var price:   int = build_controller._price_for_tile(tile_id)
	var total_cost: int = int(round(price * (_run_length / WALL_CELL_SIZE)))

	if not _wall_run_is_inside_bunker():
		build_controller._show_hud_warning("Cannot place outside the bunker")
		return

	if _wall_run_is_occupied():
		build_controller._show_hud_warning("Space is already occupied")
		return

	if world_node != null and not world_node.spend_cash(total_cost):
		return

	## Build the REAL wall body — StaticBody3D (matches every other placed
	## object's collision-layer convention) with the same mesh/dimensions
	## as the ghost, plus a matching BoxShape3D.
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 5
	body.collision_mask  = 0
	var mi: MeshInstance3D = _build_wall_mesh(_run_length, height)
	body.add_child(mi)
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(WALL_THICKNESS, height, _run_length)
	cshape.shape = box_shape
	cshape.position = mi.position   ## Same H/2 centering as the mesh
	body.add_child(cshape)
	body.set_meta("tile_id", tile_id)

	var parent: Node = build_controller.gridmap.get_parent() if build_controller.gridmap != null else build_controller.get_tree().get_root()
	parent.add_child(body)
	body.global_position  = _midpoint()
	body.rotation_degrees = Vector3(0.0, _run_angle_deg, 0.0)
	build_controller._apply_world_material(body, tile_id)   ## Reuses _mat_wall — triplanar tiling comes for free, see Part 0

	build_controller._placed_objects.append({
		"node":          body,
		"tile_id":       tile_id,
		"price":         total_cost,
		"world_pos":     _midpoint(),
		"angle_deg":     _run_angle_deg,
		"player_placed": true,
		"footprint":     Vector2(WALL_THICKNESS * 0.5, _run_length * 0.5),
	})

	wall_placed.emit(body, tile_id, total_cost, _midpoint(), _run_angle_deg)
	build_controller._spawn_float_label_at_pos(_midpoint(), total_cost, false)
	## The mode remains active after placement, so refresh availability now;
	## otherwise a newly occupied pillar socket would keep its blue dot until
	## the player left and re-entered wall mode.
	_refresh_pillar_connection_dots()

	_phase = 0
	_run_angle_deg = 0.0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_start_snap = {}
	_end_snap = {}
	_idle_snap = {}
	_clear_ghost()

func _cancel_drag() -> void:
	_phase = 0
	_run_angle_deg = 0.0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_start_snap = {}
	_end_snap = {}
	_idle_snap = {}
	_clear_ghost()

func _refresh_pillar_connection_dots() -> void:
	_clear_pillar_connection_dots()
	if build_controller == null:
		return
	var parent: Node = (
		build_controller.gridmap.get_parent()
		if build_controller.gridmap != null
		else build_controller.get_tree().get_root())
	for point: Vector3 in build_controller._pillar_wall_snap_points(TRUE_FLOOR_Y + 0.08):
		var sphere := SphereMesh.new()
		sphere.radius = CONNECTION_DOT_RADIUS
		sphere.height = CONNECTION_DOT_RADIUS * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var material := StandardMaterial3D.new()
		material.albedo_color = CONNECTION_DOT_COLOR
		material.emission_enabled = true
		material.emission = CONNECTION_DOT_COLOR
		material.emission_energy_multiplier = 1.2
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.render_priority = 3
		var dot := MeshInstance3D.new()
		dot.mesh = sphere
		dot.material_override = material
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.extra_cull_margin = 10.0
		parent.add_child(dot)
		dot.global_position = point
		_pillar_connection_dots.append(dot)

func _clear_pillar_connection_dots() -> void:
	for dot: MeshInstance3D in _pillar_connection_dots:
		if is_instance_valid(dot):
			dot.queue_free()
	_pillar_connection_dots.clear()
