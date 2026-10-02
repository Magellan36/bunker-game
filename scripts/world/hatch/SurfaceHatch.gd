extends StaticBody3D
class_name SurfaceHatch
## SurfaceHatch.gd
## Singleton fixture spawned at world start (MainWorld._spawn_surface_hatch()).
## A wall ladder up to a sealed ceiling hatch: residents are sent topside on
## timed scavenging runs from here. Owns expedition state the same way
## ResearchStation owns research state. Opens HatchInspectUI on E.
##
## Hand-off model: a departing resident is serialized with the SAME
## NPC.get_save_dict() the save system uses and freed; on return the dict is
## re-instanced with NPC.tscn + apply_save_dict() (exactly MainWorld's
## _restore_npcs() path) at the foot of the ladder. While away, nothing in
## the bunker can reference them: no jobs, reservations or nav state leak.
##
## Outcomes are rolled once at departure by ExpeditionResolver and saved, so
## a reload can't re-roll a bad trip. See docs/systems/hatch/README.md.

const T := preload("res://scripts/world/hatch/ExpeditionTables.gd")
const R := preload("res://scripts/world/hatch/ExpeditionResolver.gd")
const UI_PATH: String = "res://scripts/ui/hatch/HatchInspectUI.gd"
## Before the apocalypse the hatch offers only Leave (Oct 2026, BunkerPhase).
const LEAVE_UI_PATH: String = "res://scripts/ui/hatch/HatchLeaveUI.gd"
const NPC_SCENE_PATH: String = "res://scenes/npc/NPC.tscn"
const TICK_INTERVAL: float = 1.0

## Model footprint (local space: back against the wall at -Z, room at +Z).
const HALF_WIDTH: float = 0.45
const HALF_DEPTH: float = 0.25
const LADDER_HEIGHT: float = 2.75
const FRONT_OFFSET: float = 0.85

signal expeditions_changed

## Expedition records (JSON-safe). See launch() for the shape.
var active: Array = []
## Newest-first report history: {stamp, title, lines: Array[String], tone}.
var reports: Array = []
## Destinations visited at least once / currently known to the player.
var visited: Array = []
var discovered: Array = []
## dest id -> {value: 0..DEPLETION_MAX, stamp: game hours of last update}
var depletion: Dictionary = {}

var _ui: CanvasLayer = null
var _leave_ui: CanvasLayer = null
var _tick: float = 0.0
var _lamp_mat: StandardMaterial3D = null

func _ready() -> void:
	collision_layer = 5
	collision_mask = 0
	add_to_group("interactable")
	add_to_group("surface_hatch")
	_build_model()
	if discovered.is_empty():
		for id: String in T.DESTINATION_ORDER:
			if String(T.DESTINATIONS[id].get("requires", "")) == "":
				discovered.append(id)
	_update_lamp()

# ─── Interaction ──────────────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	if active.is_empty():
		return "[E] Surface Hatch"
	return "[E] Surface Hatch (%d topside)" % active.size()

## By act (BunkerPhase): preparing → the Leave panel; sealed and still
## inside the first HATCH_LOCK_DAYS → a toast saying how long until it's safe;
## otherwise (sealed and open, or LEGACY worlds) → expedition planning.
func on_interact() -> void:
	var phase: BunkerPhase = BunkerPhase.of(get_tree())
	if phase != null and phase.is_preparing():
		_open_leave_ui()
		return
	if phase != null and not phase.hatch_open():
		NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			phase.hatch_wait_text())
		return
	if _ui == null or not is_instance_valid(_ui):
		_ui = SharedUI.acquire(UI_PATH, self, &"_ui", {"closed": _on_ui_closed})
		if _ui == null:
			return
	if _ui.has_method("open"):
		_ui.open(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _open_leave_ui() -> void:
	if _leave_ui == null or not is_instance_valid(_leave_ui):
		_leave_ui = SharedUI.acquire(LEAVE_UI_PATH, self, &"_leave_ui", {"closed": _on_ui_closed})
		if _leave_ui == null:
			return
	_leave_ui.call("open", self)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## SharedUI clears _ui itself when the panel closes (same as WaterDispenser).
func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_tree() -> void:
	SharedUI.release(_ui, self)
	SharedUI.release(_leave_ui, self)

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.5, 0.0)

