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

const PANEL_W: float = 834.0   ## plan's 640 couldn't fit 3 grid cols + right-side branch col (4 × NODE_W) in the content area — widened; flagged for visual tuning
const PANEL_H: float = 756.0   ## plan's 620 couldn't fit the 2×2 materials grid (2 × 88px rows) + SCROLL_VISIBLE_H below it — widened; flagged
const TAB_H:   float = 40.0
const TAB_GAP: float = 6.0
const HEADER_MARGIN: float = 16.0
const MATERIAL_TOP_Y: float = 100.0   ## just below the tab row (tabs end at 92)

const SCROLL_VISIBLE_H: float = 460.0   ## ~3 rows' worth visible, rest scrolls
const CONTENT_TOP: float = 288.0   ## materials grid bottom (280) + 8

const NODE_W: float = 170.0
const NODE_H: float = 110.0      ## blank-box size
const TOP_NODE_H: float = 150.0  ## the tiered detail box is taller than blank boxes
const EXTRA_LINE_H: float = 16.0 ## per extra material-cost line
const COL_GAP: float = 30.0
const ROW_GAP: float = 40.0

const MATERIAL_BTN_W: float = NODE_W / 3.0
const MATERIAL_BTN_H: float = NODE_H * 0.8
const MATERIAL_COL_GAP: float = 10.0
const MATERIAL_ROW_GAP: float = 4.0

const COLOR_BG:      Color = Color(0.08, 0.08, 0.09, 0.97)
const COLOR_BORDER:  Color = Color(0.55, 0.58, 0.62, 0.70)
const COLOR_TITLE:   Color = Color(0.80, 0.82, 0.86, 1.00)
const COLOR_TEXT:    Color = Color(0.85, 0.86, 0.88, 0.95)
const COLOR_DIM:     Color = Color(0.50, 0.52, 0.55, 0.80)
const COLOR_TAB_IDLE: Color = Color(0.14, 0.14, 0.16, 0.95)
const COLOR_TAB_ACTIVE: Color = Color(0.22, 0.30, 0.26, 1.00)
const COLOR_ACCENT:  Color = Color(0.40, 0.75, 0.55, 1.00)   ## research-teal domain stripe
const COLOR_CONNECTOR: Color = Color(0.55, 0.58, 0.62, 0.45)
const COLOR_TIER_FILL: Color = Color(0.35, 0.62, 1.00, 1.00)   ## "filled blue" per plan
const COLOR_TIER_EMPTY: Color = Color(0.22, 0.24, 0.28, 0.90)

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
var _content_box: ScrollContainer = null
var _canvas: Control = null
var _connector_canvas: Control = null
var _connections: Array = []
var _material_labels: Dictionary = {}   ## material -> Label
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

	_build_materials_grid()

	_content_box = ScrollContainer.new()
	_content_box.position = Vector2(16.0, CONTENT_TOP)
	_content_box.size = Vector2(PANEL_W - 32.0, SCROLL_VISIBLE_H)
	_content_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_content_box)

	_canvas = Control.new()
	_canvas.size = Vector2(PANEL_W - 32.0, SCROLL_VISIBLE_H)
	_content_box.add_child(_canvas)

	_connector_canvas = Control.new()
	_connector_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connector_canvas.size = _canvas.size
	_connector_canvas.draw.connect(_on_connector_draw)
	_canvas.add_child(_connector_canvas)

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
	for material: String in ResearchStation.MATERIAL_TYPES:
		var lbl: Label = _material_labels.get(material)
		if lbl == null:
			continue
		var stored: int = 0
		if station != null:
			stored = station.stored_materials.get(material, 0)
		lbl.text = "%s: %d/%d" % [material.capitalize(), stored, ResearchStation.STORAGE_CAP]

func _clear_content() -> void:
	for child: Node in _canvas.get_children():
		if child == _connector_canvas:
			continue
		_canvas.remove_child(child)
		child.queue_free()
	_connections = []
	if _connector_canvas != null:
		_connector_canvas.queue_redraw()

## Blank bordered box — the structural scaffolding nodes (grid + branches),
## no text/data at all this pass.
func _build_blank_box() -> Control:
	var box: PanelContainer = PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	ss.border_color = COLOR_BORDER
	ss.set_border_width_all(1)
	ss.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", ss)
	box.custom_minimum_size = Vector2(NODE_W, NODE_H)
	box.size = Vector2(NODE_W, NODE_H)
	return box

