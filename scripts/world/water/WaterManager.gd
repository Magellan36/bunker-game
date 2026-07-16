extends Node
class_name WaterManager
## WaterManager.gd
## ─────────────────────────────────────────────────────────────────────────────
## Orchestrator + public API surface for the water plumbing system (Phase 1:
## hookup + pipe placement/routing only — see the groundwork plan for full
## scope notes). Thin — forwards topology/connectivity work to WaterGraph.gd,
## same split PowerManager/PowerGraph use (see docs/systems/power/README.md).
##
## STANDALONE SYSTEM — not wired into PowerManager/PowerGraph in any way.
## A future dual-dependency device (e.g. water_purifier, which needs both
## electricity AND water) should hold independent references to both
## PowerManager and this WaterManager rather than either manager referencing
## the other — see the groundwork plan §6.
##
## Instantiated and owned by MainWorld.gd exactly the way PowerManager is:
## added to the scene tree, tagged into the "water_manager" group (NOT an
## autoload — this is per-world-instance state), looked up elsewhere via
## `get_tree().get_first_node_in_group("water_manager")` cast to WaterManager.

var _graph: WaterGraph = null

## Priority-tier demand waterfall (Jul 2026) — see WaterSolver.gd. Built
## alongside _graph in _ready(), same lifecycle as PowerManager's own
## solver/graph split.
var _solver: WaterSolver = null

## Registered hookup nodes (WaterHookup instances) — kept here (not just in
## the graph) so boundary-change events can call back into each hookup's own
## reposition logic. See _on_chunk_deconstructed/_on_chunk_restored below.
var _hookups: Array[Node3D] = []

func _ready() -> void:
	_graph  = WaterGraph.new(self)
	_solver = WaterSolver.new(_graph)


# ─── Node/edge registration (forwards to WaterGraph) ──────────────────────────
## `consumer_ref` (Jul 2026, WaterSolver groundwork) — optional back-reference
## to a device implementing the demand/priority duck-typed contract (see
## WaterGraph.register_node()'s own comment). Only meaningful for role ==
## "endpoint"; every other caller can omit it.
func register_node(pos: Vector3, role: String, consumer_ref: Node = null) -> String:
	return _graph.register_node(pos, role, consumer_ref)

func get_consumer_ref(key: String) -> Node:
	return _graph.get_consumer_ref(key)

func unregister_node(key: String) -> void:
	_graph.unregister_node(key)

## Named has_water_node (not has_node) — WaterManager extends Node, and
## Node already defines has_node(NodePath) -> bool; overriding it with an
## incompatible signature is a parse error under Godot 4's strict override
## checking. WaterGraph.has_node() itself is unaffected (RefCounted, no clash).
func has_water_node(key: String) -> bool:
	return _graph.has_node(key)

func get_node_data(key: String) -> Dictionary:
	return _graph.get_node(key)

func register_edge(key_a: String, key_b: String) -> String:
	return _graph.register_edge(key_a, key_b)

func unregister_edge(edge_id: String) -> void:
	_graph.unregister_edge(edge_id)

func has_edge(edge_id: String) -> bool:
	return _graph.has_edge(edge_id)

func get_nodes() -> Dictionary:
	return _graph.get_nodes()

func get_edges() -> Dictionary:
	return _graph.get_edges()

## Forwards to WaterGraph.get_edges_touching() — see that function's own
## comment (Step 2 verification pass, July 2026).
func get_edges_touching(key: String) -> Array:
	return _graph.get_edges_touching(key)

## The one piece of "simulation" this phase needs — BFS from every registered
## hookup. This is what WaterTestSink.gd uses to prove a run is properly
## connected end to end (the acceptance test for this whole phase).
func is_reachable_from_hookup(node_key: String) -> bool:
	return _graph.is_reachable_from_hookup(node_key)

static func make_node_key(pos: Vector3) -> String:
	return WaterGraph.make_node_key(pos)


