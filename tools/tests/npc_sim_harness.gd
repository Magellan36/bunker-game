extends Node
## Headless NPC simulation harness — boots the REAL MainWorld, furnishes the
## pregen room through BuildModeController.restore_placed_objects() (the same
## path a save load uses), drops real items, spawns NPCs, and runs the game
## at fixed-FPS (faster than real time) while watching for the NPC failure
## classes that have historically needed whack-a-mole fixes:
##
##   ghost_held      — npc.held_item set but the item isn't actually held by it
##   stuck_holding   — carrying something for a long time in an activity that
##                     doesn't use it (Wander/Relax/Sit/Talk/…)
##   orphan_held     — an item still "is_held" that no NPC/player owns
##   churn           — the same activity entered and dropped again and again
##                     without lasting (the "frozen, flickering NPC" loop)
##   frozen          — non-stationary activity with zero displacement for long
##   escaped         — NPC fell through the floor or left the dug area
##   claim_leak      — items reserved by an NPC that is idle / not pursuing them
##   starving_food   — hunger/thirst critically low while food/water sits free
##   script_errors   — counted by the wrapper script from engine output
##
## Usage:
##   tools/tests/run_npc_sim.sh --scenario=basic --minutes=20 --npcs=4 --seed=1
## (runs res://tools/tests/NPCSimHarness.tscn as the main scene so autoloads exist)
## Exit code 0 = no invariant violations, 1 = violations (report printed).

const SCENARIOS: Array[String] = ["basic", "farm", "cook", "power", "stress", "scarcity", "door", "session", "morale", "all"]

var _cfg: Dictionary = {
	"scenario": "basic",
	"minutes": 10.0,      ## real-time-equivalent minutes (1 game hour = 1 minute)
	"npcs": 4,
	"seed": 1,
	"verbose": false,
	"timeline": false,
	"scores": 0.0,        ## >0: print every NPC's candidate scores at this interval (seconds)
	"capture": "",        ## directory (absolute) to write PNG frames into (needs a real renderer)
	"cam": "",            ## "px,py,pz,lx,ly,lz" camera position + look-at for captures
	"shots": "",          ## "t0:count:dt" — capture `count` frames starting at sim time t0, every dt seconds
	"hour": -1.0,         ## start the clock at this hour of day
	"follow": -1,          ## capture camera frames this resident (index) instead of --cam
	"force": "",           ## at --bubbles time, force an activity on resident 0 (e.g. "lean")
	"bubbles": -1.0,       ## at this sim time: stage a chat + a nap in front of the capture camera
	"saveload": -1.0,     ## at this sim time: save all NPCs, restore them, verify nothing was lost
	"player_sleep": 0.0,  ## +1 / -1: at sim t=2 put the PLAYER into the first bed from that side (visual check)
	"open_panel": -1.0,   ## at this sim time open the resident panel (talk menu) on the first NPC
}
var _panel_opened: bool = false
var _player_slept: bool = false
var _saveload_done: bool = false
var _shot_plan: Array = []   ## [[t0, count, dt], ...]
var _shot_index: int = 0
var _capture_cam: Camera3D = null
var _score_timer: float = 0.0

var _world: Node = null
var _bc: Node = null
var _t: float = 0.0
var _phase: int = 0
var _setup_at: float = 1.5
var _sample_timer: float = 0.0
const SAMPLE_DT: float = 0.25

