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
var _current_station: ResearchStation = null

## List of UpgradeDefs per tree — this pass, "bunker" has exactly one entry
## (the water output resource from Part 1); the other two trees stay empty,
## matching last pass's placeholder-content state for those tabs.
var _tree_upgrades: Dictionary = {
	"bunker":        [preload("res://data/upgrades/bunker_water_output_2x.tres")],
	"player_skills": [],
	"npc_skills":    [],
}

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
var _content_box: Control = null
var _materials_label: Label = null
var _tab_buttons: Dictionary = {}   ## tree_id -> Button
var _close_btn: Button = null
var _font: Font = null

## While the panel is open, a short repeating timer refreshes progress bars /
## time-left labels / the persistent materials header (materials drain in the
## background even while a DIFFERENT tab than Bunker is selected, since the
## research keeps running regardless of which tab is showing).
var _refresh_timer: float = 0.0
const REFRESH_INTERVAL: float = 0.25

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

	_materials_label = Label.new()
	_materials_label.add_theme_font_override("font", _font)
	_materials_label.add_theme_font_size_override("font_size", 12)
	_materials_label.add_theme_color_override("font_color", COLOR_TEXT)
	_materials_label.position = Vector2(16.0, 104.0)
	_materials_label.size = Vector2(PANEL_W - 32.0, 20.0)
	_panel.add_child(_materials_label)

	_content_box = Control.new()
	_content_box.position = Vector2(16.0, 130.0)
	_content_box.size = Vector2(PANEL_W - 32.0, PANEL_H - 140.0)
	_panel.add_child(_content_box)

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

func open(station: Node) -> void:
	is_open = true
	_current_station = station as ResearchStation
	visible = true
	set_process(true)
	_refresh_timer = 0.0
	_center_panel()
	_apply_tab_styles()
	_refresh_materials_header()
	_refresh_content()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	_current_station = null
	visible = false
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not is_open:
		return
	## Background drain keeps running regardless of which tab is showing, so
	## refresh on a short repeating timer while open (see REFRESH_INTERVAL).
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_materials_header()
		_refresh_content()

func _select_tree(tree_id: String) -> void:
	if not TREES.has(tree_id):
		return
	_active_tree = tree_id
	_apply_tab_styles()
	_refresh_content()

## One label/icon per MATERIAL_TYPES entry: "Metal: 3/10" etc., always
## visible regardless of _active_tree — built once, refreshed every time the
## panel opens and on the repeating timer while open.
func _refresh_materials_header() -> void:
	var station: ResearchStation = _current_station
	if station == null:
		_materials_label.text = ""
		return
	var parts: Array[String] = []
	for material: String in ResearchStation.MATERIAL_TYPES:
		parts.append("%s: %d/%d" % [material.capitalize(), station.stored_materials.get(material, 0), ResearchStation.STORAGE_CAP])
	_materials_label.text = "  ".join(parts)

func _clear_content() -> void:
	for child: Node in _content_box.get_children():
		_content_box.remove_child(child)
		child.queue_free()

