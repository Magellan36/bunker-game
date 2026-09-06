extends CanvasLayer
## Native-Control 2026 Power Terminal. Presentation only: every reading and
## action delegates to PowerManager's existing public API.

signal closed

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PROXIMITY: GDScript = preload("res://scripts/ui/common/UIProximityClose.gd")
const FADE: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const GRAPH: GDScript = preload("res://scripts/ui/power/PowerTerminalLoadGraph.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")

const PANEL_MAX := Vector2(1360.0, 800.0)
const EDGE := Vector2(44.0, 36.0)
const SAMPLE_INTERVAL: float = 1.0
const REFRESH_INTERVAL: float = 0.20
const LIVE_VALUE_RESPONSE: float = 9.0
const HISTORY_LEN: int = 60
const OVERVIEW: int = 0
const DEVICES: int = 1
const PRIORITY: int = 2
const NETWORK: int = 3

var connected_grid_key: String = ""
var connected_zone_index: int = -1
var _is_open: bool = false
var _sample_elapsed: float = 0.0
var _refresh_elapsed: float = 0.0
var _controller_hints: bool = false
var _active_tab: int = OVERVIEW
var _draw_history: PackedFloat32Array = PackedFloat32Array()
var _cap_history: PackedFloat32Array = PackedFloat32Array()
var _previous_focus: WeakRef
var _zone_customize_ui: CanvasLayer = null

var _view: Control
var _panel: PanelContainer
var _title: Label
var _header_status: PanelContainer
var _header_status_icon: TextureRect
var _header_status_text: Label
var _close: Button
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _footer: Label
var _controller_nav: Node
var _proximity: Node

var _load_value: Label
var _load_meta: Label
var _load_percent: Label
var _load_bar: ProgressBar
var _headroom_value: Label
var _headroom_meta: Label
var _battery_value: Label
var _battery_meta: Label
var _battery_bar: ProgressBar
var _graph: Control
var _source_list: VBoxContainer
var _zone_swatch: ColorRect
var _zone_name: Label
var _zone_state: Label
var _zone_counts: Label
var _zone_brownout: Label
var _zone_flow: Label
var _rename: Button
var _recolor: Button
var _consumer_preview: VBoxContainer
var _manage_priorities: Button
var _overview_reset: Button

var _generator_list: VBoxContainer
var _battery_list: VBoxContainer
var _device_consumer_list: VBoxContainer
var _priority_list: VBoxContainer
var _priority_count: Label
var _network_state: Label
var _network_detail: Label
var _network_counts: Label
var _network_brownout: Label
var _network_flow_list: VBoxContainer
var _network_shared_list: VBoxContainer
var _network_reset: Button
var _network_rename: Button
var _network_recolor: Button

var _source_signature: String = ""
var _preview_signature: String = ""
var _device_signature: String = ""
var _priority_signature: String = ""
var _network_signature: String = ""
var _source_rows: Dictionary = {}
var _preview_rows: Dictionary = {}
var _device_rows: Dictionary = {}
var _priority_rows: Dictionary = {}
var _metrics_initialized: bool = false
var _target_draw_watts: float = 0.0
var _target_capacity_watts: float = 0.0
var _display_draw_watts: float = 0.0
var _display_capacity_watts: float = 0.0
var _target_battery_charge: float = 0.0
var _target_battery_capacity: float = 0.0
var _display_battery_charge: float = 0.0
var _display_battery_capacity: float = 0.0
var _battery_connected: bool = false


func _ready() -> void:
	layer = 50
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
	set_process(true)
	get_viewport().size_changed.connect(_apply_panel_metrics)
	_apply_panel_metrics()


func open() -> void:
	if not _is_open:
		_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	_is_open = true
	visible = true
	_refresh_elapsed = REFRESH_INTERVAL
	_set_tab(OVERVIEW)
	_reset_scrolls(_view)
	_refresh_interface()
	_update_input_hint()
	_close.grab_focus()
	FADE.fade_in(_view)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if _zone_customize_ui != null and is_instance_valid(_zone_customize_ui) \
			and _zone_customize_ui.has_method("is_open") \
			and bool(_zone_customize_ui.call("is_open")):
		_zone_customize_ui.call("close")
	_proximity.unbind()
	visible = false
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


func bind_target(target: Node3D) -> void:
	if is_instance_valid(target):
		_proximity.bind_target(target)


func _process(delta: float) -> void:
	_sample_elapsed += delta
	if _sample_elapsed >= SAMPLE_INTERVAL:
		_sample_elapsed = fmod(_sample_elapsed, SAMPLE_INTERVAL)
		_sample_history()
	if not _is_open:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_refresh_interface()
	_animate_live_metrics(delta)
	if _controller_hints != InputMode.is_controller():
		_update_input_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not _controller_nav._is_topmost():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_E \
				or key_event.keycode == KEY_F1:
			close()
			get_viewport().set_input_as_handled()


func _build_interface() -> void:
	_view = Control.new()
	_view.name = "PowerTerminalWorkspace"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	C.apply_theme(_view)
	var backdrop: ColorRect = UIKit.build_modal_backdrop(0.44)
	_view.add_child(backdrop)
	_panel = PanelContainer.new()
	_panel.name = "PowerTerminalPanel"
	C.shell(_panel, 10)
	_view.add_child(_panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_panel.add_child(C.inset(content, 20, 16, 20, 12))
	_build_header(content)
	C.divider(content)
	_build_tabs(content)
	var page_stack: Control = Control.new()
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(page_stack)
	_build_overview(page_stack)
	_build_devices(page_stack)
	_build_priority(page_stack)
	_build_network(page_stack)
	C.divider(content)
	_footer = _label("", 12, S.MUTED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.custom_minimum_size.y = 22.0
	content.add_child(_footer)


func _build_header(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	row.add_child(C.icon_well("power", 54.0, S.BLUE))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(titles)
	titles.add_child(_label("POWER SYSTEM", 12, S.BRASS.lightened(0.35)))
	_title = _label("Power Terminal", 29, S.IVORY)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_title)
	_header_status = PanelContainer.new()
	_header_status.custom_minimum_size = Vector2(166.0, 42.0)
	row.add_child(_header_status)
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	_header_status.add_child(C.inset(status_row, 12, 8, 12, 8))
	_header_status_icon = TextureRect.new()
	_header_status_icon.texture = S.icon("grid")
	_header_status_icon.custom_minimum_size = Vector2(18.0, 18.0)
	_header_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_row.add_child(_header_status_icon)
	_header_status_text = _label("GRID ONLINE", 14, S.GREEN)
	status_row.add_child(_header_status_text)
	_close = Button.new()
	_close.custom_minimum_size = Vector2(48.0, 48.0)
	_close.tooltip_text = "Close power terminal"
	S.icon_button(_close, "close")
	_close.text = ""
	_close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close.pressed.connect(close)
	row.add_child(_close)


func _build_tabs(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var labels: Array[String] = ["OVERVIEW", "DEVICES", "LOAD PRIORITY", "ZONE NETWORK"]
	var icons: Array[String] = ["general", "battery", "log", "grid"]
	for index: int in range(labels.size()):
		var button: Button = Button.new()
		button.text = labels[index]
		button.icon = S.icon(icons[index])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44.0
		button.toggle_mode = true
		C.style_segment(button)
		button.pressed.connect(_set_tab.bind(index))
		row.add_child(button)
		_tabs.append(button)


func _build_overview(stack: Control) -> void:
	var page: VBoxContainer = _page(stack, "Overview", true) as VBoxContainer
	page.add_theme_constant_override("separation", 10)
	var metrics: HBoxContainer = HBoxContainer.new()
	metrics.custom_minimum_size.y = 112.0
	metrics.add_theme_constant_override("separation", 10)
	page.add_child(metrics)
	_build_metrics(metrics)
	var lower: HBoxContainer = HBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 10)
	page.add_child(lower)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.9
	left.add_theme_constant_override("separation", 10)
	lower.add_child(left)
	_build_graph_card(left)
	_build_sources_card(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 390.0
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	lower.add_child(right)
	_build_zone_card(right)
	_build_preview_card(right)
	_overview_reset = Button.new()
	_overview_reset.icon = S.icon("undo")
	S.button(_overview_reset, false, true)
	_overview_reset.disabled = true
	_overview_reset.custom_minimum_size.y = 36.0
	_overview_reset.pressed.connect(_reset_power)
	page.add_child(_overview_reset)


func _build_metrics(parent: Container) -> void:
	var body: VBoxContainer = _metric(parent, "CURRENT LOAD", "power", 1.35)
	var line: HBoxContainer = HBoxContainer.new()
	body.add_child(line)
	_load_value = _label("0 W", 27, S.BLUE)
	_load_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_load_value)
	_load_percent = _label("0%", 24, S.BLUE)
	line.add_child(_load_percent)
	_load_meta = _label("of 0 W capacity", 13, S.MUTED)
	body.add_child(_load_meta)
	_load_bar = _progress(S.BLUE)
	body.add_child(_load_bar)
	body = _metric(parent, "HEADROOM", "condition", 1.0)
	_headroom_value = _label("+0 W", 29, S.GREEN)
	body.add_child(_headroom_value)
	_headroom_meta = _label("Stable", 13, S.MUTED)
	body.add_child(_headroom_meta)
	body = _metric(parent, "BATTERY RESERVE", "battery", 1.2)
	_battery_value = _label("NONE", 27, S.BLUE.lightened(0.18))
	body.add_child(_battery_value)
	_battery_meta = _label("No battery connected", 13, S.MUTED)
	body.add_child(_battery_meta)
	_battery_bar = _progress(S.BLUE)
	_battery_bar.visible = false
	body.add_child(_battery_bar)


func _metric(parent: Container, title_text: String, icon: String,
		stretch: float) -> VBoxContainer:
	var card: PanelContainer = _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = stretch
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	card.add_child(C.inset(body, 14, 10, 14, 10))
	body.add_child(_heading(title_text, icon))
	return body


func _build_graph_card(parent: Container) -> void:
	var card: PanelContainer = _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.18
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(C.inset(body, 14, 10, 14, 10))
	var heading: HBoxContainer = _heading("LIVE LOAD · LAST 60 SECONDS", "general")
	body.add_child(heading)
	heading.add_child(_label("60s", 12, S.BLUE))
	_graph = GRAPH.new()
	_graph.custom_minimum_size.y = 150.0
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_graph)
	var legend: HBoxContainer = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 22)
	body.add_child(legend)
	legend.add_child(_legend("LOAD", S.BLUE))
	legend.add_child(_legend("CAPACITY", S.BRASS.lightened(0.35)))


