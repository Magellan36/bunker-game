extends RefCounted
class_name PowerRegistry
## PowerRegistry.gd  —  Stage 8 (first slice, mirrors Stage 5's PowerGraph.gd)
## ─────────────────────────────────────────────────────────────────────────────
## Consumer/generator/battery registration CRUD, extracted out of
## PowerManager.gd.
##
## SCOPE — pure CRUD only. Deliberately excludes anything that carries solver
## POLICY (auto-start/stop decisions, priority-driven re-shed, force-stop on
## disable), which stays in PowerManager since it's tightly coupled to the
## rest of the solver:
##   - set_consumer_priority / _reset_shed_for_consumer_component (re-shed policy)
##   - set_generator_fuel / set_generator_health (auto-start/stop a generator
##     when fuel/health crosses zero — calls _start_generator/_stop_generator)
##   - set_generator_running / set_generator_backup (backup-generator
##     orchestration + capacity recalculation)
##   - set_battery_enabled (force-stops active charge/discharge as a side effect)
##   - _generators_reachable_from_node / _generator_wire_key / _battery_wire_key
##     (BFS reachability — solver/graph concern)
##
## DESIGN — same pattern as PowerGraph.gd: `_consumers`, `_generators`, and
## `_batteries` dicts stay physically declared on PowerManager (NOT moved
## here) because they're referenced from ~135 other places scattered across
## the solver (_tick_generators, _tick_batteries, _evaluate_pass3_zone_
## resolution, shed/unshed logic, etc.) that are staying in PowerManager this
## pass — moving the dicts would mean touching all of those too. PowerRegistry
## holds a plain `_owner` back-reference and reaches into `_owner._consumers`/
## `_owner._generators`/`_owner._batteries`/`_owner._wire_nodes`/
## `_owner._adjacency` directly, calls `_owner._solve_network()`/`_pmdbg()`/
## `_owner._recalculate_capacity()`/`_owner._notify_battery_node()`/
## `_owner.unregister_wire_node()`, and emits `_owner.<signal>` (signals stay
## declared on PowerManager so existing `.connect()` sites are untouched).
##
## PowerManager holds one instance (`_registry`) and forwards its public
## consumer/generator/battery CRUD API to it with IDENTICAL signatures, so
## every external call site elsewhere in the codebase needs zero changes.

var _owner: PowerManager = null

func _init(owner: PowerManager) -> void:
	_owner = owner


func register_consumer(
		id:       String,
		watts:    float,
		node:     Node,
		type:     String = "unknown",
		priority: int    = 0,
		active:   bool   = true) -> void:

	if priority == 0:
		priority = DeviceDatabase.DEFAULT_PRIORITY_BY_TYPE.get(type, 3)

	if _owner._consumers.has(id):
		push_warning("PowerManager: duplicate consumer '%s' — updating." % id)

	_owner._consumers[id] = {
		"id":       id,
		"watts":    watts,
		"active":   active,
		"node":     node,
		"type":     type,
		"priority": priority,
		"shed":     false,
		"powered":  false,
	}
	_owner.consumer_registered.emit(id, watts, priority)


## Remove a consumer.
## NOTE: call _owner.unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.  If you forget, this function
## will clean up the wire node as a fallback (safe but slightly less clean).
func unregister_consumer(id: String) -> void:
	if not _owner._consumers.has(id):
		return
	## Safety fallback: if the wire node for this consumer still exists (device
	## was deconstructed without calling unregister_wire_node first), remove it
	## now — which also destroys all connected wire segments automatically.
	for wn: Dictionary in _owner._wire_nodes.values():
		if wn["role"] == "consumer" and wn["device_id"] == id:
			_owner.unregister_wire_node(wn["key"])
			break
	_owner._consumers.erase(id)
	_owner.consumer_unregistered.emit(id)


## Toggle device switch state (player flips a light switch, etc.)
func set_consumer_active(id: String, active: bool) -> void:
	if not _owner._consumers.has(id):
		return
	_owner._consumers[id]["active"] = active
	_owner._solve_network()


## Returns watt draw of a registered consumer, or 0.0 if unknown.
## Used by WireDrawMode to display device cost in hover labels.
func get_consumer_watts(id: String) -> float:
	return float(_owner._consumers.get(id, {}).get("watts", 0.0))
func get_consumer_priority(id: String) -> int:
	return int(_owner._consumers.get(id, {}).get("priority", 3))


