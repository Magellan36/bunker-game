extends RefCounted
## Small native-control vocabulary shared by device inspectors only.
## Device-specific order/wording lives in its UI file's _build_content().

const SYMBOL: GDScript = preload("res://scripts/ui/common/BunkerSymbolTexture.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")
static var _symbols: Dictionary = {}

static func icon(kind: String) -> Texture2D:
	if _symbols.has(kind):
		return _symbols[kind] as Texture2D
	var texture: Texture2D = SYMBOL.new()
	texture.symbol = kind
	_symbols[kind] = texture
	return texture

static func color(control: Control, token: String) -> Color:
	return control.get_theme_color(token, "Bunker")

static func column(parent: Node, key: String, gap: int = 6) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = key
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.set_meta("ui_gap", gap)
	parent.add_child(box)
	return box

static func label(parent: Node, key: String, text: String, font_size: int = 18, token: String = "text") -> Label:
	var control := Label.new()
	control.name = key
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.set_meta("ui_font_size", font_size)
	control.add_theme_font_size_override("font_size", font_size)
	parent.add_child(control)
	control.add_theme_color_override("font_color", color(control, token))
	return control

static func button(parent: Node, key: String, text: String, callback: Callable, kind: String = "", primary: bool = false) -> Button:
	var control := Button.new()
	control.name = key
	control.text = text
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.set_meta("ui_font_size", 18)
	control.set_meta("ui_min_height", 48 if primary else 44)
	control.custom_minimum_size.y = 48 if primary else 44
	control.add_theme_font_size_override("font_size", 18)
	control.clip_text = true
	control.tooltip_text = text
	if primary:
		control.theme_type_variation = &"BunkerPrimaryButton"
	if not kind.is_empty():
		control.icon = icon(kind)
		control.expand_icon = true
		control.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(control)
	if callback.is_valid():
		control.pressed.connect(callback)
	return control

static func status(parent: Node, key: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = key
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.theme_type_variation = &"BunkerInspectorCard"
	parent.add_child(card)
	card.add_theme_stylebox_override("panel", card.get_theme_stylebox("panel").duplicate() as StyleBox)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_meta("ui_gap", 8)
	card.add_child(row)
	var texture := TextureRect.new()
	texture.name = "Icon"
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.set_meta("ui_icon_size", 24)
	row.add_child(texture)
	label(row, "State", "", 16)
	return card

static func set_status(card: PanelContainer, text: String, token: String, kind: String) -> void:
	var tint: Color = color(card, token)
	var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = color(card, "background").lerp(tint, 0.08)
	style.border_color = color(card, "background").lerp(tint, 0.48)
	var caption: Label = card.get_node("Row/State") as Label
	caption.text = text
	caption.add_theme_color_override("font_color", tint)
	var texture: TextureRect = card.get_node("Row/Icon") as TextureRect
	if texture.get_meta("symbol", "") != kind:
		texture.texture = icon(kind)
		texture.set_meta("symbol", kind)
	texture.self_modulate = tint

static func stat(parent: Node, key: String, caption: String) -> VBoxContainer:
	var box: VBoxContainer = column(parent, key, 3)
	label(box, "Caption", caption, 14, "secondary")
	label(box, "Value", "—", 18)
	return box

static func set_stat(box: VBoxContainer, text: String, token: String = "text") -> void:
	var value: Label = box.get_node("Value") as Label
	value.text = text
	value.add_theme_color_override("font_color", color(box, token))

static func meter(parent: Node, key: String, caption: String, kind: String) -> VBoxContainer:
	var box: VBoxContainer = column(parent, key)
	var row := HBoxContainer.new()
	row.name = "Heading"
	row.set_meta("ui_gap", 8)
	box.add_child(row)
	var texture := TextureRect.new()
	texture.name = "Icon"
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.texture = icon(kind)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.set_meta("ui_icon_size", 20)
	row.add_child(texture)
	texture.self_modulate = color(box, "blue")
	label(row, "Caption", caption)
	var value: Label = label(row, "Value", "0%")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.name = "Bar"
	bar.theme_type_variation = &"BunkerMeter"
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("ui_min_height", 12)
	box.add_child(bar)
	bar.add_theme_stylebox_override("fill", bar.get_theme_stylebox("fill").duplicate() as StyleBox)
	label(box, "Hint", "", 14, "secondary")
	return box

static func set_meter(box: VBoxContainer, percent: float, value: String, hint: String, token: String = "blue") -> void:
	(box.get_node("Heading/Value") as Label).text = value
	var help: Label = box.get_node("Hint") as Label
	help.text = hint
	help.visible = not hint.is_empty()
	var bar: ProgressBar = box.get_node("Bar") as ProgressBar
	SMOOTH_BAR.apply(bar, clampf(percent, 0.0, 100.0))
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	style.bg_color = color(box, token)
	style.border_color = style.bg_color

static func quality_token(quality: float) -> String:
	# Preserve the water system's inclusive boundaries, not generator-health thresholds.
	return "critical" if quality <= 50.0 else ("warning" if quality <= 75.0 else "success")

static func option(parent: Node, key: String) -> OptionButton:
	var control := OptionButton.new()
	control.name = key
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.fit_to_longest_item = false
	control.clip_text = true
	control.set_meta("ui_font_size", 16)
	control.set_meta("ui_min_height", 44)
	control.custom_minimum_size.y = 44
	parent.add_child(control)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		control.add_theme_stylebox_override(state, control.get_theme_stylebox(state, "Button"))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		control.add_theme_color_override(state, control.get_theme_color(state, "Button"))
	var popup: PopupMenu = control.get_popup()
	popup.add_theme_stylebox_override("panel", control.get_theme_stylebox("panel", "BunkerInspectorCard").duplicate() as StyleBox)
	popup.add_theme_stylebox_override("hover", control.get_theme_stylebox("hover", "Button").duplicate() as StyleBox)
	popup.add_theme_font_size_override("font_size", 16)
	popup.add_theme_color_override("font_color", color(control, "text"))
	popup.add_theme_color_override("font_hover_color", color(control, "text"))
	popup.add_theme_constant_override("v_separation", 12)
	return control
