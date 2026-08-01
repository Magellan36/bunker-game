extends StaticBody3D
class_name Stove
## Stove.gd
## Cooking System Part A/B. 1x1 floor-placed power consumer. Manual on/off
## toggle via [E] — independent of whether a Cooking Pot is present. Only
## actually draws its 200W while powered_on AND a pot is present ("cooking").
## Indicator light reflects powered_on ONLY (pot or no pot).
##
## Placement/registration mirrors HeavyConsumerTest.gd / GrowLight.gd exactly
## — see those files for the established convention this follows.

# ─── Config ───────────────────────────────────────────────────────────────────
const WATTS:    float   = 200.0
const BOX_SIZE: Vector3 = Vector3(0.85, 0.55, 0.85)   ## grey box body
const BURNER_RADIUS: float = 0.32
const BURNER_HEIGHT: float = 0.03

const COLOR_BODY:      Color = Color(0.35, 0.35, 0.36, 1.0)   ## basic grey
const COLOR_BURNER:    Color = Color(0.05, 0.05, 0.05, 1.0)   ## flat black circle
const COLOR_LIGHT_ON:  Color = Color(0.30, 1.00, 0.40, 1.0)   ## green, matches HeavyConsumerTest's COLOR_ON
const COLOR_LIGHT_OFF: Color = Color(0.25, 0.05, 0.05, 1.0)   ## dark red / unlit

## Local position (relative to Stove root) where a placed Cooking Pot sits,
## centered on top of the burner. = BOX_SIZE.y + BURNER_HEIGHT.
const POT_LOCAL_POS: Vector3 = Vector3(0.0, 0.58, 0.0)

# ─── State ────────────────────────────────────────────────────────────────────
var _pm_node_key: String = ""
var powered_on:   bool   = false   ## Manual toggle state — independent of pot presence
var _is_shed:     bool   = false   ## Grid load-shed state
var pot_ref:      Node   = null    ## The CookingPot currently resting on this stove, or null

var _indicator_mi:  MeshInstance3D     = null
var _indicator_mat: StandardMaterial3D = null

## Full-fidelity preview mode — set TRUE by BuildModeHUD's construct-tab
## preview code BEFORE add_child(). Same convention as every other build
## object in this project (see HeavyConsumerTest.gd's own comment on this
## field for the full explanation). MUST be set before add_child().
var _is_preview_only: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("stove")
	_build_fixture()
	set_powered(false)   ## Safety net — matches GrowLight's convention
	if _is_preview_only:
		return
	call_deferred("_register_deferred")


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _pm_node_key.is_empty():
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))


# ─── PowerManager registration (mirrors HeavyConsumerTest.gd exactly) ────────
func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("Stove: PowerManager not found — will never receive power.")
		return

	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	## Registered INACTIVE. The stove only actually draws power once
	## powered_on AND pot_ref are both true — see _refresh_cooking_state().
	pm.register_consumer(
		str(get_instance_id()),
		WATTS,
		self,
		"stove",
		1,        ## priority — appliance-tier, not life-support
		false)    ## NOT active from the start

	_auto_connect_to_nearby_wires(pm)


## Copied (pattern) from GrowLight._auto_connect_to_nearby_wires() — confirmed
## Aug 2026 that the Stove should auto-connect like every other consumer.
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
		var ac_eid: String = pm.register_wire_edge(_pm_node_key, best_key, null, true)
		pm.set_wire_edge_no_visual(ac_eid)


## Called by BuildModeController after a new wire node is placed nearby.
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


# ─── PowerManager callbacks (required interface) ──────────────────────────────
## The registered consumer is only EVER active while cooking (see
## _refresh_cooking_state), so `on` here is only ever true while
## powered_on AND pot_ref are both true. The indicator light is driven
## independently off `powered_on` directly — see _refresh_indicator().
func set_powered(on: bool) -> void:
	if on:
		_is_shed = false

func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on


# ─── Manual on/off toggle — [E] while NOT holding a Cooking Pot ──────────────
## Called generically by InteractionSystem._try_interact() (StaticBody3D +
## "interactable" group + on_interact() — zero InteractionSystem changes
## needed for this path). InteractionSystem's is_cookpot_container branch
## (see Part D) always intercepts E BEFORE this when the player is holding
## the pot and this stove is open, so by the time this runs it is always
## meant to simply toggle.
func on_interact() -> void:
	powered_on = not powered_on
	_refresh_cooking_state()
	_refresh_indicator()

func get_interact_prompt() -> String:
	return "[E] Turn Stove %s" % ("Off" if powered_on else "On")


# ─── Pot slot management (called by InteractionSystem, Part D) ──────────────
func has_open_slot() -> bool:
	return pot_ref == null

