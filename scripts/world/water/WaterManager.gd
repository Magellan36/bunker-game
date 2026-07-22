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

## Purifier clean-pulse + dual quality/purity arrows (Jul 2026) — per-consumer
## purity memory across recomputes, keyed by consumer node key, so
## recompute_flow_directions() can detect an impure->pure FLIP (as opposed to
## just a current-state snapshot) and fire the purifier pulse VFX exactly
## once per event. See _process_purity_and_dual_arrows().
var _last_purity_state: Dictionary = {}   ## consumer_key (String) -> bool (true = pure)

## True once _last_purity_state has been populated at least once. Guards the
## very first recompute (fresh game start OR right after a save load) from
## reading every already-pure consumer as a fresh "flip" and firing a false
## burst of pulses — see _process_purity_and_dual_arrows()'s seeding branch.
var _purity_state_seeded: bool = false

## Quality-arrow live-refresh cache (Jul 2026 fix — "arrows only show green"
## bug). ROOT CAUSE: recompute_flow_directions() (the only place that ever
## pushed WaterPipeSegment.set_quality_color()) only runs on graph MUTATIONS
## (place/delete/undo/etc), but WaterHookup.water_quality decays continuously
## every frame in WaterHookup._process() — so the arrow color was pushed once
## (usually at/near 100%, hence "always green") and never touched again as
## quality drifted down in real time. Fix: cache the last-resolved reachable-
## edge set + is_purified map here, then _process() below cheaply re-pushes
## JUST the quality_color uniform on a short interval using the CURRENT live
## hookup_quality — no graph walk, no flow_sign/phase_offset/has_flow re-push
## (those are still only touched by an actual mutation, unchanged).
var _last_reachable_edges: Dictionary = {}   ## edge_id (String) -> true
var _last_edge_purity: Dictionary = {}       ## edge_id (String) -> bool (is_purified)
var _last_hookup_key: String = ""
var _quality_refresh_accum: float = 0.0
const QUALITY_REFRESH_INTERVAL: float = 0.5   ## real seconds — cheap, decay is gradual

func _ready() -> void:
	_graph  = WaterGraph.new(self)
	_solver = WaterSolver.new(_graph)

func _process(delta: float) -> void:
	_quality_refresh_accum += delta
	if _quality_refresh_accum < QUALITY_REFRESH_INTERVAL:
		return
	_quality_refresh_accum = 0.0
	_refresh_quality_colors()

## Cheap per-interval re-tint of every reachable pipe segment's quality lane
## using the hookup's CURRENT (live-decaying) water_quality — does not touch
## flow_sign/phase_offset/has_flow and does not re-run any graph BFS; reuses
## the reachable-edge set + is_purified map cached by the last
## recompute_flow_directions() pass (see its cache-write at the bottom of
## that function). No-ops harmlessly if no recompute has run yet.
func _refresh_quality_colors() -> void:
	if _last_hookup_key.is_empty() or _last_reachable_edges.is_empty():
		return
	var hookup_ref: WaterHookup = _find_hookup_by_key(_last_hookup_key)
	if hookup_ref == null:
		return
	var hookup_quality: float = hookup_ref.water_quality
	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		if not _last_reachable_edges.has(seg.edge_id):
			continue
		var is_purified: bool = bool(_last_edge_purity.get(seg.edge_id, false))
		var quality_pct: float = 100.0 if is_purified else hookup_quality
		if seg.has_method("set_quality_color"):
			seg.set_quality_color(WaterQualityColor.get_color(quality_pct))


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

## Forwards to WaterGraph.prune_orphan_waypoint() — see there for contract.
## Call after unregister_edge() with the edge's former endpoint keys to clean
## up degree-0 "corner"/"pipe_joint" nodes left dangling (Jul 2026 fix, stops
## stale nodes from persisting as snap targets after a pipe is undone).
func prune_orphan_waypoint(key: String) -> void:
	_graph.prune_orphan_waypoint(key)

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

## Returns the single registered WaterHookup, or null if none exists yet.
## Only one hookup is ever supported (see register_hookup()'s guard) —
## added for AdminMenu.gd's F7 water-quality cheat buttons (Jul 2026), which
## need direct access to the hookup without going through a graph key.
func get_the_hookup() -> WaterHookup:
	for h: Node3D in _hookups:
		if is_instance_valid(h):
			return h as WaterHookup
	return null

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

	## Purifier (Jul 2026) — pure (100%) iff EVERY path from the hookup to
	## this consumer passes through at least one "purifier" node. Computed
	## as "reachable via the unfiltered graph, but NOT in the filtered
	## contaminated-set" — see WaterGraph.get_unpurified_reachable_keys().
	var is_pure: bool = not _graph.get_unpurified_reachable_keys(hookup_key).has(consumer_node_key)

	out["connected"]     = true
	out["mL_per_day"]    = rate_day
	out["mL_per_minute"] = rate_day / 1440.0
	out["quality"]       = 100.0 if is_pure else hookup.water_quality
	return out

