extends StaticBody3D
class_name WaterDispenser
## WaterDispenser.gd
## ─────────────────────────────────────────────────────────────────────────────
## The water system's first real, gameplay-relevant consuming device (Jul
## 2026) — mirrors WaterTestSink.gd's registration/interaction shape but with
## real storage, a player-tunable requested rate (slider), on/off, and a fill
## tick driven by WaterSolver.gd's actual per-tick allocation rather than the
## raw requested rate. TILE_WATER_DISPENSER in BuildModeController.
##
## CRITICAL DISTINCTION, worth restating plainly (see the plan, Section 2):
## the slider sets REQUESTED demand. The fill rate is driven by whatever
## WaterSolver actually GRANTED this device this tick, which can be less
## than requested — a same-tier sibling raising its own demand pulls water
## away even if this device's own slider never moved. Never fill directly
## off requested_rate_mL_per_day; always off WaterManager.get_received_rate_mL().
##
## Registers into the water graph exactly like WaterTestSink (role
## "endpoint", consumer_ref = self) so WaterSolver treats it identically to
## any other consumer — no special-casing anywhere in the solver.

const MAX_STORAGE_ML: float = 5000.0

const BOX_SIZE: Vector3 = Vector3(0.45, 0.55, 0.35)
const COLOR_BODY:  Color = Color(0.26, 0.42, 0.48, 1.0)   ## teal-grey, distinct from the sink's neutral grey
const COLOR_SPOUT: Color = Color(0.18, 0.30, 0.34, 1.0)

## Adjustable — see WaterDispenserUI.gd / PowerPriorityUI.gd's equivalent for
## the power system. 1 = highest priority (served first), 5 = lowest.
@export var priority: int = 3

## The slider's value — the device's OWN desired demand, fed INTO the
## solver. Untouched by the on/off toggle (see set_on()) so re-enabling
## resumes at the same setting without the player re-dragging anything.
var requested_rate_mL_per_day: float = 0.0

var is_on: bool = true
var current_fill_mL: float = 0.0

## Cached PlayerStats ref, same lazy-lookup/cache pattern WaterHookup.gd uses
## for its own quality-decay tick — needed to convert "mL/day" into an actual
## fill-per-real-second rate using the COMPRESSED in-game day length
## (day_duration_seconds, default 1440 real seconds = 24 real minutes), not
## a literal real-world 24-hour day. See _process() below.
var _player_stats: Node = null

## Blended volume-weighted from incoming hookup water (see _process()) —
## also now the SOURCE quality read by WaterBottle.bottle_refill_tick() when
## a player refills a bottle from this dispenser (Jul 2026 bottle rework).
var stored_water_quality: float = 100.0

var _node_key: String = ""

## UI panel (lazy-instantiated, reused across opens — same spawn-once-reuse
## pattern as PowerTerminal._terminal_ui / WaterHookup._info_ui).
var _dispenser_ui: CanvasLayer = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	## Jul 2026 (bottle refill rework): lets WaterBottle.bottle_refill_tick()
	## find this dispenser via get_nodes_in_group(), same nearest-node lookup
	## pattern FuelCan._find_nearest_generator() uses for the "generator" group.
	add_to_group("water_dispenser")
	_build_mesh()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	if _dispenser_ui != null and is_instance_valid(_dispenser_ui):
		_dispenser_ui.queue_free()
		_dispenser_ui = null
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	if not _node_key.is_empty():
		wm.unregister_node(_node_key)

func _register_deferred() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		push_warning("WaterDispenser: WaterManager not found — will never receive water.")
		return
	## Registered at the top of the box, same convention as WaterTestSink —
	## the actual physical point a pipe connects to.
	_node_key = wm.register_node(global_position + Vector3(0.0, BOX_SIZE.y, 0.0), "endpoint", self)


# ─── WaterSolver duck-typed demand contract ───────────────────────────────────
## Zero whenever off or already full — this is what lets other devices (same
## tier or lower) reclaim capacity automatically the instant this one stops
## actually drawing, without the player touching anything.
func get_current_demand_mL_per_day() -> float:
	if not is_on or current_fill_mL >= MAX_STORAGE_ML:
		return 0.0
	return requested_rate_mL_per_day


