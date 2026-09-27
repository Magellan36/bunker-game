extends RefCounted
## QuietControls.gd (Sep 2026)
## The "quiet" control skin introduced with the main menu and the settings
## pass: dark, flat, text-first controls where state is carried by text
## brightness, a hairline and one muted steel-blue accent instead of filled,
## bordered, saturated buttons. Focus is shown by a FocusRail placed by the
## host, so controls themselves draw no focus box.
##
## Static helpers only (no class_name; preload it):
##   const Q := preload("res://scripts/ui/common/QuietControls.gd")
## Everything is engine-drawn: StyleBoxFlat, GradientTexture2D, draw calls.

const SWITCH_SCRIPT: GDScript = preload("res://scripts/ui/common/SwitchGlyph.gd")

## Desaturated project blue: selection without "pop".
const ACCENT: Color = Color("86a9bf")
const ACCENT_DIM: Color = Color("2b3b44")
const TEXT: Color = BunkerDesign.IVORY
const MUTED: Color = Color("aaa596")
const FAINT: Color = Color(0.667, 0.647, 0.588, 0.45)
const HAIRLINE: Color = Color(0.533, 0.451, 0.306, 0.2)
const HEADING: Color = Color("a8946c")
const SURFACE: Color = Color(0.051, 0.067, 0.063, 0.97)
const POPUP: Color = Color(0.067, 0.086, 0.082, 0.99)


