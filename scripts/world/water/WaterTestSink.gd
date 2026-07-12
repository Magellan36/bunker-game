extends StaticBody3D
class_name WaterTestSink
## WaterTestSink.gd
## Rudimentary test endpoint — mirrors HeavyConsumerTest.gd's role in the
## power system. No real gameplay function; its only job is to prove the
## plumbing works. TILE_WATER_SINK in BuildModeController, price $0.
##
## ACCEPTANCE TEST FOR THIS WHOLE PHASE: place a hookup, route a pipe run
## (through at least one corner) to a test sink, and confirm it reports
## CONNECTED. If it does, the graph/placement system works end to end.
##
## On placement it registers itself as a WaterGraph node (role "endpoint") so
## WaterManager.is_reachable_from_hookup() can BFS to it — but does NOT
## register into the pipe run automatically; the player must route a pipe to
## it with WaterPipeDrawMode (the sink is just a "start/end point" the tool
## can snap to, same as any other pipe_joint/corner node, once a nontrivial
## Phase 2 gives it real graph reachability wiring). For THIS phase, connectivity
## is checked once on a periodic timer (rudimentary, per the plan — a color
## change / debug print is enough at this stage).

const BOX_SIZE: Vector3 = Vector3(0.35, 0.30, 0.35)
const COLOR_BODY: Color = Color(0.30, 0.32, 0.34, 1.0)
const COLOR_CONNECTED:     Color = Color(0.30, 1.00, 0.40, 1.0)   ## green
const COLOR_NOT_CONNECTED: Color = Color(1.00, 0.28, 0.18, 1.0)   ## red

## How often to re-check connectivity — rudimentary polling is enough for a
## test/debug device with no real gameplay behind it (see file header).
const CHECK_INTERVAL_SECS: float = 1.0

var _node_key: String = ""
var _state_label: Label3D = null
var _check_timer: float = 0.0

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()
	_build_label()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	if not _node_key.is_empty():
		wm.unregister_node(_node_key)

func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL_SECS:
		_check_timer = 0.0
		_refresh_connectivity()

func _register_deferred() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		push_warning("WaterTestSink: WaterManager not found — will always show NOT CONNECTED.")
		return
	## Registered at the TOP of the box, not its base — this is the actual
	## physical point a pipe connects to (see WaterPipeDrawMode's vertical-
	## drop-into-the-object logic, which compares a node's registered Y
	## against ceiling height to decide whether a final vertical segment is
	## needed; no per-device special-casing required as long as every
	## connectable device registers its node at its real connection point).
	_node_key = wm.register_node(global_position + Vector3(0.0, BOX_SIZE.y, 0.0), "endpoint")
	_refresh_connectivity()

func _refresh_connectivity() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null or _node_key.is_empty():
		_update_label(false)
		return
	## Registering an "endpoint" node alone doesn't create any pipe edges to
	## it — the player must route a pipe from the hookup TO this sink with
	## WaterPipeDrawMode, which will snap onto this node the same way it
	## snaps onto any other existing graph node — see
	## WaterPipeDrawMode._get_nearest_water_node_xz()/_resolve_destination().
	## Once a pipe edge reaches this node, BFS reports true.
	var connected: bool = wm.is_reachable_from_hookup(_node_key)
	_update_label(connected)

func get_interact_prompt() -> String:
	return "Water Test Sink"

func _build_mesh() -> void:
	var mi:   MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh        = BoxMesh.new()
	mesh.size = BOX_SIZE
	mi.mesh   = mesh
	mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_BODY
	mat.roughness    = 0.75
	mat.metallic     = 0.20
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	mi.create_trimesh_collision()
	for child in mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

func _build_label() -> void:
	var lbl: Label3D = Label3D.new()
	lbl.font_size     = 36
	lbl.pixel_size    = 0.0015
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.double_sided  = true
	lbl.outline_size  = 5
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.90)
	lbl.position      = Vector3(0.0, BOX_SIZE.y + 0.30, 0.0)
	lbl.text          = "○  NOT CONNECTED"
	lbl.modulate      = COLOR_NOT_CONNECTED
	add_child(lbl)
	_state_label = lbl

func _update_label(connected: bool) -> void:
	if _state_label == null:
		return
	if connected:
		_state_label.text     = "●  CONNECTED"
		_state_label.modulate = COLOR_CONNECTED
	else:
		_state_label.text     = "○  NOT CONNECTED"
		_state_label.modulate = COLOR_NOT_CONNECTED
