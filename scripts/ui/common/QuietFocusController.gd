extends Node
## QuietFocusController.gd (Sep 2026) — the behaviour half of the quiet
## "row list" pattern first built for Graphics Settings, reusable by any
## workspace or inspector (docs/ui/QUIET_DESIGN_SYSTEM.md §3, §5):
##
##   - make_row(): label left, control right, hairline under, 46 px
##   - FocusRail follows the focused row; its label brightens
##   - hover moves focus (keyboard/mouse mode), without scrolling
##   - keyboard/controller focus reveals the row via SmoothScroll
##   - clicking a row's label acts on its control (bigger target)
##   - the footer hint line + cost tag describe the focused control
##   - value changes pulse the rail and flash "✓ Saved"
##
## Wiring (after the host has built its rail/scroll/footer):
##   _focus = FOCUS.new(); add_child(_focus)
##   _focus.surface = _panel; _focus.rail = _row_rail
##   _focus.smooth = _smooth; _focus.footer = _footer
##   _focus.is_active = func() -> bool: return _is_open

signal acknowledged(control: Control)

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

var surface: Control
var rail: Control
var smooth: Node
var footer: Node
var is_active: Callable = func() -> bool: return true
var rest_alpha: float = 0.74
var row_height: float = 46.0

var _rows: Array[Control] = []
var _active_row: Control = null
var _hover_focus: bool = false


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## One setting row. `focus_target` is the control that takes focus when it
## differs from `control` (a slider inside a slider+value group).
func make_row(parent: Container, title_text: String, control: Control, help: String,
		cost: String = "", focus_target: Control = null) -> PanelContainer:
	var target: Control = focus_target if focus_target != null else control
	var row := PanelContainer.new()
	row.name = title_text.to_pascal_case().replace("&", "And") + "Row"
	row.custom_minimum_size.y = row_height
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", Q.row_box())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	row.add_child(line)
	var name_label: Label = Q.label(title_text, 16, Q.TEXT)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.modulate.a = rest_alpha
	line.add_child(name_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	parent.add_child(row)
	register_row(row, name_label, target, help, cost)
	return row


## Adopt an existing row-like container (custom layouts).
func register_row(row: Control, name_label: Label, target: Control, help: String,
		cost: String = "") -> void:
	row.set_meta(&"control", target)
	row.set_meta(&"label", name_label)
	describe(target, help, cost)
	target.set_meta(&"settings_row", row)
	row.mouse_entered.connect(_on_row_hovered.bind(row))
	row.gui_input.connect(_on_row_input.bind(row))
	if target is OptionButton:
		(target as OptionButton).item_selected.connect(func(_i: int) -> void: acknowledge(target))
	elif target is CheckButton:
		(target as CheckButton).toggled.connect(func(_on: bool) -> void: acknowledge(target))
	elif target is Range:
		(target as Range).value_changed.connect(func(_v: float) -> void: acknowledge(target))
	_rows.append(row)


## Footer help/cost for any focusable control (rows set this automatically).
func describe(control: Control, help: String, cost: String = "") -> void:
	control.set_meta(&"help", help)
	control.set_meta(&"cost", cost)


func get_rows() -> Array[Control]:
	return _rows


## Call on open: no active row, idle hint, hidden Saved.
func reset() -> void:
	_set_active_row(null)
	if footer != null:
		footer.call("show_hint", "", "")
		footer.call("hide_saved")


## Dims labels of rows whose control is disabled.
func sync_row_states() -> void:
	for row: Control in _rows:
		var control := row.get_meta(&"control") as Control
		var disabled: bool = control is BaseButton and (control as BaseButton).disabled
		(row.get_meta(&"label") as Label).self_modulate.a = 0.45 if disabled else 1.0


## A value changed: pulse the rail on its row and confirm the save.
func acknowledge(control: Control) -> void:
	if not is_active.call():
		return
	if control.has_meta(&"settings_row") and control.get_meta(&"settings_row") == _active_row \
			and rail != null:
		rail.call("pulse")
	if footer != null:
		footer.call("flash_saved")
	acknowledged.emit(control)


func _on_focus_changed(control: Control) -> void:
	if not is_active.call() or control == null or surface == null \
			or not surface.is_ancestor_of(control):
		return
	var row: Variant = control.get_meta(&"settings_row") if control.has_meta(&"settings_row") else null
	if row is Control:
		_set_active_row(row as Control)
		if not _hover_focus and smooth != null:
			smooth.call("reveal", row, 56.0)
	else:
		_set_active_row(null)
	if footer != null:
		footer.call("show_hint", str(control.get_meta(&"help", "")), str(control.get_meta(&"cost", "")))


func _set_active_row(row: Control) -> void:
	if row == _active_row:
		return
	for candidate: Control in [_active_row, row]:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var name_label := candidate.get_meta(&"label") as Label
		var target_alpha: float = 1.0 if candidate == row else rest_alpha
		create_tween().tween_property(name_label, "modulate:a", target_alpha, UIMotion.duration(0.12))
	_active_row = row
	if rail != null:
		rail.call("set_target", row)


## Hover moves focus, so the rail, the hint and keyboard/controller agree.
func _on_row_hovered(row: Control) -> void:
	if not is_active.call() or not InputMode.is_keyboard():
		return
	if smooth != null and smooth.call("is_animating"):
		return
	var control := row.get_meta(&"control") as Control
	if control == null or control.has_focus() or control.focus_mode == Control.FOCUS_NONE:
		return
	if control is OptionButton and (control as OptionButton).get_popup().visible:
		return
	_hover_focus = true
	control.grab_focus()
	_hover_focus = false


## Clicking a row's label area acts on its control.
func _on_row_input(event: InputEvent, row: Control) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var control := row.get_meta(&"control") as Control
	if control == null or control.focus_mode == Control.FOCUS_NONE:
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	control.grab_focus()
	if control is CheckButton:
		(control as CheckButton).button_pressed = not (control as CheckButton).button_pressed
	elif control is OptionButton:
		(control as OptionButton).show_popup()
	row.accept_event()
