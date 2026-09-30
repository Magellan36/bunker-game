extends NPCActivity
## HideActivity.gd (Sep 2026, Brannon) — when a WEAPON fight breaks out
## (gun or melee, not fists), everyone not in it runs for the far side of
## the bunker, shuts any door between them and the fight behind them,
## presses against a wall and stays there until it has been quiet for a
## little while. NPCCombat raises the alarm (NPCCombat.raise_alarm); this
## is how a resident reacts to it.

const SAMPLES: int = 16
const LINGER: Vector2 = Vector2(8.0, 14.0)   ## seconds of quiet before they come out
const DOOR_NEAR: float = 1.6            ## they've just come through this door
const DOOR_CLEAR: float = 2.2           ## far enough past it to shut it
const TRAVEL_TIMEOUT: float = 25.0

enum Phase { RUN, WALL, COWER }

var _phase: Phase = Phase.RUN
var _timer: float = 0.0
var _linger: float = 0.0
var _spot: Dictionary = {}
var _leaning: bool = false
var _doors_passed: Array = []           ## doors they came through (maybe to shut)
var _doors_shut: Array = []
var _barked: bool = false

func score(npc: NPC) -> float:
	return 960.0 if should_hide(npc) else 0.0

static func should_hide(npc: NPC) -> bool:
	return NPCCombat.should_hide(npc)   ## (lives in NPCCombat: the alarm wakes residents too)

func label() -> String:
	return "Hiding"

func interruptible() -> bool:
	return false

func backoff_on_futile() -> bool:
	return false

func enter(npc: NPC) -> void:
	_phase = Phase.RUN
	_timer = 0.0
	_linger = randf_range(LINGER.x, LINGER.y)
	_doors_passed.clear()
	_doors_shut.clear()
	_leaning = false
	_barked = false
	if npc.held_item != null:
		NPCItemUser.drop_held(npc)   ## whatever they were carrying, they drop it
	npc.set_nav_target(_far_point(npc))
	NPCCombatDebug.trace(npc, "hiding from the weapon fight at %s" % NPCCombat.alarm_pos.snapped(Vector3.ONE * 0.1))

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	match _phase:
		Phase.RUN:
			npc.combat.rushing = true
			npc.nav_steer(delta)
			_track_doors(npc)
			if not _barked and _timer > 0.6:
				_barked = true
				npc.bark(NPCDialogue.bark_line("hide_run"), true)
			if npc.nav_finished() or _timer > TRAVEL_TIMEOUT:
				npc.combat.rushing = false
				_spot = LeanActivity.find_spot(npc)
				if _spot.is_empty():
					_to_cower(npc)
				else:
					npc.set_nav_target(_spot["stand"])
					_phase = Phase.WALL
					_timer = 0.0
		Phase.WALL:
			npc.nav_steer(delta)
			_track_doors(npc)
			var close: bool = NPCItemUser.flat_distance(npc.global_position, _spot["stand"]) < 0.6
			if close or npc.nav_finished() or _timer > 8.0:
				var model: Node = npc.get_node_or_null("CharacterModel")
				if close and model != null and model.has_method("begin_lean") and model.begin_lean(_spot["point"], _spot["normal"]):
					npc.lock_movement()
					_leaning = true
				_to_cower(npc)
		Phase.COWER:
			if not _leaning:
				npc.halt_movement(delta)
			_track_doors(npc)
			if _timer > 5.0 and randf() < delta * 0.08:
				npc.bark(NPCDialogue.bark_line("hide_cower"))

func done(npc: NPC) -> bool:
	## Out once the fight has been quiet for their own linger time.
	return not NPCCombat.alarm_active(_linger) or NPCCombat.alarm_involves(npc.npc_id)

func exit(npc: NPC) -> void:
	npc.combat.rushing = false
	if _leaning:
		var model: Node = npc.get_node_or_null("CharacterModel")
		if model != null:
			model.end_lean()
		npc.request_stand_at(npc.global_position)
		_leaning = false

func attention_target(_npc: NPC) -> Node3D:
	return null

func _to_cower(npc: NPC) -> void:
	_phase = Phase.COWER
	_timer = 0.0
	npc.log_event("mood", "Hid from the fight")

## The reachable open cell farthest from the fight (of a handful).
func _far_point(npc: NPC) -> Vector3:
	var from: Vector3 = NPCCombat.alarm_pos
	var best: Vector3 = npc.global_position + (npc.global_position - from).normalized() * 8.0
	var best_d: float = -1.0
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	if world == null or not world.has_method("get_random_cleared_cell_center"):
		return best
	for i: int in SAMPLES:
		var p: Vector3 = world.get_random_cleared_cell_center()
		var d: float = NPCItemUser.flat_distance(p, from)
		if d > best_d and NPCItemUser.is_reachable(npc, p, 1.0):
			best_d = d
			best = p
	return best

## Doors they pass through get shut behind them once they're clear of the
## doorway, if the door stands between them and the fight and nobody else
## is in it.
func _track_doors(npc: NPC) -> void:
	for d: Node in npc.get_tree().get_nodes_in_group("npc_bottleneck"):
		if not (d is Node3D) or not d.has_method("is_open"):
			continue
		var door: Node3D = d as Node3D
		var dist: float = NPCItemUser.flat_distance(npc.global_position, door.global_position)
		if dist < DOOR_NEAR and not _doors_passed.has(door):
			_doors_passed.append(door)
	for door: Node3D in _doors_passed.duplicate():
		if not is_instance_valid(door) or _doors_shut.has(door):
			continue
		if NPCItemUser.flat_distance(npc.global_position, door.global_position) < DOOR_CLEAR or not door.is_open():
			continue
		## The door must be between them and the fight.
		var to_me: Vector3 = npc.global_position - door.global_position
		var to_fight: Vector3 = NPCCombat.alarm_pos - door.global_position
		if to_me.dot(to_fight) >= 0.0:
			continue
		if _doorway_busy(npc, door):
			continue
		door.on_interact()   ## toggles it shut
		_doors_shut.append(door)
		npc.log_event("mood", "Shut the door behind me")
		NPCCombatDebug.trace(npc, "shut a door between them and the fight")

func _doorway_busy(npc: NPC, door: Node3D) -> bool:
	for o: Node in npc.get_tree().get_nodes_in_group("npc"):
		if o != npc and o is Node3D and NPCItemUser.flat_distance((o as Node3D).global_position, door.global_position) < 1.5:
			return true
	var player: Node3D = npc.get_tree().get_first_node_in_group("player") as Node3D
	return player != null and NPCItemUser.flat_distance(player.global_position, door.global_position) < 1.5
