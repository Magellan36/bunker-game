extends RefCounted
class_name PowerGraph
## PowerGraph.gd  —  Stage 5 extraction (review implementation plan)
## ─────────────────────────────────────────────────────────────────────────────
## Wire-node / wire-edge topology CRUD, extracted out of PowerManager.gd.
##
## SCOPE (intentionally narrow for this first extraction pass — see
## REVIEW_IMPLEMENTATION_PLAN.md Stage 5 notes for the reasoning):
##   - Wire node registration/lookup/removal (register_wire_node, get_wire_node_*,
##     has_wire_node_at_pos, unregister_wire_node, _resolve_node_key)
##   - Wire edge registration/removal (register_wire_edge, unregister_wire_edge,
##     has_wire_edge, _remove_wire_edge_internal)
##   - Wire-edge splitting when a breaker lands mid-span (_split_wire_edge_at,
##     _point_on_segment, resplit_breaker — currently unused/dead but kept as
##     a faithful port)
##   - Visual tube spawn/reuse helpers used only by the above
##     (_find_wire_segment_by_edge_id, _spawn_or_reuse_wire_visual)
##   - Pure read accessors (get_wire_nodes, get_wire_edges)
##   - Snap-key helpers (_snap_key, _snapped_pos)
##
## OUT OF SCOPE for this stage (still live in PowerManager.gd):
##   - Breaker registration/trip/reset (register_breaker, unregister_breaker,
##     trip_breaker, reset_breaker, etc.) — these call into this graph's
##     _split_wire_edge_at()/_remove_wire_edge_internal() via _graph, but their
##     own state (_breakers dict) and logic stay in PowerManager.
##   - Zones, adjacency, BFS reachability, and the solver — deferred to a later
##     stage once the codebase can be compile-tested directly in Godot (this
##     sandbox has no Godot binary; every extraction here was done via verbatim
##     line-range slicing + verified diffs, never retyped, to eliminate
##     transcription risk, but a broader zones/solver move is much more
##     interdependent and safer to do with real compile/playtest feedback).
##
## DESIGN — why this ISN'T a full ownership transfer:
## `_wire_nodes` and `_wire_edges` are still declared and physically live as
## PowerManager's own instance vars (NOT moved here). They are referenced from
## ~180 other places scattered across PowerManager's zones/breakers/solver code
## that are staying put in this pass — moving the dicts themselves would mean
## touching all of those call sites too, which is exactly the risk this staged
## approach avoids. Instead, PowerGraph holds a plain back-reference to the
## owning PowerManager (`_owner`) and reaches into `_owner._wire_nodes` /
## `_owner._wire_edges` / `_owner._breakers` directly, plus calls
## `_owner._solve_network()`, `_owner._pmdbg()`, `_owner.get_tree()`, and emits
## `_owner.<signal>` for the handful of signals that stay declared on
## PowerManager (so existing `.connect()` call sites elsewhere are untouched).
## A later stage can complete real ownership transfer once compile-testing is
## available — this stage is a readability/file-size win now, at low risk.
##
## PowerManager holds one instance (`_graph`) and forwards its public wire-node/
## wire-edge API methods to it with IDENTICAL signatures, so every one of the
## ~64 external call sites elsewhere in the codebase (BreakerBox, WallLight,
## GeneratorObject, BuildModeController, MainWorld, etc. — all converted to
## typed `PowerManager` calls in Stage 2) needs ZERO changes.

var _owner: PowerManager = null

const WIRE_GRID_Y: float = 1.0
## MUST match PowerManager.SNAP_GRID — duplicated here rather than referenced
## across the owner boundary since it's a fixed physical constant, not runtime
## state. Stage 9 (DeviceDatabase/config consolidation) is the natural place to
## give constants like this a true single source of truth if desired.
const SNAP_GRID: float = 0.25

func _init(owner: PowerManager) -> void:
	_owner = owner


func register_wire_node(pos: Vector3, role: String, device_id: String = "") -> String:
	_owner._pmdbg("[PM:REG] register_wire_node pos=%s role=%s device_id=%s" % [str(pos), role, device_id])
	## Non-breaker nodes (generators, batteries, consumers, joints) are always
	## normalised to WIRE_GRID_Y so their snap keys land on the same Y plane as
	## the auto-built perimeter grid.  Without this a generator placed at Y≈0.5
	## gets a different iy than perimeter nodes at Y=1.0, making BFS treat them
	## as separate zones even when they share the same XZ column.
	var wire_pos: Vector3 = pos
	if role != "breaker":
		wire_pos = Vector3(pos.x, WIRE_GRID_Y, pos.z)
	var key: String = _snap_key(wire_pos)
	if _owner._wire_nodes.has(key):
		var existing_role: String = _owner._wire_nodes[key].get("role", "")
		## Never overwrite device-owned nodes (breaker, generator, battery) with a
		## plain joint.  PassB1 lays ring joints over the entire perimeter and can
		## collide with a generator or battery that sits on the wall face.  Without
		## this guard the device's device_id is erased → BFS never seeds from it →
		## active_draw=0 even though the grid is fully connected.
		if existing_role in ["breaker", "generator", "battery"]:
			_owner._pmdbg("[PM:REG] SKIP overwrite of %s node key=%s (new role=%s)" % [existing_role, key, role])
			return key
		push_warning("PowerManager: wire node '%s' already exists — updating role." % key)
	_owner._wire_nodes[key] = {
		"key":       key,
		"pos":       _snapped_pos(wire_pos),
		"role":      role,
		"device_id": device_id,
		"reachable": false,
	}
	_owner.wire_node_registered.emit(key)
	_owner._solve_network()
	return key


