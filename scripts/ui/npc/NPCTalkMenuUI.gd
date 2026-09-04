extends CanvasLayer
class_name NPCTalkMenuUI
## NPCTalkMenuUI.gd (Aug 2026 rewrite — full NPC hub, pass 2 polish)
## Layout: identity bar (name/task/age/skills/traits) → needs bar (same
## fill-bar visuals as before, horizontal) → left tab list (Talk /
## Requests / Medical, extra-spaced Activity Log below them) driving a
## right content pane. Both the tab list and the content pane scroll
## independently if their contents outgrow the panel's height. Right
## pane is blank until a tab is picked, and resets to blank on every
## reopen (never persisted).
##
## Pass 2 polish (this file's current form):
##   - Tab buttons center their label text.
##   - Activity Log moved out of the Talk tab into its own left-pane
##     entry, visually separated from Talk/Requests/Medical by extra
##     spacing — selecting it shows the log in the right pane, same as
##     any other tab (no more separate expand/collapse toggle needed;
##     switching tabs away from it IS the collapse).
##   - Whole UI scaled 1.15x, and a real MarginContainer inset added on
##     every side (the previous approach — content_margin_* on the
##     panel's own StyleBoxFlat — never actually applied, since
##     root_vbox was anchored PRESET_FULL_RECT directly against the
##     Panel and stylebox content_margin only affects theme-driven auto-
##     layout, not arbitrary anchored children).
##   - The Talk tab's redundant "Talk" button is gone — arriving at the
##     tab (either the first time or by reselecting it) IS the talk
##     action: the greeting line shows immediately, Ask About sits right
##     below it. Reselecting the already-open Talk tab re-picks a fresh
##     line, same as the old button used to.

const BASE_PANEL_W: float = 820.0
const BASE_PANEL_H: float = 520.0
const BASE_LEFT_PANE_W: float = 200.0
const BASE_NEEDS_BAR_TRACK_W: float = 68.0
const UI_SCALE: float = 1.15

const PANEL_W: float = BASE_PANEL_W * UI_SCALE
const PANEL_H: float = BASE_PANEL_H * UI_SCALE
const LEFT_PANE_W: float = BASE_LEFT_PANE_W * UI_SCALE
const NEEDS_BAR_TRACK_W: float = BASE_NEEDS_BAR_TRACK_W * UI_SCALE
const BAR_H: float = 14.0

## Real inward padding on every side, between the panel's own edge/border
## and everything inside it — see this file's header note on why the old
## stylebox content_margin approach never actually did this.
const PANEL_INSET: float = 22.0

## Extra gap (on top of the tab list's normal button separation) between
## the Talk/Requests/Medical group and the Activity Log entry below it —
## a visual break, not a functional one.
const LOG_GROUP_GAP: float = 14.0

const NEED_COLORS: Dictionary = {
	"Health": Color(0.81, 0.17, 0.17, 1.0),
	"Energy": Color(0.57, 0.33, 0.81, 1.0),
	"Hunger": Color(0.90, 0.80, 0.20, 1.0),
	"Thirst": Color(0.24, 0.52, 0.90, 1.0),
	"Mood":   Color8(188, 160, 220, 255),
}
const REFRESH_INTERVAL: float = 0.25

## Body parts shown in the Medical tab (Aug 2026) — real MedicalCondition.
## BodyPart enum values now (not display strings), since the tab queries
## NPCMedical.get_conditions_for_body_part() directly. Only parts with at
## least one active condition are actually shown — see _build_medical_tab().
const MEDICAL_BODY_PART_VALUES: Array[int] = [
	MedicalCondition.BodyPart.HEAD, MedicalCondition.BodyPart.TORSO,
	MedicalCondition.BodyPart.LEFT_ARM, MedicalCondition.BodyPart.RIGHT_ARM,
	MedicalCondition.BodyPart.LEFT_LEG, MedicalCondition.BodyPart.RIGHT_LEG,
]

## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (REPLACE_FILTER), or the literal strings "CLEANING"/"REFUEL"/
## "FARMING"/"FERTILIZE" (routed to their own Command*Activity instead
## of the generic CommandJobActivity, since none of the four are
## JobBoard-claimed). HARVEST is intentionally absent as a standalone
## entry — it's folded into "FARMING"'s priority order (harvest -> plant
## -> soil) — autonomous per-plant Harvest via JobBoard is untouched.
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
	{"type": "FARMING", "label": "Tend the farm", "action_desc": "heading to tend the farm", "empty_desc": "nothing to harvest, plant, or add soil to right now"},
	{"type": "FERTILIZE", "label": "Fertilize the trays", "action_desc": "heading to fertilize", "empty_desc": "nothing needs fertilizing, or none available"},
	{"type": "COOKING", "label": "Cook a meal", "action_desc": "heading to cook", "empty_desc": "nothing to cook right now"},
]

const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN":          "nothing to clean right now",
	"NO_TRASH_RECEPTACLE":       "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING":            "everything's still settling — check back shortly",
	"ALL_CLAIMED":               "everything's already being handled by someone else",
	"NO_LIGHT_STORAGE_AVAILABLE": "there's nothing to put light items away in",
	"NO_HEAVY_STORAGE_AVAILABLE": "there's nothing to put heavy items away in",
	"STORAGE_FULL":              "storage is full",
}
const REFUEL_UNAVAILABLE_REASONS: Dictionary = {
	"ALL_GENERATORS_FULL": "every generator is already full",
	"FUEL_CAN_CLAIMED":    "the only fuel can is already being used",
	"NO_FUEL_CAN":         "there's no fuel can anywhere to refuel with",
}
const COOKING_UNAVAILABLE_REASONS: Dictionary = {
	"NO_STOVE": "there's no stove built yet",
}

var _npc: Node = null
var _backdrop: ColorRect = null
var _panel: Panel = null
var _is_open: bool = false
var _refresh_timer: float = 0.0
var _proximity: Node = null

## Identity bar widgets
var _identity_name_label: Label = null
var _identity_task_label: Label = null
var _identity_age_label: Label = null
var _skill_labels: Dictionary = {}   ## skill name -> Label
var _trait_label: Label = null

## Needs bar widgets
var _need_fills: Dictionary = {}    ## need name -> ColorRect (fill)
var _need_labels: Dictionary = {}   ## need name -> Label (value text)

## Tab list + content pane. "log" is a 4th selectable entry alongside
## talk/requests/medical, just visually separated in the left column.
var _tab_buttons: Dictionary = {}   ## "talk"/"requests"/"medical"/"log" -> Button
var _selected_tab: String = ""      ## "" = nothing selected — blank pane, always the state on open()
var _content_pane: VBoxContainer = null

## Talk tab widgets
var _dialogue_label: Label = null
var _relationship_box: VBoxContainer = null

## Requests tab widgets
var _requests_box: VBoxContainer = null
var _jobs_box: VBoxContainer = null
var _jobs_expanded: bool = false

## Medical tab widgets (Aug 2026) — nested dropdown state: body part ->
## expanded bool, and "<part>_<condition_id>" -> expanded bool for the
## injury-level dropdown nested inside it. Reset on open() for a fresh NPC
## (see open() below) so a previous NPC's expand state never bleeds into
## a different one's Medical tab.
var _medical_expanded_parts: Dictionary = {}
var _medical_expanded_conditions: Dictionary = {}

## Log tab widgets
var _log_rows_box: VBoxContainer = null
var _log_entries: Array[Dictionary] = []
var _log_time_labels: Array[Label] = []
var _log_text_labels: Array[Label] = []

func _ready() -> void:
	layer = 70
	visible = false
	_proximity = (load("res://scripts/ui/common/UIProximityClose.gd") as GDScript).new()
	_proximity.ui = self
	add_child(_proximity)
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	add_child(controller_nav)

func open(npc_name: String, npc: Node = null) -> void:
	_npc = npc
	_is_open = true
	_selected_tab = ""   ## always blank on open, never remembered
	_medical_expanded_parts = {}
	_medical_expanded_conditions = {}
	if _proximity != null:
		if npc != null and is_instance_valid(npc):
			_proximity.anchor = npc.global_position
		else:
			var player: Node = get_tree().get_first_node_in_group("player")
			if player != null:
				_proximity.anchor = player.global_position
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	add_to_group("npc_talk_ui")
	_build(npc_name)

func close() -> void:
	_is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	remove_from_group("npc_talk_ui")
	_teardown()

