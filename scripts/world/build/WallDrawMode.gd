extends Node
## WallDrawMode.gd
## Click-drag-click wall placement tool. Auto-activated by BuildModeController
## when the selected Construct tile is TILE_WALL / TILE_HALF_WALL /
## TILE_QUARTER_WALL (see BuildModeController._on_construct_item_chosen wiring)
## — NOT a separate toolbar tool like WireDrawMode/WaterPipeDrawMode, though
## it borrows their activate()/deactivate()/handle_input() contract directly.
##
## Flow:
##   Click 1 (LMB) — grid-snap the cursor, anchor as run start. Enter phase 1.
##   Move           — drag vector locked to whichever cardinal axis (X or Z)
##                     is dominant; ghost shows N wall segments stepped along
##                     that axis at WALL_CELL_SIZE spacing, live cost label
##                     at the run's midpoint showing segment_count × tier price.
##   Click 2 (LMB) — finalise: spawn all N segments via
##                    build_controller._spawn_placed_object() (same function
##                    that spawns a single wall today), charge total cost
##                    once, push ONE batched undo entry, emit wall_run_placed.
##   RMB            — cancel current drag (phase 1 → phase 0) or, in phase 0,
##                     exit wall draw mode back to normal Construct placement.
##   Q / E          — cycle height tier (Quarter → Half → Full → Quarter) at
##                     any time, in phase 0 or phase 1. Rebuilds the ghost
##                     immediately at the new tier/price.

signal wall_run_placed(seg_nodes: Array, tile_id: int, price_per_segment: int, positions: Array, angle_deg: float)
signal wall_tool_exit_requested()

# ─── Tuning ───────────────────────────────────────────────────────────────
const WALL_CELL_SIZE: float = 1.0   ## spacing between adjacent wall segments

## Height tiers, cycled by Q (back) / E (forward). Order: Quarter → Half → Full.
var HEIGHT_TIERS: Array[int] = []   ## Populated in activate() from build_controller's TILE_QUARTER_WALL / TILE_HALF_WALL / TILE_WALL
var _tier_index: int = 0            ## 0 = Quarter, 1 = Half, 2 = Full

const GHOST_COLOR_VALID:   Color = Color(0.40, 1.00, 0.50, 0.55)
const GHOST_COLOR_INVALID: Color = Color(1.00, 0.35, 0.35, 0.55)

# ─── External refs (set by BuildModeController before activating) ─────────
var camera:           Camera3D = null
var world_node:       Node     = null
var build_hud:        CanvasLayer = null
var ray_length:       float    = 50.0
var build_controller: Node     = null   ## Back-ref, same pattern as WaterPipeDrawMode

# ─── State ──────────────────────────────────────────────────────────────
var _phase: int = 0   ## 0 = idle (armed, no drag yet), 1 = dragging
var _start_pos: Vector3 = Vector3.ZERO
var _run_positions: Array[Vector3] = []   ## Computed each frame in phase 1
var _run_angle_deg: float = 0.0

var _ghost_segments: Array[MeshInstance3D] = []   ## Pooled/rebuilt per frame
var _cost_label: Label3D = null

## Mirrors the per-tier Y constants the old single-click wall path already
## used (GhostPreview's height elif-chain) — WallDrawMode needs its own
## copy since it computes _start_pos directly rather than going through
## GhostPreview._update_ghost().
func _placement_y_for_tile(tile_id: int) -> float:
	if build_controller == null:
		return 0.0
	if tile_id == build_controller.TILE_HALF_WALL:
		return build_controller.HALF_WALL_PLACEMENT_Y
	if tile_id == build_controller.TILE_QUARTER_WALL:
		return build_controller.QUARTER_WALL_PLACEMENT_Y
	return build_controller.PLACEMENT_Y

func _ready() -> void:
	set_process(false)

# ─── Activation ───────────────────────────────────────────────────────────
func activate() -> void:
	_phase = 0
	_start_pos = Vector3.ZERO
	_run_positions.clear()
	_clear_ghost_segments()
	if _cost_label != null:
		_cost_label.queue_free()
		_cost_label = null
	if build_controller != null:
		HEIGHT_TIERS = [
			build_controller.TILE_QUARTER_WALL,
			build_controller.TILE_HALF_WALL,
			build_controller.TILE_WALL,
		]
	## Start on whichever tier the Construct menu had selected (Quarter/Half/Full
	## Wall row) so switching menu rows and re-entering feels consistent.
	if build_controller != null and HEIGHT_TIERS.has(build_controller._selected_tile):
		_tier_index = HEIGHT_TIERS.find(build_controller._selected_tile)
	set_process(true)

func deactivate() -> void:
	set_process(false)
	_clear_ghost_segments()
	if _cost_label != null:
		_cost_label.queue_free()
		_cost_label = null

