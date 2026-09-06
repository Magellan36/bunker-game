extends CanvasLayer
class_name NPCTalkMenuUI
## Resident profile, conversation, command, health, and history workspace.
## The presentation is built once and reused. Gameplay ownership remains in
## NPC/NPCBrain/NPCMedical; this UI only reads their data and invokes the same
## established command methods the previous talk menu used.

signal closed

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const NAV: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PROXIMITY: GDScript = preload("res://scripts/ui/common/UIProximityClose.gd")
const PORTRAIT: GDScript = preload("res://scripts/ui/npc/NPCPortraitViewport.gd")
const RELATIONSHIP_METER: GDScript = preload("res://scripts/ui/npc/NPCRelationshipMeter.gd")
const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")

const PANEL_MAX: Vector2 = Vector2(1420.0, 820.0)
const SCREEN_MARGIN: Vector2 = Vector2(42.0, 34.0)
const LEFT_COLUMN_WIDTH: float = 356.0
const REFRESH_INTERVAL: float = 0.25

const HEALTH_COLOR: Color = Color("ef5f64")
const ENERGY_COLOR: Color = Color("e5a24a")
const FOOD_COLOR: Color = Color("d9aa63")
const WATER_COLOR: Color = Color("62bfff")
const MOOD_COLOR: Color = Color("75d48a")

enum ResidentTab { OVERVIEW, TALK, REQUESTS, HEALTH, ACTIVITY_LOG }

const MEDICAL_BODY_PARTS: Array[int] = [
	MedicalCondition.BodyPart.HEAD,
	MedicalCondition.BodyPart.TORSO,
	MedicalCondition.BodyPart.LEFT_ARM,
	MedicalCondition.BodyPart.RIGHT_ARM,
	MedicalCondition.BodyPart.LEFT_LEG,
	MedicalCondition.BodyPart.RIGHT_LEG,
]

## These strings and dispatch targets deliberately match the previous menu.
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "REPLACE_FILTER", "label": "Replace water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing", "icon": "water"},
	{"type": "REFUEL", "label": "Refuel generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling", "icon": "fuel"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now", "icon": "storage"},
	{"type": "FARMING", "label": "Tend the farm", "action_desc": "heading to tend the farm", "empty_desc": "nothing to harvest, plant, or add soil to right now", "icon": "plant"},
	{"type": "FERTILIZE", "label": "Fertilize trays", "action_desc": "heading to fertilize", "empty_desc": "nothing needs fertilizing, or none available", "icon": "plant"},
	{"type": "COOKING", "label": "Cook a meal", "action_desc": "heading to cook", "empty_desc": "nothing to cook right now", "icon": "cooking"},
]

const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN": "nothing to clean right now",
	"NO_TRASH_RECEPTACLE": "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING": "everything's still settling — check back shortly",
	"ALL_CLAIMED": "everything's already being handled by someone else",
	"NO_LIGHT_STORAGE_AVAILABLE": "there's nothing to put light items away in",
	"NO_HEAVY_STORAGE_AVAILABLE": "there's nothing to put heavy items away in",
	"STORAGE_FULL": "storage is full",
}
const REFUEL_UNAVAILABLE_REASONS: Dictionary = {
	"ALL_GENERATORS_FULL": "every generator is already full",
	"FUEL_CAN_CLAIMED": "the only fuel can is already being used",
	"NO_FUEL_CAN": "there's no fuel can anywhere to refuel with",
}
const COOKING_UNAVAILABLE_REASONS: Dictionary = {
	"NO_STOVE": "there's no stove built yet",
}

var _npc: Node = null
var _is_open: bool = false
var _active_tab: int = ResidentTab.OVERVIEW
var _refresh_elapsed: float = 0.0
var _previous_focus: WeakRef = null
var _medical_signature: String = ""
var _selected_medical_part: int = -1

var _root: Control = null
var _panel: PanelContainer = null
var _controller_nav: ControllerUINavigation = null
var _proximity: Node = null

var _name_label: Label = null
var _identity_line: Label = null
var _header_state_panel: PanelContainer = null
var _header_state_icon: TextureRect = null
var _header_state_label: Label = null
var _header_relationship_panel: PanelContainer = null
var _header_relationship_label: Label = null

var _portrait: NPCPortraitViewport = null
var _relationship_label: Label = null
var _relationship_value: Label = null
var _relationship_meter: NPCRelationshipMeter = null
var _trait_row: HFlowContainer = null

var _need_bars: Dictionary = {}
var _need_values: Dictionary = {}

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _scrolls: Array[ScrollContainer] = []

var _activity_icon: TextureRect = null
var _activity_title: Label = null
var _activity_detail: Label = null
var _activity_state_panel: PanelContainer = null
var _activity_state_label: Label = null
var _skill_bars: Dictionary = {}
var _skill_values: Dictionary = {}
var _overview_medical_value: Label = null
var _overview_irritability_value: Label = null
var _overview_last_action_value: Label = null
var _talk_to_button: Button = null

var _dialogue_label: Label = null
var _talk_topics_box: VBoxContainer = null
var _request_feedback_panel: PanelContainer = null
var _request_feedback_label: Label = null
var _job_buttons: Array[Button] = []

var _health_summary_label: Label = null
var _health_reason_panel: PanelContainer = null
var _health_reason_label: Label = null
var _medical_parts_box: VBoxContainer = null
var _medical_conditions_box: VBoxContainer = null
var _medical_part_buttons: Dictionary = {}

var _log_current_activity: Label = null
var _log_rows_box: VBoxContainer = null
var _log_entries: Array[Dictionary] = []
var _log_time_labels: Array[Label] = []
var _log_text_labels: Array[Label] = []
var _footer_hint: Label = null


func _ready() -> void:
	layer = 145
	visible = false
	set_process(false)
	_build_interface()
	_controller_nav = NAV.new() as ControllerUINavigation
	_controller_nav.ui_root = self
	_controller_nav.stick_navigation = false
	_controller_nav.right_stick_navigation = true
	add_child(_controller_nav)
	_proximity = PROXIMITY.new()
	_proximity.ui = self
	add_child(_proximity)
	get_viewport().size_changed.connect(_layout)
	_layout()


