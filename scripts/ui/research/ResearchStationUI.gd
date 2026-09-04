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

const PANEL_W: float = 1024.0  ## widened so the mirrored left branch + right branch both stay on-canvas with horizontal scroll disabled (Part 7 of the polish pass); flagged for visual tuning
const TAB_H:   float = 40.0
const TAB_GAP: float = 6.0
const HEADER_MARGIN: float = 16.0
const MATERIAL_TOP_Y: float = 100.0   ## just below the tab row (tabs end at 92)

const SCROLL_VISIBLE_H: float = 460.0   ## ~3 rows' worth visible, rest scrolls

const NODE_W: float = 170.0
const NODE_H: float = 110.0      ## blank-box size
const TOP_NODE_H: float = 150.0  ## the tiered detail box is taller than blank boxes
const EXTRA_LINE_H: float = 16.0 ## per extra material-cost line
const COL_GAP: float = 30.0
const ROW_GAP: float = 40.0

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

## Material icon textures — replace the "Metal:"/"Plastic:" etc. name text
## in the materials header grid. Keys match ResearchStation.MATERIAL_TYPES.
const MATERIAL_ICONS: Dictionary = {
	"metal":   preload("res://assets/icons/icon_material_metal.png"),
	"plastic": preload("res://assets/icons/icon_material_plastic.png"),
	"paper":   preload("res://assets/icons/icon_material_paper.png"),
	"organic": preload("res://assets/icons/icon_material_organic.png"),
}
const MATERIAL_ICON_SIZE: Vector2 = Vector2(12.0, 12.0)
const MATERIAL_ICON_BUFFER: float = 6.0    ## left inset for the icon
const MATERIAL_COUNT_BUFFER: float = 6.0   ## right inset for the "x/10" label

## Clock icon shown to the left of the duration / "Time left" text on each
## research card. Interior of the ring is pre-filled opaque white; outside
## the ring stays transparent — do not swap for a differently-prepared file.
const CLOCK_ICON_TEXTURE: Texture2D = preload("res://assets/icons/icon_clock.png")
const CLOCK_ICON_SIZE: Vector2 = Vector2(12.0, 12.0)

# ─── Controller prompt icons (Aug 2026) ───────────────────────────────────────
## Same 16px pixel set InteractPrompt/StorageUI use. A shows in front of the
## Research button (activates it); LB/RB badge the tab bar (cycle trees).
const XBOX_A_ICON: Texture2D = preload("res://assets/ui/prompts/XBOX_A.png")
const XBOX_LB_ICON: Texture2D = preload("res://assets/ui/prompts/XBOX_LB.png")
const XBOX_RB_ICON: Texture2D = preload("res://assets/ui/prompts/XBOX_RB.png")
const TAB_BADGE_SIZE: float = 20.0

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

## Controller (Aug 2026): LB/RB cycle badges pinned to the bunker (LB) and
## NPC Skills (RB) tab buttons, shown in controller mode.
var _lb_badge: TextureRect = null
var _rb_badge: TextureRect = null
## The top tiered node's SELECTION OVERLAY (focus target) + its Research
## button — the A-activated target. Set during _build_tiered_node(), nulled
## on content clear.
var _top_tile_box: Control = null
var _research_btn: Button = null

## Cached during _build_tiered_node() — set to null whenever the node isn't
## currently built (e.g. wrong tab active), so the passive tick never writes
## into a stale node. See Part 2 of the polish pass (hover-bug fix).
var _active_progress_bar: ProgressBar = null
var _active_time_label: Label         = null

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

	## Controller navigation (Aug 2026) — d-pad moves focus across the
	## research TILES (white outline on the selected one); B closes. RB/LB
	## cycle the tabs (handled in _unhandled_input); A activates the focused
	## tile's Research button. See scripts/ui/common/ControllerUINavigation.gd.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	add_child(controller_nav)

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_build_root()

