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

## Registration-order counter for edges (Jul 2026, loop-direction fix). Godot
## Dictionaries preserve insertion order, but edge_id is order-independent
## (make_edge_id() sorts key_a/key_b lexicographically) so it can't itself be
## used to tell "which of two branches did the player connect first." This
## dict records a monotonically increasing index the FIRST time each edge_id
## is registered (never touched again by the idempotent-existing-edge path in
## register_edge()) — used purely as a tie-break in compute_flow_directions()
## when two loop branches are equally direct. See docs/systems/water/README.md.
var _edge_creation_order: Dictionary = {}   ## edge_id(String) -> int
var _next_edge_order: int = 0


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
	_edge_creation_order[edge_id] = _next_edge_order
	_next_edge_order += 1
	return edge_id

func unregister_edge(edge_id: String) -> void:
	if not _water_edges.has(edge_id):
		return
	var e: Dictionary = _water_edges[edge_id]
	_water_edges.erase(edge_id)
	_edge_creation_order.erase(edge_id)
	if _adjacency.has(e["a"]):
		_adjacency[e["a"]].erase(e["b"])
	if _adjacency.has(e["b"]):
		_adjacency[e["b"]].erase(e["a"])

func has_edge(edge_id: String) -> bool:
	return _water_edges.has(edge_id)

func get_edges() -> Dictionary:
	return _water_edges

## Returns how many edges currently touch `key` (0 if unregistered or isolated).
func node_degree(key: String) -> int:
	return _adjacency.get(key, []).size()

## Cleans up a waypoint node left with zero edges after an unregister_edge()
## call. Only ever removes "corner"/"pipe_joint" roles (pipe-owned bend/split
## points) — never touches "hookup"/"endpoint"/"purifier" roles, which have
## their own lifetime management. No-op if the node still has edges, doesn't
## exist, or isn't a prunable role. Prevents orphaned nodes from persisting
## as stale snap targets after a pipe is undone/removed (Jul 2026 fix).
func prune_orphan_waypoint(key: String) -> void:
	if not _water_nodes.has(key):
		return
	var role: String = _water_nodes[key].get("role", "")
	if role != "corner" and role != "pipe_joint":
		return
	if node_degree(key) > 0:
		return
	_water_nodes.erase(key)
	_adjacency.erase(key)

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


