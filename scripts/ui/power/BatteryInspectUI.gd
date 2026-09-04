extends "res://scripts/ui/common/BunkerDeviceInspector.gd"
## Battery presentation only. Owner supplies confirmed values and handles toggle.
signal enabled_requested(enabled: bool)
var _data: Dictionary = {}
var _state: PanelContainer
var _grid: PanelContainer
var _charge: VBoxContainer
var _health: VBoxContainer
var _toggle: Button

func _build_content() -> void:
	refresh_interval = 0.0
	_state = W.status(_statuses, "BatteryState")
	_grid = W.status(_statuses, "GridState")
	_charge = W.meter(_details, "Charge", "Charge", "battery")
	_health = W.meter(_details, "Health", "Health", "condition")
	W.label(_details, "Role", "Stores surplus energy and supplies it when the network needs it.", 14, "secondary")
	W.label(_footer, "ActionHint", "Disabling the battery stops it participating in the power network.", 14, "secondary")
	_toggle = W.button(_footer, "Toggle", "Disable battery", _on_toggle, "battery", true)

func open(device: Node3D, display_name: String, data: Dictionary) -> void:
	_data = data.duplicate()
	_open_device(display_name, "POWER STORAGE", "battery", device, Vector3.INF, 620.0)

func refresh(data: Dictionary) -> void:
	if not _is_open:
		return
	_data = data.duplicate()
	_refresh_data()

func _refresh_data() -> void:
	var state: String = String(_data.get("state", "IDLE"))
	var token: String = "inactive"
	match state:
		"CHARGING": token = "success"
		"DISCHARGING": token = "warning"
		"DRAINED": token = "critical"
	var connected: bool = bool(_data.get("connected", false))
	W.set_status(_state, state.capitalize(), token, "battery")
	W.set_status(_grid, "Grid connected" if connected else "Disconnected", "success" if connected else "inactive", "grid")
	var charge: float = float(_data.get("charge_wh", 0.0))
	var capacity: float = float(_data.get("capacity_wh", 0.0))
	var percent: float = clampf(charge / maxf(capacity, 1.0) * 100.0, 0.0, 100.0)
	W.set_meter(_charge, percent, "%d%%" % int(percent), "%.0f / %.0f Wh stored" % [charge, capacity],
		"critical" if percent <= 15.0 else ("warning" if percent <= 40.0 else "blue"))
	var health: float = float(_data.get("health", 100.0))
	W.set_meter(_health, health, "%d%%" % int(health),
		"Health tracking is not active yet." if not bool(_data.get("health_implemented", false)) else "",
		"critical" if health <= 25.0 else ("warning" if health <= 50.0 else "success"))
	_toggle.text = "Disable battery" if bool(_data.get("enabled", true)) else "Enable battery"
	_toggle.tooltip_text = _toggle.text

func _on_toggle() -> void:
	if _is_open:
		enabled_requested.emit(not bool(_data.get("enabled", true)))
