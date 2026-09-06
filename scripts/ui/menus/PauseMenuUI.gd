extends CanvasLayer
## Desktop pause workspace: primary actions at left, filterable Bunker Log at
## right. The world continues to simulate; only player movement is locked.

const PANEL_MAX := Vector2(1240, 760)
const PANEL_MARGIN := Vector2(56, 42)

var world_node: Node3D
var player: Node3D

var _visible_state := false
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _blur_rect: ColorRect
var _panel: PanelContainer
var _continue_button: Button
var _slot_panel: PanelContainer
var _slot_title: Label
var _save_slots: VBoxContainer
var _load_slots: VBoxContainer
var _save_slot_buttons: Array[Button] = []
var _load_slot_buttons: Array[Button] = []
var _confirm_dialog: CanvasLayer
var _exit_confirmed_connected := false
var _settings_panel: CanvasLayer
var _history_ui: Control

func _ready() -> void:
	layer = 200
	_build_ui()
	visible = false
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	nav.stick_navigation = true
	nav.close_on_cancel = false
	add_child(nav)
	get_viewport().size_changed.connect(_layout)
	_layout()

func toggle() -> void:
	if _visible_state:
		close()
	else:
		open()

func open() -> void:
	if _visible_state:
		return
	_visible_state = true
	visible = true
	_slot_panel.hide()
	_refresh_slot_labels()
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", true)
	UIFade.fade_in(_panel)
	_continue_button.call_deferred("grab_focus")

func close() -> void:
	if not _visible_state:
		return
	_visible_state = false
	visible = false
	_close_confirm_dialog()
	Input.mouse_mode = _prev_mouse_mode
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", false)

func is_open() -> bool:
	return _visible_state

func _unhandled_input(event: InputEvent) -> void:
	if not _visible_state:
		return
	var cancel_pressed: bool = event is InputEventKey and event.pressed \
		and event.keycode == KEY_ESCAPE
	cancel_pressed = cancel_pressed or (event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_B)
	if cancel_pressed:
		if _confirm_dialog != null and _confirm_dialog.has_method("is_open") \
				and _confirm_dialog.call("is_open"):
			_close_confirm_dialog()
		elif _slot_panel.visible:
			_slot_panel.hide()
		else:
			close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_blur_rect = UIKit.build_modal_backdrop()
	add_child(_blur_rect)
	_panel = PanelContainer.new()
	BunkerPanelStyle.panel(_panel)
	_panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		Color("111615fa"), BunkerPanelStyle.BRASS.darkened(0.05), 8, 1))
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(BunkerPanelStyle.margin(outer, 18, 16, 18, 12))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)
	columns.add_child(_build_action_rail())
	var separator := VSeparator.new()
	columns.add_child(separator)
	var history_holder := MarginContainer.new()
	history_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_holder.add_theme_constant_override("margin_left", 8)
	columns.add_child(history_holder)
	_history_ui = NotificationHistoryUI.new()
	history_holder.add_child(_history_ui)
	var footer_line := HSeparator.new()
	outer.add_child(footer_line)
	outer.add_child(_build_footer())

func _build_action_rail() -> Control:
	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = 300
	rail.add_theme_constant_override("separation", 9)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 9)
	var bunker_icon := TextureRect.new()
	bunker_icon.texture = BunkerPanelStyle.icon("storage")
	bunker_icon.self_modulate = BunkerPanelStyle.BLUE
	bunker_icon.custom_minimum_size = Vector2(40, 40)
	bunker_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bunker_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(bunker_icon)
	var bunker := Label.new()
	bunker.text = "BUNKER"
	bunker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bunker.add_theme_font_size_override("font_size", 18)
	bunker.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	brand.add_child(bunker)
	rail.add_child(brand)
	var paused := Label.new()
	paused.text = "PAUSED"
	paused.add_theme_font_size_override("font_size", 42)
	paused.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	rail.add_child(paused)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	rail.add_child(spacer)
	_continue_button = _action_button("Continue", "running", _on_continue_pressed, true)
	rail.add_child(_continue_button)
	rail.add_child(_action_button("Save Game", "save", _on_save_pressed))
	rail.add_child(_action_button("Load Game", "load", _on_load_pressed))
	rail.add_child(_action_button("Settings", "settings", _on_settings_pressed))
	_slot_panel = _build_slot_panel()
	_slot_panel.hide()
	rail.add_child(_slot_panel)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(grow)
	var exit_button := _action_button("Exit to Desktop", "exit", _on_exit_pressed, false, true)
	rail.add_child(exit_button)
	return rail