func _build_sources_card(parent: Container) -> void:
	var card: PanelContainer = _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 0.82
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card.add_child(C.inset(body, 14, 10, 14, 10))
	body.add_child(_heading("POWER SOURCES", "power"))
	var scroll: ScrollContainer = _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_source_list = VBoxContainer.new()
	_source_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_source_list)


func _build_zone_card(parent: Container) -> void:
	var card: PanelContainer = _card()
	card.custom_minimum_size.y = 210.0
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card.add_child(C.inset(body, 14, 10, 14, 10))
	body.add_child(_heading("THIS ZONE", "grid"))
	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	body.add_child(main)
	_zone_swatch = ColorRect.new()
	_zone_swatch.custom_minimum_size = Vector2(52.0, 52.0)
	main.add_child(_zone_swatch)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(identity)
	_zone_name = _label("Unwired", 21, S.IVORY)
	identity.add_child(_zone_name)
	_zone_state = _label("OFFLINE", 14, S.RED)
	identity.add_child(_zone_state)
	_zone_counts = _label("0 nodes\n0 edges\n0 reachable", 13, S.MUTED)
	main.add_child(_zone_counts)
	_zone_brownout = _status_line("No brownout edges", S.GREEN)
	body.add_child(_zone_brownout)
	_zone_flow = _status_line("Single zone · No cross-zone flow", S.MUTED)
	body.add_child(_zone_flow)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	_rename = _action("Rename zone", "general")
	_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename.pressed.connect(_open_zone_rename)
	actions.add_child(_rename)
	_recolor = _action("Zone color", "settings")
	_recolor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recolor.pressed.connect(_open_zone_color_picker)
	actions.add_child(_recolor)


func _build_preview_card(parent: Container) -> void:
	var card: PanelContainer = _card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	card.add_child(C.inset(body, 14, 10, 14, 10))
	body.add_child(_heading("ACTIVE CONSUMERS", "running"))
	var scroll: ScrollContainer = _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_consumer_preview = VBoxContainer.new()
	_consumer_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_consumer_preview)
	_manage_priorities = _action("Manage load priorities", "log")
	_manage_priorities.pressed.connect(_set_tab.bind(PRIORITY))
	body.add_child(_manage_priorities)


func _build_devices(stack: Control) -> void:
	var page: HBoxContainer = _page(stack, "Devices", false) as HBoxContainer
	page.add_theme_constant_override("separation", 10)
	_generator_list = _device_column(page, "GENERATORS", "power")
	_battery_list = _device_column(page, "BATTERIES", "battery")
	_device_consumer_list = _device_column(page, "CONSUMERS", "running")


func _device_column(parent: Container, title_text: String, icon: String) -> VBoxContainer:
	var card: PanelContainer = _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card.add_child(C.inset(body, 14, 11, 14, 11))
	body.add_child(_heading(title_text, icon))
	var scroll: ScrollContainer = _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	return list


func _build_priority(stack: Control) -> void:
	var page: HBoxContainer = _page(stack, "LoadPriority", false) as HBoxContainer
	page.add_theme_constant_override("separation", 10)
	var list_card: PanelContainer = _card()
	list_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_card.size_flags_stretch_ratio = 2.1
	page.add_child(list_card)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	list_card.add_child(C.inset(body, 14, 11, 14, 11))
	var heading: HBoxContainer = _heading("LOAD PRIORITY", "log")
	body.add_child(heading)
	_priority_count = _label("0 DEVICES", 12, S.BRASS.lightened(0.35))
	heading.add_child(_priority_count)
	var intro: Label = _label(
		"Choose which systems retain power when supply cannot meet demand.", 13, S.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	var scroll: ScrollContainer = _scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_priority_list = VBoxContainer.new()
	_priority_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_priority_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_priority_list)

	var guide_card: PanelContainer = _card()
	guide_card.custom_minimum_size.x = 350.0
	page.add_child(guide_card)
	var guide: VBoxContainer = VBoxContainer.new()
	guide.add_theme_constant_override("separation", 10)
	guide_card.add_child(C.inset(guide, 16, 13, 16, 13))
	guide.add_child(_heading("SHEDDING ORDER", "warning"))
	var copy: Label = _label(
		"Higher-numbered tiers are disconnected first during an overload.", 13, S.MUTED)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_child(copy)
	var names: Array[String] = ["P1 · Critical", "P2 · Essential", "P3 · Standard", "P4 · Comfort", "P5 · First shed"]
	var details: Array[String] = ["Never intentionally shed", "Life-support systems", "Normal bunker equipment", "Nonessential comfort", "Disconnected first"]
	for index: int in range(names.size()):
		guide.add_child(_priority_guide(names[index], details[index], index + 1))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	guide.add_child(spacer)
	var note: Label = _status_line(
		"Priority changes settle after a short grid grace period.", S.BRASS.lightened(0.32))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_child(note)


