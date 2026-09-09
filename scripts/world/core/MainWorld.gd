extends Node3D
class_name MainWorld
## MainWorld.gd
## Root script for the main game world scene.

signal startup_ready

# ─── Dev Tools ────────────────────────────────────────────────────────────────
## F12 — toggle x50 time warp (speeds up clock + all stat drain)
## F11 — spawn a TestCrate in front of the player
## F9  — dump wire debug log (only useful when WIRE_DEBUG = true below)
## F7  — admin controls menu (system cheats: power, time, water)
## F1  — toggle Build Mode
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
@onready var player_medical: PlayerMedical   = $PlayerMedical
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

# ─── Storage UI (Aug 2026 — shared by Shelving and Basket, was two separate
# ShelfUI/BasketUI instances) ──────────────────────────────────────────────────
var _storage_ui: Node = null

# ─── Research Station UI (Aug 2026 — Research Station Foundation pass) ───────
var _research_ui: Node = null

# ─── Power Grid ───────────────────────────────────────────────────────────────
var _power_manager: Node = null

## Water system groundwork (July 2026) — instantiated the same way
## _power_manager is: added to scene tree, tagged "water_manager" group, NOT
## an autoload (per-world-instance state). See scripts/world/water/WaterManager.gd.
var _water_manager: Node = null

## Part A (structure refactor, Jul 2026) — see scripts/world/structure/PillarRegistry.gd
var _pillar_registry: Node = null
## Wall-locked pipe routing (Jul 2026) — see scripts/world/structure/WallPerimeterRegistry.gd
var _wall_perimeter_registry: Node = null
var _lighting_director: Node = null   ## LightingDirector.gd, built via Node.new()+set_script() same as _power_manager
var _tilt_shift_dof: TiltShiftDOF = null   ## TiltShiftDOF.gd, same dynamic-instantiation pattern
## _reconciler removed (Stage 5) — reconciler fully retired.

# ─── Admin Menu ───────────────────────────────────────────────────────────────
var _admin_cheat_menu: CanvasLayer = null

# ─── Status Screen (Aug 2026, Medical Layer 3) ───────────────────────────────
var _status_screen: CanvasLayer = null

# ─── Pause Menu ───────────────────────────────────────────────────────────────
var _pause_menu: CanvasLayer = null

# ─── Economy ──────────────────────────────────────────────────────────────────
var _cash: int = 50000   ## Starting cash; shown in HUD, spent during Build Mode

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
	_check_abyss_npcs()   ## Aug 2026 — NPC failsafe, see that function's own comment

## WireGraphBuilder.gd — auto-wire perimeter rebuild engine (Stage 10
## extraction). No state physically moved here; see WireGraphBuilder.gd
## header comment. MainWorld forwards its 3 externally-triggered entry points
## (_compute_and_rebuild_wires, _on_chunk_deconstructed, _on_chunk_restored)
## to it — everything else in that cluster is only called internally there.
var _wire_builder: WireGraphBuilder = null


func _ready() -> void:
	_wire_builder = WireGraphBuilder.new(self)
	add_to_group("main_world")   ## Lets PowerManager find us as fallback wire parent

	## NPC Pass 2, Part 1 — runtime navmesh over the dug bunker.
	var nav_script: GDScript = load("res://scripts/npc/BunkerNavMesh.gd")
	if nav_script != null:
		var navmesh_node: Node3D = Node3D.new()
		navmesh_node.set_script(nav_script)
		navmesh_node.name = "BunkerNavMesh"
		add_child(navmesh_node)

	_setup_pillar_registry()   ## Must exist before first wire/perimeter solve populates it
	_setup_wall_perimeter_registry()   ## Must exist before first wire/perimeter solve populates it
	_setup_power_manager()   ## Must be first — lights self-register in _ready()
	_setup_water_manager()
	_setup_lighting()
	_setup_lighting_director()   ## Needs "power_manager" group populated above
	_setup_tilt_shift_dof()   ## No ordering dependency — camera already exists via @onready
	_setup_ambient_dust()
	_setup_bunker_ceiling()   ## Aug 2026 — NPC/physics failsafe, see that function's own comment
	_connect_hud()
	_connect_bed()
	_connect_chair()
	_ensure_inventory_manager()
	_connect_inventory()
	## Build the full Status workspace behind the loading presentation. Its
	## inventory preview viewports and reusable controls are then ready before
	## the first Tab press instead of creating a visible post-load hitch.
	_setup_status_screen()
	_connect_world_objects()
	## StorageUI must come after inventory_manager exists and connect_world_objects
	## has registered shelf group members, so injection covers pre-placed shelves.
	_setup_storage_ui()
	_setup_trash_bag_panel()
	_setup_research_ui()
	_setup_debug_overlay()
	_register_save_fields()
	get_tree().process_frame.connect(_setup_build_mode, CONNECT_ONE_SHOT)

func _exit_tree() -> void:
	## The failsafe ceiling lives at the scene root (see _setup_bunker_ceiling)
	## so the navmesh bake never parses it — that makes it OUTLIVE this scene,
	## so free it here to avoid a stale duplicate on any scene change.
	if _bunker_ceiling != null and is_instance_valid(_bunker_ceiling):
		_bunker_ceiling.queue_free()
		_bunker_ceiling = null

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

	## Phase 4 — NPCs (NPC Pass 2, Part 6). Applied after the world exists so
	## respawned NPCs land on real floor with a valid navmesh incoming.
	## Held items are NOT persisted — NPCs reload empty-handed and re-decide
	## (FUTURE WORK: carry-state persistence if it ever matters). Claimed
	## jobs/brain state are NOT persisted either — JobBoard.get_open_jobs()
	## already auto-releases claims from freed NPCs (see JobBoard.gd), so
	## clearing-then-respawning below never leaves a job stuck.
	SaveManager.register_field(
		"npcs",
		func() -> Array: return _get_npcs_for_save(),
		func(v: Array) -> void: _restore_npcs(v),
		4)

## ── NPC save/restore (NPC Pass 2, Part 6) ───────────────────────────────────
func _get_npcs_for_save() -> Array:
	var out: Array = []
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not ("energy" in npc):
			continue
		out.append({
			"pos":           SaveManager.vec3_to_dict(npc.global_position),
			"name":          npc.npc_name,
			"energy":        npc.energy,
			"hunger":        npc.hunger,
			"thirst":        npc.thirst,
			"skills":        npc.skills.duplicate(),
			"seed":          npc.generation_seed,
			"mood":          npc.mood,
			"npc_id":        npc.npc_id,
			"relationships": npc.relationships.duplicate(),
		})
	return out

func _restore_npcs(saved: Array) -> void:
	## Clear current population first (stop activities cleanly so chairs/
	## items aren't left claimed by freed nodes, and so any job a cleared
	## NPC was working gets auto-released the next time JobBoard is polled —
	## see the phase-4 registration comment above for why that's already safe).
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		if "brain" in npc and npc.brain != null:
			npc.brain.stop_current()
		if "held_item" in npc and npc.held_item != null:
			NPCItemUser.drop_held(npc)
		npc.queue_free()

	var scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if scene == null:
		push_warning("[MainWorld] NPC.tscn missing — cannot restore NPCs")
		return
	for entry: Dictionary in saved:
		var npc: Node3D = scene.instantiate()
		add_child(npc)
		npc.global_position = SaveManager.dict_to_vec3(entry.get("pos", {}))
		npc.npc_name        = str(entry.get("name", "Survivor"))
		npc.energy          = float(entry.get("energy", 100.0))
		npc.hunger          = float(entry.get("hunger", 100.0))
		npc.thirst          = float(entry.get("thirst", 100.0))
		npc.mood            = float(entry.get("mood", 100.0))
		npc.generation_seed = int(entry.get("seed", 0))
		npc.npc_id           = str(entry.get("npc_id", npc.npc_id))
		NPC._register_id(npc.npc_id)
		npc.relationships    = (entry.get("relationships", {}) as Dictionary).duplicate()
		var sk: Dictionary  = entry.get("skills", {})
		for k: String in npc.skills.keys():
			if sk.has(k):
				npc.skills[k] = float(sk[k])

## ── Player wire save/restore (Jul 2026) ─────────────────────────────────────
## Returns every player-placed wire as a JSON-friendly array of endpoint
## position pairs. Positions (not PM keys) are the stable identity here —
## keys can be remapped by _split_wire_edge_at() over a session's lifetime,
## same reasoning _on_wire_nodes_connected()'s own comment gives for why
## _player_wire_segs stores pos_a/pos_b instead of keys.
func get_player_wires_for_save() -> Array:
	var out: Array = []
	for raw: Node in get_tree().get_nodes_in_group("wire_segment"):
		var seg := raw as WireSegment
		if seg == null or seg.is_queued_for_deletion() or not seg.player_placed:
			continue
		out.append({"pos_a": SaveManager.vec3_to_dict(seg.point_a),
			"pos_b": SaveManager.vec3_to_dict(seg.point_b)})
	return out

## Explicit delete/undo already owns the refund; discard only its tracking handle.
func forget_player_wire(seg: Node3D) -> void:
	for key: String in _player_wire_segs.keys():
		if _player_wire_segs[key].get("seg_node") == seg:
			_player_wire_segs.erase(key)

## Phase-2 endpoint-pair restore. Preserve device roles and actual endpoint Y.
## Fresh-load ownership is rebuilt; repeated restoration skips existing edges.
func restore_player_wires(data: Array) -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	pm.begin_bulk()
	for saved: Dictionary in data:
		var pos_a: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_a", {}))
		var pos_b: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_b", {}))
		var key_a: String = pm.register_wire_node(pos_a, "joint", "", true)
		var key_b: String = pm.register_wire_node(pos_b, "joint", "", true)
		var id: String = WireRoute.edge_id(key_a, key_b)
		if key_a == key_b or pm.has_wire_edge(id):
			continue
		var seg := WireSegment.new()
		seg.player_placed = true
		seg.edge_id = id
		add_child(seg)
		seg.set_endpoints(pos_a, pos_b)
		pm.register_wire_edge(key_a, key_b, seg)
		var stable_key: String = "pw_%s_%s" % [key_a, key_b]
		_player_wire_segs[stable_key] = {"pos_a": pos_a, "pos_b": pos_b,
			"seg_node": seg, "pm_edge_id": id, "stable_key": stable_key}
	pm.end_bulk()

## Create the authoritative manager before child devices register themselves.
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
	## Connect PowerManager's signals to the NotificationManager toast
	## system (UI Kit + Notifications plan, Part 3 step 4, Jul 2026) — a
	## thin adapter, all detection logic already lives in PowerManager.
	## Deferred for the same reason as above (group membership must be
	## settled before lookup).
	call_deferred("_connect_power_notification_signals")

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

## Part A (structure refactor, Jul 2026) — mirrors _setup_water_manager()'s
## shape exactly. Standalone registry, no signals — see PillarRegistry.gd.
## Must run before the first wire/perimeter solve (_wire_builder calls),
## which is why it's called before _setup_power_manager() in _ready().
func _setup_pillar_registry() -> void:
	var pr_script: GDScript = load("res://scripts/world/structure/PillarRegistry.gd")
	if pr_script == null:
		push_warning("MainWorld: PillarRegistry.gd not found — pillar clearance disabled")
		return
	_pillar_registry = Node.new()
	_pillar_registry.set_script(pr_script)
	_pillar_registry.name = "PillarRegistry"
	_pillar_registry.add_to_group("pillar_registry")
	add_child(_pillar_registry)

## Wall-locked pipe routing (Jul 2026) — mirrors _setup_pillar_registry()'s
## shape exactly. Standalone registry, no signals — see WallPerimeterRegistry.gd.
## Must run before the first wire/perimeter solve (_wire_builder calls),
## which is why it's called before _setup_power_manager() in _ready().
func _setup_wall_perimeter_registry() -> void:
	var wpr_script: GDScript = load("res://scripts/world/structure/WallPerimeterRegistry.gd")
	if wpr_script == null:
		push_warning("MainWorld: WallPerimeterRegistry.gd not found — wall-locked pipe routing disabled")
		return
	_wall_perimeter_registry = Node.new()
	_wall_perimeter_registry.set_script(wpr_script)
	_wall_perimeter_registry.name = "WallPerimeterRegistry"
	_wall_perimeter_registry.add_to_group("wall_perimeter_registry")
	add_child(_wall_perimeter_registry)

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

## Connects PowerManager signals to NotificationManager (autoload) so grid
## events surface as toasts. Added Jul 2026 (UI Kit + Notifications plan,
## Part 3 step 4) — see NotificationManager.connect_power_signals() for the
## full signal->toast mapping.
func _connect_power_notification_signals() -> void:
	if _power_manager == null:
		return
	NotificationManager.connect_power_signals()

func _on_grid_tripped() -> void:
	## Toast text for this event comes from NotificationManager (see
	## _connect_power_notification_signals()), so it is not duplicated here.
	## Camera shake (graphics plan Phase 7) — a tripped main breaker is the
	## single biggest "oh no" moment in the power system, worth a jolt.
	if camera != null:
		camera.add_trauma(0.5)

func _on_grid_restored() -> void:
	## Toast text now comes from NotificationManager — see _on_grid_tripped().
	pass

func _on_grid_offline() -> void:
	## Toast text now comes from NotificationManager — see _on_grid_tripped().
	pass

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

## Aug 2026 — replaces the former separate _setup_shelf_ui()/
## _setup_basket_ui() (each built its own ShelfUI/BasketUI CanvasLayer).
## One shared StorageUI instance now serves both. InteractionSystem.gd
## (Player-thread-owned, not touched by this change) keeps its own two
## separate properties, shelf_ui and basket_ui — both are simply pointed at
## this SAME instance below, so every existing call in that file
## (shelf_ui.is_open, basket_ui.open(...), etc.) keeps working unchanged.
func _setup_storage_ui() -> void:
	var storage_ui_script: Script = load("res://scripts/ui/inventory/StorageUI.gd")
	_storage_ui = CanvasLayer.new()
	_storage_ui.set_script(storage_ui_script)
	_storage_ui.name = "StorageUI"
	add_child(_storage_ui)

	## Inject shared refs
	_storage_ui.interaction_system = interaction_system
	_storage_ui.inventory          = inventory_manager
	var inv_hud: Node = hud.get_node_or_null("HUDRoot/InventoryHUD")
	_storage_ui.inventory_hud = inv_hud

	## Give InteractionSystem a ref so it can block input while open —
	## both properties point at the same instance, see comment above.
	interaction_system.shelf_ui  = _storage_ui
	interaction_system.basket_ui = _storage_ui

	## Inject into any shelves already in the scene (pre-placed before build mode)
	var shelves: Array = get_tree().get_nodes_in_group("shelving")
	for shelf in shelves:
		if "_storage_ui" in shelf:
			shelf.set("_storage_ui", _storage_ui)
		if "_interaction_system" in shelf:
			shelf.set("_interaction_system", interaction_system)

## Aug 2026 — the Trash Bag ambient hover panel (new UI category: proximity-
## driven, non-modal, non-input-blocking). Created once, always present,
## toggled visible by its own scan — see TrashBagInfoPanel.gd.
func _setup_trash_bag_panel() -> void:
	var panel_script: Script = load("res://scripts/ui/common/TrashBagInfoPanel.gd")
	if panel_script == null:
		return
	var panel: CanvasLayer = CanvasLayer.new()
	panel.set_script(panel_script)
	panel.name = "TrashBagInfoPanel"
	add_child(panel)
	panel.set("player_ref", player)

## Sep 2026 — the modern Research Station workspace, created once and
## injected into the spawn-time Research Station + InteractionSystem's modal
## gate.  ResearchStation remains the authority for materials, timers and
## tier state; this node is the reusable presentation/controller layer.
func _setup_research_ui() -> void:
	var ui_script: Script = load("res://scripts/ui/research/ResearchStationModernUI.gd")
	if ui_script == null:
		return
	_research_ui = CanvasLayer.new()
	_research_ui.set_script(ui_script)
	_research_ui.name = "ResearchStationModernUI"
	add_child(_research_ui)

	## Give InteractionSystem a ref so it can block E/F input while open,
	## same as shelf_ui/basket_ui (Part 7 of the plan).
	interaction_system.research_ui = _research_ui

## Sep 2026 — persistent, non-modal player Status workspace. Presentation is
## created once during world startup while the loading screen still owns the
## frame; gameplay components remain the source of truth and are injected
## before add_child() lets StatusScreenUI build its interface.
func _setup_status_screen() -> void:
	if _status_screen != null:
		return
	var ui_script: Script = load("res://scripts/ui/medical/StatusScreenUI.gd")
	if ui_script == null:
		push_warning("[Status] StatusScreenUI.gd not found")
		return
	var status: CanvasLayer = CanvasLayer.new()
	status.set_script(ui_script)
	status.name = "StatusScreenUI"
	status.set("player_medical", player_medical)
	status.set("player_stats", player_stats)
	status.set("inventory", inventory_manager)
	status.set("interaction_system", interaction_system)
	status.set("inventory_hud", hud.get_node_or_null("HUDRoot/InventoryHUD"))
	add_child(status)
	_status_screen = status

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
	# ESC / Start — toggle pause menu (only when not in build mode; build
	# mode owns its own ESC handling via BuildModeHUD for closing
	# submenus/cancelling). Start is the controller's pause button.
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.pressed \
				and event.button_index == JOY_BUTTON_START):
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

	# F9 — wire debug dump
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_dump_wire_debug()
		get_viewport().set_input_as_handled()
		return

	# Numpad 5 — add 1000w power (admin shortcut)
	if event is InputEventKey and event.pressed and event.keycode == KEY_KP_5:
		var pm: PowerManager = get_tree().get_first_node_in_group("power_manager")
		if pm != null:
			pm.admin_add_power(1000.0)
		get_viewport().set_input_as_handled()
		return

	# Numpad 2 — spawn NPC (admin shortcut)
	if event is InputEventKey and event.pressed and event.keycode == KEY_KP_2:
		_dev_spawn_npc()
		get_viewport().set_input_as_handled()
		return

	# F7 — Admin controls menu (system cheats)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F7:
		_toggle_admin_cheat_menu()
		get_viewport().set_input_as_handled()
		return

	# Tab / Gamepad Select (View/Back button) — general player Status
	# workspace. Deliberately NOT gated behind build-mode/
	# pause-menu checks the way ESC/F1 are above — StatusScreenUI is
	# non-modal by design (see its own header comment), so it's fine to allow
	# opening it more permissively. Still suppressed while build mode owns
	# input, same courtesy every other toggle here gives. Closing while open
	# is handled inside StatusScreenUI itself via _input() (see that file's
	# own comment on why it can't rely on this handler alone — Tab gets
	# eaten by Godot's built-in focus-navigation once a Button has focus) —
	# this block only ever needs to fire the OPEN path in practice.
	if (event is InputEventKey and event.pressed and event.keycode == KEY_TAB) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK):
		if not _build_mode_active:
			_toggle_status_screen()
			get_viewport().set_input_as_handled()
		return

	# F11 is now owned by DebugOverlay — do NOT handle here

func _toggle_admin_cheat_menu() -> void:
	## Lazy-init: create only on first F7 press.
	if _admin_cheat_menu == null:
		var script: GDScript = load("res://scripts/ui/menus/AdminMenu.gd")
		if script == null:
			push_warning("[DEV] AdminMenu.gd not found")
			return
		_admin_cheat_menu = CanvasLayer.new()
		_admin_cheat_menu.set_script(script)
		_admin_cheat_menu.name = "AdminMenu"
		add_child(_admin_cheat_menu)
		_admin_cheat_menu.set("world_node", self)
	if _admin_cheat_menu.has_method("toggle"):
		_admin_cheat_menu.toggle()

## Status is normally prebuilt during _ready() so its preview viewports are
## prepared behind the loading screen. The setup call remains as a defensive
## fallback for isolated/test scenes that invoke this toggle directly.
func _toggle_status_screen() -> void:
	if _status_screen == null:
		_setup_status_screen()
	if _status_screen != null and _status_screen.has_method("toggle"):
		_status_screen.toggle()

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

func _dev_spawn_npc() -> void:
	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if npc_scene == null:
		push_warning("[DEV] NPC.tscn not found — check path")
		return
	var npc: Node3D = npc_scene.instantiate()
	add_child(npc)
	npc.global_position = player.global_position \
		+ (-player.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)
	_wdbg("[DEV] Spawned NPC")

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

## Screen-space tilt-shift DOF (Aug 2026 — replaces the old
## CameraAttributesPractical distance-based DOF, see
## docs/systems/graphics/README.md). Dynamically instantiated the same way
## as LightingDirector above rather than scene-defined, so this never
## touches MainWorld.tscn or needs a manual Godot-editor step. The
## _apply_dof_setting() call after assignment guarantees the shader gets its
## initial params regardless of whether GameCamera._ready() already ran.
func _setup_tilt_shift_dof() -> void:
	var script: GDScript = load("res://scripts/core/TiltShiftDOF.gd")
	if script == null:
		push_warning("[MainWorld] TiltShiftDOF.gd not found")
		return
	var cl: CanvasLayer = CanvasLayer.new()
	cl.set_script(script)
	cl.name = "TiltShiftDOF"
	## Plan's plain `_tilt_shift_dof = CanvasLayer.new()` is a static-type
	## error (CanvasLayer.new() is typed CanvasLayer, not TiltShiftDOF) — a
	## temp var + runtime `as` cast after set_script() is the same thing with
	## the analyzer satisfied, and keeps `_tilt_shift_dof` typed TiltShiftDOF
	## so `camera.tilt_shift = _tilt_shift_dof` below stays type-safe.
	_tilt_shift_dof = cl as TiltShiftDOF
	add_child(_tilt_shift_dof)
	camera.tilt_shift = _tilt_shift_dof
	camera._apply_dof_setting()

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

