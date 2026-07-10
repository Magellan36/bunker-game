extends RefCounted
class_name WireGraphBuilder
## WireGraphBuilder.gd  —  Stage 10 extraction (review implementation plan)
## ─────────────────────────────────────────────────────────────────────────────
## The auto-wire perimeter rebuild engine, extracted out of MainWorld.gd. This
## is the wire-graph engine the review specifically called out as not
## belonging in a scene-bootstrap file — it happens to be called from
## MainWorld when terrain changes, but is really its own subsystem (perimeter
## solve, incremental node/edge diffing, player-wire culling, the correctness
## oracle). Extracted the same way as PowerGraph.gd/PowerRegistry.gd/
## PowerSolver.gd (Stage 5/8/8b): verbatim line-range slice, then only the
## identified "lives on MainWorld" identifiers regex-substituted to
## `_owner.<name>` form, full transformed output read back top-to-bottom
## before writing (caught one real miss this time: a bare `add_cash(refund)`
## call inside the player-wire-cull refund path — fixed before writing).
##
## SCOPE — the wire/perimeter rebuild cluster, confirmed (July 2026) to have
## ZERO external callers anywhere else in the codebase (every other file's
## matching-name hits were each file's own private `_wdbg` helper, or comments
## referencing these functions by name, not real calls):
##   _compute_and_rebuild_wires, _on_chunk_deconstructed, _rebuild_auto_wires,
##   _compute_boundary_diff, _compute_node_positions,
##   _verify_graph_matches_boundary, _point_on_span, _spawn_auto_wire_seg,
##   _on_chunk_restored.
##
## OUT OF SCOPE for this stage (still on MainWorld.gd): everything else —
## dev-cheat menus, HUD/inventory/bed wiring, build-mode bootstrapping,
## lighting setup, cash management, input handling. MainWorld remains a scene
## bootstrapper for all of that; only the wire-graph engine moved.
##
## DESIGN — same `_owner` back-reference pattern as the three PowerManager
## extractions. NONE of MainWorld's state was physically moved here:
## `_cleared_cells`, `_autofill_nodes`, `_auto_wire_nodes`, `_auto_wire_segs`,
## `_player_wire_segs`, `_boundary_edges_prev`, `_wire_log`, `_build_controller`,
## `rock_surround`, `WIRE_DEBUG` all stay declared on MainWorld — reached via
## `_owner.<name>`. Also routes `_owner._wdbg()`, `_owner._wkey()`,
## `_owner.add_cash()`, `_owner.get_tree()` (RefCounted has no scene-tree
## access of its own), and `_owner.add_child()` (spawning wire-segment visuals
## must parent them under MainWorld, not this RefCounted helper).
##
## MainWorld holds one instance (`_wire_builder`) and forwards the two
## externally-triggered entry points — `_compute_and_rebuild_wires()` (called
## once at startup/build-mode-setup) and the two chunk-event handlers
## `_on_chunk_deconstructed()`/`_on_chunk_restored()` (connected directly to
## RockSurround's signals) — with identical signatures. Every other function
## in this file is only ever called from another function within this same
## cluster, so needs no forwarding wrapper.

var _owner: MainWorld = null

func _init(owner: MainWorld) -> void:
	_owner = owner


func _compute_and_rebuild_wires() -> void:
	const PLACEMENT_Y: float = 2.0

	var DIRS: Array = [
		[-1,  0, "left",   -0.5,  0.0, 180.0],
		[ 1,  0, "right",   0.5,  0.0,   0.0],
		[ 0, -1, "top",     0.0, -0.5,  90.0],
		[ 0,  1, "bottom",  0.0,  0.5, 270.0],
	]

	var boundary_edges: Dictionary = {}

	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for d: Array in DIRS:
			var ncx: int     = cx + int(d[0])
			var ncz: int     = cz + int(d[1])
			var nkey: String = str(ncx) + "," + str(ncz)
			if _owner._cleared_cells.has(nkey):
				continue
			var wx: float    = cell_cx + float(d[3])
			var wz: float    = cell_cz + float(d[4])
			var ekey: String = _owner._wkey(wx) + "," + _owner._wkey(wz)
			boundary_edges[ekey] = {"pos": Vector3(wx, PLACEMENT_Y, wz), "angle": float(d[5])}

	var pillar_positions: Dictionary = {}
	var SX: Array = [-1, 1]
	var SZ: Array = [-1, 1]

	## Outer corners
	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for sx: int in SX:
			for sz: int in SZ:
				var nx_key: String = str(cx + sx) + "," + str(cz)
				var nz_key: String = str(cx) + "," + str(cz + sz)
				if _owner._cleared_cells.has(nx_key) or _owner._cleared_cells.has(nz_key):
					continue
				var px: float    = cell_cx + float(sx) * 0.5
				var pz: float    = cell_cz + float(sz) * 0.5
				var pkey: String = _owner._wkey(px) + "," + _owner._wkey(pz)
				pillar_positions[pkey] = Vector3(px, PLACEMENT_Y, pz)

	## Inward (concave) corners
	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for sx: int in SX:
			for sz: int in SZ:
				var nx_key: String = str(cx + sx) + "," + str(cz)
				var nz_key: String = str(cx) + "," + str(cz + sz)
				var nd_key: String = str(cx + sx) + "," + str(cz + sz)
				if not _owner._cleared_cells.has(nx_key):
					continue
				if not _owner._cleared_cells.has(nz_key):
					continue
				if _owner._cleared_cells.has(nd_key):
					continue
				var px: float    = cell_cx + float(sx) * 0.75
				var pz: float    = cell_cz + float(sz) * 0.75
				var pkey: String = _owner._wkey(px) + "," + _owner._wkey(pz)
				pillar_positions[pkey] = Vector3(px, PLACEMENT_Y, pz)

	_rebuild_auto_wires(boundary_edges, pillar_positions, false)