func _build_network(stack: Control) -> void:
	var page: HBoxContainer = _page(stack, "ZoneNetwork", false) as HBoxContainer
	page.add_theme_constant_override("separation", 10)
	var summary_card: PanelContainer = _card()
	summary_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(summary_card)
	var summary: VBoxContainer = VBoxContainer.new()
	summary.add_theme_constant_override("separation", 10)
	summary_card.add_child(C.inset(summary, 16, 13, 16, 13))
	summary.add_child(_heading("ZONE NETWORK", "grid"))
	_network_state = _label("UNWIRED", 26, S.RED)
	summary.add_child(_network_state)
	_network_detail = _label("Wire this terminal into an enclosed zone.", 13, S.MUTED)
	_network_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(_network_detail)
	C.divider(summary)
	_network_counts = _label("Nodes  0\nEdges  0\nReachable  0", 16, S.IVORY)
	_network_counts.add_theme_constant_override("line_spacing", 5)
	summary.add_child(_network_counts)
	_network_brownout = _status_line("No brownout edges", S.GREEN)
	summary.add_child(_network_brownout)
	C.divider(summary)
	_network_rename = _action("Rename zone", "general")
	_network_rename.pressed.connect(_open_zone_rename)
	summary.add_child(_network_rename)
	_network_recolor = _action("Zone color", "settings")
	_network_recolor.pressed.connect(_open_zone_color_picker)
	summary.add_child(_network_recolor)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary.add_child(spacer)
	_network_reset = Button.new()
	_network_reset.icon = S.icon("undo")
	S.button(_network_reset, false, true)
	_network_reset.disabled = true
	_network_reset.pressed.connect(_reset_power)
	summary.add_child(_network_reset)

	var flow_card: PanelContainer = _card()
	flow_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow_card.size_flags_stretch_ratio = 1.35
	page.add_child(flow_card)
	var flow: VBoxContainer = VBoxContainer.new()
	flow.add_theme_constant_override("separation", 8)
	flow_card.add_child(C.inset(flow, 16, 13, 16, 13))
	flow.add_child(_heading("CROSS-ZONE FLOW", "wire"))
	var flow_scroll: ScrollContainer = _scroll()
	flow_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flow.add_child(flow_scroll)
	_network_flow_list = VBoxContainer.new()
	_network_flow_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_network_flow_list.add_theme_constant_override("separation", 7)
	flow_scroll.add_child(_network_flow_list)

	var shared_card: PanelContainer = _card()
	shared_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(shared_card)
	var shared: VBoxContainer = VBoxContainer.new()
	shared.add_theme_constant_override("separation", 8)
	shared_card.add_child(C.inset(shared, 16, 13, 16, 13))
	shared.add_child(_heading("SHARED CONNECTIONS", "battery"))
	var shared_scroll: ScrollContainer = _scroll()
	shared_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shared.add_child(shared_scroll)
	_network_shared_list = VBoxContainer.new()
	_network_shared_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_network_shared_list.add_theme_constant_override("separation", 7)
	shared_scroll.add_child(_network_shared_list)


func _page(stack: Control, page_name: String, vertical: bool) -> Control:
	var page: Control = VBoxContainer.new() if vertical else HBoxContainer.new()
	page.name = page_name
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	stack.add_child(page)
	_pages.append(page)
	return page


func _set_tab(index: int) -> void:
	_active_tab = clampi(index, 0, _pages.size() - 1)
	for page_index: int in range(_pages.size()):
		_pages[page_index].visible = page_index == _active_tab
		_tabs[page_index].set_pressed_no_signal(page_index == _active_tab)
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and not focus.is_visible_in_tree():
		_tabs[_active_tab].grab_focus()
	_reset_scrolls(_pages[_active_tab])


func _apply_panel_metrics() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = Vector2(
		minf(PANEL_MAX.x, maxf(760.0, viewport_size.x - EDGE.x * 2.0)),
		minf(PANEL_MAX.y, maxf(620.0, viewport_size.y - EDGE.y * 2.0)))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -panel_size.x * 0.5
	_panel.offset_right = panel_size.x * 0.5
	_panel.offset_top = -panel_size.y * 0.5
	_panel.offset_bottom = panel_size.y * 0.5


func _sample_history() -> void:
	var bundle: Dictionary = _scoped_bundle()
	var snapshot: Dictionary = bundle.get("snapshot", {}) as Dictionary
	if snapshot.is_empty():
		return
	_draw_history.append(float(snapshot.get("total_draw_watts", 0.0)))
	_cap_history.append(float(snapshot.get("total_capacity_watts", 0.0)))
	while _draw_history.size() > HISTORY_LEN:
		_draw_history.remove_at(0)
	while _cap_history.size() > HISTORY_LEN:
		_cap_history.remove_at(0)


func _refresh_interface() -> void:
	var bundle: Dictionary = _scoped_bundle()
	var snapshot: Dictionary = bundle.get("snapshot", {}) as Dictionary
	var zone: Dictionary = bundle.get("zone", {}) as Dictionary
	var zones: Array = bundle.get("zones", []) as Array
	if snapshot.is_empty():
		_header_status_text.text = "POWER MANAGER OFFLINE"
		_header_status_text.add_theme_color_override("font_color", S.RED)
		return
	_refresh_header(snapshot, zone)
	_refresh_metrics(snapshot)
	_graph.call("set_history", _draw_history, _cap_history)
	_sync_sources(snapshot, zone, zones)
	_refresh_zone(snapshot, zone)
	_sync_preview(snapshot)
	_sync_devices(snapshot, zone, zones)
	_sync_priorities(snapshot)
	_refresh_network(snapshot, zone, zones)


func _scoped_bundle() -> Dictionary:
	var pm: PowerManager = _pm()
	if pm == null:
		return {"snapshot": {}, "zone": {}, "zones": []}
	var snapshot: Dictionary = pm.get_debug_snapshot()
	var zones: Array = pm.get_zone_snapshot()
	var zone: Dictionary = {}
	if connected_zone_index >= 0:
		for raw_zone: Variant in zones:
			var candidate: Dictionary = raw_zone as Dictionary
			if int(candidate.get("zone_index", -1)) == connected_zone_index:
				zone = candidate
				break
	if not zone.is_empty():
		_filter_to_zone(snapshot, zone)
	elif not connected_grid_key.is_empty():
		_filter_to_ids(snapshot, pm.get_reachable_device_ids(connected_grid_key))
	return {"snapshot": snapshot, "zone": zone, "zones": zones}


func _filter_to_zone(snapshot: Dictionary, zone: Dictionary) -> void:
	var generators: Array = _filter(snapshot.get("generators", []) as Array,
		_id_set(zone.get("generator_ids", []) as Array))
	var batteries: Array = _filter(snapshot.get("batteries", []) as Array,
		_id_set(zone.get("battery_ids", []) as Array))
	var consumers: Array = _filter(snapshot.get("consumers", []) as Array,
		_id_set(zone.get("consumer_ids", []) as Array))
	snapshot["generators"] = generators
	snapshot["batteries"] = batteries
	snapshot["consumers"] = consumers
	snapshot["total_draw_watts"] = float(zone.get("draw_w", _powered_draw(consumers)))
	snapshot["total_capacity_watts"] = float(zone.get("capacity_w", _running_capacity(generators)))
	snapshot["_zone_state_str"] = String(zone.get("state_str", "ONLINE"))


func _filter_to_ids(snapshot: Dictionary, ids: Array) -> void:
	var allowed: Dictionary = _id_set(ids)
	var generators: Array = _filter(snapshot.get("generators", []) as Array, allowed)
	var batteries: Array = _filter(snapshot.get("batteries", []) as Array, allowed)
	var consumers: Array = _filter(snapshot.get("consumers", []) as Array, allowed)
	snapshot["generators"] = generators
	snapshot["batteries"] = batteries
	snapshot["consumers"] = consumers
	snapshot["total_draw_watts"] = _powered_draw(consumers)
	snapshot["total_capacity_watts"] = _running_capacity(generators)


