extends StaticBody3D
## HeavyConsumerTest.gd
## Simple 500 W test object for verifying overload → flicker → offline logic.
##
## HOW TO USE
##   1. Attach this script to a StaticBody3D node (or add a StaticBody3D to
##      your test scene and set this as its script).
##   2. Place it in the world — it will auto-register with PowerManager.
##   3. Wire it up in Build Mode just like any other consumer.
##   4. When wired to a generator that can't handle the extra 500 W load
##      on top of other consumers, the overload logic kicks in.
##      Since "heavy_appliance" is NOT in the LIGHT_TYPES shed list,
##      no shedding occurs — the grid immediately begins the flicker→offline
##      sequence.
##
## POWER STATE
##   A Label3D above the box shows the current power state in large text:
##     [●  ON]   — powered, green
##     [○  OFF]  — unpowered, red

# ─── Config ───────────────────────────────────────────────────────────────────
const WATTS:    float = 500.0
const BOX_SIZE: Vector3 = Vector3(0.6, 0.6, 0.6)

## Box colour — dark industrial grey with a slight warm tint
const COLOR_BODY: Color = Color(0.22, 0.20, 0.18, 1.0)

## Label colours
const COLOR_ON:  Color = Color(0.30, 1.00, 0.40, 1.0)
const COLOR_OFF: Color = Color(1.00, 0.28, 0.18, 1.0)

# ─── State ────────────────────────────────────────────────────────────────────
var _pm_node_key:  String = ""
var _powered:      bool   = false
var _load_active:  bool   = true   ## Whether this consumer is currently drawing power

## Label3D floating above the box to show ON/OFF state.
var _state_label: Label3D = null

## True when the grid load-sheds this device (connected but cut).
var _is_shed: bool = false

## Lazily-created shared priority panel (PowerPriorityUI). Reused across opens.
var _prio_ui: CanvasLayer = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()
	_build_label()
	call_deferred("_register_deferred")


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _pm_node_key.is_empty():
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))


# ─── PowerManager registration ────────────────────────────────────────────────
func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("HeavyConsumerTest: PowerManager not found — will have no power.")
		return

	## Wire node first — this is the graph snap point.
	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	## Consumer second. Type = "heavy_appliance" — NOT in LIGHT_TYPES,
	## so it is never shed. Priority 2 = important but not life-support.
	pm.register_consumer(
		str(get_instance_id()),
		WATTS,
		self,
		"heavy_appliance",
		2,       ## priority
		true)    ## active from the start


# ─── Required interface — called by PowerManager ──────────────────────────────
func set_powered(on: bool) -> void:
	_powered = on
	## A real power state (powered or hard-cut) clears the shed flag — shedding
	## is a distinct middle state applied via set_shed().
	if on:
		_is_shed = false
	_refresh_label()


## Called by PowerManager._apply_shed_to_consumer() when this device is
## load-shed. It stays "connected" but draws no power — shown as [SHED].
func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on
	if shed_on:
		_powered = false
	_refresh_label()


## Called by InteractionSystem when the player presses E near this object.
## Opens the shared PowerPriorityUI with BOTH a load toggle and priority arrows.
func on_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _prio_ui == null or not is_instance_valid(_prio_ui):
		var ui_script: GDScript = load("res://scripts/ui/PowerPriorityUI.gd")
		if ui_script == null:
			push_warning("HeavyConsumerTest: PowerPriorityUI.gd not found")
			return
		_prio_ui = CanvasLayer.new()
		_prio_ui.set_script(ui_script)
		_prio_ui.name = "PowerPriorityUI"
		get_tree().get_root().add_child(_prio_ui)
		if _prio_ui.has_signal("closed"):
			_prio_ui.closed.connect(_on_prio_closed)
		if _prio_ui.has_signal("load_toggled"):
			_prio_ui.load_toggled.connect(_on_prio_load_toggled)

	if _prio_ui.has_method("open"):
		## show_load_toggle = true → panel includes the on/off load switch.
		_prio_ui.call("open", str(get_instance_id()), "Load Test (500W)", true)


func _on_prio_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false


func _on_prio_load_toggled(_id: String, on: bool) -> void:
	_load_active = on
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		pm.set_consumer_active(str(get_instance_id()), _load_active)
	_refresh_label()


func get_interact_prompt() -> String:
	var state: String
	if not _load_active:
		state = "OFF"
	elif _is_shed:
		state = "SHED"
	elif _powered:
		state = "ON 500W"
	else:
		state = "NO POWER"
	return "[E] Load Test  —  %s" % state


# ─── Interaction-system lookup (same pattern as GeneratorObject) ─────────────
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


# ─── Visual build ─────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	var mi:   MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh        = BoxMesh.new()
	mesh.size = BOX_SIZE
	mi.mesh   = mesh
	mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, 0.0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_BODY
	mat.roughness    = 0.80
	mat.metallic     = 0.30

	## Small orange warning stripe to visually distinguish this from other props.
	## Achieved by a second thin box overlaid on the front face.
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	mi.create_trimesh_collision()
	for child in mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Warning stripe (thin slab on front face)
	var stripe_mi:   MeshInstance3D = MeshInstance3D.new()
	var stripe_mesh: BoxMesh        = BoxMesh.new()
	stripe_mesh.size = Vector3(BOX_SIZE.x * 0.80, 0.07, 0.03)
	stripe_mi.mesh   = stripe_mesh
	stripe_mi.position = Vector3(0.0, BOX_SIZE.y * 0.5, BOX_SIZE.z * 0.5 + 0.015)
	var stripe_mat: StandardMaterial3D = StandardMaterial3D.new()
	stripe_mat.albedo_color           = Color(1.0, 0.50, 0.05, 1.0)
	stripe_mat.emission_enabled       = true
	stripe_mat.emission               = Color(1.0, 0.50, 0.05, 1.0)
	stripe_mat.emission_energy_multiplier = 1.0
	stripe_mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	stripe_mi.set_surface_override_material(0, stripe_mat)
	add_child(stripe_mi)


func _build_label() -> void:
	var lbl: Label3D = Label3D.new()
	lbl.font_size     = 42
	lbl.pixel_size    = 0.0015
	lbl.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.double_sided  = true
	lbl.outline_size  = 5
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.90)
	lbl.position      = Vector3(0.0, BOX_SIZE.y + 0.35, 0.0)
	_update_label_text(lbl, false, true)
	add_child(lbl)
	_state_label = lbl


func _refresh_label() -> void:
	if _state_label == null:
		return
	_update_label_text(_state_label, _powered, _load_active)


## Orange used for the [SHED] state — matches the light shed glow / UI accent.
const COLOR_SHED: Color = Color(1.00, 0.55, 0.10, 1.0)

func _update_label_text(lbl: Label3D, powered: bool, load_active: bool) -> void:
	if not load_active:
		lbl.text     = "⊘  INACTIVE"
		lbl.modulate = Color(0.55, 0.55, 0.55, 1.0)
	elif _is_shed:
		## Connected to the grid but load-shed — clearly distinct from OFF.
		lbl.text     = "▣  [SHED]\nCONNECTED — NO POWER"
		lbl.modulate = COLOR_SHED
	elif powered:
		lbl.text     = "●  ON\n500W"
		lbl.modulate = COLOR_ON
	else:
		lbl.text     = "○  OFF"
		lbl.modulate = COLOR_OFF
