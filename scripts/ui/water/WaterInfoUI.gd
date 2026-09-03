extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Existing shared hookup/sink/purifier API, now composed from native widgets.
## No new filter-replacement action: replacement still uses the physical item.
var _mode: String = "sink"
var _device_ref: Node
var _connection: PanelContainer
var _source: VBoxContainer
var _source_output: VBoxContainer
var _source_demand: VBoxContainer
var _source_quality: VBoxContainer
var _sink: VBoxContainer
var _sink_received: VBoxContainer
var _sink_quality: VBoxContainer
var _priority_control: VBoxContainer
var _purifier: VBoxContainer
var _input_quality: VBoxContainer
var _output_quality: VBoxContainer
var _filter: VBoxContainer
var _flow: VBoxContainer
var _warning: Label

func _build_content() -> void:
	_connection = W.status(_statuses, "Connection")
	_source = W.column(_details, "Hookup", 16)
	_source_output = W.stat(_source, "Output", "Tier output")
	_source_demand = W.stat(_source, "Demand", "Connected demand")
	_source_quality = W.meter(_source, "Quality", "Source water quality", "water")
	_sink = W.column(_details, "Sink", 16)
	_sink_received = W.stat(_sink, "Received", "Receiving now")
	_sink_quality = W.meter(_sink, "Quality", "Received water quality", "water")
	_priority_control = _add_priority(_sink, _on_priority_requested)
	_priority_control.set_hint("1 is served first · 5 is served last")
	_purifier = W.column(_details, "Purifier", 16)
	_input_quality = W.meter(_purifier, "InputQuality", "Input quality", "water")
	_output_quality = W.meter(_purifier, "OutputQuality", "Purified output", "water")
	_filter = W.meter(_purifier, "Filter", "Filter quality", "condition")
	_flow = W.stat(_purifier, "Flow", "Water flow")
	_warning = W.label(_purifier, "Warnings", "", 14, "warning")
	W.label(_footer, "Help", "Live network readings. Walk away to close this panel.", 14, "secondary")

func open(display_name: String, mode: String, device_ref: Node) -> void:
	if not is_instance_valid(device_ref) or not device_ref is Node3D:
		return
	_mode = mode
	_device_ref = device_ref
	_source.visible = mode == "hookup"
	_sink.visible = mode == "sink"
	_purifier.visible = mode == "purifier"
	_open_device(display_name, "WATER SYSTEM", "water", device_ref as Node3D,
		Vector3.INF, 740.0 if mode == "purifier" else 600.0)

func _refresh_data() -> void:
	if not is_instance_valid(_device_ref) or _device_ref.is_queued_for_deletion():
		close()
		return
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	match _mode:
		"hookup": _refresh_source(wm)
		"sink": _refresh_sink(wm)
		"purifier": _refresh_purifier(wm)

func _refresh_source(wm: WaterManager) -> void:
	var hookup: WaterHookup = _device_ref as WaterHookup
	if hookup == null:
		close()
		return
	var daily: float = hookup.get_daily_output_mL()
	var count: int = wm.get_connected_consumer_count(hookup) if wm != null else 0
	var demand: float = wm.get_total_requested_demand_mL(hookup) if wm != null else 0.0
	W.set_status(_connection, "Consumers connected" if count > 0 else "No consumers", "success" if count > 0 else "inactive", "grid")
	W.set_stat(_source_output, "%.0f mL/day · %.2f mL/min" % [daily, hookup.get_per_minute_output_mL()])
	W.set_stat(_source_demand, "%d device%s · %.0f / %.0f mL/day requested" % [count, "" if count == 1 else "s", demand, daily],
		"warning" if demand > daily else "text")
	W.set_meter(_source_quality, hookup.water_quality, "%.0f%%" % hookup.water_quality,
		"Raw water before downstream purification.", W.quality_token(hookup.water_quality))

func _refresh_sink(wm: WaterManager) -> void:
	var sink: WaterTestSink = _device_ref as WaterTestSink
	if sink == null:
		close()
		return
	var connected: bool = wm != null and wm.is_reachable_from_hookup(sink.get_node_key())
	W.set_status(_connection, "Water connected" if connected else "Disconnected", "success" if connected else "warning", "grid")
	var info: Dictionary = wm.get_received_rate_mL(sink.get_node_key()) if connected else {}
	W.set_stat(_sink_received, "%.0f mL/day · %.2f mL/min" % [float(info.get("mL_per_day", 0.0)), float(info.get("mL_per_minute", 0.0))] if connected else "Not connected to a water source",
		"blue" if connected else "warning")
	_sink_quality.visible = connected
	var quality: float = float(info.get("quality", 0.0))
	W.set_meter(_sink_quality, quality, "%.0f%%" % quality, "", W.quality_token(quality))
	_priority_control.set_value(sink.priority)

func _refresh_purifier(wm: WaterManager) -> void:
	var purifier: WaterPurifier = _device_ref as WaterPurifier
	if purifier == null:
		close()
		return
	var key: String = purifier.get_node_key()
	var upstream: Dictionary = wm.get_upstream_raw_quality(key) if wm != null and not key.is_empty() else {}
	var connected: bool = bool(upstream.get("connected", false))
	var incoming: float = float(upstream.get("quality", 0.0))
	var outgoing: float = purifier.get_output_quality()
	W.set_status(_connection, "Water connected" if connected else "Disconnected", "success" if connected else "warning", "grid")
	_input_quality.visible = connected
	_output_quality.visible = connected
	W.set_meter(_input_quality, incoming, "%.0f%%" % incoming, "", W.quality_token(incoming))
	W.set_meter(_output_quality, outgoing, "%.0f%%" % outgoing, "", W.quality_token(outgoing))
	W.set_meter(_filter, purifier.filter_quality, "%.0f%%" % purifier.filter_quality,
		"Use a purifier filter item to replace the installed filter.", W.quality_token(purifier.filter_quality))
	var flow: float = purifier.current_flow_mL_per_day
	W.set_stat(_flow, "%.0f mL/day" % flow, "success" if flow < 2500.0 else ("warning" if flow < 4000.0 else "critical"))
	var warnings: Array[String] = []
	if connected and incoming < 50.0:
		warnings.append("Incoming water quality is low — this wears filters faster.")
	var hookup: WaterHookup = wm.get_hookup_for_node(key) if wm != null and not key.is_empty() else null
	if hookup != null and flow > hookup.get_daily_output_mL() * 0.5:
		warnings.append("High water flow through this purifier — this wears filters faster.")
	_warning.text = "\n".join(warnings)
	_warning.visible = not warnings.is_empty()

func _on_priority_requested(value: int) -> void:
	if _is_open and is_instance_valid(_device_ref) and _mode == "sink":
		(_device_ref as WaterTestSink).priority = clampi(value, 1, 5)
		_refresh_data()