## The single tiered upgrade node (top of the tree). Compact stacked order
## per the drawing: name -> materials (auto-expanding) -> time -> Research
## button -> tier-segment bar. Only this box is taller than NODE_H.
func _build_tiered_node(upgrade: UpgradeDef, station: ResearchStation) -> Control:
	var completed_tiers: int = station.tier_progress.get(upgrade.id, 0)
	var max_tier: int        = upgrade.get_max_tier()
	var is_maxed: bool       = completed_tiers >= max_tier
	var next_tier: int       = mini(completed_tiers + 1, max_tier)
	var display_title: String = "Tier %d - %s" % [next_tier, upgrade.display_name]

	## Cost lines — up to 2 materials per line; a 3rd/4th material starts a
	## new line and grows this box taller (its own downstream connector shifts
	## down accordingly).
	var cost_lines: Array[String] = []
	var pair: Array[String] = []
	for material: String in upgrade.material_costs.keys():
		pair.append("%dx %s" % [upgrade.material_costs[material], material.capitalize()])
		if pair.size() == 2:
			cost_lines.append("  ".join(pair))
			pair.clear()
	if not pair.is_empty():
		cost_lines.append("  ".join(pair))

	var box_h: float = TOP_NODE_H + EXTRA_LINE_H * maxi(0, cost_lines.size() - 1)

	var is_active: bool  = station.active_upgrade == upgrade
	var can_afford: bool = true
	for material: String in upgrade.material_costs.keys():
		if station.stored_materials.get(material, 0) < upgrade.material_costs[material]:
			can_afford = false
			break

	var root: Control = Control.new()
	root.custom_minimum_size = Vector2(NODE_W, box_h)
	root.size = Vector2(NODE_W, box_h)

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
	name_lbl.text = display_title
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	v.add_child(name_lbl)

	for line: String in cost_lines:
		var cost_lbl: Label = Label.new()
		cost_lbl.text = line
		cost_lbl.add_theme_font_override("font", _font)
		cost_lbl.add_theme_font_size_override("font_size", 11)
		cost_lbl.add_theme_color_override("font_color", COLOR_DIM)
		v.add_child(cost_lbl)

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
	btn.disabled = is_maxed or is_active or not can_afford
	btn.pressed.connect(func() -> void:
		if is_maxed or is_active or not can_afford:
			return
		if not station.start_research(upgrade):
			NotificationManager.notify(
				UIKit.Domain.NEUTRAL,
				NotificationManager.Severity.WARNING,
				"Already researching something else")
		_refresh_content()
	)
	v.add_child(btn)

	## Tier-segment bar — max_tier small segments, filled blue for the first
	## `completed_tiers`, unfilled for the rest.
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for i: int in max_tier:
		var seg: ColorRect = ColorRect.new()
		seg.custom_minimum_size = Vector2(20.0, 6.0)
		seg.color = COLOR_TIER_FILL if i < completed_tiers else COLOR_TIER_EMPTY
		bar.add_child(seg)
	v.add_child(bar)

	if is_maxed:
		## Horizontal "COMPLETED" banner — only when fully maxed, not after
		## individual tiers.
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
	elif not can_afford:
		box.modulate = Color(0.55, 0.55, 0.55, 0.8)

	return root

func _add_connection(a: Vector2, b: Vector2) -> void:
	_connections.append([a, b])

func _on_connector_draw() -> void:
	for conn: Array in _connections:
		var a: Vector2 = conn[0]
		var b: Vector2 = conn[1]
		_connector_canvas.draw_line(a, b, COLOR_CONNECTOR, 2.0)

