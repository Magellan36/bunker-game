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

			## Aug 2026 — sync the ghost facing to the source object's angle so
			## the move preview starts where the object actually faces, and the
			## wheel (which rotates via _current_angle_deg) rotates it from
			## there, exactly like initial placement.
			var src_angle: float = float(entry["angle_deg"])
			_owner._current_angle_deg = src_angle
			var found_orient: bool = false
			for i: int in _owner.EIGHT_DIR_ANGLES.size():
				if absf(_owner.EIGHT_DIR_ANGLES[i] - src_angle) < 1.0:
					_owner._orient_index = i
					found_orient = true
					break
			if not found_orient:
				_owner._orient_index = -1

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

	## Aug 2026 — build the move ghost with the SAME preview builder as initial
	## placement (GhostPreview.build_ghost_onto → _rebuild_ghost_mesh), so
	## EVERY tile type gets a preview when moved. The old hand-rolled per-tile
	## switch only covered a handful of types (shelves/lights/generators/
	## wires/heavy/hookup/sink/dispenser/trays/grow lights/stove), leaving most
	## furniture with no ghost at all.
	var parent: Node = _owner.gridmap.get_parent() if _owner.gridmap != null else _owner.get_tree().get_root()
	## LIFECYCLE RULE (same as GhostPreview._spawn_ghost): the ghost root MUST
	## be inside the SceneTree before the builder runs, so real-instance
	## children's _ready() fires.
	parent.add_child(_owner._move_ghost)
	_owner._ghost_preview.build_ghost_onto(_owner._move_ghost, tile_id)
	## Cache the moved tile's model footprint too — it may not have been
	## selected this session (e.g. a tile loaded from a save), so the move
	## occupancy needs the measured footprint, not the hand-tuned fallback.
	_owner._cache_model_footprint(tile_id, _owner._ghost_preview.measure_visual_aabb(_owner._move_ghost))
	_owner._move_ghost.visible = false

func _update_move_ghost() -> void:
	if _owner._move_ghost == null or _owner._move_source_entry.is_empty():
		return

	var result: Dictionary = _owner._raycast_to_grid()
	if result.is_empty():
		_owner._move_ghost.visible = false
		return

	var snap_pos: Vector3 = _owner._snap_to_grid(result["position"])
	## Preserve the object's existing Y height when moving (Aug 2026). The old
	## per-tile PLACEMENT_Y fallback (2.0, the wall height) was lifting every
	## floor object (tables, chairs, trays, stove, storage, ...) off the floor
	## when moved. Every non-wall-snapped tile keeps its source Y; only the
	## three wall-snapped tile types below override it (they need their mount
	## height as the wall-snap raycast input).
	snap_pos.y = _owner._move_source_pos.y
	var mv_tile: int = _owner._move_source_entry.get("tile_id", _owner.TILE_WALL)
	## Ghost rotation follows _current_angle_deg (Aug 2026) — synced to the
	## source object's angle on select, and rotated by the mouse wheel exactly
	## like initial placement. Wall-snapped tile types below override it with
	## their snap-result angle.
	var ghost_angle_deg: float = _owner._current_angle_deg

	if mv_tile == _owner.TILE_LIGHT:
		snap_pos.y = _owner.LIGHT_PLACEMENT_Y
		## July 2026 fix: moving a light previously never re-ran wall-snap —
		## it just re-snapped to the flat grid, inconsistent with how it was
		## originally placed (see WallSnapHelpers.gd / GhostPreview.gd, which
		## both correctly wall-snap on INITIAL placement already). Reuse the
		## same proven _snap_light_to_wall() call GhostPreview uses — zero new
		## risk, this function is pure/read-only w.r.t. game state.
		var light_snapped: Dictionary = _owner._snap_light_to_wall(snap_pos)
		if not light_snapped.is_empty():
			snap_pos        = light_snapped["pos"]
			ghost_angle_deg = light_snapped["angle_deg"]
		else:
			_owner._move_ghost.visible = false
			return
	elif mv_tile == _owner.TILE_BREAKER or mv_tile == _owner.TILE_BREAKER_SMART:
		snap_pos.y = _owner.PLACEMENT_Y
		## Same July 2026 fix as TILE_LIGHT above, reusing the existing proven
		## _snap_breaker_to_wall() — shared by both breaker variants already.
		var brk_snapped: Dictionary = _owner._snap_breaker_to_wall(snap_pos)
		if not brk_snapped.is_empty():
			snap_pos        = brk_snapped["pos"]
			ghost_angle_deg = brk_snapped["angle_deg"]
		else:
			_owner._move_ghost.visible = false
			return
	elif mv_tile == _owner.TILE_WATER_HOOKUP:
		snap_pos.y = _owner.WATER_HOOKUP_PLACEMENT_Y   ## near-ceiling, see BuildModeController's own comment
		## Water hookup move (July 2026 groundwork pass) — the plan requires
		## this to accept ANY valid wall, any orientation (not just its
		## original one), and to update its recorded facing direction to
		## match whatever wall it lands on. Reuses the new generic
		## _snap_to_nearest_wall() helper — same mandatory-wall strictness as
		## initial placement (GhostPreview's TILE_WATER_HOOKUP branch above).
		var wh_snapped: Dictionary = _owner._snap_to_nearest_wall(snap_pos, 0.0, 0.05, 1.5)
		if not wh_snapped.is_empty():
			snap_pos        = wh_snapped["pos"]
			ghost_angle_deg = wh_snapped["angle_deg"]
		else:
			_owner._move_ghost.visible = false
			return

	_owner._move_ghost.global_position = snap_pos
	_owner._move_ghost.rotation_degrees = Vector3(0.0, ghost_angle_deg, 0.0)
	_owner._move_ghost.visible = true
	## Keep the ghost green — matches the placement ghost's per-frame tint
	## (real-model previews keep their own materials, so the tint is what makes
	## the move preview read as a ghost).
	GhostModelBuilder.apply_ghost_tint(_owner._move_ghost, true)

