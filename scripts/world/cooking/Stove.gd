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

const BODY_TOP_PLATE_H: float = 0.035
const BODY_FOOT_H: float = 0.06

const COLOR_BODY:      Color = Color(0.29, 0.30, 0.31, 1.0)
const COLOR_BODY_WEAR: Color = Color(0.36, 0.37, 0.38, 1.0)
const COLOR_BURNER:    Color = Color(0.06, 0.06, 0.06, 1.0)
const COLOR_LIGHT_ON:  Color = Color(0.30, 1.00, 0.40, 1.0)   ## green, matches HeavyConsumerTest's COLOR_ON
const COLOR_LIGHT_OFF: Color = Color(0.25, 0.05, 0.05, 1.0)   ## dark red / unlit

## Local position (relative to Stove root) where a placed Cooking Pot sits,
## centered on top of the burner. = BOX_SIZE.y + BURNER_HEIGHT.
const POT_LOCAL_POS: Vector3 = Vector3(0.0, 0.58, 0.0)

# ─── State ────────────────────────────────────────────────────────────────────
var _pm_node_key: String = ""
var powered_on:   bool   = false   ## Manual toggle state — independent of pot presence
var _is_shed:     bool   = false   ## Grid load-shed state
var _grid_connected: bool = false  ## True only when set_powered(true) has fired — i.e. wired with a live path to a generator
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
	_grid_connected = on
	if on:
		_is_shed = false
	elif powered_on:
		## Lost our wire connection (or grid path) while switched on — force
		## off. This is the "auto-disconnect" behavior: powered_on cannot
		## be true while _grid_connected is false. _refresh_cooking_state()
		## already handles stopping the 200W draw, and CookingPot's existing
		## decay logic (Part 3/G) already handles ticking cook progress back
		## down since is_cooking() will go false the instant powered_on does.
		powered_on = false
		_refresh_cooking_state()
		_refresh_indicator()

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
	if not powered_on and not _grid_connected:
		## Can't switch on without a live wire connection.
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Stove not connected to power")
		return
	powered_on = not powered_on
	_refresh_cooking_state()
	_refresh_indicator()

## If our pot has a dish ready, show ITS prompt instead of the toggle text
## — so whichever of {Stove, Pot} the nearby-interactable scan happens to
## pick as "closest", the displayed text always matches what [E] will
## actually do (InteractionSystem's take-dish check runs before the
## generic fallback regardless of which one is displayed — see Part G4).
func get_interact_prompt() -> String:
	if pot_ref != null and pot_ref.has_method("is_dish_ready") and pot_ref.is_dish_ready():
		return pot_ref.get_interact_prompt()
	if not powered_on and not _grid_connected:
		return "Stove Not Connected"
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
## "Cooking" = powered_on AND a pot is present AND that pot has ≥1 item in
## it. An empty pot on a powered-on stove draws nothing and never
## progresses — there's nothing to cook. (Once a dish finishes, the pot's
## slots are cleared — see CookingPot._finish_cooking() — so is_cooking()
## naturally goes false again the instant the dish is ready, and the stove
## stops drawing power until either the dish is taken and new items added,
## or the ready dish is served.)
func _refresh_cooking_state() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		pm.set_consumer_active(str(get_instance_id()), is_cooking())

