extends CanvasLayer
class_name StatusScreenUI
## Full player Status workspace. This remains non-modal: the world and left-stick
## movement continue while it is open. Medical simulation, inventory ownership,
## and item treatment behavior stay in their existing gameplay systems.

signal closed

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PREVIEW: GDScript = preload("res://scripts/ui/common/ItemPreviewKit.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")
const ITEM_CARD: GDScript = preload("res://scripts/ui/common/BunkerItemCard.gd")
const PRESENT: GDScript = preload("res://scripts/ui/common/ItemPresentation.gd")

const PANEL_MAX: Vector2 = Vector2(1420.0, 820.0)
const SCREEN_MARGIN: Vector2 = Vector2(42.0, 34.0)
const REFRESH_INTERVAL: float = 0.25
const INFECTION_COLOR: Color = Color("e4a24a")
const FOOD_COLOR: Color = Color("dbad64")
const WATER_COLOR: Color = Color("62bfff")
const STAMINA_COLOR: Color = Color("76d6b0")
const SLEEP_COLOR: Color = Color("a493df")

enum StatusTab { OVERVIEW, HEALTH, NEEDS, INVENTORY }

const BODY_PARTS: Array[int] = [
	MedicalCondition.BodyPart.HEAD,
	MedicalCondition.BodyPart.TORSO,
	MedicalCondition.BodyPart.LEFT_ARM,
	MedicalCondition.BodyPart.RIGHT_ARM,
	MedicalCondition.BodyPart.LEFT_LEG,
	MedicalCondition.BodyPart.RIGHT_LEG,
]
const BODY_RECTS: Dictionary = {
	MedicalCondition.BodyPart.HEAD: Rect2(106.0, 4.0, 58.0, 44.0),
	MedicalCondition.BodyPart.TORSO: Rect2(84.0, 55.0, 102.0, 90.0),
	MedicalCondition.BodyPart.LEFT_ARM: Rect2(25.0, 63.0, 49.0, 82.0),
	MedicalCondition.BodyPart.RIGHT_ARM: Rect2(196.0, 63.0, 49.0, 82.0),
	MedicalCondition.BodyPart.LEFT_LEG: Rect2(86.0, 152.0, 43.0, 94.0),
	MedicalCondition.BodyPart.RIGHT_LEG: Rect2(141.0, 152.0, 43.0, 94.0),
}

## Injected by MainWorld before this node enters the tree.
var player_medical: PlayerMedical = null
var player_stats: PlayerStats = null
var inventory: Node = null
var interaction_system: Node = null
var inventory_hud: Node = null

var _is_open: bool = false
var _refresh_elapsed: float = 0.0
var _active_tab: int = StatusTab.OVERVIEW
var _selected_part: int = MedicalCondition.BodyPart.HEAD
var _selected_condition_key: String = ""
var _selected_inventory_slot: int = 0
var _previous_focus: WeakRef = null

var _root: Control = null
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _controller_nav: ControllerUINavigation = null
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _scrolls: Array[ScrollContainer] = []

var _header_status_label: Label = null
var _header_status_panel: PanelContainer = null
var _summary_metrics: Dictionary = {}

var _overview_condition_count: Label = null
var _overview_condition_copy: Label = null
var _overview_needs_count: Label = null
var _overview_needs_copy: Label = null
var _overview_inventory_count: Label = null
var _overview_inventory_copy: Label = null

var _body_buttons: Dictionary = {}
var _body_badges: Dictionary = {}
var _part_title: Label = null
var _condition_count_label: Label = null
var _condition_list: VBoxContainer = null
var _condition_cards: Dictionary = {}
var _condition_signature: String = ""

var _detail_empty: VBoxContainer = null
var _detail_content: VBoxContainer = null
var _detail_title: Label = null
var _detail_location: Label = null
var _detail_location_panel: PanelContainer = null
var _detail_warning: PanelContainer = null
var _detail_warning_label: Label = null
var _detail_severity_value: Label = null
var _detail_severity_bar: ProgressBar = null
var _detail_recovery_value: Label = null
var _detail_recovery_bar: ProgressBar = null
var _detail_effects: Label = null
var _treatment_icon: TextureRect = null
var _treatment_title: Label = null
var _treatment_copy: Label = null
var _treatment_stock: Label = null
var _treatment_stock_panel: PanelContainer = null
var _treatment_button: Button = null
var _supply_labels: Dictionary = {}

var _needs_rows: Dictionary = {}
var _needs_reason_panel: PanelContainer = null
var _needs_reason_label: Label = null

var _inventory_cards: Array[Button] = []
var _inventory_viewports: Array[SubViewport] = []
var _inventory_signatures: Array[String] = ["", "", "", ""]
var _inventory_detail_title: Label = null
var _inventory_detail_copy: Label = null
var _inventory_detail_state: Label = null

var _footer_hint: Label = null


func _ready() -> void:
	layer = 150
	visible = false
	set_process(false)
	_build_interface()
	_controller_nav = NAV_SCRIPT.new() as ControllerUINavigation
	_controller_nav.ui_root = self
	_controller_nav.stick_navigation = false
	_controller_nav.right_stick_navigation = true
	add_child(_controller_nav)
	get_viewport().size_changed.connect(_layout)
	_layout()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus_owner) if focus_owner != null else null
	_is_open = true
	visible = true
	set_process(true)
	_refresh_elapsed = REFRESH_INTERVAL
	_select_initial_medical_target()
	_set_tab(StatusTab.OVERVIEW)
	_refresh_all()
	_reset_scrolls()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UIFade.fade_in(_panel)
	if not _tab_buttons.is_empty():
		_tab_buttons[StatusTab.OVERVIEW].grab_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _previous_focus != null:
		var previous: Variant = _previous_focus.get_ref()
		if previous is Control and is_instance_valid(previous as Control):
			(previous as Control).grab_focus()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var keyboard_close: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE)
	var view_close: bool = event is InputEventJoypadButton and event.pressed \
		and event.button_index == JOY_BUTTON_BACK
	if keyboard_close or view_close:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_set_tab(wrapi(_active_tab - 1, 0, _tab_buttons.size()))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_set_tab(wrapi(_active_tab + 1, 0, _tab_buttons.size()))
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not (event is InputEventJoypadButton) or not event.pressed:
		return
	if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		_set_tab(wrapi(_active_tab - 1, 0, _tab_buttons.size()))
		get_viewport().set_input_as_handled()
	elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		_set_tab(wrapi(_active_tab + 1, 0, _tab_buttons.size()))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_refresh_all()
	_refresh_footer()


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "StatusWorkspaceRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	C.apply_theme(_root)
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "StatusWorkspace"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	C.shell(_panel, 12)
	_root.add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_panel.add_child(C.inset(_content, 20, 17, 20, 14))
	_build_header()
	C.divider(_content)
	_build_tabs()
	_build_summary_strip()
	_build_pages()
	C.divider(_content)
	_build_footer()
	_set_tab(StatusTab.OVERVIEW)


