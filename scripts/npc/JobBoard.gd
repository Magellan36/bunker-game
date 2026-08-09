extends Node
## JobBoard.gd  (NPC Pass 2, Part 4) — AUTOLOAD "JobBoard"
## Polls world systems every SCAN_INTERVAL and maintains the open-jobs list.
## Discovery is read-only: no farming/water/power file is edited to post
## jobs — the board looks for the same world conditions a player would.
##
## Job dictionary shape:
##   id           String  — stable while the condition persists ("refuel_<iid>")
##   type         String  — "HARVEST" | "REPLACE_FILTER"
##   (REFUEL was JobBoard-claimed through Aug 2026; moved to a dedicated
##   multi-generator session — NPCBrain.RefuelActivity — since sweeping
##   every generator in one trip doesn't fit this single-target shape any
##   better than Cleaning's multi-item sweep does. See docs/systems/npc/README.md.)
##   target       Node    — tray / purifier / generator
##   fetch_filter Callable or null — matches the item that must be carried
##   claimed_by   Node    — NPC or null
##
## FUTURE WORK: planting, cooking, water-collection, repair jobs — each is
## one new _scan_*() function + one JobActivity type-branch in NPCBrain.

const SCAN_INTERVAL: float = 2.0
const FILTER_BELOW: float = 30.0

var _jobs: Dictionary = {}   ## id -> job dict
var _timer: float = 0.0

# ─── Cleaning discovery (Aug 2026) ──────────────────────────────────────────
## Idle-time gating for organizing — an item must sit untouched/unclaimed
## for this long before it's eligible, so NPCs don't sweep away something
## the player just set down to use in a moment. Trash items skip this
## entirely (they're unambiguously "done," not "in active use").
const CLEANING_IDLE_MIN_SEC: float = 90.0
## Debug-only override (F7 → NPCDebug.enabled) so idle-gate timing can be
## tested in seconds instead of minutes. Never changes real gameplay —
## only takes effect while NPCDebug.enabled is true.
const CLEANING_IDLE_MIN_SEC_DEBUG: float = 5.0

func _effective_cleaning_idle_min_sec() -> float:
	return CLEANING_IDLE_MIN_SEC_DEBUG if NPCDebug.enabled else CLEANING_IDLE_MIN_SEC

const CLEANING_IDLE_MOVE_TOLERANCE: float = 0.3   ## meters — moved more than this since tracking began = someone touched it, restart the clock
var _cleaning_idle_tracker: Dictionary = {}   ## item instance_id -> {"pos": Vector3, "since_msec": int}
var _trash_items_cache: Array = []
var _organizable_items_cache: Array = []

## Aug 2026 — count of genuine trash-classified items sitting in the world
## RIGHT NOW that are being silently excluded because no trash_receptacle
## exists anywhere in the level yet (see _has_trash_receptacle()'s own
## comment — this is a known, by-design permanent gap until a receptacle
## object is added). Tracked purely so debug tooling can surface it as a
## specific reason instead of it looking identical to "nothing to clean".
var _trash_blocked_by_no_receptacle: int = 0

func get_trash_items() -> Array:
	_trash_items_cache = _trash_items_cache.filter(func(i): return is_instance_valid(i))
	return _trash_items_cache

func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i): return is_instance_valid(i))
	return _organizable_items_cache

## Aug 2026 — cheap count for NPC.get_cleaning_unavailable_reason()'s
## "STILL_SETTLING" check. Same subtraction the periodic debug print
## already does, exposed as a real getter instead of duplicated inline.
func get_pending_cleaning_count() -> int:
	return maxi(0, _cleaning_idle_tracker.size() - _organizable_items_cache.size())

## Aug 2026 — for NPC.get_cleaning_unavailable_reason()'s "NO_TRASH_
## RECEPTACLE" check.
func get_trash_blocked_by_no_receptacle_count() -> int:
	return _trash_blocked_by_no_receptacle

## Aug 2026 — full snapshot for NPCDebug.dump_cleaning_state(). Resolves
## every still-tracked-but-not-yet-idle item's live remaining time, so a
## single dump answers "why isn't X organizable yet" directly instead of
## needing to watch the periodic scan print over time.
func get_cleaning_debug_snapshot() -> Dictionary:
	var idle_needed: float = _effective_cleaning_idle_min_sec()
	var now: int = Time.get_ticks_msec()
	var pending: Array = []
	for id in _cleaning_idle_tracker.keys():
		var item: Object = instance_from_id(id)
		if item == null or not is_instance_valid(item) or _organizable_items_cache.has(item):
			continue   ## already ready, or freed since — not "pending"
		var rec: Dictionary = _cleaning_idle_tracker[id]
		var elapsed: float = float(now - int(rec["since_msec"])) / 1000.0
		var name: String = item.get_display_name() if item.has_method("get_display_name") else str(item.name)
		pending.append({"name": name, "elapsed_sec": elapsed, "remaining_sec": maxf(0.0, idle_needed - elapsed)})
	return {
		"trash_count": _trash_items_cache.size(),
		"organizable_count": _organizable_items_cache.size(),
		"pending": pending,
		"trash_blocked_by_no_receptacle": _trash_blocked_by_no_receptacle,
		"idle_gate_sec": idle_needed,
		"idle_gate_is_debug": NPCDebug.enabled,
	}