## Bunker Ceiling failsafe, layer 1 (Aug 2026, Brannon-requested) — a real,
## solid, invisible StaticBody3D ceiling above the highest point ANYTHING in
## the game can otherwise reach, so a physics-glitched NPC or loose item can
## never fly up and out of the bunker into the void, permanently. Per
## Brannon: inevitable over a very long playthrough that SOME small physics
## oddity eventually launches something — the ceiling makes that harmless
## (it bounces/rests against a real collider) instead of catastrophic (gone
## forever). Primarily for NPCs, but catches any RigidBody3D the same way,
## for free — it's just solid geometry, it doesn't care what hits it.
##
## Height: RockSurround.BLOCK_Y (2.5) + BLOCK_HEIGHT/2 (2.25/2 = 1.125) =
## 3.625 is the true top surface of the rock ring — confirmed directly from
## RockSurround.gd's own constants, this project's own stated "highest point
## in the game." CEILING_Y sits well above that with generous headroom, so
## it's never visually or functionally near anything during normal play.
##
## Span: deliberately oversized (CEILING_HALF_EXTENT, 250m each direction —
## a 500x500 plane) rather than precisely computed from bunker_depth/
## bunker_width/dig_margin, so it stays correct without needing to change if
## any of those ever do — "simple and straightforward," per spec, over a
## tightly-fitted size that could go stale. Size is a non-issue now that the
## box is OUT of the navmesh bake (see _exit_tree note below): a static box
## costs one broadphase AABB and nothing on the GPU.
##
## collision_layer = 5 / collision_mask = 0 — the exact same convention
## every other piece of solid level geometry in this project already uses
## (floor tiles, walls, pillars, furniture StaticBodies) — guaranteed
## compatible with NPCs/player (default layer 1, mask 1) and every loose
## RigidBody3D already colliding with that same existing geometry, with zero
## new layer bookkeeping introduced.
##
## Aug 2026 — the ceiling is parented to the SCENE ROOT, not to this node,
## deliberately: BunkerNavMesh._rebake() calls
## NavigationServer3D.parse_source_geometry_data() over the "main_world"
## subtree and rasterizes every static collider matching mask 1 into a GPU
## voxel grid. A 500x500 box at cell_size 0.1 is ~5000x5000 voxels per
## layer — enough to run the GPU voxelizer out of memory and hard-crash
## (signal 11) on the rendering device (the observed startup crash). Living
## outside the parsed subtree keeps the failsafe fully functional in physics
## while costing literally zero in the bake. Freed in _exit_tree() so it
## never leaks across a scene change.
const CEILING_Y: float = 15.0
const CEILING_HALF_EXTENT: float = 250.0
const CEILING_THICKNESS: float = 1.0

var _bunker_ceiling: StaticBody3D = null

func _setup_bunker_ceiling() -> void:
	if rock_surround == null:
		return
	var center_x: float = rock_surround.OFFSET_X + float(rock_surround.bunker_depth) * 0.5
	var center_z: float = rock_surround.OFFSET_Z + float(rock_surround.bunker_width) * 0.5

	var ceiling_body: StaticBody3D = StaticBody3D.new()
	ceiling_body.name = "BunkerCeiling"
	ceiling_body.collision_layer = 5
	ceiling_body.collision_mask = 0
	## Aug 2026 — physics-ONLY failsafe group. Gameplay raycasts (build
	## placement/hover, wire placement) exclude every member of this group, so
	## a failsafe can never become a build target while still catching physics
	## bodies. See BuildModeController.get_failsafe_exclude_rids().
	ceiling_body.add_to_group("physics_failsafe")
	## Parent to the scene root (NOT this node) so BunkerNavMesh's bake —
	## which parses the "main_world" subtree — never rasterizes this box.
	get_tree().root.add_child(ceiling_body)
	ceiling_body.position = Vector3(center_x, CEILING_Y, center_z)
	_bunker_ceiling = ceiling_body

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(CEILING_HALF_EXTENT * 2.0, CEILING_THICKNESS, CEILING_HALF_EXTENT * 2.0)
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = shape
	ceiling_body.add_child(collision_shape)

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

	## Need-cap rendering (Aug 2026, Medical system) — see
	## docs/systems/medical/README.md's "Needs cap reduction."
	player_stats.food_cap_changed.connect(func(v: float)  -> void: hud.set_food_cap(v))
	player_stats.water_cap_changed.connect(func(v: float) -> void: hud.set_water_cap(v))
	player_stats.sleep_cap_changed.connect(func(v: float) -> void: hud.set_sleep_cap(v))

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
		## Animated stand-up off the bed. Clearing sleeping_bed makes
		## the shared controller play sit_to_stand and ease seat→approach; keep
		## the player frozen, then snap to the stand position + unfreeze when the
		## clip finishes — mirrors _wire_chair's stand flow.
		player.sleeping_bed = null
		var b: Node = sleep_overlay.bed
		var model: Node = player.get_node_or_null("PlayerModel")
		if b != null and is_instance_valid(b) \
				and model != null and model.has_signal("stand_animation_finished"):
			var the_bed: Node = b
			model.stand_animation_finished.connect(func() -> void:
				## Aug 2026 — snap to the EXACT position the standing animation
				## leaves the player at (the end of the seat->approach ease),
				## not a separate fixed point — no teleport away from where the
				## animation ended.
				if model.has_method("get_stand_end_position"):
					player.global_position = model.get_stand_end_position()
				else:
					player.global_position = the_bed.get_bed_stand_position()
				## Aug 2026 — face the direction the standing animation ENDED
				## facing (not the pre-sleep facing), so the player continues
				## from the pose the animation left them in.
				if model.has_method("get_visual_yaw"):
					player.rotation.y = model.get_visual_yaw()
				player.set_physics_process(true)
			, CONNECT_ONE_SHOT)
		else:
			## Fallback — old immediate behavior, better than getting stuck.
			player.set_physics_process(true)
	)

	# Connect all existing beds in the "bed" group.
	# Also called again when new beds are placed (see _wire_bed).
	for b: Node in get_tree().get_nodes_in_group("bed"):
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
		## Aug 2026 — animated sit-down onto the bed (mirrors _wire_chair's seat
		## flow). The player sits on the bed's SIDE, facing outward on whichever
		## side they approached from; the controller eases them from an approach
		## point just off the bed to the sheets position over stand_to_sit.
		## The mattress top = the chair seat height, so the controller's seated-Y
		## math is reused unchanged.
		## Aug 2026 fix — side detection is done in the BED'S LOCAL frame: the
		## world-Z comparison picked the wrong side for rotated beds (a bed at
		## ~90-225° yaw put the player on the opposite side). The bed's local
		## +Z/-Z are its two long sides (the width), so the sign of the player's
		## bed-local Z is the correct side at ANY rotation.
		var side: float = -1.0
		var bed_local: Vector3 = (the_bed as Node3D).global_transform.affine_inverse() \
			* player.global_position
		if bed_local.z >= 0.0:
			side = 1.0
		var t: Transform3D = the_bed.get_sheets_transform(side)
		player.rotation.y = t.basis.get_euler().y
		var model: Node = player.get_node_or_null("PlayerModel")
		if model != null:
			const APPROACH_OFFSET: float = 0.4   ## ~half a bed width — same as _wire_chair
			var approach_pos: Vector3 = t.origin + t.basis.z * APPROACH_OFFSET
			approach_pos.y = player.global_position.y
			model.set("_chair_approach_pos", approach_pos)
			model.set("_chair_seat_pos", Vector3(t.origin.x, approach_pos.y, t.origin.z))
			## Side turn for the lying-down clip: rotate side×90° to face AWAY
			## from the headboard over its first 1/3.
			model.set("_lie_rot_angle", side * PI * 0.5)
		player.sleeping_bed = the_bed   ## starts the controller's sitting_down phase
		player.set_physics_process(false)
		sleep_overlay.begin_sleep()
	)
	if bed.has_signal("wake_requested"):
		bed.wake_requested.connect(sleep_overlay.request_wake)

func _connect_chair() -> void:
	# Wire all existing chairs in the "chair" group.
	# Also called again when new chairs are placed (see Part 3 note on call sites).
	for c: Node in get_tree().get_nodes_in_group("chair"):
		_wire_chair(c)

