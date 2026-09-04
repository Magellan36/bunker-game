extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## View/controller only. WaterDispenser/WaterManager retain storage, blending,
## requested rate, actual grants and priority allocation. Existing open API.
var _dispenser: WaterDispenser
var _running: PanelContainer
var _connection: PanelContainer
var _storage: VBoxContainer
var _quality: VBoxContainer
var _requested: VBoxContainer
var _received: VBoxContainer
var _network_hint: Label
var _rate_slider: HSlider
var _toggle_btn: Button
var _priority_control: VBoxContainer

func _build_content() -> void:
	_running = W.status(_statuses, "Running")
	_connection = W.status(_statuses, "Connection")
	_storage = W.meter(_details, "Storage", "Stored water", "water")
	_quality = W.meter(_details, "Quality", "Water quality", "condition")
	_requested = W.stat(_details, "Requested", "Requested flow")
	_rate_slider = HSlider.new()
	_rate_slider.name = "RateSlider"
	_rate_slider.step = 1.0
	_rate_slider.focus_mode = Control.FOCUS_ALL
	_rate_slider.custom_minimum_size.y = 36
	_rate_slider.set_meta("ui_min_height", 36)
	_rate_slider.tooltip_text = "Requested flow in mL/day. Arrow keys or D-pad left/right adjust it."
	_details.add_child(_rate_slider)
	var groove: StyleBoxFlat = _view.theme.get_stylebox("background", "BunkerMeter").duplicate() as StyleBoxFlat
	groove.content_margin_top = 4.0
	groove.content_margin_bottom = 4.0
	var fill: StyleBoxFlat = _view.theme.get_stylebox("fill", "BunkerMeter").duplicate() as StyleBoxFlat
	fill.bg_color = W.color(_view, "blue")
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	_rate_slider.add_theme_stylebox_override("slider", groove)
	_rate_slider.add_theme_stylebox_override("grabber_area", fill)
	_rate_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	_rate_slider.add_theme_stylebox_override("focus", _view.theme.get_stylebox("focus", "Button"))
	_rate_slider.value_changed.connect(_on_rate_changed)
	_network_hint = W.label(_details, "NetworkHint", "", 14, "secondary")
	_received = W.stat(_details, "Received", "Receiving now")
	_priority_control = _add_priority(_details, _on_priority_requested)
	_priority_control.set_hint("1 is served first · 5 is served last")
	W.label(_footer, "ActionHint", "Controls refilling from the network; stored water stays in the tank.", 14, "secondary")
	_toggle_btn = W.button(_footer, "Toggle", "Turn dispenser on", _on_toggle_pressed, "running", true)

func open(dispenser: WaterDispenser) -> void:
	if not is_instance_valid(dispenser):
		return
	_dispenser = dispenser
	_open_device("Water dispenser", "WATER SYSTEM", "water", dispenser)

func _refresh_data() -> void:
	if not is_instance_valid(_dispenser) or _dispenser.is_queued_for_deletion():
		close()
		return
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var key: String = _dispenser.get_node_key()
	var connected: bool = wm != null and wm.is_reachable_from_hookup(key)
	var maximum: float = wm.get_dynamic_max_mL_per_day(key, _dispenser.priority) if wm != null else 0.0
	var info: Dictionary = wm.get_received_rate_mL(key) if wm != null and not key.is_empty() else {}
	var received: float = float(info.get("mL_per_day", 0.0))
	var requested: float = _dispenser.requested_rate_mL_per_day
	W.set_status(_running, "On" if _dispenser.is_on else "Off", "success" if _dispenser.is_on else "inactive", "running" if _dispenser.is_on else "stopped")
	W.set_status(_connection, "Water connected" if connected else "Disconnected", "success" if connected else "warning", "grid")
	W.set_meter(_storage, _dispenser.current_fill_mL / WaterDispenser.MAX_STORAGE_ML * 100.0,
		"%d%%" % roundi(_dispenser.current_fill_mL / WaterDispenser.MAX_STORAGE_ML * 100.0),
		"%.0f / %.0f mL stored" % [_dispenser.current_fill_mL, WaterDispenser.MAX_STORAGE_ML])
	var quality: float = _dispenser.stored_water_quality
	W.set_meter(_quality, quality, "%.0f%%" % quality, "Quality of water currently in the tank.", W.quality_token(quality))
	W.set_stat(_requested, "%.0f mL/day · %.2f mL/min" % [requested, requested / 1440.0])
	# Range.max_value can emit value_changed while clamping. Block the entire
	# update, not only the final value assignment: refreshing must NEVER write.
	_rate_slider.set_block_signals(true)
	_rate_slider.max_value = maxf(0.0, maximum)
	_rate_slider.set_value_no_signal(requested)
	_rate_slider.set_block_signals(false)
	_rate_slider.editable = maximum > 0.0
	_network_hint.text = "Network maximum now: %.0f mL/day" % maximum
	if requested > maximum:
		_network_hint.text += "\nNetwork supply has fallen below the current request."
	W.set_stat(_received, "%.0f mL/day · %.2f mL/min" % [received, received / 1440.0],
		"inactive" if not _dispenser.is_on else ("warning" if received < requested - 1.0 else "blue"))
	_priority_control.set_value(_dispenser.priority)
	_toggle_btn.text = "Turn dispenser off" if _dispenser.is_on else "Turn dispenser on"
	_toggle_btn.tooltip_text = _toggle_btn.text
	_toggle_btn.icon = W.icon("stopped" if _dispenser.is_on else "running")

func _on_rate_changed(value: float) -> void:
	if _is_open and is_instance_valid(_dispenser):
		_dispenser.set_requested_rate(value)
		_refresh_data()

func _on_toggle_pressed() -> void:
	if _is_open and is_instance_valid(_dispenser):
		_dispenser.set_on(not _dispenser.is_on)
		_refresh_data()

func _on_priority_requested(value: int) -> void:
	if _is_open and is_instance_valid(_dispenser):
		_dispenser.priority = clampi(value, 1, 5)
		_refresh_data()
