extends RefCounted
class_name PowerSolver
## PowerSolver.gd  —  Stage 8b extraction (review implementation plan)
## ─────────────────────────────────────────────────────────────────────────────
## The 3-pass zone solver, load-shedding, and cross-zone brownout/upgraded-
## breaker logic, extracted out of PowerManager.gd. This is the most
## solver-entangled piece (per the review, done last/carefully) — every
## function here was moved via verbatim line-range slicing (sed line ranges),
## never retyped, then had exactly the identified "lives on PowerManager"
## identifiers regex-substituted to `_owner.<name>` form, with the full
## transformed output read back top-to-bottom before writing, per the
## methodology established in PowerGraph.gd/PowerRegistry.gd (Stage 5/8).
##
## SCOPE — component draw/capacity accounting, the 3-pass evaluator, load
## shedding, un-shedding (full + partial), sustained cross-zone brownout,
## upgraded-breaker self-trip, and the two component-flood BFS helpers used
## only by solver decisions (_flood_component_keys / _flood_gen_component_keys):
##   _component_draw, _component_draw_unshed, _component_capacity,
##   _find_components, _find_components_raw, _get_gen_sharing_zone_pairs,
##   _shed_residual_watts, _shed_in_component, _unshed_component,
##   _partial_unshed_component, _component_sig_key, _flood_component_keys,
##   _flood_gen_component_keys, _sustained_brownout_component,
##   clear_exhausted_brownout, _find_upgraded_breakers_in_component,
##   _self_trip_upgraded_breaker, _evaluate_per_component,
##   _evaluate_pass1_local_surplus, _evaluate_pass2_cross_zone_sharing,
##   _evaluate_pass3_zone_resolution, _activate_discharge_for_component,
##   _recalculate_draw_from_consumers, _evaluate_grid_state (dead stub),
##   _attempt_load_shed (dead stub) — both stubs kept verbatim, unreferenced
##   anywhere in the codebase, preserved only for call-site safety per the
##   original code's own comment.
##
## OUT OF SCOPE for this stage (still live in PowerManager.gd):
##   - _solve_network() (the entry point that calls _evaluate_per_component()),
##     _build_adjacency(), _adjacency_bfs_can_reach(), _run_bfs(),
##     _apply_reachability(), _is_consumer_reachable(), _calculate_edge_loads(),
##     _downstream_draw() — these are graph-traversal/reachability functions,
##     conceptually PowerGraph's future territory (Stage 5 already deferred
##     "zones, adjacency, BFS reachability" for the same reason). Left in place
##     to keep this slice to solver DECISION logic only, given how entangled
##     the wider adjacency machinery already is.
##   - Generator/battery tick simulation (_tick_generators, _tick_batteries),
##     flicker sequencing, grid trip/offline handling, breaker registration —
##     these are PowerSimClock/breaker-topology territory, not touched here.
##
## DESIGN — same _owner back-reference pattern as PowerGraph.gd/PowerRegistry.gd:
## `_consumers`/`_generators`/`_batteries`/`_breakers`/`_wire_nodes`/`_wire_edges`/
## `_adjacency`/`_adjacency_gen`/`_component_cache(_valid)`/
## `_exhausted_brownout_keys`/`_needs_resolve`/`_flickering`/`_overload_timer`/
## `grid_state`/`active_draw_watts`/`total_capacity_watts` and the const tables
## (`BATTERY_CHARGE_WATTS`, `LIGHT_TYPES`, `SHED_WATTS`, `SHED_START_PRIORITY`,
## `SHED_END_PRIORITY`, the `GridState` enum) all stay physically declared on
## PowerManager — NOT moved here — for the same "don't move state referenced
## from 100+ scattered call sites in one pass" reason as the prior two
## extractions. PowerSolver reaches into them via `_owner.<name>`, and calls
## `_owner._pmdbg()`, `_owner.get_wire_zones()`, `_owner._safe_dict_node()`,
## `_owner._is_consumer_reachable()`, `_owner._adjacency_bfs_can_reach()`,
## `_owner._apply_shed_to_consumer()`, `_owner._apply_power_to_consumer()`,
## `_owner._trip_generators_in_zone()`, `_owner._cut_consumers_in_zone()`,
## `_owner._notify_battery_mode/_notify_battery_node/_notify_breaker_node()`,
## `_owner._recalculate_capacity()`, `_owner._go_offline()`, and emits
## `_owner.<signal>` for `grid_state_changed`, `overloaded_started`,
## `overloaded_ended`, `battery_state_changed`, `breaker_tripped`,
## `generator_started` (signals stay declared on PowerManager so existing
## `.connect()` call sites elsewhere are untouched).
##
## Calls BETWEEN functions that moved together in this same slice (e.g.
## `_evaluate_per_component()` calling `_evaluate_pass1_local_surplus()`, or
## `_shed_in_component()` calling `_component_draw()`) stay bare/self-implicit
## — only calls OUT to things still living on PowerManager got the `_owner.`
## prefix.
##
## PowerManager holds one instance (`_solver`) and forwards its public API
## methods to it with IDENTICAL signatures — `_evaluate_per_component()`,
## `_find_components()`, `_get_gen_sharing_zone_pairs()`,
## `_shed_residual_watts()`, `_flood_component_keys()`,
## `_flood_gen_component_keys()`, and `clear_exhausted_brownout()` are the only
## seven functions from this slice actually called from code still living on
## PowerManager (`_solve_network`, `_tick_batteries`, `set_generator_running`,
## and a couple of UI-facing zone-color helpers) — every other moved function
## is called only from other functions within this same file, so no wrapper
## was needed for those. This keeps every external call site elsewhere in the
## codebase (BuildModeController, BreakerBox, UpgradedBreakerBox, etc.)
## unaffected.

var _owner: PowerManager = null

func _init(owner: PowerManager) -> void:
	_owner = owner


func _component_draw(component_keys: Dictionary) -> float:
	var draw: float = 0.0
	for c: Dictionary in _owner._consumers.values():
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					if c.get("powered", false):
						draw += float(c.get("watts", 0.0))
					elif c.get("shed", false) and c.get("active", false):
						draw += _shed_residual_watts(c)
				break
	for bat: Dictionary in _owner._batteries.values():
		if not bat.get("charging", false):
			continue
		if float(bat.get("charge_wh", 0.0)) >= float(bat.get("capacity_wh", 0.0)):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
				if component_keys.has(wn["key"]):
					draw += _owner.BATTERY_CHARGE_WATTS
				break
	return draw


## ─── Per-component POTENTIAL (un-shed) draw ─────────────────────────────────
## Sums the FULL rated draw of every active consumer in component_keys as if
## NOTHING were shed (shed items counted at full watts, not residual).  Used by
## the HEALTHY/unshed decision so we only un-shed when the zone could carry the
## full restored load — otherwise un-shedding re-overloads and oscillates.
func _component_draw_unshed(component_keys: Dictionary) -> float:
	var draw: float = 0.0
	for c: Dictionary in _owner._consumers.values():
		if not c.get("active", false):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					draw += float(c.get("watts", 0.0))
				break
	for bat: Dictionary in _owner._batteries.values():
		if not bat.get("charging", false):
			continue
		if float(bat.get("charge_wh", 0.0)) >= float(bat.get("capacity_wh", 0.0)):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
				if component_keys.has(wn["key"]):
					draw += _owner.BATTERY_CHARGE_WATTS
				break
	return draw


