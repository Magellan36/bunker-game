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
##                      refreshed at a bounded live-status cadence).
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

## Polish Plan Group 1 item 19 (A1) — light floor speed so growth never fully
## stops in darkness. Value is a growth-speed multiplier (0.1 = 10% of normal).
const LIGHT_FLOOR_SPEED: float = 0.1

const SPIKE_WILTED_COLOR: Color = Color(0.42, 0.32, 0.16, 1.0)   ## fully wilted brown, health == 0 (wilt tint target for the bush)

## Human-built rooibos bush growth models (Sep 2026) — replaces the old green
## spike. Five bush variants used in ascending growth order E→D→C→B→A
## (E = smallest sprout → A = biggest fully-grown), mapped to 5 progress bands.
## Each GLB is pre-scaled at export to natural scale, base at y=0, centered.
const BUSH_MODEL_PATHS: Array[String] = [
	"res://assets/models/plants/bush_e.glb",
	"res://assets/models/plants/bush_d.glb",
	"res://assets/models/plants/bush_c.glb",
	"res://assets/models/plants/bush_b.glb",
	"res://assets/models/plants/bush_a.glb",
]
const BUSH_STAGE_COUNT: int = 5

## Polish Plan Group 1 item 3 — gates the on-screen debug readout. Same
## per-file const convention as GrowLight.WIRE_DEBUG / WaterPipeDrawMode's
## PIPE_DEBUG (each debug toggle lives next to what it debugs, no shared
## flag file).
const FARM_DEBUG: bool = false

@export var plant_type: String = "tomato"   ## "tomato" or "onion"

var progress: float = 0.0   ## 0.0 .. 1.0
var health:   float = 100.0 ## 0.0 .. 100.0

## Aug 2026 fix — reentrancy guard. is_instance_valid() only flips to
## false at the END of the frame a node is queue_free()'d, and is_ready()
## alone never changes either — so two callers in the SAME frame (e.g. a
## time-skip catch-up harvesting this plant, then a live NPC's
## JobActivity._complete() still mid-work on it) could both pass the old
## "is_instance_valid() and is_ready()" gate and both call harvest(),
## doubling the produce and double-running _clear_cell_and_free(). Set
## synchronously as the very first thing harvest() does, before any of
## its side effects, so a second same-frame call is a guaranteed no-op
## instead of a race. See docs/systems/npc/README.md for the incident
## writeup.
var _harvested: bool = false

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

## B4 — water fraction cached each tick so UI can read it for status text.
var water_fraction: float = 0.0

var _hour_accum: float = 0.0
var _player_stats: Node = null
## Live UI/status inputs do not need render-frame cadence. Five updates per
## second remain responsive while scaling independently of FPS.
const LIVE_STATUS_INTERVAL: float = 0.2
var _live_status_left: float = 0.0

## Polish Plan Group 1 item 2 — edge-trigger latch for the low-health toast.
var _warned_low_health: bool = false

var _mesh_instance: MeshInstance3D = null
var _debug_label: Label3D = null

## Per-instance wilt-tint materials (one per bush surface, duplicated from the
## stage's base material so albedo_color can lerp toward brown without mutating
## the shared ArrayMesh materials across plants).
var _tint_mats: Array[StandardMaterial3D] = []
var _tint_base_colors: Array[Color] = []
var _cur_stage: int = -1

## Shared bush resources — loaded once, reused by every plant instance.
static var _bush_meshes: Array = []
static var _bush_heights: Array = []
static var _bush_load_warned: bool = false

func _ready() -> void:
	_build_mesh()
	if FARM_DEBUG:
		_build_debug_label()
	_refresh_visual()
	## Spread a large farm across the interval. A negative initial phase forces
	## one refresh on the first process frame, then leaves a randomized offset.
	if _tray == null:
		_live_status_left = -randf() * LIVE_STATUS_INTERVAL

## Called once by FarmingTray right after instancing, before add_child().
func setup(tray: FarmingTray, cell_index: int, type: String) -> void:
	_tray = tray
	_cell_index = cell_index
	plant_type = type
	progress = 0.0
	health   = 100.0
	## Force one correct refresh on the first process frame (after the caller
	## assigns the cell position), then retain a randomized phase offset.
	_live_status_left = -randf() * LIVE_STATUS_INTERVAL

func _refresh_live_status() -> void:
	_light_speed_cached = _compute_light_speed()
	water_fraction = _tray.get_water_fraction() if _tray != null and is_instance_valid(_tray) else 0.0
	var grow_days_live: float = PlantDatabase.get_grow_days(plant_type)
	growth_per_hour_current = _light_speed_cached * water_fraction * (1.0 + fertilizer_bonus) / (grow_days_live * 24.0)

