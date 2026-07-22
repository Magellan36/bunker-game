extends RefCounted
class_name WaterQualityColor
## WaterQualityColor.gd
## ─────────────────────────────────────────────────────────────────────────────
## Shared red/yellow/green water-quality color helper (Jul 2026, extracted
## per the purifier-pulse/dispenser-fill plan's own flagged scope addition).
## Previously duplicated near-verbatim in WaterInfoUI.gd (_draw_quality_row())
## and WaterDispenserUI.gd (_quality_color()) — both now delegate here instead
## of keeping their own copy. Also the color source for the new pipe-flow
## dual-arrow quality lane (WaterManager._process_purity_and_dual_arrows()).
##
## Thresholds (inclusive boundaries, Brannon's explicit spec, unchanged from
## the original two copies): 0-50% red, 50.01-75% yellow, 75.01-100% green.

const CRIT_COLOR:         Color = Color(1.00, 0.35, 0.30, 1.00)
const WARN_COLOR:         Color = Color(1.00, 0.72, 0.10, 1.00)
const QUALITY_GOOD_COLOR: Color = Color(0.30, 0.85, 0.35, 1.00)

static func get_color(quality: float) -> Color:
	if quality <= 50.0:
		return CRIT_COLOR
	elif quality <= 75.0:
		return WARN_COLOR
	return QUALITY_GOOD_COLOR