func _move_confirm() -> void:
	if _owner._move_ghost == null or _owner._move_source_body == null:
		_cancel_move()
		return

	var new_pos: Vector3 = _owner._move_ghost.global_position
	var tile_id: int = _owner._move_source_entry.get("tile_id", _owner.TILE_WALL)
	## Captured here (before _destroy_move_ghost() below frees the ghost) so
	## wall-snapped tile types commit their possibly-new angle — see the
	## July 2026 wall-snap-on-move fix in _update_move_ghost() above. Previously
	## NO tile type committed a rotation change on move at all; this is
	## additive for the 3 wall-snapped types only, zero behavior change for
	## every other tile (their angle_deg simply round-trips unchanged).
	var new_angle_deg: float = _owner._move_ghost.rotation_degrees.y

	# Don't allow placing on top of another object (other than self)
	_owner._move_source_body.visible = true  ## Temporarily make visible for overlap check
	for child in _owner._move_source_body.get_children():
		if child is MeshInstance3D:
			child.visible = true
	## Exclude self from overlap check by temporarily disabling collision
	## (Only CollisionObject3D subclasses have collision_layer; Node3D e.g. WallLight does not)
	if _owner._move_source_body is CollisionObject3D:
		(_owner._move_source_body as CollisionObject3D).collision_layer = 0

	## Use the moved object's STORED footprint (walls store their full run
	## rectangle), rotated to the ghost's current angle — so a long wall keeps
	## its full-length clearance when moved, not the small tile-derived box.
	var src_he: Vector2 = _owner._move_source_entry.get("footprint", _owner._tile_half_extents(tile_id))
	var new_he_rot: Vector2 = _owner._rotate_he(src_he, _owner._current_angle_deg)
	var occupied: bool = _owner._is_position_occupied_for_tile(new_pos, tile_id, _owner._move_source_body, new_he_rot)

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

	## Commit the ghost's rotation for EVERY tile (Aug 2026) — the move ghost
	## now mirrors placement (wheel-rotatable), so the moved object adopts
	## whatever angle the ghost was left at. Starts equal to the source angle
	## (synced in _move_select), so it only changes if the player rotated it.
	_owner._move_source_body.rotation_degrees = Vector3(0.0, new_angle_deg, 0.0)
	_owner._move_source_entry["angle_deg"] = new_angle_deg

	## Water hookup: its WaterGraph node is keyed by position, so a manual
	## move needs the same re-registration reposition_to_outer_wall() does
	## after an automatic boundary-tracking move (see WaterHookup.gd).
	if tile_id == _owner.TILE_WATER_HOOKUP and _owner._move_source_body.has_method("update_graph_node_position"):
		_owner._move_source_body.call("update_graph_node_position")

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