func _build_header() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	row.add_child(C.icon_well("status", 50.0, S.BLUE))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	row.add_child(titles)
	var eyebrow: Label = _label("PLAYER  •  CURRENT STATUS", 12, S.BLUE)
	titles.add_child(eyebrow)
	var title: Label = _label("Status", 26, S.IVORY)
	titles.add_child(title)

	_header_status_panel = PanelContainer.new()
	_header_status_panel.custom_minimum_size = Vector2(150.0, 38.0)
	row.add_child(_header_status_panel)
	_header_status_label = _label("STABLE", 12, S.GREEN)
	_header_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_status_panel.add_child(_header_status_label)

	var close_button: Button = Button.new()
	close_button.custom_minimum_size = Vector2(44.0, 44.0)
	close_button.tooltip_text = "Close status"
	S.icon_button(close_button, "close")
	close_button.text = ""
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _build_tabs() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "StatusTabs"
	row.add_theme_constant_override("separation", 7)
	_content.add_child(row)
	_make_tab(row, StatusTab.OVERVIEW, "OVERVIEW", "overview")
	_make_tab(row, StatusTab.HEALTH, "HEALTH", "health")
	_make_tab(row, StatusTab.NEEDS, "NEEDS", "general")
	_make_tab(row, StatusTab.INVENTORY, "INVENTORY", "storage")


func _make_tab(parent: HBoxContainer, tab_id: int, title: String, symbol: String) -> void:
	var button: Button = Button.new()
	button.name = title.capitalize() + "Tab"
	button.text = title
	button.icon = S.icon(symbol)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	C.style_segment(button)
	button.pressed.connect(_set_tab.bind(tab_id))
	parent.add_child(button)
	_tab_buttons.append(button)


func _build_summary_strip() -> void:
	var strip: PanelContainer = PanelContainer.new()
	strip.name = "VitalsSummary"
	strip.add_theme_stylebox_override("panel", C.panel_box(
		Color("161c1c"), S.BRASS.darkened(0.38), 8, 1, 8))
	_content.add_child(strip)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	_summary_metrics["health"] = _summary_metric(row, "health", "HEALTH", S.RED)
	_summary_metrics["food"] = _summary_metric(row, "food", "FOOD", FOOD_COLOR)
	_summary_metrics["water"] = _summary_metric(row, "water", "WATER", WATER_COLOR)
	_summary_metrics["stamina"] = _summary_metric(row, "stamina", "STAMINA", STAMINA_COLOR)
	_summary_metrics["sleep"] = _summary_metric(row, "sleep", "SLEEP", SLEEP_COLOR)


func _summary_metric(parent: HBoxContainer, symbol: String, title: String, color: Color) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", C.panel_box(
		Color("202625"), S.BRASS.darkened(0.48), 7, 1, 8))
	parent.add_child(card)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var icon: TextureRect = _icon(symbol, 24.0, color)
	row.add_child(icon)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 2)
	row.add_child(stack)
	var top: HBoxContainer = HBoxContainer.new()
	stack.add_child(top)
	var title_label: Label = _label(title, 10, S.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	var value_label: Label = _label("100", 13, S.IVORY)
	top.add_child(value_label)
	var bar: ProgressBar = _progress(color, 6.0)
	stack.add_child(bar)
	var cap_label: Label = _label("", 9, INFECTION_COLOR)
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(cap_label)
	return {"value": value_label, "bar": bar, "cap": cap_label, "color": color}


func _build_pages() -> void:
	var host: Control = Control.new()
	host.name = "StatusPages"
	host.custom_minimum_size.y = 488.0
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	_content.add_child(host)
	var overview: Control = _build_overview_page()
	var health: Control = _build_health_page()
	var needs: Control = _build_needs_page()
	var inventory_page: Control = _build_inventory_page()
	for page: Control in [overview, health, needs, inventory_page]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(page)
		_pages.append(page)


func _build_overview_page() -> Control:
	var page: MarginContainer = MarginContainer.new()
	page.name = "OverviewPage"
	page.add_theme_constant_override("margin_top", 8)
	page.add_theme_constant_override("margin_bottom", 4)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	page.add_child(stack)
	var intro: HBoxContainer = HBoxContainer.new()
	intro.add_theme_constant_override("separation", 12)
	stack.add_child(intro)
	var intro_copy: VBoxContainer = VBoxContainer.new()
	intro_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_child(intro_copy)
	intro_copy.add_child(_label("AT A GLANCE", 12, S.BLUE))
	intro_copy.add_child(_label("Your bunker-day readiness", 23, S.IVORY))
	var hint: Label = _label("Open any section for detail and actions.", 13, S.MUTED)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	intro.add_child(hint)

	var cards: HBoxContainer = HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 12)
	stack.add_child(cards)
	var health_refs: Dictionary = _overview_card(cards, "health", "HEALTH", "Body condition and treatment", StatusTab.HEALTH, S.RED)
	_overview_condition_count = health_refs["value"] as Label
	_overview_condition_copy = health_refs["copy"] as Label
	var needs_refs: Dictionary = _overview_card(cards, "general", "NEEDS", "Daily readiness and reduced caps", StatusTab.NEEDS, WATER_COLOR)
	_overview_needs_count = needs_refs["value"] as Label
	_overview_needs_copy = needs_refs["copy"] as Label
	var inventory_refs: Dictionary = _overview_card(cards, "storage", "INVENTORY", "Carried supplies and equipment", StatusTab.INVENTORY, S.BLUE)
	_overview_inventory_count = inventory_refs["value"] as Label
	_overview_inventory_copy = inventory_refs["copy"] as Label

	var advice: PanelContainer = PanelContainer.new()
	advice.add_theme_stylebox_override("panel", C.panel_box(
		Color("192423"), S.BLUE.darkened(0.35), 8, 1, 12))
	stack.add_child(advice)
	var advice_row: HBoxContainer = HBoxContainer.new()
	advice_row.add_theme_constant_override("separation", 10)
	advice.add_child(advice_row)
	advice_row.add_child(_icon("status", 26.0, S.BLUE))
	var advice_copy: VBoxContainer = VBoxContainer.new()
	advice_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advice_row.add_child(advice_copy)
	advice_copy.add_child(_label("STATUS WORKSPACE", 10, S.BLUE))
	var note: Label = _label("Inspect injuries, apply carried treatment supplies, review needs, or identify what is occupying each quick slot.", 13, S.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice_copy.add_child(note)
	return page


func _overview_card(parent: HBoxContainer, symbol: String, title: String,
		subtitle: String, tab_id: int, accent: Color) -> Dictionary:
	var button: Button = Button.new()
	button.text = ""
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 310.0
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", C.panel_box(Color("1b2221"), S.BRASS.darkened(0.32), 9, 1, 14))
	button.add_theme_stylebox_override("hover", C.panel_box(Color("202b2b"), accent.darkened(0.22), 9, 1, 14))
	button.add_theme_stylebox_override("pressed", C.panel_box(Color("1d3034"), accent, 9, 2, 13))
	button.add_theme_stylebox_override("focus", C.panel_box(Color.TRANSPARENT, S.IVORY, 10, 2))
	button.pressed.connect(_set_tab.bind(tab_id))
	parent.add_child(button)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 11)
	var button_margin: MarginContainer = C.inset(stack, 18, 18, 18, 16)
	button_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(button_margin)
	stack.add_child(C.icon_well(symbol, 54.0, accent))
	stack.add_child(_label(title, 13, accent))
	var value: Label = _label("—", 32, S.IVORY)
	stack.add_child(value)
	var copy: Label = _label(subtitle, 14, S.MUTED)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(copy)
	var open_row: HBoxContainer = HBoxContainer.new()
	open_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(open_row)
	var open_label: Label = _label("OPEN SECTION", 11, S.BLUE)
	open_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(open_label)
	open_row.add_child(_icon("arrow", 20.0, S.BLUE))
	return {"value": value, "copy": copy}