## per-NPC tracking
var _track: Dictionary = {}   ## npc instance_id -> Dictionary
var _violations: Dictionary = {}   ## kind -> Array[String]
var _activity_time: Dictionary = {}   ## activity class -> seconds (all NPCs)
var _activity_entries: Dictionary = {}   ## activity class -> count
var _log_lines: Array[String] = []
var _hour_total: Array[int] = []
var _hour_asleep: Array[int] = []

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		var k: String = kv[0]
		var v: String = kv[1] if kv.size() > 1 else "true"
		match k:
			"scenario": _cfg["scenario"] = v
			"minutes": _cfg["minutes"] = float(v)
			"npcs": _cfg["npcs"] = int(v)
			"seed": _cfg["seed"] = int(v)
			"verbose": _cfg["verbose"] = v == "true"
			"timeline": _cfg["timeline"] = v == "true"
			"scores": _cfg["scores"] = float(v)
			"capture": _cfg["capture"] = v
			"cam": _cfg["cam"] = v
			"shots": _cfg["shots"] = v
			"hour": _cfg["hour"] = float(v)
			"saveload": _cfg["saveload"] = float(v)
			"bubbles": _cfg["bubbles"] = float(v)
			"follow": _cfg["follow"] = int(v)
			"force": _cfg["force"] = v
			"debug": NPCDebug.enabled = v != "0"
			"profile": NPCDebug.profile = v != "0"
			"player_sleep": _cfg["player_sleep"] = float(v)
			"open_panel": _cfg["open_panel"] = float(v)
	seed(int(_cfg["seed"]))
	_world = load("res://scenes/world/MainWorld.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_world)

func _process(delta: float) -> void:
	_t += delta
	if String(_cfg["scenario"]) == "morale" and _phase == 1:
		_run_morale_timeline()
		_phase = 3
		get_tree().quit(0 if _violations.is_empty() else 1)
		return
	if _phase == 0:
		if _t >= _setup_at:
			_phase = -1   ## setup may await a physics frame (door scenario)
			await _setup()
			_phase = 1
		return
	if _phase < 0:
		return
	if _phase == 1:
		_check_spin(delta)
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = SAMPLE_DT
			_sample()
			if String(_cfg["scenario"]) == "session":
				_check_session_cooking()
		if float(_cfg["scores"]) > 0.0:
			_score_timer -= delta
			if _score_timer <= 0.0:
				_score_timer = float(_cfg["scores"])
				_dump_scores()
		if String(_cfg["capture"]) != "":
			_tick_capture()
		if not _player_slept and float(_cfg["player_sleep"]) != 0.0 and _t - _setup_at >= 2.0:
			_player_slept = true
			var bed: Node3D = get_tree().get_nodes_in_group("bed")[0]
			var player: Node3D = get_tree().get_first_node_in_group("player")
			player.global_position = bed.global_transform * Vector3(0.8, 1.0, float(_cfg["player_sleep"]) * 0.9)
			bed.set_player_in_range(true)
			bed.sleep_requested.emit()
		if not _panel_opened and float(_cfg["open_panel"]) >= 0.0 and _t - _setup_at >= float(_cfg["open_panel"]):
			_panel_opened = true
			var first: Node3D = get_tree().get_nodes_in_group("npc")[0]
			var player: Node3D = get_tree().get_first_node_in_group("player")
			player.global_position = first.global_position + Vector3(0.0, 0.0, 1.2)
			first.on_interact()
		if not _bubbles_staged and float(_cfg["bubbles"]) >= 0.0 and _t - _setup_at >= float(_cfg["bubbles"]):
			_bubbles_staged = true
			_stage_bubbles()
		if not _saveload_done and float(_cfg["saveload"]) >= 0.0 and _t - _setup_at >= float(_cfg["saveload"]):
			_saveload_done = true
			_check_save_load()
		if _t - _setup_at >= float(_cfg["minutes"]) * 60.0:
			_phase = 2
			_report()

# ─── Setup ──────────────────────────────────────────────────────────────────
func _setup() -> void:
	_bc = _world._build_controller
	var sc: String = String(_cfg["scenario"])
	var objs: Array = []
	var items: Array = []   ## [scene_path_or_kind, Vector3, extra]
	var gen_fuel: float = -1.0
	var want_all: bool = sc == "all" or sc == "session"

	## Room is x ∈ [-12, 3], z ∈ [5, 12] (1 m cells). Research station sits
	## around the middle — keep furniture on the edges.
	if sc == "door":
		## A full-height wall splits the room at x = -8.5 with a closed bunker
		## door in it: beds on the west side, everything else east. Residents
		## must ask the door to open, queue, and cross to eat, drink and sleep.
		var wall: Dictionary = _obj(1, Vector3(DOOR_WALL_X, 0.5, 8.5), DOOR_WALL_ANGLE)
		wall["run_length"] = 7.2
		objs.append(wall)
		var door: Dictionary = _obj(39, Vector3(DOOR_WALL_X, 0.5, 8.5), DOOR_WALL_ANGLE)
		door["extra"] = {"is_open": false}   ## non-empty extra → restore attaches it to the wall
		objs.append(door)
	if sc in ["basic", "stress", "scarcity", "cook", "farm", "power", "door"] or want_all:
		objs.append(_obj(4, Vector3(-11.0, 0.5, 11.2), 0.0))        ## bed
		objs.append(_obj(4, Vector3(-11.0, 0.5, 9.0), 0.0))         ## bed
		objs.append(_obj(29, Vector3(1.5, 0.5, 11.5), 0.0))         ## chair
		objs.append(_obj(29, Vector3(0.5, 0.5, 11.5), 0.0))         ## chair
		objs.append(_obj(3, Vector3(2.5, 0.5, 6.0), 90.0))          ## shelving
		objs.append(_obj(36, Vector3(2.5, 0.5, 8.5), 0.0))          ## trash can
		objs.append(_obj(33, Vector3(-6.0, 0.5, 11.6), 0.0))        ## dresser
	if sc in ["farm"] or want_all:
		objs.append(_obj(22, Vector3(-7.0, 0.5, 6.0), 0.0))         ## double tray
		objs.append(_obj(21, Vector3(-4.5, 0.5, 6.0), 0.0))         ## single tray
	if sc in ["cook"] or want_all:
		objs.append(_obj(30, Vector3(-1.0, 0.5, 11.5), 0.0))        ## stove (has pot)
		objs.append(_obj(30, Vector3(-3.0, 0.5, 11.5), 0.0))        ## stove (no pot anywhere → must not churn)
	if sc in ["power"] or want_all:
		objs.append(_obj(6, Vector3(-9.0, 0.5, 5.6), 0.0))          ## small generator
		gen_fuel = 20.0 if sc != "session" else 80.0

	_bc.restore_placed_objects(objs)
	if sc == "door":
		await get_tree().physics_frame
		for d: Node in get_tree().get_nodes_in_group("npc_bottleneck"):
			print("[harness] door at %s host=%s open=%s" % [(d as Node3D).global_position,
				is_instance_valid(d.get("_host_wall")), d.is_open()])

	var food_count: int = 6
	var water_count: int = 6
	var clutter: int = 4
	match sc:
		"stress":
			food_count = 10; water_count = 10; clutter = 20
		"scarcity":
			food_count = 1; water_count = 1; clutter = 2
	for i in food_count:
		items.append(["res://scenes/world/FoodCan.tscn", _rand_floor_pos()])
	for i in water_count:
		items.append(["res://scenes/world/WaterBottle.tscn", _rand_floor_pos()])
	for i in clutter:
		items.append(["res://scenes/world/TestCrate.tscn", _rand_floor_pos()])
	if sc in ["farm"] or want_all:
		items.append(["soil", _rand_floor_pos()])
		items.append(["soil", _rand_floor_pos()])
		items.append(["seed:tomato", _rand_floor_pos()])
		items.append(["seed:carrot", _rand_floor_pos()])
		items.append(["res://scenes/world/Basket.tscn", _rand_floor_pos()])
	if sc in ["cook"] or want_all:
		items.append(["res://scenes/world/CookingPot.tscn", _rand_floor_pos()])
	if sc in ["power"] or want_all:
		items.append(["res://scenes/world/FuelCan.tscn", _rand_floor_pos()])

	var parent: Node = _world
	for it: Array in items:
		var kind: String = it[0]
		var pos: Vector3 = it[1]
		if kind == "soil":
			BagOfSoilItem.spawn_at(parent, pos)
		elif kind.begins_with("seed:"):
			SeedItem.spawn_at(parent, pos, kind.substr(5))
		else:
			FarmingShopHelper.spawn_scene_settled(parent, kind, pos)

	if gen_fuel >= 0.0:
		var pm: Node = get_tree().get_first_node_in_group("power_manager")
		for g: Node in get_tree().get_nodes_in_group("generator"):
			if pm != null and pm.has_method("admin_set_generator_fuel"):
				pm.admin_set_generator_fuel(str(g.get_instance_id()), gen_fuel)
			elif pm != null and pm.has_method("set_generator_fuel"):
				pm.set_generator_fuel(str(g.get_instance_id()), gen_fuel)

	if float(_cfg["hour"]) >= 0.0:
		var stats: Node = get_tree().get_first_node_in_group("player_stats")
		stats.set_elapsed(float(_cfg["hour"]) * stats._seconds_per_game_hour)
	_setup_capture()
	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	for i in int(_cfg["npcs"]):
		var npc: Node3D = npc_scene.instantiate()
		_world.add_child(npc)
		npc.global_position = _rand_floor_pos() + Vector3(0.0, 1.0, 0.0)
		if sc == "session":
			npc.hunger = randf_range(82.0, 100.0)   ## well fed: cooking must still happen
			npc.thirst = randf_range(60.0, 100.0)
			npc.energy = randf_range(55.0, 100.0)
		elif sc == "scarcity":
			npc.hunger = randf_range(35.0, 60.0)
			npc.thirst = randf_range(35.0, 60.0)
		else:
			npc.hunger = randf_range(40.0, 100.0)
			npc.thirst = randf_range(40.0, 100.0)
			npc.energy = randf_range(45.0, 100.0)
		_track[npc.get_instance_id()] = {
			"npc": npc, "act": "", "act_since": _t, "entries": [],
			"hold_since": -1.0, "hold_act": "", "last_pos": npc.global_position,
			"still_since": _t, "reported": {},
		}
	if sc == "session":
		await _wire_first_stove()
	print("[harness] scenario=%s npcs=%d minutes=%.1f seed=%d objects=%d items=%d" % [
		sc, int(_cfg["npcs"]), float(_cfg["minutes"]), int(_cfg["seed"]), objs.size(), items.size()])
	for g in ["chair", "bed", "shelving", "trash_receptacle", "generator", "farming_tray", "stove", "pickup"]:
		print("[harness]   group %s = %d" % [g, get_tree().get_nodes_in_group(g).size()])

## ─── Morale timeline (fast-forward, no physics) ─────────────────────────
## Drives NPCMorale (and crash-out risk) hour by hour for a week under three
## synthetic bunkers and checks the design targets: a badly run bunker puts
## residents at crash-out risk in ~3-5 days; a good one never does.
const MORALE_BUNKERS: Dictionary = {
	"bad":     {"light": -1.0, "power": -1.0, "space": -0.6, "safety": 0.0, "company": 0.0, "meal": "ate_cold_can", "water_q": 35.0, "sleep": "slept_on_floor"},
	"average": {"light": 0.2,  "power": 0.1,  "space": 0.0,  "safety": 0.2, "company": 0.1, "meal": "ate_cold_can", "water_q": 70.0, "sleep": "slept_in_bed"},
	"good":    {"light": 0.5,  "power": 0.3,  "space": 0.3,  "safety": 0.2, "company": 0.3, "meal": "ate_hot_meal", "water_q": 95.0, "sleep": "slept_in_bed"},
}

func _run_morale_timeline() -> void:
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	for n: NPC in npcs:
		n.set_physics_process(false)
		n.set_process(false)
		n.hunger = 70.0; n.thirst = 70.0; n.energy = 70.0
	for bunker: String in MORALE_BUNKERS.keys():
		var cfg: Dictionary = MORALE_BUNKERS[bunker]
		var first_risk: Array[float] = []
		var first_crash: Array[float] = []
		var end_morale: Array[float] = []
		for n: NPC in npcs:
			n.randomize_personality()
			n.morale_sys = NPCMorale.new()
			n.morale_sys.setup(n)
			n.morale_sys.sample_override = {"light": cfg["light"], "power": cfg["power"], "space": cfg["space"],
				"safety": cfg["safety"], "company": cfg["company"]}
			var risk_at: float = -1.0
			var crash_at: float = -1.0
			for step: int in 7 * 24 * 4:   ## a week in 15-minute steps
				var hour: float = step * 0.25
				var hod: float = fmod(hour, 24.0)
				if is_equal_approx(fmod(hod, 8.0), 0.0):
					n.morale_sys.note_meal(String(cfg["meal"]))
				if is_equal_approx(fmod(hod, 6.0), 0.0):
					n.morale_sys.note_drink(float(cfg["water_q"]))
				if is_equal_approx(hod, 7.0):
					n.morale_sys.note_sleep(String(cfg["sleep"]))
				n.morale_sys.tick(0.25, 0.0)
				if risk_at < 0.0 and n.morale_sys.morale < NPCMorale.CRASH_RISK_BELOW:
					risk_at = hour / 24.0
				if crash_at < 0.0 and n.has_method("debug_roll_crash_out") and n.debug_roll_crash_out(0.25):
					crash_at = hour / 24.0
			first_risk.append(risk_at)
			first_crash.append(crash_at)
			end_morale.append(n.morale_sys.morale)
		print("[morale] %-8s end morale %s | crash-risk from day %s | first crash day %s" % [bunker,
			_fmt_list(end_morale), _fmt_list(first_risk), _fmt_list(first_crash)])
		var risked: Array = first_risk.filter(func(d): return d >= 0.0)
		if bunker == "good" and not risked.is_empty():
			_flag("morale_timeline", npcs[0], "good bunker reached crash-out risk: %s" % str(first_risk))
		if bunker == "bad":
			## Design: the FIRST resident is at risk after ~2-4 days, most of
			## them within the week; traits spread the rest.
			var earliest: float = risked.min() if not risked.is_empty() else -1.0
			if earliest < 2.0 or earliest > 4.0:
				_flag("morale_timeline", npcs[0], "bad bunker: first resident at crash-out risk on day %.1f (want 2-4)" % earliest, "bad-first")
			if risked.size() * 2 < first_risk.size():
				_flag("morale_timeline", npcs[0], "bad bunker: only %d/%d residents at risk within a week" % [risked.size(), first_risk.size()], "bad-most")
			var crashed: Array = first_crash.filter(func(d): return d >= 0.0)
			if not crashed.is_empty() and (crashed.min() < 2.5 or crashed.min() > 5.5):
				_flag("morale_timeline", npcs[0], "bad bunker: first crash-out on day %.1f (want 3-5)" % crashed.min(), "bad-crash")
	_report()

static func _fmt_list(a: Array) -> String:
	var parts: Array[String] = []
	for v in a:
		parts.append("-" if float(v) < 0.0 else "%.1f" % float(v))
	return "[" + ", ".join(parts) + "]"

## Session scenario: the stove nearest the generator is wired to it; the
## other stays unplugged (a pot may go on it, but nobody may cook on it).
var _wired_stove: Node = null
var _first_cook_t: float = -1.0
var _cook_sessions: int = 0

func _wire_first_stove() -> void:
	for i in 3:
		await get_tree().physics_frame
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	var gens: Array = get_tree().get_nodes_in_group("generator")
	var stoves: Array = get_tree().get_nodes_in_group("stove")
	if pm == null or gens.is_empty() or stoves.is_empty():
		print("[harness] session wiring FAILED (pm/gen/stove missing)")
		return
	var gen: Node3D = gens[0]
	stoves.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(gen.global_position) < b.global_position.distance_to(gen.global_position))
	_wired_stove = stoves[0]
	var gkey: String = pm._generator_wire_key(str(gen.get_instance_id()))
	var skey: String = String(_wired_stove.get("_pm_node_key"))
	pm.register_wire_edge(gkey, skey, null, true)
	for i in 3:
		await get_tree().physics_frame
	for st: Node in stoves:
		print("[harness] stove at %s connected=%s" % [(st as Node3D).global_position, st.npc_can_power_on()])