## ─── Global perimeter solver ─────────────────────────────────────────────────
## Called when a 4×4 rock chunk is destroyed. Fills floors, then re-solves
## the full perimeter of ALL cleared chunks in one global pass.
##
## chunk_origin: local-grid Vector2i (top-left cell, before world offset).
## World position = (local_x + OFFSET_X, local_z + OFFSET_Z) from RockSurround.
func _on_chunk_deconstructed(chunk_origin: Vector2i) -> void:
	if _owner._build_controller == null:
		return

	## ── Bulk-edit window (Fix A) ──────────────────────────────────────────────
	## Opens the PM bulk window BEFORE Pass 0 so that WallLight._exit_tree()
	## calling unregister_wire_node() doesn't trigger _solve_network() for each
	## deleted light.  The nested begin_bulk() inside _rebuild_auto_wires() is
	## reference-counted — it simply increments the depth counter and the final
	## end_bulk() there closes both windows together with ONE solve.
	var pm_bulk: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
	var _chunk_bulk: bool = pm_bulk != null
	if _chunk_bulk:
		pm_bulk.begin_bulk()

	var offset_x: float = _owner.rock_surround.OFFSET_X
	var offset_z: float = _owner.rock_surround.OFFSET_Z
	var chunk_size: int = _owner.rock_surround.chunk_size
	var gm: GridMap     = _owner._build_controller.gridmap

	const PLACEMENT_Y: float = 2.0   ## wall/pillar Y (raised +0.5 from 1.5)
	const FLOOR_Y_ROW: int   = -6    ## GridMap row for auto-stamped floors (lowered by 4)
	const TILE_FLOOR:  int   = 0
	const TILE_WALL:   int   = 1
	const TILE_PILLAR: int   = 2

	## Note: _owner._cleared_cells is pre-seeded with the full bunker interior by
	## _run_pregen(), so the neighbour checks below automatically treat all
	## interior edges as open — no separate bounds check needed.

	## ── Pass 0: remove any lights mounted on the destroyed rock chunk ────────
	## The chunk occupies world X/Z [chunk_origin + OFFSET, chunk_origin + OFFSET + chunk_size].
	## We add a small margin so lights snapped flush to the rock face are caught.
	const LIGHT_REMOVE_MARGIN: float = 0.6
	var rx_min: float = float(chunk_origin.x) + offset_x - LIGHT_REMOVE_MARGIN
	var rx_max: float = float(chunk_origin.x) + float(chunk_size) + offset_x + LIGHT_REMOVE_MARGIN
	var rz_min: float = float(chunk_origin.y) + offset_z - LIGHT_REMOVE_MARGIN
	var rz_max: float = float(chunk_origin.y) + float(chunk_size) + offset_z + LIGHT_REMOVE_MARGIN
	if _owner._build_controller.has_method("remove_lights_in_bounds"):
		_owner._build_controller.remove_lights_in_bounds(rx_min, rx_max, rz_min, rz_max)

	## ── Pass 0b: remove any breakers mounted on the destroyed rock chunk ─────
	## Must happen BEFORE _rebuild_auto_wires so PM's breaker registry is clean
	## when the new wire graph is built.  Stale breaker registrations pointing at
	## freed wire nodes would corrupt the zone graph.
	## BreakerBox._exit_tree() calls pm.unregister_breaker() automatically, so
	## remove_breakers_in_bounds() only needs to queue_free() the nodes and pull
	## them from _placed_objects — no explicit PM call required here.
	var breakers_removed: bool = false
	if _owner._build_controller.has_method("remove_breakers_in_bounds"):
		breakers_removed = _owner._build_controller.call("remove_breakers_in_bounds",
				rx_min, rx_max, rz_min, rz_max)

	## ── Pass 1: stamp floors + register cleared cells ────────────────────────
	## All auto-placed objects are shifted -0.5 on X (left) and -0.5 on Z (north).
	const SHIFT_X: float = -0.5
	const SHIFT_Z: float = -0.5
	for dx: int in range(chunk_size):
		for dz: int in range(chunk_size):
			var wx: float = float(chunk_origin.x + dx) + 0.5 + offset_x
			var wz: float = float(chunk_origin.y + dz) + 0.5 + offset_z
			var cx: int   = int(floor(wx))
			var cz: int   = int(floor(wz))
			var ckey: String = str(cx) + "," + str(cz)
			_owner._cleared_cells[ckey] = true
			## Stamp floor tile at shifted position
			var fcx: int = int(floor(wx + SHIFT_X))
			var fcz: int = int(floor(wz + SHIFT_Z))
			if gm != null and gm.get_cell_item(Vector3i(fcx, FLOOR_Y_ROW, fcz)) == GridMap.INVALID_CELL_ITEM:
				gm.set_cell_item(Vector3i(fcx, FLOOR_Y_ROW, fcz), TILE_FLOOR)

	## ── Pass 2: global perimeter solve ───────────────────────────────────────
	## For every cleared cell, examine its 4 cardinal neighbours.
	##   • Neighbour is cleared  → shared interior edge → no wall needed here.
	##   • Neighbour is NOT cleared → boundary edge → need a wall/pillar.
	##
	## Each boundary edge is described by:
	##   side = "left" | "right" | "top" | "bottom"
	##   wall pos = cell centre ± 0.5 on the relevant axis
	##   wall angle per the existing convention
	##
	## We collect all required boundary edges first, then decide wall vs pillar:
	##   A corner is where two perpendicular boundary edges share the SAME corner
	##   point — place a pillar there instead of two overlapping walls.

	## direction offsets: [dcx, dcz, side_label, wx_push, wz_push, angle]
	var DIRS: Array = [
		[-1,  0, "left",    -0.5,  0.0, 180.0],
		[ 1,  0, "right",    0.5,  0.0,   0.0],
		[ 0, -1, "top",      0.0, -0.5,  90.0],
		[ 0,  1, "bottom",   0.0,  0.5, 270.0],
	]

	## Collect all boundary edge positions we want to fill.
	## boundary_edges key = "wx,wz" → {pos, angle, is_wall:true}
	## We'll convert wall→pillar at corners after collecting everything.
	var boundary_edges: Dictionary = {}   ## key → {pos:Vector3, angle:float}

	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for d: Array in DIRS:
			var ncx: int   = cx + int(d[0])
			var ncz: int   = cz + int(d[1])
			var nkey: String = str(ncx) + "," + str(ncz)
			## Skip if neighbour is cleared (dug at runtime or pre-seeded interior)
			if _owner._cleared_cells.has(nkey):
				continue

			## Boundary edge — push half a cell outward toward the rock face
			var wx: float    = cell_cx + float(d[3])
			var wz: float    = cell_cz + float(d[4])
			var angle: float = float(d[5])
			var ekey: String = _owner._wkey(wx) + "," + _owner._wkey(wz)
			boundary_edges[ekey] = {"pos": Vector3(wx, PLACEMENT_Y, wz), "angle": angle}

	## ── Corner detection: find pillar positions ───────────────────────────────
	## A pillar replaces up to 4 walls that would otherwise pile on the same
	## outer corner point. A corner point exists at (cx+kx*0.5, cz+kz*0.5)
	## where kx,kz ∈ {-1,+1} from a cleared cell corner. Two perpendicular
	## boundary edges from the SAME cleared cell meeting at that corner → pillar.
	##
	## Strategy: for every cleared cell, check its 4 diagonal corners. A diagonal
	## corner at (cx+sx*0.5, cz+sz*0.5) [sx,sz ∈ {-1,+1}] is a pillar site if:
	##   • The axial neighbour on X (cx+sx, cz) is NOT cleared, AND
	##   • The axial neighbour on Z (cx, cz+sz) is NOT cleared.
	## (Both perpendicular faces are boundary → two walls would meet here → pillar.)
	## We also make sure neither diagonal neighbour is cleared (avoid interior pillar
	## peeking out into the open bunker area from a double-cleared L-shape corner).

	var pillar_positions: Dictionary = {}   ## key=pkey → Vector3

	var SX: Array = [-1, 1]
	var SZ: Array = [-1, 1]

	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for sx: int in SX:
			for sz: int in SZ:
				## Axial neighbours on each axis
				var nx_key: String = str(cx + sx) + "," + str(cz)
				var nz_key: String = str(cx) + "," + str(cz + sz)
				## Diagonal neighbour
				var nd_key: String = str(cx + sx) + "," + str(cz + sz)

				## A cell is "open" if cleared (dug or pre-seeded interior)
				var x_is_boundary: bool = not _owner._cleared_cells.has(nx_key)
				var z_is_boundary: bool = not _owner._cleared_cells.has(nz_key)

				if not (x_is_boundary and z_is_boundary):
					continue   ## Not a real outer corner from this cell

				## Pillar world position — pushed to exact rock face corner
				var px: float  = cell_cx + float(sx) * 0.5
				var pz: float  = cell_cz + float(sz) * 0.5
				var pkey: String = _owner._wkey(px) + "," + _owner._wkey(pz)
				pillar_positions[pkey] = Vector3(px, PLACEMENT_Y, pz)

				## NOTE: We intentionally do NOT erase the corner wall edges here.
				## Previously, erasing them caused gaps between wall runs and pillars.
				## Wall segments and pillars can occupy the same corner — the pillar
				## sits on top visually and seals the joint cleanly.

	## ── Inward (concave) corner detection ────────────────────────────────────
	## An inward corner is where two cleared cells meet at a right-angle and
	## their shared diagonal neighbour is NOT cleared (still rock / unexcavated).
	## Both axial neighbours ARE cleared but the diagonal is NOT → gap in the
	## corner → place a pillar pushed 0.5 inward toward the gap.
	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var cell_cx: float = float(cx) + 0.5 - 0.5
		var cell_cz: float = float(cz) + 0.5 - 0.5

		for sx: int in SX:
			for sz: int in SZ:
				var nx_key: String = str(cx + sx) + "," + str(cz)
				var nz_key: String = str(cx) + "," + str(cz + sz)
				var nd_key: String = str(cx + sx) + "," + str(cz + sz)

				## Inward corner: both axial neighbours cleared, diagonal is NOT
				if not _owner._cleared_cells.has(nx_key):
					continue
				if not _owner._cleared_cells.has(nz_key):
					continue
				if _owner._cleared_cells.has(nd_key):
					continue

				## Pillar sits at the inner corner, pushed 0.5 toward the gap,
				## then nudged an additional 0.25 into the unexcavated diagonal
				## so it visually fills the concave corner notch.
				var px: float    = cell_cx + float(sx) * 0.75
				var pz: float    = cell_cz + float(sz) * 0.75
				var pkey: String = _owner._wkey(px) + "," + _owner._wkey(pz)
				pillar_positions[pkey] = Vector3(px, PLACEMENT_Y, pz)

	## ── Pass 3: tear down existing auto-fill structures that are no longer needed
	## Build the full set of positions we WANT occupied after this solve.
	var desired_positions: Dictionary = {}
	for ekey: String in boundary_edges:
		desired_positions[ekey] = true
	for pkey: String in pillar_positions:
		desired_positions[pkey] = true

	## Any auto-fill node NOT in desired_positions is now interior → remove it.
	var to_remove: Array = []
	for akey: String in _owner._autofill_nodes:
		if not desired_positions.has(akey):
			to_remove.append(akey)
	for akey: String in to_remove:
		var node: Node3D = _owner._autofill_nodes[akey]
		if is_instance_valid(node):
			## Remove from BuildModeController's placed objects list if present
			if _owner._build_controller.has_method("remove_placed_object"):
				_owner._build_controller.remove_placed_object(node)
			node.queue_free()
		_owner._autofill_nodes.erase(akey)

	## ── Pass 4: spawn walls for boundary edges not already placed ────────────
	for ekey: String in boundary_edges:
		if _owner._autofill_nodes.has(ekey):
			continue   ## Already placed from a previous dig, keep it
		var data: Dictionary = boundary_edges[ekey]
		var node: Node3D = _owner._build_controller.spawn_structure(
			TILE_WALL, data["pos"], data["angle"])
		if node != null:
			_owner._autofill_nodes[ekey] = node

	## ── Pass 5: spawn pillars not already placed ─────────────────────────────
	for pkey: String in pillar_positions:
		if _owner._autofill_nodes.has(pkey):
			continue   ## Already placed
		var node: Node3D = _owner._build_controller.spawn_structure(
			TILE_PILLAR, pillar_positions[pkey], 0.0)
		if node != null:
			_owner._autofill_nodes[pkey] = node

	## ── Pass 6: recompute the full auto-wire perimeter ──────────────────────
	## Every dig tears down ALL previous auto-wire nodes/segments and relays
	## a single clean ring around the current full boundary_edges perimeter.
	## Pillar positions included so corner wire nodes are not skipped.
	## Stale pregen perimeter nodes (now interior) are also removed here.
	_rebuild_auto_wires(boundary_edges, pillar_positions, breakers_removed)

	## ── Close outer bulk window (Fix A) ──────────────────────────────────────
	## _rebuild_auto_wires opened + closed its own nested bulk window.  The outer
	## window opened at the top of this function is still pending; close it now
	## so the depth counter reaches 0 and the single coalesced solve fires.
	## (If _rebuild_auto_wires already triggered the only solve — because PM was
	## unavailable and _chunk_bulk is false — this is a harmless no-op.)
	if _chunk_bulk:
		pm_bulk.end_bulk()

	## ── Stage 1: log boundary diff ────────────────────────────────────────────
	## Compute and log the diff between the previous boundary and the current one.
	## No behavior change — _owner._boundary_edges_prev is updated here for the first time.
	## Stage 2 will consume the returned dict to drive incremental removal.
	_compute_boundary_diff(boundary_edges)

