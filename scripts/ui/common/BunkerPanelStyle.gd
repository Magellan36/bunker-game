class_name BunkerPanelStyle
extends RefCounted

## Shared native-Control styling for the 2026 bunker UI.  Every shape is
## rendered by Godot; no generated bitmap UI assets are required.
const BG: Color = BunkerDesign.BG
const SURFACE: Color = BunkerDesign.SURFACE
const SURFACE_ALT: Color = BunkerDesign.SURFACE_ALT
const IVORY: Color = BunkerDesign.IVORY
const MUTED: Color = BunkerDesign.MUTED
const BRASS: Color = BunkerDesign.BRASS
const BLUE: Color = BunkerDesign.BLUE
const BLUE_DARK: Color = BunkerDesign.BLUE_DARK
const GREEN: Color = BunkerDesign.GREEN
const RED: Color = BunkerDesign.RED
const SYMBOL: GDScript = preload("res://scripts/ui/common/BunkerSymbolTexture.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
static var _symbols: Dictionary = {}

static func icon(kind: String) -> Texture2D:
	if _symbols.has(kind):
		return _symbols[kind] as Texture2D
	var texture: Texture2D = SYMBOL.new()
	texture.symbol = kind
	_symbols[kind] = texture
	return texture

static func box(bg: Color = BG, border: Color = BRASS, radius: int = 8, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	return s

static func button_box(bg: Color, border: Color, radius: int = 7, width: int = 1,
		horizontal_padding: float = 10.0,
		vertical_padding: float = BunkerDesign.CONTROL_VERTICAL_PADDING) -> StyleBoxFlat:
	var style := box(bg, border, radius, width)
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding
	return style

## Sep 2026 quiet pass (plan Pass 4): the legacy button vocabulary now draws
## the quiet language, so every consumer (workspaces, build, shop) follows
## QUIET_DESIGN_SYSTEM §3. accent = the surface's one primary; danger = red
## text action; everything else = quiet secondary. Signatures unchanged.
static func button(control: Button, accent: bool = false, danger: bool = false,
		compact: bool = false, _borderless: bool = false) -> void:
	UIButtonMotion.attach(control)
	var height: float = BunkerDesign.COMPACT_CONTROL_HEIGHT if compact else BunkerDesign.CONTROL_HEIGHT
	var font_size: int = 14 if compact else 15
	if accent:
		Q.primary_action(control, font_size, maxf(height, control.custom_minimum_size.y))
	else:
		Q.secondary_action(control, font_size, maxf(height, control.custom_minimum_size.y), danger)
	control.add_theme_constant_override("icon_max_width", 18)

## Icons are dropped (the quiet language is text-first). An icon-only button
## (no text) keeps its glyph, tinted MUTED → TEXT, so nothing goes blank.
static func icon_button(control: Button, kind: String, accent: bool = false,
		danger: bool = false, compact: bool = false, borderless: bool = false) -> void:
	button(control, accent, danger, compact, borderless)
	control.icon = icon(kind)
	control.expand_icon = true
	control.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## Callers often set the caption after styling; decide once it is final.
	if not control.tree_entered.is_connected(_strip_icon_if_captioned.bind(control)):
		control.tree_entered.connect(_strip_icon_if_captioned.bind(control), CONNECT_ONE_SHOT)
	_strip_icon_if_captioned(control)

static func _strip_icon_if_captioned(control: Button) -> void:
	if is_instance_valid(control) and not control.text.is_empty():
		control.icon = null
		control.alignment = HORIZONTAL_ALIGNMENT_CENTER

static func field(control: LineEdit) -> void:
	control.add_theme_font_size_override("font_size", 15)
	control.add_theme_color_override("font_color", IVORY)
	control.add_theme_color_override("font_placeholder_color", Color(MUTED, 0.55))
	control.add_theme_color_override("caret_color", Q.ACCENT)
	control.add_theme_color_override("selection_color", Color(Q.ACCENT, 0.3))
	var normal: StyleBoxFlat = Q.flat(Color(IVORY, 0.04), 12.0, 6.0, 6)
	normal.border_color = Q.HAIRLINE
	normal.border_width_bottom = 1
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Q.ACCENT
	focus.border_width_bottom = 2
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("focus", focus)

static func title(label: Label, size: int = 26) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", IVORY)

static func muted(label: Label, size: int = 14) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", MUTED)

static func apply(root: Control) -> void:
	var native_theme := Theme.new()
	native_theme.default_font = UIKit.font()
	native_theme.default_font_size = 16
	BunkerControlTheme.install(native_theme)
	root.theme = native_theme

static func panel(panel: PanelContainer) -> void:
	apply(panel)
	panel.add_theme_stylebox_override("panel", box())

static func margin(child: Control, left := 18, top := 16, right := 18, bottom := 16) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(child)
	return m
