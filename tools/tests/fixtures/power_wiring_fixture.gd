extends Node
## Real graph, placement, wall-feed, undo and persistence regression smoke.
class TestWorld extends MainWorld:
	var test_cash: int = 10000
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func spend_cash(amount: int) -> bool:
		if test_cash < amount: return false
		test_cash -= amount
		return true
	func add_cash(amount: int) -> void: test_cash += amount

class TestCamera extends GameCamera:
	func _ready() -> void: pass
class TestStats extends PlayerStats:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestMedical extends PlayerMedical:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class TestTool extends "res://scripts/world/power/WireDrawMode.gd":
	var cursor := Vector3.ZERO
	var picked: Dictionary = {}
	func _get_cursor_world_pos() -> Vector3: return cursor
	func _get_nearest_wire_node(_pos: Vector3, _excluded: String) -> Dictionary: return picked
	func _show_warning(_message: String) -> void: pass

class TestBuild extends BuildModeController:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _recolor_wire_zones() -> void: pass
	func _spawn_float_label_at_pos(_pos: Vector3, _amount: int, _positive: bool) -> void: pass

class TestBreaker extends BreakerBox:
	func _ready() -> void: pass

var failures: int = 0
var world: TestWorld
var pm: PowerManager

func _ready() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func node_at(pos: Vector3, role: String = "joint") -> String:
	return pm.register_wire_node(pos, role, "", true)
func clear_graph() -> void:
	pm.begin_bulk()
	for edge: Dictionary in pm.get_wire_edges(): pm.unregister_wire_edge(edge["id"])
	for data: Dictionary in pm.get_wire_nodes(): pm.unregister_wire_node(data["key"])
	pm.end_bulk()