func _teardown() -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.disconnect(_rebuild_log_rows)
	_jobs_expanded = false
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_backdrop = null
	_panel = null
	_need_fills = {}
	_need_labels = {}
	_skill_labels = {}
	_identity_name_label = null
	_identity_task_label = null
	_identity_age_label = null
	_trait_label = null
	_tab_buttons = {}
	_content_pane = null
	_dialogue_label = null
	_relationship_box = null
	_log_rows_box = null
	_requests_box = null
	_jobs_box = null

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _is_open:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh_live_values()

	## Log tab — live "Xs ago" timestamps while it's the selected pane.
	if _selected_tab == "log":
		for i: int in range(_log_time_labels.size()):
			if i >= _log_entries.size():
				continue
			_log_time_labels[i].text = _format_log_age(_log_entries[i]["fired_at_msec"] as int)
		if not _log_entries.is_empty() and bool(_log_entries[0].get("is_live_hostile", false)) \
				and not _log_text_labels.is_empty():
			_log_text_labels[0].text = str(_log_entries[0]["text"])

# ─── Construction ─────────────────────────────────────────────────────────
func _build(npc_name: String) -> void:
	_teardown()
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)

	_panel = UIKit.build_centered_panel(PANEL_W, PANEL_H, theme)
	add_child(_panel)

	## Real inward padding on every side (see header note) — a
	## MarginContainer between the panel and everything inside it.
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(PANEL_INSET))
	margin.add_theme_constant_override("margin_right", int(PANEL_INSET))
	margin.add_theme_constant_override("margin_top", int(PANEL_INSET))
	margin.add_theme_constant_override("margin_bottom", int(PANEL_INSET))
	_panel.add_child(margin)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	_build_identity_bar(root_vbox, npc_name, theme)
	root_vbox.add_child(HSeparator.new())
	_build_needs_bar(root_vbox, theme)
	root_vbox.add_child(HSeparator.new())

	## Body: left tab list | right content pane — both independently
	## scrollable if their contents outgrow the available height.
	var body_row: HBoxContainer = HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 16)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_row)

	_build_tab_list(body_row, theme)
	body_row.add_child(VSeparator.new())

	var content_scroll: ScrollContainer = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_child(content_scroll)

	_content_pane = VBoxContainer.new()
	_content_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_pane.add_theme_constant_override("separation", 8)
	content_scroll.add_child(_content_pane)
	## Blank until the player picks a tab — nothing added here.

	_refresh_live_values()
	UIFade.fade_in(_panel)

## Name / current task / age on one line; skills + traits on a second —
## multiple lines by design, prioritizing a clean layout over cramming
## everything onto one.
func _build_identity_bar(parent: VBoxContainer, npc_name: String, theme: UIKit.UITheme) -> void:
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	parent.add_child(row1)

	_identity_name_label = Label.new()
	_identity_name_label.text = npc_name
	_identity_name_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_TITLE)
	_identity_name_label.add_theme_color_override("font_color", theme.header)
	_identity_name_label.add_theme_font_override("font", UIKit.font())
	row1.add_child(_identity_name_label)

	_identity_task_label = Label.new()
	_identity_task_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_identity_task_label.add_theme_color_override("font_color", theme.dim)
	_identity_task_label.add_theme_font_override("font", UIKit.font())
	_identity_task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_identity_task_label)

	_identity_age_label = Label.new()
	_identity_age_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_identity_age_label.add_theme_color_override("font_color", theme.text)
	_identity_age_label.add_theme_font_override("font", UIKit.font())
	row1.add_child(_identity_age_label)

	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 20)
	parent.add_child(row2)

	var skills_row: HBoxContainer = HBoxContainer.new()
	skills_row.add_theme_constant_override("separation", 14)
	row2.add_child(skills_row)
	for skill: String in ["farming", "plumbing", "electrical", "construction"]:
		var lbl: Label = UIKit.make_row_label("", theme)
		lbl.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_SECTION)
		skills_row.add_child(lbl)
		_skill_labels[skill] = lbl

	_trait_label = Label.new()
	_trait_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_SECTION)
	_trait_label.add_theme_color_override("font_color", theme.dim)
	_trait_label.add_theme_font_override("font", UIKit.font())
	_trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trait_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_trait_label)

