extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Shared by standard/smart breakers. Never performs the timed reset itself.
signal battery_passthrough_requested(enabled: bool)
signal generator_passthrough_requested(enabled: bool)
signal restart_requested
var _data: Dictionary = {}
var _state: PanelContainer
var _zone_a: PanelContainer
var _zone_b: PanelContainer
var _battery: Button
var _generator: Button
var _hint: Label
var _restart: Button

func _build_content() -> void:
	refresh_interval = 0.0
	_state = W.status(_statuses, "BreakerState")
	W.label(_details, "ZonesLabel", "Connected zones", 14, "secondary")
	_zone_a = W.status(_details, "ZoneA")
	_zone_b = W.status(_details, "ZoneB")
	W.label(_details, "SharingLabel", "Power sharing", 14, "secondary")
	_battery = W.button(_details, "BatterySharing", "Battery power: Off", _on_battery, "battery")
	_battery.toggle_mode = true
	_generator = W.button(_details, "GeneratorSharing", "Generator power: Off", _on_generator, "power")
	_generator.toggle_mode = true
	W.label(_details, "SharingHint", "Allow each power source to pass between the connected zones.", 14, "secondary")
	_hint = W.label(_footer, "ActionHint", "", 14, "secondary")
	_restart = W.button(_footer, "Restart", "Restart breaker", _on_restart, "running", true)

func open(device: Node3D, display_name: String, data: Dictionary) -> void:
	_data = data.duplicate(true)
	_open_device(display_name, "POWER DISTRIBUTION", "grid", device, Vector3.INF, 660.0)

func refresh(data: Dictionary) -> void:
	if not _is_open:
		return
	_data = data.duplicate(true)
	_refresh_data()

func _refresh_data() -> void:
	var tripped: bool = bool(_data.get("tripped", false))
	W.set_status(_state, "Tripped · Power isolated" if tripped else "Breaker online", "critical" if tripped else "success", "warning" if tripped else "grid")
	var zones: Array = _data.get("zones", [])
	_set_zone(_zone_a, zones[0] if not zones.is_empty() else {})
	_zone_b.visible = zones.size() > 1
	if zones.size() > 1:
		_set_zone(_zone_b, zones[1])
	var pass_battery: bool = bool(_data.get("pass_battery", false))
	var pass_generator: bool = bool(_data.get("pass_generator", false))
	_battery.set_pressed_no_signal(pass_battery)
	_generator.set_pressed_no_signal(pass_generator)
	_battery.text = "Battery power: " + ("On" if pass_battery else "Off")
	_generator.text = "Generator power: " + ("On" if pass_generator else "Off")
	_battery.disabled = tripped
	_generator.disabled = tripped
	_restart.visible = tripped
	_hint.text = "Sharing controls are locked while tripped. Restart begins a timed electrical job; electrical injury is possible." if tripped else "Trip or reset zones from the Power Terminal."
	_hint.add_theme_color_override("font_color", W.color(_view, "warning" if tripped else "secondary"))
	# A live trip must not strand focus on a now-disabled sharing button.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if (focus == _battery or focus == _generator) and tripped:
		_close_btn.grab_focus()
	elif focus == _restart and not tripped:
		_close_btn.grab_focus()

func _set_zone(card: PanelContainer, data: Dictionary) -> void:
	W.set_status(card, String(data.get("name", "No assigned zone")), "text", "grid")
	# Custom player zone colours belong to the icon, never the text contrast.
	var tint: Color = data.get("color", W.color(_view, "inactive"))
	tint.a = 1.0
	(card.get_node("Row/Icon") as TextureRect).self_modulate = tint

func _on_battery() -> void:
	if _is_open and not bool(_data.get("tripped", false)):
		_battery.set_pressed_no_signal(bool(_data.get("pass_battery", false)))
		battery_passthrough_requested.emit(not bool(_data.get("pass_battery", false)))

func _on_generator() -> void:
	if _is_open and not bool(_data.get("tripped", false)):
		_generator.set_pressed_no_signal(bool(_data.get("pass_generator", false)))
		generator_passthrough_requested.emit(not bool(_data.get("pass_generator", false)))

func _on_restart() -> void:
	if _is_open and bool(_data.get("tripped", false)):
		restart_requested.emit()
