extends StaticBody3D
class_name FarmingTray
## FarmingTray.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §2/§5. Single (1×1, $150) or double (2×1, $275) tray,
## placed via Construct → Farming. Independent WaterSolver demand consumer
## (role "endpoint", consumer_ref = self) — exactly like WaterTestSink/
## WaterDispenser, registered at a stub on the tray's side (not its origin).
##
## Water quality does NOT affect anything here — deliberate design choice
## (plan §2). Only connection + how much of fixed demand is actually being
## met (water_fraction) matters, and that feeds FarmPlant's growth formula.

const BASIN_TOP_Y: float  = 0.85   ## Matches GeneratorObject.TIER_CONFIG size.y (plan §5.2)
const LEG_HEIGHT: float   = 0.72
const BASIN_WALL_H: float = 0.13
const SOIL_LAYER_Y: float = 0.78   ## Where FarmPlant roots sit — top of the soil layer

const COLOR_LEG:   Color = Color(0.32, 0.32, 0.34, 1.0)
const COLOR_BASIN: Color = Color(0.40, 0.40, 0.42, 1.0)   ## bare grey/metal — empty state
const COLOR_SOIL:  Color = Color(0.30, 0.20, 0.12, 1.0)   ## dark brown — soil-filled state

@export var cell_count: int = 1   ## 1 = single tray, 2 = double tray

var priority: int = 3   ## Tier-adjustable, default 3 (plan §2)

var soil_filled:  Array[bool]   = []
var planted_type: Array[String] = []
var plant_refs:   Array[FarmPlant] = []

## Aug 2026 — per-cell replant memory. Unlike planted_type (blanked by
## clear_cell() on every harvest), this survives specifically so "prefer
## replanting what was there before" has something to read afterward.
## Kept in sync by whichever plant-a-cell function is live (player- and
## NPC-driven planting both go through it) so it's never a separate thing
## to maintain. This is a SOFT preference only — distinct from and
## unrelated to get_cell_seed_lock()'s hard per-cell constraint; NPC
## Gardening consults the lock first and only falls back to this when a
## cell has no lock at all.
var last_planted_type: Array[String] = []

## B1 — fertilizer can be applied to empty (unplanted) soil. "Prepped"
## means fertilizer has been applied to empty soil; when a seed is later
## planted there, it starts already fertilized.
var cell_prepped_fertilizer: Array[String] = []

## Seed Lock plan (Aug 2026) — per-cell NPC auto-plant restriction. ""
## means "Any" (unrestricted, NPC will plant whatever the JobBoard/NPC
## logic picks). A non-empty value is a PlantDatabase plant_type key
## (e.g. "onion") — the ONLY type the NPC's future auto-planting job is
## allowed to plant into this specific cell. Deliberately does NOT gate
## the player's own manual SeedItem/FarmProduceItem on_use() — the player
## can always plant by hand regardless of this value (confirmed with
## Brannon). In-session only for now — not wired into save/load, matching
## the tray's existing soil_filled/planted_type gap (see "Known gaps" in
## docs/systems/farming/README.md).
var cell_seed_lock: Array[String] = []

## Nearest-valid-tray highlight (Polish Plan Group 5 item 12) — driven
## externally by BagOfSoilItem/SeedItem while held, mirroring their existing
## "nearest in range" lookups. Pulses a translucent green outline over the
## whole footprint so the target reads clearly before the player commits.
const HIGHLIGHT_COLOR:        Color = Color(0.35, 1.0, 0.45, 0.22)
const HIGHLIGHT_PULSE_ALPHA_LOW:  float = 0.14
const HIGHLIGHT_PULSE_ALPHA_HIGH: float = 0.40
const HIGHLIGHT_PULSE_PERIOD: float = 0.6
var _highlight_mi:     MeshInstance3D = null
var _highlight_mat:    StandardMaterial3D = null
var _highlight_tween:  Tween = null

var _node_key: String = ""
var _water_fraction_cached: float = 0.0
var _connected_cached: bool = false
## Cached WaterManager ref — lazy-resolved once (was a per-frame group scan).
var _wm: WaterManager = null

