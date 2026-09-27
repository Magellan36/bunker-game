extends SceneTree
## tools/ui_capture/capture_world.gd — in-world UI review captures.
##
##   godot --path . --windowed --script res://tools/ui_capture/capture_world.gd -- <out_prefix>
##
## SAFETY: run with isolated user data so captures can never touch real
## saves or settings (see README): XDG_DATA_HOME/XDG_CONFIG_HOME to a temp dir.
##
## Starts MainWorld, waits for startup_ready, then captures: HUD, pause,
## status, admin, build mode + catalog. Then spawns one of each device next to
## the player via BuildModeController._spawn_placed_object() and opens it
## (generator, terminal, breaker, battery, shelf, dispenser, tray, stove),
## spawns an NPC and opens its profile. Env SKIP_BASICS=1 captures devices
## only; TOAST_SCENARIOS=1 captures toast placement over the plain HUD, next
## to a docked inspector, and in build mode. Extend as new UIs appear.

var _world: Node
var _out: String
var _i: int = 0


func _initialize() -> void:
	_run()


func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := "%s_%02d_%s.png" % [_out, _i, tag]
	img.save_png(path)
	print("captured ", path)
	_i += 1


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _first_in_group_with(method: String, names: Array) -> Node:
	for n in _all(_world):
		for nm in names:
			if String(n.name).containsn(nm) and n.has_method(method):
				return n
	return null


