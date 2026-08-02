extends CanvasLayer
## AdminMenu.gd
## F7 general-purpose admin controls panel — direct system cheats/
## debug toggles that don't correspond to a placeable object.
## Injected refs set by MainWorld._toggle_admin_cheat_menu().
##
## Structure (Jul 2026 rewrite) — mirrors WaterInfoUI.gd's panel convention
## instead of the old plain Panel/VBox popup: full-screen dim overlay, a
## drawn bordered panel with a header, an X close button, ESC/E to close,
## and a column of real clickable Button rows (one per cheat action) laid
## out under section labels. Reuses the same draw-based background so this
## reads visually consistent with the rest of the game's info panels.

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
const ROW_H:   float = 34.0
const ROW_GAP: float = 8.0

const ADMIN_POWER_STEP_WATTS: float = 1000.0
const QUALITY_SCALE_DOWN: float = 0.5    ## "-50%" halves current quality
const QUALITY_SCALE_UP:   float = 1.5    ## "+50%" raises current quality by half

const TEST_EFFECT_DURATION: float = 10.0
const TEST_EFFECT_COLOR: Color = Color(0.86, 0.57, 0.19, 1.0)   ## matches StatusEffectIcon's own default (Jul 2026 — darkened 5%)

const ADMIN_CASH_STEP: int = 100000          ## "+$100,000" economy cheat row

## Farming produce spawn — matches FarmingShopHelper.SPAWN_HEIGHT_ABOVE_PLAYER
## (1.8) so admin-spawned produce drops exactly like a shop purchase does.
const PRODUCE_SPAWN_HEIGHT: float = 1.8

## One entry per clickable row: [section-or-"" , label, callback]
## A "" section repeats the previous section's header (skipped).
var _row_defs: Array = []

# ─── State ────────────────────────────────────────────────────────────────────
var _canvas:  Control = null
var _font:    Font    = null
var _close_btn: Button = null
var _row_buttons: Array[Button] = []
var _is_open: bool = false
var _test_effect_count: int = 0

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

	_row_defs = [
		["POWER", "+ %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_add_power_pressed],
		["",      "- %d w Power" % int(ADMIN_POWER_STEP_WATTS), _on_remove_power_pressed],
		["TIME",  "Fast-Forward 1 Day", _on_fast_forward_pressed],
		["WATER", "Hookup Quality -50%", _on_quality_down_pressed],
		["",      "Hookup Quality +50%", _on_quality_up_pressed],
		["",      "Hookup Output x2 (Tier +1)", _on_hookup_output_double_pressed],
		["ECONOMY", "+ $%s Cash" % _format_thousands(ADMIN_CASH_STEP), _on_add_cash_pressed],
		["FARMING", "Spawn Potato", _on_spawn_potato_pressed],
		["",        "Spawn Blueberry", _on_spawn_blueberry_pressed],
		["",        "Spawn Tomato", _on_spawn_tomato_pressed],
		["STATUS", "Add Test Status Effect (10s)", _on_add_status_effect_pressed],
		["NPC",    "Spawn NPC", _on_spawn_npc_pressed],
		["",       "Drain NPC Needs -40", _on_drain_npc_needs_pressed],
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

	for def: Array in _row_defs:
		var btn: Button = Button.new()
		btn.text       = String(def[1])
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(def[2])
		_style_row_btn(btn)
		add_child(btn)
		_row_buttons.append(btn)

func _panel_height() -> float:
	var section_count: int = 0
	for def: Array in _row_defs:
		if not String(def[0]).is_empty():
			section_count += 1
	var rows: int = _row_defs.size()
	## header + separator + per-section label (18px) + per-row (ROW_H+gap) + footer
	return 60.0 + float(section_count) * 22.0 + float(rows) * (ROW_H + ROW_GAP) + 24.0

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
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	var cy: float = py + 60.0
	for i: int in range(_row_defs.size()):
		var def: Array = _row_defs[i]
		if not String(def[0]).is_empty():
			cy += 22.0   ## room for the section label drawn above this row
		var btn: Button = _row_buttons[i]
		btn.position = Vector2(px + 20.0, cy)
		btn.size     = Vector2(PANEL_W - 40.0, ROW_H)
		cy += ROW_H + ROW_GAP

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
	for btn: Button in _row_buttons:
		btn.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	for btn: Button in _row_buttons:
		btn.visible = false
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
		var ph: float    = _panel_height()
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - ph) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
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
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.60), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
	_canvas.draw_rect(panel, BG_COLOR, true)
	_canvas.draw_rect(panel, BORDER_COLOR, false, 2.0)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 10.0, 30.0, 30.0)
	_canvas.draw_rect(close_rect, Color(0.10, 0.06, 0.06, 0.90), true)
	_canvas.draw_rect(close_rect, CRIT_COLOR, false, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)
	_canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)

	var cx: float = px + 20.0
	var cy: float = py + 20.0

	_draw_str("[F7]  ADMIN CONTROLS", Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)
	cy += 12.0

	for i: int in range(_row_defs.size()):
		var def: Array = _row_defs[i]
		var section: String = String(def[0])
		if not section.is_empty():
			_draw_str("─── %s ───" % section, Vector2(cx, cy), DIM_COLOR, 10)
			cy += 22.0
		cy += ROW_H + ROW_GAP

	_draw_str("[ESC / E]  Close", Vector2(cx, py + ph - 18.0), DIM_COLOR, 9)

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