# ─── Input (same bool-return contract as WireDrawMode.handle_input) ───────
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
				_confirm_run()
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
	## Live-rebuild whatever's currently shown at the new tier/price — works
	## in both phase 0 (single idle ghost, reuse GhostPreview's own tile
	## selection so the Construct submenu ghost + price label update too)
	## and phase 1 (rebuild the in-progress multi-segment run).
	if build_controller != null:
		build_controller._selected_tile       = HEIGHT_TIERS[_tier_index]
		build_controller._selected_tile_price = build_controller._price_for_tile(HEIGHT_TIERS[_tier_index])
	if _phase == 1:
		## FIX: re-height the in-progress run immediately, both the anchor
		## and every already-computed segment position, rather than waiting
		## for next frame's _process() tick to quietly correct it.
		_start_pos.y = _placement_y_for_tile(HEIGHT_TIERS[_tier_index])
		for i: int in _run_positions.size():
			_run_positions[i].y = _start_pos.y
		_rebuild_run_ghost()
	elif build_controller != null:
		build_controller._update_ghost()   ## Refresh the normal single-tile ghost at the new tier

func sync_selected_tier_from_controller() -> void:
	## Called when BuildModeController switches to a different wall tier via the
	## Construct menu while WallDrawMode is already active. Keeps ghost in sync.
	if build_controller != null and HEIGHT_TIERS.has(build_controller._selected_tile):
		_tier_index = HEIGHT_TIERS.find(build_controller._selected_tile)
		if _phase == 1:
			_rebuild_run_ghost()
		elif build_controller != null:
			build_controller._update_ghost()

# ─── Phase 0 → 1 ────────────────────────────────────────────────────────
func _start_drag() -> void:
	if build_controller == null:
		return
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return
	_start_pos = build_controller._snap_to_grid(hit["position"])
	var current_tile: int = HEIGHT_TIERS[_tier_index] if not HEIGHT_TIERS.is_empty() else build_controller.TILE_WALL
	_start_pos.y = _placement_y_for_tile(current_tile)   ## FIX: was always PLACEMENT_Y regardless of tier
	_phase = 1

# ─── Per-frame drag update ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _phase != 1 or build_controller == null:
		return
	var hit: Dictionary = build_controller._raycast_to_grid()
	if hit.is_empty():
		return
	var cursor: Vector3 = build_controller._snap_to_grid(hit["position"])

	var dx: float = cursor.x - _start_pos.x
	var dz: float = cursor.z - _start_pos.z
	var raw_length: float = Vector2(dx, dz).length()
	if raw_length < 0.001:
		_run_positions.clear()
		_rebuild_run_ghost()
		return

	## Snap the drag direction to the nearest of 8 compass directions (45°
	## steps) — reuses EIGHT_DIR_ANGLES, the same set already used for
	## manual wall rotation elsewhere in Construct mode, so a run can now
	## go cardinal (0/90/180/270) OR diagonal (45/135/225/315).
	var raw_angle_deg: float = rad_to_deg(atan2(dx, dz))
	if raw_angle_deg < 0.0:
		raw_angle_deg += 360.0
	var locked_angle_deg: float = _snap_to_eight_dir(raw_angle_deg)
	var angle_rad: float = deg_to_rad(locked_angle_deg)
	var dir: Vector2 = Vector2(sin(angle_rad), cos(angle_rad))   ## Unit step vector in XZ, matches the atan2(dx, dz) convention above

	var cell_count: int = maxi(1, int(round(raw_length / WALL_CELL_SIZE)))
	var current_tile: int = HEIGHT_TIERS[_tier_index] if not HEIGHT_TIERS.is_empty() else build_controller.TILE_WALL
	var seg_y: float = _placement_y_for_tile(current_tile)

	_run_positions.clear()
	for i: int in cell_count:
		var offset: Vector2 = dir * (float(i) * WALL_CELL_SIZE)
		var p: Vector3 = _start_pos
		p.x = _start_pos.x + offset.x
		p.z = _start_pos.z + offset.y
		## Re-snap XZ to the grid each segment — a 45° diagonal step won't
		## always land exactly on the fine 0.25 grid the way a cardinal step
		## does. This is the expected/standard tradeoff for diagonal
		## placement on a square grid (every base-building game with grid
		## snap has the same minor approximation) — segments stay grid-
		## snapped, just not perfectly evenly spaced along a true 45° line.
		var snapped_xz: Vector3 = build_controller._snap_to_grid(p)
		p.x = snapped_xz.x
		p.z = snapped_xz.z
		p.y = seg_y
		_run_positions.append(p)

	_run_angle_deg = locked_angle_deg
	_rebuild_run_ghost()

