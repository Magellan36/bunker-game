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

## Demand/priority (Jul 2026, WaterSolver groundwork) — exported rather than
## hardcoded specifically so different playtest scenarios can be set up by
## just changing Inspector values on placed instances, no code changes
## needed to verify WaterSolver.gd against different configurations. Same
## 1-5 tier convention as the power system (1 = highest priority / served
## first, 5 = lowest / starved first when the hookup is oversubscribed).
@export var priority: int = 3
@export var fixed_demand_mL_per_day: float = 1000.0

## How often to re-check connectivity — rudimentary polling is enough for a
## test/debug device with no real gameplay behind it (see file header).
const CHECK_INTERVAL_SECS: float = 1.0

var _node_key: String = ""
var _state_label: Label3D = null
var _check_timer: float = 0.0

## Info panel (Step 2, July 2026) — lazy-instantiated, reused across opens,
## same lifecycle pattern as PowerTerminal._terminal_ui / WaterHookup._info_ui.
var _info_ui: CanvasLayer = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()
	_build_label()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	if _info_ui != null and is_instance_valid(_info_ui):
		_info_ui.queue_free()
		_info_ui = null
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
	_node_key = wm.register_node(global_position + Vector3(0.0, BOX_SIZE.y, 0.0), "endpoint", self)
	_refresh_connectivity()

## WaterSolver.gd's duck-typed demand contract (see WaterGraph._water_nodes'
## own comment) — a fixed, always-on demand for this test/debug device.
func get_current_demand_mL_per_day() -> float:
	return fixed_demand_mL_per_day

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
	return "[E] Check Sink"

## NOTE: does NOT toggle open/closed — mirrors GeneratorObject.on_interact()'s
## simpler "always (re)open" pattern (see WaterHookup.on_interact()'s own
## comment for why this is safe with WaterInfoUI's own E/Escape-to-close).
func on_interact() -> void:
	if _info_ui == null or not is_instance_valid(_info_ui):
		var ui_script: GDScript = load("res://scripts/ui/water/WaterInfoUI.gd")
		if ui_script == null:
			push_warning("WaterTestSink: WaterInfoUI.gd not found")
			return
		_info_ui = CanvasLayer.new()
		_info_ui.set_script(ui_script)
		_info_ui.name = "WaterInfoUI"
		get_tree().get_root().add_child(_info_ui)
		if _info_ui.has_signal("closed"):
			_info_ui.closed.connect(_on_ui_closed)

	if _info_ui.has_method("open"):
		_info_ui.open("Water Test Sink", "sink", self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Public accessor for this sink's WaterGraph node key — needed by
## WaterManager's flow-split trace-back and by WaterInfoUI (Step 2, July 2026).
func get_node_key() -> String:
	return _node_key

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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
