extends CanvasLayer
## Native generator inspector, opt-in redesign pass 2.
## Presentation only: GeneratorObject owns state, restart/reset policy and actions.
## The original open/refresh signatures and signals are intentionally unchanged.

signal closed
signal backup_toggled(enabled: bool)
signal power_toggled(running: bool)

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/power/GeneratorInspectPanel.tscn")
const RUNNING_ICON: Texture2D = preload("res://assets/ui/placeholders/redesign/running_AI_PLACEHOLDER.svg")
const STOPPED_ICON: Texture2D = preload("res://assets/ui/placeholders/redesign/stopped_AI_PLACEHOLDER.svg")
const GRID_ICON: Texture2D = preload("res://assets/ui/placeholders/redesign/grid_AI_PLACEHOLDER.svg")
const FADE_SCRIPT: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")

var _display_name: String = "Generator"
var _watts: float = 0.0
var _fuel: float = 100.0
var _health: float = 100.0
var _is_backup: bool = false
var _is_running: bool = false
var _grid_tripped: bool = false
var _grid_state_str: String = "ONLINE"
var _is_open: bool = false
var _controller_hints: bool = false
var _last_display_state: Array = []
var _previous_focus: WeakRef

var _view: Control
var _panel: PanelContainer
var _toggle_btn: Button
var _power_btn: Button
var _close_btn: Button
var _controller_nav: Node

func _ready() -> void:
	layer = 60
	visible = false
	_view = PANEL_SCENE.instantiate() as Control
	add_child(_view)
	_panel = _view.get_node("%Panel") as PanelContainer
	_toggle_btn = _view.get_node("%Backup") as Button
	_power_btn = _view.get_node("%Power") as Button
	_close_btn = _view.get_node("%Close") as Button
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	_power_btn.pressed.connect(_on_power_pressed)
	_close_btn.pressed.connect(close)
	var backdrop: ColorRect = _view.get_node("Backdrop") as ColorRect
	backdrop.color.a = float(_view.theme.get_constant("backdrop_alpha_permille", "GeneratorInspector")) / 1000.0
	# Per-instance styles prevent state changes leaking into another generator.
	for card_name: String in ["GeneratorStatus", "GridStatus"]:
		var card: PanelContainer = _view.get_node("%" + card_name) as PanelContainer
		card.add_theme_stylebox_override("panel", card.get_theme_stylebox("panel").duplicate() as StyleBox)
	for bar_name: String in ["FuelBar", "ConditionBar"]:
		var bar: ProgressBar = _view.get_node("%" + bar_name) as ProgressBar
		bar.add_theme_stylebox_override("fill", bar.get_theme_stylebox("fill").duplicate() as StyleBox)
	_configure_focus()
	_controller_nav = NAV_SCRIPT.new()
	_controller_nav.ui_root = self
	# Preserve in-world controls: D-pad navigates; left stick stays for movement.
	_controller_nav.stick_navigation = false
	add_child(_controller_nav)
	set_process(false)

func _configure_focus() -> void:
	var buttons: Array[Button] = [_close_btn, _toggle_btn, _power_btn]
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_previous = button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		button.focus_next = button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(index - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[mini(index + 1, buttons.size() - 1)])
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")

func open(display_name: String, watts: float, fuel: float,
		health: float, is_backup: bool, is_running: bool,
		grid_tripped: bool = false,
		grid_state_str: String = "ONLINE") -> void:
	if not _is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	_display_name = display_name
	_watts = watts
	_last_display_state.clear()
	_is_open = true
	visible = true
	refresh(fuel, health, is_backup, is_running, grid_tripped, grid_state_str)
	_update_input_hints()
	set_process(true)
	# Safe initial target: opening an inspector must not prime a shutdown.
	_close_btn.grab_focus()
	var scroll: ScrollContainer = _view.get_node("%DetailsScroll") as ScrollContainer
	scroll.set_deferred("scroll_vertical", 0)
	FADE_SCRIPT.fade_in(_view)

func refresh(fuel: float, health: float, is_backup: bool, is_running: bool,
		grid_tripped: bool = false,
		grid_state_str: String = "ONLINE") -> void:
	_fuel = clampf(fuel, 0.0, 100.0)
	_health = clampf(health, 0.0, 100.0)
	_is_backup = is_backup
	_is_running = is_running
	_grid_tripped = grid_tripped
	_grid_state_str = grid_state_str
	if _is_open:
		_refresh_display()

func is_open() -> bool:
	return _is_open

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	set_process(false)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _view.is_ancestor_of(focused):
		focused.release_focus()
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref() as Control
			if is_instance_valid(previous) and previous.is_visible_in_tree():
				previous.grab_focus()
	closed.emit()