func _action_button(caption: String, symbol: String, callback: Callable,
		accent: bool = false, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 56
	BunkerPanelStyle.icon_button(button, symbol, accent, danger)
	button.pressed.connect(callback)
	return button

func _build_slot_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BunkerPanelStyle.box(
		BunkerPanelStyle.SURFACE, BunkerPanelStyle.BRASS.darkened(0.24), 6, 1))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(BunkerPanelStyle.margin(body, 8, 8, 8, 8))
	_slot_title = Label.new()
	BunkerPanelStyle.muted(_slot_title, 12)
	body.add_child(_slot_title)
	_save_slots = VBoxContainer.new()
	_save_slots.add_theme_constant_override("separation", 4)
	body.add_child(_save_slots)
	_load_slots = VBoxContainer.new()
	_load_slots.add_theme_constant_override("separation", 4)
	body.add_child(_load_slots)
	for slot: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var save_button := Button.new()
		save_button.custom_minimum_size.y = 38
		BunkerPanelStyle.button(save_button)
		save_button.pressed.connect(_on_save_slot_pressed.bind(slot))
		_save_slots.add_child(save_button)
		_save_slot_buttons.append(save_button)
		var load_button := Button.new()
		load_button.custom_minimum_size.y = 38
		BunkerPanelStyle.button(load_button)
		load_button.pressed.connect(_on_load_slot_pressed.bind(slot))
		_load_slots.add_child(load_button)
		_load_slot_buttons.append(load_button)
	return panel

func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 34)
	for hint_text: String in [
		"A / Enter   Select",
		"B / Esc   Resume",
		"Right stick / D-pad   Navigate",
	]:
		var hint := Label.new()
		hint.text = hint_text
		BunkerPanelStyle.muted(hint, 12)
		footer.add_child(hint)
	return footer

func _layout() -> void:
	if _panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var panel_size := Vector2(
		minf(PANEL_MAX.x, viewport.x - PANEL_MARGIN.x * 2.0),
		minf(PANEL_MAX.y, viewport.y - PANEL_MARGIN.y * 2.0))
	_panel.position = (viewport - panel_size) * 0.5
	_panel.size = panel_size

func _show_slots(saving: bool) -> void:
	_refresh_slot_labels()
	_slot_title.text = "CHOOSE A SAVE SLOT" if saving else "CHOOSE A LOAD SLOT"
	_save_slots.visible = saving
	_load_slots.visible = not saving
	_slot_panel.show()
	var target: Button = _save_slot_buttons[0] if saving else _load_slot_buttons[0]
	target.call_deferred("grab_focus")

func _refresh_slot_labels() -> void:
	for i: int in range(_save_slot_buttons.size()):
		var slot := i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		_save_slot_buttons[i].text = "Slot %d   •   %s" % [slot,
			"Overwrite Day %s" % str(info.get("day", "?")) if info.get("exists", false) else "Empty"]
	for i: int in range(_load_slot_buttons.size()):
		var slot := i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		if info.get("exists", false):
			_load_slot_buttons[i].text = "Slot %d   •   Day %s  %s" % [
				slot, str(info.get("day", "?")), str(info.get("time_display", "?"))]
			_load_slot_buttons[i].disabled = false
		else:
			_load_slot_buttons[i].text = "Slot %d   •   Empty" % slot
			_load_slot_buttons[i].disabled = true

func _on_continue_pressed() -> void:
	close()

func _on_save_pressed() -> void:
	_show_slots(true)

func _on_load_pressed() -> void:
	_show_slots(false)

func _on_save_slot_pressed(slot: int) -> void:
	SaveManager.save_game(slot)
	_refresh_slot_labels()
	_slot_panel.hide()
	_continue_button.grab_focus()

func _on_load_slot_pressed(slot: int) -> void:
	SaveManager.load_game(slot)
	close()

func _on_settings_pressed() -> void:
	if _settings_panel == null:
		var script := load("res://scripts/ui/menus/GraphicsSettingsPanel.gd") as GDScript
		if script == null:
			push_warning("[PauseMenu] GraphicsSettingsPanel.gd not found")
			return
		_settings_panel = CanvasLayer.new()
		_settings_panel.set_script(script)
		_settings_panel.name = "GraphicsSettingsPanel"
		get_parent().add_child(_settings_panel)
	if _settings_panel.has_method("open"):
		_settings_panel.open()

func _on_exit_pressed() -> void:
	_ensure_confirm_dialog()
	_confirm_dialog.open(
		"Exit to desktop?",
		"Any progress made since the last save will be lost.",
		"Exit game",
		"Stay here",
		"danger",
		"exit"
	)
	if not _exit_confirmed_connected:
		_confirm_dialog.confirmed.connect(func() -> void: get_tree().quit())
		_exit_confirmed_connected = true

func _ensure_confirm_dialog() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		return
	var dialog_script := load("res://scripts/ui/common/ConfirmDialogUI.gd") as GDScript
	if dialog_script == null:
		push_warning("[PauseMenuUI] ConfirmDialogUI.gd not found")
		return
	_confirm_dialog = CanvasLayer.new()
	_confirm_dialog.set_script(dialog_script)
	_confirm_dialog.name = "ConfirmDialogUI"
	_confirm_dialog.set("stacking_layer", 210)
	add_child(_confirm_dialog)

func _close_confirm_dialog() -> void:
	if _confirm_dialog != null and is_instance_valid(_confirm_dialog):
		_confirm_dialog.call("close")
