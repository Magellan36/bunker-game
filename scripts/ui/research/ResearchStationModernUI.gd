extends CanvasLayer
class_name ResearchStationModernUI

## Native-Control Research Station workspace.  Presentation is new; all
## research state and actions remain authoritative on ResearchStation.

signal closed

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PROXIMITY: GDScript = preload("res://scripts/ui/common/UIProximityClose.gd")
const FADE: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const PATH_CANVAS: GDScript = preload("res://scripts/ui/research/ResearchPathCanvas.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")
const WATER_UPGRADE: UpgradeDef = preload("res://data/upgrades/bunker_water_output_2x.tres")

const PANEL_MAX: Vector2 = Vector2(1360.0, 800.0)
const EDGE: Vector2 = Vector2(44.0, 36.0)
const REFRESH_INTERVAL: float = 0.20
const BUNKER_TAB: int = 0
const PLAYER_TAB: int = 1
const NPC_TAB: int = 2
const TREE_BASE_SIZE: Vector2 = Vector2(780.0, 410.0)
const ZOOM_STEPS: Array[float] = [0.85, 1.0, 1.15]

var is_open: bool = false
var _current_station: ResearchStation = null
var _active_tab: int = BUNKER_TAB
var _refresh_elapsed: float = 0.0
var _controller_hints: bool = false
var _previous_focus: WeakRef = null
var _state_signature: String = ""
var _header_status_key: String = ""
var _zoom_index: int = 1

var _view: Control = null
var _panel: PanelContainer = null
var _header_status: PanelContainer = null
var _header_status_icon: TextureRect = null
var _header_status_text: Label = null
var _close_button: Button = null
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _left_bumper_badge: PanelContainer = null
var _right_bumper_badge: PanelContainer = null
var _footer: Label = null
var _controller_nav: Node = null
var _proximity: Node = null

var _material_counts: Dictionary = {}
var _material_bars: Dictionary = {}
var _path_meta: Label = null
var _path_scroll: ScrollContainer = null
var _path_canvas: ResearchPathCanvas = null
var _water_node_button: Button = null
var _zoom_label: Label = null
var _detail_scroll: ScrollContainer = null
var _detail_content: VBoxContainer = null
var _requirement_stored: Dictionary = {}
var _research_time_value: Label = null
var _research_progress_bar: ProgressBar = null
var _research_progress_label: Label = null
var _action_button: Button = null


func _ready() -> void:
	layer = 60
	visible = false
	_build_interface()
	_controller_nav = NAV.new()
	_controller_nav.ui_root = self
	_controller_nav.stick_navigation = false
	_controller_nav.right_stick_navigation = true
	add_child(_controller_nav)
	_proximity = PROXIMITY.new()
	_proximity.ui = self
	add_child(_proximity)
	get_viewport().size_changed.connect(_layout)
	set_process(false)
	_layout()


func open(station: Node) -> void:
	var resolved_station: ResearchStation = station as ResearchStation
	if resolved_station == null:
		return
	if not is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	_current_station = resolved_station
	is_open = true
	visible = true
	_refresh_elapsed = REFRESH_INTERVAL
	_state_signature = ""
	_zoom_index = 1
	_proximity.bind_target(resolved_station)
	_set_tab(BUNKER_TAB)
	_rebuild_pathway()
	_rebuild_detail()
	_refresh_live_data()
	_state_signature = _research_state_signature()
	_reset_scrolls(_view)
	_update_input_hint()
	_layout()
	set_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FADE.fade_in(_panel)
	if _water_node_button != null:
		_water_node_button.call_deferred("grab_focus")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_current_station = null
	_proximity.unbind()
	visible = false
	set_process(false)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _view.is_ancestor_of(focused):
		focused.release_focus()
		if _previous_focus != null:
			var previous: Control = _previous_focus.get_ref() as Control
			if is_instance_valid(previous) and previous.is_visible_in_tree():
				previous.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _process(delta: float) -> void:
	if not is_open:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		var signature: String = _research_state_signature()
		if signature != _state_signature:
			_state_signature = signature
			_rebuild_pathway()
			_rebuild_detail()
			if (
				InputMode.is_controller()
				and _active_tab == BUNKER_TAB
				and _water_node_button != null
			):
				_water_node_button.call_deferred("grab_focus")
		_refresh_live_data()
	if _controller_hints != InputMode.is_controller():
		_update_input_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not _controller_nav._is_topmost():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if button_event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_tab(-1)
			get_viewport().set_input_as_handled()
		elif button_event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_tab(1)
			get_viewport().set_input_as_handled()