## Returns the role string of a wire node, or "" if not found.
## Used by MainWorld Pass 0 to avoid unregistering breaker nodes during auto-wire teardown.

func get_wire_node_role(node_key: String) -> String:
	if _owner._wire_nodes.has(node_key):
		return _owner._wire_nodes[node_key].get("role", "")
	return ""


## Returns the snapped world-space position for a wire node, or Vector3.ZERO
## if the key is not found.  Used by MainWorld to snapshot player-wire
## endpoints as positions (stable across rebuilds) instead of PM keys (stale
## after teardown).

func get_wire_node_pos(node_key: String) -> Vector3:
	if _owner._wire_nodes.has(node_key):
		return _owner._wire_nodes[node_key].get("pos", Vector3.ZERO)
	return Vector3.ZERO


## Returns the snap key for the wire node nearest to pos (within SNAP_GRID/2),
## or "" if no node exists at that position.  Used by MainWorld PassD to
## resolve snapshotted positions back to current PM keys after a rebuild.
##
## After a bunker expansion the perimeter ring shifts — a player wire endpoint
## that was on the old ring no longer has an exact match in _owner._wire_nodes.  The
## nearest-XZ fallback below finds the closest surviving perimeter node (within
## NEAREST_FALLBACK_DIST) so the reconciler can re-attach the wire to the live
## ring instead of creating a dead-end isolated edge.
const NEAREST_FALLBACK_DIST: float = 1.5   ## world-units XZ; ~6 snap cells

func get_wire_node_key_at_pos(pos: Vector3) -> String:
	var key: String = _snap_key(Vector3(pos.x, WIRE_GRID_Y, pos.z))
	if _owner._wire_nodes.has(key):
		return key
	## Fallback: check the raw pos in case it's a breaker node at non-WIRE_GRID_Y.
	var key_raw: String = _snap_key(pos)
	if _owner._wire_nodes.has(key_raw):
		return key_raw
	## Nearest-XZ fallback: scan all wire nodes and return the closest one
	## within NEAREST_FALLBACK_DIST (XZ plane only — Y is irrelevant after rebuild).
	## This handles the case where a player wire endpoint was on the old perimeter
	## ring, the ring moved after expansion, and the exact snap key no longer exists.
	var best_key:  String = ""
	var best_dist: float  = NEAREST_FALLBACK_DIST
	for wn: Dictionary in _owner._wire_nodes.values():
		var wpos: Vector3 = wn.get("pos", Vector3.ZERO)
		var dx: float = wpos.x - pos.x
		var dz: float = wpos.z - pos.z
		var d: float  = sqrt(dx * dx + dz * dz)
		if d < best_dist:
			best_dist = d
			best_key  = wn["key"]
	if best_key != "":
		_owner._pmdbg("[PM:SNAP] get_wire_node_key_at_pos: exact miss at %s — nearest fallback to %s (dist=%.3f)" % [
			str(pos), best_key, best_dist])
	return best_key


## Strict existence check — returns true only if a wire node exists at exactly
## the snapped XZ position (no nearest-neighbour fallback).  Used by the
## player-wire cull so wires on intermediate PM nodes (not in boundary_edges)
## are correctly detected as dead after an expansion removes those nodes.

func has_wire_node_at_pos(pos: Vector3) -> bool:
	var key: String = _snap_key(Vector3(pos.x, WIRE_GRID_Y, pos.z))
	return _owner._wire_nodes.has(key)

## Remove a wire node and any edges that reference it.
## Call from device _exit_tree() before unregistering the consumer/generator.

func unregister_wire_node(node_key: String) -> void:
	if not _owner._wire_nodes.has(node_key):
		return
	## Remove all edges touching this node.
	var to_remove: Array[String] = []
	for edge: Dictionary in _owner._wire_edges.values():
		if edge["node_a"] == node_key or edge["node_b"] == node_key:
			to_remove.append(edge["id"])
	for eid: String in to_remove:
		_remove_wire_edge_internal(eid)
	## Remove any breaker sitting on this node.
	for bid: String in _owner._breakers.keys():
		if _owner._breakers[bid]["node_key"] == node_key:
			_owner._breakers.erase(bid)
			break
	_owner._wire_nodes.erase(node_key)
	_owner.wire_node_unregistered.emit(node_key)
	_owner._solve_network()


## Place a wire segment between two existing wire nodes.
##   node_a_id  — snap key of endpoint A  (from register_wire_node)
##   node_b_id  — snap key of endpoint B
##   scene_node — the WireSegment Node3D in the scene (visual); may be null
## Returns edge_id — store it to unregister on deconstruct.
## NOTE: no capacity_w param — wires have no per-edge limit.
## Resolve a snap key to an existing wire node at the same XZ grid position,
## regardless of Y.  Fixes connectivity when a free joint or generator node is
## at a slightly different Y than existing wire-grid nodes at the same column.
## If no same-XZ node exists the original key is returned unchanged.

func _resolve_node_key(key: String) -> String:
	if _owner._wire_nodes.has(key):
		return key   ## exact match — fastest path
	## Extract XZ index from key (format "ix,iy,iz").
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 3:
		return key
	var ix: int = int(parts[0])
	var iz: int = int(parts[2])
	## Scan existing nodes for one at the same XZ.
	for existing_key: String in _owner._wire_nodes:
		var ep: PackedStringArray = existing_key.split(",")
		if ep.size() != 3:
			continue
		if int(ep[0]) == ix and int(ep[2]) == iz:
			return existing_key
	return key   ## no match — keep original


