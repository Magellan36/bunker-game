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

var _node_key: String = ""
var _water_fraction_cached: float = 0.0
var _connected_cached: bool = false

var _soil_mesh_instances: Array = []   ## one per cell, null until filled
var _tray_ui: CanvasLayer = null

const REPLACE_RANGE: float = 2.5   ## Same convention as PurifierFilterItem.REPLACE_RANGE

func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	soil_filled.resize(cell_count)
	planted_type.resize(cell_count)
	plant_refs.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		_soil_mesh_instances[i] = null

	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("farming_tray")
	_build_mesh()
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
	var edge_x: float = 0.45 if cell_count == 1 else 0.95
	_node_key = wm.register_node(global_position + Vector3(edge_x, BASIN_TOP_Y, 0.0), "endpoint", self)

func _process(_delta: float) -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null or _node_key.is_empty():
		_water_fraction_cached = 0.0
		_connected_cached = false
		return
	var info: Dictionary = wm.get_received_rate_mL(_node_key)
	_connected_cached = bool(info.get("connected", false))
	if not _connected_cached:
		_water_fraction_cached = 0.0
		return
	var received_mL_per_day: float = float(info.get("mL_per_day", 0.0))
	var demand: float = get_current_demand_mL_per_day()
	_water_fraction_cached = clampf(received_mL_per_day / demand, 0.0, 1.0) if demand > 0.0 else 0.0

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

## Fills the first unsoiled cell. Returns true if a cell was filled.
func fill_first_open_soil_cell() -> bool:
	for i: int in range(cell_count):
		if not soil_filled[i]:
			soil_filled[i] = true
			_refresh_soil_visual(i)
			return true
	return false

## Plants into the first open (soiled, unplanted) cell. Returns true on success.
func plant_first_open_cell(plant_type: String) -> bool:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			planted_type[i] = plant_type
			var plant: FarmPlant = FarmPlant.new()
			add_child(plant)
			plant.setup(self, i, plant_type)
			plant.position = Vector3(_cell_local_x(i), SOIL_LAYER_Y, 0.0)
			plant_refs[i] = plant
			return true
	return false

## Called by FarmPlant on harvest/death — cell goes back to soil-filled/empty,
## ready to replant, no new soil bag needed (plan §5.3/§6.3).
func clear_cell(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= cell_count:
		return
	planted_type[cell_index] = ""
	plant_refs[cell_index]   = null

func _cell_local_x(cell_index: int) -> float:
	if cell_count == 1:
		return 0.0
	return -0.475 if cell_index == 0 else 0.475

# ─── Interaction ──────────────────────────────────────────────────────────────
## Bare-handed E only — InteractionSystem routes here when held_item == null.
func get_interact_prompt() -> String:
	if not is_fully_soiled():
		return "[E] Fill with Soil"
	return "[E] Tray Info"

func on_interact() -> void:
	if not is_fully_soiled():
		_show_error("Tray needs soil")
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