## Farming Polish Plan Group 6 item 13 (perf) — batched per-hookup solve
## cache, shared by EVERY FarmingTray instance (static). Only one hookup is
## ever supported (WaterManager.get_the_hookup()), so "once per hookup"
## reduces to "once per Engine frame" here — a room with a dozen trays now
## triggers one WaterManager solve per frame instead of a dozen. Cache key
## is the frame index; it invalidates itself automatically next frame.
static var _batch_frame: int = -1
static var _batch_map: Dictionary = {}

var _soil_mesh_instances: Array = []   ## one per cell, null until filled
var _tray_ui: CanvasLayer = null

const REPLACE_RANGE: float = 2.5   ## Same convention as PurifierFilterItem.REPLACE_RANGE

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

func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	soil_filled.resize(cell_count)
	planted_type.resize(cell_count)
	plant_refs.resize(cell_count)
	cell_prepped_fertilizer.resize(cell_count)
	cell_seed_lock.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	last_planted_type.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		cell_prepped_fertilizer[i] = ""
		cell_seed_lock[i] = ""
		_soil_mesh_instances[i] = null
		last_planted_type[i] = ""

	collision_layer = 5
	collision_mask  = 0
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("farming_tray")
	_build_mesh()
	if _is_preview_only:
		return
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	if _tray_ui != null and is_instance_valid(_tray_ui):
		_tray_ui.queue_free()
		_tray_ui = null
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	if not _node_key.is_empty():
		wm.unregister_node(_node_key)

func _register_deferred() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		push_warning("FarmingTray: WaterManager not found — will never receive water.")
		return
	## Registered at a stub on the tray's +X side (not its origin) — the
	## actual physical point a pipe connects to, same convention WaterTestSink/
	## WaterDispenser use for their own top-of-box stub.
	##
	## Aug 2026 fix — must go through to_global(), not global_position + a
	## flat world-space offset. The flat-offset version ignored the tray's
	## own rotation entirely, so a tray placed at any angle other than the
	## build-mode default registered its hookup at the wrong world-space
	## spot (always +X in WORLD space, not +X in the tray's own facing),
	## producing a pipe that visually floats away from the tray's actual
	## basin edge. to_global() carries the local offset through the tray's
	## full transform (translation + Y rotation), so the registered point
	## now always lands on the correct edge regardless of placement angle.
	var edge_x: float = 0.45 if cell_count == 1 else 0.95
	_node_key = wm.register_node(to_global(Vector3(edge_x, BASIN_TOP_Y, 0.0)), "endpoint", self)

func _process(_delta: float) -> void:
	if _wm == null:
		_wm = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if _wm == null or _node_key.is_empty():
		_water_fraction_cached = 0.0
		_connected_cached = false
		return
	_connected_cached = _wm.is_reachable_from_hookup(_node_key)
	if not _connected_cached:
		_water_fraction_cached = 0.0
		return
	var map: Dictionary = _get_batched_hookup_map(_wm)
	var received_mL_per_day: float = float(map.get(_node_key, 0.0))
	var demand: float = get_current_demand_mL_per_day()
	_water_fraction_cached = clampf(received_mL_per_day / demand, 0.0, 1.0) if demand > 0.0 else 0.0

## Returns this frame's shared solve result, running the (single, since only
## one hookup exists) solve exactly once per frame no matter how many trays
## call in — see _batch_frame/_batch_map's header above.
func _get_batched_hookup_map(wm: WaterManager) -> Dictionary:
	var frame: int = Engine.get_process_frames()
	if frame != FarmingTray._batch_frame:
		FarmingTray._batch_frame = frame
		FarmingTray._batch_map = wm.solve_hookup_for_farming()
	return FarmingTray._batch_map

# ─── WaterSolver duck-typed demand contract ───────────────────────────────────
## Fixed, not player-tunable — both cells of a double tray share one
## connection/one demand figure (plan §2).
func get_current_demand_mL_per_day() -> float:
	return 1000.0 if cell_count == 1 else 2000.0

## Read live by FarmPlant every hour tick — how much of this tray's demand is
## actually being met right now (0.0 disconnected/no supply .. 1.0 full demand met).
func get_water_fraction() -> float:
	return _water_fraction_cached