func open(npc_name: String, npc: Node = null) -> void:
	_disconnect_npc_signals()
	_npc = npc
	if _npc == null or not is_instance_valid(_npc):
		return
	if not _is_open:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		_previous_focus = weakref(focus_owner) if focus_owner != null else null
	_is_open = true
	visible = true
	set_process(true)
	_refresh_elapsed = REFRESH_INTERVAL
	_medical_signature = ""
	_selected_medical_part = -1
	_name_label.text = npc_name
	_connect_npc_signals()
	if _npc is Node3D:
		_proximity.bind_target(_npc as Node3D)
	else:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			_proximity.bind_position(player.global_position)
	_portrait.show_npc(_npc)
	_rebuild_traits()
	_rebuild_talk_topics()
	_request_feedback_panel.visible = false
	_rebuild_health(true)
	_rebuild_log_rows()
	_set_tab(ResidentTab.OVERVIEW, false)
	_refresh_live_values()
	_reset_scrolls()
	_update_footer()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not is_in_group("npc_talk_ui"):
		add_to_group("npc_talk_ui")
	UIFade.fade_in(_panel)
	if not _tab_buttons.is_empty():
		_tab_buttons[ResidentTab.OVERVIEW].call_deferred("grab_focus")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	set_process(false)
	_disconnect_npc_signals()
	_proximity.unbind()
	_portrait.clear_npc()
	remove_from_group("npc_talk_ui")
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()
	if _previous_focus != null:
		var previous: Variant = _previous_focus.get_ref()
		if previous is Control and is_instance_valid(previous as Control) \
				and (previous as Control).is_visible_in_tree():
			(previous as Control).grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_npc = null
	closed.emit()


func is_open() -> bool:
	return _is_open


func _process(delta: float) -> void:
	if not _is_open:
		return
	if _npc == null or not is_instance_valid(_npc):
		close()
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_refresh_live_values()
		var signature: String = _medical_state_signature()
		if signature != _medical_signature:
			_rebuild_health(false)
	_refresh_log_timestamps()
	_update_footer()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not _controller_nav._is_topmost():
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
	_root = Control.new()
	_root.name = "ResidentProfileRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	C.apply_theme(_root)
	add_child(_root)

	var backdrop: ColorRect = UIKit.build_modal_backdrop(0.34)
	_root.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "ResidentProfilePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	C.shell(_panel, 12)
	_root.add_child(_panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	_panel.add_child(C.inset(content, 18, 15, 18, 11))
	_build_header(content)
	C.divider(content)
	_build_tabs(content)
	_build_body(content)
	C.divider(content)
	_footer_hint = _label("", 12, S.MUTED)
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_hint.custom_minimum_size.y = 22.0
	content.add_child(_footer_hint)


func _build_header(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(C.icon_well("status", 52.0, S.BLUE))

	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	row.add_child(titles)
	titles.add_child(_label("BUNKER  •  RESIDENT PROFILE", 11, S.BLUE))
	_name_label = _label("Resident", 29, S.IVORY)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_name_label)
	_identity_line = _label("Age —  •  Idle", 12, S.MUTED)
	_identity_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_identity_line)

	_header_state_panel = PanelContainer.new()
	_header_state_panel.custom_minimum_size = Vector2(136.0, 40.0)
	row.add_child(_header_state_panel)
	var state_row: HBoxContainer = HBoxContainer.new()
	state_row.alignment = BoxContainer.ALIGNMENT_CENTER
	state_row.add_theme_constant_override("separation", 7)
	_header_state_panel.add_child(C.inset(state_row, 10, 7, 10, 7))
	_header_state_icon = _icon("running", 17.0, S.GREEN)
	state_row.add_child(_header_state_icon)
	_header_state_label = _label("ON DUTY", 12, S.GREEN)
	state_row.add_child(_header_state_label)

	_header_relationship_panel = PanelContainer.new()
	_header_relationship_panel.custom_minimum_size = Vector2(176.0, 40.0)
	row.add_child(_header_relationship_panel)
	var relationship_row: HBoxContainer = HBoxContainer.new()
	relationship_row.alignment = BoxContainer.ALIGNMENT_CENTER
	relationship_row.add_theme_constant_override("separation", 7)
	_header_relationship_panel.add_child(C.inset(relationship_row, 10, 7, 10, 7))
	relationship_row.add_child(_icon("relationship", 18.0, S.GREEN))
	_header_relationship_label = _label("NEUTRAL  +0", 12, S.GREEN)
	relationship_row.add_child(_header_relationship_label)

	var close_button: Button = Button.new()
	close_button.custom_minimum_size = Vector2(48.0, 48.0)
	close_button.tooltip_text = "Close resident profile"
	S.icon_button(close_button, "close")
	close_button.text = ""
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _build_tabs(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ResidentTabs"
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var labels: Array[String] = ["OVERVIEW", "TALK", "REQUESTS", "HEALTH", "ACTIVITY LOG"]
	var icons: Array[String] = ["overview", "talk", "requests", "health", "log"]
	for index: int in range(labels.size()):
		var button: Button = Button.new()
		button.text = labels[index]
		button.icon = S.icon(icons[index])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		C.style_segment(button)
		button.pressed.connect(_set_tab.bind(index, true))
		row.add_child(button)
		_tab_buttons.append(button)


func _build_body(parent: Container) -> void:
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "ResidentBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	parent.add_child(body)
	_build_identity_column(body)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	body.add_child(right)
	_build_needs_strip(right)
	_build_pages(right)


func _build_identity_column(parent: Container) -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = LEFT_COLUMN_WIDTH
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)

	var portrait_card: PanelContainer = _card(Color("101919"), S.BRASS.darkened(0.32), 9)
	portrait_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(portrait_card)
	var portrait_box: VBoxContainer = VBoxContainer.new()
	portrait_box.add_theme_constant_override("separation", 4)
	portrait_card.add_child(C.inset(portrait_box, 8, 7, 8, 8))
	portrait_box.add_child(_label("LIVE RESIDENT VIEW", 10, S.MUTED))
	_portrait = PORTRAIT.new() as NPCPortraitViewport
	_portrait.custom_minimum_size = Vector2(330.0, 328.0)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_box.add_child(_portrait)

	var relationship_card: PanelContainer = _card(Color("141b1a"), S.BRASS.darkened(0.3), 8)
	column.add_child(relationship_card)
	var relationship_box: VBoxContainer = VBoxContainer.new()
	relationship_box.add_theme_constant_override("separation", 5)
	relationship_card.add_child(C.inset(relationship_box, 11, 8, 11, 9))
	var relationship_title: HBoxContainer = HBoxContainer.new()
	relationship_box.add_child(relationship_title)
	var title: Label = _label("YOUR RELATIONSHIP", 11, S.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relationship_title.add_child(title)
	_relationship_label = _label("Neutral", 12, S.IVORY)
	_relationship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	relationship_title.add_child(_relationship_label)
	_relationship_meter = RELATIONSHIP_METER.new() as NPCRelationshipMeter
	relationship_box.add_child(_relationship_meter)
	var scale_row: HBoxContainer = HBoxContainer.new()
	relationship_box.add_child(scale_row)
	var hostile: Label = _label("-100  Hostile", 10, S.MUTED)
	hostile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(hostile)
	_relationship_value = _label("+0", 11, S.IVORY)
	_relationship_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_row.add_child(_relationship_value)
	var close_label: Label = _label("Close  +100", 10, S.MUTED)
	close_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(close_label)
	_trait_row = HFlowContainer.new()
	_trait_row.add_theme_constant_override("h_separation", 5)
	_trait_row.add_theme_constant_override("v_separation", 5)
	relationship_box.add_child(_trait_row)


func _build_needs_strip(parent: Container) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ResidentNeeds"
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var entries: Array[Dictionary] = [
		{"key": "Health", "icon": "health", "color": HEALTH_COLOR},
		{"key": "Energy", "icon": "power", "color": ENERGY_COLOR},
		{"key": "Food", "icon": "food", "color": FOOD_COLOR},
		{"key": "Water", "icon": "water", "color": WATER_COLOR},
		{"key": "Mood", "icon": "mood", "color": MOOD_COLOR},
	]
	for entry: Dictionary in entries:
		var key: String = String(entry["key"])
		var color: Color = entry["color"] as Color
		var card: PanelContainer = _card(Color("151c1b"), S.BRASS.darkened(0.4), 7)
		card.custom_minimum_size.y = 78.0
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var card_row: HBoxContainer = HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 8)
		card.add_child(C.inset(card_row, 8, 7, 8, 7))
		card_row.add_child(_icon(String(entry["icon"]), 27.0, color))
		var copy: VBoxContainer = VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 3)
		card_row.add_child(copy)
		copy.add_child(_label(key.to_upper(), 10, S.MUTED))
		var value_label: Label = _label("100 / 100", 13, S.IVORY)
		copy.add_child(value_label)
		var bar: ProgressBar = _progress(color, 6.0)
		copy.add_child(bar)
		_need_values[key] = value_label
		_need_bars[key] = bar


