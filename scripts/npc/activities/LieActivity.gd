extends NPCActivity
class_name LieActivity
## Walk to a precise bed-side approach, then reuse the shared authored
## sit/lie/stand sequence. The CharacterBody root is never reassigned by this
## activity: navigation reaches the animation's starting point and the same
## animation returns to it before normal locomotion resumes.

const LIE_UNTIL_ENERGY: float = 100.0
const ENERGY_REGEN_PER_GAME_HOUR: float = 45.0
const APPROACH_OFFSET: float = 0.4
const ARRIVAL_DISTANCE: float = 0.3

var _bed: Node = null
var _lying: bool = false
var _side: float = 1.0
var _approach_pos: Vector3 = Vector3.ZERO


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
	var candidates: Array[Dictionary] = [
		_bed_slot_candidate(1.0, &"right_side"),
		_bed_slot_candidate(-1.0, &"left_side"),
	]
	var lease: Dictionary = npc.claim_interaction_slot(_bed as Node3D, &"lie",
		APPROACH_OFFSET, candidates)
	if lease.is_empty():
		_bed = null
		return
	_side = 1.0 if StringName(lease.get("slot_id", &"right_side")) == &"right_side" else -1.0
	_approach_pos = npc.get_interaction_slot_position()
	npc.set_nav_target(_approach_pos, NPC.NAV_PRECISE_TARGET_DISTANCE)


func tick(npc: NPC, delta: float) -> void:
	if _bed == null or not is_instance_valid(_bed):
		npc.sleeping_bed = null
		_bed = null
		_lying = false
		npc.release_interaction_slot()
		return
	if _lying:
		_regen_energy(npc, delta)
		return

	npc.nav_steer(delta)
	var approach: Vector3 = _bed_approach_position(npc)
	var flat_dist: float = NPCItemUser.flat_distance(npc.global_position, approach)
	if not npc.nav_failed() and flat_dist < ARRIVAL_DISTANCE:
		if _bed.has_method("npc_try_lie") and _bed.npc_try_lie(npc):
			_begin_lie(npc)
		else:
			_bed = null


func done(npc: NPC) -> bool:
	if _bed == null:
		return true
	return _lying and _should_wake(npc)


func exit(npc: NPC) -> void:
	if _lying:
		## Clearing this property asks AdventurerModelController to run the
		## authored wake/stand sequence back to its captured approach point.
		npc.sleeping_bed = null
	if _bed != null and is_instance_valid(_bed) and _bed.has_method("npc_stand"):
		_bed.npc_stand(npc)
	_lying = false
	_bed = null
	npc.release_interaction_slot()


func _begin_lie(npc: NPC) -> void:
	var t: Transform3D = _bed.get_sheets_transform(_side)
	npc.rotation.y = t.basis.get_euler().y
	var approach_pos: Vector3 = npc.global_position
	var model: Node = npc.get_node_or_null("CharacterModel")
	if model != null:
		model.set("_chair_approach_pos", approach_pos)
		model.set("_chair_seat_pos", Vector3(t.origin.x, approach_pos.y, t.origin.z))
		model.set("_lie_rot_angle", _side * PI * 0.5)
	npc.sleeping_bed = _bed
	npc.lock_movement()
	_lying = true


func _bed_slot_candidate(side: float, slot_id: StringName) -> Dictionary:
	var t: Transform3D = _bed.get_sheets_transform(side)
	return {
		"slot_id": slot_id,
		## Both sides are alternate approaches to the same one-person bed.
		"claim_group": &"bed",
		"transform": Transform3D(t.basis, t.origin + t.basis.z * APPROACH_OFFSET),
	}


func _bed_approach_position(npc: NPC) -> Vector3:
	var approach: Vector3 = _approach_pos
	approach.y = npc.global_position.y
	return approach


func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(100.0, npc.energy
		+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))


func _should_wake(npc: NPC) -> bool:
	return npc.energy >= LIE_UNTIL_ENERGY


func _find_free_bed(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for b: Node in npc.get_tree().get_nodes_in_group("bed"):
		if not is_instance_valid(b):
			continue
		if b.has_method("is_bed_free") and not b.is_bed_free():
			continue
		if npc.is_interaction_slot_claimed_by_other(b as Node3D, &"lie", &"bed"):
			continue
		var b_pos: Vector3 = (b as Node3D).global_position
		if not npc.is_position_compatible_with_companionship(b_pos, 1.0):
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, b_pos)
		if d < best_d:
			best_d = d
			best = b
	return best
