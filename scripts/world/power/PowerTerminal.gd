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

## Hand-made Tinkercad OBJ swap (Sep 2026) — replaces the procedural
## housing/screen/LED box. Per grid state there are TWO complete terminal
## models in assets/models/power_terminal/: the *Unpowered* model is the full
## panel with a dark screen, and the *Powered* model is the same panel with a
## lit cyan screen + green/red indicator LEDs. Both are full panels (not
## overlays), so set_powered() swaps the whole visible mesh.
## MODEL_SCALE maps the 70-unit width to PANEL_W (70 * 0.01 = 0.7); height 90
## → 0.9 = PANEL_H exactly. The model is already Y-up in OBJ space (height
## along Y, depth along Z), so NO rotation is applied — unlike the grow light
## (which was Z-up). MODEL_Y_OFFSET lifts the model's bottom (OBJ Y=-45.5 →
## -0.455) to the node origin (y=0, where the old panel's base sat) so the
## terminal rises y=0→0.9 like before. MODEL_Z_OFFSET positions the model so
## its back face sits against the wall plane the way the old centered box did
## (the wall-snap pullback is 0.04; model back at OBJ Z=19 → +0.19 needs a
## -0.15 shift to land at node-local +0.04, i.e. flush with the wall).
const MODEL_PATHS: Dictionary = {
	"unpowered": "res://assets/models/power_terminal/unpowered/tinker.obj",
	"powered":   "res://assets/models/power_terminal/powered/tinker.obj",
}
const MODEL_SCALE:    float = 0.01
const MODEL_Y_OFFSET: float = 0.455
const MODEL_Z_OFFSET: float = -0.15

## Power grid settings
## power_watts is intentionally 0.0 — the terminal is a passive grid element,
## never a real load. power_priority=1 (critical) is belt-and-suspenders on
## top of that (0 watts already makes shedding irrelevant either way).
var power_watts:    float  = 0.0
var power_priority: int    = 1
var power_zone:     String = "main"
var _pm_node_key:   String = ""
var _is_connected:  bool   = false  ## True when reachable via the wire graph (cosmetic only now)
var _wire_attachment: WallWireAttachment = null

## Internal refs
var _base_mi:   MeshInstance3D = null   ## Unpowered model (dark screen) — default
var _lit_mi:    MeshInstance3D = null   ## Powered model (cyan screen) — shown when connected
var _ui_open:      bool           = false
var _terminal_ui:  CanvasLayer    = null

## Set by BuildModeController before add_child()
## so _ready() can read it. Not used at runtime after that.

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

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_meta("tile_id", 10)
	if not _is_preview_only:
		add_to_group("interactable")
	## Layer 1 = standard world objects — must be on this layer so
	## InteractionSystem's DetectArea (which scans layer 1) can see us.
	collision_layer = 1
	collision_mask  = 0
	_build_mesh()
	if _is_preview_only:
		return
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
## the screen model swaps between the dark (Unpowered) and lit cyan (Powered)
## hand-made OBJs when the terminal's local zone is dead/alive, but the
## terminal remains fully usable regardless.
func set_powered(on: bool) -> void:
	_is_connected = on
	## Whole-model swap: the Powered OBJ is the same panel with a lit cyan
	## screen + green/red indicator LEDs; the Unpowered OBJ has the dark
	## screen. Purely visual, does not affect on_interact()/get_interact_prompt().
	if _base_mi != null:
		_base_mi.visible = not on
	if _lit_mi != null:
		_lit_mi.visible = on

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
		var ui_script: GDScript = load("res://scripts/ui/power/PowerTerminalModernUI.gd")
		if ui_script == null:
			push_warning("[PowerTerminal] PowerTerminalModernUI.gd not found")
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
	if _terminal_ui.has_method("bind_target"):
		_terminal_ui.call("bind_target", self)

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
		dev_id,
		true)           ## preserve the wall mounting height
	_wire_attachment = WallWireAttachment.new()
	add_child(_wire_attachment)
	_wire_attachment.bind(self, pm, _pm_node_key)

func refresh_power_attachment() -> void:
	if is_instance_valid(_wire_attachment):
		_wire_attachment.request_refresh()

func get_wall_wire_connector() -> Vector3:
	return to_global(Vector3(0.0, 0.45, 0.0))

