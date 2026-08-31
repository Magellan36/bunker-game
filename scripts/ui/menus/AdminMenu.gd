extends CanvasLayer
## AdminMenu.gd
## F7 general-purpose admin controls panel — direct system cheats/
## debug toggles that don't correspond to a placeable object.
## Injected refs set by MainWorld._toggle_admin_cheat_menu().
##
## Structure (Jul 2026 "collapse + scroll" rewrite): this panel had grown to
## 24 rows across 7 sections (the NPC section alone is 12 rows — folded in
## from the deleted F10 Admin Spawn Menu) and was rendering as a ~1,250px-
## tall wall of buttons. Fixed by:
##   1. The panel is back to a FIXED height (PANEL_H) — no longer computed
##      from row count, so it won't balloon again as rows get added.
##   2. Every section is a collapsible header (▶ collapsed / ▼ expanded,
##      click to toggle) — all sections start collapsed on open. Multiple
##      sections can be open at once (not an exclusive accordion).
##   3. The row area is a real ScrollContainer — mouse wheel scroll and an
##      auto right-side scrollbar are both native Godot behavior, no custom
##      code needed. Same pattern GraphicsSettingsPanel.gd already uses.
##   4. Rounded corners (UIKit.draw_rounded_rect) + the project's +6px
##      top-padding convention, both added in the last UI pass, applied
##      here too since the file was already being rewritten.
## The row DATA (`_sections`) and every `_on_*_pressed()` callback below the
## "Button callbacks" divider are unchanged by this pass — only how they're
## laid out and shown/hidden changed.

signal closed

# ─── Palette (neutral admin/military — distinct from water's blue, power's
# green) ───────────────────────────────────────────────────────────────────
## Sourced from BunkerTheme's AdminUI section in _load_theme(); these
## defaults are the fallbacks if the theme resource is missing.
var BG_COLOR:     Color = Color(0.08, 0.08, 0.10, 0.97)
## Shared backdrop dim — read from UI/backdrop_alpha_permille (Aug 2026).
var _backdrop_alpha: float = 0.60
var BORDER_COLOR: Color = Color(0.55, 0.58, 0.42, 0.85)   ## dull olive/brass accent
var HEADER_COLOR: Color = Color(0.80, 0.82, 0.62, 1.00)
var TEXT_COLOR:   Color = Color(0.85, 0.87, 0.80, 0.95)
var DIM_COLOR:    Color = Color(0.55, 0.58, 0.52, 0.80)
var CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)

## Section header / row button backgrounds (sourced from BunkerTheme in
## _load_theme — same values as the old literals, look unchanged).
var SECTION_BG:       Color = Color(0.16, 0.17, 0.13, 0.55)
var SECTION_BG_HOVER: Color = Color(0.22, 0.23, 0.18, 0.75)
var ROW_BG:           Color = Color(0.14, 0.15, 0.13, 0.90)
var ROW_BG_HOVER:     Color = Color(0.22, 0.23, 0.18, 0.95)

# ─── Layout ───────────────────────────────────────────────────────────────────
var PANEL_W: float = 320.0
var PANEL_H: float = 480.0   ## Jul 2026 — fixed again (was computed from
                             ## row count, which is what let it grow to
                             ## ~1250px). Overflow content scrolls instead.
var ROW_H:   float = 34.0
var ROW_GAP: float = 6.0
var SECTION_GAP: float = 10.0   ## vertical gap between one section and the next

const ADMIN_POWER_STEP_WATTS: float = 1000.0
const QUALITY_SCALE_DOWN: float = 0.5    ## "-50%" halves current quality
const QUALITY_SCALE_UP:   float = 1.5    ## "+50%" raises current quality by half

const TEST_EFFECT_DURATION: float = 10.0
var TEST_EFFECT_COLOR: Color = Color(0.86, 0.57, 0.19, 1.0)   ## matches StatusEffectIcon's own default (Jul 2026 — darkened 5%)

const ADMIN_CASH_STEP: int = 100000          ## "+$100,000" economy cheat row

## Farming produce spawn — matches FarmingShopHelper.SPAWN_HEIGHT_ABOVE_PLAYER
## (1.8) so admin-spawned produce drops exactly like a shop purchase does.
const PRODUCE_SPAWN_HEIGHT: float = 1.8

## One entry per collapsible section: { "name": String, "rows": Array }
## where each row is [label: String, callback: Callable]. Jul 2026 — replaced
## the old flat array-with-repeated-"" -for-continuation format; grouping is
## now explicit instead of inferred, since sections need real boundaries to
## collapse/expand independently.
var _sections: Array[Dictionary] = []

# ─── State ────────────────────────────────────────────────────────────────────
var _canvas:  Control = null
var _font:    Font    = null
var _close_btn: Button = null
var _is_open: bool = false
var _test_effect_count: int = 0

## Scroll/section Control refs (Jul 2026 collapse+scroll pass)
var _scroll: ScrollContainer = null
var _scroll_vbox: VBoxContainer = null
var _section_headers:  Array[Button] = []
var _section_bodies:   Array[VBoxContainer] = []
var _section_expanded: Array[bool] = []

# ─── Injected by MainWorld._toggle_admin_cheat_menu() ─────────────────────────
## MainWorld — used by the ECONOMY row (add_cash()). Injected via set() at
## menu-creation time; the injection call already exists in MainWorld.gd, this
## var declaration is what makes it actually land (Object.set() on an
## undeclared property is a silent no-op).
var world_node: MainWorld = null