## ─── Full auto-wire rebuild ──────────────────────────────────────────────────
## Tears down every previously-registered auto wire node/segment, then lays
## a fresh perimeter ring along all current boundary walls in two passes:
##   Pass A — collect all wire node positions (boundary midpoints + outer corners)
##   Pass B — connect every axis-aligned adjacent pair
## Light reconnection handled at the end via _auto_connect_to_nearby_wires().
##
## Since BunkerPregen no longer registers any wires, _owner._auto_wire_nodes is the
## single source of truth for ALL wires in the scene.  Full teardown on every
## dig keeps the graph consistent with no stale interior segments.
func _rebuild_auto_wires(boundary_edges: Dictionary,
		pillar_positions: Dictionary = {},
		breakers_removed: bool = false) -> void:
	var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return

	## ── Bulk-edit window ──────────────────────────────────────────────────────
	## This function fires dozens of register/unregister calls; without batching,
	## each one runs a full PowerManager._solve_network().  Wrapping the whole
	## rebuild in begin_bulk()/end_bulk() coalesces them into ONE solve at the
	## end.  end_bulk() is mirrored before every early return below.
	var _pm_bulk: bool = true
	if _pm_bulk:
		pm.begin_bulk()

	const WIRE_Y:   float = 1.0
	## Two nodes are "adjacent" if their distance is ≤ this.
	## Boundary wall nodes are 1.0 apart; pillar-injected corner nodes may
	## be 0.5 from the first wall node — 1.1 covers both safely.
	const ADJ_DIST: float = 1.1

	## ── Pre-Pass 0: snapshot zone colors + player-placed wires before teardown ─
	## Zone color snapshot: taken before teardown so that surviving zones carry
	## their existing colors through the rebuild (best-effort continuity).
	## PM's registry still holds the old rep keys at this point — saving it now
	## lets get_wire_zones_with_colors() in Pass D reuse those keys after all
	## fresh edges are re-registered.
	var zone_color_snap: Dictionary = pm.snapshot_zone_colors()
	## ── Clear log for this rebuild cycle ────────────────────────────────────
	_owner._wire_log.clear()
	_owner._wdbg("=== _rebuild_auto_wires START ===")
	_owner._wdbg("  breakers_removed=%s  boundary_edges=%d  pillar_positions=%d" % [
		str(breakers_removed), boundary_edges.size(), pillar_positions.size()])
	_owner._wdbg("  _owner._cleared_cells=%d  _owner._auto_wire_nodes(pre-teardown)=%d" % [
		_owner._cleared_cells.size(), _owner._auto_wire_nodes.size()])
	_owner._wdbg("  zone_color_snap keys=%s" % [str(zone_color_snap.keys())])

	## ── Stage 3: player-wire snapshot REMOVED ───────────────────────────────
	## Incremental rebuild never tears down nodes that survive a dig, so player
	## wire edges (which connect two surviving auto-wire nodes) are never
	## cascade-deleted.  No snapshot/restore needed.  _owner._player_wire_segs dict
	## is preserved for future use (e.g. save/load, undo), just not rebuilt here.
	_owner._wdbg("  player_wire_segs=%d (nodes survive incrementally)" % _owner._player_wire_segs.size())

	## ── Stage 2: incremental removal (replaces Pass0 full teardown) ────────────
	## Compute the set of node positions that should exist AFTER this rebuild.
	## Any _owner._auto_wire_nodes entry whose cache_key is NOT in the desired set is
	## stale — unregister it (cascade-deletes its edges in PM) and free its visual.
	## Device nodes (breaker, generator, battery) are always skipped — they own
	## their own lifetime.
	const _SKIP_ROLES: Array[String] = ["breaker", "generator", "battery"]
	var desired_node_keys: Dictionary = _compute_node_positions(boundary_edges, pillar_positions)

	var stale_cache_keys: Array[String] = []
	for cache_key: String in _owner._auto_wire_nodes:
		if not desired_node_keys.has(cache_key):
			stale_cache_keys.append(cache_key)

	var removed_node_count: int = 0
	var skipped_role_count: int = 0
	for cache_key: String in stale_cache_keys:
		var pm_key: String = _owner._auto_wire_nodes[cache_key]
		## Never unregister device-owned nodes — they manage themselves.
		var role: String = pm.get_wire_node_role(pm_key)
		if role in _SKIP_ROLES:
			_owner._wdbg("  Pass0(incr): SKIP %s node pm_key=%s (cache_key=%s)" % [role, pm_key, cache_key])
			skipped_role_count += 1
			continue
		## Unregister: cascades to delete all auto-wire edges on this node in PM.
		pm.unregister_wire_node(pm_key)
		_owner._auto_wire_nodes.erase(cache_key)
		removed_node_count += 1

	## Free visual segments whose PM edge was cascade-deleted by node removal above.
	## Any seg whose edge_id is no longer in PM's edge registry is now dangling.
	## Player wire segs (edge_id starts with "pw_") are never freed here.
	var stale_seg_ids: Array[String] = []
	for eid: String in _owner._auto_wire_segs:
		if eid.begins_with("pw_"):
			continue
		if not pm.has_wire_edge(eid):
			stale_seg_ids.append(eid)
	for eid: String in stale_seg_ids:
		var seg_raw: Variant = _owner._auto_wire_segs[eid]
		if is_instance_valid(seg_raw):
			(seg_raw as Node3D).queue_free()
		_owner._auto_wire_segs.erase(eid)
	_owner._wdbg("  Pass0(incr): freed %d stale seg visuals" % stale_seg_ids.size())

	_owner._wdbg("  Pass0(incr): desired=%d  stale_removed=%d  role_skipped=%d  surviving=%d" % [
		desired_node_keys.size(), removed_node_count,
		skipped_role_count, _owner._auto_wire_nodes.size()])
	_owner._wdbg("  Pass0(incr) summary: desired=%d  removed=%d  role_skip=%d  surviving=%d" % [
		desired_node_keys.size(), removed_node_count,
		skipped_role_count, _owner._auto_wire_nodes.size()])

	## ── Player wire culling ───────────────────────────────────────────────────
	## Check every player-placed wire against the POST-REBUILD boundary.
	##
	## Root cause of the old approach failing: player wire endpoints snap to
	## intermediate PM nodes (generated every 0.25 m along an edge by
	## register_wire_edge). Those nodes are NEVER in _owner._auto_wire_nodes, so they
	## never appear in stale_cache_keys. Comparing endpoints to stale_cache_keys
	## was therefore always a miss — no wires were ever culled.
	##
	## Correct approach: ask PowerManager directly whether each endpoint position
	## still has a wire node after the rebuild (strict snap, no nearest fallback).
	## PM is the single source of truth — it knows about boundary nodes, pillar
	## nodes, AND intermediate nodes created by register_wire_edge splitting.
	## Comparing against boundary_edges only works for the first wire placed;
	## subsequent wires that snap to intermediate nodes are never in boundary_edges
	## and were therefore never detected as dead.
	##
	## If EITHER endpoint is not near any surviving boundary node → wire is dead
	## → delete + refund.
	##
	## WHY NOT has_wire_node_at_pos:
	##   Player wire endpoints snap to intermediate PM nodes created by
	##   register_wire_edge (spaced every 0.25 m along the edge). Those nodes are
	##   NEVER in _owner._auto_wire_nodes. After a rebuild the boundary shifts, but the
	##   intermediate nodes from the old boundary survive in PM unchanged —
	##   has_wire_node_at_pos returns true → cull never fires.
	##
	## CORRECT APPROACH:
	##   _owner._auto_wire_nodes is post-cleanup truth: only nodes that belong to the
	##   NEW boundary (plus role nodes like generators). If neither endpoint is
	##   within CULL_SNAP of any surviving boundary node, the wire is floating
	##   free from the power graph → cull it.
	##
	## cache_key format: "%.3f_%.3f_%.3f"  (x _ y _ z)
	if not _owner._player_wire_segs.is_empty():
		const WIRE_COST_PER_M_F: float = 8.0    ## mirrors BuildModeController.WIRE_COST_PER_M
		const CULL_SNAP: float = 0.65            ## same tolerance used elsewhere for wire snapping

		## Build flat XZ list of surviving wire node positions.
		##
		## BUG FIX (round 1): previously this ONLY included _owner._auto_wire_nodes
		## (pure boundary/joint positions) — generator, battery, and breaker
		## nodes are DELIBERATELY excluded from _owner._auto_wire_nodes (they manage
		## their own lifetime, see _SKIP_ROLES above). That meant ANY player
		## wire whose endpoint was a generator/battery/breaker could never pass
		## _near_boundary — it was unconditionally marked dead and refunded on
		## EVERY chunk rebuild, even though the device node was still completely
		## valid and untouched in PM.
		##
		## BUG FIX (round 2 — CORRECTION): round 1 fixed the above by adding
		## EVERY current pm.get_wire_nodes() position to the rescue set,
		## including plain "joint" role nodes. That was too broad: PM's edge-
		## splitting (_split_wire_edge_at / register_wire_edge) creates
		## intermediate joint nodes that can persist in _wire_nodes even after
		## their governing boundary edge is gone — they are only pruned when
		## something explicitly calls unregister_wire_node/_remove_wire_edge_
		## internal's orphan cleanup on THAT exact edge, not proactively per
		## rebuild. Treating every leftover joint as "still valid" let stale
		## player wires survive a rebuild instead of being culled — the exact
		## opposite bug the user then reported (wires "hovering" after an area
		## with no remaining connection was expanded away).
		##
		## CORRECT RULE: a position only "rescues" a player wire endpoint if it
		## is EITHER (a) a live boundary/joint node this rebuild just computed
		## (_owner._auto_wire_nodes — authoritative current truth), OR (b) a DEVICE
		## node (generator/battery/breaker), which owns its own lifetime and is
		## never touched by this rebuild at all. Plain leftover PM joints that
		## are NOT in _owner._auto_wire_nodes are exactly the stale, no-longer-part-
		## of-the-boundary nodes this cull is supposed to catch — they must NOT
		## rescue anything.
		const _RESCUE_ROLES: Array[String] = ["generator", "battery", "breaker"]
		var surviving_xz: Array[Vector2] = []
		for ck: String in _owner._auto_wire_nodes:
			var parts: PackedStringArray = ck.split("_")
			## parts[0]=x, parts[1]=y, parts[2]=z  (all as "%.3f" strings)
			if parts.size() >= 3:
				surviving_xz.append(Vector2(float(parts[0]), float(parts[2])))
		for wn: Dictionary in (pm.get_wire_nodes() as Array):
			if not (wn.get("role", "joint") in _RESCUE_ROLES):
				continue   ## plain joint — must NOT rescue (see note above)
			var wpos2: Vector3 = wn.get("pos", Vector3.ZERO)
			surviving_xz.append(Vector2(wpos2.x, wpos2.z))

		## Helper: is position p within CULL_SNAP of any surviving boundary node?
		var _near_boundary: Callable = func(p: Vector3) -> bool:
			var pxz: Vector2 = Vector2(p.x, p.z)
			for bxz: Vector2 in surviving_xz:
				if pxz.distance_to(bxz) <= CULL_SNAP:
					return true
			return false

		var dead_wire_keys: Array[String] = []
		for pw_key: String in _owner._player_wire_segs:
			var pw: Dictionary = _owner._player_wire_segs[pw_key]
			var pa: Vector3 = pw["pos_a"]
			var pb: Vector3 = pw["pos_b"]
			var a_ok: bool = _near_boundary.call(pa)
			var b_ok: bool = _near_boundary.call(pb)
			if not a_ok or not b_ok:
				dead_wire_keys.append(pw_key)
				_owner._wdbg("  PlayerWireCull: mark dead %s  a_near_boundary=%s  b_near_boundary=%s" % [
					pw_key, str(a_ok), str(b_ok)])

		for pw_key: String in dead_wire_keys:
			var pw: Dictionary    = _owner._player_wire_segs[pw_key]
			var pa: Vector3       = pw["pos_a"]
			var pb: Vector3       = pw["pos_b"]
			var length_m: float   = pa.distance_to(pb)
			var refund: int       = int(length_m * WIRE_COST_PER_M_F)
			var midpoint: Vector3 = (pa + pb) * 0.5

			## Free visual segment.
			## Primary: use stored seg_node reference.
			## Fallback: if seg_node is null (wire was placed before signals connected),
			## scan the wire_segment group for a WireSegment whose edge_id matches
			## the canonical PM edge id stored at placement time.
			var seg_raw: Variant = pw.get("seg_node")
			var seg_freed_ok: bool = false
			if seg_raw != null and is_instance_valid(seg_raw as Node3D):
				(seg_raw as Node3D).queue_free()
				seg_freed_ok = true
			else:
				var pm_eid: String = pw.get("pm_edge_id") if pw.get("pm_edge_id") != null else ""
				if not pm_eid.is_empty():
					for ws_node: Node in _owner.get_tree().get_nodes_in_group("wire_segment"):
						if not is_instance_valid(ws_node):
							continue
						var ws_eid: String = ws_node.get("edge_id") if ws_node.get("edge_id") != null else ""
						if ws_eid == pm_eid:
							ws_node.queue_free()
							seg_freed_ok = true
							_owner._wdbg("  PlayerWireCull: fallback seg freed via group scan  eid=%s" % pm_eid)
							break

			## Unregister the PM edge so the power graph stays clean.
			## Look up each endpoint's current PM key by world-space position,
			## then ask PM to remove the edge between them (canonical sort handled
			## inside unregister_wire_edge).
			var ka: String = pm.get_wire_node_key_at_pos(pa)
			var kb: String = pm.get_wire_node_key_at_pos(pb)
			if ka != "" and kb != "":
				## Must match PowerManager._wire_edges key format: "e_<small>__<large>"
				var eid: String = "e_%s__%s" % [ka, kb] if ka < kb else "e_%s__%s" % [kb, ka]
				pm.unregister_wire_edge(eid)
				_owner._wdbg("  PlayerWireCull: unregistered PM edge %s" % eid)
			else:
				_owner._wdbg("  PlayerWireCull: PM key lookup failed  ka='%s'  kb='%s' — skipping PM unregister" % [ka, kb])

			## Erase dict entry.
			_owner._player_wire_segs.erase(pw_key)

			## Refund cash + float label.
			_owner.add_cash(refund)
			if _owner._build_controller != null and _owner._build_controller.has_method("_spawn_float_label_at_pos"):
				_owner._build_controller.call("_spawn_float_label_at_pos", midpoint, refund, true)

			_owner._wdbg("  PlayerWireCull: erased %s  refund=$%d  seg_freed=%s" % [
				pw_key, refund, str(seg_freed_ok)])

		if dead_wire_keys.size() > 0:
			_owner._wdbg("  PlayerWireCull: removed %d wires — endpoint left surviving boundary" % dead_wire_keys.size())

	if boundary_edges.is_empty():
		if _pm_bulk:
			pm.end_bulk()
		return

	var wire_script: GDScript = load("res://scripts/world/power/WireSegment.gd") as GDScript

	## ── Pass A: collect wire node positions ───────────────────────────────────
	##
	## Sources:
	##   1. Every boundary_edges midpoint  → sits on the wall face, Y=1.0
	##   2. Outer corner pillar positions  → ±0.5 fractional on BOTH axes
	##   3. Inward corner pillars          → ±0.75 fractional; snapped to the
	##      wall-face intersection (nearest ±0.5 coordinate on each axis) so
	##      they land axis-aligned with the adjacent wall-run nodes.
	##
	## All positions are deduplicated by "%.3f_%.3f" XZ key.

	var node_positions: Array[Vector3] = []
	var pos_set:        Dictionary     = {}   ## "%.3f_%.3f" → true (dedup guard)

	## Helper: add a position if not already present.
	## Inline as a local lambda (GDScript 4 supports this).
	var _add_pos: Callable = func(p: Vector3) -> void:
		var k: String = "%.3f_%.3f" % [p.x, p.z]
		if not pos_set.has(k):
			pos_set[k] = true
			node_positions.append(p)

	## Source 1 — boundary wall midpoints
	for ekey: String in boundary_edges:
		var wall_pos: Vector3 = boundary_edges[ekey]["pos"]
		_add_pos.call(Vector3(wall_pos.x, WIRE_Y, wall_pos.z))

	## Source 2 & 3 — pillar positions
	for pkey: String in pillar_positions:
		var pp: Vector3 = pillar_positions[pkey]

		## Detect inward corner: fractional part of x or z is ≈0.75 (not 0.5).
		## Outer corners land at exactly ±0.5 from an integer (frac ≈ 0.5).
		## Inward corners land at ±0.75 from an integer (frac ≈ 0.25 or 0.75).
		var frac_x: float = absf(pp.x - roundf(pp.x))
		var frac_z: float = absf(pp.z - roundf(pp.z))
		var x_is_inward: bool = (absf(frac_x - 0.75) < 0.05) or (absf(frac_x - 0.25) < 0.05)
		var z_is_inward: bool = (absf(frac_z - 0.75) < 0.05) or (absf(frac_z - 0.25) < 0.05)
		var is_inward:   bool = x_is_inward or z_is_inward

		if not is_inward:
			## Outer corner — add the pillar XZ directly as a node position.
			_add_pos.call(Vector3(pp.x, WIRE_Y, pp.z))
		else:
			## Inward corner — snap to the wall-face intersection point.
			## The pillar sits at integer ± 0.75; the adjacent wall runs land
			## at integer ± 0.5 (half-units).  Round each axis to the nearest
			## 0.5-multiple that is NOT a whole integer (i.e. the wall face).
			##
			## Algorithm for one axis:
			##   lo = floor(v * 2) / 2      hi = ceil(v * 2) / 2
			##   Choose the one whose absolute value mod 1 ≈ 0.5 (not 0.0).
			var bx_lo: float = floorf(pp.x * 2.0) / 2.0
			var bx_hi: float = ceilf(pp.x  * 2.0) / 2.0
			var bx:    float = bx_hi if (absf(bx_lo - roundf(bx_lo)) < 0.01) else bx_lo

			var bz_lo: float = floorf(pp.z * 2.0) / 2.0
			var bz_hi: float = ceilf(pp.z  * 2.0) / 2.0
			var bz:    float = bz_hi if (absf(bz_lo - roundf(bz_lo)) < 0.01) else bz_lo

			_add_pos.call(Vector3(bx, WIRE_Y, bz))

	## Log Pass A results
	_owner._wdbg("  PassA: %d node positions after dedup" % node_positions.size())
	if _owner.WIRE_DEBUG:
		var sorted_npos: Array[Vector3] = node_positions.duplicate()
		sorted_npos.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return a.x < b.x if absf(a.x - b.x) > 0.001 else a.z < b.z)
		for np: Vector3 in sorted_npos:
			_owner._wdbg("    pos=(%.3f, %.3f)  frac_x=%.3f  frac_z=%.3f" % [
				np.x, np.z,
				absf(np.x - roundf(np.x)),
				absf(np.z - roundf(np.z))])

	if node_positions.is_empty():
		if _pm_bulk:
			pm.end_bulk()
		return

	## ── Pass B: register nodes + connect adjacent pairs ──────────────────────
	##
	## Step B1: register all positions in PM, cache in _owner._auto_wire_nodes.
	## Stage 2 guard: nodes that survived the incremental removal are still
	## valid in PM — skip re-registering them to avoid overwriting their data
	## and triggering spurious solves.  Only truly new positions are registered.
	var node_keys: Array[String]  = []
	var new_node_count:      int  = 0
	var surviving_node_count: int = 0

	for wpos: Vector3 in node_positions:
		var cache_key: String = "%.3f_%.3f_%.3f" % [wpos.x, wpos.y, wpos.z]
		if _owner._auto_wire_nodes.has(cache_key):
			## Node survived — reuse its existing PM key.
			node_keys.append(_owner._auto_wire_nodes[cache_key])
			surviving_node_count += 1
		else:
			## New position — register fresh.
			var pm_key: String = pm.register_wire_node(wpos, "joint", "")
			_owner._auto_wire_nodes[cache_key] = pm_key
			node_keys.append(pm_key)
			new_node_count += 1
	_owner._wdbg("  PassB1: total=%d  new=%d  surviving=%d" % [
		node_keys.size(), new_node_count, surviving_node_count])
	_owner._wdbg("  PassB1 summary: total=%d  new=%d  surviving=%d" % [
		node_keys.size(), new_node_count, surviving_node_count])

	## Step B2: connect every axis-aligned adjacent pair.
	##
	## Connection rules:
	##   • Axis-aligned: one of |dx| or |dz| must be < 0.05 (not diagonal).
	##   • Distance: 0.05 < dist ≤ ADJ_DIST (skip co-located, skip far).
	##   • Not-interior: the segment must not float in open space.
	##     A segment floats when BOTH sides of the wall-normal axis are cleared.
	##     Exception: nodes that land on a pregen wall face coordinate
	##     (±0.5 fractional on BOTH axes, i.e. corner/intersection nodes) are
	##     on the actual physical wall and must always connect — the
	##     cleared-cell check would falsely reject them because the expansion
	##     cells on both sides may both be cleared.
	##
	## "Wall face node" = a node whose XZ both have frac ≈ 0.5 (e.g. -12.5, 4.5).
	## These are corner/pillar positions that sit exactly on the wall boundary.
	## Plain wall-run nodes have exactly ONE axis at a whole integer (frac ≈ 0.0)
	## and the other at 0.5 — they only need the cleared-cell guard on the
	## integer axis.

	var connected_pairs: Dictionary = {}
	var nn: int = node_keys.size()

	## ── Breaker-aware ring: collect surviving breaker nodes ───────────────────
	## Breaker nodes persist in PowerManager across auto-wire teardown (Pass 0
	## preserves any node whose role == "breaker").  They are NOT in
	## node_positions/node_keys, so without this the B2 loop would lay a bypass
	## edge straight THROUGH each breaker (A→B), leaving the ring electrically
	## continuous and merging every zone into one.
	##
	## Instead we detect when a breaker snap-point lies ON the A↔B span and
	## route the connection THROUGH it (A→breaker, breaker→B).  The breaker then
	## becomes a native graph cut-point with correct half-tube visuals — no
	## post-hoc stub-stitch / resplit (Pass C0) needed.
	## ── Stage 3: Incremental PassB2 ────────────────────────────────────────────
	## Only NEW node→NEW node edges and NEW node→SURVIVING node seam edges are
	## registered here.  Surviving node→surviving node edges already exist in PM
	## from the previous rebuild — re-registering them would be a no-op in PM
	## (register_wire_edge deduplicates) but would try to double-spawn visuals.
	## _spawn_auto_wire_seg guards against double-spawn via _owner._auto_wire_segs lookup,
	## so correctness is preserved, but skipping them here avoids the PM call cost.
	##
	## New→surviving seam stitching: after a dig, some new nodes appear adjacent
	## to surviving old nodes (the expansion seam).  Those seam edges must be
	## registered so the new ring section connects into the surviving ring section.
	## We detect them by checking: one endpoint is new, the other is surviving.
	##
	## Breaker-aware split is preserved: any span (new→new, new→surviving) that
	## has a breaker mid-point is chained through the breaker as before.

	## Collect breaker nodes from PM (same as before).
	var brk_nodes_b2: Array[Dictionary] = []   ## [{ "key": String, "pos": Vector3 }]
	for wn_b2: Dictionary in pm.get_wire_nodes():
		if wn_b2.get("role", "") == "breaker":
			brk_nodes_b2.append({"key": wn_b2["key"], "pos": wn_b2["pos"]})
	_owner._wdbg("  PassB2(incr): %d breaker node(s)" % brk_nodes_b2.size())

	## ── All-pairs B2 with visual dedup ──────────────────────────────────────
	## Runs over all node_positions (new + surviving).  Two guards keep it correct:
	##   • PM.register_wire_edge() deduplicates: surviving→surviving edges are
	##     already registered → PM returns the existing edge_id, no-op.
	##   • _spawn_auto_wire_seg() skips edges already in _owner._auto_wire_segs →
	##     surviving visual segs are preserved, never freed/respawned.
	## New→new and new→surviving (seam) edges: not yet in PM or _owner._auto_wire_segs
	## → registered fresh + visual spawned.  This is the seam stitch.
	## Breaker-aware split is preserved across all pair types.
	for i: int in range(nn):
		for j: int in range(i + 1, nn):
			var pa: Vector3 = node_positions[i]
			var pb: Vector3 = node_positions[j]
			var dx:   float = absf(pa.x - pb.x)
			var dz:   float = absf(pa.z - pb.z)

			## Must be axis-aligned
			if dx > 0.05 and dz > 0.05:
				continue
			var dist: float = pa.distance_to(pb)
			if dist < 0.05 or dist > ADJ_DIST:
				continue

			## Interior-stub guard — skip a seg that runs entirely through
			## cleared space (both cells on each side of the wall face cleared).
			##
			## Nodes whose BOTH axes are fractional (frac ≈ 0.5) sit on a wall
			## corner — they always connect because they are the physical wall;
			## skip the cleared-cell check for them.
			var pa_frac_x: float = absf(pa.x - roundf(pa.x))
			var pa_frac_z: float = absf(pa.z - roundf(pa.z))
			var pb_frac_x: float = absf(pb.x - roundf(pb.x))
			var pb_frac_z: float = absf(pb.z - roundf(pb.z))
			var pa_is_corner: bool = (absf(pa_frac_x - 0.5) < 0.05) and (absf(pa_frac_z - 0.5) < 0.05)
			var pb_is_corner: bool = (absf(pb_frac_x - 0.5) < 0.05) and (absf(pb_frac_z - 0.5) < 0.05)

			var skip_seg: bool = false
			var skip_reason: String = ""
			if not (pa_is_corner or pb_is_corner):
				if dz < 0.05:
					var shared_z: float = (pa.z + pb.z) * 0.5
					var cz_below: int   = int(floorf(shared_z))
					var cz_above: int   = cz_below + 1
					var mid_cx:   int   = int(floorf((pa.x + pb.x) * 0.5))
					var below: bool = _owner._cleared_cells.has(str(mid_cx) + "," + str(cz_below))
					var above: bool = _owner._cleared_cells.has(str(mid_cx) + "," + str(cz_above))
					if below and above:
						skip_seg = true
						skip_reason = "HORIZ both_cleared: mid_cx=%d  below=%s(%s)  above=%s(%s)" % [
							mid_cx,
							str(mid_cx)+","+str(cz_below), str(below),
							str(mid_cx)+","+str(cz_above), str(above)]
					elif _owner.WIRE_DEBUG:
						_owner._wdbg("  B2 HORIZ KEEP  pa=(%.3f,%.3f) pb=(%.3f,%.3f)  mid_cx=%d  below[%s]=%s  above[%s]=%s" % [
							pa.x, pa.z, pb.x, pb.z, mid_cx,
							str(mid_cx)+","+str(cz_below), str(below),
							str(mid_cx)+","+str(cz_above), str(above)])
				else:
					var shared_x: float = (pa.x + pb.x) * 0.5
					var cx_left:  int   = int(floorf(shared_x))
					var cx_right: int   = cx_left + 1
					var mid_cz:   int   = int(floorf((pa.z + pb.z) * 0.5))
					var left_c: bool  = _owner._cleared_cells.has(str(cx_left)  + "," + str(mid_cz))
					var right_c: bool = _owner._cleared_cells.has(str(cx_right) + "," + str(mid_cz))
					if left_c and right_c:
						skip_seg = true
						skip_reason = "VERT both_cleared: mid_cz=%d  left=%s(%s)  right=%s(%s)" % [
							mid_cz,
							str(cx_left)+","+str(mid_cz), str(left_c),
							str(cx_right)+","+str(mid_cz), str(right_c)]
					elif _owner.WIRE_DEBUG:
						_owner._wdbg("  B2 VERT KEEP  pa=(%.3f,%.3f) pb=(%.3f,%.3f)  mid_cz=%d  left[%s]=%s  right[%s]=%s" % [
							pa.x, pa.z, pb.x, pb.z, mid_cz,
							str(cx_left)+","+str(mid_cz), str(left_c),
							str(cx_right)+","+str(mid_cz), str(right_c)])
			else:
				_owner._wdbg("  B2 CORNER pa=(%.3f,%.3f) pb=(%.3f,%.3f)  pa_corner=%s  pb_corner=%s — ALWAYS CONNECT" % [
					pa.x, pa.z, pb.x, pb.z, str(pa_is_corner), str(pb_is_corner)])

			if skip_seg:
				_owner._wdbg("  B2 SKIP  pa=(%.3f,%.3f) pb=(%.3f,%.3f)  dist=%.3f  reason: %s" % [
					pa.x, pa.z, pb.x, pb.z, dist, skip_reason])
				continue

			var ka: String       = node_keys[i]
			var kb: String       = node_keys[j]
			var pair_key: String = ka + "|" + kb if ka < kb else kb + "|" + ka
			if connected_pairs.has(pair_key):
				continue
			connected_pairs[pair_key] = true

			## Breaker-aware split — unchanged from old B2.
			var brk_on_span: Array[Dictionary] = []
			for bn: Dictionary in brk_nodes_b2:
				if _point_on_span(bn["pos"], pa, pb):
					brk_on_span.append(bn)

			if brk_on_span.is_empty():
				var edge_id: String = pm.register_wire_edge(ka, kb, null)
				if not edge_id.is_empty() and wire_script != null:
					_owner._wdbg("  B2 EDGE  pa=(%.3f,%.3f) pb=(%.3f,%.3f)  dist=%.3f  edge=%s" % [
						pa.x, pa.z, pb.x, pb.z, dist, edge_id])
					## _spawn_auto_wire_seg guards against double-spawn:
					## surviving segs already exist in _owner._auto_wire_segs → skipped.
					## New seam edges are not in _owner._auto_wire_segs → spawned.
					_spawn_auto_wire_seg(node_positions[i], node_positions[j], edge_id, wire_script)
			else:
				brk_on_span.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
					return pa.distance_squared_to(x["pos"]) < pa.distance_squared_to(y["pos"]))
				var chain_keys: Array[String]  = [ka]
				var chain_pos:  Array[Vector3] = [node_positions[i]]
				for bn: Dictionary in brk_on_span:
					chain_keys.append(bn["key"])
					chain_pos.append(bn["pos"])
				chain_keys.append(kb)
				chain_pos.append(node_positions[j])
				_owner._wdbg("  B2 SPLIT  pa=(%.3f,%.3f) pb=(%.3f,%.3f)  through %d breaker(s)" % [
					pa.x, pa.z, pb.x, pb.z, brk_on_span.size()])
				for seg_i: int in range(chain_keys.size() - 1):
					var sk_a: String  = chain_keys[seg_i]
					var sk_b: String  = chain_keys[seg_i + 1]
					var sp_a: Vector3 = chain_pos[seg_i]
					var sp_b: Vector3 = chain_pos[seg_i + 1]
					var seg_edge: String = pm.register_wire_edge(sk_a, sk_b, null)
					if not seg_edge.is_empty() and wire_script != null:
						_owner._wdbg("    B2 SEG  %s→%s  edge=%s" % [sk_a, sk_b, seg_edge])
						_spawn_auto_wire_seg(sp_a, sp_b, seg_edge, wire_script)

	_owner._wdbg("  PassB2(incr): %d pairs  new_nodes=%d  surviving_nodes=%d" % [
		connected_pairs.size(), new_node_count, surviving_node_count])
	_owner._wdbg("  PassB2 summary: pairs=%d  new_nodes=%d  surviving_nodes=%d  segs_total=%d" % [
		connected_pairs.size(), new_node_count, surviving_node_count, _owner._auto_wire_segs.size()])

	## ── Pass C / C2: REMOVED (Stage 3) ──────────────────────────────────────
	## Lights and generators connect to auto-wire nodes that survive incremental
	## rebuild — their edges are never cascade-deleted, so re-snap is a no-op.
	## Kept as a one-line log so F9 dumps still show the pass marker.

	## ── Pass D: REMOVED (Stage 3) ────────────────────────────────────────────
	## Player wire edges survive incremental rebuild because both endpoints are
	## auto-wire nodes that are never torn down unless their boundary face was
	## removed.  If a dig deletes a node a player wire touches, that wire
	## endpoint simply no longer exists — correct behaviour (no restore needed).
	## _owner._player_wire_segs dict is kept alive; entries are added at placement time
	## and removed when the player explicitly deletes the wire.

	## ── Pass C0: REMOVED ─────────────────────────────────────────────────────
	## Breaker reconnection is now handled NATIVELY by PassB2's breaker-aware
	## ring routing.  When B2 is about to connect two perimeter nodes A→B and a
	## breaker snap-point lies on that span, it routes A→breaker→B instead, so
	## the breaker is a real graph cut-point from the start (correct half-tube
	## visuals, no bypass edge, no phantom degree-1 stub nodes).
	##
	## The old PassC0 (stub-stitch + resplit_breaker) repaired the bypass AFTER
	## the fact by picking the breaker's two nearest nodes — but those could be
	## phantom bypass endpoints, producing dangling 1-edge "stub zones" and a
	## still-continuous ring.  That whole approach is obsolete; B2 fixes it at
	## the source.

	## Seed / restore the zone color registry then recolor all wires.
	##
	## Continuity rule (user decision):
	##   Zones whose rep keys survive into the rebuilt graph inherit their old
	##   colors (best-effort).  Zones whose topology changed merge/split and
	##   get re-colored naturally by get_wire_zones_with_colors().
	##
	## We restore the pre-teardown snapshot first so that
	## get_wire_zones_with_colors() can match surviving rep keys to their old
	## colors.  Without this, every rebuild produces a blank registry and all
	## zones get fresh (often wrong) colors.
	##
	## Direct call (NOT deferred) — must run synchronously after all edges are
	## registered so the registry is fully seeded before the player's first wire
	## draw.  call_deferred fires between registration passes and leaves the
	## registry empty, causing phantom zone colors.
	## Skip restore when breakers were removed — the old registry describes zones
	## that no longer exist (breakers gone = topology changed), so restoring it
	## would prevent any new zone colors from matching. Let recolor run fresh.
	var _restore_decision: String = "SKIP" if (breakers_removed or zone_color_snap.is_empty()) else "RESTORE"
	_owner._wdbg("  Restore: breakers_removed=%s  snap_empty=%s  decision=%s  snap_keys=%s" % [
		str(breakers_removed), str(zone_color_snap.is_empty()),
		_restore_decision, str(zone_color_snap.keys())])
	if not breakers_removed and not zone_color_snap.is_empty():
		pm.restore_zone_colors(zone_color_snap)
	## Recolor wire visuals on the NEXT frame (via process_frame one-shot) so
	## that all deferred BreakerBox._register_wire_deferred() calls have already
	## fired and the zone graph is fully up-to-date before we assign colors.
	## Calling it synchronously here would run before the breakers split their
	## edges (deferred), producing an incomplete zone graph and wrong colors.
	## Guard: only recolor when build mode is active.
	if _owner._build_controller != null \
			and _owner._build_controller.has_method("_recolor_wire_zones"):
		var bc: Node = _owner._build_controller   ## capture for lambda
		_owner.get_tree().process_frame.connect(
			func() -> void:
				if bc != null and is_instance_valid(bc) \
						and bc.get("is_active") == true:
					bc.call("_recolor_wire_zones"),
			CONNECT_ONE_SHOT
		)

	_owner._wdbg("  SUMMARY: auto_wire_nodes=%d  auto_wire_segs=%d  player_wire_segs=%d" % [
		_owner._auto_wire_nodes.size(), _owner._auto_wire_segs.size(), _owner._player_wire_segs.size()])
	_owner._wdbg("=== _rebuild_auto_wires END ===")

	## Close the bulk window — runs the single coalesced solve now that the
	## entire wire graph has been re-registered with complete topology.
	if _pm_bulk:
		pm.end_bulk()

	## Reconciler retired (Stage 5) — no notify needed.

	## ── Stage 0 oracle ────────────────────────────────────────────────────────
	## Runs only when _owner.WIRE_DEBUG = true.  Call after the full rebuild so the graph
	## is in its final state.  Failures print [ORACLE FAIL] to Output and the
	## wire debug log — they do NOT crash the game.  Used to validate correctness
	## of the current system before the incremental refactor modifies anything.
	if _owner.WIRE_DEBUG:
		_verify_graph_matches_boundary(boundary_edges, pillar_positions, pm)

