class_name BunkerUIComponents
extends RefCounted

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

## Reusable presentation vocabulary distilled from the approved generator,
## water, farming, and character-creation screens.  This layer owns visual
## hierarchy only; feature UIs keep their own data and gameplay contracts.

const REDESIGN_THEME_PATH := "res://assets/ui/themes/BunkerRedesignTheme.tres"
## ScrollContainer bars overlay their viewport in Godot. Content placed flush
## to the right edge therefore sits beneath a visible vertical bar. Every
## scrollable bunker surface reserves this presentation-only gutter.
const SCROLLBAR_CONTENT_GUTTER: int = 20


static func apply_theme(root: Control) -> void:
	var resource: Resource = load(REDESIGN_THEME_PATH)
	if resource is Theme:
		root.theme = (resource as Theme).duplicate(true) as Theme
		root.theme.default_font = UIKit.font()
		BunkerControlTheme.install(root.theme)
	else:
		BunkerPanelStyle.apply(root)


## Quiet shell (Sep 2026): SURFACE, brass 30% edge, soft shadow.
static func shell(panel: PanelContainer, radius: int = 12) -> void:
	panel.add_theme_stylebox_override("panel", Q.shell_box(radius))


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


static func scroll_content(scroll: ScrollContainer, child: Control,
		left: int = 2, top: int = 2, bottom: int = 2,
		right: int = SCROLLBAR_CONTENT_GUTTER) -> MarginContainer:
	var gutter := MarginContainer.new()
	gutter.name = "ScrollContentGutter"
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_left", left)
	gutter.add_theme_constant_override("margin_top", top)
	gutter.add_theme_constant_override("margin_right", right)
	gutter.add_theme_constant_override("margin_bottom", bottom)
	scroll.add_child(gutter)
	gutter.add_child(child)
	return gutter


## Quiet pass: header/section icon wells are retired (text-first language).
## The node is still returned — hidden, zero-size — so callers keep working.
static func icon_well(symbol: String, side: float = 48.0,
		tint: Color = BunkerPanelStyle.BLUE) -> PanelContainer:
	var well := PanelContainer.new()
	well.visible = false
	well.custom_minimum_size = Vector2(side, side)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", panel_box(
		BunkerDesign.SURFACE, BunkerPanelStyle.BRASS.darkened(0.35), 8, 1, 8))
	var texture := TextureRect.new()
	texture.name = "Icon"
	texture.set_meta(&"symbol", symbol)   ## no texture: the well is retired
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
	var eyebrow: Label = Q.eyebrow(eyebrow_text, 12)
	eyebrow.name = "Eyebrow"
	titles.add_child(eyebrow)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BunkerPanelStyle.title(title, 26)
	titles.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.tooltip_text = ""
	Q.nav_button(close, 14, 30.0)
	close.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	var title: Label = Q.eyebrow(title_text, 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var meta := Label.new()
	meta.text = meta_text
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", Q.MUTED)
	row.add_child(meta)
	return {"row": row, "title": title, "meta": meta}


static func divider(parent: Container) -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", Q.hairline())
	parent.add_child(separator)
	return separator


## Quiet pass: segments/tabs are text with an ACCENT underline when pressed
## (Q.tab_button). Icons set by callers are tinted MUTED → TEXT.
static func style_segment(button: Button, compact: bool = false,
		_borderless: bool = false) -> void:
	UIButtonMotion.attach(button)
	Q.tab_button(button, 13 if compact else 15,
		BunkerDesign.COMPACT_CONTROL_HEIGHT if compact else BunkerDesign.CONTROL_HEIGHT)
	button.add_theme_constant_override("icon_max_width", 16 if compact else 18)


static func style_tool(button: Button) -> void:
	style_segment(button)
	button.custom_minimum_size = Vector2(92, 66)


static func status_style(active: bool) -> StyleBoxFlat:
	return Q.flat(Color(Q.TEXT, 0.05 if active else 0.025), 10.0, 10.0, 6)


static func key_hint(parent: Container, key_text: String, action_text: String,
		keyboard_key: String = "", controller_key: String = "",
		compact: bool = false) -> void:
	var group := BunkerInputHint.new()
	group.keyboard_key = keyboard_key if not keyboard_key.is_empty() else key_text
	group.controller_key = controller_key if not controller_key.is_empty() else key_text
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override("separation", 5 if compact else 7)
	parent.add_child(group)
	var keycap := PanelContainer.new()
	keycap.custom_minimum_size = Vector2(
		maxf(34.0, float(key_text.length()) * 8.0 + 14.0), 20 if compact else 24)
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Quiet keycap (Sep 2026, QUIET_DESIGN_SYSTEM §3): faint fill, hairline edge.
	keycap.add_theme_stylebox_override("panel", panel_box(
		Color(BunkerDesign.IVORY, 0.04), Color(BunkerDesign.IVORY, 0.2), 5, 1,
		1 if compact else 3))
	group.add_child(keycap)
	var key := Label.new()
	key.text = key_text
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.add_child(key)
	group.key_label = key
	group.keycap = keycap
	var action := Label.new()
	action.text = action_text
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.add_theme_font_size_override("font_size", 11 if compact else 12)
	action.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	group.add_child(action)
