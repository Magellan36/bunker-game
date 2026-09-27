class_name UIFormat
extends RefCounted
## Formatting only. Never round values before gameplay operations.
static func integer(value: int) -> String:
	var raw: String = str(absi(value))
	var groups: String = ""
	while raw.length() > 3:
		groups = "," + raw.right(3) + groups
		raw = raw.left(raw.length() - 3)
	return ("-" if value < 0 else "") + raw + groups

static func money(value: int) -> String:
	return ("-" if value < 0 else "") + "$" + integer(absi(value))


static func rounded_integer(value: float) -> String:
	return integer(roundi(value))


static func percent(value: float) -> String:
	return "%s%%" % rounded_integer(value)


static func uses(current: int, maximum: int, remaining: bool = true) -> String:
	return "%s / %s uses%s" % [
		integer(current), integer(maximum), " remaining" if remaining else ""]


static func battery(value: float) -> String:
	return "%s battery remaining" % percent(value)


static func battery_charge(value: float) -> String:
	return "%s charge" % percent(value)


static func water_quality(value: float) -> String:
	return "Water quality %s" % percent(value)


static func water_quality_short(value: float) -> String:
	return "%s quality" % percent(value)


static func water_quality_color(quality: float) -> Color:
	# Same boundaries as WaterQualityColor; UI uses approved semantic tints.
	if quality <= 50.0:
		return BunkerDesign.RED
	if quality <= 75.0:
		return BunkerDesign.WARNING
	return BunkerDesign.GREEN

static func allocation_tier(value: int) -> String:
	const TIER_NAMES: Array[String] = ["CRITICAL", "IMPORTANT", "STANDARD", "LOW", "LUXURY"]
	return TIER_NAMES[clampi(value, 1, 5) - 1]
