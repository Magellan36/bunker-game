extends StaticBody3D
class_name FarmPlant
## FarmPlant.gd
## ─────────────────────────────────────────────────────────────────────────────
## Per-cell plant instance (Farming System plan §5.4/§6/§7). Spawned by
## FarmingTray.plant_seed() as a sibling-positioned child above its cell,
## freed on harvest or death.
##
## Ticks once per in-game hour (accumulator scaled by PlayerStats'
## _seconds_per_game_hour, same "compressed clock" conversion WaterHookup's
## quality decay / WaterPurifier's filter depletion already use).
##
## Growth formula (plan §6.1):
##   light_speed     = 0 / 0.5 / 1.0, read live from the nearest powered
##                      GrowLight directly above this cell (pure XZ match,
##                      recomputed once per hour tick — not every frame).
##   water_fraction   = tray.get_water_fraction() — tray's demand actually met.
##   growth_per_hour  = light_speed * water_fraction / (grow_days * 24.0)
##
## Health formula (plan §6.3): -5%/hr whenever water_fraction == 0.0, and an
## independent -5%/hr once unlit for more than 24 consecutive hours. Both can
## apply the same hour. At 0% health the plant dies — no harvest, seed wasted,
## tray cell reverts to soil-filled/empty (confirmed with Brannon).
##
## Health does NOT gate readiness — a plant can show READY at low health
## (plan's explicit two-independent-readouts design).

signal died()
signal harvested()

const PLANT_FULL_HEIGHT: float = 0.85   ## Matches GeneratorObject.TIER_CONFIG size.y
const LIGHT_MATCH_RADIUS: float = 0.55  ## "Directly above this cell" XZ tolerance

## Health penalty rates (plan §6.3).
const HEALTH_LOSS_NO_WATER_PER_HOUR: float = 5.0
const HEALTH_LOSS_NO_LIGHT_PER_HOUR: float = 5.0
const NO_LIGHT_GRACE_HOURS: int = 24

const SPIKE_BASE_RADIUS: float = 0.05
const SPIKE_TIP_RADIUS:  float = 0.015
const SPIKE_COLOR: Color = Color(0.22, 0.62, 0.20, 1.0)

@export var plant_type: String = "tomato"   ## "tomato" or "onion"

var progress: float = 0.0   ## 0.0 .. 1.0
var health:   float = 100.0 ## 0.0 .. 100.0

var _tray: FarmingTray = null
var _cell_index: int   = -1

var _hours_without_light: int = 0
var _light_speed_cached:  float = 0.0

var _hour_accum: float = 0.0
var _player_stats: Node = null

var _mesh_instance: MeshInstance3D = null
var _info_ui: CanvasLayer = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("farm_plant")
	_build_mesh()
	_refresh_visual()

func _exit_tree() -> void:
	if _info_ui != null and is_instance_valid(_info_ui):
		_info_ui.queue_free()
		_info_ui = null

## Called once by FarmingTray right after instancing, before add_child().
func setup(tray: FarmingTray, cell_index: int, type: String) -> void:
	_tray = tray
	_cell_index = cell_index
	plant_type = type
	progress = 0.0
	health   = 100.0

func _process(delta: float) -> void:
	if _tray == null or not is_instance_valid(_tray):
		queue_free()
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	var sec_per_hour: float = 3600.0   ## real-hour fallback if PlayerStats isn't found yet
	if _player_stats != null and _player_stats._seconds_per_game_hour > 0.0:
		sec_per_hour = _player_stats._seconds_per_game_hour

	_hour_accum += delta
	var safety: int = 0   ## guards against a huge delta (e.g. time-warp) looping forever
	while _hour_accum >= sec_per_hour and safety < 48:
		_hour_accum -= sec_per_hour
		_tick_one_game_hour()
		safety += 1
		if not is_instance_valid(self):
			return   ## died mid-loop