func register_wire_edge(
		node_a_id:  String,
		node_b_id:  String,
		scene_node: Node  = null,
		no_visual:  bool  = false) -> String:

	## Normalise both keys to existing same-XZ nodes so that a generator at
	## Y≠0 (or a free joint at a slightly different Y) correctly merges with
	## the existing wire graph instead of forming an isolated zone.
	node_a_id = _resolve_node_key(node_a_id)
	node_b_id = _resolve_node_key(node_b_id)


	## Auto-create bare joint nodes if endpoints don't exist yet
	## (wire placed before a device is placed at that snap point).
	if not _owner._wire_nodes.has(node_a_id):
		_owner._wire_nodes[node_a_id] = {
			"key": node_a_id, "pos": Vector3.ZERO,
			"role": "joint", "device_id": "", "reachable": false
		}
	if not _owner._wire_nodes.has(node_b_id):
		_owner._wire_nodes[node_b_id] = {
			"key": node_b_id, "pos": Vector3.ZERO,
			"role": "joint", "device_id": "", "reachable": false
		}

	## Canonical edge id: sorted so A<B, prevents duplicate in both directions.
	var parts: Array[String] = [node_a_id, node_b_id]
	parts.sort()
	var edge_id: String = "e_%s__%s" % [parts[0], parts[1]]

	if _owner._wire_edges.has(edge_id):
		## Edge already exists — idempotent re-registration.
		## Still honour the bulk contract: mark dirty so the outermost end_bulk()
		## (or a direct request_solve()) runs a fresh solve over the current graph.
		## Without this, a bulk window where ALL edges already exist exits with
		## _owner._needs_resolve=false and the solver never runs (even if topology changed).
		if _owner._bulk_depth > 0:
			_owner._needs_resolve = true
		else:
			_owner._solve_network()
		return edge_id

	_owner._wire_edges[edge_id] = {
		"id":        edge_id,
		"node_a":    node_a_id,
		"node_b":    node_b_id,
		"load_w":    0.0,
		"node":      scene_node,
		"no_visual": no_visual,   ## true = logical-only edge; reconciler never spawns a tube
	}

	## Auto-generate intermediate joint nodes every SNAP_GRID metres along the
	## A→B segment so breakers and lights always have a wire-grid snap point
	## beneath them. Endpoints are already registered above; skip them.
	## We decode positions from the snap keys (a and b may have been
	## auto-created with Vector3.ZERO, so only generate intermediates when both
	## endpoints have a real non-zero position or when they were registered
	## through register_wire_node which stores the actual snapped pos).
	var pos_a: Vector3 = _owner._wire_nodes[node_a_id]["pos"]
	var pos_b: Vector3 = _owner._wire_nodes[node_b_id]["pos"]
	## If either endpoint pos is zero it was auto-created without a position —
	## fall back to reconstructing from the snap key integers.
	if pos_a == Vector3.ZERO:
		var tok_a: PackedStringArray = node_a_id.split(",")
		if tok_a.size() == 3:
			pos_a = Vector3(int(tok_a[0]) * SNAP_GRID,
							int(tok_a[1]) * SNAP_GRID,
							int(tok_a[2]) * SNAP_GRID)
		else:
			pass  ## key malformed, pos_a stays zero
	if pos_b == Vector3.ZERO:
		var tok_b: PackedStringArray = node_b_id.split(",")
		if tok_b.size() == 3:
			pos_b = Vector3(int(tok_b[0]) * SNAP_GRID,
							int(tok_b[1]) * SNAP_GRID,
							int(tok_b[2]) * SNAP_GRID)
		else:
			pass  ## key malformed, pos_b stays zero

	var seg_len: float = pos_a.distance_to(pos_b)
	var intermediate_count: int = 0
	if seg_len > SNAP_GRID * 1.5:
		## Number of interior steps between the two endpoints.
		var steps: int = roundi(seg_len / SNAP_GRID)
		for i: int in range(1, steps):
			var t: float     = float(i) / float(steps)
			var ipos: Vector3 = pos_a.lerp(pos_b, t)
			var ikey: String  = _snap_key(ipos)
			## Never overwrite a node that already has a real role (device, breaker).
			if not _owner._wire_nodes.has(ikey):
				_owner._wire_nodes[ikey] = {
					"key":       ikey,
					"pos":       _snapped_pos(ipos),
					"role":      "joint",
					"device_id": "",
					"reachable": false,
				}
				intermediate_count += 1

	## ── T-junction split ───────────────────────────────────────────────────
	## If either endpoint of the new wire landed on an *intermediate* joint of
	## an existing edge (i.e. the node exists in _owner._wire_nodes but is not yet an
	## endpoint of any edge), split that existing edge at this point so the BFS
	## can traverse through it.  Without this, the connecting wire forms an
	## isolated zone because the intermediate joint is never in node_edges.
	##
	## We must do this AFTER adding the new edge to _owner._wire_edges so that
	## _split_wire_edge_at won't try to split the new edge we just registered
	## (it only splits edges where mid_key is NOT already an endpoint —
	## the new edge has node_a/node_b as endpoints, so they are safe from
	## double-splitting).  Note: _split_wire_edge_at does not call
	## _solve_network; we let the call below handle it.
	_split_wire_edge_at(node_a_id)
	_split_wire_edge_at(node_b_id)

	_owner.wire_edge_registered.emit(edge_id)
	_owner._solve_network()
	return edge_id


## Remove a wire segment (deconstructed by player).
## Triggers a full network re-solve — downstream devices may lose power.

func unregister_wire_edge(edge_id: String) -> void:
	if not _owner._wire_edges.has(edge_id):
		return
	_remove_wire_edge_internal(edge_id)
	_owner._solve_network()