func _build_health_page() -> Control:
	var page: HBoxContainer = HBoxContainer.new()
	page.name = "HealthPage"
	page.add_theme_constant_override("separation", 10)
	var body_panel: PanelContainer = _section_panel()
	body_panel.custom_minimum_size.x = 310.0
	page.add_child(body_panel)
	var body_stack: VBoxContainer = VBoxContainer.new()
	body_stack.add_theme_constant_override("separation", 8)
	body_panel.add_child(C.inset(body_stack, 12, 12, 12, 12))
	var body_header: Dictionary = C.section_header(body_stack, "BODY STATUS", "SELECT A REGION")
	(body_header["title"] as Label).add_theme_color_override("font_color", S.BLUE)
	var diagram: Control = Control.new()
	diagram.name = "BodyMap"
	diagram.custom_minimum_size = Vector2(270.0, 252.0)
	diagram.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body_stack.add_child(diagram)
	for part: int in BODY_PARTS:
		_make_body_button(diagram, part)
	var body_list: GridContainer = GridContainer.new()
	body_list.columns = 2
	body_list.add_theme_constant_override("h_separation", 5)
	body_list.add_theme_constant_override("v_separation", 4)
	body_stack.add_child(body_list)
	for part: int in BODY_PARTS:
		var select: Button = Button.new()
		select.text = MedicalCondition.body_part_label(part)
		select.icon = S.icon("medical")
		select.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		C.style_segment(select, true)
		select.custom_minimum_size = Vector2(126.0, 28.0)
		select.pressed.connect(_select_body_part.bind(part))
		body_list.add_child(select)
		_body_badges[part] = select

	var condition_panel: PanelContainer = _section_panel()
	condition_panel.custom_minimum_size.x = 390.0
	page.add_child(condition_panel)
	var condition_stack: VBoxContainer = VBoxContainer.new()
	condition_stack.add_theme_constant_override("separation", 9)
	condition_panel.add_child(C.inset(condition_stack, 12, 12, 12, 12))
	var condition_header: HBoxContainer = HBoxContainer.new()
	condition_stack.add_child(condition_header)
	var condition_titles: VBoxContainer = VBoxContainer.new()
	condition_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition_header.add_child(condition_titles)
	condition_titles.add_child(_label("SELECTED REGION", 10, S.BLUE))
	_part_title = _label("Head", 21, S.IVORY)
	condition_titles.add_child(_part_title)
	_condition_count_label = _label("0 CONDITIONS", 11, S.MUTED)
	_condition_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	condition_header.add_child(_condition_count_label)
	C.divider(condition_stack)
	var condition_scroll: ScrollContainer = ScrollContainer.new()
	condition_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	condition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	condition_stack.add_child(condition_scroll)
	_scrolls.append(condition_scroll)
	_condition_list = VBoxContainer.new()
	_condition_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_list.add_theme_constant_override("separation", 8)
	condition_scroll.add_child(_condition_list)

	var detail_panel: PanelContainer = _section_panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(detail_panel)
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(detail_scroll)
	_scrolls.append(detail_scroll)
	var detail_host: VBoxContainer = VBoxContainer.new()
	detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(C.inset(detail_host, 14, 12, 14, 12))
	_build_health_detail(detail_host)
	return page


func _make_body_button(parent: Control, part: int) -> void:
	var rect: Rect2 = BODY_RECTS[part]
	var button: Button = Button.new()
	button.name = MedicalCondition.body_part_label(part).replace(" ", "")
	button.position = rect.position
	button.size = rect.size
	button.tooltip_text = MedicalCondition.body_part_label(part)
	button.focus_mode = Control.FOCUS_ALL
	button.toggle_mode = true
	button.add_theme_stylebox_override("normal", C.panel_box(Color("222827"), S.BRASS.darkened(0.3), 7, 1))
	button.add_theme_stylebox_override("hover", C.panel_box(Color("263236"), S.BLUE.darkened(0.15), 7, 1))
	button.add_theme_stylebox_override("pressed", C.panel_box(Color("294b62"), S.BLUE, 7, 2))
	button.add_theme_stylebox_override("focus", C.panel_box(Color.TRANSPARENT, S.IVORY, 8, 2))
	button.pressed.connect(_select_body_part.bind(part))
	parent.add_child(button)
	_body_buttons[part] = button


func _build_health_detail(parent: VBoxContainer) -> void:
	_detail_empty = VBoxContainer.new()
	_detail_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_detail_empty)
	_detail_empty.add_child(C.icon_well("medical", 62.0, S.MUTED.darkened(0.1)))
	var empty_title: Label = _label("No active condition", 21, S.IVORY)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_empty.add_child(empty_title)
	var empty_copy: Label = _label("This region currently requires no treatment.", 13, S.MUTED)
	empty_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty.add_child(empty_copy)

	_detail_content = VBoxContainer.new()
	_detail_content.add_theme_constant_override("separation", 10)
	parent.add_child(_detail_content)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	_detail_content.add_child(heading)
	var title_stack: VBoxContainer = VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_stack)
	title_stack.add_child(_label("CONDITION", 10, S.BLUE))
	_detail_title = _label("Open wound", 23, S.IVORY)
	title_stack.add_child(_detail_title)
	var location_refs: Dictionary = _pill(heading, "HEAD", S.BLUE, 82.0)
	_detail_location_panel = location_refs["panel"] as PanelContainer
	_detail_location = location_refs["label"] as Label

	_detail_warning = PanelContainer.new()
	_detail_content.add_child(_detail_warning)
	_detail_warning_label = _label("INFECTION ACTIVE", 11, INFECTION_COLOR)
	_detail_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_warning.add_child(C.inset(_detail_warning_label, 8, 6, 8, 6))

	var metrics: HBoxContainer = HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 8)
	_detail_content.add_child(metrics)
	var severity: Dictionary = _detail_metric(metrics, "SEVERITY", S.RED)
	_detail_severity_value = severity["value"] as Label
	_detail_severity_bar = severity["bar"] as ProgressBar
	var recovery: Dictionary = _detail_metric(metrics, "RECOVERY", S.GREEN)
	_detail_recovery_value = recovery["value"] as Label
	_detail_recovery_bar = recovery["bar"] as ProgressBar

	var effects_panel: PanelContainer = PanelContainer.new()
	effects_panel.add_theme_stylebox_override("panel", C.panel_box(Color("1b2221"), S.BRASS.darkened(0.4), 7, 1, 10))
	_detail_content.add_child(effects_panel)
	var effects_stack: VBoxContainer = VBoxContainer.new()
	effects_stack.add_theme_constant_override("separation", 5)
	effects_panel.add_child(effects_stack)
	effects_stack.add_child(_label("CURRENT EFFECTS", 10, S.BLUE))
	_detail_effects = _label("", 13, S.MUTED)
	_detail_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effects_stack.add_child(_detail_effects)

	var treatment_panel: PanelContainer = PanelContainer.new()
	treatment_panel.add_theme_stylebox_override("panel", C.panel_box(Color("192423"), S.BLUE.darkened(0.38), 8, 1, 12))
	_detail_content.add_child(treatment_panel)
	var treatment_stack: VBoxContainer = VBoxContainer.new()
	treatment_stack.add_theme_constant_override("separation", 8)
	treatment_panel.add_child(treatment_stack)
	var treatment_heading: HBoxContainer = HBoxContainer.new()
	treatment_heading.add_theme_constant_override("separation", 9)
	treatment_stack.add_child(treatment_heading)
	_treatment_icon = _icon("bandage", 31.0, S.BLUE)
	treatment_heading.add_child(_treatment_icon)
	var treatment_titles: VBoxContainer = VBoxContainer.new()
	treatment_titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	treatment_heading.add_child(treatment_titles)
	treatment_titles.add_child(_label("RECOMMENDED TREATMENT", 9, S.BLUE))
	_treatment_title = _label("Apply bandage", 17, S.IVORY)
	treatment_titles.add_child(_treatment_title)
	var stock_refs: Dictionary = _pill(treatment_heading, "0 CARRIED", S.MUTED, 92.0)
	_treatment_stock_panel = stock_refs["panel"] as PanelContainer
	_treatment_stock = stock_refs["label"] as Label
	_treatment_copy = _label("Stops active blood loss on this body region.", 12, S.MUTED)
	_treatment_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	treatment_stack.add_child(_treatment_copy)
	_treatment_button = Button.new()
	_treatment_button.text = "APPLY TREATMENT"
	_treatment_button.icon = S.icon("medical")
	_treatment_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	S.button(_treatment_button, true)
	_treatment_button.pressed.connect(_apply_selected_treatment)
	treatment_stack.add_child(_treatment_button)

	C.section_header(_detail_content, "CARRIED MEDICAL SUPPLIES", "QUICK SLOTS + HELD ITEM")
	var supply_row: HBoxContainer = HBoxContainer.new()
	supply_row.add_theme_constant_override("separation", 6)
	_detail_content.add_child(supply_row)
	for kind: String in ["bandage", "antibiotics", "splint", "trauma_kit"]:
		var symbol: String = "trauma" if kind == "trauma_kit" else kind
		var refs: Dictionary = _supply_chip(supply_row, symbol, kind)
		_supply_labels[kind] = refs["label"]


