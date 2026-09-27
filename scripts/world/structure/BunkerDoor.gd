extends StaticBody3D
class_name BunkerDoor

signal navigation_topology_changed()
## A player-built, manually-operated double sliding bunker door.
##
## The host wall remains the authoritative build object. Doors register a
## 1.8m cut on that wall and rebuild only its visible/collidable solid pieces.
## This makes removal, movement and undo restore the wall without manufacturing
## a replacement wall (and supports more than one door on a long wall).

const OPENING_WIDTH: float = 1.8
const OPENING_HEIGHT: float = 2.2
const PANEL_DEPTH: float = 0.12
const FRAME_DEPTH: float = 0.38
const FRAME_WIDTH: float = 0.12
const FRAME_WALL_CLEARANCE: float = 0.01
## The usable passage/panels remain exactly 1.8m. The structural cut includes
## both jambs plus a 1cm buffer outside each frame edge, preventing the wall's
## cut faces from occupying the same space and producing z-fighting artifacts.
const WALL_CUT_WIDTH: float = OPENING_WIDTH + (FRAME_WIDTH + FRAME_WALL_CLEARANCE) * 2.0
const WALL_CUT_HEIGHT: float = OPENING_HEIGHT + 0.16 + FRAME_WALL_CLEARANCE
const ANIM_TIME: float = 1.36
const CUTS_META: StringName = &"_bunker_door_cuts"
const ORIGINAL_META: StringName = &"_bunker_door_originals"
const GENERATED_META: StringName = &"_bunker_door_wall_segment"

var _is_preview_only: bool = false
var _host_wall: Node3D = null
var _left_panel: MeshInstance3D = null
var _right_panel: MeshInstance3D = null
var _left_collision: CollisionShape3D = null
var _right_collision: CollisionShape3D = null
var _is_open: bool = false
var _animating: bool = false
var _relocating: bool = false
var _tween: Tween = null
var _navigation_link: NavigationLink3D = null
var _npc_open_requested: bool = false


func _ready() -> void:
	collision_layer = 5
	collision_mask = 0
	set_meta("tile_id", 39)
	_build_model()
	_setup_navigation_link()
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("npc_bottleneck")
		add_to_group("navigation_topology_source")


func _exit_tree() -> void:
	if not _is_preview_only and not _relocating:
		_unregister_from_host()


func _build_model() -> void:
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.39, 0.41, 0.43)
	gray.metallic = 0.45
	gray.roughness = 0.42
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.20, 0.22, 0.24)
	dark.metallic = 0.6
	dark.roughness = 0.36

	# Local Z runs along the wall; local X is wall depth.
	_add_box("LeftJamb", Vector3(FRAME_DEPTH, OPENING_HEIGHT + 0.16, FRAME_WIDTH),
		Vector3.ZERO + Vector3(0.0, (OPENING_HEIGHT + 0.16) * 0.5, -OPENING_WIDTH * 0.5 - FRAME_WIDTH * 0.5), dark, true)
	_add_box("RightJamb", Vector3(FRAME_DEPTH, OPENING_HEIGHT + 0.16, FRAME_WIDTH),
		Vector3(0.0, (OPENING_HEIGHT + 0.16) * 0.5, OPENING_WIDTH * 0.5 + FRAME_WIDTH * 0.5), dark, true)
	_add_box("Header", Vector3(FRAME_DEPTH, 0.16, OPENING_WIDTH + FRAME_WIDTH * 2.0),
		Vector3(0.0, OPENING_HEIGHT + 0.08, 0.0), dark, true)

	_left_panel = _add_box("LeftDoor", Vector3(PANEL_DEPTH, OPENING_HEIGHT, OPENING_WIDTH * 0.5 - 0.02),
		Vector3(0.0, OPENING_HEIGHT * 0.5, -OPENING_WIDTH * 0.25), gray, false)
	_right_panel = _add_box("RightDoor", Vector3(PANEL_DEPTH, OPENING_HEIGHT, OPENING_WIDTH * 0.5 - 0.02),
		Vector3(0.0, OPENING_HEIGHT * 0.5, OPENING_WIDTH * 0.25), gray, false)
	_left_collision = _add_shape("LeftDoorCollision", Vector3(PANEL_DEPTH, OPENING_HEIGHT, OPENING_WIDTH * 0.5 - 0.02), _left_panel.position)
	_right_collision = _add_shape("RightDoorCollision", Vector3(PANEL_DEPTH, OPENING_HEIGHT, OPENING_WIDTH * 0.5 - 0.02), _right_panel.position)


func _setup_navigation_link() -> void:
	## A closed door separates the baked polygons on its two sides. This link
	## preserves the knowledge that the separation is intentionally traversable,
	## allowing an NPC route to choose the door and request that it open.
	_navigation_link = NavigationLink3D.new()
	_navigation_link.name = "NPCDoorPortal"
	_navigation_link.bidirectional = true
	_navigation_link.navigation_layers = 1
	_navigation_link.enter_cost = 0.25
	_navigation_link.start_position = Vector3(-1.15, 0.0, 0.0)
	_navigation_link.end_position = Vector3(1.15, 0.0, 0.0)
	add_child(_navigation_link)


