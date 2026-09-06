extends CanvasLayer
## Compact companion panel for the native Power Terminal.
## Preserves ZoneCustomizeUI's public signal/open contracts exactly.

signal closed
signal name_changed(zone_key: String, new_name: String)
signal color_changed(zone_key: String, new_color: Color)

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const FADE: GDScript = preload("res://scripts/ui/common/UIFade.gd")

const RENAME_SIZE := Vector2(520.0, 470.0)
const COLOR_SIZE := Vector2(570.0, 690.0)
const EDGE_MARGIN := Vector2(36.0, 30.0)
const NAME_LIMIT: int = 18
const MODE_RENAME: int = 0
const MODE_COLOR: int = 1
const COLOR_NAMES: Array[String] = [
	"Signal red", "Burnt orange", "Emergency amber", "Sulfur yellow",
	"Utility lime", "Working green", "Spring green", "Coolant teal",
	"Cyan", "Bunker blue", "Deep blue", "Indigo",
	"Violet", "Magenta", "Rose", "Warning pink",
]

var _zone_key: String = ""
var _current_name: String = ""
var _mode: int = MODE_RENAME
var _is_open: bool = false
var _controller_hints: bool = false
var _previous_focus: WeakRef

var _view: Control
var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _close_button: Button
var _preview_swatch: ColorRect
var _preview_name: Label
var _preview_detail: Label
var _rename_content: VBoxContainer
var _color_content: VBoxContainer
var _name_edit: LineEdit
var _character_count: Label
var _apply_button: Button
var _cancel_button: Button
var _swatch_buttons: Array[Button] = []
var _footer_hint: Label
var _controller_nav: Node


func _ready() -> void:
	layer = 60
	visible = false
	_build_interface()
	_controller_nav = NAV.new()
	_controller_nav.ui_root = self
	_controller_nav.stick_navigation = false
	_controller_nav.right_stick_navigation = true
	add_child(_controller_nav)
	get_viewport().size_changed.connect(_layout)
	set_process(false)
	_layout()


func open_rename(zone_key: String, current_name: String) -> void:
	_begin_open(zone_key, MODE_RENAME)
	_current_name = current_name
	_title.text = "Rename zone"
	_subtitle.text = "Give this power segment a recognizable name."
	_rename_content.visible = true
	_color_content.visible = false
	_name_edit.text = current_name
	_update_name_preview(current_name)
	_update_character_count(current_name)
	_apply_button.text = "Apply name"
	_layout()
	_name_edit.call_deferred("grab_focus")
	_name_edit.call_deferred("select_all")


func open_color(zone_key: String, current_display_color: Color) -> void:
	_begin_open(zone_key, MODE_COLOR)
	_title.text = "Zone color"
	_subtitle.text = "Choose how this power segment appears across the bunker."
	_rename_content.visible = false
	_color_content.visible = true
	_preview_swatch.color = current_display_color
	_preview_name.text = _resolved_zone_name()
	_preview_detail.text = "Wire overlays and zone markers update immediately"
	_highlight_matching_swatch(current_display_color)
	_layout()
	var target: Button = _matching_swatch(current_display_color)
	if target == null and not _swatch_buttons.is_empty():
		target = _swatch_buttons[0]
	if target != null:
		target.call_deferred("grab_focus")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	set_process(false)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _view.is_ancestor_of(focused):
		focused.release_focus()
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref() as Control
			if is_instance_valid(previous) and previous.is_visible_in_tree():
				previous.grab_focus()
	closed.emit()


func is_open() -> bool:
	return _is_open


func _begin_open(zone_key: String, mode: int) -> void:
	if not _is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	_zone_key = zone_key
	_mode = mode
	_is_open = true
	visible = true
	_update_zone_preview()
	_update_input_hint()
	set_process(true)
	FADE.fade_in(_panel)


func _process(_delta: float) -> void:
	if _controller_hints != InputMode.is_controller():
		_update_input_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not _controller_nav._is_topmost():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()


func _build_interface() -> void:
	_view = Control.new()
	_view.name = "ZoneCustomizeWorkspace"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	C.apply_theme(_view)
	_backdrop = UIKit.build_modal_backdrop(0.50)
	_view.add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)
	_panel = PanelContainer.new()
	_panel.name = "ZoneCustomizePanel"
	C.shell(_panel, 10)
	_view.add_child(_panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 11)
	_panel.add_child(C.inset(content, 20, 17, 20, 13))
	_build_header(content)
	C.divider(content)
	content.add_child(_build_preview())
	_build_rename_content(content)
	_build_color_content(content)
	var grow: Control = Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grow)
	C.divider(content)
	_footer_hint = _label("", 12, S.MUTED)
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer_hint)