## Pulls every palette + component value from BunkerTheme's AdminUI section
## so the theme is the single source of truth (this panel keeps its own
## olive/brass palette — distinct from the shared UI palette).
func _load_theme() -> void:
	BG_COLOR = UIKit.theme_color("AdminUI", "bg", Color(0.08, 0.08, 0.10, 0.97))
	BORDER_COLOR = UIKit.theme_color("AdminUI", "border", Color(0.55, 0.58, 0.42, 0.85))
	HEADER_COLOR = UIKit.theme_color("AdminUI", "header", Color(0.80, 0.82, 0.62, 1.00))
	TEXT_COLOR = UIKit.theme_color("AdminUI", "text", Color(0.85, 0.87, 0.80, 0.95))
	DIM_COLOR = UIKit.theme_color("AdminUI", "dim", Color(0.55, 0.58, 0.52, 0.80))
	CRIT_COLOR = UIKit.theme_color("AdminUI", "crit", Color(1.00, 0.35, 0.30, 1.00))
	TEST_EFFECT_COLOR = UIKit.theme_color("AdminUI", "test_effect", Color(0.86, 0.57, 0.19, 1.0))
	SECTION_BG = UIKit.theme_color("AdminUI", "section_bg", Color(0.16, 0.17, 0.13, 0.55))
	SECTION_BG_HOVER = UIKit.theme_color("AdminUI", "section_bg_hover", Color(0.22, 0.23, 0.18, 0.75))
	ROW_BG = UIKit.theme_color("AdminUI", "row_bg", Color(0.14, 0.15, 0.13, 0.90))
	ROW_BG_HOVER = UIKit.theme_color("AdminUI", "row_bg_hover", Color(0.22, 0.23, 0.18, 0.95))
	PANEL_W = float(UIKit.theme_constant("AdminUI", "panel_w", 320))
	PANEL_H = float(UIKit.theme_constant("AdminUI", "panel_h", 480))
	ROW_H = float(UIKit.theme_constant("AdminUI", "row_h", 34))
	ROW_GAP = float(UIKit.theme_constant("AdminUI", "row_gap", 6))
	SECTION_GAP = float(UIKit.theme_constant("AdminUI", "section_gap", 10))
	_backdrop_alpha = float(UIKit.theme_constant("UI", "backdrop_alpha_permille", 600)) / 1000.0

