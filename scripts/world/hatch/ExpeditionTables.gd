extends RefCounted
class_name ExpeditionTables
## ExpeditionTables.gd
## Pure data for surface expeditions sent out through the Surface Hatch.
## Tuning lives here; the rules that read it live in ExpeditionResolver.gd and
## the hatch/NPC hand-off lives in SurfaceHatch.gd. See docs/systems/hatch/README.md.
##
## Every number is a first-pass ballpark pending playtesting, same convention
## as the medical tuning constants.

## ── Destinations ─────────────────────────────────────────────────────────────
## hours      : planned round trip in game hours (before approach scaling)
## encounters : how many times the trip rolls against `danger`
## danger     : base chance (0..1) that one encounter goes wrong
## loot_rolls : [min, max] item draws before approach/depletion scaling
## hazards    : hazard id -> weight (see HAZARDS)
## loot       : loot id -> weight (see LOOT_ITEMS)
## requires   : destination id that must have been visited once to reveal it
##              ("" = known from day one). The reveal is written into the
##              report so the player can see why a new place appeared.
const DESTINATIONS: Dictionary = {
	"gas_station": {
		"name": "Gas Station",
		"blurb": "Close by and mostly stripped. Fuel residue, snacks, junk.",
		"hours": 6.0, "encounters": 2, "danger": 0.16, "loot_rolls": [2, 4],
		"requires": "",
		"hazards": {"glass": 3, "chemical": 3, "exposure": 2, "dog": 1},
		"loot": {"fuel_can": 5, "food_can": 3, "water_bottle": 2, "scrap_plastic": 4, "scrap_metal": 3, "flashlight": 1},
	},
	"row_houses": {
		"name": "Row Houses",
		"blurb": "Abandoned homes. Pantries, garden sheds, rotten floors.",
		"hours": 8.0, "encounters": 3, "danger": 0.2, "loot_rolls": [3, 5],
		"requires": "",
		"hazards": {"fall": 4, "glass": 3, "dog": 2, "exposure": 1},
		"loot": {"food_can": 5, "water_bottle": 4, "seed": 3, "soil": 1, "bandage": 1, "scrap_paper": 3, "flashlight": 1},
	},
	"pharmacy": {
		"name": "Pharmacy",
		"blurb": "Picked over, but back rooms may still hold medicine.",
		"hours": 12.0, "encounters": 3, "danger": 0.3, "loot_rolls": [2, 4],
		"requires": "row_houses",
		"hazards": {"scavengers": 4, "glass": 3, "chemical": 1, "exposure": 1},
		"loot": {"bandage": 5, "antibiotics": 3, "splint": 3, "trauma_kit": 1, "water_bottle": 2, "scrap_plastic": 2},
	},
	"hardware_store": {
		"name": "Hardware Store",
		"blurb": "Heavy shelving, collapsed aisles. Tools, filters, garden supply.",
		"hours": 12.0, "encounters": 3, "danger": 0.28, "loot_rolls": [2, 4],
		"requires": "gas_station",
		"hazards": {"fall": 4, "chemical": 3, "glass": 2, "scavengers": 1},
		"loot": {"purifier_filter": 3, "fertilizer": 3, "soil": 3, "seed": 2, "fuel_can": 2, "scrap_metal": 4},
	},
	"field_hospital": {
		"name": "Field Hospital",
		"blurb": "An army aid station. Well stocked. Other survivors know it too.",
		"hours": 20.0, "encounters": 4, "danger": 0.42, "loot_rolls": [3, 6],
		"requires": "pharmacy",
		"hazards": {"scavengers": 5, "exposure": 3, "glass": 2, "fall": 1},
		"loot": {"trauma_kit": 3, "antibiotics": 4, "splint": 3, "bandage": 4, "food_can": 2, "water_bottle": 2},
	},
}

## Stable display order for UI.
const DESTINATION_ORDER: Array[String] = [
	"gas_station", "row_houses", "hardware_store", "pharmacy", "field_hospital",
]