## Returns { "connected": bool, "quality": float } — the RAW (pre-purification)
## quality of whichever hookup upstream-feeds `node_key`, regardless of how
## many purifiers sit between them. Used by WaterInfoUI's purifier panel to
## show "what's arriving before this unit treats it" — distinct from
## get_received_rate_mL()'s "quality" field, which is the POST-purification
## value a downstream consumer actually receives.
func get_upstream_raw_quality(node_key: String) -> Dictionary:
	var out: Dictionary = {"connected": false, "quality": 0.0}
	if node_key.is_empty():
		return out
	var hookup_key: String = _graph.find_reachable_hookup_key(node_key)
	if hookup_key.is_empty():
		return out
	var hookup: WaterHookup = _find_hookup_by_key(hookup_key)
	if hookup == null:
		return out
	out["connected"] = true
	out["quality"]   = hookup.water_quality
	return out


# ─── Generalized edge delete + refund (Jul 2026, Purifier pass) ──────────────
## Deletes one pipe edge and refunds whatever its visual segment cost to
## place (WaterPipeSegment.placement_cost). Generalized out of
## WaterHookup._delete_and_refund_edge() so both the hookup's reposition path
## AND purifier-adjacent deletion paths call the same, already-debugged
## logic instead of a second copy silently drifting from the first.
##
## GUARD (per design decision): refuses to delete an edge touching a node
## still marked role == "purifier" — a purifier must be deconstructed first
## (which reverts its node role back to "corner", see WaterPurifier.gd)
## before either of its edges can be torn down. Returns false (no-op) when
## refused, true when the edge was actually deleted.
func delete_and_refund_edge(edge_id: String) -> bool:
	if not _graph.has_edge(edge_id):
		return false
	var edge_data: Dictionary = _graph.get_edges().get(edge_id, {})
	var key_a: String = edge_data.get("a", "")
	var key_b: String = edge_data.get("b", "")
	if _graph.get_node(key_a).get("role", "") == "purifier" \
			or _graph.get_node(key_b).get("role", "") == "purifier":
		return false   ## refused — purifier must be removed first

	var seg: WaterPipeSegment = find_pipe_visual(edge_id)
	var refund: int = 0
	var refund_pos: Vector3 = Vector3.ZERO
	if seg != null:
		refund = seg.placement_cost
		refund_pos = (seg.point_a + seg.point_b) * 0.5
		seg.queue_free()
	_graph.unregister_edge(edge_id)
	_graph.prune_orphan_waypoint(key_a)
	_graph.prune_orphan_waypoint(key_b)
	if refund > 0:
		var world_node: Node = get_tree().get_first_node_in_group("main_world")
		if world_node != null and world_node.has_method("add_cash"):
			world_node.add_cash(refund)
			var camera: Camera3D = get_viewport().get_camera_3d()
			if camera != null:
				var screen_pos: Vector2 = camera.unproject_position(refund_pos)
				var main_hud: Node = world_node.get_node_or_null("HUD")
				if main_hud != null and main_hud.has_method("spawn_float_label"):
					main_hud.spawn_float_label(screen_pos, refund, true)
	recompute_flow_directions()
	return true

## Finds the live WaterPipeSegment visual for `edge_id` — same
## "water_pipe_visual" group lookup WaterHookup._find_pipe_visual() used
## before this was generalized.
func find_pipe_visual(edge_id: String) -> WaterPipeSegment:
	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if is_instance_valid(node) and node is WaterPipeSegment and (node as WaterPipeSegment).edge_id == edge_id:
			return node as WaterPipeSegment
	return null