## ─── Per-component capacity ────────────────────────────────────────────────
## Sums running generator watts whose wire node is in component_keys.
func _component_capacity(component_keys: Dictionary) -> float:
	var _dbg_cap_total: float = 0.0
	var cap: float = 0.0
	for gen: Dictionary in _owner._generators.values():
		if not gen.get("running", false):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
				if component_keys.has(wn["key"]):
					cap += float(gen.get("watts", 0.0))
				break
	return cap


## ─── Find all connected components in _owner._adjacency ─────────────────────────────
## Returns Array of Dictionaries, each with:
##   "keys": Dictionary (snap_key → true) — all nodes in this component
## Only visits nodes present in _owner._adjacency (live, untripped graph).
## Isolated wire nodes (no live edges) are not included.
## Returns cached connected-component partition.  Rebuilds (one flood over
## _owner._adjacency) only when the cache is invalid.  Use this everywhere instead of
## flooding the graph per-call — _tick_batteries() runs this every frame.
func _find_components() -> Array[Dictionary]:
	if not _owner._component_cache_valid:
		_owner._component_cache       = _find_components_raw()
		_owner._component_cache_valid = true
	return _owner._component_cache


## Raw connected-component flood-fill over _owner._adjacency (ignores breakers).
## Each component is { "keys": { snap_key: true, ... } }.
## Never call directly in per-frame code — go through _find_components().
func _find_components_raw() -> Array[Dictionary]:
	var visited: Dictionary = {}
	var components: Array[Dictionary] = []
	for start: String in _owner._adjacency:
		if visited.has(start):
			continue
		## BFS flood-fill from this node.
		var component_keys: Dictionary = {}
		var queue: Array[String] = [start]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			if visited.has(cur):
				continue
			visited[cur] = true
			component_keys[cur] = true
			if _owner._adjacency.has(cur):
				for nb: String in (_owner._adjacency[cur] as Array):
					if not visited.has(nb):
						queue.append(nb)
		components.append({"keys": component_keys})
	return components


## ─── Cross-zone generator sharing: identify sharing zone pairs ─────────────
## Returns Array of Dictionaries, each describing one directional gen-share link:
##   { "from_zi": int, "to_zi": int, "breaker_id": String }
## "from_zi" has surplus generators, "to_zi" has deficit.
## Only untripped, pass_generator=true breakers create sharing links.
## Sharing is bidirectional — both directions are possible depending on who
## has surplus; the caller (3-pass evaluator) decides direction at solve time.
## Each pair appears once in each direction so the evaluator can check both.
func _get_gen_sharing_zone_pairs(wire_zones: Array[Dictionary]) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	_owner._pmdbg("[PM:SHARE] _get_gen_sharing_zone_pairs wire_zones=%d" % wire_zones.size())
	if wire_zones.size() < 2:
		_owner._pmdbg("[PM:SHARE]   < 2 zones, returning empty")
		return pairs

	## Build snap_key → zone_index for fast lookup.
	var key_to_zi: Dictionary = {}
	for z: Dictionary in wire_zones:
		var zi: int = int(z.get("index", 0))
		for nk: String in (z.get("node_keys", []) as Array):
			key_to_zi[nk] = zi

	## Check every breaker: if it's untripped + pass_generator=true, find the
	## two zones on either side of it (each side is a set of edge endpoints).
	for bid: String in _owner._breakers:
		var brk: Dictionary = _owner._breakers[bid]
		if brk.get("tripped", false):
			continue
		if not brk.get("pass_generator", true):
			continue   ## This breaker blocks gen BFS — no sharing through it.

		var bk: String = brk.get("node_key", "")
		if bk.is_empty():
			continue

		## Find zone indices on each side of this breaker node.
		## A breaker is the cut-point between two zones. The zones are identified
		## by the snap keys that appear as the OTHER endpoint in edges touching bk.
		var side_zones: Dictionary = {}   ## zone_index → true (should be exactly 2)
		for edge: Dictionary in _owner._wire_edges.values():
			var na: String = edge.get("node_a", "")
			var nb: String = edge.get("node_b", "")
			var other: String = ""
			if na == bk:
				other = nb
			elif nb == bk:
				other = na
			if other.is_empty():
				continue
			if key_to_zi.has(other):
				side_zones[int(key_to_zi[other])] = true

		var zone_list: Array = side_zones.keys()
		_owner._pmdbg("[PM:SHARE]   breaker id=%s key=%s side_zones=%s" % [bid, bk, str(zone_list)])
		if zone_list.size() < 2:
			_owner._pmdbg("[PM:SHARE]     < 2 side zones — no sharing through this breaker")
			continue   ## Breaker touches fewer than 2 zones — nothing to share.

		## Generate pairs for every combination of zones touching this breaker
		## (handles T-junction breakers that border 3+ zones).
		for ai: int in zone_list.size():
			for bi: int in range(ai + 1, zone_list.size()):
				var za: int = int(zone_list[ai])
				var zb: int = int(zone_list[bi])
				## Add both directions — evaluator decides who exports to whom.
				pairs.append({ "from_zi": za, "to_zi": zb, "breaker_id": bid })
				pairs.append({ "from_zi": zb, "to_zi": za, "breaker_id": bid })

	_owner._pmdbg("[PM:SHARE] total sharing pairs=%d: %s" % [pairs.size(), str(pairs)])
	return pairs


## ─── Shed residual draw helper ──────────────────────────────────────────────
## How many watts a SHED consumer still pulls.  Lights dim to a small glow
## (_owner.SHED_WATTS); every other appliance switches fully OFF (0W).
## Single source of truth — used by the shed loop and all draw-summing passes.
func _shed_residual_watts(c: Dictionary) -> float:
	if c.get("type", "") in _owner.LIGHT_TYPES:
		return _owner.SHED_WATTS
	return 0.0


## ─── Per-component load shed ────────────────────────────────────────────────
## Sheds NON-CRITICAL consumers within component_keys, tier by tier (luxury
## first), until draw fits under capacity or there is nothing left to shed.
## Shedding is gated by PRIORITY (_owner.SHED_START_PRIORITY → _owner.SHED_END_PRIORITY), NOT
## device type — lights, microwaves, washers, anything tier ≥ 2 is eligible.
## Tier 1 (critical) is never touched.  Lights dim (_owner.SHED_WATTS), other appliances
## switch fully off (0W) — see _shed_residual_watts().
## Returns the new draw after shedding.
func _shed_in_component(component_keys: Dictionary, capacity: float) -> float:
	var draw: float = _component_draw(component_keys)
	_owner._pmdbg("[PM:SHED] enter: draw=%.1f capacity=%.1f comp_nodes=%d" % [draw, capacity, component_keys.size()])
	var priority: int = _owner.SHED_START_PRIORITY
	while priority >= _owner.SHED_END_PRIORITY and draw > capacity:
		for c: Dictionary in _owner._consumers.values():
			if c.get("priority", 3) != priority:
				continue
			if not c.get("powered", false) or c.get("shed", false):
				_owner._pmdbg("[PM:SHED]   skip id=%s pri=%d (powered=%s shed=%s)" % [
					str(c.get("id","?")), int(c.get("priority",3)),
					str(c.get("powered",false)), str(c.get("shed",false))])
				continue
			## Only shed consumers in this component.
			var in_component: bool = false
			for wn: Dictionary in _owner._wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if component_keys.has(wn["key"]):
						in_component = true
					break
			if not in_component:
				_owner._pmdbg("[PM:SHED]   skip id=%s pri=%d (NOT in this component)" % [
					str(c.get("id","?")), int(c.get("priority",3))])
				continue
			var residual: float = _shed_residual_watts(c)
			_owner._pmdbg("[PM:SHED]   SHED id=%s pri=%d watts=%.1f residual=%.1f draw %.1f->%.1f" % [
				str(c.get("id","?")), int(c.get("priority",3)),
				float(c.get("watts",0.0)), residual,
				draw, draw - float(c.get("watts",0.0)) + residual])
			c["shed"]    = true
			c["powered"] = false
			_owner._apply_shed_to_consumer(c)
			draw -= float(c.get("watts", 0.0))
			draw += residual
			if draw <= capacity:
				break
		priority -= 1
	return draw


