extends StaticBody3D
class_name GeneratorObject
## GeneratorObject.gd
## Procedural generator mesh (gray box). Sized by tier.
## Registers itself with PowerManager on _ready, unregisters on _exit_tree.
## Tier 0 = Small (1×1, 800W), Tier 1 = Med (1×2, 2000W), Tier 2 = Large (2×2, 5000W).
## Fuel banner: shows "XX% FUEL" above the generator when player is nearby.
## Wire socket: small emissive sphere at the wire connection point on the side face.
## Interaction (E key): opens GeneratorInspectUI panel with fuel bar, HP, backup toggle, grid state.

# ─── Debug ────────────────────────────────────────────────────────────────────
## Flip false to silence all [GEN] registration/ready prints.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Tier config ──────────────────────────────────────────────────────────────
const TIER_CONFIG: Array = [
	{ "size": Vector3(0.85, 0.85, 0.85), "watts": 800,  "label": "Generator S" },
	{ "size": Vector3(0.85, 0.85, 1.85), "watts": 2000, "label": "Generator M" },
	{ "size": Vector3(1.85, 0.85, 1.85), "watts": 5000, "label": "Generator L" },
]

const COLOR_BODY:     Color = Color(0.38, 0.38, 0.38, 1.0)
const COLOR_PANEL:    Color = Color(0.25, 0.25, 0.28, 1.0)
const COLOR_RUNNING:  Color = Color(0.15, 0.90, 0.20, 1.0)
const COLOR_STOPPED:  Color = Color(0.85, 0.18, 0.12, 1.0)

## Wire socket — small emissive sphere on the generator side face (−Z face).
## Indicates where a wire should be connected. Cyan when running, dim when off.
## SOCKET_RADIUS / SOCKET_COLOR_ON / SOCKET_COLOR_OFF removed with back-face socket mesh.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var generator_tier: int = 0

# ─── Internal refs ────────────────────────────────────────────────────────────
var _indicator_mi:  MeshInstance3D     = null
var _indicator_mat: StandardMaterial3D = null

var _is_running:    bool               = false
var _is_backup:     bool               = false
var _pm_id:         String             = ""
var _wire_key:      String             = ""

var _pm_retry_count: int = 0

var _inspect_ui: Node = null

var _grid_tripped: bool = false

# ─── Fuel banner ──────────────────────────────────────────────────────────────
const BANNER_HEIGHT_ABOVE: float = 0.45
var _fuel_banner:     Label3D = null
var _fuel_level:      float   = 100.0
var _player_in_range: bool    = false

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_wdbg("[GEN] _ready fired — tier=%d instance_id=%d" % [generator_tier, get_instance_id()])
	generator_tier = clamp(generator_tier, 0, 2)
	collision_layer = 5
	collision_mask  = 0
	add_to_group("generator")
	add_to_group("interactable")
	_build_mesh()
	_build_fuel_banner()
	## Defer registration one frame so PowerManager is guaranteed to be in its group.
	call_deferred("_register_with_pm")

# ─── Fuel banner ──────────────────────────────────────────────────────────────
func _build_fuel_banner() -> void:
	var sz: Vector3 = TIER_CONFIG[generator_tier]["size"]
	var lbl: Label3D = Label3D.new()
	lbl.text          = "100% FUEL"
	lbl.font_size     = 52
	lbl.pixel_size    = 0.0018
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate      = Color(0.90, 0.95, 0.90, 1.0)
	lbl.position      = Vector3(0.0, sz.y + BANNER_HEIGHT_ABOVE + 0.10, 0.0)
	lbl.visible       = false
	add_child(lbl)
	_fuel_banner = lbl

func _refresh_fuel_banner() -> void:
	if _fuel_banner == null:
		return
	var pct: int = int(clampf(_fuel_level, 0.0, 100.0))
	_fuel_banner.text = "%d%% FUEL" % pct
	if pct >= 50:
		_fuel_banner.modulate = Color(0.50, 1.00, 0.55, 1.0)
	elif pct >= 20:
		_fuel_banner.modulate = Color(1.00, 0.75, 0.15, 1.0)
	else:
		_fuel_banner.modulate = Color(1.00, 0.25, 0.15, 1.0)

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range
	if _fuel_banner != null:
		_fuel_banner.visible = in_range
	if in_range and _fuel_banner != null:
		_refresh_fuel_banner()