## Wires a single chair node to the seat/stand system. Guarded the same way
## _wire_bed() is, so re-calling on already-wired chairs (e.g. after a new
## chair is placed) is a safe no-op.
func _wire_chair(chair: Node) -> void:
	if chair == null or not chair.has_signal("seat_requested"):
		return
	if chair.has_meta("_seat_wired"):
		return
	chair.set_meta("_seat_wired", true)

	var the_chair: Node = chair
	## Aug 2026 fix — previously snapped player.global_position to
	## get_seat_transform()'s elevated seat-height Y the INSTANT E was
	## pressed, before any animation played — so "standing" at the start
	## of stand_to_sit rendered at seat height instead of the floor, and
	## (symmetrically) the end of sit_to_stand rendered "halfway in the
	## seat" until the position got released. Root cause: with the Hip
	## root-offset fix (see docs/systems/player-model/README.md "Sit
	## animation root-offset fix"), the animation's OWN baked Hip motion
	## already correctly shows the full rise/lower between standing and
	## seated heights relative to a FIXED floor-level anchor — exactly the
	## same convention idle/walk/run already use (their root motion is
	## never consumed either). The game code doesn't need to move the Y
	## (height) anchor at all during the sit sequence — the clip does that.
	## X/Z DO still need to snap here though (Aug 2026, 2nd pass): without
	## it the player keeps whatever horizontal spot they were standing at
	## when they pressed E, which usually isn't centered on the seat.
	## Aug 2026 fix (2nd pass) — no longer snaps X/Z instantly either. The
	## player's CURRENT position (wherever they were standing when they
	## pressed E — already near the chair, since interaction range put
	## them there) becomes the "approach" anchor; the chair's own seat X/Z
	## becomes the "seat" anchor. AdventurerModelController eases the
	## player smoothly between the two, in sync with the stand_to_sit /
	## sit_to_stand clip's own playback progress (see _lerp_sit_xz() in
	## that file) — sitting down eases back into the chair, standing up
	## eases forward off it, instead of either direction snapping.
	chair.seat_requested.connect(func() -> void:
		if the_chair.has_method("set_seated"):
			the_chair.set_seated(true)
		var t: Transform3D = the_chair.get_seat_transform()
		player.rotation.y = t.basis.get_euler().y
		the_chair.set_meta("_seated_facing_y", player.rotation.y)   ## NEW — restored on stand
		p…32675 tokens truncated…= 5
const SHED_END_PRIORITY:   int = 2
## Residual watts a shed LIGHT still draws (orange-dim glow) during overloaded.
## Small enough not to matter for balance but shows up correctly on the HUD.
## Non-light appliances draw 0W when shed — see _shed_residual_watts().
const SHED_WATTS: float = 5.0

## Light device types. Lights are still eligible for shedding like everything
## else; this set ONLY distinguishes their shed visual/residual draw (they dim
## to SHED_WATTS) from non-light appliances (which switch fully OFF / 0W).
const LIGHT_TYPES: Array[String] = [
	"wall_light",
	"bed_lamp",
	"emergency_light",
	"grow_light",
]

## Flicker sequence timing — kept short so overload response feels instant.
const FLICKER_TOTAL_SECS:   float = 0.5  ## total flicker duration before going dark
const FLICKER_ON_DURATION:  float = 0.08 ## how long lights stay on each pulse
const FLICKER_OFF_DURATION: float = 0.10 ## how long lights stay off each pulse

## WATT_RATINGS / DEFAULT_PRIORITY_BY_TYPE / GENERATOR_TIERS moved to the
## DeviceDatabase autoload (Stage 9, July 2026) — pure config data, unrelated
## to grid logic, was growing this file for reasons that had nothing to do
## with the solver. Read via DeviceDatabase.WATT_RATINGS etc. from anywhere;
## no PowerManager dependency needed. See DeviceDatabase.gd header comment.


# ═══════════════════════════════════════════════════════════════════════════════
# RUNTIME STATE
# ═══════════════════════════════════════════════════════════════════════════════

var grid_state: GridState = GridState.ONLINE

## Timers
var _overload_timer:    float = 0.0
## -1.0 = no pending priority-change resolve queued. >= 0.0 = counting down.
var _priority_grace_timer: float = -1.0
## Consumer ids whose component needs _reset_shed_for_consumer_component()
## once the grace timer above elapses. Cleared after each resolve.
var _pending_priority_reset_ids: Dictionary = {}
var _main_reset_timer:  float = 0.0

## Flicker sequence state.
var _flickering:         bool  = false   ## true while flicker→offline is playing
var _flicker_timer:      float = 0.0    ## total elapsed flicker time
var _flicker_pulse_t:    float = 0.0    ## time within current on/off pulse
var _flicker_pulse_on:   bool  = true   ## current pulse is "lights on"

## Re-entry guard — prevents _solve_network → _go_offline → _solve_network loops.
var _solving:            bool  = false

## Deferred-resolve flag — set by _tick_batteries when all batteries die so
## _solve_network() runs once at the END of _process(), not inside the tick.
var _needs_resolve:      bool  = false

## Bulk-edit guard — when > 0, _solve_network() defers instead of solving
## synchronously, coalescing a burst of topology changes (e.g. the dozens of
## register_wire_node/edge calls inside MainWorld._rebuild_auto_wires) into a
## SINGLE solve at end_bulk().  Nested begin_bulk/end_bulk are reference-counted.
## Behavior is identical to the old per-call solve — same final state, far fewer
## redundant intermediate solves per frame.
var _bulk_depth:         int   = 0

## ── Sustained-brownout latch (cross-zone exhaustion) ──────────────────────────
## When a CROSS-ZONE component runs out of generators + battery, it does NOT go
## fully OFFLINE — instead all its consumers are forced to the SHED (dim-orange)
## visual and its feeding generators are tripped.  The component stays in this
## "exhausted brownout" state until a generator is MANUALLY restarted (which
## clears the matching latch key).  Keyed by a stable, sorted component key so
## the state survives across re-solves even as imported/exported watts fluctuate.
##   key (String, sorted node-set signature) → true
var _exhausted_brownout_keys: Dictionary = {}

## Computed totals (recalculated by _solve_network)
var active_draw_watts:    float = 0.0
var total_capacity_watts: float = 0.0

# ─── Consumer registry ────────────────────────────────────────────────────────
## id (String = str(node.get_instance_id())) → Dictionary:
## {
##   "id":        String
##   "watts":     float
##   "active":    bool    — true = device is switched on
##   "node":      Node
##   "type":      String
##   "priority":  int     — 1 (critical) … 5 (luxury)
##   "shed":      bool    — true = currently load-shed (lights only)
##   "powered":   bool    — true = currently receiving power (graph + state)
## }
var _consumers: Dictionary = {}

# ─── Generator registry ───────────────────────────────────────────────────────
## id → Dictionary:
## {
##   "id", "watts", "node", "running", "backup",
##   "fuel" (0–100), "health" (0–100), "auto_started"
## }
var _generators: Dictionary = {}

## Wire node key for the F7 admin-cheat generator (admin_add_power()) — empty
## string when no admin power has been added yet. See admin_add_power().
var _admin_gen_wire_key: String = ""

# ─── Battery registry ─────────────────────────────────────────────────────────
## id → { "id", "capacity_wh", "charge_wh", "node", "discharging" }
var _batteries: Dictionary = {}

# ─── Wire graph ───────────────────────────────────────────────────────────────

## Wire nodes — snap-point positions that form graph vertices.
## key: snap_key string (e.g. "8,0,12")
## value:
## {
##   "key":       String  — snap key (= dict key, stored for convenience)
##   "pos":       Vector3 — world position
##   "role":      String  — "consumer" | "generator" | "battery" | "breaker" | "joint"
##   "device_id": String  — links to _consumers / _generators / _batteries (or "")
##   "reachable": bool    — set by solver; true = connected to a live generator
## }
var _wire_nodes: Dictionary = {}

## Wire edges — placed wire segments connecting two nodes.
## key: edge_id string
## value:
## {
##   "id":     String
##   "node_a": String  — snap key of endpoint A
##   "node_b": String  — snap key of endpoint B
##   "load_w": float   — watts currently flowing (computed by solver)
##   "node":   Node    — scene node (WireSegment visual); may be null
## }
var _wire_edges: Dictionary = {}

## PowerGraph.gd — wire-node/wire-edge topology CRUD (Stage 5 extraction).
## _wire_nodes/_wire_edges above stay physically owned here (see PowerGraph.gd
## header comment for why); the graph instance reaches into them via its own
## _owner back-reference. PowerManager forwards its public wire-graph API to
## this instance so external call sites are unaffected.
var _graph: PowerGraph = null

## PowerRegistry.gd — consumer/generator/battery registration CRUD (Stage 8
## first slice). _consumers/_generators/_batteries above stay physically
## owned here (see PowerRegistry.gd header comment for why); the registry
## instance reaches into them via its own _owner back-reference. PowerManager
## forwards its public consumer/generator/battery API to this instance so
## external call sites are unaffected.
var _registry: PowerRegistry = null

## PowerSolver.gd — 3-pass zone solver, load-shedding, brownout, upgraded-
## breaker self-trip (Stage 8b extraction). No dicts/consts physically moved
## here either — see PowerSolver.gd header comment. PowerManager forwards the
## handful of solver methods still called from code living here (the rest are
## only called internally within PowerSolver itself).
var _solver: PowerSolver = null

## ZoneCustomization.gd — player-set zone name/color overrides (July 2026, new
## self-contained feature, NOT an extraction). See that file's header for the
## zone_key identity scheme. PowerManager forwards get_zone_display_name()/
## set_zone_name()/get_zone_color_override()/set_zone_color_override()/
## zone_display_color() to it.
var _zone_custom: ZoneCustomization = null

## Circuit breakers — live on a wire node and open the graph at that point.
## key: breaker_id string
## value:
## {
##   "id":       String
##   "node_key": String  — snap key of the wire node this breaker sits on
##   "tripped":  bool
##   "node":     Node    — scene node
## }
var _breakers: Dictionary = {}

## Adjacency list built by _build_adjacency() and consumed by BFS solver.
## snap_key → Array[snap_key]  (only live, unblocked edges)
var _adjacency: Dictionary = {}

## Generator-only adjacency — same as _adjacency but also blocks breakers
## where pass_generator=false.  Used to limit generator BFS reach.
var _adjacency_gen: Dictionary = {}

## Consumer wire-key lookup cache for the charge path in _tick_batteries().
## consumer_id → first wire node key for that consumer.
## Cleared whenever topology changes (same timing as _zone_cache_valid).
var _charge_consumer_wire_key_cache: Dictionary = {}

## Set of snap keys that are reachable from a generator (result of last solve).
var _reachable: Dictionary = {}   ## snap_key → true

## ─── Zone color registry ─────────────────────────────────────────────────────
## Stable color assignment across topology changes (wire placement, removal,
## absorption). Maps a zone's "representative edge" (lexicographically smallest
## edge_id in that zone) → color_index (int, 0–5).
##
## Absorption rule: when two previously-separate zones merge into one (because
## a connecting wire is placed), the LARGER zone's color_index wins — the
## smaller zone's representative is removed from the registry and all its wires
## adopt the larger zone's color.  This prevents "new zone = new color" flicker
## and makes it obvious to the player that they just grew an existing grid.
##
## On undo: BuildModeController snapshots this dict before each wire placement
## and restores it (via restore_zone_colors) on undo.  The registry is then
## coherent with the pre-placement topology and _recolor_wire_zones() redisplays
## the exact original colors.
var _zone_color_registry: Dictionary = {}   ## zone_sig → color_index (int)
## zone_sig = sorted breaker node keys joined by "|", e.g. "-5,4,18|-6,4,50"
## For a zone with no bounding breakers (full perimeter) the sig is "__MAIN__".
## Breaker node keys are position-based and survive any auto-wire rebuild,
## making this registry stable across full perimeter teardown/rebuild cycles.
## (Old scheme keyed on rep_edge_id which changed every rebuild → color flips.)

## ─── Zone membership cache ────────────────────────────────────────────────────
## Caches get_wire_zones() output so _tick_batteries() doesn't re-run the full
## BFS graph partition every frame.  Invalidated by _solve_network().
var _zone_cache: Array[Dictionary] = []
var _zone_cache_valid: bool        = false
## Maps snap key → index into _zone_cache for O(1) lookup.
var _node_to_zone_idx: Dictionary  = {}   ## snap_key → int

## ─── Connected-component cache ────────────────────────────────────────────────
## Caches _find_components() output (full-connectivity flood over _adjacency,
## ignores breakers) so _tick_batteries() doesn't re-flood the whole graph every
## frame.  Invalidated at the SAME point as _zone_cache (in _solve_network()).
## NOTE: components are keyed on _adjacency, which is rebuilt by _build_adjacency()
## inside _solve_network() — so invalidating here keeps the cache in lock-step.
var _component_cache: Array[Dictionary] = []
var _component_cache_valid: bool        = false

## ─── Wire debug log buffer ────────────────────────────────────────────────────
## All [PM:*] log lines go here instead of printing live.
## Cleared at begin_bulk() (start of each rebuild window).
## Flushed and returned by dump_wire_log() which MainWorld's F9 handler calls.
var _pm_wire_log: Array[String] = []

## Internal helper — appends msg only when WIRE_DEBUG is true.
func _pmdbg(msg: String) -> void:
	if WIRE_DEBUG:
		_pm_wire_log.append(msg)

## Returns all buffered PM wire-debug lines as an Array[String] and clears
## the buffer.  Called by MainWorld._dump_wire_debug() on F9.
## Also dumps a snapshot of the current graph state (node count, edge count,
## zone registry entries, consumer registrations).
func dump_wire_log() -> Array:
	var out: Array = _pm_wire_log.duplicate()
	_pm_wire_log.clear()
	## Append graph-state snapshot so each F9 dump is self-contained.
	out.append("── PM GRAPH SNAPSHOT ───────────────────────────────────────")
	out.append("  wire_nodes  : %d" % _wire_nodes.size())
	out.append("  wire_edges  : %d" % _wire_edges.size())
	out.append("  breakers    : %d" % _breakers.size())
	out.append("  consumers   : %d" % _consumers.size())
	out.append("  generators  : %d" % _generators.size())
	out.append("  batteries   : %d" % _batteries.size())
	out.append("  zone_registry entries: %d" % _zone_color_registry.size())
	for sig: String in _zone_color_registry:
		out.append("    reg[sig=%s] = color %d" % [sig, int(_zone_color_registry[sig])])
	out.append("  grid_state  : %s" % get_grid_state_string())
	out.append("  active_draw : %.1fw / %.1fw cap" % [active_draw_watts, total_capacity_watts])
	out.append("────────────────────────────────────────────────────────────")
	return out


# ═══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════════

## Grid-level
signal grid_state_changed(new_state: GridState, old_state: GridState)
signal draw_changed(active_watts: float, capacity_watts: float, battery_pct: float)
signal grid_tripped
signal grid_restored
signal grid_offline
signal overloaded_started
signal overloaded_ended

## Consumer
signal consumer_registered(id: String, watts: float, priority: int)
signal consumer_unregistered(id: String)
## Emitted whenever a consumer's power priority is changed by the player UI.
signal consumer_priority_changed(id: String, priority: int)

## Generator
signal generator_registered(gen_id: String, watts: float, is_backup: bool)
signal generator_unregistered(gen_id: String)
signal generator_started(gen_id: String)
signal generator_stopped(gen_id: String, reason: String)
signal generator_fuel_low(gen_id: String, fuel_pct: float)

## Battery
signal battery_registered(bat_id: String, capacity_wh: float)
signal battery_unregistered(bat_id: String)
signal battery_low(bat_id: String, charge_pct: float)
signal battery_state_changed(bat_id: String, discharging: bool)
## Fired when a battery's charge reaches exactly 0.  The battery node should
## switch to a visually distinct "DRAINED" state (e.g. red LED, dead display).
signal battery_drained(bat_id: String)

## Wire / graph
signal wire_edge_registered(edge_id: String)
signal wire_edge_unregistered(edge_id: String)
signal wire_node_registered(node_key: String)
signal wire_node_unregistered(node_key: String)

## Breakers
signal breaker_tripped(breaker_id: String)
signal breaker_reset(breaker_id: String)

## Zone customization (July 2026) — fired by set_zone_color_override()/
## set_zone_name() so any interested listener (BuildModeController repaints
## world wire tubes; PowerTerminalUI/BreakerBox/DebugOverlay just re-read live
## data on their own next redraw, so they don't strictly need this signal, but
## it's here for any future listener) can react immediately without polling.
signal zone_color_changed(zone_key: String)
signal zone_name_changed(zone_key: String)


# ═══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_graph = PowerGraph.new(self)
	_registry = PowerRegistry.new(self)
	_solver = PowerSolver.new(self)
	_zone_custom = ZoneCustomization.new(self)
	pass   ## No default zone — graph starts empty.

func _process(delta: float) -> void:
	_tick_generators(delta)
	_tick_batteries(delta)

	## If _tick_batteries flagged a resolve (all batteries died), run it now —
	## once per frame rather than every frame inside the tick loop.
	if _needs_resolve:
		_needs_resolve = false
		_solve_network()

	## Priority-change grace period — fire the deferred reset+resolve once the
	## timer elapses (see set_consumer_priority()). Runs regardless of
	## _flickering below; _solve_network() already no-ops safely mid-flicker.
	if _priority_grace_timer >= 0.0:
		_priority_grace_timer -= delta
		if _priority_grace_timer <= 0.0:
			_priority_grace_timer = -1.0
			for pending_id: String in _pending_priority_reset_ids.keys():
				_reset_shed_for_consumer_component(pending_id)
			_pending_priority_reset_ids.clear()
			_solve_network()

	## Flicker sequence overrides everything else.
	if _flickering:
		_tick_flicker(delta)
		return

	match grid_state:
		GridState.BROWNOUT:
			## NOTE: this arm is structurally unreachable and intentionally
			## left as a defensive no-op, not deleted. grid_state can only
			## ever become BROWNOUT inside _start_flicker_offline(), which
			## always sets _flickering = true in that same call — so by the
			## time any _process() tick observes grid_state == BROWNOUT,
			## the "if _flickering: ...; return" guard above this match has
			## already returned early. The real BROWNOUT → TRIPPED
			## transition happens via _tick_flicker() completing and calling
			## _go_offline(), which calls _trip_main_grid() when there's no
			## local battery left to fall back on (see that function).
			pass
		GridState.TRIPPED:
			if MAIN_AUTO_RESET_SECS > 0.0:
				_main_reset_timer += delta
				if _main_reset_timer >= MAIN_AUTO_RESET_SECS:
					reset_main_breaker()
		_:
			pass


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — WIRE GRAPH
# ═══════════════════════════════════════════════════════════════════════════════

## ─────────────────────────────────────────────────────────────────────────────
## WIRE GRAPH — forwarded to PowerGraph.gd (Stage 5 extraction, see
## REVIEW_IMPLEMENTATION_PLAN.md). Signatures identical to before the split —
## every external call site (BreakerBox, WallLight, GeneratorObject,
## BuildModeController, MainWorld, etc.) needs zero changes.
## ─────────────────────────────────────────────────────────────────────────────

func register_wire_node(pos: Vector3, role: String, device_id: String = "", preserve_height: bool = false) -> String:
	return _graph.register_wire_node(pos, role, device_id, preserve_height)

func get_wire_node_role(node_key: String) -> String:
	return _graph.get_wire_node_role(node_key)

func get_wire_node_pos(node_key: String) -> Vector3:
	return _graph.get_wire_node_pos(node_key)

func get_wire_node_key_at_pos(pos: Vector3) -> String:
	return _graph.get_wire_node_key_at_pos(pos)

func has_wire_node_at_pos(pos: Vector3) -> bool:
	return _graph.has_wire_node_at_pos(pos)

func unregister_wire_node(node_key: String) -> void:
	_graph.unregister_wire_node(node_key)

func register_wire_edge(
		node_a_id:  String,
		node_b_id:  String,
		scene_node: Node  = null,
		no_visual:  bool  = false) -> String:
	return _graph.register_wire_edge(node_a_id, node_b_id, scene_node, no_visual)

func unregister_wire_edge(edge_id: String) -> void:
	_graph.unregister_wire_edge(edge_id)

func has_wire_edge(edge_id: String) -> bool:
	return _graph.has_wire_edge(edge_id)


## Register a circuit breaker on an existing wire node.
## Returns breaker_id — store it to trip/reset/unregister later.
## Also splits any existing wire edge whose A→B segment passes through the
## breaker's snap point, so the breaker becomes a true cut-point in the graph.
func register_breaker(wire_node_key: String, scene_node: Node = null) -> String:
	if not _wire_nodes.has(wire_node_key):
		push_warning("PowerManager: breaker registered on unknown node '%s'" % wire_node_key)
		push_warning("PowerManager: register_breaker failed — node_key '%s' not in _wire_nodes." % wire_node_key)
		return ""
	var bid: String = "brk_%s" % wire_node_key
	_breakers[bid] = {
		"id":            bid,
		"node_key":      wire_node_key,
		"tripped":       false,
		"node":          scene_node,
		"pass_battery":  true,   ## allow battery current through (player-toggled)
		"pass_generator": true,  ## allow generator current through (player-toggled)
		"upgraded":      false,  ## smart breaker — self-trips to isolate on cross-zone
		                         ## exhaustion instead of allowing the standard shared
		                         ## sustained-brownout (see set_breaker_upgraded()).
		"trip_group_key": "",    ## non-empty while self-tripped as part of a group —
		                         ## lets reset_breaker() find + reset every breaker that
		                         ## isolated the SAME exhaustion event together, instead
		                         ## of leaving siblings stuck tripped. See
		                         ## _reset_upgraded_breaker_group().
		"pretrip_pass_battery":  true,  ## pass_battery value at the moment of self-trip —
		                                ## restored on group reset instead of leaving the
		                                ## forced-off value in place.
		"pretrip_pass_generator": true, ## same, for pass_generator.
	}
	## Update the wire node's role so adjacency builder knows it's a breaker point.
	_wire_nodes[wire_node_key]["role"] = "breaker"

	## Split any wire edge that passes through this snap point so the breaker
	## is a genuine cut-point rather than floating beside the wire.
	_graph._split_wire_edge_at(wire_node_key)

	## Re-solve now that topology has changed (split added new edges/cut-point).
	_solve_network()
	return bid


## Safely read a stored scene node out of a registry dict.
## Many dicts (_wire_edges, _consumers, _generators, _batteries, _breakers)
## cache a "node" reference that can be queue_free()'d elsewhere while the dict
## entry lingers.  Reading such a freed object into a TYPED Node variable throws
## "Trying to assign invalid previously freed instance".  This helper reads the
## value untyped, validates it, and returns null when the instance is dead —
## so callers can assign the result into a typed Node var without crashing.
func _safe_dict_node(d: Dictionary, key: String = "node") -> Node:
	var raw: Variant = d.get(key)
	if raw == null:
		return null
	if not is_instance_valid(raw):
		return null
	return raw as Node


## PUBLIC wrapper around PowerGraph._split_wire_edge_at() — forwarded to
## PowerGraph.gd (Stage 5 extraction). Currently unused/dead in-repo but kept
## as public API (was already unreferenced before the split — see review notes).
func resplit_breaker(node_key: String) -> void:
	_graph.resplit_breaker(node_key)


func unregister_breaker(breaker_id: String) -> void:
	if not _breakers.has(breaker_id):
		return
	var mid_key: String = _breakers[breaker_id]["node_key"]
	_breakers.erase(breaker_id)

	## ── Re-stitch the split wire edge ────────────────────────────────────────
	## When the breaker was placed, _split_wire_edge_at() removed the original
	## A→B edge and created A→mid and mid→B.  On removal we must invert that:
	## find both half-edges, recover their far endpoints (A and B), preserve the
	## scene node (the wire mesh lives on the A→mid edge), remove both halves,
	## and register a single A→B edge so the zone stays connected.
	var far_a: String = ""   ## endpoint on the A side
	var far_b: String = ""   ## endpoint on the B side
	var orig_scene: Node = null

	for edge: Dictionary in _wire_edges.values():
		if edge["node_a"] == mid_key:
			var far: String = edge["node_b"]
			if far == mid_key:
				continue   ## degenerate self-loop, ignore
			## Decide which side is A vs B: we just need two distinct far keys.
			if far_a.is_empty():
				far_a = far
				if orig_scene == null:
					orig_scene = _safe_dict_node(edge)
			elif far_b.is_empty() and far != far_a:
				far_b = far
		elif edge["node_b"] == mid_key:
			var far: String = edge["node_a"]
			if far == mid_key:
				continue
			if far_a.is_empty():
				far_a = far
				if orig_scene == null:
					orig_scene = _safe_dict_node(edge)
			elif far_b.is_empty() and far != far_a:
				far_b = far

	## Only stitch when exactly two distinct far endpoints were found (the
	## normal case after a clean split).  If the breaker was placed on a
	## T-junction or had extra manual edges, leave the topology as-is — the
	## mid node role reverts to "joint" below and BFS still flows through it.
	if not far_a.is_empty() and not far_b.is_empty() and far_a != far_b:
		## Collect the M→B spawned WireSegment so we can free it after
		## stitching.  The A→M node (orig_scene) becomes the merged A→B tube;
		## the M→B node is no longer needed once the breaker is gone.
		var mb_scene_to_free: Node = null
		for e2: Dictionary in _wire_edges.values():
			if (e2["node_a"] == mid_key or e2["node_b"] == mid_key) \
					and e2.get("node") != null and e2.get("node") != orig_scene:
				mb_scene_to_free = _safe_dict_node(e2)
				break

		## Null out the scene node ref on both half-edges BEFORE removing them
		## so _remove_wire_edge_internal does NOT queue_free the wire mesh —
		## we're handing it off to the new merged edge.
		for eid: String in _wire_edges.keys():
			var e: Dictionary = _wire_edges[eid]
			if (e["node_a"] == mid_key or e["node_b"] == mid_key) \
					and e.get("node") != null:
				_wire_edges[eid]["node"] = null

		## Remove all edges that touch mid_key (the two split halves).
		## We use the internal helper directly to skip the scene-node free
		## (already nulled above) and skip the dangling-joint prune for
		## the intermediate nodes which belong to the merged edge.
		var to_remove: Array[String] = []
		for edge: Dictionary in _wire_edges.values():
			if edge["node_a"] == mid_key or edge["node_b"] == mid_key:
				to_remove.append(edge["id"])
		for eid: String in to_remove:
			_graph._remove_wire_edge_internal(eid, true)   ## is_split=true → no scene free, no prune

		## Remove the breaker wire node itself.
		_wire_nodes.erase(mid_key)
		wire_node_unregistered.emit(mid_key)

		## Re-register the merged A→B edge, preserving the original wire mesh.
		var merged_parts: Array[String] = [far_a, far_b]
		merged_parts.sort()
		var merged_id: String = "e_%s__%s" % [merged_parts[0], merged_parts[1]]
		if not _wire_edges.has(merged_id):
			_wire_edges[merged_id] = {
				"id":     merged_id,
				"node_a": far_a,
				"node_b": far_b,
				"load_w": 0.0,
				"node":   orig_scene,
			}
			## Update the scene node's edge_id so _recolor_wire_zones() finds it.
			if orig_scene != null and is_instance_valid(orig_scene) \
					and "edge_id" in orig_scene:
				orig_scene.set("edge_id", merged_id)
			## Restore orig_scene endpoints to span the full A→B range again.
			## When the breaker was placed, set_endpoints() shrank it to A→M;
			## now the breaker is gone so we re-expand it to A→B.
			if orig_scene != null and is_instance_valid(orig_scene) \
					and orig_scene.has_method("set_endpoints") \
					and _wire_nodes.has(far_a) and _wire_nodes.has(far_b):
				orig_scene.call("set_endpoints",
					_wire_nodes[far_a]["pos"], _wire_nodes[far_b]["pos"])
			## Free the M→B spawned WireSegment — it only existed while the
			## breaker was present to colour the B-side of the split.
			if mb_scene_to_free != null and is_instance_valid(mb_scene_to_free):
				mb_scene_to_free.queue_free()
			wire_edge_registered.emit(merged_id)
	else:
		## Fallback: could not find two clean far endpoints (breaker on a
		## terminal node, T-junction, etc).  Revert role to joint so BFS
		## still treats it as passable.
		if _wire_nodes.has(mid_key):
			_wire_nodes[mid_key]["role"] = "joint"

	_solve_network()


## Trip a circuit breaker (player interacts, or called by event).
## Triggers full re-solve — everything past this point loses power.
func trip_breaker(breaker_id: String) -> void:
	if not _breakers.has(breaker_id):
		return
	if _breakers[breaker_id]["tripped"]:
		return
	_breakers[breaker_id]["tripped"] = true
	_notify_breaker_node(breaker_id, true)
	breaker_tripped.emit(breaker_id)
	_solve_network()


## Reset a circuit breaker (player interacts at the physical breaker, or
## clicks RESTART on an upgraded/smart breaker's panel).
##
## If this breaker self-tripped as part of an upgraded-breaker exhaustion
## event (trip_group_key non-empty), resetting it resets the WHOLE GROUP —
## every other breaker that isolated the same event together — and restores
## each breaker's pre-trip pass_battery/pass_generator values instead of
## leaving them forced off. See _reset_upgraded_breaker_group().
##
## After the group (or single breaker) is un-tripped, ONE _solve_network()
## runs. The solver is fully stateless per-solve for the upgraded-breaker
## path (unlike the standard breaker's _exhausted_brownout_keys latch, which
## this path never touches) — so _evaluate_per_component() naturally
## re-derives fresh from CURRENT draw/capacity:
##   - If the zones can now healthily share (load dropped, or capacity grew),
##     the cross-zone branch simply won't hit the exhausted-deficit path and
##     power resumes normally.
##   - If the offending zone is STILL overpowering the shared component, the
##     exact same cross-zone-exhausted detection fires again next solve and
##     _find_upgraded_breakers_in_component() finds this breaker (now
##     untripped + passing again) and re-trips it with a fresh trip_group_key
##     — i.e. it re-trips itself automatically, no extra code needed here.
func reset_breaker(breaker_id: String) -> void:
	if not _breakers.has(breaker_id):
		return
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		push_warning("PowerManager: reset_breaker called while grid is %s — reset main first."
			% GridState.keys()[grid_state])
		return
	var group_key: String = str(_breakers[breaker_id].get("trip_group_key", ""))
	if not group_key.is_empty():
		_reset_upgraded_breaker_group(group_key)
	else:
		## Standard path — untouched. Also covers an upgraded breaker that was
		## tripped some other way (e.g. via Power Terminal) with no group.
		_breakers[breaker_id]["tripped"] = false
		_notify_breaker_node(breaker_id, false)
		breaker_reset.emit(breaker_id)
	_solve_network()


## ─── Group reset for self-tripped upgraded breakers ──────────────────────────
## Finds every breaker whose trip_group_key matches the given key (all of them
## self-tripped together from the SAME cross-zone exhaustion event — see the
## trip_group_key assignment in _evaluate_per_component's upgraded-breaker
## branch) and resets them as one unit:
##   - tripped -> false
##   - pass_battery/pass_generator restored to their PRE-TRIP values (what the
##     player had set before the self-trip forced them off), not left at false.
##   - trip_group_key cleared back to "".
## Notifies each breaker's scene node + emits breaker_reset per breaker so the
## UI (TRIPPED banner, LED, pass-through pill states) updates for every one of
## them, not just the breaker the player physically clicked RESTART on.
## Does NOT call _solve_network() itself — reset_breaker() does that once,
## after this returns, so a group of N breakers only triggers one solve.
func _reset_upgraded_breaker_group(group_key: String) -> void:
	var reset_ids: Array[String] = []
	for bid: String in _breakers:
		var brk: Dictionary = _breakers[bid]
		if str(brk.get("trip_group_key", "")) != group_key:
			continue
		brk["tripped"]        = false
		brk["pass_battery"]   = bool(brk.get("pretrip_pass_battery", true))
		brk["pass_generator"] = bool(brk.get("pretrip_pass_generator", true))
		brk["trip_group_key"] = ""
		_notify_breaker_node(bid, false)
		reset_ids.append(bid)
	for rid: String in reset_ids:
		breaker_reset.emit(rid)
	_pmdbg("[PM:BREAKER] _reset_upgraded_breaker_group(%s) reset %d breaker(s): %s" % [
		group_key, reset_ids.size(), str(reset_ids)])


## Reset the whole-bunker main breaker (player at main breaker panel).
## Clears all tripped breakers, puts the grid back to ONLINE state.
## Does NOT auto-start generators — the player must manually restart each one.
func reset_main_breaker() -> void:
	if grid_state == GridState.OFFLINE:
		push_warning("PowerManager: grid OFFLINE — repair generators before resetting.")
		return
	if grid_state != GridState.TRIPPED:
		return   ## Nothing to reset.
	_main_reset_timer = 0.0
	_overload_timer   = 0.0
	_flickering = false
	## Un-trip every circuit breaker in the building.
	for brk: Dictionary in _breakers.values():
		if brk["tripped"]:
			brk["tripped"] = false
			_notify_breaker_node(brk["id"], false)
			breaker_reset.emit(brk["id"])
	## Clear all shed flags.
	_unshed_all()
	var old: GridState = grid_state
	grid_state = GridState.ONLINE
	grid_state_changed.emit(grid_state, old)
	grid_restored.emit()
	_solve_network()


## ─── Breaker pass-through API ────────────────────────────────────────────────
## Called by BreakerBox when the player toggles a pass-through option.
## pass_battery  = true  → battery current may flow through this breaker node.
## pass_generator = true → generator current may flow through this breaker node.
## Triggers a full network re-solve because the two adjacency graphs change.
func set_breaker_passthrough(breaker_id: String, pass_battery: bool, pass_generator: bool) -> void:
	if not _breakers.has(breaker_id):
		return
	_breakers[breaker_id]["pass_battery"]   = pass_battery
	_breakers[breaker_id]["pass_generator"] = pass_generator
	_solve_network()


## ─── Upgraded ("smart") breaker flag ─────────────────────────────────────────
## Marks a breaker as the upgraded/smart variant.  Does NOT change adjacency or
## trip state by itself — it only changes what happens at the cross-zone
## exhaustion decision point in _evaluate_per_component(): an upgraded breaker
## self-trips to ISOLATE its two bordering zones instead of allowing the
## standard multi-zone sustained brownout.  See _find_upgraded_breaker_for_component().
## Called by the (future) UpgradedBreakerBox scene in _ready(), or by debug
## tooling to test the behavior on an existing standard breaker.
func set_breaker_upgraded(breaker_id: String, upgraded: bool) -> void:
	if not _breakers.has(breaker_id):
		return
	_breakers[breaker_id]["upgraded"] = upgraded
	_solve_network()


## Returns true if the given breaker is the upgraded/smart variant.
func get_breaker_upgraded(breaker_id: String) -> bool:
	return bool(_breakers.get(breaker_id, {}).get("upgraded", false))


## ─── Battery enable / disable API ────────────────────────────────────────────
## Called by BatteryBank when the player toggles the battery on/off.
## A disabled battery cannot charge or discharge — it is treated as fully
## absent from the grid until re-enabled.
func set_battery_enabled(bat_id: String, enabled: bool) -> void:
	if not _batteries.has(bat_id):
		return
	_batteries[bat_id]["enabled"] = enabled
	if not enabled:
		## Force-stop any active charge/discharge.
		var bat: Dictionary = _batteries[bat_id]
		if bat.get("discharging", false):
			bat["discharging"] = false
			battery_state_changed.emit(bat_id, false)
			_notify_battery_mode(bat_id)
		if bat.get("charging", false):
			bat["charging"] = false
			_notify_battery_mode(bat_id)
	_solve_network()


## ─── Zone snapshot API ───────────────────────────────────────────────────────
## Returns per-zone data used by DebugOverlay and PowerTerminalUI.
## Each element:
##   zone_index      int     — matches get_wire_zones()[i]["index"]
##   color_index     int     — for UI palette lookup (zone_index % 6)
##   consumer_ids    Array   — consumer IDs reachable in this zone
##   generator_ids   Array   — generator IDs with a wire node in this zone
##   battery_ids     Array   — battery IDs with a wire node in this zone
##   breaker_keys    Array   — snap keys of breaker nodes bounding this zone
##   powered         bool    — true if any generator or battery serves this zone
##   overloaded        bool    — true if zone has at least one shed consumer
##   state_str       String  — "ONLINE" / "OVERLOADED" / "OFFLINE" (zone-local)
## Returns [] if no wire zones exist (no breakers placed, or wire graph empty).
func get_zone_snapshot() -> Array[Dictionary]:
	## Use get_wire_zones_with_colors so color_index reflects the actual registry-
	## assigned palette entry rather than zone_index % 6.  This is required for
	## DebugOverlay to show the true wire colour next to each zone name.
	var wire_zones: Array[Dictionary] = get_wire_zones_with_colors()
	if wire_zones.is_empty():
		return []

	## Pre-build: snap_key → device info for quick lookup.
	var key_to_consumer: Dictionary = {}
	var key_to_generator: Dictionary = {}
	var key_to_battery: Dictionary = {}
	for wn: Dictionary in _wire_nodes.values():
		var k: String = wn.get("key", "")
		var did: String = wn.get("device_id", "")
		if did.is_empty():
			continue
		match wn.get("role", ""):
			"consumer":  key_to_consumer[k]  = did
			"generator": key_to_generator[k] = did
			"battery":   key_to_battery[k]   = did

	## Breaker keys lookup (all breakers that bound a zone segment).
	var breaker_key_set: Dictionary = {}
	for bid: String in _breakers:
		var bk: String = _breakers[bid].get("node_key", "")
		if not bk.is_empty():
			breaker_key_set[bk] = bid

	var out: Array[Dictionary] = []

	for zone: Dictionary in wire_zones:
		var z_idx: int    = int(zone.get("index", 0))
		var z_key: String = String(zone.get("zone_key", ""))
		var edge_ids: Array = zone.get("edge_ids", [])

		## Collect all snap keys in this zone (from its edges).
		var zone_keys: Dictionary = {}   ## snap_key → true
		for eid: String in edge_ids:
			if not _wire_edges.has(eid):
				continue
			var edge: Dictionary = _wire_edges[eid]
			zone_keys[edge.get("node_a", "")] = true
			zone_keys[edge.get("node_b", "")] = true

		## Collect device IDs.
		var consumer_ids:  Array[String] = []
		var generator_ids: Array[String] = []
		var battery_ids:   Array[String] = []
		var brk_keys:      Array[String] = []

		for k: String in zone_keys:
			if key_to_consumer.has(k):
				consumer_ids.append(key_to_consumer[k])
			if key_to_generator.has(k):
				generator_ids.append(key_to_generator[k])
			if key_to_battery.has(k):
				battery_ids.append(key_to_battery[k])
			## Also check neighbouring breaker nodes (they border but aren't inside).
		## Breakers bound the zone — check all breakers to see if their node
		## is adjacent to any of this zone's keys (i.e. was an endpoint of a zone edge).
		for eid: String in edge_ids:
			if not _wire_edges.has(eid):
				continue
			var edge: Dictionary = _wire_edges[eid]
			for ep: String in [edge.get("node_a", ""), edge.get("node_b", "")]:
				if breaker_key_set.has(ep) and not brk_keys.has(ep):
					brk_keys.append(ep)

		## Zone power state (local assessment).
		var zone_powered: bool = false
		var zone_overloaded: bool = false

		for gen_id: String in generator_ids:
			if _generators.has(gen_id) and _generators[gen_id].get("running", false):
				zone_powered = true
				break
		if not zone_powered:
			for bat_id: String in battery_ids:
				if _batteries.has(bat_id) \
						and _batteries[bat_id].get("discharging", false) \
						and float(_batteries[bat_id].get("charge_wh", 0.0)) > 0.0:
					zone_powered = true
					break

		for con_id: String in consumer_ids:
			if _consumers.has(con_id) and _consumers[con_id].get("shed", false):
				zone_overloaded = true
				break

		var zone_state_str: String
		if not zone_powered:
			zone_state_str = "OFFLINE"
		elif zone_overloaded:
			zone_state_str = "OVERLOADED"
		else:
			zone_state_str = "ONLINE"

		## Per-zone draw and capacity for debug display.
		var zone_draw_w: float = 0.0
		var zone_cap_w:  float = 0.0
		for con_id: String in consumer_ids:
			if not _consumers.has(con_id):
				continue
			var c: Dictionary = _consumers[con_id]
			if c.get("powered", false):
				zone_draw_w += float(c.get("watts", 0.0))
			elif c.get("shed", false) and c.get("active", false):
				zone_draw_w += _shed_residual_watts(c)
		for gen_id: String in generator_ids:
			if _generators.has(gen_id) and _generators[gen_id].get("running", false):
				zone_cap_w += float(_generators[gen_id].get("watts", 0.0))

		## Surplus: positive = zone has excess capacity it could export to neighbors;
		## negative = zone has a deficit and needs to import. Used by UI to show
		## cross-zone power flow in the WIRE GRAPH section.
		var zone_surplus_w: float = zone_cap_w - zone_draw_w

		## ── Cross-zone gen sharing flow (from last _evaluate_per_component run) ──
		## We re-run a lightweight version of the pass-2 sharing calc here so
		## get_zone_snapshot() always reflects the current solve result.
		## This mirrors what _evaluate_per_component does but read-only.
		var zone_exported_w: float    = 0.0
		var zone_imported_w: float    = 0.0
		var zone_import_from: Array   = []
		var zone_export_to:   Array   = []

		out.append({
			"zone_index":    z_idx,
			## zone_key — stable zone identity (see ZoneCustomization.gd),
			## used by callers to look up player name/color overrides.
			"zone_key":      z_key,
			## zone_name — player override if set, else the default "Z%d" label.
			"zone_name":     get_zone_display_name(z_key, "Z%d" % z_idx),
			## color_index comes from get_wire_zones_with_colors() above —
			## this is the actual registry-assigned palette index, NOT z_idx % 6.
			"color_index":   int(zone.get("color_index", z_idx % ZONE_COLORS.size())),
			"consumer_ids":  consumer_ids,
			"generator_ids": generator_ids,
			"battery_ids":   battery_ids,
			"breaker_keys":  brk_keys,
			"powered":       zone_powered,
			"overloaded":      zone_overloaded,
			"state_str":     zone_state_str,
			"draw_w":        zone_draw_w,
			"capacity_w":    zone_cap_w,
			"surplus_w":     zone_surplus_w,
			"neighbor_zones": [],   ## filled in after all zones built (see below)
			## Flow fields — populated in the post-pass below.
			"exported_w":    zone_exported_w,
			"imported_w":    zone_imported_w,
			"import_from":   zone_import_from,
			"export_to":     zone_export_to,
			## Cross-zone device lists — populated in post-pass below.
			## cross_consumer_ids: consumers in zones that import gen power from us.
			## cross_battery_ids:  batteries in other zones reachable via pass_battery breakers.
			"cross_consumer_ids": [],
			"cross_battery_ids":  [],
		})

	## ── Post-pass: compute neighbor zone pairs via shared breaker nodes ───────
	## A breaker node sits between two zones. We find which zones each breaker
	## touches by checking which zone's edge-set has an endpoint at the breaker key.
	## Two zones that both touch the same breaker key are neighbors.
	var brk_to_zones: Dictionary = {}   ## breaker_key → Array[int] (zone indices)
	for z: Dictionary in out:
		var zidx: int = z["zone_index"]
		for bk: String in (z["breaker_keys"] as Array):
			if not brk_to_zones.has(bk):
				brk_to_zones[bk] = []
			var lst: Array = brk_to_zones[bk]
			if not lst.has(zidx):
				lst.append(zidx)

	## For each breaker that touches exactly two zones, mark them as neighbors.
	for bk: String in brk_to_zones:
		var touching: Array = brk_to_zones[bk]
		if touching.size() == 2:
			var ia: int = touching[0]
			var ib: int = touching[1]
			for z: Dictionary in out:
				var zi: int = z["zone_index"]
				var nb: Array = z["neighbor_zones"]
				if zi == ia and not nb.has(ib):
					nb.append(ib)
				elif zi == ib and not nb.has(ia):
					nb.append(ia)

	## ── Post-pass: compute cross-zone gen sharing flow for UI (BFS pool) ──────
	## Mirrors the updated PASS 2 BFS pool logic from _evaluate_per_component.
	## Read-only: updates out[] imported_w/exported_w/import_from/export_to only.
	var sharing_pairs_snap: Array[Dictionary] = _get_gen_sharing_zone_pairs(wire_zones)

	## Build undirected zone adjacency from sharing pairs.
	var snap_n: int = out.size()
	var snap_adj: Array = []
	for _si: int in snap_n:
		snap_adj.append([])
	var snap_zi_to_oi: Dictionary = {}
	for oi_s: int in snap_n:
		snap_zi_to_oi[int(out[oi_s]["zone_index"])] = oi_s
	for pair_s: Dictionary in sharing_pairs_snap:
		var fa_s: int = int(pair_s["from_zi"])
		var ta_s: int = int(pair_s["to_zi"])
		var oi_fa: int = snap_zi_to_oi.get(fa_s, -1)
		var oi_ta: int = snap_zi_to_oi.get(ta_s, -1)
		if oi_fa < 0 or oi_ta < 0:
			continue
		if not (snap_adj[oi_fa] as Array).has(oi_ta):
			(snap_adj[oi_fa] as Array).append(oi_ta)
		if not (snap_adj[oi_ta] as Array).has(oi_fa):
			(snap_adj[oi_ta] as Array).append(oi_fa)

	## BFS flood: find power pools in snapshot.
	var snap_pool: Array[int] = []
	for _si2: int in snap_n:
		snap_pool.append(-1)
	var snap_pools: Array[Dictionary] = []

	for seed_s: int in snap_n:
		if snap_pool[seed_s] != -1:
			continue
		var sp_idx: int = snap_pools.size()
		var sp: Dictionary = { "total_cap": 0.0, "total_draw": 0.0, "members": [] }
		var sp_q: Array[int] = [seed_s]
		var sp_vis: Dictionary = {}
		while not sp_q.is_empty():
			var cur_s: int = sp_q.pop_front()
			if sp_vis.has(cur_s):
				continue
			sp_vis[cur_s] = true
			snap_pool[cur_s] = sp_idx
			(sp["members"] as Array).append(cur_s)
			sp["total_cap"]  = float(sp["total_cap"])  + float(out[cur_s]["capacity_w"])
			sp["total_draw"] = float(sp["total_draw"]) + float(out[cur_s]["draw_w"])
			for nb_s: int in (snap_adj[cur_s] as Array):
				if not sp_vis.has(nb_s):
					sp_q.append(nb_s)
		snap_pools.append(sp)

	## Distribute pool capacity across snapshot zones.
	for sp2: Dictionary in snap_pools:
		var sp_members: Array = sp2["members"]
		if float(sp2["total_cap"]) <= 0.0:
			continue
		for oi_d: int in sp_members:
			var z_d: Dictionary = out[oi_d]
			var zi_d: int = int(z_d["zone_index"])
			var deficit_s: float = float(z_d["draw_w"]) - float(z_d["capacity_w"]) - float(z_d["imported_w"])
			if deficit_s <= 0.0:
				continue
			for oi_src: int in sp_members:
				if oi_src == oi_d or deficit_s <= 0.0:
					continue
				var z_src: Dictionary = out[oi_src]
				var zi_src: int = int(z_src["zone_index"])
				var avail_s: float = maxf(0.0,
					float(z_src["capacity_w"]) - float(z_src["draw_w"]) - float(z_src["exported_w"]))
				if avail_s <= 0.0:
					continue
				var transfer_s: float = minf(avail_s, deficit_s)
				z_d["imported_w"] = float(z_d["imported_w"]) + transfer_s
				z_src["exported_w"] = float(z_src["exported_w"]) + transfer_s
				deficit_s -= transfer_s
				var imp_arr_s: Array = z_d["import_from"]
				if not imp_arr_s.has(zi_src):
					imp_arr_s.append(zi_src)
				var exp_arr_s: Array = z_src["export_to"]
				if not exp_arr_s.has(zi_d):
					exp_arr_s.append(zi_d)

	## ── Post-pass: populate cross_consumer_ids and cross_battery_ids ─────────
	## For each zone that has export_to entries (it's supplying gen power to others),
	## collect the consumer and battery IDs from those importing zones.
	## These are shown in the UI under the exporting zone's own device lists.
	## Also: cross_battery_ids for every zone = batteries in OTHER zones that are
	## BFS-reachable via _adjacency (pass_battery=true path).
	##
	## Build zone_index → out[] index, and zone_index → node_keys dict for BFS.
	var zi_to_out2: Dictionary = {}
	var zi_to_consumer_ids: Dictionary  = {}   ## zone_index → Array[String]
	var zi_to_battery_ids: Dictionary   = {}   ## zone_index → Array[String]
	var zi_to_zone_keys: Dictionary     = {}   ## zone_index → Dictionary(snap_key→true)
	for oi2: int in out.size():
		var oz: Dictionary = out[oi2]
		var ozidx: int = int(oz["zone_index"])
		zi_to_out2[ozidx]         = oi2
		zi_to_consumer_ids[ozidx] = oz["consumer_ids"]
		zi_to_battery_ids[ozidx]  = oz["battery_ids"]

	## Also rebuild zone node key sets from the wire_zones data.
	for wz: Dictionary in wire_zones:
		var wzidx: int = int(wz.get("index", 0))
		var wz_keys: Dictionary = {}
		for nk: String in (wz.get("node_keys", []) as Array):
			wz_keys[nk] = true
		zi_to_zone_keys[wzidx] = wz_keys

	for oi3: int in out.size():
		var oz3: Dictionary     = out[oi3]
		var ozidx3: int         = int(oz3["zone_index"])
		var exp_to3: Array      = oz3["export_to"]
		var cross_cons: Array   = oz3["cross_consumer_ids"]
		var cross_bats: Array   = oz3["cross_battery_ids"]

		## cross_consumer_ids: consumers in zones this zone exports gen power to.
		for dst_zi: int in exp_to3:
			if zi_to_consumer_ids.has(dst_zi):
				for cid: String in (zi_to_consumer_ids[dst_zi] as Array):
					if not cross_cons.has(cid):
						cross_cons.append(cid)

		## cross_battery_ids: batteries in OTHER zones reachable via _adjacency.
		## We check BFS from any node in this zone to the battery's wire node key.
		var own_keys3: Dictionary = zi_to_zone_keys.get(ozidx3, {})
		var own_key_list3: Array[String] = []
		for osk: String in own_keys3:
			own_key_list3.append(osk)

		for other_zi: int in zi_to_battery_ids:
			if other_zi == ozidx3:
				continue
			for bid3: String in (zi_to_battery_ids[other_zi] as Array):
				if not _batteries.has(bid3):
					continue
				## Find this battery's wire node key.
				var bkey3: String = ""
				for wn3: Dictionary in _wire_nodes.values():
					if wn3["role"] == "battery" and wn3["device_id"] == bid3:
						bkey3 = wn3.get("key", "")
						break
				if bkey3.is_empty():
					continue
				## BFS check: is this battery reachable from this zone via _adjacency?
				var reachable3: bool = false
				for seed3: String in own_key_list3:
					if _adjacency_bfs_can_reach(seed3, bkey3):
						reachable3 = true
						break
				if reachable3 and not cross_bats.has(bid3):
					cross_bats.append(bid3)

	return out

## ════════════════════════════════════════════════════════════════════════════
## ZONE COLOUR PALETTE — SINGLE SOURCE OF TRUTH
## ════════════════════════════════════════════════════════════════════════════
## This is the ONE canonical palette.  BuildModeController (world wires) and
## PowerTerminalUI (terminal labels) MUST read from here — do not redefine.
##   - World wires use these colours at alpha 0.60 (see zone_color_at()).
##   - The terminal UI uses them at alpha 1.0.
## Index 0 = light blue (default/unbroken zone, matches WireSegment.COLOR_GHOST).
## Index 1+ = green / red / yellow / magenta / orange ...
## RGB is the source; alpha is applied per-consumer so both stay in lockstep.
const ZONE_COLORS: Array[Color] = [
	Color(0.35, 0.80, 1.00, 0.60),   ##  0 light blue    (default zone)
	Color(0.10, 0.95, 0.35, 0.60),   ##  1 green
	Color(0.95, 0.18, 0.10, 0.60),   ##  2 red
	Color(0.95, 0.90, 0.10, 0.60),   ##  3 yellow
	Color(0.90, 0.10, 0.95, 0.60),   ##  4 magenta
	Color(0.95, 0.55, 0.10, 0.60),   ##  5 orange
	Color(0.10, 0.70, 0.70, 0.60),   ##  6 teal
	Color(0.95, 0.40, 0.70, 0.60),   ##  7 pink
	Color(0.50, 0.30, 0.95, 0.60),   ##  8 purple
	Color(0.55, 0.85, 0.10, 0.60),   ##  9 lime
	Color(0.95, 0.70, 0.30, 0.60),   ## 10 amber
	Color(0.10, 0.45, 0.95, 0.60),   ## 11 cobalt blue
]

## Return palette colour for a zone color_index at the requested alpha.
## Wraps the palette (repeating) for arbitrary zone counts.
## Callers: BuildModeController (alpha 0.60), PowerTerminalUI (alpha 1.0).
## NOTE: this is the pure ALGORITHMIC palette lookup — it does NOT know about
## player color overrides. Use zone_display_color() below wherever a zone_key
## is available (i.e. everywhere except inside the graph-coloring algorithm
## itself, which must stay override-agnostic to keep coloring adjacent zones
## distinct).
func zone_color_at(color_index: int, alpha: float = 0.60) -> Color:
	var c: Color = ZONE_COLORS[color_index % ZONE_COLORS.size()]
	c.a = alpha
	return c


## ════════════════════════════════════════════════════════════════════════════
## ZONE CUSTOMIZATION (player-set name/color overrides) — Public API
## ════════════════════════════════════════════════════════════════════════════
## See ZoneCustomization.gd for the zone_key identity scheme and persistence
## guarantees. All zone_key values here come from get_wire_zones_with_colors()/
## get_zone_snapshot()'s "zone_key" field.

## Returns the zone's display name — the player override if one is set,
## otherwise `default_name` (callers pass "Z%d" % zone_index).
func get_zone_display_name(zone_key: String, default_name: String) -> String:
	var override_name: String = _zone_custom.get_name_override(zone_key)
	return override_name if not override_name.is_empty() else default_name

## Sets (or clears, if blank) the player's display-name override for a zone.
## Called by PowerTerminal's rename UI. Takes effect immediately — the next
## get_zone_snapshot()/get_zone_display_name() call reflects it.
func set_zone_name(zone_key: String, new_name: String) -> void:
	_zone_custom.set_name_override(zone_key, new_name)
	zone_name_changed.emit(zone_key)

## Returns the player's color override for a zone, or null if none is set.
func get_zone_color_override(zone_key: String) -> Variant:
	if _zone_custom.has_color_override(zone_key):
		return _zone_custom.get_color_override(zone_key)
	return null

## Sets the player's color override for a zone. ALWAYS persists once set —
## does not re-check the graph-coloring adjacency rule, per design (the
## player's choice always wins, even if it happens to match/clash with a
## bordering zone). Called by PowerTerminal's color-picker UI.
func set_zone_color_override(zone_key: String, new_color: Color) -> void:
	_zone_custom.set_color_override(zone_key, new_color)
	zone_color_changed.emit(zone_key)

## Zone color for DISPLAY — checks the player override FIRST, falls back to
## the auto-assigned algorithmic palette color otherwise. This is what every
## UI/world-wire render site should call once it has a zone_key (world wires
## via BuildModeController, PowerTerminalUI, BreakerBox zone swatches,
## DebugOverlay). zone_color_at() itself stays pure/override-agnostic since
## the greedy graph-coloring algorithm internally depends on it being so.
func zone_display_color(zone_key: String, color_index: int, alpha: float = 0.60) -> Color:
	if _zone_custom.has_color_override(zone_key):
		var c: Color = _zone_custom.get_color_override(zone_key)
		c.a = alpha
		return c
	return zone_color_at(color_index, alpha)


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — CONSUMERS
# ═══════════════════════════════════════════════════════════════════════════════

## ─────────────────────────────────────────────────────────────────────────────
## CONSUMERS / GENERATORS / BATTERIES — forwarded to PowerRegistry.gd
## (Stage 8 extraction, see REVIEW_IMPLEMENTATION_PLAN.md). Signatures
## identical to before the split — every external call site needs zero
## changes. Solver-policy setters (set_consumer_priority, set_generator_fuel/
## health/running/backup, set_battery_enabled) stay below, unmoved.
## ─────────────────────────────────────────────────────────────────────────────

func register_consumer(
		id:       String,
		watts:    float,
		node:     Node,
		type:     String = "unknown",
		priority: int    = 0,
		active:   bool   = true) -> void:
	_registry.register_consumer(id, watts, node, type, priority, active)

func unregister_consumer(id: String) -> void:
	_registry.unregister_consumer(id)

func set_consumer_active(id: String, active: bool) -> void:
	_registry.set_consumer_active(id, active)

func get_consumer_watts(id: String) -> float:
	return _registry.get_consumer_watts(id)



# ─── Power priority API ──────────────────────────────────────────────────────
## Lowest/highest selectable priority tiers exposed to the player UI.
## 1 = critical (never shed) … 5 = luxury (first to shed).
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

## Returns the current priority (1–5) of a consumer, or 3 (default) if unknown.
func get_consumer_priority(id: String) -> int:
	return _registry.get_consumer_priority(id)


## Set a consumer's power priority (1–5) and re-solve the grid so shedding
## immediately reflects the new tier.  Clamped to [PRIORITY_MIN, PRIORITY_MAX].
## Called by PowerPriorityUI when the player presses the ◄ / ► arrows.
func set_consumer_priority(id: String, priority: int) -> void:
	if not _consumers.has(id):
		return
	var clamped: int = clampi(priority, PRIORITY_MIN, PRIORITY_MAX)
	if int(_consumers[id].get("priority", 3)) == clamped:
		return
	_consumers[id]["priority"] = clamped
	consumer_priority_changed.emit(id, clamped)
	## Grace period (standing decision, July 2026) — do NOT reset shed state
	## or re-solve right now. Queue this consumer's component for a clean
	## reset+resolve once PRIORITY_CHANGE_GRACE_SECS elapses (see _process()).
	## The grid keeps running on its last-solved state in the meantime, so a
	## tier change can't visibly flash the grid through a transient overload
	## before things settle. Rapid repeated changes within the window all
	## collapse into that single resolve.
	_pending_priority_reset_ids[id] = true
	if _priority_grace_timer < 0.0:
		_priority_grace_timer = PRIORITY_CHANGE_GRACE_SECS


## ─── Reset shed/powered state across a consumer's whole electrical component ──
## Finds the wire node for `id`, floods the full connected component via
## _flood_component_keys (same BFS used by the sustained-brownout path), then
## clears shed=false / powered=false on EVERY consumer whose wire node falls
## inside that component.  This does NOT apply any power to the nodes itself —
## it just wipes stale flags so the next _solve_network() re-sheds from a clean
## slate instead of trusting flags computed under the old priority ordering.
func _reset_shed_for_consumer_component(id: String) -> void:
	var seed_key: String = ""
	for wn: Dictionary in _wire_nodes.values():
		if wn.get("role", "") == "consumer" and wn.get("device_id", "") == id:
			seed_key = wn.get("key", "")
			break
	if seed_key.is_empty():
		return
	var component_keys: Dictionary = _flood_component_keys({seed_key: true})
	for c: Dictionary in _consumers.values():
		var in_component: bool = false
		for wn2: Dictionary in _wire_nodes.values():
			if wn2.get("role", "") == "consumer" and wn2.get("device_id", "") == c.get("id", ""):
				if component_keys.has(wn2.get("key", "")):
					in_component = true
				break
		if in_component:
			c["shed"] = false
			c["powered"] = false


## Returns true if the consumer is currently switched on (drawing/attempting).
func get_consumer_active(id: String) -> bool:
	return _registry.get_consumer_active(id)

func get_consumer_powered(id: String) -> bool:
	return _registry.get_consumer_powered(id)

func get_consumer_shed(id: String) -> bool:
	return _registry.get_consumer_shed(id)

func get_consumer_status(id: String) -> Dictionary:
	return _registry.get_consumer_status(id)

## True if this consumer has a wire node that participates in any edge.
func _consumer_is_wired(id: String) -> bool:
	return _registry._consumer_is_wired(id)



# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — GENERATORS
# ═══════════════════════════════════════════════════════════════════════════════

## Register a generator. Call from GeneratorObject._ready().
##   gen_id    — str(node.get_instance_id()) or a stable string id
##   watts     — rated output when running and healthy
##   node      — scene node; implement set_running(bool)
##   is_backup — if true, idles until all primaries fail
##   fuel      — 0–100
##   health    — 0–100
func register_generator(
		gen_id:    String,
		watts:     float,
		node:      Node  = null,
		is_backup: bool  = false,
		fuel:      float = 100.0,
		health:    float = 100.0,
		infinite:  bool  = false) -> void:
	_registry.register_generator(gen_id, watts, node, is_backup, fuel, health, infinite)

func unregister_generator(gen_id: String) -> void:
	_registry.unregister_generator(gen_id)


## ── ADMIN CHEAT (F7 menu, Jul 2026) ──────────────────────────────────────────
## Adds (positive delta) or removes (negative delta) `delta_watts` of power
## from the grid, as if a fictional infinitely-fueled generator were wired
## straight into the network. Stackable: repeated calls accumulate onto the
## SAME hidden generator (ADMIN_GEN_ID) rather than spawning a new one each
## time. Wattage is clamped to >= 0; hitting exactly 0 fully unregisters the
## generator and its wire node again, leaving no trace.
##
## Wiring approach: the hidden generator needs a wire-graph node to actually
## count toward a zone's reachable capacity (not just the flat
## total_capacity_watts sum) — a bare register_generator() call alone is not
## enough. It attaches via a "no_visual" (logical-only, no rendered tube)
## edge to whatever wire node happens to be first in get_wire_nodes() — any
## already-connected node works since the whole point is "infinitely
## connected to the system," not a specific physical location. The admin
## node itself sits one snap-grid cell (PowerGraph.SNAP_GRID) away from that
## anchor so register_wire_edge() never walks its automatic intermediate-
## joint-generation loop across a huge distance (that loop steps every
## SNAP_GRID metres between the two endpoints — fine at 0.25m, but a distant
## sentinel position would generate thousands of joints and stall the game).
const ADMIN_GEN_ID: String = "admin_cheat_gen"

func admin_add_power(delta_watts: float) -> void:
	var cur_watts: float = 0.0
	if _generators.has(ADMIN_GEN_ID):
		cur_watts = float(_generators[ADMIN_GEN_ID].get("watts", 0.0))
	var new_watts: float = maxf(0.0, cur_watts + delta_watts)

	if new_watts <= 0.0:
		if _generators.has(ADMIN_GEN_ID):
			unregister_generator(ADMIN_GEN_ID)
		if not _admin_gen_wire_key.is_empty():
			unregister_wire_node(_admin_gen_wire_key)
			_admin_gen_wire_key = ""
		return

	register_generator(ADMIN_GEN_ID, new_watts, null, false, 100.0, 100.0, true)

	if _admin_gen_wire_key.is_empty():
		var nodes: Array[Dictionary] = get_wire_nodes()
		if nodes.is_empty():
			push_warning("PowerManager: admin_add_power() found no existing wire node to attach to yet — try again once the grid has any wiring.")
			return
		var anchor: Dictionary = nodes[0]
		var anchor_pos: Vector3 = anchor.get("pos", Vector3.ZERO)
		var admin_pos: Vector3 = anchor_pos + Vector3(PowerGraph.SNAP_GRID, 0.0, 0.0)
		_admin_gen_wire_key = register_wire_node(admin_pos, "generator", ADMIN_GEN_ID)
		register_wire_edge(_admin_gen_wire_key, anchor["key"], null, true)

## Returns current fuel level [0.0–100.0] for the given generator.
## Returns -1.0 if the gen_id is not registered.
func get_generator_fuel(gen_id: String) -> float:
	return _registry.get_generator_fuel(gen_id)

## Returns whether the generator is currently running.
## Returns false if the id is unknown.
func get_generator_running(gen_id: String) -> bool:
	return _registry.get_generator_running(gen_id)

## Player refuels at the generator.
func set_generator_fuel(gen_id: String, new_fuel: float) -> void:
	if not _generators.has(gen_id):
		return
	var gen: Dictionary = _generators[gen_id]
	gen["fuel"] = clampf(new_fuel, 0.0, 100.0)
	if gen["fuel"] > 0.0 and gen["health"] > 0.0 and not gen["running"]:
		if not gen.get("backup", false) or _all_primaries_offline():
			_start_generator(gen_id)
	_recalculate_capacity()


## Repair event updates health.
func set_generator_health(gen_id: String, new_health: float) -> void:
	if not _generators.has(gen_id):
		return
	var gen: Dictionary = _generators[gen_id]
	gen["health"] = clampf(new_health, 0.0, 100.0)
	if gen["health"] > 0.0 and gen["fuel"] > 0.0 and not gen["running"]:
		if not gen.get("backup", false) or _all_primaries_offline():
			_start_generator(gen_id)
	elif gen["health"] <= 0.0 and gen["running"]:
		_stop_generator(gen_id, "health")
	_recalculate_capacity()


## Manual start/stop (player interaction at the generator panel).
func set_generator_running(gen_id: String, running: bool) -> void:
	if not _generators.has(gen_id):
		return
	if running:
		if grid_state == GridState.TRIPPED:
			push_warning("PowerManager: cannot start generator while grid is TRIPPED.")
			return
		## Manual generator restart clears any sustained-brownout latches so the
		## upcoming _solve_network() can re-power cross-zone components that were
		## held in exhausted brownout.
		clear_exhausted_brownout()
		## When the grid is OFFLINE (post-overload blackout) and the player
		## manually starts a generator, bring the grid back to ONLINE so that
		## _solve_network() can run the full BFS and re-power consumers.
		## Without this, _solve_network() hits the OFFLINE early-return and
		## consumers stay dead even with a running generator.
		if grid_state == GridState.OFFLINE:
			_flickering = false
			_unshed_all()
			for brk: Dictionary in _breakers.values():
				if brk["tripped"]:
					brk["tripped"] = false
					_notify_breaker_node(brk["id"], false)
					breaker_reset.emit(brk["id"])
			var old_state: GridState = grid_state
			grid_state = GridState.ONLINE
			grid_state_changed.emit(grid_state, old_state)
			grid_restored.emit()
		_start_generator(gen_id)
		_recalculate_capacity()
		_solve_network()
	else:
		_stop_generator(gen_id, "manual")
		_recalculate_capacity()


## Toggle whether a generator is a backup unit.
func set_generator_backup(gen_id: String, is_backup: bool) -> void:
	if not _generators.has(gen_id):
		return
	var gen: Dictionary = _generators[gen_id]
	gen["backup"] = is_backup
	if is_backup:
		if gen.get("running", false):
			_stop_generator(gen_id, "backup_set")
		_try_start_backups()
	else:
		if not gen.get("running", false) \
				and float(gen.get("fuel", 0.0)) > 0.0 \
				and float(gen.get("health", 0.0)) > 0.0:
			_start_generator(gen_id)
		_stop_auto_backups()
	_recalculate_capacity()
	_solve_network()

## Returns whether a generator is currently marked as a backup unit.
func get_generator_is_backup(gen_id: String) -> bool:
	return _registry.get_generator_is_backup(gen_id)

func get_generator_health(gen_id: String) -> float:
	return _registry.get_generator_health(gen_id)

func get_generator_watts(gen_id: String) -> float:
	return _registry.get_generator_watts(gen_id)

func get_generators_status() -> Array[Dictionary]:
	return _registry.get_generators_status()


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — BATTERIES
# ═══════════════════════════════════════════════════════════════════════════════

## Register a battery bank. Call from BatteryBank._ready().
##   capacity_wh    — max stored watt-hours
##   initial_charge — starting charge; -1 = full
func register_battery(
		bat_id:         String,
		capacity_wh:    float,
		node:           Node  = null,
		initial_charge: float = -1.0) -> void:
	_registry.register_battery(bat_id, capacity_wh, node, initial_charge)

## Unregister battery (sold / destroyed).
## NOTE: call unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.
func unregister_battery(bat_id: String) -> void:
	_registry.unregister_battery(bat_id)

## Force-set charge level (load from save).
func set_battery_charge(bat_id: String, charge_wh: float) -> void:
	_registry.set_battery_charge(bat_id, charge_wh)

## Total stored energy (watt-hours) across all batteries.
func total_battery_wh() -> float:
	return _registry.total_battery_wh()

## Aggregate charge as 0.0–1.0 fraction.
func battery_charge_ratio() -> float:
	return _registry.battery_charge_ratio()



# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — STATUS / QUERIES
# ═══════════════════════════════════════════════════════════════════════════════

## 0.0–1.0+ load ratio (>1.0 = currently brownout).
func load_ratio() -> float:
	if total_capacity_watts <= 0.0:
		return 1.0 if active_draw_watts > 0.0 else 0.0
	return active_draw_watts / total_capacity_watts


## Headroom in watts (negative = deficit).
func headroom_watts() -> float:
	return total_capacity_watts - active_draw_watts


## Returns true if a consumer is currently receiving power.
func is_consumer_powered(id: String) -> bool:
	return _registry.is_consumer_powered(id)


## Human-readable grid state string for UI display.
## ONLINE / OVERLOADED / BROWNOUT / TRIPPED / OFFLINE
func get_grid_state_string() -> String:
	return GridState.keys()[grid_state]


## Full debug snapshot used by DebugOverlay and PowerTerminalUI.
func get_debug_snapshot() -> Dictionary:
	var gens_out: Array[Dictionary] = []
	for gen: Dictionary in _generators.values():
		gens_out.append({
			"id":        gen.get("id", ""),
			"watts":     float(gen.get("watts", 0.0)),
			"running":   bool(gen.get("running", false)),
			"fuel":      float(gen.get("fuel", 100.0)),
			"health":    float(gen.get("health", 100.0)),
			"is_backup": bool(gen.get("is_backup", false)),
		})

	var batts_out: Array[Dictionary] = []
	for bat: Dictionary in _batteries.values():
		var bat_state: String
		var bat_charge: float = float(bat.get("charge_wh", 0.0))
		if bat_charge <= 0.0:
			bat_state = "DRAINED"
		elif bat.get("charging", false):
			bat_state = "CHARGING"
		elif bat.get("discharging", false):
			bat_state = "DISCHARGING"
		else:
			bat_state = "IDLE"
		batts_out.append({
			"id":          bat.get("id", ""),
			"capacity_wh": float(bat.get("capacity_wh", 0.0)),
			"charge_wh":   bat_charge,
			"state":       bat_state,
		})

	var cons_out: Array[Dictionary] = []
	for con: Dictionary in _consumers.values():
		cons_out.append({
			"id":       con.get("id", ""),
			"type":     con.get("type", ""),
			"watts":    float(con.get("watts", 0.0)),
			"powered":  bool(con.get("powered", false)),
			"shed":     bool(con.get("shed", false)),
			"priority": int(con.get("priority", 3)),
		})

	var zones_out: Dictionary = {}
	for zname: String in _breakers:
		zones_out[zname] = {
			"tripped": bool(_breakers[zname].get("tripped", false)),
		}

	return {
		"grid_state":            int(grid_state),
		"grid_state_str":        get_grid_state_string(),
		"total_draw_watts":      active_draw_watts,
		"total_capacity_watts":  total_capacity_watts,
		"wire_node_count":       _wire_nodes.size(),
		"wire_edge_count":       _wire_edges.size(),
		"reachable_node_count":  _reachable.size(),
		"generators":            gens_out,
		"batteries":             batts_out,
		"consumers":             cons_out,
		"zones":                 zones_out,
	}

## ─── Topology-aware battery helpers ─────────────────────────────────────────
##
## IMPORTANT DESIGN RULE
## ─────────────────────
## Batteries must only serve the sub-grid they are physically wired to.
## If a generator goes offline on Grid A, ONLY batteries on Grid A can take
## over.  Batteries on Grid B are irrelevant and must NOT be activated.
##
## "_batteries_reachable_from_node(start_key)" performs a BFS through the
## current adjacency (i.e. respecting tripped breakers) and returns every
## battery dict whose wire node is reachable from start_key.
##
## This is called instead of iterating _batteries.values() globally whenever
## the code makes decisions about battery takeover or discharge start.
##
## "_generators_reachable_from_node(start_key)" does the same for generators.

## BFS from start_key through _adjacency.  Returns battery dicts reachable
## on the same wired sub-graph (not crossing tripped breakers).
func _batteries_reachable_from_node(start_key: String) -> Array[Dictionary]:
	if not _wire_nodes.has(start_key):
		return []
	var visited: Dictionary = {}
	var queue: Array[String]  = [start_key]
	visited[start_key] = true
	var found: Array[Dictionary] = []
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var wn: Dictionary = _wire_nodes.get(cur, {})
		if wn.get("role", "") == "battery":
			var did: String = wn.get("device_id", "")
			if not did.is_empty() and _batteries.has(did):
				found.append(_batteries[did])
		if _adjacency.has(cur):
			for nb: String in (_adjacency[cur] as Array):
				if not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
	return found

## BFS from start_key.  Returns generator dicts reachable on the same sub-graph.
func _generators_reachable_from_node(start_key: String) -> Array[Dictionary]:
	if not _wire_nodes.has(start_key):
		return []
	var visited: Dictionary = {}
	var queue: Array[String]  = [start_key]
	visited[start_key] = true
	var found: Array[Dictionary] = []
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var wn: Dictionary = _wire_nodes.get(cur, {})
		if wn.get("role", "") == "generator":
			var did: String = wn.get("device_id", "")
			if not did.is_empty() and _generators.has(did):
				found.append(_generators[did])
		if _adjacency.has(cur):
			for nb: String in (_adjacency[cur] as Array):
				if not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
	return found

## Returns the wire-node snap key for a generator, or "" if not wired.
func _generator_wire_key(gen_id: String) -> String:
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "generator" and wn["device_id"] == gen_id:
			return wn["key"]
	return ""

## Returns the wire-node snap key for a battery, or "" if not wired.
func _battery_wire_key(bat_id: String) -> String:
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "battery" and wn["device_id"] == bat_id:
			return wn["key"]
	return ""

## Returns all devices_ids (generators, batteries, consumers) wired
## in the same connected component as start_key.
func get_reachable_device_ids(start_key: String) -> Array[String]:
	if not _wire_nodes.has(start_key):
		return []

	var visited: Dictionary = {}
	var queue: Array[String] = [start_key]
	visited[start_key] = true
	var device_ids: Array[String] = []

	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var nd: Dictionary = _wire_nodes.get(cur, {})
		var did: String = nd.get("device_id", "")
		if not did.is_empty():
			device_ids.append(did)
		for edge: Dictionary in _wire_edges.values():
			var a: String = edge.get("node_a", "")
			var b: String = edge.get("node_b", "")
			var neighbour: String = ""
			if a == cur:
				neighbour = b
			elif b == cur:
				neighbour = a
			if not neighbour.is_empty() and not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)

	return device_ids

