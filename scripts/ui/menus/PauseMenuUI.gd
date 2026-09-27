extends CanvasLayer
## Pause workspace (Sep 2026 quiet pass, sibling of Graphics Settings).
## Left rail: brand, "Paused", Continue / Save game / Load game / Settings,
## Exit at the bottom. Right: the Log; Save/Load swap it for a slot list.
## The world keeps simulating; only player movement is locked (unchanged).
## Save/load authority stays with SaveManager; exit still confirms through
## the shared ConfirmDialogUI.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const FOCUS_RAIL: GDScript = preload("res://scripts/ui/common/FocusRail.gd")
const FOOTER: GDScript = preload("res://scripts/ui/common/QuietFooter.gd")
const SLOT_FORMAT: GDScript = preload("res://scripts/ui/common/SaveSlotFormat.gd")

const PANEL_MAX := Vector2(1240, 760)
const PANEL_MARGIN := Vector2(56, 42)
const RAIL_WIDTH: float = 232.0
const IDLE_HINT: String = "The bunker keeps running while you are paused."

var world_node: Node3D
var player: Node3D

var _visible_state := false
var _prev_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _blur_rect: ColorRect
var _panel: PanelContainer
var _workspace: Control
var _footer: HBoxContainer
var _continue_button: Button
var _save_button: Button
var _load_button: Button
var _settings_button: Button
var _exit_button: Button
var _action_rail: Control
var _slot_rail: Control
var _history_ui: Control
var _slot_view: VBoxContainer
var _slot_eyebrow: Label
var _slot_title: Label
var _slot_buttons: Array[Button] = []
var _slot_back: Button
var _saving := false
var _view_tween: Tween
var _open_tween: Tween
var _confirm_dialog: CanvasLayer
var _exit_confirmed_connected := false
var _settings_panel: CanvasLayer

func _ready() -> void:
	layer = 200
	_build_ui()
	visible = false
	var nav := ControllerUINavigation.new()
	nav.ui_root = self
	nav.stick_navigation = false
	nav.close_on_cancel = false
	add_child(nav)
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_layout()

func toggle() -> void:
	if _visible_state:
		close()
	else:
		open()

func open() -> void:
	if _visible_state:
		return
	UIPanelLifecycle.prepare_open(self)
	_visible_state = true
	visible = true
	_show_log(false)
	_refresh_slot_labels()
	_footer.call("show_hint", "", "")
	_footer.call("hide_saved")
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", true)
	_layout()
	_play_open()
	_action_rail.call("snap")
	_continue_button.call_deferred("grab_focus")

func close() -> void:
	if not _visible_state:
		return
	_visible_state = false
	_close_confirm_dialog()
	Input.mouse_mode = _prev_mouse_mode
	if player != null and player.has_method("set_movement_locked"):
		player.call("set_movement_locked", false)
	if is_instance_valid(_open_tween):
		_open_tween.kill()
	create_tween().tween_property(_blur_rect, "modulate:a", 0.0, UIMotion.duration(UIMotion.EXIT))
	UIPanelLifecycle.dismiss(self, _panel)

func is_open() -> bool:
	return _visible_state

func _unhandled_input(event: InputEvent) -> void:
	if not _visible_state:
		return
	var cancel_pressed: bool = event is InputEventKey and event.pressed \
		and event.keycode in [KEY_ESCAPE, KEY_E]
	cancel_pressed = cancel_pressed or (event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_B)
	if cancel_pressed:
		if _confirm_dialog != null and _confirm_dialog.has_method("is_open") \
				and _confirm_dialog.call("is_open"):
			_close_confirm_dialog()
		elif _slot_view.visible:
			_show_log(true)
			(_save_button if _saving else _load_button).grab_focus()
		else:
			close()
		get_viewport().set_input_as_handled()

## Same opening as Settings: backdrop dims in, the shell rises as it fades.
func _play_open() -> void:
	if is_instance_valid(_open_tween):
		_open_tween.kill()
	UIFade.fade_in(_panel, 0.22)
	if UIMotion.reduced():
		_blur_rect.modulate.a = 1.0
		_workspace.modulate.a = 1.0
		return
	var rest_y := _panel.position.y
	_panel.position.y = rest_y + 16.0
	_blur_rect.modulate.a = 0.0
	_workspace.modulate.a = 0.0
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_blur_rect, "modulate:a", 1.0, 0.22)
	_open_tween.tween_property(_panel, "position:y", rest_y, 0.36) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_workspace, "modulate:a", 1.0, 0.28).set_delay(0.07)