# ─── Build mesh ───────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	var cfg: Dictionary = TIER_CONFIG[generator_tier]
	var sz: Vector3 = cfg["size"]

	## Body
	var body_mi:   MeshInstance3D  = MeshInstance3D.new()
	var body_mesh: BoxMesh         = BoxMesh.new()
	body_mesh.size = sz
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, sz.y * 0.5, 0.0)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.85
	body_mat.metallic     = 0.40
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)

	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Front control panel
	var panel_mi:   MeshInstance3D = MeshInstance3D.new()
	var panel_mesh: BoxMesh        = BoxMesh.new()
	var pw: float = sz.x * 0.70
	var ph: float = sz.y * 0.55
	panel_mesh.size  = Vector3(pw, ph, 0.04)
	panel_mi.mesh    = panel_mesh
	panel_mi.position = Vector3(0.0, sz.y * 0.5, sz.z * 0.5 + 0.02)

	var panel_mat: StandardMaterial3D = StandardMaterial3D.new()
	panel_mat.albedo_color = COLOR_PANEL
	panel_mat.roughness    = 0.70
	panel_mi.set_surface_override_material(0, panel_mat)
	add_child(panel_mi)

	## Status indicator LED
	_indicator_mi = MeshInstance3D.new()
	var ind_mesh: BoxMesh = BoxMesh.new()
	ind_mesh.size        = Vector3(0.09, 0.09, 0.04)
	_indicator_mi.mesh   = ind_mesh
	_indicator_mi.position = Vector3(pw * 0.30, sz.y * 0.5 + ph * 0.22, sz.z * 0.5 + 0.04)

	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.albedo_color              = COLOR_STOPPED
	_indicator_mat.emission_enabled          = true
	_indicator_mat.emission                  = COLOR_STOPPED
	_indicator_mat.emission_energy_multiplier = 1.5
	_indicator_mi.set_surface_override_material(0, _indicator_mat)
	add_child(_indicator_mi)

	## Wire socket sphere removed — wire node is at the generator centre (global_position).
	## The centre snap dot shown in Build Mode is sufficient; the back-face sphere
	## was a duplicate connection point that confused placement.


## _build_wire_socket removed — back-face socket sphere was a duplicate snap point.
## Wire node is registered at global_position (generator centre). _sync_socket
## is a no-op kept for call-site compatibility.
func _sync_socket() -> void:
	pass   ## socket mesh removed; nothing to sync


# ─── PowerManager registration ────────────────────────────────────────────────
const _PM_MAX_RETRIES: int = 5

func _register_with_pm() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	_wdbg("[GEN] _register_with_pm attempt=%d — pm_found=%s instance_id=%d" % [
		_pm_retry_count, str(pm != null), get_instance_id()])
	if pm == null:
		_pm_retry_count += 1
		if _pm_retry_count < _PM_MAX_RETRIES:
			push_warning("GeneratorObject: PowerManager not found, retry %d/%d next frame" % [
				_pm_retry_count, _PM_MAX_RETRIES])
			call_deferred("_register_with_pm")
		else:
			push_error("GeneratorObject: PowerManager not found after %d retries — generator will not produce power" % _PM_MAX_RETRIES)
		return
	_pm_id = str(get_instance_id())
	var cfg: Dictionary = TIER_CONFIG[generator_tier]
	_wdbg("[GEN] calling register_generator id=%s watts=%.0f" % [_pm_id, cfg["watts"]])
	pm.register_generator(_pm_id, cfg["watts"], self, false, 100.0, 100.0)
	pm.set_generator_running(_pm_id, true)
	_is_running = true
	_sync_indicator()
	_sync_socket()
	if pm.has_signal("generator_fuel_low") and not pm.generator_fuel_low.is_connected(_on_fuel_low):
		pm.generator_fuel_low.connect(_on_fuel_low)
	if pm.has_signal("grid_tripped") and not pm.grid_tripped.is_connected(_on_pm_grid_tripped):
		pm.grid_tripped.connect(_on_pm_grid_tripped)
	if pm.has_signal("grid_restored") and not pm.grid_restored.is_connected(_on_pm_grid_restored):
		pm.grid_restored.connect(_on_pm_grid_restored)
	call_deferred("_register_wire_deferred")