## Pure read — does this edge_id currently exist in the wire graph?
## Used by callers (e.g. MainWorld's incremental rebuild) to distinguish
## still-live edges from stale ones without mutating any state.

func has_wire_edge(edge_id: String) -> bool:
	return _owner._wire_edges.has(edge_id)


## Register a circuit breaker on an existing wire node.
## Returns breaker_id — store it to trip/reset/unregister later.
## Also splits any existing wire edge whose A→B segment passes through the
## breaker's snap point, so the breaker becomes a true cut-point in the graph.

func _find_wire_segment_by_edge_id(target_eid: String) -> Node3D:
	if _owner.get_tree() == null or target_eid.is_empty():
		return null
	for ws: Node in _owner.get_tree().get_nodes_in_group("wire_segment"):
		if not is_instance_valid(ws):
			continue
		if "edge_id" in ws and String(ws.get("edge_id")) == target_eid:
			return ws as Node3D
	return null


## Spawn (or reuse) a WireSegment tube for the given edge_id spanning p_from→p_to.
## Used by _split_wire_edge_at() to guarantee BOTH halves of a split edge get a
## visual tube even when the original edge had no source mesh (orig_node==null).
## Reuse-before-spawn prevents duplicate overlapping tubes on one edge_id.
## Returns the tube node, or null if the scene tree / script is unavailable.

func _spawn_or_reuse_wire_visual(edge_id: String, p_from: Vector3, p_to: Vector3) -> Node3D:
	if _owner.get_tree() == null or edge_id.is_empty():
		return null
	## 1. Reuse an existing tube already tagged with this edge_id.
	var existing: Node3D = _find_wire_segment_by_edge_id(edge_id)
	if existing != null:
		## Do NOT set visible here — BuildModeController owns visibility via call_group.
		if existing.has_method("set_endpoints"):
			existing.call("set_endpoints", p_from, p_to)
		return existing
	## 2. Spawn a fresh WireSegment parented to MainWorld so it joins the
	##    "wire_segment" group and receives the build-mode visibility broadcast.
	var parent: Node = _owner.get_tree().get_first_node_in_group("main_world")
	if parent == null:
		parent = _owner.get_tree().get_current_scene()
	if parent == null:
		return null
	var wire_script: GDScript = load("res://scripts/world/power/WireSegment.gd")
	if wire_script == null:
		return null
	var seg: Node3D = Node3D.new()
	seg.set_script(wire_script)
	seg.name = "WireSegment"
	parent.add_child(seg)
	seg.set_meta("_is_pregen", true)
	seg.set("edge_id", edge_id)
	## Defer set_endpoints so the node's _ready() has built its mesh first.
	seg.call_deferred("set_endpoints", p_from, p_to)
	return seg


## PUBLIC wrapper around _split_wire_edge_at().
##
## During a full auto-wire rebuild (bunker expansion or build-mode re-entry)
## Pass B2 re-lays a CONTINUOUS perimeter ring whose edges span straight
## through any surviving breaker's snap point (the breaker node is not part of
## node_positions, so B2 connects the two ring nodes that flank it directly).
## register_breaker() is NOT called again on rebuild (the breaker already
## exists), so _split_wire_edge_at() never runs and the ring stays electrically
## continuous → all zones merge into one giant zone plus dangling stubs.
##
## MainWorld.PassC0 calls this for every surviving breaker AFTER it has
## re-stitched the breaker's two stub edges, so the bypass ring edge gets cut
## and the breaker becomes a true graph cut-point again.

func resplit_breaker(node_key: String) -> void:
	if not _owner._wire_nodes.has(node_key):
		push_warning("PowerManager.resplit_breaker: unknown node '%s'" % node_key)
		return
	_split_wire_edge_at(node_key)
	_owner._solve_network()