## Where returning residents and their haul appear: the foot of the ladder.
func get_front_position() -> Vector3:
	return to_global(Vector3(0.0, 0.0, FRONT_OFFSET))

# ─── Queries (used by HatchInspectUI) ─────────────────────────────────────────
## Residents who could be sent: [{npc, name, reason}] — reason "" = eligible.
func get_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or npc.is_queued_for_deletion():
			continue
		if npc.has_method("is_dead") and bool(npc.call("is_dead")):
			continue
		var reason: String = R.ineligible_reason(R.resident_snapshot(npc))
		if reason == "" and npc.has_method("is_passed_out") and bool(npc.call("is_passed_out")):
			reason = "passed out"
		out.append({"npc": npc, "name": String(npc.get("npc_name")), "reason": reason})
	return out

func get_available_destinations() -> Array[String]:
	var out: Array[String] = []
	for id: String in T.DESTINATION_ORDER:
		if discovered.has(id):
			out.append(id)
	return out

## Current depletion (0..DEPLETION_MAX), including recovery since last visit.
func get_depletion(dest_id: String) -> float:
	var entry: Dictionary = depletion.get(dest_id, {})
	if entry.is_empty():
		return 0.0
	var days: float = maxf(0.0, NPCClock.now() - float(entry.get("stamp", 0.0))) / 24.0
	return clampf(float(entry.get("value", 0.0)) - days * T.DEPLETION_RECOVERY_PER_DAY, 0.0, T.DEPLETION_MAX)

## What the UI shows before sending — computed from the same rules resolve() uses.
func forecast(npc: Node, dest_id: String, approach_id: String) -> Dictionary:
	var snap: Dictionary = R.resident_snapshot(npc) if is_instance_valid(npc) else {}
	var chance: float = R.trip_injury_chance(dest_id, approach_id, snap)
	var dep: float = get_depletion(dest_id)
	return {
		"hours": R.planned_hours(dest_id, approach_id),
		"injury_chance": chance,
		"loss_chance": R.trip_loss_chance(dest_id, approach_id, snap),
		"risk": R.risk_word(chance),
		"haul": R.haul_word(dest_id, approach_id, dep),
		"depletion": dep,
		"loyalty": float(snap.get("loyalty", 0.0)),
	}

## "" if a new expedition can leave now, else the reason it can't.
func launch_block_reason() -> String:
	if active.size() >= T.MAX_ACTIVE_EXPEDITIONS:
		return "Only %d people can be topside at once." % T.MAX_ACTIVE_EXPEDITIONS
	return ""

# ─── Launch ───────────────────────────────────────────────────────────────────
## Record shape:
## { id, npc_id, npc_name, npc_data (NPC.get_save_dict()), dest, approach,
##   depart_h, due_h, return_h, outcome (ExpeditionResolver.resolve()),
##   overdue_noted }
func launch(npc: Node, dest_id: String, approach_id: String) -> bool:
	if not is_instance_valid(npc) or not npc.has_method("get_save_dict"):
		return false
	if launch_block_reason() != "" or not discovered.has(dest_id) or not T.APPROACHES.has(approach_id):
		return false
	var snap: Dictionary = R.resident_snapshot(npc)
	if R.ineligible_reason(snap) != "":
		return false
	var now: float = NPCClock.now()
	var planned: float = R.planned_hours(dest_id, approach_id)
	var outcome: Dictionary = R.resolve(randi(), dest_id, approach_id, snap, get_depletion(dest_id), visited)
	var name: String = String(npc.get("npc_name"))
	var record: Dictionary = {
		"id": "exp_%d_%d" % [Time.get_ticks_msec(), randi() % 10000],
		"npc_id": String(npc.get("npc_id")),
		"npc_name": name,
		"npc_data": npc.get_save_dict(),
		"dest": dest_id,
		"approach": approach_id,
		"depart_h": now,
		"due_h": now + planned,
		"return_h": now + planned + float(outcome.get("extra_hours", 0.0)),
		"outcome": outcome,
		"overdue_noted": false,
	}
	## The site is stripped the moment someone starts searching it; a second
	## run launched before the first returns already sees less.
	depletion[dest_id] = {
		"value": minf(T.DEPLETION_MAX, get_depletion(dest_id) + T.DEPLETION_PER_VISIT),
		"stamp": now,
	}
	if not visited.has(dest_id):
		visited.append(dest_id)
	_remove_resident(npc)
	active.append(record)
	var dest_name: String = String(T.DESTINATIONS[dest_id]["name"])
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
		"%s climbed topside" % name, -1.0, true,
		"Heading for the %s. Expected back in about %d hours." % [dest_name, int(round(planned))])
	_after_change()
	return true

