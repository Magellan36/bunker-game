extends Node3D
class_name MainWorld
## MainWorld.gd
## Root script for the main game world scene.

# ─── Dev Tools ────────────────────────────────────────────────────────────────
## F12 — toggle x50 time warp (speeds up clock + all stat drain)
## F11 — spawn a TestCrate in front of the player
## F1  — toggle Build Mode
## F9  — dump wire debug log (only useful when WIRE_DEBUG = true below)
const DEV_TIME_SCALE: float  = 50.0
const CRATE_SCENE: String    = "res://scenes/world/TestCrate.tscn"
var _dev_warp_active: bool   = false

# ─── Wire Debug ───────────────────────────────────────────────────────────────
## Set to true to enable wire/zone debug logging.
## Logs are BUFFERED (never spammed per-frame).  Press F9 at any time to
## print the full accumulated log + live graph snapshot to Godot output.
## Keep false in production — zero cost when false.
const WIRE_DEBUG: bool = true

## Accumulated log lines for the most recent rebuild cycle.
## Cleared at the START of every _rebuild_auto_wires() call so you always
## see the log for the LAST rebuild when you hit F9.
var _wire_log: Array[String] = []

## Append a debug line (no-op when WIRE_DEBUG is false).
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		_wire_log.append(msg)

## F9 — print the buffered wire log + live graph state snapshot.
## Call this AFTER digging a chunk (or placing a breaker) to inspect what
## the last rebuild did.  Output is one contiguous block so it won't get
## lost in the middle of other Godot output lines.
func _dump_wire_debug() -> void:
	if not WIRE_DEBUG:
		print("[WireDebug] WIRE_DEBUG is false — enable it in MainWorld.gd to collect logs.")
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("╔══════════════════════════════════════════════════════════════════╗")
	lines.append("║                  WIRE DEBUG DUMP  (F9)                          ║")
	lines.append("╚══════════════════════════════════════════════════════════════════╝")

	## ── A: MainWorld wire log (last rebuild) ──────────────────────────────────
	lines.append("── MainWorld wire log (%d lines) ──────────────────────────────────" % _wire_log.size())
	for l: String in _wire_log:
		lines.append(l)

	## ── B: Live _cleared_cells snapshot ───────────────────────────────────────
	lines.append("── _cleared_cells (%d cells) ──────────────────────────────────────" % _cleared_cells.size())
	var sorted_cells: Array = _cleared_cells.keys()
	sorted_cells.sort()
	lines.append("   " + str(sorted_cells))

	## ── C: Live _auto_wire_nodes snapshot ────────────────────────────────────
	lines.append("── _auto_wire_nodes (%d entries) ──────────────────────────────────" % _auto_wire_nodes.size())
	var sorted_wire_nodes: Array = _auto_wire_nodes.keys()
	sorted_wire_nodes.sort()
	for wk: String in sorted_wire_nodes:
		lines.append("   pos_key=%s  pm_key=%s" % [wk, _auto_wire_nodes[wk]])

	## ── D: Live _auto_wire_segs snapshot ─────────────────────────────────────
	lines.append("── _auto_wire_segs (%d segments) ──────────────────────────────────" % _auto_wire_segs.size())
	for eid: String in _auto_wire_segs:
		var seg_raw: Variant = _auto_wire_segs[eid]
		var valid: String = "VALID" if is_instance_valid(seg_raw) else "FREED"
		lines.append("   edge=%s  seg=%s" % [eid, valid])

	## ── E: Live _player_wire_segs snapshot ───────────────────────────────────
	lines.append("── _player_wire_segs (%d player wires) ────────────────────────────" % _player_wire_segs.size())
	for eid: String in _player_wire_segs:
		var pw: Dictionary = _player_wire_segs[eid]
		lines.append("   edge=%s  na=%s  nb=%s" % [eid, pw.get("node_a","?"), pw.get("node_b","?")])

	## ── F: PowerManager graph snapshot (via dump_wire_log) ────────────────────
	lines.append("── PowerManager graph snapshot ────────────────────────────────────")
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		lines.append("   [PM not found]")
	else:
		var pm_lines: Array = pm.dump_wire_log()
		for pl: String in pm_lines:
			lines.append(pl)

	lines.append("══════════════════════════════════════════════════════════════════════")

	## ── Write the FULL dump to a file ─────────────────────────────────────────
	## The Godot output panel has a finite scrollback and overflows (drops the
	## top) on large dumps no matter how we chunk the print() calls.  Writing to
	## a file guarantees we always capture the complete dump.  The file lives in
	## the user data dir — open it from Godot via:
	##   Project > Open User Data Folder  (then open wire_debug.txt)
	## or grab it directly at the OS path printed below.
	var file_text: String = "\n".join(lines)
	var f: FileAccess = FileAccess.open("user://wire_debug.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(file_text)
		f.close()
		var os_path: String = ProjectSettings.globalize_path("user://wire_debug.txt")
		print("══════════════════════════════════════════════════════════════════════")
		print("[WireDebug] FULL dump (%d lines) written to:" % lines.size())
		print("   user://wire_debug.txt")
		print("   OS path: %s" % os_path)
		print("   (Project > Open User Data Folder, or grab the OS path above)")
		print("══════════════════════════════════════════════════════════════════════")
	else:
		## Fallback: file couldn't be opened — chunk-print so at least something
		## reaches the console.
		push_warning("[WireDebug] Could not open user://wire_debug.txt — printing instead")
		const CHUNK: int = 50
		var total: int = lines.size()
		var i: int = 0
		while i < total:
			var end: int = mini(i + CHUNK, total)
			var chunk: PackedStringArray = PackedStringArray()
			for j: int in range(i, end):
				chunk.append(lines[j])
			print("\n".join(chunk))
			i += CHUNK

@onready var player: CharacterBody3D       = $Player
@onready var camera: GameCamera            = $GameCamera
@onready var world_env: WorldEnvironment   = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var hud: CanvasLayer              = $HUD
@onready var player_stats: PlayerStats      = $PlayerStats
@onready var sleep_overlay: CanvasLayer    = $SleepOverlay
@onready var interact_prompt: Node         = $InteractPrompt
@onready var interaction_system: Node = $Player/InteractionSystem
var inventory_manager: Node = null

## Rock surround — Node3D with RockSurround.gd attached, named "RockSurround" in scene.
## If the node doesn't exist yet the build controller will simply skip dig functionality.
@onready var rock_surround: Node3D = $RockSurround if has_node("RockSurround") else null

# ─── Build Mode ───────────────────────────────────────────────────────────────
var _build_controller: Node3D   = null
var _build_hud: CanvasLayer     = null
var _build_mode_active: bool    = false

# ─── Shelf UI ─────────────────────────────────────────────────────────────────
var _shelf_ui: Node = null

# ─── Power Grid ───────────────────────────────────────────────────────────────
var _power_manager: Node = null

## Water system groundwork (July 2026) — instantiated the same way
## _power_manager is: added to scene tree, tagged "water_manager" group, NOT
## an autoload (per-world-instance state). See scripts/world/water/WaterManager.gd.
var _water_manager: Node = null
var _lighting_director: Node = null   ## LightingDirector.gd, built via Node.new()+set_script() same as _power_manager
## _reconciler removed (Stage 5) — reconciler fully retired.

# ─── Admin Spawn Menu ─────────────────────────────────────────────────────────
var _admin_menu: CanvasLayer = null

# ─── Pause Menu ───────────────────────────────────────────────────────────────
var _pause_menu: CanvasLayer = null

# ─── Economy ──────────────────────────────────────────────────────────────────
var _cash: int = 50000   ## Starting cash; shown in HUD, spent during Build Mode

## Reference to the bed in the scene — assign in _ready or via @export
@export var bed_path: NodePath = NodePath("")
var _bed: Node = null

## ─── Abyss Safety ────────────────────────────────────────────────────────────
## If any physics item falls below this world-Y it has glitched through the floor.
## We teleport it back to a safe Y above the bunker floor at the same XZ coords.
const ABYSS_Y:        float = -8.0   ## below floor-grid Y; floor surface ~0
const ABYSS_RESCUE_Y: float =  1.5   ## respawn height above floor

func _process(_delta: float) -> void:
	## Keep player movement in sync with camera yaw every frame
	player.set("camera_yaw_rad", camera._cur_yaw_rad)
	## Check all pickup items for abyss fall
	_check_abyss_items()

## WireGraphBuilder.gd — auto-wire perimeter rebuild engine (Stage 10
## extraction). No state physically moved here; see WireGraphBuilder.gd
## header comment. MainWorld forwards its 3 externally-triggered entry points
## (_compute_and_rebuild_wires, _on_chunk_deconstructed, _on_chunk_restored)
## to it — everything else in that cluster is only called internally there.
var _wire_builder: WireGraphBuilder = null


func _ready() -> void:
	_wire_builder = WireGraphBuilder.new(self)
	add_to_group("main_world")   ## Lets PowerManager find us as fallback wire parent
	_setup_power_manager()   ## Must be first — lights self-register in _ready()
	_setup_water_manager()
	_setup_lighting()
	_setup_lighting_director()   ## Needs "power_manager" group populated above
	_setup_ambient_dust()
	_connect_hud()
	_connect_bed()
	_ensure_inventory_manager()
	_connect_inventory()
	_connect_world_objects()
	## ShelfUI must come after inventory_manager exists and connect_world_objects
	## has registered shelf group members, so injection covers pre-placed shelves.
	_setup_shelf_ui()
	_setup_debug_overlay()
	_register_save_fields()
	get_tree().process_frame.connect(_setup_build_mode, CONNECT_ONE_SHOT)

## ── Save/Load field registration ──────────────────────────────────────────
## Registers the CURRENT minimal set of persistable fields with the SaveManager
## autoload — player position, cash, and the game clock. Deliberately does NOT
## register power grid / inventory / placed objects yet (still evolving fast
## per project decision); add more fields here later the same way, one
## register_field() call per field, no changes needed in SaveManager itself.
func _register_save_fields() -> void:
	## Phase 0 — dug rock chunks. Must exist before anything below is restored
	## onto/around them (placed objects, wires, pipes).
	SaveManager.register_field(
		"dug_chunks",
		func() -> Array: return rock_surround.get_dug_chunk_ids_for_save() if rock_surround != null else [],
		func(v: Array) -> void:
			if rock_surround != null:
				rock_surround.restore_dug_chunks(v),
		0)

	## Phase 1 — placed objects (devices, each with embedded per-device extra
	## state — fuel/health/priority/tripped/etc). Must exist before wires/
	## pipes below try to reconnect to them.
	SaveManager.register_field(
		"placed_objects",
		func() -> Array: return _build_controller.get_placed_objects_for_save() if _build_controller != null else [],
		func(v: Array) -> void:
			if _build_controller != null:
				_build_controller.restore_placed_objects(v),
		1)

	## Phase 2 — player-placed power wires.
	SaveManager.register_field(
		"player_wires",
		func() -> Array: return get_player_wires_for_save(),
		func(v: Array) -> void: restore_player_wires(v),
		2)

	## Phase 3 — water pipe network (corners/joints + segments).
	SaveManager.register_field(
		"water_pipes",
		func() -> Dictionary: return _water_manager.get_pipe_network_for_save() if _water_manager != null else {},
		func(v: Dictionary) -> void:
			if _water_manager != null:
				_water_manager.restore_pipe_network(v),
		3)

	## Phase 4 — player position / cash / game clock. Applied last, once the
	## whole world (chunks, devices, wires, pipes) already exists.
	SaveManager.register_field(
		"player_position",
		func() -> Vector3: return player.global_position,
		func(v: Vector3) -> void: player.global_position = v,
		4)

	SaveManager.register_field(
		"cash",
		func() -> int: return get_cash(),
		func(v: int) -> void: set_cash(v),
		4)

	SaveManager.register_field(
		"game_elapsed",
		func() -> float: return player_stats.get_elapsed(),
		func(v: float) -> void: player_stats.set_elapsed(v),
		4)

## ── Player wire save/restore (Jul 2026) ─────────────────────────────────────
## Returns every player-placed wire as a JSON-friendly array of endpoint
## position pairs. Positions (not PM keys) are the stable identity here —
## keys can be remapped by _split_wire_edge_at() over a session's lifetime,
## same reasoning _on_wire_nodes_connected()'s own comment gives for why
## _player_wire_segs stores pos_a/pos_b instead of keys.
func get_player_wires_for_save() -> Array:
	var out: Array = []
	for entry: Dictionary in _player_wire_segs.values():
		out.append({
			"pos_a": SaveManager.vec3_to_dict(entry["pos_a"]),
			"pos_b": SaveManager.vec3_to_dict(entry["pos_b"]),
		})
	return out

## Rebuilds every player-placed wire from get_player_wires_for_save()'s
## output. Registering a "joint" wire node at a position that already holds a
## device node (generator/battery/breaker, restored in the earlier
## placed_objects phase) is a documented no-op in PowerGraph.register_wire_node
## (it refuses to overwrite breaker/generator/battery roles) — so this is safe
## to call for every saved wire regardless of which end is a device.
## NOTE: does not attempt to clear pre-existing player wires first — on a
## normal fresh boot there are none, and a mid-session Load is expected to run
## after clear_all_player_placed() has already torn down every device (which
## cascades wire-node cleanup for device-owned nodes) — any leftover bare
## "joint" wires from the pre-load session are a known gap, flagged in
## docs/systems/world-core/README.md, not yet auto-cleared here.
func restore_player_wires(data: Array) -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	for saved: Dictionary in data:
		var pos_a: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_a", {}))
		var pos_b: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_b", {}))
		var key_a: String = pm.register_wire_node(pos_a, "joint", "")
		var key_b: String = pm.register_wire_node(pos_b, "joint", "")
		var edge_id: String = pm.register_wire_edge(key_a, key_b)
		if edge_id.is_empty():
			continue
		var wire_script: GDScript = load("res://scripts/world/power/WireSegment.gd")
		var seg: Node3D = Node3D.new()
		if wire_script != null:
			seg.set_script(wire_script)
		seg.name = "WireSegment"
		add_child(seg)
		if seg.has_method("set_endpoints"):
			seg.set_endpoints(pos_a, pos_b)
		if "edge_id" in seg:
			seg.edge_id = edge_id
		seg.visible = true

		var stable_key: String = "pw_%s_%s" % [key_a, key_b]
		_player_wire_segs[stable_key] = {
			"pos_a":      pos_a,
			"pos_b":      pos_b,
			"seg_node":   seg,
			"pm_edge_id": edge_id,
			"stable_key": stable_key,
		}

## Instantiates PowerManager and adds it to the "power_manager" group so
## WallLight nodes can find it via get_first_node_in_group().
## Must run before any child _ready() that self-registers (i.e. pre-placed lights).
func _setup_power_manager() -> void:
	var pm_script: GDScript = load("res://scripts/world/power/PowerManager.gd")
	if pm_script == null:
		push_warning("MainWorld: PowerManager.gd not found — power grid disabled")
		return
	_power_manager = Node.new()
	_power_manager.set_script(pm_script)
	_power_manager.name = "PowerManager"
	## Add to group BEFORE add_child so _ready() (and any deferred callbacks
	## it schedules) can find PowerManager via get_first_node_in_group().
	_power_manager.add_to_group("power_manager")
	add_child(_power_manager)

	## PowerGridReconciler retired (Stage 5) — incremental wire graph makes it
	## unnecessary.  Player wire edges survive digs natively.

	## Connect grid-event signals to HUD notifications.
	## Deferred so HUD is guaranteed ready before the signal fires.
	call_deferred("_connect_power_hud_signals")

## Water system groundwork (July 2026) — mirrors _setup_power_manager()'s
## shape exactly. Standalone system (see docs/systems referenced in
## WaterManager.gd's header) — no HUD/signal wiring needed yet (Phase 1 has
## no dashboard/terminal UI).
func _setup_water_manager() -> void:
	var wm_script: GDScript = load("res://scripts/world/water/WaterManager.gd")
	if wm_script == null:
		push_warning("MainWorld: WaterManager.gd not found — water system disabled")
		return
	_water_manager = Node.new()
	_water_manager.set_script(wm_script)
	_water_manager.name = "WaterManager"
	_water_manager.add_to_group("water_manager")
	add_child(_water_manager)

## Connects PowerManager signals to HUD floating alerts.
## Called deferred from _setup_power_manager() to ensure HUD is ready.
func _connect_power_hud_signals() -> void:
	if _power_manager == null:
		return
	if _power_manager.has_signal("grid_tripped") \
			and not _power_manager.grid_tripped.is_connected(_on_grid_tripped):
		_power_manager.grid_tripped.connect(_on_grid_tripped)
	if _power_manager.has_signal("grid_restored") \
			and not _power_manager.grid_restored.is_connected(_on_grid_restored):
		_power_manager.grid_restored.connect(_on_grid_restored)
	if _power_manager.has_signal("grid_offline") \
			and not _power_manager.grid_offline.is_connected(_on_grid_offline):
		_power_manager.grid_offline.connect(_on_grid_offline)

func _on_grid_tripped() -> void:
	if hud != null and hud.has_method("show_soft_warning"):
		hud.show_soft_warning("⚡ POWER GRID TRIPPED — reduce load, then restart generators")
	## Camera shake (graphics plan Phase 7) — a tripped main breaker is the
	## single biggest "oh no" moment in the power system, worth a jolt.
	if camera != null:
		camera.add_trauma(0.5)

func _on_grid_restored() -> void:
	if hud != null and hud.has_method("show_soft_warning"):
		hud.show_soft_warning("✓ GRID RESTORED — restart generators to restore power")

func _on_grid_offline() -> void:
	if hud != null and hud.has_method("show_soft_warning"):
		hud.show_soft_warning("✗ POWER GRID OFFLINE — no generators or batteries")

func _setup_debug_overlay() -> void:
	var script: GDScript = load("res://scripts/ui/debug/DebugOverlay.gd")
	if script == null:
		return
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.set_script(script)
	overlay.name = "DebugOverlay"
	add_child(overlay)
	## Inject refs so the overlay can show player pos, cash, and live PM data
	overlay.set("player_ref",        player)
	overlay.set("world_ref",         self)
	overlay.set("power_manager_ref", _power_manager)

func _setup_shelf_ui() -> void:
	var shelf_ui_script: Script = load("res://scripts/ui/inventory/ShelfUI.gd")
	_shelf_ui = CanvasLayer.new()
	_shelf_ui.set_script(shelf_ui_script)
	_shelf_ui.name = "ShelfUI"
	add_child(_shelf_ui)

	## Inject shared refs
	_shelf_ui.interaction_system = interaction_system
	_shelf_ui.inventory          = inventory_manager
	var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
	_shelf_ui.inventory_hud = inv_hud

	## Give InteractionSystem a ref so it can block input while open
	interaction_system.shelf_ui = _shelf_ui

	## Inject into any shelves already in the scene (pre-placed before build mode)
	var shelves: Array = get_tree().get_nodes_in_group("shelving")
	for shelf in shelves:
		if "_shelf_ui" in shelf:
			shelf.set("_shelf_ui", _shelf_ui)
		if "_interaction_system" in shelf:
			shelf.set("_interaction_system", interaction_system)

func _ensure_inventory_manager() -> void:
	# Use scene node if it exists, otherwise create one at runtime
	inventory_manager = get_node_or_null("InventoryManager")
	if inventory_manager == null:
		var script: Script = load("res://scripts/ui/inventory/InventoryManager.gd")
		inventory_manager = Node.new()
		inventory_manager.name = "InventoryManager"
		inventory_manager.set_script(script)
		add_child(inventory_manager)

func _unhandled_input(event: InputEvent) -> void:
	# ESC — toggle pause menu (only when not in build mode; build mode owns
	# its own ESC handling via BuildModeHUD for closing submenus/cancelling).
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _build_mode_active:
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
			return

	# F1 — toggle Build Mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_toggle_build_mode()
		get_viewport().set_input_as_handled()
		return

	# F12 — toggle time warp x50
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_dev_toggle_warp()

	# Home / End — rotate camera 90° (only in build mode, but allowed anywhere)
	if event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		camera.rotate_view_left()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_END:
		camera.rotate_view_right()
		get_viewport().set_input_as_handled()
		return

	# F10 — Admin spawn menu
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_toggle_admin_spawn_menu()
		get_viewport().set_input_as_handled()
		return

	# F9 — wire debug dump
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_dump_wire_debug()
		get_viewport().set_input_as_handled()
		return

	# F11 is now owned by DebugOverlay — do NOT handle here

func _toggle_admin_spawn_menu() -> void:
	## Lazy-init: create only on first F10 press.
	if _admin_menu == null:
		var script: GDScript = load("res://scripts/ui/menus/AdminSpawnMenu.gd")
		if script == null:
			push_warning("[DEV] AdminSpawnMenu.gd not found")
			return
		_admin_menu = CanvasLayer.new()
		_admin_menu.set_script(script)
		_admin_menu.name = "AdminSpawnMenu"
		add_child(_admin_menu)
		## Inject refs so the menu can spawn into the world
		_admin_menu.set("world_node",       self)
		_admin_menu.set("player",           player)
		_admin_menu.set("build_controller", _build_controller)
	if _admin_menu.has_method("toggle"):
		_admin_menu.toggle()

func _toggle_pause_menu() -> void:
	## Lazy-init: create only on first ESC press.
	if _pause_menu == null:
		var script: GDScript = load("res://scripts/ui/menus/PauseMenuUI.gd")
		if script == null:
			push_warning("[PauseMenu] PauseMenuUI.gd not found")
			return
		_pause_menu = CanvasLayer.new()
		_pause_menu.set_script(script)
		_pause_menu.name = "PauseMenuUI"
		add_child(_pause_menu)
		_pause_menu.set("world_node", self)
		_pause_menu.set("player",     player)
	if _pause_menu.has_method("toggle"):
		_pause_menu.toggle()

func _dev_toggle_warp() -> void:
	_dev_warp_active = not _dev_warp_active
	if _dev_warp_active:
		Engine.time_scale = DEV_TIME_SCALE
		_wdbg("[DEV] Time warp ON (x%.0f)" % DEV_TIME_SCALE)
	else:
		Engine.time_scale = 1.0
		_wdbg("[DEV] Time warp OFF")

func _dev_spawn_crate() -> void:
	var crate_res: Resource = load(CRATE_SCENE)
	if crate_res == null:
		push_error("[DEV] Could not load TestCrate.tscn — check path: %s" % CRATE_SCENE)
		return
	var crate: Node3D = crate_res.instantiate()
	add_child(crate)
	# Spawn 2m in front of player, slightly above ground
	crate.global_position = player.global_position \
		+ (-player.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)
	_wdbg("[DEV] Spawned TestCrate")

func _setup_lighting() -> void:
	## Subtle moonlight — barely visible cool ambient, not true sunlight.
	## Energy 0.06 is low enough to give a faint blue-grey ambient without
	## washing out the warm sconce lighting.
	dir_light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	dir_light.light_color      = Color(0.72, 0.80, 1.0, 1.0)  ## cool blue-white
	dir_light.light_energy     = 0.06
	dir_light.shadow_enabled   = false

## Instantiates LightingDirector (global fog-tint/vignette-alarm reactor —
## see LightingDirector.gd's header for why it does NOT touch individual
## Light3D energy) and injects the WorldEnvironment + HUD vignette refs it
## needs. Must run AFTER _setup_power_manager() so the "power_manager" group
## already has a member for it to connect grid_state_changed to.
func _setup_lighting_director() -> void:
	var script: GDScript = load("res://scripts/world/environment/LightingDirector.gd")
	if script == null:
		push_warning("[MainWorld] LightingDirector.gd not found")
		return
	_lighting_director = Node.new()
	_lighting_director.set_script(script)
	_lighting_director.name = "LightingDirector"
	_lighting_director.set("world_env", world_env)
	_lighting_director.set("hud_vignette", hud.get_node_or_null("HUDRoot/CriticalVignette"))
	add_child(_lighting_director)

## Ambient dark-room dust drift (graphics plan Section 4 VFX priority #2) —
## a single sparse, world-space GPUParticles3D covering the bunker interior.
## Sized off rock_surround's own bunker_width/bunker_depth/OFFSET_X/OFFSET_Z
## (same values RockSurround/BuildModeController use), so it automatically
## matches whatever the actual instance-level bunker dimensions are set to.
## Deliberately simple — does NOT track chunk expansion/digs; a single fixed
## volume sized to the starting bunker footprint is enough atmosphere value
## for the cost, per the "keep it simple, don't over-engineer" mandate.
func _setup_ambient_dust() -> void:
	if rock_surround == null:
		return
	var depth: float    = float(rock_surround.bunker_depth)   ## maps to world X, see RockSurround.gd
	var width: float    = float(rock_surround.bunker_width)   ## maps to world Z, see RockSurround.gd
	var offset_x: float = rock_surround.OFFSET_X
	var offset_z: float = rock_surround.OFFSET_Z
	var dust: GPUParticles3D = DustMotes.create_ambient_dust(Vector3(depth, 3.0, width))
	dust.position = Vector3(offset_x + depth * 0.5, 1.5, offset_z + width * 0.5)
	dust.name = "AmbientDust"
	add_child(dust)

func _connect_hud() -> void:
	hud.set_health(100.0)
	hud.set_stamina(100.0)
	hud.set_food(100.0)
	hud.set_water(100.0)
	hud.set_sleep(100.0)
	hud.set_cash(_cash)

	player.stamina_changed.connect(func(v: float) -> void: hud.set_stamina(v))

	player_stats.food_changed.connect(func(v: float)   -> void: hud.set_food(v))
	player_stats.water_changed.connect(func(v: float)  -> void: hud.set_water(v))
	player_stats.sleep_changed.connect(func(v: float)  -> void: hud.set_sleep(v))
	player_stats.health_changed.connect(func(v: float) -> void: hud.set_health(v))

	player_stats.time_changed.connect(
		func(_h: int, _m: int, _pm: bool, display: String) -> void:
			hud.set_clock(display)
	)

	player_stats.day_changed.connect(func(day: int) -> void: hud.set_day(day))
	hud.set_day(1)   # Initialise to Day 1 before first signal fires

func _connect_bed() -> void:
	# Wire SleepOverlay to PlayerStats
	sleep_overlay.player_stats = player_stats

	# Wire SleepOverlay.sleep_ended once (shared across all beds)
	sleep_overlay.sleep_ended.connect(func() -> void:
		player.set_physics_process(true)
	)

	# Connect all existing beds in the "bed" group.
	# Also called again when new beds are placed (see _wire_bed).
	for b: Node in get_tree().get_nodes_in_group("bed"):
		_wire_bed(b)

	# Fall back to path if set (legacy support for hand-placed scene beds)
	if bed_path != NodePath(""):
		var b: Node = get_node_or_null(bed_path)
		if b != null:
			_wire_bed(b)

## Wires a single bed node to the sleep system.
## Uses a meta tag to avoid double-wiring if called again on the same bed.
func _wire_bed(bed: Node) -> void:
	if bed == null or not bed.has_signal("sleep_requested"):
		return
	## Guard: already wired this bed
	if bed.has_meta("_sleep_wired"):
		return
	bed.set_meta("_sleep_wired", true)

	sleep_overlay.bed = bed

	## Capture bed in a local variable for the lambda; avoids .bind() Callable issues.
	var the_bed: Node = bed
	bed.sleep_requested.connect(func() -> void:
		sleep_overlay.bed = the_bed   ## keep overlay pointing at whichever bed was used
		if the_bed.has_method("set_sleeping"):
			the_bed.set_sleeping(true)
		player.set_physics_process(false)
		sleep_overlay.begin_sleep()
	)
	if bed.has_signal("wake_requested"):
		bed.wake_requested.connect(sleep_overlay.request_wake)

func _connect_inventory() -> void:
	var inv_hud: Node = hud.get_node("HUDRoot/InventoryHUD")

	# Give InteractionSystem access to InventoryManager so it can store items
	interaction_system.inventory = inventory_manager

	# Give InteractionSystem a direct ref to InventoryHUD for slot highlights
	interaction_system.inventory_hud = inv_hud

	# Give InventoryHUD its data source
	inv_hud.set("inventory", inventory_manager)

	# Redraw slots whenever inventory changes — skip if build mode is hiding the bar
	inventory_manager.inventory_changed.connect(
		func() -> void:
			if _build_mode_active:
				return
			if inv_hud.has_method("refresh_previews"):
				inv_hud.refresh_previews()
			else:
				inv_hud.queue_redraw()
	)

func _setup_build_mode() -> void:  ## coroutine — called via process_frame one-shot signal
	# ── Build Mode HUD (CanvasLayer overlay) ──
	var hud_script: Script = load("res://scripts/ui/build/BuildModeHUD.gd")
	_build_hud = CanvasLayer.new()
	_build_hud.set_script(hud_script)
	_build_hud.name = "BuildModeHUD"
	add_child(_build_hud)
	_build_hud.visible = false

	# ── Build Mode Controller (lives under Player) ──
	var ctrl_script: Script = load("res://scripts/world/build/BuildModeController.gd")
	_build_controller = Node3D.new()
	_build_controller.set_script(ctrl_script)
	_build_controller.name = "BuildModeController"
	player.add_child(_build_controller)

	# Find the GridMap (BunkerLayout)
	var gm: GridMap = get_tree().get_first_node_in_group("gridmap") as GridMap
	if gm == null:
		# Fallback: find by class
		for child in get_children():
			if child is GridMap:
				gm = child
				break
	if gm == null:
		push_warning("MainWorld: Could not find GridMap for BuildModeController")

	_build_controller.gridmap    = gm
	_build_controller.build_hud  = _build_hud
	_build_controller.camera     = camera
	_build_controller.world_node    = self         ## So controller can call spend_cash() / add_cash()
	_build_controller.rock_surround = rock_surround ## May be null if node not yet in scene
	_build_controller.set_process(false)            ## Off until activated

	# Give BuildModeHUD the camera so it can project 3D→2D for the deconstruct overlay
	_build_hud.camera = camera

	## Connect rock chunk signals → auto-fill handlers
	if rock_surround != null and rock_surround.has_signal("chunk_deconstructed"):
		rock_surround.chunk_deconstructed.connect(_on_chunk_deconstructed)
	if rock_surround != null and rock_surround.has_signal("chunk_restored"):
		rock_surround.chunk_restored.connect(_on_chunk_restored)

	## ── Generate the pre-built bunker layout ──────────────────────────────
	## Replaces the hand-designed GridMap level entirely.
	## _run_pregen is async (awaits one frame) — call with await so the
	## coroutine completes before _setup_build_mode returns.
	await _run_pregen(gm)

	## Starting water hookup — see _spawn_initial_water_hookup() below.
	## Awaited: the function itself waits out two physics frames before
	## raycasting (same fix as WaterManager's reposition-lag bug — pregen's
	## walls were just spawned this frame and their colliders aren't
	## registered with the physics server yet).
	await _spawn_initial_water_hookup()

	## Apply concrete floor texture to the GridMap's floor tile mesh.
	## We override the material on the MeshLibrary item directly so all
	## GridMap-stamped floor tiles pick it up immediately.
	_apply_floor_texture(gm)

	## Hook WireDrawMode signals so MainWorld can track player-placed wires.
	## WireDrawMode is added inside BuildModeController._ready() (_setup_wire_draw_mode),
	## which fires AFTER player.add_child() returns — so we must defer this connection
	## by one frame to guarantee WireDrawMode exists before we query for it.
	call_deferred("_connect_wire_draw_mode")

	## Wire tubes default to visible=false in WireSegment._ready(), but pregen
	## spawns some tubes before _ready() runs (deferred add_child timing) and
	## others may be added synchronously.  Since build mode is NOT active at
	## startup, force-hide every wire segment now so nothing leaks into play mode.
	## This mirrors exactly what exit_build_mode() does — just run it at init too.
	get_tree().call_group("wire_segment", "set_visible", false)


## Patches the GridMap MeshLibrary's floor mesh (item 0) with the
## concrete_floor texture. Safe to call after pregen has run.
func _apply_floor_texture(gm: GridMap) -> void:
	if gm == null:
		return
	var lib: MeshLibrary = gm.mesh_library
	if lib == null:
		return
	var floor_mesh: Mesh = lib.get_item_mesh(0)   ## TILE_FLOOR = 0
	if floor_mesh == null:
		return

	var floor_tex: Texture2D = load("res://assets/textures/concrete_floor.jpg") as Texture2D
	if floor_tex == null:
		push_warning("[MainWorld] concrete_floor.jpg not found — floor texture skipped")
		return

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = floor_tex
	mat.albedo_color   = Color(1.0, 1.0, 1.0, 1.0)
	mat.roughness      = 0.90
	mat.metallic       = 0.0

	for s: int in floor_mesh.get_surface_count():
		floor_mesh.surface_set_material(s, mat)


## Deduct cash. Returns false (and does NOT deduct) if balance is insufficient.
func spend_cash(amount: int) -> bool:
	if _cash < amount:
		return false
	_cash -= amount
	hud.set_cash(_cash)
	return true

## Add cash (refund on deconstruct).
func add_cash(amount: int) -> void:
	_cash += amount
	hud.set_cash(_cash)

## Read current cash balance (used by BuildModeController ghost validity check).
func get_cash() -> int:
	return _cash

## Directly set cash balance (used by SaveManager on load — bypasses the
## spend_cash()/add_cash() delta logic since a load is an absolute restore,
## not a transaction).
func set_cash(value: int) -> void:
	_cash = value
	hud.set_cash(_cash)

## ── Player wire tracking ─────────────────────────────────────────────────────
## Called when WireDrawMode successfully places a wire (via wire_nodes_connected signal).
## Stores world-space endpoint positions + seg_node — no PM key lookup needed.
## Using wire_nodes_connected instead of wire_placed because it carries key_a/key_b
## directly, and we store pos_a/pos_b at placement time so the snapshot loop
## never needs to call PM.get_wire_node_pos() (which can fail if _split_wire_edge_at
## remapped the key before the snapshot runs).
func _on_wire_nodes_connected(key_a: String, pos_a: Vector3, key_b: String, pos_b: Vector3) -> void:
	## Consume whatever seg_node _on_player_wire_placed stored (may be null if
	## the signals connected AFTER this particular wire was already placed —
	## i.e. the deferred _connect_wire_draw_mode() hadn't fired yet).
	## We still register the entry so cull logic can find and erase it;
	## the seg_node fallback in the cull block handles the null case by scanning
	## the wire_segment group for a matching edge_id.
	var seg: Node3D = _pending_wire_seg
	_pending_wire_seg = null

	## Stable position-pair key (PM keys can change after edge splits).
	var stable_key: String = "pw_%s_%s" % [key_a, key_b]
	## Canonical PM edge id — matches PowerManager.register_wire_edge() format:
	## "e_<smaller_key>__<larger_key>"  (double underscore, leading "e_").
	## Used as fallback to locate the visual WireSegment node by its edge_id field.
	var pm_edge_id: String = "e_%s__%s" % [key_a, key_b] if key_a < key_b else "e_%s__%s" % [key_b, key_a]
	_player_wire_segs[stable_key] = {
		"pos_a":      pos_a,
		"pos_b":      pos_b,
		"seg_node":   seg,          ## may be null — see fallback in cull block
		"pm_edge_id": pm_edge_id,   ## fallback: scan wire_segment group by edge_id
		"stable_key": stable_key,
	}
	## Player wire is tracked in _player_wire_segs — survives digs natively.
	## (Reconciler hand-off removed Stage 5.)

## Called one line before _on_wire_nodes_connected — just captures the seg_node
## so the paired wire_nodes_connected handler can store it.
## If _connect_wire_draw_mode() hadn't fired yet when this wire was placed,
## this handler was not connected — _pending_wire_seg stays null, and
## _on_wire_nodes_connected stores seg_node=null with a pm_edge_id fallback.
func _on_player_wire_placed(seg_node: Node3D, _edge_id: String, _cost: int, _midpoint: Vector3) -> void:
	_pending_wire_seg = seg_node

## Deferred connection so BuildModeController._ready() has fired and
## WireDrawMode exists as a child before we query for it.
func _connect_wire_draw_mode() -> void:
	if _build_controller == null:
		push_warning("[MainWorld] _connect_wire_draw_mode: _build_controller is null")
		return
	var wdm: Node = _build_controller.get_node_or_null("WireDrawMode")
	if wdm == null:
		push_warning("[MainWorld] WireDrawMode not found — player wires won't survive expansion")
		return
	if wdm.has_signal("wire_placed") and not wdm.wire_placed.is_connected(_on_player_wire_placed):
		wdm.wire_placed.connect(_on_player_wire_placed)
	if wdm.has_signal("wire_nodes_connected") and not wdm.wire_nodes_connected.is_connected(_on_wire_nodes_connected):
		wdm.wire_nodes_connected.connect(_on_wire_nodes_connected)
		print("[MainWorld] wire_placed + wire_nodes_connected connected OK")

func _toggle_build_mode() -> void:
	_build_mode_active = not _build_mode_active

	if _build_mode_active:
		_build_controller.enter_build_mode()
		camera.enter_build_mode()
		hud.set_build_mode(true)
		interaction_system.build_mode_active = true
		# Belt-and-suspenders: re-hide inventory next frame after any deferred signals
		var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
		if inv_hud:
			inv_hud.call_deferred("set", "visible", false)
		_wdbg("[Build] Build Mode ON")
	else:
		_build_controller.exit_build_mode()
		camera.exit_build_mode()
		hud.set_build_mode(false)
		interaction_system.build_mode_active = false
		# Restore inventory visibility
		var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
		if inv_hud:
			inv_hud.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_wdbg("[Build] Build Mode OFF")

## ─── Rock chunk auto-fill ────────────────────────────────────────────────────
## Persistent set of ALL cleared GridMap cells (int cx, int cz) accumulated
## across every chunk dig. Key = "cx,cz". Used by the global perimeter solver.
var _cleared_cells: Dictionary = {}

## Persistent set of auto-fill structure world positions so we can remove
## walls/pillars that become interior after a subsequent adjacent dig.
## Key = "wx_str,wz_str"  →  the Node3D spawned there (wall or pillar).
## A position is stored with 2 decimal places to avoid float drift.
var _autofill_nodes: Dictionary = {}

## Single source of truth for ALL wire nodes in the scene.
## BunkerPregen no longer registers any wires — MainWorld owns everything.
## Torn down and rebuilt completely on every dig by _rebuild_auto_wires().
## Key = "%.3f_%.3f_%.3f" (x,y,z)  →  PM wire node key (String)
var _auto_wire_nodes: Dictionary = {}

## Tracks WireSegment visuals spawned by auto-wiring.
## Torn down on every rebuild alongside _auto_wire_nodes.
## Key = edge_id  →  WireSegment Node3D
var _auto_wire_segs: Dictionary = {}

## Tracks player-placed wire segments (via WireDrawMode).
## These survive auto-wire rebuilds — snapshotted before Pass 0,
## re-registered in PM after Pass B2 using snap-key-stable positions.
## Key = "pw_keyA_keyB"  →  {pos_a: Vector3, pos_b: Vector3, seg_node: Node3D}
var _player_wire_segs: Dictionary = {}

## ── Stage 1: boundary diff state ─────────────────────────────────────────────
## Snapshot of the boundary_edges dict from the PREVIOUS dig/undo.
## On the very first dig _boundary_edges_prev is empty, so the diff = "add
## everything" — which correctly represents the full initial build.
## Updated at the end of every _on_chunk_deconstructed / _on_chunk_restored
## AFTER _rebuild_auto_wires() completes.
## Stage 1: logging only. Stage 2+: drives incremental remove/add.
var _boundary_edges_prev: Dictionary = {}

## One-frame handoff between wire_placed and wire_nodes_connected handlers.
## wire_placed fires first (captures seg_node here), wire_nodes_connected
## fires immediately after and reads this to complete the _player_wire_segs entry.
var _pending_wire_seg: Node3D = null

## Cached reference to BunkerPregen node — set in _run_pregen().
var _bunker_pregen: Node3D = null

## Round a world-space float to 2dp for use as a stable dictionary key.
func _wkey(v: float) -> String:
	return "%.2f" % v

## ─── Pre-generation ──────────────────────────────────────────────────────────
## Wipes any hand-made GridMap tiles that were placed in the editor scene.
## Must run before pregen so the scene starts clean.
func _clear_existing_gridmap_tiles(gm: GridMap) -> void:
	if gm == null:
		return
	for cell: Vector3i in gm.get_used_cells():
		gm.set_cell_item(cell, -1)
	_wdbg("[Pregen] Cleared %d hand-placed GridMap tiles" % gm.get_used_cells().size())

## Spawns the starting bunker layout (floors, pit walls, pillars) at game start.
## Also seeds _cleared_cells with the full 16×8 interior so the auto-fill solver
## never places walls on edges that face the pre-generated room.
## Uses await so BuildModeController._ready() has fired before generate() runs.
func _run_pregen(gm: GridMap) -> void:
	if rock_surround == null or _build_controller == null:
		return

	## Wipe any tiles the designer left in the scene — prevents double-bunker glitch
	_clear_existing_gridmap_tiles(gm)

	## Seed the full bunker interior into _cleared_cells
	## so dig-auto-fill treats all interior edges as open.
	## Cell key formula must match _on_chunk_deconstructed:
	##   cx = int(floor(float(local) + 0.5 + offset_x))
	var offset_x: float = rock_surround.OFFSET_X
	var offset_z: float = rock_surround.OFFSET_Z
	var depth:    int   = rock_surround.bunker_depth   ## 16
	var width:    int   = rock_surround.bunker_width   ## 8
	for lx: int in range(depth):
		for lz: int in range(width):
			var cx: int = int(floor(float(lx) + 0.5 + offset_x))
			var cz: int = int(floor(float(lz) + 0.5 + offset_z))
			var ckey: String = str(cx) + "," + str(cz)
			_cleared_cells[ckey] = true

	## Defer one frame so BuildModeController._ready() finishes
	## (it sets up the MeshLibrary ref — without this, meshes come out blank).
	await get_tree().process_frame

	## Run the pre-gen script
	var pregen_script: Script = load("res://scripts/world/environment/BunkerPregen.gd")
	var pregen: Node3D = Node3D.new()
	pregen.set_script(pregen_script)
	pregen.name = "BunkerPregen"
	add_child(pregen)
	pregen.build_controller = _build_controller
	pregen.rock_surround    = rock_surround
	pregen.gridmap          = gm
	## Merge pregen nodes into _autofill_nodes so the dig solver can remove
	## them when a rock is destroyed and that wall edge becomes exterior-open.
	var pregen_nodes: Dictionary = pregen.generate()
	_autofill_nodes.merge(pregen_nodes)
	## Cache for stale perimeter wire cleanup on dig
	_bunker_pregen = pregen

	## Lay the initial wire perimeter around the pre-built bunker.
	## _cleared_cells is already seeded with the full bunker interior above,
	## so _compute_and_rebuild_wires() produces the correct starting ring.
	_compute_and_rebuild_wires()

## ─── Wire-only rebuild from current _cleared_cells ──────────────────────────
## Recomputes boundary_edges + pillar_positions from _cleared_cells (same
## logic used inside _on_chunk_deconstructed) and calls _rebuild_auto_wires.
## Used at startup so wires appear without requiring the player to dig first.
## ── Forwarded to WireGraphBuilder.gd (Stage 10) ─────────────────────────────
## These are the only 3 entry points still called from elsewhere in this file
## (startup wire-build, and RockSurround's chunk_deconstructed/chunk_restored
## signals, connected in _setup_build_mode / rock_surround wiring). Every other
## function that used to live here is only called from within
## WireGraphBuilder itself now — see that file for the full cluster.
func _compute_and_rebuild_wires() -> void:
	_wire_builder._compute_and_rebuild_wires()


## Starting water hookup (July 2026 playtest pass) — placed at game start
## exactly the way a player would place one via the build menu: reuses
## BuildModeController's own wall-snap helper + spawn function, just
## triggered programmatically instead of by a click. Per Brannon's explicit
## request: west wall (-X, RockSurround.OFFSET_X), near the -Z end.
## One cell in from both walls on the base_pos so the 4-direction wall-snap
## raycast (_snap_to_nearest_wall(), 1.5m range) cleanly finds the west wall
## without the south wall/corner pillar interfering.
func _spawn_initial_water_hookup() -> void:
	var bc: BuildModeController = _build_controller as BuildModeController
	if bc == null or rock_surround == null:
		push_warning("MainWorld: _spawn_initial_water_hookup skipped — BuildModeController/rock_surround not ready.")
		return

	## BUG FIX (July 2026 playtest pass) — the hookup silently failed to
	## spawn (no wall found, push_warning only visible in the console) the
	## first time this ran. ROOT CAUSE: pregen's walls were built earlier
	## THIS SAME FRAME (_run_pregen() -> BunkerPregen.generate() ->
	## spawn_structure(), all synchronous) — Godot's physics server doesn't
	## register a newly added StaticBody3D collider for raycast queries
	## until it has actually stepped at least once. _snap_to_nearest_wall()'s
	## raycast ran before that ever happened, found nothing, and this
	## function returned early. Same exact class of bug as
	## WaterManager._on_chunk_deconstructed()'s reposition-lag fix — same
	## fix here too.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var base_pos: Vector3 = Vector3(
		rock_surround.OFFSET_X + 1.0,
		bc.WATER_HOOKUP_PLACEMENT_Y,
		rock_surround.OFFSET_Z + 2.0
	)
	var snapped: Dictionary = bc._snap_to_nearest_wall(base_pos, 0.0, 0.05, 1.5)
	if snapped.is_empty():
		push_warning("MainWorld: starting water hookup could not wall-snap — no wall found near the expected west-wall position.")
		return

	var body: Node3D = bc._spawn_placed_object(bc.TILE_WATER_HOOKUP, snapped["pos"], snapped["angle_deg"])
	## Register into _placed_objects (free of charge, no undo entry — this
	## isn't a player action) so MoveDuplicateTool can find it later, same
	## as every player-placed object.
	bc._placed_objects.append({
		"node":          body,
		"tile_id":       bc.TILE_WATER_HOOKUP,
		"price":         0,
		"world_pos":     snapped["pos"],
		"angle_deg":     snapped["angle_deg"],
		"player_placed": true,
	})