func get_node_key() -> String:
	return _node_key

func is_connected_to_water() -> bool:
	return _connected_cached

# ─── Cell state queries (used by BagOfSoilItem / SeedItem) ──────────────────
func has_open_soil_cell() -> bool:
	for f: bool in soil_filled:
		if not f:
			return true
	return false

func has_open_plantable_cell() -> bool:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			return true
	return false

func is_fully_soiled() -> bool:
	for f: bool in soil_filled:
		if not f:
			return false
	return true

## Fills exactly the given cell. Returns true on success. Replaces the old
## tray-wide fill_first_open_soil_cell() (Aug 2026 per-cell interaction
## pass) — callers now resolve WHICH cell via nearest_open_soil_cell_to()
## first, then commit here.
func fill_soil_at_cell(cell_index: int) -> bool:
	if cell_index < 0 or cell_index >= cell_count:
		return false
	if soil_filled[cell_index]:
		return false
	soil_filled[cell_index] = true
	_refresh_soil_visual(cell_index)
	_play_soil_fill_puff(cell_index)
	return true

## Soil-fill dust-puff (Polish Plan Group 3 item 7) — cosmetic only, no sound
## (project has no audio infrastructure yet at all; flagged as a scope call
## in the Group 3 handover rather than introducing a first-ever audio system
## for one polish item). Tween convention mirrors WaterPurifier's
## play_clean_pulse(): create_tween, parallel scale+fade-out, then queue_free.
const SOIL_PUFF_COLOR:        Color = Color(0.42, 0.30, 0.18, 0.65)   ## dusty brown, semi-transparent
const SOIL_PUFF_START_SCALE:  float = 0.2
const SOIL_PUFF_END_SCALE:    float = 1.4
const SOIL_PUFF_DURATION:     float = 0.35

func _play_soil_fill_puff(cell_index: int) -> void:
	var puff_mi: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	puff_mi.mesh = quad

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color      = SOIL_PUFF_COLOR
	mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test     = true
	mat.billboard_mode    = BaseMaterial3D.BILLBOARD_ENABLED
	puff_mi.set_surface_override_material(0, mat)

	add_child(puff_mi)
	puff_mi.position = Vector3(_cell_local_x(cell_index), LEG_HEIGHT + BASIN_WALL_H + 0.05, 0.0)
	puff_mi.scale = Vector3.ONE * SOIL_PUFF_START_SCALE

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(puff_mi, "scale", Vector3.ONE * SOIL_PUFF_END_SCALE, SOIL_PUFF_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, SOIL_PUFF_DURATION)
	tween.chain().tween_callback(puff_mi.queue_free)

## ─── Fertilizer cell state queries (used by FertilizerItem) ──────────────────
func has_open_fertilizable_cell() -> bool:
	for i: int in range(cell_count):
		var p: FarmPlant = plant_refs[i]
		if p != null and is_instance_valid(p) and not p.is_ready() and not p.is_fertilized():
			return true
		if p == null and soil_filled[i] and cell_prepped_fertilizer[i] == "":
			return true
	return false

func has_already_fertilized_growing_cell() -> bool:
	for i: int in range(cell_count):
		var p: FarmPlant = plant_refs[i]
		if p != null and is_instance_valid(p) and not p.is_ready() and p.is_fertilized():
			return true
		if p == null and soil_filled[i] and cell_prepped_fertilizer[i] != "":
			return true   ## Already-prepped empty soil counts as "already fertilized" too
	return false

## Applies fertilizer to the first open (growing, not-yet-fertilized) cell.
## Also applies to empty-but-soiled cells (preps them for next planting).
## Returns true if fertilizer was applied.
func fertilize_first_open_cell(tier: String) -> bool:
	for i: int in range(cell_count):
		var p: FarmPlant = plant_refs[i]
		if p != null and is_instance_valid(p) and not p.is_ready() and not p.is_fertilized():
			p.apply_fertilizer(tier)
			return true
		if p == null and soil_filled[i] and cell_prepped_fertilizer[i] == "":
			cell_prepped_fertilizer[i] = tier
			return true
	return false