func _refresh_display() -> void:
	# Fuel arrives every simulation tick. Update native controls only when a
	# visible value changes; never poll PowerManager from the presentation.
	var state: Array = [_display_name, _watts, snappedf(_fuel, 0.1), snappedf(_health, 0.1),
		_is_backup, _is_running, _grid_tripped, _grid_state_str]
	if state == _last_display_state:
		return
	_last_display_state = state
	(_view.get_node("%Title") as Label).text = _display_name
	(_view.get_node("%Watts") as Label).text = "%.0f W" % _watts
	var status_text: String = "Stopped"
	var status_color: Color = _color("inactive")
	if _is_running:
		status_text = "Running"
		status_color = _color("success")
	elif _grid_tripped:
		status_text = "Offline"
		status_color = _color("warning")
	elif _is_backup:
		status_text = "Standby"
		status_color = _color("blue")
	_set_status("GeneratorStatus", status_text, status_color, RUNNING_ICON if _is_running else STOPPED_ICON)

	var grid_state: String = "TRIPPED" if _grid_tripped else _grid_state_str
	var grid_text: String = "Grid " + grid_state.to_lower()
	if grid_state.is_empty():
		grid_text = "Grid unknown"
	_set_status("GridStatus", grid_text, _grid_state_color(grid_state), GRID_ICON)
	# The passed grid state is global; this is not a per-generator wire check.
	(_view.get_node("%GridStatus") as Control).tooltip_text = "Bunker-wide grid state. Does not confirm this generator's wire connection."

	_update_meter("Fuel", _fuel, "fuel", "Fuel available", "Low fuel", "Very low fuel", "Empty — refuel to run")
	_update_meter("Condition", _health, "health", "In good condition", "Worn — maintenance advised", "Critical condition", "Broken — repair required")
	_toggle_btn.set_pressed_no_signal(_is_backup)
	_toggle_btn.text = "Backup mode: On" if _is_backup else "Backup mode: Off"
	_toggle_btn.add_theme_color_override("icon_normal_color", _color("blue"))
	(_view.get_node("%BackupHint") as Label).text = "Waits until primary power fails."
	_toggle_btn.tooltip_text = "Starts automatically when primary power fails, provided fuel and condition allow."

	_power_btn.theme_type_variation = &"BunkerDangerButton" if _is_running else &"BunkerPrimaryButton"
	_power_btn.icon = STOPPED_ICON if _is_running else RUNNING_ICON
	_power_btn.text = "Shut down generator" if _is_running else "Start generator"
	var hint: String = "Starts this generator and supplies power to connected devices."
	var hint_color: Color = _color("secondary")
	if _is_running:
		hint = "Stops this generator. Devices relying on it may lose power."
	elif _grid_tripped:
		_power_btn.text = "Reset grid & start"
		hint = "Resets the main breaker and attempts to start this generator."
		hint_color = _color("warning")
	if not _is_running and (_fuel <= 0.0 or _health <= 0.0):
		hint = "Refuel and repair as needed before this generator can run." if not _grid_tripped else "Start resets the grid; this generator still needs fuel and working condition."
		hint_color = _color("warning")
	(_view.get_node("%ActionHint") as Label).text = hint
	(_view.get_node("%ActionHint") as Label).add_theme_color_override("font_color", hint_color)

func _set_status(card_name: String, text: String, color: Color, icon: Texture2D) -> void:
	var card: PanelContainer = _view.get_node("%" + card_name) as PanelContainer
	var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = _color("background").lerp(color, 0.08)
	style.border_color = _color("background").lerp(color, 0.48)
	var label: Label = card.get_node("Row/State") as Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	var texture: TextureRect = card.get_node("Row/Icon") as TextureRect
	texture.texture = icon
	texture.self_modulate = color

func _update_meter(prefix: String, value: float, threshold_key: String,
		good: String, low: String, critical: String, empty: String) -> void:
	var warn: float = _view.theme.get_constant(threshold_key + "_warn_thresh", "GeneratorInspector")
	var crit: float = _view.theme.get_constant(threshold_key + "_crit_thresh", "GeneratorInspector")
	var color: Color = _color("blue") if prefix == "Fuel" else _color("success")
	var hint: String = good
	if value <= crit:
		color = _color("critical")
		hint = empty if value <= 0.0 else critical
	elif value <= warn:
		color = _color("warning")
		hint = low
	(_view.get_node("%" + prefix + "Value") as Label).text = "%d%%" % int(value)
	var bar: ProgressBar = _view.get_node("%" + prefix + "Bar") as ProgressBar
	bar.value = value
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = color
	fill.border_color = color
	var label: Label = _view.get_node("%" + prefix + "Hint") as Label
	label.text = hint
	label.add_theme_color_override("font_color", _color("secondary") if value > warn else color)

func _grid_state_color(state: String) -> Color:
	match state:
		"ONLINE": return _color("success")
		"OVERLOADED", "TRIPPED": return _color("warning")
		"BROWNOUT": return _color("critical")
		_: return _color("inactive")

func _color(token: String) -> Color:
	return _view.theme.get_color(token, "Bunker")

func _process(_delta: float) -> void:
	if _controller_hints != InputMode.is_controller():
		_update_input_hints()

func _update_input_hints() -> void:
	_controller_hints = InputMode.is_controller()
	(_view.get_node("%NavigationHint") as Label).text = "[A] Select   •   D-pad: navigate   •   [B] Close" if _controller_hints else "Enter / Space: select   •   Esc / E: close"

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not _controller_nav._is_topmost():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()

func _on_toggle_pressed() -> void:
	if not _is_open:
		return
	# Display confirmed state only. The existing owner responds via refresh().
	_toggle_btn.set_pressed_no_signal(_is_backup)
	backup_toggled.emit(not _is_backup)

func _on_power_pressed() -> void:
	if _is_open:
		power_toggled.emit(not _is_running)
