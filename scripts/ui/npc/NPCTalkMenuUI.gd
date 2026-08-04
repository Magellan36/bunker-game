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
const REFRESH_INTERVAL: float = 0.25
const PLACEHOLDER_LINE: String = "\"...\""

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
		personality_label.text = ", ".join(_npc.get_personality_words())
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
	_command_box.add_child(UIKit.make_button("Go eat something", _on_command_eat_pressed))
	_command_box.add_child(UIKit.make_button("Go drink something", _on_command_drink_pressed))
	_command_box.add_child(UIKit.make_button("Take a load off", _on_command_rest_pressed))
	_command_box.add_child(UIKit.make_button("Harvest the plants", _on_command_harvest_pressed))

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
	fill.color = theme.ok
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
			fill.color = theme.ok if v >= 50.0 else (theme.warn if v >= 25.0 else theme.crit)
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

func _on_command_harvest_pressed() -> void:
	_issue_command(NPCBrain.CommandHarvestActivity.new(), "heading to harvest", "nothing ready to harvest")

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