extends CanvasLayer
## Native generator inspector, opt-in redesign pass 2.
## Presentation only: GeneratorObject owns state, restart/reset policy and actions.
## The original open/refresh signatures and signals are intentionally unchanged.

signal closed
signal backup_toggled(enabled: bool)
signal power_toggled(running: bool)

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/power/GeneratorInspectPanel.tscn")
const W: GDScript = preload("res://scripts/ui/common/BunkerInspectorWidgets.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const FADE_SCRIPT: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")

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
var _toggle_btn: CheckButton
var _rail: Control
var _power_btn: Button
var _close_btn: Button
var _controller_nav: Node
var _proximity: Node

func _ready() -> void:
	layer = 60
	visible = false
	_view = PANEL_SCENE.instantiate() as Control
	add_child(_view)
	_panel = _view.get_node("%Panel") as PanelContainer
	Q.avoid_toasts(_panel, false)  # never covered by toasts
	_toggle_btn = _view.get_node("%Backup") as CheckButton
	_power_btn = _view.get_node("%Power") as Button
	_close_btn = _view.get_node("%Close") as Button
	_quiet_style()
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	_power_btn.pressed.connect(_on_power_pressed)
	_close_btn.pressed.connect(close)
	_configure_focus()
	_controller_nav = NAV_SCRIPT.new()
	_controller_nav.ui_root = self
	# Preserve in-world controls: D-pad navigates; left stick stays for movement.
	_controller_nav.stick_navigation = false
	add_child(_controller_nav)
	_proximity = preload("res://scripts/ui/common/UIProximityClose.gd").new()
	_proximity.ui = self
	add_child(_proximity)
	set_process(false)

## Sep 2026 quiet pass: same scene contract, quiet language (shared with
## every device inspector through W.quiet_shell). Readings are rows, status
## is dot + word, meters are 3 px, the power action is the one primary.
func _quiet_style() -> void:
	_rail = W.quiet_shell(_view, _close_btn)
	get_viewport().gui_focus_changed.connect(func(control: Control) -> void:
		if _is_open and control != null and _view.is_ancestor_of(control):
			_rail.call("set_target", null if control == _close_btn else control))
	var watts_label := _view.get_node("%Watts") as Label
	watts_label.add_theme_color_override("font_color", Q.TEXT)
	watts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for card_name: String in ["GeneratorStatus", "GridStatus"]:
		var card: PanelContainer = _view.get_node("%" + card_name) as PanelContainer
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var dot: TextureRect = card.get_node("Row/Icon") as TextureRect
		dot.texture = Q._disc(16, Color.WHITE)
		dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.set_meta("ui_icon_size", 8)
		dot.custom_minimum_size = Vector2(8, 8)
		var word: Label = card.get_node("Row/State") as Label
		word.set_meta("ui_font_size", 15)
		word.autowrap_mode = TextServer.AUTOWRAP_OFF
		word.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for prefix: String in ["Fuel", "Condition"]:
		var bar: ProgressBar = _view.get_node("%" + prefix + "Bar") as ProgressBar
		bar.theme_type_variation = &""
		Q.meter(bar, 3.0)
		(_view.get_node("%" + prefix + "Hint") as Label).set_meta("ui_font_size", 13)
	Q.switch(_toggle_btn, 15)
	_toggle_btn.custom_minimum_size.y = 34.0   ## keep the approved 34 px target
	(_view.get_node("%BackupHint") as Label).set_meta("ui_font_size", 13)
	(_view.get_node("%BackupHint") as Label).add_theme_color_override("font_color", Q.MUTED)
	(_view.get_node("%ActionHint") as Label).set_meta("ui_font_size", 13)
	_power_btn.theme_type_variation = &""
	_power_btn.icon = null
	Q.primary_action(_power_btn, 16, 40.0)

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
		grid_state_str: String = "ONLINE", device: Node3D = null) -> void:
	if not _is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	if is_instance_valid(device):
		_proximity.bind_target(device)
	else:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		_proximity.bind_position(player.global_position if is_instance_valid(player) else Vector3.ZERO)
	_display_name = display_name
	_watts = watts
	_last_display_state.clear()
	_is_open = true
	UIPanelLifecycle.prepare_open(self)
	visible = true
	refresh(fuel, health, is_backup, is_running, grid_tripped, grid_state_str)
	_update_input_hints()
	set_process(true)
	# Safe initial target: opening an inspector must not prime a shutdown.
	_close_btn.grab_focus()
	_rail.call("set_target", null)
	_rail.call("snap")
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
	set_process(false)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _view.is_ancestor_of(focused):
		focused.release_focus()
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref() as Control
			if is_instance_valid(previous) and previous.is_visible_in_tree():
				previous.grab_focus()
	UIPanelLifecycle.dismiss(self, _view)
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
	var status_token: String = "inactive"
	if _is_running:
		status_text = "Running"
		status_token = "success"
	elif _grid_tripped:
		status_text = "Offline"
		status_token = "warning"
	elif _is_backup:
		status_text = "Standby"
		status_token = "blue"
	_set_status("GeneratorStatus", status_text, status_token)

	var grid_state: String = "TRIPPED" if _grid_tripped else _grid_state_str
	var grid_text: String = "Grid " + grid_state.to_lower()
	if grid_state.is_empty():
		grid_text = "Grid unknown"
	_set_status("GridStatus", grid_text, _grid_state_token(grid_state))
	# The passed grid state is global; this is not a per-generator wire check.
	(_view.get_node("%GridStatus") as Control).tooltip_text = "Bunker-wide grid state. Does not confirm this generator's wire connection."

	_update_meter("Fuel", _fuel, "fuel", "", "Low fuel", "Very low fuel", "Empty — refuel to run")
	_update_meter("Condition", _health, "health", "", "Worn — maintenance advised", "Critical condition", "Broken — repair required")
	W.set_switch(_toggle_btn, _is_backup)
	(_view.get_node("%BackupHint") as Label).text = "This generator will power on when other power sources fail."
	_toggle_btn.tooltip_text = ""

	W.set_power_button(_power_btn, _is_running)
	var hint: String = "Starts this generator and supplies power to connected devices."
	var hint_color: Color = _color("secondary")
	if _is_running:
		hint = ""
	elif _grid_tripped:
		hint = "Resets the main breaker and attempts to start this generator."
		hint_color = _color("warning")
	if not _is_running and (_fuel <= 0.0 or _health <= 0.0):
		hint = "Refuel and repair as needed before this generator can run." if not _grid_tripped else "Start resets the grid; this generator still needs fuel and working condition."
		hint_color = _color("warning")
	var action_hint := _view.get_node("%ActionHint") as Label
	action_hint.text = hint
	action_hint.visible = not hint.is_empty()
	action_hint.add_theme_color_override("font_color", hint_color)

