extends CanvasLayer
class_name NPCTalkMenuUI
## NPCTalkMenuUI.gd  (rewritten in NPC Pass 2, Part 5 — full NPC panel)
## Opened by NPC.on_interact(). Shows live needs bars, skills, current
## activity, and the Talk button (placeholder dialogue retained from Pass 1).
## Built entirely on UIKit's shared menu builders (NEUTRAL theme).
##
## FUTURE WORK (build nothing yet):
##   - Command/priority buttons ("Prioritize this", job toggles) go under
##     the skills block once the player-orders pass lands.
##   - A bunker-wide "Residents" roster panel (hotkey, all NPCs at once).

const PANEL_W: float = 380.0
const PANEL_H: float = 900.0   ## Part 23 — bumped again for the Ask About
                               ## relationship Q&A section (label + "about
                               ## me" button + one button per other live NPC,
                               ## typically 1-2 in a small bunker); retune
                               ## visually once content is fully settled
                               ## (same standing note as Part 20's bump)
const BAR_H: float = 14.0

## Action Log (Aug 2026) — extra height the panel grows by when the log
## dropdown is expanded; shrinks back when collapsed. Log area itself
## stays a fixed, modest size (LOG_AREA_H) — the scroll happens inside
## it, the panel doesn't grow to fit unlimited entries.
const LOG_AREA_H: float = 220.0
const LOG_TOGGLE_BUTTON_H: float = 32.0
const LOG_SECTION_H: float = LOG_AREA_H + LOG_TOGGLE_BUTTON_H + 8.0

## Generous fixed bump covering the Requests box (4 buttons) plus the
## Jobs sub-list (currently 4 entries, grows as job types are added) —
## simplification: ONE combined bump rather than precisely tracking two
## separate additive heights, same "retune visually later" spirit as
## every other PANEL_H bump in this file's history.
const REQUESTS_SECTION_H: float = 260.0

## Aug 2026 — fixed per-stat identity colors, matching the player's own
## NeedsGauge convention (one color per stat, always, regardless of
## current fill — NOT recolored by value the way this panel used to).
## Health/Energy/Thirst are exact copies of NeedsGauge's
## COLOR_HEALTH/COLOR_SLEEP/COLOR_WATER. Hunger has no player-HUD yellow
## to copy (the player has no yellow stat), so it reuses the project's
## other established yellow (Power panels' stripe color) instead of a new
## one. Mood is Brannon's exact #bca0dc via Color8 (0-255 ints), no
## float-rounding.
const NEED_COLORS: Dictionary = {
	"Health": Color(0.81, 0.17, 0.17, 1.0),
	"Energy": Color(0.57, 0.33, 0.81, 1.0),
	"Hunger": Color(0.90, 0.80, 0.20, 1.0),
	"Thirst": Color(0.24, 0.52, 0.90, 1.0),
	"Mood":   Color8(188, 160, 220, 255),
}
const REFRESH_INTERVAL: float = 0.25
const PLACEHOLDER_LINE: String = "\"...\""

## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (HARVEST/REPLACE_FILTER), or the literal strings "CLEANING"/"REFUEL"
## (routed to CommandCleaningActivity/CommandRefuelActivity instead of
## the generic CommandJobActivity, since neither is JobBoard-claimed).
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "HARVEST", "label": "Harvest the plants", "action_desc": "heading to harvest", "empty_desc": "nothing ready to harvest"},
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
]

## Aug 2026 — maps NPC.get_cleaning_unavailable_reason()'s keys to the
## exact player-facing toast text. Keep in sync with that function's own
## doc comment if the reason set ever changes. Falls back to the generic
## "nothing to clean right now" (NPC_JOB_MENU_ENTRIES' empty_desc) for any
## key not listed here, including "" (available).
const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN":     "nothing to clean right now",
	"NO_TRASH_RECEPTACLE":  "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING":       "everything's still settling — check back shortly",
	"ALL_CLAIMED":          "everything's already being handled by someone else",
	"NO_STORAGE_AVAILABLE": "there's nothing to put things away in",
	"STORAGE_FULL":         "storage is full",
}

var _npc: Node = null
var _backdrop: ColorRect = null
var _panel: Panel = null
var _vbox: VBoxContainer = null
var _is_open: bool = false
var _refresh_timer: float = 0.0

