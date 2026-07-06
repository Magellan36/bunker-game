extends StaticBody3D
class_name PowerTerminal
## PowerTerminal.gd
## Buildable power dashboard terminal. TILE_TERMINAL = 10.
##
## A wall-mounted panel that opens PowerTerminalUI on interact.
## Registers as a wire node so it participates in the wire graph and can be
## routed to visually — but it draws ZERO watts, so it is never actually a
## load on the grid. It only needs to be CONNECTED (reachable via wires) to
## light its screen; being POWERED is no longer required to open/use it.
##
## IMPLEMENTATION NOTE: still registered as a "consumer" (role + register_
## consumer call) with watts=0.0 and priority=1 (critical/never-shed) rather
## than introducing a brand-new passive node type. This reuses PowerManager's
## existing reachability BFS + set_powered() callback machinery as-is (zero
## PowerManager changes needed) — with 0 watts it contributes nothing to any
## zone's draw/capacity/shedding math, so functionally it behaves exactly
## like a passive grid element (BreakerBox-style), it just rides the existing
## consumer pipe for its cosmetic "is this zone alive" signal.
##
## Self-registration via call_deferred() so global_position is settled after
## BuildModeController.add_child() fires.

const PANEL_W: float = 0.7
const PANEL_H: float = 0.9
const PANEL_D: float = 0.08

## Power grid settings
## power_watts is intentionally 0.0 — the terminal is a passive grid element,
## never a real load. power_priority=1 (critical) is belt-and-suspenders on
## top of that (0 watts already makes shedding irrelevant either way).
var power_watts:    float  = 0.0
var power_priority: int    = 1
var power_zone:     String = "main"
var _pm_node_key:   String = ""
var _is_connected:  bool   = false  ## True when reachable via the wire graph (cosmetic only now)

## Internal refs
var _screen_mesh:  MeshInstance3D = null
var _ui_open:      bool           = false
var _terminal_ui:  CanvasLayer    = null

## Set by BuildModeController before add_child()
## so _ready() can read it. Not used at runtime after that.

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_meta("tile_id", 10)
	add_to_group("interactable")
	## Layer 1 = standard world objects — must be on this layer so
	## InteractionSystem's DetectArea (which scans layer 1) can see us.
	collision_layer = 1
	collision_mask  = 0
	_build_mesh()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	## Free the persistent UI node when this terminal is deconstructed.
	if _terminal_ui != null and is_instance_valid(_terminal_ui):
		_terminal_ui.queue_free()
		_terminal_ui = null
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if _pm_node_key != "":
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))

# ─── Power API (called by PowerManager) ───────────────────────────────────────
## PowerManager still calls this (the terminal is registered with 0 watts, so
## it's technically still a "consumer" in the registry — see _register_deferred
## for why). It now represents COSMETIC grid-connectivity, not real power —
## the screen dims when the terminal's local zone is dead, but the terminal
## remains fully usable regardless.
func set_powered(on: bool) -> void:
	_is_connected = on
	## Screen dims when the surrounding grid segment has no power flowing —
	## purely visual, does not affect on_interact()/get_interact_prompt().
	if _screen_mesh != null:
		var mat: StandardMaterial3D = _screen_mesh.get_surface_override_material(0)
		if mat != null:
			mat.emission_enabled = on
			mat.emission_energy_multiplier = 1.0 if on else 0.35

# ─── Interaction ─────────────────────────────────────────────────────────────
## Called by InteractionSystem when player presses E near this node.
## No longer gated on power — only needs to exist/be built to be usable.
## (Being wired into the grid is still required for the UI to show live zone
## data; an unwired terminal shows "no zone data" inside the UI itself.)
func on_interact() -> void:
	_open_terminal_ui()

## InteractionSystem reads this to build the prompt line.
func get_interact_prompt() -> String:
	return "[E] Open Power Terminal"

# ─────────────────────────────────────────────────────────────────────────────
func _open_terminal_ui() -> void:
	if _ui_open:
		_close_terminal_ui()
		return

	## Lazy-create the UI node once; reuse on subsequent opens so history persists.
	if _terminal_ui == null or not is_instance_valid(_terminal_ui):
		var ui_script: GDScript = load("res://scripts/ui/PowerTerminalUI.gd")
		if ui_script == null:
			push_warning("[PowerTerminal] PowerTerminalUI.gd not found")
			return

		_terminal_ui = CanvasLayer.new()
		_terminal_ui.set_script(ui_script)
		_terminal_ui.name = "PowerTerminalUI"
		get_tree().get_root().add_child(_terminal_ui)

		## Connect close signal once (not ONE_SHOT — we reuse this node).
		if _terminal_ui.has_signal("closed"):
			_terminal_ui.closed.connect(_on_ui_closed)

	## Resolve which wire zone this terminal belongs to and pass the index.
	## The UI uses this to scope all displayed data to only this zone.
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var zone_idx: int = -1
	if pm != null and _pm_node_key != "":
		zone_idx = pm.get_zone_index_for_key(_pm_node_key)
	if "connected_zone_index" in _terminal_ui:
		_terminal_ui.connected_zone_index = zone_idx
	## Keep legacy key in sync (used by UI fallback path if zone is -1).
	if "connected_grid_key" in _terminal_ui:
		_terminal_ui.connected_grid_key = _pm_node_key

	if _terminal_ui.has_method("open"):
		_terminal_ui.open()

	_ui_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_terminal_ui() -> void:
	## Hide the UI — do NOT free it so history arrays survive.
	if _terminal_ui != null and is_instance_valid(_terminal_ui):
		if _terminal_ui.has_method("close"):
			_terminal_ui.close()
	_ui_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	## UI signalled close (e.g. ESC key) — just update local state.
	_ui_open = false