## Returns the zone index (from get_wire_zones()) that contains node_key.
## Returns -1 if node_key is not found in any zone.
## Use this to scope a PowerTerminal to its own wire zone.
func get_zone_index_for_key(node_key: String) -> int:
	var zones: Array[Dictionary] = get_wire_zones()
	for zone: Dictionary in zones:
		var edge_ids: Array = zone.get("edge_ids", [])
		for eid: String in edge_ids:
			if not _wire_edges.has(eid):
				continue
			var edge: Dictionary = _wire_edges[eid]
			if edge.get("node_a", "") == node_key or edge.get("node_b", "") == node_key:
				return int(zone.get("index", -1))
	return -1

## Resets only the breakers that bound a specific wire zone (by zone index).
## Does NOT call reset_main_breaker — only the breakers adjacent to this zone
## are reset, leaving the rest of the grid untouched.
func reset_zone_by_index(zone_index: int) -> void:
	var zones: Array[Dictionary] = get_wire_zones()
	## Find the matching zone entry.
	var target_zone: Dictionary = {}
	for zone: Dictionary in zones:
		if int(zone.get("index", -1)) == zone_index:
			target_zone = zone
			break
	if target_zone.is_empty():
		push_warning("PowerManager: reset_zone_by_index(%d) — zone not found." % zone_index)
		return

	## Collect all snap keys in this zone (from its edges).
	var zone_keys: Dictionary = {}
	for eid: String in target_zone.get("edge_ids", []):
		if not _wire_edges.has(eid):
			continue
		var edge: Dictionary = _wire_edges[eid]
		zone_keys[edge.get("node_a", "")] = true
		zone_keys[edge.get("node_b", "")] = true

	## Find breakers adjacent to this zone (their node_key is in zone_keys or
	## is the opposite endpoint of an edge whose other endpoint is in zone_keys).
	var reset_breaker_ids: Array[String] = []
	for bid: String in _breakers:
		var bk: String = _breakers[bid].get("node_key", "")
		if bk.is_empty():
			continue
		## Check if this breaker node borders the zone (adjacent via any edge).
		for eid: String in _wire_edges:
			var edge: Dictionary = _wire_edges[eid]
			var na: String = edge.get("node_a", "")
			var nb: String = edge.get("node_b", "")
			if (na == bk and zone_keys.has(nb)) or (nb == bk and zone_keys.has(na)):
				if not reset_breaker_ids.has(bid):
					reset_breaker_ids.append(bid)
				break

	if reset_breaker_ids.is_empty():
		push_warning("PowerManager: reset_zone_by_index(%d) — no bounding breakers found." % zone_index)
		return

	## Reset each bounding breaker.
	for bid: String in reset_breaker_ids:
		if _breakers.has(bid):
			_breakers[bid]["tripped"] = false
			var brk_node: Node = _safe_dict_node(_breakers[bid])
			if brk_node != null and is_instance_valid(brk_node) \
					and brk_node.has_method("set_tripped"):
				brk_node.set_tripped(false)

	## Re-solve now that these breakers are no longer tripped.
	_solve_network()