# ─── Hookup registry + boundary-change reposition dispatch ───────────────────
## Called by WaterHookup._ready(). Not part of the graph node registry above —
## this is a plain node reference list so boundary-change events can call each
## hookup's own reposition method directly.
func register_hookup(hookup: Node3D) -> void:
	if not _hookups.has(hookup):
		## Defensive guard only (Step 2, July 2026) — exactly one hookup is
		## ever expected to exist (auto-placed at game start, see
		## MainWorld._spawn_initial_water_hookup(); the build menu no longer
		## offers a purchasable hookup — see BuildModeHUD.CATEGORIES["Water"]).
		## Not a supported feature to have more than one; this is purely a
		## guard against a future bug reintroducing multi-hookup placement.
		if _hookups.size() >= 1:
			push_warning("WaterManager: a second WaterHookup was registered — only one hookup is supported per game; flow-split math assumes exactly one and will behave unpredictably with more.")
		_hookups.append(hookup)

func unregister_hookup(hookup: Node3D) -> void:
	_hookups.erase(hookup)

## Forwarded by MainWorld from RockSurround.chunk_deconstructed /
## chunk_restored — the SAME boundary-change event WireGraphBuilder already
## listens to for the wire graph's incremental rebuild (see
## docs/systems/world-core/README.md). We deliberately reuse this existing
## event rather than polling or re-deriving boundary detection independently.
##
## BUG FIX (July 2026 playtest pass) — the hookup used to lag exactly one
## expansion behind and end up floating in open air. ROOT CAUSE: a single
## call_deferred("_reposition_all_hookups") only waits for the REST of the
## current frame (after WireGraphBuilder synchronously spawns/removes the new
## wall's StaticBody3D + collider via spawn_structure(), called earlier in
## the same MainWorld._on_chunk_deconstructed()/_on_chunk_restored() chain).
## That's not enough — Godot's physics server doesn't register a newly added
## (or freed) collider for raycast queries until it has actually STEPPED at
## least once after the node entered/left the tree. So the very next
## reposition raycast still saw the OLD collider layout: expansion #1's
## raycast found nothing new (silently left the hookup in place — matches
## "expand once, doesn't move"), then expansion #2's raycast finally saw
## expansion #1's now-physics-registered wall and snapped there — one
## expansion behind, and that spot is open air once expansion #2 clears
## past it (matches "moves back one expansion, still floating").
## FIX: await two physics frames (standard safety margin for this exact
## Godot collider-registration gotcha) before raycasting, instead of a
## single same-frame call_deferred.
func _on_chunk_deconstructed(_chunk_origin: Vector2i) -> void:
	_reposition_all_hookups_after_physics_settles()

func _on_chunk_restored(_chunk_origin: Vector2i) -> void:
	_reposition_all_hookups_after_physics_settles()

func _reposition_all_hookups_after_physics_settles() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reposition_all_hookups()

func _reposition_all_hookups() -> void:
	for hookup: Node3D in _hookups:
		if is_instance_valid(hookup) and hookup.has_method("reposition_to_outer_wall"):
			hookup.reposition_to_outer_wall()


# ─── Demand-based priority-tier allocation (Jul 2026) ────────────────────────
## Supersedes the old Step 2 equal-split logic entirely — every registered
## endpoint now has its own tunable priority + live demand (WaterTestSink,
## WaterDispenser), routed through WaterSolver.gd's waterfall. See that file
## for the full algorithm. Still "compute live, no persistence" — every call
## re-solves from scratch, matching this system's existing pattern.

## Counts nodes with role == "endpoint" reachable from `hookup` via BFS —
## real connectable devices only, corners/pipe joints don't count. Forwards
## to WaterGraph.count_reachable_endpoints() using the hookup's own graph key.
func get_connected_consumer_count(hookup: WaterHookup) -> int:
	if hookup == null:
		return 0
	var key: String = hookup.get_node_key()
	if key.is_empty():
		return 0
	return _graph.count_reachable_endpoints(key)

