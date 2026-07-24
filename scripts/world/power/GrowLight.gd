extends StaticBody3D
class_name GrowLight
## GrowLight.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §3.2/§4. Lives in scripts/world/power/ (NOT
## scripts/world/farming/) — structurally this is a PowerManager consumer
## device exactly like WallLight/HeavyConsumerTest, not a farming-specific
## object. One script, two tiers via `tier` export (mirrors
## PurifierFilterItem's "one script, state param" convention rather than two
## near-duplicate classes).
##
## Registration/interaction shape copied from HeavyConsumerTest.gd (a plain
## StaticBody3D consumer that opens PowerPriorityUI directly on E — no
## PowerPriorityInteractable proxy needed, that proxy only exists for
## Node3D-without-a-body hosts like WallLight).
##
## Auto-connects to the nearest wire node within AUTO_CONNECT_RADIUS, same
## exact mechanism WallLight._auto_connect_to_nearby_wires() uses — a grow
## light placed near an existing wire run just works with no separate
## wire-drawing step.
##
## Growth contract read by FarmPlant.gd (plan §4, "pure XZ position match" —
## no parent/child relationship or registration handshake with any tray):
##   get_active_growth_speed() -> float   0.0 unpowered/shed, 0.5 normal, 1.0 pro

# ─── Debug ────────────────────────────────────────────────────────────────────
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Tier config ──────────────────────────────────────────────────────────────
@export var tier: String = "normal"   ## "normal" or "pro"

const TIER_WATTS: Dictionary = {
	"normal": 75.0,
	"pro":    100.0,
}
const TIER_GROWTH_SPEED: Dictionary = {
	"normal": 0.5,
	"pro":    1.0,
}
const TIER_TYPE_TAG: Dictionary = {
	"normal": "grow_light_normal",
	"pro":    "grow_light_pro",
}

# ─── Model geometry (§4.1) ────────────────────────────────────────────────────
const TUBE_LENGTH: float  = 0.62
const TUBE_RADIUS: float  = 0.035
const TUBE_SPACING: float = 0.22   ## gap between the 3 parallel tubes (Z axis)
const COVER_COLOR: Color  = Color(0.15, 0.15, 0.16, 1.0)

## Unshaded/emissive white tube material — matches the connectable-dot
## material's unshaded convention already used elsewhere in this codebase.
const TUBE_COLOR_ON:  Color = Color(1.0, 1.0, 0.98, 1.0)

## Shed (overloaded grid) state — reused VERBATIM from WallLight's own
## SHED_COLOR/SHED_ENERGY so a shed grow light reads consistently with every
## other shed device in the game.
const SHED_COLOR:  Color = Color(1.0, 0.45, 0.0, 1.0)
const SHED_ENERGY: float = 0.15

const TUBE_ENERGY_ON: float = 2.0

# ─── Power grid ───────────────────────────────────────────────────────────────
var power_priority: int = 3   ## Both tiers default to priority 3 (plan §3.1)

var _pm_node_key: String = ""
var _is_powered:  bool   = false
var _is_shed:     bool   = false

## Tube materials — one per tube so all 3 update together in set_powered()/set_shed().
var _tube_mats: Array[StandardMaterial3D] = []

## Lazily-created shared priority panel (PowerPriorityUI). Reused across opens.
var _prio_ui: CanvasLayer = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	tier = tier if TIER_WATTS.has(tier) else "normal"
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("grow_light")
	_build_fixture()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _pm_node_key.is_empty():
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))

# ─── PowerManager registration (mirrors WallLight's auto-connect exactly) ────
func _register_deferred() -> void:
	_register_with_power_manager()
	call_deferred("_auto_connect_deferred")

func _auto_connect_deferred() -> void:
	if _pm_node_key == "":
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		_auto_connect_to_nearby_wires(pm)

func _register_with_power_manager() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("GrowLight: PowerManager not found — will never receive power.")
		return

	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	pm.register_consumer(
		str(get_instance_id()),
		TIER_WATTS.get(tier, 75.0),
		self,
		TIER_TYPE_TAG.get(tier, "grow_light_normal"),
		power_priority,
		true)

	_auto_connect_to_nearby_wires(pm)