func _split_wire_edge_at(mid_key: String) -> void:
	if not _owner._wire_nodes.has(mid_key):
		return
	var mid_pos: Vector3 = _owner._wire_nodes[mid_key]["pos"]
	## Collect edges to split (don't modify dict while iterating).
	var to_split: Array[String] = []
	_owner._pmdbg("[SPLIT] _split_wire_edge_at mid_key=%s  mid_pos=%s  total_edges=%d" % [
		mid_key, str(mid_pos), _owner._wire_edges.size()])
	for edge: Dictionary in _owner._wire_edges.values():
		var a_key: String = edge["node_a"]
		var b_key: String = edge["node_b"]
		## If mid IS already one of the endpoints, the breaker node was snapped
		## exactly onto an existing wire joint.  The edge still needs to be
		## re-routed through the breaker so it acts as a graph cut-point; skip
		## only if the other endpoint is also the breaker (self-loop, impossible
		## in practice) or if a downstream edge already connects them.
		if a_key == mid_key and b_key == mid_key:
			_owner._pmdbg("[SPLIT]   SKIP self-loop edge %s" % edge["id"])
			continue   ## degenerate self-loop, ignore
		if a_key == mid_key or b_key == mid_key:
			## The breaker snapped exactly onto an existing wire endpoint.
			## We must NOT skip — the edge's visual tube still needs its
			## edge_id patched (the split loop below handles this via the
			## degenerate-length guard: one half will have zero length and
			## be treated as a no-op while the other keeps the orig_node).
			## Falling through to to_split ensures the tube is re-linked
			## with the correct edge_id so _recolor_wire_zones() finds it.
			_owner._pmdbg("[SPLIT]   ENDPOINT edge %s  (a=%s b=%s) — falling through to split" % [edge["id"], a_key, b_key])
		if not _owner._wire_nodes.has(a_key) or not _owner._wire_nodes.has(b_key):
			_owner._pmdbg("[SPLIT]   SKIP missing node edge %s" % edge["id"])
			continue
		var a_pos: Vector3 = _owner._wire_nodes[a_key]["pos"]
		var b_pos: Vector3 = _owner._wire_nodes[b_key]["pos"]
		var on_seg: bool = _point_on_segment(mid_pos, a_pos, b_pos)
		var am: float = a_pos.distance_to(mid_pos)
		var mb: float = mid_pos.distance_to(b_pos)
		_owner._pmdbg("[SPLIT]   check edge %s  a=%s b=%s  on_seg=%s  am=%.3f mb=%.3f" % [
			edge["id"], a_key, b_key, str(on_seg), am, mb])
		if on_seg:
			to_split.append(edge["id"])

	_owner._pmdbg("[SPLIT] edges to split: %d → %s" % [to_split.size(), str(to_split)])

	for eid: String in to_split:
		if not _owner._wire_edges.has(eid):
			_owner._pmdbg("[SPLIT]   eid %s vanished before split loop, skipping" % eid)
			continue
		var edge: Dictionary = _owner._wire_edges[eid]
		var a_key: String = edge["node_a"]
		var b_key: String = edge["node_b"]
		## keep scene node on first segment.
		## Guard against freed instances: a prior split or the recolor dedupe
		## pass may have queue_free()'d this mesh while the edge dict still holds
		## the stale reference.  Assigning a freed object to a typed Node var
		## throws "Trying to assign invalid previously freed instance" — so read
		## it untyped first, validate, then coerce to null when dead.
		var _raw_node: Variant = edge.get("node")
		var orig_node: Node = _raw_node if (_raw_node != null and is_instance_valid(_raw_node)) else null
		## Fetch world positions for the two endpoints (needed for WireSegment resize).
		var a_pos: Vector3 = _owner._wire_nodes[a_key]["pos"] if _owner._wire_nodes.has(a_key) else Vector3.ZERO
		var b_pos: Vector3 = _owner._wire_nodes[b_key]["pos"] if _owner._wire_nodes.has(b_key) else Vector3.ZERO
		## ── Degenerate-length guard ─────────────────────────────────────────
		## _point_on_segment tolerance allows mid to sit very near (or exactly
		## on) an endpoint even though the top-of-loop endpoint guard only
		## catches EXACT key matches.  If either half would be shorter than
		## half a snap cell it is invisible — skip it to prevent ghost tubes.
		var am_len: float = a_pos.distance_to(mid_pos)
		var mb_len: float = mid_pos.distance_to(b_pos)
		## ── Zone boundary endpoints ─────────────────────────────────────────
		## Both tube halves meet exactly at mid_pos.  The breaker mesh covers
		## the single-pixel seam — no overshoot, no overlap, no blend artifact.
		var mid_am: Vector3 = mid_pos
		var mid_mb: Vector3 = mid_pos
		_owner._pmdbg("[SPLIT]   SPLITTING eid=%s  a=%s b=%s  am_len=%.3f mb_len=%.3f  orig_node=%s" % [
			eid, a_key, b_key, am_len, mb_len,
			"null" if orig_node == null else ("valid(%s)" % orig_node.name if is_instance_valid(orig_node) else "INVALID")])
		if am_len < SNAP_GRID * 0.5 and mb_len < SNAP_GRID * 0.5:
			_owner._pmdbg("[SPLIT]   SKIP: both halves degenerate, nothing to do")
			continue   ## Zero-length edge entirely, nothing to do.
		## Pass is_split=true so _remove_wire_edge_internal:
		##   • does NOT queue_free the scene node (we re-assign it to new_id_ab)
		##   • does NOT prune intermediate joints (they become node_keys for the
		##     new edges and serve as stable zone-color registry anchors)
		_remove_wire_edge_internal(eid, true)
		## Register the two replacement edges without triggering a full solve each
		## time — we'll let the caller's _owner._solve_network() do it once at the end.
		##
		## ENDPOINT CASE: when the breaker snapped exactly onto endpoint A or B,
		## one half is a zero-length self-loop — skip registering that half.
		## The surviving half inherits the orig_node and covers the full span.
		var parts_ab: Array[String] = [a_key, mid_key]
		parts_ab.sort()
		var new_id_ab: String = "e_%s__%s" % [parts_ab[0], parts_ab[1]]
		## Skip A→M when it is a self-loop (mid == a).
		if mid_key == a_key:
			_owner._pmdbg("[SPLIT]   A→M: skipped — mid==a (breaker was endpoint A, M→B takes orig_node)")
		elif not _owner._wire_edges.has(new_id_ab):
			_owner._wire_edges[new_id_ab] = {
				"id": new_id_ab, "node_a": a_key, "node_b": mid_key,
				"load_w": 0.0,
				## If the A→M half is degenerate, don't assign the visual node
				## here — it will be freed or stays at full length.  Assign it
				## to M→B instead so the tube is at least visible on that side.
				"node": orig_node if am_len >= SNAP_GRID * 0.5 else null,
			}
			if am_len >= SNAP_GRID * 0.5 and orig_node != null and is_instance_valid(orig_node):
				## Patch edge_id so _recolor_wire_zones() finds it by edge_id match.
				if "edge_id" in orig_node:
					orig_node.set("edge_id", new_id_ab)
				## ── Resize orig_node to span only A→M ──────────────────────
				## The original WireSegment tube was built from A→B.  After the
				## split it belongs to zone A (A→M side) — shrink it so the
				## colour boundary aligns exactly with the breaker position.
				if orig_node.has_method("set_endpoints"):
					orig_node.call("set_endpoints", a_pos, mid_am)
				_owner._pmdbg("[SPLIT]   A→M: reused orig_node edge_id=%s  endpoints %s→%s (inset)" % [
					new_id_ab, str(a_pos), str(mid_am)])
			elif am_len < SNAP_GRID * 0.5 and orig_node != null and is_instance_valid(orig_node):
				## A→M is degenerate — hide the original tube so it doesn't
				## show as a ghost; it will be re-used as the M→B visual below.
				orig_node.visible = false
				_owner._pmdbg("[SPLIT]   A→M: degenerate, hid orig_node")
			elif am_len >= SNAP_GRID * 0.5 and (orig_node == null or not is_instance_valid(orig_node)):
				## ── ROOT-CAUSE FIX: A→M has NO source mesh ─────────────────
				## orig_node is null (the edge was registered by an auto-wire
				## Pass with no spawned tube yet).  Previously this half got NO
				## visual at all — so zone-A's wire visually ended at the prior
				## full grid node instead of at the breaker, making the colour
				## seam appear offset by up to one grid step from the breaker.
				## Spawn (or reuse) a tube spanning A→mid so the seam lands
				## exactly on the breaker position, mirroring the M→B path.
				var am_node: Node3D = _spawn_or_reuse_wire_visual(new_id_ab, a_pos, mid_am)
				_owner._wire_edges[new_id_ab]["node"] = am_node
				_owner._pmdbg("[SPLIT]   A→M: spawned/reused visual (orig_node was null)  edge_id=%s  endpoints %s→%s" % [
					new_id_ab, str(a_pos), str(mid_am)])
			_owner.wire_edge_registered.emit(new_id_ab)
		else:
			_owner._pmdbg("[SPLIT]   A→M: edge %s already exists, skipped" % new_id_ab)
		## Skip M→B when it is a self-loop (mid == b).
		## The A→M edge already covers the full original span in that case.
		if mid_key == b_key:
			_owner._pmdbg("[SPLIT]   M→B: skipped — mid==b (breaker was endpoint B, A→M took orig_node)")
			continue
		var parts_mb: Array[String] = [mid_key, b_key]
		parts_mb.sort()
		var new_id_mb: String = "e_%s__%s" % [parts_mb[0], parts_mb[1]]
		if not _owner._wire_edges.has(new_id_mb):
			## ── Spawn a new WireSegment visual for the M→B half ────────────
			## Skip spawning when M→B is degenerate (near-zero) to prevent the
			## light-blue ghost tube visible behind the breaker object.
			var mb_node: Node = null
			if mb_len < SNAP_GRID * 0.5:
				_owner._pmdbg("[SPLIT]   M→B: degenerate (%.3f < %.3f), no visual spawned" % [
					mb_len, SNAP_GRID * 0.5])
			elif _owner.get_tree() == null:
				_owner._pmdbg("[SPLIT]   M→B: no scene tree, cannot spawn visual")
			elif orig_node == null or not is_instance_valid(orig_node):
				## orig_node is null — happens when the edge was registered by
				## Pass C0 with no visual (e.g. a surviving breaker's neighbor
				## edge after a rebuild).  Spawn a fresh WireSegment parented to
				## MainWorld so it still gets the "wire_segment" group and the
				## build-mode visibility broadcast.
				##
				## EXCEPTION: never spawn a visual when either endpoint is a
				## consumer node (wall lights, devices).  Those edges carry power
				## logically — there is no physical wire tube between a light and
				## the perimeter ring.
				var mid_role: String = (_owner._wire_nodes.get(mid_key, {}) as Dictionary).get("role", "joint")
				var b_role:   String = (_owner._wire_nodes.get(b_key,   {}) as Dictionary).get("role", "joint")
				if mid_role != "consumer" and b_role != "consumer":
					## ── ROOT-CAUSE FIX: reuse an EXISTING visual before spawning ──
					## Pass C0 in MainWorld._rebuild_auto_wires() already spawns and
					## registers a WireSegment for this same M→B edge_id BEFORE the
					## breaker's deferred _split runs.  If we blindly spawn a fallback
					## here we end up with TWO overlapping tubes on one edge — the
					## tracked Pass-C0 mesh AND this orphan fallback.  The orphan never
					## receives the zone recolor pass, so it shows the default/blue
					## tube on top of the correctly-colored one → "stitched" multicolor
					## artifact at every breaker/generator join.
					##
					## Search the scene for a WireSegment already tagged with this
					## edge_id and reuse it instead of spawning a duplicate.
					var existing_mb: Node3D = _find_wire_segment_by_edge_id(new_id_mb)
					if existing_mb != null:
						## Do NOT set visible here — BuildModeController owns visibility.
						if existing_mb.has_method("set_endpoints"):
							existing_mb.call("set_endpoints", mid_mb, b_pos)
						mb_node = existing_mb
						_owner._pmdbg("[SPLIT]   M→B: reused EXISTING WireSegment (no duplicate spawned)  edge_id=%s" % new_id_mb)
					else:
						var fallback_parent: Node = _owner.get_tree().get_first_node_in_group("main_world")
						if fallback_parent == null:
							fallback_parent = _owner.get_tree().get_current_scene()
						if fallback_parent != null:
							var wire_script_fb: GDScript = load("res://scripts/world/power/WireSegment.gd")
							if wire_script_fb != null:
								var fb_seg: Node3D = Node3D.new()
								fb_seg.set_script(wire_script_fb)
								fb_seg.name = "WireSegment"
								fallback_parent.add_child(fb_seg)
								fb_seg.set_meta("_is_pregen", true)
								fb_seg.set("edge_id", new_id_mb)
								fb_seg.call_deferred("set_endpoints", mid_mb, b_pos)
								mb_node = fb_seg
								_owner._pmdbg("[SPLIT]   M→B: spawned fallback WireSegment (orig_node was null)  edge_id=%s  parent=%s" % [
									new_id_mb, fallback_parent.name])
							else:
								_owner._pmdbg("[SPLIT]   M→B: ERROR — could not load WireSegment.gd for fallback")
						else:
							_owner._pmdbg("[SPLIT]   M→B: orig_node null and no valid parent found, cannot spawn visual")
			else:
				## If am_len was degenerate we reuse orig_node for M→B instead
				## of spawning a brand-new scene, saving a script load.
				if am_len < SNAP_GRID * 0.5:
					# Do NOT set visible here — BuildModeController owns visibility.
					if "edge_id" in orig_node:
						orig_node.set("edge_id", new_id_mb)
					if orig_node.has_method("set_endpoints"):
						orig_node.call("set_endpoints", mid_mb, b_pos)
					mb_node = orig_node
					_owner._pmdbg("[SPLIT]   M→B: reused orig_node (A side was degenerate)  edge_id=%s" % new_id_mb)
				else:
					## ── ROOT-CAUSE FIX (Step 2): reuse-before-spawn ──────────
					## Pass C0 in MainWorld._rebuild_auto_wires() may already have
					## spawned a WireSegment for this exact M→B edge_id BEFORE the
					## breaker's deferred _split runs.  Spawning unconditionally
					## here produced TWO overlapping tubes on one edge — the
					## tracked Pass-C0 mesh AND this orphan — causing the
					## "stitched" multicolor artifact at breaker/generator joins.
					## Always search for an existing tube first and reuse it; only
					## spawn when none exists.  This makes EVERY M→B spawn path
					## one-mesh-per-edge, so the BuildModeController dedup SAFETY
					## NET is no longer needed.
					var existing_mb2: Node3D = _find_wire_segment_by_edge_id(new_id_mb)
					if existing_mb2 != null and existing_mb2 != orig_node:
						# Do NOT set visible here — BuildModeController owns visibility.
						if existing_mb2.has_method("set_endpoints"):
							existing_mb2.call("set_endpoints", mid_mb, b_pos)
						mb_node = existing_mb2
						_owner._pmdbg("[SPLIT]   M→B: reused EXISTING WireSegment (no duplicate spawned)  edge_id=%s" % new_id_mb)
					else:
						var wire_script: GDScript = load("res://scripts/world/power/WireSegment.gd")
						if wire_script != null:
							var new_seg: Node3D = Node3D.new()
							new_seg.set_script(wire_script)
							new_seg.name = "WireSegment"
							## Add to same parent as the A-side segment so it lives in
							## the same scene subtree and gets the build-mode visibility
							## broadcast (group "wire_segment" registered in _ready).
							orig_node.get_parent().add_child(new_seg)
							## Carry pregen meta so delete-mode/highlight treats
							## the B-side tube the same as the A-side.
							if orig_node.has_meta("_is_pregen"):
								new_seg.set_meta("_is_pregen", true)
							## Set edge_id BEFORE deferring set_endpoints so that
							## _recolor_wire_zones() (which also runs deferred) finds
							## the correct edge_id when it queries WireSegment nodes.
							## Note: script is set before add_child so the property
							## exists immediately even before _ready() runs.
							new_seg.set("edge_id", new_id_mb)
							## Defer set_endpoints so the node's _ready() has run
							## before we try to resize the tube geometry.
							new_seg.call_deferred("set_endpoints", mid_mb, b_pos)
							mb_node = new_seg
							_owner._pmdbg("[SPLIT]   M→B: spawned new WireSegment  edge_id=%s  endpoints %s→%s (inset)  node=%s" % [
								new_id_mb, str(mid_mb), str(b_pos), new_seg.name])
						else:
							_owner._pmdbg("[SPLIT]   M→B: ERROR — could not load WireSegment.gd script")
			_owner._wire_edges[new_id_mb] = {
				"id": new_id_mb, "node_a": mid_key, "node_b": b_key,
				"load_w": 0.0, "node": mb_node,
			}
			_owner.wire_edge_registered.emit(new_id_mb)
			_owner._pmdbg("[SPLIT]   M→B: registered edge %s  node=%s" % [
				new_id_mb, "null" if mb_node == null else mb_node.name])
		else:
			_owner._pmdbg("[SPLIT]   M→B: edge %s already exists, skipped" % new_id_mb)


