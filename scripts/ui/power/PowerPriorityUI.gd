extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Shared consumer inspector. Optional load toggle remains signal-only;
## priority still writes through PowerManager then emits the existing signal.
signal priority_changed(id: String, value: int)
signal load_toggled(id: String, on: bool)

var _device_id: String = ""
var _show_toggle: bool = false
var _priority: int = 3
var _active: bool = true
var _registered: bool = false
var _status: PanelContainer
var _watts: VBoxContainer
var _priority_control: VBoxContainer
var _toggle_btn: Button
var _explanation: Label

func _build_content() -> void:
	_status = W.status(_statuses, "PowerState")
	_watts = W.stat(_details, "Watts", "Rated load")
	_priority_control = _add_priority(_details, _apply_priority)
	_priority_control.set_hint("1 is critical · 5 is shed first during shortages")
	_explanation = W.label(_details, "Explanation", "", 14, "secondary")
	_toggle_btn = W.button(_footer, "Toggle", "Turn load off", _on_toggle_pressed, "stopped", true)

func open(device_id: String, display_name: String, show_load_toggle: bool = false,
		anchor_world: Vector3 = Vector3.INF, device: Node3D = null) -> void:
	_device_id = device_id
	_show_toggle = show_load_toggle
	_toggle_btn.visible = show_load_toggle
	_open_device(display_name, "POWER SYSTEM", "power", device, anchor_world, 540.0)

func _refresh_data() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var data: Dictionary = pm.get_consumer_status(_device_id) if pm != null and not _device_id.is_empty() else {}
	_registered = bool(data.get("registered", false))
	_priority = int(data.get("priority", 3))
	_active = bool(data.get("active", true))
	var state: String = String(data.get("status_str", "NO POWER"))
	var text: String = "No power"
	var token: String = "critical"
	match state:
		"POWERED":
			text = "Powered"
			token = "success"
		"SHED":
			text = "Load shed"
			token = "warning"
		"OFF":
			text = "Off"
			token = "inactive"
		"UNWIRED":
			text = "Not wired"
			token = "warning"
	if not _registered:
		text = "Unavailable"
		token = "inactive"
	W.set_status(_status, text, token, "power")
	W.set_stat(_watts, "%.0f W" % float(data.get("watts", 0.0)) if _registered else "—")
	_priority_control.set_value(_priority, _registered)
	_toggle_btn.disabled = not _registered
	_toggle_btn.text = "Turn load off" if _active else "Turn load on"
	_toggle_btn.tooltip_text = _toggle_btn.text
	_explanation.text = "Priority controls which devices keep power during a shortage."
	if state == "SHED":
		_explanation.text = "The network has shed this load. A higher priority may help it retain power."
	elif state == "UNWIRED":
		_explanation.text = "Connect this device to the power network."
	elif not _registered:
		_explanation.text = "This device is no longer registered with the power network."

func _apply_priority(value: int) -> void:
	if not _is_open or not _registered:
		return
	var clamped: int = clampi(value, 1, 5)
	if clamped == _priority:
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	pm.set_consumer_priority(_device_id, clamped)
	priority_changed.emit(_device_id, clamped)
	_refresh_data()

func _on_toggle_pressed() -> void:
	if _is_open and _registered and _show_toggle:
		load_toggled.emit(_device_id, not _active)
		_refresh_data()