func _check_session_cooking() -> void:
	for st: Node in get_tree().get_nodes_in_group("stove"):
		var pot: Node = st.pot_ref
		if pot == null or not is_instance_valid(pot):
			continue
		if not st.npc_can_power_on() and pot.count_filled() > 0:
			_flag("cook_unwired", get_tree().get_nodes_in_group("npc")[0], "ingredients put in a pot on an UNCONNECTED stove", str(st.get_instance_id()))
	if _first_cook_t < 0.0:
		for n: Node in get_tree().get_nodes_in_group("npc"):
			if _act_class(n) == "CookingActivity":
				_first_cook_t = _t - _setup_at
				print("[harness] first cooking decision at %.1fs by %s" % [_first_cook_t, n.npc_name])
				break

## Spin detector: body yaw turning > 1.5 full turns within 4 s while the
## resident barely moves = spinning in place.
const SPIN_WINDOW: float = 4.0
func _check_spin(delta: float) -> void:
	for id in _track.keys():
		var tr: Dictionary = _track[id]
		var raw = tr["npc"]
		if not is_instance_valid(raw):
			continue
		var npc: Node3D = raw
		var yaw: float = npc.rotation.y
		var model: Node3D = npc.get_node_or_null("CharacterModel") as Node3D
		var myaw: float = model.global_rotation.y if model != null else yaw
		if not tr.has("spin_yaw"):
			tr["spin_yaw"] = yaw; tr["spin_myaw"] = myaw; tr["spin_acc"] = 0.0; tr["spin_macc"] = 0.0
			tr["spin_t"] = 0.0; tr["spin_pos"] = npc.global_position
		tr["spin_acc"] = float(tr["spin_acc"]) + absf(angle_difference(float(tr["spin_yaw"]), yaw))
		tr["spin_net"] = float(tr.get("spin_net", 0.0)) + angle_difference(float(tr["spin_yaw"]), yaw)
		tr["spin_locked"] = int(tr.get("spin_locked", 0)) + (1 if npc.is_movement_locked() else 0)
		tr["spin_frames"] = int(tr.get("spin_frames", 0)) + 1
		tr["spin_macc"] = float(tr["spin_macc"]) + absf(angle_difference(float(tr["spin_myaw"]), myaw))
		tr["spin_yaw"] = yaw
		tr["spin_myaw"] = myaw
		tr["spin_t"] = float(tr["spin_t"]) + delta
		if float(tr["spin_t"]) >= SPIN_WINDOW:
			var moved: float = NPCItemUser.flat_distance(npc.global_position, tr["spin_pos"])
			var turns: float = maxf(float(tr["spin_acc"]), float(tr["spin_macc"])) / TAU
			if (absf(float(tr["spin_net"])) / TAU > 1.5 or turns > 2.5) and moved < 1.0:
				_flag("spinning", npc, "turned %.1f times (net %.1f) in %.0fs while moving %.2fm (model %.1f) locked %d/%d frames pos=%s" % [
					turns, float(tr["spin_net"]) / TAU, SPIN_WINDOW, moved, float(tr["spin_macc"]) / TAU,
					int(tr["spin_locked"]), int(tr["spin_frames"]), npc.global_position],
					"spin" + str(int(_t / 20.0)))
			tr["spin_acc"] = 0.0; tr["spin_macc"] = 0.0; tr["spin_t"] = 0.0; tr["spin_pos"] = npc.global_position
			tr["spin_net"] = 0.0; tr["spin_locked"] = 0; tr["spin_frames"] = 0

