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
##   multi-generator session — RefuelActivity — since sweeping
##   every generator in one trip doesn't fit this single-target shape any
##   better than Cleaning's multi-item sweep does. See docs/systems/npc/README.md.)
##   target       Node    — tray / purifier / generator
##   fetch_filter Callable or null — matches the item that must be carried
##   claimed_by   Node    — NPC or null
##
## FUTURE WORK: cooking, water-collection, repair jobs — each is
## one new _scan_*() function + one JobActivity type-branch in NPCBrain.
## (Gardening was listed here once, but was built as a direct NPC activity
## in NPCBrain.gd instead of a JobBoard job — hence it's dropped from this
## list.)

const SCAN_INTERVAL: float = 2.0
const FILTER_BELOW: float = 30.0

var _jobs: Dictionary = {}   ## id -> job dict
var _timer: float = 0.0

## Sep 2026 — called by WorldManager.leave_world() before the current world is
## freed (game over → reload, and any future return-to-menu). Jobs and caches
## hold node references into the old world; a fresh world must start clean.
func reset_world_state() -> void:
	_jobs.clear()
	_timer = 0.0
	_cleaning_clock_sec = 0.0
	_cleaning_idle_tracker.clear()
	_trash_items_cache.clear()
	_organizable_items_cache.clear()
	_trash_blocked_by_no_receptacle = 0

# ─── Cleaning discovery (Aug 2026) ──────────────────────────────────────────
## Idle-time gating for organizing — an item must sit untouched/unclaimed
## for this long before it's eligible, so NPCs don't sweep away something
## the player just set down to use in a moment. Trash items skip this
## entirely (they're unambiguously "done," not "in active use").

## Aug 2026 — sanity bounds for "is this thing actually still in the
## bunker." Not a general physics constraint — every real in-play
## position seen across testing sits within roughly -2..+15 on Y; an
## item outside this generous range (two NPCs were observed at
## Y≈-140000 and Y≈-58000 in one session — clearly fallen/ejected far
## outside the level, not a real placement) is excluded from the
## cleaning system entirely at scan time, for every NPC at once, rather
## than discovered per-NPC through repeated failed attempts.
## flat_distance() (used for normal target-picking) deliberately ignores
## Y — this is the check that actually catches a pure vertical
## fall-through, which flat_distance alone never would.
const CLEANING_SANITY_Y_MIN: float = -20.0
const CLEANING_SANITY_Y_MAX: float = 30.0

## Loose objects now have two deliberately separate concepts: one simulated
## second confirming that physics has actually stopped, then a short courtesy
## grace before NPCs tidy them. Player-dropped objects receive a longer,
## explicit protection window; spawned/ejected/NPC-dropped clutter does not.
## Every duration uses _cleaning_clock_sec, so 5x dev speed presents the same
## sequence five times faster instead of leaving cleanable objects untouched
## for real-time minutes.
const CLEANING_STABILIZE_SEC: float = 1.0
const CLEANING_GRACE_MAX_SEC: float = 6.0
const CLEANING_GRACE_MIN_SEC: float = 2.0
const CLEANING_PLAYER_GRACE_SEC: float = 20.0
const CLUTTER_IDLE_ZERO_AT: int = 20

func _effective_cleaning_grace_sec() -> float:
	var clutter: int = get_total_clutter_count()
	var fraction: float = clampf(float(clutter) / float(CLUTTER_IDLE_ZERO_AT), 0.0, 1.0)
	return lerpf(CLEANING_GRACE_MAX_SEC, CLEANING_GRACE_MIN_SEC, fraction)

const CLEANING_MOVE_TOLERANCE: float = 0.15
const CLEANING_STILL_LINEAR: float = 0.08
const CLEANING_STILL_ANGULAR: float = 0.15
var _cleaning_clock_sec: float = 0.0
var _cleaning_idle_tracker: Dictionary = {}   ## item instance_id -> motion/provenance state
var _trash_items_cache: Array = []
var _organizable_items_cache: Array = []

