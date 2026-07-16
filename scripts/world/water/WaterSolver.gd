extends RefCounted
class_name WaterSolver
## WaterSolver.gd
## ─────────────────────────────────────────────────────────────────────────────
## Demand-based, priority-tier water allocation waterfall (Jul 2026). Replaces
## the old equal-split flow logic (WaterManager.get_per_consumer_rate_mL_per_day()
## et al, Step 2) now that real consumers with individual demand + priority
## exist (WaterTestSink, WaterDispenser).
##
## Extracted as its own file from day one — mirrors the exact reason
## PowerSolver.gd was split out of PowerManager (see docs/systems/power/
## README.md's own history): this is real, nontrivial solving logic, not
## something that should get bolted onto WaterManager.gd as it grows.
##
## ALGORITHM (see bunker-game-water-dispenser-plan §0 for the full derivation
## and worked examples):
##   1. Group every registered consumer reachable from a hookup by priority
##      tier (1 = highest, served first -- 5 = lowest, served last).
##   2. Walk tiers 1 -> 5. Each tier's total requested demand is either fully
##      served (tier_requested <= remaining_supply) or proportionally scaled
##      down (scale = remaining_supply / tier_requested) when oversubscribed,
##      after which remaining_supply is zeroed and every tier below receives 0.
##
## Duck-typed consumer contract (via WaterGraph.get_consumer_ref()):
##   priority: int                                (1-5, defaults to 3 if absent)
##   func get_current_demand_mL_per_day() -> float
## WaterSolver never knows or cares which concrete script implements this —
## same composition-over-inheritance pattern the power system's registries
## already use (see WaterGraph._water_nodes' own comment).
##
## DESIGN — same `_graph` back-reference pattern as PowerGraph/PowerRegistry/
## PowerSolver's split. Pure read-only queries against the graph; holds no
## state of its own between calls (matches this system's existing "compute
## live, no persistence" convention from Phase 1/Step 2).

const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5
const DEFAULT_PRIORITY: int = 3

var _graph: WaterGraph = null

func _init(graph: WaterGraph) -> void:
	_graph = graph


## Reads a consumer's tunable priority off its consumer_ref, defensively
## defaulting to DEFAULT_PRIORITY and clamping to the valid 1-5 range so a
## malformed/absent `priority` field never breaks the tier grouping.
func _read_priority(ref: Node) -> int:
	if ref == null or not is_instance_valid(ref):
		return DEFAULT_PRIORITY
	if not ("priority" in ref):
		return DEFAULT_PRIORITY
	return clampi(int(ref.priority), PRIORITY_MIN, PRIORITY_MAX)

func _read_demand(ref: Node) -> float:
	if ref == null or not is_instance_valid(ref):
		return 0.0
	if not ref.has_method("get_current_demand_mL_per_day"):
		return 0.0
	return maxf(0.0, float(ref.get_current_demand_mL_per_day()))


## Builds { tier(int) -> Array[{ "key": String, "demand": float }] } for every
## endpoint reachable from `hookup_key`. `exclude_key`, if non-empty, is
## skipped entirely (used by get_dynamic_max_for_device() to look at every
## OTHER device while reasoning about one specific device's own ceiling).
func _group_by_tier(hookup_key: String, exclude_key: String = "") -> Dictionary:
	var by_tier: Dictionary = {}
	for key: String in _graph.get_reachable_endpoint_keys(hookup_key):
		if key == exclude_key:
			continue
		var ref: Node = _graph.get_consumer_ref(key)
		if ref == null or not is_instance_valid(ref):
			continue
		var tier: int = _read_priority(ref)
		var demand: float = _read_demand(ref)
		if not by_tier.has(tier):
			by_tier[tier] = []
		(by_tier[tier] as Array).append({ "key": key, "demand": demand })
	return by_tier


## The core waterfall. Returns { node_key(String) -> received_mL_per_day(float) }
## for every endpoint reachable from `hookup_key` — a device not present in
## the returned dict simply never registered (or has 0 demand); treat a
## missing key the same as 0.0 received.
func solve_for_hookup(hookup_key: String, total_supply_mL_per_day: float) -> Dictionary:
	var received: Dictionary = {}
	var by_tier: Dictionary = _group_by_tier(hookup_key)
	var remaining: float = maxf(0.0, total_supply_mL_per_day)

	for tier: int in range(PRIORITY_MIN, PRIORITY_MAX + 1):
		if not by_tier.has(tier):
			continue
		var entries: Array = by_tier[tier]
		var tier_requested: float = 0.0
		for e: Dictionary in entries:
			tier_requested += e["demand"]

		if tier_requested <= 0.0:
			continue   ## Nothing requested this tier -- nothing to hand out, remaining untouched.

		if tier_requested <= remaining:
			for e: Dictionary in entries:
				received[e["key"]] = e["demand"]
			remaining -= tier_requested
		else:
			var scale: float = remaining / tier_requested
			for e: Dictionary in entries:
				received[e["key"]] = e["demand"] * scale
			remaining = 0.0
			## Every tier below this one is now fully starved -- the loop
			## keeps running (cheap, tiny arrays) but tier_requested <= 0.0
			## check above won't save us, so explicitly zero every
			## lower tier's entries too.
			for lower_tier: int in range(tier + 1, PRIORITY_MAX + 1):
				if by_tier.has(lower_tier):
					for e2: Dictionary in by_tier[lower_tier]:
						received[e2["key"]] = 0.0
			break

	return received


## A device's dynamic slider maximum (plan §0): run the waterfall fully
## through every tier STRICTLY ABOVE `device_priority`, then within the
## device's own tier subtract every OTHER device's current requested demand
## from what's left. Floored at 0. Recomputed live on every call -- reacts
## immediately to any other device's priority/on-off/slider state changing
## anywhere in the network, since nothing here is cached.
##
## `device_key` is excluded from its own tier's "other demand" sum (a device
## querying its own ceiling shouldn't have its own current setting subtracted
## from itself) but IS still allowed to appear in higher tiers' groupings if
## its priority ever changes mid-call -- doesn't happen in one call, so this
## is purely defensive.
func get_dynamic_max_for_device(hookup_key: String, total_supply_mL_per_day: float,
		device_key: String, device_priority: int) -> float:
	var priority: int = clampi(device_priority, PRIORITY_MIN, PRIORITY_MAX)
	var by_tier: Dictionary = _group_by_tier(hookup_key, device_key)
	var remaining: float = maxf(0.0, total_supply_mL_per_day)

	## Tiers strictly above this device's own tier, fully waterfalled.
	for tier: int in range(PRIORITY_MIN, priority):
		if not by_tier.has(tier):
			continue
		var entries: Array = by_tier[tier]
		var tier_requested: float = 0.0
		for e: Dictionary in entries:
			tier_requested += e["demand"]
		if tier_requested <= 0.0:
			continue
		if tier_requested <= remaining:
			remaining -= tier_requested
		else:
			remaining = 0.0
			break   ## Higher tiers already consumed everything -- 0 left for anything at or below.

	## Within the device's own tier, subtract every OTHER device's current
	## requested demand (device_key itself was excluded from by_tier already).
	var own_tier_other_demand: float = 0.0
	if by_tier.has(priority):
		for e: Dictionary in by_tier[priority]:
			own_tier_other_demand += e["demand"]

	return maxf(0.0, remaining - own_tier_other_demand)
