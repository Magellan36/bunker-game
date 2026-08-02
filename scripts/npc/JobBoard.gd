extends Node
## JobBoard.gd  (NPC Pass 2, Part 4) — AUTOLOAD "JobBoard"
## Polls world systems every SCAN_INTERVAL and maintains the open-jobs list.
## Discovery is read-only: no farming/water/power file is edited to post
## jobs — the board looks for the same world conditions a player would.
##
## Job dictionary shape:
##   id           String  — stable while the condition persists ("refuel_<iid>")
##   type         String  — "HARVEST" | "REPLACE_FILTER" | "REFUEL"
##   target       Node    — tray / purifier / generator
##   fetch_filter Callable or null — matches the item that must be carried
##   claimed_by   Node    — NPC or null
##
## FUTURE WORK: planting, cooking, water-collection, repair jobs — each is
## one new _scan_*() function + one JobActivity type-branch in NPCBrain.

const SCAN_INTERVAL: float = 2.0
const REFUEL_BELOW: float = 40.0
const FILTER_BELOW: float = 30.0

var _jobs: Dictionary = {}   ## id -> job dict
var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	_rescan()

func get_open_jobs() -> Array:
	var out: Array = []
	for job: Dictionary in _jobs.values():
		var claimant: Node = job.get("claimed_by")
		if claimant != null and not is_instance_valid(claimant):
			job["claimed_by"] = null   ## claimant vanished — auto-release
		if job.get("claimed_by") == null:
			out.append(job)
	return out

func claim(job: Dictionary, npc: Node) -> bool:
	var live: Dictionary = _jobs.get(job.get("id", ""), {})
	if live.is_empty() or live.get("claimed_by") != null:
		return false
	live["claimed_by"] = npc
	NPCDebug.log_job("claimed", live, npc)
	return true

func release(job: Dictionary, npc: Node) -> void:
	var live: Dictionary = _jobs.get(job.get("id", ""), {})
	if not live.is_empty() and live.get("claimed_by") == npc:
		live["claimed_by"] = null

## True while the job's world condition still holds (activities poll this so
## a job finished by the player mid-walk cancels cleanly).
func still_valid(job: Dictionary) -> bool:
	return _jobs.has(job.get("id", ""))

func _rescan() -> void:
	var seen: Dictionary = {}
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_refuel(seen)
	## Drop jobs whose condition ended; keep claim state on persisting ones.
	for id: String in _jobs.keys().duplicate():
		if not seen.has(id):
			_jobs.erase(id)

func _mark(seen: Dictionary, id: String, type: String, target: Node,
		fetch_filter: Variant) -> void:
	seen[id] = true
	if _jobs.has(id):
		_jobs[id]["target"] = target   ## refresh ref; keep claimed_by
		return
	_jobs[id] = {
		"id": id, "type": type, "target": target,
		"fetch_filter": fetch_filter, "claimed_by": null,
	}
	NPCDebug.log_job("posted", _jobs[id])

func _scan_harvest(seen: Dictionary) -> void:
	for tray: Node in get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray) or not ("plant_refs" in tray):
			continue
		var any_ready: bool = false
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.is_ready():
				any_ready = true
				break
		if any_ready:
			_mark(seen, "harvest_%d" % tray.get_instance_id(),
				"HARVEST", tray, null)

func _scan_filters(seen: Dictionary) -> void:
	## Only post if a usable spare filter exists SOMEWHERE (loose or shelved)
	## — per spec, NPCs only replace when a replacement is actually around.
	var spare_filter: Callable = func(item: Node) -> bool:
		return item is PurifierFilterItem and not item.is_used
	if not _spare_exists(spare_filter):
		return
	for pur: Node in get_tree().get_nodes_in_group("water_purifier"):
		if not is_instance_valid(pur) or not ("filter_quality" in pur):
			continue
		if pur.filter_quality < FILTER_BELOW:
			_mark(seen, "filter_%d" % pur.get_instance_id(),
				"REPLACE_FILTER", pur, spare_filter)

func _scan_refuel(seen: Dictionary) -> void:
	## FuelCan.gd declares no class_name — duck-type instead of `is FuelCan`.
	var fuel_can: Callable = func(item: Node) -> bool:
		return item.has_method("refuel_tick") and item.has_method("can_store") \
			and ("_fuel_remaining" in item) and item._fuel_remaining > 0.0
	if not _spare_exists(fuel_can):
		return
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return
	for gen: Node in get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		var fuel: float = pm.get_generator_fuel(str(gen.get_instance_id()))
		if fuel < REFUEL_BELOW:
			_mark(seen, "refuel_%d" % gen.get_instance_id(),
				"REFUEL", gen, fuel_can)

## Does any loose-or-shelved item matching the filter exist? Uses a dummy
## NPC-shaped search: loose world scan mirrors NPCItemUser.find_loose_item's
## exclusions, shelf scan mirrors find_shelved_item.
func _spare_exists(filter: Callable) -> bool:
	for node: Node in get_tree().get_nodes_in_group("pickup"):
		if not (node is RigidBody3D) or not is_instance_valid(node):
			continue
		if node.is_in_group("shelved"):
			continue
		if ("is_held" in node) and node.is_held:
			continue
		if (node as RigidBody3D).freeze:
			continue
		if filter.call(node):
			return true
	for shelf: Node in get_tree().get_nodes_in_group("shelf"):
		if not is_instance_valid(shelf) or not ("slots" in shelf):
			continue
		for stack in shelf.slots:
			if stack is Array and not stack.is_empty() and filter.call(stack.back()):
				return true
	return false