## Returns all registered wire nodes as Array[Dictionary] {key, pos, role}.
func get_wire_nodes() -> Array[Dictionary]:
	return _graph.get_wire_nodes()

## Patch the scene node reference stored on a wire edge.
## Called by MainWorld Pass C0 after spawning a WireSegment visual for a
## null-node edge, so that _split_wire_edge_at() can find and resize it.
func patch_wire_edge_node(edge_id: String, node: Node) -> void:
	if _wire_edges.has(edge_id):
		_wire_edges[edge_id]["node"] = node

## ─── Wire zone graph partition ───────────────────────────────────────────────
## Returns the wire network partitioned into zones.
## A zone is a contiguous group of wire edges whose endpoints are NOT breaker
## nodes — breakers act as cut-points that divide the graph into segments.
##
## Return value: Array of zones, each zone is:
##   {
##     "edge_ids": Array[String]   — edge_ids belonging to this zone
##     "index":    int             — zone index (stable for a given wire layout)
##   }
##
## If no breakers are registered, all edges form a single zone (index 0).
## Edges touching a breaker node on BOTH endpoints end up in neither zone
## (very unlikely in practice but handled gracefully — they are orphaned).

## ─────────────────────────────────────────────────────────────────────────────
## ZONE COLOR REGISTRY — Public API
## ─────────────────────────────────────────────────────────────────────────────

## Returns a deep copy of _zone_color_registry.
## BuildModeController calls this BEFORE placing/removing a wire so it can
## restore exact zone colors on undo.  Since colors are now persistent (not
## re-derived), this snapshot is the only way undo can rewind them correctly.
func snapshot_zone_colors() -> Dictionary:
	return _zone_color_registry.duplicate(true)


## Restore _zone_color_registry to a previously snapshotted state.
## Called by BuildModeController during undo.  After restoring, the next call
## to get_wire_zones_with_colors() will re-read the registry and emit the
## pre-placement colors without any re-assignment.
func restore_zone_colors(snapshot: Dictionary) -> void:
	_zone_color_registry = snapshot.duplicate(true)


