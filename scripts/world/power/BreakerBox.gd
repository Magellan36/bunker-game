extends StaticBody3D
class_name BreakerBox
## BreakerBox.gd  — v2.0
## A circuit breaker placed on the wire graph.
##
## CHANGED in v2.0:
##   - E-key interaction NO LONGER trips/resets the breaker.
##   - Instead it opens a CanvasLayer settings panel with:
##       • Zone colour swatch (matching BuildModeController wire palette)
##       • "Allow battery power through" toggle
##       • "Allow generator power through" toggle
##       • Current state label (ONLINE / TRIPPED)
##   - Trip / reset can only be done from PowerTerminal (or PM code).
##   - set_tripped(bool) still works — PM calls it to update the LED.
##
## PowerManager integration:
##   _ready()     → register_wire_node() → register_breaker()
##   _exit_tree() → unregister_breaker() → unregister_wire_node()
##   set_tripped(bool)  — called by PM when trip state changes
##   on_interact()      — opens settings panel

# ─── Debug ────────────────────────────────────────────────────────────────────
## Set false to silence all [BreakerBox] placement/registration prints.
## Matches MainWorld.WIRE_DEBUG — flip both together.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Colours ──────────────────────────────────────────────────────────────────
const COLOR_BODY:    Color = Color(0.30, 0.30, 0.32, 1.0)
const COLOR_PANEL:   Color = Color(0.20, 0.20, 0.22, 1.0)
const COLOR_LED_ON:  Color = Color(0.10, 0.95, 0.25, 1.0)   ## green = ONLINE
const COLOR_LED_OFF: Color = Color(0.95, 0.18, 0.10, 1.0)   ## red   = TRIPPED

## Zone wire palette — must match BuildModeController._recolor_wire_zones() and PM.
## Index 0 = light blue (default/unbroken zone). Index 1–5 = coloured zones.
## SINGLE SOURCE OF TRUTH: the real palette lives in PowerManager.ZONE_COLORS.
## _palette_col() below pulls from PowerManager (alpha 0.60, matching the wire
## tubes).  This const is ONLY a fallback mirror if PM is unreachable — keep it
## identical to PM's RGB.
const ZONE_COLORS: Array[Color] = [
	Color(0.35, 0.80, 1.00, 0.60),   ## 0 light blue  (default zone)
	Color(0.10, 0.95, 0.35, 0.60),   ## 1 green
	Color(0.95, 0.18, 0.10, 0.60),   ## 2 red
	Color(0.95, 0.90, 0.10, 0.60),   ## 3 yellow
	Color(0.90, 0.10, 0.95, 0.60),   ## 4 magenta
	Color(0.95, 0.55, 0.10, 0.60),   ## 5 orange
]

## Zone palette colour at alpha 0.60, sourced from PowerManager.
## Falls back to the local ZONE_COLORS mirror only if PM is unreachable.
func _palette_col(color_index: int) -> Color:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		return pm.zone_color_at(color_index, 0.60)
	return ZONE_COLORS[color_index % ZONE_COLORS.size()]

# ─── Box dimensions ───────────────────────────────────────────────────────────
const BOX_SIZE: Vector3 = Vector3(0.36, 0.44, 0.14)

# ─── State ────────────────────────────────────────────────────────────────────
var _tripped:    bool   = false
var _pm_id:      String = ""
var _wire_key:   String = ""
var _breaker_id: String = ""
var _attachment_queued: bool = false
var _attachment_refreshing: bool = false
var _force_attachment_rebind: bool = false

## Pass-through flags — set by player via settings panel, sent to PM.
var _pass_battery:   bool = true
var _pass_generator: bool = true

## Zone indices on each side of this breaker (-1 = unassigned).
## A breaker borders up to two zones; we store both for display.
var _zone_index:  int = -1   ## primary (first found) — kept for compat
var _zone_index_b: int = -1  ## secondary zone on the other side

## Zone keys (stable identity, see ZoneCustomization.gd) + display names for
## each side, refreshed alongside _zone_index/_zone_index_b in
## _refresh_zone_index(). Used so this breaker's swatches/labels reflect a
## player's zone rename/recolor (done via that zone's Power Terminal)
## immediately, matching the world-wire tubes and the terminal UI.
var _zone_key:    String = ""
var _zone_key_b:  String = ""
var _zone_name:   String = ""
var _zone_name_b: String = ""

# ─── Mesh refs ────────────────────────────────────────────────────────────────
var _led_mat: StandardMaterial3D = null

