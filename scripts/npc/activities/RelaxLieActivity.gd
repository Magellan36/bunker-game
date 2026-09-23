extends LieActivity
class_name RelaxLieActivity
## Relaxing in bed (Aug 2026) — same reasoning as RelaxSitActivity,
## mirrored for beds.
const RELAX_ENERGY_REGEN_MULT: float = 0.25

func label() -> String:
	return "Relaxing (Lying down)" if _lying else "Finding a bed"

func score(_npc: NPC) -> float:
	return 0.0   ## delegation-only

func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(100.0, npc.energy
		+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))

func _should_wake(_npc: NPC) -> bool:
	return false

func done(npc: NPC) -> bool:
	return _bed == null   ## energy is NOT a completion condition here