func _ready() -> void:
	_load_theme()
	layer   = 128   ## On top of everything (PauseMenuUI sits above at 200)
	visible = false
	set_process(false)
	## Controller navigation (Aug 2026) — d-pad + left stick drive focus
	## (movement is locked while this is open), B closes this UI. See
	## scripts/ui/common/ControllerUINavigation.gd.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = true
	add_child(controller_nav)

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_sections = [
		{ "name": "POWER", "rows": [
			["+ %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_add_power_pressed],
			["- %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_remove_power_pressed],
		]},
		{ "name": "TIME", "rows": [
			["Fast-Forward 1 Day", _on_fast_forward_pressed],
		]},
		{ "name": "WATER", "rows": [
			["Hookup Quality -50%", _on_quality_down_pressed],
			["Hookup Quality +50%", _on_quality_up_pressed],
			["Hookup Output x2 (Tier +1)", _on_hookup_output_double_pressed],
		]},
		{ "name": "ECONOMY", "rows": [
			["+ $%s Cash" % _format_thousands(ADMIN_CASH_STEP), _on_add_cash_pressed],
		]},
		{ "name": "RESEARCH", "rows": [
			["+10 Each Material Type", _on_add_research_materials_pressed],
		]},
	{ "name": "FARMING", "rows": [
		["Spawn Potato", _on_spawn_potato_pressed],
		["Spawn Blueberry", _on_spawn_blueberry_pressed],
		["Spawn Tomato", _on_spawn_tomato_pressed],
		["Spawn Onion", _on_spawn_onion_pressed],
		["Spawn Basil", _on_spawn_basil_pressed],
		["Spawn Strawberry", _on_spawn_strawberry_pressed],
		["Spawn Carrot", _on_spawn_carrot_pressed],
		["Spawn Chili Pepper", _on_spawn_chili_pepper_pressed],
		["Spawn Bell Pepper", _on_spawn_bell_pepper_pressed],
		["Spawn Garlic", _on_spawn_garlic_pressed],
		["Spawn Corn", _on_spawn_corn_pressed],
		["Spawn Pumpkin", _on_spawn_pumpkin_pressed],
	]},
		{ "name": "MEDICAL", "rows": [
			["Spawn Open Wound (Left Arm)",  _on_spawn_wound_left_arm_pressed],
			["Spawn Open Wound (Right Arm)", _on_spawn_wound_right_arm_pressed],
			["Spawn Open Wound (Left Leg)",  _on_spawn_wound_left_leg_pressed],
			["Spawn Open Wound (Right Leg)", _on_spawn_wound_right_leg_pressed],
			["Spawn Open Wound (Torso)",     _on_spawn_wound_torso_pressed],
			["Spawn Open Wound (Head)",      _on_spawn_wound_head_pressed],
			["Spawn Open Wound + Bleeding (Guaranteed, Left Arm)", _on_spawn_wound_bleeding_guaranteed_pressed],
			["Force-Bandage All Bleeding",   _on_force_bandage_all_pressed],
			["Force-Infect Nearest Open Wound", _on_force_infect_pressed],
			["Apply Antibiotics (Left Arm)", _on_apply_antibiotics_left_arm_pressed],
			["Infection Severity +20 (all)", _on_infection_sev_up_pressed],
			["Infection Severity -20 (all)", _on_infection_sev_down_pressed],
			["Spawn Fractured (Left Leg)",   _on_spawn_fracture_left_leg_pressed],
			["Spawn Fractured (Right Leg)",  _on_spawn_fracture_right_leg_pressed],
			["Apply Splint (Left Leg)",      _on_apply_splint_left_leg_pressed],
			["Apply Splint (Right Leg)",     _on_apply_splint_right_leg_pressed],
			["Force Escalate All Fractures", _on_force_escalate_fracture_pressed],
			["Force-Convert Fractures to Broken", _on_force_break_pressed],
			["Spawn Electrical Burn (Left Arm)", _on_spawn_electrical_burn_pressed],
			["Spawn Cooking Burn (Right Arm)", _on_spawn_cooking_burn_pressed],
			["Simulate 8h Sleep (real sleep path)", _on_simulate_sleep_pressed],
			["Spawn Bandage (drop in front of player)", _on_spawn_bandage_pressed],
			["Spawn Antibiotics (drop in front of player)", _on_spawn_antibiotics_pressed],
			["Spawn Splint Kit (drop in front of player)", _on_spawn_splint_pressed],
			["Spawn Trauma Kit (drop in front of player)", _on_spawn_trauma_kit_pressed],
			["Clear All Medical Conditions", _on_clear_all_medical_pressed],
			["Print Medical Debug State",    _on_print_medical_debug_pressed],
		]},
		{ "name": "STATUS", "rows": [
			["Add Test Status Effect (10s)", _on_add_status_effect_pressed],
		]},
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
			["Spawn Neutral NPC (Testing)", _on_spawn_neutral_npc_pressed],
			["Make All NPCs Clean", _on_make_all_npcs_clean_pressed],
			["Drain NPC Needs -40", _on_drain_npc_needs_pressed],
			["Drain NPC Mood -40", _on_drain_npc_mood_pressed],
			["Health +20", _on_npc_health_up_pressed],
			["Health -20", _on_npc_health_down_pressed],
			["Energy +20", _on_npc_energy_up_pressed],
			["Energy -20", _on_npc_energy_down_pressed],
			["Hunger +20", _on_npc_hunger_up_pressed],
			["Hunger -20", _on_npc_hunger_down_pressed],
			["Thirst +20", _on_npc_thirst_up_pressed],
			["Thirst -20", _on_npc_thirst_down_pressed],
			["Randomize NPC Skills", _on_npc_randomize_skills_pressed],
			["Despawn All NPCs", _on_npc_despawn_all_pressed],
			["Force Rebake Navmesh", _on_npc_force_rebake_pressed],
			["Toggle NPC Debug Logging", _on_npc_toggle_debug_pressed],
			["Print NPC Debug State", _on_npc_print_debug_pressed],
			["Print NPC Cleaning Debug State", _on_npc_print_cleaning_debug_pressed],
			["Print NPC Job Debug State", _on_npc_print_job_debug_pressed],
			["Force Nearest NPC to Snatch Player Item", _on_npc_force_snatch_pressed],
			["Force Nearest NPC to Talk to NPC", _on_npc_force_talk_pressed],
			["Force Nearest NPC to Give to Friend", _on_npc_force_give_friend_pressed],
			["Force Nearest NPC to Snatch NPC Item", _on_npc_force_npc_snatch_pressed],
			["Relationship -25 (All NPCs ↔ Player)", _on_npc_relationship_down_pressed],
			["Relationship +25 (All NPCs ↔ Player)", _on_npc_relationship_up_pressed],
			["NPC↔NPC Relationship -25 (All Pairs)", _on_npc_npc_relationship_down_pressed],
			["NPC↔NPC Relationship +25 (All Pairs)", _on_npc_npc_relationship_up_pressed],
		]},
	]

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "AdminMenuCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	_build_scroll_area()

## Builds the ScrollContainer + its VBoxContainer of section header/body
## pairs. Runs once in _ready(); sections/rows never change after this.
func _build_scroll_area() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scroll)

	## Themed scrollbar so the auto-generated right-side scrollbar matches
	## this panel's olive palette instead of Godot's default blue engine
	## theme.
	var scroll_theme: Theme = Theme.new()
	var grabber: StyleBoxFlat = StyleBoxFlat.new()
	grabber.bg_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.65)
	grabber.set_corner_radius_all(4)
	var grabber_hi: StyleBoxFlat = grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.85)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	track.set_corner_radius_all(4)
	scroll_theme.set_stylebox("grabber", "VScrollBar", grabber)
	scroll_theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	scroll_theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hi)
	scroll_theme.set_stylebox("scroll", "VScrollBar", track)
	scroll_theme.set_stylebox("scroll_focus", "VScrollBar", track)
	_scroll.theme = scroll_theme

	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.add_theme_constant_override("separation", SECTION_GAP)
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_scroll_vbox)

	for i: int in range(_sections.size()):
		var section: Dictionary = _sections[i]

		var header: Button = Button.new()
		header.flat       = true
		header.focus_mode = Control.FOCUS_NONE
		header.alignment  = HORIZONTAL_ALIGNMENT_LEFT
		header.text       = "▶  %s" % String(section["name"])
		_style_section_header(header)
		header.pressed.connect(_on_section_header_pressed.bind(i))
		_scroll_vbox.add_child(header)
		_section_headers.append(header)
		_section_expanded.append(false)   ## every section starts collapsed

		var body: VBoxContainer = VBoxContainer.new()
		body.add_theme_constant_override("separation", ROW_GAP)
		body.visible = false
		_scroll_vbox.add_child(body)
		_section_bodies.append(body)

		var rows: Array = section["rows"]
		for row: Array in rows:
			var btn: Button = Button.new()
			btn.text                = String(row[0])
			btn.focus_mode          = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(0.0, ROW_H)
			btn.pressed.connect(row[1])
			_style_row_btn(btn)
			body.add_child(btn)

