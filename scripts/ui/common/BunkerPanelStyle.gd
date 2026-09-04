class_name BunkerPanelStyle
extends RefCounted

## Shared native-Control styling for the 2026 bunker UI.  Every shape is
## rendered by Godot; no generated bitmap UI assets are required.
const BG := Color("181d1d")
const SURFACE := Color("202625")
const SURFACE_ALT := Color("252c2b")
const IVORY := Color("f2e8cf")
const MUTED := Color("c5c0b2")
const BRASS := Color("88734e")
const BLUE := Color("66bfff")
const BLUE_DARK := Color("294b62")
const GREEN := Color("75d48a")
const RED := Color("df7669")
const SYMBOL: GDScript = preload("res://scripts/ui/common/BunkerSymbolTexture.gd")
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

static func button(control: Button, accent: bool = false, danger: bool = false) -> void:
	control.focus_mode = Control.FOCUS_ALL
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 42.0)
	control.add_theme_font_size_override("font_size", 17)
	control.add_theme_color_override("font_color", IVORY)
	control.add_theme_color_override("font_hover_color", IVORY)
	control.add_theme_color_override("font_pressed_color", IVORY)
	var normal_bg := BLUE_DARK if accent else (Color("512923") if danger else SURFACE)
	var edge := BLUE if accent else (RED if danger else BRASS.darkened(0.18))
	control.add_theme_stylebox_override("normal", box(normal_bg, edge, 7, 1))
	control.add_theme_stylebox_override("hover", box(normal_bg.lightened(0.07), BLUE if not danger else RED, 7, 1))
	control.add_theme_stylebox_override("pressed", box(normal_bg.darkened(0.08), IVORY, 7, 2))
	control.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, BLUE, 7, 2))
	control.add_theme_stylebox_override("disabled", box(SURFACE.darkened(0.1), BRASS.darkened(0.45), 7, 1))
	control.add_theme_color_override("font_disabled_color", MUTED.darkened(0.35))
	control.add_theme_constant_override("icon_max_width", 28)

static func icon_button(control: Button, kind: String, accent: bool = false, danger: bool = false) -> void:
	button(control, accent, danger)
	control.icon = icon(kind)
	control.expand_icon = true
	control.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT

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
