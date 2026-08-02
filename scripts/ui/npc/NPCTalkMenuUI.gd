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
const PANEL_H: float = 460.0
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

	## Needs
	_vbox.add_child(UIKit.make_section_label("NEEDS", theme))
	for need: String in ["Energy", "Hunger", "Thirst"]:
		_vbox.add_child(_build_need_row(need, theme))

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
		"Energy": float(_npc.energy),
		"Hunger": float(_npc.hunger),
		"Thirst": float(_npc.thirst),
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
			(_skill_labels[skill] as Label).text = "%s  %.2f" % [skill.capitalize(), s]

	if _activity_label != null and "brain" in _npc and _npc.brain != null:
		_activity_label.text = _npc.brain.current_label()

# ─── Buttons ──────────────────────────────────────────────────────────────
func _on_talk_pressed() -> void:
	if _dialogue_label != null:
		_dialogue_label.visible = true