## Toggles one section's expanded/collapsed state and swaps its arrow.
func _on_section_header_pressed(index: int) -> void:
	_section_expanded[index] = not _section_expanded[index]
	_section_bodies[index].visible = _section_expanded[index]
	var arrow: String = "▼" if _section_expanded[index] else "▶"
	_section_headers[index].text = "%s  %s" % [arrow, String(_sections[index]["name"])]

func _style_section_header(btn: Button) -> void:
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", HEADER_COLOR)
	btn.add_theme_color_override("font_hover_color", HEADER_COLOR)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = SECTION_BG
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 8.0
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = SECTION_BG_HOVER
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

func _style_row_btn(btn: Button) -> void:
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color     = ROW_BG
	normal.border_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color     = ROW_BG_HOVER
	hover.border_color = Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.85)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover",  hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", HEADER_COLOR)

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 16.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	## Scroll area sits between the header chrome (title+separator, ends
	## ~py+72) and the footer hint line (~py+PANEL_H-30) — see _on_draw().
	var scroll_top: float    = py + 72.0
	var scroll_bottom: float = py + PANEL_H - 34.0
	_scroll.position = Vector2(px + 16.0, scroll_top)
	_scroll.size     = Vector2(PANEL_W - 32.0, scroll_bottom - scroll_top)

# ─── Open / Close ─────────────────────────────────────────────────────────────
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	_is_open = true
	visible  = true
	set_process(true)
	_reposition_controls()
	_close_btn.visible = true
	_scroll.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	_scroll.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	closed.emit()

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - PANEL_H) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
		if panel.has_point(event.position):
			get_viewport().set_input_as_handled()

## Redraw throttle (Aug 2026 optimization) — the static list doesn't need 60Hz.
const REDRAW_INTERVAL: float = 0.1
var _redraw_accum: float = 0.0

func _process(_delta: float) -> void:
	if not _is_open:
		return
	_redraw_accum += _delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _is_open:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, _backdrop_alpha), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	UIKit.draw_rounded_rect(_canvas, panel, BG_COLOR, BORDER_COLOR, 2.0)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 16.0, 30.0, 30.0)
	UIKit.draw_rounded_rect(_canvas, close_rect, Color(0.10, 0.06, 0.06, 0.90), CRIT_COLOR, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0, true)
	_canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), Color(1.0, 0.7, 0.7, 1.0), 2.0, true)

	var cx: float = px + 20.0
	var cy: float = py + 26.0

	_draw_str("[F7]  ADMIN CONTROLS", Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0, true)

	_draw_str("[ESC / E]  Close", Vector2(cx, py + PANEL_H - 18.0), DIM_COLOR, 9)

	_reposition_controls()

func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	_canvas.draw_string(_font, pos + Vector2(0, size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## 100000 → "100,000". Local to this menu — no shared number-format helper
## exists in the project yet, and this is the only caller.
func _format_thousands(value: int) -> String:
	var s: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out

# ─── Button callbacks ──────────────────────────────────────────────────────────
func _get_power_manager() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager

func _get_player_stats() -> PlayerStats:
	return get_tree().get_first_node_in_group("player_stats") as PlayerStats

func _get_water_manager() -> WaterManager:
	return get_tree().get_first_node_in_group("water_manager") as WaterManager

func _get_research_station() -> ResearchStation:
	return get_tree().get_first_node_in_group("research_station") as ResearchStation

func _get_status_effects() -> StatusEffectsContainer:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not ("status_effects" in hud):
		return null
	return hud.get("status_effects") as StatusEffectsContainer

func _get_player_medical() -> PlayerMedical:
	return get_tree().get_first_node_in_group("player_medical") as PlayerMedical

## MEDICAL section callbacks (Aug 2026, Pass 1) — each of these calls the
## exact same PlayerMedical functions the eventual real items/triggers will
## use; never a separate debug-only code path. See
## docs/systems/medical/README.md and
## plans/medical-system-implementation-plan.md.
func _on_spawn_wound_left_arm_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.LEFT_ARM)

func _on_spawn_wound_right_arm_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.RIGHT_ARM)

func _on_spawn_wound_left_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.LEFT_LEG)

func _on_spawn_wound_right_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.RIGHT_LEG)

func _on_spawn_wound_torso_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.TORSO)

func _on_spawn_wound_head_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_open_wound(MedicalCondition.BodyPart.HEAD)

## Guarantees a bleeding wound for testing WITHOUT changing the real 66%
## odds on spawn_open_wound() itself — spawns the wound, then explicitly
## adds Bleeding if the roll didn't happen to produce one.
func _on_spawn_wound_bleeding_guaranteed_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm == null:
		return
	var part: int = MedicalCondition.BodyPart.LEFT_ARM
	pm.spawn_open_wound(part)
	if pm.get_condition_by_id_and_part("bleeding", part) == null:
		pm.spawn_bleeding(part)