## ── Stage 1: boundary edge diff ──────────────────────────────────────────────
## Computes and logs the diff between the previous boundary set and the new one.
## Returns a Dictionary with keys "added" and "removed", each an Array[String]
## of boundary_edge ekeys.  In Stage 1 the return value is ignored — this is
## logging only.  Stage 2+ will consume the return value to drive incremental
## node removal/addition instead of the full bulldoze.
##
## Call AFTER _rebuild_auto_wires() with the fresh boundary_edges dict, then
## update _owner._boundary_edges_prev to the new snapshot.
func _compute_boundary_diff(boundary_new: Dictionary) -> Dictionary:
	var added:   Array[String] = []
	var removed: Array[String] = []

	## Keys present in new but not in prev → newly exposed wall faces.
	for ekey: String in boundary_new:
		if not _owner._boundary_edges_prev.has(ekey):
			added.append(ekey)

	## Keys present in prev but not in new → wall faces that became interior.
	for ekey: String in _owner._boundary_edges_prev:
		if not boundary_new.has(ekey):
			removed.append(ekey)

	if _owner.WIRE_DEBUG:
		_owner._wdbg("[diff]  added=%d  removed=%d  total_prev=%d  total_new=%d" % [
			added.size(), removed.size(),
			_owner._boundary_edges_prev.size(), boundary_new.size()])
		## Log individual added/removed keys — buffered only (can be noisy).
		for ekey: String in added:
			var p: Vector3 = boundary_new[ekey]["pos"]
			_owner._wdbg("  [+] %s  pos=(%.3f,%.3f)" % [ekey, p.x, p.z])
		for ekey: String in removed:
			var p: Vector3 = _owner._boundary_edges_prev[ekey]["pos"]
			_owner._wdbg("  [-] %s  pos=(%.3f,%.3f)" % [ekey, p.x, p.z])

	## Advance the snapshot AFTER logging (so "prev" still refers to the old
	## set during logging above).
	_owner._boundary_edges_prev = boundary_new.duplicate()

	return {"added": added, "removed": removed}

