extends RefCounted
class_name NPCBehaviorProfile
## Stable, low-dimensional behavior signature derived from an NPC's saved
## generation seed and existing personality. This changes timing and leisure
## preferences, never core need thresholds or job correctness.

const LANDMARK_GROUPS: Array[StringName] = [
	&"stove", &"farming_tray", &"shelving", &"generator", &"interactable_static",
]

var patience: float = 0.5
var restlessness: float = 0.5
var novelty_seeking: float = 0.5
var sitting_affinity: float = 0.5
var preferred_social_distance: float = 1.2
var movement_tempo: float = 1.0
var preferred_landmark_group: StringName = &""
var agenda_min_beats: int = 2
var agenda_max_beats: int = 4


func setup(generation_seed: int, personality: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	## Keep this stream independent from global gameplay randomness. The xor
	## salt also prevents a generation seed reused elsewhere from reproducing
	## the same first values by accident.
	rng.seed = generation_seed ^ 0x4E504342
	var sociability: float = clampf(float(personality.get("sociability", 0.5)), 0.0, 1.0)
	var work_ethic: float = clampf(float(personality.get("work_ethic", 0.5)), 0.0, 1.0)
	var resilience: float = clampf(float(personality.get("resilience", 0.5)), 0.0, 1.0)
	patience = clampf(lerpf(rng.randf_range(0.25, 0.75), resilience, 0.35), 0.0, 1.0)
	restlessness = clampf(lerpf(rng.randf_range(0.2, 0.8), work_ethic, 0.25), 0.0, 1.0)
	novelty_seeking = rng.randf_range(0.15, 0.9)
	sitting_affinity = clampf(lerpf(rng.randf_range(0.15, 0.9), 1.0 - work_ethic, 0.35), 0.0, 1.0)
	preferred_social_distance = lerpf(1.55, 0.95, sociability)
	movement_tempo = lerpf(0.92, 1.06, restlessness)
	preferred_landmark_group = LANDMARK_GROUPS[rng.randi_range(0, LANDMARK_GROUPS.size() - 1)]
	agenda_min_beats = 2
	agenda_max_beats = 3 if restlessness < 0.35 else 4


func debug_info() -> Dictionary:
	return {
		"patience": patience,
		"restlessness": restlessness,
		"novelty_seeking": novelty_seeking,
		"sitting_affinity": sitting_affinity,
		"preferred_social_distance": preferred_social_distance,
		"movement_tempo": movement_tempo,
		"preferred_landmark_group": String(preferred_landmark_group),
	}