func _build_root() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	## Materials grid size computed first so the panel can size itself to fit
	## it (short/tight buttons now, not the old 88px rows) — see Part 1.
	var btn_size: Vector2 = _compute_material_btn_size()
	var grid_bottom: float = MATERIAL_TOP_Y + btn_size.y * 2.0 + MATERIAL_ROW_GAP
	var content_top: float = grid_bottom + 8.0
	var panel_h: float     = content_top + SCROLL_VISIBLE_H + 24.0

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.50)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_root.add_child(backdrop)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(PANEL_W, panel_h)
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
	_close_btn.focus_mode = Control.FOCUS_NONE   ## mouse-only; B closes
	_close_btn.position = Vector2(PANEL_W - 42.0, 10.0)
	_close_btn.size = Vector2(32.0, 32.0)
	_panel.add_child(_close_btn)

	## 3 tab buttons across the top, wired to _select_tree(). RB/LB cycle
	## them; they are NOT d-pad targets (FOCUS_NONE).
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
		## LB badge on the first tab (Bunker Upgrades) and RB badge on the
		## last tab (NPC Skills) — controller mode only.
		if tree_id == TREES[0]:
			_lb_badge = _make_tab_badge(btn, XBOX_LB_ICON, true)
		elif tree_id == TREES[TREES.size() - 1]:
			_rb_badge = _make_tab_badge(btn, XBOX_RB_ICON, false)

	_build_materials_grid()

	_content_box = ScrollContainer.new()
	_content_box.position = Vector2(16.0, content_top)
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

## Controller tab badge (Aug 2026): a small icon pinned to a corner of a tab
## button (LB top-left on the first tab, RB top-right on the last), shown in
## controller mode via _refresh_controller_hints().
func _make_tab_badge(btn: Button, icon: Texture2D, top_left: bool) -> TextureRect:
	var badge := TextureRect.new()
	badge.texture = icon
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT if top_left else Control.PRESET_TOP_RIGHT)
	badge.offset_left   = 2.0 if top_left else -TAB_BADGE_SIZE - 2.0
	badge.offset_top    = 2.0
	badge.offset_right  = 2.0 + TAB_BADGE_SIZE if top_left else -2.0
	badge.offset_bottom = 2.0 + TAB_BADGE_SIZE
	btn.add_child(badge)
	return badge

## Makes a research tile d-pad selectable via a transparent overlay Control.
## The tiles themselves are PanelContainers, which the nav's focusable
## collection skips (Container exclusion) — so a plain Control overlay is the
## focus target. It draws a white rounded selection outline when focused
## (same style as the other controller selection indicators). Returns the
## overlay so callers can track the top tile.
func _enable_tile_selection(box: Control) -> Control:
	var sel := Control.new()
	sel.name = "TileSelector"
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.focus_mode = Control.FOCUS_ALL
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var focus_ss: StyleBoxFlat = StyleBoxFlat.new()
	focus_ss.draw_center = false
	focus_ss.border_color = Color.WHITE
	focus_ss.set_border_width_all(2)
	focus_ss.set_corner_radius_all(4)
	sel.add_theme_stylebox_override("focus", focus_ss)
	box.add_child(sel)
	return sel

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
	## Controller (Aug 2026) — auto-select the top-most research on open so
	## A is immediately ready to research (the _process null-focus fallback
	## below is a safety net; this fires instantly).
	if InputMode.is_controller() and _top_tile_box != null:
		_top_tile_box.grab_focus()
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
	## Only the lightweight in-place tick runs here — never a full rebuild —
	## or the Research button would flicker on hover (Part 2 of the polish
	## pass: Godot doesn't retro-mark freshly-rebuilt Controls as hovered).
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_materials_header()
		_tick_active_progress()
	## Controller (Aug 2026): keep a tile selected in controller mode and
	## refresh the prompt hints (A icon, LB/RB tab badges).
	if InputMode.is_controller():
		if get_viewport().gui_get_focus_owner() == null and _top_tile_box != null:
			_top_tile_box.grab_focus()
	_refresh_controller_hints()

## Controller prompt hints (Aug 2026): shows the Xbox A icon in front of the
## Research button and the LB/RB tab-cycle badges, all only in controller
## mode. Tile selection outlines are the boxes' own focus styleboxes — no
## per-frame mutation needed.
func _refresh_controller_hints() -> void:
	var controller: bool = InputMode.is_controller()
	if _research_btn != null and is_instance_valid(_research_btn):
		_research_btn.icon = XBOX_A_ICON if controller else null
	if _lb_badge != null:
		_lb_badge.visible = controller
	if _rb_badge != null:
		_rb_badge.visible = controller

## RB (right) / LB (left) cycle the tree tabs, wrapping.
func _cycle_tree(dir: int) -> void:
	var idx: int = TREES.find(_active_tree)
	if idx == -1:
		return
	_select_tree(TREES[(idx + dir + TREES.size()) % TREES.size()])