func _build_pages(parent: Container) -> void:
	var stack: Control = Control.new()
	stack.name = "ResidentPages"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(stack)

	var overview_data: Dictionary = _make_page(stack, "OverviewPage")
	_build_overview(overview_data["content"] as VBoxContainer)
	var talk_data: Dictionary = _make_page(stack, "TalkPage")
	_build_talk(talk_data["content"] as VBoxContainer)
	var requests_data: Dictionary = _make_page(stack, "RequestsPage")
	_build_requests(requests_data["content"] as VBoxContainer)
	var health_data: Dictionary = _make_page(stack, "HealthPage")
	_build_health(health_data["content"] as VBoxContainer)
	var log_data: Dictionary = _make_page(stack, "ActivityLogPage")
	_build_activity_log(log_data["content"] as VBoxContainer)
	_set_tab(ResidentTab.OVERVIEW, false)


func _make_page(parent: Control, page_name: String) -> Dictionary:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = page_name
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	var inset: MarginContainer = C.inset(content, 2, 2, 9, 4)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	_pages.append(scroll)
	_scrolls.append(scroll)
	return {"scroll": scroll, "content": content}


func _build_overview(parent: VBoxContainer) -> void:
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 9)
	parent.add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	_build_activity_card(left)
	_build_skills_card(left)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.9
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	_build_at_a_glance(right)
	_talk_to_button = Button.new()
	_talk_to_button.text = "Talk to resident"
	_talk_to_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	S.icon_button(_talk_to_button, "talk", true)
	_talk_to_button.custom_minimum_size.y = 55.0
	_talk_to_button.pressed.connect(_open_talk_tab)
	right.add_child(_talk_to_button)


