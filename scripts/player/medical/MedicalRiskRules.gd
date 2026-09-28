extends RefCounted
## Shared value-only rules. Callers supply local device facts, never infer
## electrical danger from the bunker-wide OFFLINE/ONLINE label.
const LEG_ACCIDENT_RATE: float = 0.018
const ARM_ACCIDENT_RATE: float = 0.026
const MIN_MOVEMENT_MULT: float = 0.35
const MIN_WORK_MULT: float = 0.35
const MAX_STAMINA_MULT: float = 5.0

static func electrical_chance(generator: bool, tripped: bool, health: float = 100.0) -> float:
	var wear: float = clampf((50.0 - health) / 50.0, 0.0, 1.0) if generator else 0.0
	if not tripped and wear <= 0.0:
		return 0.0
	return (0.08 if generator else 0.04) + wear * 0.08

static func electrical_warning(generator: bool, tripped: bool, health: float = 100.0) -> String:
	var chance: float = electrical_chance(generator, tripped, health)
	if chance <= 0.0:
		return ""
	var reason: String = "Damaged generator" if generator and health < 50.0 else "Tripped circuit"
	return "%s — restart burn risk %d%%" % [reason, roundi(chance * 100.0)]

static func accident_probability(leg_dose: float, arm_dose: float) -> float:
	return 1.0 - exp(-(LEG_ACCIDENT_RATE * leg_dose + ARM_ACCIDENT_RATE * arm_dose))
