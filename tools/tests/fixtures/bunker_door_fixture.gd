extends Node3D

class TestBuild extends BuildModeController:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("Bunker door smoke: " + message)

func _ready() -> void:
	_run.call_deferred()

func make_wall(length: float = 5.0) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 5
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 3.0, length)
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 1.5
	wall.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 3.0, length)
	collision.shape = shape
	collision.position.y = 1.5
	wall.add_child(collision)
	add_child(wall)
	return wall

func generated_count(wall: Node3D) -> int:
	var count := 0
	for child: Node in wall.get_children():
		if child.has_meta("_bunker_door_wall_segment"):
			count += 1
	return count

func _run() -> void:
	var wall := make_wall()
	var controller := TestBuild.new()
	add_child(controller)
	controller._placed_objects.append({"node": wall, "tile_id": controller.TILE_WALL,
		"price": 250, "world_pos": wall.global_position, "angle_deg": 0.0,
		"player_placed": true, "footprint": Vector2(0.15, 2.5)})
	var centered: Dictionary = controller._resolve_door_placement(Vector3.ZERO)
	check(bool(centered.get("valid", false)), "center of a long player wall should accept a door")
	var over_end: Dictionary = controller._resolve_door_placement(Vector3(0.0, 0.0, 2.45))
	check(not bool(over_end.get("valid", true)), "an opening extending past a wall end must be rejected")

	var crossing_wall := make_wall(2.0)
	crossing_wall.rotation_degrees.y = 90.0
	controller._placed_objects.append({"node": crossing_wall, "tile_id": controller.TILE_WALL,
		"price": 100, "world_pos": crossing_wall.global_position, "angle_deg": 90.0,
		"player_placed": true, "footprint": Vector2(0.15, 1.0)})
	var blocked: Dictionary = controller._resolve_door_placement(Vector3.ZERO)
	check(not bool(blocked.get("valid", true)), "a perpendicular wall crossing the opening must reject placement")
	controller._placed_objects.pop_back()
	crossing_wall.free()

	var door := BunkerDoor.new()
	add_child(door)
	## Deliberately pass the legacy generic placement height. install_on_wall()
	## must normalize it to the host wall's floor plane.
	door.install_on_wall(wall, Vector3(0.0, 2.0, 0.0), 0.0)
	controller._placed_objects.append({"node": door, "tile_id": controller.TILE_BUNKER_DOOR,
		"price": 500, "world_pos": door.global_position, "angle_deg": 0.0,
		"player_placed": true, "footprint": Vector2(0.20, 0.90)})
	var original_mesh := wall.get_child(0) as MeshInstance3D
	var original_collision := wall.get_child(1) as CollisionShape3D
	check(is_equal_approx(door.global_position.y, wall.global_position.y),
		"door should be grounded to the host wall even when placement supplies a raised Y")
	check(not original_mesh.visible, "host wall mesh should be replaced while a door is installed")
	check(original_collision.disabled, "host wall collision should be replaced while a door is installed")
	check(generated_count(wall) == 6, "one centered cut should create two side and one lintel mesh/collision pairs")
	check(BunkerDoor.WALL_CUT_WIDTH > BunkerDoor.OPENING_WIDTH + BunkerDoor.FRAME_WIDTH * 2.0,
		"wall cut should include clearance beyond both outer frame edges")
	check(BunkerDoor.WALL_CUT_HEIGHT > BunkerDoor.OPENING_HEIGHT + 0.16,
		"wall cut should include clearance above the frame header")
	check(door.get_interact_prompt() == "[E] Open Door", "closed door should advertise Open")
	var portal := door.get_node_or_null("NPCDoorPortal") as NavigationLink3D
	check(portal != null and portal.bidirectional,
		"door should expose a bidirectional NPC navigation portal while closed")
	check((controller.get_nav_obstacle_snapshot().get("obstacles", []) as Array).size() == 3,
		"closed door navigation should contain two wall sides plus the blocking door")
	var topology_events: Array[int] = [0]
	door.navigation_topology_changed.connect(func() -> void: topology_events[0] += 1)
	door.request_npc_open()
	check(door.get_interact_prompt() == "[E] Close Door", "open door should advertise Close immediately")
	check(not bool(door.get_npc_portal_info().get("open", true)),
		"door must remain navigation-closed while its collision panels animate")
	check((controller.get_nav_obstacle_snapshot().get("obstacles", []) as Array).size() == 3,
		"opening door fingerprint must stay blocked until panel collision clears")
	await get_tree().create_timer(BunkerDoor.ANIM_TIME + 0.1).timeout
	check(bool(door.get_npc_portal_info().get("open", false)),
		"door should become navigation-open after the panel animation")
	check((controller.get_nav_obstacle_snapshot().get("obstacles", []) as Array).size() == 2,
		"open door navigation should leave only the two wall sides")
	check(topology_events[0] >= 1,
		"door should publish a topology event from its final collision state")

	controller._placed_objects.pop_back()
	door.free()
	check(original_mesh.visible, "deleting a door should restore the original host wall mesh")
	check(not original_collision.disabled, "deleting a door should restore the original host wall collision")
	check(generated_count(wall) == 0, "deleting the last door should remove generated wall segments")
	print("Bunker door smoke: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