## ── Approach (the main risk/reward dial the player sets) ────────────────────
const APPROACHES: Dictionary = {
	"careful":  {"name": "Careful",  "blurb": "Stay on known routes. Less loot, fewer injuries.", "hours_mult": 1.25, "danger_mult": 0.55, "loot_mult": 0.65},
	"balanced": {"name": "Balanced", "blurb": "Search what's safe to reach.",                      "hours_mult": 1.0,  "danger_mult": 1.0,  "loot_mult": 1.0},
	"greedy":   {"name": "Greedy",   "blurb": "Push into every room. Big haul, big risk.",         "hours_mult": 1.15, "danger_mult": 1.6,  "loot_mult": 1.55},
}
const APPROACH_ORDER: Array[String] = ["careful", "balanced", "greedy"]

## ── Hazards → existing medical conditions ────────────────────────────────────
## Every hazard maps onto a condition that already exists in NPCMedical, so a
## returning resident is treated with the same Bandage / Antibiotics / Splint
## loop as any other injury. `injury`: open_wound | fractured | burn | none.
## `parts`: body parts the injury may land on (MedicalCondition.BodyPart
## names). `needs`: flat drain applied on top of the trip's normal drain.
## `loot_loss`: fraction of the haul lost when this hazard fires.
const HAZARDS: Dictionary = {
	"glass":      {"text": "cut %s on broken glass",               "injury": "open_wound", "parts": ["LEFT_ARM", "RIGHT_ARM"]},
	"fall":       {"text": "fell through a rotted floor",           "injury": "fractured",  "parts": ["LEFT_LEG", "RIGHT_LEG"]},
	"chemical":   {"text": "was splashed by something caustic",     "injury": "burn",       "parts": ["LEFT_ARM", "RIGHT_ARM", "HEAD"]},
	"dog":        {"text": "was bitten by a feral dog",             "injury": "open_wound", "parts": ["LEFT_LEG", "RIGHT_LEG"]},
	"scavengers": {"text": "ran into scavengers and had to fight clear", "injury": "open_wound", "parts": ["TORSO", "LEFT_ARM", "RIGHT_ARM"], "loot_loss": 0.5},
	"exposure":   {"text": "got caught out in the ash and cold",   "injury": "none",       "parts": [], "needs": {"energy": 30.0, "thirst": 20.0, "health": 10.0}},
}

## ── Loot → real item specs (ItemSaveData.spawn format) ──────────────────────
## `state` values that are [min, max] pairs are rolled per item. Found water is
## surface water: low quality on purpose, so the purifier matters.
const LOOT_ITEMS: Dictionary = {
	"food_can":        {"name": "Canned food",      "scene": "res://scenes/world/FoodCan.tscn"},
	"water_bottle":    {"name": "Water (untreated)", "scene": "res://scenes/world/WaterBottle.tscn", "state": {"fill": [250.0, 750.0], "quality": [15.0, 60.0]}},
	"bandage":         {"name": "Bandage",          "scene": "res://scenes/world/Bandage.tscn"},
	"antibiotics":     {"name": "Antibiotics",      "scene": "res://scenes/world/Antibiotics.tscn"},
	"splint":          {"name": "Splint",           "scene": "res://scenes/world/Splint.tscn"},
	"trauma_kit":      {"name": "Trauma kit",       "scene": "res://scenes/world/TraumaKit.tscn"},
	"fuel_can":        {"name": "Fuel can",         "scene": "res://scenes/world/FuelCan.tscn", "state": {"fuel": [20.0, 70.0], "empty": false}},
	"flashlight":      {"name": "Flashlight",       "scene": "res://scenes/world/Flashlight.tscn", "state": {"battery": [10.0, 60.0], "is_dead": false}},
	"purifier_filter": {"name": "Purifier filter",  "scene": "res://scenes/world/PurifierFilterItem.tscn"},
	"seed":            {"name": "Seeds",            "script": "res://scripts/world/items/SeedItem.gd", "state": {"seed_type": "@seed", "charges": [1, 4]}},
	"fertilizer":      {"name": "Fertilizer",       "script": "res://scripts/world/items/FertilizerItem.gd", "state": {"tier": "normal", "charges": [1, 4]}},
	"soil":            {"name": "Bag of soil",      "script": "res://scripts/world/items/BagOfSoilItem.gd"},
	"scrap_plastic":   {"name": "Plastic scrap",    "script": "res://scripts/world/items/EmptyBagItem.gd"},
	"scrap_paper":     {"name": "Paper scrap",      "script": "res://scripts/world/items/EmptySeedBagItem.gd"},
	"scrap_metal":     {"name": "Metal scrap",      "scene": "res://scenes/world/FoodCan.tscn", "state": {"bites": 0, "empty": true}},
}

