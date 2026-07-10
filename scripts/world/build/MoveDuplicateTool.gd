extends RefCounted
class_name MoveDuplicateTool
## MoveDuplicateTool.gd  —  Stage 10 (BuildModeController slice) extraction
## ─────────────────────────────────────────────────────────────────────────────
## The move/duplicate tool logic, extracted out of BuildModeController.gd:
## duplicate (copies a placed object's tile/angle/price and re-enters
## construct mode with it pre-selected) and the two-phase move tool (phase 0
## select → spawn a green move-ghost clone; phase 1 confirm/cancel → commit
## the position change, including shelf-stored-item repositioning, or restore).
##
## SCOPE: _try_duplicate, _pick_dupe_source (dead stub, kept verbatim),
## _try_move_click, _move_select, _spawn_move_ghost, _update_move_ghost,
## _move_confirm, _cancel_move_confirm, _cancel_move, _destroy_move_ghost.
## Confirmed zero external callers anywhere else in the repo before
## extraction (same check as every prior slice).
##
## DESIGN — same `_owner` back-reference pattern as every prior extraction.
## Nothing moved: `_placed_objects`, `_dupe_source_tile/_angle/_price`,
## `EIGHT_DIR_ANGLES`, `_orient_index`, `_current_angle_deg`, `build_hud`,
## `_move_phase`, `_move_source_body/_entry/_pos`, `_move_ghost`, `gridmap`,
## `_mat_valid`, all `TILE_*`/`*_PLACEMENT_Y` consts stay on
## BuildModeController. Also routes `_owner._get_hovered_placed_body()`,
## `_owner._show_hud_warning()`, `_owner._on_construct_item_chosen()`,
## `_owner._clear_hover_glow()`, `_owner._raycast_to_grid()`,
## `_owner._snap_to_grid()`, `_owner._is_position_occupied_for_tile()`,
## `_owner._push_undo_move()` (BuildModeController's own forwarding wrapper
## into BuildUndoStack — called as a normal method here, no special handling
## needed), and `_owner.get_tree()` (RefCounted has no scene-tree access of
## its own).
##
## BuildModeController holds one instance (`_move_tool`) and forwards the 6
## functions still called from elsewhere in that file with identical
## signatures: `_try_duplicate()`/`_pick_dupe_source()`/`_try_move_click()`
## (input handling), `_update_move_ghost()` (`_process()`),
## `_cancel_move_confirm()`/`_cancel_move()` (tool-switch/exit/undo-request
## paths). `_move_select()`, `_spawn_move_ghost()`, `_move_confirm()`, and
## `_destroy_move_ghost()` are only called from within this same cluster, so
## need no wrapper.

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner


func _try_duplicate() -> void:
	var body: Node3D = _owner._get_hovered_placed_body()
	if body == null:
		return
	for entry: Dictionary in _owner._placed_objects:
		if entry["node"] == body:
			# Guard: level-placed objects cannot be duplicated
			if not entry.get("player_placed", true):
				_owner._show_hud_warning("Cannot modify level structure")
				return
			_owner._dupe_source_tile  = entry["tile_id"]
			_owner._dupe_source_angle = entry["angle_deg"]
			_owner._dupe_source_price = entry["price"]
			var snapped_angle: float = entry["angle_deg"]
			for i: int in _owner.EIGHT_DIR_ANGLES.size():
				if absf(_owner.EIGHT_DIR_ANGLES[i] - snapped_angle) < 1.0:
					_owner._orient_index      = i
					_owner._current_angle_deg = _owner.EIGHT_DIR_ANGLES[i]
					break
			_owner._on_construct_item_chosen(_owner._dupe_source_tile)
			if _owner.build_hud != null:
				_owner.build_hud.set_active_tool(0)
			return

func _pick_dupe_source() -> void:
	pass

# ─── Move tool ────────────────────────────────────────────────────────────────
## Called on left-click while tool 3 (Move) is active.
## Phase 0 → click selects hovered object → Phase 1
## Phase 1 → click confirms new position → back to Phase 0
func _try_move_click() -> void:
	if _owner._move_phase == 0:
		_move_select()
	elif _owner._move_phase == 1:
		_move_confirm()