## ── Stage 2: node-position helper ───────────────────────────────────────────
## Returns a Dictionary of cache_key ("%.3f_%.3f_%.3f") -> Vector3 for every
## wire node position that should exist for the given boundary_edges + pillar_positions.
## Mirrors the PassA dedup logic exactly — single source of truth used by both
## incremental removal (Stage 2) and PassB1 registration.
func _compute_node_positions(boundary_edges: Dictionary,
		pillar_positions: Dictionary) -> Dictionary:
	const WIRE_Y: float = 1.0
	var result: Dictionary = {}   ## cache_key -> Vector3

	var _add: Callable = func(p: Vector3) -> void:
		var k: String = "%.3f_%.3f_%.3f" % [p.x, WIRE_Y, p.z]
		if not result.has(k):
			result[k] = Vector3(p.x, WIRE_Y, p.z)

	## Source 1: boundary wall midpoints
	for ekey: String in boundary_edges:
		var wp: Vector3 = boundary_edges[ekey]["pos"]
		_add.call(wp)

	## Source 2 & 3: pillar positions (outer corners + inward corners snapped)
	for pkey: String in pillar_positions:
		var pp: Vector3 = pillar_positions[pkey]
		var frac_x: float = absf(pp.x - roundf(pp.x))
		var frac_z: float = absf(pp.z - roundf(pp.z))
		var x_is_inward: bool = (absf(frac_x - 0.75) < 0.05) or (absf(frac_x - 0.25) < 0.05)
		var z_is_inward: bool = (absf(frac_z - 0.75) < 0.05) or (absf(frac_z - 0.25) < 0.05)
		if not (x_is_inward or z_is_inward):
			_add.call(pp)
		else:
			var bx_lo: float = floorf(pp.x * 2.0) / 2.0
			var bx_hi: float = ceilf(pp.x  * 2.0) / 2.0
			var bx:    float = bx_hi if (absf(bx_lo - roundf(bx_lo)) < 0.01) else bx_lo
			var bz_lo: float = floorf(pp.z * 2.0) / 2.0
			var bz_hi: float = ceilf(pp.z  * 2.0) / 2.0
			var bz:    float = bz_hi if (absf(bz_lo - roundf(bz_lo)) < 0.01) else bz_lo
			_add.call(Vector3(bx, WIRE_Y, bz))

	return result

