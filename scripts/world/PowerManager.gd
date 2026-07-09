extends Node
class_name PowerManager
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
## PRIORITY / OVERLOADED / SHEDDING
##   During a watts deficit the solver:
##     1. Tries to spin up backup generators first.
##     2. If still over, sheds ALL non-critical consumers by priority tier,
##        from tier 5 (luxury) down to tier 2.  ANY non-critical device cuts —
##        lights, microwave, washer, etc.  Tier 1 (critical) is NEVER shed.
##        (Future: a player option to choose which tiers cut during a overloaded,
##         tradeoff = faster battery drain.  Not implemented yet — the shed
##         function is kept parameterizable so it can be added later.)
##     3. If still over after shedding all non-critical tiers → flicker then
##        go OFFLINE.
##
## ZONES — DERIVED FROM THE GRAPH (NOT string-based)
##   There are no string zone names.  "Zones" are GRAPH COMPONENTS that emerge
##   from circuit-breaker placement: tripping/opening a breaker cuts the graph,
##   and each isolated piece becomes a zone.  Zones are computed, never stored
##   as a parameter on devices.
##     - get_wire_zones()              → partitions the graph into zones.
##     - get_wire_zones_with_colors()  → zones + a stable color_index per zone.
##     - ZONE_COLORS                   → the canonical color palette (single
##                                       source of truth; see below).
##   Zone colors are assigned so neighboring zones differ where possible.
##   Old APIs (trip_zone / reset_zone_breaker) are gone.  Use trip_breaker /
##   reset_breaker (and reset_zone_by_index) instead.
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
	OVERLOADED,   ## grid overloaded — managed via shedding / batteries
	BROWNOUT,     ## severe deficit after shedding — imminent total blackout
	TRIPPED,      ## main breaker blown — manual reset required
	OFFLINE,      ## no generators + no battery — true blackout
}

# ─── Constants ────────────────────────────────────────────────────────────────

## Snap grid in metres — must match BuildModeController.grid_size.
const SNAP_GRID: float = 0.25

## Debug toggle for the visual↔graph reconciler (reconcile_wire_visuals).
## When true, prints a one-line summary whenever tubes are corrected or freed.
const RECONCILE_DEBUG: bool = false

## Wire/zone debug toggle — mirrors MainWorld.WIRE_DEBUG.
## All [PM:*] prints are buffered into _pm_wire_log and NEVER printed live.
## MainWorld's F9 handler calls dump_wire_log() to retrieve and print them.
## Zero cost when false.
const WIRE_DEBUG: bool = true

## Seconds of grace between BROWNOUT and a full grid trip.
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

## Priority shed range — overloaded sheds EVERY non-critical consumer in tiers
## 5 (luxury) down to 2.  Tier 1 (critical) is NEVER shed.  Shedding is gated by
## PRIORITY, not device type — any non-critical appliance (microwave, washer,
## lights, …) is cut during a overloaded.
##
## FUTURE (do NOT implement yet — keep in mind): let the player choose which
## tiers shed first, trading coverage for faster battery drain.  These two
## constants are the seam for that — _shed_in_component() already walks the range
## parametrically, so a player setting would just override START/END at runtime.
const SHED_START_PRIORITY: int = 5
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


# ═══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_graph = PowerGraph.new(self)
	pass   ## No default zone — graph starts empty.

func _process(delta: float) -> void:
	_tick_generators(delta)
	_tick_batteries(delta)

	## If _tick_batteries flagged a resolve (all batteries died), run it now —
	## once per frame rather than every frame inside the tick loop.
	if _needs_resolve:
		_needs_resolve = false
		_solve_network()

	## Flicker sequence overrides everything else.
	if _flickering:
		_tick_flicker(delta)
		return

	match grid_state:
		GridState.BROWNOUT:
			## BROWNOUT → instant trip (no grace period).
			## This state is only reached when even battery coverage failed,
			## so we go straight to TRIPPED without waiting.
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

## ─────────────────────────────────────────────────────────────────────────────
## WIRE GRAPH — forwarded to PowerGraph.gd (Stage 5 extraction, see
## REVIEW_IMPLEMENTATION_PLAN.md). Signatures identical to before the split —
## every external call site (BreakerBox, WallLight, GeneratorObject,
## BuildModeController, MainWorld, etc.) needs zero changes.
## ─────────────────────────────────────────────────────────────────────────────

func register_wire_node(pos: Vector3, role: String, device_id: String = "") -> String:
	return _graph.register_wire_node(pos, role, device_id)

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
func zone_color_at(color_index: int, alpha: float = 0.60) -> Color:
	var c: Color = ZONE_COLORS[color_index % ZONE_COLORS.size()]
	c.a = alpha
	return c


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


# ─── Power priority API ──────────────────────────────────────────────────────
## Lowest/highest selectable priority tiers exposed to the player UI.
## 1 = critical (never shed) … 5 = luxury (first to shed).
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

## Returns the current priority (1–5) of a consumer, or 3 (default) if unknown.
func get_consumer_priority(id: String) -> int:
	return int(_consumers.get(id, {}).get("priority", 3))


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
	## Clear shed/powered state for every consumer sharing this component BEFORE
	## re-solving.  Without this, the solver's HEALTHY branch only ever tries to
	## UN-shed items (see _partial_unshed_component) — it never re-sheds an
	## already-powered item.  If two consumers swap priorities (A: pri2→pri3,
	## B: pri3→pri2) the post-swap net_deficit can still read <=0 against the
	## STALE shed/powered flags, so the solver thinks nothing needs to change
	## and the wrong item stays shed.  Wiping the whole component's shed state
	## forces a clean full-draw shed pass that re-evaluates by CURRENT priority.
	_reset_shed_for_consumer_component(id)
	## Re-solve so the new tier is honoured right away — an item raised to a
	## safer tier may un-shed, or one lowered may be shed if the zone is tight.
	_solve_network()


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
	return bool(_consumers.get(id, {}).get("active", false))


## Returns true if the consumer is currently receiving full power.
func get_consumer_powered(id: String) -> bool:
	return bool(_consumers.get(id, {}).get("powered", false))


## Returns true if the consumer is currently load-shed (connected but cut).
func get_consumer_shed(id: String) -> bool:
	return bool(_consumers.get(id, {}).get("shed", false))


## One-shot status snapshot for the priority UI. Keys:
##   "registered" bool — false if id unknown to the grid
##   "watts"      float
##   "priority"   int  (1–5)
##   "active"     bool — player switch state
##   "powered"    bool — receiving full power right now
##   "shed"       bool — load-shed (connected but not powered)
##   "status_str" String — "POWERED" / "SHED" / "NO POWER" / "OFF" / "UNWIRED"
func get_consumer_status(id: String) -> Dictionary:
	if not _consumers.has(id):
		return {"registered": false}
	var c: Dictionary = _consumers[id]
	var active:  bool  = bool(c.get("active", false))
	var powered: bool  = bool(c.get("powered", false))
	var shed:    bool  = bool(c.get("shed", false))
	var wired:   bool  = _consumer_is_wired(id)

	var status_str: String
	if not active:
		status_str = "OFF"
	elif shed:
		status_str = "SHED"
	elif powered:
		status_str = "POWERED"
	elif not wired:
		status_str = "UNWIRED"
	else:
		status_str = "NO POWER"

	return {
		"registered": true,
		"watts":      float(c.get("watts", 0.0)),
		"priority":   int(c.get("priority", 3)),
		"active":     active,
		"powered":    powered,
		"shed":       shed,
		"wired":      wired,
		"status_str": status_str,
	}