# ── Build ────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_blur_rect = UIKit.build_modal_backdrop()
	add_child(_blur_rect)
	_panel = PanelContainer.new()
	_panel.name = "PauseShell"
	BunkerUIComponents.apply_theme(_panel)
	_panel.add_theme_stylebox_override("panel", Q.shell_box(12))
	Q.avoid_toasts(_panel, true)
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_panel.add_child(BunkerUIComponents.inset(outer, 30, 28, 22, 16))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 30)
	outer.add_child(columns)
	columns.add_child(_build_action_rail())
	var separator := VSeparator.new()
	separator.add_theme_stylebox_override("separator", Q.hairline(true))
	columns.add_child(separator)
	_workspace = Control.new()
	_workspace.name = "PauseWorkspace"
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(_workspace)
	_history_ui = NotificationHistoryUI.new()
	_workspace.add_child(_history_ui)
	_history_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace.add_child(_build_slot_view())
	var footer_line := HSeparator.new()
	footer_line.add_theme_stylebox_override("separator", Q.hairline())
	footer_line.add_theme_constant_override("separation", 22)
	outer.add_child(footer_line)
	_footer = FOOTER.new()
	_footer.set("idle_hint", IDLE_HINT)
	_footer.call("add_key_hint", "ENTER", "Select", "ENTER", "A")
	_footer.call("add_key_hint", "ESC", "Resume", "ESC", "B")
	outer.add_child(_footer)

func _build_action_rail() -> Control:
	var rail := VBoxContainer.new()
	rail.name = "PauseActionRail"
	rail.custom_minimum_size.x = RAIL_WIDTH
	rail.add_theme_constant_override("separation", 0)
	rail.add_child(Q.eyebrow("Bunker Game", 12))
	rail.add_child(_gap(6.0))
	rail.add_child(Q.label("Paused", 40, Q.TEXT))
	rail.add_child(_gap(30.0))
	var host := Control.new()
	host.name = "ActionLinks"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size.y = 4 * 46.0
	rail.add_child(host)
	_action_rail = _make_rail(0.0, 0.92)
	host.add_child(_action_rail)
	_action_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var links := VBoxContainer.new()
	links.add_theme_constant_override("separation", 6)
	host.add_child(links)
	links.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_continue_button = _action("Continue", "Return to the bunker.", _on_continue_pressed)
	_save_button = _action("Save game", "Write this run to one of three slots.", _on_save_pressed)
	_load_button = _action("Load game", "Replace this run with a saved one.", _on_load_pressed)
	_settings_button = _action("Settings", "Display, quality and comfort options.", _on_settings_pressed)
	for button: Button in [_continue_button, _save_button, _load_button, _settings_button]:
		links.add_child(button)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(grow)
	_exit_button = Button.new()
	_exit_button.name = "ExitToDesktop"
	_exit_button.text = "Exit to desktop"
	Q.destructive_action(_exit_button, 15, 30.0)
	_exit_button.set_meta(&"help", "Close the game. Progress since your last save is lost.")
	_exit_button.pressed.connect(_on_exit_pressed)
	rail.add_child(_exit_button)
	return rail

