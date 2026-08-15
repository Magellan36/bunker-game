extends PickupableItem
## FuelCan.gd
## Pickupable fuel container. Hold it near a generator and hold E to refuel continuously.
## Carries FUEL_UNITS_TOTAL = 100 PM-units of fuel.
## Continuous refuel: FUEL_RATE units/sec transferred while E is held near a generator.
## Cannot be stored in inventory slots (can_store() → false).

# ─── Config ───────────────────────────────────────────────────────────────────
const FUEL_UNITS_TOTAL: float = 100.0  ## Total fuel in a full can (PM units)
const FUEL_PER_POUR:    float =  25.0  ## PM units per legacy "pour" (badge display only)
const TOTAL_POURS:      int   =    4
const REFUEL_RANGE:     float =  2.5   ## Max distance to generator for refuelling

## Continuous refuel rate — PM-units transferred per real second.
## At 8.0 u/s a full can takes ~12.5 s to empty into a generator.
const FUEL_RATE: float = 8.0

## Shelf / inventory config (shelf_item_type used by shelving system)
var shelf_stack_limit: int    = 2
var shelf_item_type:   String = "fuel_can"

var _mesh: MeshInstance3D = null

# ─── State ───────────────────────────────────────────────────────────────────
var _fuel_remaining:   float  = FUEL_UNITS_TOTAL
var _is_empty:         bool   = false
var _player_in_range:  bool   = false

## Aug 2026 — Cleaning's generic trash convention (see JobBoard._is_trash_item()'s
## own comment). Same reasoning as FoodCan/WaterBottle — an empty can
## stays the same node, so this reads live state, not a one-time tag.
func is_trash() -> bool:
	return _is_empty