## True if this consumer has a wire node that participates in any edge.
func _consumer_is_wired(id: String) -> bool:
	for wn: Dictionary in _wire_nodes.values():
		if wn.get("role", "") == "consumer" and wn.get("device_id", "") == id:
			var key: String = wn.get("key", "")
			return _adjacency.has(key) and not (_adjacency[key] as Array).is_empty()
	return false


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

	_pmdbg("[PM:GEN] register_generator called — id=%s watts=%.0f backup=%s fuel=%.1f health=%.1f" % [
		gen_id, watts, str(is_backup), fuel, health])
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
	_pmdbg("[PM:GEN] _generators now has %d entries" % _generators.size())
	_recalculate_capacity()
	generator_registered.emit(gen_id, watts, is_backup)
	if running:
		generator_started.emit(gen_id)
	## Trigger a network solve so consumers connected to this generator light up
	## immediately without waiting for another topology event.
	_solve_network()


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
	return _consumers.get(id, {}).get("powered", false)


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
func _component_draw(component_keys: Dictionary) -> float:
	var draw: float = 0.0
	for c: Dictionary in _consumers.values():
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					if c.get("powered", false):
						draw += float(c.get("watts", 0.0))
					elif c.get("shed", false) and c.get("active", false):
						draw += _shed_residual_watts(c)
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