## In-place update of the live-changing parts of the currently-active
## research's node, if one is being displayed right now. Never touches
## Button/Panel nodes — this is exactly what fixes the hover bug, since the
## Control the mouse is hovering over is never destroyed by a passive tick.
func _tick_active_progress() -> void:
	var station: ResearchStation = _current_station
	if station == null:
		return
	if station.active_upgrade == null:
		## The research that WAS active may have just completed inside the
		## station's own _process — rebuild so the card shows its new state
		## (the plan's "completion triggers a rebuild" needs this detection,
		## since completion isn't a UI action; flagged).
		if _active_progress_bar != null or _active_time_label != null:
			_refresh_content()
		return
	if _active_progress_bar == null or _active_time_label == null:
		return   ## active research's node isn't the one currently displayed (different tab) — nothing to update
	var upgrade: UpgradeDef = station.active_upgrade
	var frac: float = clampf(station._elapsed / upgrade.duration_seconds, 0.0, 1.0)
	_active_progress_bar.value = frac * 100.0
	if not station.is_paused:
		var remaining: float = maxf(upgrade.duration_seconds - station._elapsed, 0.0)
		_active_time_label.text = "Time left: %s" % _format_duration(remaining)

func _select_tree(tree_id: String) -> void:
	if not TREES.has(tree_id):
		return
	_active_tree = tree_id
	_apply_tab_styles()
	_refresh_content()
	## Controller (Aug 2026) — auto-select the top-most research of the new
	## tab so A is immediately ready after an LB/RB tab change.
	if InputMode.is_controller() and _top_tile_box != null:
		_top_tile_box.grab_focus()

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
		lbl.text = "%d/%d" % [stored, ResearchStation.STORAGE_CAP]

func _clear_content() -> void:
	for child: Node in _canvas.get_children():
		if child == _connector_canvas:
			continue
		_canvas.remove_child(child)
		child.queue_free()
	_connections = []
	_active_progress_bar = null
	_active_time_label   = null
	_top_tile_box        = null
	_research_btn        = null
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
	_enable_tile_selection(box)
	return box

## Shared formatter — used for both the not-started time label (Part 5) and
## the "Time left" label (Part 2's tick update), so both read consistently.
## Supports seconds and minutes now (10s / 15 Minutes-style examples given);
## hours included for future-proofing since upgrades will likely take much
## longer eventually.
func _format_duration(seconds: float) -> String:
	var s: int = int(ceil(seconds))
	if s < 60:
		return "%d Second%s" % [s, "" if s == 1 else "s"]
	if s < 3600:
		var m: int = int(round(s / 60.0))
		return "%d Minute%s" % [m, "" if m == 1 else "s"]
	var h: int = int(round(s / 3600.0))
	return "%d Hour%s" % [h, "" if h == 1 else "s"]

## max_tier segments, evenly filling the tile's width with small gaps
## between them. max_tier == 1 is the special case per direction: ONE
## full-width segment/button, grey before completion, blue after — not a
## "bar with one slot," visually just a single toggle-colored strip.
func _build_tier_bar(max_tier: int, completed_tiers: int, tile_width: float) -> Control:
	const SEG_GAP: float = 4.0
	var seg_w: float = (tile_width - SEG_GAP * float(max_tier - 1)) / float(max_tier)
	var row: Control = Control.new()
	row.custom_minimum_size = Vector2(tile_width, 14.0)
	for i: int in max_tier:
		var seg: ColorRect = ColorRect.new()
		seg.position = Vector2(float(i) * (seg_w + SEG_GAP), 0.0)
		seg.size = Vector2(seg_w, 14.0)
		seg.color = COLOR_ACCENT if i < completed_tiers else Color(0.30, 0.31, 0.33, 1.0)
		row.add_child(seg)
	return row