## ── Stage 0: correctness oracle ──────────────────────────────────────────────
## Asserts two invariants after every _rebuild_auto_wires():
##
##  INVARIANT 1 (coverage): every boundary wall-face position has at least one
##    "joint" wire node within ORACLE_SNAP_DIST XZ.  If a position is uncovered,
##    something in PassA or PassB1 dropped it.
##
##  INVARIANT 2 (no orphans): every "joint" node registered in _owner._auto_wire_nodes
##    is within ORACLE_SNAP_DIST XZ of at least one boundary edge or pillar.
##    If not, it is a ghost node that should have been removed (or was never
##    valid). Corner/pillar nodes are exempt from this check because they are
##    keyed by pillar_positions, not boundary_edges.
##
## _owner.WIRE_DEBUG gate is checked by the caller — this function always runs the full
## check.  It emits prints and log lines but NEVER pushes errors or asserts.
func _verify_graph_matches_boundary(
		boundary_edges: Dictionary,
		pillar_positions: Dictionary,
		pm: PowerManager) -> void:

	const ORACLE_SNAP_DIST: float = 0.65   ## wire node vs boundary face snap tolerance (XZ only)

	## Build a flat list of all boundary XZ positions (edges + pillars) for fast
	## distance lookup.  pillar_positions values are Vector3; boundary_edges
	## values are dicts with a "pos" key.
	var all_boundary_xz: Array[Vector2] = []
	for ekey: String in boundary_edges:
		var p: Vector3 = boundary_edges[ekey]["pos"]
		all_boundary_xz.append(Vector2(p.x, p.z))
	for pkey: String in pillar_positions:
		var p: Vector3 = pillar_positions[pkey]
		all_boundary_xz.append(Vector2(p.x, p.z))

	## Helper: is this XZ within ORACLE_SNAP_DIST of any boundary position?
	var _near_boundary: Callable = func(xz: Vector2) -> bool:
		for bxz: Vector2 in all_boundary_xz:
			if xz.distance_to(bxz) <= ORACLE_SNAP_DIST:
				return true
		return false

	## ── INVARIANT 1: every boundary edge/pillar is covered by a joint node ───
	## Build a flat list of all joint XZ positions from _owner._auto_wire_nodes.
	## _owner._auto_wire_nodes keys are "%.3f_%.3f_%.3f" (x_y_z) — parse the x and z.
	var joint_xz_list: Array[Vector2] = []
	for cache_key: String in _owner._auto_wire_nodes:
		var parts: PackedStringArray = cache_key.split("_")
		if parts.size() < 3:
			continue
		var kx: float = float(parts[0])
		var kz: float = float(parts[2])
		## Only count "joint" roles to exclude breaker/generator/battery nodes
		## that happen to share a cache_key format.
		var pm_key: String = _owner._auto_wire_nodes[cache_key]
		var role: String = ""
		if pm != null:
			role = pm.get_wire_node_role(pm_key)
		## Breaker nodes sit exactly on boundary edge midpoints — they count as
		## valid coverage.  Exclude generator/battery (they're interior nodes).
		if role == "joint" or role == "breaker" or role == "":
			joint_xz_list.append(Vector2(kx, kz))

	var inv1_fails: int = 0
	for ekey: String in boundary_edges:
		var ep: Vector3 = boundary_edges[ekey]["pos"]
		var exz: Vector2 = Vector2(ep.x, ep.z)
		var covered: bool = false
		for jxz: Vector2 in joint_xz_list:
			if exz.distance_to(jxz) <= ORACLE_SNAP_DIST:
				covered = true
				break
		if not covered:
			inv1_fails += 1
			_owner._wdbg("[ORACLE FAIL] INV1 — boundary edge UNCOVERED  ekey=%s  pos=(%.3f,%.3f)" % [
				ekey, ep.x, ep.z])
			print("[ORACLE FAIL] INV1 — boundary edge UNCOVERED  ekey=%s  pos=(%.3f,%.3f)" % [
				ekey, ep.x, ep.z])

	## Pillar coverage check
	var inv1p_fails: int = 0
	for pkey: String in pillar_positions:
		var pp: Vector3 = pillar_positions[pkey]
		var pxz: Vector2 = Vector2(pp.x, pp.z)
		var covered: bool = false
		for jxz: Vector2 in joint_xz_list:
			if pxz.distance_to(jxz) <= ORACLE_SNAP_DIST:
				covered = true
				break
		if not covered:
			inv1p_fails += 1
			_owner._wdbg("[ORACLE FAIL] INV1p — pillar UNCOVERED  pkey=%s  pos=(%.3f,%.3f)" % [
				pkey, pp.x, pp.z])
			print("[ORACLE FAIL] INV1p — pillar UNCOVERED  pkey=%s  pos=(%.3f,%.3f)" % [
				pkey, pp.x, pp.z])

	## ── INVARIANT 2: every joint node is near a boundary/pillar (no orphans) ─
	var inv2_fails: int = 0
	for cache_key: String in _owner._auto_wire_nodes:
		var pm_key: String = _owner._auto_wire_nodes[cache_key]
		var role: String = ""
		if pm != null:
			role = pm.get_wire_node_role(pm_key)
		if role != "joint" and role != "":
			continue   ## skip breaker / generator / battery nodes
		## Get position from PM for accuracy (cache_key parsing can have float drift).
		var node_pos: Vector3 = Vector3.ZERO
		if pm != null:
			node_pos = pm.get_wire_node_pos(pm_key)
		var nxz: Vector2 = Vector2(node_pos.x, node_pos.z)
		if not _near_boundary.call(nxz):
			inv2_fails += 1
			_owner._wdbg("[ORACLE FAIL] INV2 — ORPHAN joint node  cache_key=%s  pm_key=%s  pos=(%.3f,%.3f)" % [
				cache_key, pm_key, node_pos.x, node_pos.z])
			print("[ORACLE FAIL] INV2 — ORPHAN joint node  cache_key=%s  pm_key=%s  pos=(%.3f,%.3f)" % [
				cache_key, pm_key, node_pos.x, node_pos.z])

	## ── Summary ───────────────────────────────────────────────────────────────
	var pass_fail: String = "PASS" if (inv1_fails + inv1p_fails + inv2_fails == 0) else "FAIL"
	_owner._wdbg("[ORACLE %s]  INV1_edge=%d fails  INV1_pillar=%d fails  INV2_orphan=%d fails  boundary_edges=%d  pillars=%d  joints=%d" % [
		pass_fail, inv1_fails, inv1p_fails, inv2_fails,
		boundary_edges.size(), pillar_positions.size(), joint_xz_list.size()])
	print("[ORACLE %s]  edge_fails=%d  pillar_fails=%d  orphan_fails=%d  joints=%d  boundaries=%d+%d" % [
		pass_fail, inv1_fails, inv1p_fails, inv2_fails,
		joint_xz_list.size(), boundary_edges.size(), pillar_positions.size()])