## Snaps a raw angle (degrees, 0–360) to the nearest of the 8
## EIGHT_DIR_ANGLES values, wrapping correctly at the 360→0 seam.
func _snap_to_eight_dir(raw_deg: float) -> float:
	var best_angle: float = 0.0
	var best_diff:  float = 361.0
	for a: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 360.0]:
		var diff: float = absf(raw_deg - a)
		if diff < best_diff:
			best_diff  = diff
			best_angle = a
	return fmod(best_angle, 360.0)   ## Folds a 360 match back to 0

# ─── Ghost rebuild (multi-segment) ─────────────────────────────────────
func _rebuild_run_ghost() -> void:
	_clear_ghost_segments()
	if build_controller == null or HEIGHT_TIERS.is_empty():
		return
	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var price:   int = build_controller._price_for_tile(tile_id)

	for pos: Vector3 in _run_positions:
		var seg: MeshInstance3D = build_controller._ghost_preview._build_single_wall_ghost_mesh(tile_id)
		if seg == null:
			continue
		add_child(seg)
		seg.global_position = pos
		seg.rotation_degrees = Vector3(0.0, _run_angle_deg, 0.0)
		var valid: bool = build_controller._is_inside_bunker(pos, build_controller._tile_half_extents(tile_id)) \
			and not build_controller._is_position_occupied(pos, tile_id)
		_apply_ghost_color(seg, valid)
		_ghost_segments.append(seg)

	_update_cost_label(_run_positions.size() * price)

func _clear_ghost_segments() -> void:
	for seg: MeshInstance3D in _ghost_segments:
		if is_instance_valid(seg):
			seg.queue_free()
	_ghost_segments.clear()

func _apply_ghost_color(seg: MeshInstance3D, valid: bool) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = GHOST_COLOR_VALID if valid else GHOST_COLOR_INVALID
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	seg.material_override = mat

func _update_cost_label(total_cost: int) -> void:
	if _run_positions.is_empty():
		if _cost_label != null:
			_cost_label.visible = false
		return
	if _cost_label == null:
		_cost_label = Label3D.new()
		_cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_cost_label.font_size = 32
		add_child(_cost_label)
	_cost_label.visible = true
	_cost_label.text = "$%d  (%d segments)" % [total_cost, _run_positions.size()]
	var mid: Vector3 = _run_positions[_run_positions.size() / 2]
	_cost_label.global_position = mid + Vector3(0.0, 1.2, 0.0)

# ─── Confirm ────────────────────────────────────────────────────────────
func _confirm_run() -> void:
	if build_controller == null or _run_positions.is_empty() or HEIGHT_TIERS.is_empty():
		return
	var tile_id: int = HEIGHT_TIERS[_tier_index]
	var price_per_segment: int = build_controller._price_for_tile(tile_id)
	var total_cost: int = price_per_segment * _run_positions.size()

	## Reject the whole run if ANY segment is invalid — same all-or-nothing
	## principle WaterPipeDrawMode already applies to a pipe run.
	for pos: Vector3 in _run_positions:
		if not build_controller._is_inside_bunker(pos, build_controller._tile_half_extents(tile_id)):
			build_controller._show_hud_warning("Cannot place outside the bunker")
			return
		if build_controller._is_position_occupied(pos, tile_id):
			build_controller._show_hud_warning("Space is already occupied")
			return

	if world_node != null and not world_node.spend_cash(total_cost):
		return

	var seg_nodes: Array = []
	for pos: Vector3 in _run_positions:
		var node: Node3D = build_controller._spawn_placed_object(tile_id, pos, _run_angle_deg)
		seg_nodes.append(node)
		build_controller._placed_objects.append({
			"node":          node,
			"tile_id":       tile_id,
			"price":         price_per_segment,
			"world_pos":     pos,
			"angle_deg":     _run_angle_deg,
			"player_placed": true,
		})

	wall_run_placed.emit(seg_nodes, tile_id, price_per_segment, _run_positions.duplicate(), _run_angle_deg)
	build_controller._spawn_float_label_at_pos(_run_positions[_run_positions.size() / 2], total_cost, false)

	## Stay in phase 1 → re-arm phase 0 at the SAME start point immediately
	## adjacent to the run just placed, so chaining a longer wall (or an
	## L-shaped run) doesn't require re-clicking the exact seam point.
	_phase = 0
	_start_pos = Vector3.ZERO
	_run_positions.clear()
	_clear_ghost_segments()
	if _cost_label != null:
		_cost_label.visible = false

# ─── Cancel drag ────────────────────────────────────────────────────────
func _cancel_drag() -> void:
	_phase = 0
	_start_pos = Vector3.ZERO
	_run_positions.clear()
	_clear_ghost_segments()
	if _cost_label != null:
		_cost_label.visible = false