extends RefCounted
class_name PlantDatabase
## PlantDatabase.gd
## ─────────────────────────────────────────────────────────────────────────────
## Pure data table — per-species Farming config. Deliberately a plain
## RefCounted/class_name with only `const`/`static func` (no instance state),
## same "stateless shared helper" shape as WaterQualityColor.gd.
##
## grow_days lives here (not hardcoded in FarmPlant.gd's growth formula)
## specifically so per-species balance can be retuned later without touching
## any growth-math code. Confirmed with Brannon: Tomato = 10 days,
## Onion = 20 days (NOT both 10 — the plan's own placeholder default).

const PLANT_CONFIG: Dictionary = {
	"tomato": {
		"display_name": "Tomato",
		"grow_days":    10.0,
		## Small red SphereMesh (§7 produce model spec).
		"produce_color": Color(0.72, 0.10, 0.09, 1.0),
		"produce_metallic": 0.05,
		"produce_roughness": 0.55,
	},
	"onion": {
		"display_name": "Onion",
		"grow_days":    20.0,
		## Pearl/off-white SphereMesh, subtle sheen — glossier than the tomato.
		"produce_color": Color(0.90, 0.87, 0.80, 1.0),
		"produce_metallic": 0.25,
		"produce_roughness": 0.30,
	},
}

static func get_config(plant_type: String) -> Dictionary:
	return PLANT_CONFIG.get(plant_type, PLANT_CONFIG["tomato"])

static func get_grow_days(plant_type: String) -> float:
	return float(get_config(plant_type).get("grow_days", 10.0))

static func get_display_name(plant_type: String) -> String:
	return String(get_config(plant_type).get("display_name", plant_type.capitalize()))

static func get_produce_color(plant_type: String) -> Color:
	return get_config(plant_type).get("produce_color", Color(0.7, 0.7, 0.7, 1.0))

static func get_produce_metallic(plant_type: String) -> float:
	return float(get_config(plant_type).get("produce_metallic", 0.1))

static func get_produce_roughness(plant_type: String) -> float:
	return float(get_config(plant_type).get("produce_roughness", 0.5))
