extends RefCounted
## SaveSlotFormat.gd (Sep 2026) — one wording for save slots everywhere
## (main menu Continue/Load, pause Save/Load): "Day 3  ·  2:20 PM  ·  2 hours ago".
## Preload it: const SLOT_FORMAT := preload("res://scripts/ui/common/SaveSlotFormat.gd")

static func describe(info: Dictionary) -> String:
	var day: Variant = info.get("day", "?")
	var parts: PackedStringArray = ["Day %s" % (str(int(day)) if day is float or day is int else str(day))]
	var time_display := str(info.get("time_display", ""))
	if not time_display.is_empty() and time_display != "?":
		parts.append(time_display)
	var ago := relative_time(str(info.get("timestamp", "")))
	if not ago.is_empty():
		parts.append(ago)
	return "  ·  ".join(parts)


## Save timestamps are local wall-clock strings; compare against local now.
static func relative_time(stamp: String) -> String:
	if stamp.length() < 19:
		return ""
	var then := Time.get_unix_time_from_datetime_string(stamp.replace(" ", "T"))
	var now := Time.get_unix_time_from_datetime_string(
		Time.get_datetime_string_from_system(false, false))
	var seconds := int(now - then)
	if seconds < 0:
		return ""
	if seconds < 90:
		return "just now"
	if seconds < 3600:
		return "%d minutes ago" % (seconds / 60)
	if seconds < 7200:
		return "1 hour ago"
	if seconds < 86400:
		return "%d hours ago" % (seconds / 3600)
	if seconds < 172800:
		return "yesterday"
	if seconds < 86400 * 14:
		return "%d days ago" % (seconds / 86400)
	return stamp.substr(0, 10)