func _id_set(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_id: Variant in ids:
		result[String(raw_id)] = true
	return result


func _filter(devices: Array, allowed: Dictionary) -> Array:
	var result: Array = []
	for raw_device: Variant in devices:
		var device: Dictionary = raw_device as Dictionary
		if allowed.has(String(device.get("id", ""))):
			result.append(device)
	return result


func _powered_draw(consumers: Array) -> float:
	var total: float = 0.0
	for raw_consumer: Variant in consumers:
		var consumer: Dictionary = raw_consumer as Dictionary
		if bool(consumer.get("powered", false)):
			total += float(consumer.get("watts", 0.0))
	return total


func _running_capacity(generators: Array) -> float:
	var total: float = 0.0
	for raw_generator: Variant in generators:
		var generator: Dictionary = raw_generator as Dictionary
		if bool(generator.get("running", false)):
			total += float(generator.get("watts", 0.0))
	return total


func _refresh_header(snapshot: Dictionary, zone: Dictionary) -> void:
	_title.text = "%s Power Terminal" % _zone_name_for(zone) if not zone.is_empty() else "Power Terminal"
	var state: String = _state(snapshot, zone)
	var color: Color = _state_color(state)
	_header_status_text.text = "GRID %s" % state
	_header_status_text.add_theme_color_override("font_color", color)
	_header_status_icon.self_modulate = color
	_header_status.add_theme_stylebox_override("panel", C.panel_box(
		S.BG.lerp(color, 0.10), S.BG.lerp(color, 0.72), 7, 1, 8))


func _refresh_metrics(snapshot: Dictionary) -> void:
	var draw: float = float(snapshot.get("total_draw_watts", 0.0))
	var capacity: float = float(snapshot.get("total_capacity_watts", 0.0))
	var percent: float = 0.0 if capacity <= 0.0 else clampf(draw / capacity * 100.0, 0.0, 999.0)
	var previous_headroom: float = _display_capacity_watts - _display_draw_watts
	var target_headroom: float = capacity - draw
	_target_draw_watts = draw
	_target_capacity_watts = capacity
	if not _metrics_initialized or signf(previous_headroom) != signf(target_headroom):
		_display_draw_watts = draw
		_display_capacity_watts = capacity
		_metrics_initialized = true
	SMOOTH_BAR.apply(_load_bar, clampf(percent, 0.0, 100.0))
	var load_color: Color = S.RED if draw > capacity and capacity > 0.0 else S.BLUE
	_progress_color(_load_bar, load_color)
	_load_value.add_theme_color_override("font_color", load_color)
	_load_percent.add_theme_color_override("font_color", load_color)
	var headroom_color: Color = S.GREEN if target_headroom >= 0.0 else S.RED
	_headroom_value.add_theme_color_override("font_color", headroom_color)
	_headroom_meta.text = "Stable" if target_headroom >= 0.0 else "Demand exceeds available supply"
	_headroom_meta.add_theme_color_override("font_color", S.MUTED if target_headroom >= 0.0 else S.RED)
	var batteries: Array = snapshot.get("batteries", []) as Array
	var charge: float = 0.0
	var battery_capacity: float = 0.0
	for raw_battery: Variant in batteries:
		var battery: Dictionary = raw_battery as Dictionary
		charge += float(battery.get("charge_wh", 0.0))
		battery_capacity += float(battery.get("capacity_wh", 0.0))
	if batteries.is_empty() or battery_capacity <= 0.0:
		_battery_connected = false
		_battery_value.text = "NONE"
		_battery_meta.text = "No battery connected"
		_battery_bar.visible = false
	else:
		var battery_percent: float = clampf(charge / battery_capacity * 100.0, 0.0, 100.0)
		_target_battery_charge = charge
		_target_battery_capacity = battery_capacity
		if not _battery_connected:
			_display_battery_charge = charge
			_display_battery_capacity = battery_capacity
		_battery_connected = true
		_battery_bar.visible = true
		SMOOTH_BAR.apply(_battery_bar, battery_percent)
	_render_live_metrics()


func _animate_live_metrics(delta: float) -> void:
	if not _metrics_initialized:
		return
	var weight: float = 1.0 - exp(-LIVE_VALUE_RESPONSE * delta)
	_display_draw_watts = _snap_metric(
		lerpf(_display_draw_watts, _target_draw_watts, weight), _target_draw_watts
	)
	_display_capacity_watts = _snap_metric(
		lerpf(_display_capacity_watts, _target_capacity_watts, weight), _target_capacity_watts
	)
	if _battery_connected:
		_display_battery_charge = _snap_metric(
			lerpf(_display_battery_charge, _target_battery_charge, weight), _target_battery_charge
		)
		_display_battery_capacity = _snap_metric(
			lerpf(_display_battery_capacity, _target_battery_capacity, weight),
			_target_battery_capacity
		)
	_render_live_metrics()


func _render_live_metrics() -> void:
	_load_value.text = _watts(_display_draw_watts)
	_load_meta.text = "of %s capacity" % _watts(_display_capacity_watts)
	var display_percent: float = 0.0
	if _display_capacity_watts > 0.0:
		display_percent = _display_draw_watts / _display_capacity_watts * 100.0
	_load_percent.text = "%d%%" % int(round(display_percent))
	var headroom: float = _display_capacity_watts - _display_draw_watts
	_headroom_value.text = "%s%s" % ["+" if headroom >= 0.0 else "", _watts(headroom)]
	if _battery_connected and _display_battery_capacity > 0.0:
		var battery_percent: float = clampf(
			_display_battery_charge / _display_battery_capacity * 100.0, 0.0, 100.0
		)
		_battery_value.text = "%d%%" % int(round(battery_percent))
		_battery_meta.text = "%s of %s reserved" % [
			_wh(_display_battery_charge), _wh(_display_battery_capacity)
		]


func _snap_metric(value: float, target: float) -> float:
	return target if absf(value - target) < 0.05 else value


func _sync_sources(snapshot: Dictionary, zone: Dictionary, zones: Array) -> void:
	var generators: Array = snapshot.get("generators", []) as Array
	var batteries: Array = snapshot.get("batteries", []) as Array
	var shared: Array = _shared_batteries(zone, zones)
	var signature: String = _ids(generators) + "|" + _ids(batteries) + "|" + _ids(shared)
	if signature != _source_signature:
		_source_signature = signature
		_source_rows.clear()
		_clear(_source_list)
		for raw_generator: Variant in generators:
			_add_source(raw_generator as Dictionary, "generator", false, generators)
		for raw_battery: Variant in batteries:
			_add_source(raw_battery as Dictionary, "battery", false, batteries)
		for raw_shared: Variant in shared:
			_add_source(raw_shared as Dictionary, "battery", true, shared)
		if generators.is_empty() and batteries.is_empty() and shared.is_empty():
			_source_list.add_child(_empty("No power sources connected to this zone", "power"))
	_refresh_source_values(generators, batteries, shared)


func _add_source(device: Dictionary, kind: String, shared: bool, peers: Array) -> void:
	var id: String = String(device.get("id", ""))
	var key: String = ("shared:" if shared else "local:") + kind + ":" + id
	var card: PanelContainer = _card(Color("1a201f"))
	card.custom_minimum_size.y = 66.0
	_source_list.add_child(card)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(C.inset(row, 12, 8, 12, 8))
	row.add_child(C.icon_well("power" if kind == "generator" else "battery", 44.0, S.BLUE))
	var identity: VBoxContainer = VBoxContainer.new()
	identity.custom_minimum_size.x = 150.0
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(_label(_device_name(kind, id, peers), 15, S.IVORY))
	var status: Label = _label("", 12, S.GREEN)
	identity.add_child(status)
	var value: Label = _label("", 17, S.IVORY)
	value.custom_minimum_size.x = 90.0
	row.add_child(value)
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail_box)
	var detail: Label = _label("", 12, S.MUTED)
	detail_box.add_child(detail)
	var bar: ProgressBar = _progress(S.BLUE)
	detail_box.add_child(bar)
	_source_rows[key] = {"status": status, "value": value, "detail": detail, "bar": bar}


func _refresh_source_values(generators: Array, batteries: Array, shared: Array) -> void:
	for raw_generator: Variant in generators:
		var generator: Dictionary = raw_generator as Dictionary
		var row: Dictionary = _source_rows.get("local:generator:" + String(generator.get("id", "")), {}) as Dictionary
		if row.is_empty():
			continue
		var running: bool = bool(generator.get("running", false))
		var backup: bool = bool(generator.get("is_backup", false))
		var status: Label = row.get("status") as Label
		status.text = "●  RUNNING" if running else ("●  STANDBY" if backup else "●  STOPPED")
		status.add_theme_color_override("font_color", S.GREEN if running else (S.BLUE if backup else S.MUTED))
		(row.get("value") as Label).text = _watts(float(generator.get("watts", 0.0)))
		var fuel: float = clampf(float(generator.get("fuel", 0.0)), 0.0, 100.0)
		var health: float = clampf(float(generator.get("health", 0.0)), 0.0, 100.0)
		(row.get("detail") as Label).text = "Fuel %d%%  ·  Condition %d%%" % [int(fuel), int(health)]
		var bar: ProgressBar = row.get("bar") as ProgressBar
		SMOOTH_BAR.apply(bar, fuel)
		_progress_color(bar, S.RED if fuel <= 15.0 else S.BLUE)
	_refresh_battery_sources(batteries, false)
	_refresh_battery_sources(shared, true)


