extends SitActivity
class_name RelaxSitActivity
## RelaxSitActivity.gd — RelaxActivity's chair option: sit down for a break.
## Stays seated until the owning RelaxActivity's session timer ends (never
## stands up on its own), with reduced energy regen.

const RELAX_ENERGY_REGEN_MULT: float = 0.25

func label() -> String:
	match _state:
		SState.SEEK: return "finding a seat"
		SState.STANDING: return "getting up"
		_: return "sitting"

func score(_npc: NPC) -> float:
	return 0.0   ## delegation-only

func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(npc.energy_cap, npc.energy + ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))

func _should_stand(_npc: NPC) -> bool:
	return false   ## the relax session timer owns the exit