func _has_trash_receptacle() -> bool:
	## Self-gating mechanism — returns false today since nothing occupies
	## this group yet, meaning trash items never make it into
	## _trash_items_cache until a receptacle is actually added later. No
	## other change needed when that happens.
	return not get_tree().get_nodes_in_group("trash_receptacle").is_empty()

## Duck-typed, matching NPCItemUser.is_edible()/is_drinkable_bottle()'s
## own established checks exactly — FoodCan/WaterBottle have no
## class_name registered, so `is FoodCan` type checks wouldn't work here.
func _is_trash_item(item: Node) -> bool:
	if item is EmptyBagItem:
		return true
	if item.has_method("has_bites_left") and not item.has_bites_left():
		return true   ## empty FoodCan
	if item.has_method("take_drink") and ("current_fill_mL" in item) and float(item.current_fill_mL) <= 0.0:
		return true   ## empty WaterBottle
	return false

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	_rescan()

func get_open_jobs() -> Array:
	var out: Array = []
	for id: String in _jobs.keys().duplicate():
		var job: Dictionary = _jobs[id]
		var target: Node = job.get("target")
		if target == null or not is_instance_valid(target):
			## Target vanished (harvested/freed, etc.) — drop immediately
			## rather than waiting for the next _rescan() (up to
			## SCAN_INTERVAL later). This is what was letting a
			## just-harvested, already-freed plant get handed to a
			## DIFFERENT NPC's JobActivity.score() as if it were still
			## open — Godot flags the freed reference the moment it's
			## assigned to a typed Node var, before score()'s own
			## is_instance_valid() check even runs.
			_jobs.erase(id)
			continue
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
	if not _jobs.has(job.get("id", "")):
		return false
	var target: Node = job.get("target")
	return target != null and is_instance_valid(target)

func _rescan() -> void:
	var seen: Dictionary = {}
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_cleaning(seen)
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
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.is_ready():
				## One job per READY PLANT now, not one per tray — a 2x1
				## tray with both cells ready posts two independent jobs.
				## target is the plant itself.
				_mark(seen, "harvest_%d" % plant.get_instance_id(),
					"HARVEST", plant, null)

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

## Same periodic cadence as Harvest/Filter/Refuel discovery — called from
## _rescan(). Rebuilds both cached lists fresh each pass; idle-tracking
## persists across passes (that's the whole point) but gets pruned for
## anything no longer present (picked up, freed, etc.). The `seen` param
## is accepted for call-signature consistency with the other _scan_*
## functions but is intentionally ignored — this maintains its own
## separate cache, not the _jobs dict.
func _scan_cleaning(seen: Dictionary) -> void:
	var trash_receptacle_exists: bool = _has_trash_receptacle()
	var new_trash: Array = []
	var new_organizable: Array = []
	var seen_ids: Dictionary = {}
	var trash_blocked_this_scan: int = 0

	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not ("is_held" in item):
			continue
		if item.is_held or item.is_in_group("shelved"):
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
			if trash_receptacle_exists:
				new_trash.append(item)
			else:
				trash_blocked_this_scan += 1
			continue   ## trash never also counts as organizable

		var pos: Vector3 = (item as Node3D).global_position
		var now: int = Time.get_ticks_msec()
		if not _cleaning_idle_tracker.has(id):
			_cleaning_idle_tracker[id] = {"pos": pos, "since_msec": now}
			continue
		var rec: Dictionary = _cleaning_idle_tracker[id]
		if pos.distance_to(rec["pos"]) > CLEANING_IDLE_MOVE_TOLERANCE:
			_cleaning_idle_tracker[id] = {"pos": pos, "since_msec": now}
			continue
		if (now - int(rec["since_msec"])) >= int(_effective_cleaning_idle_min_sec() * 1000.0):
			new_organizable.append(item)

	for id in _cleaning_idle_tracker.keys().duplicate():
		if not seen_ids.has(id):
			_cleaning_idle_tracker.erase(id)

	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
	_trash_blocked_by_no_receptacle = trash_blocked_this_scan
	if NPCDebug.enabled:
		var blocked_suffix: String = " | %d trash item(s) blocked (no trash_receptacle in level)" % trash_blocked_this_scan \
			if trash_blocked_this_scan > 0 else ""
		print("[JobBoard] Cleaning scan: %d trash, %d organizable, %d tracked-but-not-yet-idle%s" \
			% [new_trash.size(), new_organizable.size(), _cleaning_idle_tracker.size() - new_organizable.size(), blocked_suffix])

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
	## Fixed Aug 2026 — same dead-group bug as NPCItemUser.find_shelved_item();
	## real shelf/storage objects join "shelving", never "shelf".
	for shelf: Node in get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(shelf) or not ("slots" in shelf):
			continue
		for stack in shelf.slots:
			if stack is Array and not stack.is_empty() and filter.call(stack.back()):
				return true
	return false