# ─── Flow-direction arrows (build-mode only, Jul 2026) ───────────────────────
## Recomputes flow direction for every edge reachable from the (single) real
## hookup and pushes the result to every live WaterPipeSegment's shader via
## set_flow_sign(). Called after any pipe-graph mutation (placement, split,
## purifier insertion, edge delete/refund, undo) — NOT every frame.
func recompute_flow_directions() -> void:
	var hookup_keys: Array[String] = _graph.get_hookup_keys()
	## TEMP debug (Jul 2026, arrow-regression investigation) — remove once
	## root cause of "arrows stopped working entirely" is found and fixed.
	var visual_count: int = get_tree().get_nodes_in_group("water_pipe_visual").size()
	print("[FlowDebug] recompute: hookups=%d  edges=%d  nodes=%d  visuals=%d" % [
		hookup_keys.size(), _graph.get_edges().size(), _graph.get_nodes().size(), visual_count])
	if hookup_keys.is_empty():
		print("[FlowDebug] ABORT: no hookup registered")
		return
	var directions: Dictionary = _graph.compute_flow_directions(hookup_keys[0])
	print("[FlowDebug] directions computed for hookup=%s -> %d edge(s) reachable" % [
		hookup_keys[0], directions.size()])

	## Purifier clean-pulse + dual quality/purity arrows (Jul 2026) — computed
	## ONCE here (not per-segment below) so the per-edge is_purified/
	## quality_pct lookups used in the push loop right after are cheap dict
	## reads, not repeated graph walks.
	var edge_purity: Dictionary = _process_purity_and_dual_arrows(hookup_keys[0], directions)

	var hookup_quality: float = 100.0
	var hookup_ref: WaterHookup = _find_hookup_by_key(hookup_keys[0])
	if hookup_ref != null:
		hookup_quality = hookup_ref.water_quality

	## Refresh the live quality-color cache (Jul 2026 fix) — see
	## _refresh_quality_colors()'s own header for why this exists. Reset here
	## on every mutation so a deleted/rerouted edge can't linger in the cache
	## and keep getting re-tinted by the interval refresh after it's gone.
	_last_hookup_key       = hookup_keys[0]
	_last_reachable_edges  = {}
	_last_edge_purity      = edge_purity
	_quality_refresh_accum = 0.0   ## avoid a stale-color flash before the next interval tick

	for node: Node in get_tree().get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		if not directions.has(seg.edge_id):
			## Not reachable from any hookup — dead/orphaned pipe run, no
			## water in it. No arrow animation at all (July 2026 fix; see
			## pipe_flow.gdshader's has_flow uniform).
			if seg.has_method("set_has_flow"):
				seg.set_has_flow(false)
			continue
		_last_reachable_edges[seg.edge_id] = true
		var edge_flow: Dictionary = directions[seg.edge_id]
		if seg.has_method("set_flow_sign"):
			seg.set_flow_sign(bool(edge_flow.get("a_is_upstream", true)))
		if seg.has_method("set_phase_offset"):
			seg.set_phase_offset(float(edge_flow.get("phase_offset", 0.0)))
		if seg.has_method("set_has_flow"):
			seg.set_has_flow(true)

		## Dual quality/purity arrow lanes (Jul 2026) — PERMANENT default for
		## every reachable pipe segment, not just purified ones (Brannon's
		## confirmed answer). quality_pct is 100.0 downstream of a purifier,
		## else the hookup's own raw decayed quality. NOTE: this same
		## quality_pct/set_quality_color push is ALSO done continuously by
		## _refresh_quality_colors() (Jul 2026 fix) — kept here too so a
		## fresh/mutated segment shows the correct color immediately instead
		## of waiting up to QUALITY_REFRESH_INTERVAL for the next tick.
		var is_purified: bool = bool(edge_purity.get(seg.edge_id, false))
		var quality_pct: float = 100.0 if is_purified else hookup_quality
		if seg.has_method("set_quality_color"):
			seg.set_quality_color(WaterQualityColor.get_color(quality_pct))
		if seg.has_method("set_purified"):
			seg.set_purified(is_purified)