## Builds the node-tree layout: row-0 tiered node, 3-column grid rows 1-4,
## two side branch pairs — all blank scaffolding except the top node.
func _build_tree_canvas(station: ResearchStation) -> void:
	var list: Array = _tree_upgrades.get(_active_tree, [])
	var top_upgrade: UpgradeDef = null
	for upgrade_node: Variant in list:
		var upgrade: UpgradeDef = upgrade_node as UpgradeDef
		if upgrade != null:
			top_upgrade = upgrade
			break

	var grid_w: float = 3.0 * NODE_W + 2.0 * COL_GAP
	var grid_left: float = HEADER_MARGIN
	var grid_right: float = grid_left + grid_w
	var branch_left: float = grid_right + COL_GAP
	var grid_cols: Array[float] = []
	for c: int in 3:
		grid_cols.append(grid_left + float(c) * (NODE_W + COL_GAP))

	## Row 0 — the tiered detail node, centered over the grid.
	var top_node: Control = null
	if top_upgrade != null:
		top_node = _build_tiered_node(top_upgrade, station)
	else:
		top_node = _build_blank_box()
	top_node.position = Vector2((grid_left + grid_right) * 0.5 - NODE_W * 0.5, 0.0)
	_canvas.add_child(top_node)
	var row0_h: float = top_node.size.y

	var row1_y: float = row0_h + ROW_GAP
	var row2_y: float = row1_y + NODE_H + ROW_GAP
	var row3_y: float = row2_y + NODE_H + ROW_GAP
	var row4_y: float = row3_y + NODE_H + ROW_GAP
	var row_ys: Array[float] = [row1_y, row2_y, row3_y, row4_y]

	## Rows 1-4: 3 blank boxes each.
	for r: int in 4:
		for c: int in 3:
			var box: Control = _build_blank_box()
			box.position = Vector2(grid_cols[c], row_ys[r])
			_canvas.add_child(box)

	## Vertical connectors: row 1 -> top node (all 3 up to the same node),
	## then row-to-row within each column.
	for c: int in 3:
		var col_cx: float = grid_cols[c] + NODE_W * 0.5
		_add_connection(Vector2(col_cx, row0_h), Vector2(col_cx, row1_y))
	for r: int in 3:
		for c: int in 3:
			var col_cx: float = grid_cols[c] + NODE_W * 0.5
			_add_connection(Vector2(col_cx, row_ys[r] + NODE_H), Vector2(col_cx, row_ys[r + 1]))

	## Right-side branch pair (2 blank boxes) beside rows 2-3: vertical line
	## between the pair, one diagonal from main-grid row 2 col 2.
	var rb1: Control = _build_blank_box()
	rb1.position = Vector2(branch_left, row2_y)
	_canvas.add_child(rb1)
	var rb2: Control = _build_blank_box()
	rb2.position = Vector2(branch_left, row3_y)
	_canvas.add_child(rb2)
	var rb_cx: float = branch_left + NODE_W * 0.5
	_add_connection(Vector2(rb_cx, row2_y + NODE_H), Vector2(rb_cx, row3_y))
	_add_connection(Vector2(grid_cols[2] + NODE_W, row2_y + NODE_H * 0.5), Vector2(rb_cx, row2_y))

	## Bottom-left branch pair (2 blank boxes) below row 4, one diagonal from
	## main-grid row 4 col 1.
	var bb1: Control = _build_blank_box()
	bb1.position = Vector2(grid_left, row4_y + NODE_H + ROW_GAP)
	_canvas.add_child(bb1)
	var bb2: Control = _build_blank_box()
	bb2.position = Vector2(grid_left, row4_y + NODE_H + ROW_GAP + NODE_H + ROW_GAP)
	_canvas.add_child(bb2)
	var bb_cx: float = grid_left + NODE_W * 0.5
	var bb1_y: float = row4_y + NODE_H + ROW_GAP
	_add_connection(Vector2(bb_cx, bb1_y + NODE_H), Vector2(bb_cx, bb1_y + NODE_H + ROW_GAP))
	_add_connection(Vector2(grid_cols[1] + NODE_W * 0.5, row4_y + NODE_H), Vector2(bb_cx, bb1_y))

	var canvas_h: float = bb1_y + NODE_H + ROW_GAP + NODE_H + 8.0
	_canvas.custom_minimum_size = Vector2(PANEL_W - 32.0, canvas_h)
	_canvas.size = Vector2(PANEL_W - 32.0, canvas_h)
	_connector_canvas.size = _canvas.size
	_connector_canvas.queue_redraw()

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
		_canvas.add_child(lbl)
		return
	_build_tree_canvas(station)

## Pinned 2x2 materials grid (Metal/Plastic left, Paper/Organic right),
## absolute within the fixed header area — does NOT scroll with the tree.
func _build_materials_grid() -> void:
	var col1_x: float = HEADER_MARGIN
	var col2_x: float = col1_x + MATERIAL_BTN_W + MATERIAL_COL_GAP
	var row1_y: float = MATERIAL_TOP_Y
	var row2_y: float = row1_y + MATERIAL_BTN_H + MATERIAL_ROW_GAP
	var cells: Array = [
		["metal",   col1_x, row1_y],
		["plastic", col1_x, row2_y],
		["paper",   col2_x, row1_y],
		["organic", col2_x, row2_y],
	]
	for cell: Array in cells:
		var material: String = cell[0]
		var panel: PanelContainer = PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var ss: StyleBoxFlat = StyleBoxFlat.new()
		ss.bg_color = Color(0.10, 0.10, 0.12, 0.95)
		ss.border_color = COLOR_BORDER
		ss.set_border_width_all(1)
		ss.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", ss)
		panel.position = Vector2(float(cell[1]), float(cell[2]))
		panel.size = Vector2(MATERIAL_BTN_W, MATERIAL_BTN_H)
		var lbl: Label = Label.new()
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COLOR_TEXT)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.text = "%s: %d/%d" % [material.capitalize(), 0, ResearchStation.STORAGE_CAP]
		panel.add_child(lbl)
		_panel.add_child(panel)
		_material_labels[material] = lbl

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