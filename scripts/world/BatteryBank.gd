extends StaticBody3D
class_name BatteryBank
## BatteryBank.gd  — v2.0
## Wall/floor-mounted battery bank.  Three tiers: Small / Medium / Large.
## Stores energy when generators have surplus, discharges when generators fail.
##
## CHANGED in v2.0:
##   - E-key now opens a small CanvasLayer info panel:
##       • Charge % + Wh remaining
##       • HP bar  (future — stubbed at 100%)
##       • On / Off toggle (set_enabled → PM.set_battery_enabled)
##       • State label (CHARGING / DISCHARGING / IDLE / INACTIVE / DRAINED)
##   - set_enabled(bool) wires through to PowerManager.set_battery_enabled().
##
## Tier capacities (tuned to game-minutes at 500w draw):
##   Small  — 100 Wh  ≈ 12 game-hours at 500w
##   Medium — 300 Wh  ≈ 36 game-hours at 500w
##   Large  — 600 Wh  ≈ 72 game-hours at 500w
##
## PowerManager integration:
##   _ready()     → register_wire_node() → register_battery()
##   _exit_tree() → unregister_battery() → unregister_wire_node()
##   set_charge_display(wh, cap)  — called by PM each tick
##   set_battery_mode(charging, discharging) — called by PM on state change
##   set_grid_connected(bool)     — called by PM after each solve

# ─── Tier config ──────────────────────────────────────────────────────────────
const TIER_CONFIG: Array = [
	{ "label": "Battery S", "capacity_wh": 100.0, "price": 150, "size": Vector3(0.40, 0.70, 0.22) },
	{ "label": "Battery M", "capacity_wh": 300.0, "price": 350, "size": Vector3(0.50, 0.90, 0.26) },
	{ "label": "Battery L", "capacity_wh": 600.0, "price": 600, "size": Vector3(0.60, 1.10, 0.28) },
]

# ─── Colours ──────────────────────────────────────────────────────────────────
const COLOR_BODY:          Color = Color(0.25, 0.28, 0.28, 1.0)
const COLOR_PANEL:         Color = Color(0.15, 0.18, 0.18, 1.0)
const COLOR_STRIP_FULL:    Color = Color(0.10, 0.95, 0.35, 1.0)
const COLOR_STRIP_LOW:     Color = Color(1.00, 0.75, 0.10, 1.0)
const COLOR_STRIP_EMPTY:   Color = Color(0.25, 0.25, 0.25, 1.0)
const COLOR_LED_CHARGE:    Color = Color(0.10, 0.90, 0.30, 1.0)
const COLOR_LED_DISCHARGE: Color = Color(1.00, 0.75, 0.10, 1.0)
const COLOR_LED_IDLE:      Color = Color(0.30, 0.30, 0.30, 1.0)

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var battery_tier: int = 0   ## 0=Small  1=Medium  2=Large

# ─── State ────────────────────────────────────────────────────────────────────
var _charge_wh:     float = 0.0
var _capacity_wh:   float = 0.0
var _discharging:   bool  = false
var _charging:      bool  = false
var _grid_connected: bool = false
var _enabled:       bool  = true    ## player-toggleable via info panel

var _pm_id:    String = ""
var _wire_key: String = ""
var _bat_id:   String = ""

# ─── Mesh refs ────────────────────────────────────────────────────────────────
var _strip_mat:   StandardMaterial3D = null
var _strip_mi:    MeshInstance3D     = null
var _led_mat:     StandardMaterial3D = null
var _strip_max_h: float              = 0.0

# ─── Banner ───────────────────────────────────────────────────────────────────
var _banner:        Label3D = null
var _player_nearby: bool    = false

# ─── Info panel (CanvasLayer) ─────────────────────────────────────────────────
var _panel_layer:  CanvasLayer = null
var _panel_canvas: Control     = null
var _panel_open:   bool        = false
var _font: Font = null