func _move_select() -> void:
	## Phase 0: select the hovered placed object for moving
	var body: Node3D = _owner._get_hovered_placed_body()
	if body == null:
		return

	# Find its registry entry
	for entry: Dictionary in _owner._placed_objects:
		if entry["node"] == body:
			# Guard: level-placed objects cannot be moved
			if not entry.get("player_placed", true):
				_owner._show_hud_warning("Cannot modify level structure")
				return
			_owner._move_source_body  = body
			_owner._move_source_entry = entry
			_owner._move_source_pos   = entry["world_pos"]

			# Hide original object while placing — it stays alive for physics
			body.visible = false
			# Also hide any child mesh instances so ghost doesn't double-render
			for child in body.get_children():
				if child is MeshInstance3D:
					child.visible = false

			# Spawn move ghost (clone of source mesh with green material)
			_spawn_move_ghost(entry["tile_id"])
			_owner._move_phase = 1
			_owner._clear_hover_glow()
			return

func _spawn_move_ghost(tile_id: int) -> void:
	_destroy_move_ghost()
	_owner._move_ghost = MeshInstance3D.new()

	if tile_id == _owner.TILE_SHELVING:
		var shelving_script: GDScript = load("res://scripts/world/furniture/Shelving.gd")
		if shelving_script != null and shelving_script.has_method("build_ghost_mesh"):
			var m: Mesh = shelving_script.build_ghost_mesh()
			if m != null:
				_owner._move_ghost.mesh = m
				for s: int in m.get_surface_count():
					_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)
	elif tile_id == _owner.TILE_LIGHT:
		var light_script: GDScript = load("res://scripts/world/power/WallLight.gd")
		if light_script != null and light_script.has_method("build_ghost_mesh"):
			var m: Mesh = light_script.build_ghost_mesh()
			if m != null:
				_owner._move_ghost.mesh = m
				_owner._move_ghost.position = Vector3(0.0, 1.5, 0.0)  ## Match lamp height offset
				for s: int in m.get_surface_count():
					_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)
	elif tile_id == _owner.TILE_GEN_S or tile_id == _owner.TILE_GEN_M or tile_id == _owner.TILE_GEN_L:
		const MG_SIZES: Array = [
			Vector3(0.85, 0.85, 0.85),
			Vector3(0.85, 0.85, 1.85),
			Vector3(1.85, 0.85, 1.85),
		]
		var tier: int = 0
		if tile_id == _owner.TILE_GEN_M: tier = 1
		elif tile_id == _owner.TILE_GEN_L: tier = 2
		var box: BoxMesh = BoxMesh.new()
		box.size = MG_SIZES[tier]
		_owner._move_ghost.mesh = box
		_owner._move_ghost.position = Vector3(0.0, MG_SIZES[tier].y * 0.5, 0.0)
		for s: int in box.get_surface_count():
			_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)
	elif tile_id == _owner.TILE_WIRE:
		var wire_box: BoxMesh = BoxMesh.new()
		wire_box.size = Vector3(0.90, 0.06, 0.08)
		_owner._move_ghost.mesh = wire_box
		_owner._move_ghost.position = Vector3(0.0, 0.03, 0.0)
		for s: int in wire_box.get_surface_count():
			_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)
	elif tile_id == _owner.TILE_HEAVY:
		var hc_box: BoxMesh = BoxMesh.new()
		hc_box.size = Vector3(0.60, 0.60, 0.60)
		_owner._move_ghost.mesh = hc_box
		_owner._move_ghost.position = Vector3(0.0, 0.30, 0.0)
		for s: int in hc_box.get_surface_count():
			_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)
	else:
		if _owner.gridmap != null and _owner.gridmap.mesh_library != null:
			var m: Mesh = _owner.gridmap.mesh_library.get_item_mesh(tile_id)
			if m != null:
				_owner._move_ghost.mesh = m
				for s: int in m.get_surface_count():
					_owner._move_ghost.set_surface_override_material(s, _owner._mat_valid)

	var parent: Node = _owner.gridmap.get_parent() if _owner.gridmap != null else _owner.get_tree().get_root()
	parent.add_child(_owner._move_ghost)
	_owner._move_ghost.visible = false