func _add_box(node_name: String, size: Vector3, pos: Vector3, material: Material, with_collision: bool) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	mesh_instance.set_surface_override_material(0, material)
	add_child(mesh_instance)
	if with_collision:
		_add_shape(node_name + "Collision", size, pos)
	return mesh_instance


func _add_shape(node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	add_child(collision)
	return collision


func install_on_wall(wall: Node3D, world_pos: Vector3, angle_deg: float) -> void:
	_relocating = true
	_unregister_from_host()
	## The door must inherit the host wall's local floor plane. Generic build
	## placement uses a 2.0m Y convention for several older tiles; projecting
	## through wall-local space prevents that value (or stale save data) from
	## lifting the frame and panels above the opening.
	var wall_local := wall.to_local(world_pos)
	global_position = wall.to_global(Vector3(0.0, 0.0, wall_local.z))
	rotation_degrees = Vector3(0.0, angle_deg, 0.0)
	_host_wall = wall
	_register_with_host()
	_relocating = false


func capture_move_state() -> Dictionary:
	return {"host_wall": _host_wall, "world_pos": global_position,
		"angle_deg": rotation_degrees.y, "is_open": _is_open}


func restore_move_state(state: Dictionary) -> void:
	var wall: Node3D = state.get("host_wall") as Node3D
	if wall == null or not is_instance_valid(wall):
		return
	install_on_wall(wall, state.get("world_pos", global_position), float(state.get("angle_deg", rotation_degrees.y)))
	_set_open_immediate(bool(state.get("is_open", false)))


func get_saved_state() -> Dictionary:
	var host_pos := Vector3.ZERO
	var host_angle := 0.0
	if is_instance_valid(_host_wall):
		host_pos = _host_wall.global_position
		host_angle = _host_wall.rotation_degrees.y
	return {"is_open": _is_open,
		"host_pos": {"x": host_pos.x, "y": host_pos.y, "z": host_pos.z},
		"host_angle_deg": host_angle}


func apply_saved_state(wall: Node3D, state: Dictionary) -> void:
	if wall != null and is_instance_valid(wall):
		install_on_wall(wall, global_position, rotation_degrees.y)
	_set_open_immediate(bool(state.get("is_open", false)))


func get_host_wall() -> Node3D:
	return _host_wall


func is_open() -> bool:
	return _is_open


func get_npc_portal_info() -> Dictionary:
	## Local X crosses the wall; local Z spans the doorway opening.
	return {
		"open": _is_open and not _animating,
		"half_width": OPENING_WIDTH * 0.5,
		"wait_distance": 1.15,
		"exit_distance": 0.9,
	}


func request_npc_open(_npc: Node = null) -> bool:
	if _is_preview_only:
		return false
	if _is_open:
		## True once fully open; false while the panels are still retracting.
		return not _animating
	if _animating:
		## The player began closing it. Reopen exactly once after that animation
		## finishes instead of reversing/toggling the shared tween repeatedly.
		_npc_open_requested = true
		return false
	_is_open = true
	_animate_panels(true)
	return false


func get_interact_prompt() -> String:
	return "[E] Close Door" if _is_open else "[E] Open Door"


func on_interact() -> void:
	if _animating or _is_preview_only:
		return
	_is_open = not _is_open
	_animate_panels(_is_open)


func _animate_panels(opening: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_animating = true
	var closed_offset := OPENING_WIDTH * 0.25
	var open_offset := OPENING_WIDTH * 0.75
	var target := open_offset if opening else closed_offset
	_tween = create_tween().set_parallel(true)
	## Cubic preserves the requested slow-start/fast-finish opening and reverse
	## closing shape, but stretches the slow spatial half further than quadratic:
	## opening spends longer in its first half; closing spends longer in its last.
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_IN if opening else Tween.EASE_OUT)
	_tween.tween_property(_left_panel, "position:z", -target, ANIM_TIME)
	_tween.tween_property(_right_panel, "position:z", target, ANIM_TIME)
	_tween.tween_property(_left_collision, "position:z", -target, ANIM_TIME)
	_tween.tween_property(_right_collision, "position:z", target, ANIM_TIME)
	_tween.chain().tween_callback(func() -> void:
		_animating = false
		## Navigation must be rebuilt from the panels' FINAL collision transforms.
		## Rebaking when `_is_open` flips above captured the door mid-animation
		## and could permanently leave an open doorway disconnected.
		navigation_topology_changed.emit()
		if _npc_open_requested and not _is_open:
			_npc_open_requested = false
			request_npc_open())


func _set_open_immediate(opening: bool) -> void:
	_is_open = opening
	var offset := OPENING_WIDTH * (0.75 if opening else 0.25)
	if _left_panel != null:
		_left_panel.position.z = -offset
		_right_panel.position.z = offset
		_left_collision.position.z = -offset
		_right_collision.position.z = offset
	if is_inside_tree() and not _is_preview_only:
		navigation_topology_changed.emit()


func _register_with_host() -> void:
	if not is_instance_valid(_host_wall):
		return
	var doors: Array = _host_wall.get_meta(CUTS_META, [])
	if not doors.has(self):
		doors.append(self)
	_host_wall.set_meta(CUTS_META, doors)
	rebuild_host_wall(_host_wall)


func _unregister_from_host() -> void:
	if not is_instance_valid(_host_wall):
		_host_wall = null
		return
	var old_host := _host_wall
	var doors: Array = old_host.get_meta(CUTS_META, [])
	doors.erase(self)
	old_host.set_meta(CUTS_META, doors)
	_host_wall = null
	rebuild_host_wall(old_host)


static func has_active_doors(wall: Node3D) -> bool:
	if wall == null or not is_instance_valid(wall):
		return false
	for door: Variant in wall.get_meta(CUTS_META, []):
		if door != null and is_instance_valid(door):
			return true
	return false


static func rebuild_host_wall(wall: Node3D) -> void:
	if wall == null or not is_instance_valid(wall):
		return
	var originals: Array = wall.get_meta(ORIGINAL_META, [])
	if originals.is_empty():
		for child: Node in wall.get_children():
			if child is MeshInstance3D or child is CollisionShape3D:
				originals.append(child)
		wall.set_meta(ORIGINAL_META, originals)

	for child: Node in wall.get_children():
		if child.has_meta(GENERATED_META):
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true
			wall.remove_child(child)
			child.queue_free()

	var doors: Array = []
	for raw: Variant in wall.get_meta(CUTS_META, []):
		if raw != null and is_instance_valid(raw):
			doors.append(raw)
	wall.set_meta(CUTS_META, doors)
	if doors.is_empty():
		for raw: Variant in originals:
			if raw == null or not is_instance_valid(raw):
				continue
			if raw is MeshInstance3D:
				(raw as MeshInstance3D).visible = true
			elif raw is CollisionShape3D:
				(raw as CollisionShape3D).disabled = false
		return

	var source_mesh: MeshInstance3D = null
	var source_shape: CollisionShape3D = null
	for raw: Variant in originals:
		if raw is MeshInstance3D and source_mesh == null:
			source_mesh = raw as MeshInstance3D
		elif raw is CollisionShape3D and source_shape == null:
			source_shape = raw as CollisionShape3D
	if source_mesh == null or source_shape == null or not (source_shape.shape is BoxShape3D):
		return
	source_mesh.visible = false
	source_shape.disabled = true
	var size: Vector3 = (source_shape.shape as BoxShape3D).size
	var wall_half := size.z * 0.5
	var intervals: Array[Vector2] = []
	for door: BunkerDoor in doors:
		var local_z := wall.to_local(door.global_position).z
		intervals.append(Vector2(maxf(-wall_half, local_z - WALL_CUT_WIDTH * 0.5),
			minf(wall_half, local_z + WALL_CUT_WIDTH * 0.5)))
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var material: Material = source_mesh.get_surface_override_material(0)
	var cursor := -wall_half
	for cut: Vector2 in intervals:
		if cut.x > cursor + 0.001:
			_add_wall_piece(wall, size.x, size.y, cursor, cut.x, 0.0, size.y, material)
		# Keep the structural lintel above the door assembly, with the same tiny
		# clearance used around the jambs so the header cannot z-fight the wall.
		if size.y > WALL_CUT_HEIGHT:
			_add_wall_piece(wall, size.x, size.y - WALL_CUT_HEIGHT, cut.x, cut.y,
				WALL_CUT_HEIGHT, size.y - WALL_CUT_HEIGHT, material)
		cursor = maxf(cursor, cut.y)
	if cursor < wall_half - 0.001:
		_add_wall_piece(wall, size.x, size.y, cursor, wall_half, 0.0, size.y, material)


static func _add_wall_piece(wall: Node3D, depth: float, _wall_height: float,
		z0: float, z1: float, bottom_y: float, height: float, material: Material) -> void:
	var length := z1 - z0
	if length <= 0.001 or height <= 0.001:
		return
	var pos := Vector3(0.0, bottom_y + height * 0.5, (z0 + z1) * 0.5)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.set_meta(GENERATED_META, true)
	var box := BoxMesh.new()
	box.size = Vector3(depth, height, length)
	mesh_instance.mesh = box
	mesh_instance.position = pos
	if material != null:
		mesh_instance.set_surface_override_material(0, material)
	wall.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.set_meta(GENERATED_META, true)
	var shape := BoxShape3D.new()
	shape.size = Vector3(depth, height, length)
	collision.shape = shape
	collision.position = pos
	wall.add_child(collision)
