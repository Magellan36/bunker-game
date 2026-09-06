class_name BunkerUIComponents
extends RefCounted

## Reusable presentation vocabulary distilled from the approved generator,
## water, farming, and character-creation screens.  This layer owns visual
## hierarchy only; feature UIs keep their own data and gameplay contracts.

const REDESIGN_THEME_PATH := "res://assets/ui/themes/BunkerRedesignTheme.tres"


static func apply_theme(root: Control) -> void:
	var resource: Resource = load(REDESIGN_THEME_PATH)
	if resource is Theme:
		root.theme = (resource as Theme).duplicate(true) as Theme
	else:
		BunkerPanelStyle.apply(root)


static func shell(panel: PanelContainer, radius: int = 12) -> void:
	panel.add_theme_stylebox_override("panel", panel_box(
		Color("111615f7"), BunkerPanelStyle.BRASS.darkened(0.08), radius, 1))


static func panel_box(bg: Color, border: Color, radius: int = 8,
		width: int = 1, padding: int = 0) -> StyleBoxFlat:
	var style := BunkerPanelStyle.box(bg, border, radius, width)
	if padding > 0:
		style.content_margin_left = float(padding)
		style.content_margin_top = float(padding)
		style.content_margin_right = float(padding)
		style.content_margin_bottom = float(padding)
	return style


static func inset(child: Control, left: int = 18, top: int = 16,
		right: int = 18, bottom: int = 16) -> MarginContainer:
	return BunkerPanelStyle.margin(child, left, top, right, bottom)


static func icon_well(symbol: String, side: float = 48.0,
		tint: Color = BunkerPanelStyle.BLUE) -> PanelContainer:
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(side, side)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", panel_box(
		Color("202625"), BunkerPanelStyle.BRASS.darkened(0.35), 8, 1, 8))
	var texture := TextureRect.new()
	texture.name = "Icon"
	texture.texture = BunkerPanelStyle.icon(symbol)
	texture.self_modulate = tint
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(texture)
	return well


static func header(parent: Container, eyebrow_text: String, title_text: String,
		symbol: String, close_callback: Callable = Callable()) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(icon_well(symbol, 48.0))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 1)
	row.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.name = "Eyebrow"
	eyebrow.text = eyebrow_text
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	titles.add_child(eyebrow)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BunkerPanelStyle.title(title, 24)
	titles.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.custom_minimum_size = Vector2(44, 44)
	close.tooltip_text = "Close"
	BunkerPanelStyle.icon_button(close, "close")
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.text = ""
	if close_callback.is_valid():
		close.pressed.connect(close_callback)
	row.add_child(close)
	return {"row": row, "eyebrow": eyebrow, "title": title, "close": close}


static func section_header(parent: Container, title_text: String,
		meta_text: String = "") -> Dictionary:
	var row := HBoxContainer.new()
	row.name = title_text.replace(" ", "") + "Header"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var title := Label.new()
	title.text = title_text.to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	row.add_child(title)
	var meta := Label.new()
	meta.text = meta_text
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", BunkerPanelStyle.BRASS.lightened(0.28))
	row.add_child(meta)
	return {"row": row, "title": title, "meta": meta}


static func divider(parent: Container) -> HSeparator:
	var separator := HSeparator.new()
	parent.add_child(separator)
	return separator


static func style_segment(button: Button, compact: bool = false) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.toggle_mode = true
	button.custom_minimum_size.y = 38.0 if compact else 44.0
	button.add_theme_font_size_override("font_size", 12 if compact else 14)
	button.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	button.add_theme_color_override("font_hover_color", BunkerPanelStyle.IVORY)
	button.add_theme_color_override("font_pressed_color", BunkerPanelStyle.IVORY)
	button.add_theme_color_override("icon_normal_color", BunkerPanelStyle.MUTED)
	button.add_theme_color_override("icon_hover_color", BunkerPanelStyle.BLUE)
	button.add_theme_color_override("icon_pressed_color", BunkerPanelStyle.BLUE)
	button.add_theme_constant_override("icon_max_width", 20 if compact else 24)
	button.add_theme_stylebox_override("normal", panel_box(
		Color("1a201f"), BunkerPanelStyle.BRASS.darkened(0.42), 7, 1, 7))
	button.add_theme_stylebox_override("hover", panel_box(
		Color("202b2e"), BunkerPanelStyle.BLUE.darkened(0.2), 7, 1, 7))
	button.add_theme_stylebox_override("pressed", panel_box(
		BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE, 7, 2, 6))
	button.add_theme_stylebox_override("hover_pressed", panel_box(
		BunkerPanelStyle.BLUE_DARK.lightened(0.07), BunkerPanelStyle.BLUE, 7, 2, 6))
	button.add_theme_stylebox_override("focus", panel_box(
		Color.TRANSPARENT, BunkerPanelStyle.IVORY, 9, 2))


static func style_tool(button: Button) -> void:
	style_segment(button)
	button.custom_minimum_size = Vector2(92, 66)


static func status_style(active: bool) -> StyleBoxFlat:
	if active:
		return panel_box(Color("172820"), BunkerPanelStyle.GREEN.darkened(0.28), 8, 1, 10)
	return panel_box(Color("1b2221"), BunkerPanelStyle.BRASS.darkened(0.34), 8, 1, 10)


static func key_hint(parent: Container, key_text: String, action_text: String) -> void:
	var group := HBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 7)
	parent.add_child(group)
	var keycap := PanelContainer.new()
	keycap.custom_minimum_size = Vector2(
		maxf(34.0, float(key_text.length()) * 8.0 + 14.0), 24)
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.add_theme_stylebox_override("panel", panel_box(
		Color("252c2b"), BunkerPanelStyle.BRASS.darkened(0.1), 5, 1, 3))
	group.add_child(keycap)
	var key := Label.new()
	key.text = key_text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.add_child(key)
	var action := Label.new()
	action.text = action_text
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.add_theme_font_size_override("font_size", 12)
	action.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	group.add_child(action)