# ─── Self-registration with PowerManager ──────────────────────────────────────
func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	var dev_id: String = str(get_instance_id())

	## Register consumer FIRST — PowerManager comment says "register consumer before
	## wire node" because register_wire_node triggers _solve_network immediately.
	## If the consumer isn't in the dict yet, the solve sees 0 draw and skips it.
	## power_watts=0.0 means this never actually contributes draw/shedding math —
	## it's a passive grid element riding the consumer pipe purely so PowerManager's
	## existing reachability BFS drives the cosmetic screen-glow via set_powered().
	pm.register_consumer(
		dev_id,
		power_watts,
		self,
		"terminal",    ## type
		power_priority, ## priority (1 = critical/never-shed — moot at 0 watts)
		true)           ## active immediately

	## Wire node registered AFTER consumer so the solve fired here sees the full
	## consumer entry and correctly marks us reachable if a wire path exists.
	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",    ## role must be "consumer" for _is_consumer_reachable() BFS
		dev_id)        ## device_id links wire node → consumer dict entry

# ─── Mesh ─────────────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	## DO NOT override collision_layer here — _ready() already sets it to 1
	## so the DetectArea (Area3D) picks up the terminal root on body_entered.
	## Setting it to 5 here was preventing on_interact() from ever firing.
	collision_mask  = 0

	# Outer housing — dark grey metal box
	var housing: MeshInstance3D = MeshInstance3D.new()
	var hbox: BoxMesh = BoxMesh.new()
	hbox.size = Vector3(PANEL_W, PANEL_H, PANEL_D)
	housing.mesh = hbox
	housing.position = Vector3(0.0, PANEL_H * 0.5, 0.0)
	var hmat: StandardMaterial3D = StandardMaterial3D.new()
	hmat.albedo_color = Color(0.14, 0.14, 0.16, 1.0)
	hmat.metallic     = 0.4
	hmat.roughness    = 0.8
	housing.set_surface_override_material(0, hmat)
	add_child(housing)
	housing.create_trimesh_collision()
	## Child StaticBody3D (from trimesh) must also be on layer 1 so
	## the DetectArea picks up the terminal body on body_entered.
	for child in housing.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 1
			(child as StaticBody3D).collision_mask  = 0

	# Screen — glowing green panel inset into front face
	var screen: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(PANEL_W * 0.80, PANEL_H * 0.55, 0.005)
	screen.mesh = sbox
	screen.position = Vector3(0.0, PANEL_H * 0.58, -PANEL_D * 0.5 - 0.002)
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.albedo_color              = Color(0.02, 0.08, 0.04, 1.0)
	smat.emission_enabled          = true
	smat.emission                  = Color(0.10, 0.90, 0.30, 1.0)
	smat.emission_energy_multiplier = 0.8
	screen.set_surface_override_material(0, smat)
	add_child(screen)
	_screen_mesh = screen

	# Indicator strip — three small LEDs on the bottom bar
	const LED_COLORS: Array[Color] = [
		Color(0.0, 1.0, 0.3, 1.0),
		Color(1.0, 0.7, 0.0, 1.0),
		Color(0.1, 0.4, 1.0, 1.0),
	]
	for i: int in LED_COLORS.size():
		var led: MeshInstance3D = MeshInstance3D.new()
		var lsphere: SphereMesh = SphereMesh.new()
		lsphere.radius = 0.012
		lsphere.height = 0.024
		led.mesh = lsphere
		led.position = Vector3(
			-0.08 + float(i) * 0.08,
			PANEL_H * 0.20,
			-PANEL_D * 0.5 - 0.01)
		var lmat: StandardMaterial3D = StandardMaterial3D.new()
		lmat.albedo_color              = LED_COLORS[i]
		lmat.emission_enabled          = true
		lmat.emission                  = LED_COLORS[i]
		lmat.emission_energy_multiplier = 1.2
		led.set_surface_override_material(0, lmat)
		add_child(led)

# ─── Static ghost helper (for BuildModeController preview) ───────────────────
static func build_ghost_mesh() -> Mesh:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.7, 0.9, 0.08)
	return bm