func _run() -> void:
	world = TestWorld.new()
	var player := CharacterBody3D.new()
	player.name = "Player"
	var interaction := Node.new()
	interaction.name = "InteractionSystem"
	player.add_child(interaction)
	world.add_child(player)
	var dependencies := {"GameCamera": TestCamera.new(), "WorldEnvironment": WorldEnvironment.new(),
		"DirectionalLight3D": DirectionalLight3D.new(), "HUD": CanvasLayer.new(),
		"PlayerStats": TestStats.new(), "PlayerMedical": TestMedical.new(),
		"SleepOverlay": CanvasLayer.new(), "InteractPrompt": Node.new()}
	for key: String in dependencies:
		var child: Node = dependencies[key]
		child.name = key
		world.add_child(child)
	get_tree().root.add_child(world)
	world.add_to_group("main_world")
	pm = PowerManager.new()
	pm.add_to_group("power_manager")
	world.add_child(pm)
	pm.set_process(false)
	var high := Vector3(0, 2.625, 0)
	var low := Vector3(2, 1, 0)
	var route := WireRoute.points(high, low)
	check(route == PackedVector3Array([high, Vector3(2, 2.625, 0), low]), "high horizontal then drop")
	var reverse := WireRoute.points(low, high)
	reverse.reverse()
	check(reverse == route, "route independent of click direction")
	check(is_equal_approx(WireRoute.length(route), 3.625), "length includes vertical drop")
	var high_key := node_at(high, "consumer")
	var low_key := node_at(low)
	var floor_key := node_at(Vector3(0, 1, 0))
	var floor_edge := pm.register_wire_edge(floor_key, low_key)
	pm.register_wire_edge(high_key, node_at(Vector3(2, 2.625, 0)))
	check(pm.has_wire_edge(floor_edge), "higher edge leaves lower same-XZ run separate")
	check(pm.get_wire_node_pos(high_key).y == high.y, "exact mounting height")
	node_at(high)
	check(pm.get_wire_node_role(high_key) == "consumer", "joint preserves device identity")
	clear_graph()

	var tool := TestTool.new()
	world.add_child(tool)
	tool.world_node = world
	tool.cursor = low
	tool._try_pick_source()
	tool.cancel_placement()
	world.test_cash = 0
	tool._try_pick_source()
	tool.cursor = Vector3(5, 1, 0)
	tool._try_pick_dest()
	check(pm.get_wire_nodes().is_empty() and world.test_cash == 0, "insufficient cash leaves graph untouched")
	tool.cancel_placement()
	world.test_cash = 10000
	check(pm.get_wire_nodes().is_empty(), "cancel leaves no orphan draft nodes")
	high_key = node_at(high, "consumer")
	low_key = node_at(low)
	var build := TestBuild.new()
	world.add_child(build)
	build.world_node = world
	var undo := BuildUndoStack.new(build)
	tool.wire_placed.connect(undo._push_undo_wire)
	tool.wire_placed.connect(world._on_player_wire_placed)
	tool.wire_nodes_connected.connect(world._on_wire_nodes_connected)
	tool.picked = {"key": high_key, "pos": high}
	tool.cursor = high
	tool._try_pick_source()
	tool.picked = {"key": low_key, "pos": low}
	tool.cursor = low
	tool._try_pick_dest()
	check(world.test_cash == 9971, "one charge for full route")
	check(pm.get_wire_edges().size() == 2, "two connected physical legs")
	check(build._undo_stack.size() == 1, "one undo action")
	check(world.get_player_wires_for_save().size() == 2, "both legs saved")
	var wall := Node3D.new()
	world.add_child(wall)
	wall.position = Vector3(1, 3.5, 0)
	var wall_key := node_at(wall.position, "consumer")
	var feed := WallWireAttachment.new()
	wall.add_child(feed)
	feed.bind(wall, pm, wall_key)
	await get_tree().process_frame
	await get_tree().process_frame
	check(pm.has_wire_edge(feed._edge_id), "wall taps existing run")
	check(pm._wire_edges.get(feed._edge_id, {}).get("no_visual", false), "wall feed is invisible")
	check(world.get_player_wires_for_save().size() == 3, "split pieces preserve ownership")
	undo._undo()
	await get_tree().process_frame
	await get_tree().process_frame
	check(world.test_cash == 10000, "undo refunds once")
	check(world.get_player_wires_for_save().is_empty(), "undo removes split run from save")
	check(pm.get_wire_edges().is_empty(), "undo removes run and dangling wall feed")
	check(world._player_wire_segs.is_empty(), "undo clears stale expansion tracking")
	wall.free()
	clear_graph()

	wall = Node3D.new()
	world.add_child(wall)
	wall.position = Vector3(1, 2.5, 0)
	wall_key = node_at(wall.position, "consumer")
	feed = WallWireAttachment.new()
	wall.add_child(feed)
	feed.bind(wall, pm, wall_key)
	await get_tree().process_frame
	check(feed._edge_id.is_empty(), "no wire means no phantom feed")
	pm.register_wire_edge(node_at(Vector3(0, 1, 0)), node_at(Vector3(2, 1, 0)))
	await get_tree().process_frame
	await get_tree().process_frame
	check(pm.has_wire_edge(feed._edge_id), "wire placed after wall connects")
	wall.free()
	clear_graph()

	# Breakers share the wall-feed search, but replace the invisible feed with
	# a real cut point on the physical run below them.
	var breaker := TestBreaker.new()
	world.add_child(breaker)
	breaker.position = Vector3(1, 2.5, 0)
	breaker._register_with_pm()
	await get_tree().process_frame
	check(breaker.get_breaker_id().is_empty(), "breaker waits for a physical wire")
	pm.register_wire_edge(node_at(Vector3(0, 1, 0)), node_at(Vector3(2, 1, 0)))
	await get_tree().process_frame
	await get_tree().process_frame
	check(not breaker.get_breaker_id().is_empty(), "wire placed beneath attaches breaker")
	check(pm.get_wire_node_pos(breaker._wire_key) == Vector3(1, 1, 0), "breaker electrical cut stays on wire height")
	var breaker_sides: int = 0
	for edge: Dictionary in pm.get_wire_edges():
		if not bool(edge.get("no_visual", false)) and (edge.get("node_a", "") == breaker._wire_key or edge.get("node_b", "") == breaker._wire_key):
			breaker_sides += 1
	check(breaker_sides == 2, "breaker splits physical run into two sides")
	check(pm.get_wire_zones().size() == 2, "breaker creates separate grid zones")
	breaker.free()
	await get_tree().process_frame
	clear_graph()
	tool.picked = {}
	tool.cursor = Vector3(0, 1, 0)
	tool._try_pick_source()
	tool.cursor = Vector3(4, 1, 0)
	tool._try_pick_dest()
	var paid: int = world.test_cash
	tool.cursor = Vector3(0, 1, 0)
	tool._try_pick_source()
	tool.cursor = Vector3(5, 1, 0)
	tool._try_pick_dest()
	check(world.test_cash == paid, "overlapping extension rejected without charge")
	tool.cancel_placement()
	for raw: Node in get_tree().get_nodes_in_group("wire_segment"):
		var seg := raw as WireSegment
		if seg != null and seg.player_placed and not seg.is_queued_for_deletion():
			build._try_deconstruct_wire(seg)
	undo._undo()
	check(world.test_cash == 10000, "deconstruct then undo never double refunds")
	check(build._closest_dist_ray_to_segment(Vector3(0.1, 5, 0), Vector3.DOWN, 10, Vector3(0, 1, 0), Vector3(4, 1, 0)) < 0.001, "ray selects near endpoint of long run")
	check(build._closest_dist_ray_to_segment(Vector3(4, 2, 5), Vector3.FORWARD, 10, Vector3(4, 1, 0), Vector3(4, 3, 0)) < 0.001, "ray selects vertical drop")
	clear_graph()
	var saved := [{"pos_a": save_vec(high), "pos_b": save_vec(Vector3(2, 2.625, 0))},
		{"pos_a": save_vec(Vector3(2, 2.625, 0)), "pos_b": save_vec(low)}]
	world.restore_player_wires(saved)
	check(world.get_player_wires_for_save().size() == 2, "save round trip")
	check(pm.get_wire_node_pos(pm._graph._snap_key(high)).y == high.y, "load preserves height")
	world.restore_player_wires(saved)
	check(world.get_player_wires_for_save().size() == 2, "repeat restore is idempotent")
	clear_graph()
	var ghost := WireSegment.make_ghost_wire(world, high, low) as WireSegment
	var tube := ghost._tubes[0]
	ghost.set_endpoints(high, Vector3(3, 1, 0))
	check(ghost._tubes[0] == tube and ghost._tubes.size() == 2, "drag reuses geometry")
	check(ghost._caps.size() == 3, "endpoints and elbow have restrained caps")
	check(not ghost.is_in_group("wire_segment"), "ghost not saved")
	UIMotion._loaded = true
	UIMotion._reduced = true
	ghost.set_preview_color(WireSegment.COLOR_DELETE)
	ghost._process(0.016)
	check(ghost._material.albedo_color == WireSegment.COLOR_DELETE, "reduced motion immediate")
	ghost.free()
	tool.free()
	build.free()
	world.free()
	print("POWER_WIRING_SMOKE_%s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)

func save_vec(pos: Vector3) -> Dictionary:
	return {"x": pos.x, "y": pos.y, "z": pos.z}