func _build_activity_card(parent: Container) -> void:
	var card: PanelContainer = _card(Color("131a19"), S.BRASS.darkened(0.35), 8)
	card.custom_minimum_size.y = 155.0
	parent.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	card.add_child(C.inset(box, 12, 9, 12, 10))
	C.section_header(box, "CURRENT ACTIVITY", "LIVE")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	box.add_child(row)
	_activity_icon = _icon("clock", 34.0, S.IVORY)
	row.add_child(_activity_icon)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	_activity_title = _label("Idle", 17, S.IVORY)
	copy.add_child(_activity_title)
	_activity_detail = _label("Live behavior • Updates automatically", 11, S.MUTED)
	copy.add_child(_activity_detail)
	_activity_state_panel = PanelContainer.new()
	_activity_state_panel.custom_minimum_size = Vector2(96.0, 30.0)
	row.add_child(_activity_state_panel)
	_activity_state_label = _label("IDLE", 11, S.MUTED)
	_activity_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_activity_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_activity_state_panel.add_child(_activity_state_label)
	var explanation: Label = _label(
		"The resident's current behavior is shown exactly as the simulation reports it.",
		11, S.MUTED
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(explanation)


func _build_skills_card(parent: Container) -> void:
	var card: PanelContainer = _card(Color("131a19"), S.BRASS.darkened(0.35), 8)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	card.add_child(C.inset(box, 12, 9, 12, 9))
	C.section_header(box, "SKILLS", "20 MAX")
	var icons: Dictionary = {
		"farming": "plant",
		"plumbing": "water",
		"electrical": "power",
		"construction": "build",
	}
	for skill: String in ["farming", "plumbing", "electrical", "construction"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		row.add_child(_icon(String(icons[skill]), 21.0, S.IVORY))
		var name_label: Label = _label(skill.capitalize(), 12, S.MUTED)
		name_label.custom_minimum_size.x = 86.0
		row.add_child(name_label)
		var bar: ProgressBar = _progress(S.BLUE, 7.0)
		bar.max_value = 20.0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var value_label: Label = _label("10", 12, S.IVORY)
		value_label.custom_minimum_size.x = 24.0
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_skill_bars[skill] = bar
		_skill_values[skill] = value_label


func _build_at_a_glance(parent: Container) -> void:
	var card: PanelContainer = _card(Color("131a19"), S.BRASS.darkened(0.35), 8)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(C.inset(box, 12, 9, 12, 9))
	C.section_header(box, "AT A GLANCE")
	_overview_medical_value = _build_fact_row(box, "medical", "Medical status", "No active conditions")
	box.add_child(HSeparator.new())
	_overview_irritability_value = _build_fact_row(box, "mood", "Irritability", "Calm")
	box.add_child(HSeparator.new())
	_overview_last_action_value = _build_fact_row(box, "clock", "Last notable action", "Nothing notable yet")


func _build_fact_row(parent: Container, symbol: String, title_text: String, value_text: String) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 67.0
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	row.add_child(_icon(symbol, 23.0, S.IVORY))
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	copy.add_child(_label(title_text, 11, S.MUTED))
	var value_label: Label = _label(value_text, 12, S.IVORY)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.max_lines_visible = 2
	copy.add_child(value_label)
	return value_label


func _build_talk(parent: VBoxContainer) -> void:
	C.section_header(parent, "CONVERSATION", "RELATIONSHIPS")
	var dialogue_card: PanelContainer = _card(Color("132025"), S.BLUE.darkened(0.45), 8)
	parent.add_child(dialogue_card)
	var dialogue_row: HBoxContainer = HBoxContainer.new()
	dialogue_row.add_theme_constant_override("separation", 11)
	dialogue_card.add_child(C.inset(dialogue_row, 13, 11, 13, 11))
	dialogue_row.add_child(_icon("talk", 30.0, S.BLUE))
	var dialogue_copy: VBoxContainer = VBoxContainer.new()
	dialogue_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_copy.add_theme_constant_override("separation", 5)
	dialogue_row.add_child(dialogue_copy)
	_dialogue_label = _label("Select Talk to begin a conversation.", 15, S.IVORY)
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.custom_minimum_size.y = 54.0
	dialogue_copy.add_child(_dialogue_label)
	var talk_again: Button = Button.new()
	talk_again.text = "Talk again"
	talk_again.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	S.icon_button(talk_again, "talk")
	talk_again.custom_minimum_size.x = 170.0
	talk_again.pressed.connect(_refresh_dialogue)
	dialogue_row.add_child(talk_again)
	C.section_header(parent, "ASK ABOUT", "CURRENT RESIDENTS")
	_talk_topics_box = VBoxContainer.new()
	_talk_topics_box.add_theme_constant_override("separation", 6)
	parent.add_child(_talk_topics_box)


func _build_requests(parent: VBoxContainer) -> void:
	C.section_header(parent, "QUICK REQUESTS", "DIRECT COMMANDS")
	var quick_row: HBoxContainer = HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 7)
	parent.add_child(quick_row)
	quick_row.add_child(_request_button("Find food", "food", _on_command_eat_pressed))
	quick_row.add_child(_request_button("Get water", "water", _on_command_drink_pressed))
	quick_row.add_child(_request_button("Take a rest", "sleep", _on_command_rest_pressed))

	_request_feedback_panel = _card(Color("17231f"), S.GREEN.darkened(0.35), 7)
	_request_feedback_panel.visible = false
	parent.add_child(_request_feedback_panel)
	_request_feedback_label = _label("", 12, S.IVORY)
	_request_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_request_feedback_panel.add_child(C.inset(_request_feedback_label, 10, 8, 10, 8))

	C.section_header(parent, "WORK ORDERS", "ASSIGN ONE JOB")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	parent.add_child(grid)
	for entry: Dictionary in NPC_JOB_MENU_ENTRIES:
		var button: Button = Button.new()
		button.text = String(entry["label"])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, 54.0)
		S.icon_button(button, String(entry["icon"]))
		button.pressed.connect(_on_job_command_pressed.bind(String(entry["type"])))
		grid.add_child(button)
		_job_buttons.append(button)


func _request_button(text_value: String, symbol: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 52.0
	S.icon_button(button, symbol)
	button.pressed.connect(callback)
	return button


func _build_health(parent: VBoxContainer) -> void:
	var summary_card: PanelContainer = _card(Color("141b1a"), S.BRASS.darkened(0.35), 8)
	parent.add_child(summary_card)
	var summary_row: HBoxContainer = HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 10)
	summary_card.add_child(C.inset(summary_row, 12, 9, 12, 9))
	summary_row.add_child(_icon("health", 28.0, HEALTH_COLOR))
	_health_summary_label = _label("No active conditions", 14, S.IVORY)
	_health_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_row.add_child(_health_summary_label)

	_health_reason_panel = _card(Color("32231b"), ENERGY_COLOR.darkened(0.35), 7)
	_health_reason_panel.visible = false
	parent.add_child(_health_reason_panel)
	_health_reason_label = _label("", 12, ENERGY_COLOR)
	_health_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_health_reason_panel.add_child(C.inset(_health_reason_label, 10, 8, 10, 8))

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 9)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(columns)
	var regions_card: PanelContainer = _card(Color("131918"), S.BRASS.darkened(0.38), 8)
	regions_card.custom_minimum_size.x = 215.0
	columns.add_child(regions_card)
	var regions: VBoxContainer = VBoxContainer.new()
	regions.add_theme_constant_override("separation", 6)
	regions_card.add_child(C.inset(regions, 10, 9, 10, 9))
	C.section_header(regions, "BODY REGIONS")
	_medical_parts_box = VBoxContainer.new()
	_medical_parts_box.add_theme_constant_override("separation", 5)
	regions.add_child(_medical_parts_box)

	var conditions_card: PanelContainer = _card(Color("131918"), S.BRASS.darkened(0.38), 8)
	conditions_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(conditions_card)
	var conditions: VBoxContainer = VBoxContainer.new()
	conditions.add_theme_constant_override("separation", 7)
	conditions_card.add_child(C.inset(conditions, 11, 9, 11, 9))
	C.section_header(conditions, "ACTIVE CONDITIONS", "SELECTED REGION")
	_medical_conditions_box = VBoxContainer.new()
	_medical_conditions_box.add_theme_constant_override("separation", 7)
	conditions.add_child(_medical_conditions_box)


