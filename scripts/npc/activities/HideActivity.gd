extends NPCActivity
## HideActivity.gd (Sep 2026, Brannon) — when a WEAPON fight breaks out
## (gun or melee, not fists), everyone not in it runs for the far side of
## the bunker, shuts any door between them and the fight behind them,
## presses against a wall and stays there until it has been quiet for a
## little while. NPCCombat raises the alarm (NPCCombat.raise_alarm); this
## is how a resident reacts to it.

const SAMPLES: int = 24
## Sep 2026: real people stay down a good while after the shooting stops
## (was 8–14 s, then straight back to normal).
const LINGER: Vector2 = Vector2(45.0, 120.0)   ## seconds of quiet before they come out
const SPOT_SPACING: float = 2.5          ## hiders don't all pile into one corner
const DOOR_BONUS: float = 6.0            ## a door between them and the fight is worth metres
## Hiding spots taken (npc instance id -> point), so everyone picks their own.
static var _claimed: Dictionary = {}
const DOOR_NEAR: float = 1.6            ## they've just come through this door
const DOOR_CLEAR: float = 2.2           ## far enough past it to shut it
const TRAVEL_TIMEOUT: float = 25.0
## Watching the real game (Sep 2026): all five hiders ran for the one
## farthest corner, wedged there, stuck recovery pulled them out of hiding
## and every re-entry shouted a fresh panic line. Now distance stops
## mattering past FAR_ENOUGH, other hiders' spots count against a place,
## and someone already well away who stalls just gets down where they are.
const FAR_ENOUGH: float = 14.0
const CROWD_RADIUS: float = 6.0
const CROWD_PENALTY: float = 3.0         ## metres of distance per hider already heading there
const SAFE_DISTANCE: float = 8.0         ## far enough to get down wherever they are
const STALL_SECONDS: float = 2.0
const REENTER_SECONDS: float = 30.0      ## back into hiding this soon = the same scare
const WALL_RADIUS: float = 4.0

enum Phase { RUN, WALL, COWER }

var _phase: Phase = Phase.RUN
var _timer: float = 0.0
var _linger: float = 0.0
var _spot: Dictionary = {}
var _leaning: bool = false
var _doors_passed: Array = []           ## doors they came through (maybe to shut)
var _doors_shut: Array = []
var _barked: bool = false
var _run_best: float = INF
var _run_still: float = 0.0
var _cower_bark_at: float = 0.0
var _again: bool = false

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
	_run_best = INF
	_run_still = 0.0
	_cower_bark_at = randf_range(8.0, 30.0)
	if npc.held_item != null:
		NPCItemUser.drop_held(npc)   ## whatever they were carrying, they drop it
	## Pulled out of hiding a moment ago (stuck recovery, a door): the same
	## scare, so no new line, and if they're already well away they get
	## down where they are instead of running again.
	var again: bool = Time.get_ticks_msec() - int(npc.get_meta("_hid_msec", -1000000)) < int(REENTER_SECONDS * 1000.0)
	npc.set_meta("_hid_msec", Time.get_ticks_msec())
	_barked = again
	_again = again
	if again and NPCItemUser.flat_distance(npc.global_position, NPCCombat.alarm_pos) >= SAFE_DISTANCE:
		_claimed[npc.get_instance_id()] = npc.global_position
		_arrive(npc)
		return
	var spot: Vector3 = _far_point(npc)
	_claimed[npc.get_instance_id()] = spot
	npc.set_nav_target(spot)
	if not again:
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
			var target: Vector3 = _claimed.get(npc.get_instance_id(), npc.global_position)
			var safe: bool = NPCItemUser.flat_distance(npc.global_position, NPCCombat.alarm_pos) >= SAFE_DISTANCE
			if npc.nav_finished() or _timer > TRAVEL_TIMEOUT or NPCItemUser.flat_distance(npc.global_position, target) < 2.0 \
					or (safe and _stalled(npc, target, delta)):
				_arrive(npc)
		Phase.WALL:
			npc.nav_steer(delta)
			_track_doors(npc)
			var close: bool = NPCItemUser.flat_distance(npc.global_position, _spot["stand"]) < 0.6
			if close or npc.nav_finished() or _timer > 8.0 or _stalled(npc, _spot["stand"], delta):
				var model: Node = npc.get_node_or_null("CharacterModel")
				if close and model != null and model.has_method("begin_lean") and model.begin_lean(_spot["point"], _spot["normal"]):
					npc.lock_movement()
					_leaning = true
				_to_cower(npc)
		Phase.COWER:
			if not _leaning:
				npc.halt_movement(delta)
			_track_doors(npc)
			## One quiet line at most while down (it used to be one every
			## ~12 s per hider, a constant murmur).
			if _cower_bark_at > 0.0 and _timer > _cower_bark_at:
				_cower_bark_at = 0.0
				if randf() < 0.5:
					npc.bark(NPCDialogue.bark_line("hide_cower"))