# Presentation is owned by scripts/ui/power/BreakerInspectUI.gd.
var _inspect_ui: CanvasLayer = null
var _inspect_refresh_queued: bool = false

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


# ═════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("breaker")
	_build_mesh()
	if _is_preview_only:
		return
	_register_with_pm()


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _breaker_id.is_empty():
		pm.unregister_breaker(_breaker_id)
	if not _wire_key.is_empty():
		pm.unregister_wire_node(_wire_key)


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER REGISTRATION
# ══════════════════════════════════════════════════════════════════════════════

func _register_with_pm() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("BreakerBox: PowerManager not found")
		return
	_pm_id = str(get_instance_id())
	if not pm.wire_edge_registered.is_connected(_queue_attachment_refresh):
		pm.wire_edge_registered.connect(_queue_attachment_refresh)
	if not pm.wire_edge_unregistered.is_connected(_queue_attachment_refresh):
		pm.wire_edge_unregistered.connect(_queue_attachment_refresh)
	call_deferred("_register_wire_deferred")


func _register_wire_deferred() -> void:
	_queue_attachment_refresh("")


func _queue_attachment_refresh(_changed_edge_id: String) -> void:
	if _attachment_queued or _attachment_refreshing or not is_inside_tree():
		return
	_attachment_queued = true
	call_deferred("_refresh_breaker_attachment")


func refresh_power_attachment() -> void:
	_force_attachment_rebind = true
	_queue_attachment_refresh("")


func _has_live_cut_point(pm: PowerManager) -> bool:
	if _breaker_id.is_empty() or not pm._breakers.has(_breaker_id):
		return false
	var physical_sides: int = 0
	for edge: Dictionary in pm.get_wire_edges():
		if bool(edge.get("no_visual", false)):
			continue
		if edge.get("node_a", "") == _wire_key or edge.get("node_b", "") == _wire_key:
			physical_sides += 1
	return physical_sides >= 2


func _detach_from_grid(pm: PowerManager) -> void:
	if not _breaker_id.is_empty():
		pm.unregister_breaker(_breaker_id)
	if not _wire_key.is_empty():
		pm.unregister_wire_node(_wire_key)
	_breaker_id = ""
	_wire_key = ""


func _refresh_breaker_attachment() -> void:
	_attachment_queued = false
	if _attachment_refreshing or _pm_id.is_empty() or not is_inside_tree():
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	var force_rebind: bool = _force_attachment_rebind
	_force_attachment_rebind = false
	if not force_rebind and _has_live_cut_point(pm):
		return

	var candidate: Dictionary = WallWireAttachment.find_candidate(global_position, pm)
	if candidate.is_empty():
		if force_rebind:
			_attachment_refreshing = true
			pm.begin_bulk()
			_detach_from_grid(pm)
			pm.end_bulk()
			_attachment_refreshing = false
		return

	var cut_pos: Vector3 = candidate["pos"]
	var cut_key: String = pm._graph._snap_key(cut_pos)
	if not force_rebind and cut_key == _wire_key and not _breaker_id.is_empty():
		pm.resplit_breaker(_wire_key)
		return

	var restore_tripped: bool = _tripped
	_attachment_refreshing = true
	pm.begin_bulk()
	_detach_from_grid(pm)
	_wire_key = pm.register_wire_node(cut_pos, "breaker", _pm_id, true)
	_breaker_id = pm.register_breaker(_wire_key, self)
	if not _breaker_id.is_empty():
		pm.set_breaker_passthrough(_breaker_id, _pass_battery, _pass_generator)
		_apply_breaker_variant(pm)
		if restore_tripped:
			pm.trip_breaker(_breaker_id)
	pm.end_bulk()
	_attachment_refreshing = false


func _apply_breaker_variant(_pm: PowerManager) -> void:
	pass


func notify_wire_placed(_wn_key: String, _wn_pos: Vector3) -> void:
	_queue_attachment_refresh("")


# ══════════════════════════════════════════════════════════════════════════════
# POWERMANAGER INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

## Save/Load (Jul 2026) — public read accessors for this breaker's mutable
## state. Restore goes through PowerManager.trip_breaker()/
## set_breaker_passthrough() (same paths the settings panel/PM already use),
## not a direct instance var write.
func get_tripped() -> bool:
	return _tripped

func get_pass_battery() -> bool:
	return _pass_battery

func get_pass_generator() -> bool:
	return _pass_generator