## Panel dimensions
const PANEL_W: float = 280.0
const PANEL_H: float = 190.0
const PAD:     float = 14.0

## UI colours (matching BreakerBox style)
const UI_BG:     Color = Color(0.05, 0.08, 0.05, 0.96)
const UI_BORDER: Color = Color(0.28, 0.85, 0.32, 0.75)
const UI_TEXT:   Color = Color(0.80, 0.95, 0.82, 0.95)
const UI_DIM:    Color = Color(0.45, 0.55, 0.45, 0.85)
const UI_ON:     Color = Color(0.20, 0.90, 0.35, 1.0)
const UI_OFF:    Color = Color(0.90, 0.28, 0.15, 1.0)
const UI_WARN:   Color = Color(1.00, 0.72, 0.10, 1.0)
const UI_HEADER: Color = Color(0.22, 0.75, 0.28, 1.0)

## Hit-test rects (screen-space, built during draw)
var _rect_close:     Rect2 = Rect2()
var _rect_toggle:    Rect2 = Rect2()
var _panel_rect:     Rect2 = Rect2()


# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	battery_tier = clamp(battery_tier, 0, 2)
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("battery")
	_capacity_wh = float(TIER_CONFIG[battery_tier]["capacity_wh"])
	_charge_wh   = 0.0
	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font
	_build_mesh()
	_build_banner()
	_build_panel()
	_register_with_pm()


func _exit_tree() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return
	if not _bat_id.is_empty() and pm.has_method("unregister_battery"):
		pm.call("unregister_battery", _bat_id)
	if not _wire_key.is_empty() and pm.has_method("unregister_wire_node"):
		pm.call("unregister_wire_node", _wire_key)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER REGISTRATION
# ══════════════════════════════════════════════════════════════════════════════

func _register_with_pm() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		push_warning("BatteryBank: PowerManager not found")
		return
	_pm_id  = str(get_instance_id())
	_bat_id = _pm_id
	call_deferred("_register_deferred")


func _register_deferred() -> void:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return
	if pm.has_method("register_wire_node"):
		_wire_key = pm.call("register_wire_node", global_position, "battery", _pm_id)
	if pm.has_method("register_battery"):
		pm.call("register_battery", _bat_id, _capacity_wh, self, 0.0)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

func set_charge_display(wh: float, cap: float) -> void:
	_charge_wh   = wh
	_capacity_wh = cap if cap > 0.0 else _capacity_wh
	_sync_strip()
	_sync_led()
	if _player_nearby:
		_sync_banner()
	if _panel_open and _panel_canvas != null:
		_panel_canvas.queue_redraw()


func set_battery_mode(charging: bool, discharging: bool) -> void:
	_charging    = charging
	_discharging = discharging
	_sync_led()
	if _player_nearby:
		_sync_banner()
	if _panel_open and _panel_canvas != null:
		_panel_canvas.queue_redraw()


func set_grid_connected(connected: bool) -> void:
	if connected == _grid_connected:
		return
	_grid_connected = connected
	_sync_led()
	if _player_nearby:
		_sync_banner()
	if _panel_open and _panel_canvas != null:
		_panel_canvas.queue_redraw()


## Called by the info panel toggle — routes through PM.
func set_enabled(on: bool) -> void:
	_enabled = on
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm != null and pm.has_method("set_battery_enabled") and not _bat_id.is_empty():
		pm.call("set_battery_enabled", _bat_id, _enabled)
	_sync_led()
	if _panel_open and _panel_canvas != null:
		_panel_canvas.queue_redraw()


# ══════════════════════════════════════════════════════════════════════════════
# INTERACTION
# ══════════════════════════════════════════════════════════════════════════════

func get_interact_prompt() -> String:
	var pct: int = _charge_pct()
	return "%s — %d%%  [E] Info" % [TIER_CONFIG[battery_tier]["label"], pct]


func on_interact() -> void:
	if _panel_open:
		_close_panel()
	else:
		_open_panel()


