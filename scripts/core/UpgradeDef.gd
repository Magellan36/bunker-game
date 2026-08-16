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

## Override per upgrade. Called exactly once, the instant research completes.
func apply_effect() -> void:
	pass