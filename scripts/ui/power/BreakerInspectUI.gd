extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Shared by standard/smart breakers. Never performs the timed reset itself.
signal battery_passthrough_requested(enabled: bool)
signal generator_passthrough_requested(enabled: bool)
signal restart_requested
var _data: Dictionary = {}
var _state: PanelContainer
var _zone_a: PanelContainer
var _zone_b: PanelContainer
var _battery: CheckButton
var _generator: CheckButton
var _hint: Label
var _restart: Button

func _build_content() -> void:
	refresh_interval = 0.0
	_state = W.status(_statuses, "BreakerState")
	W.heading(_details, "ZonesLabel", "Connected zones")
	_zone_a = W.status(_details, "ZoneA")
	_zone_b = W.status(_details, "ZoneB")
	W.heading(_details, "SharingLabel", "Power sharing")
	_battery = W.switch_row(_details, "BatterySharing", "Battery power", _on_battery)
	_generator = W.switch_row(_details, "GeneratorSharing", "Generator power", _on_generator)
	W.label(_details, "SharingHint", "Allow each power source to pass between the connected zones.", 13, "secondary")
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
	W.set_switch(_battery, pass_battery)
	W.set_switch(_generator, pass_generator)
	_battery.disabled = tripped
	_generator.disabled = tripped
	_restart.visible = tripped
	_hint.text = "Sharing controls are locked while tripped. Restart begins a timed electrical job; electrical injury is possible." if tripped else "Trip or reset zones from the Power Terminal."
	_hint.add_theme_color_override("font_color", W.color(_view, "warning" if tripped else "secondary"))
	_hint.add_theme_font_size_override("font_size", 13)
	# A live trip must not strand focus on a now-disabled sharing button.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if (focus == _battery or focus == _generator) and tripped:
		_close_btn.grab_focus()
	elif focus == _restart and not tripped:
		_close_btn.grab_focus()

func _set_zone(card: PanelContainer, data: Dictionary) -> void:
	W.set_status(card, String(data.get("name", "No assigned zone")), "text", "grid")
	(card.get_node("Row/State") as Label).add_theme_color_override("font_color", Q.TEXT)
	# Custom player zone colours belong to the icon, never the text contrast.
	var tint: Color = data.get("color", W.color(_view, "inactive"))
	tint.a = 1.0
	(card.get_node("Row/Icon") as TextureRect).self_modulate = tint

func _on_battery() -> void:
	if _is_open and not bool(_data.get("tripped", false)):
		W.set_switch(_battery, bool(_data.get("pass_battery", false)))
		battery_passthrough_requested.emit(not bool(_data.get("pass_battery", false)))

func _on_generator() -> void:
	if _is_open and not bool(_data.get("tripped", false)):
		W.set_switch(_generator, bool(_data.get("pass_generator", false)))
		generator_passthrough_requested.emit(not bool(_data.get("pass_generator", false)))

func _on_restart() -> void:
	if _is_open and bool(_data.get("tripped", false)):
		restart_requested.emit()