static func flat(bg: Color = Color(0, 0, 0, 0), h_pad: float = 10.0,
		v_pad: float = 4.0, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(0)
	style.content_margin_left = h_pad
	style.content_margin_right = h_pad
	style.content_margin_top = v_pad
	style.content_margin_bottom = v_pad
	return style


## Dialog/panel surface: near-opaque charcoal, faint brass edge, soft shadow.
static func shell_box(radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = Color(BunkerDesign.BRASS, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 36
	style.shadow_offset = Vector2(0, 10)
	style.anti_aliasing = true
	return style


## Transparent row with a single hairline underneath.
static func row_box(h_pad: float = 16.0, v_pad: float = 6.0) -> StyleBoxFlat:
	var style := flat(Color(0, 0, 0, 0), h_pad, v_pad, 0)
	style.content_margin_right = 6.0
	style.border_color = HAIRLINE
	style.border_width_bottom = 1
	return style


static func hairline(vertical: bool = false) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = HAIRLINE
	line.thickness = 1
	line.vertical = vertical
	return line


static func tracked(label: Label, spacing: int) -> void:
	var font := label.get_theme_font("font")
	var variation := font as FontVariation
	if variation == null:
		variation = FontVariation.new()
		variation.base_font = font
		label.add_theme_font_override("font", variation)
	variation.spacing_glyph = spacing


static func label(text: String, font_size: int, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


## Small tracked caps heading in worn brass.
static func eyebrow(text: String, font_size: int = 12) -> Label:
	var result := label(text.to_upper(), font_size, HEADING)
	tracked(result, 3)
	return result


static func _text_colors(button: Control, normal: Color = MUTED) -> void:
	button.add_theme_color_override("font_color", normal)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_hover_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.35))


static func _all_states(control: Control, style: StyleBox, focus: StyleBox = null) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		control.add_theme_stylebox_override(state, style)
	control.add_theme_stylebox_override("focus", focus if focus != null else StyleBoxEmpty.new())


## Text-only navigation/list entry. Selection shown by brightness (+ a rail
## the host places); keyboard focus gets a faint wash.
static func nav_button(button: Button, font_size: int = 16, height: float = 30.0) -> void:
	button.flat = false
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = height
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	_text_colors(button)
	var base := flat(Color(0, 0, 0, 0), 14.0, 2.0)
	_all_states(button, base, flat(Color(TEXT, 0.05), 14.0, 2.0))


## Segmented-control entry (quality preset): muted text, bright when active.
static func segment(button: Button, font_size: int = 15) -> void:
	nav_button(button, font_size, 30.0)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.toggle_mode = true
	var base := flat(Color(0, 0, 0, 0), 14.0, 2.0)
	_all_states(button, base, flat(Color(TEXT, 0.05), 14.0, 2.0))


## Dropdown that reads as a value: right-aligned, borderless, cycles with
## Left/Right (keyboard and d-pad) via the ControllerUINavigation ui_cycle hook.
static func option(option_button: OptionButton, font_size: int = 15, width: float = 260.0) -> void:
	option_button.custom_minimum_size = Vector2(width, 30.0)
	option_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	option_button.focus_mode = Control.FOCUS_ALL
	option_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	option_button.add_theme_font_size_override("font_size", font_size)
	option_button.add_theme_constant_override("arrow_margin", 8)
	_text_colors(option_button)
	var base := flat(Color(0, 0, 0, 0), 10.0, 2.0)
	base.content_margin_right = 30.0
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(TEXT, 0.04)
	for state: String in ["normal", "disabled"]:
		option_button.add_theme_stylebox_override(state, base)
	for state: String in ["hover", "pressed", "hover_pressed"]:
		option_button.add_theme_stylebox_override(state, hover)
	option_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_popup(option_button.get_popup(), font_size)
	option_button.set_meta(&"ui_cycle", func(direction: int) -> void:
		cycle_option(option_button, direction))


## Selects the next/previous enabled item and emits item_selected like a click.
static func cycle_option(option_button: OptionButton, direction: int) -> void:
	if option_button.disabled or option_button.item_count == 0:
		return
	var index := option_button.selected
	for step: int in range(option_button.item_count):
		index = wrapi(index + direction, 0, option_button.item_count)
		if not option_button.is_item_disabled(index):
			break
	if index == option_button.selected or option_button.is_item_disabled(index):
		return
	option_button.select(index)
	option_button.item_selected.emit(index)


static func _style_popup(popup: PopupMenu, font_size: int) -> void:
	var panel := flat(POPUP, 6.0, 6.0, 8)
	panel.border_color = Color(BunkerDesign.BRASS, 0.3)
	panel.set_border_width_all(1)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 18
	popup.add_theme_stylebox_override("panel", panel)
	var hover := flat(ACCENT_DIM, 10.0, 4.0, 5)
	popup.add_theme_stylebox_override("hover", hover)
	popup.add_theme_stylebox_override("focus", hover)
	popup.add_theme_color_override("font_color", MUTED)
	popup.add_theme_color_override("font_hover_color", TEXT)
	popup.add_theme_color_override("font_disabled_color", Color(MUTED, 0.3))
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_constant_override("v_separation", 10)
	popup.add_theme_constant_override("item_start_padding", 12)
	popup.add_theme_constant_override("item_end_padding", 16)
	for icon_name: String in ["radio_checked", "radio_unchecked", "checked", "unchecked"]:
		popup.add_theme_icon_override(icon_name, _blank(Vector2i(6, 6)))


## Animated on/off switch with an "On"/"Off" caption to its left.
static func switch(toggle: CheckButton, font_size: int = 15, ui_scale: float = 1.0) -> void:
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toggle.custom_minimum_size = Vector2(maxf(toggle.custom_minimum_size.x, 110.0), 30.0)
	toggle.add_theme_font_size_override("font_size", font_size)
	_text_colors(toggle)
	var base := flat(Color(0, 0, 0, 0), 8.0, 2.0)
	base.content_margin_right = 4.0
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(TEXT, 0.04)
	toggle.add_theme_stylebox_override("normal", base)
	toggle.add_theme_stylebox_override("disabled", base)
	for state: String in ["hover", "pressed", "hover_pressed"]:
		toggle.add_theme_stylebox_override(state, hover if state != "pressed" else base)
	toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	toggle.add_theme_constant_override("h_separation", 12)
	var reserve := _blank(Vector2i(roundi(34.0 * ui_scale), roundi(18.0 * ui_scale)))
	for icon_name: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled",
			"checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored",
			"unchecked_disabled_mirrored"]:
		toggle.add_theme_icon_override(icon_name, reserve)
	var glyph: Control = SWITCH_SCRIPT.new()
	glyph.name = "SwitchGlyph"
	glyph.set("ui_scale", ui_scale)
	toggle.add_child(glyph, false, Node.INTERNAL_MODE_BACK)
	set_switch_text(toggle)
	toggle.toggled.connect(func(_on: bool) -> void: set_switch_text(toggle))


static func set_switch_text(toggle: CheckButton) -> void:
	toggle.text = "On" if toggle.button_pressed else "Off"


## Thin track, muted fill, small ivory knob. Wheel does not change values
## (it scrolls the page instead).
static func slider(bar: HSlider) -> void:
	bar.focus_mode = Control.FOCUS_ALL
	bar.scrollable = false
	bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bar.custom_minimum_size = Vector2(maxf(bar.custom_minimum_size.x, 180.0), 30.0)
	var track := flat(Color(TEXT, 0.09), 0.0, 1.5, 2)
	bar.add_theme_stylebox_override("slider", track)
	bar.add_theme_stylebox_override("grabber_area", flat(Color(ACCENT, 0.55), 0.0, 1.5, 2))
	bar.add_theme_stylebox_override("grabber_area_highlight", flat(Color(ACCENT, 0.8), 0.0, 1.5, 2))
	bar.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	bar.add_theme_icon_override("grabber", _disc(14, Color(TEXT, 0.92)))
	bar.add_theme_icon_override("grabber_highlight", _disc(16, TEXT))
	bar.add_theme_icon_override("grabber_disabled", _disc(12, Color(MUTED, 0.4)))


## Slim, faint scrollbar that brightens on hover. Keeps a controller-sized
## hit area (ControllerUINavigation widens useful bars to 16 px) but draws a
## 6 px grabber inside it via transparent side borders.
static func scrollbar(bar: ScrollBar) -> void:
	bar.set_meta(&"shared_scrollbar_skin", true)
	bar.add_theme_stylebox_override("scroll", flat(Color(0, 0, 0, 0), 0.0, 0.0, 3))
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var alpha: float = {"grabber": 0.13, "grabber_highlight": 0.26, "grabber_pressed": 0.34}[state]
		var grab := flat(Color(TEXT, alpha), 0.0, 0.0, 3)
		grab.border_color = Color(0, 0, 0, 0)
		grab.border_width_left = 5
		grab.border_width_right = 5
		bar.add_theme_stylebox_override(state, grab)


static func _disc(diameter: int, color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.8, 0.96])
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = diameter
	texture.height = diameter
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


static func _blank(pixels: Vector2i) -> ImageTexture:
	var image := Image.create_empty(maxi(pixels.x, 1), maxi(pixels.y, 1), false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)
