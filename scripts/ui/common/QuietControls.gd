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


# ── Actions ──────────────────────────────────────────────────────────────────

## The one main action on a surface: dim steel fill, no border, ivory text.
## danger = true tints the fill red (irreversible confirmations in dialogs).
static func primary_action(button: Button, font_size: int = 16, height: float = 40.0,
		danger: bool = false) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = height
	button.add_theme_font_size_override("font_size", font_size)
	for key: String in ["font_color", "font_hover_color", "font_focus_color",
			"font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, TEXT)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.4))
	var fill := Color("4a2622") if danger else ACCENT_DIM
	var base := flat(Color(fill, 0.85), 18.0, 6.0)
	var hover := flat(Color(fill.lightened(0.06), 0.95), 18.0, 6.0)
	var pressed := flat(Color(fill.darkened(0.12), 0.95), 18.0, 6.0)
	var disabled := flat(Color(TEXT, 0.04), 18.0, 6.0)
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus_underline())


## Secondary action (Pass 4): any action that is not the surface's one
## primary. Faint ivory wash, no border, radius 6, MUTED → TEXT; keyboard
## focus adds the ACCENT underline. danger = red text (pair with confirm).
static func secondary_action(button: Button, font_size: int = 15, height: float = 36.0,
		danger: bool = false) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, height)
	button.add_theme_font_size_override("font_size", font_size)
	_text_colors(button, Color(BunkerDesign.RED, 0.9) if danger else MUTED)
	if danger:
		for key: String in ["font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			button.add_theme_color_override(key, BunkerDesign.RED.lightened(0.12))
	var base := flat(Color(TEXT, 0.04), 14.0, 5.0)
	var hover := flat(Color(TEXT, 0.075), 14.0, 5.0)
	var pressed := flat(Color(TEXT, 0.02), 14.0, 5.0)
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", hover)
	button.add_theme_stylebox_override("disabled", flat(Color(TEXT, 0.02), 14.0, 5.0))
	button.add_theme_stylebox_override("focus", focus_underline())
	button.add_theme_color_override("icon_normal_color", MUTED)
	button.add_theme_color_override("icon_hover_color", TEXT)
	button.add_theme_color_override("icon_pressed_color", TEXT)
	button.add_theme_color_override("icon_focus_color", TEXT)


## Selected tab / segment (toggle buttons): MUTED text at rest, TEXT when
## pressed, with a 2 px ACCENT underline under the pressed one. No fills.
static func tab_button(button: Button, font_size: int = 15, height: float = 36.0) -> void:
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, height)
	button.add_theme_font_size_override("font_size", font_size)
	_text_colors(button)
	var base := flat(Color(0, 0, 0, 0), 12.0, 4.0, 0)
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(TEXT, 0.035)
	var active := base.duplicate() as StyleBoxFlat
	active.border_color = ACCENT
	active.border_width_bottom = 2
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_stylebox_override("disabled", base)
	## Focus must never read as a second selection: a faint 1 px ivory
	## underline (selection is the 2 px ACCENT one).
	var focus := flat(Color(0, 0, 0, 0), 12.0, 4.0, 0)
	focus.border_color = Color(TEXT, 0.4)
	focus.border_width_bottom = 1
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("icon_normal_color", Color(MUTED, 0.8))
	button.add_theme_color_override("icon_hover_color", TEXT)
	button.add_theme_color_override("icon_pressed_color", TEXT)


## Keyboard/controller focus for free-standing buttons (no FocusRail):
## a 2 px ACCENT underline, no box.
static func focus_underline() -> StyleBoxFlat:
	var style := flat(Color(0, 0, 0, 0), 0.0, 0.0, 0)
	style.border_color = ACCENT
	style.border_width_bottom = 2
	return style


## Text action in muted red. Pair with confirm_twice() for anything that
## cannot be undone.
static func destructive_action(button: Button, font_size: int = 15, height: float = 30.0) -> void:
	nav_button(button, font_size, height)
	var red := Color(BunkerDesign.RED, 0.85)
	button.add_theme_color_override("font_color", red)
	button.add_theme_color_override("font_hover_color", BunkerDesign.RED.lightened(0.15))
	button.add_theme_color_override("font_focus_color", BunkerDesign.RED.lightened(0.15))
	button.add_theme_color_override("font_pressed_color", BunkerDesign.RED)


