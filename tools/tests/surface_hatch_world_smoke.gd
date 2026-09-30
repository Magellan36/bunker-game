extends SceneTree
## In-world smoke for the Surface Hatch: spawn, send a resident topside,
## force the return, and check the resident, injury, loot, report and save.
## Run with:
## godot --headless --path . --script res://tools/tests/surface_hatch_world_smoke.gd

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)

func _run() -> void:
	change_scene_to_file("res://scenes/world/MainWorld.tscn")
	var hatch: Node = null
	for i: int in 3000:
		await process_frame
		hatch = get_first_node_in_group("surface_hatch")
		if hatch != null:
			break
	_check(hatch != null, "hatch spawns with the world")
	if hatch == null:
		quit(1)
		return
	for i: int in 30:
		await physics_frame
	var world: Node = get_first_node_in_group("main_world")
	var rs: Node = get_first_node_in_group("rock_surround")
	var hp: Vector3 = (hatch as Node3D).global_position
	print("hatch at ", hp, " yaw ", (hatch as Node3D).rotation.y)
	_check(hp.x > -12.5 and hp.x < 3.5 and hp.z > 4.5 and hp.z < 12.5, "hatch sits inside the starting bunker")

	## A resident to send.
	var npc: Node3D = (load("res://scenes/npc/NPC.tscn") as PackedScene).instantiate()
	world.add_child(npc)
	npc.global_position = (hatch as Node3D).call("get_front_position") + Vector3(0.0, 0.6, 0.0)
	for i: int in 10:
		await process_frame
	npc.set("health", 100.0)
	npc.set("energy", 100.0)
	var npc_id: String = String(npc.get("npc_id"))
	var names: Array = []
	for c: Dictionary in hatch.call("get_candidates"):
		names.append(String(c["npc"].get("npc_id")))
	_check(names.has(npc_id), "resident is offered as a candidate")

	## UI builds and opens (player stands at the ladder: walk-away close).
	var player: Node3D = get_first_node_in_group("player") as Node3D
	var fwd: Vector3 = (hatch as Node3D).global_transform.basis.z.normalized()
	player.global_position = (hatch as Node3D).global_position + fwd * 1.4 + Vector3(0.0, 1.0, 0.0)
	for i: int in 5:
		await physics_frame
	hatch.call("on_interact")
	for i: int in 5:
		await process_frame
	var ui: Node = hatch.get("_ui")
	_check(ui != null and bool(ui.call("is_open")), "hatch inspector opens (player %.2fm from hatch)" %
		player.global_position.distance_to((hatch as Node3D).global_position))
	if ui != null:
		var send: Button = ui.find_child("Send", true, false) as Button
		_check(send != null and not send.disabled, "send is available with a fit resident")
		ui.call("close")

	var ok: bool = bool(hatch.call("launch", npc, "gas_station", "balanced"))
	_check(ok, "launch succeeds")
	await process_frame
	await process_frame
	_check(not is_instance_valid(npc), "resident leaves the bunker")
	var active: Array = hatch.get("active")
	_check(active.size() == 1, "one expedition active")
	_check(not bool(hatch.call("launch", null, "pharmacy", "balanced")), "undiscovered/invalid launch refused")

	## Save round-trip while they're away (JSON, like SaveManager).
	var saved: Variant = JSON.parse_string(JSON.stringify(hatch.call("get_save_data")))
	hatch.call("restore_save_data", saved)
	active = hatch.get("active")
	_check(active.size() == 1 and String(active[0]["npc_id"]) == npc_id, "expedition survives save/load")

	## Force a known outcome and an immediate return.
	var rec: Dictionary = active[0]
	rec["outcome"]["fate"] = "returned"
	rec["outcome"]["hazards"] = [{"id": "glass", "text": "cut their left arm on broken glass", "injury": "open_wound", "part": "LEFT_ARM"}]
	rec["outcome"]["loot"] = ["food_can", "water_bottle", "seed", "scrap_metal", "fuel_can"]
	rec["outcome"]["reveals"] = ["hardware_store"]
	rec["return_h"] = NPCClock.now() - 0.1
	rec["due_h"] = NPCClock.now() - 0.1
	var pickups_before: int = get_nodes_in_group("pickup").size()
	for i: int in 150:
		await process_frame
	var back: Node = null
	for n: Node in get_nodes_in_group("npc"):
		if String(n.get("npc_id")) == npc_id:
			back = n
	_check(back != null, "resident comes back through the hatch")
	if back != null:
		var wounds: int = 0
		for c: Variant in back.get("medical").get("active_conditions"):
			if String(c.id) == "open_wound":
				wounds += 1
		_check(wounds == 1, "the injury from the report is real (open wound)")
		_check((back as Node3D).global_position.distance_to((hatch as Node3D).call("get_front_position")) < 2.5,
			"resident appears at the foot of the ladder")
	_check(get_nodes_in_group("pickup").size() - pickups_before >= 5, "the haul lands as real items")
	_check((hatch.get("active") as Array).is_empty(), "expedition cleared")
	_check((hatch.get("reports") as Array).size() == 1, "a report is filed")
	_check((hatch.get("discovered") as Array).has("hardware_store"), "reveal adds a destination")

	if _failures == 0:
		print("PASS: surface_hatch_world_smoke")
	quit(1 if _failures > 0 else 0)