func done(npc: NPC) -> bool:
	## Out once the fight has been quiet for their own linger time.
	return not NPCCombat.alarm_active(_linger) or NPCCombat.alarm_involves(npc.npc_id)

func exit(npc: NPC) -> void:
	_claimed.erase(npc.get_instance_id())
	LeanActivity._spots.erase(npc.get_instance_id())
	npc.set_meta("_hid_msec", Time.get_ticks_msec())
	npc.combat.rushing = false
	if _leaning:
		var model: Node = npc.get_node_or_null("CharacterModel")
		if model != null:
			model.end_lean()
		npc.request_stand_at(npc.global_position)
		_leaning = false

func attention_target(_npc: NPC) -> Node3D:
	return null

## Got there (or as far as they're getting): a wall nearby, on the far
## side from the fight, else down where they are.
func _arrive(npc: NPC) -> void:
	npc.combat.rushing = false
	var from_fight: float = NPCItemUser.flat_distance(npc.global_position, NPCCombat.alarm_pos)
	_spot = LeanActivity.find_spot(npc, WALL_RADIUS, NPCCombat.alarm_pos, from_fight - 1.0)
	if _spot.is_empty():
		_to_cower(npc)
		return
	LeanActivity._spots[npc.get_instance_id()] = _spot["point"]   ## other hiders and leaners take other walls
	npc.set_nav_target(_spot["stand"])
	_phase = Phase.WALL
	_timer = 0.0
	_run_best = INF
	_run_still = 0.0

## No real progress toward `target` for STALL_SECONDS (crowded corner,
## jostling) — checked before stuck recovery's own 5 s window gives up.
func _stalled(npc: NPC, target: Vector3, delta: float) -> bool:
	var d: float = NPCItemUser.flat_distance(npc.global_position, target)
	if d < _run_best - 0.3:
		_run_best = d
		_run_still = 0.0
		return false
	_run_still += delta
	return _run_still > STALL_SECONDS

func _to_cower(npc: NPC) -> void:
	_phase = Phase.COWER
	_timer = 0.0
	if not _again:
		npc.log_event("mood", "Hid from the fight")

## A reachable spot of their own, far from the fight, ideally with a door
## in between — not the one corner everyone else is running to.
func _far_point(npc: NPC) -> Vector3:
	var from: Vector3 = NPCCombat.alarm_pos
	var best: Vector3 = npc.global_position + (npc.global_position - from).normalized() * 8.0
	var best_score: float = -INF
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	if world == null or not world.has_method("get_random_cleared_cell_center"):
		return best
	for i: int in SAMPLES:
		var p: Vector3 = world.get_random_cleared_cell_center()
		if _taken(npc, p):
			continue
		var sc: float = minf(NPCItemUser.flat_distance(p, from), FAR_ENOUGH)
		if _door_between(npc, from, p):
			sc += DOOR_BONUS
		sc -= CROWD_PENALTY * _hiders_near(npc, p)
		sc -= 0.15 * NPCItemUser.flat_distance(npc.global_position, p)   ## not across the whole map for a metre's gain
		if sc > best_score and NPCItemUser.is_reachable(npc, p, 1.0):
			best_score = sc
			best = p
	return best

func _hiders_near(npc: NPC, p: Vector3) -> int:
	var n: int = 0
	for id: int in _claimed.keys():
		if id != npc.get_instance_id() and NPCItemUser.flat_distance(_claimed[id], p) < CROWD_RADIUS:
			n += 1
	return n

func _taken(npc: NPC, p: Vector3) -> bool:
	for id: int in _claimed.keys():
		if id != npc.get_instance_id() and NPCItemUser.flat_distance(_claimed[id], p) < SPOT_SPACING:
			return true
	return false

## Is there a door roughly on the way between the fight and this spot?
static func _door_between(npc: NPC, fight: Vector3, spot: Vector3) -> bool:
	for d: Node in npc.get_tree().get_nodes_in_group("npc_bottleneck"):
		if not (d is Node3D) or not d.has_method("is_open"):
			continue
		var dp: Vector3 = (d as Node3D).global_position
		if (spot - dp).dot(fight - dp) >= 0.0:
			continue   ## both on the same side of it
		var seg: Vector3 = Vector3(spot.x - fight.x, 0.0, spot.z - fight.z)
		var t: float = clampf(Vector3(dp.x - fight.x, 0.0, dp.z - fight.z).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
		var closest: Vector3 = Vector3(fight.x, 0.0, fight.z) + seg * t
		if Vector2(closest.x - dp.x, closest.z - dp.z).length() < 3.0:
			return true
	return false

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