func _detail_metric(parent: HBoxContainer, title: String, color: Color) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", C.panel_box(Color("202625"), S.BRASS.darkened(0.44), 7, 1, 9))
	parent.add_child(card)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	card.add_child(stack)
	var row: HBoxContainer = HBoxContainer.new()
	stack.add_child(row)
	var title_label: Label = _label(title, 10, S.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var value: Label = _label("0%", 13, S.IVORY)
	row.add_child(value)
	var bar: ProgressBar = _progress(color, 7.0)
	stack.add_child(bar)
	return {"value": value, "bar": bar}


func _supply_chip(parent: HBoxContainer, symbol: String, kind: String) -> Dictionary:
	var chip: PanelContainer = PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", C.panel_box(Color("202625"), S.BRASS.darkened(0.43), 7, 1, 6))
	parent.add_child(chip)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)
	row.add_child(_icon(symbol, 18.0, S.BLUE))
	var label: Label = _label(_supply_short_name(kind) + "  0", 10, S.MUTED)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	return {"label": label}


func _build_needs_page() -> Control:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "NeedsPage"
	page.add_theme_constant_override("separation", 10)
	var header: HBoxContainer = HBoxContainer.new()
	page.add_child(header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("DAILY READINESS", 11, S.BLUE))
	titles.add_child(_label("Needs and recovery", 23, S.IVORY))
	var explainer: Label = _label("Caps show the highest value currently reachable.", 12, S.MUTED)
	explainer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header.add_child(explainer)
	_needs_reason_panel = PanelContainer.new()
	_needs_reason_panel.add_theme_stylebox_override("panel", C.panel_box(Color("2c241b"), INFECTION_COLOR.darkened(0.15), 7, 1, 8))
	page.add_child(_needs_reason_panel)
	_needs_reason_label = _label("", 12, INFECTION_COLOR)
	_needs_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_needs_reason_panel.add_child(_needs_reason_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	page.add_child(grid)
	_needs_rows["health"] = _need_card(grid, "health", "HEALTH", "Physical resilience. Deprivation and bleeding reduce this value.", S.RED)
	_needs_rows["food"] = _need_card(grid, "food", "FOOD", "Eat before the reserve is exhausted; illness can reduce the attainable cap.", FOOD_COLOR)
	_needs_rows["water"] = _need_card(grid, "water", "WATER", "Hydration depletes quickly and directly threatens health at zero.", WATER_COLOR)
	_needs_rows["stamina"] = _need_card(grid, "stamina", "STAMINA", "Short-term exertion reserve used by sprinting and demanding actions.", STAMINA_COLOR)
	_needs_rows["sleep"] = _need_card(grid, "sleep", "SLEEP", "Rest in a bed to recover. Medical conditions may reduce the cap.", SLEEP_COLOR)
	return page


func _need_card(parent: GridContainer, symbol: String, title: String, copy_text: String, color: Color) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 125.0
	card.add_theme_stylebox_override("panel", C.panel_box(Color("1b2221"), S.BRASS.darkened(0.38), 8, 1, 11))
	parent.add_child(card)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	card.add_child(stack)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	row.add_child(_icon(symbol, 25.0, color))
	var title_label: Label = _label(title, 12, color)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var value: Label = _label("100 / 100", 16, S.IVORY)
	row.add_child(value)
	var bar: ProgressBar = _progress(color, 9.0)
	stack.add_child(bar)
	var copy: Label = _label(copy_text, 11, S.MUTED)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(copy)
	var state: Label = _label("STABLE", 10, color)
	stack.add_child(state)
	return {"value": value, "bar": bar, "state": state, "color": color}


func _build_inventory_page() -> Control:
	var page: HBoxContainer = HBoxContainer.new()
	page.name = "InventoryPage"
	page.add_theme_constant_override("separation", 10)
	var slots_panel: PanelContainer = _section_panel()
	slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(slots_panel)
	var slots_stack: VBoxContainer = VBoxContainer.new()
	slots_stack.add_theme_constant_override("separation", 10)
	slots_panel.add_child(C.inset(slots_stack, 14, 12, 14, 12))
	var header: Dictionary = C.section_header(slots_stack, "QUICK INVENTORY", "4 CARRIED SLOTS")
	(header["title"] as Label).add_theme_color_override("font_color", S.BLUE)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	slots_stack.add_child(grid)
	for slot: int in range(4):
		var card: Button = ITEM_CARD.new() as Button
		card.name = "InventorySlot%d" % (slot + 1)
		grid.add_child(card)
		card.custom_minimum_size = Vector2(285.0, 198.0)
		card.pressed.connect(_select_inventory_slot.bind(slot))
		_inventory_cards.append(card)
		var viewport: SubViewport = PREVIEW.build_viewport(card, 152, 1.35)
		_inventory_viewports.append(viewport)

	var detail_panel: PanelContainer = _section_panel()
	detail_panel.custom_minimum_size.x = 430.0
	page.add_child(detail_panel)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	detail_panel.add_child(C.inset(detail, 16, 14, 16, 14))
	detail.add_child(_label("SELECTED SLOT", 10, S.BLUE))
	_inventory_detail_title = _label("Empty slot", 24, S.IVORY)
	detail.add_child(_inventory_detail_title)
	var line: HSeparator = HSeparator.new()
	detail.add_child(line)
	_inventory_detail_state = _label("AVAILABLE", 11, S.GREEN)
	detail.add_child(_inventory_detail_state)
	_inventory_detail_copy = _label("This quick slot is ready for a carried item.", 14, S.MUTED)
	_inventory_detail_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_detail_copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_inventory_detail_copy)
	var note: PanelContainer = PanelContainer.new()
	note.add_theme_stylebox_override("panel", C.panel_box(Color("192423"), S.BLUE.darkened(0.38), 8, 1, 10))
	detail.add_child(note)
	var note_copy: Label = _label("Quick-slot switching and item use remain available in the world. This page is an inspection view and does not silently change what you are holding.", 12, S.MUTED)
	note_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_child(note_copy)
	return page


