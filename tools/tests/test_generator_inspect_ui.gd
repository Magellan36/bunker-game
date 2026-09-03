extends Node
## Run this scene headlessly for isolated presentation/API regression tests.
## Requires InputMode (normal project autoload); does not create a PowerManager.

const UI_SCRIPT: GDScript = preload("res://scripts/ui/power/GeneratorInspectUI.gd")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]
var _failures: Array[String] = []
var _power_requests: Array[bool] = []
var _backup_requests: Array[bool] = []
var _close_count: int = 0
var _world_clicks: int = 0

func _ready() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("Generator UI test timed out")
		get_tree().quit(2))
	_run.call_deferred()

func _run() -> void:
	var shared: Theme = load("res://assets/ui/themes/BunkerRedesignTheme.tres") as Theme
	var shared_margins: Vector4 = _style_margins(shared.get_stylebox("normal", "Button"))
	var plain_button := Button.new()
	var default_style: StyleBox = plain_button.get_theme_stylebox("disabled")
	var default_margins: Vector4 = _style_margins(default_style)
	plain_button.free()
	for resolution: Vector2i in SIZES:
		await _check_resolution(resolution)
	await _check_world_visibility_and_input()
	await _check_state_and_input()
	_expect(_style_margins(shared.get_stylebox("normal", "Button")) == shared_margins, "inspector changed shared character-creation button margins")
	_expect(_style_margins(default_style) == default_margins, "inspector changed engine fallback style margins")
	if _failures.is_empty():
		print("Generator inspector UI passed: six actual viewport sizes, compact right docking, world click-through, live resize, states, signals, focus, input and reopen.")
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	for frame: int in range(5):
		await get_tree().process_frame

func _check_resolution(resolution: Vector2i) -> void:
	get_window().size = resolution
	var ui: CanvasLayer = UI_SCRIPT.new()
	add_child(ui)
	ui.open("Generator M", 2000.0, 78.0, 94.0, false, true)
	await _settle()
	_expect(Vector2i(get_viewport().get_visible_rect().size) == resolution, "actual viewport size differs from test target")
	var panel: PanelContainer = ui._panel
	var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
	_expect(bounds.encloses(panel.get_global_rect()), "%s: panel outside viewport" % resolution)
	_check_dock(panel, Vector2(resolution), str(resolution))
	_expect(ui._power_btn.size.y >= 48.0, "%s: main action target too small" % resolution)
	_expect(ui._toggle_btn.size.y >= 44.0, "%s: backup target too small" % resolution)
	_expect(ui._toggle_btn.get_theme_font_size("font_size") >= 18, "%s: body text shrunk below desktop baseline" % resolution)
	_expect(panel.get_global_rect().encloses(ui._power_btn.get_global_rect()), "%s: main action outside panel" % resolution)
	_expect(panel.get_global_rect().encloses(ui._close_btn.get_global_rect()), "%s: Close outside panel" % resolution)
	var scroll: ScrollContainer = ui._view.get_node("%DetailsScroll") as ScrollContainer
	_expect(scroll.size.y > 200.0, "%s: details collapsed" % resolution)
	_expect(scroll.scroll_vertical == 0, "%s: inspector did not open at top" % resolution)
	if resolution == Vector2i(1920, 1080):
		_expect(panel.size.is_equal_approx(Vector2(500.0, 740.0)), "1080p panel no longer matches compact 500x740 spec")
		_expect(scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page, "normal 1080p layout needs unnecessary scrolling")
	var grid: PanelContainer = ui._view.get_node("%GridStatus") as PanelContainer
	_expect(grid.get_node("Row/State").size.x > 90.0, "%s: grid state cannot fit" % resolution)
	for state: String in ["ONLINE", "OVERLOADED", "BROWNOUT", "TRIPPED", "OFFLINE", "UNKNOWN"]:
		ui.refresh(78.0, 94.0, false, true, false, state)
		await _settle()
		_expect(grid.get_global_rect().encloses(grid.get_node("Row/State").get_global_rect()), "%s: grid label overflows: %s" % [resolution, state])
		_check_dock(panel, Vector2(resolution), "%s / %s" % [resolution, state])
	ui._toggle_btn.grab_focus()
	await _settle()
	_expect(scroll.get_global_rect().grow(1.0).encloses(ui._toggle_btn.get_global_rect()), "%s: focused Backup hidden by scrolling" % resolution)
	get_window().size = Vector2i(resolution.x + 50, resolution.y - 20)
	await _settle()
	bounds.size = Vector2(get_window().size)
	_expect(bounds.encloses(panel.get_global_rect()), "%s: resize escaped viewport" % resolution)
	_check_dock(panel, bounds.size, "%s live resize" % resolution)
	ui.close()
	ui.queue_free()
	await get_tree().process_frame

