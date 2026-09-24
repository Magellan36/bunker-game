extends RefCounted
class_name NPCMetrics
## Low-volume, aggregate NPC instrumentation. Disabled by default and never
## consulted by gameplay code: enabling it may observe behavior, but cannot
## change scores, timing, navigation, or activity selection.

const RECENT_EVENT_CAPACITY: int = 64
const DEFAULT_BOUNDS: Array[float] = [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]

static var enabled: bool = false
static var _counters: Dictionary = {}
static var _histograms: Dictionary = {}
static var _recent_events: Array[Dictionary] = []


static func set_enabled(value: bool, clear_existing: bool = false) -> void:
	enabled = value
	if clear_existing:
		reset()


static func reset() -> void:
	_counters.clear()
	_histograms.clear()
	_recent_events.clear()


static func increment(name: StringName, amount: int = 1) -> void:
	if not enabled:
		return
	_counters[name] = int(_counters.get(name, 0)) + amount


static func observe(name: StringName, value: float, bounds: Array = DEFAULT_BOUNDS) -> void:
	if not enabled or is_nan(value) or is_inf(value):
		return
	var histogram: Dictionary = _histograms.get(name, {})
	if histogram.is_empty():
		var normalized_bounds: Array[float] = []
		for bound: Variant in bounds:
			normalized_bounds.append(float(bound))
		normalized_bounds.sort()
		histogram = {
			"bounds": normalized_bounds,
			"buckets": PackedInt64Array(),
			"count": 0,
			"sum": 0.0,
			"min": value,
			"max": value,
		}
		var buckets := PackedInt64Array()
		buckets.resize(normalized_bounds.size() + 1)
		histogram["buckets"] = buckets
	var bucket_index: int = 0
	var live_bounds: Array = histogram["bounds"]
	while bucket_index < live_bounds.size() and value > float(live_bounds[bucket_index]):
		bucket_index += 1
	var live_buckets: PackedInt64Array = histogram["buckets"]
	live_buckets[bucket_index] += 1
	histogram["buckets"] = live_buckets
	histogram["count"] = int(histogram["count"]) + 1
	histogram["sum"] = float(histogram["sum"]) + value
	histogram["min"] = minf(float(histogram["min"]), value)
	histogram["max"] = maxf(float(histogram["max"]), value)
	_histograms[name] = histogram


static func record_event(kind: StringName, npc: Node = null, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var event: Dictionary = {
		"time_msec": Time.get_ticks_msec(),
		"kind": String(kind),
		"npc_id": String(npc.get("npc_id")) if npc != null and "npc_id" in npc else "",
		"npc_name": String(npc.get("npc_name")) if npc != null and "npc_name" in npc else "",
		"data": data.duplicate(true),
	}
	_recent_events.append(event)
	while _recent_events.size() > RECENT_EVENT_CAPACITY:
		_recent_events.pop_front()


static func snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"counters": _counters.duplicate(true),
		"histograms": _histograms.duplicate(true),
		"recent_events": _recent_events.duplicate(true),
	}