## Returns true if point `p` lies ON the axis-aligned span a↔b (between the two
## endpoints, not at either end).  Used by PassB2 to detect a breaker node that
## sits mid-span so the ring is routed THROUGH it instead of bypassing it.
## Tolerance is generous on the perpendicular axis (snap-grid jitter) and
## strict-but-inclusive on the parallel axis.
func _point_on_span(p: Vector3, a: Vector3, b: Vector3) -> bool:
	const PERP_TOL: float = 0.20   ## off-line tolerance (perpendicular distance)
	const END_TOL:  float = 0.05   ## exclude points sitting on an endpoint
	## Must lie within the segment's bounding box (with a tiny margin).
	var min_x: float = minf(a.x, b.x) - PERP_TOL
	var max_x: float = maxf(a.x, b.x) + PERP_TOL
	var min_z: float = minf(a.z, b.z) - PERP_TOL
	var max_z: float = maxf(a.z, b.z) + PERP_TOL
	if p.x < min_x or p.x > max_x or p.z < min_z or p.z > max_z:
		return false
	## Reject points coincident with either endpoint — those aren't "mid-span".
	if p.distance_to(a) < END_TOL or p.distance_to(b) < END_TOL:
		return false
	## Perpendicular distance from p to the infinite line through a→b.
	var ab: Vector3 = b - a
	var ab_len: float = ab.length()
	if ab_len < 0.001:
		return false
	var ap: Vector3 = p - a
	## Cross-product magnitude / |ab| = perpendicular distance (XZ plane).
	var cross_y: float = ab.x * ap.z - ab.z * ap.x
	var perp_dist: float = absf(cross_y) / ab_len
	return perp_dist <= PERP_TOL

