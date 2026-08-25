extends NPCActivity
class_name SitActivity
## Walk to the nearest free chair, sit, recover Energy, stand when rested.
const SIT_UNTIL_ENERGY: float = 90.0
const ENERGY_REGEN_PER_GAME_HOUR: float = 25.0

var _chair: Node = null
var _seated: bool = false

func label() -> String:
	return "Resting" if _seated else "Finding a seat"

func score(npc: NPC) -> float:
	if npc.energy >= 60.0:
		return 0.0
	if _find_free_chair(npc) == null:
		return 0.0
	return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()   ## 40..100 as energy falls 60→0

func interruptible() -> bool:
	return not _seated   ## once seated, finish resting (Part 4 jobs can
	                     ## still out-wait it; nothing urgent exists yet)

func enter(npc: NPC) -> void:
	_chair = _find_free_chair(npc)
	_seated = false
	if _chair == null:
		return
	npc.set_nav_target((_chair as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _chair == null or not is_instance_valid(_chair):
		_chair = null
		return
	if _seated:
		npc.energy = minf(100.0, npc.energy
			+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))
		return
	npc.nav_steer(delta)
	var chair_pos: Vector3 = (_chair as Node3D).global_position
	var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
		.distance_to(Vector2(chair_pos.x, chair_pos.z))
	if npc.nav_finished() or flat_dist < 0.9:
		## Claim + snap onto the seat (mirrors the player seat flow in
		## MainWorld._wire_chair, minus the physics-process freeze —
		## the NPC just parks with zero velocity).
		if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
			_seated = true
			npc.seated_chair = _chair
			var t: Transform3D = _chair.get_seat_transform()
			npc.global_position = t.origin
			npc.rotation.y = t.basis.get_euler().y
			npc.lock_movement()
		else:
			_chair = null   ## someone took it — done() ends us; rescore

func done(npc: NPC) -> bool:
	if _chair == null:
		return true
	return _seated and npc.energy >= SIT_UNTIL_ENERGY

func exit(npc: NPC) -> void:
	if _seated and _chair != null and is_instance_valid(_chair):
		if _chair.has_method("npc_stand"):
			_chair.npc_stand(npc)
		npc.global_position = _chair.get_stand_position()
	_seated = false
	npc.seated_chair = null
	_chair = null

func _find_free_chair(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for c: Node in npc.get_tree().get_nodes_in_group("chair"):
		if not is_instance_valid(c):
			continue
		if c.has_method("is_seat_free") and not c.is_seat_free():
			continue
		var c_pos: Vector3 = (c as Node3D).global_position
		var d: float = Vector2(c_pos.x, c_pos.z) \
			.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
		if d < best_d:
			best_d = d
			best = c
	return best