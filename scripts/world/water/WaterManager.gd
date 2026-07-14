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

## Registered hookup nodes (WaterHookup instances) — kept here (not just in
## the graph) so boundary-change events can call back into each hookup's own
## reposition logic. See _on_chunk_deconstructed/_on_chunk_restored below.
var _hookups: Array[Node3D] = []

func _ready() -> void:
	_graph = WaterGraph.new(self)


# ─── Node/edge registration (forwards to WaterGraph) ──────────────────────────
func register_node(pos: Vector3, role: String) -> String:
	return _graph.register_node(pos, role)

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
