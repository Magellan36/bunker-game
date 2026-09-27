extends RefCounted
class_name NPCMetrics
## Low-volume, aggregate NPC instrumentation. Disabled by default and never
## consulted by gameplay code: enabling it may observe behavior, but cannot
## change scores, timing, navigation, or activity selection.

const RECENT_EVENT_CAPACITY: int = 256
const PER_NPC_EVENT_CAPACITY: int = 128
const PER_NPC_DECISION_CAPACITY: int = 64
const PER_NPC_ANOMALY_CAPACITY: int = 24
const DECISION_HEARTBEAT_MSEC: int = 10000
const DEFAULT_BOUNDS: Array[float] = [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]

static var enabled: bool = false
static var _counters: Dictionary = {}
static var _histograms: Dictionary = {}
static var _recent_events: Array[Dictionary] = []
static var _per_npc: Dictionary = {}
static var _started_msec: int = 0
static var _stopped_msec: int = 0


static func set_enabled(value: bool, clear_existing: bool = false) -> void:
	if enabled and not value:
		_stopped_msec = Time.get_ticks_msec()
	enabled = value
	if clear_existing:
		reset()
	if enabled and _started_msec <= 0:
		_started_msec = Time.get_ticks_msec()
		_stopped_msec = 0


static func reset() -> void:
	_counters.clear()
	_histograms.clear()
	_recent_events.clear()
	_per_npc.clear()
	_started_msec = Time.get_ticks_msec() if enabled else 0
	_stopped_msec = 0


static func _npc_key(npc: Node) -> String:
	if npc == null:
		return ""
	if "npc_id" in npc and not String(npc.get("npc_id")).is_empty():
		return String(npc.get("npc_id"))
	return "instance_%d" % npc.get_instance_id()


static func _state_for(npc: Node) -> Dictionary:
	var key: String = _npc_key(npc)
	if key.is_empty():
		return {}
	if not _per_npc.has(key):
		_per_npc[key] = {
			"npc_id": key,
			"npc_name": String(npc.get("npc_name")) if "npc_name" in npc else key,
			"activity_seconds": {},
			"activity_starts": {},
			"activity_end_reasons": {},
			"active_span": {},
			"last_decision": {},
			"last_decision_signature": "",
			"last_decision_recorded_msec": 0,
			"decisions": [],
			"events": [],
			"anomalies": [],
		}
	return _per_npc[key] as Dictionary


static func _append_bounded(target: Array, value: Dictionary, capacity: int) -> void:
	target.append(value)
	while target.size() > capacity:
		target.pop_front()


static func _activity_type(activity: NPCActivity) -> String:
	return activity.debug_type() if activity != null else "Idle"


static func begin_activity(npc: Node, activity: NPCActivity, reason: String,
		data: Dictionary = {}) -> void:
	if not enabled or npc == null or activity == null:
		return
	var state: Dictionary = _state_for(npc)
	if not (state.get("active_span", {}) as Dictionary).is_empty():
		end_activity(npc, "replaced_without_explicit_end")
	var activity_type: String = _activity_type(activity)
	var starts: Dictionary = state["activity_starts"]
	starts[activity_type] = int(starts.get(activity_type, 0)) + 1
	state["activity_starts"] = starts
	state["active_span"] = {
		"activity_type": activity_type,
		"label": activity.label(),
		"started_msec": Time.get_ticks_msec(),
		"start_reason": reason,
		"start_data": data.duplicate(true),
	}
	record_event(&"activity_span_started", npc, {
		"activity_type": activity_type, "label": activity.label(), "reason": reason,
	})


static func end_activity(npc: Node, reason: String, data: Dictionary = {}) -> void:
	if not enabled or npc == null:
		return
	var state: Dictionary = _state_for(npc)
	var span: Dictionary = state.get("active_span", {}) as Dictionary
	if span.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var duration: float = maxf(0.0, float(now - int(span.get("started_msec", now))) / 1000.0)
	var activity_type: String = String(span.get("activity_type", "Unknown"))
	var durations: Dictionary = state["activity_seconds"]
	durations[activity_type] = float(durations.get(activity_type, 0.0)) + duration
	state["activity_seconds"] = durations
	var reasons: Dictionary = state["activity_end_reasons"]
	var reason_key: String = "%s:%s" % [activity_type, reason]
	reasons[reason_key] = int(reasons.get(reason_key, 0)) + 1
	state["activity_end_reasons"] = reasons
	state["active_span"] = {}
	var event_data: Dictionary = data.duplicate(true)
	event_data.merge({
		"activity_type": activity_type,
		"label": span.get("label", activity_type),
		"reason": reason,
		"duration_sec": duration,
	}, true)
	record_event(&"activity_span_ended", npc, event_data)