## Spawns a WireSegment visual for an auto-wired edge.
func _spawn_auto_wire_seg(
		pos_a: Vector3, pos_b: Vector3,
		edge_id: String, wire_script: GDScript) -> void:

	## Don't double-spawn the same edge
	if _owner._auto_wire_segs.has(edge_id):
		return

	var seg: Node3D = Node3D.new()
	seg.set_script(wire_script)
	seg.name = "AutoWireSegment"
	_owner.add_child(seg)
	seg.set_meta("_is_pregen", true)  ## Protects from deletion + suppresses red highlight in build mode
	if seg.has_method("set_endpoints"):
		seg.call("set_endpoints", pos_a, pos_b)
	if "edge_id" in seg:
		seg.edge_id = edge_id

	## If build mode is currently active when this segment is spawned
	## (e.g. player digs a chunk while in build mode), make it visible
	## immediately — the call_group("wire_segment", "set_visible", true)
	## already fired before this segment existed.
	if _owner._build_controller != null and _owner._build_controller.get("is_active") == true:
		seg.visible = true

	_owner._auto_wire_segs[edge_id] = seg

	## Register the scene node with PM so _split_wire_edge_at() can find and
	## resize this visual when a breaker is placed on a pregen wire.
	## Without this, PM's edge dict has node=null, the split can't resize the
	## tube, and the original full-length segment stays visible as a ghost.
	var pm: PowerManager = _owner.get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		pm.set_wire_edge_node(edge_id, seg)

## ─── Rock chunk UNDO (restore) handler ──────────────────────────────────────
## Called when a previously-dug chunk is restored via Undo.
## Removes all auto-fill nodes whose world positions fall inside the
## restored chunk cells, then re-runs the global perimeter solve so
## walls/pillars along adjacent cleared chunks regenerate correctly.
func _on_chunk_restored(chunk_origin: Vector2i) -> void:
	if _owner._build_controller == null or _owner.rock_surround == null:
		return

	var offset_x: float = _owner.rock_surround.OFFSET_X
	var offset_z: float = _owner.rock_surround.OFFSET_Z
	var chunk_size: int = _owner.rock_surround.chunk_size
	var gm: GridMap     = _owner._build_controller.gridmap

	const FLOOR_Y_ROW: int = -6
	const PLACEMENT_Y: float = 2.0
	const TILE_WALL:   int   = 1
	const TILE_PILLAR: int   = 2

	## ── Step 1: un-register the restored chunk's cells from _owner._cleared_cells ───
	## and remove the floor tiles that were stamped when the chunk was dug.
	const SHIFT_X: float = -0.5
	const SHIFT_Z: float = -0.5
	for dx: int in range(chunk_size):
		for dz: int in range(chunk_size):
			var wx: float = float(chunk_origin.x + dx) + 0.5 + offset_x
			var wz: float = float(chunk_origin.y + dz) + 0.5 + offset_z
			var cx: int   = int(floor(wx))
			var cz: int   = int(floor(wz))
			_owner._cleared_cells.erase(str(cx) + "," + str(cz))
			var fcx: int = int(floor(wx + SHIFT_X))
			var fcz: int = int(floor(wz + SHIFT_Z))
			if gm != null:
				gm.set_cell_item(Vector3i(fcx, FLOOR_Y_ROW, fcz), GridMap.INVALID_CELL_ITEM)

	## ── Step 2: remove ONLY autofill nodes adjacent to the restored chunk ────
	## "Adjacent" = world position within (chunk_size + 1) cells of chunk centre.
	## This avoids nuking the entire autofill set (which loses pregen bunker walls).
	var chunk_world_cx: float = float(chunk_origin.x) + float(chunk_size) * 0.5 + offset_x
	var chunk_world_cz: float = float(chunk_origin.y) + float(chunk_size) * 0.5 + offset_z
	var cull_radius: float    = float(chunk_size) * 0.5 + 1.5   ## half-chunk + 1 cell margin

	var to_remove: Array = []
	for akey: String in _owner._autofill_nodes:
		var parts: PackedStringArray = akey.split(",")
		if parts.size() < 2:
			continue
		var ax: float = float(parts[0])
		var az: float = float(parts[1])
		if absf(ax - chunk_world_cx) <= cull_radius and absf(az - chunk_world_cz) <= cull_radius:
			to_remove.append(akey)

	for akey: String in to_remove:
		var node: Node3D = _owner._autofill_nodes[akey]
		if is_instance_valid(node):
			if _owner._build_controller.has_method("remove_placed_object"):
				_owner._build_controller.remove_placed_object(node)
			node.queue_free()
		_owner._autofill_nodes.erase(akey)

	## ── Step 2b: wire teardown deferred to _rebuild_auto_wires below ─────────
	## Full teardown+rebuild happens after the perimeter re-solve in Step 3 so
	## _rebuild_auto_wires receives the correct complete boundary_edges dict.
	## No per-chunk partial wire removal needed — _rebuild_auto_wires handles
	## the entire graph atomically.

	## ── Step 3: single full global perimeter re-solve ────────────────────────
	## Run ONE pass over all _owner._cleared_cells to decide what walls/pillars are
	## needed. We must not call _on_chunk_deconstructed here — that re-stamps
	## floors and re-registers cells (idempotent but confusing). Instead we
	## inline just the perimeter solve (Passes 2–5 of _on_chunk_deconstructed).
	if _owner._cleared_cells.is_empty():
		return

	var DIRS: Array = [
		[-1,  0, "left",    -0.5,  0.0, 180.0],
		[ 1,  0, "right",    0.5,  0.0,   0.0],
		[ 0, -1, "top",      0.0, -0.5,  90.0],
		[ 0,  1, "bottom",   0.0,  0.5, 270.0],
	]

	var boundary_edges: Dictionary = {}
	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int   = int(parts[0])
		var cz: int   = int(parts[1])
		var ccx: float = float(cx) + 0.5 - 0.5
		var ccz: float = float(cz) + 0.5 - 0.5
		for d: Array in DIRS:
			var nkey: String = str(cx + int(d[0])) + "," + str(cz + int(d[1]))
			if _owner._cleared_cells.has(nkey):
				continue
			var wx: float    = ccx + float(d[3])
			var wz: float    = ccz + float(d[4])
			var ekey: String = _owner._wkey(wx) + "," + _owner._wkey(wz)
			boundary_edges[ekey] = {"pos": Vector3(wx, PLACEMENT_Y, wz), "angle": float(d[5])}

	var pillar_positions: Dictionary = {}
	var SX: Array = [-1, 1]
	var SZ: Array = [-1, 1]
	for ckey: String in _owner._cleared_cells:
		var parts: PackedStringArray = ckey.split(",")
		var cx: int   = int(parts[0])
		var cz: int   = int(parts[1])
		var ccx: float = float(cx) + 0.5 - 0.5
		var ccz: float = float(cz) + 0.5 - 0.5
		for sx: int in SX:
			for sz: int in SZ:
				var x_is_boundary: bool = not _owner._cleared_cells.has(str(cx + sx) + "," + str(cz))
				var z_is_boundary: bool = not _owner._cleared_cells.has(str(cx) + "," + str(cz + sz))
				if x_is_boundary and z_is_boundary:
					var px: float    = ccx + float(sx) * 0.5
					var pz: float    = ccz + float(sz) * 0.5
					pillar_positions[_owner._wkey(px) + "," + _owner._wkey(pz)] = Vector3(px, PLACEMENT_Y, pz)
				## Inward (concave) corners
				if _owner._cleared_cells.has(str(cx + sx) + "," + str(cz)) \
						and _owner._cleared_cells.has(str(cx) + "," + str(cz + sz)) \
						and not _owner._cleared_cells.has(str(cx + sx) + "," + str(cz + sz)):
					var px: float    = ccx + float(sx) * 0.75
					var pz: float    = ccz + float(sz) * 0.75
					pillar_positions[_owner._wkey(px) + "," + _owner._wkey(pz)] = Vector3(px, PLACEMENT_Y, pz)

	## Desired set = boundary edges + pillars
	var desired: Dictionary = {}
	for ekey: String in boundary_edges:
		desired[ekey] = true
	for pkey: String in pillar_positions:
		desired[pkey] = true

	## Remove any remaining autofill nodes no longer needed
	var stale: Array = []
	for akey: String in _owner._autofill_nodes:
		if not desired.has(akey):
			stale.append(akey)
	for akey: String in stale:
		var node: Node3D = _owner._autofill_nodes[akey]
		if is_instance_valid(node):
			if _owner._build_controller.has_method("remove_placed_object"):
				_owner._build_controller.remove_placed_object(node)
			node.queue_free()
		_owner._autofill_nodes.erase(akey)

	## Spawn missing walls
	for ekey: String in boundary_edges:
		if _owner._autofill_nodes.has(ekey):
			continue
		var data: Dictionary = boundary_edges[ekey]
		var node: Node3D = _owner._build_controller.spawn_structure(
			TILE_WALL, data["pos"], data["angle"])
		if node != null:
			_owner._autofill_nodes[ekey] = node

	## Spawn missing pillars
	for pkey: String in pillar_positions:
		if _owner._autofill_nodes.has(pkey):
			continue
		var node: Node3D = _owner._build_controller.spawn_structure(
			TILE_PILLAR, pillar_positions[pkey], 0.0)
		if node != null:
			_owner._autofill_nodes[pkey] = node

	## ── Step 4: incremental wire graph rebuild (Stage 3 unified path) ──────────
	## Undo is a symmetric boundary edit — exactly like a dig, just removing
	## boundary edges instead of adding them.  The same _rebuild_auto_wires()
	## call handles both: Stage2 removal prunes nodes whose positions are no
	## longer in the desired set; PassB2 stitches the surviving ring closed.
	## No separate bespoke undo rebuild needed.
	_rebuild_auto_wires(boundary_edges, pillar_positions, false)
	## Update _owner._boundary_edges_prev so the next diff is correct.
	_compute_boundary_diff(boundary_edges)