## Builds one button widget for a single upgrade — the ONLY place any
## upgrade-specific rendering logic lives, and it's entirely data-driven off
## the UpgradeDef passed in, never the upgrade's specific id/type. Returns a
## self-contained Control the caller positions into _content_box.
func _build_upgrade_button(upgrade: UpgradeDef, station: ResearchStation) -> Control:
	## Cost line — simple, static, no dynamic "missing amount" math per
	## direction ("just simple, no dynamic messaging needed").
	var cost_parts: Array[String] = []
	for material: String in upgrade.material_costs.keys():
		cost_parts.append("%dx %s" % [upgrade.material_costs[material], material.capitalize()])
	var cost_text: String = ", ".join(cost_parts)

	var is_completed: bool = station.completed_upgrade_ids.has(upgrade.id)
	var is_active: bool    = station.active_upgrade == upgrade
	var can_afford: bool   = true
	for material: String in upgrade.material_costs.keys():
		if station.stored_materials.get(material, 0) < upgrade.material_costs[material]:
			can_afford = false
			break

	var root: Control = Control.new()
	root.custom_minimum_size = Vector2(_content_box.size.x, 92.0)
	root.size = Vector2(_content_box.size.x, 92.0)

	var box: PanelContainer = PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	ss.border_color = COLOR_BORDER
	ss.set_border_width_all(1)
	ss.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", ss)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(box)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 10.0
	v.offset_top    = 8.0
	v.offset_right  = -10.0
	v.offset_bottom = -8.0
	box.add_child(v)

	var name_lbl: Label = Label.new()
	name_lbl.text = upgrade.display_name
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	v.add_child(name_lbl)

	var cost_lbl: Label = Label.new()
	cost_lbl.text = "Cost: %s" % cost_text
	cost_lbl.add_theme_font_override("font", _font)
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.add_theme_color_override("font_color", COLOR_DIM)
	v.add_child(cost_lbl)

	var progress: ProgressBar = ProgressBar.new()
	progress.min_value = 0.0
	progress.max_value = 100.0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0.0, 12.0)
	if is_active:
		var frac: float = clampf(station._elapsed / upgrade.duration_seconds, 0.0, 1.0)
		progress.value = frac * 100.0
	else:
		progress.value = 0.0
	v.add_child(progress)

	var time_lbl: Label = Label.new()
	time_lbl.add_theme_font_override("font", _font)
	time_lbl.add_theme_font_size_override("font_size", 11)
	if is_active:
		var remaining: int = ceili(maxf(upgrade.duration_seconds - station._elapsed, 0.0))
		time_lbl.text = "Time left: %ds" % remaining
		time_lbl.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		time_lbl.text = "Time to completion: %ds" % int(upgrade.duration_seconds)
		time_lbl.add_theme_color_override("font_color", COLOR_DIM)
	v.add_child(time_lbl)

	var btn: Button = UIKit.make_button("Research", Callable())
	btn.disabled = is_completed or is_active or not can_afford
	btn.pressed.connect(func() -> void:
		if is_completed or is_active or not can_afford:
			return
		if not station.start_research(upgrade):
			NotificationManager.notify(
				UIKit.Domain.NEUTRAL,
				NotificationManager.Severity.WARNING,
				"Already researching something else")
		_refresh_content()
	)
	v.add_child(btn)

	if is_completed:
		## Horizontal "COMPLETED" banner overlaid on top, visible only when
		## is_completed — per direction.
		var banner: ColorRect = ColorRect.new()
		banner.color = Color(0.0, 0.0, 0.0, 0.72)
		banner.set_anchors_preset(Control.PRESET_FULL_RECT)
		banner.mouse_filter = Control.MOUSE_FILTER_STOP
		var banner_lbl: Label = Label.new()
		banner_lbl.text = "COMPLETED"
		banner_lbl.add_theme_font_override("font", _font)
		banner_lbl.add_theme_font_size_override("font_size", 14)
		banner_lbl.add_theme_color_override("font_color", COLOR_ACCENT)
		banner_lbl.set_anchors_preset(Control.PRESET_CENTER)
		banner.add_child(banner_lbl)
		box.add_child(banner)

	## Disabled/greyed (modulate dimmed) when NOT completed and NOT affordable
	if not is_completed and not can_afford:
		box.modulate = Color(0.55, 0.55, 0.55, 0.8)

	return root

func _refresh_content() -> void:
	_clear_content()
	_refresh_materials_header()
	var station: ResearchStation = _current_station
	if station == null:
		return
	var list: Array = _tree_upgrades.get(_active_tree, [])
	if list.is_empty():
		var lbl: Label = Label.new()
		lbl.text = "%s — upgrades coming in a later pass.\n\n(No upgrades defined for this tree yet.)" % String(TREE_LABELS.get(_active_tree, _active_tree))
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", COLOR_DIM)
		lbl.position = Vector2(0.0, 8.0)
		lbl.size = _content_box.size
		_content_box.add_child(lbl)
		return
	var y: float = 0.0
	for upgrade_node: Variant in list:
		var upgrade: UpgradeDef = upgrade_node as UpgradeDef
		if upgrade == null:
			continue
		var widget: Control = _build_upgrade_button(upgrade, station)
		widget.position = Vector2(0.0, y)
		_content_box.add_child(widget)
		y += widget.size.y + 8.0

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