static func record_decision(npc: Node, receipt: Dictionary) -> void:
	if not enabled or npc == null:
		return
	var state: Dictionary = _state_for(npc)
	var now: int = Time.get_ticks_msec()
	var stored: Dictionary = receipt.duplicate(true)
	stored["time_msec"] = now
	state["last_decision"] = stored
	var signature: String = "%s|%s|%s|%s" % [
		stored.get("outcome", ""), stored.get("current_type", ""),
		stored.get("winner_type", ""), stored.get("reason", ""),
	]
	var last_time: int = int(state.get("last_decision_recorded_msec", 0))
	if signature == String(state.get("last_decision_signature", "")) \
			and now - last_time < DECISION_HEARTBEAT_MSEC:
		return
	state["last_decision_signature"] = signature
	state["last_decision_recorded_msec"] = now
	var decisions: Array = state["decisions"]
	_append_bounded(decisions, stored, PER_NPC_DECISION_CAPACITY)
	state["decisions"] = decisions
	record_event(&"decision", npc, stored)


static func record_anomaly(kind: StringName, npc: Node, data: Dictionary = {},
		navigation: Dictionary = {}) -> void:
	if not enabled or npc == null:
		return
	var compact_nav: Dictionary = navigation.duplicate(true)
	var samples: Array = compact_nav.get("recent_samples", []) as Array
	if samples.size() > 12:
		samples = samples.slice(samples.size() - 12)
	compact_nav["recent_samples"] = samples
	var anomaly: Dictionary = {
		"time_msec": Time.get_ticks_msec(),
		"kind": String(kind),
		"activity": (npc.brain.current_label() if "brain" in npc and npc.brain != null else "?"),
		"activity_info": (npc.brain.get_current_activity_debug_info()
			if "brain" in npc and npc.brain != null else {}),
		"data": data.duplicate(true),
		"navigation": compact_nav,
	}
	var state: Dictionary = _state_for(npc)
	var anomalies: Array = state["anomalies"]
	_append_bounded(anomalies, anomaly, PER_NPC_ANOMALY_CAPACITY)
	state["anomalies"] = anomalies
	record_event(kind, npc, {"anomaly": anomaly})


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
	if npc != null:
		var state: Dictionary = _state_for(npc)
		var events: Array = state["events"]
		_append_bounded(events, event, PER_NPC_EVENT_CAPACITY)
		state["events"] = events


static func get_last_decision(npc: Node) -> Dictionary:
	if npc == null:
		return {}
	var key: String = _npc_key(npc)
	if not _per_npc.has(key):
		return {}
	return (_per_npc[key] as Dictionary).get("last_decision", {}).duplicate(true)


static func session_snapshot() -> Dictionary:
	var now: int = Time.get_ticks_msec() if enabled or _stopped_msec <= 0 else _stopped_msec
	var residents: Dictionary = _per_npc.duplicate(true)
	for key: String in residents.keys():
		var state: Dictionary = residents[key]
		var active: Dictionary = state.get("active_span", {}) as Dictionary
		if not active.is_empty():
			var durations: Dictionary = state.get("activity_seconds", {}) as Dictionary
			var activity_type: String = String(active.get("activity_type", "Unknown"))
			durations[activity_type] = float(durations.get(activity_type, 0.0)) \
				+ maxf(0.0, float(now - int(active.get("started_msec", now))) / 1000.0)
			state["activity_seconds"] = durations
		residents[key] = state
	return {
		"enabled": enabled,
		"duration_sec": maxf(0.0, float(now - _started_msec) / 1000.0) if _started_msec > 0 else 0.0,
		"counters": _counters.duplicate(true),
		"histograms": _histograms.duplicate(true),
		"residents": residents,
		"recent_events": _recent_events.duplicate(true),
	}


static func snapshot() -> Dictionary:
	return session_snapshot()