## Set a consumer's power priority (1–5) and re-solve the grid so shedding
## immediately reflects the new tier.  Clamped to [PRIORITY_MIN, PRIORITY_MAX].
## Called by PowerPriorityUI when the player presses the ◄ / ► arrows.
func get_consumer_active(id: String) -> bool:
	return bool(_owner._consumers.get(id, {}).get("active", false))


## Returns true if the consumer is currently receiving full power.
func get_consumer_powered(id: String) -> bool:
	return bool(_owner._consumers.get(id, {}).get("powered", false))


## Returns true if the consumer is currently load-shed (connected but cut).
func get_consumer_shed(id: String) -> bool:
	return bool(_owner._consumers.get(id, {}).get("shed", false))


## One-shot status snapshot for the priority UI. Keys:
##   "registered" bool — false if id unknown to the grid
##   "watts"      float
##   "priority"   int  (1–5)
##   "active"     bool — player switch state
##   "powered"    bool — receiving full power right now
##   "shed"       bool — load-shed (connected but not powered)
##   "status_str" String — "POWERED" / "SHED" / "NO POWER" / "OFF" / "UNWIRED"
func get_consumer_status(id: String) -> Dictionary:
	if not _owner._consumers.has(id):
		return {"registered": false}
	var c: Dictionary = _owner._consumers[id]
	var active:  bool  = bool(c.get("active", false))
	var powered: bool  = bool(c.get("powered", false))
	var shed:    bool  = bool(c.get("shed", false))
	var wired:   bool  = _consumer_is_wired(id)

	var status_str: String
	if not active:
		status_str = "OFF"
	elif shed:
		status_str = "SHED"
	elif powered:
		status_str = "POWERED"
	elif not wired:
		status_str = "UNWIRED"
	else:
		status_str = "NO POWER"

	return {
		"registered": true,
		"watts":      float(c.get("watts", 0.0)),
		"priority":   int(c.get("priority", 3)),
		"active":     active,
		"powered":    powered,
		"shed":       shed,
		"wired":      wired,
		"status_str": status_str,
	}


## True if this consumer has a wire node that participates in any edge.
func _consumer_is_wired(id: String) -> bool:
	for wn: Dictionary in _owner._wire_nodes.values():
		if wn.get("role", "") == "consumer" and wn.get("device_id", "") == id:
			var key: String = wn.get("key", "")
			return _owner._adjacency.has(key) and not (_owner._adjacency[key] as Array).is_empty()
	return false


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — GENERATORS
# ═══════════════════════════════════════════════════════════════════════════════

## Register a generator. Call from GeneratorObject._ready().
##   gen_id    — str(node.get_instance_id()) or a stable string id
##   watts     — rated output when running and healthy
##   node      — scene node; implement set_running(bool)
##   is_backup — if true, idles until all primaries fail
##   fuel      — 0–100
##   health    — 0–100
func register_generator(
		gen_id:    String,
		watts:     float,
		node:      Node  = null,
		is_backup: bool  = false,
		fuel:      float = 100.0,
		health:    float = 100.0) -> void:

	_owner._pmdbg("[PM:GEN] register_generator called — id=%s watts=%.0f backup=%s fuel=%.1f health=%.1f" % [
		gen_id, watts, str(is_backup), fuel, health])
	var running: bool = (not is_backup) and fuel > 0.0 and health > 0.0
	_owner._generators[gen_id] = {
		"id":           gen_id,
		"watts":        watts,
		"node":         node,
		"running":      running,
		"backup":       is_backup,
		"fuel":         clampf(fuel,   0.0, 100.0),
		"health":       clampf(health, 0.0, 100.0),
		"auto_started": false,
	}
	_owner._pmdbg("[PM:GEN] _generators now has %d entries" % _owner._generators.size())
	_owner._recalculate_capacity()
	_owner.generator_registered.emit(gen_id, watts, is_backup)
	if running:
		_owner.generator_started.emit(gen_id)
	## Trigger a network solve so consumers connected to this generator light up
	## immediately without waiting for another topology event.
	_owner._solve_network()


## Unregister a generator (sold / destroyed).
## NOTE: call _owner.unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.
func unregister_generator(gen_id: String) -> void:
	if not _owner._generators.has(gen_id):
		return
	## Safety fallback: clean up wire node and its edges if still registered.
	for wn: Dictionary in _owner._wire_nodes.values():
		if wn["role"] == "generator" and wn["device_id"] == gen_id:
			_owner.unregister_wire_node(wn["key"])
			break
	_owner._generators.erase(gen_id)
	_owner._recalculate_capacity()
	_owner.generator_unregistered.emit(gen_id)
	_owner._solve_network()


