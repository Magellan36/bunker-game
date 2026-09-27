extends RefCounted
## Small native-control vocabulary shared by device inspectors only.
## Device-specific order/wording lives in its UI file's _build_content().
##
## Sep 2026 quiet pass (docs/ui/QUIET_DESIGN_SYSTEM.md, archetype B): the same
## node structure and API as before, drawn in the quiet language. No icons,
## no pills or bordered cards; status is a dot + word, readings are rows and
## 3 px meters, colour appears only when a value needs attention. Node paths
## (Row/State, Row/Icon, Heading/Value, Caption/Value, Hint, Bar) are kept so
## device adapters and tests address the same children.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")

## Legacy token → quiet palette. "success" reads as nominal (ACCENT) — the
## design reserves green for the rare case where "good" must stand out.
const TOKENS: Dictionary = {
	"text": Q.TEXT, "secondary": Q.MUTED, "blue": Q.ACCENT, "success": Q.ACCENT,
	"warning": BunkerDesign.WARNING, "critical": BunkerDesign.RED,
	"inactive": Q.FAINT, "brass": Q.HEADING, "background": Q.SURFACE,
}

## Kept for adapters that still ask for a symbol; the quiet shell shows none.
static func icon(kind: String) -> Texture2D:
	return BunkerPanelStyle.icon(kind)

static func color(_control: Control, token: String) -> Color:
	return TOKENS.get(token, Q.TEXT)

## Maps a legacy colour token onto Q meter/status states.
static func state(token: String) -> String:
	match token:
		"warning": return "warning"
		"critical": return "critical"
	return "normal"

static func column(parent: Node, key: String, gap: int = 6) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = key
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.set_meta("ui_gap", gap)
	parent.add_child(box)
	return box

static func label(parent: Node, key: String, text: String, font_size: int = 16, token: String = "text") -> Label:
	var control := Label.new()
	control.name = key
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Body copy settles at 14–16; the old 18 px default was card-era sizing.
	var quiet_size: int = mini(font_size, 16) if font_size > 14 else font_size
	control.set_meta("ui_font_size", quiet_size)
	control.add_theme_font_size_override("font_size", quiet_size)
	control.add_theme_color_override("font_color", color(control, token))
	parent.add_child(control)
	return control

## Group heading (tracked brass caps). Replaces bordered cards for grouping.
static func heading(parent: Node, key: String, text: String) -> Label:
	var control: Label = Q.eyebrow(text, 12)
	control.name = key
	control.set_meta("ui_font_size", 12)
	## Section rhythm: extra air above a group heading, tight below (design §2).
	control.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	control.custom_minimum_size.y = 30.0
	control.set_meta("ui_min_height", 30)
	parent.add_child(control)
	return control

## Text action. primary = the surface's one main action (steel fill); other
## actions are quiet text buttons that brighten on hover/focus.
static func button(parent: Node, key: String, text: String, callback: Callable, _kind: String = "", primary: bool = false) -> Button:
	var control := Button.new()
	control.name = key
	control.text = text
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.clip_text = true
	control.tooltip_text = ""
	var height: float = 40.0 if primary else 34.0
	if primary:
		Q.primary_action(control, 16, height)
	else:
		Q.nav_button(control, 15, height)
	control.set_meta("ui_font_size", 16 if primary else 15)
	control.set_meta("ui_min_height", height)
	parent.add_child(control)
	if callback.is_valid():
		control.pressed.connect(callback)
	return control