## Same clean-removal sequence MainWorld._restore_npcs() uses before freeing
## residents: stop the activity (releases reservations), set down anything
## held, leave the group so no system counts them, then free.
func _remove_resident(npc: Node) -> void:
	if "brain" in npc and npc.brain != null:
		npc.brain.stop_current()
	if "held_item" in npc and npc.held_item != null:
		NPCItemUser.drop_held(npc)
	npc.remove_from_group("npc")
	npc.queue_free()

# ─── Returns ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick += delta
	if _tick < TICK_INTERVAL:
		return
	_tick = 0.0
	if active.is_empty():
		return
	var now: float = NPCClock.now()
	for record: Dictionary in active.duplicate():
		var fate: String = String(record["outcome"].get("fate", "returned"))
		if fate == "returned" and now >= float(record["return_h"]):
			_complete_return(record)
			continue
		if fate != "returned" and now >= float(record["due_h"]) + T.WRITE_OFF_AFTER_HOURS:
			_write_off(record)
			continue
		if now >= float(record["due_h"]) and not bool(record.get("overdue_noted", false)):
			record["overdue_noted"] = true
			NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
				"%s is overdue" % record["npc_name"], -1.0, true,
				"Expected back from the %s by now." % T.DESTINATIONS[record["dest"]]["name"])
			expeditions_changed.emit()

func _complete_return(record: Dictionary) -> void:
	active.erase(record)
	var outcome: Dictionary = record["outcome"]
	var world: Node = get_tree().get_first_node_in_group("main_world")
	var scene: PackedScene = load(NPC_SCENE_PATH) as PackedScene
	if world == null or scene == null:
		push_warning("SurfaceHatch: cannot respawn returning resident — main_world/NPC scene missing")
		return

	var data: Dictionary = (record["npc_data"] as Dictionary).duplicate(true)
	var front: Vector3 = get_front_position()
	data["pos"] = {"x": front.x, "y": front.y + 0.6, "z": front.z}
	var needs: Dictionary = outcome.get("needs", {})
	for k: String in ["hunger", "thirst", "energy"]:
		data[k] = clampf(float(data.get(k, 100.0)) + float(needs.get(k, 0.0)), T.NEED_FLOOR_ON_RETURN, 100.0)
	data["health"] = clampf(float(data.get("health", 100.0)) + float(needs.get("health", 0.0)), 1.0, 100.0)

	var npc: Node3D = scene.instantiate()
	npc.apply_save_dict(data)   ## before add_child — same as _restore_npcs()
	world.add_child(npc)
	_apply_trip_effects.call_deferred(npc, record)

	for r: Variant in outcome.get("reveals", []):
		if not discovered.has(String(r)):
			discovered.append(String(r))
	_spawn_loot(outcome.get("loot", []), int(float(record.get("depart_h", 0.0)) * 1000.0))

	var lines: Array[String] = R.report_lines(String(record["npc_name"]), String(record["dest"]), outcome)
	var hurt: bool = not (outcome.get("hazards", []) as Array).is_empty()
	_add_report("%s is back from the %s" % [record["npc_name"], T.DESTINATIONS[record["dest"]]["name"]],
		lines, "warning" if hurt else "info")
	NotificationManager.notify(UIKit.Domain.NEUTRAL,
		NotificationManager.Severity.WARNING if hurt else NotificationManager.Severity.INFO,
		"%s is back from topside" % record["npc_name"], -1.0, true, " ".join(lines))
	_after_change()

