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


# ─── Save/Load — pipe network (Jul 2026) ───────────────────────────────────────
## Returns the player-placed pipe network as a JSON-friendly dictionary:
##   { "nodes": [{pos:{x,y,z}, role}],  "edges": [{pos_a, pos_b, cost}] }
## Deliberately excludes "hookup"/"endpoint" roles — those nodes belong to
## WaterHookup/WaterTestSink/WaterDispenser and are recreated by THEIR OWN
## restore (BuildModeController.restore_placed_objects(), phase 1, which runs
## before this — phase 3). Only "corner" and "pipe_joint" nodes (pipe-owned)
## are included here.
func get_pipe_network_for_save() -> Dictionary:
	var nodes_out: Array = []
	for key: String in _graph.get_nodes():
		var n: Dictionary = _graph.get_nodes()[key]
		var role: String = n.get("role", "")
		if role != "corner" and role != "pipe_joint":
			continue
		nodes_out.append({
			"pos":  SaveManager.vec3_to_dict(n.get("pos", Vector3.ZERO)),
			"role": role,
		})

	var edges_out: Array = []
	var visuals: Dictionary = {}   ## edge_id -> WaterPipeSegment, for cost lookup
	for seg: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if seg is WaterPipeSegment:
			visuals[(seg as WaterPipeSegment).edge_id] = seg
	for edge_id: String in _graph.get_edges():
		var e: Dictionary = _graph.get_edges()[edge_id]
		var na: Dictionary = _graph.get_node(e.get("a", ""))
		var nb: Dictionary = _graph.get_node(e.get("b", ""))
		if na.is_empty() or nb.is_empty():
			continue
		var cost: int = 0
		if visuals.has(edge_id):
			cost = (visuals[edge_id] as WaterPipeSegment).placement_cost
		edges_out.append({
			"pos_a": SaveManager.vec3_to_dict(na.get("pos", Vector3.ZERO)),
			"pos_b": SaveManager.vec3_to_dict(nb.get("pos", Vector3.ZERO)),
			"cost":  cost,
		})

	return {"nodes": nodes_out, "edges": edges_out}

## Removes every pipe-owned node (role "corner"/"pipe_joint") + edge from the
## graph, and frees every pipe/elbow visual. Leaves "hookup"/"endpoint" nodes
## (owned by WaterHookup/WaterTestSink/WaterDispenser) untouched — those are
## torn down by BuildModeController.clear_all_player_placed() instead, via
## each device's own _exit_tree(). Mid-session Load only (fresh boot is a
## no-op — nothing to clear).
func clear_water_pipes() -> void:
	for seg: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if is_instance_valid(seg):
			seg.queue_free()
	for elbow: Node in get_tree().get_nodes_in_group("water_pipe_elbow"):
		if is_instance_valid(elbow):
			elbow.queue_free()
	var keys_to_remove: Array = []
	for key: String in _graph.get_nodes():
		var role: String = _graph.get_nodes()[key].get("role", "")
		if role == "corner" or role == "pipe_joint":
			keys_to_remove.append(key)
	for key: String in keys_to_remove:
		_graph.unregister_node(key)   ## also removes touching edges

## Rebuilds the pipe network from get_pipe_network_for_save()'s output.
## Clears any existing pipe-owned nodes/visuals first (safe no-op on a fresh
## boot). Node identity is POSITION, not saved key — WaterGraph.register_node()
## has NO overwrite guard (unlike PowerGraph's), so re-registering at a
## position already held by a hookup/endpoint node would silently steal its
## role and wipe its consumer_ref. We avoid that entirely by checking
## has_water_node() first and skipping registration when a node (device-owned
## or otherwise) already exists at that exact snapped position.
func restore_pipe_network(data: Dictionary) -> void:
	clear_water_pipes()
	var scene_root: Node = get_tree().get_first_node_in_group("main_world")
	if scene_root == null:
		scene_root = get_tree().get_root()

	for saved: Dictionary in data.get("nodes", []):
		var pos: Vector3 = SaveManager.dict_to_vec3(saved.get("pos", {}))
		var role: String = saved.get("role", "pipe_joint")
		var key: String = WaterGraph.make_node_key(pos)
		if has_water_node(key):
			continue   ## already exists (e.g. a device's own node) — don't overwrite
		register_node(pos, role)
		if role == "corner":
			var elbow_script: GDScript = load("res://scripts/world/water/WaterPipeElbow.gd")
			var elbow: Node3D = Node3D.new()
			if elbow_script != null:
				elbow.set_script(elbow_script)
			scene_root.add_child(elbow)
			elbow.global_position = pos
			elbow.set("node_key", key)

	for saved: Dictionary in data.get("edges", []):
		var pos_a: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_a", {}))
		var pos_b: Vector3 = SaveManager.dict_to_vec3(saved.get("pos_b", {}))
		var key_a: String = WaterGraph.make_node_key(pos_a)
		var key_b: String = WaterGraph.make_node_key(pos_b)
		var edge_id: String = register_edge(key_a, key_b)
		if edge_id.is_empty():
			continue
		var seg_script: GDScript = load("res://scripts/world/water/WaterPipeSegment.gd")
		var seg: Node3D = Node3D.new()
		if seg_script != null:
			seg.set_script(seg_script)
		scene_root.add_child(seg)
		seg.set("edge_id", edge_id)
		seg.call("set_endpoints", pos_a, pos_b)
		seg.set("placement_cost", int(saved.get("cost", 0)))


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
