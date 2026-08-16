extends Resource
class_name UpgradeDef
## UpgradeDef.gd
## Base class for every upgrade in the game. Plain data fields are shared/
## generic (name, tree, duration, material cost) — the actual EFFECT is the
## one thing that legitimately differs per upgrade, so it's a virtual method
## subclasses override. "Mass-producible": a new upgrade is a tiny subclass
## (just apply_effect()) + a .tres resource instance with the data fields
## filled in — the runtime/UI code (ResearchStation, ResearchStationUI)
## never has per-upgrade special-casing anywhere.

@export var id: String              = ""
@export var display_name: String    = ""
@export var tree: String            = ""   ## "bunker" / "player_skills" / "npc_skills"
@export var duration_seconds: float = 10.0
@export var material_costs: Dictionary = {}   ## e.g. {"metal": 5, "plastic": 5} — keys match get_trash_material()'s return values

## Total completions in this chain. Flat cost/duration across all tiers
## this pass (per direction — balance later).
@export var max_tier: int = 1

## Called once per tier completion, passed the tier number JUST reached
## (1-indexed). Direct-set semantics expected: subclasses should SET the
## external system to match tier_reached, not increment it relative to
## unknown prior state — the station is the authoritative progress tracker,
## effects just sync external systems to match it.
func apply_effect(tier_reached: int) -> void:
	pass

## Override when a chain's true tier count should be computed from the
## external system it drives, rather than a static exported number (e.g.
## Water Hookup's tier count comes from WaterHookup's own array size, not a
## number I'd have to keep in sync by hand in a .tres file). Defaults to
## the static export.
func get_max_tier() -> int:
	return max_tier