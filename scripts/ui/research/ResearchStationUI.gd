extends CanvasLayer
class_name ResearchStationUI
## ResearchStationUI.gd
## Aug 2026 — Part 1 of the Research Station feature. Shell only: modal
## chrome (matches WaterInfoUI/StorageUI conventions), 3 selectable tabs
## corresponding to the three upgrade trees, each with its own SEPARATE
## progress-state stub (empty/unused this pass). No buttons, no timers, no
## feed logic — those are the next pass. See UpgradeDef.gd for the data
## shape this will eventually populate.
##
## Modal-convention notes:
##  - Public `is_open` (StorageUI-style, NOT WaterInfoUI's private _is_open)
##    so InteractionSystem's existing "any modal UI open" gate reads it the
##    same way it reads shelf_ui/basket_ui — see InteractionSystem.gd.
##  - Owns the E/ESC dismiss in _unhandled_input like WaterInfoUI; the
##    E/F-dispatch gate in InteractionSystem does the blocking of world
##    input (Part 7 of the plan).
##  - Input.mouse_mode handled in open()/close() like StorageUI.

const TREES: Array[String] = ["bunker", "player_skills", "npc_skills"]
const TREE_LABELS: Dictionary = {
	"bunker":        "Bunker Upgrades",
	"player_skills": "Player Skills",
	"npc_skills":    "NPC Skills",
}

const PANEL_W: float = 520.0
const PANEL_H: float = 360.0
const TAB_H:   float = 40.0
const TAB_GAP: float = 6.0

const COLOR_BG:      Color = Color(0.08, 0.08, 0.09, 0.97)
const COLOR_BORDER:  Color = Color(0.55, 0.58, 0.62, 0.70)
const COLOR_TITLE:   Color = Color(0.80, 0.82, 0.86, 1.00)
const COLOR_TEXT:    Color = Color(0.85, 0.86, 0.88, 0.95)
const COLOR_DIM:     Color = Color(0.50, 0.52, 0.55, 0.80)
const COLOR_TAB_IDLE: Color = Color(0.14, 0.14, 0.16, 0.95)
const COLOR_TAB_ACTIVE: Color = Color(0.22, 0.30, 0.26, 1.00)
const COLOR_ACCENT:  Color = Color(0.40, 0.75, 0.55, 1.00)   ## research-teal domain stripe

var is_open: bool = false
var _active_tree: String = "bunker"

## Per-tree state, kept SEPARATE per your requirement ("separate tabs/trees
## with separate individual progress") — placeholder/empty this pass, real
## shape TBD once upgrades are actually defined (Part 4's UpgradeDef).
var _tree_state: Dictionary = {
	"bunker":        {},
	"player_skills": {},
	"npc_skills":    {},
}

var _root: Control = null
var _panel: Panel = null
var _title: Label = null
var _content: Label = null
var _tab_buttons: Dictionary = {}   ## tree_id -> Button
var _close_btn: Button = null
var _font: Font = null

func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_build_root()

func _build_root() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.50)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_root.add_child(backdrop)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color = COLOR_BG
	ss.set_corner_radius_all(8)
	ss.set_border_width_all(1)
	ss.border_color = COLOR_BORDER
	_panel.add_theme_stylebox_override("panel", ss)
	_root.add_child(_panel)

	var accent: ColorRect = ColorRect.new()
	accent.color = COLOR_ACCENT
	accent.size = Vector2(PANEL_W, 3.0)
	accent.position = Vector2(0.0, 0.0)
	_panel.add_child(accent)

	_title = Label.new()
	_title.text = "RESEARCH STATION"
	_title.add_theme_font_override("font", _font)
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", COLOR_TITLE)
	_title.position = Vector2(16.0, 14.0)
	_panel.add_child(_title)

	_close_btn = Button.new()
	_close_btn.flat = true
	_close_btn.text = "X"
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.add_theme_font_override("font", _font)
	_close_btn.add_theme_font_size_override("font_size", 16)
	_close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	_close_btn.pressed.connect(close)
	_close_btn.position = Vector2(PANEL_W - 42.0, 10.0)
	_close_btn.size = Vector2(32.0, 32.0)
	_panel.add_child(_close_btn)

	## 3 tab buttons across the top, wired to _select_tree()
	var tab_w: float = (PANEL_W - 32.0 - TAB_GAP * 2.0) / 3.0
	for i: int in TREES.size():
		var tree_id: String = TREES[i]
		var btn: Button = Button.new()
		btn.text = TREE_LABELS[tree_id]
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 13)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_select_tree.bind(tree_id))
		btn.position = Vector2(16.0 + float(i) * (tab_w + TAB_GAP), 52.0)
		btn.size = Vector2(tab_w, TAB_H)
		_panel.add_child(btn)
		_tab_buttons[tree_id] = btn

	_content = Label.new()
	_content.add_theme_font_override("font", _font)
	_content.add_theme_font_size_override("font_size", 13)
	_content.add_theme_color_override("font_color", COLOR_TEXT)
	_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.position = Vector2(16.0, 108.0)
	_content.size = Vector2(PANEL_W - 32.0, PANEL_H - 124.0)
	_panel.add_child(_content)

	_apply_tab_styles()
	_refresh_content()

func _center_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _style_tab(btn: Button, active: bool) -> void:
	var base: Color = COLOR_TAB_ACTIVE if active else COLOR_TAB_IDLE
	var fg: Color = COLOR_TEXT if active else COLOR_DIM
	for sname: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = base.lightened(0.15) if sname == "hover" else base
		sb.border_color = COLOR_ACCENT if active else COLOR_BORDER
		sb.set_border_width_all(1 if active else 0)
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override(sname, sb)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)

func _apply_tab_styles() -> void:
	for tree_id: String in TREES:
		var btn: Button = _tab_buttons.get(tree_id)
		if btn != null:
			_style_tab(btn, tree_id == _active_tree)

func open(_station: Node) -> void:
	is_open = true
	visible = true
	set_process(false)
	_center_panel()
	_apply_tab_styles()
	_refresh_content()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _select_tree(tree_id: String) -> void:
	if not TREES.has(tree_id):
		return
	_active_tree = tree_id
	_apply_tab_styles()
	_refresh_content()

func _refresh_content() -> void:
	## Placeholder only this pass — real per-tree content (upgrade
	## buttons/timers) is next pass's work.
	var label: String = String(TREE_LABELS.get(_active_tree, _active_tree))
	_content.text = "%s — upgrades coming in a later pass.\n\n(No feed/consumption logic yet; this shell proves the tab layout.)" % label

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()