## Sum of every reachable endpoint's CURRENT requested demand (not what
## they'll actually receive — see WaterSolver.solve_for_hookup() for that).
## Used by the hookup's own info panel to show total requested load vs.
## capacity now that the split is no longer equal.
func get_total_requested_demand_mL(hookup: WaterHookup) -> float:
	if hookup == null:
		return 0.0
	var key: String = hookup.get_node_key()
	if key.is_empty():
		return 0.0
	var total: float = 0.0
	for endpoint_key: String in _graph.get_reachable_endpoint_keys(key):
		var ref: Node = _graph.get_consumer_ref(endpoint_key)
		if ref != null and is_instance_valid(ref) and ref.has_method("get_current_demand_mL_per_day"):
			total += maxf(0.0, float(ref.get_current_demand_mL_per_day()))
	return total

## Finds the WaterHookup instance registered under `hookup_key` — _hookups is
## a plain node-ref list (see file header), so this re-derives each
## registered hookup's own graph key rather than storing a second key->node
## map, since there's only ever one to check in practice (see
## register_hookup()'s guard).
func _find_hookup_by_key(hookup_key: String) -> WaterHookup:
	for h: Node3D in _hookups:
		if not is_instance_valid(h):
			continue
		if h.has_method("get_node_key") and h.get_node_key() == hookup_key:
			return h as WaterHookup
	return null

## Traces back from a consumer's graph node key to whichever hookup feeds it
## (there's only ever one real hookup — see register_hookup()'s guard),
## solves the WHOLE hookup's priority-tier waterfall, and returns this
## specific consumer's actual RECEIVED share (which can be less than what it
## requested, if its tier is oversubscribed or a higher tier consumed
## everything) plus that hookup's water quality (quality shown at a sink/
## dispenser is always the SOURCE hookup's quality — water doesn't gain/lose
## quality in transit through pipes in this pass, see docs/systems/water/
## README.md).
## Returns { "connected": bool, "mL_per_day": float, "mL_per_minute": float,
##           "quality": float }.
func get_received_rate_mL(consumer_node_key: String) -> Dictionary:
	var out: Dictionary = {
		"connected":     false,
		"mL_per_day":    0.0,
		"mL_per_minute": 0.0,
		"quality":       0.0,
	}
	if consumer_node_key.is_empty():
		return out

	var hookup_key: String = _graph.find_reachable_hookup_key(consumer_node_key)
	if hookup_key.is_empty():
		return out

	var hookup: WaterHookup = _find_hookup_by_key(hookup_key)
	if hookup == null:
		return out

	var received_map: Dictionary = _solver.solve_for_hookup(hookup_key, hookup.get_daily_output_mL())
	var rate_day: float = float(received_map.get(consumer_node_key, 0.0))

	out["connected"]     = true
	out["mL_per_day"]    = rate_day
	out["mL_per_minute"] = rate_day / 1440.0
	out["quality"]       = hookup.water_quality
	return out

## A device's dynamic slider maximum (see WaterSolver.get_dynamic_max_for_device()
## for the exact algorithm). Returns 0.0 if the device isn't connected to any
## hookup. `device_priority` is passed in rather than read off consumer_ref
## directly so the UI can preview a not-yet-applied priority change if it
## ever wants to (not used that way currently, but keeps the API honest).
func get_dynamic_max_mL_per_day(consumer_node_key: String, device_priority: int) -> float:
	if consumer_node_key.is_empty():
		return 0.0
	var hookup_key: String = _graph.find_reachable_hookup_key(consumer_node_key)
	if hookup_key.is_empty():
		return 0.0
	var hookup: WaterHookup = _find_hookup_by_key(hookup_key)
	if hookup == null:
		return 0.0
	return _solver.get_dynamic_max_for_device(hookup_key, hookup.get_daily_output_mL(),
			consumer_node_key, device_priority)