## ─── Unshed all lights in a component ─────────────────────────────────────
## Clears the shed flag AND restores full power on each previously-shed,
## reachable consumer in the component.  Unshed only ever runs from the HEALTHY
## branch (capacity available), so re-powering here is safe.  Critically, we
## must call set_powered(true) ourselves: _apply_reachability() runs BEFORE this
## in the solve and saw the consumer still shed (powered stays false), so it
## never re-powers it.  Without this the node clears _is_shed (set_shed(false))
## but is left visually dark/dim until some later solve — the "lights stay dim
## after recovery" bug.  Setting powered=true + set_powered(true) restores full
## brightness on the same frame recovery happens.
func _unshed_component(component_keys: Dictionary) -> void:
	for c: Dictionary in _owner._consumers.values():
		if not c.get("shed", false):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					c["shed"] = false
					var n: Node = _owner._safe_dict_node(c)
					if n != null and is_instance_valid(n) and n.has_method("set_shed"):
						n.set_shed(false)
					## Re-power so the light returns full-bright immediately,
					## not on some later solve.  Only if active + reachable.
					if c.get("active", false) and _owner._is_consumer_reachable(c["id"]):
						c["powered"] = true
						if n != null and is_instance_valid(n) and n.has_method("set_powered"):
							n.set_powered(true)
				break


## ─── Partial unshed ──────────────────────────────────────────────────────────
## Called from the HEALTHY AT-CAPACITY branch when the FULL unshed draw exceeds
## available capacity but individual items might still fit.  Iterates shed
## consumers from highest priority (2 = most important) to lowest (5 = first-to-
## shed), restoring each one only if its watts fit within remaining headroom.
## Items that don't fit stay shed.  This avoids the ALL-or-NOTHING behavior of
## _unshed_component that kept all lights dim when only a subset could be powered.
## Non-oscillating: we only unshed items that genuinely fit; the next solve sees
## committed_draw rise by exactly their watts, leaving the same remaining headroom.
func _partial_unshed_component(component_keys: Dictionary, avail_cap: float) -> void:
	## Compute draw already committed by powered (non-shed) consumers in this zone.
	var committed_draw: float = 0.0
	for c: Dictionary in _owner._consumers.values():
		if not c.get("powered", false) or c.get("shed", false):
			continue
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
				if component_keys.has(wn["key"]):
					committed_draw += float(c.get("watts", 0.0))
				break
	var remaining_cap: float = maxf(0.0, avail_cap - committed_draw)
	_owner._pmdbg("[PM:PARTIAL_UNSHED] enter: avail=%.1f committed=%.1f remaining=%.1f" % [
		avail_cap, committed_draw, remaining_cap])

	## Walk priority 2 → _owner.SHED_START_PRIORITY (most critical first).
	for priority: int in range(_owner.SHED_END_PRIORITY, _owner.SHED_START_PRIORITY + 1):
		for c: Dictionary in _owner._consumers.values():
			if not c.get("shed", false) or not c.get("active", false):
				continue
			if c.get("priority", 3) != priority:
				continue
			## Must be in this component.
			var in_component: bool = false
			for wn: Dictionary in _owner._wire_nodes.values():
				if wn["role"] == "consumer" and wn["device_id"] == c["id"]:
					if component_keys.has(wn["key"]):
						in_component = true
					break
			if not in_component:
				continue
			var watts: float = float(c.get("watts", 0.0))
			if watts > remaining_cap:
				_owner._pmdbg("[PM:PARTIAL_UNSHED]   NO-FIT id=%s pri=%d watts=%.1f remaining=%.1f" % [
					str(c.get("id","?")), priority, watts, remaining_cap])
				continue
			## Restore this item.
			c["shed"]    = false
			c["powered"] = true
			remaining_cap -= watts
			var n: Node = _owner._safe_dict_node(c)
			if n != null and is_instance_valid(n):
				if n.has_method("set_shed"):
					n.set_shed(false)
				if n.has_method("set_powered"):
					n.set_powered(true)
			_owner._pmdbg("[PM:PARTIAL_UNSHED]   RESTORED id=%s pri=%d watts=%.1f remaining=%.1f" % [
				str(c.get("id","?")), priority, watts, remaining_cap])


## ─── Stable component signature key ───────────────────────────────────────────
## Builds a deterministic key from a component's node-set so the sustained-
## brownout latch survives across re-solves even as imported/exported watts
## fluctuate.  Sorted so node-set ordering never changes the key.
func _component_sig_key(component_keys: Dictionary) -> String:
	var ks: Array = component_keys.keys()
	ks.sort()
	return "|".join(PackedStringArray(ks))