func _refresh_battery_sources(batteries: Array, shared: bool) -> void:
	for raw_battery: Variant in batteries:
		var battery: Dictionary = raw_battery as Dictionary
		var key: String = ("shared:" if shared else "local:") + "battery:" + String(battery.get("id", ""))
		var row: Dictionary = _source_rows.get(key, {}) as Dictionary
		if row.is_empty():
			continue
		var capacity: float = float(battery.get("capacity_wh", 0.0))
		var charge: float = float(battery.get("charge_wh", 0.0))
		var percent: float = 0.0 if capacity <= 0.0 else clampf(charge / capacity * 100.0, 0.0, 100.0)
		var state: String = String(battery.get("state", "IDLE"))
		var status: Label = row.get("status") as Label
		status.text = "●  %s%s" % [state, " · SHARED" if shared else ""]
		status.add_theme_color_override("font_color", _battery_color(state))
		(row.get("value") as Label).text = "%d%%" % int(round(percent))
		(row.get("detail") as Label).text = "%s of %s" % [_wh(charge), _wh(capacity)]
		var bar: ProgressBar = row.get("bar") as ProgressBar
		SMOOTH_BAR.apply(bar, percent)
		_progress_color(bar, S.RED if percent <= 10.0 else S.BLUE)


func _refresh_zone(snapshot: Dictionary, zone: Dictionary) -> void:
	var wired: bool = not zone.is_empty()
	var state: String = _state(snapshot, zone)
	_zone_swatch.color = _zone_color(zone) if wired else S.SURFACE_ALT
	_zone_name.text = _zone_name_for(zone) if wired else "Unwired"
	_zone_state.text = "●  " + state
	_zone_state.add_theme_color_override("font_color", _state_color(state))
	_zone_counts.text = "%d nodes\n%d edges\n%d reachable" % [
		int(snapshot.get("wire_node_count", 0)), int(snapshot.get("wire_edge_count", 0)),
		int(snapshot.get("reachable_node_count", 0))]
	var overloaded: bool = bool(zone.get("overloaded", false)) if wired else false
	_zone_brownout.text = "⚠  Brownout edges detected" if overloaded else "●  No brownout edges"
	_zone_brownout.add_theme_color_override("font_color", S.BRASS.lightened(0.3) if overloaded else S.GREEN)
	_zone_flow.text = _flow_summary(zone)
	var can_customize: bool = wired and not String(zone.get("zone_key", "")).is_empty()
	_rename.disabled = not can_customize
	_recolor.disabled = not can_customize
	_overview_reset.disabled = not _reset_active(snapshot, zone)
	_overview_reset.text = "Reset %s" % _zone_name_for(zone) if wired else "Reset grid"


func _sync_preview(snapshot: Dictionary) -> void:
	var consumers: Array = snapshot.get("consumers", []) as Array
	var signature: String = _ids(consumers)
	if signature != _preview_signature:
		_preview_signature = signature
		_preview_rows.clear()
		_clear(_consumer_preview)
		if consumers.is_empty():
			_consumer_preview.add_child(_empty("No consumers connected", "running"))
		else:
			for raw_consumer: Variant in consumers:
				_add_preview(raw_consumer as Dictionary, consumers)
	for raw_consumer: Variant in consumers:
		var consumer: Dictionary = raw_consumer as Dictionary
		var row: Dictionary = _preview_rows.get(String(consumer.get("id", "")), {}) as Dictionary
		if row.is_empty():
			continue
		(row.get("watts") as Label).text = _watts(float(consumer.get("watts", 0.0)))
		var state: String = _consumer_state(consumer)
		var status: Label = row.get("status") as Label
		status.text = "●  " + state
		status.add_theme_color_override("font_color", _consumer_color(state))
		(row.get("priority") as Button).text = "P%d" % int(consumer.get("priority", 3))