## Horizontal — 5 need blocks side by side, same fill-bar visuals/colors
## as before (ColorRect track+fill, same NEED_COLORS).
func _build_needs_bar(parent: VBoxContainer, theme: UIKit.UITheme) -> void:
	parent.add_child(UIKit.make_section_label("NEEDS", theme))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	for need: String in ["Health", "Energy", "Hunger", "Thirst", "Mood"]:
		row.add_child(_build_need_block(need, theme))

func _build_need_block(need: String, theme: UIKit.UITheme) -> HBoxContainer:
	var block: HBoxContainer = HBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var name_lbl: Label = UIKit.make_row_label(need, theme)
	name_lbl.custom_minimum_size = Vector2(42.0, 0.0)
	block.add_child(name_lbl)

	var track: ColorRect = ColorRect.new()
	track.color = Color(0.10, 0.10, 0.12, 1.0)
	track.custom_minimum_size = Vector2(NEEDS_BAR_TRACK_W, BAR_H)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(track)

	var fill: ColorRect = ColorRect.new()
	fill.color = NEED_COLORS.get(need, theme.ok)
	fill.position = Vector2.ZERO
	fill.size = Vector2(NEEDS_BAR_TRACK_W, BAR_H)
	track.add_child(fill)
	_need_fills[need] = fill

	var val: Label = UIKit.make_row_label("100", theme)
	val.custom_minimum_size = Vector2(24.0, 0.0)
	block.add_child(val)
	_need_labels[need] = val

	return block

## Left tab list — Talk / Requests / Medical, then Activity Log below
## them with extra separation. Scrollable if it ever outgrows the
## panel's height. Every button's text is explicitly centered.
func _build_tab_list(parent: HBoxContainer, theme: UIKit.UITheme) -> void:
	var tab_scroll: ScrollContainer = ScrollContainer.new()
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size = Vector2(LEFT_PANE_W, 0.0)
	parent.add_child(tab_scroll)

	var tab_col: VBoxContainer = VBoxContainer.new()
	tab_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_col.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tab_col)

	for entry in [["talk", "Talk"], ["requests", "Requests"], ["medical", "Medical"]]:
		var key: String = entry[0]
		var label: String = entry[1]
		var btn: Button = UIKit.make_button(label, Callable(self, "_on_tab_selected").bind(key))
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_col.add_child(btn)
		_tab_buttons[key] = btn

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, LOG_GROUP_GAP)
	tab_col.add_child(spacer)

	var log_btn: Button = UIKit.make_button("Activity Log", Callable(self, "_on_tab_selected").bind("log"))
	log_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_col.add_child(log_btn)
	_tab_buttons["log"] = log_btn

	_restyle_tab_buttons(theme)
	if InputMode.is_controller() and _tab_buttons.has("talk"):
		(_tab_buttons["talk"] as Button).grab_focus()

## Highlights whichever tab is currently selected — a simple border/bg
## swap on top of UIKit.make_button()'s existing 3-state styling.
func _restyle_tab_buttons(theme: UIKit.UITheme) -> void:
	for key: String in _tab_buttons.keys():
		var btn: Button = _tab_buttons[key]
		var selected: bool = key == _selected_tab
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.20, 0.20, 0.23, 0.98) if selected else Color(0.14, 0.14, 0.16, 0.95)
		sb.border_color = theme.accent if selected else Color(0.30, 0.30, 0.33, 0.85)
		sb.set_border_width_all(2 if selected else 1)
		sb.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", sb)

func _on_tab_selected(key: String) -> void:
	_selected_tab = key
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)
	_restyle_tab_buttons(theme)
	_rebuild_content_pane(theme)

func _rebuild_content_pane(theme: UIKit.UITheme) -> void:
	if _content_pane == null:
		return
	for child: Node in _content_pane.get_children():
		child.queue_free()
	_dialogue_label = null
	_relationship_box = null
	_log_rows_box = null
	_requests_box = null
	_jobs_box = null

	match _selected_tab:
		"talk":
			_build_talk_tab(theme)
		"requests":
			_build_requests_tab(theme)
		"medical":
			_build_medical_tab(theme)
		"log":
			_build_log_tab(theme)