## Returns current fuel level [0.0–100.0] for the given generator.
## Returns -1.0 if the gen_id is not registered.
func get_generator_fuel(gen_id: String) -> float:
	if not _owner._generators.has(gen_id):
		return -1.0
	return _owner._generators[gen_id]["fuel"]

## Returns whether the generator is currently running.
## Returns false if the id is unknown.
func get_generator_running(gen_id: String) -> bool:
	if not _owner._generators.has(gen_id):
		return false
	return _owner._generators[gen_id].get("running", false)

## Player refuels at the generator.
func get_generator_is_backup(gen_id: String) -> bool:
	if not _owner._generators.has(gen_id):
		return false
	return _owner._generators[gen_id].get("backup", false)

## Returns current health [0.0–100.0] for the given generator.
func get_generator_health(gen_id: String) -> float:
	if not _owner._generators.has(gen_id):
		return -1.0
	return _owner._generators[gen_id].get("health", 100.0)

## Returns rated output watts for the given generator.
func get_generator_watts(gen_id: String) -> float:
	if not _owner._generators.has(gen_id):
		return 0.0
	return _owner._generators[gen_id].get("watts", 0.0)

## Status snapshot for HUD or save system.
func get_generators_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gen: Dictionary in _owner._generators.values():
		out.append({
			"id": gen["id"], "watts": gen["watts"], "running": gen["running"],
			"backup": gen["backup"], "fuel": gen["fuel"], "health": gen["health"],
		})
	return out


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — BATTERIES
# ═══════════════════════════════════════════════════════════════════════════════

## Register a battery bank. Call from BatteryBank._ready().
##   capacity_wh    — max stored watt-hours
##   initial_charge — starting charge; -1 = full
func register_battery(
		bat_id:         String,
		capacity_wh:    float,
		node:           Node  = null,
		initial_charge: float = -1.0) -> void:

	var charge: float = initial_charge if initial_charge >= 0.0 else capacity_wh
	charge = clampf(charge, 0.0, capacity_wh)
	_owner._batteries[bat_id] = {
		"id":          bat_id,
		"capacity_wh": capacity_wh,
		"charge_wh":   charge,
		"node":        node,
		"discharging": false,
		"enabled":     true,   ## player can disable via BatteryBank info panel
	}
	_owner.battery_registered.emit(bat_id, capacity_wh)
	_owner._notify_battery_node(bat_id)


## Unregister battery (sold / destroyed).
## NOTE: call _owner.unregister_wire_node() BEFORE this in _exit_tree() so that
## connected wire segments are destroyed first.
func unregister_battery(bat_id: String) -> void:
	if not _owner._batteries.has(bat_id):
		return
	## Safety fallback: clean up wire node and its edges if still registered.
	for wn: Dictionary in _owner._wire_nodes.values():
		if wn["role"] == "battery" and wn["device_id"] == bat_id:
			_owner.unregister_wire_node(wn["key"])
			break
	_owner._batteries.erase(bat_id)
	_owner.battery_unregistered.emit(bat_id)


## Force-set charge level (load from save).
func set_battery_charge(bat_id: String, charge_wh: float) -> void:
	if not _owner._batteries.has(bat_id):
		return
	_owner._batteries[bat_id]["charge_wh"] = clampf(
		charge_wh, 0.0, float(_owner._batteries[bat_id]["capacity_wh"]))
	## Reset drained flag so battery_drained can fire again if needed.
	if float(_owner._batteries[bat_id]["charge_wh"]) > 0.0:
		_owner._batteries[bat_id]["_drained_emitted"] = false
	_owner._notify_battery_node(bat_id)


## Total stored energy (watt-hours) across all batteries.
func total_battery_wh() -> float:
	var t: float = 0.0
	for bat: Dictionary in _owner._batteries.values():
		t += float(bat.get("charge_wh", 0.0))
	return t


## Aggregate charge as 0.0–1.0 fraction.
func battery_charge_ratio() -> float:
	var cap: float = 0.0
	var chg: float = 0.0
	for bat: Dictionary in _owner._batteries.values():
		cap += float(bat.get("capacity_wh", 0.0))
		chg += float(bat.get("charge_wh",   0.0))
	return chg / cap if cap > 0.0 else 0.0


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — STATUS / QUERIES
# ═══════════════════════════════════════════════════════════════════════════════

## 0.0–1.0+ load ratio (>1.0 = currently brownout).
func is_consumer_powered(id: String) -> bool:
	return _owner._consumers.get(id, {}).get("powered", false)


## Human-readable grid state string for UI display.
## ONLINE / OVERLOADED / BROWNOUT / TRIPPED / OFFLINE