## Returns zones with STABLE, PERSISTENT color indices.
## Each zone dict is the same as get_wire_zones() PLUS a "color_index" field.
##
## ── Stability guarantee ───────────────────────────────────────────────────────
## Zone identity = its "breaker signature" = sorted breaker node keys joined
## by "|".  Breaker node keys are position-based (e.g. "-6,4,18") and SURVIVE
## every auto-wire perimeter teardown/rebuild unchanged.
##
## The old scheme keyed on rep_edge_id, which is a perimeter edge ID that gets
## brand-new IDs every rebuild → zone appeared "new" every rebuild → all zones
## reset to light blue.  Breaker signatures fix this completely.
##
## Sentinel: a zone with NO bounding breakers (entire unbroken perimeter) uses
## the signature "__MAIN__".  This is the only zone that exists before any
## breakers are placed, and it always gets color 0 (light blue).
##
## ── New zone coloring ─────────────────────────────────────────────────────────
## New zones (no registry entry for their signature) get the lowest palette
## index not used by any neighboring zone (greedy graph-coloring).
##
## ── Zone merges ───────────────────────────────────────────────────────────────
## When two zones merge (a breaker is removed), the surviving zone's signature
## changes.  Old signatures are pruned; the new signature inherits the color of
## the larger predecessor.
##
## ── No re-coloring of existing zones ─────────────────────────────────────────
## Adding/removing perimeter wires NEVER changes the color of an existing zone.
## Colors only change when the zone's breaker boundary changes.
func get_wire_zones_with_colors() -> Array[Dictionary]:
	var raw_zones: Array[Dictionary] = get_wire_zones()
	if raw_zones.is_empty():
		_zone_color_registry.clear()
		return []

	## ── DETERMINISTIC GREEDY GRAPH-COLORING (always-distinct policy) ──────────
	## User decision (Jun 2026): zone colors must ALWAYS be valid and distinct
	## (no two adjacent zones share a color, never "both green"), even if a
	## color occasionally changes after a bunker expansion.  Perfect color
	## persistence across expansion is impossible because expansion physically
	## moves the perimeter, so no perimeter-based identity is stable.
	##
	## Algorithm:
	##   1. Per-zone stable sort key = min NON-breaker node key (deterministic,
	##      same topology → same key → same color every rebuild).  Falls back to
	##      min of ALL node keys, then to "__MAIN__", so every zone has a key.
	##   2. Build zone adjacency: two zones are adjacent if they share a bounding
	##      breaker (they border each other across that breaker).
	##   3. Process zones in ascending sort-key order; assign each the lowest
	##      palette index not used by an already-colored ADJACENT zone — classic
	##      greedy graph-coloring.  Determinism comes from the stable ordering.
	##
	## The registry is still written (so undo snapshot/restore keeps working) but
	## it is fully RECOMPUTED here every call — it is a cache of the deterministic
	## result, not a persistence anchor.
	_zone_color_registry.clear()

	## ── 1. Stable per-zone sort key ──────────────────────────────────────────
	var breaker_key_set: Dictionary = {}
	for bid: String in _breakers:
		var bkk: String = _breakers[bid].get("node_key", "")
		if not bkk.is_empty():
			breaker_key_set[bkk] = true

	var zone_sort_key: Array[String] = []
	for zi: int in raw_zones.size():
		var nkeys: Array = (raw_zones[zi].get("node_keys", []) as Array)
		var min_non_brk: String = ""
		var min_any: String = ""
		for nk: String in nkeys:
			if min_any.is_empty() or nk < min_any:
				min_any = nk
			if not breaker_key_set.has(nk):
				if min_non_brk.is_empty() or nk < min_non_brk:
					min_non_brk = nk
		var sk: String = min_non_brk
		if sk.is_empty():
			sk = min_any
		if sk.is_empty():
			sk = "__MAIN__"
		zone_sort_key.append(sk)

	## ── 2. Zone adjacency via shared bounding breakers ───────────────────────
	var zone_adjacent: Array[Array] = []
	for _i: int in raw_zones.size():
		zone_adjacent.append([])
	var brk_to_zones: Dictionary = {}   ## breaker_key → Array[int]
	for zi: int in raw_zones.size():
		for bk: String in (raw_zones[zi].get("breaker_keys", []) as Array):
			if not brk_to_zones.has(bk):
				brk_to_zones[bk] = []
			if not (brk_to_zones[bk] as Array).has(zi):
				(brk_to_zones[bk] as Array).append(zi)
	for bk: String in brk_to_zones:
		var adj: Array = brk_to_zones[bk] as Array
		for ia: int in adj.size():
			for ib: int in range(ia + 1, adj.size()):
				var za: int = int(adj[ia])
				var zb: int = int(adj[ib])
				if not (zone_adjacent[za] as Array).has(zb):
					(zone_adjacent[za] as Array).append(zb)
				if not (zone_adjacent[zb] as Array).has(za):
					(zone_adjacent[zb] as Array).append(za)

	## ── 3. Greedy coloring in deterministic order ────────────────────────────
	## Process zones sorted by (sort_key, then index) for a fully stable order.
	var order: Array[int] = []
	for zi: int in raw_zones.size():
		order.append(zi)
	order.sort_custom(func(a: int, b: int) -> bool:
		if zone_sort_key[a] != zone_sort_key[b]:
			return zone_sort_key[a] < zone_sort_key[b]
		return a < b)

	var zi_to_color: Dictionary = {}   ## zi → color_index
	for zi: int in order:
		var blocked: Dictionary = {}
		for adj_zi: int in (zone_adjacent[zi] as Array):
			if zi_to_color.has(adj_zi):
				blocked[int(zi_to_color[adj_zi])] = true
		## Pick lowest unblocked palette index.
		var chosen: int = 0
		var c: int = 0
		while true:
			var candidate: int = c % ZONE_COLORS.size()
			if not blocked.has(candidate):
				chosen = candidate
				break
			c += 1
			if c > 256:
				chosen = 0
				break
		zi_to_color[zi] = chosen
		## Cache into registry keyed by this zone's stable sort key (undo support).
		_zone_color_registry[zone_sort_key[zi]] = chosen

	## ── 4. Emit result ────────────────────────────────────────────────────────
	var out: Array[Dictionary] = []
	for zi: int in raw_zones.size():
		var z: Dictionary = raw_zones[zi].duplicate()
		z["color_index"] = int(zi_to_color.get(zi, 0))
		## "zone_key" — the stable zone identity used by _zone_color_registry
		## above. Exposed so callers (get_zone_snapshot(), UI, world-wire
		## coloring) can look up player overrides via zone_display_color()/
		## get_zone_display_name() without recomputing this key themselves.
		z["zone_key"] = zone_sort_key[zi]
		out.append(z)

	return out

func get_wire_zones() -> Array[Dictionary]:
	## Collect the set of snap keys that are breaker nodes.
	var breaker_keys: Dictionary = {}
	for bid: String in _breakers:
		var bk: String = _breakers[bid].get("node_key", "")
		if not bk.is_empty():
			breaker_keys[bk] = true


	## If no breakers exist, still run BFS to split disconnected wire islands
	## into separate zones rather than lumping everything into zone 0.
	## (Falls through to the BFS block below — breaker_keys stays empty so
	##  every endpoint is treated as a non-breaker and the flood-fill splits
	##  correctly by physical connectivity.)

	## Build a node→edge adjacency that skips breaker nodes as pass-through:
	## an edge is included if AT LEAST ONE endpoint is NOT a breaker.
	## Edges where both endpoints are breakers are excluded from all zones.
	## The adjacency maps non-breaker snap keys to their neighbouring non-breaker
	## snap keys via edges that don't cross two breakers.
	##
	## Actually we walk by edge: for each edge, if neither endpoint is a breaker,
	## include in adjacency normally. If exactly one endpoint is a breaker, we
	## treat the breaker node as a wall — the edge is a terminal edge for the
	## non-breaker endpoint (it doesn't connect through to other edges beyond
	## the breaker). This means we simply DO NOT add adjacency through breakers.

	## Build node→[edge_id] adjacency for non-breaker endpoints only.
	var node_edges: Dictionary = {}   ## snap_key → Array[String] (edge_ids)
	for eid: String in _wire_edges:
		var edge: Dictionary = _wire_edges[eid]
		var na: String = edge.get("node_a", "")
		var nb: String = edge.get("node_b", "")
		var a_is_brk: bool = breaker_keys.has(na)
		var b_is_brk: bool = breaker_keys.has(nb)
		if a_is_brk and b_is_brk:
			continue   ## Edge between two breakers — skip
		## Add to each non-breaker endpoint's list.
		if not a_is_brk:
			if not node_edges.has(na):
				node_edges[na] = []
			(node_edges[na] as Array).append(eid)
		if not b_is_brk:
			if not node_edges.has(nb):
				node_edges[nb] = []
			(node_edges[nb] as Array).append(eid)

	## BFS over edges to find connected components (zones).
	## We start from an unvisited edge, flood-fill through shared non-breaker
	## endpoints, and collect all reachable edges into one zone.
	var visited_edges: Dictionary = {}   ## edge_id → true
	var zones: Array[Dictionary] = []

	for start_eid: String in _wire_edges:
		if visited_edges.has(start_eid):
			continue
		var edge: Dictionary = _wire_edges[start_eid]
		var na: String = edge.get("node_a", "")
		var nb: String = edge.get("node_b", "")
		## Skip edges between two breakers.
		if breaker_keys.has(na) and breaker_keys.has(nb):
			continue

		## BFS flood-fill.
		var zone_edges: Array[String] = []
		var queue: Array[String] = [start_eid]
		while not queue.is_empty():
			var cur_eid: String = queue.pop_front()
			if visited_edges.has(cur_eid):
				continue
			visited_edges[cur_eid] = true
			zone_edges.append(cur_eid)

			## Expand through each non-breaker endpoint of this edge.
			var cur_edge: Dictionary = _wire_edges[cur_eid]
			for endpoint_key: String in [cur_edge.get("node_a", ""), cur_edge.get("node_b", "")]:
				if endpoint_key.is_empty() or breaker_keys.has(endpoint_key):
					continue
				## All edges touching this non-breaker node are in the same zone.
				if node_edges.has(endpoint_key):
					for neighbour_eid: String in (node_edges[endpoint_key] as Array):
						if not visited_edges.has(neighbour_eid):
							queue.append(neighbour_eid)

		if not zone_edges.is_empty():
			## Collect unique node snap keys for this zone (both endpoints of
			## every edge).  NON-breaker keys change position on every wire
			## rebuild (perimeter is torn down + re-laid), so they are
			## unreliable as color-registry anchors.  BREAKER keys are stable —
			## breakers are placed on inner walls and survive expansion — so we
			## INCLUDE them in node_keys specifically to give get_wire_zones_with_colors()
			## a stable identifier that survives a full auto-wire teardown/rebuild.
			var zone_node_set: Dictionary = {}
			var zone_brk_set:  Dictionary = {}   ## breaker keys bounding this zone
			for eid: String in zone_edges:
				var ze: Dictionary = _wire_edges.get(eid, {})
				var za: String     = ze.get("node_a", "")
				var zb: String     = ze.get("node_b", "")
				if not za.is_empty():
					if breaker_keys.has(za):
						zone_brk_set[za] = true   ## stable anchor
					else:
						zone_node_set[za] = true
				if not zb.is_empty():
					if breaker_keys.has(zb):
						zone_brk_set[zb] = true   ## stable anchor
					else:
						zone_node_set[zb] = true
			## Merge breaker keys INTO node_keys so the registry can anchor on them.
			for bk: String in zone_brk_set:
				zone_node_set[bk] = true
			_pmdbg("[PM:ZONES] zone %d: %d edges, %d node_keys (incl %d breaker anchors) brk_keys=%s" % [
				zones.size(), zone_edges.size(), zone_node_set.size(),
				zone_brk_set.size(), zone_brk_set.keys()])
			zones.append({
				"edge_ids":    zone_edges,
				"node_keys":   zone_node_set.keys(),
				"breaker_keys": zone_brk_set.keys(),   ## stable anchors for color registry
				"index":       zones.size(),
			})

	_pmdbg("[PM:ZONES] get_wire_zones total=%d, breaker_keys=%s" % [zones.size(), breaker_keys.keys()])
	return zones


## ─── Cached zone helpers ─────────────────────────────────────────────────────
## Returns cached get_wire_zones() result.  Rebuilds if invalidated.
## Use this in per-frame code (_tick_batteries) instead of get_wire_zones().
func get_wire_zones_cached() -> Array[Dictionary]:
	if not _zone_cache_valid:
		_zone_cache       = get_wire_zones()
		_zone_cache_valid = true
		_node_to_zone_idx.clear()
		for zi: int in _zone_cache.size():
			for nk: String in (_zone_cache[zi].get("node_keys", []) as Array):
				_node_to_zone_idx[nk] = zi
	return _zone_cache

## Returns the set of snap keys in the same zone as node_key using the cache.
## Returns an empty Dictionary if node_key is not in any zone.
func get_zone_node_set_for_key_cached(node_key: String) -> Dictionary:
	get_wire_zones_cached()   ## ensure cache is warm
	if not _node_to_zone_idx.has(node_key):
		return {}
	var zi: int = int(_node_to_zone_idx[node_key])
	if zi < 0 or zi >= _zone_cache.size():
		return {}
	var out: Dictionary = {}
	for nk: String in (_zone_cache[zi].get("node_keys", []) as Array):
		out[nk] = true
	return out


## ─── True edge endpoints (single source of truth) ────────────────────────────
## Returns the EXACT world-space endpoints of a logical edge, derived purely
## from the power graph (_wire_nodes positions, with snap-key fallback — the
## SAME decode the zone BFS uses).  This is the geometry the visual tube MUST
## span.  Returns false if the edge id is unknown.
func get_edge_world_endpoints(edge_id: String) -> Dictionary:
	if not _wire_edges.has(edge_id):
		return {"ok": false}
	var edge: Dictionary = _wire_edges[edge_id]
	var na: String = edge.get("node_a", "")
	var nb: String = edge.get("node_b", "")
	var pa: Vector3 = _node_world_pos(na)
	var pb: Vector3 = _node_world_pos(nb)
	return {"ok": true, "a": pa, "b": pb}

## Decode a node snap key to its exact world position.  Prefers the stored
## _wire_nodes pos; falls back to reconstructing from the snap-key integers
## (auto-created joints may carry Vector3.ZERO until a device registers a pos).
func _node_world_pos(node_key: String) -> Vector3:
	if node_key.is_empty():
		return Vector3.ZERO
	if _wire_nodes.has(node_key):
		var p: Vector3 = _wire_nodes[node_key].get("pos", Vector3.ZERO)
		if p != Vector3.ZERO:
			return p
	## Fallback: rebuild from "ix,iy,iz" * SNAP_GRID.
	var tok: PackedStringArray = node_key.split(",")
	if tok.size() == 3:
		return Vector3(int(tok[0]) * SNAP_GRID,
					   int(tok[1]) * SNAP_GRID,
					   int(tok[2]) * SNAP_GRID)
	return Vector3.ZERO


## ─── VISUAL ↔ GRAPH RECONCILIATION ───────────────────────────────────────────
## Forces the visual wire layer to be a PURE DERIVATIVE of the power graph.
## After this runs, the following invariants ALWAYS hold:
##   1. Every logical edge in _wire_edges owns EXACTLY ONE scene tube.
##   2. That tube's mesh spans EXACTLY the edge's true endpoints (no inset,
##      no leftover full-grid coverage) — so a zone seam lands precisely at
##      the breaker on every wall, every time.
##   3. No orphan tubes survive: any WireSegment whose edge_id is not in the
##      current graph is freed (ghost / drag-preview tubes are never touched).
##
## This is the structural fix for "visual split offset from breaker": instead of
## trying to keep geometry correct inside every mutation path, we re-derive it
## from the graph on EVERY grid change.  Call this from the recolor pass (which
## already fires on every topology change) BEFORE colors are applied.
##
## Cheap: one pass over _wire_edges + one pass over the wire_segment group.
## Returns the number of tubes whose endpoints were corrected (for debug).
func reconcile_wire_visuals() -> int:
	if get_tree() == null:
		return 0

	## ── 1. Index existing scene tubes by edge_id ─────────────────────────────
	var tubes_by_eid: Dictionary = {}   ## edge_id → Node3D (first seen)
	var dup_tubes:    Array       = []   ## extra tubes sharing an edge_id
	var orphan_tubes: Array       = []   ## tubes whose edge_id isn't in graph
	for ws: Node in get_tree().get_nodes_in_group("wire_segment"):
		if not is_instance_valid(ws):
			continue
		## Never touch drag-preview / ghost tubes — they're transient.
		if "is_ghost" in ws and bool(ws.get("is_ghost")):
			continue
		var eid: String = String(ws.get("edge_id")) if ("edge_id" in ws and ws.get("edge_id") != null) else ""
		if eid.is_empty():
			continue   ## untagged tube — leave it (e.g. mid-spawn before edge_id set)
		if not _wire_edges.has(eid):
			orphan_tubes.append(ws)         ## edge gone from graph → free later
			continue
		if tubes_by_eid.has(eid):
			dup_tubes.append(ws)            ## second tube for same edge → free later
		else:
			tubes_by_eid[eid] = ws

	## ── 2. Free orphans + duplicates (enforce one-mesh-per-edge) ─────────────
	var freed: int = 0
	for ws: Node in orphan_tubes:
		if is_instance_valid(ws):
			ws.queue_free()
			freed += 1
	for ws: Node in dup_tubes:
		if is_instance_valid(ws):
			ws.queue_free()
			freed += 1

	## ── 3. Every graph edge: force its tube to span the TRUE endpoints ───────
	var corrected: int = 0
	for eid: String in _wire_edges:
		var ep: Dictionary = get_edge_world_endpoints(eid)
		if not bool(ep.get("ok", false)):
			continue
		var pa: Vector3 = ep["a"]
		var pb: Vector3 = ep["b"]
		## Skip degenerate edges (zero length) — nothing to draw.
		if pa.distance_to(pb) < SNAP_GRID * 0.5:
			continue
		## Never show a tube for logical-only edges (e.g. wall-light auto-connect).
		## This also catches pre-existing tubes on edges that were registered
		## before the no_visual flag existed — free them on first reconcile.
		var is_no_visual: bool = bool(_wire_edges[eid].get("no_visual", false))
		var tube: Node3D = tubes_by_eid.get(eid, null)
		if is_no_visual:
			if tube != null and is_instance_valid(tube):
				tube.queue_free()   ## remove any stale tube on a logical-only edge
				freed += 1
			continue   ## never spawn one either
		if tube == null:
			## Missing tube for a live edge — spawn one (reuse-before-spawn).
			tube = _graph._spawn_or_reuse_wire_visual(eid, pa, pb)
			if tube != null:
				tubes_by_eid[eid] = tube
				corrected += 1
			continue
		## Tube exists — force its geometry to match the graph exactly.
		## set_endpoints rebuilds the mesh between pa→pb with NO inset, so this
		## guarantees the visual span == the logical span.
		var cur_a: Vector3 = tube.get("point_a") if "point_a" in tube else Vector3.INF
		var cur_b: Vector3 = tube.get("point_b") if "point_b" in tube else Vector3.INF
		## Only rebuild if geometry actually drifted (avoid needless mesh rebuilds).
		var drifted: bool = cur_a.distance_to(pa) > 0.001 or cur_b.distance_to(pb) > 0.001
		if drifted and tube.has_method("set_endpoints"):
			tube.call("set_endpoints", pa, pb)
			corrected += 1
		## Keep the node's cached edge_id in sync (defensive).
		if "edge_id" in tube and String(tube.get("edge_id")) != eid:
			tube.set("edge_id", eid)

	if RECONCILE_DEBUG and (corrected > 0 or freed > 0):
		_pmdbg("[PM:RECONCILE] edges=%d  tubes_corrected=%d  freed(orphan+dup)=%d" % [
			_wire_edges.size(), corrected, freed])
	return corrected


## Returns all registered wire edges as Array[Dictionary].
func get_wire_edges() -> Array[Dictionary]:
	return _graph.get_wire_edges()

## Link a scene node to an existing wire edge after the fact.
## Called by MainWorld after spawning a pregen WireSegment so that
## _split_wire_edge_at() can find and resize the visual when a breaker
## is placed on a pregen wire.
func set_wire_edge_node(edge_id: String, scene_node: Node) -> void:
	if _wire_edges.has(edge_id):
		_wire_edges[edge_id]["node"] = scene_node

## Stamp an existing edge as logical-only (no visual tube).
## Called by WallLight after register_wire_edge so that even edges created
## before the no_visual flag existed get correctly marked on next reconcile.
func set_wire_edge_no_visual(edge_id: String) -> void:
	if _wire_edges.has(edge_id):
		_wire_edges[edge_id]["no_visual"] = true

## Returns all registered circuit breakers as Array[Dictionary].
## Each dict has: id, node_key, tripped, node.
func get_breakers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for brk: Dictionary in _breakers.values():
		out.append(brk.duplicate())
	return out

func get_status() -> Dictionary:
	return {
		"state":       get_grid_state_string(),
		"draw_w":      active_draw_watts,
		"capacity_w":  total_capacity_watts,
		"load_pct":    int(load_ratio() * 100.0),
		"battery_pct": int(battery_charge_ratio() * 100.0),
		"consumers":   _consumers.size(),
		"generators":  _generators.size(),
		"batteries":   _batteries.size(),
		"wire_nodes":  _wire_nodes.size(),
		"wire_edges":  _wire_edges.size(),
		"breakers":    _breakers.size(),
	}


## Get the load on a specific wire segment (watts). Returns 0 if edge unknown.
func get_edge_load(edge_id: String) -> float:
	return float(_wire_edges.get(edge_id, {}).get("load_w", 0.0))


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — NETWORK SOLVER
# ═══════════════════════════════════════════════════════════════════════════════

## Core solver — call this after any topology change (node/edge add/remove,
## breaker trip/reset, generator start/stop).
## ─── Bulk-edit window ────────────────────────────────────────────────────────
## Wrap a burst of topology changes (e.g. MainWorld._rebuild_auto_wires, which
## fires dozens of register/unregister calls) in begin_bulk()/end_bulk() so the
## intermediate _solve_network() calls defer and only ONE solve runs at the end.
## Reference-counted so nested windows are safe; the final end_bulk() solves once
## if anything inside requested a resolve.  Outside a window, solves stay
## synchronous exactly as before.
func begin_bulk() -> void:
	_bulk_depth += 1
	## Clear wire-debug log at the start of every rebuild window so each F9
	## dump reflects only the most recent begin_bulk/end_bulk pass.
	_pm_wire_log.clear()

func end_bulk() -> void:
	if _bulk_depth > 0:
		_bulk_depth -= 1
	## Only the outermost end_bulk() triggers the coalesced solve.
	if _bulk_depth == 0 and _needs_resolve:
		_needs_resolve = false
		_solve_network()

## Force a solve immediately, bypassing the _needs_resolve gate.
## Use when re-registration was fully idempotent (all edges already existed)
## so _needs_resolve was never set, but the graph state has changed and a
## fresh solve is still required (e.g. reconciler re-applying player wires).
## Still defers correctly if called inside an open bulk window.
func request_solve() -> void:
	if _bulk_depth > 0:
		_needs_resolve = true   ## defer to the outermost end_bulk
		return
	_solve_network()

func _solve_network() -> void:
	## Re-entry guard: _go_offline → _solve_network → _evaluate_per_component
	## → _start_flicker_offline → _go_offline would cause infinite recursion.
	_pmdbg("[PM:SOLVE] _solve_network called — grid_state=%s wire_nodes=%d wire_edges=%d consumers=%d gens=%d" % [
		get_grid_state_string(), _wire_nodes.size(), _wire_edges.size(),
		_consumers.size(), _generators.size()])
	if _solving:
		_pmdbg("[PM:SOLVE] re-entry guard triggered, skipping")
		return
	## Bulk-edit guard: inside a begin_bulk/end_bulk window we DEFER the solve so
	## a burst of topology mutations collapses into one solve at end_bulk().
	## Caches are still invalidated below (cheap) so any mid-bulk reader stays
	## correct; the heavy adjacency/BFS/eval work is what we skip until the end.
	if _bulk_depth > 0:
		_needs_resolve = true
		## Still invalidate caches — topology is changing under us.
		_zone_cache_valid      = false
		_zone_cache            = []
		_node_to_zone_idx      = {}
		_component_cache_valid = false
		_component_cache       = []
		_charge_consumer_wire_key_cache.clear()
		return
	## Invalidate zone cache on every topology change regardless of grid state.
	_zone_cache_valid = false
	_zone_cache       = []
	_node_to_zone_idx = {}
	## Invalidate the connected-component cache — _adjacency is about to change.
	## (Rebuilt lazily on the next _find_components() call, after _build_adjacency.)
	_component_cache_valid = false
	_component_cache       = []
	## Invalidate the charge-path consumer wire-key cache — wire topology changed.
	_charge_consumer_wire_key_cache.clear()
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		_cut_all_consumers()
		return
	if _flickering:
		return   ## Let flicker complete; it will call _go_offline() when done.

	_solving = true
	_build_adjacency()
	_run_bfs()
	_apply_reachability()
	_calculate_edge_loads()
	_evaluate_per_component()   ## zone-aware draw + shed + state evaluation
	draw_changed.emit(active_draw_watts, total_capacity_watts, battery_charge_ratio())
	_solving = false