## Returns true if point P lies on segment A→B (collinear + between/at endpoints).
## Works in the XZ plane only — Y is ignored so that breakers placed slightly
## above the wire (different Y snap level) still register as on-segment.
## Tolerance: half the snap grid (0.125 m) for collinearity check.
## NOTE: endpoint hits (t≈0 or t≈1) ARE included so a breaker snapped exactly
## onto a wire endpoint is detected and the edge can be re-routed through it.

func _point_on_segment(p: Vector3, a: Vector3, b: Vector3) -> bool:
	## Project everything to 2D XZ.
	var ab: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var ap: Vector2 = Vector2(p.x - a.x, p.z - a.z)
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return false   ## Degenerate edge (zero length).
	## Cross product magnitude in 2D = |ab.x*ap.y - ab.y*ap.x|.
	## If P is collinear with A→B this is zero; tolerance = half snap grid.
	var cross: float = ab.x * ap.y - ab.y * ap.x
	var tol: float   = SNAP_GRID * 0.5   ## 0.125 m
	if cross * cross > len_sq * tol * tol:
		return false
	## Check that P is between A and B inclusive (t ∈ [0, 1] with small margin).
	## Endpoints are intentionally included — a breaker at an edge endpoint is
	## still considered "on" that edge so we re-route the edge through the breaker.
	var t: float = ab.dot(ap) / len_sq
	return t >= -0.001 and t <= 1.001