# ─── Talk tab ──────────────────────────────────────────────────────────────
## No more standalone "Talk" button — arriving at this tab (first click
## or reselecting it) IS the talk action: greeting line shows
## immediately, Ask About sits right below.
func _build_talk_tab(theme: UIKit.UITheme) -> void:
	_dialogue_label = Label.new()
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dialogue_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_dialogue_label.add_theme_color_override("font_color", theme.text)
	_dialogue_label.add_theme_font_override("font", UIKit.font())
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_dialogue_line"):
		_dialogue_label.text = _npc.get_dialogue_line()
	_content_pane.add_child(_dialogue_label)

	_relationship_box = VBoxContainer.new()
	_relationship_box.add_theme_constant_override("separation", 4)
	_content_pane.add_child(_relationship_box)
	_relationship_box.add_child(UIKit.make_section_label("ASK ABOUT", theme))
	_relationship_box.add_child(UIKit.make_button("What do you think of me?", _on_ask_about_player_pressed))
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_other_npc_topics"):
		for topic: Dictionary in _npc.get_other_npc_topics():
			var target_id: String = String(topic.get("id", ""))
			var target_name: String = String(topic.get("name", "them"))
			_relationship_box.add_child(UIKit.make_button(
				"What do you think of %s?" % target_name,
				Callable(self, "_on_ask_about_npc_pressed").bind(target_id)))

# ─── Requests tab ──────────────────────────────────────────────────────────
func _build_requests_tab(theme: UIKit.UITheme) -> void:
	_requests_box = VBoxContainer.new()
	_requests_box.add_theme_constant_override("separation", 4)
	_content_pane.add_child(_requests_box)
	_requests_box.add_child(UIKit.make_button("Can you go eat something?", _on_command_eat_pressed))
	_requests_box.add_child(UIKit.make_button("Can you go drink something?", _on_command_drink_pressed))
	_requests_box.add_child(UIKit.make_button("Take a load off", _on_command_rest_pressed))
	_requests_box.add_child(UIKit.make_button("Can you complete this job?", _on_jobs_toggle_pressed))

	_jobs_box = VBoxContainer.new()
	_jobs_box.add_theme_constant_override("separation", 4)
	_jobs_box.visible = false
	_content_pane.add_child(_jobs_box)
	for entry: Dictionary in NPC_JOB_MENU_ENTRIES:
		var job_type: String = String(entry.get("type", ""))
		var label_text: String = String(entry.get("label", job_type))
		_jobs_box.add_child(UIKit.make_button(label_text, Callable(self, "_on_job_command_pressed").bind(job_type)))

	## A dialogue line (e.g. the relaxing-refusal line) can still fire
	## from here — a small inline label local to this tab.
	_dialogue_label = Label.new()
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dialogue_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_dialogue_label.add_theme_color_override("font_color", theme.text)
	_dialogue_label.add_theme_font_override("font", UIKit.font())
	_dialogue_label.visible = false
	_content_pane.add_child(_dialogue_label)

# ─── Medical tab ─────────────────────────────────────────────────────────
## Aug 2026 rewrite — real NPCMedical data, no longer the healthy-for-
## everyone stub. Per Brannon's explicit spec: only body parts with an
## active condition are shown at all (not the full always-listed 6), each
## a dropdown (▶/▼) that reveals its individual conditions, each of
## THOSE also a dropdown revealing that one condition's numeric detail —
## a nested dropdown inside a dropdown. Reuses NPCMedical.
## get_status_detail_text() verbatim for the innermost detail text — same
## "reuse the exact same per-condition data" principle the player's
## Status Screen already follows, not a second description of the same
## data. Same plain-text (not hover) needs-cap reason row the Status
## Screen uses, reusing NPCMedical.get_needs_cap_reason_text() verbatim.
func _build_medical_tab(theme: UIKit.UITheme) -> void:
	if _npc == null or not is_instance_valid(_npc) or not ("medical" in _npc) or _npc.medical == null:
		_content_pane.add_child(UIKit.make_row_label("No medical data available", theme))
		return
	var medical: NPCMedical = _npc.medical

	var reason: String = medical.get_needs_cap_reason_text()
	if reason != "":
		var reason_lbl: Label = Label.new()
		reason_lbl.text = "⚠ " + reason
		reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		reason_lbl.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
		reason_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.20, 1.0))
		reason_lbl.add_theme_font_override("font", UIKit.font())
		_content_pane.add_child(reason_lbl)

	_content_pane.add_child(UIKit.make_section_label("BODY", theme))

	var any_injury: bool = false
	for part: int in MEDICAL_BODY_PART_VALUES:
		var conditions: Array[MedicalCondition] = medical.get_conditions_for_body_part(part)
		if conditions.is_empty():
			continue
		any_injury = true
		_build_medical_body_part_row(part, conditions, medical, theme)

	if not any_injury:
		var ok_lbl: Label = Label.new()
		ok_lbl.text = "No injuries or illnesses"
		ok_lbl.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
		ok_lbl.add_theme_color_override("font_color", theme.dim)
		ok_lbl.add_theme_font_override("font", UIKit.font())
		_content_pane.add_child(ok_lbl)

