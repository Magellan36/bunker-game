extends Node3D
class_name FarmPlant
## FarmPlant.gd
## ─────────────────────────────────────────────────────────────────────────────
## Per-cell plant instance (Farming System plan §5.4/§6/§7). Spawned by
## FarmingTray.plant_seed() as a sibling-positioned child above its cell,
## freed on harvest or death.
##
## Polish Plan Group 0 item 19 cleanup: plain `Node3D` — no collider, no
## `on_interact()`, no `interactable`/`farm_plant` group membership. Pure
## simulation (growth/health tick) + visual (the spike mesh), read *by* its
## parent `FarmingTray` and displayed *in* the tray's own `FarmingTrayUI`
## (see `_draw_plant_block()` there). Group 0's original commit only deleted
## the `on_interact()`/`get_interact_prompt()` functions, not the
## StaticBody3D/collider/groups underneath them — this pass finishes that
## cleanup (harmless in practice since `InteractionSystem` gates on
## `has_method("on_interact")`, but inconsistent with the "no collider, no
## interactable group" claim, so tidied up while touching this file for
## Group 1 anyway).
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
##   growth_per_hour  = light_speed * water_fraction * (1 + fertilizer_bonus)
##                      / (grow_days * 24.0)
##                      fertilizer_bonus: 0.0 none / 0.125 normal / 0.25 pro
##
## Health formula (plan §6.3): -5%/hr whenever water_fraction == 0.0, and an
## independent -5%/hr once unlit for more than 24 consecutive hours. Both can
## apply the same hour. At 0% health the plant dies — no harvest, seed wasted,
## tray cell reverts to soil-filled/empty (confirmed with Brannon).
##
## Health does NOT gate readiness — a plant can show READY at low health
## (plan's explicit two-independent-readouts design).
##
## Polish Plan Group 1 additions:
##   1 — wilting visual: `_refresh_visual()` lerps the spike's albedo from
##       healthy green to wilted-brown as `health` crosses below
##       `FarmingConstants.HEALTH_WILT_THRESHOLD`, scaling to fully brown at 0.
##   2 — low-health toast: fires once (edge-triggered) via
##       `NotificationManager` when `health` first crosses below
##       `FarmingConstants.HEALTH_WARNING_THRESHOLD`. NotificationManager (the
##       project's current central toast system) is used here rather than the
##       older standalone `TransientNotice.gd` the original polish doc named
##       (written before NotificationManager existed) — NEUTRAL domain, since
##       Farming has no domain of its own, WARNING severity (a localized
##       per-plant problem, not a total-system failure).
##   3 — FARM_DEBUG-gated on-screen readout (billboarded Label3D) showing
##       hours_without_light/health/water_fraction/light_speed, same
##       per-file debug-const convention as WIRE_DEBUG/PIPE_DEBUG elsewhere.
##   4 — `growth_per_hour_current` is cached each tick so FarmingTrayUI's
##       "Ready in ~X days" countdown (item 4) can read the live rate.

signal died()
signal harvested()

const PLANT_FULL_HEIGHT: float = 0.85   ## Matches GeneratorObject.TIER_CONFIG size.y

## Health penalty rates (plan §6.3).
const HEALTH_LOSS_NO_WATER_PER_HOUR: float = 5.0
const HEALTH_LOSS_NO_LIGHT_PER_HOUR: float = 5.0
const NO_LIGHT_GRACE_HOURS: int = 24

const SPIKE_BASE_RADIUS: float = 0.05
const SPIKE_TIP_RADIUS:  float = 0.015
const SPIKE_COLOR:        Color = Color(0.22, 0.62, 0.20, 1.0)   ## healthy green
const SPIKE_WILTED_COLOR: Color = Color(0.42, 0.32, 0.16, 1.0)   ## fully wilted brown, health == 0

## Polish Plan Group 1 item 3 — gates the on-screen debug readout. Same
## per-file const convention as GrowLight.WIRE_DEBUG / WaterPipeDrawMode's
## PIPE_DEBUG (each debug toggle lives next to what it debugs, no shared
## flag file).
const FARM_DEBUG: bool = false

@export var plant_type: String = "tomato"   ## "tomato" or "onion"

var progress: float = 0.0   ## 0.0 .. 1.0
var health:   float = 100.0 ## 0.0 .. 100.0

## Farming Fertilizer plan — set via apply_fertilizer(), reset per-planting
## automatically since a fresh FarmPlant instance is created on every
## plant_seed()/harvest cycle (no explicit reset code needed).
var fertilizer_bonus: float = 0.0    ## 0.0 / 0.125 / 0.25
var fertilizer_tier:  String = ""    ## "" / "normal" / "pro" — for the UI label

var _tray: FarmingTray = null
var _cell_index: int   = -1

var _hours_without_light: int = 0
var _light_speed_cached:  float = 0.0