## PM-assigned breaker id ("brk_<wire_node_key>") — needed by anything
## outside this node that wants to call PowerManager.trip_breaker()/
## set_breaker_passthrough() on THIS breaker specifically (e.g. save/load
## restore in BuildModeController). Empty until wire registration completes.
func get_breaker_id() -> String:
	return _breaker_id

## Called by PM when trip state changes (LED + banner update only).
func set_tripped(on: bool) -> void:
	var was_tripped: bool = _tripped
	_tripped = on
	_sync_led()
	## One-shot spark burst, only on the false→true transition (not on
	## resets, and not re-triggered by redundant same-state calls).
	## Purely cosmetic — doesn't touch any trip/reset logic above.
	if on and not was_tripped:
		_spawn_trip_sparks()
	## If settings panel is open, refresh it.
	_request_inspect_refresh()


## Graphics plan Section 4 VFX priority #4 — one-shot spark burst at the LED
## when this breaker trips. Self-contained GPUParticles3D, frees itself via
## the `finished` signal once the (short, one_shot) burst completes.
func _spawn_trip_sparks() -> void:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount        = 14
	p.lifetime      = 0.5
	p.one_shot      = true
	p.explosiveness = 0.9
	p.local_coords  = true
	p.position      = Vector3(0.0, BOX_SIZE.y * 0.5 + BOX_SIZE.y * 0.15, BOX_SIZE.z * 0.5 + 0.05)

	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.02, 0.02)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/vfx/soft_glow_dot.png")
	mat.albedo_color   = Color(1.0, 0.85, 0.3, 1.0)
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode     = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	p.draw_pass_1 = mesh

	var pmat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pmat.direction            = Vector3(0.0, 1.0, 0.0)
	pmat.spread               = 60.0
	pmat.initial_velocity_min = 0.6
	pmat.initial_velocity_max = 1.6
	pmat.gravity              = Vector3(0.0, -3.0, 0.0)
	pmat.scale_min            = 0.5
	pmat.scale_max            = 1.0
	p.process_material = pmat

	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# ══════════════════════════════════════════════════════════════════════════════
# INTERACTION SYSTEM INTERFACE
# ══════════════════════════════════════════════════════════════════════════════

func get_interact_prompt() -> String:
	return "Breaker Settings [E]"


func on_interact() -> void:
	## Refresh zone index from PM before opening.
	_refresh_zone_index()
	_open_settings()


func set_player_in_range(in_range: bool) -> void:
	## Close settings panel when player walks away.
	if not in_range:
		_close_settings()


# ══════════════════════════════════════════════════════════════════════════════
# SETTINGS PANEL
# ══════════════════════════════════════════════════════════════════════════════

func _open_settings() -> void:
	if is_instance_valid(_inspect_ui) and _inspect_ui.is_open():
		_close_settings()
		return
	if not is_instance_valid(_inspect_ui):
		_inspect_ui = (load("res://scripts/ui/power/BreakerInspectUI.gd") as GDScript).new()
		add_child(_inspect_ui)
		_inspect_ui.battery_passthrough_requested.connect(_on_battery_passthrough)
		_inspect_ui.generator_passthrough_requested.connect(_on_generator_passthrough)
		_inspect_ui.restart_requested.connect(_on_inspect_restart)
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if pm != null:
			pm.draw_changed.connect(_on_inspector_draw_changed)
			pm.zone_name_changed.connect(_on_inspector_zone_changed)
			pm.zone_color_changed.connect(_on_inspector_zone_changed)
	var title: String = "Smart breaker" if self is UpgradedBreakerBox else "Breaker"
	_inspect_ui.open(self, title, _inspect_snapshot())

func _close_settings() -> void:
	if is_instance_valid(_inspect_ui):
		_inspect_ui.close()

func _inspect_snapshot() -> Dictionary:
	_refresh_zone_index()
	# A smart-breaker self-trip/reset changes the manager's sharing flags;
	# set_tripped() only updates the device's trip flag. Read authoritative
	# values instead of presenting stale local toggle preferences.
	var state: Dictionary = {"tripped": _tripped, "pass_battery": _pass_battery,
		"pass_generator": _pass_generator}
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		for breaker: Dictionary in pm.get_breakers():
			if String(breaker.get("id", "")) == _breaker_id:
				state["tripped"] = bool(breaker.get("tripped", _tripped))
				state["pass_battery"] = bool(breaker.get("pass_battery", _pass_battery))
				state["pass_generator"] = bool(breaker.get("pass_generator", _pass_generator))
				break
	var zones: Array[Dictionary] = []
	if _zone_index >= 0:
		zones.append({"name": _zone_name if not _zone_name.is_empty() else "Z%d" % _zone_index, "color": _zone_color()})
	if _zone_index_b >= 0:
		zones.append({"name": _zone_name_b if not _zone_name_b.is_empty() else "Z%d" % _zone_index_b, "color": _zone_color_b()})
	state["zones"] = zones
	return state