## Bubble demo: two residents chat at (-3.4, 8.6), a third naps in the
## first bed — framed by --cam=-3.4,2.6,5.6,-3.4,1.6,8.6 or similar.
var _bubbles_staged: bool = false
func _stage_bubbles() -> void:
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	if String(_cfg["force"]) == "lean" and not npcs.is_empty():
		var l: NPC = npcs[0]
		if NPCItemUser.hands_full(l):
			NPCItemUser.drop_held(l)
		for attempt: int in 15:
			if NPCItemUser.hands_full(l):
				NPCItemUser.drop_held(l)
			l.remove_meta("_lean_cooldown_until") if l.has_meta("_lean_cooldown_until") else null
			l.brain.force_command(LeanActivity.new())
			await get_tree().physics_frame
			if l.brain.current_activity() is LeanActivity and not l.brain.current_activity().done(l):
				print("[harness] forced lean on %s (try %d)" % [l.npc_name, attempt])
				return
			await get_tree().create_timer(1.0).timeout
		print("[harness] forced lean FAILED")
		return
	if npcs.size() < 3:
		return
	var a: NPC = npcs[0]
	var b: NPC = npcs[1]
	for n: NPC in [a, b]:
		n.brain.stop_current()
		n.hunger = 95.0; n.thirst = 95.0; n.energy = 90.0
	a.place_standing_at(Vector3(-4.0, 0.5, 8.6))
	b.place_standing_at(Vector3(-2.8, 0.5, 8.6))
	a.relationships[b.npc_id] = 40.0
	b.relationships[a.npc_id] = 40.0
	var c: NPC = npcs[2]
	c.energy = 5.0
	c.brain.stop_current()
	for attempt: int in 12:
		for n: NPC in [a, b]:
			if NPCItemUser.hands_full(n):
				NPCItemUser.drop_held(n)
			n._talk_cooldown_until = -1.0 if "_talk_cooldown_until" in n else 0.0
		if a.debug_force_talk():
			print("[harness] staged chat started (try %d)" % attempt)
			return
		await get_tree().create_timer(1.0).timeout
	print("[harness] staged chat FAILED: partner=%s avail_b=%s" % [a.find_talk_partner(), b.is_available_to_talk()])