func _all(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out


func _run() -> void:
	_out = OS.get_cmdline_user_args()[0]
	## Hard stop so a stuck scenario never outlives its captures.
	create_timer(float(OS.get_environment("CAPTURE_TIMEOUT")) if OS.get_environment("CAPTURE_TIMEOUT") != "" else 200.0) \
		.timeout.connect(func() -> void: quit())
	_world = (load("res://scenes/world/MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	current_scene = _world
	if _world.has_signal("startup_ready"):
		await _world.startup_ready
	await _wait(3.0)
	if OS.get_environment("SKIP_BASICS") == "":
		await _shot("hud")

	if OS.get_environment("SLEEP_SCENARIO") != "":
		var stats: Node = _world.get("player_stats")
		stats.set("sleep", 35.0)
		var overlay: Node = _world.get("sleep_overlay")
		overlay.call("begin_sleep")
		await _wait(1.6)
		await _shot("sleeping")
		overlay.call("request_wake")
		await _wait(0.6)
		await _shot("woke")
		quit()
		return
	if OS.get_environment("DEATH_SCENARIO") != "":
		await _death_scenario()
		return
	if OS.get_environment("PAUSE_SCENARIO") != "":
		await _pause_scenario()
		return
	if OS.get_environment("BUILD_SCENARIO") != "":
		await _build_scenario()
		return
	if OS.get_environment("WORKSPACES") != "":
		await _workspaces()
		return
	if OS.get_environment("TOAST_SCENARIOS") != "":
		await _toast_scenarios()
		return
	if OS.get_environment("SKIP_BASICS") != "":
		await _devices()
		return
	_world.call("_toggle_pause_menu")
	await _wait(0.8)
	await _shot("pause")
	_world.call("_toggle_pause_menu")
	await _wait(0.5)

	_world.call("_toggle_status_screen")
	await _wait(1.0)
	await _shot("status")
	_world.call("_toggle_status_screen")
	await _wait(0.5)

	_world.call("_toggle_admin_cheat_menu")
	await _wait(0.8)
	await _shot("admin")
	_world.call("_toggle_admin_cheat_menu")
	await _wait(0.5)

	await _devices()


func _devices() -> void:
	var bc: Node = _world.get("_build_controller")
	var player: Node3D = _world.get("player")
	var base: Vector3 = player.global_position
	var devices := [[6, "generator"], [10, "terminal"], [12, "breaker"], [13, "battery"],
		[34, "shelf"], [19, "dispenser"], [21, "tray"]]
	var i := 0
	for d in devices:
		## Ring within the 3 m walk-away radius (UIProximityClose).
		var angle := TAU * float(i) / float(devices.size())
		var node: Node3D = bc.call("_spawn_placed_object", d[0], base + Vector3(cos(angle), 0.0, sin(angle)) * 1.7, 0.0)
		i += 1
		await _wait(0.4)
		if node == null or not node.has_method("on_interact"):
			print("missing ", d[1])
			continue
		if node.has_method("fill_soil_at_cell"):   ## a tray only opens once it has soil
			for cell: int in range(4):
				node.call("fill_soil_at_cell", cell)
		if node.has_method("on_e_interact"):   ## shelves: E opens, F places
			node.call("on_e_interact")
		else:
			node.call("on_interact")
		await _wait(1.0)
		for n in _all(root):
			if n is CanvasLayer and (n as CanvasLayer).visible and n.has_method("close"):
				print("  open: ", n.name)
		await _shot(d[1])
		## Inspectors/workspaces parent to the root, not the world.
		for n in _all(root):
			if n is CanvasLayer and n.has_method("close") and (n as CanvasLayer).visible and n.name != "HUD":
				print("  closing ", n.name)
				n.call("close")
		await _wait(0.6)
	_world.call("_dev_spawn_npc")
	await _wait(2.5)
	for n in _all(_world):
		var sc: Script = n.get_script()
		if sc != null and str(sc.resource_path).get_file() == "NPC.gd":
			n.call("on_interact")
			await _wait(1.0)
			await _shot("npc_talk")
			break
	quit()


## Build mode (Pass 5): toolbar, catalog (first and wall categories), shop.
func _build_scenario() -> void:
	_world.call("_toggle_build_mode")
	await _wait(1.2)
	await _shot("build")
	var hud: Node = null
	for n in _all(root):
		if n.has_method("open_shop_menu") and n.has_method("open_construct_menu"):
			hud = n
	if hud == null:
		quit()
		return
	hud.call("open_construct_menu")
	await _wait(1.5)
	await _shot("build_catalog")
	var workspace: Node = hud.get("_workspace")
	var catalog: Node = workspace.get("catalog") if workspace != null else null
	if catalog != null:
		for category: String in ["Walls", "Structure", "Building"]:
			if catalog.has_method("_category_changed"):
				catalog.call("_category_changed", category)
				await _wait(1.5)
				await _shot("build_catalog_" + category.to_lower())
				break
	hud.call("close_workspace_menu")
	await _wait(0.4)
	hud.call("open_shop_menu")
	await _wait(1.5)
	await _shot("build_shop")
	quit()


## Every tab of every workspace (Pass 4). Closes each before the next.
func _workspaces() -> void:
	var status: Node = _world.get("status_screen") if "status_screen" in _world else null
	_world.call("_toggle_status_screen")
	await _wait(1.0)
	for n in _all(root):
		if is_instance_valid(n) and n is CanvasLayer and (n as CanvasLayer).visible and n.has_method("_set_tab") \
				and str((n.get_script() as Script).resource_path).get_file() == "StatusScreenUI.gd":
			status = n
	for tab: int in range(4):
		if status != null:
			status.call("_set_tab", tab)
		await _wait(0.6)
		await _shot("status_%d" % tab)
	_world.call("_toggle_status_screen")
	await _wait(0.5)
	var bc: Node = _world.get("_build_controller")
	var player: Node3D = _world.get("player")
	var terminal: Node3D = bc.call("_spawn_placed_object", 10, player.global_position + Vector3(1.4, 0.0, 0.6), 0.0)
	await _wait(0.4)
	terminal.call("on_interact")
	await _wait(1.0)
	var term_ui: Node = root.get_node_or_null("PowerTerminalUI")
	for tab: int in range(4):
		term_ui.call("_set_tab", tab)
		await _wait(0.6)
		await _shot("terminal_%d" % tab)
	term_ui.call("close")
	await _wait(0.5)
	var station: Node = get_first_node_in_group("research_station")
	if station != null:
		station.call("on_interact")
		await _wait(1.0)
		for n in _all(root):
			if is_instance_valid(n) and n is CanvasLayer and (n as CanvasLayer).visible and n.has_method("_set_tab") \
					and str((n.get_script() as Script).resource_path).get_file() == "ResearchStationModernUI.gd":
				for tab: int in range(3):
					n.call("_set_tab", tab)
					await _wait(0.6)
					await _shot("research_%d" % tab)
				n.call("close")
		await _wait(0.5)
	_world.call("_dev_spawn_npc")
	await _wait(2.5)
	for n in _all(_world):
		var sc: Script = n.get_script()
		if sc != null and str(sc.resource_path).get_file() == "NPC.gd":
			n.call("on_interact")
			await _wait(1.0)
			for m in _all(root):
				if is_instance_valid(m) and m is CanvasLayer and (m as CanvasLayer).visible and m.has_method("_set_tab") \
						and str((m.get_script() as Script).resource_path).get_file() == "NPCTalkMenuUI.gd":
					for tab: int in range(5):
						m.call("_set_tab", tab)
						await _wait(0.6)
						await _shot("npc_%d" % tab)
			break
	quit()


func _notify_batch(tag: String) -> void:
	var nm: Node = root.get_node("NotificationManager")
	nm.call("notify", 1, 0, "Generator S started (%s)" % tag)
	nm.call("notify", 1, 1, "Generator S fuel reserve low", -1.0, true, "18% remaining")
	nm.call("notify", 3, 1, "Inventory full", -1.0, true, "Store something to pick this up")


func _toast_scenarios() -> void:
	_notify_batch("hud")
	await _wait(1.2)
	await _shot("toasts_hud")
	var bc: Node = _world.get("_build_controller")
	var player: Node3D = _world.get("player")
	var battery: Node3D = bc.call("_spawn_placed_object", 13, player.global_position + Vector3(1.2, 0.0, 1.2), 0.0)
	await _wait(0.5)
	battery.call("on_interact")
	await _wait(0.6)
	_notify_batch("docked")
	await _wait(1.2)
	await _shot("toasts_docked")
	for n in _all(_world):
		if n is CanvasLayer and n.has_method("is_open") and bool(n.call("is_open")):
			n.call("close")
	await _wait(0.8)
	_world.call("_toggle_build_mode")
	await _wait(1.5)
	_notify_batch("build")
	await _wait(1.2)
	await _shot("toasts_build")
	quit()


func _pause_scenario() -> void:
	_notify_batch("log")
	var nm: Node = root.get_node("NotificationManager")
	nm.call("notify", 1, 2, "Power grid tripped", -1.0, true, "Reduce load, then restart generators")
	await _wait(0.5)
	_world.call("_toggle_pause_menu")
	await _wait(1.0)
	await _shot("pause_log")
	var pause: Node = _world.get("_pause_menu")
	pause.call("_on_save_pressed")
	await _wait(0.8)
	await _shot("pause_save")
	# Never write a real save from a capture: show the confirmation only.
	(pause.get("_footer") as Node).call("flash_saved", "✓  Saved to slot 3")
	await _wait(0.3)
	await _shot("pause_saved")
	quit()


## Death → game over → Load last save → fresh world via LoadingScreen.
## Writes a save: only ever run with isolated XDG user data.
func _death_scenario() -> void:
	var saves: Node = root.get_node("SaveManager")
	saves.call("save_game", 1)
	var old_world_id := _world.get_instance_id()
	_world.get("player_stats").call("replenish_health", -500.0)
	await _wait(5.0)
	await _shot("game_over")
	var game_over: Node = root.get_node_or_null("GameOverUI")
	if game_over == null:
		print("DEATH_SCENARIO_FAIL: no game over")
		quit(1)
		return
	game_over.call("_on_load_pressed")
	await _wait(1.2)
	await _shot("leaving")
	var waited := 0.0
	while waited < 60.0:
		await _wait(0.5)
		waited += 0.5
		var scene := current_scene
		if scene != null and scene.get_instance_id() != old_world_id and scene.has_signal("startup_ready") \
				and scene.get("player") != null:
			break
	await _wait(3.0)
	await _shot("reloaded")
	var world := current_scene
	var player: Node = world.get("player") if world != null else null
	var alive := player != null and not bool(player.get("dead"))
	print("DEATH_SCENARIO ", "RELOAD_OK" if alive else "RELOAD_FAIL",
		" scene=", world.name if world != null else "none",
		" game_over_left=", root.get_node_or_null("GameOverUI") != null)
	quit()