## Outer dropdown — one body part, expands to list its conditions.
func _build_medical_body_part_row(part: int, conditions: Array[MedicalCondition], medical: NPCMedical, theme: UIKit.UITheme) -> void:
	var expanded: bool = bool(_medical_expanded_parts.get(part, false))
	var header: Button = Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_ALL
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var part_label: String = MedicalCondition.body_part_label(part)
	header.text = "%s  %s" % ["▼" if expanded else "▶", part_label]
	header.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	header.add_theme_color_override("font_color", theme.text)
	header.add_theme_font_override("font", UIKit.font())
	_content_pane.add_child(header)

	var body_margin: MarginContainer = MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.visible = expanded
	var body_vbox: VBoxContainer = VBoxContainer.new()
	body_vbox.add_theme_constant_override("separation", 4)
	body_margin.add_child(body_vbox)
	_content_pane.add_child(body_margin)

	for c: MedicalCondition in conditions:
		_build_medical_condition_row(part, c, medical, body_vbox, theme)

	header.pressed.connect(func() -> void:
		var now: bool = not bool(_medical_expanded_parts.get(part, false))
		_medical_expanded_parts[part] = now
		header.text = "%s  %s" % ["▼" if now else "▶", part_label]
		body_margin.visible = now
	)

## Inner dropdown — one condition on that body part, expands to show its
## numeric detail (NPCMedical.get_status_detail_text()).
func _build_medical_condition_row(part: int, condition: MedicalCondition, medical: NPCMedical, parent: VBoxContainer, theme: UIKit.UITheme) -> void:
	var key: String = "%d_%s" % [part, condition.id]
	var expanded: bool = bool(_medical_expanded_conditions.get(key, false))
	var header: Button = Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_ALL
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var cond_label: String = "%s%s" % [condition.id.capitalize(), " (Infected)" if (condition.id == "open_wound" and condition.is_infected) else ""]
	header.text = "%s  %s" % ["▼" if expanded else "▶", cond_label]
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", theme.dim)
	header.add_theme_font_override("font", UIKit.font())
	parent.add_child(header)

	var body_margin: MarginContainer = MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.visible = expanded
	var detail_lbl: Label = Label.new()
	detail_lbl.text = medical.get_status_detail_text(condition)
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_lbl.add_theme_font_size_override("font_size", 11)
	detail_lbl.add_theme_color_override("font_color", theme.dim)
	detail_lbl.add_theme_font_override("font", UIKit.font())
	body_margin.add_child(detail_lbl)
	parent.add_child(body_margin)

	header.pressed.connect(func() -> void:
		var now: bool = not bool(_medical_expanded_conditions.get(key, false))
		_medical_expanded_conditions[key] = now
		header.text = "%s  %s" % ["▼" if now else "▶", cond_label]
		body_margin.visible = now
	)

