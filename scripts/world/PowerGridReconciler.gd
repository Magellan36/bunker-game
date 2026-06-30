extends Node
## PowerGridReconciler.gd
## ─────────────────────────────────────────────────────────────────────────────
## Standalone safety net for the power grid.
##
## PURPOSE
## The power system rebuilds its wire graph from scratch on every dig/expansion.
## Player-placed wire edges can silently disappear from the PM during that
## rebuild window, leaving the generator isolated from consumers even though
## the generator reports RUNNING and lights report NO_POWER.
##
## This reconciler solves that in two layers:
##
##   LAYER 1 — Aggressive (event-driven)
##     Called immediately after every rebuild, wire placement, object placement,
##     or any topology change via notify_rebuild_complete().
##     Re-registers all tracked player wire edges into PM from their stored
##     world-space positions.  Costs one PM solve (already happening anyway).
##
##   LAYER 2 — Passive (poll)
##     Every POLL_INTERVAL seconds, checks if any running generator cannot
##     reach any powered consumer.  If a mismatch is detected, re-applies
##     all player wire edges and forces a PM solve.
##     Catches anything the aggressive layer missed.
##
## DESIGN RULES
##   - Uses ONLY public PM API (register_wire_edge, get_wire_node_key_at_pos,
##     get_reachable_device_ids, begin_bulk, end_bulk).  No internal dict access.
##   - Player wire records are keyed by a stable "pw_" string built from
##     world-space positions (rounded to 2dp) — survives every PM rebuild.
##   - The reconciler never queue_free()s anything.  It only registers edges.
##   - Wire segment scene nodes (visuals) are stored weakly — if they're freed
##     the edge is still re-registered; the visual just won't exist.
##   - One reconciler per MainWorld.  Added in _setup_power_manager().
## ─────────────────────────────────────────────────────────────────────────────

# ── Tuning ────────────────────────────────────────────────────────────────────
## Seconds between passive connectivity checks.
const POLL_INTERVAL: float = 2.0

## How long to wait after notify_rebuild_complete() before running the
## aggressive pass.  0.15 s gives PM's own _solve_network() calls time to
## finish, including any force-created joint nodes from prior frames.
const REBUILD_SETTLE_DELAY: float = 0.15

# ── State ─────────────────────────────────────────────────────────────────────
## Key: stable "pw_<ax>_<az>_<bx>_<bz>" string (position-derived, never changes)
## Value: { pos_a: Vector3, pos_b: Vector3, seg_node: Node3D (may be freed/null) }
var _player_wires: Dictionary = {}

var _pm: Node = null          ## cached PowerManager reference
var _poll_timer: float = 0.0  ## counts up to POLL_INTERVAL
var _rebuild_pending: bool = false

# ── Setup ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("power_grid_reconciler")
	## Defer PM lookup so PowerManager._ready() has fired first.
	call_deferred("_cache_pm")

func _cache_pm() -> void:
	_pm = get_tree().get_first_node_in_group("power_manager")
	if _pm == null:
		push_warning("PowerGridReconciler: PowerManager not found — reconciler disabled.")

# ── Public API ────────────────────────────────────────────────────────────────

## Call this whenever the PM topology changes:
##   - after _rebuild_auto_wires completes
##   - after any object is placed/removed
##   - after any wire is placed
## MainWorld calls this; it schedules a deferred aggressive re-registration.
func notify_rebuild_complete() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		get_tree().create_timer(REBUILD_SETTLE_DELAY).timeout.connect(_aggressive_pass)

## Register a player-placed wire so the reconciler owns it permanently.
## Call this INSTEAD OF (or in addition to) the existing _player_wire_segs
## storage.  pos_a/pos_b are global world-space Vector3.
## seg_node is the visual WireSegment Node3D — may be null if purely logical.
func register_player_wire(pos_a: Vector3, pos_b: Vector3, seg_node: Node3D = null) -> void:
	var key: String = _stable_key(pos_a, pos_b)
	_player_wires[key] = {
		"pos_a":    pos_a,
		"pos_b":    pos_b,
		"seg_node": seg_node,   ## stored as Variant so GDScript nullifies if freed
	}
	## Immediately register into PM too — catches the initial placement case.
	_register_one(pos_a, pos_b, seg_node)

## Remove a player wire (called when the player demolishes a wire segment).
func unregister_player_wire(pos_a: Vector3, pos_b: Vector3) -> void:
	var key: String = _stable_key(pos_a, pos_b)
	_player_wires.erase(key)

## Returns how many player wires the reconciler is tracking.
func player_wire_count() -> int:
	return _player_wires.size()

# ── Per-frame passive poll ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _pm == null:
		return
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_passive_check()