func _add_preview(consumer: Dictionary, peers: Array) -> void:
	var id: String = String(consumer.get("id", ""))
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 24.0
	_consumer_preview.add_child(row)
	var name_label: Label = _label(_device_name(
		String(consumer.get("type", "device")), id, peers), 12, S.MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var watts_label: Label = _label("", 12, S.IVORY)
	watts_label.custom_minimum_size.x = 65.0
	row.add_child(watts_label)
	var status: Label = _label("", 12, S.GREEN)
	status.custom_minimum_size.x = 64.0
	row.add_child(status)
	var priority_label: Button = _pill("P3", S.BLUE)
	row.add_child(priority_label)
	_preview_rows[id] = {"watts": watts_label, "status": status, "priority": priority_label}


func _sync_devices(snapshot: Dictionary, zone: Dictionary, zones: Array) -> void:
	var generators: Array = snapshot.get("generators", []) as Array
	var batteries: Array = snapshot.get("batteries", []) as Array
	var consumers: Array = snapshot.get("consumers", []) as Array
	var shared: Array = _shared_batteries(zone, zones)
	var remote: Array = _remote_consumers(zone, zones)
	var signature: String = _ids(generators) + "|" + _ids(batteries) + "|" \
		+ _ids(shared) + "|" + _ids(consumers) + "|" + _ids(remote)
	if signature != _device_signature:
		_device_signature = signature
		_device_rows.clear()
		_clear(_generator_list)
		_clear(_battery_list)
		_clear(_device_consumer_list)
		_build_device_column(_generator_list, generators, "generator", false)
		_build_device_column(_battery_list, batteries, "battery", false)
		_build_device_column(_battery_list, shared, "battery", true)
		_build_device_column(_device_consumer_list, consumers, "consumer", false)
		_build_device_column(_device_consumer_list, remote, "consumer", true)
	_refresh_device_values(generators, batteries, shared, consumers, remote)


func _build_device_column(parent: VBoxContainer, devices: Array,
		kind: String, remote: bool) -> void:
	if devices.is_empty() and parent.get_child_count() == 0:
		parent.add_child(_empty("No %s connected" % _device_plural(kind),
			kind if kind != "consumer" else "running"))
		return
	if not devices.is_empty() and parent.get_child_count() > 0:
		var first: Node = parent.get_child(0)
		if first.name == "EmptyState":
			parent.remove_child(first)
			first.queue_free()
	for raw_device: Variant in devices:
		var device: Dictionary = raw_device as Dictionary
		var id: String = String(device.get("id", ""))
		var key: String = ("remote:" if remote else "local:") + kind + ":" + id
		var card: PanelContainer = _card(Color("1a201f"))
		card.custom_minimum_size.y = 104.0
		parent.add_child(card)
		var body: VBoxContainer = VBoxContainer.new()
		body.add_theme_constant_override("separation", 5)
		card.add_child(C.inset(body, 11, 9, 11, 9))
		var heading: HBoxContainer = HBoxContainer.new()
		body.add_child(heading)
		var shown_kind: String = String(device.get("type", "device")) if kind == "consumer" else kind
		var name_label: Label = _label(_device_name(shown_kind, id, devices), 15, S.IVORY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.add_child(name_label)
		var badge: Button = _pill("SHARED" if kind == "battery" else "REMOTE", S.BLUE)
		badge.visible = remote
		heading.add_child(badge)
		var status: Label = _label("", 13, S.GREEN)
		body.add_child(status)
		var value: Label = _label("", 13, S.MUTED)
		body.add_child(value)
		var bar: ProgressBar = _progress(S.BLUE)
		bar.visible = kind != "consumer"
		body.add_child(bar)
		_device_rows[key] = {"status": status, "value": value, "bar": bar}


func _refresh_device_values(generators: Array, batteries: Array, shared: Array,
		consumers: Array, remote: Array) -> void:
	for raw_generator: Variant in generators:
		var generator: Dictionary = raw_generator as Dictionary
		var row: Dictionary = _device_rows.get(
			"local:generator:" + String(generator.get("id", "")), {}) as Dictionary
		if row.is_empty():
			continue
		var running: bool = bool(generator.get("running", false))
		var backup: bool = bool(generator.get("is_backup", false))
		var status: Label = row.get("status") as Label
		status.text = "●  RUNNING" if running else ("●  STANDBY" if backup else "●  STOPPED")
		status.add_theme_color_override("font_color", S.GREEN if running else (S.BLUE if backup else S.MUTED))
		var fuel: float = clampf(float(generator.get("fuel", 0.0)), 0.0, 100.0)
		(row.get("value") as Label).text = "%s · Fuel %d%% · Condition %d%%" % [
			_watts(float(generator.get("watts", 0.0))), int(fuel),
			int(float(generator.get("health", 0.0)))]
		var bar: ProgressBar = row.get("bar") as ProgressBar
		SMOOTH_BAR.apply(bar, fuel)
		_progress_color(bar, S.BLUE if fuel > 15.0 else S.RED)
	_refresh_device_batteries(batteries, false)
	_refresh_device_batteries(shared, true)
	_refresh_device_consumers(consumers, false)
	_refresh_device_consumers(remote, true)


func _refresh_device_batteries(batteries: Array, remote: bool) -> void:
	for raw_battery: Variant in batteries:
		var battery: Dictionary = raw_battery as Dictionary
		var key: String = ("remote:" if remote else "local:") + "battery:" \
			+ String(battery.get("id", ""))
		var row: Dictionary = _device_rows.get(key, {}) as Dictionary
		if row.is_empty():
			continue
		var capacity: float = float(battery.get("capacity_wh", 0.0))
		var charge: float = float(battery.get("charge_wh", 0.0))
		var percent: float = 0.0 if capacity <= 0.0 else clampf(charge / capacity * 100.0, 0.0, 100.0)
		var state: String = String(battery.get("state", "IDLE"))
		var status: Label = row.get("status") as Label
		status.text = "●  " + state
		status.add_theme_color_override("font_color", _battery_color(state))
		(row.get("value") as Label).text = "%s of %s · %d%%" % [
			_wh(charge), _wh(capacity), int(percent)]
		var bar: ProgressBar = row.get("bar") as ProgressBar
		SMOOTH_BAR.apply(bar, percent)
		_progress_color(bar, S.BLUE if percent > 10.0 else S.RED)


func _refresh_device_consumers(consumers: Array, remote: bool) -> void:
	for raw_consumer: Variant in consumers:
		var consumer: Dictionary = raw_consumer as Dictionary
		var key: String = ("remote:" if remote else "local:") + "consumer:" \
			+ String(consumer.get("id", ""))
		var row: Dictionary = _device_rows.get(key, {}) as Dictionary
		if row.is_empty():
			continue
		var state: String = _consumer_state(consumer)
		var status: Label = row.get("status") as Label
		status.text = "●  " + state
		status.add_theme_color_override("font_color", _consumer_color(state))
		(row.get("value") as Label).text = "%s · Priority P%d" % [
			_watts(float(consumer.get("watts", 0.0))), int(consumer.get("priority", 3))]


func _sync_priorities(snapshot: Dictionary) -> void:
	var consumers: Array = snapshot.get("consumers", []) as Array
	var signature: String = _ids(consumers)
	_priority_count.text = "%d DEVICES" % consumers.size()
	if signature != _priority_signature:
		_priority_signature = signature
		_priority_rows.clear()
		_clear(_priority_list)
		if consumers.is_empty():
			_priority_list.add_child(_empty("No local consumers connected", "log"))
		else:
			for raw_consumer: Variant in consumers:
				_add_priority_row(raw_consumer as Dictionary, consumers)
	for raw_consumer: Variant in consumers:
		_refresh_priority_row(raw_consumer as Dictionary)


func _add_priority_row(consumer: Dictionary, peers: Array) -> void:
	var id: String = String(consumer.get("id", ""))
	var card: PanelContainer = _card(Color("1a201f"))
	card.custom_minimum_size.y = 68.0
	_priority_list.add_child(card)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(C.inset(row, 12, 8, 12, 8))
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(_label(_device_name(
		String(consumer.get("type", "device")), id, peers), 15, S.IVORY))
	var detail: Label = _label("", 12, S.MUTED)
	identity.add_child(detail)
	var state: Button = _pill("ON", S.GREEN)
	state.custom_minimum_size.x = 78.0
	row.add_child(state)
	var decrement: Button = _priority_button("−")
	decrement.tooltip_text = "Move toward critical priority"
	decrement.pressed.connect(_change_priority.bind(id, -1))
	row.add_child(decrement)
	var priority_label: Button = _pill("P3", S.BLUE)
	priority_label.custom_minimum_size = Vector2(54.0, 34.0)
	row.add_child(priority_label)
	var increment: Button = _priority_button("+")
	increment.tooltip_text = "Move toward first-shed priority"
	increment.pressed.connect(_change_priority.bind(id, 1))
	row.add_child(increment)
	_priority_rows[id] = {"detail": detail, "state": state, "decrement": decrement,
		"priority": priority_label, "increment": increment}


func _refresh_priority_row(consumer: Dictionary) -> void:
	var id: String = String(consumer.get("id", ""))
	var row: Dictionary = _priority_rows.get(id, {}) as Dictionary
	if row.is_empty():
		return
	var priority_value: int = clampi(int(consumer.get("priority", 3)), 1, 5)
	(row.get("detail") as Label).text = "%s draw" % _watts(float(consumer.get("watts", 0.0)))
	var state_name: String = _consumer_state(consumer)
	var state: Button = row.get("state") as Button
	state.text = state_name
	state.add_theme_color_override("font_color", _consumer_color(state_name))
	(row.get("priority") as Button).text = "P%d" % priority_value
	(row.get("decrement") as Button).disabled = priority_value <= 1
	(row.get("increment") as Button).disabled = priority_value >= 5


func _change_priority(consumer_id: String, delta: int) -> void:
	var pm: PowerManager = _pm()
	if pm == null:
		return
	var current: int = pm.get_consumer_priority(consumer_id)
	pm.set_consumer_priority(consumer_id, current + delta)
	var row: Dictionary = _priority_rows.get(consumer_id, {}) as Dictionary
	if not row.is_empty():
		var next_value: int = clampi(current + delta, 1, 5)
		(row.get("priority") as Button).text = "P%d" % next_value
		(row.get("decrement") as Button).disabled = next_value <= 1
		(row.get("increment") as Button).disabled = next_value >= 5


func _refresh_network(snapshot: Dictionary, zone: Dictionary, zones: Array) -> void:
	var wired: bool = not zone.is_empty()
	var state: String = _state(snapshot, zone)
	_network_state.text = "%s · %s" % [_zone_name_for(zone), state] if wired else "UNWIRED"
	_network_state.add_theme_color_override("font_color", _state_color(state))
	_network_detail.text = "This terminal's enclosed power segment and permitted cross-zone links." \
		if wired else "Wire this terminal into an enclosed zone to inspect network flow."
	_network_counts.text = "Nodes  %d\nEdges  %d\nReachable  %d\nGenerators  %d\nBatteries  %d\nConsumers  %d" % [
		int(snapshot.get("wire_node_count", 0)), int(snapshot.get("wire_edge_count", 0)),
		int(snapshot.get("reachable_node_count", 0)),
		(snapshot.get("generators", []) as Array).size(),
		(snapshot.get("batteries", []) as Array).size(),
		(snapshot.get("consumers", []) as Array).size()]
	var overloaded: bool = bool(zone.get("overloaded", false)) if wired else false
	_network_brownout.text = "⚠  Brownout edges detected" if overloaded else "●  No brownout edges"
	_network_brownout.add_theme_color_override("font_color", S.BRASS.lightened(0.32) if overloaded else S.GREEN)
	var customizable: bool = wired and not String(zone.get("zone_key", "")).is_empty()
	_network_rename.disabled = not customizable
	_network_recolor.disabled = not customizable
	_network_reset.disabled = not _reset_active(snapshot, zone)
	_network_reset.text = "Reset %s" % _zone_name_for(zone) if wired else "Reset grid"
	_sync_network_lists(zone, zones)


func _sync_network_lists(zone: Dictionary, zones: Array) -> void:
	var signature: String = str(zone.get("import_from", [])) + "|" + str(zone.get("export_to", [])) \
		+ "|" + str(zone.get("cross_consumer_ids", [])) + "|" + str(zone.get("cross_battery_ids", [])) \
		+ "|" + str(zone.get("imported_w", 0.0)) + "|" + str(zone.get("exported_w", 0.0))
	if signature == _network_signature:
		return
	_network_signature = signature
	_clear(_network_flow_list)
	_clear(_network_shared_list)
	if zone.is_empty():
		_network_flow_list.add_child(_empty("No zone flow data", "wire"))
		_network_shared_list.add_child(_empty("No shared connections", "battery"))
		return
	var import_from: Array = zone.get("import_from", []) as Array
	var export_to: Array = zone.get("export_to", []) as Array
	var imported: float = float(zone.get("imported_w", 0.0))
	var exported: float = float(zone.get("exported_w", 0.0))
	if import_from.is_empty() and export_to.is_empty():
		_network_flow_list.add_child(_empty("Single zone · No cross-zone flow", "wire"))
	else:
		for raw_index: Variant in import_from:
			var source: Dictionary = _zone_by_index(zones, int(raw_index))
			var amount: float = imported / maxf(1.0, float(import_from.size()))
			_network_flow_list.add_child(_flow_row("IMPORT", _zone_name_for(source), amount, _zone_color(source)))
		for raw_index: Variant in export_to:
			var destination: Dictionary = _zone_by_index(zones, int(raw_index))
			var amount: float = exported / maxf(1.0, float(export_to.size()))
			_network_flow_list.add_child(_flow_row("EXPORT", _zone_name_for(destination), amount, _zone_color(destination)))
	var shared: Array = _shared_batteries(zone, zones)
	var remote: Array = _remote_consumers(zone, zones)
	if shared.is_empty() and remote.is_empty():
		_network_shared_list.add_child(_empty("No shared batteries or remote consumers", "battery"))
	else:
		for raw_battery: Variant in shared:
			_network_shared_list.add_child(_connection_row("Shared battery", raw_battery as Dictionary, "battery"))
		for raw_consumer: Variant in remote:
			var consumer: Dictionary = raw_consumer as Dictionary
			_network_shared_list.add_child(_connection_row(
				"Remote consumer", consumer, String(consumer.get("type", "device"))))


func _shared_batteries(zone: Dictionary, zones: Array) -> Array:
	if zone.is_empty():
		return []
	var ids: Dictionary = _id_set(zone.get("cross_battery_ids", []) as Array)
	var pm: PowerManager = _pm()
	if ids.is_empty() or pm == null:
		return []
	var all_batteries: Array = pm.get_debug_snapshot().get("batteries", []) as Array
	var result: Array = _filter(all_batteries, ids)
	for raw_battery: Variant in result:
		var battery: Dictionary = raw_battery as Dictionary
		battery["_source_zone"] = _device_zone_name(
			String(battery.get("id", "")), zones, "battery_ids")
	return result


func _remote_consumers(zone: Dictionary, zones: Array) -> Array:
	if zone.is_empty():
		return []
	var ids: Dictionary = _id_set(zone.get("cross_consumer_ids", []) as Array)
	var pm: PowerManager = _pm()
	if ids.is_empty() or pm == null:
		return []
	var all_consumers: Array = pm.get_debug_snapshot().get("consumers", []) as Array
	var result: Array = _filter(all_consumers, ids)
	for raw_consumer: Variant in result:
		var consumer: Dictionary = raw_consumer as Dictionary
		consumer["_source_zone"] = _device_zone_name(
			String(consumer.get("id", "")), zones, "consumer_ids")
	return result


func _device_zone_name(device_id: String, zones: Array, field: String) -> String:
	for raw_zone: Variant in zones:
		var zone: Dictionary = raw_zone as Dictionary
		var ids: Array = zone.get(field, []) as Array
		if ids.has(device_id):
			return _zone_name_for(zone)
	return "Other zone"


func _flow_row(direction: String, zone_label: String, amount: float,
		color: Color) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	card.custom_minimum_size.y = 64.0
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(C.inset(row, 11, 8, 11, 8))
	var swatch: ColorRect = ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(8.0, 42.0)
	row.add_child(swatch)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(_label(direction, 12,
		S.BLUE if direction == "IMPORT" else S.BRASS.lightened(0.35)))
	identity.add_child(_label(zone_label, 15, S.IVORY))
	row.add_child(_label(_watts(amount), 18, S.IVORY))
	return card


func _connection_row(copy: String, device: Dictionary, kind: String) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	card.custom_minimum_size.y = 66.0
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(C.inset(row, 11, 8, 11, 8))
	row.add_child(C.icon_well("battery" if kind == "battery" else "running", 42.0, S.BLUE))
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(_label(_device_name(kind), 14, S.IVORY))
	identity.add_child(_label("%s · %s" % [copy,
		String(device.get("_source_zone", "Other zone"))], 12, S.MUTED))
	return card


func _reset_power() -> void:
	var pm: PowerManager = _pm()
	if pm == null:
		return
	if connected_zone_index >= 0:
		pm.reset_zone_by_index(connected_zone_index)
	else:
		pm.reset_main_breaker()
	_refresh_interface()


func _reset_active(snapshot: Dictionary, zone: Dictionary) -> bool:
	if not zone.is_empty():
		var state_name: String = String(zone.get("state_str", "ONLINE"))
		return state_name == "OFFLINE" or state_name == "OVERLOADED"
	return int(snapshot.get("grid_state", 0)) == 3


func _ensure_zone_customize_ui() -> CanvasLayer:
	if _zone_customize_ui != null and is_instance_valid(_zone_customize_ui):
		return _zone_customize_ui
	var script: GDScript = load("res://scripts/ui/power/ZoneCustomizeModernUI.gd") as GDScript
	if script == null:
		push_warning("[PowerTerminalModernUI] ZoneCustomizeModernUI.gd not found")
		return null
	_zone_customize_ui = CanvasLayer.new()
	_zone_customize_ui.set_script(script)
	_zone_customize_ui.name = "ZoneCustomizeUI"
	get_tree().get_root().add_child(_zone_customize_ui)
	if _zone_customize_ui.has_signal("name_changed"):
		_zone_customize_ui.name_changed.connect(_on_zone_name_changed)
	if _zone_customize_ui.has_signal("color_changed"):
		_zone_customize_ui.color_changed.connect(_on_zone_color_changed)
	return _zone_customize_ui


func _open_zone_rename() -> void:
	var pm: PowerManager = _pm()
	if pm == null:
		return
	var key: String = _current_zone_key(pm)
	if key.is_empty():
		return
	var ui: CanvasLayer = _ensure_zone_customize_ui()
	if ui != null:
		ui.call("open_rename", key,
			pm.get_zone_display_name(key, "Z%d" % connected_zone_index))


func _open_zone_color_picker() -> void:
	var pm: PowerManager = _pm()
	if pm == null:
		return
	var key: String = _current_zone_key(pm)
	if key.is_empty():
		return
	var color_index: int = 0
	for raw_zone: Variant in pm.get_zone_snapshot():
		var zone: Dictionary = raw_zone as Dictionary
		if int(zone.get("zone_index", -1)) == connected_zone_index:
			color_index = int(zone.get("color_index", 0))
			break
	var ui: CanvasLayer = _ensure_zone_customize_ui()
	if ui != null:
		ui.call("open_color", key, pm.zone_display_color(key, color_index, 1.0))


func _current_zone_key(pm: PowerManager) -> String:
	if connected_zone_index < 0:
		return ""
	for raw_zone: Variant in pm.get_zone_snapshot():
		var zone: Dictionary = raw_zone as Dictionary
		if int(zone.get("zone_index", -1)) == connected_zone_index:
			return String(zone.get("zone_key", ""))
	return ""


func _on_zone_name_changed(zone_key: String, new_name: String) -> void:
	var pm: PowerManager = _pm()
	if pm != null:
		pm.set_zone_name(zone_key, new_name)
	_network_signature = ""
	_refresh_interface()


func _on_zone_color_changed(zone_key: String, new_color: Color) -> void:
	var pm: PowerManager = _pm()
	if pm != null:
		pm.set_zone_color_override(zone_key, new_color)
	_network_signature = ""
	_refresh_interface()


func _update_input_hint() -> void:
	_controller_hints = InputMode.is_controller()
	_footer.text = "[A] Select     D-pad / R-stick  Navigate     Scrollbar  Scroll     [B] Close" \
		if _controller_hints else "Enter / Space  Select     Arrows  Navigate     Scrollbar / Wheel  Scroll     Esc / E  Close"


func _reset_scrolls(root: Node) -> void:
	for node: Node in root.find_children("*", "ScrollContainer", true, false):
		(node as ScrollContainer).set_deferred("scroll_vertical", 0)


func _card(background: Color = Color("171d1c")) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", C.panel_box(
		background, S.BRASS.darkened(0.40), 7, 1))
	return card