## Injuries, mood and the relationship consequence, applied once the
## re-instanced resident's components exist (NPC._ready() has run).
func _apply_trip_effects(npc: Node, record: Dictionary) -> void:
	if not is_instance_valid(npc):
		return
	var outcome: Dictionary = record["outcome"]
	var hazards: Array = outcome.get("hazards", [])
	var med: Variant = npc.get("medical")
	if med != null:
		for h: Dictionary in hazards:
			var part: int = int(MedicalCondition.BodyPart.get(String(h.get("part", "TORSO")), MedicalCondition.BodyPart.TORSO))
			match String(h.get("injury", "none")):
				"open_wound": med.spawn_open_wound(part)
				"fractured": med.spawn_fractured(part)
				"burn": med.spawn_burn(part, "surface")
	var dest_name: String = String(T.DESTINATIONS[record["dest"]]["name"])
	if npc.has_method("log_event"):
		npc.log_event("expedition", "Went topside to the %s" % dest_name)
		for h: Dictionary in hazards:
			npc.log_event("expedition", "Topside: %s" % h["text"])
	var thoughts: Variant = npc.get("thoughts")
	if thoughts != null:
		thoughts.add("rough_trip_topside" if not hazards.is_empty() else "went_topside")
	var bonds: Variant = npc.get("bonds")
	if bonds != null:
		## Blame lands only where the player's choice plausibly caused it:
		## being sent in greedy and coming back hurt.
		if not hazards.is_empty() and String(record["approach"]) == "greedy":
			bonds.relate("player", -6.0, "pushed me too hard out there")
		elif hazards.is_empty():
			bonds.relate("player", 2.0, "trusted me with a supply run")

func _write_off(record: Dictionary) -> void:
	active.erase(record)
	var lines: Array[String] = R.report_lines(String(record["npc_name"]), String(record["dest"]), record["outcome"])
	var title: String = "%s didn't come back" % record["npc_name"]
	_add_report(title, lines, "critical")
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.CRITICAL,
		title, -1.0, true, " ".join(lines))
	_after_change()

func _spawn_loot(loot: Array, seed_value: int) -> void:
	var world_root: Node3D = get_tree().get_first_node_in_group("world") as Node3D
	if world_root == null or loot.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var front: Vector3 = get_front_position()
	var right: Vector3 = global_transform.basis.x.normalized()
	var fwd: Vector3 = global_transform.basis.z.normalized()
	for i: int in loot.size():
		var spec: Dictionary = R.loot_spec(String(loot[i]), rng)
		var item: Node = ItemSaveData.spawn(spec, world_root)
		if item == null or not (item is Node3D):
			continue
		## Small pile at the foot of the ladder, lifted so it settles.
		var col: int = i % 3
		var row: int = int(i / 3.0)
		(item as Node3D).global_position = front + right * (float(col) - 1.0) * 0.3 \
			+ fwd * float(row) * 0.3 + Vector3(0.0, 0.4 + 0.1 * float(row), 0.0)
		if item is RigidBody3D:
			var rb: RigidBody3D = item as RigidBody3D
			if rb.has_method("rest_collision_layer"):
				rb.collision_layer = rb.rest_collision_layer()
			if rb.has_method("_rest_collision_mask"):
				rb.collision_mask = rb._rest_collision_mask()
			rb.linear_velocity = Vector3.ZERO
			rb.gravity_scale = 1.0

func _add_report(title: String, lines: Array[String], tone: String) -> void:
	reports.push_front({"stamp": NPCClock.now(), "title": title, "lines": lines, "tone": tone})
	while reports.size() > T.MAX_REPORTS:
		reports.pop_back()