func _build_activity_log(parent: VBoxContainer) -> void:
	var current_card: PanelContainer = _card(Color("132025"), S.BLUE.darkened(0.5), 7)
	parent.add_child(current_card)
	var current_row: HBoxContainer = HBoxContainer.new()
	current_row.add_theme_constant_override("separation", 9)
	current_card.add_child(C.inset(current_row, 11, 8, 11, 8))
	current_row.add_child(_icon("running", 21.0, S.BLUE))
	current_row.add_child(_label("CURRENT ACTIVITY", 11, S.MUTED))
	_log_current_activity = _label("Idle", 12, S.IVORY)
	_log_current_activity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_current_activity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	current_row.add_child(_log_current_activity)
	C.section_header(parent, "ACTIVITY LOG", "NEWEST FIRST")
	_log_rows_box = VBoxContainer.new()
	_log_rows_box.add_theme_constant_override("separation", 6)
	parent.add_child(_log_rows_box)


func _set_tab(index: int, refresh_content: bool = true) -> void:
	if index < 0 or index >= _tab_buttons.size():
		return
	_active_tab = index
	for button_index: int in range(_tab_buttons.size()):
		_tab_buttons[button_index].button_pressed = button_index == index
		_pages[button_index].visible = button_index == index
	if refresh_content:
		if index == ResidentTab.TALK:
			_refresh_dialogue()
			_rebuild_talk_topics()
		elif index == ResidentTab.HEALTH:
			_rebuild_health(true)
		elif index == ResidentTab.ACTIVITY_LOG:
			_rebuild_log_rows()
	if index < _scrolls.size():
		_reset_scroll(_scrolls[index])


func _cycle_tab(direction: int) -> void:
	var next_tab: int = wrapi(_active_tab + direction, 0, _tab_buttons.size())
	_set_tab(next_tab, true)
	_tab_buttons[next_tab].grab_focus()


func _open_talk_tab() -> void:
	_set_tab(ResidentTab.TALK, true)
	if InputMode.is_controller() and _talk_topics_box != null:
		for child: Node in _talk_topics_box.get_children():
			if child is Button:
				(child as Button).grab_focus()
				break


func _refresh_live_values() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var resident_name: String = String(_npc.get("npc_name"))
	var age: int = int(_npc.get("age"))
	var activity: String = _current_activity()
	_name_label.text = resident_name
	_identity_line.text = "Age %d  •  %s" % [age, activity]
	_talk_to_button.text = "Talk to %s" % resident_name
	_update_activity(activity)
	_update_needs()
	_update_relationship()
	_update_skills()
	_update_overview_facts()
	if _log_current_activity != null:
		_log_current_activity.text = activity


func _update_activity(activity: String) -> void:
	_activity_title.text = activity
	_activity_detail.text = _activity_detail_text(activity)
	_activity_icon.texture = S.icon(_activity_icon_kind(activity))
	var state: String = _activity_state(activity)
	var color: Color = S.GREEN
	if state == "RESTING":
		color = S.BLUE
	elif state == "IDLE":
		color = S.MUTED
	elif state == "UNWELL":
		color = S.RED
	_header_state_label.text = state
	_header_state_label.add_theme_color_override("font_color", color)
	_header_state_icon.texture = S.icon("running" if state == "ON DUTY" else "clock")
	_header_state_icon.self_modulate = color
	_set_state_panel(_header_state_panel, color)
	_activity_state_label.text = state
	_activity_state_label.add_theme_color_override("font_color", color)
	_set_state_panel(_activity_state_panel, color)


func _update_needs() -> void:
	var values: Dictionary = {
		"Health": float(_npc.get("health")),
		"Energy": float(_npc.get("energy")),
		"Food": float(_npc.get("hunger")),
		"Water": float(_npc.get("thirst")),
		"Mood": float(_npc.get("mood")),
	}
	for key: String in values.keys():
		var value: float = clampf(float(values[key]), 0.0, 100.0)
		var bar: ProgressBar = _need_bars[key] as ProgressBar
		var label: Label = _need_values[key] as Label
		SMOOTH_BAR.apply(bar, value)
		label.text = "%d / 100" % int(round(value))


func _update_relationship() -> void:
	var value: float = 0.0
	var label_text: String = "Neutral"
	if _npc.has_method("get_relationship"):
		value = float(_npc.call("get_relationship", "player"))
	if _npc.has_method("get_relationship_label"):
		label_text = String(_npc.call("get_relationship_label", "player"))
	var color: Color = _relationship_color(label_text)
	_relationship_label.text = label_text
	_relationship_label.add_theme_color_override("font_color", color)
	_relationship_value.text = "%+.0f" % value
	_relationship_meter.set_target_value(value)
	_header_relationship_label.text = "%s  %+.0f" % [label_text.to_upper(), value]
	_header_relationship_label.add_theme_color_override("font_color", color)
	_set_state_panel(_header_relationship_panel, color)


func _update_skills() -> void:
	var skills_variant: Variant = _npc.get("skills")
	if not (skills_variant is Dictionary):
		return
	var skills: Dictionary = skills_variant as Dictionary
	for skill: String in _skill_bars.keys():
		var display_value: float = clampf(float(skills.get(skill, 1.0)) * 10.0, 0.0, 20.0)
		SMOOTH_BAR.apply(_skill_bars[skill] as ProgressBar, display_value)
		(_skill_values[skill] as Label).text = str(int(round(display_value)))


func _update_overview_facts() -> void:
	var condition_count: int = _active_condition_count()
	_overview_medical_value.text = (
		"No active conditions" if condition_count == 0
		else "%d active condition%s" % [condition_count, "" if condition_count == 1 else "s"]
	)
	_overview_medical_value.add_theme_color_override(
		"font_color", S.GREEN if condition_count == 0 else S.RED
	)
	var irritation: String = ""
	if _npc.has_method("get_irritability_label"):
		irritation = String(_npc.call("get_irritability_label"))
	_overview_irritability_value.text = "Calm" if irritation == "" else irritation
	_overview_irritability_value.add_theme_color_override(
		"font_color", S.GREEN if irritation == "" else ENERGY_COLOR
	)
	var entries: Array[Dictionary] = _get_action_log()
	if entries.is_empty():
		_overview_last_action_value.text = "Nothing notable yet"
	else:
		var latest: Dictionary = entries[0]
		_overview_last_action_value.text = "%s  •  %s" % [
			String(latest.get("text", "Nothing notable yet")),
			_format_log_age(int(latest.get("fired_at_msec", Time.get_ticks_msec()))),
		]


