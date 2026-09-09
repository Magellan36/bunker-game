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
		player.velocity = Vector3.ZERO
		player.set_physics_process(false)
		var model: Node = player.get_node_or_null("PlayerModel")
		if model != null:
			## Aug 2026 fix (3rd pass) — FIXED approach point (~half a chair
			## width in front of the seat) instead of the player's actual
			## position when E was pressed. The clip is authored assuming a
			## fixed travel distance/timing, so a variable start point (near
			## vs. far from the chair depending on approach angle) made the
			## slide look wrong. -t.basis.z is the chair's own "open front"
			## direction (the model faces +PI from this — toward the
			## backrest — while seated; see AdventurerModelController.gd).
			##
			## Aug 2026 fix (6th pass) — approach_pos.y was being computed
			## from t.origin.y (= Chair.SEAT_Y, the ELEVATED seat surface
			## height, ~0.56), not the player's actual floor-level height.
			## Since a CharacterBody3D's own global_position sits at the
			## CENTER of its capsule collider (not the feet), the player's
			## real standing Y is closer to ~1.0 for this project's capsule
			## — meaning the sit-down height-lerp (see
			## AdventurerModelController._lerp_sit_position(), "Seat-height
			## correction" in docs/systems/player-model/README.md) started
			## FROM the wrong (much lower) value the instant sitting_down
			## began, snapping the character down before the clip's own
			## motion had done anything — looked exactly like sinking into
			## the floor. approach_pos.y must come from the player's OWN
			## current height, not the chair's seat transform at all.
			const APPROACH_OFFSET: float = 0.4   ## ~half a chair width
			var approach_pos: Vector3 = t.origin + t.basis.z * APPROACH_OFFSET
			approach_pos.y = player.global_position.y
			model.set("_chair_approach_pos", approach_pos)
			model.set("_chair_seat_pos", Vector3(t.origin.x, approach_pos.y, t.origin.z))
		player.seated_chair = the_chair   ## NEW
	)
	## Aug 2026 fix — the player used to snap free (position + physics)
	## the instant E was pressed, well before the sit_to_stand animation
	## (2.25s) finished playing — clearing seated_chair immediately still
	## correctly triggers AdventurerModelController's stand-up animation
	## (it only checks whether seated_chair is null), but the player's
	## actual position/physics now stay anchored at the chair until that
	## model emits stand_animation_finished, so the character doesn't
	## visibly teleport away mid-animation. Connects to PlayerModel (not
	## the Shadow instance, which is otherwise identical) once per chair,
	## same guard pattern (_seat_wired) as the rest of this function.
	chair.stand_requested.connect(func() -> void:
		if the_chair.has_method("set_seated"):
			the_chair.set_seated(false)
		player.seated_chair = null   ## NEW — still cleared immediately, starts the animation
		var model: Node = player.get_node_or_null("PlayerModel")
		if model != null and model.has_signal("stand_animation_finished"):
			model.stand_animation_finished.connect(func() -> void:
				## Aug 2026 — snap to the EXACT position the standing animation
				## leaves the player at (the end of the seat->approach ease),
				## not the fixed chair-front point — no teleport away from where
				## the animation ended.
				if model.has_method("get_stand_end_position"):
					player.global_position = model.get_stand_end_position()
				else:
					player.global_position = the_chair.get_stand_position()
				## Aug 2026 — face the direction the standing animation ENDED
				## facing instead of the pre-sit facing, so the player continues
				## from the pose the animation left them in (no snap back to the
				## old direction).
				if model.has_method("get_visual_yaw"):
					player.rotation.y = model.get_visual_yaw()
				player.set_physics_process(true)
			, CONNECT_ONE_SHOT)
		else:
			## Fallback if the model node/signal isn't found for some reason
			## — old immediate behavior, better than getting stuck seated forever.
			player.global_position = the_chair.get_stand_position()
			if the_chair.has_meta("_seated_facing_y"):
				player.rotation.y = the_chair.get_meta("_seated_facing_y")
			player.set_physics_process(true)
	)

func _connect_inventory() -> void:
	var inv_hud: Node = hud.get_node("HUDRoot/InventoryHUD")

	# Give InteractionSystem access to InventoryManager so it can store items
	interaction_system.inventory = inventory_manager

	# Give InteractionSystem a direct ref to InventoryHUD for slot highlights
	interaction_system.inventory_hud = inv_hud

	# Give InventoryHUD its data source
	inv_hud.set("inventory", inventory_manager)
	if inv_hud.has_method("refresh_previews"):
		inv_hud.call_deferred("refresh_previews")
	if inv_hud.has_method("set_selected"):
		inv_hud.call_deferred("set_selected", interaction_system.selected_slot)

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

	## Prebuild construct/shop previews before LoadingScreen hands the scene to
	## the player. The pool is still staggered across frames, but it now runs
	## behind the loading presentation instead of causing seconds of post-load
	## stutter. The persistent viewports are reused for the entire session.
	if _build_hud != null and gm != null:
		_build_hud.gridmap = gm
		await _build_hud._build_submenu_previews_staggered()

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
	await _spawn_initial_build_station()
	await _spawn_initial_research_station()

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

	## LoadingScreen waits for this before revealing the bunker. Emit last so
	## every synchronous setup step and the expensive preview pool are complete.
	startup_ready.emit()