func _on_force_bandage_all_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm == null:
		return
	for part in [
		MedicalCondition.BodyPart.HEAD, MedicalCondition.BodyPart.TORSO,
		MedicalCondition.BodyPart.LEFT_ARM, MedicalCondition.BodyPart.RIGHT_ARM,
		MedicalCondition.BodyPart.LEFT_LEG, MedicalCondition.BodyPart.RIGHT_LEG,
	]:
		pm.treat_bleeding(part)

## Infection (Pass 2) callbacks.
func _on_force_infect_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_force_infect_nearest_wound()

## Applies antibiotics to whatever's on the Left Arm — works whether that's
## a plain Open Wound (preventative) or an already-infected one (curative);
## treat_open_wound_antibiotics() itself decides which per the item's real
## dual role. Left Arm chosen as the one predictable test target since the
## other MEDICAL rows don't let you pick an arbitrary body part per-press.
func _on_apply_antibiotics_left_arm_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.treat_open_wound_antibiotics(MedicalCondition.BodyPart.LEFT_ARM)

func _on_infection_sev_up_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_adjust_infection_severity(20.0)

func _on_infection_sev_down_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_adjust_infection_severity(-20.0)

## Fracture / Broken (Pass 2) callbacks.
func _on_spawn_fracture_left_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_fractured(MedicalCondition.BodyPart.LEFT_LEG)

func _on_spawn_fracture_right_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_fractured(MedicalCondition.BodyPart.RIGHT_LEG)

func _on_apply_splint_left_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.apply_splint(MedicalCondition.BodyPart.LEFT_LEG)

func _on_apply_splint_right_leg_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.apply_splint(MedicalCondition.BodyPart.RIGHT_LEG)

func _on_force_escalate_fracture_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_force_escalate_all_fractures()

func _on_force_break_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_force_break_all_fractures()

## Burns (Pass 2.5) callbacks. Left/Right arm are fixed test targets, same
## pattern as the antibiotics row — the underlying mechanics are identical
## for both flavors, only the `cause` label (shown in the tooltip) differs.
func _on_spawn_electrical_burn_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_burn(MedicalCondition.BodyPart.LEFT_ARM, "electrical")

func _on_spawn_cooking_burn_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.spawn_burn(MedicalCondition.BodyPart.RIGHT_ARM, "cooking")

## Calls the exact same sequence SleepOverlay._do_time_skip() uses for a
## real sleep cycle — skip_time_with_drain() (real sleep drains sleep too,
## it doesn't refill it — skip_time() with its full-refill behavior isn't
## actually what real sleep calls), PlayerMedical.catch_up() for the base
## condition progression, and apply_rest_bonus() for the extra Broken/
## Burns speedup genuine rest gets. This is a faithful test of the real
## path, not a separate shortcut.
func _on_simulate_sleep_pressed() -> void:
	var stats: PlayerStats = _get_player_stats()
	if stats == null:
		return
	stats.skip_time_with_drain(8.0)
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.catch_up(8.0)
		pm.apply_rest_bonus(8.0)

func _on_clear_all_medical_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_clear_all()

func _on_print_medical_debug_pressed() -> void:
	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.debug_print_state()
	else:
		print("[AdminMenu] PlayerMedical not found (not in 'player_medical' group?).")

## Items (Aug 2026) — spawns a real Bandage.tscn 2m in front of the player,
## same drop-offset pattern _on_spawn_npc_pressed() uses (just at ground
## height instead of npc-eye height, since this is a small loose item, not
## a character). See docs/systems/medical/README.md's "Item roles and
## mechanics" — this is the actual pickupable item, not a condition stub;
## use F to pick it up, E to open the injury-selection submenu.
func _on_spawn_bandage_pressed() -> void:
	_spawn_medical_item("res://scenes/world/Bandage.tscn", "Bandage")

func _on_spawn_antibiotics_pressed() -> void:
	_spawn_medical_item("res://scenes/world/Antibiotics.tscn", "Antibiotics")

func _on_spawn_splint_pressed() -> void:
	_spawn_medical_item("res://scenes/world/Splint.tscn", "Splint")

func _on_spawn_trauma_kit_pressed() -> void:
	_spawn_medical_item("res://scenes/world/TraumaKit.tscn", "Trauma Kit")

## Shared spawner for all four MEDICAL item rows above — identical drop-
## offset pattern to _on_spawn_npc_pressed(), factored out once there were
## four near-identical copies instead of duplicating it a fourth time.
func _spawn_medical_item(scene_path: String, display_name: String) -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cannot spawn %s" % display_name)
		return
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_warning("[AdminMenu] No player found in scene — cannot spawn %s" % display_name)
		return
	var item_scene: PackedScene = load(scene_path)
	if item_scene == null:
		push_warning("[AdminMenu] %s not found — check path" % scene_path)
		return
	var item: Node3D = item_scene.instantiate()
	world_node.add_child(item)
	item.global_position = player_node.global_position \
		+ (-player_node.global_transform.basis.z * 1.5) \
		+ Vector3(0.0, 0.5, 0.0)

## Adds one test status effect badge with no real icon (grey placeholder,
## see StatusEffectIcon.gd), a 10-second timer, and the default orange ring
## color. Each press gets a unique id so presses stack into separate
## badges instead of restarting the same one.
func _on_add_status_effect_pressed() -> void:
	var se: StatusEffectsContainer = _get_status_effects()
	if se == null:
		return
	_test_effect_count += 1
	var id: String = "test_effect_%d" % _test_effect_count
	se.add_effect(id, null, TEST_EFFECT_DURATION, TEST_EFFECT_COLOR)