## Remove a breaker (sold / deconstructed).
## Re-stitches the wire edge that was split when the breaker was placed,
## restoring A→B connectivity so the zone is not permanently severed.

func get_wire_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: String in _owner._wire_nodes:
		var nd: Dictionary = _owner._wire_nodes[k]
		out.append({
			"key":       k,
			"pos":       nd.get("pos", Vector3.ZERO),
			"role":      nd.get("role", "joint"),
			"device_id": nd.get("device_id", ""),
		})
	return out

func get_wire_edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge: Dictionary in _owner._wire_edges.values():
		out.append(edge.duplicate())
	return out

func _remove_wire_edge_internal(edge_id: String, is_split: bool = false) -> void:
	if not _owner._wire_edges.has(edge_id):
		return
	## Destroy the WireSegment scene node when this edge is removed due to a
	## device being deconstructed.  Without this, the wire mesh stays in the
	## world even though it is electrically gone.
	## Skip during splits — the caller takes ownership of the scene node and
	## reassigns it to the first replacement edge.
	var edge: Dictionary = _owner._wire_edges[edge_id]
	## Read untyped first: the stored mesh may already be freed (a prior split
	## or the recolor dedupe pass queue_free()'d it while the edge dict still
	## holds the stale reference).  Assigning a freed object to a typed Node var
	## throws "Trying to assign invalid previously freed instance" — so validate
	## before coercing to a typed handle.
	var _raw_scene: Variant = edge.get("node")
	var scene_node: Node = _raw_scene if (_raw_scene != null and is_instance_valid(_raw_scene)) else null
	if not is_split and scene_node != null:
		scene_node.queue_free()

	## ── Clean up orphaned intermediate joint nodes ────────────────────────────
	## When register_wire_edge() auto-generates intermediate joint nodes along
	## the segment (every SNAP_GRID metre between the two endpoints), those
	## nodes are never removed by simply erasing the edge dict.  We must
	## explicitly prune them here, but ONLY if:
	##   1. The node's role is "joint" (not a device or breaker).
	##   2. After this edge is removed the node would have no remaining edges.
	## This prevents phantom nodes that confuse get_wire_zones() into creating
	## new zones instead of reusing an existing one.
	var na: String = edge.get("node_a", "")
	var nb: String = edge.get("node_b", "")

	## Collect ALL snap keys that lie on this edge's geometric segment,
	## including the auto-generated intermediates (which share the segment).
	## We reconstruct them from the recorded positions, same way register_wire_edge did.
	var candidate_keys: Array[String] = []
	if _owner._wire_nodes.has(na) and _owner._wire_nodes.has(nb):
		var pos_a: Vector3 = _owner._wire_nodes[na].get("pos", Vector3.ZERO)
		var pos_b: Vector3 = _owner._wire_nodes[nb].get("pos", Vector3.ZERO)
		## Decode from snap key if stored as ZERO (auto-created node).
		if pos_a == Vector3.ZERO:
			var tok: PackedStringArray = na.split(",")
			if tok.size() == 3:
				pos_a = Vector3(int(tok[0]) * SNAP_GRID, int(tok[1]) * SNAP_GRID, int(tok[2]) * SNAP_GRID)
		if pos_b == Vector3.ZERO:
			var tok: PackedStringArray = nb.split(",")
			if tok.size() == 3:
				pos_b = Vector3(int(tok[0]) * SNAP_GRID, int(tok[1]) * SNAP_GRID, int(tok[2]) * SNAP_GRID)
		var seg_len: float = pos_a.distance_to(pos_b)
		if seg_len > SNAP_GRID * 1.5:
			var steps: int = roundi(seg_len / SNAP_GRID)
			for i: int in range(1, steps):
				var t: float      = float(i) / float(steps)
				var ipos: Vector3 = pos_a.lerp(pos_b, t)
				candidate_keys.append(_snap_key(ipos))

	## Erase the edge first so the edge-reference check below is accurate.
	_owner._wire_edges.erase(edge_id)

	## When called from a split, skip pruning entirely.
	## The replacement edges (A→mid, mid→B) need all intermediate nodes to stay
	## intact so BFS can traverse them and the color registry can use them as
	## stable zone anchors.  Pruning here would destroy those nodes before the
	## replacement edges are even added, collapsing zone history.
	if is_split:
		_owner.wire_edge_unregistered.emit(edge_id)
		return

	## Build a fast set of all snap keys still referenced by remaining edges.
	var still_used: Dictionary = {}
	for e: Dictionary in _owner._wire_edges.values():
		still_used[e.get("node_a", "")] = true
		still_used[e.get("node_b", "")] = true

	## Prune intermediate joints that are no longer referenced by any edge
	## and have no real device role (pure auto-generated stubs).
	for ikey: String in candidate_keys:
		if still_used.has(ikey):
			continue   ## Still part of another edge — keep it.
		if not _owner._wire_nodes.has(ikey):
			continue
		var wn: Dictionary = _owner._wire_nodes[ikey]
		var role: String = wn.get("role", "joint")
		if role != "joint":
			continue   ## Device or breaker node — never auto-remove.
		_owner._wire_nodes.erase(ikey)
		_owner.wire_node_unregistered.emit(ikey)

	_owner.wire_edge_unregistered.emit(edge_id)


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — CONSUMER POWER APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════

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