## Patches the GridMap MeshLibrary's floor mesh (item 0) with the shared
## floor material (Concrete032, triplanar one-image-across-the-bunker).
## Safe to call after pregen has run. Mirrors BuildMaterials.build_floor_material()
## so the pregen floor and player-built floors always match.
func _apply_floor_texture(gm: GridMap) -> void:
	if gm == null:
		return
	var lib: MeshLibrary = gm.mesh_library
	if lib == null:
		return
	var floor_mesh: Mesh = lib.get_item_mesh(0)   ## TILE_FLOOR = 0
	if floor_mesh == null:
		return

	var mat: StandardMaterial3D = BuildMaterials.build_floor_material()
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
		## Aug 2026 — drop whatever's held on build-mode entry, same as an F
		## press. Applies uniformly to both entry paths (Build Station and
		## the F1 dev shortcut) since they share this one toggle function.
		if interaction_system.held_item != null:
			interaction_system._quick_drop()
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

## Public: raw key list of every currently-cleared cell ("cx,cz" strings).
## Consumed by BunkerNavMesh (walkable quads) and NPC wander targeting.
func get_cleared_cell_keys() -> Array:
	return _cleared_cells.keys()

## Public: world-space center of one random cleared cell — a guaranteed-
## walkable wander target (unlike a random point in the bounding box, which
## can land inside undug rock in an L-shaped dig).
func get_random_cleared_cell_center() -> Vector3:
	var keys: Array = _cleared_cells.keys()
	if keys.is_empty():
		return Vector3.ZERO
	var key: String = keys[randi() % keys.size()]
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return Vector3.ZERO
	return Vector3(float(parts[0]) + 0.5, 0.0, float(parts[1]) + 0.5)


## Public: live bounding box (world-space XZ) of every currently-cleared
## GridMap cell (the pregen room + anything the player has since dug out).
## Used by NPC.gd to pick wander targets. Returns a Rect2 where
## `position` = (min_x, min_z) and `size` = (width_x, depth_z). Each
## "cx,cz" key in _cleared_cells represents a 1×1 world-unit cell — this
## approximates its footprint as spanning from (cx, cz) to (cx+1, cz+1),
## which is precise enough for picking a wander point (not for anything
## requiring exact placement).
func get_cleared_cell_bounds_world() -> Rect2:
	if _cleared_cells.is_empty():
		return Rect2(0.0, 0.0, 0.0, 0.0)

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for key: String in _cleared_cells.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue
		var cx: float = float(parts[0])
		var cz: float = float(parts[1])
		min_x = minf(min_x, cx)
		max_x = maxf(max_x, cx + 1.0)
		min_z = minf(min_z, cz)
		max_z = maxf(max_z, cz + 1.0)

	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)

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


func _spawn_initial_build_station() -> void:
	var bc: BuildModeController = _build_controller as BuildModeController
	if bc == null:
		push_warning("MainWorld: _spawn_initial_build_station skipped — BuildModeController not ready.")
		return

	await get_tree().physics_frame
	await get_tree().physics_frame

	## Position/angle taken verbatim from the BuildSandbox reference scene
	## (scenes/world/BuildSandbox.tscn) — the sandbox floor is calibrated to
	## the real bunker floor top (y 0.45), so these translate 1:1.
	var center_pos: Vector3 = Vector3(-11.897, 0.45, 8.5)

	var body: Node3D = bc._spawn_placed_object(bc.TILE_BUILD_STATION, center_pos, 90.0)
	if body != null and body.has_method("set"):
		body.set("_main_world", self)
	if bc.has_method("set"):
		bc.set("build_station", body)
		bc.set("_main_world", self)

	bc._placed_objects.append({
		"node":          body,
		"tile_id":       bc.TILE_BUILD_STATION,
		"price":         0,
		"world_pos":     center_pos,
		"angle_deg":     90.0,
		"player_placed": true,
	})


func _spawn_initial_research_station() -> void:
	var bc: BuildModeController = _build_controller as BuildModeController
	if bc == null:
		push_warning("MainWorld: _spawn_initial_research_station skipped — BuildModeController not ready.")
		return

	await get_tree().physics_frame
	await get_tree().physics_frame

	## Flush against the north wall (confirmed with the person: north = the
	## wall nearer player spawn, the bunker's low-Z boundary, OFFSET_Z=4.5 —
	## matches BunkerPregen.gd's own "wall_top = north wall" convention used
	## for its pregen light placement). X is centered along the wall's run
	## (same cx_mid = OFFSET_X + depth*0.5 constant BunkerPregen.gd computes
	## for that same wall's light). Z sits at OFFSET_Z + this object's own
	## half-depth (0.48, from _tile_half_extents(TILE_RESEARCH_STATION)) —
	## same "wall coordinate + inset" idiom BunkerPregen.gd uses for its
	## wall-flush lights (LWHT), just with this object's own footprint as
	## the inset instead of a light's thin fixture inset. Y=0.45 — the real
	## bunker floor top (BuildSandbox-calibrated), per the reference.
	## Angle 0.0 unchanged — per
	## BuildModeController.DEFAULT_ORIENT_INDEX, local +Z (front) already
	## points world +Z (south/into the room) at angle 0, which is correct
	## with the object's back against this north wall.
	## X shifted +4 from the room's own center per direction (confirmed:
	## literal world X=4 would sit outside the bunker — interior X only
	## runs to 3.5, less once the station's own half-width is subtracted —
	## so this is +4 relative to cx_mid, landing at -0.5, comfortably
	## inside the bunker regardless of the Aug 2026 widened footprint).
	var half_extent: Vector2 = bc._tile_half_extents(bc.TILE_RESEARCH_STATION)
	var research_pos: Vector3 = Vector3(
		rock_surround.OFFSET_X + float(rock_surround.bunker_depth) * 0.5 + 4.0,
		0.45,
		rock_surround.OFFSET_Z + half_extent.y
	)

	var body: Node3D = bc._spawn_placed_object(bc.TILE_RESEARCH_STATION, research_pos, 0.0)
	if body != null and body.has_method("set"):
		body.set("_research_ui", _research_ui)
	if bc.has_method("set"):
		bc.set("research_station", body)

	bc._placed_objects.append({
		"node":          body,
		"tile_id":       bc.TILE_RESEARCH_STATION,
		"price":         0,
		"world_pos":     research_pos,
		"angle_deg":     0.0,
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

## Bunker Ceiling failsafe, layer 2 (Aug 2026, Brannon-requested) — see
## MainWorld._setup_bunker_ceiling()'s own comment for the primary fix (a
## real, solid invisible ceiling). This is the fallback: if an NPC ends up
## below the world anyway (ceiling failure, or falling through the floor
## some other way — same failure mode ABYSS_Y/ABYSS_RESCUE_Y above already
## exists to catch for loose items), it's teleported to the exact CENTER
## of the original starting bunker footprint — same OFFSET_X/OFFSET_Z +
## half-depth/half-width centering formula _setup_ambient_dust() and
## _spawn_initial_research_station() already use elsewhere in this file,
## so this always lands on real, guaranteed-walkable floor regardless of
## how much the player has since dug outward. Deliberately minimal —
## position + velocity only. Current activity is reset via
## brain.stop_current() (the same clean-abandon method NPC.gd's own
## stuck-recovery already uses) so it cleanly drops whatever it was doing
## and the brain re-decides fresh next tick. Needs/mood/relationships/
## held item are all left completely untouched — "no adverse effects,"
## per spec. Called every frame alongside _check_abyss_items(), same cheap
## group-scan + float-comparison cost.
func _check_abyss_npcs() -> void:
	if rock_surround == null:
		return
	var center_x: float = rock_surround.OFFSET_X + float(rock_surround.bunker_depth) * 0.5
	var center_z: float = rock_surround.OFFSET_Z + float(rock_surround.bunker_width) * 0.5
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not (npc is Node3D):
			continue
		if (npc as Node3D).global_position.y >= ABYSS_Y:
			continue
		npc.global_position = Vector3(center_x, ABYSS_RESCUE_Y, center_z)
		if "velocity" in npc:
			npc.velocity = Vector3.ZERO
		if "brain" in npc and npc.brain != null and npc.brain.has_method("stop_current"):
			npc.brain.stop_current()
		var npc_label: String = npc.npc_name if "npc_name" in npc else str(npc)
		print("[MainWorld] Rescued %s from below the world — teleported to bunker center" % npc_label)

func _connect_world_objects() -> void:
	# Wire prompt to interaction system
	interaction_system.prompt = interact_prompt

	## Aug 2026 — inject the shared prompt renderer into BuildModeController
	## so it can drive the exact same on-screen prompt UI during build mode
	## (visual consistency "same as other objects" — reuses the existing
	## set_prompts()/hide_prompt() node rather than a second prompt renderer).
	if _build_controller != null:
		_build_controller.set("interact_prompt", interact_prompt)

	# Inject player_stats into any world object that has a _player_stats property.
	# Scans both interactable and pickup groups to catch all cases.
	var all_world_nodes: Array = []
	all_world_nodes.append_array(get_tree().get_nodes_in_group("interactable"))
	all_world_nodes.append_array(get_tree().get_nodes_in_group("pickup"))
	for node in all_world_nodes:
		if "_player_stats" in node:
			node._player_stats = player_stats