func _on_add_power_pressed() -> void:
	var pm: PowerManager = _get_power_manager()
	if pm != null:
		pm.admin_add_power(ADMIN_POWER_STEP_WATTS)

func _on_remove_power_pressed() -> void:
	var pm: PowerManager = _get_power_manager()
	if pm != null:
		pm.admin_add_power(-ADMIN_POWER_STEP_WATTS)

## Jumps the game clock forward exactly one full day AND actually simulates
## that day passing (Jul 2026 fix). Each affected system's own real update
## function is called directly with one lumped 24-game-hour delta — food/
## water/sleep/health drain (PlayerStats), water quality decay
## (WaterHookup), plant growth (every FarmPlant), and Medical condition
## progression (PlayerMedical.catch_up() — Aug 2026 fix; without this,
## infection severity/bleeding rate/healing time silently didn't advance
## during a skip, since PlayerMedical only reacted to real per-frame delta
## on its own) — instead of reimplementing any of that math here, so this
## can't drift out of sync with what 24 hours of normal play would
## actually do.
func _on_fast_forward_pressed() -> void:
	var stats: PlayerStats = _get_player_stats()
	if stats == null:
		return
	var scaled: float = 24.0 * stats._seconds_per_game_hour

	stats.skip_time_with_drain(24.0)
	NPC.catch_up_all(24.0)

	var pm: PlayerMedical = _get_player_medical()
	if pm != null:
		pm.catch_up(24.0)

	var wm: WaterManager = _get_water_manager()
	if wm != null:
		var hookup: WaterHookup = wm.get_the_hookup()
		if hookup != null:
			hookup._process(scaled)

	for tray: FarmingTray in get_tree().get_nodes_in_group("farming_tray"):
		for plant: FarmPlant in tray.plant_refs:
			if plant != null and is_instance_valid(plant):
				plant._process(scaled)

## "By 50%" read as relative to the hookup's CURRENT quality value (halves /
## raises-by-half from wherever it currently sits), not a flat ±50 points —
## lets you test decay/purifier behavior starting from any current quality.
func _on_quality_down_pressed() -> void:
	var wm: WaterManager = _get_water_manager()
	if wm == null:
		return
	var hookup: WaterHookup = wm.get_the_hookup()
	if hookup != null:
		hookup.water_quality = clampf(hookup.water_quality * QUALITY_SCALE_DOWN, 0.0, 100.0)

func _on_quality_up_pressed() -> void:
	var wm: WaterManager = _get_water_manager()
	if wm == null:
		return
	var hookup: WaterHookup = wm.get_the_hookup()
	if hookup != null:
		hookup.water_quality = clampf(hookup.water_quality * QUALITY_SCALE_UP, 0.0, 100.0)

## Spawns one NPC.tscn instance 2m in front of the player, facing them —
## same spawn-offset pattern MainWorld._dev_spawn_crate() uses for TestCrate.
func _on_spawn_npc_pressed() -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cannot spawn NPC")
		return
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_warning("[AdminMenu] No player found in scene — cannot spawn NPC")
		return

	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if npc_scene == null:
		push_warning("[AdminMenu] NPC.tscn not found — check path")
		return

	var npc: Node3D = npc_scene.instantiate()
	world_node.add_child(npc)
	npc.global_position = player_node.global_position \
		+ (-player_node.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)

## Aug 2026 — identical spawn to _on_spawn_npc_pressed() above, but then
## overrides _ready()'s random personality/skill roll with a fully
## neutral baseline: for reproducible bug-hunting where trait-driven
## behavior variance (irritability, work ethic, forgetfulness, job
## priority weighting) would otherwise be one more variable to account
## for. personality = {} already means "every trait absent/baseline" per
## randomize_personality()'s own convention (a PRESENT trait is never
## neutral by design — see that function's comment) — this just makes it
## deterministic instead of leaving it to chance which traits happened
## not to roll present. Skills forced to 1.0 (dead center of
## randomize_skills()'s normal 0.6-1.4 range) for the same reason. Name
## stays on the normal random pool — only traits/skills are neutralized.
func _on_spawn_neutral_npc_pressed() -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cannot spawn NPC")
		return
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_warning("[AdminMenu] No player found in scene — cannot spawn NPC")
		return

	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if npc_scene == null:
		push_warning("[AdminMenu] NPC.tscn not found — check path")
		return

	var npc: Node3D = npc_scene.instantiate()
	world_node.add_child(npc)
	npc.global_position = player_node.global_position \
		+ (-player_node.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)

	if "personality" in npc:
		npc.personality = {}
	if "skills" in npc:
		for key: String in npc.skills.keys():
			npc.skills[key] = 1.0

## Aug 2026 — force-starts every NPC in the level straight into Cleaning,
## bypassing normal scoring entirely (same force_command() path the
## player-issued Talk-menu "Clean the bunker" request uses via
## CommandCleaningActivity, just applied to every NPC at once instead of
## one at a time). Useful for clearing test clutter fast, and for
## isolating whether a reported cleaning issue is about the JOB-PICKING
## logic (never gets chosen) versus the cleaning behavior itself (chosen,
## but doesn't work right) — this button skips past the former entirely.
func _on_make_all_npcs_clean_pressed() -> void:
	var count: int = 0
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not ("brain" in npc) or npc.brain == null:
			continue
		npc.brain.force_command(CommandCleaningActivity.new())
		count += 1
	print("[AdminMenu] Forced %d NPC(s) into Cleaning" % count)