const DOOR_WALL_X: float = -8.5
const DOOR_WALL_ANGLE: float = 0.0   ## wall run (and door) along world Z
var _door_crossings: int = 0
var _door_toggles: int = 0
var _door_last_close: float = 0.0

func _obj(tile: int, pos: Vector3, angle: float) -> Dictionary:
	return {"tile_id": tile, "price": 0, "pos": {"x": pos.x, "y": pos.y, "z": pos.z}, "angle_deg": angle, "extra": {}}

func _rand_floor_pos() -> Vector3:
	## avoid the room's centre band where the research station sits
	var x: float = randf_range(-10.5, 1.5)
	var z: float = randf_range(6.3, 10.7)
	return Vector3(x, 1.0, z)

# ─── Sampling / invariants ────────────────────────────────────────────────
const STATIONARY_OK: Array[String] = ["LeanActivity", 
	"SitActivity", "LieActivity", "RelaxActivity", "RelaxSitActivity", "RelaxLieActivity",
	"PassedOutActivity", "TalkActivity", "WanderActivity", "ForgetfulWanderActivity",
	"SleepActivity", "", "Idle",
]
const HOLD_OK: Array[String] = [
	"EatActivity", "DrinkActivity", "GivenEatActivity", "GivenDrinkActivity",
	"CleaningActivity", "RefuelActivity", "GardeningActivity", "CookingActivity",
	"PutAwayHeldItemActivity", "JobActivity", "GiveToFriendActivity", "SnatchActivity",
	"CommandCleaningActivity", "CommandRefuelActivity", "CommandGardeningActivity",
	"CommandCookingActivity", "CommandHarvestActivity", "CommandJobActivity",
]

func _act_class(npc: Node) -> String:
	if npc.brain == null or npc.brain._current == null:
		return ""
	var s: Script = npc.brain._current.get_script()
	return s.get_global_name() if s != null else "?"

func _flag(kind: String, npc: Node, msg: String, once_key: String = "") -> void:
	var tr: Dictionary = _track.get(npc.get_instance_id(), {})
	var key: String = kind + ":" + once_key
	if once_key != "" and tr.get("reported", {}).has(key):
		return
	if once_key != "":
		tr["reported"][key] = true
	if not _violations.has(kind):
		_violations[kind] = []
	var line: String = "t=%6.1fs %s [%s] %s" % [_t - _setup_at, npc.npc_name, _act_class(npc), msg]
	_violations[kind].append(line)
	if _cfg["verbose"]:
		print("[VIOLATION %s] %s" % [kind, line])