## Live-updating widgets, rebuilt on open
var _need_fills: Dictionary = {}    ## need name -> ColorRect (fill)
var _need_labels: Dictionary = {}   ## need name -> Label (value text)
var _skill_labels: Dictionary = {}  ## skill name -> Label
var _activity_label: Label = null
var _dialogue_label: Label = null   ## hidden until Talk pressed
var _status_label: Label = null     ## Part 14
var _command_box: VBoxContainer = null   ## Part 19
var _relationship_box: VBoxContainer = null   ## Part 23
var _log_expanded: bool = false
var _log_toggle_button: Button = null
var _log_scroll: ScrollContainer = null
var _log_rows_box: VBoxContainer = null
var _log_entries: Array[Dictionary] = []
var _requests_toggle_button: Button = null
var _requests_box: VBoxContainer = null
var _requests_expanded: bool = false
var _jobs_box: VBoxContainer = null
var _jobs_expanded: bool = false
var _log_time_labels: Array[Label] = []
var _log_text_labels: Array[Label] = []

const BAR_TRACK_W: float = 200.0

func _ready() -> void:
	layer = 70
	visible = false

func open(npc_name: String, npc: Node = null) -> void:
	_npc = npc
	_is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build(npc_name)

func close() -> void:
	_is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_teardown()