func _build_interface() -> void:
	_view = Control.new()
	_view.name = "ResearchStationWorkspace"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	C.apply_theme(_view)
	var backdrop: ColorRect = UIKit.build_modal_backdrop(0.44)
	backdrop.gui_input.connect(_on_backdrop_input)
	_view.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "ResearchStationPanel"
	C.shell(_panel, 10)
	_view.add_child(_panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	_panel.add_child(C.inset(content, 20, 16, 20, 12))
	_build_header(content)
	C.divider(content)
	_build_tabs(content)
	_build_material_reserves(content)
	_build_pages(content)
	C.divider(content)
	_footer = _label("", 12, S.MUTED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.custom_minimum_size.y = 22.0
	content.add_child(_footer)


func _build_header(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	row.add_child(C.icon_well("general", 54.0, S.BLUE))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(titles)
	titles.add_child(_label("RESEARCH & DEVELOPMENT", 12, S.BLUE))
	var title: Label = _label("Research Station", 29, S.IVORY)
	titles.add_child(title)

	_header_status = PanelContainer.new()
	_header_status.custom_minimum_size = Vector2(176.0, 42.0)
	row.add_child(_header_status)
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	_header_status.add_child(C.inset(status_row, 12, 8, 12, 8))
	_header_status_icon = _icon("check", 18.0, S.GREEN)
	status_row.add_child(_header_status_icon)
	_header_status_text = _label("STATION READY", 13, S.GREEN)
	status_row.add_child(_header_status_text)

	_close_button = Button.new()
	_close_button.custom_minimum_size = Vector2(48.0, 48.0)
	_close_button.tooltip_text = "Close research station"
	S.icon_button(_close_button, "close")
	_close_button.text = ""
	_close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_button.pressed.connect(close)
	row.add_child(_close_button)


func _build_tabs(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	_left_bumper_badge = _input_badge("LB")
	row.add_child(_left_bumper_badge)
	var labels: Array[String] = ["Bunker Upgrades", "Player Skills", "NPC Skills"]
	var icons: Array[String] = ["build", "general", "storage"]
	for index: int in range(labels.size()):
		var button: Button = Button.new()
		button.text = labels[index]
		button.icon = S.icon(icons[index])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		C.style_segment(button)
		button.pressed.connect(_set_tab.bind(index))
		row.add_child(button)
		_tabs.append(button)
	_right_bumper_badge = _input_badge("RB")
	row.add_child(_right_bumper_badge)


func _build_material_reserves(parent: Container) -> void:
	var reserve_panel: PanelContainer = _card(Color("151b1a"))
	reserve_panel.custom_minimum_size.y = 90.0
	parent.add_child(reserve_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	reserve_panel.add_child(C.inset(box, 12, 9, 12, 9))
	C.section_header(box, "MATERIAL RESERVES", "10 UNIT CAPACITY")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for material: String in ResearchStation.MATERIAL_TYPES:
		row.add_child(_build_material_card(material))

	var helper: HBoxContainer = HBoxContainer.new()
	helper.custom_minimum_size.x = 230.0
	helper.add_theme_constant_override("separation", 9)
	row.add_child(helper)
	var divider: VSeparator = VSeparator.new()
	helper.add_child(divider)
	helper.add_child(_icon("load", 28.0, S.MUTED.darkened(0.12)))
	var helper_text: Label = _label("Feed salvage through\nthe station chute", 12, S.MUTED)
	helper_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	helper.add_child(helper_text)


func _build_material_card(material: String) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(C.inset(row, 9, 7, 9, 7))
	var symbols: Dictionary = {
		"metal": "storage",
		"plastic": "container",
		"paper": "log",
		"organic": "plant",
	}
	var colors: Dictionary = {
		"metal": S.MUTED,
		"plastic": S.BLUE,
		"paper": S.IVORY,
		"organic": S.GREEN,
	}
	var icon_color: Color = colors.get(material, S.MUTED)
	row.add_child(_icon(String(symbols.get(material, "storage")), 25.0, icon_color))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	var title_row: HBoxContainer = HBoxContainer.new()
	copy.add_child(title_row)
	var name_label: Label = _label(material.to_upper(), 11, S.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)
	var count: Label = _label("0 / 10", 12, S.IVORY)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(count)
	var bar: ProgressBar = _progress(S.BLUE, 6.0)
	bar.max_value = float(ResearchStation.STORAGE_CAP)
	copy.add_child(bar)
	_material_counts[material] = count
	_material_bars[material] = bar
	return card


func _build_pages(parent: Container) -> void:
	var stack: Control = Control.new()
	stack.name = "ResearchPages"
	stack.custom_minimum_size.y = 430.0
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(stack)

	var bunker_page: HBoxContainer = HBoxContainer.new()
	bunker_page.name = "BunkerUpgradesPage"
	bunker_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bunker_page.add_theme_constant_override("separation", 10)
	stack.add_child(bunker_page)
	_pages.append(bunker_page)
	_build_pathway_panel(bunker_page)
	_build_detail_panel(bunker_page)

	var player_page: Control = _build_empty_page(
		"PLAYER SKILLS",
		"Personal research has not been defined yet.",
		"This workspace is ready for future player progression without changing the station shell."
	)
	stack.add_child(player_page)
	_pages.append(player_page)

	var npc_page: Control = _build_empty_page(
		"NPC SKILLS",
		"Crew research has not been defined yet.",
		"Future survivor training will live here as a separate progression tree."
	)
	stack.add_child(npc_page)
	_pages.append(npc_page)


func _build_pathway_panel(parent: HBoxContainer) -> void:
	var card: PanelContainer = _card(Color("131918"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.75
	parent.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(C.inset(box, 10, 9, 10, 8))
	var header: Dictionary = C.section_header(box, "RESEARCH PATHWAYS", "0 / 3 TIERS COMPLETE")
	_path_meta = header.get("meta") as Label

	_path_scroll = ScrollContainer.new()
	_path_scroll.name = "ResearchPathScroll"
	_path_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_path_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_path_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_path_scroll.follow_focus = true
	_path_scroll.add_theme_stylebox_override(
		"panel", C.panel_box(Color("101615"), S.BRASS.darkened(0.50), 7, 1)
	)
	box.add_child(_path_scroll)
	_path_canvas = PATH_CANVAS.new() as ResearchPathCanvas
	_path_canvas.custom_minimum_size = TREE_BASE_SIZE
	_path_scroll.add_child(_path_canvas)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	box.add_child(controls)
	var minus: Button = _compact_icon_button("minus", "Zoom out")
	minus.pressed.connect(_change_zoom.bind(-1))
	controls.add_child(minus)
	_zoom_label = _label("100%", 11, S.MUTED)
	_zoom_label.custom_minimum_size.x = 44.0
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(_zoom_label)
	var plus: Button = _compact_icon_button("plus", "Zoom in")
	plus.pressed.connect(_change_zoom.bind(1))
	controls.add_child(plus)
	var reset: Button = _compact_icon_button("search", "Reset view")
	reset.pressed.connect(_reset_path_view)
	controls.add_child(reset)
	var grow: Control = Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(grow)
	controls.add_child(
		_label("Select a node to inspect its requirements", 11, S.MUTED.darkened(0.10))
	)


func _build_detail_panel(parent: HBoxContainer) -> void:
	var card: PanelContainer = _card(Color("151b1a"))
	card.custom_minimum_size.x = 395.0
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	parent.add_child(card)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "ResearchDetailScroll"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_detail_scroll.follow_focus = true
	card.add_child(C.inset(_detail_scroll, 14, 12, 10, 10))
	_detail_content = VBoxContainer.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_constant_override("separation", 8)
	_detail_scroll.add_child(_detail_content)


func _build_empty_page(eyebrow: String, title_text: String, detail_text: String) -> Control:
	var page: Control = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var card: PanelContainer = _card(Color("151b1a"))
	card.custom_minimum_size = Vector2(610.0, 230.0)
	center.add_child(card)
	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 11)
	card.add_child(C.inset(content, 36, 28, 36, 28))
	var icon_well: PanelContainer = C.icon_well("general", 58.0, S.BLUE)
	icon_well.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(icon_well)
	var eyebrow_label: Label = _label(eyebrow, 12, S.BLUE)
	eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(eyebrow_label)
	var title_label: Label = _label(title_text, 22, S.IVORY)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_label)
	var detail: Label = _label(detail_text, 13, S.MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 480.0
	content.add_child(detail)
	return page


func _rebuild_pathway() -> void:
	if _path_canvas == null:
		return
	_clear(_path_canvas)
	var zoom: float = ZOOM_STEPS[_zoom_index]
	_path_canvas.custom_minimum_size = TREE_BASE_SIZE * zoom
	_zoom_label.text = "%d%%" % roundi(zoom * 100.0)
	var completed: int = _completed_tiers()
	var maximum: int = WATER_UPGRADE.get_max_tier()
	_path_meta.text = "%d / %d TIERS COMPLETE" % [completed, maximum]

	var base_rect: Rect2 = _scaled_rect(Rect2(285.0, 15.0, 210.0, 62.0), zoom)
	var water_rect: Rect2 = _scaled_rect(Rect2(255.0, 103.0, 270.0, 86.0), zoom)
	var purifier_rect: Rect2 = _scaled_rect(Rect2(55.0, 245.0, 225.0, 72.0), zoom)
	var reservoir_rect: Rect2 = _scaled_rect(Rect2(500.0, 245.0, 225.0, 72.0), zoom)
	var future_rect: Rect2 = _scaled_rect(Rect2(280.0, 335.0, 220.0, 62.0), zoom)

	_path_canvas.add_child(
		_static_path_node(base_rect, "Basic Water Supply", "COMPLETE", "water", "complete")
	)
	_water_node_button = _research_path_button(water_rect)
	_path_canvas.add_child(_water_node_button)
	_path_canvas.add_child(
		_static_path_node(
			purifier_rect, "Purifier Throughput", "REQUIRES PRIOR RESEARCH", "water", "locked"
		)
	)
	_path_canvas.add_child(
		_static_path_node(
			reservoir_rect, "Reservoir Capacity", "REQUIRES PRIOR RESEARCH", "storage", "locked"
		)
	)
	_path_canvas.add_child(
		_static_path_node(
			future_rect, "Future Research", "REQUIRES PRIOR RESEARCH", "general", "locked"
		)
	)

	var base_bottom: Vector2 = Vector2(base_rect.get_center().x, base_rect.end.y)
	var water_top: Vector2 = Vector2(water_rect.get_center().x, water_rect.position.y)
	var water_bottom: Vector2 = Vector2(water_rect.get_center().x, water_rect.end.y)
	var branch_y: float = (water_rect.end.y + purifier_rect.position.y) * 0.5
	var purifier_top: Vector2 = Vector2(purifier_rect.get_center().x, purifier_rect.position.y)
	var reservoir_top: Vector2 = Vector2(reservoir_rect.get_center().x, reservoir_rect.position.y)
	var future_top: Vector2 = Vector2(future_rect.get_center().x, future_rect.position.y)
	var connections: Array[Dictionary] = [
		{"points": PackedVector2Array([base_bottom, water_top]), "active": true},
		{
			"points":
			PackedVector2Array(
				[
					water_bottom,
					Vector2(water_bottom.x, branch_y),
					Vector2(purifier_top.x, branch_y),
					purifier_top
				]
			),
			"active": false
		},
		{
			"points":
			PackedVector2Array(
				[
					water_bottom,
					Vector2(water_bottom.x, branch_y),
					Vector2(reservoir_top.x, branch_y),
					reservoir_top
				]
			),
			"active": false
		},
		{"points": PackedVector2Array([water_bottom, future_top]), "active": false},
	]
	_path_canvas.set_connections(connections)


func _research_path_button(rect: Rect2) -> Button:
	var button: Button = Button.new()
	button.name = "WaterHookupOutputNode"
	button.position = rect.position
	button.size = rect.size
	button.custom_minimum_size = rect.size
	button.icon = S.icon("water")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", roundi(34.0 * ZOOM_STEPS[_zoom_index]))
	button.add_theme_font_size_override(
		"font_size", maxi(11, roundi(14.0 * ZOOM_STEPS[_zoom_index]))
	)
	button.tooltip_text = "Inspect Water Hookup Output"
	button.pressed.connect(_select_water_upgrade)
	_style_research_path_button(button)
	_update_water_node_text(button)
	return button


func _static_path_node(
	rect: Rect2, title_text: String, subtitle_text: String, symbol: String, state: String
) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge: Color = S.GREEN.darkened(0.18) if state == "complete" else S.BRASS.darkened(0.34)
	var background: Color = Color("17231d") if state == "complete" else Color("191e1e")
	panel.add_theme_stylebox_override("panel", C.panel_box(background, edge, 7, 1, 8))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(C.inset(row, 10, 7, 10, 7))
	row.add_child(_icon(symbol, 27.0, S.GREEN if state == "complete" else S.MUTED.darkened(0.22)))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(_label(title_text, 13, S.IVORY if state == "complete" else S.MUTED))
	var subtitle_color: Color = S.GREEN if state == "complete" else S.MUTED.darkened(0.28)
	copy.add_child(_label(subtitle_text, 9, subtitle_color))
	return panel


func _style_research_path_button(button: Button) -> void:
	var state: String = _research_state()
	var background: Color = S.BLUE_DARK if state == "available" else Color("182220")
	var edge: Color = S.BLUE
	if state == "active":
		background = Color("172820")
		edge = S.GREEN
	elif state == "paused":
		background = Color("29241a")
		edge = S.BRASS.lightened(0.25)
	elif state == "complete":
		background = Color("172820")
		edge = S.GREEN
	elif state == "materials":
		background = Color("202321")
		edge = S.BRASS
	elif state == "busy":
		background = Color("202321")
		edge = S.MUTED.darkened(0.25)
	button.add_theme_color_override("font_color", S.IVORY)
	button.add_theme_color_override("font_hover_color", S.IVORY)
	button.add_theme_color_override("font_pressed_color", S.IVORY)
	button.add_theme_color_override("icon_normal_color", edge)
	button.add_theme_color_override("icon_hover_color", S.IVORY)
	button.add_theme_stylebox_override("normal", C.panel_box(background, edge, 8, 2, 10))
	button.add_theme_stylebox_override(
		"hover", C.panel_box(background.lightened(0.06), S.BLUE, 8, 2, 10)
	)
	button.add_theme_stylebox_override(
		"pressed", C.panel_box(background.darkened(0.06), S.IVORY, 8, 2, 10)
	)
	button.add_theme_stylebox_override("focus", C.panel_box(Color.TRANSPARENT, S.IVORY, 9, 2))


func _update_water_node_text(button: Button) -> void:
	var completed: int = _completed_tiers()
	var maximum: int = WATER_UPGRADE.get_max_tier()
	var state_text: String = _research_state().replace("_", " ").to_upper()
	if state_text == "MATERIALS":
		state_text = "MATERIALS REQUIRED"
	button.text = "Water Hookup Output\nTier %d / %d     %s" % [completed, maximum, state_text]


func _select_water_upgrade() -> void:
	_rebuild_detail()
	if _detail_scroll != null:
		_detail_scroll.set_deferred("scroll_vertical", 0)


func _rebuild_detail() -> void:
	if _detail_content == null:
		return
	_clear(_detail_content)
	_requirement_stored.clear()
	_research_time_value = null
	_research_progress_bar = null
	_research_progress_label = null
	_action_button = null
	var completed: int = _completed_tiers()
	var maximum: int = WATER_UPGRADE.get_max_tier()
	_detail_content.add_child(_label("WATER SYSTEMS", 12, S.BLUE))
	_detail_content.add_child(_label("Water Hookup Output", 24, S.IVORY))
	_detail_content.add_child(_label("Tier %d of %d" % [completed, maximum], 14, S.MUTED))
	var description: Label = _label(
		"Double the daily water supplied by the bunker hookup.", 13, S.MUTED
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_content.add_child(description)
	_detail_content.add_child(_effect_comparison(completed, maximum))
	C.section_header(_detail_content, "REQUIREMENTS")
	for material: String in ResearchStation.MATERIAL_TYPES:
		if not WATER_UPGRADE.material_costs.has(material):
			continue
		_detail_content.add_child(
			_requirement_row(material, int(WATER_UPGRADE.material_costs.get(material, 0)))
		)
	C.section_header(_detail_content, "RESEARCH TIME")
	var time_row: HBoxContainer = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	time_row.add_child(_icon("clock", 20.0, S.MUTED))
	_research_time_value = _label(_format_duration(WATER_UPGRADE.duration_seconds), 14, S.IVORY)
	time_row.add_child(_research_time_value)
	_detail_content.add_child(time_row)

	if _current_station != null and _current_station.active_upgrade == WATER_UPGRADE:
		var progress_header: Dictionary = C.section_header(_detail_content, "ACTIVE RESEARCH", "0%")
		_research_progress_label = progress_header.get("meta") as Label
		_research_progress_bar = _progress(S.BLUE, 9.0)
		_detail_content.add_child(_research_progress_bar)

	_detail_content.add_child(_tier_segments(completed, maximum))
	_action_button = Button.new()
	_action_button.custom_minimum_size.y = 48.0
	_action_button.pressed.connect(_on_research_action)
	_detail_content.add_child(_action_button)
	_style_research_action()
	var helper: Label = _label("Materials are consumed as research progresses.", 11, S.MUTED)
	helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_content.add_child(helper)
	_refresh_live_data()


func _effect_comparison(completed: int, maximum: int) -> PanelContainer:
	var card: PanelContainer = _card(Color("171d1c"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(C.inset(row, 12, 10, 12, 10))
	var current: VBoxContainer = VBoxContainer.new()
	current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(current)
	current.add_child(_label("CURRENT", 10, S.BLUE))
	current.add_child(_label(_water_output_for_tier(completed), 13, S.IVORY))
	row.add_child(_icon("arrow", 26.0, S.BLUE))
	var next: VBoxContainer = VBoxContainer.new()
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(next)
	next.add_child(_label("NEXT TIER", 10, S.BLUE if completed < maximum else S.GREEN))
	next.add_child(
		_label(
			_water_output_for_tier(completed + 1) if completed < maximum else "Maximum output",
			13,
			S.IVORY
		)
	)
	return card


func _requirement_row(material: String, cost: int) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(C.inset(row, 10, 7, 10, 7))
	var symbols: Dictionary = {
		"metal": "storage",
		"plastic": "container",
		"paper": "log",
		"organic": "plant",
	}
	var symbol: String = String(symbols.get(material, "container"))
	row.add_child(_icon(symbol, 20.0, S.BLUE if material == "plastic" else S.MUTED))
	var name_label: Label = _label(material.capitalize(), 13, S.IVORY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var cost_label: Label = _label("%d required" % cost, 12, S.MUTED)
	row.add_child(cost_label)
	var stored_label: Label = _label("0 stored", 12, S.GREEN)
	stored_label.custom_minimum_size.x = 78.0
	stored_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(stored_label)
	_requirement_stored[material] = stored_label
	return card


func _tier_segments(completed: int, maximum: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	for index: int in range(maximum):
		var segment: PanelContainer = PanelContainer.new()
		segment.custom_minimum_size.y = 11.0
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var color: Color = S.GREEN if index < completed else S.SURFACE_ALT
		segment.add_theme_stylebox_override("panel", C.panel_box(color, color, 4, 0))
		row.add_child(segment)
	return row


func _style_research_action() -> void:
	if _action_button == null:
		return
	var state: String = _research_state()
	_action_button.disabled = false
	match state:
		"active":
			_action_button.text = "Pause Research"
			_action_button.icon = S.icon("stopped")
			S.button(_action_button)
			var amber: Color = S.BRASS.lightened(0.28)
			_action_button.add_theme_stylebox_override(
				"normal", C.panel_box(Color("2b251a"), amber, 7, 1, 9)
			)
		"paused":
			_action_button.text = "Resume Research"
			_action_button.icon = S.icon("running")
			S.button(_action_button, true)
		"complete":
			_action_button.text = "Research Complete"
			_action_button.icon = S.icon("check")
			S.button(_action_button)
			_action_button.disabled = true
		"materials":
			_action_button.text = "Materials Required"
			_action_button.icon = S.icon("warning")
			S.button(_action_button)
			_action_button.disabled = true
		"busy":
			_action_button.text = "Another Research Is Active"
			_action_button.icon = S.icon("warning")
			S.button(_action_button)
			_action_button.disabled = true
		_:
			_action_button.text = "Begin Research"
			_action_button.icon = S.icon("general")
			S.button(_action_button, true)
	_action_button.expand_icon = true
	_action_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_action_button.add_theme_constant_override("icon_max_width", 22)


func _on_research_action() -> void:
	if _current_station == null:
		return
	var state: String = _research_state()
	if state == "active":
		_current_station.pause_research()
	elif state == "paused":
		_current_station.resume_research()
	elif state == "available":
		if not _current_station.start_research(WATER_UPGRADE):
			NotificationManager.feedback(
				UIKit.Domain.NEUTRAL,
				NotificationManager.Severity.WARNING,
				"Unable to begin research"
			)
	_state_signature = ""
	_rebuild_pathway()
	_rebuild_detail()
	_refresh_live_data()
	_state_signature = _research_state_signature()
	if _action_button != null:
		_action_button.call_deferred("grab_focus")


func _refresh_live_data() -> void:
	_refresh_materials()
	_refresh_header_status()
	_refresh_research_progress()
	if _water_node_button != null:
		_update_water_node_text(_water_node_button)


func _refresh_materials() -> void:
	for material: String in ResearchStation.MATERIAL_TYPES:
		var stored: int = 0
		if _current_station != null:
			stored = int(_current_station.stored_materials.get(material, 0))
		var count: Label = _material_counts.get(material) as Label
		if count != null:
			count.text = "%d / %d" % [stored, ResearchStation.STORAGE_CAP]
		var bar: ProgressBar = _material_bars.get(material) as ProgressBar
		if bar != null:
			SMOOTH_BAR.apply(bar, float(stored))
		var requirement: Label = _requirement_stored.get(material) as Label
		if requirement != null:
			var needed: int = int(WATER_UPGRADE.material_costs.get(material, 0))
			requirement.text = "%d stored" % stored
			var requirement_color: Color = S.GREEN if stored >= needed else S.RED
			if _current_station != null and _current_station.active_upgrade == WATER_UPGRADE:
				requirement_color = S.BLUE
			requirement.add_theme_color_override("font_color", requirement_color)


func _refresh_header_status() -> void:
	var text_value: String = "STATION READY"
	var color: Color = S.GREEN
	var icon_name: String = "check"
	if _current_station != null and _current_station.active_upgrade != null:
		if _current_station.is_paused:
			text_value = "RESEARCH PAUSED"
			color = S.BRASS.lightened(0.28)
			icon_name = "stopped"
		else:
			text_value = "RESEARCH ACTIVE"
			color = S.BLUE
			icon_name = "running"
	if text_value == _header_status_key:
		return
	_header_status_key = text_value
	_header_status_text.text = text_value
	_header_status_text.add_theme_color_override("font_color", color)
	_header_status_icon.texture = S.icon(icon_name)
	_header_status_icon.self_modulate = color
	_header_status.add_theme_stylebox_override(
		"panel", C.panel_box(S.BG.lerp(color, 0.10), S.BG.lerp(color, 0.52), 7, 1, 7)
	)


func _refresh_research_progress() -> void:
	if _current_station == null or _current_station.active_upgrade != WATER_UPGRADE:
		return
	var duration: float = maxf(WATER_UPGRADE.duration_seconds, 0.001)
	var fraction: float = clampf(_current_station._elapsed / duration, 0.0, 1.0)
	var remaining: float = maxf(duration - _current_station._elapsed, 0.0)
	if _research_progress_bar != null:
		SMOOTH_BAR.apply(_research_progress_bar, fraction * 100.0)
	if _research_progress_label != null:
		_research_progress_label.text = "%d%%" % roundi(fraction * 100.0)
	if _research_time_value != null:
		_research_time_value.text = "%s remaining" % _format_duration(remaining)


func _research_state() -> String:
	if _current_station == null:
		return "materials"
	var completed: int = _completed_tiers()
	if completed >= WATER_UPGRADE.get_max_tier():
		return "complete"
	if _current_station.active_upgrade == WATER_UPGRADE:
		return "paused" if _current_station.is_paused else "active"
	if _current_station.active_upgrade != null:
		return "busy"
	return "available" if _can_afford() else "materials"


func _research_state_signature() -> String:
	if _current_station == null:
		return "none"
	var active_id: String = ""
	if _current_station.active_upgrade != null:
		active_id = _current_station.active_upgrade.id
	return "%s|%s|%d" % [active_id, str(_current_station.is_paused), _completed_tiers()]


func _completed_tiers() -> int:
	if _current_station == null:
		return 0
	return int(_current_station.tier_progress.get(WATER_UPGRADE.id, 0))


func _can_afford() -> bool:
	if _current_station == null:
		return false
	for material: String in WATER_UPGRADE.material_costs.keys():
		var stored: int = int(_current_station.stored_materials.get(material, 0))
		var needed: int = int(WATER_UPGRADE.material_costs.get(material, 0))
		if stored < needed:
			return false
	return true


func _water_output_for_tier(tier: int) -> String:
	var index: int = clampi(tier, 0, WaterHookup.TIER_DAILY_ML.size() - 1)
	return "%d mL / day" % roundi(WaterHookup.TIER_DAILY_ML[index])


func _set_tab(index: int) -> void:
	_active_tab = clampi(index, 0, _pages.size() - 1)
	for button_index: int in range(_tabs.size()):
		_tabs[button_index].set_pressed_no_signal(button_index == _active_tab)
	for page_index: int in range(_pages.size()):
		_pages[page_index].visible = page_index == _active_tab
	if InputMode.is_controller():
		var target: Control = (
			_water_node_button if _active_tab == BUNKER_TAB else _tabs[_active_tab]
		)
		if target != null:
			target.call_deferred("grab_focus")


func _cycle_tab(direction: int) -> void:
	_set_tab((_active_tab + direction + _pages.size()) % _pages.size())


func _change_zoom(direction: int) -> void:
	_zoom_index = clampi(_zoom_index + direction, 0, ZOOM_STEPS.size() - 1)
	_rebuild_pathway()
	if _water_node_button != null:
		_water_node_button.call_deferred("grab_focus")


func _reset_path_view() -> void:
	_zoom_index = 1
	_rebuild_pathway()
	_path_scroll.set_deferred("scroll_horizontal", 0)
	_path_scroll.set_deferred("scroll_vertical", 0)
	if _water_node_button != null:
		_water_node_button.call_deferred("grab_focus")


func _scaled_rect(rect: Rect2, zoom: float) -> Rect2:
	return Rect2(rect.position * zoom, rect.size * zoom)


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = Vector2(
		maxf(320.0, viewport_size.x - EDGE.x * 2.0), maxf(320.0, viewport_size.y - EDGE.y * 2.0)
	)
	_panel.size = Vector2(minf(PANEL_MAX.x, available.x), minf(PANEL_MAX.y, available.y))
	_panel.position = (viewport_size - _panel.size) * 0.5


func _update_input_hint() -> void:
	_controller_hints = InputMode.is_controller()
	_left_bumper_badge.visible = _controller_hints
	_right_bumper_badge.visible = _controller_hints
	var controller_text: String = (
		"[A] Select     [LB] / [RB] Tabs     D-pad / R-stick  Navigate"
		+ "     Scrollbar  Scroll     [B] Close"
	)
	var keyboard_text: String = (
		"Enter / Space  Select     Arrows  Navigate     Wheel / Scrollbar  Scroll"
		+ "     Esc / E  Close"
	)
	_footer.text = controller_text if _controller_hints else keyboard_text


func _reset_scrolls(root_node: Node) -> void:
	for node: Node in root_node.find_children("*", "ScrollContainer", true, false):
		var scroll: ScrollContainer = node as ScrollContainer
		if scroll != null:
			scroll.set_deferred("scroll_horizontal", 0)
			scroll.set_deferred("scroll_vertical", 0)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()


func _card(background: Color = Color("171d1c")) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", C.panel_box(background, S.BRASS.darkened(0.40), 7, 1))
	return card


func _label(text_value: String, size_value: int, color: Color) -> Label:
	var result: Label = Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", size_value)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _icon(symbol: String, side: float, color: Color) -> TextureRect:
	var texture: TextureRect = TextureRect.new()
	texture.texture = S.icon(symbol)
	texture.self_modulate = color
	texture.custom_minimum_size = Vector2(side, side)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture


func _progress(fill_color: Color, height: float) -> ProgressBar:
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(
		"background", C.panel_box(S.SURFACE_ALT, S.SURFACE_ALT, roundi(height * 0.5), 0)
	)
	bar.add_theme_stylebox_override(
		"fill", C.panel_box(fill_color, fill_color, roundi(height * 0.5), 0)
	)
	return bar


func _compact_icon_button(symbol: String, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.tooltip_text = tooltip
	S.icon_button(button, symbol)
	button.custom_minimum_size = Vector2(34.0, 30.0)
	button.text = ""
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 17)
	return button


func _input_badge(text_value: String) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.custom_minimum_size = Vector2(40.0, 40.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override(
		"panel", C.panel_box(S.SURFACE_ALT, S.BRASS.darkened(0.12), 6, 1, 5)
	)
	var label: Label = _label(text_value, 11, S.IVORY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(label)
	return badge


func _format_duration(seconds: float) -> String:
	var rounded_seconds: int = int(ceil(seconds))
	if rounded_seconds < 60:
		return "%d second%s" % [rounded_seconds, "" if rounded_seconds == 1 else "s"]
	var minutes: int = int(round(float(rounded_seconds) / 60.0))
	return "%d minute%s" % [minutes, "" if minutes == 1 else "s"]


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