func _sample() -> void:
	var now: float = _t
	if String(_cfg["scenario"]) == "door":
		for d: Node in get_tree().get_nodes_in_group("npc_bottleneck"):
			## Play the player: shut the door every 30 s (when nobody is in
			## the doorway) so residents keep having to open it and wait.
			if d.is_open() and _t - _door_last_close > 30.0:
				var clear: bool = true
				for n: Node in get_tree().get_nodes_in_group("npc"):
					if NPCItemUser.flat_distance((n as Node3D).global_position, (d as Node3D).global_position) < 2.0:
						clear = false
				if clear:
					d.on_interact()
					_door_last_close = _t
			var open_now: bool = d.is_open()
			if open_now != bool(d.get_meta("_harness_open", false)):
				d.set_meta("_harness_open", open_now)
				_door_toggles += 1
				if _cfg["timeline"]:
					print("[tl] %6.1f door %s" % [_t - _setup_at, "OPENS" if open_now else "closes"])
	if _hour_total.is_empty():
		_hour_total.resize(24)
		_hour_asleep.resize(24)
		_hour_total.fill(0)
		_hour_asleep.fill(0)
	var hr: int = int(NPCClock.hour_of_day()) % 24
	for id in _track.keys():
		var tr: Dictionary = _track[id]
		var raw = tr["npc"]   ## untyped: a save/load cycle frees the old NPC nodes
		if not is_instance_valid(raw):
			continue
		var npc: Node = raw
		if String(_cfg["scenario"]) == "door":
			var side: int = 1 if (npc as Node3D).global_position.x > DOOR_WALL_X else -1
			if int(tr.get("side", side)) != side:
				_door_crossings += 1
			tr["side"] = side
		var act: String = _act_class(npc)
		_activity_time[act] = float(_activity_time.get(act, 0.0)) + SAMPLE_DT
		_hour_total[hr] += 1
		if npc.brain != null and (npc.brain.is_sleeping() or act == "PassedOutActivity"):
			_hour_asleep[hr] += 1
		if act != tr["act"]:
			var lasted: float = now - float(tr["act_since"])
			if tr["act"] != "":
				(tr["entries"] as Array).append({"act": tr["act"], "t": float(tr["act_since"]), "dur": lasted})
			if _cfg["timeline"]:
				print("[tl] %6.1f %s: %s -> %s (%.1fs) h=%.0f t=%.0f e=%.0f pos=(%.1f,%.1f,%.1f) held=%s" % [
					now - _setup_at, npc.npc_name, tr["act"], act, lasted, npc.hunger, npc.thirst, npc.energy, npc.global_position.x, npc.global_position.y, npc.global_position.z,
					(npc.held_item.name if npc.held_item != null and is_instance_valid(npc.held_item) else "-")])
			tr["act"] = act
			tr["act_since"] = now
			_activity_entries[act] = int(_activity_entries.get(act, 0)) + 1
			_check_churn(npc, tr)

		## ghost held
		var h = npc.held_item
		if h != null and not is_instance_valid(h):
			h = null   ## freed this frame (a used-up seed packet, an eaten dish) — NPC clears it next physics frame
		if h != null:
			if not is_instance_valid(h):
				_flag("ghost_held", npc, "held_item is a freed instance", "freed")
			elif ("is_held" in h) and not h.is_held:
				_flag("ghost_held", npc, "held_item %s is not is_held (dropped/knocked out but reference kept)" % h.name, str(h.get_instance_id()))
			elif ("_hold_point" in h) and h._hold_point != npc.hold_point:
				_flag("ghost_held", npc, "held_item %s follows a different hold point" % h.name, "hp" + str(h.get_instance_id()))
		## stuck holding
		if h != null and is_instance_valid(h) and not (act in HOLD_OK):
			if float(tr["hold_since"]) < 0.0 or tr["hold_act"] != act:
				tr["hold_since"] = now
				tr["hold_act"] = act
			elif now - float(tr["hold_since"]) > 25.0:
				_flag("stuck_holding", npc, "holding %s for %.0fs during %s" % [h.name, now - float(tr["hold_since"]), act], act + str(h.get_instance_id()))
		else:
			tr["hold_since"] = -1.0

		## frozen
		var pos: Vector3 = npc.global_position
		if pos.distance_to(tr["last_pos"]) > 0.3:
			tr["last_pos"] = pos
			tr["still_since"] = now
		elif not (act in STATIONARY_OK) and now - float(tr["still_since"]) > 30.0 \
				and now - float(tr["act_since"]) > 30.0:
			var lbl: String = npc.brain.current_label() if npc.brain != null else "?"
			_flag("frozen", npc, "no displacement for %.0fs while '%s' [in_sit=%s locked=%s nav_done=%s vel=%.2f stuck_recov=%d cause=%s pos=%s]" % [
				now - float(tr["still_since"]), lbl, npc.in_sit_sequence(), npc.is_movement_locked(), npc.nav_finished(),
				Vector2(npc.velocity.x, npc.velocity.z).length(), npc.stuck.recoveries, npc.stuck.last_cause, str(pos)], act + "@" + str(int(tr["act_since"])))

		## escaped
		if pos.y < -1.0 or pos.x < -13.5 or pos.x > 4.5 or pos.z < 3.5 or pos.z > 13.5:
			_flag("escaped", npc, "position %s out of the bunker" % str(pos), "esc")

		## starving with food available
		if npc.hunger < 15.0 and _free_count(Callable(NPCItemUser, "is_edible")) > 0 and act != "EatActivity" and act != "GivenEatActivity" and act != "PassedOutActivity":
			_flag("starving_food", npc, "hunger %.0f with edible items free" % npc.hunger, "h" + str(int(now / 30.0)))
		if npc.thirst < 15.0 and _free_count(Callable(NPCItemUser, "is_drinkable_bottle")) > 0 and act != "DrinkActivity" and act != "GivenDrinkActivity" and act != "PassedOutActivity":
			_flag("starving_food", npc, "thirst %.0f with water free" % npc.thirst, "t" + str(int(now / 30.0)))

	_check_orphans()
	_check_claims()

func _check_churn(npc: Node, tr: Dictionary) -> void:
	var entries: Array = tr["entries"]
	## last 60s of entries that lasted < 1.5s — a healthy NPC basically never
	## does this more than a couple of times a minute.
	var short: Dictionary = {}
	for e: Dictionary in entries:
		if _t - float(e["t"]) > 60.0:
			continue
		if float(e["dur"]) < 1.5:
			short[e["act"]] = int(short.get(e["act"], 0)) + 1
	for a in short.keys():
		if int(short[a]) >= 6:
			_flag("churn", npc, "%s entered/ended %d times in 60s lasting <1.5s each" % [a, short[a]], a + str(int(_t / 60.0)))
	## trim
	while entries.size() > 200:
		entries.pop_front()

func _free_count(filter: Callable) -> int:
	var n: int = 0
	for it: Node in get_tree().get_nodes_in_group("pickup"):
		if not (it is RigidBody3D) or not is_instance_valid(it):
			continue
		if it.is_in_group("shelved") or (("is_held" in it) and it.is_held):
			continue
		if filter.call(it):
			n += 1
	return n

func _check_orphans() -> void:
	var owners: Dictionary = {}
	for id in _track.keys():
		var npc: Node = _track[id]["npc"]
		if is_instance_valid(npc) and npc.held_item != null and is_instance_valid(npc.held_item):
			owners[npc.held_item.get_instance_id()] = true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_held_item"):
		var ph: Node = player.get_held_item()
		if ph != null and is_instance_valid(ph):
			owners[ph.get_instance_id()] = true
	for it: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(it) or not ("is_held" in it) or not it.is_held:
			continue
		if owners.has(it.get_instance_id()):
			continue
		if ("from_inventory" in it) and it.from_inventory:
			continue
		var npc0: Node = _track.values()[0]["npc"] if not _track.is_empty() else null
		if npc0 != null:
			_flag("orphan_held", npc0, "item %s is_held=true but nobody holds it" % it.name, "orph" + str(it.get_instance_id()))

