extends Node3D

class TestBuild extends BuildModeController:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Build wall tier smoke: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var hud_script: GDScript = load("res://scripts/ui/build/BuildModeHUD.gd") as GDScript
	var hud: CanvasLayer = hud_script.new() as CanvasLayer
	get_tree().root.add_child(hud)
	await get_tree().process_frame

	## Catalog: Half/Quarter are Q / E tiers of Wall, not menu entries, but
	## their tile ids keep pricing for live placement, saves and refunds.
	for item: Dictionary in hud.CATEGORIES["Structure"]:
		check(int(item["tile_id"]) not in [25, 26],
			"Structure catalog no longer lists %s" % item["name"])
	for item: Dictionary in hud.CONSTRUCT_ITEMS:
		check(int(item["tile_id"]) not in [25, 26], "flat construct list omits wall tiers")
	check(hud.get_item_price(1) == 50, "full wall keeps its per-metre price")
	check(hud.get_item_price(25) == 30, "half wall keeps its per-metre price")
	check(hud.get_item_price(26) == 15, "quarter wall keeps its per-metre price")

	var player := Node3D.new()
	add_child(player)
	var build := TestBuild.new()
	player.add_child(build)
	build._wall_snap = WallSnapHelpers.new(build)
	build._undo_manager = BuildUndoStack.new(build)
	build._materials = BuildMaterials.new(build)
	build.build_hud = hud
	build._setup_wall_draw_mode()
	build._update_wall_draw_refs()
	var mode: Node = build._wall_draw_mode
	var indicator: Control = hud.get("_wall_tier_indicator") as Control
	check(indicator != null, "HUD builds the wall-height indicator")

	## Picking "Wall" always starts at full height and tells the HUD.
	hud.set_wall_height_tier(2)
	build._selected_tile = build.TILE_WALL
	mode.call("activate")
	hud.set_wall_draw_active(true)
	check(int(mode.call("current_tier_index")) == 0, "wall draw starts at full height")
	check(hud.get_wall_height_tier() == 0, "indicator highlights full on activation")
	var expected: Array = [
		[1, build.TILE_HALF_WALL, 30], [2, build.TILE_QUARTER_WALL, 15],
		[0, build.TILE_WALL, 50], [2, build.TILE_QUARTER_WALL, 15],
	]
	var deltas: Array[int] = [1, 1, 1, -1]
	for i: int in deltas.size():
		mode.call("cycle_tier", deltas[i])
		var want: Array = expected[i]
		check(int(mode.call("current_tier_index")) == want[0], "tier step %d index" % i)
		check(hud.get_wall_height_tier() == want[0], "tier step %d indicator" % i)
		check(build._selected_tile == want[1], "tier step %d selects the tier tile" % i)
		check(build._selected_tile_price == want[2], "tier step %d prices the tier" % i)

	## Q / E keys drive the same path (E = right = shorter, Q = left = taller).
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Q
	check(bool(mode.call("handle_input", key)), "Q is consumed by wall draw")
	check(hud.get_wall_height_tier() == 1, "Q steps the indicator left (taller)")
	key.keycode = KEY_E
	mode.call("handle_input", key)
	check(hud.get_wall_height_tier() == 2, "E steps the indicator right (shorter)")

	## Indicator geometry: three bottom-aligned bars, full > half > quarter.
	var full: Rect2 = indicator.call("bar_rect", 0)
	var half: Rect2 = indicator.call("bar_rect", 1)
	var quarter: Rect2 = indicator.call("bar_rect", 2)
	check(full.size.y > half.size.y and half.size.y > quarter.size.y,
		"bars descend in height left to right")
	check(is_equal_approx(full.end.y, half.end.y) and is_equal_approx(half.end.y, quarter.end.y),
		"bars share one baseline")
	check(indicator.size.x <= 24.0 and indicator.size.y <= 20.0, "indicator stays small")
	hud.show_hud()
	hud.set_wall_draw_active(true)
	await get_tree().process_frame
	check(indicator.visible == not bool(hud.call("pointer_over_ui",
		get_viewport().get_mouse_position())), "indicator follows wall draw beside the cursor")
	hud.set_wall_draw_active(false)
	check(not indicator.visible, "indicator hides when wall draw ends")

	## A saved half wall still rebuilds at half height through the same path.
	var restored: Node3D = build._spawn_wall_run(build.TILE_HALF_WALL, Vector3(0, 0.5, 0), 0.0, 2.0)
	var restored_mesh: MeshInstance3D = restored.get_child(0) as MeshInstance3D
	check(is_equal_approx((restored_mesh.mesh as BoxMesh).size.y, build.WALL_HEIGHT_M * 0.5),
		"saved half-wall tile restores at half height")
	restored.free()

	## Pillar connection dots: the pick is the drawn dot itself, in screen space.
	var pillar := StaticBody3D.new()
	add_child(pillar)
	build._placed_objects.append({"node": pillar, "tile_id": build.TILE_PILLAR,
		"world_pos": Vector3(5.0, 0.0, 0.0), "footprint": Vector2(0.25, 0.25),
		"angle_deg": 0.0, "player_placed": false})
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(5.0, 8.0, 7.0)
	cam.look_at(Vector3(5.0, 0.5, 0.0))
	cam.current = true
	build.camera = cam
	mode.call("_refresh_pillar_connection_dots")
	var socket := Vector3(5.25, 0.58, 0.0)
	var screen: Vector2 = cam.unproject_position(socket)
	var picked: Vector3 = mode.call("_connection_dot_near", screen + Vector2(3.0, -2.0))
	check(picked.is_finite() and picked.is_equal_approx(socket),
		"aiming at a blue dot picks exactly that dot")
	var far_pick: Vector3 = mode.call("_connection_dot_near", screen + Vector2(200.0, 0.0))
	check(not far_pick.is_finite(), "aiming well away from every dot picks none")
	if picked.is_finite():
		var dot_snap: Dictionary = build._snap_wall_run_point(Vector3(picked.x, 0.5, picked.z),
			WallSnapHelpers.WALL_RUN_JUNCTION_EPSILON * 2.0)
		check(not dot_snap.is_empty()
			and (dot_snap["pos"] as Vector3).is_equal_approx(Vector3(5.25, 0.5, 0.0))
			and dot_snap.get("target_kind", "") == "pillar",
			"a picked dot resolves to its exact pillar socket")
	## The physics hit under that dot lands on the pillar top, parallax-shifted
	## toward the camera; that point alone would not resolve to this socket.
	var origin: Vector3 = cam.project_ray_origin(screen)
	var direction: Vector3 = cam.project_ray_normal(screen)
	var top_hit: Vector3 = origin + direction * ((3.5 - origin.y) / direction.y)
	var top_snap: Dictionary = build._snap_wall_run_point(top_hit)
	check(top_snap.is_empty() or not (top_snap["pos"] as Vector3).is_equal_approx(
		Vector3(5.25, top_hit.y, 0.0)),
		"(sanity) the raw physics hit under the dot is offset from the socket")
	mode.call("deactivate")
	build._placed_objects.pop_back()
	pillar.free()

	hud.free()
	print("Build wall tier smoke: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