func _rebuild_traits() -> void:
	_clear(_trait_row)
	var words: Array[String] = []
	if _npc != null and _npc.has_method("get_personality_words"):
		var result: Variant = _npc.call("get_personality_words")
		if result is Array:
			for word_variant: Variant in result:
				words.append(String(word_variant))
	if words.is_empty():
		words.append("No notable traits")
	for word: String in words:
		var pill: PanelContainer = _card(Color("192220"), S.BRASS.darkened(0.38), 6)
		_trait_row.add_child(pill)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		pill.add_child(C.inset(row, 7, 4, 7, 4))
		var dot: ColorRect = ColorRect.new()
		dot.color = S.GREEN
		dot.custom_minimum_size = Vector2(7.0, 7.0)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		row.add_child(_label(word, 10, S.IVORY))


func _rebuild_talk_topics() -> void:
	if _talk_topics_box == null:
		return
	_clear(_talk_topics_box)
	var player_button: Button = Button.new()
	player_button.text = "What do you think of me?"
	player_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	S.icon_button(player_button, "relationship")
	player_button.pressed.connect(_show_relationship_answer.bind("player"))
	_talk_topics_box.add_child(player_button)
	if _npc == null or not _npc.has_method("get_other_npc_topics"):
		return
	var topics_variant: Variant = _npc.call("get_other_npc_topics")
	if not (topics_variant is Array):
		return
	for topic_variant: Variant in topics_variant:
		if not (topic_variant is Dictionary):
			continue
		var topic: Dictionary = topic_variant as Dictionary
		var target_id: String = String(topic.get("id", ""))
		var target_name: String = String(topic.get("name", "them"))
		var button: Button = Button.new()
		button.text = "What do you think of %s?" % target_name
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		S.icon_button(button, "talk")
		button.pressed.connect(_show_relationship_answer.bind(target_id))
		_talk_topics_box.add_child(button)


func _refresh_dialogue() -> void:
	if _dialogue_label == null or _npc == null:
		return
	if _npc.has_method("get_dialogue_line"):
		_dialogue_label.text = String(_npc.call("get_dialogue_line"))


func _show_relationship_answer(target_id: String) -> void:
	if _dialogue_label == null or _npc == null or not is_instance_valid(_npc):
		return
	if _npc.has_method("get_relationship_dialogue_line"):
		_dialogue_label.text = String(_npc.call("get_relationship_dialogue_line", target_id))


func _issue_command(activity: NPCActivity, action_desc: String, empty_desc: String) -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var brain: Object = _npc.get("brain") as Object
	if brain == null or not brain.has_method("force_command"):
		return
	brain.call("force_command", activity)
	var resident_name: String = String(_npc.get("npc_name"))
	if activity.done(_npc):
		NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			"%s: %s" % [resident_name, empty_desc])
		_show_request_feedback("%s: %s" % [resident_name, empty_desc], false)
	else:
		NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
			"%s: %s" % [resident_name, action_desc])
		_show_request_feedback("Request accepted — %s is %s." % [resident_name, action_desc], true)


func _on_command_eat_pressed() -> void:
	_issue_command(EatActivity.new(), "heading to eat", "nothing to eat nearby")


func _on_command_drink_pressed() -> void:
	_issue_command(DrinkActivity.new(), "heading to get water", "no water source nearby")


func _on_command_rest_pressed() -> void:
	_issue_command(CommandRestActivity.new(), "heading to rest", "nowhere to rest nearby")