## The single tiered upgrade node (top of the tree). Compact stacked order
## per the drawing: name -> materials (auto-expanding) -> time -> progress
## bar -> Research/Stop/Resume button -> tier-segment bar. Only this box is
## taller than NODE_H.
func _build_tiered_node(upgrade: UpgradeDef, station: ResearchStation) -> Control:
	var completed_tiers: int = station.tier_progress.get(upgrade.id, 0)
	var max_tier: int        = upgrade.get_max_tier()
	var is_maxed: bool       = completed_tiers >= max_tier
	## Per direction: no tier wording in the displayed title — the tier bar
	## (Part 3) and future visuals communicate tier status instead. Toast
	## notifications keep the tier number (unchanged, in
	## ResearchStation._complete_research()).
	var display_title: String = upgrade.display_name

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
	var is_paused: bool  = is_active and station.is_paused
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
	## This tile's overlay is the d-pad selection target; A activates its
	## Research button (recorded below).
	_top_tile_box = _enable_tile_selection(box)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 10.0
	v.offset_top    = 8.0
	v.offset_right  = -10.0
	v.offset_bottom = -4.0   ## was -8.0 — tighter fit now that the tier bar is the last element
	box.add_child(v)

	var name_lbl: Label = Label.new()
	name_lbl.text = display_title
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL   ## needed for centering to have room to work inside the VBox
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
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_active:
		var remaining: float = maxf(upgrade.duration_seconds - station._elapsed, 0.0)
		time_lbl.text = "Time left: %s" % _format_duration(remaining)
		time_lbl.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		time_lbl.text = _format_duration(upgrade.duration_seconds)
		time_lbl.add_theme_color_override("font_color", COLOR_DIM)

	## Clock icon sits to the left of time_lbl in both states (not-started
	## duration and active countdown) — there's only one text slot for this
	## value, so both read consistently rather than the icon appearing only
	## during the countdown.
	var time_row: HBoxContainer = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	var clock_icon: TextureRect = TextureRect.new()
	clock_icon.texture = CLOCK_ICON_TEXTURE
	clock_icon.custom_minimum_size = CLOCK_ICON_SIZE
	clock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	time_row.add_child(clock_icon)
	time_row.add_child(time_lbl)
	v.add_child(time_row)

	## Progress bar — the live-changing part the passive tick updates in
	## place (Part 2). Added back here per plan (the tiered redesign had
	## dropped it, but the tick + checklist #6 both need one).
	var progress_bar: ProgressBar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0.0, 10.0)
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	if is_active:
		progress_bar.value = clampf(station._elapsed / upgrade.duration_seconds, 0.0, 1.0) * 100.0
	v.add_child(progress_bar)

	## 3-state button: Resume (paused) / Stop Research (active) / Research
	## (idle) — Part 6 of the polish pass. Pause freezes progress with no
	## refund; the button text/style is what communicates the state.
	var btn: Button = UIKit.make_button("", Callable())
	if is_paused:
		btn.text = "Resume"
		## default/accent style — flagged for visual tuning if it should
		## look distinct from plain "Research"
	elif is_active:
		btn.text = "Stop Research"
		var ss_stop: StyleBoxFlat = StyleBoxFlat.new()
		ss_stop.bg_color     = Color(0.35, 0.08, 0.08, 1.0)   ## dark red
		ss_stop.border_color = Color(0.65, 0.20, 0.20, 1.0)   ## lighter red border
		ss_stop.set_border_width_all(1)
		ss_stop.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", ss_stop)
		btn.add_theme_stylebox_override("hover",  ss_stop)
	else:
		btn.text = "Research"
	btn.disabled = is_maxed or (not is_active and not can_afford)
	btn.pressed.connect(func() -> void:
		if is_paused:
			station.resume_research()
		elif is_active:
			station.pause_research()
		else:
			if is_maxed or not can_afford:
				return
			if not station.start_research(upgrade):
				NotificationManager.feedback(
					UIKit.Domain.NEUTRAL,
					NotificationManager.Severity.WARNING,
					"Already researching something else")
		_refresh_content()   ## structural change — full rebuild is correct here (Part 2 only removed the PASSIVE per-tick rebuild)
	)
	## Tile-selection model (Aug 2026): the d-pad selects the TILE, not this
	## button; A on the tile activates it. A's icon is shown in front of the
	## text in controller mode (see _refresh_controller_hints).
	btn.focus_mode = Control.FOCUS_NONE
	_research_btn = btn
	v.add_child(btn)

	## Tier-segment bar — max_tier segments filling the tile's full content
	## width edge-to-edge (Part 3), accent-filled for the completed tiers,
	## wrapped in a CenterContainer so it stays centered within the tile.
	var tier_bar_wrap: CenterContainer = CenterContainer.new()
	tier_bar_wrap.custom_minimum_size = Vector2(NODE_W - 20.0, 14.0)
	tier_bar_wrap.add_child(_build_tier_bar(max_tier, completed_tiers, NODE_W - 20.0))
	v.add_child(tier_bar_wrap)

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

	## Cache the live-changing refs for the passive tick (Part 2) — set to
	## null when this card isn't the active research so a later tick never
	## writes into a stale/foreign node.
	if is_active:
		_active_progress_bar = progress_bar
		_active_time_label   = time_lbl
	else:
		_active_progress_bar = null
		_active_time_label   = null

	return root

