extends Resource
class_name UpgradeDef
## UpgradeDef.gd
## Aug 2026 — minimal stub per design direction: the data shape for a single
## upgrade, established now so next pass's real buttons/content have
## something to target. NOT instantiated or referenced anywhere yet — no
## actual upgrades are defined, no feed/consumption logic exists. Fields are
## a first-pass guess at what an upgrade needs; expect this to grow.

@export var id: String            = ""
@export var display_name: String  = ""
@export var tree: String          = ""   ## "bunker" / "player_skills" / "npc_skills"
@export var duration_seconds: float = 0.0
@export var material_costs: Dictionary = {}   ## e.g. {"metal": 5, "plastic": 2} — keys match get_trash_material()'s return values
@export var completed: bool       = false