extends NPCActivity
class_name LieActivity
## Walk to the nearest free bed, lie down (rotated horizontal via
## Bed.get_lie_transform()), recover Energy faster and further than a
## chair (proper rest vs a quick break), stand when fully rested.
## Structurally mirrors SitActivity — see that class for the reasoning
## behind the XZ-flattened arrival check (Part 12) and lock_movement()
## at the transition instant (Part 13).
const LIE_UNTIL_ENERGY: float = 100.0
const ENERGY_REGEN_PER_GAME_HOUR: float = 45.0

var _bed: Node = null
var _lying: bool = false
var _orig_rotation: Vector3 = Vector3.ZERO

func label() -> String:
	return "Sleeping" if _lying else "Finding a bed"

func score(npc: NPC) -> float:
	if npc.energy >= 60.0:
		return 0.0
	if _find_free_bed(npc) == null:
		return 0.0
	return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()
func interruptible() -> bool:
	return not _lying

func enter(npc: NPC) -> void:
	_bed = _find_free_bed(npc)
	_lying = false
	if _bed == null:
		return
	npc.set_nav_target((_bed as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _bed == null or not is_instance_valid(_bed):
		_bed = null
		return
	if _lying:
		npc.energy = minf(100.0, npc.energy
			+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))
		return
	npc.nav_steer(delta)
	var bed_pos: Vector3 = (_bed as Node3D).global_position
	var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
		.distance_to(Vector2(bed_pos.x, bed_pos.z))
	if npc.nav_finished() or flat_dist < 1.1:
		if _bed.has_method("npc_try_lie") and _bed.npc_try_lie(npc):
			_lying = true
			_orig_rotation = npc.rotation
			npc.lock_movement()
			var t: Transform3D = _bed.get_lie_transform()
			npc.global_position = t.origin
			npc.rotation = t.basis.get_euler()
		else:
			_bed = null   ## someone took it — done() ends us; rescore

func done(npc: NPC) -> bool:
	if _bed == null:
		return true
	return _lying and npc.energy >= LIE_UNTIL_ENERGY

func exit(npc: NPC) -> void:
	if _lying and _bed != null and is_instance_valid(_bed):
		if _bed.has_method("npc_stand"):
			_bed.npc_stand(npc)
		npc.global_position = _bed.get_bed_stand_position()
		npc.rotation = _orig_rotation   ## restore upright orientation
	_lying = false
	_bed = null

func _find_free_bed(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for b: Node in npc.get_tree().get_nodes_in_group("bed"):
		if not is_instance_valid(b):
			continue
		if b.has_method("is_bed_free") and not b.is_bed_free():
			continue
		var b_pos: Vector3 = (b as Node3D).global_position
		var d: float = Vector2(b_pos.x, b_pos.z) \
			.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
		if d < best_d:
			best_d = d
			best = b
	return best