func _add_connection(a: Vector2, b: Vector2) -> void:
	_connections.append([a, b])

func _on_connector_draw() -> void:
	for conn: Array in _connections:
		var a: Vector2 = conn[0]
		var b: Vector2 = conn[1]
		_connector_canvas.draw_line(a, b, COLOR_CONNECTOR, 2.0, true)

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
	## Shifts the whole diagram right by exactly enough to fit the mirrored
	## left branch (NODE_W + COL_GAP left of the old grid_left) — folded
	## into grid_left so every downstream position shifts consistently.
	var grid_left: float = HEADER_MARGIN + NODE_W + COL_GAP
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

	## Vertical connectors: row 1 -> top node. The middle column runs
	## straight up into the top node's bottom edge; the two OUTER columns
	## run up to the top node's vertical center then jog horizontally into
	## its left/right edge (previously they stopped at row0_h with nothing
	## to meet, leaving dangling stubs). Row-to-row lines follow after.
	var top_node_left_x: float  = top_node.position.x
	var top_node_right_x: float = top_node.position.x + NODE_W
	var top_node_mid_y: float   = row0_h * 0.5
	for c: int in 3:
		var col_cx: float = grid_cols[c] + NODE_W * 0.5
		if c == 0:
			_add_connection(Vector2(col_cx, row1_y), Vector2(col_cx, top_node_mid_y))
			_add_connection(Vector2(col_cx, top_node_mid_y), Vector2(top_node_left_x, top_node_mid_y))
		elif c == 2:
			_add_connection(Vector2(col_cx, row1_y), Vector2(col_cx, top_node_mid_y))
			_add_connection(Vector2(col_cx, top_node_mid_y), Vector2(top_node_right_x, top_node_mid_y))
		else:
			_add_connection(Vector2(col_cx, row0_h), Vector2(col_cx, row1_y))
	for r: int in 3:
		for c: int in 3:
			var col_cx: float = grid_cols[c] + NODE_W * 0.5
			_add_connection(Vector2(col_cx, row_ys[r] + NODE_H), Vector2(col_cx, row_ys[r + 1]))

	## Right-side branch pair (2 blank boxes) beside rows 2-3: vertical line
	## between the pair, one diagonal from main-grid row 1 col 2 (7a: was
	## row 2's right edge).
	var rb1: Control = _build_blank_box()
	rb1.position = Vector2(branch_left, row2_y)
	_canvas.add_child(rb1)
	var rb2: Control = _build_blank_box()
	rb2.position = Vector2(branch_left, row3_y)
	_canvas.add_child(rb2)
	var rb_cx: float = branch_left + NODE_W * 0.5
	_add_connection(Vector2(rb_cx, row2_y + NODE_H), Vector2(rb_cx, row3_y))
	_add_connection(Vector2(grid_cols[2] + NODE_W, row1_y + NODE_H * 0.5), Vector2(rb_cx, row2_y))

	## Left-side branch pair — horizontal mirror of the corrected right
	## branch: same row2_y/row3_y rows, connected via a diagonal from the
	## LEFTMOST main column's row 1 (mirroring 7a's row-1 anchor).
	var left_branch_x: float = grid_left - COL_GAP - NODE_W
	var lb1: Control = _build_blank_box()
	lb1.position = Vector2(left_branch_x, row2_y)
	_canvas.add_child(lb1)
	var lb2: Control = _build_blank_box()
	lb2.position = Vector2(left_branch_x, row3_y)
	_canvas.add_child(lb2)
	var lb_cx: float = left_branch_x + NODE_W * 0.5
	_add_connection(Vector2(lb_cx, row2_y + NODE_H), Vector2(lb_cx, row3_y))
	_add_connection(Vector2(grid_cols[0], row1_y + NODE_H * 0.5), Vector2(lb_cx, row2_y))

	## Diagram is now NODE_W + COL_GAP wider overall — grow the canvas width
	## to match so the right branch stays fully on-canvas (horizontal scroll
	## is disabled, so PANEL_W had to grow too — see const).
	var canvas_h: float = row4_y + NODE_H + 8.0
	var canvas_w: float = PANEL_W - 32.0 + NODE_W + COL_GAP
	_canvas.custom_minimum_size = Vector2(canvas_w, canvas_h)
	_canvas.size = Vector2(canvas_w, canvas_h)
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

