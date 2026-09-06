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

static func water_quality_color(quality: float) -> Color:
	# Same boundaries as WaterQualityColor; UI uses approved semantic tints.
	if quality <= 50.0:
		return BunkerDesign.RED
	if quality <= 75.0:
		return BunkerDesign.WARNING
	return BunkerDesign.GREEN
