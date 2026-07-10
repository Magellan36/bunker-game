extends Node
## DeviceDatabase.gd — Stage 9 extraction (review implementation plan)
## ─────────────────────────────────────────────────────────────────────────────
## Autoload singleton. Single source of truth for device balance/config tables
## that used to live as `const` blocks at the top of PowerManager.gd:
## WATT_RATINGS, DEFAULT_PRIORITY_BY_TYPE, GENERATOR_TIERS.
##
## Moved out because this data has nothing to do with the solver — it's pure
## config, and it was growing PowerManager.gd for reasons unrelated to grid
## logic every time a new device type was added. Now any system (build shop
## UI, device _ready() scripts, PowerRegistry, etc.) can read balance data
## straight from this autoload without a PowerManager dependency at all.
##
## Verified (July 2026) that WATT_RATINGS and GENERATOR_TIERS had ZERO other
## code call sites anywhere in the repo at time of extraction — every device
## script passes its own hardcoded watts value to register_consumer/
## register_generator directly, and BuildModeController's generator tiers are
## a separate hardcoded table, not wired to GENERATOR_TIERS. Only
## DEFAULT_PRIORITY_BY_TYPE had a real caller (PowerRegistry.gd,
## register_consumer's priority-0 fallback), updated to point here.
##
## Values copied verbatim from PowerManager.gd — no balance numbers changed.

# ─── Watt ratings (single source of truth) ───────────────────────────────────
## BuildModeController and device _ready() scripts should pull from here.
const WATT_RATINGS: Dictionary = {
	## Lighting
	"wall_light":           40.0,
	"bed_lamp":             15.0,
	"emergency_light":       8.0,
	"grow_light":           80.0,
	## Security / Comms
	"security_camera":      10.0,
	"radio":                20.0,
	"comms_terminal":       60.0,
	## Appliances
	"small_fan":            35.0,
	"refrigerator":        150.0,
	"water_purifier":      200.0,
	"ventilation_unit":    300.0,
	"medical_station":     120.0,
	"defibrillator":       500.0,
	"workshop_tools":      500.0,
	"electric_stove":      180.0,
	"microwave":            90.0,
	"coffee_maker":         40.0,
	"washer":              200.0,
	## Infrastructure
	"water_pump":          180.0,
	"air_recycler":        220.0,
	"blast_door_motor":    150.0,
	"elevator_motor":      400.0,
	## Test / debug
	"heavy_appliance":     500.0,
}

## Default priority per type tag. 1 = life-support, 5 = luxury.
const DEFAULT_PRIORITY_BY_TYPE: Dictionary = {
	"air_recycler":         1,
	"defibrillator":        1,
	"emergency_light":      1,
	"medical_station":      2,
	"water_pump":           2,
	"blast_door_motor":     2,
	"security_camera":      2,
	"water_purifier":       3,
	"wall_light":           3,
	"ventilation_unit":     3,
	"refrigerator":         3,
	"radio":                4,
	"grow_light":           4,
	"small_fan":            4,
	"electric_stove":       4,
	"microwave":            5,
	"coffee_maker":         5,
	"workshop_tools":       5,
	"washer":               5,
	"heavy_appliance":      2,
}

## Generator upgrade tiers — indexed by shop/upgrade system.
const GENERATOR_TIERS: Array[Dictionary] = [
	{ "name": "Starter Generator",    "watts": 800.0,  "price": 0     },
	{ "name": "Mid-Range Generator",  "watts": 2000.0, "price": 3500  },
	{ "name": "Industrial Generator", "watts": 5000.0, "price": 12000 },
]
