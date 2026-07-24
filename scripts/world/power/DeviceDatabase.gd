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
	## Farming (Jul 2026) — two grow-light tiers, replacing the old single
	## unused "grow_light" placeholder entry (confirmed zero call sites before
	## removal; GrowLight.gd carries its own TIER_WATTS table and never reads
	## this dict directly, same as every other device script in this project —
	## kept here purely so build-shop UI/balance tooling can read it).
	"grow_light_normal":    75.0,
	"grow_light_pro":      100.0,
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
	"wall_light":           1,   ## kept in sync with WallLight.gd's own power_priority default
	"ventilation_unit":     3,
	"refrigerator":         3,
	"radio":                4,
	## Farming (Jul 2026) — both grow-light tiers default to priority 3
	## ("start at 3 like usual", both player-tier-adjustable via the existing
	## generic priority-change flow — no new UI needed for this).
	"grow_light_normal":    3,
	"grow_light_pro":       3,
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

# ─── Status-indicator emission color convention (graphics plan Section 3) ───
## Standardized green/amber/red convention for any device's status LED/
## indicator: green = running/healthy, amber = warning/brownout,
## red = fault/tripped/stopped. Intended for NEW devices going forward —
## BreakerBox.gd/BatteryBank.gd/GeneratorObject.gd already have their own
## tuned, independently-working `COLOR_LED_*`/`COLOR_STOPPED`/etc. constants
## and are deliberately NOT retrofitted to this table in this pass (real
## regression risk on the most load-bearing, heavily-tested system in the
## project, for a pure-consistency win with no functional payoff — same
## reasoning PROJECT_SUMMARY.md §13 already applies to the hand-drawn-UI
## retrofit question). Point new device scripts here; leave the three
## existing ones alone unless explicitly asked to unify them.
const STATE_EMISSION_COLORS: Dictionary = {
	"healthy": Color(0.15, 0.90, 0.20, 1.0),   ## green
	"warning": Color(1.00, 0.72, 0.10, 1.0),   ## amber
	"fault":   Color(0.95, 0.15, 0.10, 1.0),   ## red
}


## Looks up a status-tag color, defaulting to "fault" red for unknown tags
## so a typo'd tag fails loud (bright red) rather than silently invisible.
static func get_status_emission_color(tag: String) -> Color:
	return STATE_EMISSION_COLORS.get(tag, STATE_EMISSION_COLORS["fault"])


# ─── Player zone-color picker palette (July 2026) ────────────────────────────
## The fixed set of 16 swatches ZoneCustomizeUI.gd's color picker offers the
## player when recoloring a wire zone via its Power Terminal. Deliberately
## SEPARATE from PowerManager.ZONE_COLORS (the smaller, auto-assigned
## graph-coloring palette) — this is a much larger, purely player-facing
## choice set and has no adjacency-distinctness constraint to satisfy (a
## player's chosen zone color is allowed to match a neighboring zone; see
## PowerManager.set_zone_color_override()). 16 hues evenly spaced around the
## color wheel at fixed high saturation/value so all 16 read as clearly
## distinct swatches in the picker grid.
const ZONE_PLAYER_COLOR_CHOICES: Array[Color] = [
	Color(0.95, 0.14, 0.14, 1.0),   ##  0 red
	Color(0.95, 0.45, 0.14, 1.0),   ##  1 orange
	Color(0.95, 0.75, 0.14, 1.0),   ##  2 amber/gold
	Color(0.85, 0.95, 0.14, 1.0),   ##  3 yellow-green
	Color(0.55, 0.95, 0.14, 1.0),   ##  4 lime
	Color(0.24, 0.95, 0.14, 1.0),   ##  5 green
	Color(0.14, 0.95, 0.34, 1.0),   ##  6 spring green
	Color(0.14, 0.95, 0.65, 1.0),   ##  7 teal-green
	Color(0.14, 0.95, 0.95, 1.0),   ##  8 cyan
	Color(0.14, 0.65, 0.95, 1.0),   ##  9 sky blue
	Color(0.14, 0.34, 0.95, 1.0),   ## 10 blue
	Color(0.24, 0.14, 0.95, 1.0),   ## 11 indigo
	Color(0.55, 0.14, 0.95, 1.0),   ## 12 violet
	Color(0.85, 0.14, 0.95, 1.0),   ## 13 magenta
	Color(0.95, 0.14, 0.75, 1.0),   ## 14 pink
	Color(0.95, 0.14, 0.45, 1.0),   ## 15 rose
]