func _build_footer() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(row)
	_footer_hint = _label("Q / E: tabs   •   Enter / Space: select   •   Tab / Esc: close", 12, S.MUTED)
	row.add_child(_footer_hint)


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = Vector2(
		maxf(760.0, viewport_size.x - SCREEN_MARGIN.x * 2.0),
		maxf(620.0, viewport_size.y - SCREEN_MARGIN.y * 2.0))
	var target: Vector2 = Vector2(minf(PANEL_MAX.x, available.x), minf(PANEL_MAX.y, available.y))
	_panel.size = target
	_panel.custom_minimum_size = target
	_panel.position = (viewport_size - target) * 0.5


func _set_tab(tab_id: int) -> void:
	if tab_id < 0 or tab_id >= _pages.size():
		return
	_active_tab = tab_id
	for index: int in range(_pages.size()):
		_pages[index].visible = index == tab_id
		_tab_buttons[index].button_pressed = index == tab_id
	_refresh_all()
	_reset_scrolls()
	if tab_id == StatusTab.HEALTH:
		var body_button: Button = _body_buttons.get(_selected_part) as Button
		if body_button != null:
			body_button.grab_focus()
	elif tab_id == StatusTab.INVENTORY and not _inventory_cards.is_empty():
		_inventory_cards[_selected_inventory_slot].grab_focus()


func _select_body_part(part: int) -> void:
	_selected_part = part
	var conditions: Array[MedicalCondition] = _conditions_for_part(part)
	_selected_condition_key = _condition_key(conditions[0]) if not conditions.is_empty() else ""
	_condition_signature = "__rebuild__"
	_refresh_health()


func _select_condition(key: String) -> void:
	_selected_condition_key = key
	_refresh_health()


func _select_inventory_slot(slot: int) -> void:
	_selected_inventory_slot = clampi(slot, 0, 3)
	for index: int in range(_inventory_cards.size()):
		_inventory_cards[index].button_pressed = index == _selected_inventory_slot
	_refresh_inventory_detail()


func _select_initial_medical_target() -> void:
	var all_conditions: Array[MedicalCondition] = _active_conditions()
	if all_conditions.is_empty():
		_selected_part = MedicalCondition.BodyPart.HEAD
		_selected_condition_key = ""
		return
	var worst: MedicalCondition = all_conditions[0]
	for condition: MedicalCondition in all_conditions:
		if _urgency(condition) > _urgency(worst):
			worst = condition
	_selected_part = int(worst.body_part)
	_selected_condition_key = _condition_key(worst)


func _refresh_all() -> void:
	if _panel == null:
		return
	_refresh_summary()
	_refresh_overview()
	_refresh_tabs()
	if _active_tab == StatusTab.HEALTH:
		_refresh_health()
	elif _active_tab == StatusTab.NEEDS:
		_refresh_needs()
	elif _active_tab == StatusTab.INVENTORY:
		_refresh_inventory()


func _refresh_tabs() -> void:
	if _tab_buttons.size() < 4:
		return
	var condition_count: int = _active_conditions().size()
	var occupied: int = _inventory_occupied_count()
	_tab_buttons[StatusTab.OVERVIEW].text = "OVERVIEW"
	_tab_buttons[StatusTab.HEALTH].text = "HEALTH  %d" % condition_count if condition_count > 0 else "HEALTH"
	_tab_buttons[StatusTab.NEEDS].text = "NEEDS"
	_tab_buttons[StatusTab.INVENTORY].text = "INVENTORY  %d/4" % occupied


func _refresh_summary() -> void:
	var health: float = player_stats.health if player_stats != null else 100.0
	var food: float = player_stats.food if player_stats != null else 100.0
	var water: float = player_stats.water if player_stats != null else 100.0
	var sleep: float = player_stats.sleep if player_stats != null else 100.0
	var food_cap: float = player_stats.food_cap if player_stats != null else 100.0
	var water_cap: float = player_stats.water_cap if player_stats != null else 100.0
	var sleep_cap: float = player_stats.sleep_cap if player_stats != null else 100.0
	var stamina: float = _player_stamina()
	_update_summary_metric("health", health, 100.0)
	_update_summary_metric("food", food, food_cap)
	_update_summary_metric("water", water, water_cap)
	_update_summary_metric("stamina", stamina, 100.0)
	_update_summary_metric("sleep", sleep, sleep_cap)
	var conditions: Array[MedicalCondition] = _active_conditions()
	var untreated: int = 0
	var infected: bool = false
	for condition: MedicalCondition in conditions:
		if _treatment_kind(condition) != "none" and not condition.is_treated:
			untreated += 1
		if condition.id == "open_wound" and condition.is_infected:
			infected = true
	var state_text: String = "STABLE"
	var state_color: Color = S.GREEN
	if infected:
		state_text = "INFECTION ACTIVE"
		state_color = INFECTION_COLOR
	elif untreated > 0:
		state_text = "%d UNTREATED" % untreated
		state_color = S.RED
	elif not conditions.is_empty():
		state_text = "RECOVERING"
		state_color = S.BLUE
	_header_status_label.text = state_text
	_header_status_label.add_theme_color_override("font_color", state_color)
	_header_status_panel.add_theme_stylebox_override("panel", C.panel_box(
		Color("17211f"), state_color.darkened(0.2), 18, 1, 6))


func _update_summary_metric(key: String, value: float, cap: float) -> void:
	var metric: Dictionary = _summary_metrics.get(key, {}) as Dictionary
	if metric.is_empty():
		return
	(metric["value"] as Label).text = "%d" % roundi(value)
	SMOOTH_BAR.apply(metric["bar"] as ProgressBar, clampf(value, 0.0, 100.0))
	var cap_label: Label = metric["cap"] as Label
	cap_label.text = "CAP %d%%" % roundi(cap) if cap < 99.5 else ""