func _set_status(card_name: String, text: String, token: String) -> void:
	W.set_status(_view.get_node("%" + card_name) as PanelContainer, text, token)

func _update_meter(prefix: String, value: float, threshold_key: String,
		good: String, low: String, critical: String, empty: String) -> void:
	var warn: float = _view.theme.get_constant(threshold_key + "_warn_thresh", "GeneratorInspector")
	var crit: float = _view.theme.get_constant(threshold_key + "_crit_thresh", "GeneratorInspector")
	var meter_state: String = "normal"
	var hint: String = good
	if value <= crit:
		meter_state = "critical"
		hint = empty if value <= 0.0 else critical
	elif value <= warn:
		meter_state = "warning"
		hint = low
	var readout: Label = _view.get_node("%" + prefix + "Value") as Label
	readout.text = "%d%%" % int(value)
	readout.add_theme_color_override("font_color", Q.state_color(meter_state, Q.MUTED))
	var bar: ProgressBar = _view.get_node("%" + prefix + "Bar") as ProgressBar
	SMOOTH_BAR.apply(bar, value)
	Q.set_meter_state(bar, meter_state)
	var label: Label = _view.get_node("%" + prefix + "Hint") as Label
	label.text = hint
	label.visible = not hint.is_empty()
	label.add_theme_color_override("font_color", Q.state_color(meter_state, Q.MUTED))

func _grid_state_token(state: String) -> String:
	match state:
		"ONLINE": return "success"
		"OVERLOADED", "TRIPPED": return "warning"
		"BROWNOUT": return "critical"
		_: return "inactive"

func _color(token: String) -> Color:
	return W.color(_view, token)

func _process(_delta: float) -> void:
	if _controller_hints != InputMode.is_controller():
		_update_input_hints()

func _update_input_hints() -> void:
	_controller_hints = InputMode.is_controller()
	(_view.get_node("%NavigationHint") as Label).text = "[A] Select · D-pad / R-stick: navigate · [B] Close" if _controller_hints else "Enter / Space: select · Esc / E: close"

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