func _action(caption: String, help: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = caption.to_pascal_case()
	button.text = caption
	Q.nav_button(button, 17, 40.0)
	button.set_meta(&"help", help)
	button.pressed.connect(callback)
	button.mouse_entered.connect(func() -> void:
		if _visible_state and InputMode.is_keyboard() and not button.has_focus():
			button.grab_focus())
	return button

func _build_slot_view() -> VBoxContainer:
	_slot_view = VBoxContainer.new()
	_slot_view.name = "SlotView"
	_slot_view.visible = false
	_slot_view.add_theme_constant_override("separation", 0)
	_slot_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_eyebrow = Q.eyebrow("Save game", 12)
	_slot_view.add_child(_slot_eyebrow)
	_slot_view.add_child(_gap(4.0))
	_slot_title = Q.label("Choose a slot", 26, Q.TEXT)
	_slot_view.add_child(_slot_title)
	_slot_view.add_child(_gap(22.0))
	var host := Control.new()
	host.name = "Slots"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size.y = SaveManager.SAVE_SLOT_COUNT * 66.0
	_slot_view.add_child(host)
	_slot_rail = _make_rail(0.0, 0.7)
	host.add_child(_slot_rail)
	_slot_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	host.add_child(list)
	list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for slot: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var button: Button = Q.list_action("Slot %d" % slot, "Empty", 60.0)
		button.name = "Slot%d" % slot
		button.pressed.connect(_on_slot_pressed.bind(slot))
		button.mouse_entered.connect(func() -> void:
			if _visible_state and InputMode.is_keyboard() and not button.has_focus() \
					and not button.disabled:
				button.grab_focus())
		list.add_child(button)
		_slot_buttons.append(button)
	_slot_view.add_child(_gap(18.0))
	_slot_back = Button.new()
	_slot_back.name = "BackToLog"
	_slot_back.text = "←   Back to log"
	Q.nav_button(_slot_back, 15, 30.0)
	_slot_back.set_meta(&"help", "Return to the activity log.")
	_slot_back.pressed.connect(func() -> void:
		_show_log(true)
		(_save_button if _saving else _load_button).grab_focus())
	_slot_view.add_child(_slot_back)
	return _slot_view

func _make_rail(offset: float, extent: float) -> Control:
	var rail: Control = FOCUS_RAIL.new()
	rail.set("rail_offset", offset)
	rail.set("rail_width", 2.0)
	rail.set("wash_extent", extent)
	rail.set("wash_alpha", 0.08)
	rail.set("inset_fraction", 0.22)
	rail.set("glow", false)
	rail.set("color", Q.ACCENT)
	return rail

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

func _layout() -> void:
	if _panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	UIPanelLayout.fit(_panel, viewport, PANEL_MAX, PANEL_MARGIN)

# ── Views ────────────────────────────────────────────────────────────────────

func _show_log(animate: bool) -> void:
	_swap(_history_ui, _slot_view, animate)

func _show_slots(saving: bool) -> void:
	_saving = saving
	_refresh_slot_labels()
	_slot_eyebrow.text = ("Save game" if saving else "Load game").to_upper()
	_slot_title.text = "Choose a slot to overwrite" if saving else "Choose a save to load"
	_swap(_slot_view, _history_ui, true)
	var target: Button = _slot_back
	for button: Button in _slot_buttons:
		if not button.disabled:
			target = button
			break
	_slot_rail.call("snap")
	target.call_deferred("grab_focus")

## Main-menu view swap: old fades/slides out, new slides in from the right.
func _swap(incoming: Control, outgoing: Control, animate: bool) -> void:
	if is_instance_valid(_view_tween):
		_view_tween.kill()
	incoming.visible = true
	incoming.position.x = 0.0
	if not animate or UIMotion.reduced() or not outgoing.visible:
		outgoing.visible = false
		incoming.modulate.a = 1.0
		return
	incoming.modulate.a = 0.0
	_view_tween = create_tween().set_parallel(true)
	_view_tween.tween_property(outgoing, "modulate:a", 0.0, 0.12)
	_view_tween.tween_property(incoming, "modulate:a", 1.0, 0.24).set_delay(0.1)
	_view_tween.tween_property(incoming, "position:x", 0.0, 0.34).from(26.0).set_delay(0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_view_tween.chain().tween_callback(func() -> void:
		outgoing.visible = false
		outgoing.modulate.a = 1.0)

func _refresh_slot_labels() -> void:
	for i: int in range(_slot_buttons.size()):
		var slot := i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		var exists: bool = info.get("exists", false)
		var caption: String = SLOT_FORMAT.describe(info) if exists else "Empty"
		if _saving and exists:
			caption = "Overwrite  ·  " + caption
		Q.set_list_action(_slot_buttons[i], "Slot %d" % slot, caption, not _saving and not exists)
		_slot_buttons[i].set_meta(&"help", ("Save this run to slot %d." % slot) if _saving
			else ("Load slot %d." % slot))

func _on_focus_changed(control: Control) -> void:
	if not _visible_state or control == null or not _panel.is_ancestor_of(control):
		return
	if control in [_continue_button, _save_button, _load_button, _settings_button]:
		_action_rail.call("set_target", control)
	elif control in _slot_buttons:
		_slot_rail.call("set_target", control)
	_footer.call("show_hint", str(control.get_meta(&"help", "")), "")

# ── Actions (behaviour unchanged) ────────────────────────────────────────────

func _on_continue_pressed() -> void:
	close()

func _on_save_pressed() -> void:
	_show_slots(true)

func _on_load_pressed() -> void:
	_show_slots(false)

func _on_slot_pressed(slot: int) -> void:
	if _saving:
		SaveManager.save_game(slot)
		_refresh_slot_labels()
		_footer.call("flash_saved", "✓  Saved to slot %d" % slot)
	else:
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
