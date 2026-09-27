extends Button
## MainMenuItem.gd (Sep 2026)
## Text-only main-menu entry. A real Button (native focus, accept, disabled
## and accessibility), with every stylebox emptied: the shared
## FocusRail (scripts/ui/common) draws focus, and this node animates only its own content
## offset, brightness and trailing arrow. Mouse hover moves keyboard focus so
## the menu has exactly one "current" item regardless of input device.

const FONT_TITLE: FontFile = preload("res://assets/fonts/IosevkaCharon-Medium.ttf")
const FONT_CAPTION: FontFile = preload("res://assets/fonts/IosevkaCharon-Regular.ttf")

const REST_ALPHA: float = 0.6
const DISABLED_ALPHA: float = 0.28
const SLIDE_PX: float = 14.0

## Accent the selector uses for this item. Danger items switch to red while
## they are asking for confirmation.
var accent: Color = BunkerDesign.BLUE
## Keep the caption line even when empty, so a caption moving between
## sibling options (e.g. "Selected") never shifts the layout.
var reserve_caption: bool = false

var _title: Label
var _caption: Label
var _arrow: Label
var _arrow_slot: Control
var _content: Control
var _row: HBoxContainer
var _column: VBoxContainer
var _hot: float = 0.0
var _ui_scale: float = 1.0
var _title_color: Color = BunkerDesign.IVORY


func _init() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled",
			"normal_mirrored", "hover_mirrored", "pressed_mirrored", "hover_pressed_mirrored",
			"disabled_mirrored"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 0)
	_content.add_child(_column)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_row)

	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", FONT_TITLE)
	_row.add_child(_title)

	# The arrow lives in a plain Control so it can slide without fighting the
	# HBoxContainer's layout.
	_arrow_slot = Control.new()
	_arrow_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_arrow_slot)
	_arrow = Label.new()
	_arrow.name = "Arrow"
	_arrow.text = "→"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.add_theme_font_override("font", FONT_CAPTION)
	_arrow.add_theme_color_override("font_color", BunkerDesign.BLUE)
	_arrow.modulate.a = 0.0
	_arrow_slot.add_child(_arrow)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("font", FONT_CAPTION)
	_caption.add_theme_color_override("font_color", BunkerDesign.MUTED)
	_caption.visible = false
	_column.add_child(_caption)


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	resized.connect(_fit_content)
	apply_ui_scale(_ui_scale)


func setup(title_text: String, caption_text: String = "") -> Button:
	name = title_text.to_pascal_case()
	_title.text = title_text
	tooltip_text = ""
	set_caption(caption_text)
	return self


func set_title(title_text: String) -> void:
	_title.text = title_text


func get_title() -> String:
	return _title.text


func set_caption(caption_text: String) -> void:
	_caption.text = caption_text
	_caption.visible = reserve_caption or not caption_text.is_empty()
	apply_ui_scale(_ui_scale)


func set_title_color(color: Color) -> void:
	_title_color = color


## Caption tint — hosts mark a chosen option ("Selected") in their accent.
func set_caption_color(color: Color) -> void:
	_caption.add_theme_color_override("font_color", color)


## In-game hosts (game over, loading) use the quiet ACCENT instead of the
## main menu's hero blue for the arrow and rail.
func set_accent_color(color: Color) -> void:
	accent = color
	_arrow.add_theme_color_override("font_color", color)


func apply_ui_scale(ui_scale: float) -> void:
	_ui_scale = ui_scale
	# Floors keep small type legible at 720p and on handhelds.
	_title.add_theme_font_size_override("font_size", maxi(22, roundi(30.0 * ui_scale)))
	_arrow.add_theme_font_size_override("font_size", maxi(18, roundi(24.0 * ui_scale)))
	_caption.add_theme_font_size_override("font_size", maxi(12, roundi(14.0 * ui_scale)))
	_row.add_theme_constant_override("separation", roundi(14.0 * ui_scale))
	_arrow_slot.custom_minimum_size = _arrow.get_combined_minimum_size()
	_arrow_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	## 40px floor keeps pointer/controller targets comfortable at 720p.
	custom_minimum_size.y = maxf(56.0 if _caption.visible else 40.0,
		roundf((68.0 if _caption.visible else 52.0) * ui_scale))
	_fit_content()


## 0 = resting, 1 = current. Driven every frame for interruptible motion.
func get_hot() -> float:
	return _hot


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() and not disabled else 0.0
	_hot = lerpf(_hot, target, UIMotion.weight(delta, 14.0))
	if absf(_hot - target) < 0.001:
		_hot = target
	_content.position.x = _hot * SLIDE_PX * _ui_scale
	var rest := DISABLED_ALPHA if disabled else REST_ALPHA
	_title.add_theme_color_override("font_color", Color(_title_color, lerpf(rest, 1.0, _hot)))
	_caption.modulate.a = lerpf(0.55 if disabled else 0.7, 1.0, _hot)
	_arrow.modulate.a = _hot
	_arrow.position.x = (1.0 - _hot) * -8.0 * _ui_scale


func _fit_content() -> void:
	if _content == null:
		return
	_content.size = size
	_column.position = Vector2.ZERO
	_column.size = size


func _on_mouse_entered() -> void:
	if not disabled and not has_focus():
		grab_focus()