## Computed once: the widest of the 4 possible label strings, plus small
## fixed padding — applied uniformly to all four buttons regardless of
## their own individual text length.
func _compute_material_btn_size() -> Vector2:
	var max_w: float = 0.0
	for material: String in ResearchStation.MATERIAL_TYPES:
		var sample: String = "%s: %d/%d" % [material.capitalize(), ResearchStation.STORAGE_CAP, ResearchStation.STORAGE_CAP]
		var w: float = _font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		max_w = maxf(max_w, w)
	var text_h: float = _font.get_height(11)
	const PAD_X: float = 10.0
	const PAD_Y: float = 3.0   ## "nearly just the text height, tiny margin" per direction
	return Vector2(max_w + PAD_X * 2.0, text_h + PAD_Y * 2.0)

## Pinned 2x2 materials grid (Metal/Plastic left, Paper/Organic right),
## absolute within the fixed header area — does NOT scroll with the tree.
func _build_materials_grid() -> void:
	var btn_size: Vector2 = _compute_material_btn_size()
	var col1_x: float = HEADER_MARGIN
	var col2_x: float = col1_x + btn_size.x + MATERIAL_COL_GAP
	var row1_y: float = MATERIAL_TOP_Y
	var row2_y: float = row1_y + btn_size.y + MATERIAL_ROW_GAP
	var cells: Array = [
		["metal",   col1_x, row1_y],
		["plastic", col1_x, row2_y],
		["paper",   col2_x, row1_y],
		["organic", col2_x, row2_y],
	]
	for cell: Array in cells:
		var material: String = cell[0]
		var panel: Panel = Panel.new()   ## was PanelContainer — Panel doesn't auto-resize to content
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var ss: StyleBoxFlat = StyleBoxFlat.new()
		ss.bg_color = Color(0.10, 0.10, 0.12, 0.95)
		ss.border_color = COLOR_BORDER
		ss.set_border_width_all(1)
		ss.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", ss)
		panel.position = Vector2(float(cell[1]), float(cell[2]))
		panel.custom_minimum_size = btn_size
		panel.size = btn_size
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.texture = MATERIAL_ICONS[material]
		## expand_mode/stretch_mode MUST be set before .size below — Control's
		## size setter clamps to the current minimum size at call time, and a
		## TextureRect's minimum size is its texture's native dimensions until
		## expand_mode is changed off the EXPAND_KEEP_SIZE default. Setting
		## .size first silently clamps it back up to the full 100x100 source
		## texture regardless of MATERIAL_ICON_SIZE's value — this was the
		## actual bug behind icons rendering full-sized.
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = MATERIAL_ICON_SIZE
		icon_rect.size = MATERIAL_ICON_SIZE
		icon_rect.position = Vector2(MATERIAL_ICON_BUFFER, (btn_size.y - MATERIAL_ICON_SIZE.y) * 0.5)
		panel.add_child(icon_rect)

		## Count-only label now, right-aligned — the icon above replaces the
		## material name text. _material_labels keeps its existing name/type
		## so _refresh_materials_header() needs only a format-string change.
		var lbl: Label = Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.offset_right = -MATERIAL_COUNT_BUFFER   ## small right inset, not flush against the border
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COLOR_TEXT)
		lbl.text = "%d/%d" % [0, ResearchStation.STORAGE_CAP]
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
	## Controller (Aug 2026): RB/LB cycle tabs; A activates the focused
	## tile's Research button. (D-pad/tile navigation and B-close are the
	## nav's job in _input; B is consumed there before this runs.)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_tree(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_tree(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			var focused: Control = get_viewport().gui_get_focus_owner()
			if focused != null and _top_tile_box != null and focused == _top_tile_box \
					and _research_btn != null and is_instance_valid(_research_btn) \
					and not _research_btn.disabled:
				_research_btn.emit_signal("pressed")
			get_viewport().set_input_as_handled()
