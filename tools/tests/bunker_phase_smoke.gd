extends SceneTree
## tools/tests/bunker_phase_smoke.gd — pre-/post-apocalypse run structure.
##   godot --headless --path . --script res://tools/tests/bunker_phase_smoke.gd
## Drives the real path: a New Game world starts in preparation (clock held,
## PREPARATION eyebrow, survivors waiting outside, hatch offers Leave) →
## SealTransition seals it (survivors in, Day 1, clock running, hatch locked
## for 10 days with a toast) → sealed build rules (Build/Duplicate/Shop
## locked, Move default, Metal costs, salvage + chute) → save/load keeps the
## act; a save without the field loads as LEGACY.

var failures: int = 0
## Loaded at runtime: in --script runs, class names whose scripts touch
## autoloads don't compile at parse time.
var E: GDScript
var SEAL: GDScript


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		failures += 1
		push_error("FAIL: " + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	E = load("res://scripts/world/build/BuildEconomy.gd")
	SEAL = load("res://scripts/ui/hatch/SealTransition.gd")
	# ── Pure rules ──
	_check(E.wire_metal(0.4) == 1 and E.wire_metal(3.0) == 1
		and E.wire_metal(3.1) == 2 and E.wire_metal(9.0) == 3,
		"wire: one Metal per 3 m, +1 per further 3 m")
	_check(E.pipe_metal(1.5) == 1 and E.pipe_metal(1.6) == 2,
		"pipe: one Metal per 1.5 m (shorter than wire)")
	var w3: Array[float] = [1.0, 2.0, 0.5]
	var shares: Array = E.split(5, w3)
	_check(shares[0] + shares[1] + shares[2] == 5, "split shares add back to what was paid %s" % [shares])
	_check(E.salvage_for_tile(8, 12000).get("metal", 0) == 6, "large generator salvages 6 Metal")

	# ── New Game world ──
	var wm: Node = root.get_node("WorldManager")
	wm.set("pending_new_game", true)
	change_scene_to_file("res://scenes/world/MainWorld.tscn")
	var world: Node = null
	for i: int in 3000:
		await process_frame
		world = get_first_node_in_group("main_world")
		if world != null and bool(world.get("startup_complete")):
			break
	wm.set("pending_new_game", false)
	_check(world != null and bool(world.get("startup_complete")), "world starts")
	if world == null:
		quit(1)
		return
	var phase: Node = get_first_node_in_group("bunker_phase")
	var stats: Node = world.get("player_stats")
	var hud: Node = world.get("hud")
	var hatch: Node3D = get_first_node_in_group("surface_hatch") as Node3D
	var station: Node = get_first_node_in_group("research_station")
	_check(phase != null and phase.is_preparing(), "a New Game starts before the apocalypse")
	var t0: float = stats.get_elapsed()
	for i: int in 60:
		await process_frame
	_check(is_equal_approx(stats.get_elapsed(), t0), "the clock holds during preparation")
	_check(String((hud.get("day_label") as Label).text) == "PREPARATION"
		and not (hud.get("clock_label") as Label).visible, "HUD reads PREPARATION, no time")
	_check(phase.hatch_days_remaining() == 0 and not phase.hatch_open(), "hatch isn't for travel while preparing")

	# Survivors wait outside.
	var draft: GDScript = load("res://scripts/ui/new_game/SurvivorDraft.gd")
	var rolled: Array = draft.call("roll", 2)
	phase.queue_survivors(rolled)
	_check(get_nodes_in_group("npc").is_empty() and phase.pending_names().size() == 2,
		"picked survivors are absent until the seal")

	# Preparation still builds with cash.
	world.call("_toggle_build_mode")
	await process_frame
	var bhud: Node = world.get("_build_hud")
	_check(int(bhud.get("active_tool")) == 0 and bhud.call("tool_available", 7),
		"preparation: build mode opens on Build, shop open")
	world.call("_toggle_build_mode")
	await process_frame

	# Hatch shows Leave.
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = hatch.global_position + hatch.global_transform.basis.z * 1.4 + Vector3(0, 1, 0)
	await physics_frame
	hatch.call("on_interact")
	await process_frame
	var leave_ui: Node = hatch.get("_leave_ui")
	_check(leave_ui != null and bool(leave_ui.call("is_open")), "hatch opens the Leave panel")
	if leave_ui != null:
		var people := leave_ui.get("_people") as Control
		var shown: String = (people.get_node("Line/Value") as Label).text
		_check(shown.contains(String(rolled[0]["name"])) and shown.contains(" and "),
			"Leave panel names who is coming (%s)" % shown)
		_check((leave_ui.get("_leave_btn") as Button).text == "Leave", "big Leave button")
		leave_ui.call("close")

	# Nothing wears out or gets used before Day 1.
	var hookup: Node = get_first_node_in_group("water_hookup")
	var q0: float = float(hookup.get("water_quality"))
	for i: int in 30:
		await process_frame
	_check(is_equal_approx(float(hookup.get("water_quality")), q0), "water quality holds during preparation")
	var controller: Node = world.get("_build_controller")
	var tray: Node = controller.call("_spawn_placed_object", 21,
		player.global_position + Vector3(2.5, 0.0, 0.0), 0.0)
	_check(tray != null and not bool(tray.call("fill_soil_at_cell", 0)), "no soil before Day 1")
	_check(String(load("res://scripts/world/core/BunkerPhase.gd").call("gate_prompt", self, "[E] Fill Tray with Soil"))
		.ends_with("from Day 1"), "locked use prompts say they open on Day 1")
	var BP: GDScript = load("res://scripts/world/core/BunkerPhase.gd")
	var far: Vector3 = player.global_position + Vector3(0.0, 40.0, 0.0)   ## nowhere near a dispenser
	var can: Node3D = (load("res://scenes/world/FoodCan.tscn") as PackedScene).instantiate()
	var bottle: Node3D = (load("res://scenes/world/WaterBottle.tscn") as PackedScene).instantiate()
	var fuel: Node3D = (load("res://scenes/world/FuelCan.tscn") as PackedScene).instantiate()
	for it: Node3D in [can, bottle, fuel]:
		world.add_child(it)
		it.global_position = far
		it.freeze = true
	await process_frame
	_check(not BP.use_allowed(self, can) and not BP.use_allowed(self, bottle) and not BP.use_allowed(self, fuel),
		"eating, drinking and refuelling wait for Day 1")
	var dispenser: Node3D = controller.call("_spawn_placed_object", 19,
		player.global_position + Vector3(-2.0, 0.0, 0.0), 0.0)
	bottle.global_position = dispenser.global_position + Vector3(0.5, 0.6, 0.0)
	await process_frame
	_check(BP.use_allowed(self, bottle), "refilling a bottle at a dispenser is allowed")

	# Save during preparation.
	var save_ok: bool = root.get_node("SaveManager").call("save_game", 1)
	_check(save_ok, "save during preparation")
	var slot_text: String = load("res://scripts/ui/common/SaveSlotFormat.gd").call("describe",
		root.get_node("SaveManager").call("get_slot_info", 1))
	_check(slot_text.begins_with("Preparation") and not slot_text.contains("Day"),
		"preparation save reads \"Preparation\" (%s)" % slot_text)

	# ── Seal ──
	var transition: CanvasLayer = SEAL.play(self, phase)
	## ~6 s of motion; wait on wall time, not frames (headless frame rate varies).
	for i: int in 150:
		await create_timer(0.1, true).timeout
		if not is_instance_valid(transition):
			break
	_check(not is_instance_valid(transition) and not paused, "seal transition plays out and unpauses")
	_check(phase.is_sealed(), "bunker is sealed")
	_check(int(world.call("get_cash")) == 0, "leftover cash is gone")
	bottle.global_position = far
	await process_frame
	_check(BP.use_allowed(self, can) and BP.use_allowed(self, bottle) and BP.use_allowed(self, fuel),
		"supplies can be used once sealed")
	_check(tray != null and bool(tray.call("fill_soil_at_cell", 0)), "soil can go in once sealed")
	var npcs: Array = get_nodes_in_group("npc")
	_check(npcs.size() == 2, "both survivors came in (%d)" % npcs.size())
	_check(phase.pending_survivors.is_empty(), "nobody left waiting")
	var t1: float = stats.get_elapsed()
	for i: int in 30:
		await process_frame
	_check(stats.get_elapsed() > t1 and stats.current_day == 1, "Day 1, clock running")
	_check(String((hud.get("day_label") as Label).text) == "DAY 1" and (hud.get("clock_label") as Label).visible,
		"HUD back to DAY 1 with the time")
	_check(phase.hatch_days_remaining() == 10 and not phase.hatch_open(), "hatch locked for 10 days")
	hatch.call("on_interact")
	await process_frame
	var toast_found: bool = false
	for e: Dictionary in root.get_node("NotificationManager").get("_queue"):
		if String(e.get("text", "")) == "10 days until it is safe to travel":
			toast_found = true
	_check(toast_found, "early hatch use shows the days-until-safe toast")
	var inspect_ui: Node = hatch.get("_ui")
	_check(inspect_ui == null or not bool(inspect_ui.call("is_open")), "expedition panel stays shut while locked")
	stats.set_elapsed(stats.get_elapsed() + 9.5 * stats.day_duration_seconds)
	_check(phase.hatch_days_remaining() == 1 and phase.hatch_wait_text() == "1 day until it is safe to travel",
		"singular wording on the last day")
	stats.set_elapsed(stats.get_elapsed() + 0.6 * stats.day_duration_seconds)
	_check(phase.hatch_open(), "hatch opens after 10 days")

	# ── Sealed build mode ──
	world.call("_toggle_build_mode")
	await process_frame
	_check(int(bhud.get("active_tool")) == 3, "sealed: build mode opens on Move")
	var ws: Node = bhud.get("_workspace")
	var tool_buttons: Array = ws.get("_tool_buttons")
	var shop_btn: Button = ws.get("shop_button")
	_check((tool_buttons[0] as Button).disabled and (tool_buttons[2] as Button).disabled
		and not (tool_buttons[1] as Button).disabled and not (tool_buttons[5] as Button).disabled,
		"Build and Duplicate greyed; Move/Wire live")
	_check(shop_btn.disabled and shop_btn.tooltip_text == "Shop is permanently closed", "shop closed with hover text")
	bhud.call("_on_toolbar_click", 0)
	bhud.call("open_shop_menu")
	await process_frame
	_check(int(bhud.get("active_tool")) == 3 and not bool(ws.call("menu_open")), "locked tabs can't be opened")
	_check(String((hud.get("cash_label") as Label).text).ends_with("Metal"), "build HUD shows Metal instead of cash")
	world.call("_toggle_build_mode")
	await process_frame
	_check(is_zero_approx((hud.get("cash_label") as Label).modulate.a), "cash hidden after the seal")

	# ── Metal reserve ──
	station.set("stored_materials", {"metal": 5, "plastic": 0, "paper": 0, "organic": 0})
	_check(E.metal_available(self) == 5 and E.spend_metal(self, 2)
		and E.metal_available(self) == 3, "Metal spent from the Research Station")
	_check(not E.spend_metal(self, 4) and E.metal_available(self) == 3,
		"can't overspend Metal")

	# ── Salvage and the chute ──
	var drop_at: Vector3 = player.global_position + Vector3(1.0, 0.0, 0.0)
	var spheres: Array = E.drop_salvage(self, drop_at, {"metal": 3, "plastic": 1})
	_check(spheres.size() == 2, "salvage drops one sphere per material")
	var metal_sphere: Node = null
	for sph: Node in spheres:
		if String(sph.get("salvage_material")) == "metal":
			metal_sphere = sph
	station.set("stored_materials", {"metal": 9, "plastic": 0, "paper": 0, "organic": 0})
	var isys: Node = player.get_node("InteractionSystem")
	isys.set("held_item", metal_sphere)
	station.call("on_chute_f_interact")
	_check(int(metal_sphere.get("salvage_units")) == 2 and int(station.get("stored_materials")["metal"]) == 10,
		"chute takes what fits and the rest stays in the sphere")
	station.set("stored_materials", {"metal": 0, "plastic": 0, "paper": 0, "organic": 0})
	station.call("on_chute_f_interact")
	await process_frame
	_check(not is_instance_valid(metal_sphere) and int(station.get("stored_materials")["metal"]) == 2,
		"a sphere that fits is consumed")

	# ── Save/load keeps the act ──
	root.get_node("SaveManager").call("save_game", 2)
	root.get_node("SaveManager").call("load_game", 1)
	await process_frame
	_check(phase.is_preparing() and phase.pending_names().size() == 2 and not stats.clock_running,
		"loading the preparation save restores the act, the waiting survivors and the held clock")
	root.get_node("SaveManager").call("load_game", 2)
	await process_frame
	_check(phase.is_sealed() and stats.clock_running, "loading the sealed save restores the seal")
	var path: String = ProjectSettings.globalize_path("user://saves/save_slot_2.json")
	var f := FileAccess.open("user://saves/save_slot_2.json", FileAccess.READ)
	if f == null:
		f = FileAccess.open(String(root.get_node("SaveManager").get("SAVE_PATH_FORMAT")) % 2, FileAccess.READ)
	if f != null:
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		data.erase("bunker_phase")
		var w := FileAccess.open(String(root.get_node("SaveManager").get("SAVE_PATH_FORMAT")) % 3, FileAccess.WRITE)
		w.store_string(JSON.stringify(data))
		w.close()
		root.get_node("SaveManager").call("load_game", 3)
		await process_frame
		_check(int(phase.get("phase")) == 0 and stats.clock_running and phase.hatch_open(),
			"a save from before this feature loads under the old rules")
	else:
		_check(false, "could not read back the save file (%s)" % path)

	if failures == 0:
		print("BUNKER_PHASE_SMOKE_OK")
	quit(1 if failures > 0 else 0)