# ─── Log tab (Aug 2026 — moved here from a Talk-tab toggle) ────────────────
func _build_log_tab(theme: UIKit.UITheme) -> void:
	_content_pane.add_child(UIKit.make_section_label("ACTIVITY LOG", theme))

	var log_bg: PanelContainer = PanelContainer.new()
	var log_style: StyleBoxFlat = StyleBoxFlat.new()
	log_style.bg_color     = Color(0.05, 0.05, 0.06, 0.9)
	log_style.border_color = Color(0.30, 0.30, 0.33, 0.85)
	log_style.set_border_width_all(1)
	log_style.set_corner_radius_all(3)
	log_style.content_margin_left   = 6.0
	log_style.content_margin_right  = 6.0
	log_style.content_margin_top    = 6.0
	log_style.content_margin_bottom = 6.0
	log_bg.add_theme_stylebox_override("panel", log_style)
	_content_pane.add_child(log_bg)

	_log_rows_box = VBoxContainer.new()
	_log_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows_box.add_theme_constant_override("separation", 2)
	log_bg.add_child(_log_rows_box)

	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if not _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.connect(_rebuild_log_rows)
	_rebuild_log_rows()

# ─── Live refresh ─────────────────────────────────────────────────────────
func _refresh_live_values() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

	var needs: Dictionary = {
		"Health": float(_npc.health),
		"Energy": float(_npc.energy),
		"Hunger": float(_npc.hunger),
		"Thirst": float(_npc.thirst),
		"Mood": float(_npc.mood),
	}
	for need: String in needs.keys():
		var v: float = clampf(needs[need], 0.0, 100.0)
		var fill: ColorRect = _need_fills.get(need)
		var lbl: Label = _need_labels.get(need)
		if fill != null:
			fill.size = Vector2(NEEDS_BAR_TRACK_W * (v / 100.0), BAR_H)
			fill.color = NEED_COLORS.get(need, theme.ok)
		if lbl != null:
			lbl.text = str(int(round(v)))

	if "skills" in _npc:
		for skill: String in _skill_labels.keys():
			var s: float = float(_npc.skills.get(skill, 1.0))
			(_skill_labels[skill] as Label).text = "%s %d" % [skill.capitalize(), int(round(s * 10.0))]

	if _identity_task_label != null and "brain" in _npc and _npc.brain != null:
		_identity_task_label.text = _npc.brain.current_label()

	if _identity_age_label != null and ("age" in _npc):
		_identity_age_label.text = "Age %d" % int(_npc.age)

	if _trait_label != null and _npc.has_method("get_personality_words"):
		var words: Array[String] = _npc.get_personality_words()
		_trait_label.text = ", ".join(words) if not words.is_empty() else "Nothing stands out"

# ─── Buttons ──────────────────────────────────────────────────────────────
## Shared dispatch for every command button. Feedback is a plain
## NotificationManager toast confirming the command was ISSUED — not that
## it necessarily found something to do (e.g. "Harvest" still confirms
## even with nothing ready; the toast text itself says so, and the NPC
## visibly does nothing further, which is honest feedback on its own).
func _issue_command(activity: NPCActivity, action_desc: String, empty_desc: String) -> void:
	if _npc == null or not is_instance_valid(_npc) or not ("brain" in _npc) or _npc.brain == null:
		return
	_npc.brain.force_command(activity)
	if activity.done(_npc):
		NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			"%s: %s" % [_npc.npc_name, empty_desc])
	else:
		NotificationManager.feedback(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
			"%s: %s" % [_npc.npc_name, action_desc])

func _on_command_eat_pressed() -> void:
	_issue_command(EatActivity.new(), "heading to eat", "nothing to eat nearby")

func _on_command_drink_pressed() -> void:
	_issue_command(DrinkActivity.new(), "heading to get water", "no water source nearby")

func _on_command_rest_pressed() -> void:
	_issue_command(CommandRestActivity.new(), "heading to rest", "nowhere to rest nearby")

func _on_jobs_toggle_pressed() -> void:
	_jobs_expanded = not _jobs_expanded
	if _jobs_box != null:
		_jobs_box.visible = _jobs_expanded