## Polish Plan Group 1 item 4 — last computed growth rate, read by
## FarmingTrayUI's countdown estimate (public, not "_"-prefixed private).
var growth_per_hour_current: float = 0.0

var _hour_accum: float = 0.0
var _player_stats: Node = null

## Polish Plan Group 1 item 2 — edge-trigger latch for the low-health toast.
var _warned_low_health: bool = false

var _mesh_instance: MeshInstance3D = null
var _spike_mat: StandardMaterial3D = null
var _debug_label: Label3D = null

func _ready() -> void:
	_build_mesh()
	if FARM_DEBUG:
		_build_debug_label()
	_refresh_visual()

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

	var growth_per_hour: float = _light_speed_cached * water_fraction * (1.0 + fertilizer_bonus) / (grow_days * 24.0)
	growth_per_hour_current = growth_per_hour
	progress = clampf(progress + growth_per_hour, 0.0, 1.0)

	if water_fraction == 0.0:
		health = maxf(0.0, health - HEALTH_LOSS_NO_WATER_PER_HOUR)

	if _light_speed_cached == 0.0:
		_hours_without_light += 1
	else:
		_hours_without_light = 0

	if _hours_without_light > NO_LIGHT_GRACE_HOURS:
		health = maxf(0.0, health - HEALTH_LOSS_NO_LIGHT_PER_HOUR)

	## Polish Plan Group 1 item 2 — edge-triggered low-health toast (fires
	## once when crossing the threshold, not every hour it stays below it).
	if health < FarmingConstants.HEALTH_WARNING_THRESHOLD and not _warned_low_health:
		_warned_low_health = true
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			"%s wilting — health low" % plant_type.capitalize())
	elif health >= FarmingConstants.HEALTH_WARNING_THRESHOLD:
		_warned_low_health = false

	_refresh_visual()
	_update_debug_label()

	if health <= 0.0:
		_die()

## Polish Plan Group 6 item 14 (perf) — spatial-hash bucket lookup replacing
## the old per-hour, per-plant O(n) scan over every "grow_light" group
## member. Still "nearest light within radius" (no parent/child relationship
## or registration handshake with the light itself, plan §4) — just
## resolved via GrowLight's static bucket registry (3x3 neighborhood scan +
## exact distance check) instead of scanning every light in the game.
func _compute_light_speed() -> float:
	return GrowLight.get_best_growth_speed_near(global_position)

func is_ready() -> bool:
	return progress >= 1.0

func is_fertilized() -> bool:
	return fertilizer_bonus > 0.0

## Called by FarmingTray.fertilize_first_open_cell() — one-time application,
## blocked by the tray/item's own "already fertilized" check upstream.
func apply_fertilizer(tier: String) -> void:
	fertilizer_tier  = tier
	fertilizer_bonus = 0.25 if tier == "pro" else 0.125

# ─── Visual ───────────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	_spike_mat = StandardMaterial3D.new()
	_spike_mat.albedo_color = SPIKE_COLOR
	_spike_mat.roughness    = 0.85
	_mesh_instance.set_surface_override_material(0, _spike_mat)
	add_child(_mesh_instance)

func _refresh_visual() -> void:
	if _mesh_instance == null:
		return
	var height: float = progress * PLANT_FULL_HEIGHT
	if height <= 0.001:
		_mesh_instance.visible = false
	else:
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

	## Polish Plan Group 1 item 1 — wilting visual: lerp albedo from healthy
	## green toward wilted brown as health drops below the wilt threshold,
	## fully wilted at health == 0.
	if _spike_mat != null:
		if health >= FarmingConstants.HEALTH_WILT_THRESHOLD:
			_spike_mat.albedo_color = SPIKE_COLOR
		else:
			var wilt_t: float = 1.0 - (health / FarmingConstants.HEALTH_WILT_THRESHOLD)
			_spike_mat.albedo_color = SPIKE_COLOR.lerp(SPIKE_WILTED_COLOR, clampf(wilt_t, 0.0, 1.0))

## Polish Plan Group 1 item 3 — FARM_DEBUG-gated on-screen readout, built
## once in _ready() when FARM_DEBUG is true.
func _build_debug_label() -> void:
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.font_size = 32
	_debug_label.outline_size = 8
	_debug_label.position = Vector3(0.0, PLANT_FULL_HEIGHT + 0.3, 0.0)
	add_child(_debug_label)
	_update_debug_label()

func _update_debug_label() -> void:
	if _debug_label == null:
		return
	_debug_label.text = "%s\nhealth=%.0f  water=%.2f\nlight=%.1f  no_light_hrs=%d" % [
		plant_type, health, (_tray.get_water_fraction() if _tray != null and is_instance_valid(_tray) else 0.0),
		_light_speed_cached, _hours_without_light
	]

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
