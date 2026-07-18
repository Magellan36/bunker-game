extends RefCounted
class_name BuildUndoStack
## BuildUndoStack.gd  —  Stage 10 (BuildModeController slice) extraction
## ─────────────────────────────────────────────────────────────────────────────
## The undo system, extracted out of BuildModeController.gd: pop/replay logic
## (_undo) plus the 5 push helpers that record place/remove/dig_rock/move/wire
## actions onto the undo stack.
##
## SCOPE: _undo, _push_undo_place, _push_undo_remove, _push_undo_dig_rock,
## _push_undo_move, _push_undo_wire. Confirmed zero external callers anywhere
## else in the repo before extraction (same check as every prior slice).
##
## NOTE ON LAYOUT: unlike WireGraphBuilder/BuildMaterials, this cluster was
## NOT contiguous in the source file — _push_undo_wire sat ~150 lines after
## the other 5, separated by _on_wire_nodes_connected/_restore_then_recolor/
## _recolor_wire_zones (a different concern: retroactive wire-to-device
## linking + zone recolor, stays on BuildModeController). Extracted via two
## verbatim line-range slices, concatenated, then transformed together.
##
## DESIGN — same `_owner` back-reference pattern as every prior extraction.
## Nothing moved: `_undo_stack`, `MAX_UNDO`, `ROCK_DIG_COST`, the `TILE_*`
## consts, `_placed_objects`, `rock_surround`, `world_node` all stay on
## BuildModeController, reached via `_owner.<name>`. Also routes
## `_owner._recolor_wire_zones()` (called directly and passed as a
## `tree_exited`-connected Callable — must bind to the BuildModeController
## instance, not this RefCounted helper), `_owner._spawn_float_label_at_pos()`,
## `_owner._spawn_placed_object()`, `_owner._wdbg()`, and `_owner.get_tree()`
## (RefCounted has no scene-tree access of its own).
##
## BuildModeController holds one instance (`_undo_manager`) and forwards all
## 6 functions with identical signatures — every one of them is called from
## elsewhere in BuildModeController.gd (`_on_undo_requested()` calls `_undo()`;
## the 5 push helpers are called from the construct/deconstruct/dig/move/wire
## placement code paths), so all 6 need thin wrappers (no internal-only
## functions to skip this time, unlike the two prior slices).

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner


func _undo() -> void:
	if _owner._undo_stack.is_empty():
		return

	var entry: Dictionary = _owner._undo_stack.pop_back()
	var type: String      = entry["type"]

	if type == "place":
		## Hoist tile_id here so it's in scope for the breaker recolor block
		## below, which runs even when the node is no longer valid.
		var undo_tid: int = entry.get("tile_id", -1)
		## Safe cast: avoids "assign invalid freed instance" crash when the
		## node was already queue_free'd before undo was triggered.
		var body: Node3D = entry["node"] as Node3D
		if is_instance_valid(body):
			if body.has_method("eject_all_items"):
				body.eject_all_items()
			for i: int in _owner._placed_objects.size():
				if _owner._placed_objects[i]["node"] == body:
					_owner._placed_objects.remove_at(i)
					break
			## Unregister from power grid before freeing (undo-place path)
			if undo_tid == _owner.TILE_LIGHT:
				var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
				if pm != null:
					pm.unregister_consumer(str(body.get_instance_id()))
			elif undo_tid == _owner.TILE_GEN_S or undo_tid == _owner.TILE_GEN_M or undo_tid == _owner.TILE_GEN_L:
				var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
				if pm != null:
					var gid: String = str(body.get_instance_id())
					pm.unregister_generator(gid)
					pm.unregister_wire_node(gid)
			elif undo_tid == _owner.TILE_HEAVY:
				var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
				if pm != null:
					var hid: String = str(body.get_instance_id())
					pm.unregister_consumer(hid)
					pm.unregister_wire_node(hid)
			## _owner.TILE_BREAKER, _owner.TILE_BREAKER_SMART, and TILE_BATTERY_* self-unregister in _exit_tree().
			elif undo_tid == _owner.TILE_WATER_PURIFIER:
				## Undoing a just-placed purifier — revert its graph node back
				## to "corner" (pipe stays intact) before freeing, same
				## treatment as a normal deconstruct. See WaterPurifier.gd's
				## own header for the full deletion-order design.
				if body.has_method("revert_to_corner"):
					body.revert_to_corner()
			body.queue_free()

		## After freeing a breaker, restore zone color registry to the snapshot
		## taken just before it was placed, then recolor — this reverts the zone
		## split that placement caused and restores original wire colors.
		## Connect to tree_exited (one-shot) so _recolor fires AFTER _exit_tree()
		## finishes unregister_breaker (re-stitching the edge).  call_deferred
		## races against _exit_tree and would recolor against stale topology.
		## Applies to BOTH breaker variants.
		if (undo_tid == _owner.TILE_BREAKER or undo_tid == _owner.TILE_BREAKER_SMART) and is_instance_valid(body):
			var pm_brk: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
			var snap_brk: Dictionary = entry.get("zone_color_snap", {})
			if not snap_brk.is_empty() and pm_brk != null:
				pm_brk.restore_zone_colors(snap_brk)
				_owner._wdbg("[Undo] Breaker removed — zone color registry restored (%d entries)" \
						% snap_brk.size())
			body.tree_exited.connect(_owner._recolor_wire_zones, CONNECT_ONE_SHOT)

		var refund: int = entry["price"]
		if refund > 0 and _owner.world_node != null:
			_owner.world_node.add_cash(refund)
		_owner._spawn_float_label_at_pos(entry["world_pos"], refund, true)

	elif type == "remove":
		var tile_id:   int     = entry["tile_id"]
		var price:     int     = entry["price"]
		var pos:       Vector3 = entry["world_pos"]
		var angle_deg: float   = entry["angle_deg"]

		if _owner.world_node != null:
			_owner.world_node.spend_cash(price)

		var body: Node3D = _owner._spawn_placed_object(tile_id, pos, angle_deg)
		_owner._placed_objects.append({
			"node":          body,
			"tile_id":       tile_id,
			"price":         price,
			"world_pos":     pos,
			"angle_deg":     angle_deg,
			"player_placed": true,
		})
		_owner._spawn_float_label_at_pos(pos, price, false)

	elif type == "dig_rock":
		## Undo a rock dig: restore the chunk and refund the cost
		var chunk_id: Vector2i = entry["chunk_id"]
		var cost: int          = entry["cost"]
		var center: Vector3    = entry["world_pos"]

		if _owner.rock_surround != null:
			_owner.rock_surround.restore_chunk(chunk_id)

		if _owner.world_node != null:
			_owner.world_node.add_cash(cost)

		_owner._spawn_float_label_at_pos(center, cost, true)

	elif type == "move":
		## Undo a move: teleport the object back to its original position
		var body: Node3D = entry["node"] as Node3D
		if is_instance_valid(body):
			var old_pos: Vector3 = entry["old_pos"]
			body.global_position = old_pos
			# Update the registry entry too
			for reg_entry: Dictionary in _owner._placed_objects:
				if reg_entry["node"] == body:
					reg_entry["world_pos"] = old_pos
					break

	elif type == "wire":
		## Undo a wire placement: free the segment node, unregister the PM edge, refund cash.
		var seg_node_raw: Variant = entry.get("node", null)
		var seg_node: Node3D = null
		if seg_node_raw != null and is_instance_valid(seg_node_raw):
			seg_node = seg_node_raw as Node3D
		## Prefer the scene node's CURRENT edge_id — PM may have patched it during
		## a breaker or door split, making the stored edge_id stale and no longer
		## present in PM's _wire_edges dict (unregister_wire_edge would return early).
		var edge_id: String = ""
		if seg_node != null:
			var live_eid: Variant = seg_node.get("edge_id")
			if live_eid != null and live_eid is String and (live_eid as String) != "":
				edge_id = live_eid as String
		if edge_id == "":
			edge_id = entry.get("edge_id", "")   ## fallback to stored id
		if seg_node != null:
			seg_node.queue_free()
		var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
		if edge_id != "" and pm != null:
			pm.unregister_wire_edge(edge_id)
		var wire_cost: int = entry.get("cost", 0)
		if wire_cost > 0 and _owner.world_node != null:
			_owner.world_node.add_cash(wire_cost)
		_owner._spawn_float_label_at_pos(entry.get("world_pos", Vector3.ZERO), wire_cost, true)
		## Restore zone color registry to the snapshot taken just before this wire
		## was placed.  This undoes any zone absorption that happened when the wire
		## bridged two previously-separate grids, restoring both grids' original colors.
		var snap: Dictionary = entry.get("zone_color_snap", {})
		if not snap.is_empty() and pm != null:
			pm.restore_zone_colors(snap)
			_owner._wdbg("[Undo] Zone color registry restored from snapshot (%d entries)" % snap.size())
		## Recompute zone topology and push restored colors to all WireSegment nodes.
		_owner._recolor_wire_zones()

	elif type == "pipe":
		## Undo a pipe run: free every placed segment + elbow node, unregister
		## each WaterManager edge, refund cash. Mirrors the "wire" case above
		## (WaterPipeDrawMode/WireDrawMode are twin systems) — no zone-color
		## machinery here since the water system has no zones/breakers (see
		## docs/systems/water/README.md Non-responsibilities).
		var seg_nodes: Array = entry.get("seg_nodes", [])
		for n: Variant in seg_nodes:
			if n != null and is_instance_valid(n):
				(n as Node3D).queue_free()
		var elbow_nodes: Array = entry.get("elbow_nodes", [])
		for n: Variant in elbow_nodes:
			if n != null and is_instance_valid(n):
				(n as Node3D).queue_free()
		var wm: WaterManager = _owner.get_tree().get_first_node_in_group("water_manager") as WaterManager
		var edge_ids: Array = entry.get("edge_ids", [])
		if wm != null:
			for eid: Variant in edge_ids:
				if eid != null and (eid as String) != "":
					wm.unregister_edge(eid as String)
		var pipe_cost: int = entry.get("cost", 0)
		if pipe_cost > 0 and _owner.world_node != null:
			_owner.world_node.add_cash(pipe_cost)
		_owner._spawn_float_label_at_pos(entry.get("world_pos", Vector3.ZERO), pipe_cost, true)
		## Flow-direction arrows (Jul 2026) — recompute after undoing a pipe run.
		if wm != null:
			wm.recompute_flow_directions()