func _build_header(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(C.icon_well("grid", 50.0, S.BLUE))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(_label("ZONE SETTINGS", 12, S.BLUE))
	_title = _label("Rename zone", 25, S.IVORY)
	copy.add_child(_title)
	_close_button = Button.new()
	_close_button.custom_minimum_size = Vector2(46.0, 46.0)
	_close_button.tooltip_text = "Close without making changes"
	S.icon_button(_close_button, "close")
	_close_button.text = ""
	_close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_button.pressed.connect(close)
	row.add_child(_close_button)
	_subtitle = _label("", 13, S.MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_subtitle)


func _build_preview() -> PanelContainer:
	var card: PanelContainer = _card(Color("19201f"), S.BRASS.darkened(0.38))
	card.custom_minimum_size.y = 72.0
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(C.inset(row, 12, 9, 12, 9))
	_preview_swatch = ColorRect.new()
	_preview_swatch.custom_minimum_size = Vector2(48.0, 48.0)
	_preview_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_preview_swatch)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	_preview_name = _label("Zone", 18, S.IVORY)
	_preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(_preview_name)
	_preview_detail = _label("", 12, S.MUTED)
	copy.add_child(_preview_detail)
	var live: PanelContainer = _pill("LIVE", S.GREEN)
	row.add_child(live)
	return card