## Scans existing PM wire nodes and connects to the nearest one within
## AUTO_CONNECT_RADIUS — copied verbatim from WallLight._auto_connect_to_nearby_wires().
func _auto_connect_to_nearby_wires(pm: PowerManager) -> void:
	if _pm_node_key == "":
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	var my_pos: Vector3 = global_position

	var edge_endpoint_keys: Dictionary = {}
	var edges: Array[Dictionary] = pm.get_wire_edges()
	for ed: Dictionary in edges:
		var na: String = ed.get("node_a", "")
		var nb: String = ed.get("node_b", "")
		if not na.is_empty(): edge_endpoint_keys[na] = true
		if not nb.is_empty(): edge_endpoint_keys[nb] = true

	var best_key:  String = ""
	var best_dist: float  = AUTO_CONNECT_RADIUS + 0.001

	for pass_idx: int in range(2):
		for wn: Dictionary in pm.get_wire_nodes():
			var wn_key: String = wn.get("key", "")
			if wn_key == _pm_node_key:
				continue
			if wn.get("role", "joint") != "joint":
				continue
			if pass_idx == 0 and not edge_endpoint_keys.has(wn_key):
				continue
			var wn_pos: Vector3 = wn.get("pos", Vector3.ZERO)
			var dx: float = wn_pos.x - my_pos.x
			var dz: float = wn_pos.z - my_pos.z
			var dist: float = sqrt(dx * dx + dz * dz)
			if dist < best_dist:
				best_dist = dist
				best_key  = wn_key
		if best_key != "":
			break

	if best_key != "":
		_wdbg("[GROWLIGHT] auto-connect id=%d -> key=%s dist=%.3f" % [get_instance_id(), best_key, best_dist])
		var ac_eid: String = pm.register_wire_edge(_pm_node_key, best_key, null, true)
		pm.set_wire_edge_no_visual(ac_eid)

## Called by BuildModeController after a new wire node is placed (mirrors WallLight).
func notify_wire_placed(wn_key: String, wn_pos: Vector3) -> void:
	if _pm_node_key == "":
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	var dx: float = wn_pos.x - global_position.x
	var dz: float = wn_pos.z - global_position.z
	if sqrt(dx * dx + dz * dz) <= AUTO_CONNECT_RADIUS:
		var nw_eid: String = pm.register_wire_edge(_pm_node_key, wn_key, null, true)
		pm.set_wire_edge_no_visual(nw_eid)

# ─── PowerManager callbacks ───────────────────────────────────────────────────
func set_powered(on: bool) -> void:
	_is_powered = on
	if on:
		_is_shed = false
	_refresh_tubes()

func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on
	if shed_on:
		_is_powered = false
	_refresh_tubes()

func _refresh_tubes() -> void:
	var col: Color
	var energy: float
	if _is_powered:
		col    = TUBE_COLOR_ON
		energy = TUBE_ENERGY_ON
	elif _is_shed:
		col    = SHED_COLOR
		energy = SHED_ENERGY
	else:
		col    = SHED_COLOR
		energy = 0.0
	for mat: StandardMaterial3D in _tube_mats:
		mat.emission = col
		mat.emission_energy_multiplier = energy
		mat.albedo_color = col if energy > 0.0 else Color(0.25, 0.25, 0.26, 1.0)

## Growth contract read by FarmPlant.gd — see file header.
func get_active_growth_speed() -> float:
	if not _is_powered:
		return 0.0
	return TIER_GROWTH_SPEED.get(tier, 0.5)

# ─── Priority interaction (direct — StaticBody3D host, no proxy needed) ──────
func on_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _prio_ui == null or not is_instance_valid(_prio_ui):
		var ui_script: GDScript = load("res://scripts/ui/power/PowerPriorityUI.gd")
		if ui_script == null:
			push_warning("GrowLight: PowerPriorityUI.gd not found")
			return
		_prio_ui = CanvasLayer.new()
		_prio_ui.set_script(ui_script)
		_prio_ui.name = "PowerPriorityUI"
		get_tree().get_root().add_child(_prio_ui)
		if _prio_ui.has_signal("closed"):
			_prio_ui.closed.connect(_on_prio_closed)
		if _prio_ui.has_signal("priority_changed"):
			_prio_ui.priority_changed.connect(_on_prio_changed)

	var display_name: String = "Grow Light" if tier == "normal" else "Grow Light (Pro)"
	if _prio_ui.has_method("open"):
		_prio_ui.call("open", str(get_instance_id()), display_name, false)