func _tick_one_game_hour() -> void:
	_light_speed_cached = _compute_light_speed()
	var water_fraction: float = _tray.get_water_fraction() if _tray != null and is_instance_valid(_tray) else 0.0
	var grow_days: float = PlantDatabase.get_grow_days(plant_type)

	var growth_per_hour: float = _light_speed_cached * water_fraction / (grow_days * 24.0)
	progress = clampf(progress + growth_per_hour, 0.0, 1.0)

	if water_fraction == 0.0:
		health = maxf(0.0, health - HEALTH_LOSS_NO_WATER_PER_HOUR)

	if _light_speed_cached == 0.0:
		_hours_without_light += 1
	else:
		_hours_without_light = 0

	if _hours_without_light > NO_LIGHT_GRACE_HOURS:
		health = maxf(0.0, health - HEALTH_LOSS_NO_LIGHT_PER_HOUR)

	_refresh_visual()

	if health <= 0.0:
		_die()

## Pure XZ position match against every powered grow light in the world —
## no parent/child relationship or registration handshake (plan §4).
func _compute_light_speed() -> float:
	var best: float = 0.0
	for node: Node in get_tree().get_nodes_in_group("grow_light"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var n3: Node3D = node as Node3D
		var dx: float = n3.global_position.x - global_position.x
		var dz: float = n3.global_position.z - global_position.z
		if sqrt(dx * dx + dz * dz) <= LIGHT_MATCH_RADIUS:
			if node.has_method("get_active_growth_speed"):
				best = maxf(best, float(node.call("get_active_growth_speed")))
	return best

func is_ready() -> bool:
	return progress >= 1.0

# ─── Visual ───────────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = SPIKE_COLOR
	mat.roughness    = 0.85
	_mesh_instance.set_surface_override_material(0, mat)
	add_child(_mesh_instance)

func _refresh_visual() -> void:
	if _mesh_instance == null:
		return
	var height: float = progress * PLANT_FULL_HEIGHT
	if height <= 0.001:
		_mesh_instance.visible = false
		return
	_mesh_instance.visible = true
	var cyl: CylinderMesh = _mesh_instance.mesh as CylinderMesh
	if cyl == null:
		cyl = CylinderMesh.new()
		cyl.radial_segments = 8
		_mesh_instance.mesh = cyl
	cyl.height       = height
	cyl.bottom_radius = SPIKE_BASE_RADIUS
	cyl.top_radius    = SPIKE_TIP_RADIUS
	## Root fixed at the top of the tray's soil layer (local Y=0); cylinder
	## is centred by default, so offset up by half its live height.
	_mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)

# ─── Harvest / Death ──────────────────────────────────────────────────────────
## Called by InteractionSystem via on_interact() when is_ready() — harvests
## immediately, no menu step (plan §5.4, confirmed with Brannon).
func harvest() -> void:
	if not is_ready():
		return
	FarmProduceItem.spawn_at(get_parent(), global_position, plant_type)
	FarmProduceItem.spawn_at(get_parent(), global_position, plant_type)
	harvested.emit()
	_clear_cell_and_free()

func _die() -> void:
	died.emit()
	_clear_cell_and_free()

func _clear_cell_and_free() -> void:
	if _tray != null and is_instance_valid(_tray):
		_tray.clear_cell(_cell_index)
	queue_free()

# ─── Interaction ──────────────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	if is_ready():
		return "[E] Harvest  %s" % PlantDatabase.get_display_name(plant_type)
	return "[E] Inspect  %s" % PlantDatabase.get_display_name(plant_type)

## Harvest takes priority the instant it's available — info-only otherwise
## (plan §5.4's explicit resolution of the one real ambiguity in the ask).
func on_interact() -> void:
	if is_ready():
		harvest()
		return

	if _info_ui == null or not is_instance_valid(_info_ui):
		var ui_script: GDScript = load("res://scripts/ui/farming/PlantInfoUI.gd")
		if ui_script == null:
			push_warning("FarmPlant: PlantInfoUI.gd not found")
			return
		_info_ui = CanvasLayer.new()
		_info_ui.set_script(ui_script)
		_info_ui.name = "PlantInfoUI"
		get_tree().get_root().add_child(_info_ui)
		if _info_ui.has_signal("closed"):
			_info_ui.closed.connect(_on_ui_closed)

	if _info_ui.has_method("open"):
		_info_ui.call("open", PlantDatabase.get_display_name(plant_type), health, is_ready())

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