## Two-step confirmation in place. First press swaps the caption to `prompt`
## for `seconds`; a second press inside that window returns true.
##   if Q.confirm_twice(exit_button, "Press again to exit"): get_tree().quit()
static func confirm_twice(button: Button, prompt: String, seconds: float = 3.0) -> bool:
	var now := Time.get_ticks_msec()
	if button.has_meta(&"quiet_armed_until") and now <= int(button.get_meta(&"quiet_armed_until")):
		_disarm(button)
		return true
	if not button.has_meta(&"quiet_armed_caption"):
		button.set_meta(&"quiet_armed_caption", button.text)
	button.set_meta(&"quiet_armed_until", now + int(seconds * 1000.0))
	button.text = prompt
	var serial := now
	button.set_meta(&"quiet_armed_serial", serial)
	button.get_tree().create_timer(seconds, true).timeout.connect(func() -> void:
		if is_instance_valid(button) and int(button.get_meta(&"quiet_armed_serial", 0)) == serial:
			_disarm(button))
	return false


static func _disarm(button: Button) -> void:
	if button.has_meta(&"quiet_armed_caption"):
		button.text = str(button.get_meta(&"quiet_armed_caption"))
		button.remove_meta(&"quiet_armed_caption")
	if button.has_meta(&"quiet_armed_until"):
		button.remove_meta(&"quiet_armed_until")


## Two-line list action (save slots, pickers): 16 px title + 13 px muted
## caption, flat, brightening on hover/focus. Pair with a FocusRail.
## Update with set_list_action().
static func list_action(title: String, caption: String = "", height: float = 60.0) -> Button:
	var button := Button.new()
	nav_button(button, 16, height)
	button.text = ""
	var copy := VBoxContainer.new()
	copy.name = "Copy"
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 2)
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	copy.offset_left = 14.0
	copy.offset_right = -14.0
	button.add_child(copy)
	var title_label := label(title, 16, TEXT)
	title_label.name = "Title"
	copy.add_child(title_label)
	var caption_label := label(caption, 13, MUTED)
	caption_label.name = "Caption"
	caption_label.visible = not caption.is_empty()
	copy.add_child(caption_label)
	button.set_meta(&"quiet_title", title_label)
	button.set_meta(&"quiet_caption", caption_label)
	var refresh := func() -> void:
		var lit: bool = button.has_focus() or button.is_hovered()
		copy.modulate.a = 0.35 if button.disabled else (1.0 if lit else 0.78)
	for signal_name: String in ["focus_entered", "focus_exited", "mouse_entered", "mouse_exited",
			"visibility_changed"]:
		button.connect(signal_name, refresh)
	button.set_meta(&"quiet_refresh", refresh)
	refresh.call()
	return button


static func set_list_action(button: Button, title: String, caption: String = "",
		disabled: bool = false) -> void:
	(button.get_meta(&"quiet_title") as Label).text = title
	var caption_label := button.get_meta(&"quiet_caption") as Label
	caption_label.text = caption
	caption_label.visible = not caption.is_empty()
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	(button.get_meta(&"quiet_refresh") as Callable).call()


# ── Data display ─────────────────────────────────────────────────────────────

## Slim meter: 3 px track, ACCENT fill. Use a BunkerSmoothProgressBar for live
## values (first update snaps, then eases). set_meter_state() recolours the
## fill only when the value needs attention.
static func meter(bar: ProgressBar, height: float = 3.0) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := flat(Color(TEXT, 0.09), 0.0, 0.0, 2)
	bar.add_theme_stylebox_override("background", track)
	set_meter_state(bar, "normal")


## state: "normal" | "good" | "warning" | "critical"
static func set_meter_state(bar: ProgressBar, state: String) -> void:
	bar.add_theme_stylebox_override("fill", flat(Color(state_color(state, ACCENT), 0.75), 0.0, 0.0, 2))


## Semantic colour for a state; `normal` falls back to the caller's neutral.
static func state_color(state: String, normal: Color = MUTED) -> Color:
	match state:
		"good":
			return BunkerDesign.GREEN
		"warning":
			return BunkerDesign.WARNING
		"critical":
			return BunkerDesign.RED
	return normal


## Eyebrow over a large value with a muted unit. Update with set_stat().
static func stat(caption: String, value: String, unit: String = "", value_size: int = 26) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.add_child(eyebrow(caption, 12))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	var value_label := label(value, value_size, TEXT)
	value_label.name = "Value"
	value_label.add_theme_font_override("font", load("res://assets/fonts/IosevkaCharon-Medium.ttf"))
	line.add_child(value_label)
	var unit_label := label(unit, maxi(12, roundi(value_size * 0.55)), MUTED)
	unit_label.name = "Unit"
	unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	unit_label.visible = not unit.is_empty()
	line.add_child(unit_label)
	box.set_meta(&"quiet_value", value_label)
	box.set_meta(&"quiet_unit", unit_label)
	return box