func _check_dock(panel: PanelContainer, viewport_size: Vector2, context: String) -> void:
	var factor: float = clampf(minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0), 1.0, 1.25)
	_expect(is_equal_approx(panel.size.x, 500.0 * factor), context + ": panel width exceeds compact spec")
	_expect(is_equal_approx(viewport_size.x - panel.get_global_rect().end.x, 24.0 * factor), context + ": panel is not right-docked")
	_expect(is_equal_approx(panel.position.y, (viewport_size.y - panel.size.y) * 0.5), context + ": panel is not vertically balanced")

func _check_world_visibility_and_input() -> void:
	get_window().size = Vector2i(1920, 1080)
	# This lower-layer native control stands in for world-facing mouse input.
	var world := Button.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.focus_mode = Control.FOCUS_NONE
	world.pressed.connect(func() -> void: _world_clicks += 1)
	add_child(world)
	var ui: CanvasLayer = UI_SCRIPT.new()
	add_child(ui)
	ui.open("Generator M", 2000.0, 100.0, 100.0, false, true)
	await _settle()
	_expect(not ui._view.has_node("Backdrop"), "screen-wide darkening layer was reintroduced")
	_expect(ui._view.get_child_count() == 1 and ui._view.get_child(0) == ui._panel, "inspector paints outside its panel subtree")
	_expect(ui._view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "root blocks exposed world input")
	_expect(ui._panel.mouse_filter == Control.MOUSE_FILTER_STOP, "panel does not contain its own mouse input")
	_click_at(Vector2(100.0, 540.0))
	await get_tree().process_frame
	_expect(_world_clicks == 1, "exposed world click was blocked")
	_click_at(ui._panel.position + Vector2(4.0, 4.0))
	await get_tree().process_frame
	_expect(_world_clicks == 1, "panel-background click leaked to world")
	ui.close()
	ui.queue_free()
	world.queue_free()
	await get_tree().process_frame