func set_player_in_range(in_range: bool) -> void:
	_player_nearby = in_range
	if _banner != null:
		_banner.visible = in_range
	if in_range:
		_sync_banner()
	if not in_range and _panel_open:
		_close_panel()


# ══════════════════════════════════════════════════════════════════════════════
# INFO PANEL
# ══════════════════════════════════════════════════════════════════════════════

func _build_panel() -> void:
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 60
	_panel_layer.visible = false
	add_child(_panel_layer)

	_panel_canvas = Control.new()
	_panel_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_canvas.name = "BatteryInfoCanvas"
	_panel_layer.add_child(_panel_canvas)
	_panel_canvas.draw.connect(_on_panel_draw)
	_panel_canvas.gui_input.connect(_on_panel_input)


func _open_panel() -> void:
	_panel_open = true
	_panel_layer.visible = true
	_panel_canvas.queue_redraw()


func _close_panel() -> void:
	_panel_open = false
	_panel_layer.visible = false


func _on_panel_draw() -> void:
	if not _panel_open:
		return

	var vp: Vector2 = _panel_canvas.get_viewport_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	## Dim background
	_panel_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.42), true)

	## Panel bg + border
	_panel_rect = Rect2(px, py, PANEL_W, PANEL_H)
	_panel_canvas.draw_rect(_panel_rect, UI_BG, true)
	_panel_canvas.draw_rect(_panel_rect, UI_BORDER, false, 2.0)

	## ── Title ─────────────────────────────────────────────────────────────────
	var cfg: Dictionary = TIER_CONFIG[battery_tier]
	var title_y: float  = py + PAD + 11.0
	_ds("🔋 " + (cfg["label"] as String).to_upper(), Vector2(px + PAD, title_y), UI_HEADER, 13)

	## ── State ─────────────────────────────────────────────────────────────────
	var state: String = _state_string()
	var state_col: Color = _state_color()
	_ds(state, Vector2(px + PANEL_W - PAD - 80.0, title_y), state_col, 11)

	## ── Separator ─────────────────────────────────────────────────────────────
	var sep_y: float = title_y + 16.0
	_panel_canvas.draw_line(Vector2(px + PAD, sep_y), Vector2(px + PANEL_W - PAD, sep_y),
		UI_BORDER * Color(1, 1, 1, 0.5), 1.0)

	## ── Charge bar ────────────────────────────────────────────────────────────
	var bar_y: float = sep_y + 14.0
	_ds("Charge", Vector2(px + PAD, bar_y), UI_TEXT, 10)
	var pct: float = clampf(_charge_wh / maxf(_capacity_wh, 1.0), 0.0, 1.0)
	var pct_int: int = int(pct * 100.0)
	_ds("%d%%  (%.0f / %.0f Wh)" % [pct_int, _charge_wh, _capacity_wh],
		Vector2(px + 66.0, bar_y), _pct_color(pct), 10)

	var bbar_y: float = bar_y + 14.0
	var bbar_w: float = PANEL_W - PAD * 2.0
	_panel_canvas.draw_rect(Rect2(px + PAD, bbar_y, bbar_w, 8.0),
		Color(0.12, 0.12, 0.12, 0.90), true)
	_panel_canvas.draw_rect(Rect2(px + PAD, bbar_y, bbar_w * pct, 8.0),
		_pct_color(pct), true)
	_panel_canvas.draw_rect(Rect2(px + PAD, bbar_y, bbar_w, 8.0),
		UI_BORDER * Color(1, 1, 1, 0.40), false, 1.0)

	## ── HP bar (placeholder at 100%) ──────────────────────────────────────────
	var hp_y: float = bbar_y + 20.0
	_ds("Health", Vector2(px + PAD, hp_y), UI_TEXT, 10)
	_ds("100%", Vector2(px + 66.0, hp_y), UI_ON, 10)
	_panel_canvas.draw_rect(Rect2(px + PAD, hp_y + 12.0, bbar_w, 6.0),
		Color(0.12, 0.12, 0.12, 0.90), true)
	_panel_canvas.draw_rect(Rect2(px + PAD, hp_y + 12.0, bbar_w, 6.0),
		UI_ON, true)
	_panel_canvas.draw_rect(Rect2(px + PAD, hp_y + 12.0, bbar_w, 6.0),
		UI_BORDER * Color(1, 1, 1, 0.40), false, 1.0)

	## ── Separator ─────────────────────────────────────────────────────────────
	var sep2_y: float = hp_y + 26.0
	_panel_canvas.draw_line(Vector2(px + PAD, sep2_y), Vector2(px + PANEL_W - PAD, sep2_y),
		UI_BORDER * Color(1, 1, 1, 0.35), 1.0)

	## ── On / Off toggle ───────────────────────────────────────────────────────
	var tog_y: float = sep2_y + 10.0
	var row_rect: Rect2 = Rect2(px + PAD, tog_y, PANEL_W - PAD * 2.0, 30.0)
	_panel_canvas.draw_rect(row_rect, Color(0.10, 0.14, 0.10, 0.60), true)
	_panel_canvas.draw_rect(row_rect, UI_BORDER * Color(1, 1, 1, 0.35), false, 1.0)
	_ds("Battery unit", Vector2(px + PAD + 6.0, tog_y + 18.0), UI_TEXT, 10)

	## Pill toggle
	var pill_w: float = 42.0
	var pill_h: float = 18.0
	var pill_x: float = px + PANEL_W - PAD - pill_w - 4.0
	var pill_y: float = tog_y + 6.0
	_rect_toggle = Rect2(px + PAD, tog_y, PANEL_W - PAD * 2.0, 30.0)
	var pill_rect: Rect2 = Rect2(pill_x, pill_y, pill_w, pill_h)
	var pill_col: Color  = UI_ON if _enabled else UI_DIM
	_panel_canvas.draw_rect(pill_rect, pill_col * Color(1, 1, 1, 0.75), true)
	_panel_canvas.draw_rect(pill_rect, pill_col, false, 1.5)
	_ds("ON" if _enabled else "OFF", Vector2(pill_x + 9.0, pill_y + 12.0), Color(1, 1, 1, 0.95), 9)

	## ── Close + footer ────────────────────────────────────────────────────────
	_rect_close = Rect2(px + PANEL_W - PAD - 24.0, py + PANEL_H - PAD - 20.0, 24.0, 20.0)
	_panel_canvas.draw_rect(_rect_close, Color(0.25, 0.06, 0.06, 0.90), true)
	_panel_canvas.draw_rect(_rect_close, UI_OFF * Color(1, 1, 1, 0.7), false, 1.5)
	_ds("✕", Vector2(_rect_close.position.x + 5.0, _rect_close.position.y + 14.0),
		Color(1.0, 0.7, 0.7, 1.0), 11)
	_ds("[ESC] close", Vector2(px + PAD, py + PANEL_H - PAD - 10.0), UI_DIM, 9)