func _push_undo_place(body: Node3D, tile_id: int, price: int, pos: Vector3,
		zone_color_snap: Dictionary = {}) -> void:
	_owner._undo_stack.append({
		"type":            "place",
		"node":            body,
		"tile_id":         tile_id,
		"price":           price,
		"world_pos":       pos,
		"zone_color_snap": zone_color_snap,
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()

func _push_undo_remove(tile_id: int, price: int, pos: Vector3, angle_deg: float) -> void:
	_owner._undo_stack.append({
		"type":      "remove",
		"tile_id":   tile_id,
		"price":     price,
		"world_pos": pos,
		"angle_deg": angle_deg,
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()

func _push_undo_dig_rock(chunk_id: Vector2i, center: Vector3) -> void:
	_owner._undo_stack.append({
		"type":      "dig_rock",
		"chunk_id":  chunk_id,
		"cost":      _owner.ROCK_DIG_COST,
		"world_pos": center,
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()

func _push_undo_move(body: Node3D, reg_entry: Dictionary, old_pos: Vector3) -> void:
	_owner._undo_stack.append({
		"type":    "move",
		"node":    body,
		"old_pos": old_pos,
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()
func _push_undo_wire(seg_node: Node3D, edge_id: String, cost: int, midpoint: Vector3) -> void:
	## Capture color state BEFORE this wire's placement causes a zone-merge/recolor.
	var zone_color_snap: Dictionary = {}
	var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		zone_color_snap = pm.snapshot_zone_colors()

	_owner._undo_stack.append({
		"type":            "wire",
		"node":            seg_node,
		"edge_id":         edge_id,
		"cost":            cost,
		"world_pos":       midpoint,
		"zone_color_snap": zone_color_snap,   ## restore on undo
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()

## Mirrors _push_undo_wire() immediately above. No zone-color snapshot —
## the water system has no zones/breakers to preserve (see
## docs/systems/water/README.md Non-responsibilities).
func _push_undo_pipe(seg_nodes: Array, edge_ids: Array, cost: int, elbow_nodes: Array, midpoint: Vector3) -> void:
	_owner._undo_stack.append({
		"type":        "pipe",
		"seg_nodes":   seg_nodes,
		"edge_ids":    edge_ids,
		"elbow_nodes": elbow_nodes,
		"cost":        cost,
		"world_pos":   midpoint,
	})
	if _owner._undo_stack.size() > _owner.MAX_UNDO:
		_owner._undo_stack.pop_front()

