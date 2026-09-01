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
##
## The full animated sit-down/stand-up sequence lives in the base
## SitActivity (SEEK -> SEATED -> STANDING); this only scales the regen
## rate and disables the energy-based stand trigger.
const RELAX_ENERGY_REGEN_MULT: float = 0.25

func label() -> String:
	match _state:
		SState.SEEK: return "Finding a seat"
		SState.STANDING: return "Standing up"
		_: return "Relaxing (Sitting)"

func score(_npc: NPC) -> float:
	return 0.0   ## delegation-only

func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(100.0, npc.energy
		+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))

func _should_stand(_npc: NPC) -> bool:
	return false   ## session timer owns the exit, not energy

func done(npc: NPC) -> bool:
	## Base done() returns true when the NPC has stood up and released the
	## chair. For a relax session, that only happens when RelaxActivity ends
	## the session (which calls our exit() and triggers the animated stand-up).
	return _chair == null
