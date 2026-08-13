extends LieActivity
class_name RelaxLieActivity
## Relaxing in bed (Aug 2026) — same reasoning as RelaxSitActivity,
## mirrored for beds.
const RELAX_ENERGY_REGEN_MULT: float = 0.25

func label() -> String:
	return "Relaxing (Lying down)" if _lying else "Finding a bed"

func score(_npc: NPC) -> float:
	return 0.0   ## delegation-only

func tick(npc: NPC, delta: float) -> void:
	if _bed == null or not is_instance_valid(_bed):
		_bed = null
		return
	if _lying:
		npc.energy = minf(100.0, npc.energy
			+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
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
			_bed = null   ## someone took it

func done(npc: NPC) -> bool:
	return _bed == null   ## energy is NOT a completion condition here