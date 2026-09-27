extends Control
## QuietSegmented.gd (Sep 2026) — segmented control / text tabs for the quiet
## UI language (docs/ui/QUIET_DESIGN_SYSTEM.md §3). Muted text entries; the
## active one is ivory with a 2 px ACCENT underline that slides (position and
## width, text-width) when the selection changes. Read-only entries (e.g. the
## graphics "Custom" preset) are shown but not clickable, and light up when
## they are the active state.
##
##   var tabs := QuietSegmented.new()   # via preload, no class_name
##   tabs.setup(["Overview", "Devices"], [], 15, true)   # true = LB/RB tabs
##   tabs.segment_pressed.connect(_on_tab)
##   tabs.set_active(0, false)

signal segment_pressed(index: int)

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

var _buttons: Array[Button] = []
var _read_only: Array[int] = []
var _row: HBoxContainer
var _underline: ColorRect
var _tween: Tween
var _active: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Segments"
	_row.add_theme_constant_override("separation", 2)
	add_child(_row)
	_underline = ColorRect.new()
	_underline.name = "Underline"
	_underline.color = Q.ACCENT
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_underline)
	_row.resized.connect(_on_row_resized)


## labels: captions; read_only: indices shown but not selectable;
## as_tabs: mark entries for ControllerUINavigation LB/RB cycling.
func setup(labels: Array[String], read_only: Array[int] = [], font_size: int = 15,
		as_tabs: bool = false) -> void:
	_read_only = read_only
	for index: int in labels.size():
		var segment := Button.new()
		segment.name = labels[index].to_pascal_case() + "Segment"
		segment.text = labels[index]
		Q.segment(segment, font_size)
		if index in read_only:
			segment.disabled = true
			segment.focus_mode = Control.FOCUS_NONE
			segment.mouse_default_cursor_shape = Control.CURSOR_ARROW
		elif as_tabs:
			segment.set_meta(&"ui_tab", true)
		segment.pressed.connect(func() -> void: segment_pressed.emit(index))
		# Re-seat the underline whenever layout moves the active entry.
		segment.item_rect_changed.connect(func() -> void:
			if index == _active and not is_instance_valid(_tween):
				_place(false))
		_row.add_child(segment)
		_buttons.append(segment)
	_on_row_resized()


func get_buttons() -> Array[Button]:
	return _buttons


func get_active() -> int:
	return _active


## Help text/cost shown in a QuietFooter when an entry is focused.
func describe(help: String, cost: String = "") -> void:
	for segment: Button in _buttons:
		segment.set_meta(&"help", help)
		segment.set_meta(&"cost", cost)


func set_active(index: int, animate: bool = true) -> void:
	var changed := index != _active
	_active = index
	for i: int in _buttons.size():
		var segment := _buttons[i]
		segment.set_pressed_no_signal(i == index)
		if i in _read_only:
			segment.add_theme_color_override("font_disabled_color",
				Q.TEXT if i == index else Color(Q.MUTED, 0.35))
	_place(animate and changed)


func _on_row_resized() -> void:
	custom_minimum_size = _row.get_combined_minimum_size()
	_place(false)


func _place(animated: bool) -> void:
	if _active < 0 or _active >= _buttons.size():
		_underline.visible = false
		return
	_underline.visible = true
	var segment := _buttons[_active]
	var font := segment.get_theme_font("font")
	var font_size := segment.get_theme_font_size("font_size")
	var text_width := font.get_string_size(segment.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var target := Rect2(segment.position.x + (segment.size.x - text_width) * 0.5,
		segment.position.y + segment.size.y + 2.0, text_width, 2.0)
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null
	if not animated or UIMotion.reduced() or _underline.size.x <= 0.0 or not is_inside_tree():
		_underline.position = target.position
		_underline.size = target.size
		return
	_tween = create_tween().set_parallel(true)
	_tween.finished.connect(func() -> void: _tween = null)
	_tween.tween_property(_underline, "position", target.position, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_underline, "size", target.size, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