## "Cooking" = powered_on AND a pot is present AND that pot has ≥1 item in
## it. An empty pot on a powered-on stove draws nothing and never
## progresses — there's nothing to cook. (Once a dish finishes, the pot's
## slots are cleared — see CookingPot._finish_cooking() — so is_cooking()
## naturally goes false again the instant the dish is ready, and the stove
## stops drawing power until either the dish is taken and new items added,
## or the ready dish is served.)
func is_cooking() -> bool:
	if not powered_on or pot_ref == null:
		return false
	if not pot_ref.has_method("count_filled"):
		return false
	return pot_ref.count_filled() > 0


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
	## Main body
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = BOX_SIZE
	body_mi.mesh   = body_mesh
	body_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.88
	body_mat.metallic     = 0.30
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)

	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Slightly lighter top plate for worn enamel/steel variation
	var top_plate_mi: MeshInstance3D = MeshInstance3D.new()
	var top_plate_mesh: BoxMesh = BoxMesh.new()
	top_plate_mesh.size = Vector3(BOX_SIZE.x - 0.06, BODY_TOP_PLATE_H, BOX_SIZE.z - 0.06)
	top_plate_mi.mesh = top_plate_mesh
	top_plate_mi.position = Vector3(0.0, BOX_SIZE.y - BODY_TOP_PLATE_H * 0.5 - 0.005, 0.0)
	var top_plate_mat: StandardMaterial3D = StandardMaterial3D.new()
	top_plate_mat.albedo_color = COLOR_BODY_WEAR
	top_plate_mat.roughness = 0.84
	top_plate_mat.metallic = 0.38
	top_plate_mi.set_surface_override_material(0, top_plate_mat)
	add_child(top_plate_mi)

	## Four short feet so the body does not read like a floating cube
	var foot_mat: StandardMaterial3D = StandardMaterial3D.new()
	foot_mat.albedo_color = Color(0.18, 0.18, 0.19, 1.0)
	foot_mat.roughness = 0.80
	foot_mat.metallic = 0.35
	var foot_positions: Array[Vector3] = [
		Vector3(-0.34, BODY_FOOT_H * 0.5, -0.34),
		Vector3( 0.34, BODY_FOOT_H * 0.5, -0.34),
		Vector3(-0.34, BODY_FOOT_H * 0.5,  0.34),
		Vector3( 0.34, BODY_FOOT_H * 0.5,  0.34),
	]
	for p: Vector3 in foot_positions:
		var foot_mi: MeshInstance3D = MeshInstance3D.new()
		var foot_mesh: BoxMesh = BoxMesh.new()
		foot_mesh.size = Vector3(0.07, BODY_FOOT_H, 0.07)
		foot_mi.mesh = foot_mesh
		foot_mi.position = p
		foot_mi.set_surface_override_material(0, foot_mat)
		add_child(foot_mi)

	## Burner ring assembly — cast-iron style ring with supports
	var burner_mat: StandardMaterial3D = StandardMaterial3D.new()
	burner_mat.albedo_color = COLOR_BURNER
	burner_mat.roughness    = 0.94
	burner_mat.metallic     = 0.06

	var ring_outer_r: float = BURNER_RADIUS * 0.86
	var ring_inner_r: float = BURNER_RADIUS * 0.56
	var ring_major: float = (ring_outer_r + ring_inner_r) * 0.5
	var ring_minor: float = (ring_outer_r - ring_inner_r) * 0.5
	var ring_y: float = BOX_SIZE.y + 0.018

	var burner_ring_mi: MeshInstance3D = MeshInstance3D.new()
	var burner_ring_mesh: TorusMesh = TorusMesh.new()
	burner_ring_mesh.inner_radius = ring_major - ring_minor
	burner_ring_mesh.outer_radius = ring_major + ring_minor
	burner_ring_mesh.rings = 30
	burner_ring_mesh.ring_segments = 14
	burner_ring_mi.mesh = burner_ring_mesh
	burner_ring_mi.position = Vector3(0.0, ring_y, 0.0)
	burner_ring_mi.set_surface_override_material(0, burner_mat)
	add_child(burner_ring_mi)

	var burner_inner_ring_mi: MeshInstance3D = MeshInstance3D.new()
	var burner_inner_ring_mesh: TorusMesh = TorusMesh.new()
	burner_inner_ring_mesh.inner_radius = BURNER_RADIUS * 0.24
	burner_inner_ring_mesh.outer_radius = BURNER_RADIUS * 0.31
	burner_inner_ring_mesh.rings = 24
	burner_inner_ring_mesh.ring_segments = 10
	burner_inner_ring_mi.mesh = burner_inner_ring_mesh
	burner_inner_ring_mi.position = Vector3(0.0, ring_y - 0.002, 0.0)
	burner_inner_ring_mi.set_surface_override_material(0, burner_mat)
	add_child(burner_inner_ring_mi)

	var spoke_len: float = BURNER_RADIUS * 0.28
	var spoke_w: float = 0.05
	var spoke_h: float = 0.024
	for i: int in range(4):
		var ang: float = deg_to_rad(45.0 + float(i) * 90.0)
		var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
		var spoke_mi: MeshInstance3D = MeshInstance3D.new()
		var spoke_mesh: BoxMesh = BoxMesh.new()
		spoke_mesh.size = Vector3(spoke_len, spoke_h, spoke_w)
		spoke_mi.mesh = spoke_mesh
		spoke_mi.position = Vector3(dir.x * (BURNER_RADIUS * 0.16), ring_y - 0.001, dir.z * (BURNER_RADIUS * 0.16))
		spoke_mi.rotation_degrees = Vector3(0.0, -rad_to_deg(ang), 0.0)
		spoke_mi.set_surface_override_material(0, burner_mat)
		add_child(spoke_mi)

	## Burner base disc below the ring
	var burner_base_mi: MeshInstance3D = MeshInstance3D.new()
	var burner_base_mesh: CylinderMesh = CylinderMesh.new()
	burner_base_mesh.top_radius = BURNER_RADIUS * 0.58
	burner_base_mesh.bottom_radius = BURNER_RADIUS * 0.58
	burner_base_mesh.height = 0.016
	burner_base_mesh.radial_segments = 20
	burner_base_mi.mesh = burner_base_mesh
	burner_base_mi.position = Vector3(0.0, BOX_SIZE.y + 0.008, 0.0)
	burner_base_mi.set_surface_override_material(0, burner_mat)
	add_child(burner_base_mi)

	## Front control knob
	var knob_mi: MeshInstance3D = MeshInstance3D.new()
	var knob_mesh: CylinderMesh = CylinderMesh.new()
	knob_mesh.top_radius = 0.05
	knob_mesh.bottom_radius = 0.05
	knob_mesh.height = 0.04
	knob_mesh.radial_segments = 16
	knob_mi.mesh = knob_mesh
	knob_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	knob_mi.position = Vector3(0.0, BOX_SIZE.y * 0.52, BOX_SIZE.z * 0.5 + 0.03)
	var knob_mat: StandardMaterial3D = StandardMaterial3D.new()
	knob_mat.albedo_color = Color(0.13, 0.13, 0.14, 1.0)
	knob_mat.roughness = 0.72
	knob_mat.metallic = 0.30
	knob_mi.set_surface_override_material(0, knob_mat)
	add_child(knob_mi)

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
