extends Node3D

class TestBuild extends BuildModeController:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := Node3D.new()
	add_child(player)
	var build := TestBuild.new()
	player.add_child(build)
	var helper := WallSnapHelpers.new(build)
	build._wall_snap = helper
	build._undo_manager = BuildUndoStack.new(build)
	build._setup_wall_draw_mode()
	var wall := StaticBody3D.new()
	wall.collision_layer = 5
	wall.set_meta("tile_id", build.TILE_WALL)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 3.0, 4.0)
	collision.shape = box
	collision.position.y = 2.0
	wall.add_child(collision)
	add_child(wall)
	build._wall_draw_mode.emit_signal("wall_placed", wall, build.TILE_WALL, 20, Vector3.ZERO, 37.5)
	check(build._undo_stack.size() == 1, "wall signal records undo with float yaw")
	if not build._undo_stack.is_empty():
		check(build._undo_stack[0]["node"] == wall and build._undo_stack[0]["zone_color_snap"] == {},
			"wall undo retains body and dictionary snapshot")
	build._placed_objects.append({"node": wall, "tile_id": build.TILE_WALL,
		"world_pos": Vector3.ZERO, "footprint": Vector2(0.15, 2.0), "angle_deg": 0.0,
		"player_placed": true})
	check(build._entry_supports_tool(build._placed_objects[-1], 1),
		"player-drawn walls are eligible for deconstruction")
	var nested_collider := StaticBody3D.new()
	wall.add_child(nested_collider)
	check(build._registered_placed_root_for(nested_collider) == wall,
		"child collision bodies resolve to their registered deconstruct root")
	var pregen_light_node := Node3D.new()
	var pregen_light_entry := {"node": pregen_light_node, "tile_id": build.TILE_LIGHT,
		"price": 0, "player_placed": false}
	check(build._entry_supports_tool(pregen_light_entry, 1),
		"pregenerated wall lights are eligible for deconstruction")
	check(build._entry_supports_tool(pregen_light_entry, 3),
		"pregenerated wall lights are eligible for movement")
	check(not build._entry_supports_tool(pregen_light_entry, 2),
		"pregenerated wall lights are not duplicable")
	pregen_light_node.free()
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	var original_material := StandardMaterial3D.new()
	visual.set_surface_override_material(0, original_material)
	wall.add_child(visual)
	var delete_material := StandardMaterial3D.new()
	delete_material.albedo_color = Color.RED
	build._set_hover_highlight(wall, delete_material)
	check(visual.get_surface_override_material(0) == delete_material,
		"deconstruct hover applies the red override to descendant meshes")
	build._clear_hover_glow()
	check(visual.get_surface_override_material(0) == original_material,
		"leaving deconstruct hover restores the exact original material")
	var drag_math: GDScript = load("res://scripts/world/build/DragPlacementMath.gd")
	check(drag_math.snap_xz_to_octant(Vector3.ZERO, Vector3(0.2, 0.0, -2.0), 0.25)
		.is_equal_approx(Vector3(0.0, 0.0, -2.0)), "Ctrl constrains to 180 degrees")
	check(drag_math.snap_xz_to_octant(Vector3.ZERO, Vector3(-2.0, 0.0, 0.2), 0.25)
		.is_equal_approx(Vector3(-2.0, 0.0, 0.0)), "Ctrl constrains to 270 degrees")
	check(drag_math.snap_xz_to_octant(Vector3.ZERO, Vector3(1.8, 0.0, 2.1), 0.25)
		.is_equal_approx(Vector3(2.0, 0.0, 2.0)), "Ctrl constrains to a grid-aligned 45 degrees")
	var wall_intersection: Vector3 = drag_math.snap_xz_octant_to_segment(
		Vector3.ZERO, Vector3(3.0, 0.0, 2.0),
		Vector3(2.0, 0.0, -4.0), Vector3(2.0, 0.0, 4.0))
	check(wall_intersection.is_equal_approx(Vector3(2.0, 0.0, 2.0)),
		"Ctrl moves a wall snap along its run to the exact 45-degree intersection")
	check(drag_math.is_xz_octant_aligned(Vector3.ZERO, wall_intersection),
		"snapped structural intersection remains octant aligned")
	check(not drag_math.is_xz_octant_aligned(Vector3.ZERO, Vector3(2.0, 0.0, 1.0)),
		"off-angle wire nodes cannot override Ctrl")
	var pipe_mode := WaterPipeDrawMode.new()
	add_child(pipe_mode)
	var direct_pipe_path: Array = pipe_mode._build_direct_pipe_path(
		Vector3(0.0, pipe_mode.WATER_CEILING_Y, 0.0),
		Vector3(2.0, pipe_mode.WATER_CEILING_Y, 2.0))
	check(direct_pipe_path.size() == 2
		and (direct_pipe_path[1] as Vector3).is_equal_approx(
			Vector3(2.0, pipe_mode.WATER_CEILING_Y, 2.0)),
		"Ctrl pipe routing is one direct diagonal instead of a Manhattan path")
	var diagonal_pipe := WaterPipeSegment.new()
	diagonal_pipe.point_a = Vector3(-1.0, pipe_mode.WATER_CEILING_Y, 1.0)
	diagonal_pipe.point_b = Vector3(1.0, pipe_mode.WATER_CEILING_Y, -1.0)
	var diagonal_cross: Vector3 = pipe_mode._find_perpendicular_crossing(
		Vector3(-1.0, pipe_mode.WATER_CEILING_Y, -1.0),
		Vector3(1.0, pipe_mode.WATER_CEILING_Y, 1.0), diagonal_pipe)
	check(diagonal_cross.is_equal_approx(Vector3(0.0, pipe_mode.WATER_CEILING_Y, 0.0)),
		"diagonal Ctrl pipes retain real crossing-junction geometry")
	var split_pipe: WaterPipeSegment = _make_test_pipe(
		Vector3.ZERO, Vector3(2.0, 0.0, 2.0))
	var diagonal_split: Vector3 = pipe_mode._grid_snap_split_point(
		Vector3(0.8, pipe_mode.WATER_CEILING_Y, 0.8),
		split_pipe)
	check(diagonal_split.is_equal_approx(Vector3(0.75, pipe_mode.WATER_CEILING_Y, 0.75)),
		"diagonal Ctrl pipes retain on-line grid-snapped split points")
	diagonal_pipe.free()
	split_pipe.free()
	pipe_mode.free()
	for angle: float in [0.0, 17.0, 45.0, 89.0, 123.4, 180.0, 271.0, 359.0]:
		wall.rotation.y = deg_to_rad(angle)
		build._placed_objects[0]["angle_deg"] = angle
		var run_axis := Vector3(sin(deg_to_rad(angle)), 0.0, cos(deg_to_rad(angle)))
		var side_axis := Vector3(cos(deg_to_rad(angle)), 0.0, -sin(deg_to_rad(angle)))
		var wall_cursor: Vector3 = run_axis * 0.7 + side_axis * 0.5
		var run_snap: Dictionary = helper._snap_wall_run_point(wall_cursor)
		check(not run_snap.is_empty(), "drawn wall snap missing at angle %s" % angle)
		if not run_snap.is_empty():
			var expected_run_pos: Vector3 = run_axis * 0.7
			expected_run_pos.y = wall_cursor.y
			check((run_snap["pos"] as Vector3).distance_to(expected_run_pos) < 0.001,
				"drawn wall centre-line snap at angle %s" % angle)
			check((run_snap.get("walls", []) as Array).has(wall),
				"drawn wall support identity at angle %s" % angle)
			check(build._is_position_occupied(expected_run_pos, build.TILE_WALL, null,
				Vector2(0.15, 0.5), angle), "support should collide without junction exemption")
			check(not build._is_position_occupied(expected_run_pos, build.TILE_WALL, null,
				Vector2(0.15, 0.5), angle, [wall]), "junction exemption should ignore exact support")
		await get_tree().physics_frame
		await get_tree().physics_frame
		for side: float in [-1.0, 1.0]:
			var normal: Vector3 = wall.global_basis.x * side
			for kind: int in range(4):
				var base: Vector3 = normal * 1.45
				base.y = 1.0 if kind == 0 else 2.0
				var offset: float = [0.05, 0.07, 0.04, 0.015][kind]
				var result: Dictionary
				match kind:
					0: result = helper._snap_light_to_wall(base)
					1: result = helper._snap_breaker_to_wall(base)
					2: result = helper._snap_to_nearest_wall(base, 0.45, offset, 1.5)
					3: result = helper._snap_to_nearest_wall(base, 0.0, offset, 1.5)
				var label := "angle %s side %s fixture %s" % [angle, side, kind]
				check(not result.is_empty(), "missing snap " + label)
				if result.is_empty():
					continue
				var expected: Vector3 = normal * (0.15 + offset)
				expected.y = base.y
				check(result["pos"].distance_to(expected) < 0.001, "flush position " + label)
				var front := Vector3.BACK if kind == 1 else Vector3.FORWARD
				front = front.rotated(Vector3.UP, deg_to_rad(result["angle_deg"]))
				check(front.dot(normal) > 0.9999, "front orientation " + label)
				var tile: int = [build.TILE_LIGHT, build.TILE_BREAKER, build.TILE_TERMINAL, build.TILE_POSTER][kind]
				check(not build._is_position_occupied_for_tile(result["pos"], tile, null,
					Vector2(-1, -1), result["angle_deg"]), "mounting wall blocks " + label)
				if kind != 0:
					var obstacle := Node3D.new()
					add_child(obstacle)
					build._placed_objects.append({"node": obstacle, "tile_id": tile,
						"world_pos": result["pos"], "angle_deg": result["angle_deg"]})
					check(build._is_position_occupied_for_tile(result["pos"], tile, null,
						Vector2(-1, -1), result["angle_deg"]), "duplicate must block " + label)
					build._placed_objects.pop_back()
					obstacle.free()
			var cap_pos: Vector3 = wall.global_basis.z * side * 2.5
			cap_pos.y = 2.0
			check(helper._snap_to_nearest_wall(cap_pos, 0.0, 0.015, 1.5).is_empty(),
				"end cap must reject at %s" % angle)
		var above: Vector3 = wall.global_basis.x
		above.y = 4.0
		check(helper._snap_to_nearest_wall(above, 0.0, 0.015, 1.5).is_empty(),
			"no attachment above wall")

	## WallDrawMode must accept real junctions while rejecting the one dangerous
	## use of its support exemption: laying a new run along the middle of the
	## same wall.
	wall.rotation.y = 0.0
	build._placed_objects[0]["angle_deg"] = 0.0
	var mode: Node = build._wall_draw_mode
	mode.call("activate")
	var branch_snap: Dictionary = helper._snap_wall_run_point(Vector3(0.5, 0.5, 0.0))
	mode.set("_start_snap", branch_snap)
	mode.set("_start_pos", branch_snap["pos"])
	mode.set("_end_snap", {"pos": Vector3(1.0, 0.5, 0.0), "wall": null, "walls": [], "at_cap": false})
	mode.set("_end_pos", Vector3(1.0, 0.5, 0.0))
	mode.set("_run_angle_deg", 90.0)
	mode.set("_run_length", 1.0)
	check(bool(mode.call("_junctions_are_valid")), "perpendicular wall branch should be valid")
	check(not bool(mode.call("_wall_run_is_occupied")), "support should not block a valid branch")

	var cap_snap: Dictionary = helper._snap_wall_run_point(Vector3(0.0, 0.5, 2.4))
	mode.set("_start_snap", cap_snap)
	mode.set("_start_pos", cap_snap["pos"])
	mode.set("_end_snap", {"pos": Vector3(0.0, 0.5, 3.0), "wall": null, "walls": [], "at_cap": false})
	mode.set("_end_pos", Vector3(0.0, 0.5, 3.0))
	mode.set("_run_angle_deg", 0.0)
	mode.set("_run_length", 1.0)
	check(bool(mode.call("_junctions_are_valid")), "wall continuation from an end cap should be valid")
	check(not bool(mode.call("_wall_run_is_occupied")), "end-cap support should not block continuation")

	var middle_snap: Dictionary = helper._snap_wall_run_point(Vector3(0.5, 0.5, 0.0))
	mode.set("_start_snap", middle_snap)
	mode.set("_start_pos", middle_snap["pos"])
	mode.set("_end_snap", {"pos": Vector3(0.0, 0.5, 3.0), "wall": null, "walls": [], "at_cap": false})
	mode.set("_end_pos", Vector3(0.0, 0.5, 3.0))
	mode.set("_run_angle_deg", 0.0)
	mode.set("_run_length", 3.0)
	check(not bool(mode.call("_junctions_are_valid")), "parallel overlay from a broad face must be rejected")
	mode.call("deactivate")

	## Generated perimeter walls are one-metre segments. A junction directly on
	## their shared seam must recognize both supports so neither segment causes
	## a false collision.
	var pregen_neighbor := StaticBody3D.new()
	pregen_neighbor.set_meta("tile_id", build.TILE_WALL)
	add_child(pregen_neighbor)
	build._placed_objects.append({
		"node": pregen_neighbor,
		"tile_id": build.TILE_WALL,
		"world_pos": Vector3(0.0, 0.0, 4.0),
		"footprint": Vector2(0.15, 2.0),
		"angle_deg": 0.0,
		"player_placed": false,
	})
	var seam_snap: Dictionary = helper._snap_wall_run_point(Vector3(0.5, 0.5, 2.0))
	check(not seam_snap.is_empty(), "generated wall seam should snap")
	if not seam_snap.is_empty():
		var seam_supports: Array = seam_snap.get("walls", [])
		check(seam_supports.has(wall) and seam_supports.has(pregen_neighbor),
			"generated wall seam should exempt both adjacent supports")
	build._placed_objects.pop_back()
	pregen_neighbor.free()

	var pillar := StaticBody3D.new()
	pillar.set_meta("tile_id", build.TILE_PILLAR)
	add_child(pillar)
	build._placed_objects.append({
		"node": pillar,
		"tile_id": build.TILE_PILLAR,
		"world_pos": Vector3(5.0, 0.0, 0.0),
		"footprint": Vector2(0.25, 0.25),
		"angle_deg": 0.0,
		"player_placed": false,
	})
	var pillar_snap: Dictionary = helper._snap_wall_run_point(Vector3(5.5, 0.5, 0.0))
	check(not pillar_snap.is_empty(), "pillar side should snap")
	if not pillar_snap.is_empty():
		check((pillar_snap["pos"] as Vector3).is_equal_approx(Vector3(5.25, 0.5, 0.0)),
			"pillar snap lands at side centre")
		check(pillar_snap.get("target_kind", "") == "pillar",
			"pillar snap identifies its target kind")
		check((pillar_snap.get("walls", []) as Array).has(pillar),
			"pillar is the exact junction support")
	check(helper._pillar_wall_snap_points(0.58).size() == 4,
		"pillar exposes four blue-dot connection points")
	mode.call("_refresh_pillar_connection_dots")
	check((mode.get("_pillar_connection_dots") as Array).size() == 4,
		"wall mode renders all four pillar connection dots")
	mode.call("_clear_pillar_connection_dots")
	var player_connected_wall := StaticBody3D.new()
	player_connected_wall.set_meta("tile_id", build.TILE_WALL)
	add_child(player_connected_wall)
	build._placed_objects.append({
		"node": player_connected_wall,
		"tile_id": build.TILE_WALL,
		"world_pos": Vector3(5.75, 0.0, 0.0),
		"footprint": Vector2(0.15, 0.5),
		"angle_deg": 90.0,
		"player_placed": true,
	})
	var pregen_connected_wall := StaticBody3D.new()
	pregen_connected_wall.set_meta("tile_id", build.TILE_WALL)
	add_child(pregen_connected_wall)
	build._placed_objects.append({
		"node": pregen_connected_wall,
		"tile_id": build.TILE_WALL,
		"world_pos": Vector3(4.25, 0.0, 0.0),
		"footprint": Vector2(0.15, 0.5),
		"angle_deg": 90.0,
		"player_placed": false,
	})
	check(helper._pillar_wall_snap_points(0.58).size() == 2,
		"player and pregenerated wall connections each hide their pillar dot")
	mode.call("_refresh_pillar_connection_dots")
	check((mode.get("_pillar_connection_dots") as Array).size() == 2,
		"wall mode renders only unoccupied pillar sockets")
	mode.call("_clear_pillar_connection_dots")
	build._placed_objects.pop_back()
	build._placed_objects.pop_back()
	pregen_connected_wall.free()
	player_connected_wall.free()
	if not pillar_snap.is_empty():
		var pillar_preview: Vector3 = mode.call("_idle_preview_position", pillar_snap)
		check(pillar_preview.distance_to(pillar_snap["pos"]) > 0.15,
			"idle pillar preview is pulled visibly clear of the pillar")
	build._placed_objects.pop_back()
	pillar.free()
	var wall_preview: Vector3 = mode.call("_idle_preview_position", branch_snap)
	check(wall_preview.distance_to(branch_snap["pos"]) > 0.27,
		"idle wall preview is pulled visibly clear of the wall")
	mode.set("_run_angle_deg", 137.0)
	mode.call("_cancel_drag")
	check(is_zero_approx(float(mode.get("_run_angle_deg"))),
		"wall idle preview resets to its neutral angle")

	check(build._entry_supports_tool(build._placed_objects[0], 1),
		"player wall should remain deletable/refundable")
	check(not build._entry_supports_tool(build._placed_objects[0], 2),
		"player wall should not be copyable")
	check(not build._entry_supports_tool(build._placed_objects[0], 3),
		"player wall should not be movable")
	print("Wall snap smoke: %s failures" % failures)
	get_tree().quit(1 if failures else 0)

func _make_test_pipe(a: Vector3, b: Vector3) -> WaterPipeSegment:
	var pipe := WaterPipeSegment.new()
	pipe.point_a = a
	pipe.point_b = b
	return pipe