func _on_chunk_deconstructed(chunk_origin: Vector2i) -> void:
	_wire_builder._on_chunk_deconstructed(chunk_origin)
	## Water system groundwork (July 2026) — reuses this SAME boundary-change
	## event for the water hookup's outer-wall auto-tracking, rather than
	## polling or re-deriving boundary detection independently. See
	## WaterManager._on_chunk_deconstructed()/WaterHookup.reposition_to_outer_wall().
	if _water_manager != null and _water_manager.has_method("_on_chunk_deconstructed"):
		_water_manager._on_chunk_deconstructed(chunk_origin)


func _on_chunk_restored(chunk_origin: Vector2i) -> void:
	_wire_builder._on_chunk_restored(chunk_origin)
	if _water_manager != null and _water_manager.has_method("_on_chunk_restored"):
		_water_manager._on_chunk_restored(chunk_origin)




## Scans all nodes in the "pickup" group and teleports any that have fallen
## below ABYSS_Y back to the same XZ at ABYSS_RESCUE_Y.
## Called every frame from _process — cheap because get_nodes_in_group()
## returns a cached list and the abyss check is a single float comparison.
func _check_abyss_items() -> void:
	for node: Node in get_tree().get_nodes_in_group("pickup"):
		if node is Node3D:
			var item: Node3D = node as Node3D
			if item.global_position.y < ABYSS_Y:
				## Clamp XZ to bunker interior so items don't rescue outside walls.
				var rx: float = item.global_position.x
				var rz: float = item.global_position.z
				if rock_surround != null:
					var ox: float = rock_surround.OFFSET_X
					var oz: float = rock_surround.OFFSET_Z
					var depth: int = rock_surround.bunker_depth
					var width: int = rock_surround.bunker_width
					rx = clampf(rx, ox + 1.0, ox + float(depth) - 1.0)
					rz = clampf(rz, oz + 1.0, oz + float(width) - 1.0)
				var rescue_pos: Vector3 = Vector3(rx, ABYSS_RESCUE_Y, rz)
				## If it's a RigidBody3D freeze momentarily to set position cleanly
				if item is RigidBody3D:
					var rb: RigidBody3D = item as RigidBody3D
					rb.freeze             = true
					rb.freeze_mode        = RigidBody3D.FREEZE_MODE_KINEMATIC
					rb.global_position    = rescue_pos
					rb.linear_velocity    = Vector3.ZERO
					rb.angular_velocity   = Vector3.ZERO
					rb.call_deferred("set", "freeze", false)
				else:
					item.global_position = rescue_pos

func _connect_world_objects() -> void:
	# Wire prompt to interaction system
	interaction_system.prompt = interact_prompt

	# Inject player_stats into any world object that has a _player_stats property.
	# Scans both interactable and pickup groups to catch all cases.
	var all_world_nodes: Array = []
	all_world_nodes.append_array(get_tree().get_nodes_in_group("interactable"))
	all_world_nodes.append_array(get_tree().get_nodes_in_group("pickup"))
	for node in all_world_nodes:
		if "_player_stats" in node:
			node._player_stats = player_stats