## Knocks 40 points off every spawned NPC's three needs — instant way to
## trigger drink/eat/sit behavior without waiting on the game clock.
func _on_drain_npc_needs_pressed() -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if "energy" in npc:
			npc.energy = maxf(0.0, npc.energy - 40.0)
			npc.hunger = maxf(0.0, npc.hunger - 40.0)
			npc.thirst = maxf(0.0, npc.thirst - 40.0)

## Shared helper — clamp-adjusts one need on every spawned NPC by `delta`.
func _on_drain_npc_mood_pressed() -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if "mood" in npc:
			npc.mood = clampf(float(npc.mood) - 40.0, 0.0, 100.0)

func _adjust_all_npc_need(need_name: String, delta: float) -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if need_name in npc:
			npc.set(need_name, clampf(float(npc.get(need_name)) + delta, 0.0, 100.0))

func _on_npc_health_up_pressed() -> void:   _adjust_all_npc_need("health", 20.0)
func _on_npc_health_down_pressed() -> void: _adjust_all_npc_need("health", -20.0)
func _on_npc_energy_up_pressed() -> void:   _adjust_all_npc_need("energy", 20.0)
func _on_npc_energy_down_pressed() -> void: _adjust_all_npc_need("energy", -20.0)
func _on_npc_hunger_up_pressed() -> void:   _adjust_all_npc_need("hunger", 20.0)
func _on_npc_hunger_down_pressed() -> void: _adjust_all_npc_need("hunger", -20.0)
func _on_npc_thirst_up_pressed() -> void:   _adjust_all_npc_need("thirst", 20.0)
func _on_npc_thirst_down_pressed() -> void: _adjust_all_npc_need("thirst", -20.0)

## Re-rolls every spawned NPC's skill set (0.6–1.4 uniform, same as spawn-
## time randomization) — handy for re-testing skill-weighted job claiming
## without respawning.
func _on_npc_randomize_skills_pressed() -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("randomize_skills"):
			npc.randomize_skills()

## Frees every spawned NPC cleanly (stops brain activity first so any held
## item/claimed job/chair is released, same teardown SaveManager's load
## path uses) — faster than reloading a save to get back to zero NPCs.
func _on_npc_despawn_all_pressed() -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		if "brain" in npc and npc.brain != null:
			npc.brain.stop_current()
		if "held_item" in npc and npc.held_item != null:
			NPCItemUser.drop_held(npc)
		npc.queue_free()

## Bypasses BunkerNavMesh's debounce/poll cycle for an instant rebake —
## useful right after manually editing the world in ways the automatic
## dig/place-fingerprint triggers wouldn't catch.
func _on_npc_force_rebake_pressed() -> void:
	var nav: Node = get_tree().get_first_node_in_group("bunker_navmesh")
	if nav != null and nav.has_method("mark_dirty"):
		nav.mark_dirty()

func _on_npc_toggle_debug_pressed() -> void:
	NPCDebug.enabled = not NPCDebug.enabled
	print("[AdminMenu] NPC debug logging: %s" % ("ON" if NPCDebug.enabled else "OFF"))

func _on_npc_print_debug_pressed() -> void:
	NPCDebug.dump_all(get_tree())

func _on_npc_print_cleaning_debug_pressed() -> void:
	NPCDebug.dump_cleaning_state(get_tree())

func _on_npc_print_job_debug_pressed() -> void:
	NPCDebug.dump_job_state(get_tree())