## Build two adjacency graphs from live edges:
##   _adjacency      — full graph: respects tripped breakers + pass_battery flags
##                     (used by battery BFS and by the generic solver BFS).
##   _adjacency_gen  — generator-only graph: also blocks breakers where
##                     pass_generator=false (used to seed BFS from generators).
##
## A breaker node blocks both graphs when tripped.
## When NOT tripped, pass_battery/pass_generator independently control which
## graph the breaker stays open in.
func _build_adjacency() -> void:
	_adjacency.clear()
	_adjacency_gen.clear()

	## Categorise breaker nodes.
	var tripped_nodes: Dictionary     = {}   ## node_key → true  (both graphs blocked)
	var bat_blocked_nodes: Dictionary = {}   ## node_key → true  (battery graph blocked)
	var gen_blocked_nodes: Dictionary = {}   ## node_key → true  (gen graph only blocked)

	for brk: Dictionary in _breakers.values():
		var bk: String = brk["node_key"]
		if brk.get("tripped", false):
			tripped_nodes[bk] = true
		else:
			## pass_battery=false blocks battery current through this breaker.
			if not brk.get("pass_battery", true):
				bat_blocked_nodes[bk] = true
			## pass_generator=false blocks generator BFS through this breaker.
			if not brk.get("pass_generator", true):
				gen_blocked_nodes[bk] = true


	_pmdbg("[PM:ADJ] tripped_nodes=%s bat_blocked=%s gen_blocked=%s total_edges=%d" % [
		tripped_nodes.keys(), bat_blocked_nodes.keys(), gen_blocked_nodes.keys(),
		_wire_edges.size()])
	for edge: Dictionary in _wire_edges.values():
		var a: String = edge["node_a"]
		var b: String = edge["node_b"]
		if not _wire_nodes.has(a) or not _wire_nodes.has(b):
			_pmdbg("[PM:ADJ]   SKIP edge %s→%s (missing wire node)" % [a, b])
			continue

		## ── Full adjacency (battery graph) — blocked by tripped OR pass_battery=false ──
		var bat_blocked: bool = tripped_nodes.has(a) or tripped_nodes.has(b) \
			or bat_blocked_nodes.has(a) or bat_blocked_nodes.has(b)
		if not bat_blocked:
			if not _adjacency.has(a): _adjacency[a] = []
			if not _adjacency.has(b): _adjacency[b] = []
			(_adjacency[a] as Array).append(b)
			(_adjacency[b] as Array).append(a)

		## ── Generator adjacency (blocks pass_generator=false breakers too) ──
		var gen_blocked: bool = tripped_nodes.has(a) or tripped_nodes.has(b) \
			or gen_blocked_nodes.has(a) or gen_blocked_nodes.has(b)
		if not gen_blocked:
			if not _adjacency_gen.has(a): _adjacency_gen[a] = []
			if not _adjacency_gen.has(b): _adjacency_gen[b] = []
			(_adjacency_gen[a] as Array).append(b)
			(_adjacency_gen[b] as Array).append(a)

	_pmdbg("[PM:ADJ] _build_adjacency done: _adjacency=%d nodes, _adjacency_gen=%d nodes" % [
		_adjacency.size(), _adjacency_gen.size()])
	for ak: String in _adjacency:
		_pmdbg("[PM:ADJ]   bat_adj[%s] → %s" % [ak, str(_adjacency[ak])])
	for ak: String in _adjacency_gen:
		_pmdbg("[PM:ADJ]   gen_adj[%s] → %s" % [ak, str(_adjacency_gen[ak])])


## Point-to-point BFS through _adjacency (battery graph, respects pass_battery=false).
## Returns true if target_key is reachable from origin_key.
## Used by cross-zone battery classification in _evaluate_per_component.
func _adjacency_bfs_can_reach(origin_key: String, target_key: String) -> bool:
	if origin_key == target_key:
		return true
	if not _adjacency.has(origin_key):
		return false
	var visited: Dictionary = {}
	var queue: Array[String] = [origin_key]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == target_key:
			return true
		if visited.has(cur):
			continue
		visited[cur] = true
		if _adjacency.has(cur):
			for nb: String in (_adjacency[cur] as Array):
				if not visited.has(nb):
					queue.append(nb)
	return false