## ─── Per-component POTENTIAL (un-shed) draw ─────────────────────────────────
## Sums the FULL rated draw of every active consumer in component_keys as if
## NOTHING were shed (shed items counted at full watts, not residual).  Used by
## the HEALTHY/unshed decision so we only un-shed when the zone could carry the
## full restored load — otherwise un-shedding re-overloads and oscillates.
func _component_draw_unshed(component_keys: Dictionary) -> float:
	var draw: float = 0.0
	for c: Dictionary in _consumers.values():
		if not c.get("active", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					draw += float(c.get("watts", 0.0))
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
	var _dbg_cap_total: float = 0.0
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
## Returns cached connected-component partition.  Rebuilds (one flood over
## _adjacency) only when the cache is invalid.  Use this everywhere instead of
## flooding the graph per-call — _tick_batteries() runs this every frame.
func _find_components() -> Array[Dictionary]:
	if not _component_cache_valid:
		_component_cache       = _find_components_raw()
		_component_cache_valid = true
	return _component_cache


## Raw connected-component flood-fill over _adjacency (ignores breakers).
## Each component is { "keys": { snap_key: true, ... } }.
## Never call directly in per-frame code — go through _find_components().
func _find_components_raw() -> Array[Dictionary]:
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


## ─── Cross-zone generator sharing: identify sharing zone pairs ─────────────
## Returns Array of Dictionaries, each describing one directional gen-share link:
##   { "from_zi": int, "to_zi": int, "breaker_id": String }
## "from_zi" has surplus generators, "to_zi" has deficit.
## Only untripped, pass_generator=true breakers create sharing links.
## Sharing is bidirectional — both directions are possible depending on who
## has surplus; the caller (3-pass evaluator) decides direction at solve time.
## Each pair appears once in each direction so the evaluator can check both.
func _get_gen_sharing_zone_pairs(wire_zones: Array[Dictionary]) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	_pmdbg("[PM:SHARE] _get_gen_sharing_zone_pairs wire_zones=%d" % wire_zones.size())
	if wire_zones.size() < 2:
		_pmdbg("[PM:SHARE]   < 2 zones, returning empty")
		return pairs

	## Build snap_key → zone_index for fast lookup.
	var key_to_zi: Dictionary = {}
	for z: Dictionary in wire_zones:
		var zi: int = int(z.get("index", 0))
		for nk: String in (z.get("node_keys", []) as Array):
			key_to_zi[nk] = zi

	## Check every breaker: if it's untripped + pass_generator=true, find the
	## two zones on either side of it (each side is a set of edge endpoints).
	for bid: String in _breakers:
		var brk: Dictionary = _breakers[bid]
		if brk.get("tripped", false):
			continue
		if not brk.get("pass_generator", true):
			continue   ## This breaker blocks gen BFS — no sharing through it.

		var bk: String = brk.get("node_key", "")
		if bk.is_empty():
			continue

		## Find zone indices on each side of this breaker node.
		## A breaker is the cut-point between two zones. The zones are identified
		## by the snap keys that appear as the OTHER endpoint in edges touching bk.
		var side_zones: Dictionary = {}   ## zone_index → true (should be exactly 2)
		for edge: Dictionary in _wire_edges.values():
			var na: String = edge.get("node_a", "")
			var nb: String = edge.get("node_b", "")
			var other: String = ""
			if na == bk:
				other = nb
			elif nb == bk:
				other = na
			if other.is_empty():
				continue
			if key_to_zi.has(other):
				side_zones[int(key_to_zi[other])] = true

		var zone_list: Array = side_zones.keys()
		_pmdbg("[PM:SHARE]   breaker id=%s key=%s side_zones=%s" % [bid, bk, str(zone_list)])
		if zone_list.size() < 2:
			_pmdbg("[PM:SHARE]     < 2 side zones — no sharing through this breaker")
			continue   ## Breaker touches fewer than 2 zones — nothing to share.

		## Generate pairs for every combination of zones touching this breaker
		## (handles T-junction breakers that border 3+ zones).
		for ai: int in zone_list.size():
			for bi: int in range(ai + 1, zone_list.size()):
				var za: int = int(zone_list[ai])
				var zb: int = int(zone_list[bi])
				## Add both directions — evaluator decides who exports to whom.
				pairs.append({ "from_zi": za, "to_zi": zb, "breaker_id": bid })
				pairs.append({ "from_zi": zb, "to_zi": za, "breaker_id": bid })

	_pmdbg("[PM:SHARE] total sharing pairs=%d: %s" % [pairs.size(), str(pairs)])
	return pairs


## ─── Shed residual draw helper ──────────────────────────────────────────────
## How many watts a SHED consumer still pulls.  Lights dim to a small glow
## (SHED_WATTS); every other appliance switches fully OFF (0W).
## Single source of truth — used by the shed loop and all draw-summing passes.
func _shed_residual_watts(c: Dictionary) -> float:
	if c.get("type", "") in LIGHT_TYPES:
		return SHED_WATTS
	return 0.0


## ─── Per-component load shed ────────────────────────────────────────────────
## Sheds NON-CRITICAL consumers within component_keys, tier by tier (luxury
## first), until draw fits under capacity or there is nothing left to shed.
## Shedding is gated by PRIORITY (SHED_START_PRIORITY → SHED_END_PRIORITY), NOT
## device type — lights, microwaves, washers, anything tier ≥ 2 is eligible.
## Tier 1 (critical) is never touched.  Lights dim (SHED_WATTS), other appliances
## switch fully off (0W) — see _shed_residual_watts().
## Returns the new draw after shedding.
func _shed_in_component(component_keys: Dictionary, capacity: float) -> float:
	var draw: float = _component_draw(component_keys)
	_pmdbg("[PM:SHED] enter: draw=%.1f capacity=%.1f comp_nodes=%d" % [draw, capacity, component_keys.size()])
	var priority: int = SHED_START_PRIORITY
	while priority >= SHED_END_PRIORITY and draw > capacity:
		for c: Dictionary in _consumers.values():
			if c.get("priority", 3) != priority:
				continue
			if not c.get("powered", false) or c.get("shed", false):
				_pmdbg("[PM:SHED]   skip id=%s pri=%d (powered=%s shed=%s)" % [
					str(c.get("id","?")), int(c.get("priority",3)),
					str(c.get("powered",false)), str(c.get("shed",false))])
				continue
			## Only shed consumers in this component.
			var in_component: bool = false
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if component_keys.has(wn["key"]):
						in_component = true
					break
			if not in_component:
				_pmdbg("[PM:SHED]   skip id=%s pri=%d (NOT in this component)" % [
					str(c.get("id","?")), int(c.get("priority",3))])
				continue
			var residual: float = _shed_residual_watts(c)
			_pmdbg("[PM:SHED]   SHED id=%s pri=%d watts=%.1f residual=%.1f draw %.1f->%.1f" % [
				str(c.get("id","?")), int(c.get("priority",3)),
				float(c.get("watts",0.0)), residual,
				draw, draw - float(c.get("watts",0.0)) + residual])
			c["shed"]    = true
			c["powered"] = false
			_apply_shed_to_consumer(c)
			draw -= float(c.get("watts", 0.0))
			draw += residual
			if draw <= capacity:
				break
		priority -= 1
	return draw


## ─── Unshed all lights in a component ─────────────────────────────────────
## Clears the shed flag AND restores full power on each previously-shed,
## reachable consumer in the component.  Unshed only ever runs from the HEALTHY
## branch (capacity available), so re-powering here is safe.  Critically, we
## must call set_powered(true) ourselves: _apply_reachability() runs BEFORE this
## in the solve and saw the consumer still shed (powered stays false), so it
## never re-powers it.  Without this the node clears _is_shed (set_shed(false))
## but is left visually dark/dim until some later solve — the "lights stay dim
## after recovery" bug.  Setting powered=true + set_powered(true) restores full
## brightness on the same frame recovery happens.
func _unshed_component(component_keys: Dictionary) -> void:
	for c: Dictionary in _consumers.values():
		if not c.get("shed", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					c["shed"] = false
					var n: Node = _safe_dict_node(c)
					if n != null and is_instance_valid(n) and n.has_method("set_shed"):
						n.set_shed(false)
					## Re-power so the light returns full-bright immediately,
					## not on some later solve.  Only if active + reachable.
					if c.get("active", false) and _is_consumer_reachable(c["id"]):
						c["powered"] = true
						if n != null and is_instance_valid(n) and n.has_method("set_powered"):
							n.set_powered(true)
				break


## ─── Partial unshed ──────────────────────────────────────────────────────────
## Called from the HEALTHY AT-CAPACITY branch when the FULL unshed draw exceeds
## available capacity but individual items might still fit.  Iterates shed
## consumers from highest priority (2 = most important) to lowest (5 = first-to-
## shed), restoring each one only if its watts fit within remaining headroom.
## Items that don't fit stay shed.  This avoids the ALL-or-NOTHING behavior of
## _unshed_component that kept all lights dim when only a subset could be powered.
## Non-oscillating: we only unshed items that genuinely fit; the next solve sees
## committed_draw rise by exactly their watts, leaving the same remaining headroom.
func _partial_unshed_component(component_keys: Dictionary, avail_cap: float) -> void:
	## Compute draw already committed by powered (non-shed) consumers in this zone.
	var committed_draw: float = 0.0
	for c: Dictionary in _consumers.values():
		if not c.get("powered", false) or c.get("shed", false):
			continue
		for wn: Dictionary in _wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					committed_draw += float(c.get("watts", 0.0))
				break
	var remaining_cap: float = maxf(0.0, avail_cap - committed_draw)
	_pmdbg("[PM:PARTIAL_UNSHED] enter: avail=%.1f committed=%.1f remaining=%.1f" % [
		avail_cap, committed_draw, remaining_cap])

	## Walk priority 2 → SHED_START_PRIORITY (most critical first).
	for priority: int in range(SHED_END_PRIORITY, SHED_START_PRIORITY + 1):
		for c: Dictionary in _consumers.values():
			if not c.get("shed", false) or not c.get("active", false):
				continue
			if c.get("priority", 3) != priority:
				continue
			## Must be in this component.
			var in_component: bool = false
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if component_keys.has(wn["key"]):
						in_component = true
					break
			if not in_component:
				continue
			var watts: float = float(c.get("watts", 0.0))
			if watts > remaining_cap:
				_pmdbg("[PM:PARTIAL_UNSHED]   NO-FIT id=%s pri=%d watts=%.1f remaining=%.1f" % [
					str(c.get("id","?")), priority, watts, remaining_cap])
				continue
			## Restore this item.
			c["shed"]    = false
			c["powered"] = true
			remaining_cap -= watts
			var n: Node = _safe_dict_node(c)
			if n != null and is_instance_valid(n):
				if n.has_method("set_shed"):
					n.set_shed(false)
				if n.has_method("set_powered"):
					n.set_powered(true)
			_pmdbg("[PM:PARTIAL_UNSHED]   RESTORED id=%s pri=%d watts=%.1f remaining=%.1f" % [
				str(c.get("id","?")), priority, watts, remaining_cap])


## ─── Stable component signature key ───────────────────────────────────────────
## Builds a deterministic key from a component's node-set so the sustained-
## brownout latch survives across re-solves even as imported/exported watts
## fluctuate.  Sorted so node-set ordering never changes the key.
func _component_sig_key(component_keys: Dictionary) -> String:
	var ks: Array = component_keys.keys()
	ks.sort()
	return "|".join(PackedStringArray(ks))


## ─── Flood-fill the full shared electrical component ──────────────────────────
## Given one or more seed node keys (typically a single zone's node set), BFS
## across _adjacency — the power/battery graph that already excludes tripped and
## pass-through-blocked breakers — to gather EVERY node key in the same connected
## electrical component.  This spans an arbitrary number of zones bridged by
## non-tripped pass-through breakers (cross-zone shares can chain indefinitely),
## so the brownout + gen-trip below act on the WHOLE shared group, not just the
## one zone that happened to run a deficit.
##   seed_keys: Dictionary of node_key → true (or any keys() iterable set)
## Returns: Dictionary of node_key → true for the full component.
func _flood_component_keys(seed_keys: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = []
	for sk: String in seed_keys.keys():
		if not visited.has(sk):
			visited[sk] = true
			queue.append(sk)
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if not _adjacency.has(cur):
			continue
		for nb: String in (_adjacency[cur] as Array):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited


## ─── Flood-fill the GENERATOR-sharing component (pass_generator=true only) ──
## Same BFS as _flood_component_keys() but walks _adjacency_gen instead of
## _adjacency — i.e. it crosses untripped breakers with pass_generator=true,
## and is blocked by tripped breakers or pass_generator=false breakers (same
## rules the rest of the system already uses for generator BFS seeding and
## cross-zone capacity sharing in _evaluate_per_component's PASS 2).
##
## Used by _tick_batteries()'s charge path so a battery correctly sees
## generator capacity/load from a NEIGHBORING zone connected via a
## pass_generator=true breaker, instead of being scoped to only its own
## breaker-partitioned zone (which was the root cause of batteries never
## charging across a shared-generator breaker connection).
func _flood_gen_component_keys(seed_keys: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = []
	for sk: String in seed_keys.keys():
		if not visited.has(sk):
			visited[sk] = true
			queue.append(sk)
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if not _adjacency_gen.has(cur):
			continue
		for nb: String in (_adjacency_gen[cur] as Array):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited


## ─── Sustained brownout (cross-zone exhaustion) ──────────────────────────────
## Forces EVERY consumer in the component to the SHED (dim-orange) visual —
## including tier-1 critical, because there is genuinely no source left (gens
## tripped, batteries empty).  Then trips the generators feeding the component
## so they require a manual restart.  Unlike _cut_consumers_in_zone() this does
## NOT mark the component OFFLINE: lights keep their dim glow, the rest show
## their [SHED] state.  Latches the component so it stays this way until a
## generator is manually restarted (clear_exhausted_brownout()).
##
## IMPORTANT: callers must pass the FULL shared-component key set (use
## _flood_component_keys first).  A cross-zone share can span many zones; the
## exporter's generator lives in a DIFFERENT zone from the deficit zone, so
## scoping this to a single zone would never trip the source generator.
func _sustained_brownout_component(component_keys: Dictionary) -> void:
	for c: Dictionary in _consumers.values():
		## Only consumers in this component.
		var in_component: bool = false
		for wn: Dictionary in _wire_nodes.values():
			if wn.get("role", "") == "consumer" and wn.get("device_id", "") == c["id"]:
				if component_keys.has(wn.get("key", "")):
					in_component = true
				break
		if not in_component:
			continue
		## Priority 1 (critical) is NEVER shed — even in a sustained brownout
		## where there is genuinely no power source.  These items go fully OFF
		## (set_powered(false), no orange dim) rather than SHED.  The semantic
		## is: "shed" = temporarily reduced load that could come back; a critical
		## item going dark means the whole grid is dead, not just load-shedding.
		if c.get("priority", 3) == 1:
			if c.get("powered", false):
				c["powered"] = false
				_apply_power_to_consumer(c, false)
			continue
		## Force shed visual (dim-orange), no real power.
		c["powered"] = false
		if not c.get("shed", false):
			c["shed"] = true
		_apply_shed_to_consumer(c)
	## Trip the generators feeding this component (manual restart required).
	_trip_generators_in_zone(component_keys)
	## Latch so subsequent re-solves keep this component in brownout until a
	## generator is manually restarted.
	_exhausted_brownout_keys[_component_sig_key(component_keys)] = true


## Clear ALL sustained-brownout latches.  Called when a generator is manually
## restarted — the next _solve_network() re-evaluates from scratch and power
## returns to any component the restarted generator can now feed.
func clear_exhausted_brownout() -> void:
	if _exhausted_brownout_keys.is_empty():
		return
	_exhausted_brownout_keys.clear()
	_needs_resolve = true


## ─── Upgraded breaker: find + self-trip ──────────────────────────────────────
## Returns the breaker_id of every UPGRADED breaker whose node_key falls inside
## component_keys, is currently untripped, AND is currently passing power
## (pass_battery or pass_generator true — a locked/already-tripped upgraded
## breaker has already done its job and shouldn't re-trigger).  In practice a
## single upgraded breaker sits on the boundary between the donor and deficit
## zones, but this returns an Array so multiple bridging upgraded breakers in
## a longer chain all trip together and fully isolate the deficit side.
func _find_upgraded_breakers_in_component(component_keys: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for bid: String in _breakers:
		var brk: Dictionary = _breakers[bid]
		if not bool(brk.get("upgraded", false)):
			continue
		if bool(brk.get("tripped", false)):
			continue   ## already tripped — nothing new to do
		var bk: String = brk.get("node_key", "")
		if bk.is_empty() or not component_keys.has(bk):
			continue
		## Only relevant if it's actually passing something right now — a
		## breaker with both pass-throughs already off isn't contributing to
		## the share and doesn't need to self-trip.
		if not bool(brk.get("pass_battery", true)) and not bool(brk.get("pass_generator", true)):
			continue
		found.append(bid)
	return found


## Self-trip an upgraded breaker on cross-zone exhaustion: sets tripped=true,
## FORCES both pass-throughs off (locked — the player can't re-enable sharing
## until the breaker is manually reset), notifies the scene node for the LED /
## TRIPPED banner, and emits breaker_tripped so any listening UI updates.
##
## group_key identifies the exhaustion EVENT this breaker tripped alongside —
## every upgraded breaker that self-trips from the same
## _find_upgraded_breakers_in_component() call shares the same group_key
## (the component signature). reset_breaker() uses this to find and reset
## every sibling breaker from the same event together (see
## _reset_upgraded_breaker_group()), instead of leaving some tripped while
## only one gets manually reset.
##
## Also snapshots the pre-trip pass_battery/pass_generator values so a group
## reset can restore the player's ORIGINAL sharing intent rather than leaving
## both pass-throughs forced off after reset (which would silently disable
## sharing the player explicitly enabled, with no way to tell from the UI
## alone why it stopped working).
##
## Deliberately does NOT call _solve_network() itself — the caller is already
## mid-solve (_evaluate_per_component) and sets _needs_resolve=true so the
## severed topology is picked up cleanly on the next frame's solve, exactly
## like the _tick_batteries() -> _needs_resolve -> _process() pattern already
## used elsewhere in this file.
func _self_trip_upgraded_breaker(breaker_id: String, group_key: String) -> void:
	if not _breakers.has(breaker_id):
		return
	var brk: Dictionary = _breakers[breaker_id]
	## Preserve whatever the player had set BEFORE forcing both off, so a
	## later group reset can restore intent instead of leaving them off.
	brk["pretrip_pass_battery"]   = brk.get("pass_battery", true)
	brk["pretrip_pass_generator"] = brk.get("pass_generator", true)
	brk["trip_group_key"] = group_key
	brk["tripped"]       = true
	brk["pass_battery"]  = false
	brk["pass_generator"] = false
	_notify_breaker_node(breaker_id, true)
	breaker_tripped.emit(breaker_id)


## ─── Main per-zone evaluation ────────────────────────────────────────────────
## Three-pass zone solver with cross-zone generator sharing.
##
## PASS 1  — compute raw surplus/deficit per zone (local gens only).
## PASS 2  — redistribute surplus from pass_generator=true neighbors to zones
##           still in deficit.  Own-zone load always served first.
## PASS 3  — for each zone, evaluate final watts with imports/exports factored
##           in, then apply shedding / battery / offline as needed.
##
## After this function returns:
##   active_draw_watts    = sum of all zone draws (for HUD signal)
##   total_capacity_watts = sum of all zone generator capacity
##   Grid state = WORST state across all zones.
##
## Cross-zone SHARING RULES (from task.md decisions):
##   • Own-zone load served first — surplus is capacity MINUS own draw.
##   • Exporting zone stress: if (own_draw + exported_w) > capacity → overloaded.
##   • No grace periods — BROWNOUT → instant trip.
func _evaluate_per_component() -> void:
	if grid_state == GridState.TRIPPED or grid_state == GridState.OFFLINE:
		return

	## Get wire zones (breaker-partitioned segments).
	var wire_zones: Array[Dictionary] = get_wire_zones()

	## No wires at all — bare minimum accounting.
	if wire_zones.is_empty():
		active_draw_watts    = 0.0
		total_capacity_watts = 0.0
		for gen: Dictionary in _generators.values():
			if gen.get("running", false):
				total_capacity_watts += float(gen.get("watts", 0.0))
		for c: Dictionary in _consumers.values():
			if c.get("powered", false):
				active_draw_watts += float(c.get("watts", 0.0))
		return

	## Pre-compute per-zone node sets as Dictionary (snap_key → true).
	var n_zones: int = wire_zones.size()
	var zone_node_sets: Array[Dictionary] = []
	for zone: Dictionary in wire_zones:
		var d: Dictionary = {}
		for nk: String in (zone.get("node_keys", []) as Array):
			d[nk] = true
		zone_node_sets.append(d)

	## Each labeled pass below is its own function (Stage 4 refactor — no
	## behavior change, pure extraction). zone_info is a mutable Array of
	## Dictionaries; Pass 2 mutates entries in place (imported_w/exported_w/
	## import_from/export_to), which Pass 3 then reads.
	var zone_info: Array[Dictionary] = _evaluate_pass1_local_surplus(n_zones, zone_node_sets)
	_evaluate_pass2_cross_zone_sharing(wire_zones, n_zones, zone_info)
	var pass3_result: Dictionary = _evaluate_pass3_zone_resolution(n_zones, zone_node_sets, zone_info)

	var any_overloaded: bool      = pass3_result["any_overloaded"]
	var any_offline: bool         = pass3_result["any_offline"]
	var zones_with_device: int    = pass3_result["zones_with_device"]
	var zones_offline: int        = pass3_result["zones_offline"]

	## ── Recalculate global draw after potential shedding ─────────────────────
	active_draw_watts = 0.0
	for c: Dictionary in _consumers.values():
		if not _is_consumer_reachable(c["id"]):
			continue
		if c.get("powered", false):
			active_draw_watts += float(c.get("watts", 0.0))
		elif c.get("shed", false) and c.get("active", false):
			active_draw_watts += _shed_residual_watts(c)
	for bat: Dictionary in _batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			active_draw_watts += BATTERY_CHARGE_WATTS

	## ── Post-loop: stop battery discharge if no zone needs coverage ──────────
	if not any_overloaded and not any_offline:
		for bat: Dictionary in _batteries.values():
			if bat.get("discharging", false):
				bat["discharging"] = false
				bat["charging"]    = false
				battery_state_changed.emit(bat["id"], false)
				_notify_battery_mode(bat["id"])
				_notify_battery_node(bat["id"])

	## ── Global grid state machine ─────────────────────────────────────────────
	var old_state: GridState = grid_state

	if any_offline:
		if zones_offline >= zones_with_device and not _flickering:
			if grid_state != GridState.OFFLINE:
				_go_offline()
			return
		any_overloaded = true   ## partial offline → treat as overloaded for HUD

	if any_overloaded:
		if grid_state != GridState.OVERLOADED:
			grid_state = GridState.OVERLOADED
			_overload_timer = 0.0
			grid_state_changed.emit(grid_state, old_state)
			overloaded_started.emit()
	else:
		match grid_state:
			GridState.OVERLOADED:
				grid_state = GridState.ONLINE
				_overload_timer = 0.0
				grid_state_changed.emit(grid_state, old_state)
				overloaded_ended.emit()
			GridState.BROWNOUT:
				grid_state = GridState.ONLINE
				_overload_timer = 0.0
				grid_state_changed.emit(grid_state, old_state)


## ──────────────────────────────────────────────────────────────────────────
## PASS 1 — raw per-zone surplus/deficit with local gens only.
## ──────────────────────────────────────────────────────────────────────────
## Returns zone_info: Array[Dictionary], one entry per zone (index = zone
## index zi), each dict:
##   "local_cap"   float — running gen watts physically inside this zone
##   "local_draw"  float — consumer draw inside this zone
##   "surplus"     float — local_cap - local_draw  (neg = deficit)
##   "exported_w"  float — watts committed to export (filled in pass 2)
##   "imported_w"  float — watts imported from neighbors (filled in pass 2)
##   "import_from" Array[int] — zone indices we import from
##   "export_to"   Array[int] — zone indices we export to
##   "has_device"  bool  — any non-joint node inside zone
func _evaluate_pass1_local_surplus(
		n_zones: int,
		zone_node_sets: Array[Dictionary]) -> Array[Dictionary]:
	var zone_info: Array[Dictionary] = []
	for zi: int in n_zones:
		var zone_keys: Dictionary = zone_node_sets[zi]
		var has_device: bool = false
		for k: String in zone_keys:
			if _wire_nodes.has(k) and _wire_nodes[k].get("role", "joint") != "joint":
				has_device = true
				break
		var local_cap:  float = _component_capacity(zone_keys)
		var local_draw: float = _component_draw(zone_keys)
		_pmdbg("[PM:EVAL] PASS1 zone %d: local_cap=%.1fw local_draw=%.1fw has_device=%s node_count=%d" % [
			zi, local_cap, local_draw, str(has_device), zone_keys.size()])
		zone_info.append({
			"local_cap":   local_cap,
			"local_draw":  local_draw,
			"surplus":     local_cap - local_draw,
			"exported_w":  0.0,
			"imported_w":  0.0,
			"import_from": [],
			"export_to":   [],
			"has_device":  has_device,
		})
	return zone_info


## ──────────────────────────────────────────────────────────────────────────
## PASS 2 — cross-zone generator sharing via BFS pool flood fill.
##
## OLD APPROACH (broken): iterative round-based loop skipped zones with
## still_needed<=0. Pass-through zones (0 draw, 0 cap) were always skipped,
## so power never propagated beyond the first zone hop.
##
## NEW APPROACH: BFS from every generator zone simultaneously.
##   1. Build undirected zone adjacency from sharing_pairs (breaker links).
##   2. BFS flood-fill to find connected power pools (groups of zones
##      reachable from each other through untripped pass_generator breakers).
##   3. Each pool's total capacity is shared across all its member zones.
##      Zones with local generators donate surplus to deficit zones anywhere
##      in the pool regardless of hop distance or intermediate zone load.
## ──────────────────────────────────────────────────────────────────────────
## Mutates zone_info in place (imported_w/exported_w/import_from/export_to) —
## Dictionaries and Arrays are passed by reference in GDScript, so callers see
## the updates without needing a return value.
func _evaluate_pass2_cross_zone_sharing(
		wire_zones: Array[Dictionary],
		n_zones: int,
		zone_info: Array[Dictionary]) -> void:
	var sharing_pairs: Array[Dictionary] = _get_gen_sharing_zone_pairs(wire_zones)

	## Build undirected zone adjacency from sharing_pairs.
	var zone_adj: Array = []
	for _zi: int in n_zones:
		zone_adj.append([])
	for pair: Dictionary in sharing_pairs:
		var fa: int = int(pair["from_zi"])
		var ta: int = int(pair["to_zi"])
		if not (zone_adj[fa] as Array).has(ta):
			(zone_adj[fa] as Array).append(ta)
		if not (zone_adj[ta] as Array).has(fa):
			(zone_adj[ta] as Array).append(fa)

	## BFS flood: partition zones into power pools.
	## Each pool = all zones reachable from each other via untripped gen-pass breakers.
	var zone_pool: Array[int] = []
	for _zi2: int in n_zones:
		zone_pool.append(-1)
	var pools: Array[Dictionary] = []

	for seed: int in n_zones:
		if zone_pool[seed] != -1:
			continue
		var pool_idx: int = pools.size()
		var pool: Dictionary = { "total_cap": 0.0, "total_draw": 0.0, "members": [] }
		var bfs_q: Array[int] = [seed]
		var bfs_vis: Dictionary = {}
		while not bfs_q.is_empty():
			var cur: int = bfs_q.pop_front()
			if bfs_vis.has(cur):
				continue
			bfs_vis[cur] = true
			zone_pool[cur] = pool_idx
			(pool["members"] as Array).append(cur)
			pool["total_cap"]  = float(pool["total_cap"])  + float(zone_info[cur]["local_cap"])
			pool["total_draw"] = float(pool["total_draw"]) + float(zone_info[cur]["local_draw"])
			for nb: int in (zone_adj[cur] as Array):
				if not bfs_vis.has(nb):
					bfs_q.append(nb)
		pools.append(pool)

	_pmdbg("[PM:EVAL] PASS2 pools=%d zones=%d" % [pools.size(), n_zones])
	for pi: int in pools.size():
		var p: Dictionary = pools[pi]
		_pmdbg("[PM:EVAL]   pool%d members=%s cap=%.1fw draw=%.1fw" % [
			pi, str(p["members"]), p["total_cap"], p["total_draw"]])

	## Distribute pool capacity: each deficit zone pulls surplus from generator zones
	## in the same pool. No hop limit — any zone in the pool can power any other.
	for pi: int in pools.size():
		var p: Dictionary = pools[pi]
		var members: Array = p["members"]
		if float(p["total_cap"]) <= 0.0:
			continue   ## No generators in this pool.

		for zi: int in members:
			var local_cap_zi:  float = float(zone_info[zi]["local_cap"])
			var local_draw_zi: float = float(zone_info[zi]["local_draw"])
			var deficit: float = local_draw_zi - local_cap_zi - float(zone_info[zi]["imported_w"])
			if deficit <= 0.0:
				continue   ## Zone covered locally.

			## Pull from any pool member that has surplus.
			for nj: int in members:
				if nj == zi or deficit <= 0.0:
					continue
				var nj_cap:  float = float(zone_info[nj]["local_cap"])
				var nj_draw: float = float(zone_info[nj]["local_draw"])
				var nj_exp:  float = float(zone_info[nj]["exported_w"])
				var avail: float = maxf(0.0, nj_cap - nj_draw - nj_exp)
				if avail <= 0.0:
					continue
				var transfer: float = minf(avail, deficit)
				_pmdbg("[PM:EVAL] PASS2 pool%d: %.1fw  Z%d->Z%d (avail=%.1f deficit=%.1f)" % [
					pi, transfer, nj, zi, avail, deficit])
				zone_info[zi]["imported_w"] = float(zone_info[zi]["imported_w"]) + transfer
				zone_info[nj]["exported_w"] = float(zone_info[nj]["exported_w"]) + transfer
				deficit -= transfer
				var imp_from: Array = zone_info[zi]["import_from"]
				if not imp_from.has(nj):
					imp_from.append(nj)
				var exp_to: Array = zone_info[nj]["export_to"]
				if not exp_to.has(zi):
					exp_to.append(zi)


## ──────────────────────────────────────────────────────────────────────────
## PASS 3 — evaluate each zone with net watts (local ± imported/exported).
## ──────────────────────────────────────────────────────────────────────────
## Sets active_draw_watts / total_capacity_watts (accumulated per zone) as a
## side effect, same as the pre-split monolith did. Returns a Dictionary with
## the four aggregate flags/counters the caller's tail section needs:
##   "any_overloaded", "any_offline", "zones_with_device", "zones_offline"
func _evaluate_pass3_zone_resolution(
		n_zones: int,
		zone_node_sets: Array[Dictionary],
		zone_info: Array[Dictionary]) -> Dictionary:
	active_draw_watts    = 0.0
	total_capacity_watts = 0.0

	var any_overloaded:      bool = false
	var any_offline:       bool = false
	var zones_with_device: int  = 0
	var zones_offline:     int  = 0

	for zi: int in n_zones:
		var info: Dictionary    = zone_info[zi]
		if not bool(info["has_device"]):
			continue
		zones_with_device += 1

		var zone_keys: Dictionary = zone_node_sets[zi]

		## ── Sustained-brownout latch ───────────────────────────────────────
		## If this zone's FULL shared component was latched into exhausted
		## brownout (cross-zone gens+battery depleted), keep it brownout
		## regardless of what a foreign zone might momentarily offer — power
		## only returns after a MANUAL generator restart clears the latch.
		## Flood to the full component so every zone in the share produces the
		## SAME signature and all of them stay latched together.
		if not _exhausted_brownout_keys.is_empty():
			var latched_keys: Dictionary = _flood_component_keys(zone_keys)
			if _exhausted_brownout_keys.has(_component_sig_key(latched_keys)):
				_pmdbg("[PM:EVAL]   zone %d: LATCHED (exhausted brownout) — holding full component" % zi)
				_sustained_brownout_component(latched_keys)
				any_overloaded = true
				continue

		## ── Battery classification ─────────────────────────────────────────
		## local_bats  — batteries physically inside this zone.
		## cross_bats  — batteries in OTHER zones that are BFS-reachable via
		##               _adjacency (which already blocks pass_battery=false
		##               breakers).  Only charged, reachable batteries qualify.
		var local_bats:       Array[Dictionary] = []
		var cross_bats:       Array[Dictionary] = []
		var local_bat_charge: float             = 0.0

		## Collect one snap_key per local zone node (for BFS origin seeds).
		var zone_key_list: Array[String] = []
		for zk: String in zone_keys:
			zone_key_list.append(zk)

		for bat: Dictionary in _batteries.values():
			if not bat.get("enabled", true):
				continue
			var bcharge: float = float(bat.get("charge_wh", 0.0))
			var bat_key: String = ""
			var is_local: bool = false

			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
					bat_key = wn.get("key", "")
					if zone_keys.has(bat_key):
						is_local = true
					break

			if is_local:
				local_bats.append(bat)
				local_bat_charge += bcharge
			elif bcharge > 0.0 and not bat_key.is_empty():
				## Cross-zone battery — only valid if reachable through _adjacency
				## (i.e. all breakers between us have pass_battery=true).
				var bat_reachable: bool = false
				for seed: String in zone_key_list:
					if _adjacency_bfs_can_reach(seed, bat_key):
						bat_reachable = true
						break
				if bat_reachable:
					cross_bats.append(bat)

		var any_bat_charge: float = local_bat_charge
		for cb: Dictionary in cross_bats:
			any_bat_charge += float(cb.get("charge_wh", 0.0))

		## ── Effective watts ────────────────────────────────────────────────
		## Exported watts count as extra load on this zone (own-zone stress rule).
		## Imported watts reduce the effective deficit.
		var exported_w:   float = float(info["exported_w"])
		var imported_w:   float = float(info["imported_w"])
		var local_cap:    float = float(info["local_cap"])
		var local_draw:   float = float(info["local_draw"])

		## Effective draw this zone must cover = own draw + any exports committed.
		var effective_draw: float = local_draw + exported_w
		## Net deficit = what we still need after imports.
		var net_deficit: float   = effective_draw - local_cap - imported_w

		## Accumulate global totals (local gen cap + local consumer draw, no double-count).
		total_capacity_watts += local_cap
		active_draw_watts    += local_draw



		_pmdbg("[PM:EVAL] PASS3 zone %d: local_cap=%.1f local_draw=%.1f imported=%.1f exported=%.1f net_deficit=%.1f local_bats=%d cross_bats=%d any_bat_charge=%.1f" % [
			zi, local_cap, local_draw, imported_w, exported_w, net_deficit,
			local_bats.size(), cross_bats.size(), any_bat_charge])
		## ── No local capacity and no import: battery or cut ───────────────
		if local_cap <= 0.0 and imported_w <= 0.0:
			if local_draw <= 0.0:
				_pmdbg("[PM:EVAL]   zone %d: empty (no cap, no draw)" % zi)
				continue   ## Empty zone.
			if any_bat_charge > 0.0:
				_pmdbg("[PM:EVAL]   zone %d: no gen, using battery" % zi)
				_activate_discharge_for_component(local_bats, cross_bats)
				_shed_in_component(zone_keys, 0.0)
				any_overloaded = true
			else:
				_pmdbg("[PM:EVAL]   zone %d: CUT (no gen, no battery)" % zi)
				_cut_consumers_in_zone(zone_keys)
				any_offline = true
				zones_offline += 1
			continue

		## ── Zone is healthy (net_deficit ≤ 0): maybe unshed ───────────────
		## net_deficit is computed from the CURRENT (post-shed) draw, where shed
		## items count at residual (0w).  A zone can therefore read "healthy"
		## purely BECAUSE items are shed.  Un-shedding then restores full draw,
		## re-overloads, re-sheds next solve → shed↔unshed oscillation + false
		## OVERLOADED flicker.  So only un-shed when the FULL restored draw
		## (every shed item back at full watts) still fits under available
		## capacity (own cap + imports).  Otherwise hold the shed: the grid is
		## genuinely at-capacity and stays ONLINE with load-shedding active.
		if net_deficit <= 0.0:
			var avail_cap: float = local_cap + imported_w - exported_w
			var full_draw: float = _component_draw_unshed(zone_keys)
			if full_draw <= avail_cap:
				_pmdbg("[PM:EVAL]   zone %d: HEALTHY+UNSHED (net_deficit=%.1f full_draw=%.1f avail=%.1f)" % [zi, net_deficit, full_draw, avail_cap])
				_unshed_component(zone_keys)
			else:
				## Full unshed draw exceeds cap — try to restore the highest-
				## priority items that individually fit (partial unshed).  Items
				## that won't fit stay shed.  Stable: we only commit what fits,
				## so the next solve sees the same committed_draw and makes the
				## same decision → no oscillation.
				_pmdbg("[PM:EVAL]   zone %d: AT-CAPACITY, partial unshed (net_deficit=%.1f full_draw=%.1f avail=%.1f)" % [zi, net_deficit, full_draw, avail_cap])
				_partial_unshed_component(zone_keys, avail_cap)
			continue

		## ── Zone has deficit: try backups first ───────────────────────────
		var zone_capacity: float = local_cap
		var zone_draw:     float = local_draw

		var backups_started: bool = false
		for gen: Dictionary in _generators.values():
			if not gen.get("backup", false) or gen.get("running", false):
				continue
			if float(gen.get("fuel", 0.0)) <= 0.0 or float(gen.get("health", 0.0)) <= 0.0:
				continue
			for wn: Dictionary in _wire_nodes.values():
				if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
					if zone_keys.has(wn["key"]):
						gen["running"]      = true
						gen["auto_started"] = true
						var gn: Node = _safe_dict_node(gen)
						if gn != null and is_instance_valid(gn) and gn.has_method("set_running"):
							gn.set_running(true)
						generator_started.emit(gen["id"])
						_recalculate_capacity()
						backups_started = true
					break
		if backups_started:
			zone_capacity = _component_capacity(zone_keys)
			zone_draw     = _component_draw(zone_keys)
			total_capacity_watts += zone_capacity - local_cap   ## add backup delta
			## Recompute net deficit after backups.
			net_deficit = (zone_draw + exported_w) - zone_capacity - imported_w

		## ── Shed lights to close the gap ─────────────────────────────────
		## Effective capacity available to this zone = own cap + imports.
		var effective_cap: float = zone_capacity + imported_w - exported_w
		## Did we have to shed anything this pass to fit under capacity?  If so,
		## the zone is at-capacity and must STAY shed — the final else branch
		## below must NOT unshed it (doing so caused a shed↔unshed oscillation
		## that flickered the grid into a false OVERLOADED state every solve).
		var shed_this_pass: bool = false
		if net_deficit > 0.0:
			var pre_shed_draw: float = zone_draw
			zone_draw = _shed_in_component(zone_keys, effective_cap)
			shed_this_pass = zone_draw < pre_shed_draw
			net_deficit = (zone_draw + exported_w) - zone_capacity - imported_w

		## ── Final: battery or cut ─────────────────────────────────────────
		if net_deficit > 0.0:
			if any_bat_charge > 0.0:
				_activate_discharge_for_component(local_bats, cross_bats)
				any_overloaded = true
			else:
				## Distinguish CROSS-ZONE share from a STANDALONE zone:
				##   • Cross-zone = this zone imports power from, or exports
				##     power to, a foreign zone across a pass-through breaker
				##     (imported_w > 0 OR exported_w > 0).  Its exhaustion goes
				##     to SUSTAINED BROWNOUT (orange, gens tripped, latched) —
				##     NOT fully offline — per the cross-zone decisions.
				##   • Standalone (own gen, no battery, no import/export) keeps
				##     the original OFFLINE cut behavior.
				var is_cross_zone: bool = imported_w > 0.0 or exported_w > 0.0
				if is_cross_zone:
					## Expand to the FULL shared component (every zone bridged by
					## non-tripped pass-through breakers — scales to N zones), so
					## the exporter's generator (in a DIFFERENT zone) actually
					## trips and ALL shared zones brown out together.
					var comp_keys: Dictionary = _flood_component_keys(zone_keys)
					## ── Upgraded ("smart") breaker pre-empt ────────────────────
					## If an UPGRADED breaker sits in this component, untripped,
					## and currently passing power, it self-trips to ISOLATE the
					## two sides instead of the standard multi-zone sustained
					## brownout.  The generator side keeps running (untouched);
					## only THIS deficit zone (which has no gen/battery of its
					## own — it was piggybacking) goes OFFLINE, same as a
					## standalone zone with no source.  The severed adjacency
					## only takes effect on the NEXT solve (this pass already
					## computed sharing with the old topology), so we flag
					## _needs_resolve to re-evaluate cleanly next frame with the
					## breaker isolated.
					var upgraded_ids: Array[String] = _find_upgraded_breakers_in_component(comp_keys)
					if not upgraded_ids.is_empty():
						## Group key ties every sibling breaker that self-tripped
						## FROM THIS SAME EXHAUSTION EVENT together, so a group
						## reset (see _reset_upgraded_breaker_group) can find and
						## reset all of them at once instead of leaving some stuck.
						var trip_group_key: String = _component_sig_key(comp_keys)
						_pmdbg("[PM:EVAL]   zone %d: CROSS-ZONE EXHAUSTED -> UPGRADED breaker(s) %s self-trip, isolating (imp=%.1f exp=%.1f) group=%s" % [zi, str(upgraded_ids), imported_w, exported_w, trip_group_key])
						for ubid: String in upgraded_ids:
							_self_trip_upgraded_breaker(ubid, trip_group_key)
						_cut_consumers_in_zone(zone_keys)
						any_offline = true
						zones_offline += 1
						_needs_resolve = true   ## re-solve next frame with breaker isolated
					else:
						_pmdbg("[PM:EVAL]   zone %d: CROSS-ZONE EXHAUSTED -> sustained brownout FULL component (%d nodes, imp=%.1f exp=%.1f)" % [zi, comp_keys.size(), imported_w, exported_w])
						_sustained_brownout_component(comp_keys)
						any_overloaded = true   ## brownout, not offline
				else:
					_cut_consumers_in_zone(zone_keys)
					any_offline = true
					zones_offline += 1
		else:
			## Backups or shedding resolved the deficit (net_deficit ≤ 0).
			## Per the locked shed-before-battery policy: shed load is the
			## LAST line of defense before the battery, so once shedding has
			## fired we keep it shed and the grid stays ONLINE (with a load-
			## shedding badge) — we do NOT unshed just because the reduced
			## draw now fits under capacity, or it would immediately re-power,
			## overload again, and oscillate.  Only unshed when the zone fits
			## entirely WITHOUT any shed this pass (genuinely healthy).
			if shed_this_pass:
				## At-capacity, holding shed.  Grid is ONLINE, not OVERLOADED —
				## load shedding is doing its job and the deficit is gone.
				pass
			else:
				_unshed_component(zone_keys)

	return {
		"any_overloaded":   any_overloaded,
		"any_offline":      any_offline,
		"zones_with_device": zones_with_device,
		"zones_offline":    zones_offline,
	}



## ── Activate battery discharge for a component in deficit/overload ───────────
## Stops charging and starts discharging on local batteries first.
## If local charge is zero, falls through to cross-zone batteries.
## Called inline from _evaluate_per_component() — never trips the global grid.
func _activate_discharge_for_component(
		local_bats: Array[Dictionary],
		cross_bats: Array[Dictionary]) -> void:

	var activated_any: bool = false

	## Local batteries first.
	for bat: Dictionary in local_bats:
		if not bat.get("enabled", true):
			continue
		if float(bat.get("charge_wh", 0.0)) <= 0.0:
			continue
		if not bat.get("discharging", false):
			bat["discharging"] = true
			bat["charging"]    = false
			battery_state_changed.emit(bat["id"], true)
			_notify_battery_mode(bat["id"])
			_notify_battery_node(bat["id"])
		elif bat.get("charging", false):
			## Was charging — flip it.
			bat["charging"] = false
			_notify_battery_mode(bat["id"])
			_notify_battery_node(bat["id"])
		activated_any = true

	## If local batteries are empty, fall through to cross-zone.
	if not activated_any:
		for bat: Dictionary in cross_bats:
			if not bat.get("enabled", true):
				continue
			if float(bat.get("charge_wh", 0.0)) <= 0.0:
				continue
			if not bat.get("discharging", false):
				bat["discharging"] = true
				bat["charging"]    = false
				battery_state_changed.emit(bat["id"], true)
				_notify_battery_mode(bat["id"])
				_notify_battery_node(bat["id"])


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
			active_draw_watts += _shed_residual_watts(c)
	for bat: Dictionary in _batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			active_draw_watts += BATTERY_CHARGE_WATTS


func _evaluate_grid_state() -> void:
	pass  ## Replaced by _evaluate_per_component(). Stub preserved for compile safety.


func _attempt_load_shed(_deficit: float) -> void:
	pass  ## Replaced by _evaluate_per_component(). Stub preserved for compile safety.


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

	## No local batteries with charge → true blackout.
	_flickering = false
	var old: GridState = grid_state
	grid_state = GridState.OFFLINE
	grid_state_changed.emit(grid_state, old)
	grid_offline.emit()
	grid_tripped.emit()
	_cut_all_consumers()



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