func _label(text_value: String, size: int, color: Color) -> Label:
	var result: Label = Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _heading(text_value: String, icon: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var texture: TextureRect = TextureRect.new()
	texture.texture = S.icon(icon)
	texture.self_modulate = S.MUTED
	texture.custom_minimum_size = Vector2(18.0, 18.0)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(texture)
	var copy: Label = _label(text_value, 13, S.IVORY)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	return row


func _progress(fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 9.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", C.panel_box(S.SURFACE_ALT, S.SURFACE_ALT, 4, 0))
	_progress_color(bar, fill_color)
	return bar


func _progress_color(bar: ProgressBar, color: Color) -> void:
	bar.add_theme_stylebox_override("fill", C.panel_box(color, color, 4, 0))


func _scroll() -> ScrollContainer:
	var result: ScrollContainer = ScrollContainer.new()
	result.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	result.follow_focus = true
	return result


func _legend(text_value: String, color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var line: ColorRect = ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(34.0, 3.0)
	row.add_child(line)
	row.add_child(_label(text_value, 11, S.MUTED))
	return row


func _action(text_value: String, icon: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.icon = S.icon(icon)
	S.button(button)
	button.custom_minimum_size.y = 38.0
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_constant_override("icon_max_width", 20)
	return button


func _priority_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(42.0, 38.0)
	S.button(button)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _pill(text_value: String, color: Color) -> Button:
	var result: Button = Button.new()
	result.text = text_value
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", 12)
	result.add_theme_color_override("font_color", color)
	result.alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.custom_minimum_size = Vector2(44.0, 24.0)
	var style: StyleBoxFlat = C.panel_box(
		S.BG.lerp(color, 0.10), S.BG.lerp(color, 0.48), 5, 1, 5)
	result.add_theme_stylebox_override("normal", style)
	result.add_theme_stylebox_override("hover", style)
	result.add_theme_stylebox_override("pressed", style)
	result.add_theme_stylebox_override("focus", style)
	return result


func _status_line(text_value: String, color: Color) -> Label:
	var result: Label = _label(text_value, 12, color)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.custom_minimum_size.y = 24.0
	result.add_theme_stylebox_override("normal", C.panel_box(
		S.SURFACE.darkened(0.04), S.SURFACE_ALT, 5, 0, 6))
	return result


func _empty(text_value: String, icon: String) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	card.name = "EmptyState"
	card.custom_minimum_size.y = 62.0
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(C.inset(row, 12, 9, 12, 9))
	var texture: TextureRect = TextureRect.new()
	texture.texture = S.icon(icon)
	texture.self_modulate = S.MUTED.darkened(0.25)
	texture.custom_minimum_size = Vector2(30.0, 30.0)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(texture)
	var copy: Label = _label(text_value, 13, S.MUTED.darkened(0.15))
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	return card


func _priority_guide(title_text: String, detail_text: String,
		priority_value: int) -> PanelContainer:
	var card: PanelContainer = _card(Color("1a201f"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(C.inset(row, 10, 7, 10, 7))
	var color: Color = S.BLUE if priority_value <= 2 else (
		S.BRASS.lightened(0.25) if priority_value <= 4 else S.RED)
	row.add_child(_pill("P%d" % priority_value, color))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(_label(title_text, 13, S.IVORY))
	copy.add_child(_label(detail_text, 11, S.MUTED))
	return card


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _ids(devices: Array) -> String:
	var values: Array[String] = []
	for raw_device: Variant in devices:
		var device: Dictionary = raw_device as Dictionary
		values.append(String(device.get("id", "")))
	values.sort()
	return ",".join(values)


func _device_name(kind: String, id: String = "", peers: Array = []) -> String:
	var cleaned: String = kind.strip_edges().replace("_", " ").replace("-", " ")
	if cleaned.is_empty() or cleaned == "unknown" or cleaned == "consumer":
		cleaned = "device"
	var words: PackedStringArray = cleaned.split(" ", false)
	for index: int in range(words.size()):
		words[index] = words[index].capitalize()
	var result: String = " ".join(words)
	if result == "Terminal":
		result = "Power Terminal"
	if id.is_empty() or peers.size() <= 1:
		return result
	var same_kind_ids: Array[String] = []
	for raw_peer: Variant in peers:
		var peer: Dictionary = raw_peer as Dictionary
		var peer_kind: String = String(peer.get("type", kind))
		if peer_kind == kind or (kind == "battery" and not peer.has("type")) \
				or (kind == "generator" and not peer.has("type")):
			same_kind_ids.append(String(peer.get("id", "")))
	same_kind_ids.sort()
	var ordinal: int = same_kind_ids.find(id)
	return "%s %02d" % [result, ordinal + 1] if ordinal >= 0 else result


func _device_plural(kind: String) -> String:
	match kind:
		"battery": return "batteries"
		"generator": return "generators"
		"consumer": return "consumers"
		_: return "devices"


func _watts(value: float) -> String:
	var sign_value: String = "-" if value < 0.0 else ""
	var magnitude: float = absf(value)
	if magnitude >= 10000.0:
		return "%s%.1f kW" % [sign_value, magnitude / 1000.0]
	return "%s%d W" % [sign_value, int(round(magnitude))]


func _wh(value: float) -> String:
	if absf(value) >= 1000.0:
		return "%.1f kWh" % (value / 1000.0)
	return "%d Wh" % int(round(value))


func _state(snapshot: Dictionary, zone: Dictionary) -> String:
	return String(zone.get("state_str", "ONLINE")) if not zone.is_empty() \
		else String(snapshot.get("grid_state_str", "UNKNOWN"))


func _state_color(state_name: String) -> Color:
	match state_name.to_upper():
		"ONLINE": return S.GREEN
		"OVERLOADED", "BROWNOUT": return S.BRASS.lightened(0.35)
		"TRIPPED", "OFFLINE": return S.RED
		_: return S.MUTED


func _battery_color(state_name: String) -> Color:
	match state_name.to_upper():
		"CHARGING": return S.GREEN
		"DISCHARGING": return S.BLUE
		"DRAINED": return S.RED
		_: return S.MUTED


func _consumer_state(consumer: Dictionary) -> String:
	if bool(consumer.get("shed", false)):
		return "SHED"
	return "ON" if bool(consumer.get("powered", false)) else "OFF"


func _consumer_color(state_name: String) -> Color:
	match state_name:
		"ON": return S.GREEN
		"SHED": return S.BRASS.lightened(0.35)
		_: return S.RED


func _zone_name_for(zone: Dictionary) -> String:
	if zone.is_empty():
		return "Grid"
	var fallback: String = "Z%d" % int(zone.get("zone_index", connected_zone_index))
	return String(zone.get("zone_name", fallback))


func _zone_color(zone: Dictionary) -> Color:
	if zone.is_empty():
		return S.BLUE
	var pm: PowerManager = _pm()
	var key: String = String(zone.get("zone_key", ""))
	var index: int = int(zone.get("color_index", 0))
	return pm.zone_display_color(key, index, 1.0) if pm != null else S.BLUE


func _zone_by_index(zones: Array, index: int) -> Dictionary:
	for raw_zone: Variant in zones:
		var zone: Dictionary = raw_zone as Dictionary
		if int(zone.get("zone_index", -1)) == index:
			return zone
	return {}


func _flow_summary(zone: Dictionary) -> String:
	if zone.is_empty():
		return "Terminal is not assigned to a wire zone"
	var imported: float = float(zone.get("imported_w", 0.0))
	var exported: float = float(zone.get("exported_w", 0.0))
	if imported > 0.0 and exported > 0.0:
		return "Import %s · Export %s" % [_watts(imported), _watts(exported)]
	if imported > 0.0:
		return "Importing %s from neighboring zones" % _watts(imported)
	if exported > 0.0:
		return "Exporting %s to neighboring zones" % _watts(exported)
	return "Single zone · No cross-zone flow"


func _zone_by_device(device_id: String, zones: Array, field: String) -> Dictionary:
	for raw_zone: Variant in zones:
		var zone: Dictionary = raw_zone as Dictionary
		if (zone.get(field, []) as Array).has(device_id):
			return zone
	return {}


func _pm() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager
