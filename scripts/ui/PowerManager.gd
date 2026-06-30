extends Node
## PowerManager.gd  —  v3.1
## Central electricity grid controller for the bunker.
##
## ═══════════════════════════════════════════════════════════════════════════════
## ARCHITECTURE  (read this before touching anything)
## ═══════════════════════════════════════════════════════════════════════════════
##
## The grid is a GRAPH.  No rooms required.  No string zones.  Just wires.
##
##   WireNodes  — snap-point positions in the world.  Every device (generator,
##                consumer, battery, breaker) AND every bare wire joint (elbow,
##                T-junction, etc.) owns exactly one WireNode at its world snap
##                position.
##
##   WireEdges  — a placed wire segment connecting exactly two WireNodes.
##                No per-edge capacity limit.  Wires never burn.
##
##   CircuitBreakers — placed on a WireNode like a device.  Tripping one opens
##                     the graph at that point — everything downstream loses
##                     power.  This is the ONLY way to isolate sections of the
##                     grid (replaces the old zone/room concept entirely).
##
## WIRE PLACEMENT  (freeform, RimWorld-style)
##   - The bunker has no required rooms.  Players drag wire anywhere they like.
##   - Wires are VISIBLE only in Build Mode (BuildModeController toggles
##     visibility on all WireSegment nodes via a "wire_segment" group or signal).
##   - Outside Build Mode all wire meshes are hidden — they're structural, not
##     decorative.
##   - To split the grid, players place a CircuitBreaker mid-wire.  That breaker
##     node becomes an openable cut-point in the graph.
##
## NETWORK SOLVE  (runs after every topology change — NOT every frame)
##   1. Build adjacency from all live (non-tripped-breaker) edges.
##   2. BFS outward from every running generator's WireNode.
##   3. Each reachable consumer WireNode → set_powered(true).
##      Each unreachable consumer WireNode → set_powered(false).
##   4. Compute per-edge load (sum of powered consumer draw downstream of edge).
##   5. Battery banks on the reachable graph charge from surplus / discharge
##      to cover deficit.
##
## PRIORITY / BROWNOUT / SHEDDING
##   During a watts deficit the solver:
##     1. Tries to spin up backup generators first.
##     2. If still over, sheds ONLY lights (wall_light, bed_lamp, emergency_light,
##        grow_light). Non-light consumers are never shed.
##     3. If still over after shedding all lights → flicker then go OFFLINE.
##   There is NO OVERLOADED grace timer state for non-light overloads — the
##   system immediately begins the flicker → offline sequence.
##
## ZONES — REMOVED ENTIRELY
##   String-based zones are gone.  "Zones" emerge naturally from circuit breaker
##   placement.  There is no zone param anywhere in this file.
##   Old APIs (trip_zone / reset_zone_breaker) are gone.  Use trip_breaker /
##   reset_breaker instead.
##
## ═══════════════════════════════════════════════════════════════════════════════
## SNAP KEY CONVENTION
## ═══════════════════════════════════════════════════════════════════════════════
##   _snap_key(pos: Vector3) → String  e.g. "8,0,12"
##   Uses SNAP_GRID (0.25 m) — must match BuildModeController.grid_size.
##   Devices call register_wire_node(global_position, ...) in _ready();
##   PowerManager derives and stores the snap key automatically.
##   Store the returned key — you need it to unregister in _exit_tree().
##
## ═══════════════════════════════════════════════════════════════════════════════
## WIRE VISIBILITY RULE
## ═══════════════════════════════════════════════════════════════════════════════
##   WireSegment scene nodes are responsible for their own visibility.
##   Recommended: join the "wire_segment" group in _ready() and toggle
##   visibility from BuildModeController when build mode opens/closes.
##
##   Example in WireSegment._ready():
##     add_to_group("wire_segment")
##     visible = false   # hidden by default
##
##   Example in BuildModeController:
##     # on entering build mode:
##     get_tree().call_group("wire_segment", "set_visible", true)
##     # on exiting build mode:
##     get_tree().call_group("wire_segment", "set_visible", false)
##
##   PowerManager does NOT control visibility — that's BuildModeController's job.
##
## ═══════════════════════════════════════════════════════════════════════════════
## INTEGRATION QUICK-REF
## ═══════════════════════════════════════════════════════════════════════════════
##
##   ── Every powered device (_ready / _exit_tree) ───────────────────────────────
##     var pm := get_tree().get_first_node_in_group("power_manager")
##     # _ready — register wire node FIRST, then consumer:
##     _pm_node_key = pm.register_wire_node(global_position, "consumer", str(get_instance_id()))
##     pm.register_consumer(str(get_instance_id()), WATTS, self, "wall_light", priority)
##     # _exit_tree — unregister wire node FIRST, then consumer:
##     pm.unregister_wire_node(_pm_node_key)
##     pm.unregister_consumer(str(get_instance_id()))
##
##   ── Wire segment (placed by BuildModeController) ─────────────────────────────
##     # node_a_id / node_b_id are snap keys returned by register_wire_node()
##     var edge_id := pm.register_wire_edge(node_a_id, node_b_id, wire_scene_node)
##     # on deconstruct / sell:
##     pm.unregister_wire_edge(edge_id)
##
##   ── Circuit breaker (BreakerBox._ready) ──────────────────────────────────────
##     _pm_node_key = pm.register_wire_node(global_position, "breaker", str(get_instance_id()))
##     _breaker_id  = pm.register_breaker(_pm_node_key, self)
##     # player interacts:
##     pm.trip_breaker(_breaker_id)    # cuts power past this point
##     pm.reset_breaker(_breaker_id)   # restores (only if grid not TRIPPED/OFFLINE)
##     # _exit_tree:
##     pm.unregister_breaker(_breaker_id)
##     pm.unregister_wire_node(_pm_node_key)
##
##   ── Generator (GeneratorObject._ready) ───────────────────────────────────────
##     pm.register_generator(str(get_instance_id()), watts, self, is_backup, fuel, health)
##     _pm_node_key = pm.register_wire_node(global_position, "generator", str(get_instance_id()))
##     # _exit_tree:
##     pm.unregister_wire_node(_pm_node_key)
##     pm.unregister_generator(str(get_instance_id()))
##
##   ── Battery (BatteryBank._ready) ─────────────────────────────────────────────
##     pm.register_battery(str(get_instance_id()), capacity_wh, self, initial_charge)
##     _pm_node_key = pm.register_wire_node(global_position, "battery", str(get_instance_id()))
##     # _exit_tree:
##     pm.unregister_wire_node(_pm_node_key)
##     pm.unregister_battery(str(get_instance_id()))
##
##   ── Required interface on powered device nodes ────────────────────────────────
##     func set_powered(on: bool) -> void        # consumer — called by solver
##     func set_running(on: bool) -> void        # generator — called by PowerManager
##     func set_charge_display(wh: float, cap: float) -> void  # battery
##     func set_tripped(on: bool) -> void        # circuit breaker
##
##   ── Consumer ID rule (never use node path) ───────────────────────────────────
##     Always use str(node.get_instance_id()) as the id.
##     Node paths change when scenes are rearranged; instance IDs don't.
##
## ═══════════════════════════════════════════════════════════════════════════════


# ─── Grid state enum ──────────────────────────────────────────────────────────
enum GridState {
	ONLINE,       ## all reachable consumers powered, draw ≤ capacity
	BROWNOUT,     ## deficit covered by shedding lights
	OVERLOADED,   ## brief intermediate before flicker→offline (non-light overload)
	TRIPPED,      ## main breaker blown — manual reset required
	OFFLINE,      ## no generators + no battery — true blackout
}

# ─── Constants ────────────────────────────────────────────────────────────────

## Snap grid in metres — must match BuildModeController.grid_size.
const SNAP_GRID: float = 0.25

## Seconds of grace between OVERLOADED and a full grid trip.
## Near-instant: flicker sequence is short, this just guards against edge cases.
const OVERLOAD_GRACE_SECS: float = 0.5

## Seconds before the main breaker auto-resets after a trip.
## -1 = manual only (requires player interaction at the breaker panel).
const MAIN_AUTO_RESET_SECS: float = -1.0

## Watt-hours charged per second per surplus watt.
## At 800w surplus: 800 * 0.000138 ≈ 0.11 Wh/sec → 100 Wh fills in ~900 real-sec = ~15 game-hours.
const BATTERY_CHARGE_RATE: float = 0.000138

## Watt draw a charging battery bank places on the grid.
## Treated as a real consumer load — shows as CHARGING in the debug panel.
const BATTERY_CHARGE_WATTS: float = 20.0

## Watt-hours discharged per second when covering a deficit.
## (legacy constant — discharge is now computed directly from watts×delta/3600)
const BATTERY_DISCHARGE_RATE: float = 0.5

## Battery charge fraction below which battery_low signal fires.
const BATTERY_LOW_THRESHOLD: float = 0.15

## Priority shed range — only for lights (see LIGHT_TYPES set).
const SHED_START_PRIORITY: int = 5
const SHED_END_PRIORITY:   int = 2
## Watts a shed (orange-dim) light still draws from the battery during brownout.
## Small enough not to matter for balance but shows up correctly on the HUD.
const SHED_WATTS: float = 5.0

## Light device types that are eligible for load-shedding.
## Non-light consumers are NEVER shed — an overload from non-lights
## triggers the flicker→offline sequence directly.
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

# ─── Watt ratings (single source of truth) ───────────────────────────────────
## BuildModeController and device _ready() scripts should pull from here.
const WATT_RATINGS: Dictionary = {
	## Lighting
	"wall_light":           40.0,
	"bed_lamp":             15.0,
	"emergency_light":       8.0,
	"grow_light":           80.0,
	## Security / Comms
	"security_camera":      10.0,
	"radio":                20.0,
	"comms_terminal":       60.0,
	## Appliances
	"small_fan":            35.0,
	"refrigerator":        150.0,
	"water_purifier":      200.0,
	"ventilation_unit":    300.0,
	"medical_station":     120.0,
	"defibrillator":       500.0,
	"workshop_tools":      500.0,
	"electric_stove":      180.0,
	"microwave":            90.0,
	"coffee_maker":         40.0,
	"washer":              200.0,
	## Infrastructure
	"water_pump":          180.0,
	"air_recycler":        220.0,
	"blast_door_motor":    150.0,
	"elevator_motor":      400.0,
	## Test / debug
	"heavy_appliance":     500.0,
}

## Default priority per type tag. 1 = life-support, 5 = luxury.
const DEFAULT_PRIORITY_BY_TYPE: Dictionary = {
	"air_recycler":         1,
	"defibrillator":        1,
	"emergency_light":      1,
	"medical_station":      2,
	"water_pump":           2,
	"blast_door_motor":     2,
	"security_camera":      2,
	"water_purifier":       3,
	"wall_light":           3,
	"ventilation_unit":     3,
	"refrigerator":         3,
	"radio":                4,
	"grow_light":           4,
	"small_fan":            4,
	"electric_stove":       4,
	"microwave":            5,
	"coffee_maker":         5,
	"workshop_tools":       5,
	"washer":               5,
	"heavy_appliance":      2,
}

## Generator upgrade tiers — indexed by shop/upgrade system.
const GENERATOR_TIERS: Array[Dictionary] = [
	{ "name": "Starter Generator",    "watts": 800.0,  "price": 0     },
	{ "name": "Mid-Range Generator",  "watts": 2000.0, "price": 3500  },
	{ "name": "Industrial Generator", "watts": 5000.0, "price": 12000 },
]


# ═══════════════════════════════════════════════════════════════════════════════
# RUNTIME STATE
# ═══════════════════════════════════════════════════════════════════════════════

var grid_state: GridState = GridState.ONLINE

## Timers
var _overload_timer:    float = 0.0
var _main_reset_timer:  float = 0.0

## Flicker sequence state.
var _flickering:         bool  = false   ## true while flicker→offline is playing
var _flicker_timer:      float = 0.0    ## total elapsed flicker time
var _flicker_pulse_t:    float = 0.0    ## time within current on/off pulse
var _flicker_pulse_on:   bool  = true   ## current pulse is "lights on"

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

## Set of snap keys that are reachable from a generator (result of last solve).
var _reachable: Dictionary = {}   ## snap_key → true


# ═══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════════

## Grid-level
signal grid_state_changed(new_state: GridState, old_state: GridState)
signal draw_changed(active_watts: float, capacity_watts: float, battery_pct: float)
signal grid_tripped
signal grid_restored
signal grid_offline
signal brownout_started
signal brownout_ended

## Consumer
signal consumer_registered(id: String, watts: float, priority: int)
signal consumer_unregistered(id: String)

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


# ═══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	pass   ## No default zone — graph starts empty.

func _process(delta: float) -> void:
	_tick_generators(delta)
	_tick_batteries(delta)

	## Flicker sequence overrides everything else.
	if _flickering:
		_tick_flicker(delta)
		return

	match grid_state:
		GridState.OVERLOADED:
			## OVERLOADED only reached when shedding wasn't possible.
			## Count down grace timer — then trip.
			_overload_timer += delta
			if _overload_timer >= OVERLOAD_GRACE_SECS:
				_trip_main_grid("overload")
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

## Register a wire node (snap point) for a device or bare wire joint.
##   pos       — world position; snapped to SNAP_GRID automatically
##   role      — "consumer" | "generator" | "battery" | "breaker" | "joint"
##   device_id — id matching the consumer/generator/battery registry (or "")
## Returns the snap key string — store it; you need it to unregister.
func register_wire_node(pos: Vector3, role: String, device_id: String = "") -> String:
	var key: String = _snap_key(pos)
	if _wire_nodes.has(key):
		push_warning("PowerManager: wire node '%s' already exists — updating role." % key)
	_wire_nodes[key] = {
		"key":       key,
		"pos":       _snapped_pos(pos),
		"role":      role,
		"device_id": device_id,
		"reachable": false,
	}
	wire_node_registered.emit(key)
	_solve_network()
	return key


## Remove a wire node and any edges that reference it.
## Call from device _exit_tree() before unregistering the consumer/generator.
func unregister_wire_node(node_key: String) -> void:
	if not _wire_nodes.has(node_key):
		return
	## Remove all edges touching this node.
	var to_remove: Array[String] = []
	for edge: Dictionary in _wire_edges.values():
		if edge["node_a"] == node_key or edge["node_b"] == node_key:
			to_remove.append(edge["id"])
	for eid: String in to_remove:
		_remove_wire_edge_internal(eid)
	## Remove any breaker sitting on this node.
	for bid: String in _breakers.keys():
		if _breakers[bid]["node_key"] == node_key:
			_breakers.erase(bid)
			break
	_wire_nodes.erase(node_key)
	wire_node_unregistered.emit(node_key)
	_solve_network()


## Place a wire segment between two existing wire nodes.
##   node_a_id  — snap key of endpoint A  (from register_wire_node)
##   node_b_id  — snap key of endpoint B
##   scene_node — the WireSegment Node3D in the scene (visual); may be null
## Returns edge_id — store it to unregister on deconstruct.
## NOTE: no capacity_w param — wires have no per-edge limit.
func register_wire_edge(
		node_a_id:  String,
		node_b_id:  String,
		scene_node: Node  = null) -> String:

	## Auto-create bare joint nodes if endpoints don't exist yet
	## (wire placed before a device is placed at that snap point).
	if not _wire_nodes.has(node_a_id):
		_wire_nodes[node_a_id] = {
			"key": node_a_id, "pos": Vector3.ZERO,
			"role": "joint", "device_id": "", "reachable": false
		}
	if not _wire_nodes.has(node_b_id):
		_wire_nodes[node_b_id] = {
			"key": node_b_id, "pos": Vector3.ZERO,
			"role": "joint", "device_id": "", "reachable": false
		}

	## Canonical edge id: sorted so A<B, prevents duplicate in both directions.
	var parts: Array[String] = [node_a_id, node_b_id]
	parts.sort()
	var edge_id: String = "e_%s__%s" % [parts[0], parts[1]]

	if _wire_edges.has(edge_id):
		push_warning("PowerManager: wire edge '%s' already registered." % edge_id)
		return edge_id

	_wire_edges[edge_id] = {
		"id":     edge_id,
		"node_a": node_a_id,
		"node_b": node_b_id,
		"load_w": 0.0,
		"node":   scene_node,
	}
	wire_edge_registered.emit(edge_id)
	_solve_network()
	return edge_id


## Remove a wire segment (deconstructed by player).
## Triggers a full network re-solve — downstream devices may lose power.
func unregister_wire_edge(edge_id: String) -> void:
	if not _wire_edges.has(edge_id):
		return
	_remove_wire_edge_internal(edge_id)
	_solve_network()


## Register a circuit breaker on an existing wire node.
## Returns breaker_id — store it to trip/reset/unregister later.
## Also splits any existing wire edge whose A→B segment passes through the
## breaker's snap point, so the breaker becomes a true cut-point in the graph.
func register_breaker(wire_node_key: String, scene_node: Node = null) -> String:
	if not _wire_nodes.has(wire_node_key):
		push_warning("PowerManager: breaker registered on unknown node '%s'" % wire_node_key)
		return ""
	var bid: String = "brk_%s" % wire_node_key
	_breakers[bid] = {
		"id":            bid,
		"node_key":      wire_node_key,
		"tripped":       false,
		"node":          scene_node,
		"pass_battery":  true,   ## allow battery current through (player-toggled)
		"pass_generator": true,  ## allow generator current through (player-toggled)
	}
	## Update the wire node's role so adjacency builder knows it's a breaker point.
	_wire_nodes[wire_node_key]["role"] = "breaker"
	## Split any wire edge that passes through this snap point so the breaker
	## is a genuine cut-point rather than floating beside the wire.
	_split_wire_edge_at(wire_node_key)
	return bid


## Check every existing wire edge to see if the given snap key lies on it
## (i.e. between its two endpoints, collinear within tolerance).
## If found: remove the old edge and add two new edges A→mid and mid→B,
## preserving the original scene node (wire visual) on the first segment.
## This is called whenever a breaker is placed so it intercepts wire current.
func _split_wire_edge_at(mid_key: String) -> void:
	if not _wire_nodes.has(mid_key):
		return
	var mid_pos: Vector3 = _wire_nodes[mid_key]["pos"]

	## Collect edges to split (don't modify dict while iterating).
	var to_split: Array[String] = []
	for edge: Dictionary in _wire_edges.values():
		var a_key: String = edge["node_a"]
		var b_key: String = edge["node_b"]
		## Skip if mid IS one of the endpoints.
		if a_key == mid_key or b_key == mid_key:
			continue
		if not _wire_nodes.has(a_key) or not _wire_nodes.has(b_key):
			continue
		var a_pos: Vector3 = _wire_nodes[a_key]["pos"]
		var b_pos: Vector3 = _wire_nodes[b_key]["pos"]
		if _point_on_segment(mid_pos, a_pos, b_pos):
			to_split.append(edge["id"])

	for eid: String in to_split:
		if not _wire_edges.has(eid):
			continue
		var edge: Dictionary = _wire_edges[eid]
		var a_key: String = edge["node_a"]
		var b_key: String = edge["node_b"]
		var orig_node: Node  = edge.get("node")   ## keep scene node on first segment
		_remove_wire_edge_internal(eid)
		## Register the two replacement edges without triggering a full solve each
		## time — we'll let the caller's _solve_network() do it once at the end.
		var parts_ab: Array[String] = [a_key, mid_key]
		parts_ab.sort()
		var new_id_ab: String = "e_%s__%s" % [parts_ab[0], parts_ab[1]]
		if not _wire_edges.has(new_id_ab):
			_wire_edges[new_id_ab] = {
				"id": new_id_ab, "node_a": a_key, "node_b": mid_key,
				"load_w": 0.0, "node": orig_node,
			}
			wire_edge_registered.emit(new_id_ab)
		var parts_mb: Array[String] = [mid_key, b_key]
		parts_mb.sort()
		var new_id_mb: String = "e_%s__%s" % [parts_mb[0], parts_mb[1]]
		if not _wire_edges.has(new_id_mb):
			_wire_edges[new_id_mb] = {
				"id": new_id_mb, "node_a": mid_key, "node_b": b_key,
				"load_w": 0.0, "node": null,   ## second segment has no separate visual
			}
			wire_edge_registered.emit(new_id_mb)


## Returns true if point P lies on segment A→B (collinear + between endpoints).
## Uses a tolerance of half the snap grid to handle floating-point jitter.
func _point_on_segment(p: Vector3, a: Vector3, b: Vector3) -> bool:
	var ab: Vector3 = b - a
	var ap: Vector3 = p - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return false   ## Degenerate edge (zero length).
	## Check collinearity: cross product should be near-zero.
	var cross: Vector3 = ab.cross(ap)
	if cross.length_squared() > (SNAP_GRID * SNAP_GRID * 0.25):
		return false
	## Check that P is between A and B (0 ≤ t ≤ 1).
	var t: float = ab.dot(ap) / len_sq
	return t > 0.001 and t < 0.999


## Remove a breaker (sold / deconstructed).
func unregister_breaker(breaker_id: String) -> void:
	if not _breakers.has(breaker_id):
		return
	var key: String = _breakers[breaker_id]["node_key"]
	_breakers.erase(breaker_id)
	## Restore node role to "joint" (or whatever was there before).
	if _wire_nodes.has(key):
		_wire_nodes[key]["role"] = "joint"
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


## Reset a circuit breaker (player interacts at the physical breaker).
func reset_breaker(breaker_id: String) -> void:
	if not _breakers.has(breaker_id):
		return
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		push_warning("PowerManager: reset_breaker called while grid is %s — reset main first."
			% GridState.keys()[grid_state])
		return
	_breakers[breaker_id]["tripped"] = false
	_notify_breaker_node(breaker_id, false)
	breaker_reset.emit(breaker_id)
	_solve_network()


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
##   brownout        bool    — true if zone has at least one shed consumer
##   state_str       String  — "ONLINE" / "BROWNOUT" / "OFFLINE" (zone-local)
## Returns [] if no wire zones exist (no breakers placed, or wire graph empty).
func get_zone_snapshot() -> Array[Dictionary]:
	var wire_zones: Array[Dictionary] = get_wire_zones()
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
		var zone_brownout: bool = false

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
				zone_brownout = true
				break

		var zone_state_str: String
		if not zone_powered:
			zone_state_str = "OFFLINE"
		elif zone_brownout:
			zone_state_str = "BROWNOUT"
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
				zone_draw_w += SHED_WATTS
		for gen_id: String in generator_ids:
			if _generators.has(gen_id) and _generators[gen_id].get("running", false):
				zone_cap_w += float(_generators[gen_id].get("watts", 0.0))

		out.append({
			"zone_index":    z_idx,
			"color_index":   z_idx % ZONE_COLORS.size(),
			"consumer_ids":  consumer_ids,
			"generator_ids": generator_ids,
			"battery_ids":   battery_ids,
			"breaker_keys":  brk_keys,
			"powered":       zone_powered,
			"brownout":      zone_brownout,
			"state_str":     zone_state_str,
			"draw_w":        zone_draw_w,
			"capacity_w":    zone_cap_w,
		})

	return out

## Zone colour palette (matches BuildModeController._recolor_wire_zones()).
## Index 0–5: green / red / yellow / cyan / magenta / orange  (alpha 0.60)
const ZONE_COLORS: Array[Color] = [
	Color(0.10, 0.95, 0.35, 0.60),
	Color(0.95, 0.18, 0.10, 0.60),
	Color(0.95, 0.90, 0.10, 0.60),
	Color(0.10, 0.90, 0.95, 0.60),
	Color(0.90, 0.10, 0.95, 0.60),
	Color(0.95, 0.55, 0.10, 0.60),
]


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — CONSUMERS
# ═══════════════════════════════════════════════════════════════════════════════

## Register a power-consuming device.
##   id       — str(node.get_instance_id())
##   watts    — rated draw; use WATT_RATINGS["wall_light"]
##   node     — scene node; must implement set_powered(bool)
##   type     — category tag for default priority lookup
##   priority — 1–5; pass 0 to auto-assign from type
##   active   — true if device starts switched on
func register_consumer(
		id:       String,
		watts:    float,
		node:     Node,
		type:     String = "unknown",
		priority: int    = 0,
		active:   bool   = true) -> void:

	if priority == 0:
		priority = DEFAULT_PRIORITY_BY_TYPE.get(type, 3)

	if _consumers.has(id):
		push_warning("PowerManager: duplicate consumer '%s' — updating." % id)

	_consumers[id] = {
		"id":       id,
		"watts":    watts,
		"active":   active,
		"node":     node,
		"type":     type,
		"priority": priority,
		"shed":     false,
		"powered":  false,
	}
	consumer_registered.emit(id, watts, priority)


## Remove a consumer.
## NOTE: call unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.  If you forget, this function
## will clean up the wire node as a fallback (safe but slightly less clean).
func unregister_consumer(id: String) -> void:
	if not _consumers.has(id):
		return
	## Safety fallback: if the wire node for this consumer still exists (device
	## was deconstructed without calling unregister_wire_node first), remove it
	## now — which also destroys all connected wire segments automatically.
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "consumer" and wn["device_id"] == id:
			unregister_wire_node(wn["key"])
			break
	_consumers.erase(id)
	consumer_unregistered.emit(id)


## Toggle device switch state (player flips a light switch, etc.)
func set_consumer_active(id: String, active: bool) -> void:
	if not _consumers.has(id):
		return
	_consumers[id]["active"] = active
	_solve_network()


## Returns watt draw of a registered consumer, or 0.0 if unknown.
## Used by WireDrawMode to display device cost in hover labels.
func get_consumer_watts(id: String) -> float:
	return float(_consumers.get(id, {}).get("watts", 0.0))


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
		health:    float = 100.0) -> void:

	var running: bool = (not is_backup) and fuel > 0.0 and health > 0.0
	_generators[gen_id] = {
		"id":           gen_id,
		"watts":        watts,
		"node":         node,
		"running":      running,
		"backup":       is_backup,
		"fuel":         clampf(fuel,   0.0, 100.0),
		"health":       clampf(health, 0.0, 100.0),
		"auto_started": false,
	}
	_recalculate_capacity()
	generator_registered.emit(gen_id, watts, is_backup)
	if running:
		generator_started.emit(gen_id)


## Unregister a generator (sold / destroyed).
## NOTE: call unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.
func unregister_generator(gen_id: String) -> void:
	if not _generators.has(gen_id):
		return
	## Safety fallback: clean up wire node and its edges if still registered.
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "generator" and wn["device_id"] == gen_id:
			unregister_wire_node(wn["key"])
			break
	_generators.erase(gen_id)
	_recalculate_capacity()
	generator_unregistered.emit(gen_id)
	_solve_network()


## Returns current fuel level [0.0–100.0] for the given generator.
## Returns -1.0 if the gen_id is not registered.
func get_generator_fuel(gen_id: String) -> float:
	if not _generators.has(gen_id):
		return -1.0
	return _generators[gen_id]["fuel"]

## Returns whether the generator is currently running.
## Returns false if the id is unknown.
func get_generator_running(gen_id: String) -> bool:
	if not _generators.has(gen_id):
		return false
	return _generators[gen_id].get("running", false)

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
			print("PowerManager: generator started — grid restored from OFFLINE.")
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
	if not _generators.has(gen_id):
		return false
	return _generators[gen_id].get("backup", false)

## Returns current health [0.0–100.0] for the given generator.
func get_generator_health(gen_id: String) -> float:
	if not _generators.has(gen_id):
		return -1.0
	return _generators[gen_id].get("health", 100.0)

## Returns rated output watts for the given generator.
func get_generator_watts(gen_id: String) -> float:
	if not _generators.has(gen_id):
		return 0.0
	return _generators[gen_id].get("watts", 0.0)

## Status snapshot for HUD or save system.
func get_generators_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gen: Dictionary in _generators.values():
		out.append({
			"id": gen["id"], "watts": gen["watts"], "running": gen["running"],
			"backup": gen["backup"], "fuel": gen["fuel"], "health": gen["health"],
		})
	return out


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

	var charge: float = initial_charge if initial_charge >= 0.0 else capacity_wh
	charge = clampf(charge, 0.0, capacity_wh)
	_batteries[bat_id] = {
		"id":          bat_id,
		"capacity_wh": capacity_wh,
		"charge_wh":   charge,
		"node":        node,
		"discharging": false,
		"enabled":     true,   ## player can disable via BatteryBank info panel
	}
	battery_registered.emit(bat_id, capacity_wh)
	_notify_battery_node(bat_id)


## Unregister battery (sold / destroyed).
## NOTE: call unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.
func unregister_battery(bat_id: String) -> void:
	if not _batteries.has(bat_id):
		return
	## Safety fallback: clean up wire node and its edges if still registered.
	for wn: Dictionary in _wire_nodes.values():
		if wn["role"] == "battery" and wn["device_id"] == bat_id:
			unregister_wire_node(wn["key"])
			break
	_batteries.erase(bat_id)
	battery_unregistered.emit(bat_id)


## Force-set charge level (load from save).
func set_battery_charge(bat_id: String, charge_wh: float) -> void:
	if not _batteries.has(bat_id):
		return
	_batteries[bat_id]["charge_wh"] = clampf(
		charge_wh, 0.0, float(_batteries[bat_id]["capacity_wh"]))
	## Reset drained flag so battery_drained can fire again if needed.
	if float(_batteries[bat_id]["charge_wh"]) > 0.0:
		_batteries[bat_id]["_drained_emitted"] = false
	_notify_battery_node(bat_id)


## Total stored energy (watt-hours) across all batteries.
func total_battery_wh() -> float:
	var t: float = 0.0
	for bat: Dictionary in _batteries.values():
		t += float(bat.get("charge_wh", 0.0))
	return t


## Aggregate charge as 0.0–1.0 fraction.
func battery_charge_ratio() -> float:
	var cap: float = 0.0
	var chg: float = 0.0
	for bat: Dictionary in _batteries.values():
		cap += float(bat.get("capacity_wh", 0.0))
		chg += float(bat.get("charge_wh",   0.0))
	return chg / cap if cap > 0.0 else 0.0


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — STATUS / QUERIES
# ═══════════════════════════════════════════════════════════════════════════════

## 0.0–1.0+ load ratio (>1.0 = currently overloaded).
func load_ratio() -> float:
	if total_capacity_watts <= 0.0:
		return 1.0 if active_draw_watts > 0.0 else 0.0
	return active_draw_watts / total_capacity_watts


## Headroom in watts (negative = deficit).
func headroom_watts() -> float:
	return total_capacity_watts - active_draw_watts


## Returns true if a consumer is currently receiving power.
func is_consumer_powered(id: String) -> bool:
	return _consumers.get(id, {}).get("powered", false)


## Human-readable grid state string for UI display.
## ONLINE / BROWNOUT / OVERLOADED / TRIPPED / OFFLINE
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
			"id":      con.get("id", ""),
			"type":    con.get("type", ""),
			"watts":   float(con.get("watts", 0.0)),
			"powered": bool(con.get("powered", false)),
			"shed":    bool(con.get("shed", false)),
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
			var brk_node: Node = _breakers[bid].get("node", null)
			if brk_node != null and is_instance_valid(brk_node) \
					and brk_node.has_method("set_tripped"):
				brk_node.set_tripped(false)

	## Re-solve now that these breakers are no longer tripped.
	_solve_network()

## Returns all registered wire nodes as Array[Dictionary] {key, pos, role}.
func get_wire_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: String in _wire_nodes:
		var nd: Dictionary = _wire_nodes[k]
		out.append({
			"key":       k,
			"pos":       nd.get("pos", Vector3.ZERO),
			"role":      nd.get("role", "joint"),
			"device_id": nd.get("device_id", ""),
		})
	return out

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
func get_wire_zones() -> Array[Dictionary]:
	## Collect the set of snap keys that are breaker nodes.
	var breaker_keys: Dictionary = {}
	for bid: String in _breakers:
		var bk: String = _breakers[bid].get("node_key", "")
		if not bk.is_empty():
			breaker_keys[bk] = true

	## If no breakers exist, return one zone containing all edges.
	if breaker_keys.is_empty():
		var all_ids: Array[String] = []
		for eid: String in _wire_edges:
			all_ids.append(eid)
		if all_ids.is_empty():
			return []
		return [{"edge_ids": all_ids, "index": 0}]

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
			zones.append({"edge_ids": zone_edges, "index": zones.size()})

	return zones


## Returns all registered wire edges as Array[Dictionary].
func get_wire_edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge: Dictionary in _wire_edges.values():
		out.append(edge.duplicate())
	return out

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
func _solve_network() -> void:
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		_cut_all_consumers()
		return
	if _flickering:
		return   ## Let flicker complete; it will call _go_offline() when done.

	_build_adjacency()
	_run_bfs()
	_apply_reachability()
	_calculate_edge_loads()
	_evaluate_per_component()   ## zone-aware draw + shed + state evaluation
	draw_changed.emit(active_draw_watts, total_capacity_watts, battery_charge_ratio())


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
	var gen_blocked_nodes: Dictionary = {}   ## node_key → true  (gen graph only blocked)

	for brk: Dictionary in _breakers.values():
		var bk: String = brk["node_key"]
		if brk.get("tripped", false):
			tripped_nodes[bk] = true
		elif not brk.get("pass_generator", true):
			gen_blocked_nodes[bk] = true

	for edge: Dictionary in _wire_edges.values():
		var a: String = edge["node_a"]
		var b: String = edge["node_b"]
		if not _wire_nodes.has(a) or not _wire_nodes.has(b):
			continue

		## ── Full adjacency (battery graph) ──
		if not tripped_nodes.has(a) and not tripped_nodes.has(b):
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


## BFS from all running generator wire nodes AND discharging battery wire nodes.
##
## Generators use _adjacency_gen (respects pass_generator=false breakers).
## Batteries use _adjacency (full graph — pass_battery flags already handled
## by the adjacency builder blocking tripped breakers only).
## The _reachable set is the UNION of both BFS results.
func _run_bfs() -> void:
	_reachable.clear()
	for wn: Dictionary in _wire_nodes.values():
		wn["reachable"] = false

	var gen_queue: Array[String] = []
	var bat_queue: Array[String] = []

	## Seed generators → gen queue (uses _adjacency_gen).
	for gen: Dictionary in _generators.values():
		if not gen.get("running", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
				var key: String = wn["key"]
				if not _reachable.has(key):
					_reachable[key] = true
					wn["reachable"] = true
					gen_queue.append(key)
				break

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
			continue
		for neighbor: String in (_adjacency_gen[current] as Array):
			if not _reachable.has(neighbor):
				_reachable[neighbor] = true
				if _wire_nodes.has(neighbor):
					_wire_nodes[neighbor]["reachable"] = true
				gen_queue.append(neighbor)

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


## Apply power state to all consumers based on reachability.
func _apply_reachability() -> void:
	for c: Dictionary in _consumers.values():
		var dev_id: String = c["id"]
		var node_reachable: bool = _is_consumer_reachable(dev_id)
		var should_power: bool = node_reachable \
			and c.get("active", false) \
			and not c.get("shed", false)
		var was_powered: bool = c.get("powered", false)
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
		var bat_node: Node = bat.get("node")
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
func _component_draw(component_keys: Dictionary) -> float:
	var draw: float = 0.0
	for c: Dictionary in _consumers.values():
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					if c.get("powered", false):
						draw += float(c.get("watts", 0.0))
					elif c.get("shed", false) and c.get("active", false):
						draw += SHED_WATTS
				break
	for bat: Dictionary in _batteries.values():
		if not bat.get("charging", false):
			continue
		if float(bat.get("charge_wh", 0.0)) >= float(bat.get("capacity_wh", 0.0)):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
				if component_keys.has(wn["key"]):
					draw += BATTERY_CHARGE_WATTS
				break
	return draw


## ─── Per-component capacity ────────────────────────────────────────────────
## Sums running generator watts whose wire node is in component_keys.
func _component_capacity(component_keys: Dictionary) -> float:
	var cap: float = 0.0
	for gen: Dictionary in _generators.values():
		if not gen.get("running", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
				if component_keys.has(wn["key"]):
					cap += float(gen.get("watts", 0.0))
				break
	return cap


## ─── Find all connected components in _adjacency ─────────────────────────────
## Returns Array of Dictionaries, each with:
##   "keys": Dictionary (snap_key → true) — all nodes in this component
## Only visits nodes present in _adjacency (live, untripped graph).
## Isolated wire nodes (no live edges) are not included.
func _find_components() -> Array[Dictionary]:
	var visited: Dictionary = {}
	var components: Array[Dictionary] = []
	for start: String in _adjacency:
		if visited.has(start):
			continue
		## BFS flood-fill from this node.
		var component_keys: Dictionary = {}
		var queue: Array[String] = [start]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			if visited.has(cur):
				continue
			visited[cur] = true
			component_keys[cur] = true
			if _adjacency.has(cur):
				for nb: String in (_adjacency[cur] as Array):
					if not visited.has(nb):
						queue.append(nb)
		components.append({"keys": component_keys})
	return components


## ─── Per-component load shed ────────────────────────────────────────────────
## Attempts to shed lights within component_keys to cover the deficit.
## Returns the new draw after shedding.
func _shed_lights_in_component(component_keys: Dictionary, capacity: float) -> float:
	var draw: float = _component_draw(component_keys)
	var priority: int = SHED_START_PRIORITY
	while priority >= SHED_END_PRIORITY and draw > capacity:
		var deficit_now: float = draw - capacity
		for c: Dictionary in _consumers.values():
			if not (c.get("type", "") in LIGHT_TYPES):
				continue
			if c.get("priority", 3) != priority:
				continue
			if not c.get("powered", false) or c.get("shed", false):
				continue
			## Only shed consumers in this component.
			var in_component: bool = false
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if component_keys.has(wn["key"]):
						in_component = true
					break
			if not in_component:
				continue
			c["shed"]    = true
			c["powered"] = false
			_apply_shed_to_consumer(c)
			draw -= float(c.get("watts", 0.0))
			draw += SHED_WATTS
			deficit_now -= float(c.get("watts", 0.0)) - SHED_WATTS
			if draw <= capacity:
				break
		priority -= 1
	return draw


## ─── Unshed all lights in a component ─────────────────────────────────────
func _unshed_component(component_keys: Dictionary) -> void:
	for c: Dictionary in _consumers.values():
		if not c.get("shed", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					c["shed"] = false
					var n: Node = c.get("node")
					if n != null and is_instance_valid(n) and n.has_method("set_shed"):
						n.set_shed(false)
				break


## ─── Main per-component evaluation ──────────────────────────────────────────
## Replaces the old _recalculate_draw_from_consumers() + _evaluate_grid_state()
## + _attempt_load_shed() with a zone-aware version that evaluates each
## electrically-isolated sub-grid independently.
##
## After this function returns:
##   active_draw_watts    = sum of all components' draw (for HUD signal)
##   total_capacity_watts = sum of all components' generator capacity
##
## Grid state is set to the WORST state across all components.
func _evaluate_per_component() -> void:
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		return

	## Find connected components (isolated sub-grids) in the live adjacency graph.
	var components: Array[Dictionary] = _find_components()

	## Aggregate totals reset — will be rebuilt below.
	active_draw_watts    = 0.0
	total_capacity_watts = 0.0

	## Track overall worst state across all components.
	var any_brownout:  bool = false
	var any_overload:  bool = false
	var any_offline:   bool = false

	for comp: Dictionary in components:
		var comp_keys: Dictionary = comp["keys"]

		## Skip components with no devices (bare wire only).
		var has_device: bool = false
		for k: String in comp_keys:
			if _wire_nodes.has(k) and _wire_nodes[k].get("role", "joint") != "joint":
				has_device = true
				break
		if not has_device:
			continue

		## Is any battery in this component currently discharging?
		var comp_battery_discharging: bool = false
		for bat: Dictionary in _batteries.values():
			if not bat.get("discharging", false) or not bat.get("enabled", true):
				continue
			if float(bat.get("charge_wh", 0.0)) <= 0.0:
				continue
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
					if comp_keys.has(wn["key"]):
						comp_battery_discharging = true
					break
			if comp_battery_discharging:
				break

		var comp_capacity: float = _component_capacity(comp_keys)
		var comp_draw:     float = _component_draw(comp_keys)

		## Accumulate global totals.
		total_capacity_watts += comp_capacity
		active_draw_watts    += comp_draw

		## Skip shed/overload evaluation when a battery is covering this component.
		## _tick_batteries() owns the drain→offline logic for battery-backed zones.
		if comp_battery_discharging:
			continue

		## No capacity and no battery → this component is offline.
		if comp_capacity <= 0.0:
			## Only trigger offline if there are active consumers here.
			if comp_draw > 0.0:
				## No local battery charge either?
				var local_bat_charge: float = 0.0
				for bat: Dictionary in _batteries.values():
					for wn: Dictionary in _wire_nodes.values():
						if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
							if comp_keys.has(wn["key"]) and bat.get("enabled", true):
								local_bat_charge += float(bat.get("charge_wh", 0.0))
							break
				if local_bat_charge <= 0.0:
					any_offline = true
			continue

		var deficit: float = comp_draw - comp_capacity
		if deficit <= 0.0:
			## This component is healthy — unshed any lights that were previously shed.
			_unshed_component(comp_keys)
		else:
			## Deficit — try to shed lights within this component.
			## Step 1: try starting backup generators on this component.
			var backups_started: bool = false
			for gen: Dictionary in _generators.values():
				if not gen.get("backup", false) or gen.get("running", false):
					continue
				if float(gen.get("fuel", 0.0)) <= 0.0 or float(gen.get("health", 0.0)) <= 0.0:
					continue
				## Check if this backup generator's wire node is in this component.
				for wn: Dictionary in _wire_nodes.values():
					if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
						if comp_keys.has(wn["key"]):
							gen["auto_started"] = true
							_start_generator(gen["id"])
							backups_started = true
						break
			if backups_started:
				## Capacity may have changed — recompute.
				comp_capacity = _component_capacity(comp_keys)
				comp_draw     = _component_draw(comp_keys)
				total_capacity_watts += comp_capacity  ## add newly started gen
				active_draw_watts    = 0.0             ## will re-sum below; mark dirty
				## Mark active_draw_watts dirty — we recalculate globally after loop.

			## Step 2: shed lights in this component.
			if comp_draw > comp_capacity:
				comp_draw = _shed_lights_in_component(comp_keys, comp_capacity)
				if comp_draw > comp_capacity:
					## Still over after shedding all lights → trigger flicker→offline.
					any_overload = true
				else:
					any_brownout = true
			elif comp_capacity > 0.0:
				## Backups resolved it — unshed.
				_unshed_component(comp_keys)

	## ── Recalculate global draw after potential shedding ─────────────────────
	## (capacity was already accumulated in the loop; draw needs a clean pass
	## because shedding changes powered→shed which changes watts counted.)
	active_draw_watts = 0.0
	for c: Dictionary in _consumers.values():
		if not _is_consumer_reachable(c["id"]):
			continue
		if c.get("powered", false):
			active_draw_watts += float(c.get("watts", 0.0))
		elif c.get("shed", false) and c.get("active", false):
			active_draw_watts += SHED_WATTS
	for bat: Dictionary in _batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			active_draw_watts += BATTERY_CHARGE_WATTS

	## ── Global grid state machine ────────────────────────────────────────────
	## The global grid_state reflects the worst condition across all components.
	## Component-level "OFFLINE" means _go_offline() needs to evaluate topology.
	var old_state: GridState = grid_state

	if any_overload and not _flickering:
		_start_flicker_offline()
		return   ## Flicker will call _go_offline() when done.

	if any_offline:
		## Only fire _go_offline() if we're not already handling it.
		if grid_state != GridState.OFFLINE and not _flickering:
			_go_offline()
		return

	if any_brownout:
		if grid_state != GridState.BROWNOUT:
			grid_state = GridState.BROWNOUT
			_overload_timer = 0.0
			grid_state_changed.emit(grid_state, old_state)
			brownout_started.emit()
	else:
		## All components healthy.
		match grid_state:
			GridState.BROWNOUT:
				grid_state = GridState.ONLINE
				_overload_timer = 0.0
				grid_state_changed.emit(grid_state, old_state)
				brownout_ended.emit()
			GridState.OVERLOADED:
				grid_state = GridState.ONLINE
				_overload_timer = 0.0
				grid_state_changed.emit(grid_state, old_state)


## ─── Legacy stubs (kept so call-sites compile) ───────────────────────────────
## These are no longer called internally — _evaluate_per_component() replaces them.
## External callers (if any) are directed here for safety.
func _recalculate_draw_from_consumers() -> void:
	## Recompute global active_draw_watts from all reachable consumers.
	## Still used by _start_generator() recovery path and any legacy callers.
	active_draw_watts = 0.0
	for c: Dictionary in _consumers.values():
		if not _is_consumer_reachable(c["id"]):
			continue
		if c.get("powered", false):
			active_draw_watts += float(c.get("watts", 0.0))
		elif c.get("shed", false) and c.get("active", false):
			active_draw_watts += SHED_WATTS
	for bat: Dictionary in _batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			active_draw_watts += BATTERY_CHARGE_WATTS


func _evaluate_grid_state() -> void:
	## Replaced by _evaluate_per_component(). This stub is kept for safety.
	_evaluate_per_component()


func _attempt_load_shed(_deficit: float) -> void:
	## Replaced by _evaluate_per_component(). This stub is kept for safety.
	_evaluate_per_component()


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
	## Transition to OVERLOADED briefly so the HUD can show the right state.
	if grid_state != GridState.OVERLOADED:
		var old: GridState = grid_state
		grid_state = GridState.OVERLOADED
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
				var n: Node = c.get("node")
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
			var n: Node = c.get("node")
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
			var n: Node = gen.get("node")
			if n != null and is_instance_valid(n):
				if n.has_method("set_running"):
					n.set_running(false)
				if n.has_method("on_grid_tripped"):
					n.on_grid_tripped()
			generator_stopped.emit(gen["id"], "grid_tripped")
	_recalculate_capacity()
	print("PowerManager: grid TRIPPED — %s" % reason)


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
			var gn: Node = gen.get("node")
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
		if bat_old != GridState.BROWNOUT:
			grid_state = GridState.BROWNOUT
			grid_state_changed.emit(grid_state, bat_old)
			brownout_started.emit()

		_solve_network()
		print("PowerManager: generators offline — battery takeover (topology-local), lights shed.")
		return

	## No local batteries with charge → true blackout.
	_flickering = false
	var old: GridState = grid_state
	grid_state = GridState.OFFLINE
	grid_state_changed.emit(grid_state, old)
	grid_offline.emit()
	grid_tripped.emit()
	_cut_all_consumers()
	print("PowerManager: grid OFFLINE — no generation, no local battery.")


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
	var n: Node = gen.get("node")
	if n != null and is_instance_valid(n) and n.has_method("set_running"):
		n.set_running(true)
	generator_started.emit(gen_id)
	_recalculate_capacity()

	## If we were running on battery power (BROWNOUT from battery takeover),
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
		if grid_state == GridState.BROWNOUT:
			var old_s: GridState = grid_state
			grid_state = GridState.ONLINE
			_overload_timer = 0.0
			grid_state_changed.emit(grid_state, old_s)
			brownout_ended.emit()
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
	var n: Node = gen.get("node")
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


## Start backup generators when the grid is overloaded but primaries are alive.
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

		var gen_w:    float = maxf(float(gen.get("watts", 0.0)), 1.0)
		var share:    float = clampf(gen_w / total_w, 0.0, 1.0)
		var drain:    float = BASE_DRAIN * share * (0.2 + 0.8 * lr)

		gen["fuel"] = maxf(0.0, float(gen["fuel"]) - drain * delta)

		var gen_node: Node = gen.get("node", null)
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
		## group_key (battery wire key) → { "batteries": [], "load_w": float }

		for bat: Dictionary in _batteries.values():
			if not bat.get("discharging", false) or not bat.get("enabled", true):
				continue
			var bkey: String = _battery_wire_key(bat["id"])
			if bkey.is_empty():
				## Battery has no wire node — it cannot serve anyone, skip.
				continue
			## Find all OTHER discharging batteries in the same component.
			## We BFS from this battery's node to accumulate local consumer draw.
			## For grouping, use the BFS to find a canonical "component id"
			## (lowest snap key in the component, for determinism).
			var visited: Dictionary = {}
			var queue: Array[String] = [bkey]
			visited[bkey] = true
			var component_keys: Array[String] = [bkey]
			while not queue.is_empty():
				var cur: String = queue.pop_front()
				if _adjacency.has(cur):
					for nb: String in (_adjacency[cur] as Array):
						if not visited.has(nb):
							visited[nb] = true
							queue.append(nb)
							component_keys.append(nb)

			## Compute local consumer draw (only reachable consumers).
			var local_draw: float = 0.0
			for c: Dictionary in _consumers.values():
				var c_reachable: bool = _is_consumer_reachable(c["id"])
				if not c_reachable:
					continue
				## Is this consumer's wire node in our BFS component?
				var c_in_component: bool = false
				for wn: Dictionary in _wire_nodes.values():
					if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
						if visited.has(wn["key"]):
							c_in_component = true
						break
				if not c_in_component:
					continue
				if c.get("powered", false):
					local_draw += float(c.get("watts", 0.0))
				elif c.get("shed", false) and c.get("active", false):
					local_draw += SHED_WATTS

			## Canonical group id = lexicographically smallest key in component.
			component_keys.sort()
			var group_id: String = component_keys[0]
			if not discharge_groups.has(group_id):
				discharge_groups[group_id] = { "batteries": [], "load_w": 0.0, "visited": visited }
			(discharge_groups[group_id]["batteries"] as Array).append(bat)
			discharge_groups[group_id]["load_w"] = local_draw   ## same for all in group

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
		var any_still_discharging: bool = false
		for bat: Dictionary in _batteries.values():
			if bat.get("discharging", false) and float(bat.get("charge_wh", 0.0)) > 0.0:
				any_still_discharging = true
				break
		if not any_still_discharging and not any_still_alive_globally:
			_go_offline_true()
		return   ## Skip charge path when discharging.

	## ── CHARGE path — only when generators have surplus ───────────────────────
	## TOPOLOGY RULE: a battery only charges from generators on its own sub-grid.

	for bat: Dictionary in _batteries.values():
		## Skip disabled batteries — they neither charge nor discharge.
		if not bat.get("enabled", true):
			continue
		var cap: float = float(bat.get("capacity_wh", 0.0))
		var cur: float = float(bat.get("charge_wh",   0.0))

		## Find this battery's wire node and BFS to get local generator capacity.
		var bkey: String = _battery_wire_key(bat["id"])
		if bkey.is_empty():
			continue   ## Unwired battery — cannot charge or discharge.

		## Local capacity = sum of running generators reachable from this battery.
		var local_capacity: float = 0.0
		var bfs_visited: Dictionary = {}
		var bfs_queue: Array[String] = [bkey]
		bfs_visited[bkey] = true
		while not bfs_queue.is_empty():
			var cur_key: String = bfs_queue.pop_front()
			var wn: Dictionary = _wire_nodes.get(cur_key, {})
			if wn.get("role", "") == "generator":
				var gid: String = wn.get("device_id", "")
				if not gid.is_empty() and _generators.has(gid):
					var gen: Dictionary = _generators[gid]
					if gen.get("running", false):
						local_capacity += float(gen.get("watts", 0.0))
			if _adjacency.has(cur_key):
				for nb: String in (_adjacency[cur_key] as Array):
					if not bfs_visited.has(nb):
						bfs_visited[nb] = true
						bfs_queue.append(nb)

		## Local consumer draw = sum of powered consumers reachable from battery.
		var local_draw: float = 0.0
		for c: Dictionary in _consumers.values():
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if bfs_visited.has(wn["key"]):
						if c.get("powered", false):
							local_draw += float(c.get("watts", 0.0))
						elif c.get("shed", false) and c.get("active", false):
							local_draw += SHED_WATTS
					break

		var local_surplus: float = maxf(0.0, local_capacity - local_draw)

		if local_surplus > 0.0 and cur < cap:
			var charge_wh: float = BATTERY_CHARGE_RATE * local_surplus * delta
			bat["charge_wh"] = minf(cap, cur + charge_wh)
			if bat.get("discharging", false):
				bat["discharging"] = false
				battery_state_changed.emit(bat["id"], false)
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
	_flickering = false
	var old: GridState = grid_state
	grid_state = GridState.OFFLINE
	grid_state_changed.emit(grid_state, old)
	grid_offline.emit()
	_cut_all_consumers()
	print("PowerManager: grid OFFLINE — all generators and batteries exhausted.")


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — WIRE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _remove_wire_edge_internal(edge_id: String) -> void:
	if not _wire_edges.has(edge_id):
		return
	## Destroy the WireSegment scene node when this edge is removed due to a
	## device being deconstructed.  Without this, the wire mesh stays in the
	## world even though it is electrically gone.
	var edge: Dictionary = _wire_edges[edge_id]
	var scene_node: Node = edge.get("node")
	if scene_node != null and is_instance_valid(scene_node):
		scene_node.queue_free()
	_wire_edges.erase(edge_id)
	wire_edge_unregistered.emit(edge_id)


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
			var sn: Node = c.get("node")
			if sn != null and is_instance_valid(sn) and sn.has_method("set_shed"):
				sn.set_shed(false)
		c["powered"] = false
		_apply_power_to_consumer(c, false)
	## Zero draw so the HUD and debug panel reflect true blackout immediately.
	active_draw_watts = 0.0
	draw_changed.emit(active_draw_watts, total_capacity_watts, battery_charge_ratio())


func _apply_power_to_consumer(c: Dictionary, powered: bool) -> void:
	var n: Node = c.get("node")
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_powered"):
		n.set_powered(powered)


## Called when a consumer is shed (lights only). Tells the node to dim rather
## than go fully dark. Uses set_shed() if available, otherwise set_powered(false).
func _apply_shed_to_consumer(c: Dictionary) -> void:
	var n: Node = c.get("node")
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
	var n: Node = bat.get("node")
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
	var n: Node = bat.get("node")
	if n == null or not is_instance_valid(n):
		return
	var discharging: bool = bat.get("discharging", false)
	var charging:    bool = bat.get("charging",    false)
	if n.has_method("set_battery_mode"):
		n.set_battery_mode(charging, discharging)


func _notify_breaker_node(breaker_id: String, tripped: bool) -> void:
	if not _breakers.has(breaker_id):
		return
	var n: Node = _breakers[breaker_id].get("node")
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("set_tripped"):
		n.set_tripped(tripped)


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — SNAP KEY UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

## Convert a world position to a snap-grid key string.
func _snap_key(pos: Vector3) -> String:
	var ix: int = roundi(pos.x / SNAP_GRID)
	var iy: int = roundi(pos.y / SNAP_GRID)
	var iz: int = roundi(pos.z / SNAP_GRID)
	return "%d,%d,%d" % [ix, iy, iz]


## Reconstruct the exact snapped world position from a snap key.
func _snapped_pos(pos: Vector3) -> Vector3:
	return Vector3(
		roundf(pos.x / SNAP_GRID) * SNAP_GRID,
		roundf(pos.y / SNAP_GRID) * SNAP_GRID,
		roundf(pos.z / SNAP_GRID) * SNAP_GRID
	)