func _on_battery_passthrough(enabled: bool) -> void:
	var state: Dictionary = _inspect_snapshot()
	if bool(state["tripped"]):
		return
	_pass_battery = enabled
	_pass_generator = bool(state["pass_generator"])
	_send_passthrough_to_pm()
	_request_inspect_refresh()

func _on_generator_passthrough(enabled: bool) -> void:
	var state: Dictionary = _inspect_snapshot()
	if bool(state["tripped"]):
		return
	_pass_generator = enabled
	_pass_battery = bool(state["pass_battery"])
	_send_passthrough_to_pm()
	_request_inspect_refresh()

func _on_inspect_restart() -> void:
	if _tripped:
		_request_restart()

func _request_inspect_refresh() -> void:
	if _inspect_refresh_queued or not is_instance_valid(_inspect_ui) or not _inspect_ui.is_open():
		return
	_inspect_refresh_queued = true
	_flush_inspect_refresh.call_deferred()

func _flush_inspect_refresh() -> void:
	_inspect_refresh_queued = false
	if is_instance_valid(_inspect_ui) and _inspect_ui.is_open():
		_inspect_ui.refresh(_inspect_snapshot())

func _on_inspector_draw_changed(_draw: float, _capacity: float, _battery: float) -> void:
	_request_inspect_refresh()

func _on_inspector_zone_changed(_key: String) -> void:
	_request_inspect_refresh()


## Player requested RESTART while tripped. PowerManager owns all reset policy:
## a standard reset preserves sharing settings; an upgraded self-trip group
## reset restores the group's pre-trip sharing intent. The solver may re-trip
## an unhealthy group. The UI must not override any of these results.
##
## Job Progress Bar (Aug 2026) — pressing RESTART now closes the settings
## panel immediately and starts a timed job at the player's position
## instead of resetting the breaker on the spot; the actual
## pm.reset_breaker() call is deferred to the job's completion. Falls back
## to the old instant reset if InteractionSystem can't be resolved.
func _request_restart() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or _breaker_id.is_empty():
		return
	_close_settings()
	## Real Burn trigger (Aug 2026) — "resetting a hazardous breaker...
	## carries a bounded burn chance, scaled visibly by the actual hazard
	## state involved," per docs/systems/medical/README.md. Captured BEFORE
	## the reset actually runs, so the chance reflects the hazard the player
	## was reaching into (this breaker was tripped, by definition — this
	## method is only ever called while _tripped), not the post-fix state.
	var grid_state_at_reset: String = pm.get_grid_state_string()
	var isys: Node = _resolve_interaction_system()
	if isys == null or not isys.has_method("start_job"):
		_finish_restart(pm, grid_state_at_reset)
		return
	isys.start_job(self, InteractionSystem.JOB_DEFAULT_DURATION,
		Callable(self, "_finish_restart").bind(pm, grid_state_at_reset), "Resetting Breaker...")

## Split from _request_restart() so both the job-completion path and the
## no-InteractionSystem fallback share exactly one place that actually
## resets the breaker and rolls the Burn chance.
func _finish_restart(pm: PowerManager, grid_state_at_reset: String) -> void:
	pm.reset_breaker(_breaker_id)
	var player_medical: PlayerMedical = get_tree().get_first_node_in_group("player_medical") as PlayerMedical
	if player_medical != null:
		player_medical.roll_electrical_burn(grid_state_at_reset)

func _resolve_interaction_system() -> Node:
	var plr: Node = get_tree().get_first_node_in_group("player")
	if plr != null and "interaction_system" in plr:
		return plr.interaction_system
	return null


func _send_passthrough_to_pm() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null and not _breaker_id.is_empty():
		pm.set_breaker_passthrough(_breaker_id, _pass_battery, _pass_generator)


