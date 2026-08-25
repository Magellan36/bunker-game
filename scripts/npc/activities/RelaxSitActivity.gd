extends SitActivity
class_name RelaxSitActivity
## Relaxing in a chair (Aug 2026) — delegation-only, never auto-
## selected. Unlike SitActivity, does NOT end just because energy
## reached SIT_UNTIL_ENERGY — without this override, an NPC already
## at/above that energy would sit down, have done()==true the instant
## _seated flips, stand right back up, and loop with RelaxActivity
## re-selecting the same chair every think-cycle. RelaxActivity's own
## session-length timer is what ends this instead. Energy still
## regenerates, just at 1/4 the normal rate — a break, not full rest.
const RELAX_ENERGY_REGEN_MULT: float = 0.25

func label() -> String:
	return "Relaxing (Sitting)" if _seated else "Finding a seat"

func score(_npc: NPC) -> float:
	return 0.0   ## delegation-only

func tick(npc: NPC, delta: float) -> void:
	if _chair == null or not is_instance_valid(_chair):
		_chair = null
		return
	if _seated:
		npc.energy = minf(100.0, npc.energy
			+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
		return
	npc.nav_steer(delta)
	var chair_pos: Vector3 = (_chair as Node3D).global_position
	var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
		.distance_to(Vector2(chair_pos.x, chair_pos.z))
	if npc.nav_finished() or flat_dist < 0.9:
		if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
			_seated = true
			npc.seated_chair = _chair
			var t: Transform3D = _chair.get_seat_transform()
			npc.global_position = t.origin
			npc.rotation.y = t.basis.get_euler().y
			npc.lock_movement()
		else:
			_chair = null   ## someone took it

func done(npc: NPC) -> bool:
	return _chair == null   ## energy is NOT a completion condition here