# ─── Purifier — contaminated-set BFS (Jul 2026) ──────────────────────────────
## Returns every node key reachable from `hookup_key` WITHOUT ever traversing
## INTO a node whose role == "purifier". Any consumer key in this set is
## impure (some path from the hookup bypasses every purifier); any consumer
## reachable via the normal unfiltered BFS (is_reachable_from_hookup()) but
## NOT in this set is pure. Mirrors is_reachable_from_hookup()'s exact walk
## shape, just excluding purifier nodes from traversal.
func get_unpurified_reachable_keys(hookup_key: String) -> Dictionary:
	var visited: Dictionary = {}
	if not _water_nodes.has(hookup_key):
		return visited
	visited[hookup_key] = true
	var queue: Array = [hookup_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			var node_data: Dictionary = _water_nodes.get(neighbor, {})
			if node_data.get("role", "") == "purifier":
				continue   ## never traverse INTO a purifier node
			visited[neighbor] = true
			queue.append(neighbor)
	return visited


## Returns every "purifier"-role node key crossed on the BFS-shortest path
## from `hookup_key` to `target_key` (Jul 2026, Purifier Filter plan §3.3 —
## multi-purifier output-quality resolution). Fresh, un-cached BFS every
## call — deliberately NOT sharing/caching WaterManager's directed
## recompute-time adjacency (a plan-suggested alternative): a purifier's
## OWN output quality changes continuously (filter depletion ticks every
## frame, same category of problem the "quality arrow stuck green" bug
## already taught this project to watch for — see docs/systems/water/
## README.md), so the call site always needs a live re-evaluation anyway;
## keeping the TOPOLOGY lookup here uncached too avoids a second, separate
## staleness class entirely and matches this file's own established
## "compute on demand" convention (see get_unpurified_reachable_keys()
## immediately above, same shape). Same graph-walk cost as that function —
## no new expense category, just one more BFS of the same size.
## Only the ONE resolved BFS-shortest path is considered (not every
## possible path) — consistent with how compute_flow_directions() and
## get_unpurified_reachable_keys() already only ever reason about one
## resolved tree, not an exhaustive multi-path search; a rare diamond
## topology takes whichever path BFS visits first, same known limitation
## already documented for the purity-flip/pulse system.
func get_purifiers_on_path(hookup_key: String, target_key: String) -> Array[String]:
	var result: Array[String] = []
	if not _water_nodes.has(hookup_key) or not _water_nodes.has(target_key):
		return result
	var visited: Dictionary = { hookup_key: true }
	var purifiers_so_far: Dictionary = { hookup_key: [] as Array[String] }
	var queue: Array = [hookup_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		var current_purifiers: Array[String] = purifiers_so_far.get(current, [])
		var current_role: String = _water_nodes.get(current, {}).get("role", "")
		var forward_purifiers: Array[String] = current_purifiers.duplicate()
		if current_role == "purifier" and not forward_purifiers.has(current):
			forward_purifiers.append(current)
		## Return AFTER folding current's own purifier role in — Jul 2026 fix.
		## ROOT CAUSE (quality arrow lagging one edge behind the purity arrow):
		## when target_key IS the purifier node itself (the case for the edge
		## immediately downstream of a purifier, whose upstream key is the
		## purifier's own node_key), the old code returned
		## `purifiers_so_far.get(current, [])` here BEFORE current's own role
		## was folded in — so that one edge's quality resolved as if no
		## purifier existed yet, while `_process_purity_and_dual_arrows()`'s
		## own BFS (which folds a node's role in before tagging its outgoing
		## edges) already marked that same edge purified. Result: the purity
		## (blue) arrow switched at the correct spot, the quality-color arrow
		## lagged one edge/segment downstream. Returning `forward_purifiers`
		## here keeps both in sync.
		if current == target_key:
			return forward_purifiers
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			purifiers_so_far[neighbor] = forward_purifiers
			queue.append(neighbor)
	return result
## Returns edge_id -> { "a_is_upstream": bool, "phase_offset": float }.
## `a_is_upstream` true if the edge's stored "a" endpoint is the upstream
## (closer to hookup) side, false if "b" is — consumers use this to decide
## which direction to scroll their arrow shader (WaterPipeSegment.
## set_flow_sign()). `phase_offset` is the REAL-WORLD (Euclidean, not
## hop-count) cumulative pipe distance from the hookup to the edge's upstream
## endpoint, in world units — consumers feed this into WaterPipeSegment.
## set_phase_offset() so the scrolling arrow texture's phase lines up
## seamlessly across joints instead of restarting at 0 on every segment
## (July 2026 arrow continuity fix — hop-count distance is unusable for this,
## only real distance keeps the texture pattern spatially continuous).
## Computed via BFS from the hookup, accumulating real segment length —
## recomputed on demand (WaterManager.recompute_flow_directions()) whenever
## the pipe graph mutates, not every frame.
func compute_flow_directions(hookup_key: String) -> Dictionary:
	if not _water_nodes.has(hookup_key):
		return {}

	## ── Pass 1: BFS spanning tree from the hookup ────────────────────────────
	## distances = real cumulative hookup-distance (used for LCA/branch-length
	## comparison below). parent/tree_edge_of record the spanning tree itself —
	## any edge NOT in tree_edge_of's values is a "closing" edge that turns a
	## tree branch into an actual loop.
	var distances: Dictionary = {}    ## node_key -> float
	var parent: Dictionary = {}       ## node_key -> node_key ("" for hookup)
	var tree_edge_of: Dictionary = {} ## node_key -> edge_id (edge to its parent)
	distances[hookup_key] = 0.0
	parent[hookup_key] = ""
	var queue: Array = [hookup_key]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		var current_pos: Vector3 = _water_nodes.get(current, {}).get("pos", Vector3.ZERO)
		for neighbor: String in _adjacency.get(current, []):
			if distances.has(neighbor):
				continue
			var neighbor_pos: Vector3 = _water_nodes.get(neighbor, {}).get("pos", Vector3.ZERO)
			distances[neighbor] = distances[current] + current_pos.distance_to(neighbor_pos)
			parent[neighbor] = current
			tree_edge_of[neighbor] = make_edge_id(current, neighbor)
			queue.append(neighbor)

	var tree_edge_ids: Dictionary = {}   ## Set of edge_id currently used as tree edges
	for node_key: String in tree_edge_of:
		tree_edge_ids[tree_edge_of[node_key]] = true

	## a_is_upstream (per edge_id) — natural tree direction to start with;
	## closing edges get filled in below during cycle resolution.
	var a_is_upstream: Dictionary = {}
	var closing_edge_ids: Array = []
	for edge_id: String in _water_edges:
		var edge_data: Dictionary = _water_edges[edge_id]
		var key_a: String = edge_data.get("a", "")
		var key_b: String = edge_data.get("b", "")
		if not (distances.has(key_a) and distances.has(key_b)):
			continue   ## unreachable from this hookup — no direction to assign
		if tree_edge_ids.has(edge_id):
			a_is_upstream[edge_id] = distances[key_a] <= distances[key_b]
		else:
			closing_edge_ids.append(edge_id)   ## resolved in pass 2

	## ── Pass 2: fundamental-cycle resolution for each closing edge ──────────
	## Process closing edges in creation order (deterministic) so overlapping/
	## nested loops resolve consistently run-to-run. When a closing edge's
	## recessive branch overlaps one already reversed by an earlier-processed
	## (i.e. earlier-created) closing edge, the earlier loop's decision wins —
	## `reversed_tree_edges` guards against re-flipping the same edge twice.
	var ordered_closing: Array = closing_edge_ids.duplicate()
	ordered_closing.sort_custom(func(x, y): return _edge_creation_order.get(x, 0) < _edge_creation_order.get(y, 0))

	var reversed_tree_edges: Dictionary = {}   ## edge_id -> true, already flipped
	for edge_id: String in ordered_closing:
		var edge_data: Dictionary = _water_edges[edge_id]
		var key_a: String = edge_data.get("a", "")
		var key_b: String = edge_data.get("b", "")
		var lca: String = _find_lca(key_a, key_b, parent)
		if lca == "":
			## Endpoints aren't both descendants of a common tree node reachable
			## from this hookup (shouldn't happen given the distances guard
			## above) — fall back to the old local comparison, no reversal.
			a_is_upstream[edge_id] = distances[key_a] <= distances[key_b]
			continue

		if lca == hookup_key:
			## The loop wraps all the way back through the hookup itself —
			## this is a real ring-main topology, not an interior loop. The
			## hookup is a pure source and must NEVER receive an inflow, so
			## its two branches always keep their natural hookup-outward
			## direction (never reversed), exactly like a real ring main
			## being fed from one point and flowing both ways around the
			## ring. The two flows meeting on the far side of the ring is
			## correct physical behavior here, not the convergence bug this
			## pass exists to fix (that bug is specifically about INTERIOR
			## loops that don't touch the hookup — see lca != hookup_key
			## branch below). Only the closing edge's own direction is
			## decided, by the same dominance rule, purely cosmetic here.
			a_is_upstream[edge_id] = distances[key_a] <= distances[key_b]
			continue

		var branch_a_len: float = distances[key_a] - distances[lca]
		var branch_b_len: float = distances[key_b] - distances[lca]
		var a_is_dominant: bool
		if not is_equal_approx(branch_a_len, branch_b_len):
			a_is_dominant = branch_a_len < branch_b_len
		else:
			## Tie — whichever branch's LCA-adjacent tree edge was placed first
			## by the player wins (registration order), per Brannon's call.
			var child_a: String = _direct_child_of_lca(key_a, lca, parent)
			var child_b: String = _direct_child_of_lca(key_b, lca, parent)
			var order_a: int = _edge_creation_order.get(tree_edge_of.get(child_a, ""), 999999999)
			var order_b: int = _edge_creation_order.get(tree_edge_of.get(child_b, ""), 999999999)
			a_is_dominant = order_a <= order_b

		var dominant_key: String = key_a if a_is_dominant else key_b
		var recessive_key: String = key_b if a_is_dominant else key_a

		## Reverse every still-untouched tree edge on the path from the LCA
		## down to the recessive endpoint — the whole spine now flows
		## leaf-to-LCA instead of LCA-to-leaf. Side branches hanging off that
		## spine (not on this path) are untouched, per design.
		var cur: String = recessive_key
		while cur != lca:
			var spine_edge_id: String = tree_edge_of.get(cur, "")
			if spine_edge_id != "" and not reversed_tree_edges.has(spine_edge_id):
				var spine_edge_data: Dictionary = _water_edges[spine_edge_id]
				var natural_a_is_upstream: bool = distances[spine_edge_data["a"]] <= distances[spine_edge_data["b"]]
				a_is_upstream[spine_edge_id] = not natural_a_is_upstream
				reversed_tree_edges[spine_edge_id] = true
			cur = parent.get(cur, lca)

		## Closing edge itself flows from the dominant endpoint into the
		## (now-reversed) recessive endpoint, completing one continuous loop.
		a_is_upstream[edge_id] = (dominant_key == key_a)

	## ── Pass 3: phase_offset via a second pass following FINAL directions ───
	## Raw hookup-BFS distance is wrong for reversed edges (their true
	## "distance traveled along the actual flow path" differs once reversed).
	## Walk the graph again, this time strictly following each edge's final
	## upstream->downstream direction, accumulating real distance as we go.
	var directed_adjacency: Dictionary = {}   ## upstream_key -> Array[{down, edge_id, len}]
	for edge_id: String in a_is_upstream:
		var edge_data: Dictionary = _water_edges[edge_id]
		var key_a: String = edge_data.get("a", "")
		var key_b: String = edge_data.get("b", "")
		var up_key: String = key_a if a_is_upstream[edge_id] else key_b
		var down_key: String = key_b if a_is_upstream[edge_id] else key_a
		var up_pos: Vector3 = _water_nodes.get(up_key, {}).get("pos", Vector3.ZERO)
		var down_pos: Vector3 = _water_nodes.get(down_key, {}).get("pos", Vector3.ZERO)
		if not directed_adjacency.has(up_key):
			directed_adjacency[up_key] = []
		directed_adjacency[up_key].append({ "down": down_key, "edge_id": edge_id, "len": up_pos.distance_to(down_pos) })

	var flow_dist: Dictionary = { hookup_key: 0.0 }
	var dqueue: Array = [hookup_key]
	while not dqueue.is_empty():
		var current2: String = dqueue.pop_front()
		for link: Dictionary in directed_adjacency.get(current2, []):
			var down_key2: String = link["down"]
			if flow_dist.has(down_key2):
				continue
			flow_dist[down_key2] = flow_dist[current2] + link["len"]
			dqueue.append(down_key2)

	var result: Dictionary = {}
	for edge_id: String in a_is_upstream:
		var edge_data: Dictionary = _water_edges[edge_id]
		var key_a: String = edge_data.get("a", "")
		var key_b: String = edge_data.get("b", "")
		var up_key: String = key_a if a_is_upstream[edge_id] else key_b
		## Fall back to raw hookup distance if the directed walk somehow never
		## reached this edge's upstream node (defensive — shouldn't happen for
		## a fully hookup-connected graph).
		var phase_offset: float = flow_dist.get(up_key, distances.get(up_key, 0.0))
		result[edge_id] = { "a_is_upstream": a_is_upstream[edge_id], "phase_offset": phase_offset }
	return result

## Walks parent pointers from both `node_a` and `node_b` to find their lowest
## common ancestor in the BFS spanning tree. Returns "" if none found (should
## only happen if one of the nodes isn't actually in the tree).
func _find_lca(node_a: String, node_b: String, parent: Dictionary) -> String:
	var ancestors_a: Dictionary = {}
	var cur: String = node_a
	while cur != "":
		ancestors_a[cur] = true
		cur = parent.get(cur, "")
	cur = node_b
	while cur != "":
		if ancestors_a.has(cur):
			return cur
		cur = parent.get(cur, "")
	return ""

## Walks parent pointers up from `node` until reaching the tree-child of
## `lca` that leads toward `node` — i.e. the first node below `lca` on that
## branch. Used only for the registration-order tie-break.
func _direct_child_of_lca(node: String, lca: String, parent: Dictionary) -> String:
	var cur: String = node
	while parent.get(cur, "") != lca and parent.get(cur, "") != "":
		cur = parent[cur]
	return cur


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