func _click_at(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = position
		click.global_position = position
		click.pressed = pressed
		Input.parse_input_event(click)

func _check_state_and_input() -> void:
	get_window().size = Vector2i(1920, 1080)
	var ui: CanvasLayer = UI_SCRIPT.new()
	add_child(ui)
	ui.power_toggled.connect(func(value: bool) -> void: _power_requests.append(value))
	ui.backup_toggled.connect(func(value: bool) -> void: _backup_requests.append(value))
	ui.closed.connect(func() -> void: _close_count += 1)
	ui.open("Generator L", 5000.0, 90.0, 100.0, false, true)
	await _settle()
	_expect(_status(ui, "GeneratorStatus") == "Running", "running status incorrect")
	_expect(_status(ui, "GridStatus") == "Grid online", "online state incorrect")
	for card_name: String in ["GeneratorStatus", "GridStatus"]:
		var icon: TextureRect = ui._view.get_node("%" + card_name).get_node("Row/Icon")
		_expect(icon.self_modulate == ui._view.theme.get_color("success", "Bunker"), "healthy status is not green: " + card_name)
	_expect(ui._close_btn.has_focus(), "initial focus is not on safe Close action")
	ui._toggle_btn.grab_focus()
	await _settle()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = ui._toggle_btn.get_global_rect().get_center()
		click.global_position = click.position
		click.pressed = pressed
		Input.parse_input_event(click)
	await get_tree().process_frame
	_expect(_backup_requests == [true], "native mouse click did not request backup mode")
	_backup_requests.clear()
	ui._power_btn.grab_focus()
	_accept()
	await get_tree().process_frame
	_expect(_power_requests == [false], "native accept did not emit exactly one shutdown request")
	_expect(_status(ui, "GeneratorStatus") == "Running", "UI invented success without owner refresh")

	ui.refresh(70.0, 60.0, true, false, false, "ONLINE")
	_expect(_status(ui, "GeneratorStatus") == "Standby", "backup standby not represented")
	ui._toggle_btn.grab_focus()
	_accept()
	await get_tree().process_frame
	_expect(_backup_requests == [false], "backup disable signal incorrect")
	_expect(ui._toggle_btn.button_pressed, "backup toggle invented unconfirmed state")

	ui.refresh(20.0, 25.0, false, false, true, "TRIPPED")
	_expect(ui._power_btn.text == "Reset grid & start", "tripped-grid action lost")
	ui._power_btn.grab_focus()
	_accept()
	await get_tree().process_frame
	_expect(_power_requests == [false, true], "tripped-grid restart signal incorrect")
	_expect(_status(ui, "GridStatus") == "Grid tripped", "tripped-grid badge incorrect")
	_expect((ui._view.get_node("%FuelHint") as Label).text == "Very low fuel", "fuel threshold changed")
	_expect((ui._view.get_node("%ConditionHint") as Label).text == "Critical condition", "condition threshold changed")
	for meter_name: String in ["FuelBar", "ConditionBar"]:
		var meter: ProgressBar = ui._view.get_node("%" + meter_name)
		_expect((meter.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == ui._view.theme.get_color("critical", "Bunker"), "critical meter colour incorrect: " + meter_name)
	for grid_state: String in ["ONLINE", "OVERLOADED", "BROWNOUT", "TRIPPED", "OFFLINE", "UNKNOWN"]:
		ui.refresh(100.0, 100.0, false, false, false, grid_state)
		_expect(_status(ui, "GridStatus") == "Grid " + grid_state.to_lower(), "grid state missing: " + grid_state)
	ui.refresh(-10.0, 140.0, false, false, false, "OFFLINE")
	_expect((ui._view.get_node("%FuelBar") as ProgressBar).value == 0.0, "fuel clamp lost")
	_expect((ui._view.get_node("%ConditionBar") as ProgressBar).value == 100.0, "health clamp lost")
	_expect((ui._view.get_node("%Watts") as Label).text == "5000 W", "rated output incorrectly replaced by guessed live draw")

	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	InputMode._input(joy)
	await _settle()
	_expect((ui._view.get_node("%NavigationHint") as Label).text.contains("[B]"), "controller hints not switched")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	InputMode._input(key)
	await _settle()
	_expect((ui._view.get_node("%NavigationHint") as Label).text.contains("Esc / E"), "keyboard hints not restored")

	var second: CanvasLayer = UI_SCRIPT.new()
	add_child(second)
	second.open("Generator S", 800.0, 100.0, 100.0, false, true)
	_expect(_status(second, "GeneratorStatus") == "Running", "second instance not independent")
	_expect(ui._view.theme != second._view.theme, "mutable theme shared across instances")
	second.close()
	second.queue_free()
	await get_tree().process_frame
	ui._close_btn.grab_focus()
	ui._controller_nav._move_cooldown = 0.0
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	await _settle()
	_expect(ui._toggle_btn.has_focus(), "D-pad did not reach Backup")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	# A higher menu must own cancel rather than also closing the inspector.
	var higher := CanvasLayer.new()
	higher.layer = 200
	add_child(higher)
	var higher_nav: Node = ui.NAV_SCRIPT.new()
	higher_nav.ui_root = higher
	higher.add_child(higher_nav)
	var blocked_escape := InputEventKey.new()
	blocked_escape.keycode = KEY_ESCAPE
	blocked_escape.pressed = true
	ui._unhandled_input(blocked_escape)
	_expect(ui.is_open(), "lower inspector handled Escape under a higher menu")
	Input.parse_input_event(back)
	await _settle()
	_expect(ui.is_open() and not higher.visible, "B closed more than the topmost menu")
	higher.queue_free()
	await get_tree().process_frame
	Input.parse_input_event(back)
	await _settle()
	_expect(not ui.is_open(), "B did not close inspector")
	ui.close()
	_expect(_close_count == 1, "close signal emitted more than once")

	ui.open("Backup Generator L — Emergency reserve", 5000.0, 50.0, 50.0, true, false)
	await _settle()
	_check_dock(ui._panel, Vector2(1920.0, 1080.0), "long generator name")
	_expect((ui._view.get_node("%DetailsScroll") as ScrollContainer).scroll_vertical == 0, "reopen did not reset scroll")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _settle()
	_expect(not ui.is_open(), "Escape did not close inspector")
	ui.open("Generator S", 800.0, 100.0, 100.0, false, false)
	await _settle()
	escape.keycode = KEY_E
	Input.parse_input_event(escape)
	await _settle()
	_expect(not ui.is_open(), "E did not close inspector")
	ui.queue_free()
	await get_tree().process_frame

func _status(ui: CanvasLayer, card: String) -> String:
	return (ui._view.get_node("%" + card).get_node("Row/State") as Label).text

func _style_margins(style: StyleBox) -> Vector4:
	return Vector4(style.content_margin_left, style.content_margin_top,
		style.content_margin_right, style.content_margin_bottom)

func _accept() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"ui_accept"
		event.pressed = pressed
		Input.parse_input_event(event)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