func _unfreeze_after_spawn() -> void:
	freeze = false

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("interactable")
	_mesh = get_node_or_null("Model/MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

# ─── Inventory gate ──────────────────────────────────────────────────────────
## Returning false blocks InteractionSystem from storing this item into a slot.
## Fuel cans must stay in the world — you carry them by hand only.
func can_store() -> bool:
	return false

# ─── Proximity callback ───────────────────────────────────────────────────────
## Called by InteractionSystem when player enters/exits the DetectArea.
func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Jerry Can"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Jerry Can (Empty)"
	var pct: int = int((_fuel_remaining / FUEL_UNITS_TOTAL) * 100.0)
	return "[F] Pick up  Jerry Can (%d%%)" % pct

func get_use_prompt() -> String:
	if _is_empty:
		return ""
	var gen: Node3D = _find_nearest_generator()
	if gen == null:
		return ""
	## Line 1 — action + live generator fuel%
	## Line 2 — this can's own remaining fuel%
	var can_pct: int = int((_fuel_remaining / FUEL_UNITS_TOTAL) * 100.0)
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		var gen_id: String  = str(gen.get_instance_id())
		var gen_fuel: float = pm.get_generator_fuel(gen_id)
		var gen_pct: int    = int(clampf(gen_fuel, 0.0, 100.0))
		return "[Hold E] Refuel Generator  —  %d%%\nFuel: %d%%" % [gen_pct, can_pct]
	return "[Hold E] Refuel Generator\nFuel: %d%%" % can_pct

# ─── Continuous refuel tick (called by InteractionSystem._process each frame) ─
## Transfers FUEL_RATE * delta units from this can into the nearest in-range
## generator. Called externally — InteractionSystem detects E-held + generator.
func refuel_tick(delta: float) -> void:
	if _is_empty:
		return

	var gen: Node3D = _find_nearest_generator()
	if gen == null:
		return

	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	var gen_id: String  = str(gen.get_instance_id())
	var current: float  = pm.get_generator_fuel(gen_id)

	if current >= 100.0:
		return   ## Generator already full — nothing to do this tick

	var transfer: float  = minf(FUEL_RATE * delta, 100.0 - current)
	transfer             = minf(transfer, _fuel_remaining)

	if transfer <= 0.0:
		return

	pm.set_generator_fuel(gen_id, current + transfer)

	_fuel_remaining -= transfer
	_fuel_remaining  = maxf(0.0, _fuel_remaining)

	charge_changed.emit()

	if _fuel_remaining <= 0.0:
		_become_empty()

# ─── Legacy on_use — kept so existing callers don't break, but does nothing. ──
## Continuous refuel via refuel_tick() supersedes this.
func on_use() -> void:
	pass   ## No-op: InteractionSystem uses refuel_tick() instead

func _find_nearest_generator() -> Node3D:
	var best_node: Node3D = null
	var best_dist: float  = REFUEL_RANGE
	for node: Node in get_tree().get_nodes_in_group("generator"):
		if node is Node3D:
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best_node = node as Node3D
	return best_node

# ─── Empty state ──────────────────────────────────────────────────────────────
func _become_empty() -> void:
	_is_empty       = true
	_fuel_remaining = 0.0

# ─── Mesh ─────────────────────────────────────────────────────────────────────

## Procedural jerry can model — red body, dark grey handle, metallic cap.
## Built from BoxMesh + CylinderMesh primitives.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.17, 0.0)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.30, 0.35, 0.20, 1.0)
	body_mat.roughness    = 0.55
	body_mat.metallic     = 0.15

	var handle_mat: StandardMaterial3D = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.30, 0.30, 0.30, 1.0)
	handle_mat.roughness    = 0.60
	handle_mat.metallic     = 0.30

	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.35, 0.35, 0.35, 1.0)
	cap_mat.roughness    = 0.40
	cap_mat.metallic     = 0.50

	var label_mat: StandardMaterial3D = StandardMaterial3D.new()
	label_mat.albedo_color = Color(0.90, 0.85, 0.70, 1.0)
	label_mat.roughness    = 0.80
	label_mat.metallic     = 0.0

	## Main body — rectangular tank.
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(0.24, 0.34, 0.14)
	body.position = Vector3(0.0, 0.0, 0.0)
	body.set_surface_override_material(0, body_mat)
	_mesh.add_child(body)

	## Handle — dark bar on top.
	var handle: MeshInstance3D = MeshInstance3D.new()
	handle.mesh = BoxMesh.new()
	(handle.mesh as BoxMesh).size = Vector3(0.10, 0.03, 0.04)
	handle.position = Vector3(0.0, 0.185, 0.0)
	handle.set_surface_override_material(0, handle_mat)
	_mesh.add_child(handle)

	## Handle supports — two thin vertical bars connecting handle to body.
	for sign_x: int in [-1, 1]:
		var support: MeshInstance3D = MeshInstance3D.new()
		support.mesh = BoxMesh.new()
		(support.mesh as BoxMesh).size = Vector3(0.02, 0.04, 0.03)
		support.position = Vector3(sign_x * 0.04, 0.16, 0.0)
		support.set_surface_override_material(0, handle_mat)
		_mesh.add_child(support)

	## Spout base — short cylinder on the right side.
	var spout: MeshInstance3D = MeshInstance3D.new()
	var spout_mesh: CylinderMesh = CylinderMesh.new()
	spout_mesh.top_radius    = 0.025
	spout_mesh.bottom_radius = 0.025
	spout_mesh.height        = 0.03
	spout.mesh = spout_mesh
	spout.position = Vector3(0.135, 0.10, 0.0)
	spout.rotation.z = PI / 2.0
	spout.set_surface_override_material(0, handle_mat)
	_mesh.add_child(spout)

	## Cap — slightly wider cylinder covering spout.
	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius    = 0.03
	cap_mesh.bottom_radius = 0.03
	cap_mesh.height        = 0.015
	cap.mesh = cap_mesh
	cap.position = Vector3(0.155, 0.10, 0.0)
	cap.rotation.z = PI / 2.0
	cap.set_surface_override_material(0, cap_mat)
	_mesh.add_child(cap)

	## Front label — thin flat box.
	var label: MeshInstance3D = MeshInstance3D.new()
	label.mesh = BoxMesh.new()
	(label.mesh as BoxMesh).size = Vector3(0.12, 0.14, 0.005)
	label.position = Vector3(0.0, -0.02, 0.073)
	label.set_surface_override_material(0, label_mat)
	_mesh.add_child(label)

	add_child(_mesh)