func _after_change() -> void:
	_update_lamp()
	expeditions_changed.emit()

# ─── Persistence (SaveManager field "surface_hatch", registered by MainWorld) ─
func get_save_data() -> Dictionary:
	return {
		"active": active.duplicate(true),
		"reports": reports.duplicate(true),
		"visited": visited.duplicate(),
		"discovered": discovered.duplicate(),
		"depletion": depletion.duplicate(true),
	}

func restore_save_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	active = (d.get("active", []) as Array).duplicate(true)
	reports = (d.get("reports", []) as Array).duplicate(true)
	visited = (d.get("visited", []) as Array).duplicate()
	var saved_discovered: Array = d.get("discovered", [])
	if not saved_discovered.is_empty():
		discovered = saved_discovered.duplicate()
	depletion = (d.get("depletion", {}) as Dictionary).duplicate(true)
	_after_change()

# ─── Model (procedural placeholder) ───────────────────────────────────────────
## Wall ladder + ceiling hatch collar with a hand wheel, a hazard-striped
## floor plate and a status lamp (green = sealed, amber = someone topside).
func _build_model() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.33)
	steel.metallic = 0.7
	steel.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.17, 0.17)
	dark.metallic = 0.5
	dark.roughness = 0.7
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = Color(0.78, 0.6, 0.12)
	hazard.roughness = 0.8
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission_energy_multiplier = 1.6

	var rail_z: float = -HALF_DEPTH + 0.08
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.06, LADDER_HEIGHT, 0.06), Vector3(side * 0.24, LADDER_HEIGHT * 0.5, rail_z), steel)
		## Wall brackets
		for y: float in [0.6, 1.8]:
			_box(Vector3(0.05, 0.05, 0.14), Vector3(side * 0.24, y, rail_z - 0.08), dark)
	var rung_y: float = 0.3
	while rung_y < LADDER_HEIGHT - 0.1:
		_box(Vector3(0.48, 0.035, 0.035), Vector3(0.0, rung_y, rail_z), steel)
		rung_y += 0.3

	## Ceiling collar + lid + wheel, just in front of the ladder top.
	var collar := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.42
	tube.bottom_radius = 0.42
	tube.height = 0.22
	collar.mesh = tube
	collar.material_override = dark
	collar.position = Vector3(0.0, LADDER_HEIGHT + 0.1, 0.12)
	add_child(collar)
	var lid := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.38
	disk.bottom_radius = 0.38
	disk.height = 0.05
	lid.mesh = disk
	lid.material_override = steel
	lid.position = Vector3(0.0, LADDER_HEIGHT - 0.03, 0.12)
	add_child(lid)
	var wheel := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.14
	torus.outer_radius = 0.18
	wheel.mesh = torus
	wheel.material_override = hazard
	wheel.position = Vector3(0.0, LADDER_HEIGHT - 0.08, 0.12)
	add_child(wheel)

	## Floor plate: hazard border with a dark centre.
	_box(Vector3(HALF_WIDTH * 2.0, 0.02, 0.8), Vector3(0.0, 0.01, 0.25), hazard)
	_box(Vector3(HALF_WIDTH * 2.0 - 0.16, 0.025, 0.64), Vector3(0.0, 0.012, 0.25), dark)

	## Status lamp beside the ladder.
	_box(Vector3(0.1, 0.16, 0.06), Vector3(0.38, 1.6, -HALF_DEPTH + 0.03), dark)
	var lamp := _box(Vector3(0.06, 0.06, 0.04), Vector3(0.38, 1.63, -HALF_DEPTH + 0.07), _lamp_mat)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	## Collision covers the ladder only; the floor plate stays walkable.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, LADDER_HEIGHT, HALF_DEPTH * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, LADDER_HEIGHT * 0.5, 0.0)
	add_child(shape)

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _update_lamp() -> void:
	if _lamp_mat == null:
		return
	var c: Color = Color(0.25, 0.85, 0.35) if active.is_empty() else Color(1.0, 0.62, 0.12)
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