func _build_rename_content(parent: Container) -> void:
	_rename_content = VBoxContainer.new()
	_rename_content.add_theme_constant_override("separation", 9)
	parent.add_child(_rename_content)
	var heading: HBoxContainer = HBoxContainer.new()
	_rename_content.add_child(heading)
	var field_label: Label = _label("ZONE NAME", 12, S.MUTED)
	field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(field_label)
	_character_count = _label("0 / 18", 12, S.BRASS.lightened(0.30))
	heading.add_child(_character_count)
	_name_edit = LineEdit.new()
	_name_edit.max_length = NAME_LIMIT
	_name_edit.placeholder_text = "Automatic zone name"
	_name_edit.custom_minimum_size.y = 48.0
	S.field(_name_edit)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_rename_content.add_child(_name_edit)
	var hint: Label = _label(
		"Leave the field blank to restore the automatically assigned zone name.", 12, S.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rename_content.add_child(hint)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_rename_content.add_child(actions)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.icon = S.icon("close")
	S.button(_cancel_button)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.pressed.connect(close)
	actions.add_child(_cancel_button)
	_apply_button = Button.new()
	_apply_button.text = "Apply name"
	_apply_button.icon = S.icon("check")
	S.button(_apply_button, true)
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.pressed.connect(_submit_name)
	actions.add_child(_apply_button)


func _build_color_content(parent: Container) -> void:
	_color_content = VBoxContainer.new()
	_color_content.add_theme_constant_override("separation", 9)
	parent.add_child(_color_content)
	var heading: HBoxContainer = HBoxContainer.new()
	_color_content.add_child(heading)
	var title_label: Label = _label("CHOOSE ZONE COLOR", 12, S.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	heading.add_child(_pill("APPLIES IMMEDIATELY", S.BLUE))
	var instruction: Label = _label(
		"Color is used for wire overlays, terminal readouts, and connected-zone markers.", 12, S.MUTED)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_color_content.add_child(instruction)
	var well: PanelContainer = _card(Color("141918"), S.BRASS.darkened(0.48))
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_color_content.add_child(well)
	var center: CenterContainer = CenterContainer.new()
	well.add_child(C.inset(center, 12, 12, 12, 12))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	center.add_child(grid)
	_swatch_buttons.clear()
	for index: int in range(DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES.size()):
		var color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[index]
		var button: Button = _swatch_button(color, index)
		grid.add_child(button)
		_swatch_buttons.append(button)
	var note: Label = _label(
		"Player-selected colors remain fixed even if neighboring zones use the same color.",
		12, S.BRASS.lightened(0.28))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_color_content.add_child(note)


func _swatch_button(color: Color, index: int) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(72.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = COLOR_NAMES[index]
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", _contrast_color(color))
	button.add_theme_color_override("font_hover_color", _contrast_color(color))
	button.add_theme_color_override("font_pressed_color", _contrast_color(color))
	button.add_theme_stylebox_override("normal", _swatch_style(color, S.BG, 2))
	button.add_theme_stylebox_override("hover", _swatch_style(color.lightened(0.05), S.IVORY, 2))
	button.add_theme_stylebox_override("pressed", _swatch_style(color.darkened(0.08), S.IVORY, 3))
	button.add_theme_stylebox_override("focus", _swatch_style(Color.TRANSPARENT, S.BLUE, 3))
	button.pressed.connect(_on_swatch_pressed.bind(index))
	return button


func _swatch_style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = C.panel_box(color, border, 8, width)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style


func _begin_selected_style(button: Button, color: Color, selected: bool) -> void:
	button.text = "✓" if selected else ""
	button.add_theme_stylebox_override("normal", _swatch_style(
		color, S.IVORY if selected else S.BG, 4 if selected else 2))


func _highlight_matching_swatch(current_color: Color) -> void:
	for index: int in range(_swatch_buttons.size()):
		var color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[index]
		_begin_selected_style(_swatch_buttons[index], color,
			color.is_equal_approx(current_color))


func _matching_swatch(current_color: Color) -> Button:
	for index: int in range(_swatch_buttons.size()):
		var color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[index]
		if color.is_equal_approx(current_color):
			return _swatch_buttons[index]
	return null


func _on_name_changed(text: String) -> void:
	_update_character_count(text)
	_update_name_preview(text)


func _update_character_count(text: String) -> void:
	_character_count.text = "%d / %d" % [text.length(), NAME_LIMIT]
	_character_count.add_theme_color_override("font_color",
		S.BRASS.lightened(0.30) if text.length() < NAME_LIMIT else S.BLUE)


func _update_name_preview(text: String) -> void:
	var trimmed: String = text.strip_edges()
	_preview_name.text = trimmed if not trimmed.is_empty() else "Automatic zone name"
	_preview_detail.text = "Saved to this zone's stable wire identity"


func _submit_name() -> void:
	_on_name_submitted(_name_edit.text)


func _on_name_submitted(text: String) -> void:
	name_changed.emit(_zone_key, text.strip_edges())
	close()


func _on_swatch_pressed(index: int) -> void:
	if index < 0 or index >= DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES.size():
		return
	var color: Color = DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[index]
	_preview_swatch.color = color
	color_changed.emit(_zone_key, color)
	close()


func _update_zone_preview() -> void:
	var zone: Dictionary = _zone_snapshot()
	_preview_swatch.color = _zone_color(zone)
	_preview_name.text = _zone_name_for(zone)
	_preview_detail.text = "Saved to this zone's stable wire identity"


func _zone_snapshot() -> Dictionary:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return {}
	for raw_zone: Variant in pm.get_zone_snapshot():
		var zone: Dictionary = raw_zone as Dictionary
		if String(zone.get("zone_key", "")) == _zone_key:
			return zone
	return {}


func _zone_color(zone: Dictionary) -> Color:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or zone.is_empty():
		return S.BLUE
	return pm.zone_display_color(String(zone.get("zone_key", "")),
		int(zone.get("color_index", 0)), 1.0)


func _zone_name_for(zone: Dictionary) -> String:
	if zone.is_empty():
		return _current_name if not _current_name.is_empty() else "Power zone"
	var fallback: String = "Z%d" % int(zone.get("zone_index", 0))
	return String(zone.get("zone_name", fallback))


func _resolved_zone_name() -> String:
	return _zone_name_for(_zone_snapshot())


func _layout() -> void:
	if _panel == null:
		return
	var wanted: Vector2 = RENAME_SIZE if _mode == MODE_RENAME else COLOR_SIZE
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var actual: Vector2 = Vector2(
		minf(wanted.x, maxf(420.0, viewport_size.x - EDGE_MARGIN.x * 2.0)),
		minf(wanted.y, maxf(360.0, viewport_size.y - EDGE_MARGIN.y * 2.0)))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -actual.x * 0.5
	_panel.offset_right = actual.x * 0.5
	_panel.offset_top = -actual.y * 0.5
	_panel.offset_bottom = actual.y * 0.5


func _update_input_hint() -> void:
	_controller_hints = InputMode.is_controller()
	_footer_hint.text = "[A] Select     D-pad / R-stick  Navigate     [B] Cancel" \
		if _controller_hints else "Enter  Apply     Mouse / Arrows  Navigate     Esc / E  Cancel"


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close()
			get_viewport().set_input_as_handled()


func _card(background: Color, border: Color) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", C.panel_box(background, border, 7, 1))
	return card


func _label(text_value: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _pill(text_value: String, color: Color) -> PanelContainer:
	var panel: PanelContainer = _card(S.BG.lerp(color, 0.10), S.BG.lerp(color, 0.52))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = _label(text_value, 11, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(52.0, 24.0)
	panel.add_child(label)
	return panel


func _contrast_color(color: Color) -> Color:
	var luminance: float = color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return Color("18201f") if luminance > 0.58 else S.IVORY