## Places `pot` on top of the burner. Caller is responsible for releasing it
## from the player's hand — this only handles the stove/pot side.
func try_place_pot(pot: Node) -> bool:
	if pot_ref != null:
		return false
	pot_ref = pot
	var old_parent: Node = pot.get_parent()
	if old_parent != null:
		old_parent.remove_child(pot)
	add_child(pot)
	pot.position = POT_LOCAL_POS
	pot.rotation = Vector3.ZERO
	if pot is RigidBody3D:
		var rb: RigidBody3D = pot as RigidBody3D
		rb.freeze           = true
		rb.freeze_mode      = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer  = 0
		rb.collision_mask   = 0
		rb.linear_velocity  = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	if "is_held" in pot:
		pot.is_held = false
	if pot.has_method("set_host_stove"):
		pot.set_host_stove(self)
	_refresh_cooking_state()
	return true

## Detaches the current pot, restores its physics, and returns it — caller
## (InteractionSystem's F-handler, Part D) then calls pot.pickup(hold_point)
## on it exactly like a normal world pickup. Returns null if no pot present.
func try_remove_pot() -> Node:
	if pot_ref == null:
		return null
	var pot: Node = pot_ref
	pot_ref = null
	var world_root: Node = get_tree().get_root()
	remove_child(pot)
	world_root.add_child(pot)
	pot.global_position = global_position + Vector3(0.0, POT_LOCAL_POS.y + 0.05, 0.0)
	if pot is RigidBody3D:
		var rb: RigidBody3D = pot as RigidBody3D
		rb.freeze          = false
		rb.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.gravity_scale   = 0.0
		rb.collision_layer = 2
		rb.collision_mask  = 1
	if pot.has_method("set_host_stove"):
		pot.set_host_stove(null)
	_refresh_cooking_state()
	return pot


# ─── Cooking-active / power-draw logic ────────────────────────────────────────
## "Cooking" = powered_on AND a pot is present. This is the ONLY condition
## under which the 200W is actually drawn.
func _refresh_cooking_state() -> void:
	var cooking: bool = powered_on and pot_ref != null
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		pm.set_consumer_active(str(get_instance_id()), cooking)

func is_cooking() -> bool:
	return powered_on and pot_ref != null


# ─── Indicator light — reflects powered_on ONLY ──────────────────────────────
func _refresh_indicator() -> void:
	if _indicator_mat == null:
		return
	var c: Color = COLOR_LIGHT_ON if powered_on else COLOR_LIGHT_OFF
	_indicator_mat.albedo_color = c
	_indicator_mat.emission     = c
	_indicator_mat.emission_energy_multiplier = 2.5 if powered_on else 0.0


# ─── Visual build ──────────────────────────────────────────────────────────
func _build_fixture() -> void:
	## Body — basic grey box
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = BOX_SIZE
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.75
	body_mat.metallic     = 0.15
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)

	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Burner — single flat black circle on top
	var burner_mi: MeshInstance3D = MeshInstance3D.new()
	var burner_mesh: CylinderMesh = CylinderMesh.new()
	burner_mesh.top_radius    = BURNER_RADIUS
	burner_mesh.bottom_radius = BURNER_RADIUS
	burner_mesh.height        = BURNER_HEIGHT
	burner_mi.mesh = burner_mesh
	burner_mi.position = Vector3(0.0, BOX_SIZE.y + BURNER_HEIGHT * 0.5, 0.0)
	var burner_mat: StandardMaterial3D = StandardMaterial3D.new()
	burner_mat.albedo_color = COLOR_BURNER
	burner_mat.roughness    = 0.55
	burner_mat.metallic     = 0.10
	burner_mi.set_surface_override_material(0, burner_mat)
	add_child(burner_mi)

	## Indicator light — small emissive sphere on the front face
	_indicator_mi = MeshInstance3D.new()
	var ind_mesh: SphereMesh = SphereMesh.new()
	ind_mesh.radius = 0.035
	ind_mesh.height = 0.07
	_indicator_mi.mesh = ind_mesh
	_indicator_mi.position = Vector3(0.0, BOX_SIZE.y * 0.75, BOX_SIZE.z * 0.5 + 0.02)
	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.albedo_color     = COLOR_LIGHT_OFF
	_indicator_mat.emission_enabled = true
	_indicator_mat.emission         = COLOR_LIGHT_OFF
	_indicator_mat.emission_energy_multiplier = 0.0
	_indicator_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_mi.set_surface_override_material(0, _indicator_mat)
	add_child(_indicator_mi)


## Side-effect-free ghost mesh for build-mode previews — same convention as
## HeavyConsumerTest.build_ghost_mesh(): no registration, no groups, no
## signals, just the plain mesh. Body box only (burner disc omitted from the
## ghost as a minor cosmetic simplification — GhostPreview only renders ONE
## mesh resource per tile).
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = BOX_SIZE
	return box