## Part 29 — forces the NEAREST spawned NPC to attempt a snatch against
## the player right now, bypassing relationship/probability (still
## requires the player to actually be holding a matching food/water
## item). Nearest-to-player, not nearest-to-camera or first-spawned.
func _on_npc_force_snatch_pressed() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		push_warning("[AdminMenu] No player found — cannot force snatch")
		return
	var nearest: Node = null
	var nearest_d: float = INF
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		var d: float = (npc as Node3D).global_position.distance_to((player as Node3D).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = npc
	if nearest == null:
		push_warning("[AdminMenu] No NPCs spawned — cannot force snatch")
		return
	if nearest.has_method("debug_force_snatch") and not nearest.debug_force_snatch():
		print("[AdminMenu] Force snatch failed — player isn't holding a matching food/water item")

func _nearest_npc_to_player() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return null
	var nearest: Node = null
	var nearest_d: float = INF
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		var d: float = (npc as Node3D).global_position.distance_to((player as Node3D).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = npc
	return nearest

func _on_npc_force_talk_pressed() -> void:
	var nearest: Node = _nearest_npc_to_player()
	if nearest == null:
		push_warning("[AdminMenu] No NPCs spawned — cannot force talk")
		return
	if not nearest.has_method("debug_force_talk") or not nearest.debug_force_talk():
		print("[AdminMenu] Force talk failed — no free NPC partner within TALK_RANGE")

func _on_npc_force_give_friend_pressed() -> void:
	var nearest: Node = _nearest_npc_to_player()
	if nearest == null:
		push_warning("[AdminMenu] No NPCs spawned — cannot force give-to-friend")
		return
	if not nearest.has_method("debug_force_give_to_friend") or not nearest.debug_force_give_to_friend():
		print("[AdminMenu] Force give-to-friend failed — no eligible needy friend + matching loose item")

func _on_npc_force_npc_snatch_pressed() -> void:
	var nearest: Node = _nearest_npc_to_player()
	if nearest == null:
		push_warning("[AdminMenu] No NPCs spawned — cannot force NPC snatch")
		return
	if not nearest.has_method("debug_force_npc_snatch") or not nearest.debug_force_npc_snatch():
		print("[AdminMenu] Force NPC snatch failed — no eligible disliked NPC holding a matching item")

func _on_npc_relationship_down_pressed() -> void: _adjust_all_npc_relationship(-25.0)
func _on_npc_relationship_up_pressed() -> void:   _adjust_all_npc_relationship(25.0)

func _adjust_all_npc_relationship(delta: float) -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(npc) and npc.has_method("debug_adjust_player_relationship"):
			npc.debug_adjust_player_relationship(delta)

func _on_npc_npc_relationship_down_pressed() -> void: _adjust_all_npc_npc_relationships(-25.0)
func _on_npc_npc_relationship_up_pressed() -> void:   _adjust_all_npc_npc_relationships(25.0)

## Adjusts every DIRECTED pair independently (A's feeling toward B, and
## B's feeling toward A, separately) — relationships are one-sided per
## NPC, same as everywhere else in this system.
func _adjust_all_npc_npc_relationships(delta: float) -> void:
	var npcs: Array = get_tree().get_nodes_in_group("npc")
	for npc: Node in npcs:
		if not is_instance_valid(npc) or not npc.has_method("debug_adjust_relationship"):
			continue
		for other: Node in npcs:
			if other == npc or not is_instance_valid(other) or not ("npc_id" in other):
				continue
			npc.debug_adjust_relationship(other.npc_id, delta)

## Adds a flat $100,000 through MainWorld.add_cash() rather than writing
## MainWorld._cash directly — add_cash() is what also pushes the new balance
## into the HUD via hud.set_cash(). Writing _cash directly would desync the
## HUD readout until the next transaction.
func _on_add_cash_pressed() -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cash cheat skipped")
		return
	world_node.add_cash(ADMIN_CASH_STEP)

## "2x water output" == tier + 1, because WaterHookup.TIER_DAILY_ML is
## [3000, 6000, 12000, 24000] — each tier is exactly double the last. Bumping
## the tier is therefore the doubling, and it goes through the real upgrade
## data path instead of inventing a debug-only multiplier. Clamped at the top
## tier (no-op there, no error). Nothing needs to be refreshed afterwards:
## WaterManager and WaterInfoUI both call get_daily_output_mL() live.
func _on_hookup_output_double_pressed() -> void:
	var wm: WaterManager = _get_water_manager()
	if wm == null:
		return
	var hookup: WaterHookup = wm.get_the_hookup()
	if hookup == null:
		return
	var max_tier: int = WaterHookup.TIER_DAILY_ML.size() - 1
	if hookup.tier >= max_tier:
		push_warning("[AdminMenu] hookup already at max tier (%d) — output unchanged" % max_tier)
		return
	hookup.tier += 1

## Debug-only — clamped at the same STORAGE_CAP everything else respects.
## Per direction, exceptions/bypasses to the cap may be added later; this
## pass applies the cap uniformly, including here.
func _on_add_research_materials_pressed() -> void:
	var station: ResearchStation = _get_research_station()
	if station == null:
		push_warning("[AdminMenu] research station not found — material cheat skipped")
		return
	for material: String in ResearchStation.MATERIAL_TYPES:
		station.add_material(material, 10)

## Shared spawner for the three FARMING rows. Mirrors
## FarmingShopHelper.spawn_purchased_item()'s positioning exactly (player
## position + 1.8 up, item falls under normal gravity into normal pickup
## rules) — deliberately reusing FarmProduceItem.spawn_at() rather than
## instancing here, so admin-spawned produce is byte-for-byte the same object
## a harvest produces (pop-in tween, jitter, charges, all of it).
## No cash cost — this is a cheat menu, not the shop.
func _spawn_produce(produce_type: String) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		push_warning("[AdminMenu] no player in tree — produce spawn skipped")
		return
	var parent: Node = player.get_parent()
	if parent == null:
		return
	var base_pos: Vector3 = player.global_position + Vector3(0.0, PRODUCE_SPAWN_HEIGHT, 0.0)
	FarmProduceItem.spawn_at(parent, base_pos, produce_type)

func _on_spawn_potato_pressed() -> void:
	_spawn_produce("potato")

func _on_spawn_blueberry_pressed() -> void:
	_spawn_produce("blueberry")

func _on_spawn_tomato_pressed() -> void:
	_spawn_produce("tomato")

func _on_spawn_onion_pressed() -> void:
	_spawn_produce("onion")

func _on_spawn_basil_pressed() -> void:
	_spawn_produce("basil")

func _on_spawn_strawberry_pressed() -> void:
	_spawn_produce("strawberry")

func _on_spawn_carrot_pressed() -> void:
	_spawn_produce("carrot")

func _on_spawn_chili_pepper_pressed() -> void:
	_spawn_produce("chili_pepper")

func _on_spawn_bell_pepper_pressed() -> void:
	_spawn_produce("bell_pepper")

func _on_spawn_garlic_pressed() -> void:
	_spawn_produce("garlic")

func _on_spawn_corn_pressed() -> void:
	_spawn_produce("corn")

func _on_spawn_pumpkin_pressed() -> void:
	_spawn_produce("pumpkin")