## Seed types a scavenged packet can hold (subset of PlantDatabase).
const SEED_TYPES: Array[String] = ["tomato", "onion", "potato", "carrot", "garlic", "basil"]

## ── Resident modifiers ───────────────────────────────────────────────────────
const MIN_HEALTH_TO_SEND: float = 35.0
const MIN_ENERGY_TO_SEND: float = 20.0
## A hurt or tired resident is more likely to get hurt again.
const LOW_HEALTH_DANGER_BONUS: float = 0.12   ## at MIN_HEALTH_TO_SEND, fading to 0 at 100
const LOW_ENERGY_DANGER_BONUS: float = 0.08   ## at MIN_ENERGY_TO_SEND, fading to 0 at 100
## Level-Headed (high resilience) residents keep calm; Neurotic ones panic.
const RESILIENCE_DANGER_SWING: float = 0.06
const NEUROTIC_DANGER_SWING: float = 0.05
## Probability ceiling so no single encounter is ever a sure thing.
const MAX_ENCOUNTER_DANGER: float = 0.85

## ── Loyalty (relationship with the player, -100..100) ──────────────────────
const SKIM_BELOW: float = -15.0      ## below this they may keep part of the haul
const SKIM_FRACTION: float = 0.35
const DESERT_BELOW: float = -40.0    ## below this they may not come back at all
const DESERT_CHANCE_PER_POINT: float = 0.006
const DESERT_CHANCE_MAX: float = 0.35

## ── Bad trips ────────────────────────────────────────────────────────────────
## Two or more hazards can pin a resident down: they come back late.
const DELAY_CHANCE_PER_EXTRA_HAZARD: float = 0.35
const DELAY_HOURS_MULT: Array[float] = [0.4, 0.9]
## Three or more hazards on one trip can mean they never make it home.
const LOST_MIN_HAZARDS: int = 3
const LOST_CHANCE: float = 0.3
## A resident presumed lost/deserted is written off this long after they were due.
const WRITE_OFF_AFTER_HOURS: float = 36.0

## ── Trip upkeep ──────────────────────────────────────────────────────────────
## Fraction of the normal NPC drain applied over the trip (they forage and
## ration on the way). NPC drain rates: hunger 1.39/h, thirst 2.08/h.
const TRIP_NEED_DRAIN_MULT: float = 0.6
const NPC_HUNGER_PER_HOUR: float = 1.39
const NPC_THIRST_PER_HOUR: float = 2.08
const NPC_ENERGY_PER_HOUR: float = 1.6
const NEED_FLOOR_ON_RETURN: float = 5.0

## ── Depletion (entropy for the surface) ──────────────────────────────────────
## Every run strips a destination a little more; it slowly refills as the
## world shifts (other survivors move on, rubble settles, new stock washes in).
const DEPLETION_PER_VISIT: float = 0.18
const DEPLETION_RECOVERY_PER_DAY: float = 0.04
const DEPLETION_MAX: float = 0.75

## ── Hatch ────────────────────────────────────────────────────────────────────
const MAX_ACTIVE_EXPEDITIONS: int = 2
const MAX_REPORTS: int = 8