func _process(delta: float) -> void:
	if _tray == null or not is_instance_valid(_tray):
		queue_free()
		return

	## Live display refresh — recomputed at a bounded 5 Hz cadence,
	## independent of the once-per-game-hour simulation tick below, so the
	## tray UI's Dormant/Stalled/Growing status and growth-rate readout react
	## immediately to anything that changes light/water/fertilizer state
	## (adding/removing a light, a pipe, water, or fertilizer) instead of
	## waiting up to a full game hour to catch up. Only these three
	## READ-ONLY cached fields move here — actual progress/health simulation
	## still advances strictly once per game hour in _tick_one_game_hour().
	_live_status_left -= delta
	if _live_status_left <= 0.0:
		_live_status_left += LIVE_STATUS_INTERVAL
		_refresh_live_status()

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
	## _light_speed_cached / water_fraction / growth_per_hour_current are now
	## kept fresh by _process() above — just
	## apply this hour's growth/health using the current values, no
	## recompute here.
	progress = clampf(progress + growth_per_hour_current, 0.0, 1.0)

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
		NotificationManager.notify(UIKit.Domain.FARMING, NotificationManager.Severity.WARNING,
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
	var speed: float = GrowLight.get_best_growth_speed_near(global_position)
	return maxf(speed, LIGHT_FLOOR_SPEED)

func is_ready() -> bool:
	return progress >= 1.0 and not _harvested

func is_fertilized() -> bool:
	return fertilizer_bonus > 0.0

## Called by FarmingTray.fertilize_first_open_cell() — one-time application,
## blocked by the tray/item's own "already fertilized" check upstream.
func apply_fertilizer(tier: String) -> void:
	fertilizer_tier  = tier
	fertilizer_bonus = 0.25 if tier == "pro" else 0.125
	_refresh_live_status()

# ─── Visual ───────────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	_load_bush_meshes()
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

## Loads the five bush ArrayMeshes once (shared across all plant instances).
## Each .glb is a single-mesh scene; the shared ArrayMesh (with its embedded
## surface materials) is grabbed off the instantiated wrapper then freed.
static func _load_bush_meshes() -> void:
	if not _bush_meshes.is_empty():
		return
	for path: String in BUSH_MODEL_PATHS:
		var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
		var mesh: ArrayMesh = null
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			if inst != null:
				var mi: MeshInstance3D = inst as MeshInstance3D
				if mi == null:
					var kids := inst.find_children("*", "MeshInstance3D", true, false)
					if kids.size() > 0:
						mi = kids[0] as MeshInstance3D
				if mi != null:
					mesh = mi.mesh as ArrayMesh
				inst.free()
		_bush_meshes.append(mesh)
		if mesh != null:
			_bush_heights.append(mesh.get_aabb().size.y)
		else:
			_bush_heights.append(0.0)

func _refresh_visual() -> void:
	if _mesh_instance == null:
		return
	_load_bush_meshes()
	if progress <= 0.001:
		_mesh_instance.visible = false
		return
	_mesh_instance.visible = true

	var stage: int = clampi(int(progress * BUSH_STAGE_COUNT), 0, BUSH_STAGE_COUNT - 1)
	var mesh: ArrayMesh = _bush_meshes[stage] as ArrayMesh
	if mesh == null:
		_mesh_instance.visible = false
		if not _bush_load_warned:
			_bush_load_warned = true
			push_warning("FarmPlant: one or more bush models failed to load (%s)" % str(BUSH_MODEL_PATHS))
		return

	_mesh_instance.mesh = mesh
	_ensure_tint_mats(stage, mesh)

	## Seamless growth — within each stage band, scale the current bush from
	## its natural size up to the NEXT stage's height, so switching models at
	## the band boundary is height-continuous (no pop). The first stage grows
	## from nothing (sprout emerging from the soil).
	var band: float = 1.0 / float(BUSH_STAGE_COUNT)
	var band_t: float = clampf((progress - float(stage) * band) / band, 0.0, 1.0)
	var start_scale: float
	var end_scale: float
	if stage == 0:
		start_scale = 0.0
		end_scale = (_bush_heights[1] / _bush_heights[0]) if _bush_heights[0] > 0.0 else 1.0
	elif stage < BUSH_STAGE_COUNT - 1:
		start_scale = 1.0
		end_scale = (_bush_heights[stage + 1] / _bush_heights[stage]) if _bush_heights[stage] > 0.0 else 1.0
	else:
		start_scale = 1.0
		end_scale = 1.0
	_mesh_instance.scale = Vector3.ONE * lerpf(start_scale, end_scale, band_t)
	_mesh_instance.position = Vector3.ZERO   ## bush base sits on the soil layer (local Y=0)

	## Polish Plan Group 1 item 1 — wilting visual (preserved from the spike):
	## lerp each surface's base color toward wilted brown as health drops below
	## the wilt threshold, fully wilted at health == 0.
	var wilt_t: float = 0.0
	if health < FarmingConstants.HEALTH_WILT_THRESHOLD:
		wilt_t = 1.0 - (health / FarmingConstants.HEALTH_WILT_THRESHOLD)
	wilt_t = clampf(wilt_t, 0.0, 1.0)
	for i: int in _tint_mats.size():
		_tint_mats[i].albedo_color = _tint_base_colors[i].lerp(SPIKE_WILTED_COLOR, wilt_t)

## Builds one duplicated StandardMaterial3D per bush surface (on stage change
## only) so the wilt tint can be applied per-instance without mutating the
## shared ArrayMesh materials.
func _ensure_tint_mats(stage: int, mesh: ArrayMesh) -> void:
	if stage == _cur_stage:
		return
	_cur_stage = stage
	_tint_mats.clear()
	_tint_base_colors.clear()
	for s: int in mesh.get_surface_count():
		var base: Material = mesh.surface_get_material(s)
		var dup: StandardMaterial3D
		if base is StandardMaterial3D:
			dup = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			dup = StandardMaterial3D.new()
			dup.roughness = 0.8
		_tint_mats.append(dup)
		_tint_base_colors.append(dup.albedo_color)
		_mesh_instance.set_surface_override_material(s, dup)

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
	if _harvested or not is_ready():
		return
	_harvested = true   ## must be set before any side effect below — see the var's own comment
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