func _register_wire_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	_wdbg("[GEN] _register_wire_deferred — pm_found=%s pm_id='%s' gpos=%s" % [
		str(pm != null), _pm_id, str(global_position)])
	if pm == null or _pm_id.is_empty():
		push_warning("GeneratorObject: _register_wire_deferred skipped — pm=%s pm_id='%s'" % [
			str(pm != null), _pm_id])
		return
	## Pass Y=1.0 explicitly so the snap key lands on the canonical wire-grid
	## plane, matching perimeter nodes.  PowerManager also normalises this, but
	## being explicit here keeps stored world position correct too.
	var wire_pos: Vector3 = Vector3(global_position.x, 1.0, global_position.z)
	_wire_key = pm.register_wire_node(wire_pos, "generator", _pm_id)
	_wdbg("[GEN] wire node registered: key=%s" % _wire_key)
	## Generators must be manually wired — no auto-connect.


func _on_fuel_low(gen_id: String, fuel_pct: float) -> void:
	if gen_id != _pm_id:
		return
	_fuel_level = fuel_pct
	if _player_in_range and _fuel_banner != null:
		_refresh_fuel_banner()


func _on_pm_grid_tripped() -> void:
	_grid_tripped = true
	_is_running   = false
	_sync_indicator()
	_sync_socket()
	if _inspect_ui != null and is_instance_valid(_inspect_ui) \
			and _inspect_ui.has_method("refresh"):
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		var health: float = 100.0
		if pm != null:
			health = pm.get_generator_health(_pm_id)
		var gs: String = "TRIPPED"
		if pm != null:
			gs = pm.get_grid_state_string()
		_inspect_ui.call("refresh", _fuel_level, health, _is_backup, false, true, gs)


func _on_pm_grid_restored() -> void:
	_grid_tripped = false
	if _inspect_ui != null and is_instance_valid(_inspect_ui) \
			and _inspect_ui.has_method("refresh"):
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		var health: float = 100.0
		if pm != null:
			health = pm.get_generator_health(_pm_id)
		var gs: String = "ONLINE"
		if pm != null:
			gs = pm.get_grid_state_string()
		_inspect_ui.call("refresh", _fuel_level, health, _is_backup, _is_running, false, gs)


func on_grid_tripped() -> void:
	_on_pm_grid_tripped()


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or _pm_id.is_empty():
		return
	## Wire node MUST be unregistered before generator to avoid dangling edges.
	if not _wire_key.is_empty():
		pm.unregister_wire_node(_wire_key)
	pm.unregister_generator(_pm_id)

# ─── Public API — called by PowerManager ──────────────────────────────────────
func set_powered(_on: bool) -> void:
	pass

func set_running(on: bool) -> void:
	_is_running = on
	_sync_indicator()
	_sync_socket()

func set_fuel(level: float) -> void:
	_fuel_level = clampf(level, 0.0, 100.0)
	if _fuel_banner != null:
		_refresh_fuel_banner()

# ─── Interaction prompt ───────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	var fuel_pct: int = int(clampf(_fuel_level, 0.0, 100.0))
	var state_str: String
	if _is_backup:
		state_str = "Backup — Standby" if not _is_running else "Backup — Active"
	else:
		state_str = "Running" if _is_running else "Stopped"
	return "[E] %s  %d%% fuel  [%s]" % [_get_display_name(), fuel_pct, state_str]

func _get_display_name() -> String:
	var base: String = TIER_CONFIG[generator_tier].get("label", "Generator")
	return ("Backup " + base) if _is_backup else base