func _on_job_command_pressed(job_type: String) -> void:
	if _npc != null and _npc.has_method("is_relaxing") and _npc.call("is_relaxing") == true:
		if _npc.has_method("request_job_while_relaxing") \
				and _npc.call("request_job_while_relaxing") != true:
			var refusal: String = "They would rather keep resting."
			if _npc.has_method("get_relaxing_refusal_line"):
				refusal = String(_npc.call("get_relaxing_refusal_line"))
			_show_request_feedback(refusal, false)
			return
	var entry: Dictionary = {}
	for candidate: Dictionary in NPC_JOB_MENU_ENTRIES:
		if String(candidate.get("type", "")) == job_type:
			entry = candidate
			break
	var action_desc: String = String(entry.get("action_desc", "heading to work"))
	var empty_desc: String = String(entry.get("empty_desc", "nothing to do right now"))
	if job_type == "CLEANING":
		if _npc.has_method("get_cleaning_unavailable_reason"):
			var reason: String = String(_npc.call("get_cleaning_unavailable_reason"))
			if CLEANING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(CLEANING_UNAVAILABLE_REASONS[reason])
		_issue_command(CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		if _npc.has_method("get_refuel_unavailable_reason"):
			var reason: String = String(_npc.call("get_refuel_unavailable_reason"))
			if REFUEL_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(REFUEL_UNAVAILABLE_REASONS[reason])
		_issue_command(CommandRefuelActivity.new(), action_desc, empty_desc)
	elif job_type == "FARMING":
		var farm_command: CommandGardeningActivity = CommandGardeningActivity.new()
		farm_command.mode = "farming"
		_issue_command(farm_command, action_desc, empty_desc)
	elif job_type == "FERTILIZE":
		var fertilizer_command: CommandGardeningActivity = CommandGardeningActivity.new()
		fertilizer_command.mode = "fertilize_only"
		_issue_command(fertilizer_command, action_desc, empty_desc)
	elif job_type == "COOKING":
		if _npc.has_method("get_cooking_unavailable_reason"):
			var reason: String = String(_npc.call("get_cooking_unavailable_reason"))
			if COOKING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(COOKING_UNAVAILABLE_REASONS[reason])
		_issue_command(CommandCookingActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(CommandJobActivity.new(job_type), action_desc, empty_desc)


func _show_request_feedback(message: String, success: bool) -> void:
	_request_feedback_panel.visible = true
	_request_feedback_label.text = message
	var color: Color = S.GREEN if success else ENERGY_COLOR
	_request_feedback_label.add_theme_color_override("font_color", color)
	_request_feedback_panel.add_theme_stylebox_override("panel", C.panel_box(
		Color("17231f") if success else Color("32231b"), color.darkened(0.35), 7, 1
	))


func _rebuild_health(force: bool) -> void:
	if _medical_parts_box == null or _medical_conditions_box == null:
		return
	var signature: String = _medical_state_signature()
	if not force and signature == _medical_signature:
		return
	_medical_signature = signature
	_clear(_medical_parts_box)
	_clear(_medical_conditions_box)
	_medical_part_buttons.clear()
	var medical: NPCMedical = _npc_medical()
	if medical == null:
		_health_summary_label.text = "No medical data available"
		_medical_conditions_box.add_child(_empty_state("Medical information is unavailable."))
		return
	var active_parts: Array[int] = []
	for part: int in MEDICAL_BODY_PARTS:
		if not medical.get_conditions_for_body_part(part).is_empty():
			active_parts.append(part)
	var count: int = medical.active_conditions.size()
	_health_summary_label.text = (
		"No injuries or illnesses" if count == 0
		else "%d active condition%s requiring attention" % [count, "" if count == 1 else "s"]
	)
	_health_summary_label.add_theme_color_override("font_color", S.GREEN if count == 0 else S.RED)
	var reason: String = medical.get_needs_cap_reason_text()
	_health_reason_panel.visible = reason != ""
	_health_reason_label.text = "⚠  " + reason if reason != "" else ""
	if active_parts.is_empty():
		_selected_medical_part = -1
		_medical_parts_box.add_child(_empty_state("ALL REGIONS CLEAR"))
		_medical_conditions_box.add_child(_empty_state(
			"No active conditions. This resident is currently healthy."
		))
		return
	if not active_parts.has(_selected_medical_part):
		_selected_medical_part = active_parts[0]
	for part: int in active_parts:
		var conditions: Array[MedicalCondition] = medical.get_conditions_for_body_part(part)
		var button: Button = Button.new()
		button.text = "%s    %d" % [MedicalCondition.body_part_label(part).to_upper(), conditions.size()]
		button.icon = S.icon("medical")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		C.style_segment(button, true)
		button.button_pressed = part == _selected_medical_part
		button.pressed.connect(_select_medical_part.bind(part))
		_medical_parts_box.add_child(button)
		_medical_part_buttons[part] = button
	_rebuild_selected_conditions()


func _select_medical_part(part: int) -> void:
	_selected_medical_part = part
	for key: Variant in _medical_part_buttons.keys():
		(_medical_part_buttons[key] as Button).button_pressed = int(key) == part
	_rebuild_selected_conditions()


func _rebuild_selected_conditions() -> void:
	_clear(_medical_conditions_box)
	var medical: NPCMedical = _npc_medical()
	if medical == null or _selected_medical_part < 0:
		return
	var conditions: Array[MedicalCondition] = medical.get_conditions_for_body_part(_selected_medical_part)
	for condition: MedicalCondition in conditions:
		var ring_color: Color = medical.get_ring_color_for_condition(condition)
		var card: PanelContainer = _card(Color("171d1c"), ring_color.darkened(0.2), 7)
		_medical_conditions_box.add_child(card)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(C.inset(row, 11, 9, 11, 9))
		row.add_child(_icon("medical", 25.0, ring_color))
		var copy: VBoxContainer = VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 4)
		row.add_child(copy)
		var title_row: HBoxContainer = HBoxContainer.new()
		copy.add_child(title_row)
		var title: Label = _label(_condition_title(condition), 14, S.IVORY)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(title)
		var state: Label = _label(_condition_state(condition), 10, ring_color)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title_row.add_child(state)
		var detail: Label = _label(medical.get_status_detail_text(condition), 11, S.MUTED)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(detail)


func _medical_state_signature() -> String:
	var medical: NPCMedical = _npc_medical()
	if medical == null:
		return "none"
	var parts: PackedStringArray = PackedStringArray()
	for condition: MedicalCondition in medical.active_conditions:
		parts.append("%s:%d:%s:%s" % [
			condition.id,
			condition.body_part,
			str(condition.is_treated),
			str(condition.is_infected),
		])
	return "|".join(parts)


func _npc_medical() -> NPCMedical:
	if _npc == null or not is_instance_valid(_npc):
		return null
	var value: Variant = _npc.get("medical")
	return value as NPCMedical


func _active_condition_count() -> int:
	var medical: NPCMedical = _npc_medical()
	return medical.active_conditions.size() if medical != null else 0


func _rebuild_log_rows() -> void:
	if _log_rows_box == null:
		return
	_clear(_log_rows_box)
	_log_time_labels.clear()
	_log_text_labels.clear()
	_log_entries = _get_action_log()
	if _log_entries.is_empty():
		_log_rows_box.add_child(_empty_state("Nothing notable yet."))
		return
	for entry: Dictionary in _log_entries:
		var hostile: bool = entry.get("is_live_hostile", false) == true
		var color: Color = S.RED if hostile else S.BLUE
		var card: PanelContainer = _card(Color("141b1a"), color.darkened(0.55), 7)
		card.tooltip_text = "At %s" % String(entry.get("game_time", "?"))
		_log_rows_box.add_child(card)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(C.inset(row, 10, 8, 10, 8))
		var marker: ColorRect = ColorRect.new()
		marker.color = color
		marker.custom_minimum_size = Vector2(4.0, 34.0)
		row.add_child(marker)
		var text_label: Label = _label(String(entry.get("text", "")), 12, S.IVORY)
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_label)
		_log_text_labels.append(text_label)
		var time_label: Label = _label(
			_format_log_age(int(entry.get("fired_at_msec", Time.get_ticks_msec()))), 10, S.MUTED
		)
		time_label.custom_minimum_size.x = 58.0
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(time_label)
		_log_time_labels.append(time_label)


func _refresh_log_timestamps() -> void:
	for index: int in range(_log_time_labels.size()):
		if index >= _log_entries.size():
			continue
		var fired_at: int = int(_log_entries[index].get("fired_at_msec", Time.get_ticks_msec()))
		_log_time_labels[index].text = _format_log_age(fired_at)
		if _log_entries[index].get("is_live_hostile", false) == true and index < _log_text_labels.size():
			_log_text_labels[index].text = String(_log_entries[index].get("text", ""))