func _teardown() -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.disconnect(_rebuild_log_rows)
	_log_expanded = false
	_requests_expanded = false
	_jobs_expanded = false
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_backdrop = null
	_panel = null
	_vbox = null
	_need_fills = {}
	_need_labels = {}
	_skill_labels = {}
	_activity_label = null
	_dialogue_label = null
	_status_label = null
	_command_box = null
	_relationship_box = null

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

	## Action Log (Aug 2026) — live "Xs ago" timestamps while expanded.
	if _log_expanded:
		for i: int in range(_log_time_labels.size()):
			if i >= _log_entries.size():
				continue
			_log_time_labels[i].text = _format_log_age(_log_entries[i]["fired_at_msec"] as int)
		## Live hostile entry — always the newest, so always index 0 if
		## present. get_action_log()'s shallow duplicate means _log_entries[0]
		## is the SAME dictionary NPC.gd keeps mutating in update_hostile_log()
		## — just re-read its current text, no extra query needed.
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
	var ps: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	ps.content_margin_left = 20.0
	ps.content_margin_right = 20.0
	ps.content_margin_top = 16.0
	ps.content_margin_bottom = 16.0
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

	## Name
	var title: Label = Label.new()
	title.text = npc_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_TITLE)
	title.add_theme_color_override("font_color", theme.header)
	title.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(title)

	## Current activity
	_activity_label = Label.new()
	_activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_activity_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_activity_label.add_theme_color_override("font_color", theme.dim)
	_activity_label.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(_activity_label)

	_vbox.add_child(HSeparator.new())

	## Needs (+ Health, Part 14 — same bar style, reads _npc.health directly)
	_vbox.add_child(UIKit.make_section_label("NEEDS", theme))
	for need: String in ["Health", "Energy", "Hunger", "Thirst", "Mood"]:
		_vbox.add_child(_build_need_row(need, theme))

	_vbox.add_child(HSeparator.new())

	## Status (Part 14) — plain-text summary from NPC.get_status_labels();
	## never shown in the overhead hover prompt, per Brannon's instruction —
	## this panel only.
	_vbox.add_child(UIKit.make_section_label("STATUS", theme))
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_status_label.add_theme_color_override("font_color", theme.text)
	_status_label.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(_status_label)

	_vbox.add_child(HSeparator.new())

	## Personality (Part 20) — fixed per NPC, shown as descriptive words
	## only, never raw trait numbers. Computed once here since traits never
	## change after spawn.
	_vbox.add_child(UIKit.make_section_label("PERSONALITY", theme))
	var personality_label: Label = Label.new()
	personality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	personality_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	personality_label.add_theme_color_override("font_color", theme.text)
	personality_label.add_theme_font_override("font", UIKit.font())
	if _npc != null and _npc.has_method("get_personality_words"):
		var words: Array[String] = _npc.get_personality_words()
		personality_label.text = ", ".join(words) if not words.is_empty() else "Nothing stands out"
	_vbox.add_child(personality_label)

	_vbox.add_child(HSeparator.new())

	## Skills
	_vbox.add_child(UIKit.make_section_label("SKILLS", theme))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	_vbox.add_child(grid)
	for skill: String in ["farming", "plumbing", "electrical", "construction"]:
		var lbl: Label = UIKit.make_row_label("", theme)
		grid.add_child(lbl)
		_skill_labels[skill] = lbl

	_vbox.add_child(HSeparator.new())

	## Dialogue line (hidden until Talk)
	_dialogue_label = Label.new()
	_dialogue_label.text = PLACEHOLDER_LINE
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dialogue_label.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_BODY)
	_dialogue_label.add_theme_color_override("font_color", theme.text)
	_dialogue_label.add_theme_font_override("font", UIKit.font())
	_dialogue_label.visible = false
	_vbox.add_child(_dialogue_label)

	## Commands (Part 19) — revealed alongside dialogue when Talk is pressed.
	## Each button force-starts an existing NPCBrain activity directly,
	## bypassing normal need-based scoring — the player explicitly asked for
	## this action right now. Reuses the SAME activity classes the automatic
	## system already uses, so behavior is identical either way.
	## FUTURE WORK: this list intentionally matches Brannon's explicit
	## examples only — adding more later is one button + one dispatch call,
	## nothing structural.
	_command_box = VBoxContainer.new()
	_command_box.add_theme_constant_override("separation", 4)
	_command_box.visible = false
	_vbox.add_child(_command_box)
	_requests_toggle_button = UIKit.make_button("Requests", _on_requests_toggle_pressed)
	_command_box.add_child(_requests_toggle_button)

	_requests_box = VBoxContainer.new()
	_requests_box.add_theme_constant_override("separation", 4)
	_requests_box.visible = false
	_command_box.add_child(_requests_box)
	_requests_box.add_child(UIKit.make_button("Can you go eat something?", _on_command_eat_pressed))
	_requests_box.add_child(UIKit.make_button("Can you go drink something?", _on_command_drink_pressed))
	_requests_box.add_child(UIKit.make_button("Take a load off", _on_command_rest_pressed))
	_requests_box.add_child(UIKit.make_button("Can you complete this job?", _on_jobs_toggle_pressed))

	_jobs_box = VBoxContainer.new()
	_jobs_box.add_theme_constant_override("separation", 4)
	_jobs_box.visible = false
	_command_box.add_child(_jobs_box)
	for entry: Dictionary in NPC_JOB_MENU_ENTRIES:
		var job_type: String = String(entry.get("type", ""))
		var label_text: String = String(entry.get("label", job_type))
		_jobs_box.add_child(UIKit.make_button(label_text, Callable(self, "_on_job_command_pressed").bind(job_type)))

	## Ask About (Part 23) — relationship Q&A. Reveals alongside dialogue/
	## commands when Talk is pressed. Answer reuses _dialogue_label above
	## (swaps its text) rather than a second label, since it's the same
	## "NPC said a line" moment, just player-triggered by topic instead of
	## automatic.
	_relationship_box = VBoxContainer.new()
	_relationship_box.add_theme_constant_override("separation", 4)
	_relationship_box.visible = false
	_vbox.add_child(_relationship_box)
	_relationship_box.add_child(UIKit.make_section_label("ASK ABOUT", theme))
	_relationship_box.add_child(UIKit.make_button("What do you think of me?", _on_ask_about_player_pressed))
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_other_npc_topics"):
		for topic: Dictionary in _npc.get_other_npc_topics():
			var target_id: String = String(topic.get("id", ""))
			var target_name: String = String(topic.get("name", "them"))
			_relationship_box.add_child(UIKit.make_button(
				"What do you think of %s?" % target_name,
				Callable(self, "_on_ask_about_npc_pressed").bind(target_id)))

	## Buttons
	_vbox.add_child(UIKit.make_button("Talk", _on_talk_pressed))
	_vbox.add_child(UIKit.make_button("Close", close))

	## Action Log (Aug 2026) — collapsed by default on every fresh open,
	## deliberately not remembered across panel reopens.
	_log_toggle_button = UIKit.make_button("Show Activity Log ▾", _on_log_toggle_pressed)
	_vbox.add_child(_log_toggle_button)

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
	log_bg.custom_minimum_size = Vector2(0.0, LOG_AREA_H)
	log_bg.visible = false
	_vbox.add_child(log_bg)

	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_bg.add_child(_log_scroll)

	_log_rows_box = VBoxContainer.new()
	_log_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows_box.add_theme_constant_override("separation", 2)
	_log_scroll.add_child(_log_rows_box)

	if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_action_log"):
		if not _npc.action_logged.is_connected(_rebuild_log_rows):
			_npc.action_logged.connect(_rebuild_log_rows)
	_rebuild_log_rows()

	_refresh_live_values()
	UIFade.fade_in(_panel)