func get_interact_prompt() -> String:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var prio: int = power_priority
	if pm != null:
		prio = pm.get_consumer_priority(str(get_instance_id()))
	var state: String = "Powered" if _is_powered else ("Shed" if _is_shed else "No Power")
	var label: String = "Grow Light" if tier == "normal" else "Grow Light (Pro)"
	return "[E] %s  —  Priority %d  (%s)" % [label, prio, state]

func _on_prio_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false

func _on_prio_changed(_id: String, value: int) -> void:
	power_priority = value

func _get_interaction_system() -> Node:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			for sub: Node in (child as Node3D).get_children():
				if sub is CharacterBody3D:
					for s2: Node in sub.get_children():
						if s2.get_script() != null and str(s2.get_script().resource_path).contains("InteractionSystem"):
							return s2
	return null

# ─── Model (procedural — no GLB, matches GeneratorObject/WaterPurifier convention) ──
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.70, 0.10, 0.70)
	return box

func _build_fixture() -> void:
	_tube_mats.clear()

	## 3 glowing tubes, lying on their sides (long axis horizontal along X),
	## equally spaced across the 1×1 footprint on the Z axis.
	for i: int in range(3):
		var tube_mi: MeshInstance3D = MeshInstance3D.new()
		var tube_mesh: CylinderMesh = CylinderMesh.new()
		tube_mesh.top_radius    = TUBE_RADIUS
		tube_mesh.bottom_radius = TUBE_RADIUS
		tube_mesh.height        = TUBE_LENGTH
		tube_mesh.radial_segments = 10
		tube_mi.mesh = tube_mesh
		## CylinderMesh's long axis is local Y by default — rotate 90° so it lies horizontal.
		tube_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		tube_mi.position = Vector3(0.0, 0.0, (i - 1) * TUBE_SPACING)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.albedo_color     = Color(0.25, 0.25, 0.26, 1.0)
		mat.emission         = SHED_COLOR
		mat.emission_energy_multiplier = 0.0
		tube_mi.set_surface_override_material(0, mat)
		add_child(tube_mi)
		_tube_mats.append(mat)

	## Dark grey cover — flat top plate + two thin side-wall panels dropping
	## down partway along the tubes' height, wrapping 2 of the 4 sides only
	## (leave the short ends open, matching a real shop-light reflector).
	var cover_mat: StandardMaterial3D = StandardMaterial3D.new()
	cover_mat.albedo_color = COVER_COLOR
	cover_mat.metallic     = 0.10
	cover_mat.roughness    = 0.80

	var top_mi:   MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh        = BoxMesh.new()
	top_mesh.size = Vector3(0.66, 0.03, 0.66)
	top_mi.mesh   = top_mesh
	top_mi.position = Vector3(0.0, TUBE_RADIUS + 0.05, 0.0)
	top_mi.set_surface_override_material(0, cover_mat)
	add_child(top_mi)

	for side: int in [-1, 1]:
		var side_mi:   MeshInstance3D = MeshInstance3D.new()
		var side_mesh: BoxMesh        = BoxMesh.new()
		side_mesh.size = Vector3(0.66, 0.10, 0.03)
		side_mi.mesh   = side_mesh
		side_mi.position = Vector3(0.0, 0.0, side * 0.33)
		side_mi.set_surface_override_material(0, cover_mat)
		add_child(side_mi)

	## No collision beyond the parent StaticBody3D itself needing a shape for
	## interaction proximity/raycast — add a slim invisible collider matching
	## the 1×1 footprint used by _tile_half_extents().
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.70, 0.20, 0.70)
	shape.shape = box
	add_child(shape)