func _check_claims() -> void:
	var claims: Dictionary = NPCItemUser._claims if "_claims" in NPCItemUser else {}
	for iid in claims.keys():
		var owner_iid: int = int(claims[iid]) if not (claims[iid] is Dictionary) else int(claims[iid].get("owner", 0))
		var owner: Object = instance_from_id(owner_iid)
		var item: Object = instance_from_id(int(iid))
		if item == null or not is_instance_valid(item):
			continue
		if owner == null or not is_instance_valid(owner) or not (owner is NPC):
			continue
		var act: String = _act_class(owner)
		if act in ["WanderActivity", "RelaxActivity", "SitActivity", "LieActivity", "TalkActivity", ""]:
			_flag("claim_leak", owner, "still reserves %s while %s" % [(item as Node).name, act], "cl" + str(iid))

func _dump_scores() -> void:
	for id in _track.keys():
		var npc: Node = _track[id]["npc"]
		if not is_instance_valid(npc) or npc.brain == null:
			continue
		var parts: Array[String] = []
		for c in npc.brain._candidates:
			var s: float = c.score(npc)
			if s > 0.0:
				parts.append("%s=%.1f" % [c.get_script().get_global_name().replace("Activity", ""), s])
		print("[scores] %6.1f %s h=%.0f t=%.0f e=%.0f cur=%s | %s" % [_t - _setup_at, npc.npc_name, npc.hunger, npc.thirst, npc.energy, _act_class(npc), ", ".join(parts)])

# ─── Save/load round trip ────────────────────────────────────────────────
const SAVE_KEYS: Array[String] = ["npc_name", "npc_id", "age", "health", "mood", "energy", "hunger", "thirst", "chronotype"]

func _npc_fingerprint(npc: Node) -> Dictionary:
	var d: Dictionary = {}
	for k: String in SAVE_KEYS:
		d[k] = npc.get(k)
	d["personality"] = _canon(npc.personality)
	d["relationships"] = _canon(npc.relationships)
	d["skills"] = _canon(npc.skills)
	d["thoughts"] = npc.thoughts.describe().size()
	d["gender"] = String(npc.get_meta("_adventurer_random_gender", ""))
	d["log"] = npc.get_action_log().size()
	d["medical"] = npc.medical.active_conditions.size() if npc.medical != null else 0
	return d

## Order-independent, rounding-tolerant dictionary fingerprint (JSON
## re-sorts keys and rounds the last digit or two of a double).
static func _canon(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%.5f" % [str(k), float(d[k])])
	return ",".join(parts)

func _check_save_load() -> void:
	## Give one NPC a medical condition so that path is exercised too.
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	if not npcs.is_empty() and npcs[0].medical != null:
		npcs[0].medical.spawn_fractured(MedicalCondition.BodyPart.LEFT_LEG)
	var before: Dictionary = {}
	for n: Node in npcs:
		before[n.npc_id] = _npc_fingerprint(n)
	var saved: Array = _world._get_npcs_for_save()
	var json: String = JSON.stringify(saved)   ## must survive a real JSON round trip
	var parsed: Variant = JSON.parse_string(json)
	_world._restore_npcs(parsed)
	await get_tree().process_frame
	await get_tree().process_frame
	var ok: int = 0
	_track.clear()
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if n.is_queued_for_deletion():
			continue
		_track[n.get_instance_id()] = {"npc": n, "act": "", "act_since": _t, "entries": [],
			"hold_since": -1.0, "hold_act": "", "last_pos": n.global_position, "still_since": _t, "reported": {}}
		var b: Dictionary = before.get(n.npc_id, {})
		if b.is_empty():
			_flag("saveload", n, "restored NPC %s had no saved counterpart" % n.npc_id, "missing" + n.npc_id)
			continue
		var a: Dictionary = _npc_fingerprint(n)
		for k in b.keys():
			var same: bool = str(a[k]) == str(b[k]) if not (b[k] is float) else absf(float(a[k]) - float(b[k])) < 0.01
			if not same:
				_flag("saveload", n, "%s changed across save/load: %s -> %s" % [k, str(b[k]), str(a[k])], k + n.npc_id)
			else:
				ok += 1
	print("[harness] save/load round trip: %d NPCs, %d fields verified" % [before.size(), ok])

# ─── Visual capture ────────────────────────────────────────────────────────
func _setup_capture() -> void:
	if String(_cfg["capture"]) == "":
		return
	DirAccess.make_dir_recursive_absolute(String(_cfg["capture"]))
	for part: String in String(_cfg["shots"]).split(";", false):
		var p: PackedStringArray = part.split(":")
		_shot_plan.append([float(p[0]), int(p[1]), float(p[2])])
	if String(_cfg["cam"]) != "":
		var c: PackedFloat64Array = String(_cfg["cam"]).split_floats(",")
		_capture_cam = Camera3D.new()
		_capture_cam.fov = 50.0
		get_tree().root.add_child(_capture_cam)
		_capture_cam.global_position = Vector3(c[0], c[1], c[2])
		_capture_cam.look_at(Vector3(c[3], c[4], c[5]), Vector3.UP)
		_capture_cam.current = true
	## Capture lighting: the bunker is dark until the player wires lights, so
	## brighten ambient and hang a few lamps over the room (visual only).
	var we: WorldEnvironment = _world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.72, 0.70, 0.66)
		we.environment.ambient_light_energy = 0.9
		we.environment.fog_enabled = false
	for x: float in [-9.0, -4.5, 0.0]:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.omni_range = 9.0
		lamp.light_energy = 1.6
		lamp.light_color = Color(1.0, 0.9, 0.75)
		_world.add_child(lamp)
		lamp.global_position = Vector3(x, 3.2, 8.5)
	## Rendering is only switched on for the frames we actually capture —
	## llvmpipe is far too slow to render every simulated frame.
	RenderingServer.render_loop_enabled = false

var _next_shot_t: float = -1.0
var _shots_left: int = 0
var _shot_dt: float = 0.0
var _frame_no: int = 0
var _render_warm: int = 0