## Same "asking during a conversation shouldn't count" relaxing-refusal
## guard the old Harvest-only handler had — applies to EVERY job type
## uniformly.
func _on_job_command_pressed(job_type: String) -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("is_relaxing") and _npc.is_relaxing():
		if _npc.has_method("request_job_while_relaxing") and not _npc.request_job_while_relaxing():
			if _dialogue_label != null and _npc.has_method("get_relaxing_refusal_line"):
				_dialogue_label.text = _npc.get_relaxing_refusal_line()
				_dialogue_label.visible = true
			return
	var entry: Dictionary = {}
	for e: Dictionary in NPC_JOB_MENU_ENTRIES:
		if String(e.get("type", "")) == job_type:
			entry = e
			break
	var action_desc: String = String(entry.get("action_desc", "heading to work"))
	var empty_desc: String = String(entry.get("empty_desc", "nothing to do right now"))
	if job_type == "CLEANING":
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_cleaning_unavailable_reason"):
			var reason: String = _npc.get_cleaning_unavailable_reason()
			if reason != "" and CLEANING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(CLEANING_UNAVAILABLE_REASONS[reason])
		_issue_command(CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_refuel_unavailable_reason"):
			var rreason: String = _npc.get_refuel_unavailable_reason()
			if rreason != "" and REFUEL_UNAVAILABLE_REASONS.has(rreason):
				empty_desc = String(REFUEL_UNAVAILABLE_REASONS[rreason])
		_issue_command(CommandRefuelActivity.new(), action_desc, empty_desc)
	elif job_type == "FARMING":
		var farm_cmd: CommandGardeningActivity = CommandGardeningActivity.new()
		farm_cmd.mode = "farming"
		_issue_command(farm_cmd, action_desc, empty_desc)
	elif job_type == "FERTILIZE":
		var fert_cmd: CommandGardeningActivity = CommandGardeningActivity.new()
		fert_cmd.mode = "fertilize_only"
		_issue_command(fert_cmd, action_desc, empty_desc)
	elif job_type == "COOKING":
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_cooking_unavailable_reason"):
			var creason: String = _npc.get_cooking_unavailable_reason()
			if creason != "" and COOKING_UNAVAILABLE_REASONS.has(creason):
				empty_desc = String(COOKING_UNAVAILABLE_REASONS[creason])
		_issue_command(CommandCookingActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(CommandJobActivity.new(job_type), action_desc, empty_desc)

# ─── Ask About (Part 23) ─────────────────────────────────────────────────
func _on_ask_about_player_pressed() -> void:
	_show_relationship_answer("player")

func _on_ask_about_npc_pressed(target_id: String) -> void:
	_show_relationship_answer(target_id)

func _show_relationship_answer(target_id: String) -> void:
	if _dialogue_label == null or _npc == null or not is_instance_valid(_npc):
		return
	if _npc.has_method("get_relationship_dialogue_line"):
		_dialogue_label.text = _npc.get_relationship_dialogue_line(target_id)
		_dialogue_label.visible = true

# ─── Action Log ───────────────────────────────────────────────────────────
func _rebuild_log_rows() -> void:
	if _log_rows_box == null:
		return
	for child: Node in _log_rows_box.get_children():
		child.queue_free()
	_log_time_labels.clear()
	_log_text_labels.clear()
	_log_entries = _npc.get_action_log() if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log") else []

	if _log_entries.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Nothing notable yet"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_font_override("font", UIKit.font())
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
		_log_rows_box.add_child(empty_lbl)
		return

	for entry: Dictionary in _log_entries:
		_log_rows_box.add_child(_make_log_row(entry))

func _make_log_row(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = "At %s" % str(entry.get("game_time", "?"))

	var text_lbl: Label = Label.new()
	text_lbl.text = str(entry["text"])
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", 12)
	text_lbl.add_theme_font_override("font", UIKit.font())
	text_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.90, 0.95))
	row.add_child(text_lbl)
	_log_text_labels.append(text_lbl)

	var time_lbl: Label = Label.new()
	time_lbl.text = _format_log_age(entry["fired_at_msec"] as int)
	time_lbl.custom_minimum_size = Vector2(52.0, 0.0)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.add_theme_font_override("font", UIKit.font())
	time_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72, 0.8))
	row.add_child(time_lbl)
	_log_time_labels.append(time_lbl)

	return row

func _format_log_age(fired_at_msec: int) -> String:
	var elapsed_sec: int = int((Time.get_ticks_msec() - fired_at_msec) / 1000.0)
	if elapsed_sec < 60:
		return "%ds ago" % elapsed_sec
	var elapsed_min: int = int(elapsed_sec / 60.0)
	if elapsed_min < 60:
		return "%dm ago" % elapsed_min
	var elapsed_hr: int = int(elapsed_min / 60.0)
	return "%dh ago" % elapsed_hr