## Aug 2026 — count of genuine trash-classified items sitting in the world
## RIGHT NOW that are being silently excluded because no trash_receptacle
## exists anywhere in the level yet (see _has_trash_receptacle()'s own
## comment — this is a known, by-design permanent gap until a receptacle
## object is added). Tracked purely so debug tooling can surface it as a
## specific reason instead of it looking identical to "nothing to clean".
var _trash_blocked_by_no_receptacle: int = 0

## Aug 2026 — now also filters out anything that's become shelved or
## held SINCE the last _scan_cleaning() pass, not just freed instances.
## Root cause of a real bug: this cache only rebuilds every
## SCAN_INTERVAL (2s), so for up to ~2s after an NPC successfully
## stores an item, the now-shelved item was still returned here as if
## still organizable — and since it's now the item physically nearest
## to the NPC standing right next to the storage it just used,
## find_cleaning_target() kept re-selecting it, only for the fetch
## phase's own is_in_group("shelved") check to immediately reject it,
## every single think-tick, in a tight repeating loop until the next
## scan finally dropped it. Filtering here closes the gap at the source
## for every caller, not just find_cleaning_target()'s own defensive
## checks.
func get_trash_items() -> Array:
	_trash_items_cache = _trash_items_cache.filter(func(i):
		return is_instance_valid(i) and not i.is_in_group("shelved") \
			and not (("is_held" in i) and i.is_held))
	return _trash_items_cache

func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i):
		return is_instance_valid(i) and not i.is_in_group("shelved") \
			and not (("is_held" in i) and i.is_held))
	return _organizable_items_cache

## Aug 2026 — cheap count for NPC.get_cleaning_unavailable_reason()'s
## Pending means physically moving, stabilizing, or inside explicit player
## placement protection. Ready items are subtracted from the same tracker.
func get_pending_cleaning_count() -> int:
	return maxi(0, _cleaning_idle_tracker.size() - _organizable_items_cache.size())

func get_pending_cleaning_reason() -> String:
	var moving: int = 0
	var player_protected: int = 0
	for rec: Dictionary in _cleaning_idle_tracker.values():
		if float(rec.get("stable_since_sec", -1.0)) < 0.0:
			moving += 1
		elif StringName(rec.get("release_source", &"world")) == &"player":
			player_protected += 1
	if player_protected > 0:
		return "RECENTLY_PLACED_BY_PLAYER"
	if moving > 0:
		return "PHYSICALLY_MOVING"
	return "STABILIZING"

## Aug 2026 — total loose clutter in the level right now, for
## CleaningActivity's escalating urgency score: ready trash + ready
## organizable + still-settling (not yet past the idle gate). Includes
## the settling ones deliberately — urgency should build from the
## moment something hits the floor, not only after its individual short
## grace has elapsed.
func get_total_clutter_count() -> int:
	return _trash_items_cache.size() + _organizable_items_cache.size() + get_pending_cleaning_count()

func promote_settled_cleaning_near(origin: Vector3, radius: float) -> int:
	## A resident deliberately looking over storage has visually inspected the
	## surrounding floor. Physically sleeping/still items no longer need the
	## full courtesy delay: make them eligible now, then rebuild the cache so
	## the same utility pass can act on what the resident just noticed.
	var promoted: int = 0
	var grace_needed: float = _effective_cleaning_grace_sec()
	for id in _cleaning_idle_tracker.keys():
		var raw: Object = instance_from_id(id)
		if raw == null or not is_instance_valid(raw) or not raw is RigidBody3D:
			continue
		var item: RigidBody3D = raw as RigidBody3D
		if _organizable_items_cache.has(item) or _trash_items_cache.has(item):
			continue
		if item.freeze or item.is_in_group("shelved") \
				or (("is_held" in item) and item.is_held):
			continue
		if NPCItemUser.flat_distance(origin, item.global_position) > radius:
			continue
		var physically_settled: bool = item.sleeping \
			or (item.linear_velocity.length() < CLEANING_STILL_LINEAR \
				and item.angular_velocity.length() < CLEANING_STILL_ANGULAR)
		if not physically_settled:
			continue
		var rec: Dictionary = _cleaning_idle_tracker[id]
		if StringName(rec.get("release_source", &"world")) == &"player":
			continue   ## deliberate player placement keeps its authored protection
		rec["stable_since_sec"] = _cleaning_clock_sec \
			- CLEANING_STABILIZE_SEC - grace_needed
		_cleaning_idle_tracker[id] = rec
		promoted += 1
	if promoted > 0:
		_scan_cleaning({})
	return promoted