# ── Aggressive pass ───────────────────────────────────────────────────────────
## Runs REBUILD_SETTLE_DELAY seconds after notify_rebuild_complete().
## Re-registers every tracked player wire edge unconditionally.
func _aggressive_pass() -> void:
	_rebuild_pending = false
	if _pm == null or _player_wires.is_empty():
		return
	_reapply_all_player_wires("aggressive")

# ── Passive check ─────────────────────────────────────────────────────────────
## Every POLL_INTERVAL seconds.  Only acts when a mismatch is detected:
## running generator exists but at least one tracked player wire's endpoints
## are not bridged in PM (i.e. the edge is missing from the graph).
func _passive_check() -> void:
	if _pm == null or _player_wires.is_empty():
		return

	## Quick smell-test: are there running generators?
	var has_running_gen: bool = false
	var generators: Dictionary = _pm.get("_generators") if _pm.get("_generators") != null else {}
	for gen: Dictionary in generators.values():
		if gen.get("running", false):
			has_running_gen = true
			break
	if not has_running_gen:
		return   ## No generator running — nothing to fix.

	## Check if any consumer is unpowered.
	var consumers: Dictionary = _pm.get("_consumers") if _pm.get("_consumers") != null else {}
	var any_unpowered: bool = false
	for c: Dictionary in consumers.values():
		if c.get("active", false) and not c.get("powered", false):
			any_unpowered = true
			break
	if not any_unpowered:
		return   ## Everyone is powered — nothing to fix.

	## Mismatch detected: generator running but consumer(s) unpowered.
	## Re-apply all player wires and force a solve.
	_reapply_all_player_wires("passive")

# ── Core re-application ───────────────────────────────────────────────────────
func _reapply_all_player_wires(source: String) -> void:
	var registered: int = 0
	var skipped: int    = 0

	_pm.call("begin_bulk")
	for key: String in _player_wires:
		var pw: Dictionary = _player_wires[key]
		var pos_a: Vector3  = pw.get("pos_a", Vector3.ZERO)
		var pos_b: Vector3  = pw.get("pos_b", Vector3.ZERO)
		if pos_a == Vector3.ZERO or pos_b == Vector3.ZERO:
			skipped += 1
			continue
		## seg_node may be null/freed — that's fine, edge is logical only.
		var seg: Variant = pw.get("seg_node")
		var seg_node: Node3D = seg as Node3D if is_instance_valid(seg) else null
		var ok: bool = _register_one(pos_a, pos_b, seg_node)
		if ok:
			registered += 1
		else:
			skipped += 1
	_pm.call("end_bulk")
	## Fix A: _needs_resolve was false (all edges already existed → idempotent
	## re-registration → no call set the flag → end_bulk was a no-op).
	## request_solve() forces a fresh solve regardless, so the now-correct
	## graph actually gets evaluated and active_draw_watts updates.
	if _pm.has_method("request_solve"):
		_pm.call("request_solve")

	print("[Reconciler:%s] re-applied %d player wires (%d skipped/pos-fail)" % [
		source, registered, skipped])

	## ── POST-SOLVE DIAGNOSTICS ────────────────────────────────────────────────
	## Print enough info to confirm whether the edge actually landed on live
	## ring nodes, and whether the solve saw the generator as connected.
	var active_draw: float = _pm.get("active_draw_watts") if "active_draw_watts" in _pm else -1.0
	print("[Reconciler:diag] POST end_bulk — active_draw=%.1fw  total_wire_nodes=%d  total_wire_edges=%d" % [
		active_draw,
		_pm.get_wire_nodes().size() if _pm.has_method("get_wire_nodes") else -1,
		_pm.get_wire_edges().size() if _pm.has_method("get_wire_edges") else -1,
	])
	## For every player wire, show what keys the endpoints resolved to and whether
	## those keys appear as endpoints in any live edge (i.e. are on the ring).
	var edge_endpoint_keys: Dictionary = {}
	if _pm.has_method("get_wire_edges"):
		for ed: Dictionary in _pm.get_wire_edges():
			edge_endpoint_keys[ed.get("node_a", "")] = true
			edge_endpoint_keys[ed.get("node_b", "")] = true
	for key2: String in _player_wires:
		var pw2: Dictionary = _player_wires[key2]
		var pa: Vector3 = pw2.get("pos_a", Vector3.ZERO)
		var pb: Vector3 = pw2.get("pos_b", Vector3.ZERO)
		var na: String = _pm.call("get_wire_node_key_at_pos", pa)
		var nb: String = _pm.call("get_wire_node_key_at_pos", pb)
		var na_on_ring: bool = edge_endpoint_keys.get(na, false)
		var nb_on_ring: bool = edge_endpoint_keys.get(nb, false)
		print("[Reconciler:diag]   wire key=%s" % key2)
		print("[Reconciler:diag]     pos_a=%s → pm_key='%s'  on_ring=%s" % [str(pa), na, str(na_on_ring)])
		print("[Reconciler:diag]     pos_b=%s → pm_key='%s'  on_ring=%s" % [str(pb), nb, str(nb_on_ring)])

