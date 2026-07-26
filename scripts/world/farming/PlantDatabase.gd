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
## any growth-math code.
##
## `category` is cosmetic/organizational only (Vegetable/Fruit/Herb) — not
## read by any gameplay logic, just future-proofing for a possible tabbed
## shop UI later.
## `seed_packet_color` drives SeedItem.gd's placeholder mesh tint — every
## species must have one or seed packets render visually identical.

const PLANT_CONFIG: Dictionary = {
	"tomato": {
		"display_name": "Tomato", "grow_days": 5.0, "category": "Vegetable",
		## Small red SphereMesh (§7 produce model spec).
		"produce_color": Color(0.72, 0.10, 0.09, 1.0), "produce_metallic": 0.05, "produce_roughness": 0.55,
		"seed_packet_color": Color(0.85, 0.65, 0.25, 1.0),
	},
	"onion": {
		"display_name": "Onion", "grow_days": 10.0, "category": "Vegetable",
		## Pearl/off-white SphereMesh, subtle sheen — glossier than the tomato.
		"produce_color": Color(0.90, 0.87, 0.80, 1.0), "produce_metallic": 0.25, "produce_roughness": 0.30,
		"seed_packet_color": Color(0.75, 0.78, 0.55, 1.0),
	},
	"basil": {
		"display_name": "Basil", "grow_days": 2.5, "category": "Herb",
		"produce_color": Color(0.20, 0.55, 0.18, 1.0), "produce_metallic": 0.10, "produce_roughness": 0.25,
		"seed_packet_color": Color(0.35, 0.60, 0.30, 1.0),
	},
	"strawberry": {
		"display_name": "Strawberry", "grow_days": 3.5, "category": "Fruit",
		"produce_color": Color(0.80, 0.08, 0.20, 1.0), "produce_metallic": 0.05, "produce_roughness": 0.20,
		"seed_packet_color": Color(0.90, 0.55, 0.60, 1.0),
	},
	"carrot": {
		"display_name": "Carrot", "grow_days": 4.0, "category": "Vegetable",
		"produce_color": Color(0.88, 0.45, 0.08, 1.0), "produce_metallic": 0.0, "produce_roughness": 0.70,
		"seed_packet_color": Color(0.80, 0.55, 0.30, 1.0),
	},
	"chili_pepper": {
		"display_name": "Chili Pepper", "grow_days": 4.5, "category": "Herb",
		"produce_color": Color(0.78, 0.18, 0.05, 1.0), "produce_metallic": 0.05, "produce_roughness": 0.25,
		"seed_packet_color": Color(0.70, 0.30, 0.20, 1.0),
	},
	"bell_pepper": {
		"display_name": "Bell Pepper", "grow_days": 6.0, "category": "Vegetable",
		"produce_color": Color(0.75, 0.12, 0.10, 1.0), "produce_metallic": 0.05, "produce_roughness": 0.22,
		"seed_packet_color": Color(0.70, 0.45, 0.35, 1.0),
	},
	"garlic": {
		"display_name": "Garlic", "grow_days": 7.0, "category": "Vegetable",
		"produce_color": Color(0.88, 0.85, 0.88, 1.0), "produce_metallic": 0.15, "produce_roughness": 0.40,
		"seed_packet_color": Color(0.70, 0.65, 0.72, 1.0),
	},
	"potato": {
		"display_name": "Potato", "grow_days": 8.0, "category": "Vegetable",
		"produce_color": Color(0.62, 0.48, 0.30, 1.0), "produce_metallic": 0.0, "produce_roughness": 0.85,
		"seed_packet_color": Color(0.55, 0.42, 0.28, 1.0),
	},
	"blueberry": {
		"display_name": "Blueberry", "grow_days": 9.0, "category": "Fruit",
		"produce_color": Color(0.16, 0.16, 0.42, 1.0), "produce_metallic": 0.10, "produce_roughness": 0.20,
		"seed_packet_color": Color(0.30, 0.30, 0.55, 1.0),
	},
	"corn": {
		"display_name": "Corn", "grow_days": 11.0, "category": "Vegetable",
		"produce_color": Color(0.95, 0.80, 0.15, 1.0), "produce_metallic": 0.0, "produce_roughness": 0.60,
		"seed_packet_color": Color(0.85, 0.75, 0.30, 1.0),
	},
	"pumpkin": {
		"display_name": "Pumpkin", "grow_days": 15.0, "category": "Fruit",
		"produce_color": Color(0.85, 0.42, 0.05, 1.0), "produce_metallic": 0.0, "produce_roughness": 0.65,
		"seed_packet_color": Color(0.75, 0.50, 0.20, 1.0),
	},
}

static func get_config(plant_type: String) -> Dictionary:
	return PLANT_CONFIG.get(plant_type, PLANT_CONFIG["tomato"])

static func get_grow_days(plant_type: String) -> float:
	return float(get_config(plant_type).get("grow_days", 10.0))

static func get_display_name(plant_type: String) -> String:
	return String(get_config(plant_type).get("display_name", plant_type.capitalize()))

static func get_category(plant_type: String) -> String:
	return String(get_config(plant_type).get("category", "Vegetable"))

static func get_produce_color(plant_type: String) -> Color:
	return get_config(plant_type).get("produce_color", Color(0.7, 0.7, 0.7, 1.0))

static func get_produce_metallic(plant_type: String) -> float:
	return float(get_config(plant_type).get("produce_metallic", 0.1))

static func get_produce_roughness(plant_type: String) -> float:
	return float(get_config(plant_type).get("produce_roughness", 0.5))

static func get_seed_packet_color(plant_type: String) -> Color:
	return get_config(plant_type).get("seed_packet_color", Color(0.7, 0.7, 0.7, 1.0))