## ─── Flood-fill the full shared electrical component ──────────────────────────
## Given one or more seed node keys (typically a single zone's node set), BFS
## across _owner._adjacency — the power/battery graph that already excludes tripped and
## pass-through-blocked breakers — to gather EVERY node key in the same connected
## electrical component.  This spans an arbitrary number of zones bridged by
## non-tripped pass-through breakers (cross-zone shares can chain indefinitely),
## so the brownout + gen-trip below act on the WHOLE shared group, not just the
## one zone that happened to run a deficit.
##   seed_keys: Dictionary of node_key → true (or any keys() iterable set)
## Returns: Dictionary of node_key → true for the full component.
func _flood_component_keys(seed_keys: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = []
	for sk: String in seed_keys.keys():
		if not visited.has(sk):
			visited[sk] = true
			queue.append(sk)
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if not _owner._adjacency.has(cur):
			continue
		for nb: String in (_owner._adjacency[cur] as Array):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited


## ─── Flood-fill the GENERATOR-sharing component (pass_generator=true only) ──
## Same BFS as _flood_component_keys() but walks _owner._adjacency_gen instead of
## _owner._adjacency — i.e. it crosses untripped breakers with pass_generator=true,
## and is blocked by tripped breakers or pass_generator=false breakers (same
## rules the rest of the system already uses for generator BFS seeding and
## cross-zone capacity sharing in _evaluate_per_component's PASS 2).
##
## Used by _tick_batteries()'s charge path so a battery correctly sees
## generator capacity/load from a NEIGHBORING zone connected via a
## pass_generator=true breaker, instead of being scoped to only its own
## breaker-partitioned zone (which was the root cause of batteries never
## charging across a shared-generator breaker connection).
func _flood_gen_component_keys(seed_keys: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = []
	for sk: String in seed_keys.keys():
		if not visited.has(sk):
			visited[sk] = true
			queue.append(sk)
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if not _owner._adjacency_gen.has(cur):
			continue
		for nb: String in (_owner._adjacency_gen[cur] as Array):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited


## ─── Sustained brownout (cross-zone exhaustion) ──────────────────────────────
## Forces EVERY consumer in the component to the SHED (dim-orange) visual —
## including tier-1 critical, because there is genuinely no source left (gens
## tripped, batteries empty).  Then trips the generators feeding the component
## so they require a manual restart.  Unlike _owner._cut_consumers_in_zone() this does
## NOT mark the component OFFLINE: lights keep their dim glow, the rest show
## their [SHED] state.  Latches the component so it stays this way until a
## generator is manually restarted (clear_exhausted_brownout()).
##
## IMPORTANT: callers must pass the FULL shared-component key set (use
## _flood_component_keys first).  A cross-zone share can span many zones; the
## exporter's generator lives in a DIFFERENT zone from the deficit zone, so
## scoping this to a single zone would never trip the source generator.
func _sustained_brownout_component(component_keys: Dictionary) -> void:
	for c: Dictionary in _owner._consumers.values():
		## Only consumers in this component.
		var in_component: bool = false
		for wn: Dictionary in _owner._wire_nodes.values():
			if wn.get("role", "") == "consumer" and wn.get("device_id", "") == c["id"]:
				if component_keys.has(wn.get("key", "")):
					in_component = true
				break
		if not in_component:
			continue
		## Priority 1 (critical) is NEVER shed — even in a sustained brownout
		## where there is genuinely no power source.  These items go fully OFF
		## (set_powered(false), no orange dim) rather than SHED.  The semantic
		## is: "shed" = temporarily reduced load that could come back; a critical
		## item going dark means the whole grid is dead, not just load-shedding.
		if c.get("priority", 3) == 1:
			if c.get("powered", false):
				c["powered"] = false
				_owner._apply_power_to_consumer(c, false)
			continue
		## Force shed visual (dim-orange), no real power.
		c["powered"] = false
		if not c.get("shed", false):
			c["shed"] = true
		_owner._apply_shed_to_consumer(c)
	## Trip the generators feeding this component (manual restart required).
	_owner._trip_generators_in_zone(component_keys)
	## Latch so subsequent re-solves keep this component in brownout until a
	## generator is manually restarted.
	_owner._exhausted_brownout_keys[_component_sig_key(component_keys)] = true


## Clear ALL sustained-brownout latches.  Called when a generator is manually
## restarted — the next _solve_network() re-evaluates from scratch and power
## returns to any component the restarted generator can now feed.
func clear_exhausted_brownout() -> void:
	if _owner._exhausted_brownout_keys.is_empty():
		return
	_owner._exhausted_brownout_keys.clear()
	_owner._needs_resolve = true


## ─── Upgraded breaker: find + self-trip ──────────────────────────────────────
## Returns the breaker_id of every UPGRADED breaker whose node_key falls inside
## component_keys, is currently untripped, AND is currently passing power
## (pass_battery or pass_generator true — a locked/already-tripped upgraded
## breaker has already done its job and shouldn't re-trigger).  In practice a
## single upgraded breaker sits on the boundary between the donor and deficit
## zones, but this returns an Array so multiple bridging upgraded breakers in
## a longer chain all trip together and fully isolate the deficit side.
func _find_upgraded_breakers_in_component(component_keys: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for bid: String in _owner._breakers:
		var brk: Dictionary = _owner._breakers[bid]
		if not bool(brk.get("upgraded", false)):
			continue
		if bool(brk.get("tripped", false)):
			continue   ## already tripped — nothing new to do
		var bk: String = brk.get("node_key", "")
		if bk.is_empty() or not component_keys.has(bk):
			continue
		## Only relevant if it's actually passing something right now — a
		## breaker with both pass-throughs already off isn't contributing to
		## the share and doesn't need to self-trip.
		if not bool(brk.get("pass_battery", true)) and not bool(brk.get("pass_generator", true)):
			continue
		found.append(bid)
	return found


## Self-trip an upgraded breaker on cross-zone exhaustion: sets tripped=true,
## FORCES both pass-throughs off (locked — the player can't re-enable sharing
## until the breaker is manually reset), notifies the scene node for the LED /
## TRIPPED banner, and emits _owner.breaker_tripped so any listening UI updates.
##
## group_key identifies the exhaustion EVENT this breaker tripped alongside —
## every upgraded breaker that self-trips from the same
## _find_upgraded_breakers_in_component() call shares the same group_key
## (the component signature). reset_breaker() uses this to find and reset
## every sibling breaker from the same event together (see
## _reset_upgraded_breaker_group()), instead of leaving some tripped while
## only one gets manually reset.
##
## Also snapshots the pre-trip pass_battery/pass_generator values so a group
## reset can restore the player's ORIGINAL sharing intent rather than leaving
## both pass-throughs forced off after reset (which would silently disable
## sharing the player explicitly enabled, with no way to tell from the UI
## alone why it stopped working).
##
## Deliberately does NOT call _solve_network() itself — the caller is already
## mid-solve (_evaluate_per_component) and sets _owner._needs_resolve=true so the
## severed topology is picked up cleanly on the next frame's solve, exactly
## like the _tick_batteries() -> _owner._needs_resolve -> _process() pattern already
## used elsewhere in this file.
func _self_trip_upgraded_breaker(breaker_id: String, group_key: String) -> void:
	if not _owner._breakers.has(breaker_id):
		return
	var brk: Dictionary = _owner._breakers[breaker_id]
	## Preserve whatever the player had set BEFORE forcing both off, so a
	## later group reset can restore intent instead of leaving them off.
	brk["pretrip_pass_battery"]   = brk.get("pass_battery", true)
	brk["pretrip_pass_generator"] = brk.get("pass_generator", true)
	brk["trip_group_key"] = group_key
	brk["tripped"]       = true
	brk["pass_battery"]  = false
	brk["pass_generator"] = false
	_owner._notify_breaker_node(breaker_id, true)
	_owner.breaker_tripped.emit(breaker_id)


## ─── Main per-zone evaluation ────────────────────────────────────────────────
## Three-pass zone solver with cross-zone generator sharing.
##
## PASS 1  — compute raw surplus/deficit per zone (local gens only).
## PASS 2  — redistribute surplus from pass_generator=true neighbors to zones
##           still in deficit.  Own-zone load always served first.
## PASS 3  — for each zone, evaluate final watts with imports/exports factored
##           in, then apply shedding / battery / offline as needed.
##
## After this function returns:
##   _owner.active_draw_watts    = sum of all zone draws (for HUD signal)
##   _owner.total_capacity_watts = sum of all zone generator capacity
##   Grid state = WORST state across all zones.
##
## Cross-zone SHARING RULES (from task.md decisions):
##   • Own-zone load served first — surplus is capacity MINUS own draw.
##   • Exporting zone stress: if (own_draw + exported_w) > capacity → overloaded.
##   • No grace periods — BROWNOUT → instant trip.
func _evaluate_per_component() -> void:
	if _owner.grid_state == _owner.GridState.TRIPPED or _owner.grid_state == _owner.GridState.OFFLINE:
		return

	## Get wire zones (breaker-partitioned segments).
	var wire_zones: Array[Dictionary] = _owner.get_wire_zones()

	## No wires at all — bare minimum accounting.
	if wire_zones.is_empty():
		_owner.active_draw_watts    = 0.0
		_owner.total_capacity_watts = 0.0
		for gen: Dictionary in _owner._generators.values():
			if gen.get("running", false):
				_owner.total_capacity_watts += float(gen.get("watts", 0.0))
		for c: Dictionary in _owner._consumers.values():
			if c.get("powered", false):
				_owner.active_draw_watts += float(c.get("watts", 0.0))
		return

	## Pre-compute per-zone node sets as Dictionary (snap_key → true).
	var n_zones: int = wire_zones.size()
	var zone_node_sets: Array[Dictionary] = []
	for zone: Dictionary in wire_zones:
		var d: Dictionary = {}
		for nk: String in (zone.get("node_keys", []) as Array):
			d[nk] = true
		zone_node_sets.append(d)

	## Each labeled pass below is its own function (Stage 4 refactor — no
	## behavior change, pure extraction). zone_info is a mutable Array of
	## Dictionaries; Pass 2 mutates entries in place (imported_w/exported_w/
	## import_from/export_to), which Pass 3 then reads.
	var zone_info: Array[Dictionary] = _evaluate_pass1_local_surplus(n_zones, zone_node_sets)
	_evaluate_pass2_cross_zone_sharing(wire_zones, n_zones, zone_info)
	var pass3_result: Dictionary = _evaluate_pass3_zone_resolution(n_zones, zone_node_sets, zone_info)

	var any_overloaded: bool      = pass3_result["any_overloaded"]
	var any_offline: bool         = pass3_result["any_offline"]
	var zones_with_device: int    = pass3_result["zones_with_device"]
	var zones_offline: int        = pass3_result["zones_offline"]

	## ── Recalculate global draw after potential shedding ─────────────────────
	_owner.active_draw_watts = 0.0
	for c: Dictionary in _owner._consumers.values():
		if not _owner._is_consumer_reachable(c["id"]):
			continue
		if c.get("powered", false):
			_owner.active_draw_watts += float(c.get("watts", 0.0))
		elif c.get("shed", false) and c.get("active", false):
			_owner.active_draw_watts += _shed_residual_watts(c)
	for bat: Dictionary in _owner._batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			_owner.active_draw_watts += _owner.BATTERY_CHARGE_WATTS

	## ── Post-loop: stop battery discharge if no zone needs coverage ──────────
	if not any_overloaded and not any_offline:
		for bat: Dictionary in _owner._batteries.values():
			if bat.get("discharging", false):
				bat["discharging"] = false
				bat["charging"]    = false
				_owner.battery_state_changed.emit(bat["id"], false)
				_owner._notify_battery_mode(bat["id"])
				_owner._notify_battery_node(bat["id"])

	## ── Global grid state machine ─────────────────────────────────────────────
	var old_state: PowerManager.GridState = _owner.grid_state

	if any_offline:
		if zones_offline >= zones_with_device and not _owner._flickering:
			## Total grid failure (every zone with a device is offline).
			## Trigger the flicker→BROWNOUT warning sequence instead of
			## jumping straight to a hard state — this was previously the
			## dead-code trail documented in
			## bunker-game-power-critical-finding.md: _start_flicker_offline()
			## had zero call sites anywhere, so BROWNOUT/TRIPPED were
			## structurally unreachable and players got zero warning before
			## an instant blackout. _tick_flicker() (already fully
			## implemented) takes it from here once the flicker completes.
			if _owner.grid_state != _owner.GridState.OFFLINE \
					and _owner.grid_state != _owner.GridState.TRIPPED:
				_owner._start_flicker_offline()
			return
		any_overloaded = true   ## partial offline → treat as overloaded for HUD

	if any_overloaded:
		if _owner.grid_state != _owner.GridState.OVERLOADED:
			_owner.grid_state = _owner.GridState.OVERLOADED
			_owner._overload_timer = 0.0
			_owner.grid_state_changed.emit(_owner.grid_state, old_state)
			_owner.overloaded_started.emit()
	else:
		match _owner.grid_state:
			_owner.GridState.OVERLOADED:
				_owner.grid_state = _owner.GridState.ONLINE
				_owner._overload_timer = 0.0
				_owner.grid_state_changed.emit(_owner.grid_state, old_state)
				_owner.overloaded_ended.emit()
			_owner.GridState.BROWNOUT:
				_owner.grid_state = _owner.GridState.ONLINE
				_owner._overload_timer = 0.0
				_owner.grid_state_changed.emit(_owner.grid_state, old_state)


## ──────────────────────────────────────────────────────────────────────────
## PASS 1 — raw per-zone surplus/deficit with local gens only.
## ──────────────────────────────────────────────────────────────────────────
## Returns zone_info: Array[Dictionary], one entry per zone (index = zone
## index zi), each dict:
##   "local_cap"   float — running gen watts physically inside this zone
##   "local_draw"  float — consumer draw inside this zone
##   "surplus"     float — local_cap - local_draw  (neg = deficit)
##   "exported_w"  float — watts committed to export (filled in pass 2)
##   "imported_w"  float — watts imported from neighbors (filled in pass 2)
##   "import_from" Array[int] — zone indices we import from
##   "export_to"   Array[int] — zone indices we export to
##   "has_device"  bool  — any non-joint node inside zone
func _evaluate_pass1_local_surplus(
		n_zones: int,
		zone_node_sets: Array[Dictionary]) -> Array[Dictionary]:
	var zone_info: Array[Dictionary] = []
	for zi: int in n_zones:
		var zone_keys: Dictionary = zone_node_sets[zi]
		var has_device: bool = false
		for k: String in zone_keys:
			if _owner._wire_nodes.has(k) and _owner._wire_nodes[k].get("role", "joint") != "joint":
				has_device = true
				break
		var local_cap:  float = _component_capacity(zone_keys)
		var local_draw: float = _component_draw(zone_keys)
		_owner._pmdbg("[PM:EVAL] PASS1 zone %d: local_cap=%.1fw local_draw=%.1fw has_device=%s node_count=%d" % [
			zi, local_cap, local_draw, str(has_device), zone_keys.size()])
		zone_info.append({
			"local_cap":   local_cap,
			"local_draw":  local_draw,
			"surplus":     local_cap - local_draw,
			"exported_w":  0.0,
			"imported_w":  0.0,
			"import_from": [],
			"export_to":   [],
			"has_device":  has_device,
		})
	return zone_info


## ──────────────────────────────────────────────────────────────────────────
## PASS 2 — cross-zone generator sharing via BFS pool flood fill.
##
## OLD APPROACH (broken): iterative round-based loop skipped zones with
## still_needed<=0. Pass-through zones (0 draw, 0 cap) were always skipped,
## so power never propagated beyond the first zone hop.
##
## NEW APPROACH: BFS from every generator zone simultaneously.
##   1. Build undirected zone adjacency from sharing_pairs (breaker links).
##   2. BFS flood-fill to find connected power pools (groups of zones
##      reachable from each other through untripped pass_generator breakers).
##   3. Each pool's total capacity is shared across all its member zones.
##      Zones with local generators donate surplus to deficit zones anywhere
##      in the pool regardless of hop distance or intermediate zone load.
## ──────────────────────────────────────────────────────────────────────────
## Mutates zone_info in place (imported_w/exported_w/import_from/export_to) —
## Dictionaries and Arrays are passed by reference in GDScript, so callers see
## the updates without needing a return value.
func _evaluate_pass2_cross_zone_sharing(
		wire_zones: Array[Dictionary],
		n_zones: int,
		zone_info: Array[Dictionary]) -> void:
	var sharing_pairs: Array[Dictionary] = _get_gen_sharing_zone_pairs(wire_zones)

	## Build undirected zone adjacency from sharing_pairs.
	var zone_adj: Array = []
	for _zi: int in n_zones:
		zone_adj.append([])
	for pair: Dictionary in sharing_pairs:
		var fa: int = int(pair["from_zi"])
		var ta: int = int(pair["to_zi"])
		if not (zone_adj[fa] as Array).has(ta):
			(zone_adj[fa] as Array).append(ta)
		if not (zone_adj[ta] as Array).has(fa):
			(zone_adj[ta] as Array).append(fa)

	## BFS flood: partition zones into power pools.
	## Each pool = all zones reachable from each other via untripped gen-pass breakers.
	var zone_pool: Array[int] = []
	for _zi2: int in n_zones:
		zone_pool.append(-1)
	var pools: Array[Dictionary] = []

	for seed: int in n_zones:
		if zone_pool[seed] != -1:
			continue
		var pool_idx: int = pools.size()
		var pool: Dictionary = { "total_cap": 0.0, "total_draw": 0.0, "members": [] }
		var bfs_q: Array[int] = [seed]
		var bfs_vis: Dictionary = {}
		while not bfs_q.is_empty():
			var cur: int = bfs_q.pop_front()
			if bfs_vis.has(cur):
				continue
			bfs_vis[cur] = true
			zone_pool[cur] = pool_idx
			(pool["members"] as Array).append(cur)
			pool["total_cap"]  = float(pool["total_cap"])  + float(zone_info[cur]["local_cap"])
			pool["total_draw"] = float(pool["total_draw"]) + float(zone_info[cur]["local_draw"])
			for nb: int in (zone_adj[cur] as Array):
				if not bfs_vis.has(nb):
					bfs_q.append(nb)
		pools.append(pool)

	_owner._pmdbg("[PM:EVAL] PASS2 pools=%d zones=%d" % [pools.size(), n_zones])
	for pi: int in pools.size():
		var p: Dictionary = pools[pi]
		_owner._pmdbg("[PM:EVAL]   pool%d members=%s cap=%.1fw draw=%.1fw" % [
			pi, str(p["members"]), p["total_cap"], p["total_draw"]])

	## Distribute pool capacity: each deficit zone pulls surplus from generator zones
	## in the same pool. No hop limit — any zone in the pool can power any other.
	for pi: int in pools.size():
		var p: Dictionary = pools[pi]
		var members: Array = p["members"]
		if float(p["total_cap"]) <= 0.0:
			continue   ## No generators in this pool.

		for zi: int in members:
			var local_cap_zi:  float = float(zone_info[zi]["local_cap"])
			var local_draw_zi: float = float(zone_info[zi]["local_draw"])
			var deficit: float = local_draw_zi - local_cap_zi - float(zone_info[zi]["imported_w"])
			if deficit <= 0.0:
				continue   ## Zone covered locally.

			## Pull from any pool member that has surplus.
			for nj: int in members:
				if nj == zi or deficit <= 0.0:
					continue
				var nj_cap:  float = float(zone_info[nj]["local_cap"])
				var nj_draw: float = float(zone_info[nj]["local_draw"])
				var nj_exp:  float = float(zone_info[nj]["exported_w"])
				var avail: float = maxf(0.0, nj_cap - nj_draw - nj_exp)
				if avail <= 0.0:
					continue
				var transfer: float = minf(avail, deficit)
				_owner._pmdbg("[PM:EVAL] PASS2 pool%d: %.1fw  Z%d->Z%d (avail=%.1f deficit=%.1f)" % [
					pi, transfer, nj, zi, avail, deficit])
				zone_info[zi]["imported_w"] = float(zone_info[zi]["imported_w"]) + transfer
				zone_info[nj]["exported_w"] = float(zone_info[nj]["exported_w"]) + transfer
				deficit -= transfer
				var imp_from: Array = zone_info[zi]["import_from"]
				if not imp_from.has(nj):
					imp_from.append(nj)
				var exp_to: Array = zone_info[nj]["export_to"]
				if not exp_to.has(zi):
					exp_to.append(zi)


## ──────────────────────────────────────────────────────────────────────────
## PASS 3 — evaluate each zone with net watts (local ± imported/exported).
## ──────────────────────────────────────────────────────────────────────────
## Sets _owner.active_draw_watts / _owner.total_capacity_watts (accumulated per zone) as a
## side effect, same as the pre-split monolith did. Returns a Dictionary with
## the four aggregate flags/counters the caller's tail section needs:
##   "any_overloaded", "any_offline", "zones_with_device", "zones_offline"
func _evaluate_pass3_zone_resolution(
		n_zones: int,
		zone_node_sets: Array[Dictionary],
		zone_info: Array[Dictionary]) -> Dictionary:
	_owner.active_draw_watts    = 0.0
	_owner.total_capacity_watts = 0.0

	var any_overloaded:      bool = false
	var any_offline:       bool = false
	var zones_with_device: int  = 0
	var zones_offline:     int  = 0

	for zi: int in n_zones:
		var info: Dictionary    = zone_info[zi]
		if not bool(info["has_device"]):
			continue
		zones_with_device += 1

		var zone_keys: Dictionary = zone_node_sets[zi]

		## ── Sustained-brownout latch ───────────────────────────────────────
		## If this zone's FULL shared component was latched into exhausted
		## brownout (cross-zone gens+battery depleted), keep it brownout
		## regardless of what a foreign zone might momentarily offer — power
		## only returns after a MANUAL generator restart clears the latch.
		## Flood to the full component so every zone in the share produces the
		## SAME signature and all of them stay latched together.
		if not _owner._exhausted_brownout_keys.is_empty():
			var latched_keys: Dictionary = _flood_component_keys(zone_keys)
			if _owner._exhausted_brownout_keys.has(_component_sig_key(latched_keys)):
				_owner._pmdbg("[PM:EVAL]   zone %d: LATCHED (exhausted brownout) — holding full component" % zi)
				_sustained_brownout_component(latched_keys)
				any_overloaded = true
				continue

		## ── Battery classification ─────────────────────────────────────────
		## local_bats  — batteries physically inside this zone.
		## cross_bats  — batteries in OTHER zones that are BFS-reachable via
		##               _owner._adjacency (which already blocks pass_battery=false
		##               breakers).  Only charged, reachable batteries qualify.
		var local_bats:       Array[Dictionary] = []
		var cross_bats:       Array[Dictionary] = []
		var local_bat_charge: float             = 0.0

		## Collect one snap_key per local zone node (for BFS origin seeds).
		var zone_key_list: Array[String] = []
		for zk: String in zone_keys:
			zone_key_list.append(zk)

		for bat: Dictionary in _owner._batteries.values():
			if not bat.get("enabled", true):
				continue
			var bcharge: float = float(bat.get("charge_wh", 0.0))
			var bat_key: String = ""
			var is_local: bool = false

			for wn: Dictionary in _owner._wire_nodes.values():
				if wn["role"] == "battery" and wn["device_id"] == bat["id"]:
					bat_key = wn.get("key", "")
					if zone_keys.has(bat_key):
						is_local = true
					break

			if is_local:
				local_bats.append(bat)
				local_bat_charge += bcharge
			elif bcharge > 0.0 and not bat_key.is_empty():
				## Cross-zone battery — only valid if reachable through _owner._adjacency
				## (i.e. all breakers between us have pass_battery=true).
				var bat_reachable: bool = false
				for seed: String in zone_key_list:
					if _owner._adjacency_bfs_can_reach(seed, bat_key):
						bat_reachable = true
						break
				if bat_reachable:
					cross_bats.append(bat)

		var any_bat_charge: float = local_bat_charge
		for cb: Dictionary in cross_bats:
			any_bat_charge += float(cb.get("charge_wh", 0.0))

		## ── Effective watts ────────────────────────────────────────────────
		## Exported watts count as extra load on this zone (own-zone stress rule).
		## Imported watts reduce the effective deficit.
		var exported_w:   float = float(info["exported_w"])
		var imported_w:   float = float(info["imported_w"])
		var local_cap:    float = float(info["local_cap"])
		var local_draw:   float = float(info["local_draw"])

		## Effective draw this zone must cover = own draw + any exports committed.
		var effective_draw: float = local_draw + exported_w
		## Net deficit = what we still need after imports.
		var net_deficit: float   = effective_draw - local_cap - imported_w

		## Accumulate global totals (local gen cap + local consumer draw, no double-count).
		_owner.total_capacity_watts += local_cap
		_owner.active_draw_watts    += local_draw



		_owner._pmdbg("[PM:EVAL] PASS3 zone %d: local_cap=%.1f local_draw=%.1f imported=%.1f exported=%.1f net_deficit=%.1f local_bats=%d cross_bats=%d any_bat_charge=%.1f" % [
			zi, local_cap, local_draw, imported_w, exported_w, net_deficit,
			local_bats.size(), cross_bats.size(), any_bat_charge])
		## ── No local capacity and no import: battery or cut ───────────────
		if local_cap <= 0.0 and imported_w <= 0.0:
			if local_draw <= 0.0:
				_owner._pmdbg("[PM:EVAL]   zone %d: empty (no cap, no draw)" % zi)
				continue   ## Empty zone.
			if any_bat_charge > 0.0:
				_owner._pmdbg("[PM:EVAL]   zone %d: no gen, using battery" % zi)
				_activate_discharge_for_component(local_bats, cross_bats)
				_shed_in_component(zone_keys, 0.0)
				any_overloaded = true
			else:
				_owner._pmdbg("[PM:EVAL]   zone %d: CUT (no gen, no battery)" % zi)
				_owner._cut_consumers_in_zone(zone_keys)
				any_offline = true
				zones_offline += 1
			continue

		## ── Zone is healthy (net_deficit ≤ 0): maybe unshed ───────────────
		## net_deficit is computed from the CURRENT (post-shed) draw, where shed
		## items count at residual (0w).  A zone can therefore read "healthy"
		## purely BECAUSE items are shed.  Un-shedding then restores full draw,
		## re-overloads, re-sheds next solve → shed↔unshed oscillation + false
		## OVERLOADED flicker.  So only un-shed when the FULL restored draw
		## (every shed item back at full watts) still fits under available
		## capacity (own cap + imports).  Otherwise hold the shed: the grid is
		## genuinely at-capacity and stays ONLINE with load-shedding active.
		if net_deficit <= 0.0:
			var avail_cap: float = local_cap + imported_w - exported_w
			var full_draw: float = _component_draw_unshed(zone_keys)
			if full_draw <= avail_cap:
				_owner._pmdbg("[PM:EVAL]   zone %d: HEALTHY+UNSHED (net_deficit=%.1f full_draw=%.1f avail=%.1f)" % [zi, net_deficit, full_draw, avail_cap])
				_unshed_component(zone_keys)
			else:
				## Full unshed draw exceeds cap — try to restore the highest-
				## priority items that individually fit (partial unshed).  Items
				## that won't fit stay shed.  Stable: we only commit what fits,
				## so the next solve sees the same committed_draw and makes the
				## same decision → no oscillation.
				_owner._pmdbg("[PM:EVAL]   zone %d: AT-CAPACITY, partial unshed (net_deficit=%.1f full_draw=%.1f avail=%.1f)" % [zi, net_deficit, full_draw, avail_cap])
				_partial_unshed_component(zone_keys, avail_cap)
			continue

		## ── Zone has deficit: try backups first ───────────────────────────
		var zone_capacity: float = local_cap
		var zone_draw:     float = local_draw

		var backups_started: bool = false
		for gen: Dictionary in _owner._generators.values():
			if not gen.get("backup", false) or gen.get("running", false):
				continue
			if float(gen.get("fuel", 0.0)) <= 0.0 or float(gen.get("health", 0.0)) <= 0.0:
				continue
			for wn: Dictionary in _owner._wire_nodes.values():
				if wn["role"] == "generator" and wn["device_id"] == gen["id"]:
					if zone_keys.has(wn["key"]):
						gen["running"]      = true
						gen["auto_started"] = true
						var gn: Node = _owner._safe_dict_node(gen)
						if gn != null and is_instance_valid(gn) and gn.has_method("set_running"):
							gn.set_running(true)
						_owner.generator_started.emit(gen["id"])
						_owner._recalculate_capacity()
						backups_started = true
					break
		if backups_started:
			zone_capacity = _component_capacity(zone_keys)
			zone_draw     = _component_draw(zone_keys)
			_owner.total_capacity_watts += zone_capacity - local_cap   ## add backup delta
			## Recompute net deficit after backups.
			net_deficit = (zone_draw + exported_w) - zone_capacity - imported_w

		## ── Shed lights to close the gap ─────────────────────────────────
		## Effective capacity available to this zone = own cap + imports.
		var effective_cap: float = zone_capacity + imported_w - exported_w
		## Did we have to shed anything this pass to fit under capacity?  If so,
		## the zone is at-capacity and must STAY shed — the final else branch
		## below must NOT unshed it (doing so caused a shed↔unshed oscillation
		## that flickered the grid into a false OVERLOADED state every solve).
		var shed_this_pass: bool = false
		if net_deficit > 0.0:
			var pre_shed_draw: float = zone_draw
			zone_draw = _shed_in_component(zone_keys, effective_cap)
			shed_this_pass = zone_draw < pre_shed_draw
			net_deficit = (zone_draw + exported_w) - zone_capacity - imported_w

		## ── Final: battery or cut ─────────────────────────────────────────
		if net_deficit > 0.0:
			if any_bat_charge > 0.0:
				_activate_discharge_for_component(local_bats, cross_bats)
				any_overloaded = true
			else:
				## Distinguish CROSS-ZONE share from a STANDALONE zone:
				##   • Cross-zone = this zone imports power from, or exports
				##     power to, a foreign zone across a pass-through breaker
				##     (imported_w > 0 OR exported_w > 0).  Its exhaustion goes
				##     to SUSTAINED BROWNOUT (orange, gens tripped, latched) —
				##     NOT fully offline — per the cross-zone decisions.
				##   • Standalone (own gen, no battery, no import/export) keeps
				##     the original OFFLINE cut behavior.
				var is_cross_zone: bool = imported_w > 0.0 or exported_w > 0.0
				if is_cross_zone:
					## Expand to the FULL shared component (every zone bridged by
					## non-tripped pass-through breakers — scales to N zones), so
					## the exporter's generator (in a DIFFERENT zone) actually
					## trips and ALL shared zones brown out together.
					var comp_keys: Dictionary = _flood_component_keys(zone_keys)
					## ── Upgraded ("smart") breaker pre-empt ────────────────────
					## If an UPGRADED breaker sits in this component, untripped,
					## and currently passing power, it self-trips to ISOLATE the
					## two sides instead of the standard multi-zone sustained
					## brownout.  The generator side keeps running (untouched);
					## only THIS deficit zone (which has no gen/battery of its
					## own — it was piggybacking) goes OFFLINE, same as a
					## standalone zone with no source.  The severed adjacency
					## only takes effect on the NEXT solve (this pass already
					## computed sharing with the old topology), so we flag
					## _owner._needs_resolve to re-evaluate cleanly next frame with the
					## breaker isolated.
					var upgraded_ids: Array[String] = _find_upgraded_breakers_in_component(comp_keys)
					if not upgraded_ids.is_empty():
						## Group key ties every sibling breaker that self-tripped
						## FROM THIS SAME EXHAUSTION EVENT together, so a group
						## reset (see _reset_upgraded_breaker_group) can find and
						## reset all of them at once instead of leaving some stuck.
						var trip_group_key: String = _component_sig_key(comp_keys)
						_owner._pmdbg("[PM:EVAL]   zone %d: CROSS-ZONE EXHAUSTED -> UPGRADED breaker(s) %s self-trip, isolating (imp=%.1f exp=%.1f) group=%s" % [zi, str(upgraded_ids), imported_w, exported_w, trip_group_key])
						for ubid: String in upgraded_ids:
							_self_trip_upgraded_breaker(ubid, trip_group_key)
						_owner._cut_consumers_in_zone(zone_keys)
						any_offline = true
						zones_offline += 1
						_owner._needs_resolve = true   ## re-solve next frame with breaker isolated
					else:
						_owner._pmdbg("[PM:EVAL]   zone %d: CROSS-ZONE EXHAUSTED -> sustained brownout FULL component (%d nodes, imp=%.1f exp=%.1f)" % [zi, comp_keys.size(), imported_w, exported_w])
						_sustained_brownout_component(comp_keys)
						any_overloaded = true   ## brownout, not offline
				else:
					_owner._cut_consumers_in_zone(zone_keys)
					any_offline = true
					zones_offline += 1
		else:
			## Backups or shedding resolved the deficit (net_deficit ≤ 0).
			## Per the locked shed-before-battery policy: shed load is the
			## LAST line of defense before the battery, so once shedding has
			## fired we keep it shed and the grid stays ONLINE (with a load-
			## shedding badge) — we do NOT unshed just because the reduced
			## draw now fits under capacity, or it would immediately re-power,
			## overload again, and oscillate.  Only unshed when the zone fits
			## entirely WITHOUT any shed this pass (genuinely healthy).
			if shed_this_pass:
				## At-capacity, holding shed.  Grid is ONLINE, not OVERLOADED —
				## load shedding is doing its job and the deficit is gone.
				pass
			else:
				_unshed_component(zone_keys)

	return {
		"any_overloaded":   any_overloaded,
		"any_offline":      any_offline,
		"zones_with_device": zones_with_device,
		"zones_offline":    zones_offline,
	}



## ── Activate battery discharge for a component in deficit/overload ───────────
## Stops charging and starts discharging on local batteries first.
## If local charge is zero, falls through to cross-zone batteries.
## Called inline from _evaluate_per_component() — never trips the global grid.
func _activate_discharge_for_component(
		local_bats: Array[Dictionary],
		cross_bats: Array[Dictionary]) -> void:

	var activated_any: bool = false

	## Local batteries first.
	for bat: Dictionary in local_bats:
		if not bat.get("enabled", true):
			continue
		if float(bat.get("charge_wh", 0.0)) <= 0.0:
			continue
		if not bat.get("discharging", false):
			bat["discharging"] = true
			bat["charging"]    = false
			_owner.battery_state_changed.emit(bat["id"], true)
			_owner._notify_battery_mode(bat["id"])
			_owner._notify_battery_node(bat["id"])
		elif bat.get("charging", false):
			## Was charging — flip it.
			bat["charging"] = false
			_owner._notify_battery_mode(bat["id"])
			_owner._notify_battery_node(bat["id"])
		activated_any = true

	## If local batteries are empty, fall through to cross-zone.
	if not activated_any:
		for bat: Dictionary in cross_bats:
			if not bat.get("enabled", true):
				continue
			if float(bat.get("charge_wh", 0.0)) <= 0.0:
				continue
			if not bat.get("discharging", false):
				bat["discharging"] = true
				bat["charging"]    = false
				_owner.battery_state_changed.emit(bat["id"], true)
				_owner._notify_battery_mode(bat["id"])
				_owner._notify_battery_node(bat["id"])


## ─── Legacy stubs (kept so call-sites compile) ───────────────────────────────
## These are no longer called internally — _evaluate_per_component() replaces them.
## External callers (if any) are directed here for safety.
func _recalculate_draw_from_consumers() -> void:
	## Recompute global _owner.active_draw_watts from all reachable consumers.
	## Still used by _start_generator() recovery path and any legacy callers.
	_owner.active_draw_watts = 0.0
	for c: Dictionary in _owner._consumers.values():
		if not _owner._is_consumer_reachable(c["id"]):
			continue
		if c.get("powered", false):
			_owner.active_draw_watts += float(c.get("watts", 0.0))
		elif c.get("shed", false) and c.get("active", false):
			_owner.active_draw_watts += _shed_residual_watts(c)
	for bat: Dictionary in _owner._batteries.values():
		if bat.get("charging", false) \
				and float(bat.get("charge_wh", 0.0)) < float(bat.get("capacity_wh", 0.0)):
			_owner.active_draw_watts += _owner.BATTERY_CHARGE_WATTS


func _evaluate_grid_state() -> void:
	pass  ## Replaced by _evaluate_per_component(). Stub preserved for compile safety.


func _attempt_load_shed(_deficit: float) -> void:
	pass  ## Replaced by _evaluate_per_component(). Stub preserved for compile safety.