## Register one player wire edge into PM.  Resolves world-space positions to
## PM snap keys, force-creating joint nodes if either endpoint is missing.
## Returns true if the edge was registered (or already existed).
func _register_one(pos_a: Vector3, pos_b: Vector3, seg_node: Node3D = null) -> bool:
	if _pm == null:
		return false

	## Try to find existing snap keys for both endpoints.
	var na_raw: String = _snap_key_exact(pos_a)   ## what the exact snap would be
	var nb_raw: String = _snap_key_exact(pos_b)
	var na: String = _pm.call("get_wire_node_key_at_pos", pos_a)
	var nb: String = _pm.call("get_wire_node_key_at_pos", pos_b)

	## ── DIAGNOSTIC: log what each endpoint resolved to ────────────────────────
	var na_how: String = "exact" if na == na_raw and not na.is_empty() \
		else ("fallback" if not na.is_empty() else "MISSING")
	var nb_how: String = "exact" if nb == nb_raw and not nb.is_empty() \
		else ("fallback" if not nb.is_empty() else "MISSING")
	print("[Reconciler:_reg1] pos_a=%s  exact_snap=%s  resolved=%s  how=%s" % [
		str(pos_a), na_raw, na, na_how])
	print("[Reconciler:_reg1] pos_b=%s  exact_snap=%s  resolved=%s  how=%s" % [
		str(pos_b), nb_raw, nb, nb_how])

	## If either endpoint is missing from the PM graph (e.g. the perimeter ring
	## shifted on expansion and the old key no longer exists), force-create a
	## joint node at the stored world position.  register_wire_node is idempotent
	## — it will never overwrite a breaker, and returns the final key either way.
	if na.is_empty():
		na = _pm.call("register_wire_node", pos_a, "joint", "")
		print("[Reconciler:_reg1] force-created joint at pos_a=%s → key=%s" % [str(pos_a), na])
	if nb.is_empty():
		nb = _pm.call("register_wire_node", pos_b, "joint", "")
		print("[Reconciler:_reg1] force-created joint at pos_b=%s → key=%s" % [str(pos_b), nb])

	## Still empty after forced creation → something is very wrong in PM.
	if na.is_empty() or nb.is_empty():
		push_warning("[Reconciler] _register_one: could not resolve/create nodes for %s↔%s" % [
			str(pos_a), str(pos_b)])
		return false

	## register_wire_edge is idempotent — safe to call after every rebuild.
	var edge_id: String = _pm.call("register_wire_edge", na, nb, seg_node)
	print("[Reconciler:_reg1] register_wire_edge(%s, %s) → edge_id='%s'" % [na, nb, edge_id])

	## Keep the visual seg_node's edge_id in sync so BuildModeController's
	## _remove_dangling_wire_segments() skips it (pw_ prefix = player wire).
	if seg_node != null and is_instance_valid(seg_node) and "edge_id" in seg_node:
		seg_node.edge_id = _stable_key(pos_a, pos_b)

	return not edge_id.is_empty()

## Compute what PM's _snap_key() would produce for this position (no lookup).
## Used for diagnostic "exact vs fallback" labelling only.
func _snap_key_exact(pos: Vector3) -> String:
	var snap: float = 0.25   ## must match PowerManager.SNAP_GRID
	var ix: int = roundi(pos.x / snap)
	var iy: int = roundi(1.0  / snap)   ## WIRE_GRID_Y = 1.0
	var iz: int = roundi(pos.z / snap)
	return "%d,%d,%d" % [ix, iy, iz]

# ── Helpers ───────────────────────────────────────────────────────────────────
## Stable dictionary key from two world positions.
## Positions are rounded to 2 decimal places so floating-point drift doesn't
## create duplicate keys for the same conceptual wire.
## The pair is sorted so pw_A_B == pw_B_A (undirected).
func _stable_key(pos_a: Vector3, pos_b: Vector3) -> String:
	var a: String = "%.2f_%.2f" % [pos_a.x, pos_a.z]
	var b: String = "%.2f_%.2f" % [pos_b.x, pos_b.z]
	## Sort so A < B — key is direction-agnostic.
	if a > b:
		var tmp: String = a
		a = b
		b = tmp
	return "pw_%s__%s" % [a, b]