func _refresh_overview() -> void:
	var conditions: Array[MedicalCondition] = _active_conditions()
	var untreated: int = 0
	for condition: MedicalCondition in conditions:
		if _treatment_kind(condition) != "none" and not condition.is_treated:
			untreated += 1
	_overview_condition_count.text = "%d ACTIVE" % conditions.size() if not conditions.is_empty() else "CLEAR"
	_overview_condition_copy.text = "%d condition%s can be treated from carried supplies." % [untreated, "" if untreated == 1 else "s"] if untreated > 0 else "No untreated condition currently needs a carried medical item."
	var capped_names: Array[String] = _capped_need_names()
	_overview_needs_count.text = "%d CAPPED" % capped_names.size() if not capped_names.is_empty() else "STABLE"
	_overview_needs_copy.text = "%s cannot currently reach 100%%." % ", ".join(capped_names) if not capped_names.is_empty() else "Food, water, and sleep can currently reach their full values."
	var occupied: int = _inventory_occupied_count()
	_overview_inventory_count.text = "%d / 4" % occupied
	_overview_inventory_copy.text = "%d open quick slot%s available." % [4 - occupied, "" if 4 - occupied == 1 else "s"]


func _refresh_health() -> void:
	_part_title.text = MedicalCondition.body_part_label(_selected_part)
	var selected_conditions: Array[MedicalCondition] = _conditions_for_part(_selected_part)
	_condition_count_label.text = "%d CONDITION%s" % [selected_conditions.size(), "" if selected_conditions.size() == 1 else "S"]
	for part: int in BODY_PARTS:
		var conditions: Array[MedicalCondition] = _conditions_for_part(part)
		var active: bool = not conditions.is_empty()
		var selected: bool = part == _selected_part
		var color: Color = _worst_color(conditions)
		var body_button: Button = _body_buttons.get(part) as Button
		if body_button != null:
			body_button.button_pressed = selected
			body_button.add_theme_stylebox_override("normal", C.panel_box(
				Color("2a1e1d") if active else Color("222827"),
				color if active else S.BRASS.darkened(0.3), 7, 2 if selected else 1))
		var row_button: Button = _body_badges.get(part) as Button
		if row_button != null:
			row_button.text = "%s     %s" % [MedicalCondition.body_part_label(part), "%d ACTIVE" % conditions.size() if active else "CLEAR"]
			row_button.button_pressed = selected
	_rebuild_condition_cards_if_needed(selected_conditions)
	_update_condition_cards(selected_conditions)
	var selected_condition: MedicalCondition = _selected_condition()
	_detail_empty.visible = selected_condition == null
	_detail_content.visible = selected_condition != null
	if selected_condition != null:
		_refresh_condition_detail(selected_condition)


func _rebuild_condition_cards_if_needed(conditions: Array[MedicalCondition]) -> void:
	var keys: Array[String] = []
	for condition: MedicalCondition in conditions:
		keys.append(_condition_key(condition))
	var signature: String = "|".join(keys)
	if signature == _condition_signature and _condition_list.get_child_count() > 0:
		return
	_condition_signature = signature
	_clear_children(_condition_list)
	_condition_cards.clear()
	if conditions.is_empty():
		var empty: PanelContainer = PanelContainer.new()
		empty.custom_minimum_size.y = 150.0
		empty.add_theme_stylebox_override("panel", C.panel_box(Color("181e1d"), S.BRASS.darkened(0.48), 8, 1, 12))
		_condition_list.add_child(empty)
		var copy: Label = _label("No conditions recorded for this region.", 13, S.MUTED)
		copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(copy)
		return
	for condition: MedicalCondition in conditions:
		var key: String = _condition_key(condition)
		var button: Button = Button.new()
		button.text = ""
		button.toggle_mode = true
		button.custom_minimum_size.y = 104.0
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override("normal", C.panel_box(Color("1b2221"), S.BRASS.darkened(0.38), 8, 1, 9))
		button.add_theme_stylebox_override("hover", C.panel_box(Color("202b2b"), S.BLUE.darkened(0.2), 8, 1, 9))
		button.add_theme_stylebox_override("pressed", C.panel_box(Color("1f3035"), S.BLUE, 8, 2, 8))
		button.add_theme_stylebox_override("focus", C.panel_box(Color.TRANSPARENT, S.IVORY, 9, 2))
		button.pressed.connect(_select_condition.bind(key))
		_condition_list.add_child(button)
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		var card_margin: MarginContainer = C.inset(row, 10, 9, 10, 9)
		card_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(card_margin)
		var icon_well: PanelContainer = C.icon_well(_condition_icon(condition), 42.0, _condition_color(condition))
		row.add_child(icon_well)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stack)
		var title: Label = _label(_condition_title(condition), 16, S.IVORY)
		stack.add_child(title)
		var state: Label = _label("", 11, S.MUTED)
		stack.add_child(state)
		var bar: ProgressBar = _progress(_condition_color(condition), 7.0)
		stack.add_child(bar)
		var value: Label = _label("", 11, S.MUTED)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		_condition_cards[key] = {"button": button, "title": title, "state": state, "bar": bar, "value": value}
	if _selected_condition_key.is_empty() or not _condition_cards.has(_selected_condition_key):
		_selected_condition_key = keys[0]


func _update_condition_cards(conditions: Array[MedicalCondition]) -> void:
	for condition: MedicalCondition in conditions:
		var key: String = _condition_key(condition)
		var refs: Dictionary = _condition_cards.get(key, {}) as Dictionary
		if refs.is_empty():
			continue
		(refs["button"] as Button).button_pressed = key == _selected_condition_key
		(refs["title"] as Label).text = _condition_title(condition)
		(refs["state"] as Label).text = _condition_state(condition)
		SMOOTH_BAR.apply(refs["bar"] as ProgressBar, _condition_primary_value(condition))
		(refs["value"] as Label).text = "%d%%" % roundi(_condition_primary_value(condition))


func _refresh_condition_detail(condition: MedicalCondition) -> void:
	var color: Color = _condition_color(condition)
	_detail_title.text = _condition_title(condition)
	_detail_location.text = MedicalCondition.body_part_label(condition.body_part).to_upper()
	_detail_location.add_theme_color_override("font_color", color)
	_detail_location_panel.add_theme_stylebox_override("panel", C.panel_box(Color("202625"), color.darkened(0.18), 16, 1, 6))
	var infection_active: bool = condition.id == "open_wound" and condition.is_infected
	_detail_warning.visible = infection_active
	if infection_active:
		_detail_warning.add_theme_stylebox_override("panel", C.panel_box(Color("30251a"), INFECTION_COLOR, 7, 1, 6))
		_detail_warning_label.text = "INFECTION ACTIVE  •  %d%% SEVERITY" % roundi(condition.infection_severity)
	_detail_severity_value.text = "%d%%" % roundi(_condition_primary_value(condition))
	SMOOTH_BAR.apply(_detail_severity_bar, _condition_primary_value(condition))
	_detail_severity_bar.add_theme_stylebox_override("fill", C.panel_box(color, color, 4, 0))
	_detail_recovery_value.text = "%d%%" % roundi(condition.heal_progress) if condition.has_heal_ring else _condition_state(condition).to_upper()
	var recovery_value: float = condition.heal_progress if condition.has_heal_ring else (100.0 if condition.is_treated else 0.0)
	SMOOTH_BAR.apply(_detail_recovery_bar, recovery_value)
	_detail_effects.text = _condition_detail_text(condition)
	_refresh_treatment(condition)
	_refresh_supplies()