# ─── Interaction ──────────────────────────────────────────────────────────────
func on_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _inspect_ui == null or not is_instance_valid(_inspect_ui):
		var ui_script: GDScript = load("res://scripts/ui/GeneratorInspectUI.gd")
		if ui_script == null:
			push_warning("GeneratorObject: GeneratorInspectUI.gd not found")
			return
		_inspect_ui = CanvasLayer.new()
		_inspect_ui.set_script(ui_script)
		_inspect_ui.name = "GeneratorInspectUI"
		get_tree().get_root().add_child(_inspect_ui)
		if _inspect_ui.has_signal("closed"):
			_inspect_ui.closed.connect(_on_inspect_closed)
		if _inspect_ui.has_signal("backup_toggled"):
			_inspect_ui.backup_toggled.connect(_on_backup_toggled)
		if _inspect_ui.has_signal("power_toggled"):
			_inspect_ui.power_toggled.connect(_on_power_toggled)

	if _inspect_ui.has_method("open"):
		var pm:        PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		var fuel:      float = _fuel_level
		var health:    float = 100.0
		var is_backup: bool  = _is_backup
		var gs:        String = "ONLINE"
		if pm != null and not _pm_id.is_empty():
			fuel      = pm.get_generator_fuel(_pm_id)
			health    = pm.get_generator_health(_pm_id)
			is_backup = pm.get_generator_is_backup(_pm_id)
			gs        = pm.get_grid_state_string()
		_inspect_ui.call("open", _get_display_name(),
			TIER_CONFIG[generator_tier].get("watts", 0),
			fuel, health, is_backup, _is_running, _grid_tripped, gs)


func _on_inspect_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false


func _on_backup_toggled(enabled: bool) -> void:
	_is_backup = enabled
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null and not _pm_id.is_empty():
		pm.set_generator_backup(_pm_id, enabled)
	if pm != null:
		_is_running = pm.get_generator_running(_pm_id)
	_sync_indicator()
	_sync_socket()
	_refresh_inspect_ui()
	if _player_in_range and _fuel_banner != null:
		_refresh_fuel_banner()


func _on_power_toggled(desired_running: bool) -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or _pm_id.is_empty():
		return

	## When the grid is TRIPPED and the player wants to start this generator,
	## reset the main breaker first (clears the trip). This is the manual
	## per-generator restart flow — player presses Start on each generator
	## individually to bring the grid back up.
	if desired_running and _grid_tripped:
		pm.reset_main_breaker()
		_grid_tripped = false   ## cleared locally; PM emits grid_restored for UI

	pm.set_generator_running(_pm_id, desired_running)
	_is_running = pm.get_generator_running(_pm_id)
	_sync_indicator()
	_sync_socket()
	_refresh_inspect_ui()
	if _player_in_range and _fuel_banner != null:
		_refresh_fuel_banner()


func _refresh_inspect_ui() -> void:
	if _inspect_ui == null or not is_instance_valid(_inspect_ui):
		return
	if not _inspect_ui.has_method("refresh"):
		return
	var pm:     PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var health: float = 100.0
	var gs:     String = "ONLINE"
	if pm != null:
		health = pm.get_generator_health(_pm_id)
		gs     = pm.get_grid_state_string()
	_inspect_ui.call("refresh", _fuel_level, health, _is_backup, _is_running, _grid_tripped, gs)


func _sync_indicator() -> void:
	if _indicator_mat == null:
		return
	var col: Color = COLOR_RUNNING if _is_running else COLOR_STOPPED
	_indicator_mat.albedo_color = col
	_indicator_mat.emission     = col


func _get_main_world() -> Node:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			return child
	return null


func _get_interaction_system() -> Node:
	var main_world: Node = _get_main_world()
	if main_world == null:
		return null
	for child: Node in main_world.get_children():
		if child is CharacterBody3D:
			for sub: Node in child.get_children():
				if sub.get_script() != null:
					var path: String = str(sub.get_script().resource_path)
					if path.contains("InteractionSystem"):
						return sub
	return null
