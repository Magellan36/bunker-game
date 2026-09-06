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

## Low-battery flicker (graphics plan Section 4 VFX priority #3) — purely a
## post-process on top of _sync_led()/_sync_strip()'s existing color choice,
## does not change what color is shown, only pulses its emission energy when
## discharging under this threshold. Base multipliers (1.5 for LED, 1.0 for
## strip) match the constants already used in _build_mesh().
const LOW_BATTERY_FLICKER_THRESHOLD: float = 0.15
const LED_BASE_ENERGY:    float = 1.5
const STRIP_BASE_ENERGY:  float = 1.0

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
var _flicker_t: float = 0.0   ## low-battery flicker phase, see _process()

## Full-fidelity preview mode (Jul 2026) — set TRUE by BuildModeHUD's
## construct-tab preview code BEFORE add_child(), so this instance builds
## its real visual exactly like a placed object but skips every
## side-effecting call (group membership, PowerManager/WaterManager
## registration). MUST be set before add_child() — _ready() fires
## synchronously during add_child() and reads this immediately. See
## docs/systems/build/README.md "Full-fidelity previews" for the full
## convention and why this exists (a previous version instantiated these
## same scripts with no guard and registered 3 real running generators
## into the live PowerManager the instant Build Mode opened).
var _is_preview_only: bool = false

# ─── Mesh refs ────────────────────────────────────────────────────────────────
var _strip_mat:   StandardMaterial3D = null
var _strip_mi:    MeshInstance3D     = null
var _led_mat:     StandardMaterial3D = null
var _strip_max_h: float              = 0.0

# ─── Interaction state ────────────────────────────────────────────────────────
var _player_nearby: bool = false

# Presentation is owned by scripts/ui/power/BatteryInspectUI.gd.
var _inspect_ui: CanvasLayer = null
var _inspect_refresh_queued: bool = false

func _ready() -> void:
	battery_tier = clamp(battery_tier, 0, 2)
	collision_layer = 5
	collision_mask  = 0
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("battery")
	_capacity_wh = float(TIER_CONFIG[battery_tier]["capacity_wh"])
	_charge_wh   = 0.0
	_build_mesh()
	if _is_preview_only:
		return
	set_process(true)
	_register_with_pm()


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _bat_id.is_empty():
		pm.unregister_battery(_bat_id)
	if not _wire_key.is_empty():
		pm.unregister_wire_node(_wire_key)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER REGISTRATION
# ══════════════════════════════════════════════════════════════════════════════

func _register_with_pm() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("BatteryBank: PowerManager not found")
		return
	_pm_id  = str(get_instance_id())
	_bat_id = _pm_id
	call_deferred("_register_deferred")


func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	_wire_key = pm.register_wire_node(global_position, "battery", _pm_id)
	pm.register_battery(_bat_id, _capacity_wh, self, 0.0)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

func set_charge_display(wh: float, cap: float) -> void:
	_charge_wh   = wh
	_capacity_wh = cap if cap > 0.0 else _capacity_wh
	_sync_strip()
	_sync_led()
	_request_inspect_refresh()


func set_battery_mode(charging: bool, discharging: bool) -> void:
	_charging    = charging
	_discharging = discharging
	_sync_led()
	_request_inspect_refresh()


func set_grid_connected(connected: bool) -> void:
	if connected == _grid_connected:
		return
	_grid_connected = connected
	_sync_led()
	_request_inspect_refresh()


## Save/Load (Jul 2026) — public read accessors for this battery's mutable
## runtime state. No setter counterpart needed here: restore goes through
## PowerManager.set_battery_charge()/set_battery_enabled() (same path the
## solver/info-panel already use), not a direct instance var write.
func get_charge_wh() -> float:
	return _charge_wh

func get_enabled() -> bool:
	return _enabled

## Called by the info panel toggle — routes through PM.
func set_enabled(on: bool) -> void:
	_enabled = on
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null and not _bat_id.is_empty():
		pm.set_battery_enabled(_bat_id, _enabled)
	_sync_led()
	_request_inspect_refresh()