func _on_panel_input(event: InputEvent) -> void:
	if not _panel_open:
		return

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_panel()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mpos: Vector2 = (event as InputEventMouseButton).position

		if _rect_close.has_point(mpos):
			_close_panel()
			get_viewport().set_input_as_handled()
			return

		if _rect_toggle.has_point(mpos):
			set_enabled(not _enabled)
			get_viewport().set_input_as_handled()
			return

		if _panel_rect.has_point(mpos):
			get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════════════════════════════════
# MESH BUILD
# ══════════════════════════════════════════════════════════════════════════════

func _build_mesh() -> void:
	var cfg: Dictionary = TIER_CONFIG[battery_tier]
	var sz:  Vector3    = cfg["size"]

	## Body
	var body_mi:   MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh        = BoxMesh.new()
	body_mesh.size = sz
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, sz.y * 0.5, 0.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.80
	body_mat.metallic     = 0.55
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)
	body_mi.create_trimesh_collision()
	for child: Node in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Front panel
	var panel_mi:   MeshInstance3D = MeshInstance3D.new()
	var panel_mesh: BoxMesh        = BoxMesh.new()
	panel_mesh.size  = Vector3(sz.x * 0.85, sz.y * 0.85, 0.025)
	panel_mi.mesh    = panel_mesh
	panel_mi.position = Vector3(0.0, sz.y * 0.5, sz.z * 0.5 + 0.012)
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = COLOR_PANEL
	panel_mat.roughness    = 0.65
	panel_mi.set_surface_override_material(0, panel_mat)
	add_child(panel_mi)

	## Charge strip track
	var track_w:  float = sz.x * 0.22
	var track_h:  float = sz.y * 0.65
	var track_mi:   MeshInstance3D = MeshInstance3D.new()
	var track_mesh: BoxMesh        = BoxMesh.new()
	track_mesh.size  = Vector3(track_w, track_h, 0.018)
	track_mi.mesh    = track_mesh
	track_mi.position = Vector3(-sz.x * 0.25, sz.y * 0.5, sz.z * 0.5 + 0.025)
	var track_mat: StandardMaterial3D = StandardMaterial3D.new()
	track_mat.albedo_color = Color(0.10, 0.10, 0.10, 1.0)
	track_mat.roughness    = 0.90
	track_mi.set_surface_override_material(0, track_mat)
	add_child(track_mi)

	## Charge strip fill
	_strip_max_h = track_h * 0.95
	_strip_mi = MeshInstance3D.new()
	var strip_mesh: BoxMesh = BoxMesh.new()
	strip_mesh.size = Vector3(track_w * 0.80, 0.01, 0.022)
	_strip_mi.mesh  = strip_mesh
	_strip_mi.position = Vector3(-sz.x * 0.25, sz.y * 0.5 - track_h * 0.5, sz.z * 0.5 + 0.028)
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.albedo_color              = COLOR_STRIP_EMPTY
	_strip_mat.emission_enabled          = true
	_strip_mat.emission                  = COLOR_STRIP_EMPTY
	_strip_mat.emission_energy_multiplier = 1.0
	_strip_mi.set_surface_override_material(0, _strip_mat)
	add_child(_strip_mi)

	## LED
	var led_mi:   MeshInstance3D = MeshInstance3D.new()
	var led_mesh: BoxMesh        = BoxMesh.new()
	led_mesh.size  = Vector3(0.06, 0.06, 0.025)
	led_mi.mesh    = led_mesh
	led_mi.position = Vector3(sz.x * 0.22, sz.y * 0.5 + sz.y * 0.35, sz.z * 0.5 + 0.038)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color              = COLOR_LED_IDLE
	_led_mat.emission_enabled          = true
	_led_mat.emission                  = COLOR_LED_IDLE
	_led_mat.emission_energy_multiplier = 1.5
	led_mi.set_surface_override_material(0, _led_mat)
	add_child(led_mi)

	## Tier label
	var tier_lbl: Label3D = Label3D.new()
	tier_lbl.text       = (cfg["label"] as String).to_upper()
	tier_lbl.font_size  = 28
	tier_lbl.pixel_size = 0.0014
	tier_lbl.billboard  = BaseMaterial3D.BILLBOARD_DISABLED
	tier_lbl.modulate   = Color(0.60, 0.80, 0.70, 1.0)
	tier_lbl.position   = Vector3(sz.x * 0.16, sz.y * 0.5 + sz.y * 0.10, sz.z * 0.5 + 0.028)
	add_child(tier_lbl)


