extends NPCActivity
class_name WanderActivity
## WanderActivity.gd — what a resident does with a free moment.
##
## Sep 2026 rework — wandering has intent now instead of walking to uniformly
## random cells across the whole bunker:
##   • Each leg picks a destination by weighted choice: near a friend,
##     near someone they get along with, a spot by the furniture people use
##     (chairs, beds, shelves, the stove...), or just somewhere random.
##   • Between legs they pause — and while paused they look at whoever is
##     nearby (turning to face the player walking up to them).
##   • A stroll is 2–4 legs and then ENDS, handing control back to the brain
##     so relaxing/chatting/chores get a natural look-in. (It used to be
##     endless and could only be displaced by a large score margin.)
## `leisurely` (RelaxActivity's stroll fallback): slower pace, longer pauses.

const BASE_SCORE: float = 6.0
const LOOK_RANGE: float = 4.5

var leisurely: bool = false

var _legs_left: int = 3
var _idle_left: float = 0.0
var _walking: bool = false
var _look_target: Node3D = null
var _look_timer: float = 0.0

func score(npc: NPC) -> float:
	return BASE_SCORE * npc.get_work_ethic_passive_mult()

func label() -> String:
	return "Taking a stroll" if leisurely else "Wandering"

func enter(npc: NPC) -> void:
	_legs_left = randi_range(2, 4)
	_walking = false
	_idle_left = randf_range(0.5, 1.5)

func tick(npc: NPC, delta: float) -> void:
	if _walking:
		npc.nav_steer(delta)
		if npc.nav_finished():
			_walking = false
			_legs_left -= 1
			_idle_left = randf_range(npc.idle_time_min, npc.idle_time_max) * (1.8 if leisurely else 1.0)
		return
	npc.halt_movement(delta)
	_tick_look(npc, delta)
	_idle_left -= delta
	if _idle_left <= 0.0 and _legs_left > 0:
		npc.set_nav_target(_pick_destination(npc))
		_walking = true

func done(_npc: NPC) -> bool:
	return _legs_left <= 0 and not _walking and _idle_left <= 0.0

func exit(npc: NPC) -> void:
	npc.lock_movement()   ## was halt_movement(1.0): a lerp weight of 8 flipped velocity to -7x (backward lurch)

func backoff_on_futile() -> bool:
	return false

## Speed factor applied by NPC.nav_steer via get_status_speed_multiplier —
## a leisurely stroll is just shorter hops with longer pauses.
func _pick_destination(npc: NPC) -> Vector3:
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	var fallback: Vector3 = world.get_random_cleared_cell_center() if world != null and world.has_method("get_random_cleared_cell_center") else npc.global_position
	var options: Array[Dictionary] = []   ## {"pos", "w"}
	options.append({"pos": fallback, "w": 1.0})
	## People they like
	for other: Node in npc.get_tree().get_nodes_in_group("npc"):
		if other == npc or not (other is NPC):
			continue
		var rel: float = npc.mutual_relationship(other)
		if rel >= 10.0:
			options.append({"pos": _near(other.global_position, 1.8), "w": 0.6 + rel / 50.0})
	## Places people use
	for group: String in ["chair", "stove", "shelving", "farming_tray", "water_dispenser"]:
		var n: Node = _random_member(npc, group)
		if n != null:
			options.append({"pos": _near((n as Node3D).global_position, 1.5), "w": 0.5})
	if npc.home_bed != null and is_instance_valid(npc.home_bed) and npc.is_night_for_me() == false and randf() < 0.3:
		options.append({"pos": _near((npc.home_bed as Node3D).global_position, 1.6), "w": 0.4})
	var total: float = 0.0
	for o: Dictionary in options:
		total += float(o["w"])
	var roll: float = randf() * total
	for o: Dictionary in options:
		roll -= float(o["w"])
		if roll <= 0.0:
			var p: Vector3 = o["pos"]
			if leisurely:
				## shorter hop toward it
				p = npc.global_position.lerp(p, 0.5)
			return p
	return fallback

static func _near(p: Vector3, radius: float) -> Vector3:
	var a: float = randf() * TAU
	return p + Vector3(cos(a), 0.0, sin(a)) * randf_range(radius * 0.6, radius)

static func _random_member(npc: NPC, group: String) -> Node:
	var members: Array = npc.get_tree().get_nodes_in_group(group)
	if members.is_empty():
		return null
	var n: Node = members[randi() % members.size()]
	return n if is_instance_valid(n) and n is Node3D else null

## While paused: face whoever is nearest (the player counts, and gets
## priority — a resident notices you walking up to them).
func _tick_look(npc: NPC, delta: float) -> void:
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(0.6, 1.4)
		_look_target = null
		var best_d: float = LOOK_RANGE
		var player: Node3D = npc.get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			var pd: float = NPCItemUser.flat_distance(npc.global_position, player.global_position)
			if pd < LOOK_RANGE:
				_look_target = player
				best_d = -1.0
		if _look_target == null:
			for other: Node in npc.get_tree().get_nodes_in_group("npc"):
				if other == npc or not (other is Node3D):
					continue
				var d: float = NPCItemUser.flat_distance(npc.global_position, other.global_position)
				if d < best_d:
					best_d = d
					_look_target = other
	if _look_target != null and is_instance_valid(_look_target):
		npc.face_toward(_look_target.global_position, delta * 4.0)