func _update_move_ghost() -> void:
	if _owner._move_ghost == null or _owner._move_source_entry.is_empty():
		return

	var result: Dictionary = _owner._raycast_to_grid()
	if result.is_empty():
		_owner._move_ghost.visible = false
		return

	var snap_pos: Vector3 = _owner._snap_to_grid(result["position"])
	var mv_tile: int = _owner._move_source_entry.get("tile_id", _owner.TILE_WALL)
	if mv_tile == _owner.TILE_SHELVING or mv_tile == _owner.TILE_BED:
		snap_pos.y = _owner.SHELF_PLACEMENT_Y
	elif mv_tile == _owner.TILE_LIGHT:
		snap_pos.y = _owner.LIGHT_PLACEMENT_Y
	elif mv_tile == _owner.TILE_GEN_S or mv_tile == _owner.TILE_GEN_M \
			or mv_tile == _owner.TILE_GEN_L:
		snap_pos.y = _owner.GEN_PLACEMENT_Y
	elif mv_tile == _owner.TILE_WIRE or mv_tile == _owner.TILE_HEAVY:
		snap_pos.y = _owner.PLACEMENT_Y
	elif mv_tile == _owner.TILE_BREAKER or mv_tile == _owner.TILE_BREAKER_SMART \
			or mv_tile == _owner.TILE_BATTERY_S \
			or mv_tile == _owner.TILE_BATTERY_M or mv_tile == _owner.TILE_BATTERY_L:
		snap_pos.y = _owner.PLACEMENT_Y
	else:
		snap_pos.y = _owner.PLACEMENT_Y

	_owner._move_ghost.global_position = snap_pos
	_owner._move_ghost.rotation_degrees = Vector3(0.0, _owner._move_source_entry.get("angle_deg", 0.0), 0.0)
	_owner._move_ghost.visible = true
	# Keep ghost green — reuse _owner._mat_valid which is already applied

func _move_confirm() -> void:
	if _owner._move_ghost == null or _owner._move_source_body == null:
		_cancel_move()
		return

	var new_pos: Vector3 = _owner._move_ghost.global_position
	var tile_id: int = _owner._move_source_entry.get("tile_id", _owner.TILE_WALL)

	# Don't allow placing on top of another object (other than self)
	_owner._move_source_body.visible = true  ## Temporarily make visible for overlap check
	for child in _owner._move_source_body.get_children():
		if child is MeshInstance3D:
			child.visible = true
	## Exclude self from overlap check by temporarily disabling collision
	## (Only CollisionObject3D subclasses have collision_layer; Node3D e.g. WallLight does not)
	if _owner._move_source_body is CollisionObject3D:
		(_owner._move_source_body as CollisionObject3D).collision_layer = 0

	var occupied: bool = _owner._is_position_occupied_for_tile(new_pos, tile_id)

	## Restore full layer (1=player collide, 4=build hover raycast) — NOT just 4
	if _owner._move_source_body is CollisionObject3D:
		(_owner._move_source_body as CollisionObject3D).collision_layer = 5
	_owner._move_source_body.visible = false
	for child in _owner._move_source_body.get_children():
		if child is MeshInstance3D:
			child.visible = false

	if occupied:
		_owner._show_hud_warning("Space is already occupied")
		return

	# Push undo entry for the move before committing
	_owner._push_undo_move(_owner._move_source_body, _owner._move_source_entry, _owner._move_source_pos)

	# Commit the move — calculate delta so stored items move with shelf
	var old_pos: Vector3 = _owner._move_source_entry["world_pos"]
	var delta: Vector3   = new_pos - old_pos

	_owner._move_source_body.global_position = new_pos
	_owner._move_source_entry["world_pos"] = new_pos
	_owner._move_source_body.visible = true
	for child in _owner._move_source_body.get_children():
		if child is MeshInstance3D:
			child.visible = true

	# Move stored shelf items with the shelf
	if _owner._move_source_body.has_method("get") and "slots" in _owner._move_source_body:
		var shelf_slots: Array = _owner._move_source_body.slots
		for slot_stack: Array in shelf_slots:
			for item: RigidBody3D in slot_stack:
				if item != null and is_instance_valid(item):
					item.global_position += delta

	_destroy_move_ghost()
	_owner._move_phase       = 0
	_owner._move_source_body  = null
	_owner._move_source_entry = {}

func _cancel_move_confirm() -> void:
	## Cancel while in phase 1 — restore original visibility, back to phase 0
	if _owner._move_source_body != null and is_instance_valid(_owner._move_source_body):
		_owner._move_source_body.visible = true
		for child in _owner._move_source_body.get_children():
			if child is MeshInstance3D:
				child.visible = true
	_destroy_move_ghost()
	_owner._move_phase        = 0
	_owner._move_source_body  = null
	_owner._move_source_entry = {}

func _cancel_move() -> void:
	## Full cancel — also used on tool switch / exit
	_cancel_move_confirm()

func _destroy_move_ghost() -> void:
	if _owner._move_ghost != null:
		_owner._move_ghost.queue_free()
		_owner._move_ghost = null