## Plants into exactly the given cell (must already be soiled and empty).
## Returns true on success. Replaces the old tray-wide plant_first_open_cell()
## (Aug 2026 per-cell interaction pass) — callers now resolve WHICH cell via
## nearest_open_plantable_cell_to() first, then commit here. Deliberately
## does NOT consult cell_seed_lock — the lock only constrains the NPC
## thread's own job-discovery/dispatch logic (their choice of WHICH job to
## post/claim), never this low-level mutator. A player (or, per the NPC
## thread's own future logic, an NPC executing a job it already chose)
## calling this directly always succeeds regardless of any lock set here.
func plant_seed_at_cell(cell_index: int, plant_type: String) -> bool:
	if cell_index < 0 or cell_index >= cell_count:
		return false
	if not soil_filled[cell_index] or planted_type[cell_index] != "":
		return false
	planted_type[cell_index] = plant_type
	last_planted_type[cell_index] = plant_type   ## Aug 2026 — survives the eventual harvest, unlike planted_type
	var plant: FarmPlant = FarmPlant.new()
	add_child(plant)
	plant.setup(self, cell_index, plant_type)
	plant.position = Vector3(_cell_local_x(cell_index), SOIL_LAYER_Y, 0.0)
	plant_refs[cell_index] = plant
	## B7 — if this cell had prepped fertilizer, apply it now and clear it
	if cell_prepped_fertilizer[cell_index] != "":
		plant.apply_fertilizer(cell_prepped_fertilizer[cell_index])
		cell_prepped_fertilizer[cell_index] = ""
	return true