## Query PM for the wire zone index of this breaker's snap key.
func _refresh_zone_index() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		_zone_index   = -1
		_zone_index_b = -1
		_zone_key     = ""
		_zone_key_b   = ""
		_zone_name    = ""
		_zone_name_b  = ""
		return
	var zones: Array = pm.get_zone_snapshot()
	_zone_index   = -1
	_zone_index_b = -1
	_zone_key     = ""
	_zone_key_b   = ""
	_zone_name    = ""
	_zone_name_b  = ""
	## Collect up to two zone dicts that list this breaker's wire key
	## in their breaker_keys array (one zone per side of the breaker).
	var found: Array[Dictionary] = []
	for zd: Dictionary in zones:
		var brk_keys: Array = zd.get("breaker_keys", [])
		for bk: String in brk_keys:
			if bk == _wire_key:
				found.append(zd)
				break   ## One match per zone is enough.
	if found.size() >= 1:
		_zone_index = int(found[0].get("zone_index", 0))
		_zone_key   = String(found[0].get("zone_key", ""))
		_zone_name  = String(found[0].get("zone_name", "Z%d" % _zone_index))
	if found.size() >= 2:
		_zone_index_b = int(found[1].get("zone_index", 0))
		_zone_key_b   = String(found[1].get("zone_key", ""))
		_zone_name_b  = String(found[1].get("zone_name", "Z%d" % _zone_index_b))


func _zone_color() -> Color:
	if _zone_index < 0:
		return Color(0.50, 0.50, 0.50, 0.60)   ## grey = unassigned
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		return pm.zone_display_color(_zone_key, _zone_index, 0.60)
	return _palette_col(_zone_index)

func _zone_color_b() -> Color:
	if _zone_index_b < 0:
		return Color(0.50, 0.50, 0.50, 0.60)
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		return pm.zone_display_color(_zone_key_b, _zone_index_b, 0.60)
	return _palette_col(_zone_index_b)


# ══════════════════════════════════════════════════════════════════════════════
# MESH BUILD
# ══════════════════════════════════════════════════════════════════════════════

func _build_mesh() -> void:
	## ── Main body ─────────────────────────────────────────────────────────────
	var body_mi:   MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh        = BoxMesh.new()
	body_mesh.size = BOX_SIZE
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.80
	body_mat.metallic     = 0.50
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)
	body_mi.create_trimesh_collision()
	for child: Node in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## ── Front control panel ───────────────────────────────────────────────────
	var panel_mi:   MeshInstance3D = MeshInstance3D.new()
	var panel_mesh: BoxMesh        = BoxMesh.new()
	panel_mesh.size  = Vector3(BOX_SIZE.x * 0.80, BOX_SIZE.y * 0.60, 0.03)
	panel_mi.mesh    = panel_mesh
	panel_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, BOX_SIZE.z * 0.5 + 0.015)
	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = COLOR_PANEL
	panel_mat.roughness    = 0.70
	panel_mi.set_surface_override_material(0, panel_mat)
	add_child(panel_mi)

	## ── LED indicator ─────────────────────────────────────────────────────────
	var led_mi:   MeshInstance3D = MeshInstance3D.new()
	var led_mesh: BoxMesh        = BoxMesh.new()
	led_mesh.size  = Vector3(0.06, 0.06, 0.03)
	led_mi.mesh    = led_mesh
	led_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5 + BOX_SIZE.y * 0.15, BOX_SIZE.z * 0.5 + 0.035)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color              = COLOR_LED_ON
	_led_mat.emission_enabled          = true
	_led_mat.emission                  = COLOR_LED_ON
	_led_mat.emission_energy_multiplier = 2.0
	led_mi.set_surface_override_material(0, _led_mat)
	add_child(led_mi)

	## ── Breaker lever ─────────────────────────────────────────────────────────
	var lever_mi:   MeshInstance3D = MeshInstance3D.new()
	var lever_mesh: BoxMesh        = BoxMesh.new()
	lever_mesh.size  = Vector3(0.055, 0.13, 0.025)
	lever_mi.mesh    = lever_mesh
	lever_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5 - BOX_SIZE.y * 0.10, BOX_SIZE.z * 0.5 + 0.040)
	var lever_mat: StandardMaterial3D = StandardMaterial3D.new()
	lever_mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)
	lever_mat.roughness    = 0.60
	lever_mi.set_surface_override_material(0, lever_mat)
	add_child(lever_mi)


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL SYNC
# ══════════════════════════════════════════════════════════════════════════════

func _sync_led() -> void:
	if _led_mat == null:
		return
	var col: Color = COLOR_LED_OFF if _tripped else COLOR_LED_ON
	_led_mat.albedo_color = col
	_led_mat.emission     = col