## Aug 2026 — for NPC.get_cleaning_unavailable_reason()'s "NO_TRASH_
## RECEPTACLE" check.
func get_trash_blocked_by_no_receptacle_count() -> int:
	return _trash_blocked_by_no_receptacle

## Aug 2026 — full snapshot for NPCDebug.dump_cleaning_state(). Resolves
## every still-tracked-but-not-yet-idle item's live remaining time, so a
## single dump answers "why isn't X organizable yet" directly instead of
## needing to watch the periodic scan print over time.
func get_cleaning_debug_snapshot() -> Dictionary:
	var ordinary_grace: float = _effective_cleaning_grace_sec()
	var pending: Array = []
	for id in _cleaning_idle_tracker.keys():
		var item: Object = instance_from_id(id)
		if item == null or not is_instance_valid(item) or _organizable_items_cache.has(item):
			continue   ## already ready, or freed since — not "pending"
		var rec: Dictionary = _cleaning_idle_tracker[id]
		var stable_since: float = float(rec.get("stable_since_sec", -1.0))
		var source: StringName = StringName(rec.get("release_source", &"world"))
		var grace: float = CLEANING_PLAYER_GRACE_SEC if source == &"player" else ordinary_grace
		var elapsed: float = 0.0 if stable_since < 0.0 else _cleaning_clock_sec - stable_since
		var required: float = CLEANING_STABILIZE_SEC + grace
		var name: String = item.get_display_name() if item.has_method("get_display_name") else str(item.name)
		pending.append({
			"name": name,
			"state": "PHYSICALLY_MOVING" if stable_since < 0.0 \
				else ("RECENTLY_PLACED_BY_PLAYER" if source == &"player" else "STABILIZING"),
			"release_source": String(source),
			"elapsed_sec": elapsed,
			"required_sec": required,
			"remaining_sec": required if stable_since < 0.0 else maxf(0.0, required - elapsed),
		})
	return {
		"trash_count": _trash_items_cache.size(),
		"organizable_count": _organizable_items_cache.size(),
		"pending": pending,
		"trash_blocked_by_no_receptacle": _trash_blocked_by_no_receptacle,
		"idle_gate_sec": CLEANING_STABILIZE_SEC + ordinary_grace,
		"ordinary_grace_sec": ordinary_grace,
		"player_grace_sec": CLEANING_PLAYER_GRACE_SEC,
	}

func _has_trash_receptacle() -> bool:
	## Self-gating convention implemented by TrashCan and any future
	## receptacle with the same group/API contract.
	return not get_tree().get_nodes_in_group("trash_receptacle").is_empty()

## Aug 2026 fix — generic, scalable convention. An item is trash if EITHER:
##   (a) it's in the "trash" group — for items that are ALWAYS trash by
##       their existence (e.g. EmptyBagItem: one line in _ready(),
##       add_to_group("trash"), no method needed), or
##   (b) it has an is_trash() -> bool method that returns true — for
##       items that are CONDITIONALLY trash based on their own state
##       (a bottle/can/tank that empties but stays the same node).
## This is the ENTIRE trash-classification surface now — no future item
## type should ever require editing this function again. See
## docs/systems/npc/README.md for the full convention writeup aimed at
## other threads/agents wiring up new items.
func _is_trash_item(item: Node) -> bool:
	if item.is_in_group("trash"):
		return true
	if item.has_method("is_trash") and item.is_trash():
		return true
	return false