func _build_need_row(need: String, theme: UIKit.UITheme) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_lbl: Label = UIKit.make_row_label(need, theme)
	name_lbl.custom_minimum_size = Vector2(70.0, 0.0)
	name_lbl.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(name_lbl)

	var track: ColorRect = ColorRect.new()
	track.color = Color(0.10, 0.10, 0.12, 1.0)
	track.custom_minimum_size = Vector2(BAR_TRACK_W, BAR_H)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(track)

	var fill: ColorRect = ColorRect.new()
	fill.color = NEED_COLORS.get(need, theme.ok)
	fill.position = Vector2.ZERO
	fill.size = Vector2(BAR_TRACK_W, BAR_H)
	track.add_child(fill)
	_need_fills[need] = fill

	var val: Label = UIKit.make_row_label("100", theme)
	val.custom_minimum_size = Vector2(36.0, 0.0)
	val.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(val)
	_need_labels[need] = val

	return row

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
			fill.size = Vector2(BAR_TRACK_W * (v / 100.0), BAR_H)
			fill.color = NEED_COLORS.get(need, theme.ok)   ## Aug 2026 — fixed per-stat color, no longer recolors by value
		if lbl != null:
			lbl.text = str(int(round(v)))

	if "skills" in _npc:
		for skill: String in _skill_labels.keys():
			var s: float = float(_npc.skills.get(skill, 1.0))
			(_skill_labels[skill] as Label).text = "%s  %d" % [skill.capitalize(), int(round(s * 10.0))]

	if _activity_label != null and "brain" in _npc and _npc.brain != null:
		_activity_label.text = _npc.brain.current_label()

	if _status_label != null and _npc.has_method("get_status_labels"):
		_status_label.text = "\n".join(_npc.get_status_labels())

# ─── Buttons ──────────────────────────────────────────────────────────────
func _on_talk_pressed() -> void:
	if _dialogue_label != null:
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_dialogue_line"):
			_dialogue_label.text = _npc.get_dialogue_line()   ## Part 20 — picked fresh each press
		_dialogue_label.visible = true
	if _command_box != null:
		_command_box.visible = true
	if _relationship_box != null:
		_relationship_box.visible = true

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
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			"%s: %s" % [_npc.npc_name, empty_desc])
	else:
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
			"%s: %s" % [_npc.npc_name, action_desc])

func _on_command_eat_pressed() -> void:
	_issue_command(NPCBrain.EatActivity.new(), "heading to eat", "nothing to eat nearby")

func _on_command_drink_pressed() -> void:
	_issue_command(NPCBrain.DrinkActivity.new(), "heading to get water", "no water source nearby")

func _on_command_rest_pressed() -> void:
	_issue_command(NPCBrain.CommandRestActivity.new(), "heading to rest", "nowhere to rest nearby")

func _on_requests_toggle_pressed() -> void:
	_requests_expanded = not _requests_expanded
	_requests_toggle_button.text = "Requests ▴" if _requests_expanded else "Requests"
	if _requests_box != null:
		_requests_box.visible = _requests_expanded
	if not _requests_expanded and _jobs_box != null:
		## collapsing Requests also collapses Jobs so it doesn't linger
		## open behind a now-hidden parent
		_jobs_box.visible = false
		_jobs_expanded = false
	_refresh_panel_height()

func _on_jobs_toggle_pressed() -> void:
	_jobs_expanded = not _jobs_expanded
	if _jobs_box != null:
		_jobs_box.visible = _jobs_expanded
	_refresh_panel_height()

## Same "asking during a conversation shouldn't count" relaxing-refusal
## guard the old Harvest-only handler had — now applies to EVERY job
## type uniformly, fulfilling the note left in an earlier plan about
## extending this to future job buttons.
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
		## Aug 2026 — swap the generic empty_desc for a specific reason
		## when we have one, so the player sees exactly WHY instead of a
		## blanket "nothing to clean right now" every time.
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_cleaning_unavailable_reason"):
			var reason: String = _npc.get_cleaning_unavailable_reason()
			if reason != "" and CLEANING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(CLEANING_UNAVAILABLE_REASONS[reason])
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		_issue_command(NPCBrain.CommandRefuelActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)

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

# ─── Action Log (Aug 2026) ───────────────────────────────────────────────
func _on_log_toggle_pressed() -> void:
	_log_expanded = not _log_expanded
	_log_toggle_button.text = "Hide Activity Log ▴" if _log_expanded else "Show Activity Log ▾"
	## The log_bg panel is the sibling right after the toggle button —
	## found by index rather than a stored reference to keep this
	## function self-contained.
	var log_idx: int = _log_toggle_button.get_index() + 1
	if log_idx < _vbox.get_child_count():
		_vbox.get_child(log_idx).visible = _log_expanded
	_refresh_panel_height()

## Combines every section that can currently be expanded — Log and
## Requests/Jobs both call this instead of computing height independently,
## so they stack correctly rather than overwriting each other's contribution.
func _refresh_panel_height() -> void:
	var height: float = PANEL_H
	if _log_expanded:
		height += LOG_SECTION_H
	if _requests_expanded:
		height += REQUESTS_SECTION_H
	_apply_panel_height(height)

## Resizes and re-centers the panel — mirrors UIKit.build_centered_panel()'s
## own centering math, since that helper has no public "resize" method.
func _apply_panel_height(height: float) -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(PANEL_W, height)
	_panel.offset_top    = -height * 0.5
	_panel.offset_bottom =  height * 0.5

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