func _refresh_treatment(condition: MedicalCondition) -> void:
	var kind: String = _treatment_kind(condition)
	var available: Node = _find_treatment_item(kind)
	var stock: int = _supply_charges(kind)
	var already_treated: bool = condition.is_treated and kind != "bandage"
	_treatment_icon.texture = S.icon(_treatment_icon_name(kind))
	_treatment_title.text = _treatment_title_text(kind, condition)
	_treatment_copy.text = _treatment_description(kind, condition)
	_treatment_stock.text = "%d CARRIED" % stock if stock > 0 else "NONE CARRIED"
	var stock_color: Color = S.GREEN if stock > 0 else S.MUTED.darkened(0.15)
	_treatment_stock.add_theme_color_override("font_color", stock_color)
	_treatment_stock_panel.add_theme_stylebox_override("panel", C.panel_box(Color("202625"), stock_color.darkened(0.2), 16, 1, 6))
	_treatment_button.visible = kind != "none"
	_treatment_button.disabled = available == null or already_treated
	if already_treated:
		_treatment_button.text = "TREATMENT APPLIED"
		_treatment_button.icon = S.icon("check")
	elif available == null:
		_treatment_button.text = "NO %s CARRIED" % _supply_short_name(kind).to_upper()
		_treatment_button.icon = S.icon(_treatment_icon_name(kind))
	else:
		_treatment_button.text = "APPLY %s" % _supply_short_name(kind).to_upper()
		_treatment_button.icon = S.icon(_treatment_icon_name(kind))


func _apply_selected_treatment() -> void:
	var condition: MedicalCondition = _selected_condition()
	if condition == null:
		return
	var kind: String = _treatment_kind(condition)
	var item: Node = _find_treatment_item(kind)
	if item == null:
		return
	var applied: bool = false
	if interaction_system != null and interaction_system.has_method("apply_medical_treatment_from_status"):
		applied = bool(interaction_system.call("apply_medical_treatment_from_status", item, int(condition.body_part)))
	elif item.has_method("apply_to_target"):
		item.call("apply_to_target", int(condition.body_part))
		applied = true
	if not applied:
		return
	_selected_condition_key = ""
	_condition_signature = "__rebuild__"
	_refresh_all()
	var remaining: Array[MedicalCondition] = _conditions_for_part(_selected_part)
	if not remaining.is_empty():
		_selected_condition_key = _condition_key(remaining[0])
		_refresh_health()


func _refresh_supplies() -> void:
	for kind_value: Variant in _supply_labels.keys():
		var kind: String = str(kind_value)
		var label: Label = _supply_labels[kind] as Label
		var charges: int = _supply_charges(kind)
		label.text = "%s  %d" % [_supply_short_name(kind), charges]
		label.add_theme_color_override("font_color", S.IVORY if charges > 0 else S.MUTED.darkened(0.25))


func _refresh_needs() -> void:
	var health: float = player_stats.health if player_stats != null else 100.0
	var food: float = player_stats.food if player_stats != null else 100.0
	var water: float = player_stats.water if player_stats != null else 100.0
	var sleep: float = player_stats.sleep if player_stats != null else 100.0
	var food_cap: float = player_stats.food_cap if player_stats != null else 100.0
	var water_cap: float = player_stats.water_cap if player_stats != null else 100.0
	var sleep_cap: float = player_stats.sleep_cap if player_stats != null else 100.0
	_update_need_card("health", health, 100.0)
	_update_need_card("food", food, food_cap)
	_update_need_card("water", water, water_cap)
	_update_need_card("stamina", _player_stamina(), 100.0)
	_update_need_card("sleep", sleep, sleep_cap)
	var reason: String = player_medical.get_needs_cap_reason_text() if player_medical != null else ""
	_needs_reason_panel.visible = not reason.is_empty()
	_needs_reason_label.text = reason


func _update_need_card(key: String, value: float, cap: float) -> void:
	var refs: Dictionary = _needs_rows.get(key, {}) as Dictionary
	if refs.is_empty():
		return
	(refs["value"] as Label).text = "%d / %d" % [roundi(value), roundi(cap)]
	SMOOTH_BAR.apply(refs["bar"] as ProgressBar, clampf(value, 0.0, 100.0))
	var state: Label = refs["state"] as Label
	if cap < 99.5:
		state.text = "CAPPED BY CONDITION"
		state.add_theme_color_override("font_color", INFECTION_COLOR)
	elif value <= 20.0:
		state.text = "CRITICAL"
		state.add_theme_color_override("font_color", S.RED)
	elif value <= 50.0:
		state.text = "LOW"
		state.add_theme_color_override("font_color", FOOD_COLOR)
	else:
		state.text = "STABLE"
		state.add_theme_color_override("font_color", refs["color"] as Color)


func _refresh_inventory() -> void:
	var slots: Array = _inventory_slots()
	for slot: int in range(4):
		var item: Node = _slot_item(slots, slot)
		var signature: String = PRESENT.signature(item)
		var card: BunkerItemCard = _inventory_cards[slot] as BunkerItemCard
		if signature != _inventory_signatures[slot]:
			_inventory_signatures[slot] = signature
			PREVIEW.set_item(_inventory_viewports[slot], item)
			card.display(PRESENT.title(item), _inventory_viewports[slot].get_texture() if item != null else null, 1)
		card.button_pressed = slot == _selected_inventory_slot
	_refresh_inventory_detail()


func _refresh_inventory_detail() -> void:
	var item: Node = _slot_item(_inventory_slots(), _selected_inventory_slot)
	if item == null:
		_inventory_detail_title.text = "Empty slot"
		_inventory_detail_state.text = "SLOT %d  •  AVAILABLE" % (_selected_inventory_slot + 1)
		_inventory_detail_state.add_theme_color_override("font_color", S.GREEN)
		_inventory_detail_copy.text = "This quick slot is ready for a carried item. Pick up an object in the world to store it here."
		return
	_inventory_detail_title.text = PRESENT.title(item)
	var held: bool = interaction_system != null and interaction_system.get("held_item") == item
	_inventory_detail_state.text = "SLOT %d  •  %s" % [_selected_inventory_slot + 1, "IN HAND" if held else "STORED"]
	_inventory_detail_state.add_theme_color_override("font_color", S.BLUE if held else S.GREEN)
	_inventory_detail_copy.text = PRESENT.detail(item)


func _refresh_footer() -> void:
	if _footer_hint == null:
		return
	if InputMode.is_controller():
		_footer_hint.text = "LB / RB: tabs   •   D-pad / right stick: navigate   •   A: select   •   View / B: close"
	else:
		_footer_hint.text = "Q / E: tabs   •   Enter / Space: select   •   Tab / Esc: close"


func _active_conditions() -> Array[MedicalCondition]:
	var result: Array[MedicalCondition] = []
	if player_medical != null:
		result.assign(player_medical.active_conditions)
	return result


func _conditions_for_part(part: int) -> Array[MedicalCondition]:
	var result: Array[MedicalCondition] = []
	if player_medical != null:
		result.assign(player_medical.get_conditions_for_body_part(part))
	return result


func _selected_condition() -> MedicalCondition:
	for condition: MedicalCondition in _conditions_for_part(_selected_part):
		if _condition_key(condition) == _selected_condition_key:
			return condition
	return null