# ══════════════════════════════════════════════════════════════════════════════
# BANNER
# ══════════════════════════════════════════════════════════════════════════════

func _build_banner() -> void:
	var sz: Vector3 = TIER_CONFIG[battery_tier]["size"]
	var lbl: Label3D = Label3D.new()
	lbl.text          = "0% CHARGE"
	lbl.font_size     = 48
	lbl.pixel_size    = 0.0018
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate      = Color(0.90, 0.95, 0.90, 1.0)
	lbl.position      = Vector3(0.0, sz.y + 0.20, 0.0)
	lbl.visible       = false
	add_child(lbl)
	_banner = lbl


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL SYNC
# ══════════════════════════════════════════════════════════════════════════════

func _charge_pct() -> int:
	if _capacity_wh <= 0.0:
		return 0
	return int(clampf(_charge_wh / _capacity_wh, 0.0, 1.0) * 100.0)


func _state_string() -> String:
	if not _enabled:
		return "DISABLED"
	if not _grid_connected:
		return "INACTIVE"
	if _charge_wh <= 0.0:
		return "DRAINED"
	if _discharging:
		return "DISCHARGING"
	if _charging:
		return "CHARGING"
	return "IDLE"


func _state_color() -> Color:
	match _state_string():
		"CHARGING":    return UI_ON
		"DISCHARGING": return UI_WARN
		"DRAINED":     return UI_OFF
		"DISABLED":    return UI_DIM
		"INACTIVE":    return UI_DIM
	return UI_TEXT   ## IDLE