func _get_action_log() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _npc == null or not _npc.has_method("get_action_log"):
		return result
	var entries_variant: Variant = _npc.call("get_action_log")
	if not (entries_variant is Array):
		return result
	for entry_variant: Variant in entries_variant:
		if entry_variant is Dictionary:
			result.append(entry_variant as Dictionary)
	return result


func _connect_npc_signals() -> void:
	if _npc != null and _npc.has_signal("action_logged"):
		var callback: Callable = Callable(self, "_rebuild_log_rows")
		if not _npc.is_connected("action_logged", callback):
			_npc.connect("action_logged", callback)


func _disconnect_npc_signals() -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_signal("action_logged"):
		var callback: Callable = Callable(self, "_rebuild_log_rows")
		if _npc.is_connected("action_logged", callback):
			_npc.disconnect("action_logged", callback)


func _current_activity() -> String:
	if _npc == null:
		return "Idle"
	var brain: Object = _npc.get("brain") as Object
	if brain != null and brain.has_method("current_label"):
		return String(brain.call("current_label"))
	return "Idle"


func _activity_state(activity: String) -> String:
	var lower: String = activity.to_lower()
	if "passed out" in lower or "injured" in lower:
		return "UNWELL"
	if "sleep" in lower or "rest" in lower or "relax" in lower or "sit" in lower:
		return "RESTING"
	if lower == "idle" or lower == "wandering":
		return "IDLE"
	return "ON DUTY"


func _activity_icon_kind(activity: String) -> String:
	var lower: String = activity.to_lower()
	if "farm" in lower or "plant" in lower or "harvest" in lower or "tray" in lower:
		return "plant"
	if "water" in lower or "drink" in lower or "filter" in lower:
		return "water"
	if "fuel" in lower or "generator" in lower:
		return "power"
	if "eat" in lower or "food" in lower:
		return "food"
	if "cook" in lower:
		return "cooking"
	if "talk" in lower:
		return "talk"
	if "sleep" in lower or "rest" in lower or "relax" in lower:
		return "sleep"
	if "clean" in lower or "put away" in lower:
		return "storage"
	return "clock"


func _activity_detail_text(activity: String) -> String:
	var lower: String = activity.to_lower()
	if "farm" in lower or "plant" in lower or "harvest" in lower or "tray" in lower:
		return "Bunker agriculture • Current assignment"
	if "filter" in lower or "water" in lower:
		return "Water system • Current assignment"
	if "fuel" in lower or "generator" in lower:
		return "Power system • Current assignment"
	if "clean" in lower or "put away" in lower:
		return "Bunker upkeep • Current assignment"
	if "cook" in lower:
		return "Meal preparation • Current assignment"
	if "sleep" in lower or "rest" in lower or "relax" in lower:
		return "Personal time • Recovering"
	if lower == "idle" or lower == "wandering":
		return "No assigned work • Available"
	return "Live behavior • Updates automatically"


func _relationship_color(label_text: String) -> Color:
	match label_text:
		"Hostile":
			return S.RED
		"Cold":
			return ENERGY_COLOR
		"Friendly", "Close":
			return S.GREEN
		_:
			return S.MUTED


func _condition_title(condition: MedicalCondition) -> String:
	var title: String = condition.id.replace("_", " ").capitalize()
	if condition.id == "open_wound" and condition.is_infected:
		title += " — Infected"
	return title


func _condition_state(condition: MedicalCondition) -> String:
	if condition.is_treated:
		return "TREATED"
	if condition.id == "open_wound" and condition.is_infected:
		return "INFECTION ACTIVE"
	return "UNTREATED"


func _format_log_age(fired_at_msec: int) -> String:
	var elapsed_seconds: int = maxi(0, int((Time.get_ticks_msec() - fired_at_msec) / 1000.0))
	if elapsed_seconds < 60:
		return "%ds ago" % elapsed_seconds
	var elapsed_minutes: int = int(elapsed_seconds / 60.0)
	if elapsed_minutes < 60:
		return "%dm ago" % elapsed_minutes
	return "%dh ago" % int(elapsed_minutes / 60.0)


func _update_footer() -> void:
	if _footer_hint == null:
		return
	_footer_hint.text = (
		"LB / RB  Switch tab    •    D-pad / Right stick  Navigate    •    A  Select    •    B / E  Close    •    Walk away to close"
		if InputMode.is_controller()
		else "Click  Select    •    Mouse wheel  Scroll    •    E / Esc  Close    •    Walk away to close"
	)


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = Vector2(
		maxf(720.0, viewport_size.x - SCREEN_MARGIN.x * 2.0),
		maxf(560.0, viewport_size.y - SCREEN_MARGIN.y * 2.0)
	)
	var panel_size: Vector2 = Vector2(
		minf(PANEL_MAX.x, available.x),
		minf(PANEL_MAX.y, available.y)
	)
	_panel.position = (viewport_size - panel_size) * 0.5
	_panel.size = panel_size


func _reset_scrolls() -> void:
	for scroll: ScrollContainer in _scrolls:
		_reset_scroll(scroll)


func _reset_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	scroll.scroll_vertical = 0
	scroll.scroll_horizontal = 0
	scroll.set_deferred("scroll_vertical", 0)


func _set_state_panel(panel: PanelContainer, color: Color) -> void:
	panel.add_theme_stylebox_override("panel", C.panel_box(
		Color(color.darkened(0.72), 0.78), color.darkened(0.27), 7, 1
	))


func _card(bg: Color, border: Color, radius: int = 8) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", C.panel_box(bg, border, radius, 1))
	return card


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _icon(symbol: String, side: float, color: Color) -> TextureRect:
	var texture: TextureRect = TextureRect.new()
	texture.texture = S.icon(symbol)
	texture.self_modulate = color
	texture.custom_minimum_size = Vector2(side, side)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture


func _progress(color: Color, height: float) -> ProgressBar:
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", C.panel_box(
		Color("0c1111"), S.BRASS.darkened(0.48), int(height * 0.5), 1
	))
	bar.add_theme_stylebox_override("fill", C.panel_box(
		color, color, int(height * 0.5), 0
	))
	return bar


func _empty_state(message: String) -> Label:
	var label: Label = _label(message, 12, S.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 58.0
	return label


func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