## Switch row: caption left, "On/Off" + SwitchGlyph right. `callback` runs on
## press; owners confirm and the adapter re-syncs with set_switch().
static func switch_row(parent: Node, key: String, caption: String, callback: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.name = key + "Row"
	row.set_meta("ui_gap", 12)
	parent.add_child(row)
	var name_label: Label = label(row, "Caption", caption, 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var toggle := CheckButton.new()
	toggle.name = key
	row.add_child(toggle)
	Q.switch(toggle, 15)
	toggle.set_meta("ui_min_height", 34)
	toggle.custom_minimum_size.y = 34
	if callback.is_valid():
		toggle.pressed.connect(callback)
	return toggle

static func set_switch(toggle: CheckButton, on: bool) -> void:
	toggle.set_pressed_no_signal(on)
	Q.set_switch_text(toggle)

## Status line: tinted dot + word. PanelContainer root kept for API
## compatibility (adapters type these as PanelContainer).
static func status(parent: Node, key: String) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.name = key
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(holder)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("ui_gap", 8)
	holder.add_child(row)
	var dot := TextureRect.new()
	dot.name = "Icon"   ## tinted like the old icon (zone colours use it)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.texture = Q._disc(16, Color.WHITE)
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.set_meta("ui_icon_size", 8)
	dot.custom_minimum_size = Vector2(8, 8)
	row.add_child(dot)
	var word: Label = label(row, "State", "", 15, "secondary")
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	word.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return holder

## Nominal ("success"/"text"/"blue") reads quietly: ACCENT dot, MUTED word.
## Warning/critical colour both; inactive dims the dot.
static func set_status(card: PanelContainer, text: String, token: String, _kind: String = "") -> void:
	var caption: Label = card.get_node("Row/State") as Label
	caption.text = text
	var deviation: bool = token == "warning" or token == "critical"
	caption.add_theme_color_override("font_color", color(card, token) if deviation else Q.MUTED)
	var dot: TextureRect = card.get_node("Row/Icon") as TextureRect
	dot.self_modulate = color(card, token) if deviation or token == "inactive" else Q.ACCENT

## Reading row: caption left (MUTED), value right (TEXT).
static func stat(parent: Node, key: String, caption: String,
		_caption_size: int = 15, _value_size: int = 15) -> VBoxContainer:
	var box: VBoxContainer = column(parent, key, 2)
	var row := HBoxContainer.new()
	row.name = "Line"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("ui_gap", 12)
	box.add_child(row)
	var name_label: Label = label(row, "Caption", caption, 15, "secondary")
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var value: Label = label(row, "Value", "—", 15)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	## Legacy callers address Caption/Value directly under the stat.
	box.set_meta(&"caption", name_label)
	box.set_meta(&"value", value)
	return box

static func set_stat(box: VBoxContainer, text: String, token: String = "text") -> void:
	var value: Label = box.get_node("Line/Value") as Label
	value.text = text
	value.add_theme_color_override("font_color", color(box, token) if token != "blue" and token != "success" else Q.TEXT)


static func set_power_button(button: Button, powered: bool) -> void:
	## Text describes the available action; it stays the surface's one main action.
	button.text = "Power off" if powered else "Power on"
	button.tooltip_text = ""

## Former bordered card. Now a borderless group holder with no inset, so the
## content aligns to the shell edges. Structure (Card/Inset) is unchanged.
static func frame(parent: Node, key: String) -> MarginContainer:
	var card := PanelContainer.new()
	card.name = key
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(card)
	var margin := MarginContainer.new()
	margin.name = "Inset"
	margin.set_meta("ui_padding", 0)
	card.add_child(margin)
	return margin

## Meter: caption left, value right, 3 px bar, optional MUTED hint.
static func meter(parent: Node, key: String, caption: String, _kind: String = "",
		boxed: bool = false) -> VBoxContainer:
	var content_parent: Node = parent
	if boxed:
		content_parent = frame(parent, key + "Card")
	var box: VBoxContainer = column(content_parent, key, 6)
	var row := HBoxContainer.new()
	row.name = "Heading"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("ui_gap", 12)
	box.add_child(row)
	var name_label: Label = label(row, "Caption", caption, 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var value: Label = label(row, "Value", "0%", 15, "secondary")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Q.meter(bar, 3.0)
	bar.set_meta("ui_min_height", 3)
	box.add_child(bar)
	label(box, "Hint", "", 13, "secondary")
	return box

static func set_meter(box: VBoxContainer, percent: float, value: String, hint: String, token: String = "blue") -> void:
	var readout: Label = box.get_node("Heading/Value") as Label
	readout.text = value
	var meter_state: String = state(token)
	readout.add_theme_color_override("font_color", Q.state_color(meter_state, Q.MUTED))
	var help: Label = box.get_node("Hint") as Label
	help.text = hint
	help.visible = not hint.is_empty()
	var bar: ProgressBar = box.get_node("Bar") as ProgressBar
	SMOOTH_BAR.apply(bar, clampf(percent, 0.0, 100.0))
	if bar.get_meta(&"quiet_state", "") != meter_state:
		bar.set_meta(&"quiet_state", meter_state)
		Q.set_meter_state(bar, meter_state)

static func quality_token(quality: float) -> String:
	# Preserve the water system's inclusive boundaries, not generator-health thresholds.
	return "critical" if quality <= 50.0 else ("warning" if quality <= 75.0 else "success")

## Full-width value dropdown (seed locks). Quiet popup; Left/Right cycles.
static func option(parent: Node, key: String) -> OptionButton:
	var control := OptionButton.new()
	control.name = key
	control.fit_to_longest_item = false
	control.clip_text = true
	parent.add_child(control)
	Q.option(control, 15, 0.0)
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.set_meta("ui_font_size", 15)
	control.set_meta("ui_min_height", 34)
	control.custom_minimum_size.y = 34
	return control


## Restyles an inspector shell scene (DeviceInspectPanel / GeneratorInspectPanel,
## same node contract) in the quiet language and returns its FocusRail.
## Header = brass eyebrow + title + text "Close"; hairline dividers; quiet
## scrollbar; the rail sits behind the content; key hints replace the old
## sentence footer (the %NavigationHint label stays, hidden, for callers).
static func quiet_shell(view: Control, close_btn: Button) -> Control:
	var panel: PanelContainer = view.get_node("%Panel") as PanelContainer
	panel.add_theme_stylebox_override("panel", Q.shell_box(12))
	view.theme.default_font = UIKit.font()   ## Iosevka Charon, like every quiet surface
	var rail: Control = (load("res://scripts/ui/common/FocusRail.gd") as GDScript).new()
	rail.name = "FocusRail"
	rail.set("color", Q.ACCENT)
	rail.set("rail_offset", 14.0)
	rail.set("wash_extent", 0.9)
	rail.set("wash_alpha", 0.1)
	panel.add_child(rail)
	panel.move_child(rail, 0)   ## behind the content, above the shell fill
	(view.get_node("Panel/Margin") as Control).set_meta("ui_padding", 24)
	var header: Node = view.get_node("Panel/Margin/Content/Header")
	for child: Node in header.get_children():
		if child is TextureRect:
			(child as TextureRect).visible = false
	## No icons in the quiet language: hide scene-authored meter/heading icons.
	for node: Node in view.find_children("Icon", "TextureRect", true, false):
		if node.get_parent().name == "Heading":
			(node as TextureRect).visible = false
	var eyebrow: Label = header.get_node("Titles/Eyebrow") as Label
	eyebrow.text = eyebrow.text.to_upper()
	eyebrow.set_meta("ui_font_size", 12)
	eyebrow.add_theme_color_override("font_color", Q.HEADING)
	Q.tracked(eyebrow, 3)
	var title: Label = view.get_node("%Title") as Label
	title.set_meta("ui_font_size", 26)
	title.add_theme_color_override("font_color", Q.TEXT)
	close_btn.theme_type_variation = &""
	close_btn.text = "Close"
	close_btn.tooltip_text = ""
	if close_btn.has_meta("ui_icon_size"):
		close_btn.remove_meta("ui_icon_size")
	Q.nav_button(close_btn, 14, 30.0)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_btn.custom_minimum_size = Vector2(0.0, 30.0)
	close_btn.set_meta("ui_font_size", 14)
	for divider: Node in view.find_children("*", "HSeparator", true, false):
		(divider as HSeparator).add_theme_stylebox_override("separator", Q.hairline())
	var scroll: ScrollContainer = view.get_node("%DetailsScroll") as ScrollContainer
	Q.scrollbar(scroll.get_v_scroll_bar())
	(view.get_node("Panel/Margin/Content") as Control).set_meta("ui_gap", 14)
	(view.get_node("Panel/Margin/Content/StatusRow") as Control).set_meta("ui_gap", 22)
	(view.get_node("Panel/Margin/Content/DetailsLane/DetailsScroll/FocusInset/Details") as Control).set_meta("ui_gap", 16)
	var nav_hint: Label = view.get_node("%NavigationHint") as Label
	nav_hint.visible = false
	var hints := HBoxContainer.new()
	hints.name = "KeyHints"
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.alignment = BoxContainer.ALIGNMENT_END
	hints.add_theme_constant_override("separation", 16)
	nav_hint.get_parent().add_child(hints)
	BunkerUIComponents.key_hint(hints, "ENTER", "Select", "ENTER", "A")
	BunkerUIComponents.key_hint(hints, "ESC", "Close", "ESC", "B")
	return rail