func _pct_color(ratio: float) -> Color:
	if ratio <= 0.0:    return COLOR_STRIP_EMPTY
	if ratio <= 0.15:   return UI_OFF
	if ratio <= 0.40:   return UI_WARN
	return UI_ON


func _sync_strip() -> void:
	if _strip_mi == null or _strip_mat == null:
		return
	var ratio: float = clampf(_charge_wh / maxf(_capacity_wh, 1.0), 0.0, 1.0)
	var new_h: float = maxf(0.005, _strip_max_h * ratio)
	var sz: Vector3   = TIER_CONFIG[battery_tier]["size"]
	var track_w: float = sz.x * 0.22
	var bm: BoxMesh   = BoxMesh.new()
	bm.size = Vector3(track_w * 0.80, new_h, 0.022)
	_strip_mi.mesh = bm
	var track_h: float = sz.y * 0.65
	_strip_mi.position = Vector3(
		-sz.x * 0.25,
		sz.y * 0.5 - track_h * 0.5 + new_h * 0.5,
		sz.z * 0.5 + 0.028
	)
	var col: Color = COLOR_STRIP_FULL if ratio >= 0.40 else \
		(COLOR_STRIP_LOW if ratio > 0.0 else COLOR_STRIP_EMPTY)
	_strip_mat.albedo_color = col
	_strip_mat.emission     = col


func _sync_led() -> void:
	if _led_mat == null:
		return
	var col: Color
	if not _enabled:
		col = Color(0.18, 0.18, 0.18, 1.0)   ## dark = disabled
	elif not _grid_connected:
		col = COLOR_LED_IDLE
	elif _discharging:
		col = COLOR_LED_DISCHARGE
	elif _charging:
		col = COLOR_LED_CHARGE
	else:
		col = COLOR_LED_IDLE
	_led_mat.albedo_color = col
	_led_mat.emission     = col


func _sync_banner() -> void:
	if _banner == null:
		return
	var pct: int = _charge_pct()
	_banner.text = "%d%%  |  %s" % [pct, _state_string()]
	if pct <= 15:
		_banner.modulate = Color(1.0, 0.30, 0.15, 1.0)
	elif pct <= 40:
		_banner.modulate = Color(1.0, 0.75, 0.10, 1.0)
	else:
		_banner.modulate = Color(0.90, 0.95, 0.90, 1.0)
	if not _enabled:
		_banner.modulate = Color(0.55, 0.55, 0.55, 1.0)


## Shorthand draw helper.
func _ds(text: String, pos: Vector2, col: Color, size: int) -> void:
	_panel_canvas.draw_string(
		_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_panel_canvas.draw_string(
		_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