# ─── Fill tick ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _node_key.is_empty():
		return

	## Reclamp rule (plan §2): every solve pass, clamp the requested rate down
	## to whatever the network can actually grant. Must happen here (every
	## frame) rather than only while the UI panel is open, otherwise a
	## dispenser left at, say, 5000 could silently end up "requesting" more
	## than the network can give it the moment some OTHER device's priority
	## or demand changes elsewhere, even with this panel closed.
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	var dynamic_max: float = wm.get_dynamic_max_mL_per_day(_node_key, priority)
	requested_rate_mL_per_day = minf(requested_rate_mL_per_day, dynamic_max)

	if not is_on or current_fill_mL >= MAX_STORAGE_ML:
		return

	var info: Dictionary = wm.get_received_rate_mL(_node_key)
	if not bool(info.get("connected", false)):
		return

	## Fixed prior bug: this used to divide by a literal 86400 (real seconds
	## in an actual 24-hour day), running ~60x slower than every other timed
	## system in the game — PlayerStats' own thirst/hunger/sleep drain is
	## scaled to the COMPRESSED in-game day (day_duration_seconds, default
	## 1440 real seconds = 24 real minutes per game day). "mL/day" now means
	## per GAME day consistently across the whole water system, matching
	## WaterHookup's quality-decay tick (same _player_stats/
	## _seconds_per_game_hour lookup/cache pattern).
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	var seconds_per_game_day: float = 86400.0   ## real-day fallback if PlayerStats isn't found yet
	if _player_stats != null and _player_stats._seconds_per_game_hour > 0.0:
		seconds_per_game_day = _player_stats._seconds_per_game_hour * 24.0

	var received_mL_per_day: float = float(info.get("mL_per_day", 0.0))
	var incoming_quality: float    = float(info.get("quality", 100.0))
	var received_mL_per_sec: float = received_mL_per_day / seconds_per_game_day

	## Volume-weighted quality blend (Jul 2026, Purifier pass):
	## new_avg = (old_volume*old_avg + added_volume*added_quality) / (old_volume+added_volume).
	## `added_mL` is clamped to the tank's remaining headroom FIRST so the
	## blend always uses the exact volume actually added this frame — using
	## the pre-clamp delta here would under-count old_volume's weight right
	## at the moment the tank finishes filling.
	var added_mL: float = minf(received_mL_per_sec * delta, MAX_STORAGE_ML - current_fill_mL)
	if added_mL > 0.0:
		var new_total: float = current_fill_mL + added_mL
		if new_total > 0.0:
			stored_water_quality = (current_fill_mL * stored_water_quality + added_mL * incoming_quality) / new_total
		current_fill_mL = new_total


# ─── Public API (used by WaterDispenserUI.gd) ─────────────────────────────────
func get_node_key() -> String:
	return _node_key

## Toggling off sets is_on = false; requested_rate_mL_per_day (the slider's
## stored value) is left untouched, so turning back on resumes at the same
## setting without the player re-dragging anything (plan §2).
func set_on(value: bool) -> void:
	is_on = value

func set_requested_rate(value: float) -> void:
	requested_rate_mL_per_day = maxf(0.0, value)

## Save/Load (Jul 2026) — restores stored fill volume directly. No other
## caller needs this (normal gameplay only ever grows current_fill_mL via the
## _process() fill tick), so a plain setter is enough — no signal/UI refresh
## needed like set_on()/set_requested_rate() (those are called live from the
## open panel; this one only runs once, at load time, before the panel could
## possibly be open).
func set_fill(value: float) -> void:
	current_fill_mL = clampf(value, 0.0, MAX_STORAGE_ML)


# ─── Interaction ──────────────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	return "[E] Use Dispenser"

## NOTE: does NOT toggle open/closed — mirrors PowerTerminal/WaterHookup/
## WaterTestSink's "always (re)open" pattern.
func on_interact() -> void:
	if _dispenser_ui == null or not is_instance_valid(_dispenser_ui):
		var ui_script: GDScript = load("res://scripts/ui/water/WaterDispenserUI.gd")
		if ui_script == null:
			push_warning("WaterDispenser: WaterDispenserUI.gd not found")
			return
		_dispenser_ui = CanvasLayer.new()
		_dispenser_ui.set_script(ui_script)
		_dispenser_ui.name = "WaterDispenserUI"
		get_tree().get_root().add_child(_dispenser_ui)
		if _dispenser_ui.has_signal("closed"):
			_dispenser_ui.closed.connect(_on_ui_closed)

	if _dispenser_ui.has_method("open"):
		_dispenser_ui.open(self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ─── Mesh (placeholder — grey/teal box body + darker spout nub) ──────────────
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = BOX_SIZE
	return box

func _build_mesh() -> void:
	var mi:   MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh        = BoxMesh.new()
	mesh.size = BOX_SIZE
	mi.mesh   = mesh
	mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_BODY
	mat.roughness    = 0.55
	mat.metallic     = 0.30
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	## Small spout nub near the bottom-front — purely cosmetic, no collision.
	var spout: MeshInstance3D = MeshInstance3D.new()
	var spout_mesh: CylinderMesh = CylinderMesh.new()
	spout_mesh.top_radius    = 0.05
	spout_mesh.bottom_radius = 0.05
	spout_mesh.height        = 0.10
	spout.mesh     = spout_mesh
	spout.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	spout.position = Vector3(0.0, BOX_SIZE.y * 0.18, BOX_SIZE.z * 0.5 + 0.05)
	var spout_mat: StandardMaterial3D = StandardMaterial3D.new()
	spout_mat.albedo_color = COLOR_SPOUT
	spout_mat.roughness    = 0.40
	spout_mat.metallic     = 0.60
	spout.set_surface_override_material(0, spout_mat)
	mi.add_child(spout)

	mi.create_trimesh_collision()
	for child in mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0
