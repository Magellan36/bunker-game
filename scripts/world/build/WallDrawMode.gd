extends Node
## WallDrawMode.gd (rewrite — single stretched wall, not N segments)
## Click-drag-click wall placement. Click 1 anchors the start (grid-snapped),
## dragging stretches ONE wall mesh/collision from start to cursor at a free
## 360° angle, click 2 confirms and spawns exactly one StaticBody3D sized to
## the exact run length. Q/E cycle height tier at any time.

signal wall_placed(node: Node3D, tile_id: int, price: int, pos: Vector3, angle_deg: float)
signal wall_tool_exit_requested()

const WALL_CELL_SIZE:  float = 1.0    ## $/price-per-meter unit — confirmed real mesh cell size
const WALL_THICKNESS:  float = 0.3    ## Confirmed from tile_set.tscn's BoxMesh
const WALL_HEIGHT_FULL: float = 3.0   ## Matches BuildModeController.WALL_HEIGHT_M
const TRUE_FLOOR_Y:    float = 0.5    ## True floor Y in this coordinate frame

const MIN_LENGTH: float = WALL_CELL_SIZE   ## Floor for a degenerate near-zero drag

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

var _ghost_body: MeshInstance3D = null
var _cost_label: Label3D = null

func _ready() -> void:
	set_process(false)

func activate() -> void:
	_phase = 0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_clear_ghost()
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

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_cycle_tier(-1)
			return true
		if event.keycode == KEY_E:
			_cycle_tier(1)
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
	elif build_controller != null:
		build_controller._update_ghost()

func _start_drag() -> void:
	if build_controller == null:
		return
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return
	_start_pos   = build_controller._snap_to_grid(hit["position"])
	_start_pos.y = TRUE_FLOOR_Y
	_end_pos     = _start_pos
	_phase = 1

func _process(_delta: float) -> void:
	if _phase != 1 or build_controller == null:
		return
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return
	var cursor: Vector3 = build_controller._snap_to_grid(hit["position"])
	_end_pos = Vector3(cursor.x, TRUE_FLOOR_Y, cursor.z)

	var dx: float = _end_pos.x - _start_pos.x
	var dz: float = _end_pos.z - _start_pos.z
	var raw_angle_deg: float = rad_to_deg(atan2(dx, dz))
	if raw_angle_deg < 0.0:
		raw_angle_deg += 360.0
	_run_angle_deg = raw_angle_deg
	_run_length    = maxf(MIN_LENGTH, Vector2(dx, dz).length())
	_rebuild_ghost()

func _current_tier_height(tile_id: int) -> float:
	if build_controller == null:
		return WALL_HEIGHT_FULL
	if tile_id == build_controller.TILE_HALF_WALL:
		return WALL_HEIGHT_FULL * 0.5
	if tile_id == build_controller.TILE_QUARTER_WALL:
		return WALL_HEIGHT_FULL * 0.25
	return WALL_HEIGHT_FULL

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
	_ghost_body.global_position  = _midpoint()
	_ghost_body.rotation_degrees = Vector3(0.0, _run_angle_deg, 0.0)

	var half_extent: Vector2 = Vector2(WALL_THICKNESS * 0.5, _run_length * 0.5)
	var valid: bool = build_controller._is_inside_bunker(_start_pos, half_extent) \
		and build_controller._is_inside_bunker(_end_pos, half_extent) \
		and build_controller._is_inside_bunker(_midpoint(), half_extent)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = GHOST_COLOR_VALID if valid else GHOST_COLOR_INVALID
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_body.material_override = mat

	var price: int = build_controller._price_for_tile(tile_id)
	var total_cost: int = int(round(price * (_run_length / WALL_CELL_SIZE)))
	_update_cost_label(total_cost)

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
	_cost_label.text = "$%d  (%.1fm)" % [total_cost, _run_length]
	_cost_label.global_position = _midpoint() + Vector3(0.0, 1.2, 0.0)

func _confirm_wall() -> void:
	if build_controller == null or HEIGHT_TIERS.is_empty():
		return
	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var height:  float = _current_tier_height(tile_id)
	var price:   int = build_controller._price_for_tile(tile_id)
	var total_cost: int = int(round(price * (_run_length / WALL_CELL_SIZE)))

	var half_extent: Vector2 = Vector2(WALL_THICKNESS * 0.5, _run_length * 0.5)
	for p: Vector3 in [_start_pos, _end_pos, _midpoint()]:
		if not build_controller._is_inside_bunker(p, half_extent):
			build_controller._show_hud_warning("Cannot place outside the bunker")
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
	})

	wall_placed.emit(body, tile_id, total_cost, _midpoint(), _run_angle_deg)
	build_controller._spawn_float_label_at_pos(_midpoint(), total_cost, false)

	_phase = 0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_clear_ghost()

func _cancel_drag() -> void:
	_phase = 0
	_start_pos = Vector3.ZERO
	_end_pos   = Vector3.ZERO
	_clear_ghost()