## Called by FarmPlant on harvest/death — cell goes back to soil-filled/empty,
## ready to replant, no new soil bag needed (plan §5.3/§6.3).
func clear_cell(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	planted_type[cell_index] = ""
	plant_refs[cell_index]   = null
	cell_prepped_fertilizer[cell_index] = ""
	## Seed Lock plan — deliberately NOT cleared on harvest/death. A lock
	## is a standing instruction ("always replant onions here"), not a
	## one-shot flag, so it survives the cell going empty and applies to
	## the next auto-plant too.

## ─── Seed Lock (used by FarmingTrayUI, read by the NPC thread) ──────────────
## "" = Any/unrestricted. Non-empty = a PlantDatabase plant_type key. Does
## NOT gate FarmingTray.plant_seed_at_cell() — see that function's own
## comment. Purely a read/write data field for the NPC thread's future
## PLANT_SEED job discovery to consult.
func get_cell_seed_lock(cell_index: int) -> String:
	if cell_index < 0 or cell_index >= cell_count:
		return ""
	return cell_seed_lock[cell_index]

func set_cell_seed_lock(cell_index: int, seed_type: String) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	cell_seed_lock[cell_index] = seed_type

func _cell_local_x(cell_index: int) -> float:
	if cell_count == 1:
		return 0.0
	return -0.475 if cell_index == 0 else 0.475

# ─── Per-cell targeting (Aug 2026 — treat a double tray as two independent
# 1×1 cells for every action: soil, seed, harvest. A single tray always
# resolves to cell 0. XZ-only distance (matches every other horizontal-only
# proximity check in this file, e.g. GrowLight's own XZ match) — Y doesn't
# matter since cells never differ in height. Used by held items (their own
# global_position while held) and, going forward, by NPC job execution
# (their own global_position at time of acting). ────────────────────────────
func nearest_cell_to(pos: Vector3) -> int:
	if cell_count == 1:
		return 0
	var best_i: int = 0
	var best_d: float = INF
	for i: int in range(cell_count):
		var cell_pos: Vector3 = to_global(Vector3(_cell_local_x(i), 0.0, 0.0))
		var d: float = Vector2(cell_pos.x, cell_pos.z).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

## Same nearest-cell search, restricted to cells matching `predicate(i)`.
## Returns -1 if no cell matches. Shared by the three typed lookups below.
func _nearest_matching_cell(pos: Vector3, predicate: Callable) -> int:
	var best_i: int = -1
	var best_d: float = INF
	for i: int in range(cell_count):
		if not predicate.call(i):
			continue
		var cell_pos: Vector3 = to_global(Vector3(_cell_local_x(i), 0.0, 0.0))
		var d: float = Vector2(cell_pos.x, cell_pos.z).distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

## Used by BagOfSoilItem.on_use() (and, going forward, NPC FILL_SOIL jobs).
func nearest_open_soil_cell_to(pos: Vector3) -> int:
	return _nearest_matching_cell(pos, func(i: int) -> bool: return not soil_filled[i])

## Used by SeedItem/FarmProduceItem.on_use() (and, going forward, NPC
## PLANT_SEED jobs).
func nearest_open_plantable_cell_to(pos: Vector3) -> int:
	return _nearest_matching_cell(pos, func(i: int) -> bool: return soil_filled[i] and planted_type[i] == "")

## Used by on_interact()/get_interact_prompt()/get_prompt_world_pos() below
## (bare-handed E) — resolves the single cell that this E-press addresses,
## via the "player" group lookup convention used elsewhere in this file
## (_show_error() looks up "hud" the same way). Falls back to cell 0 if the
## player node can't be found for any reason.
func _nearest_cell_to_player() -> int:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return nearest_cell_to((player as Node3D).global_position)
	return 0

# ─── Interaction ──────────────────────────────────────────────────────────────
## Bare-handed E only — InteractionSystem routes here when held_item == null.
## Polish Plan Group 0 item 19: FarmPlant has no interactability of its own
## anymore — this is now the single E-press entry point for the whole tray.
## Aug 2026 per-cell interaction pass — bare-handed E now always addresses
## the ONE cell nearest the player (_nearest_cell_to_player()), never "any
## cell"/"every ready cell". A double tray reads as two independent 1×1
## units: standing closer to the left cell only ever fills/harvests the
## left cell, even if the right cell also needs soil or is also ready.
func get_interact_prompt() -> String:
	var idx: int = _nearest_cell_to_player()
	if not soil_filled[idx]:
		return "[E] Fill with Soil"
	var plant: FarmPlant = plant_refs[idx]
	if plant != null and is_instance_valid(plant) and plant.is_ready():
		return "[E] Harvest"
	return "[E] Tray Info"

func on_interact() -> void:
	var idx: int = _nearest_cell_to_player()
	if not soil_filled[idx]:
		_show_error("Tray needs soil")
		return

	## Harvest only the nearest cell's plant, one cell per E-press (Aug
	## 2026 per-cell interaction pass — was "every ready cell in the tray
	## at once"). If the player wants both cells of a double tray
	## harvested, that's two separate E-presses, one per side.
	var plant: FarmPlant = plant_refs[idx]
	if plant != null and is_instance_valid(plant) and plant.is_ready():
		plant.harvest()
		return

	if _tray_ui == null or not is_instance_valid(_tray_ui):
		var ui_script: GDScript = load("res://scripts/ui/farming/FarmingTrayUI.gd")
		if ui_script == null:
			push_warning("FarmingTray: FarmingTrayUI.gd not found")
			return
		_tray_ui = CanvasLayer.new()
		_tray_ui.set_script(ui_script)
		_tray_ui.name = "FarmingTrayUI"
		get_tree().get_root().add_child(_tray_ui)
		if _tray_ui.has_signal("closed"):
			_tray_ui.closed.connect(_on_ui_closed)

	if _tray_ui.has_method("open"):
		_tray_ui.call("open", self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## A2 — custom prompt world position so bare-handed E prompt sits above
## the tray basin (single) or above the used side (double) instead of the
## tray's center. InteractionSystem calls this via has_method() duck-typing.
## Aug 2026 per-cell interaction pass — always anchors over whichever cell
## _nearest_cell_to_player() resolves to, replacing the old soil-count-based
## heuristic. This keeps the prompt, the prompt's world position, and
## on_interact()'s actual target in permanent agreement (all three now call
## the same resolution function).
func get_prompt_world_pos() -> Vector3:
	var idx: int = _nearest_cell_to_player()
	return global_position + Vector3(_cell_local_x(idx), BASIN_TOP_Y, 0.0)

## Same lookup path WaterPipeDrawMode._show_error() uses — HUD's
## `inventory_hud` @onready child, InventoryHUD.show_error_message() convention
## (see HUD.gd). This is a standalone world item with no injected hud ref, so
## it looks the HUD node up via the "hud" group instead.
func _show_error(text: String) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and "inventory_hud" in hud:
		var ihud: Node = hud.get("inventory_hud")
		if ihud != null and ihud.has_method("show_error_message"):
			ihud.show_error_message(text)
			return
	push_warning("[FarmingTray] " + text)

# ─── Model (procedural — no GLB, matches GeneratorObject/WaterPurifier convention) ──
static func build_ghost_mesh(cell_count: int = 1) -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.90, BASIN_TOP_Y, 0.90) if cell_count == 1 else Vector3(1.90, BASIN_TOP_Y, 0.96)
	return box

func _build_mesh() -> void:
	var footprint_x: float = 0.90 if cell_count == 1 else 1.90
	var footprint_z: float = 0.90

	var leg_mat: StandardMaterial3D = StandardMaterial3D.new()
	leg_mat.albedo_color = COLOR_LEG
	leg_mat.metallic = 0.30
	leg_mat.roughness = 0.70

	## 4 legs at the footprint's corners.
	var leg_positions: Array[Vector2] = [
		Vector2(-footprint_x * 0.5 + 0.05, -footprint_z * 0.5 + 0.05),
		Vector2( footprint_x * 0.5 - 0.05, -footprint_z * 0.5 + 0.05),
		Vector2(-footprint_x * 0.5 + 0.05,  footprint_z * 0.5 - 0.05),
		Vector2( footprint_x * 0.5 - 0.05,  footprint_z * 0.5 - 0.05),
	]
	for p: Vector2 in leg_positions:
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.03
		leg_mesh.bottom_radius = 0.03
		leg_mesh.height = LEG_HEIGHT
		leg_mesh.radial_segments = 8
		leg_mi.mesh = leg_mesh
		leg_mi.position = Vector3(p.x, LEG_HEIGHT * 0.5, p.y)
		leg_mi.set_surface_override_material(0, leg_mat)
		add_child(leg_mi)

	## Basin floor — bare grey/metal, empty state.
	var basin_mat: StandardMaterial3D = StandardMaterial3D.new()
	basin_mat.albedo_color = COLOR_BASIN
	basin_mat.metallic = 0.25
	basin_mat.roughness = 0.75

	var floor_mi:   MeshInstance3D = MeshInstance3D.new()
	var floor_mesh: BoxMesh        = BoxMesh.new()
	floor_mesh.size = Vector3(footprint_x - 0.06, 0.05, footprint_z - 0.06)
	floor_mi.mesh   = floor_mesh
	floor_mi.position = Vector3(0.0, LEG_HEIGHT, 0.0)
	floor_mi.set_surface_override_material(0, basin_mat)
	add_child(floor_mi)
	floor_mi.create_trimesh_collision()
	for child in floor_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## 4 thin wall panels around the basin perimeter — shallow open-top box,
	## like a planter box.
	var wall_positions: Array = [
		{ "pos": Vector3(0.0, LEG_HEIGHT + BASIN_WALL_H * 0.5, -footprint_z * 0.5 + 0.02), "size": Vector3(footprint_x, BASIN_WALL_H, 0.03) },
		{ "pos": Vector3(0.0, LEG_HEIGHT + BASIN_WALL_H * 0.5,  footprint_z * 0.5 - 0.02), "size": Vector3(footprint_x, BASIN_WALL_H, 0.03) },
		{ "pos": Vector3(-footprint_x * 0.5 + 0.02, LEG_HEIGHT + BASIN_WALL_H * 0.5, 0.0), "size": Vector3(0.03, BASIN_WALL_H, footprint_z) },
		{ "pos": Vector3( footprint_x * 0.5 - 0.02, LEG_HEIGHT + BASIN_WALL_H * 0.5, 0.0), "size": Vector3(0.03, BASIN_WALL_H, footprint_z) },
	]
	for w: Dictionary in wall_positions:
		var wall_mi:   MeshInstance3D = MeshInstance3D.new()
		var wall_mesh: BoxMesh        = BoxMesh.new()
		wall_mesh.size = w["size"]
		wall_mi.mesh   = wall_mesh
		wall_mi.position = w["pos"]
		wall_mi.set_surface_override_material(0, basin_mat)
		add_child(wall_mi)

	## Middle divider for the double tray — a thin wall down the seam.
	if cell_count == 2:
		var div_mi:   MeshInstance3D = MeshInstance3D.new()
		var div_mesh: BoxMesh        = BoxMesh.new()
		div_mesh.size = Vector3(0.03, BASIN_WALL_H, footprint_z)
		div_mi.mesh   = div_mesh
		div_mi.position = Vector3(0.0, LEG_HEIGHT + BASIN_WALL_H * 0.5, 0.0)
		div_mi.set_surface_override_material(0, basin_mat)
		add_child(div_mi)

## Toggles the nearest-valid-target highlight (Group 5 item 12). Idempotent —
## safe to call every frame with the same value from the held item's
## _physics_process.
func set_target_highlighted(active: bool) -> void:
	if active:
		if _highlight_mi != null:
			return   ## already on
		var footprint_x: float = 0.90 if cell_count == 1 else 1.90
		var footprint_z: float = 0.90

		_highlight_mi = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(footprint_x + 0.10, footprint_z + 0.10)
		_highlight_mi.mesh = quad

		_highlight_mat = StandardMaterial3D.new()
		_highlight_mat.albedo_color  = HIGHLIGHT_COLOR
		_highlight_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_mat.no_depth_test = true
		_highlight_mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
		_highlight_mi.set_surface_override_material(0, _highlight_mat)
		_highlight_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   ## lay flat, quad defaults to facing +Z

		add_child(_highlight_mi)
		_highlight_mi.position = Vector3(0.0, LEG_HEIGHT + BASIN_WALL_H + 0.02, 0.0)

		_highlight_tween = create_tween()
		_highlight_tween.set_loops()
		_highlight_tween.set_trans(Tween.TRANS_SINE)
		_highlight_tween.tween_property(_highlight_mat, "albedo_color:a", HIGHLIGHT_PULSE_ALPHA_HIGH, HIGHLIGHT_PULSE_PERIOD * 0.5)
		_highlight_tween.tween_property(_highlight_mat, "albedo_color:a", HIGHLIGHT_PULSE_ALPHA_LOW, HIGHLIGHT_PULSE_PERIOD * 0.5)
	else:
		if _highlight_tween != null and _highlight_tween.is_valid():
			_highlight_tween.kill()
		_highlight_tween = null
		if _highlight_mi != null and is_instance_valid(_highlight_mi):
			_highlight_mi.queue_free()
		_highlight_mi  = null
		_highlight_mat = null

## Soil-filled state (plan §5.2): a second, slightly-inset BoxMesh sits inside
## the basin at roughly half the basin's depth, dark brown — only exists once
## soil is present (swapped in/out on fill, not just a recolor).
func _refresh_soil_visual(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	if _soil_mesh_instances[cell_index] != null:
		return   ## already filled — no double-fill possible per the state model

	var cell_w: float = (0.90 if cell_count == 1 else 1.90 / float(cell_count)) - 0.10
	var cell_z: float = 0.90 - 0.10

	var soil_mat: StandardMaterial3D = StandardMaterial3D.new()
	soil_mat.albedo_color = COLOR_SOIL
	soil_mat.roughness    = 0.95

	var soil_mi:   MeshInstance3D = MeshInstance3D.new()
	var soil_mesh: BoxMesh        = BoxMesh.new()
	soil_mesh.size = Vector3(cell_w, BASIN_WALL_H * 0.5, cell_z)
	soil_mi.mesh   = soil_mesh
	soil_mi.position = Vector3(_cell_local_x(cell_index), LEG_HEIGHT + BASIN_WALL_H * 0.25, 0.0)
	soil_mi.set_surface_override_material(0, soil_mat)
	add_child(soil_mi)
	_soil_mesh_instances[cell_index] = soil_mi