## BFS from all running generator wire nodes AND discharging battery wire nodes.
##
## Generators use _adjacency_gen (respects pass_generator=false breakers).
## Batteries use _adjacency (pass_battery=false breakers are blocked at build time,
## so batteries only flow through breakers where pass_battery=true).
## The _reachable set is the UNION of both BFS results.
func _run_bfs() -> void:
	_reachable.clear()
	for wn: Dictionary in _wire_nodes.values():
		wn["reachable"] = false

	var gen_queue: Array[String] = []
	var bat_queue: Array[String] = []

	_pmdbg("[PM:BFS] --- _run_bfs START ---")
	_pmdbg("[PM:BFS] generators registered: %d, batteries registered: %d, wire_nodes: %d" % [
		_generators.size(), _batteries.size(), _wire_nodes.size()])
	## Log all wire nodes with role=generator to diagnose seeding failures.
	for wn: Dictionary in _wire_nodes.values():
		if wn.get("role","") == "generator":
			_pmdbg("[PM:BFS]   gen-wire-node key=%s device_id=%s" % [wn["key"], wn.get("device_id","")])
	## Seed generators → gen queue (uses _adjacency_gen).
	for gen: Dictionary in _generators.values():
		_pmdbg("[PM:BFS] gen id=%s running=%s fuel=%.1f health=%.1f" % [
			gen.get("id","?"), str(gen.get("running",false)),
			gen.get("fuel",0.0), gen.get("health",0.0)])
		if not gen.get("running", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
				var key: String = wn["key"]
				if not _reachable.has(key):
					_reachable[key] = true
					wn["reachable"] = true
					gen_queue.append(key)
					_pmdbg("[PM:BFS]   gen seed key=%s" % key)
				break

	_pmdbg("[PM:BFS] gen_queue seeds: %s" % str(gen_queue))
	## Seed discharging batteries → bat queue (uses _adjacency).
	for bat: Dictionary in _batteries.values():
		if not bat.get("discharging", false):
			continue
		if not bat.get("enabled", true):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
				var key: String = wn["key"]
				if not _reachable.has(key):
					_reachable[key] = true
					wn["reachable"] = true
					bat_queue.append(key)
				break

	## BFS from generator seeds through _adjacency_gen.
	var head: int = 0
	while head < gen_queue.size():
		var current: String = gen_queue[head]
		head += 1
		if not _adjacency_gen.has(current):
			_pmdbg("[PM:BFS]   gen BFS: no adj entry for key=%s" % current)
			continue
		for neighbor: String in (_adjacency_gen[current] as Array):
			if not _reachable.has(neighbor):
				_reachable[neighbor] = true
				if _wire_nodes.has(neighbor):
					_wire_nodes[neighbor]["reachable"] = true
				gen_queue.append(neighbor)

	_pmdbg("[PM:BFS] gen BFS done. reachable count=%d keys=%s" % [_reachable.size(), _reachable.keys()])
	## BFS from battery seeds through _adjacency.
	head = 0
	while head < bat_queue.size():
		var current: String = bat_queue[head]
		head += 1
		if not _adjacency.has(current):
			continue
		for neighbor: String in (_adjacency[current] as Array):
			if not _reachable.has(neighbor):
				_reachable[neighbor] = true
				if _wire_nodes.has(neighbor):
					_wire_nodes[neighbor]["reachable"] = true
				bat_queue.append(neighbor)


	_pmdbg("[PM:BFS] final reachable=%s" % str(_reachable.keys()))

## Apply power state to all consumers based on reachability.
func _apply_reachability() -> void:
	_pmdbg("[PM:REACH] --- _apply_reachability ---")
	for c: Dictionary in _consumers.values():
		var dev_id: String = c["id"]
		var node_reachable: bool = _is_consumer_reachable(dev_id)
		var should_power: bool = node_reachable \
			and c.get("active", false) \
			and not c.get("shed", false)
		var was_powered: bool = c.get("powered", false)
		_pmdbg("[PM:REACH]   consumer id=%s reachable=%s active=%s shed=%s => power=%s (was=%s)" % [
			dev_id, str(node_reachable), str(c.get("active",false)),
			str(c.get("shed",false)), str(should_power), str(was_powered)])
		c["powered"] = should_power
		if should_power != was_powered:
			_apply_power_to_consumer(c, should_power)

	## Notify each battery whether it is reachable in the wire graph.
	## A battery with no wire connection shows "INACTIVE" on its panel instead
	## of the misleading "IDLE" state.
	for bat: Dictionary in _batteries.values():
		var bat_id: String = bat["id"]
		var bat_reachable: bool = false
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "battery" and wn["device_id"] == bat_id:
				bat_reachable = wn.get("reachable", false)
				break
		var bat_node: Node = _safe_dict_node(bat)
		if bat_node != null and is_instance_valid(bat_node) \
				and bat_node.has_method("set_grid_connected"):
			bat_node.set_grid_connected(bat_reachable)


## Returns true if the consumer's wire node is in the reachable set.
func _is_consumer_reachable(consumer_id: String) -> bool:
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "consumer" and wn["device_id"] == consumer_id:
			return wn.get("reachable", false)
	return false


## Compute per-edge load (watts flowing through each segment).
func _calculate_edge_loads() -> void:
	for edge: Dictionary in _wire_edges.values():
		var load: float = _downstream_draw(edge["node_a"], edge["node_b"])
		edge["load_w"] = load


## BFS from 'from_node' toward 'into_node' — returns downstream consumer draw.
func _downstream_draw(from_node: String, into_node: String) -> float:
	if not _reachable.has(into_node):
		return 0.0

	var visited: Dictionary = {}
	visited[from_node] = true
	var queue: Array[String] = [into_node]
	var head: int = 0
	var total: float = 0.0

	while head < queue.size():
		var cur: String = queue[head]
		head += 1
		if visited.has(cur):
			continue
		visited[cur] = true

		if _wire_nodes.has(cur):
			var wn: Dictionary = _wire_nodes[cur]
			if wn["role"] == "consumer" and wn["device_id"] != "":
				var c: Dictionary = _consumers.get(wn["device_id"], {})
				if c.get("powered", false):
					total += float(c.get("watts", 0.0))

		if not _adjacency.has(cur):
			continue
		for neighbor: String in (_adjacency[cur] as Array):
			if not visited.has(neighbor):
				queue.append(neighbor)

	return total


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — GRID STATE MACHINE
# ═══════════════════════════════════════════════════════════════════════════════

## ─── Per-component draw recalculation ───────────────────────────────────────
## Sums draw only for consumers whose wire node is in component_keys.
## Also adds BATTERY_CHARGE_WATTS for batteries in this component that are
## currently charging.
## ── Forwarded to PowerSolver.gd (Stage 8b) ──────────────────────────────────
## These are the only solver functions still called from code living on
## PowerManager itself (_solve_network, _tick_batteries, set_generator_running,
## and a couple of zone-color UI helpers) — every other solver function moved
## in this slice is only ever called from other functions inside PowerSolver
## itself, so it needs no forwarding wrapper here. See PowerSolver.gd for the
## full function list and the reasoning behind this split.
func _evaluate_per_component() -> void:
	_solver._evaluate_per_component()


func _find_components() -> Array[Dictionary]:
	return _solver._find_components()


func _get_gen_sharing_zone_pairs(wire_zones: Array[Dictionary]) -> Array[Dictionary]:
	return _solver._get_gen_sharing_zone_pairs(wire_zones)


func _shed_residual_watts(c: Dictionary) -> float:
	return _solver._shed_residual_watts(c)


func _flood_component_keys(seed_keys: Dictionary) -> Dictionary:
	return _solver._flood_component_keys(seed_keys)


func _flood_gen_component_keys(seed_keys: Dictionary) -> Dictionary:
	return _solver._flood_gen_component_keys(seed_keys)


func clear_exhausted_brownout() -> void:
	_solver.clear_exhausted_brownout()



# ─── Flicker → offline sequence ───────────────────────────────────────────────
## Starts a short flicker sequence on all powered consumers, then cuts all power.
## Called when the grid is over capacity and shedding lights didn't fix it.
func _start_flicker_offline() -> void:
	if _flickering:
		return   ## Already in progress.
	_flickering       = true
	_flicker_timer    = 0.0
	_flicker_pulse_t  = 0.0
	_flicker_pulse_on = true
	## Transition to BROWNOUT briefly so the HUD can show the right state.
	if grid_state != GridState.BROWNOUT:
		var old: GridState = grid_state
		grid_state = GridState.BROWNOUT
		grid_state_changed.emit(grid_state, old)


## Called every frame while _flickering == true.
## Pulses all powered consumers on/off, then calls _go_offline().
func _tick_flicker(delta: float) -> void:
	_flicker_timer   += delta
	_flicker_pulse_t += delta

	## Toggle pulse state.
	var pulse_dur: float = FLICKER_ON_DURATION if _flicker_pulse_on else FLICKER_OFF_DURATION
	if _flicker_pulse_t >= pulse_dur:
		_flicker_pulse_t -= pulse_dur
		_flicker_pulse_on = not _flicker_pulse_on
		## Apply current pulse state ONLY to consumers on THIS grid (reachable).
		## Consumers on isolated/unwired grids must not flash when a different
		## part of the network overloads — they are powered by their own source.
		## Skip already-shed consumers: their node has a dim orange glow and
		## calling set_powered(true) would clear _is_shed + restore full brightness,
		## causing lights to be white instead of orange after the flicker ends.
		for c: Dictionary in _consumers.values():
			if c.get("active", false) \
					and not c.get("shed", false) \
					and _is_consumer_reachable(c["id"]):
				var n: Node = _safe_dict_node(c)
				if n != null and is_instance_valid(n) and n.has_method("set_powered"):
					n.set_powered(_flicker_pulse_on)

	## Flicker complete — go dark permanently.
	if _flicker_timer >= FLICKER_TOTAL_SECS:
		_flickering = false
		_go_offline()


func _unshed_all() -> void:
	for c: Dictionary in _consumers.values():
		if c.get("shed", false):
			c["shed"] = false
			## Reachability will re-power it on next solve.
			## Also clear the shed visual on the node.
			var n: Node = _safe_dict_node(c)
			if n != null and is_instance_valid(n) and n.has_method("set_shed"):
				n.set_shed(false)


## Shed every light consumer — called during battery takeover so only
## non-light devices draw from the battery.  Lights get the orange glow.
## Always re-applies set_shed(true) on the node even if already shed in dict,
## so that a flicker pulse which called set_powered(true) (clearing _is_shed on
## the node) is corrected before the network solve runs.
func _shed_all_lights() -> void:
	for c: Dictionary in _consumers.values():
		if c.get("type", "") in LIGHT_TYPES:
			c["shed"]    = true
			c["powered"] = false
			_apply_shed_to_consumer(c)   ## always re-sync node visual


func _trip_main_grid(reason: String) -> void:
	_flickering = false
	var old: GridState = grid_state
	grid_state        = GridState.TRIPPED
	_overload_timer   = 0.0
	_main_reset_timer = 0.0
	grid_state_changed.emit(grid_state, old)
	grid_tripped.emit()
	_cut_all_consumers()
	for gen: Dictionary in _generators.values():
		if gen.get("running", false):
			gen["running"]      = false
			gen["auto_started"] = false
			var n: Node = _safe_dict_node(gen)
			if n != null and is_instance_valid(n):
				if n.has_method("set_running"):
					n.set_running(false)
				if n.has_method("on_grid_tripped"):
					n.on_grid_tripped()
			generator_stopped.emit(gen["id"], "grid_tripped")
	_recalculate_capacity()



func _go_offline() -> void:
	## ── Battery takeover check ────────────────────────────────────────────────
	## TOPOLOGY RULE: only batteries physically connected on the SAME sub-grid
	## as the failing generator(s) may take over.  Batteries on isolated
	## segments (behind a tripped breaker or on an entirely separate wire run)
	## must NOT activate — they belong to a different circuit.
	##
	## We collect reachable batteries by doing a BFS from each stopped
	## generator's wire node BEFORE the adjacency is updated.  Because
	## _go_offline() is called from the state machine (not mid-BFS), the
	## adjacency still reflects the pre-failure wiring.
	##
	## If _go_offline() is called with no generators at all (first startup with
	## no gen), fall through to the full battery search as a safe fallback.

	## Build set of wire keys reachable from any (formerly) running generator
	## on this sub-graph.  We use the current _adjacency (built by the last
	## _solve_network call) so breaker isolation is respected.
	var affected_keys: Dictionary = {}   ## snap_key → true
	var found_any_gen: bool = false
	for gen: Dictionary in _generators.values():
		var gkey: String = _generator_wire_key(gen["id"])
		if gkey.is_empty():
			continue
		found_any_gen = true
		## BFS from this generator node through current adjacency.
		var visited: Dictionary = {}
		var queue: Array[String] = [gkey]
		visited[gkey] = true
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			affected_keys[cur] = true
			if _adjacency.has(cur):
				for nb: String in (_adjacency[cur] as Array):
					if not visited.has(nb):
						visited[nb] = true
						queue.append(nb)

	## Gather topology-local batteries — those whose wire node is in affected_keys.
	## If no generator wire nodes were found (edge case), use ALL batteries as
	## a safe fallback (single-grid bunker at startup).
	var local_batteries: Array[Dictionary] = []
	for bat: Dictionary in _batteries.values():
		var bkey: String = _battery_wire_key(bat["id"])
		if bkey.is_empty():
			continue
		if not found_any_gen or affected_keys.has(bkey):
			local_batteries.append(bat)

	## Any local battery with remaining charge AND enabled?
	var local_charge: float = 0.0
	for bat: Dictionary in local_batteries:
		if bat.get("enabled", true):
			local_charge += float(bat.get("charge_wh", 0.0))

	if local_charge > 0.0:
		## Stop ALL generators on this sub-grid — batteries take over.
		for gen: Dictionary in _generators.values():
			if not gen.get("running", false):
				continue
			var gkey: String = _generator_wire_key(gen["id"])
			## Only stop generators that are on the affected sub-graph.
			if found_any_gen and not affected_keys.has(gkey):
				continue
			gen["running"]      = false
			gen["auto_started"] = false
			var gn: Node = _safe_dict_node(gen)
			if gn != null and is_instance_valid(gn):
				if gn.has_method("set_running"):
					gn.set_running(false)
				if gn.has_method("on_grid_tripped"):
					gn.on_grid_tripped()
			generator_stopped.emit(gen["id"], "battery_takeover")
		_recalculate_capacity()   ## capacity now 0 for this sub-grid

		## Activate discharge on local batteries that have charge and are enabled.
		for bat: Dictionary in local_batteries:
			if float(bat.get("charge_wh", 0.0)) > 0.0 and bat.get("enabled", true):
				if not bat.get("discharging", false):
					bat["discharging"] = true
					bat["charging"]    = false
					battery_state_changed.emit(bat["id"], true)
					_notify_battery_mode(bat["id"])
					_notify_battery_node(bat["id"])

		## Shed all lights — batteries power non-lights only.
		_shed_all_lights()

		_flickering     = false
		_overload_timer = 0.0
		var bat_old: GridState = grid_state
		if bat_old != GridState.OVERLOADED:
			grid_state = GridState.OVERLOADED
			grid_state_changed.emit(grid_state, bat_old)
			overloaded_started.emit()

		_solve_network()

		return

	## No local batteries with charge to fall back on. This is the
	## self-protective TRIP the design doc describes: recoverable via
	## reset_main_breaker() + manually restarting repaired/refueled
	## generators — NOT the separate, more permanent GridState.OFFLINE
	## (reserved for "no generators + no battery exist anywhere in the
	## bunker at all", a distinct and rarer condition — see
	## reset_main_breaker()'s own guard, which explicitly refuses to run
	## while grid_state == OFFLINE but allows it from TRIPPED).
	## _trip_main_grid() already does everything needed here: stops all
	## generators, cuts all consumers, sets GridState.TRIPPED, emits
	## grid_tripped.
	_trip_main_grid("battery_exhausted")



# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — GENERATOR HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _start_generator(gen_id: String) -> void:
	if not _generators.has(gen_id):
		return
	var gen: Dictionary = _generators[gen_id]
	if gen.get("running", false):
		return
	gen["running"] = true
	var n: Node = _safe_dict_node(gen)
	if n != null and is_instance_valid(n) and n.has_method("set_running"):
		n.set_running(true)
	generator_started.emit(gen_id)
	_recalculate_capacity()

	## If we were running on battery power (OVERLOADED from battery takeover),
	## a generator coming back online ends battery-only mode:
	##   - Stop all batteries discharging (generator covers load now).
	##   - Restore shed lights.
	##   - Transition back to ONLINE.
	var was_battery_only: bool = false
	for bat: Dictionary in _batteries.values():
		if bat.get("discharging", false):
			was_battery_only = true
			bat["discharging"] = false
			bat["charging"]    = false
			battery_state_changed.emit(bat["id"], false)
			_notify_battery_mode(bat["id"])
			_notify_battery_node(bat["id"])

	if was_battery_only:
		_unshed_all()
		if grid_state == GridState.OVERLOADED:
			var old_s: GridState = grid_state
			grid_state = GridState.ONLINE
			_overload_timer = 0.0
			grid_state_changed.emit(grid_state, old_s)
			overloaded_ended.emit()
			grid_restored.emit()

	_solve_network()


func _stop_generator(gen_id: String, reason: String) -> void:
	if not _generators.has(gen_id):
		return
	var gen: Dictionary = _generators[gen_id]
	if not gen.get("running", false):
		return
	gen["running"]      = false
	gen["auto_started"] = false
	var n: Node = _safe_dict_node(gen)
	if n != null and is_instance_valid(n) and n.has_method("set_running"):
		n.set_running(false)
	generator_stopped.emit(gen_id, reason)
	if not gen.get("backup", false):
		_try_start_backups()
	_recalculate_capacity()
	_solve_network()


func _try_start_backups() -> void:
	if not _all_primaries_offline():
		return
	for gen: Dictionary in _generators.values():
		if gen.get("backup", false) \
				and not gen.get("running", false) \
				and float(gen.get("fuel", 0.0)) > 0.0 \
				and float(gen.get("health", 0.0)) > 0.0:
			gen["auto_started"] = true
			_start_generator(gen["id"])


## Start backup generators when the grid is brownout but primaries are alive.
## Returns true if at least one backup was newly started.
func _try_start_backups_for_overload() -> bool:
	var started_any: bool = false
	for gen: Dictionary in _generators.values():
		if gen.get("backup", false) \
				and not gen.get("running", false) \
				and float(gen.get("fuel", 0.0)) > 0.0 \
				and float(gen.get("health", 0.0)) > 0.0:
			gen["auto_started"] = true
			_start_generator(gen["id"])
			started_any = true
	return started_any


## Stop backup gens that auto-started when a primary comes back online.
func _stop_auto_backups() -> void:
	for gen: Dictionary in _generators.values():
		if gen.get("backup", false) \
				and gen.get("running", false) \
				and gen.get("auto_started", false):
			gen["auto_started"] = false
			_stop_generator(gen["id"], "primary_restored")


func _all_primaries_offline() -> bool:
	for gen: Dictionary in _generators.values():
		if not gen.get("backup", false) and gen.get("running", false):
			return false
	return true


func _recalculate_capacity() -> void:
	total_capacity_watts = 0.0
	for gen: Dictionary in _generators.values():
		if gen.get("running", false):
			total_capacity_watts += float(gen.get("watts", 0.0))


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — PROCESS TICKS
# ═══════════════════════════════════════════════════════════════════════════════

func _tick_generators(delta: float) -> void:
	## Generators only drain fuel when the grid is live and they are actually
	## providing power.  TRIPPED / OFFLINE → all generators should already be
	## stopped; skip entirely to prevent phantom fuel loss.
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		return

	const BASE_DRAIN: float = 0.125  ## %/sec for a 100%-share gen at full load

	var lr: float = clampf(load_ratio(), 0.0, 1.0)
	var total_w: float = maxf(total_capacity_watts, 1.0)

	for gen: Dictionary in _generators.values():
		## Only drain running generators that are actually contributing watts.
		## If all generators are stopped (battery takeover), nothing runs here.
		if not gen.get("running", false):
			continue

		## Admin/cheat generators (F7 menu, PowerManager.admin_add_power())
		## never drain — they represent an infinite external supply, not a
		## physical fuel-burning unit.
		if gen.get("infinite", false):
			continue

		var gen_w:    float = maxf(float(gen.get("watts", 0.0)), 1.0)
		var share:    float = clampf(gen_w / total_w, 0.0, 1.0)
		var drain:    float = BASE_DRAIN * share * (0.2 + 0.8 * lr)

		gen["fuel"] = maxf(0.0, float(gen["fuel"]) - drain * delta)

		var gen_node: Node = _safe_dict_node(gen)
		if gen_node != null and is_instance_valid(gen_node) and gen_node.has_method("set_fuel"):
			gen_node.call("set_fuel", gen["fuel"])

		if gen["fuel"] <= 0.0:
			_stop_generator(gen["id"], "fuel")
		elif gen["fuel"] < 25.0:
			generator_fuel_low.emit(gen["id"], gen["fuel"])


## Max watts a single battery can output before accelerated drain kicks in.
const BATTERY_OUTPUT_CAP_WATTS: float = 500.0

func _tick_batteries(delta: float) -> void:
	## ── DISCHARGE path ────────────────────────────────────────────────────────
	## TOPOLOGY RULE: each discharging battery only covers load from consumers
	## on ITS OWN sub-grid segment.  We group discharging batteries by their
	## connected component (identified by which consumers are reachable from
	## their wire node), then drain each group proportionally to its local load.
	##
	## This prevents a battery on Sub-Grid B from helping Sub-Grid A just
	## because they are both registered in _batteries.

	var any_discharging: bool = false
	for bat: Dictionary in _batteries.values():
		if bat.get("discharging", false) and bat.get("enabled", true):
			any_discharging = true
			break

	if any_discharging:
		## Group batteries by connected component (snap key of their wire node).
		var discharge_groups: Dictionary = {}
		## group_key (lex-min node key of component) → { "batteries": [], "load_w": float, "visited": Dictionary }

		## ── OPTIMISATION: run component BFS exactly ONCE for the whole graph ──
		## Old code ran a full BFS per battery → O(N_batteries × graph_size) per
		## frame which killed FPS with even 2 batteries.  Instead call
		## _find_components() once (one pass over _adjacency), then assign each
		## battery to whichever component its wire key landed in.
		var components: Array[Dictionary] = _find_components()
		## Build snap_key → component_index map for O(1) lookup.
		var key_to_comp: Dictionary = {}   ## String → int
		for ci: int in components.size():
			for ck: String in (components[ci]["keys"] as Dictionary).keys():
				key_to_comp[ck] = ci

		## Pre-build consumer wire-key lookup to avoid inner-loop _wire_nodes scan.
		## consumer_id → wire node key (first found)
		var consumer_wire_key: Dictionary = {}
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and not (wn["device_id"] as String).is_empty():
				var did: String = wn["device_id"]
				if not consumer_wire_key.has(did):
					consumer_wire_key[did] = wn["key"]

		## Assign each discharging battery to its component group.
		for bat: Dictionary in _batteries.values():
			if not bat.get("discharging", false) or not bat.get("enabled", true):
				continue
			var bkey: String = _battery_wire_key(bat["id"])
			if bkey.is_empty():
				continue   ## Battery has no wire node — cannot serve anyone.
			if not key_to_comp.has(bkey):
				continue   ## Isolated node (no adjacency entry yet).
			var ci: int = int(key_to_comp[bkey])
			var comp_keys: Dictionary = components[ci]["keys"]

			## Canonical group id = lex-min key of component (deterministic).
			var group_id: String = ""
			for ck: String in comp_keys:
				if group_id.is_empty() or ck < group_id:
					group_id = ck

			if not discharge_groups.has(group_id):
				## Compute local consumer draw once per component group.
				var local_draw: float = 0.0
				for c: Dictionary in _consumers.values():
					if not _is_consumer_reachable(c["id"]):
						continue
					var cwk: String = consumer_wire_key.get(c["id"], "")
					if cwk.is_empty() or not comp_keys.has(cwk):
						continue
					if c.get("powered", false):
						local_draw += float(c.get("watts", 0.0))
					elif c.get("shed", false) and c.get("active", false):
						local_draw += _shed_residual_watts(c)
				discharge_groups[group_id] = {
					"batteries": [],
					"load_w":    local_draw,
					"visited":   comp_keys,   ## reuse component key set
				}
			(discharge_groups[group_id]["batteries"] as Array).append(bat)

		## Now drain each group independently.
		var any_still_alive_globally: bool = false

		for group: Dictionary in discharge_groups.values():
			var group_bats: Array = group["batteries"]
			var load_watts: float = float(group["load_w"])

			## Count live batteries in this group.
			var active_count: int = 0
			for bat: Dictionary in group_bats:
				if float(bat.get("charge_wh", 0.0)) > 0.0:
					active_count += 1

			if active_count == 0:
				## All batteries in this segment are dead → true offline for it.
				## _go_offline_true() handles the global signal if all are dead.
				continue

			var share_w: float = load_watts / float(active_count)
			var overload_factor: float = 1.0
			if share_w > BATTERY_OUTPUT_CAP_WATTS:
				overload_factor = share_w / BATTERY_OUTPUT_CAP_WATTS

			var drain_wh: float = (share_w * overload_factor * delta) / 3600.0

			for bat: Dictionary in group_bats:
				var cur: float = float(bat.get("charge_wh", 0.0))
				if cur <= 0.0:
					## Already dead — ensure flags cleared and drained signal fired.
					if bat.get("discharging", false):
						bat["discharging"] = false
						battery_state_changed.emit(bat["id"], false)
						_notify_battery_mode(bat["id"])
						_notify_battery_node(bat["id"])
					continue

				var new_charge: float = maxf(0.0, cur - drain_wh)
				bat["charge_wh"] = new_charge

				if new_charge > 0.0:
					any_still_alive_globally = true
					bat["discharging"] = true
				else:
					## Battery just drained to zero.
					bat["discharging"] = false
					bat["charging"]    = false
					battery_state_changed.emit(bat["id"], false)
					battery_drained.emit(bat["id"])   ## NEW: drained signal
					_notify_battery_mode(bat["id"])

				_notify_battery_node(bat["id"])

				var cap: float = float(bat.get("capacity_wh", 1.0))
				if new_charge / cap < BATTERY_LOW_THRESHOLD and new_charge > 0.0:
					battery_low.emit(bat["id"], new_charge / cap * 100.0)

		## Check if ALL discharging batteries are now dead.
		## IMPORTANT: do NOT call _go_offline_true() here — that cuts ALL consumers
		## globally including zones with their own healthy generators.  Instead,
		## trigger a network re-solve so _evaluate_per_component() can handle each
		## zone independently: a zone whose battery just died will be evaluated
		## freshly and either go OFFLINE (no generator, no battery) or shed lights
		## if a generator is running.  Only _evaluate_per_component → _go_offline()
		## should make the grid-wide OFFLINE call.
		var any_still_discharging: bool = false
		for bat: Dictionary in _batteries.values():
			if bat.get("discharging", false) and float(bat.get("charge_wh", 0.0)) > 0.0:
				any_still_discharging = true
				break
		if not any_still_discharging and not any_still_alive_globally:
			## All batteries dead — flag a resolve for _process() to run once
			## at end of frame instead of calling _solve_network() here every frame.
			_needs_resolve = true
		return   ## Skip charge path when discharging.

	## ── CHARGE path — only when generators have surplus ───────────────────────
	## TOPOLOGY RULE: a battery only charges from generators on its own sub-grid.

	for bat: Dictionary in _batteries.values():
		## Skip disabled batteries — they neither charge nor discharge.
		if not bat.get("enabled", true):
			continue
		## Skip batteries that are actively discharging to cover a deficit
		## elsewhere. The discharge path already returned above for the case
		## where ANY battery is discharging, but this guard handles the
		## edge case where a battery is flagged discharging but the
		## any_discharging check was evaluated before it was set this frame.
		if bat.get("discharging", false):
			continue
		## Skip truly dead batteries (fully drained, emitted battery_drained) to
		## avoid calling get_zone_node_set_for_key_cached() every frame and tanking
		## FPS.  Do NOT skip charge=0 batteries that haven't been drained yet —
		## those are freshly placed batteries starting at 0% that need to charge.
		if float(bat.get("charge_wh", 0.0)) <= 0.0 and bat.get("_drained_emitted", false):
			continue
		var cap: float = float(bat.get("capacity_wh", 0.0))
		var cur: float = float(bat.get("charge_wh",   0.0))

		## Find this battery's wire node and BFS to get local generator capacity.
		var bkey: String = _battery_wire_key(bat["id"])
		if bkey.is_empty():
			continue   ## Unwired battery — cannot charge or discharge.
		## Extra guard: if the battery wire node has NO adjacency edges (isolated
		## snap node with no wire segment attached), it cannot receive power.
		## This prevents spurious charging ticks after a wire is deconstructed
		## before _solve_network() has had a chance to prune the adjacency.
		if not _adjacency.has(bkey) or (_adjacency[bkey] as Array).is_empty():
			## Clear any stale charging flag if we find the battery is now isolated.
			if bat.get("charging", false):
				bat["charging"] = false
				_notify_battery_mode(bat["id"])
				_notify_battery_node(bat["id"])
			continue

		## CROSS-ZONE-AWARE capacity: flood the GENERATOR-sharing component from
		## this battery's wire node via _adjacency_gen (crosses untripped
		## pass_generator=true breakers, blocked by tripped/pass_generator=false
		## breakers) — NOT the single breaker-partitioned zone.  Previously this
		## used get_zone_node_set_for_key_cached() which scoped strictly to the
		## battery's own zone and never saw a generator sitting one breaker hop
		## away even with pass_generator=true, so a battery on a load-only zone
		## sharing a neighbor's generator never charged.  Mirrors the same
		## _adjacency_gen traversal _run_bfs() and PASS 2 sharing already use.
		var bat_gen_component: Dictionary = _flood_gen_component_keys({bkey: true})

		## If battery wire node isn't reachable to anything (isolated), skip.
		if bat_gen_component.is_empty():
			if bat.get("charging", false):
				bat["charging"] = false
				_notify_battery_mode(bat["id"])
				_notify_battery_node(bat["id"])
			continue

		## Capacity = running generators anywhere in the shared gen-component
		## (own zone OR a neighbor zone reachable via pass_generator=true breakers).
		var local_capacity: float = 0.0
		for wn: Dictionary in _wire_nodes.values():
			if wn.get("role", "") == "generator" and bat_gen_component.has(wn.get("key", "")):
				var gid: String = wn.get("device_id", "")
				if not gid.is_empty() and _generators.has(gid):
					var gen: Dictionary = _generators[gid]
					if gen.get("running", false):
						local_capacity += float(gen.get("watts", 0.0))

		## Draw = powered consumers anywhere in that same shared gen-component,
		## so a neighbor zone's own load is correctly subtracted before any
		## surplus is offered to this battery (own-load-first, same rule the
		## rest of the cross-zone sharing system already follows).
		## OPTIMISATION: avoid O(consumers × wire_nodes) scan every frame per battery.
		## Build consumer_id → wire_key map once and reuse (lazy-init per _tick_batteries call).
		if _charge_consumer_wire_key_cache.is_empty() and not _consumers.is_empty():
			for _cwn: Dictionary in _wire_nodes.values():
				if _cwn["role"] == "consumer" and not (_cwn["device_id"] as String).is_empty():
					var _did: String = _cwn["device_id"]
					if not _charge_consumer_wire_key_cache.has(_did):
						_charge_consumer_wire_key_cache[_did] = _cwn["key"]
		var local_draw: float = 0.0
		for c: Dictionary in _consumers.values():
			var cwk: String = _charge_consumer_wire_key_cache.get(c["id"], "")
			if cwk.is_empty() or not bat_gen_component.has(cwk):
				continue
			if c.get("powered", false):
				local_draw += float(c.get("watts", 0.0))
			elif c.get("shed", false) and c.get("active", false):
				local_draw += _shed_residual_watts(c)

		var local_surplus: float = maxf(0.0, local_capacity - local_draw)

		if local_surplus > 0.0 and cur < cap:
			## IMPORTANT: do NOT charge a discharging battery. The discharging
			## flag means _evaluate_per_component determined this battery is
			## covering a deficit. Only charge when surplus exists AND no deficit
			## is being covered — i.e., discharging flag must be clear.
			## (The `continue` above should already skip discharging bats, but
			## this is a belt-and-suspenders guard for frame-ordering edge cases.)
			if bat.get("discharging", false):
				continue
			var charge_wh: float = BATTERY_CHARGE_RATE * local_surplus * delta
			bat["charge_wh"] = minf(cap, cur + charge_wh)
			if not bat.get("charging", false):
				bat["charging"] = true
				_notify_battery_mode(bat["id"])
			## Reset the drained flag so battery_drained can fire again
			## if this battery is run down again in a future cycle.
			bat["_drained_emitted"] = false
			_notify_battery_node(bat["id"])
		else:
			var was_charging: bool = bat.get("charging", false)
			if was_charging:
				bat["charging"] = false
				_notify_battery_mode(bat["id"])
				_notify_battery_node(bat["id"])


## True blackout — called only when BOTH generators AND batteries are dead.
func _go_offline_true() -> void:
	if grid_state == GridState.OFFLINE:
		return   ## Already offline — no double-emit.
	## Clear all discharging / charging flags.
	## Also emit battery_drained for any battery that is at 0 and hasn't
	## already signalled it (e.g. if they all died simultaneously this frame).
	for bat: Dictionary in _batteries.values():
		var was_active: bool = bat.get("discharging", false) or bat.get("charging", false)
		bat["discharging"] = false
		bat["charging"]    = false
		if was_active:
			battery_state_changed.emit(bat["id"], false)
			_notify_battery_mode(bat["id"])
		## Emit drained signal if charge is at zero and not already flagged.
		if float(bat.get("charge_wh", 0.0)) <= 0.0 and not bat.get("_drained_emitted", false):
			bat["_drained_emitted"] = true
			battery_drained.emit(bat["id"])
		_notify_battery_node(bat["id"])
	## Trip all running generators — battery is dead, grid is fully down.
	## Generators require a manual restart (same behaviour as _trip_main_grid).
	for gen: Dictionary in _generators.values():
		if not gen.get("running", false):
			continue
		gen["running"]      = false
		gen["auto_started"] = false
		var gn: Node = _safe_dict_node(gen)
		if gn != null and is_instance_valid(gn):
			if gn.has_method("set_running"):
				gn.set_running(false)
			if gn.has_method("on_grid_tripped"):
				gn.on_grid_tripped()
		generator_stopped.emit(gen["id"], "zone_offline")
	_recalculate_capacity()
	_flickering = false
	var old: GridState = grid_state
	grid_state = GridState.OFFLINE
	grid_state_changed.emit(grid_state, old)
	grid_offline.emit()
	_cut_all_consumers()



# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — CONSUMER POWER APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════

func _cut_all_consumers() -> void:
	for c: Dictionary in _consumers.values():
		## Clear shed flag first — if a light is in shed (orange) state,
		## set_powered(false) would be ignored by the node because _is_shed=true.
		## We must unshed it so the true blackout turns it fully dark.
		if c.get("shed", false):
			c["shed"] = false
			var sn: Node = _safe_dict_node(c)
			if sn != null and is_instance_valid(sn) and sn.has_method("set_shed"):
				sn.set_shed(false)
		c["powered"] = false
		_apply_power_to_consumer(c, false)
	## Zero draw so the HUD and debug panel reflect true blackout immediately.
	active_draw_watts = 0.0
	draw_changed.emit(active_draw_watts, total_capacity_watts, battery_charge_ratio())


## Trip (stop + on_grid_tripped) every generator whose wire node is inside
## the given zone key set.  Called when a zone collapses to OFFLINE so the
## generator requires a manual restart — mirrors what _trip_main_grid() does
## for the full grid.  Generators stay running during OVERLOADED; they only
## trip when the zone actually goes dead (no battery coverage remaining).
func _trip_generators_in_zone(zone_keys: Dictionary) -> void:
	for gen: Dictionary in _generators.values():
		if not gen.get("running", false):
			continue
		## Find this generator's wire node and check if it's inside the zone.
		for wn: Dictionary in _wire_nodes.values():
			if wn.get("role", "") == "generator" and wn.get("device_id", "") == gen["id"]:
				if zone_keys.has(wn.get("key", "")):
					gen["running"]      = false
					gen["auto_started"] = false
					var n: Node = _safe_dict_node(gen)
					if n != null and is_instance_valid(n):
						if n.has_method("set_running"):
							n.set_running(false)
						if n.has_method("on_grid_tripped"):
							n.on_grid_tripped()
					generator_stopped.emit(gen["id"], "zone_offline")
					_recalculate_capacity()
				break


## Cut power to consumers in a specific zone without touching other zones.
## Used by per-zone overload / no-battery offline — does NOT call _go_offline().
## zone_keys: Dictionary of snap_key → true (the zone's node set).
func _cut_consumers_in_zone(zone_keys: Dictionary) -> void:
	for c: Dictionary in _consumers.values():
		## Find this consumer's wire node and check if it's in the zone.
		var in_zone: bool = false
		for wn: Dictionary in _wire_nodes.values():
			if wn.get("role", "") == "consumer" and wn.get("device_id", "") == c["id"]:
				if zone_keys.has(wn.get("key", "")):
					in_zone = true
				break
		if not in_zone:
			continue
		## Clear shed flag so set_powered(false) takes full effect.
		## Capture was_shed BEFORE clearing — the condition below needs it.
		var was_shed: bool = c.get("shed", false)
		if was_shed:
			c["shed"] = false
			var sn: Node = _safe_dict_node(c)
			if sn != null and is_instance_valid(sn) and sn.has_method("set_shed"):
				sn.set_shed(false)
		## Use was_shed (pre-clear value) — after clearing, c["shed"] is always false.
		if c.get("powered", false) or was_shed:
			c["powered"] = false
			_apply_power_to_consumer(c, false)
	## Trip any generators inside this zone — they ran during overloaded but
	## must stop now that the zone is fully dead (no battery coverage left).
	_trip_generators_in_zone(zone_keys)


func _apply_power_to_consumer(c: Dictionary, powered: bool) -> void:
	var n: Node = _safe_dict_node(c)
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_powered"):
		n.set_powered(powered)


## Called when a consumer is shed (lights only). Tells the node to dim rather
## than go fully dark. Uses set_shed() if available, otherwise set_powered(false).
func _apply_shed_to_consumer(c: Dictionary) -> void:
	var n: Node = _safe_dict_node(c)
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_shed"):
		n.set_shed(true)
	elif n.has_method("set_powered"):
		n.set_powered(false)


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — NODE NOTIFICATIONS
# ═══════════════════════════════════════════════════════════════════════════════

func _notify_battery_node(bat_id: String) -> void:
	if not _batteries.has(bat_id):
		return
	var bat: Dictionary = _batteries[bat_id]
	var n: Node = _safe_dict_node(bat)
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_charge_display"):
		n.set_charge_display(float(bat.get("charge_wh", 0.0)), float(bat.get("capacity_wh", 1.0)))


## Notify battery node of its current charge/discharge/idle mode.
## Called whenever the discharging or charging flag changes.
func _notify_battery_mode(bat_id: String) -> void:
	if not _batteries.has(bat_id):
		return
	var bat: Dictionary = _batteries[bat_id]
	var n: Node = _safe_dict_node(bat)
	if n == null or not is_instance_valid(n):
		return
	var discharging: bool = bat.get("discharging", false)
	var charging:    bool = bat.get("charging",    false)
	if n.has_method("set_battery_mode"):
		n.set_battery_mode(charging, discharging)


func _notify_breaker_node(breaker_id: String, tripped: bool) -> void:
	if not _breakers.has(breaker_id):
		return
	var n: Node = _safe_dict_node(_breakers[breaker_id])
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_tripped"):
		n.set_tripped(tripped)


## _snap_key() / _snapped_pos() moved to PowerGraph.gd (Stage 5 extraction) —
## no remaining callers in this file.