func _tick_capture() -> void:
	var st: float = _t - _setup_at
	if _shots_left <= 0:
		if _shot_index >= _shot_plan.size():
			return
		var plan: Array = _shot_plan[_shot_index]
		if st < float(plan[0]):
			return
		_shot_index += 1
		_shots_left = int(plan[1])
		_shot_dt = float(plan[2])
		_next_shot_t = st
	if st >= _next_shot_t:
		if _capture_cam != null:
			_capture_cam.current = true
			var fi: int = int(_cfg["follow"])
			var npcs: Array = get_tree().get_nodes_in_group("npc")
			if fi >= 0 and fi < npcs.size():
				## Three-quarter view in front of the resident.
				var n: Node3D = npcs[fi]
				var fwd: Vector3 = -n.global_transform.basis.z
				var eye: Vector3 = n.global_position + fwd * 2.6 + n.global_transform.basis.x * 1.2 + Vector3.UP * 1.1
				_capture_cam.global_position = eye
				_capture_cam.look_at(n.global_position + Vector3.UP * 0.6)
		RenderingServer.render_loop_enabled = true
		_render_warm += 1
		if _render_warm < 3:
			return   ## let a couple of frames render so the image is current
		_render_warm = 0
		var img: Image = get_viewport().get_texture().get_image()
		_frame_no += 1
		var path: String = "%s/frame_%04d.png" % [String(_cfg["capture"]), _frame_no]
		img.save_png(path)
		print("[capture] %s at sim %.1fs (%s)" % [path, st, NPCClock.time_string()])
		_shots_left -= 1
		_next_shot_t = st + _shot_dt
		if _shots_left <= 0 or _shot_dt > 0.5:
			RenderingServer.render_loop_enabled = false

# ─── Report ──────────────────────────────────────────────────────────────
func _report() -> void:
	print("")
	print("══════════ NPC SIM REPORT (%s, %d NPCs, %.1f sim-min) ══════════" % [_cfg["scenario"], int(_cfg["npcs"]), float(_cfg["minutes"])])
	var total: float = 0.0
	for a in _activity_time.keys():
		total += float(_activity_time[a])
	var acts: Array = _activity_time.keys()
	acts.sort_custom(func(x, y): return float(_activity_time[x]) > float(_activity_time[y]))
	print("Activity share (time / entries):")
	for a in acts:
		print("  %-28s %5.1f%%  %4d" % [a if a != "" else "(idle)", 100.0 * float(_activity_time[a]) / maxf(total, 0.001), int(_activity_entries.get(a, 0))])
	var rhythm: Array[String] = []
	for h in 24:
		if _hour_total.size() == 24 and _hour_total[h] > 0:
			rhythm.append("%02d:%3d%%" % [h, int(100.0 * _hour_asleep[h] / _hour_total[h])])
	if not rhythm.is_empty():
		print("Asleep by hour: " + " ".join(rhythm))
	print("NPC end state:")
	for id in _track.keys():
		var npc: Node = _track[id]["npc"]
		if not is_instance_valid(npc):
			continue
		print("  %-7s h=%3.0f t=%3.0f e=%3.0f mood=%3.0f hp=%3.0f held=%s now='%s'" % [
			npc.npc_name, npc.hunger, npc.thirst, npc.energy, npc.mood, npc.health,
			(npc.held_item.name if npc.held_item != null and is_instance_valid(npc.held_item) else "-"),
			npc.brain.current_label() if npc.brain != null else "?"])
	## Refinement metrics.
	var short: Dictionary = {}
	var total_recov: Array[String] = []
	for id in _track.keys():
		var tr: Dictionary = _track[id]
		for e: Dictionary in tr["entries"]:
			if float(e["dur"]) < 1.5:
				short[e["act"]] = int(short.get(e["act"], 0)) + 1
		var n = tr["npc"]
		if is_instance_valid(n):
			total_recov.append("%s:%d" % [n.npc_name, n.stuck.recoveries])
	print("Short (<1.5s) activity entries: %s" % str(short))
	print("Stuck recoveries: %s" % " ".join(total_recov))
	var causes: Dictionary = {}
	for id in _track.keys():
		var n = _track[id]["npc"]
		if is_instance_valid(n):
			for k in n.stuck.cause_counts.keys():
				causes[k] = int(causes.get(k, 0)) + int(n.stuck.cause_counts[k])
	var ck: Array = causes.keys()
	ck.sort_custom(func(a, b): return int(causes[a]) > int(causes[b]))
	for k in ck.slice(0, 12):
		print("  stuck: %4d  %s" % [int(causes[k]), k])
	if NPCDebug.profile and NPCDebug.prof_frames > 0:
		var sum: int = 0
		for k in NPCDebug.prof_usec.keys():
			sum += int(NPCDebug.prof_usec[k])
		print("NPC CPU per NPC-frame: %.1f us total" % [float(sum) / NPCDebug.prof_frames])
		var keys: Array = NPCDebug.prof_usec.keys()
		keys.sort_custom(func(a, b): return int(NPCDebug.prof_usec[a]) > int(NPCDebug.prof_usec[b]))
		for k in keys:
			print("  %-20s %6.1f us" % [k, float(NPCDebug.prof_usec[k]) / NPCDebug.prof_frames])
	var bad: int = 0
	for k in _violations.keys():
		var arr: Array = _violations[k]
		bad += arr.size()
		print("VIOLATIONS %s: %d" % [k, arr.size()])
		for i in mini(arr.size(), 12):
			print("    " + String(arr[i]))
	if _cfg["timeline"]:
		for n: Node in get_tree().get_nodes_in_group("npc"):
			var lines: Array[String] = []
			for e: Dictionary in n._action_log:
				lines.append(String(e.get("text", "")))
			print("[harness] %s actions: %s" % [n.npc_name, " | ".join(lines.slice(maxi(0, lines.size() - 25)))])
	if String(_cfg["scenario"]) == "session":
		print("[harness] first cooking decision: %s" % ("%.1fs" % _first_cook_t if _first_cook_t >= 0.0 else "NEVER"))
		for st: Node in get_tree().get_nodes_in_group("stove"):
			var pot: Node = st.pot_ref
			print("[harness] stove connected=%s pot=%s filled=%d powered=%s" % [st.npc_can_power_on(), pot != null,
				pot.count_filled() if pot != null else 0, st.powered_on])
	if String(_cfg["scenario"]) == "door":
		print("[harness] door crossings: %d, door open/close changes: %d" % [_door_crossings, _door_toggles])
	print("RESULT: %s (%d violations)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(0 if bad == 0 else 1)