## Purifier clean-pulse + dual quality/purity arrows (Jul 2026 — see the
## purifier-pulse plan doc). Called once per recompute_flow_directions()
## pass, reusing `directions` (already computed this pass by
## WaterGraph.compute_flow_directions() — no second flow-direction
## resolution here, just a linear pass over its already-resolved result) plus
## WaterGraph.get_unpurified_reachable_keys() (the existing, already-correct
## per-consumer purity check). Returns edge_id -> bool (is_purified) for the
## push loop above to consume.
##
## Three things happen here, in order:
## 1. Build a directed adjacency (upstream_key -> [{down, edge_id}]) AND its
##    reverse (down_key -> {up, edge_id}) from `directions` + get_edges() —
##    the same up/down split compute_flow_directions() itself derives
##    internally, just rebuilt here from its already-resolved output rather
##    than re-deriving flow direction from scratch.
## 2. Forward BFS from the hookup along that directed graph computing, per
##    edge, whether the water has already passed a "purifier" role node by
##    the time it reaches that edge (is_purified = the edge's own upstream
##    node's outgoing water was already purified, OR that upstream node IS a
##    purifier). This covers every edge in one linear pass.
## 3. Diff current per-consumer purity (via get_unpurified_reachable_keys())
##    against _last_purity_state. For every consumer that just flipped
##    impure->pure, walk the REVERSE adjacency from that consumer back to
##    the hookup collecting every "purifier" node crossed (Brannon's
##    confirmed answer: attribute to EVERY purifier on the path, not just the
##    most-recently-placed one). Pulse each unique purifier collected across
##    ALL flips this pass exactly once (Brannon's confirmed answer: one pulse
##    total per recompute pass, deduped by purifier — not one pulse per
##    consumer that happens to reference it).
func _process_purity_and_dual_arrows(hookup_key: String, directions: Dictionary) -> Dictionary:
	## ── Step 1: directed adjacency (forward + reverse) from `directions` ──
	var directed_adjacency: Dictionary = {}   ## up_key -> Array[{down, edge_id}]
	var reverse_of: Dictionary = {}           ## down_key -> {up, edge_id}
	var all_edges: Dictionary = _graph.get_edges()
	for edge_id: String in directions:
		var edge_data: Dictionary = all_edges.get(edge_id, {})
		var key_a: String = edge_data.get("a", "")
		var key_b: String = edge_data.get("b", "")
		if key_a.is_empty() or key_b.is_empty():
			continue
		var a_is_upstream: bool = bool(directions[edge_id].get("a_is_upstream", true))
		var up_key: String = key_a if a_is_upstream else key_b
		var down_key: String = key_b if a_is_upstream else key_a
		if not directed_adjacency.has(up_key):
			directed_adjacency[up_key] = []
		directed_adjacency[up_key].append({ "down": down_key, "edge_id": edge_id })
		reverse_of[down_key] = { "up": up_key, "edge_id": edge_id }

	## ── Step 2: forward BFS computing is_purified per edge ──────────────────
	var edge_is_purified: Dictionary = {}   ## edge_id -> bool
	var node_out_purified: Dictionary = { hookup_key: false }   ## node_key -> bool (water LEAVING this node is purified)
	var bfs_queue: Array = [hookup_key]
	while not bfs_queue.is_empty():
		var cur: String = bfs_queue.pop_front()
		var cur_role: String = _graph.get_node(cur).get("role", "")
		var cur_out_purified: bool = bool(node_out_purified.get(cur, false)) or cur_role == "purifier"
		for link: Dictionary in directed_adjacency.get(cur, []):
			edge_is_purified[link["edge_id"]] = cur_out_purified
			var down_key: String = link["down"]
			if not node_out_purified.has(down_key):
				node_out_purified[down_key] = cur_out_purified
				bfs_queue.append(down_key)

	## ── Step 3: purity-flip diff + purifier pulse attribution ──────────────
	var unpurified_keys: Dictionary = _graph.get_unpurified_reachable_keys(hookup_key)
	var purifiers_to_pulse: Dictionary = {}   ## purifier_key -> true (set, deduped)

	for node_key: String in node_out_purified:
		if _graph.get_node(node_key).get("role", "") != "endpoint":
			continue   ## only real consumers count for the purity-flip/pulse system
		var current_pure: bool = not unpurified_keys.has(node_key)

		if _purity_state_seeded:
			var was_pure: bool = bool(_last_purity_state.get(node_key, false))
			if current_pure and not was_pure:
				## Flip event — walk backward to the hookup collecting every
				## purifier crossed on this consumer's resolved path.
				var walk: String = node_key
				while walk != hookup_key and reverse_of.has(walk):
					var up_key: String = reverse_of[walk]["up"]
					if _graph.get_node(up_key).get("role", "") == "purifier":
						purifiers_to_pulse[up_key] = true
					walk = up_key

		_last_purity_state[node_key] = current_pure

	if not _purity_state_seeded:
		## First-ever recompute (fresh game or right after a save load) —
		## _last_purity_state is now populated from the current state, but no
		## pulses fire this pass. Prevents a false burst on every already-
		## purified consumer the instant the save finishes loading.
		_purity_state_seeded = true
	else:
		for purifier_key: String in purifiers_to_pulse:
			var purifier_node: Node = _find_purifier_by_key(purifier_key)
			if purifier_node != null and purifier_node.has_method("play_clean_pulse"):
				purifier_node.play_clean_pulse()

	return edge_is_purified

## Finds the WaterPurifier instance for a given graph node key — purifier
## nodes are registered without a consumer_ref (see WaterPurifierAttach
## .insert_purifier_at()), so get_consumer_ref() can't find them; scans the
## "water_purifier" group instead, same shape as find_pipe_visual()'s
## "water_pipe_visual" group scan.
func _find_purifier_by_key(purifier_key: String) -> Node:
	for node: Node in get_tree().get_nodes_in_group("water_purifier"):
		if is_instance_valid(node) and node.get("node_key") == purifier_key:
			return node
	return null


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
