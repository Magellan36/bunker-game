extends RefCounted
class_name WaterGraph
## WaterGraph.gd
## ─────────────────────────────────────────────────────────────────────────────
## Node/edge registry + BFS connectivity for the water plumbing system.
## Deliberately mirrors PowerGraph.gd's wire-node/wire-edge shape (see
## docs/systems/power/README.md) so anyone who's worked on the power system
## recognizes this immediately — but this is a STANDALONE data structure, not
## wired into PowerManager/PowerGraph in any way.
##
## No solver-equivalent needed yet (Phase 1 scope) — there's no flow/pressure
## simulation, just "is this endpoint reachable from a hookup" (plain BFS).
## A future WaterSolver.gd would slot in the same way PowerSolver.gd was later
## split out of PowerManager — see docs/systems/power/README.md's own history
## for why this split is done from day one here instead of deferred.
##
## DESIGN — same `_owner` back-reference pattern as the power system's
## PowerGraph/PowerRegistry/PowerSolver split and BuildModeController's Stage
## 10 slices. `_owner: WaterManager` reaches back for nothing right now (this
## graph is fully self-contained), but the pattern is kept consistent so a
## future WaterSolver.gd can be added the same way without restructuring.

var _owner: WaterManager = null

func _init(owner: WaterManager) -> void:
	_owner = owner

## Snap grid — matches WireDrawMode.gd's _WIRE_GRID (0.25 m) as an independent
## constant (NOT shared/coupled to the power system's grid — same starting
## number, own tuning knob, per the plan's "cohesive pattern, not literal
## coupling" guidance).
const SNAP_GRID: float = 0.25

## _water_nodes: node_key(String) -> {
##   "role":         String    -- "hookup" | "pipe_joint" | "corner" | "endpoint"
##   "pos":          Vector3
##   "consumer_ref": Node      -- OPTIONAL, "endpoint" nodes only (WaterSolver.gd,
##                                Jul 2026). Duck-typed contract: the referenced
##                                node implements get_current_demand_mL_per_day()
##                                -> float and exposes a priority: int (1-5)
##                                field. WaterSolver never needs to know or care
##                                which concrete script (WaterTestSink,
##                                WaterDispenser, ...) it's talking to -- same
##                                composition-over-inheritance pattern the power
##                                system's registries already use. null for
##                                every non-endpoint role (hookup/pipe_joint/
##                                corner never carry a consumer_ref).
## }
var _water_nodes: Dictionary = {}

## _water_edges: edge_id(String, "e_%s__%s") -> {
##   "a": node_key(String), "b": node_key(String)
## }
## One edge = one straight WaterPipeSegment. A node can have any number of
## edges touching it (real graph, not a linked list) — see file header.
var _water_edges: Dictionary = {}

## Adjacency cache: node_key -> Array[node_key]. Rebuilt whenever an edge is
## added/removed (cheap at this scale — no incremental diffing needed yet,
## unlike the power system's wire graph which has to handle far larger churn).
var _adjacency: Dictionary = {}


## Converts a world position into the shared snap-grid key format, identical
## in spirit to PowerManager._snap_key() / WireDrawMode._make_free_key() —
## "%d,%d,%d" with rounded grid indices — but computed independently so this
## system has zero runtime dependency on PowerManager.
static func make_node_key(pos: Vector3) -> String:
	var gx: int = roundi(pos.x / SNAP_GRID)
	var gy: int = roundi(pos.y / SNAP_GRID)
	var gz: int = roundi(pos.z / SNAP_GRID)
	return "%d,%d,%d" % [gx, gy, gz]

static func make_edge_id(key_a: String, key_b: String) -> String:
	## Order-independent — same two nodes always produce the same edge id
	## regardless of which one was "a" vs "b" at call time.
	if key_a <= key_b:
		return "e_%s__%s" % [key_a, key_b]
	return "e_%s__%s" % [key_b, key_a]


## Registers a node at `pos` with the given role. Returns its node_key.
## Idempotent — registering the same position twice just updates role/pos
## (and consumer_ref, if provided).
## `consumer_ref` (Jul 2026, WaterSolver groundwork) — optional back-reference
## to the device implementing the demand/priority duck-typed contract (see
## _water_nodes' own comment above). Only meaningful for role == "endpoint";
## harmless to pass null for every other role.
func register_node(pos: Vector3, role: String, consumer_ref: Node = null) -> String:
	var key: String = make_node_key(pos)
	_water_nodes[key] = { "role": role, "pos": pos, "consumer_ref": consumer_ref }
	if not _adjacency.has(key):
		_adjacency[key] = []
	return key

## Returns the consumer_ref stored at `key`, or null if unregistered / not set
## / no longer a valid instance (freed nodes are NOT auto-scrubbed from the
## dict — callers must is_instance_valid() check, same as every other
## Node-ref cache in this codebase, e.g. WaterManager._hookups).
func get_consumer_ref(key: String) -> Node:
	if not _water_nodes.has(key):
		return null
	return _water_nodes[key].get("consumer_ref", null)

func unregister_node(key: String) -> void:
	if not _water_nodes.has(key):
		return
	_water_nodes.erase(key)
	## Remove any edges touching this node.
	var edges_to_remove: Array = []
	for edge_id: String in _water_edges:
		var e: Dictionary = _water_edges[edge_id]
		if e["a"] == key or e["b"] == key:
			edges_to_remove.append(edge_id)
	for edge_id: String in edges_to_remove:
		unregister_edge(edge_id)
	_adjacency.erase(key)

