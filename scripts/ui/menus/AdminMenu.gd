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
const BG_COLOR:     Color = Color(0.08, 0.08, 0.10, 0.97)
const BORDER_COLOR: Color = Color(0.55, 0.58, 0.42, 0.85)   ## dull olive/brass accent
const HEADER_COLOR: Color = Color(0.80, 0.82, 0.62, 1.00)
const TEXT_COLOR:   Color = Color(0.85, 0.87, 0.80, 0.95)
const DIM_COLOR:    Color = Color(0.55, 0.58, 0.52, 0.80)
const CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)

# ─── Layout ───────────────────────────────────────────────────────────────────
const PANEL_W: float = 320.0
const PANEL_H: float = 480.0   ## Jul 2026 — fixed again (was computed from
                                ## row count, which is what let it grow to
                                ## ~1250px). Overflow content scrolls instead.
const ROW_H:   float = 34.0
const ROW_GAP: float = 6.0
const SECTION_GAP: float = 10.0   ## vertical gap between one section and the next

const ADMIN_POWER_STEP_WATTS: float = 1000.0
const QUALITY_SCALE_DOWN: float = 0.5    ## "-50%" halves current quality
const QUALITY_SCALE_UP:   float = 1.5    ## "+50%" raises current quality by half

const TEST_EFFECT_DURATION: float = 10.0
const TEST_EFFECT_COLOR: Color = Color(0.86, 0.57, 0.19, 1.0)   ## matches StatusEffectIcon's own default (Jul 2026 — darkened 5%)

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

func _ready() -> void:
	layer   = 128   ## On top of everything (PauseMenuUI sits above at 200)
	visible = false
	set_process(false)

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
		{ "name": "FARMING", "rows": [
			["Spawn Potato", _on_spawn_potato_pressed],
			["Spawn Blueberry", _on_spawn_blueberry_pressed],
			["Spawn Tomato", _on_spawn_tomato_pressed],
		]},
		{ "name": "STATUS", "rows": [
			["Add Test Status Effect (10s)", _on_add_status_effect_pressed],
		]},
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
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
	grabber.set_corner_radius_all(3)
	var grabber_hi: StyleBoxFlat = grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.85)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.25)
	track.set_corner_radius_all(3)
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
	normal.bg_color = Color(0.16, 0.17, 0.13, 0.55)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 8.0
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.23, 0.18, 0.75)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

func _style_row_btn(btn: Button) -> void:
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color     = Color(0.14, 0.15, 0.13, 0.90)
	normal.border_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(0.22, 0.23, 0.18, 0.95)
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

func _process(_delta: float) -> void:
	if _is_open:
		_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _is_open:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.60), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	UIKit.draw_rounded_rect(_canvas, panel, BG_COLOR, BORDER_COLOR, 2.0)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 16.0, 30.0, 30.0)
	UIKit.draw_rounded_rect(_canvas, close_rect, Color(0.10, 0.06, 0.06, 0.90), CRIT_COLOR, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)
	_canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)

	var cx: float = px + 20.0
	var cy: float = py + 26.0

	_draw_str("[F7]  ADMIN CONTROLS", Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)

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

func _get_status_effects() -> StatusEffectsContainer:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not ("status_effects" in hud):
		return null
	return hud.get("status_effects") as StatusEffectsContainer

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
## (WaterHookup), and plant growth (every FarmPlant) — instead of
## reimplementing any of that math here, so this can't drift out of sync
## with what 24 hours of normal play would actually do.
func _on_fast_forward_pressed() -> void:
	var stats: PlayerStats = _get_player_stats()
	if stats == null:
		return
	var scaled: float = 24.0 * stats._seconds_per_game_hour

	stats.skip_time_with_drain(24.0)
	NPC.catch_up_all(24.0)

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