# ══════════════════════════════════════════════════════════════════════════════
# INTERACTION
# ══════════════════════════════════════════════════════════════════════════════

func get_interact_prompt() -> String:
	var pct: int = _charge_pct()
	return "%s — %d%%  [E] Info" % [TIER_CONFIG[battery_tier]["label"], pct]


func on_interact() -> void:
	if is_instance_valid(_inspect_ui) and _inspect_ui.is_open():
		_close_panel()
	else:
		_open_panel()


func set_player_in_range(in_range: bool) -> void:
	_player_nearby = in_range
	if not in_range:
		_close_panel()


# ══════════════════════════════════════════════════════════════════════════════
# INFO PANEL
# ══════════════════════════════════════════════════════════════════════════════

func _open_panel() -> void:
	if not is_instance_valid(_inspect_ui):
		_inspect_ui = (load("res://scripts/ui/power/BatteryInspectUI.gd") as GDScript).new()
		add_child(_inspect_ui)
		_inspect_ui.enabled_requested.connect(set_enabled)
	_inspect_ui.open(self, String(TIER_CONFIG[battery_tier]["label"]), _inspect_snapshot())

func _close_panel() -> void:
	if is_instance_valid(_inspect_ui):
		_inspect_ui.close()

func _inspect_snapshot() -> Dictionary:
	return {"charge_wh": _charge_wh, "capacity_wh": _capacity_wh,
		"state": _state_string(), "connected": _grid_connected, "enabled": _enabled,
		# Explicit existing stub, retained for the planned battery-health system.
		"health": 100.0, "health_implemented": false}

func _request_inspect_refresh() -> void:
	if _inspect_refresh_queued or not is_instance_valid(_inspect_ui) or not _inspect_ui.is_open():
		return
	_inspect_refresh_queued = true
	_flush_inspect_refresh.call_deferred()

func _flush_inspect_refresh() -> void:
	_inspect_refresh_queued = false
	if is_instance_valid(_inspect_ui) and _inspect_ui.is_open():
		_inspect_ui.refresh(_inspect_snapshot())


# Meshes, LEDs, banners and simulation remain world-owned.
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


## Low-battery flicker — runs continuously but is a no-op above the
## threshold, so it only costs a percent check per frame in the common case.
## Never touches _sync_led()/_sync_strip()'s color logic, only the emission
## energy multiplier, so a normal/charging/idle battery looks identical to
## before this was added.
func _process(delta: float) -> void:
	if _capacity_wh <= 0.0:
		return
	var pct: float = clampf(_charge_wh / _capacity_wh, 0.0, 1.0)
	var flickering: bool = _enabled and _discharging and pct < LOW_BATTERY_FLICKER_THRESHOLD
	if not flickering:
		if _led_mat != null:
			_led_mat.emission_energy_multiplier = LED_BASE_ENERGY
		if _strip_mat != null:
			_strip_mat.emission_energy_multiplier = STRIP_BASE_ENERGY
		return
	_flicker_t += delta * 9.0
	## Irregular flicker (two sines at different rates) rather than a clean
	## pulse — reads as "failing" instead of "breathing".
	var flick: float = 0.6 + 0.4 * sin(_flicker_t) * sin(_flicker_t * 2.7)
	if _led_mat != null:
		_led_mat.emission_energy_multiplier = LED_BASE_ENERGY * flick
	if _strip_mat != null:
		_strip_mat.emission_energy_multiplier = STRIP_BASE_ENERGY * flick


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


## Side-effect-free ghost mesh for build-mode previews — matches
## GhostPreview.gd's inline TILE_BATTERY_S/M/L branch.
static func build_ghost_mesh(tier: int = 0) -> Mesh:
	const BAT_SIZES: Array = [
		Vector3(0.40, 0.70, 0.22),   ## Small
		Vector3(0.50, 0.90, 0.26),   ## Medium
		Vector3(0.60, 1.10, 0.28),   ## Large
	]
	var box: BoxMesh = BoxMesh.new()
	box.size = BAT_SIZES[clamp(tier, 0, 2)]
	return box