func has_node(key: String) -> bool:
	return _water_nodes.has(key)

func get_node(key: String) -> Dictionary:
	return _water_nodes.get(key, {})

func get_nodes() -> Dictionary:
	return _water_nodes

## Registers an edge (one straight pipe segment) between two already-registered
## node keys. Returns the edge_id, or "" if either node doesn't exist.
func register_edge(key_a: String, key_b: String) -> String:
	if not _water_nodes.has(key_a) or not _water_nodes.has(key_b):
		return ""
	var edge_id: String = make_edge_id(key_a, key_b)
	if _water_edges.has(edge_id):
		return edge_id   ## Already exists — idempotent, same as PowerGraph's convention
	_water_edges[edge_id] = { "a": key_a, "b": key_b }
	_adjacency[key_a].append(key_b)
	_adjacency[key_b].append(key_a)
	return edge_id

func unregister_edge(edge_id: String) -> void:
	if not _water_edges.has(edge_id):
		return
	var e: Dictionary = _water_edges[edge_id]
	_water_edges.erase(edge_id)
	if _adjacency.has(e["a"]):
		_adjacency[e["a"]].erase(e["b"])
	if _adjacency.has(e["b"]):
		_adjacency[e["b"]].erase(e["a"])

func has_edge(edge_id: String) -> bool:
	return _water_edges.has(edge_id)

func get_edges() -> Dictionary:
	return _water_edges

## Returns [{ "edge_id": String, "other_key": String }] for every edge
## touching `key` — used by WaterHookup.update_graph_node_position() (Step 2
## verification pass, July 2026) to preserve and redraw pipe edges across a
## reposition event instead of silently orphaning their visuals when the old
## node (and its edges, via unregister_node()'s cascade) gets torn down.
func get_edges_touching(key: String) -> Array:
	var out: Array = []
	for edge_id: String in _water_edges:
		var e: Dictionary = _water_edges[edge_id]
		if e["a"] == key:
			out.append({ "edge_id": edge_id, "other_key": e["b"] })
		elif e["b"] == key:
			out.append({ "edge_id": edge_id, "other_key": e["a"] })
	return out


## BFS reachability check — true if `node_key` is connected via an unbroken
## chain of edges to ANY node with role == "hookup".
func is_reachable_from_hookup(node_key: String) -> bool:
	if not _water_nodes.has(node_key):
		return false
	if _water_nodes[node_key].get("role", "") == "hookup":
		return true   ## A hookup is trivially "reachable from a hookup" (itself).

	var visited: Dictionary = { node_key: true }
	var queue: Array = [node_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if _water_nodes.has(neighbor) and _water_nodes[neighbor].get("role", "") == "hookup":
				return true
			queue.append(neighbor)
	return false

## Returns the node_key of every "endpoint" node reachable from `hookup_key`
## via BFS. Mirrors count_reachable_endpoints()'s exact walk, just collecting
## keys instead of counting — used by WaterSolver.gd (Jul 2026) to gather the
## live consumer set for its priority-tier waterfall.
func get_reachable_endpoint_keys(hookup_key: String) -> Array[String]:
	var out: Array[String] = []
	if not _water_nodes.has(hookup_key):
		return out
	var visited: Dictionary = { hookup_key: true }
	var queue: Array = [hookup_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if _water_nodes.has(neighbor) and _water_nodes[neighbor].get("role", "") == "endpoint":
				out.append(neighbor)
			queue.append(neighbor)
	return out

## Returns the node_key of every registered hookup (role == "hookup").
func get_hookup_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in _water_nodes:
		if _water_nodes[key].get("role", "") == "hookup":
			out.append(key)
	return out


# ─── Live flow-split (Step 2, July 2026) ─────────────────────────────────────
## BFS from `hookup_key`, counting every reachable node with role ==
## "endpoint" (real connectable devices only — corners/pipe_joints/the
## hookup itself never count). Mirrors is_reachable_from_hookup()'s exact BFS
## shape, just collecting every match across the whole component instead of
## stopping at the first hit.
func count_reachable_endpoints(hookup_key: String) -> int:
	if not _water_nodes.has(hookup_key):
		return 0
	var visited: Dictionary = { hookup_key: true }
	var queue: Array = [hookup_key]
	var count: int = 0
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if _water_nodes.has(neighbor) and _water_nodes[neighbor].get("role", "") == "endpoint":
				count += 1
			queue.append(neighbor)
	return count

## BFS from `from_key` outward, returning the node_key of the first "hookup"
## role node reached — there should only ever be one real hookup in this
## game (see WaterManager.register_hookup()'s defensive guard), so "first
## reached" and "the" hookup are the same thing in practice. Returns "" if no
## hookup is reachable. Mirrors is_reachable_from_hookup()'s exact walk, just
## returning the key instead of a bool.
func find_reachable_hookup_key(from_key: String) -> String:
	if not _water_nodes.has(from_key):
		return ""
	if _water_nodes[from_key].get("role", "") == "hookup":
		return from_key
	var visited: Dictionary = { from_key: true }
	var queue: Array = [from_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if _water_nodes.has(neighbor) and _water_nodes[neighbor].get("role", "") == "hookup":
				return neighbor
			queue.append(neighbor)
	return ""