func get_wall_wire_inset() -> float:
	return 0.06

# ─── Mesh (hand-made OBJ swap — replaces the procedural housing/screen/LEDs) ─
func _build_mesh() -> void:
	## DO NOT override collision_layer here — _ready() already sets it to 1
	## so the DetectArea (Area3D) picks up the terminal root on body_entered.
	## Setting it to 5 here was preventing on_interact() from ever firing.
	collision_mask  = 0

	## Load both hand-made OBJ panels (Unpowered = dark screen, Powered = lit
	## cyan screen) as sibling MeshInstance3D children at the SAME transform.
	## The two models share an identical AABB (both 70×90×11 OBJ units), so one
	## scale + offset places both. set_powered() toggles which one is visible.
	_load_terminal_models()

	## Invisible box collider matching the old panel footprint — the model is
	## detailed (34–35 surfaces), so a trimesh collider would be wasteful; the
	## DetectArea only needs a shape on the root to detect the terminal.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(PANEL_W, PANEL_H, PANEL_D)
	shape.shape = box
	shape.position = Vector3(0.0, PANEL_H * 0.5, 0.0)
	add_child(shape)

func _load_terminal_models() -> void:
	var base_path: String = MODEL_PATHS["unpowered"]
	var lit_path:  String = MODEL_PATHS["powered"]
	var base_mesh: ArrayMesh = load(base_path) as ArrayMesh
	var lit_mesh:  ArrayMesh = load(lit_path) as ArrayMesh
	if base_mesh == null:
		push_warning("PowerTerminal: model missing at %s" % base_path)
		return
	if lit_mesh == null:
		push_warning("PowerTerminal: model missing at %s" % lit_path)

	## Angle-based normal rebuild (Sep 2026) — the OBJ carries no normals, so
	## Godot's importer smooth-averages them and smears the boxy panel's flat
	## faces (the visible "diagonal seam" across the screen). Auto-smooth keeps
	## rounded surfaces smooth while splitting hard box edges flat. See
	## BuildMaterials.build_auto_smooth_mesh().
	base_mesh = BuildMaterials.build_auto_smooth_mesh(base_mesh)
	lit_mesh  = BuildMaterials.build_auto_smooth_mesh(lit_mesh)

	_base_mi = MeshInstance3D.new()
	_base_mi.mesh = base_mesh
	_base_mi.name = "TerminalUnpowered"
	_apply_mood_override(_base_mi)
	add_child(_base_mi)

	_lit_mi = MeshInstance3D.new()
	_lit_mi.mesh = lit_mesh
	_lit_mi.name = "TerminalPowered"
	_apply_mood_override(_lit_mi)
	## The Powered model's screen/LEDs are meant to read as lit — leave them
	## slightly brighter than the mood override's flat default by re-applying
	## the override only to the housing surfaces. Simpler: keep the override
	## uniform so both states match the theme; the cyan screen still reads as
	## lit against the dark screen at the same dimming.
	add_child(_lit_mi)

	## Same transform for both — identical AABB means one placement fits both.
	var t := Transform3D()
	t = t.scaled(Vector3.ONE * MODEL_SCALE)
	t = t.translated(Vector3(0.0, MODEL_Y_OFFSET, MODEL_Z_OFFSET))
	_base_mi.transform = t
	_lit_mi.transform = t

	## Default to the unpowered (dark) state until PowerManager tells us otherwise.
	_base_mi.visible = true
	_lit_mi.visible  = false

## Dims/desaturates/mattens the terminal's surfaces so it reads in-theme with
## the dark bunker. Deliberately STRONGER than the default mood override
## (0.6/0.12/0.8) because this panel's hand-made MTL colors are bright and
## saturated (cyan screen, white label, colored LED strip) and pop harshly
## against the grim aesthetic. Chosen values are a tuning starting point for
## Brannon to eyeball in-editor — adjust dark/desat/roughness here, not the
## shared BuildMaterials default (other hand-made models use that).
func _apply_mood_override(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	BuildMaterials.apply_mood_override(mi, 0.5, 0.45, 0.85)

# ─── Static ghost helper (for BuildModeController preview) ───────────────────
static func build_ghost_mesh() -> Mesh:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.7, 0.9, 0.08)
	return bm