func _condition_key(condition: MedicalCondition) -> String:
	return "%s:%d" % [condition.id, int(condition.body_part)]


func _condition_title(condition: MedicalCondition) -> String:
	match condition.id:
		"open_wound": return "Open wound"
		"bleeding": return "Bleeding"
		"fractured": return "Fracture"
		"broken": return "Broken bone"
		"burn": return "Burn"
	return condition.id.replace("_", " ").capitalize()


func _condition_icon(condition: MedicalCondition) -> String:
	match condition.id:
		"bleeding": return "water"
		"fractured", "broken": return "splint"
		"open_wound": return "medical"
		"burn": return "warning"
	return "health"


func _condition_color(condition: MedicalCondition) -> Color:
	if condition.id == "open_wound" and condition.is_infected:
		return INFECTION_COLOR
	if player_medical != null:
		return player_medical.get_condition_ring_color(condition)
	return S.RED


func _condition_primary_value(condition: MedicalCondition) -> float:
	if condition.id == "open_wound" and condition.is_infected:
		return condition.infection_severity
	return clampf(condition.severity, 0.0, 100.0)


func _condition_state(condition: MedicalCondition) -> String:
	if condition.id == "open_wound" and condition.is_infected:
		return "Infection active" if not condition.is_treated else "Antibiotics applied"
	if condition.is_treated:
		return "Treatment applied"
	if condition.has_heal_ring and condition.heal_progress > 0.0:
		return "Recovering"
	if _treatment_kind(condition) != "none":
		return "Treatment available"
	return "Monitoring"


func _condition_detail_text(condition: MedicalCondition) -> String:
	if player_medical != null:
		var text: String = player_medical.get_status_detail_text(condition)
		if not text.is_empty():
			return text
	return "No additional symptom effects are currently recorded."


func _urgency(condition: MedicalCondition) -> float:
	var value: float = _condition_primary_value(condition)
	if condition.id == "bleeding":
		value += 150.0
	elif condition.id == "open_wound" and condition.is_infected:
		value += 100.0
	return value


func _worst_color(conditions: Array[MedicalCondition]) -> Color:
	if conditions.is_empty():
		return S.GREEN
	var worst: MedicalCondition = conditions[0]
	for condition: MedicalCondition in conditions:
		if _urgency(condition) > _urgency(worst):
			worst = condition
	return _condition_color(worst)


func _treatment_kind(condition: MedicalCondition) -> String:
	match condition.id:
		"bleeding": return "bandage"
		"open_wound": return "antibiotics"
		"fractured", "broken": return "splint"
	return "none"


func _treatment_icon_name(kind: String) -> String:
	return "medical" if kind == "none" else kind


func _treatment_title_text(kind: String, condition: MedicalCondition) -> String:
	if kind == "none":
		return "Observation and recovery"
	if condition.is_treated and kind != "bandage":
		return "%s applied" % _supply_short_name(kind)
	return "Apply %s" % _supply_short_name(kind)


func _treatment_description(kind: String, condition: MedicalCondition) -> String:
	match kind:
		"bandage": return "Stops active blood loss on this body region."
		"antibiotics":
			return "Treats the active infection." if condition.is_infected else "Prevents this open wound from becoming infected."
		"splint": return "Stabilizes the injury, improves symptoms, and hastens recovery."
	return "No carried medical item can directly treat this condition. Rest and monitor its recovery."


func _find_treatment_item(kind: String) -> Node:
	if kind == "none":
		return null
	if interaction_system != null:
		var held_value: Variant = interaction_system.get("held_item")
		if held_value is Node and _item_matches_kind(held_value as Node, kind):
			return held_value as Node
	for item_value: Variant in _inventory_slots():
		if item_value is Node and _item_matches_kind(item_value as Node, kind):
			return item_value as Node
	return null


func _item_matches_kind(item: Node, kind: String) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not ("shelf_item_type" in item) or str(item.get("shelf_item_type")) != kind:
		return false
	if item.has_method("has_charges_left"):
		return bool(item.call("has_charges_left"))
	return _item_charges(item) > 0


func _supply_charges(kind: String) -> int:
	if kind == "none":
		return 0
	var total: int = 0
	var seen: Dictionary = {}
	if interaction_system != null:
		var held_value: Variant = interaction_system.get("held_item")
		if held_value is Node:
			var held: Node = held_value as Node
			if _item_matches_kind(held, kind):
				seen[held.get_instance_id()] = true
				total += _item_charges(held)
	for item_value: Variant in _inventory_slots():
		if not (item_value is Node):
			continue
		var item: Node = item_value as Node
		if seen.has(item.get_instance_id()) or not _item_matches_kind(item, kind):
			continue
		seen[item.get_instance_id()] = true
		total += _item_charges(item)
	return total


func _item_charges(item: Node) -> int:
	if "_charges_left" in item:
		return maxi(0, int(item.get("_charges_left")))
	if "_charges" in item:
		return maxi(0, int(item.get("_charges")))
	return 1


func _supply_short_name(kind: String) -> String:
	match kind:
		"bandage": return "Bandage"
		"antibiotics": return "Antibiotics"
		"splint": return "Splint"
		"trauma_kit": return "Trauma kit"
	return "Treatment"


func _inventory_slots() -> Array:
	if inventory != null and "slots" in inventory:
		var slots_value: Variant = inventory.get("slots")
		if slots_value is Array:
			return slots_value as Array
	return []


func _slot_item(slots: Array, slot: int) -> Node:
	if slot < 0 or slot >= slots.size():
		return null
	var value: Variant = slots[slot]
	return value as Node if value is Node and is_instance_valid(value as Node) else null


func _inventory_occupied_count() -> int:
	var count: int = 0
	for value: Variant in _inventory_slots():
		if value is Node and is_instance_valid(value as Node):
			count += 1
	return count


func _capped_need_names() -> Array[String]:
	var names: Array[String] = []
	if player_stats == null:
		return names
	if player_stats.food_cap < 99.5:
		names.append("Food")
	if player_stats.water_cap < 99.5:
		names.append("Water")
	if player_stats.sleep_cap < 99.5:
		names.append("Sleep")
	return names


func _player_stamina() -> float:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "stamina" in player:
		return clampf(float(player.get("stamina")), 0.0, 100.0)
	return 100.0


func _section_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", C.panel_box(Color("181e1d"), S.BRASS.darkened(0.38), 8, 1))
	return panel


func _pill(parent: Container, text_value: String, color: Color, minimum_width: float) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(minimum_width, 28.0)
	panel.add_theme_stylebox_override("panel", C.panel_box(Color("202625"), color.darkened(0.2), 16, 1, 5))
	parent.add_child(panel)
	var label: Label = _label(text_value, 10, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return {"panel": panel, "label": label}


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _icon(symbol: String, side: float, color: Color) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(side, side)
	icon.texture = S.icon(symbol)
	icon.self_modulate = color
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _progress(color: Color, height: float) -> ProgressBar:
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", C.panel_box(Color("111615"), S.BRASS.darkened(0.48), 4, 1))
	bar.add_theme_stylebox_override("fill", C.panel_box(color, color, 4, 0))
	return bar


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _reset_scrolls() -> void:
	for scroll: ScrollContainer in _scrolls:
		scroll.scroll_vertical = 0