func _process(delta: float) -> void:
	## This is simulation time, intentionally affected by dev/sleep time scale.
	## The old wall-clock timestamp made a 90-second courtesy delay remain 90
	## real seconds at 5x, making stable floor items appear permanently ignored.
	_cleaning_clock_sec += maxf(0.0, delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	_rescan()

func get_open_jobs() -> Array:
	var out: Array = []
	for id: String in _jobs.keys().duplicate():
		var job: Dictionary = _jobs[id]
		## A freed Object held by a Variant is not null, and casting it raises
		## before a later validity check can run. Validate raw values first.
		var target: Node = _get_live_node(job.get("target"))
		if target == null:
			_jobs.erase(id)
			continue
		var claimant: Node = _get_live_node(job.get("claimed_by"))
		if claimant == null:
			job["claimed_by"] = null
			out.append(job)
	return out

func claim(job: Dictionary, npc: Node) -> bool:
	var id: String = String(job.get("id", ""))
	var live: Dictionary = _jobs.get(id, {})
	if live.is_empty() or _get_live_node(live.get("target")) == null \
			or _get_live_node(npc) == null:
		if not live.is_empty() and _get_live_node(live.get("target")) == null:
			_jobs.erase(id)
		return false
	var claimant: Node = _get_live_node(live.get("claimed_by"))
	if claimant != null:
		return false
	live["claimed_by"] = npc
	NPCDebug.log_job("claimed", live, npc)
	return true

func release(job: Dictionary, npc: Node) -> void:
	var live: Dictionary = _jobs.get(job.get("id", ""), {})
	if live.is_empty():
		return
	var claimant: Node = _get_live_node(live.get("claimed_by"))
	if claimant == null or claimant == npc:
		live["claimed_by"] = null

## True while the job's world condition still holds (activities poll this so
## a job finished by the player mid-walk cancels cleanly).
func still_valid(job: Dictionary) -> bool:
	var id: String = String(job.get("id", ""))
	if not _jobs.has(id):
		return false
	var live: Dictionary = _jobs[id]
	var target: Node = _get_live_node(job.get("target"))
	var live_target: Node = _get_live_node(live.get("target"))
	if target == null or live_target == null or target != live_target:
		_jobs.erase(id)
		return false
	if String(job.get("type", "")) == "HARVEST" \
			and (not target.has_method("is_ready") or not target.is_ready()):
		_jobs.erase(id)
		return false
	return true


func _get_live_node(raw: Variant) -> Node:
	## Do not move a typed assignment or `as Node` above this check.
	if not is_instance_valid(raw):
		return null
	var object: Object = raw
	if not object is Node:
		return null
	var node: Node = object as Node
	return null if node.is_queued_for_deletion() else node

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
	## Lifecycle invalidation closes the scan-cache window. The read-time raw
	## Variant guard remains necessary for same-frame queued deletions.
	var target_id: int = target.get_instance_id()
	var exiting_callback: Callable = _on_job_target_finished.bind(id, target_id)
	if not target.tree_exiting.is_connected(exiting_callback):
		target.tree_exiting.connect(exiting_callback, CONNECT_ONE_SHOT)
	for signal_name: StringName in [&"harvested", &"died"]:
		if not target.has_signal(signal_name):
			continue
		var finish_callback: Callable = _on_job_target_finished.bind(id, target_id)
		if not target.is_connected(signal_name, finish_callback):
			target.connect(signal_name, finish_callback, CONNECT_ONE_SHOT)
	NPCDebug.log_job("posted", _jobs[id])


func _on_job_target_finished(id: String, target_id: int) -> void:
	var live: Dictionary = _jobs.get(id, {})
	if live.is_empty():
		return
	var target: Node = _get_live_node(live.get("target"))
	if target == null or target.get_instance_id() == target_id:
		_jobs.erase(id)

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
		if not is_instance_valid(item) or not item is RigidBody3D \
				or not ("is_held" in item):
			continue
		## Frozen bodies (stored/shelved/placed) are never cleaning candidates —
		## defensive catch on top of the group/held/shelved exclusions (Aug 2026).
		if item.is_held or item.is_in_group("shelved") \
				or (item is RigidBody3D and (item as RigidBody3D).freeze):
			continue
		## Aug 2026 — a pot resting on a stove sits perfectly still
		## (is_held is false the whole time it's hosted, same convention
		## as a shelved item) and would otherwise pass the idle gate and
		## look exactly like any other settled, organizable item. See
		## NPCItemUser.is_on_stove()'s own comment — this now covers the
		## whole time it's placed, not just while actively cooking.
		if NPCItemUser.is_on_stove(item):
			continue
		var item_y: float = (item as Node3D).global_position.y
		if item_y < CLEANING_SANITY_Y_MIN or item_y > CLEANING_SANITY_Y_MAX:
			## Glitched/out-of-bounds — never enters the cleaning system
			## at all, for any NPC. See CLEANING_SANITY_Y_MIN's comment.
			if NPCDebug.enabled:
				print("[JobBoard] Cleaning scan: excluding %s — Y=%.1f is outside sane bunker bounds (glitched/out-of-bounds)" \
					% [(item.get_display_name() if item.has_method("get_display_name") else str(item.name)), item_y])
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
			if trash_receptacle_exists:
				new_trash.append(item)
			else:
				trash_blocked_this_scan += 1
			continue   ## trash never also counts as organizable

		var body: RigidBody3D = item as RigidBody3D
		var pos: Vector3 = body.global_position
		var release_source: StringName = StringName(item.get("cleanup_release_source")) \
			if "cleanup_release_source" in item else &"world"
		var release_serial: int = int(item.get("cleanup_release_serial")) \
			if "cleanup_release_serial" in item else 0
		var physically_still: bool = body.sleeping \
			or (body.linear_velocity.length() < CLEANING_STILL_LINEAR \
				and body.angular_velocity.length() < CLEANING_STILL_ANGULAR)
		if not _cleaning_idle_tracker.has(id):
			_cleaning_idle_tracker[id] = {
				"sample_pos": pos,
				"stable_since_sec": _cleaning_clock_sec if physically_still else -1.0,
				"release_source": release_source,
				"release_serial": release_serial,
			}
			continue
		var rec: Dictionary = _cleaning_idle_tracker[id]
		var fresh_release: bool = int(rec.get("release_serial", -1)) != release_serial
		var moved: bool = pos.distance_to(rec.get("sample_pos", pos)) > CLEANING_MOVE_TOLERANCE
		if fresh_release:
			rec["release_source"] = release_source
			rec["release_serial"] = release_serial
		if fresh_release or moved or not physically_still:
			rec["stable_since_sec"] = -1.0
		elif float(rec.get("stable_since_sec", -1.0)) < 0.0:
			rec["stable_since_sec"] = _cleaning_clock_sec
		rec["sample_pos"] = pos
		_cleaning_idle_tracker[id] = rec
		var stable_since: float = float(rec.get("stable_since_sec", -1.0))
		if stable_since < 0.0:
			continue
		var grace: float = CLEANING_PLAYER_GRACE_SEC \
			if StringName(rec.get("release_source", &"world")) == &"player" \
			else _effective_cleaning_grace_sec()
		if (_cleaning_clock_sec - stable_since) >= CLEANING_STABILIZE_SEC + grace:
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