static func set_stat(box: Control, value: String, unit: String = "", state: String = "normal") -> void:
	var value_label := box.get_meta(&"quiet_value") as Label
	var unit_label := box.get_meta(&"quiet_unit") as Label
	value_label.text = value
	value_label.add_theme_color_override("font_color", state_color(state, TEXT))
	unit_label.text = unit
	unit_label.visible = not unit.is_empty()


## Dot + word. Nominal reads quietly (MUTED text, ACCENT dot); only a real
## deviation takes semantic colour. Replaces every pill/badge.
static func status_line(text: String, state: String = "normal", font_size: int = 14) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	var dot := label("●", 11, ACCENT)
	dot.name = "Dot"
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(dot)
	var word := label(text, font_size, MUTED)
	word.name = "Word"
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(word)
	set_status(line, text, state)
	return line


static func set_status(line: Control, text: String, state: String = "normal") -> void:
	var dot := line.get_node("Dot") as Label
	var word := line.get_node("Word") as Label
	word.text = text
	var deviation := state != "normal"
	dot.add_theme_color_override("font_color", state_color(state, ACCENT))
	word.add_theme_color_override("font_color", state_color(state, MUTED) if deviation else MUTED)


# ── Surfaces ─────────────────────────────────────────────────────────────────

## Selectable tile for items with a 3D preview (catalog, storage, shop).
## Selection = TEXT name + ACCENT underline edge; no outline box.
static func tile(button: BaseButton) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base := flat(Color(TEXT, 0.03), 10.0, 10.0, 8)
	var hover := flat(Color(TEXT, 0.06), 10.0, 10.0, 8)
	var selected := flat(Color(TEXT, 0.06), 10.0, 10.0, 8)
	selected.border_color = ACCENT
	selected.border_width_bottom = 2
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	button.add_theme_stylebox_override("disabled", flat(Color(TEXT, 0.015), 10.0, 10.0, 8))
	button.add_theme_stylebox_override("focus", flat(Color(TEXT, 0.05), 10.0, 10.0, 8))


## Docked-inspector / dialog header: eyebrow + title left, quiet "Close"
## text action right (omit on_close for no close action).
static func inspector_header(eyebrow_text: String, title_text: String,
		on_close: Callable = Callable(), title_size: int = 26) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "QuietHeader"
	header.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	header.add_child(copy)
	var brow := eyebrow(eyebrow_text, 12)
	brow.name = "Eyebrow"
	copy.add_child(brow)
	var title := label(title_text, title_size, TEXT)
	title.name = "Title"
	copy.add_child(title)
	if on_close.is_valid():
		var close := Button.new()
		close.name = "Close"
		close.text = "Close"
		nav_button(close, 14, 30.0)
		close.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		close.pressed.connect(on_close)
		header.add_child(close)
	return header


## Centered dialog surface (confirmations, rename, zone colour).
static func dialog_box() -> StyleBoxFlat:
	var style := shell_box(8)
	style.bg_color = POPUP
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 20.0
	return style


## World-anchored surfaces (prompts, hover cards) follow projected 3D points
## that move by fractions of a pixel as the camera eases. Godot snaps every
## unrotated Control to whole pixels, so such text ticks 1 px at irregular
## intervals ("stutter") while the world glides. Snapping is skipped for
## rotated Controls, so a visually nil rotation restores true sub-pixel
## motion (measured: 0.2 px steps instead of 1 px jumps). Use only on
## surfaces that track the world.
const SUBPIXEL_ROTATION: float = 0.0001

static func allow_subpixel(control: Control) -> void:
	control.rotation = SUBPIXEL_ROTATION


## Registers a surface that notification toasts must never cover.
## modal = true for centred workspaces/dialogs (ordinary toasts then wait
## until it closes); false for docked panels and top strips (toasts move
## around them). Visibility is checked live, so register once at build time.
static func avoid_toasts(control: Control, modal: bool = false) -> void:
	control.add_to_group(&"ui_toast_avoid")
	control.set_meta(&"toast_modal", modal)


## Toast surface: soft charcoal scrim, no border, no stripe.
static func toast_box() -> StyleBoxFlat:
	var style := flat(Color(0.047, 0.061, 0.058, 0.9), 16.0, 10.0, 8)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	return style


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
