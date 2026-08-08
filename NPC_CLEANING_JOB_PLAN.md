# NPC Cleaning Job: Trash + Organizing + Stuck-Recovery Integration (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/world/furniture/Shelving.gd`,
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`.

## Architecture summary

Cleaning is **not** routed through `JobBoard`'s claim system the way
Harvest/Filter/Refuel are — those are single-location jobs (travel to one
fixed spot, work there); Cleaning is three-location (go to the item → go
to a *different* destination → drop it there). That shape already exists
and works: it's exactly `GiveToFriendActivity`'s fetch→travel→deliver
pattern. `CleaningActivity` mirrors that directly. `JobBoard` gains a new
role instead — periodic world-state discovery (what's trash, what's
idle long enough to be organized), cached and refreshed on its existing
scan cadence, which `NPC.gd` reads from. `get_work_ethic_job_mult()` is
applied directly to `CleaningActivity.score()` so it still counts as a
"job" for Lazy/Hard Worker purposes, without needing literal `JobBoard`
claim-dict integration.

Per your answers: trash carry logic is fully built now but self-gates —
`_has_trash_receptacle()` checks a `"trash_receptacle"` group that
nothing occupies yet, so trash jobs simply never get discovered until
something is added to that group later. Organizing requires an item to
sit idle (untouched, unclaimed) for 90 seconds before it's eligible —
tunable. The stuck-recovery trigger bypasses both checks entirely, by
design.

---

## Part A — `scripts/world/furniture/Shelving.gd`: NPC-side placement

**Anchor:** immediately after `npc_retrieve()`.

Insert:

```gdscript
## NPC-side placement (Aug 2026, Cleaning) — mirrors _try_place_item()
## exactly for the actual shelving math/animation (reuses
## _find_slot_for()/_place_item_in_slot() directly, unchanged), but
## sources the item from an NPC's held_item instead of the player's
## InteractionSystem and skips all the InteractionSystem-specific
## bookkeeping (inventory slot clearing, knocked_out signal) that simply
## doesn't apply to NPCs. Returns false if the shelf has no room — caller
## decides what to do next (CleaningActivity just sets the item back
## down rather than carrying it forever).
func npc_try_place_item(npc: Node, item: RigidBody3D) -> bool:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return false

	if "held_item" in npc and npc.held_item == item:
		npc.held_item = null

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	var stack_idx: int = slots[slot].size()
	slots[slot].append(item)
	_place_item_in_slot(item, slot, stack_idx)
	item_placed.emit(slot, item)
	return true
```

---

## Part B — `scripts/npc/JobBoard.gd`: trash/organizing discovery

### 1. Idle tracker + cached lists

**Anchor:** near the top-level vars.

Insert:

```gdscript
# ─── Cleaning discovery (Aug 2026) ──────────────────────────────────────────
## Idle-time gating for organizing — an item must sit untouched/unclaimed
## for this long before it's eligible, so NPCs don't sweep away something
## the player just set down to use in a moment. Trash items skip this
## entirely (they're unambiguously "done," not "in active use").
const CLEANING_IDLE_MIN_SEC: float = 90.0
const CLEANING_IDLE_MOVE_TOLERANCE: float = 0.3   ## meters — moved more than this since tracking began = someone touched it, restart the clock
var _cleaning_idle_tracker: Dictionary = {}   ## item instance_id -> {"pos": Vector3, "since_msec": int}
var _trash_items_cache: Array = []
var _organizable_items_cache: Array = []

func get_trash_items() -> Array:
	return _trash_items_cache

func get_organizable_items() -> Array:
	return _organizable_items_cache

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
```

### 2. The scan itself

**Anchor:** near the other `_scan_*` functions.

Insert:

```gdscript
## Same periodic cadence as Harvest/Filter/Refuel discovery — called from
## _rescan(). Rebuilds both cached lists fresh each pass; idle-tracking
## persists across passes (that's the whole point) but gets pruned for
## anything no longer present (picked up, freed, etc.).
func _scan_cleaning() -> void:
	var trash_receptacle_exists: bool = _has_trash_receptacle()
	var new_trash: Array = []
	var new_organizable: Array = []
	var seen_ids: Dictionary = {}

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
		if (now - int(rec["since_msec"])) >= int(CLEANING_IDLE_MIN_SEC * 1000.0):
			new_organizable.append(item)

	for id in _cleaning_idle_tracker.keys().duplicate():
		if not seen_ids.has(id):
			_cleaning_idle_tracker.erase(id)

	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
```

### 3. Wire into `_rescan()`

**Anchor:**

```gdscript
func _rescan() -> void:
	var seen: Dictionary = {}
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_refuel(seen)
```

Replace with:

```gdscript
func _rescan() -> void:
	var seen: Dictionary = {}
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_refuel(seen)
	_scan_cleaning(seen)
```

(`_scan_cleaning()` doesn't use the `seen`/`_jobs` dict at all — it
maintains its own separate cache — so accepting the parameter is just for
call-signature consistency; fine to ignore it inside the function, as
already written above.)

---

## Part C — `scripts/npc/NPC.gd`: target-finding + destination-finding

**Anchor:** anywhere near the Relaxing/GiveToFriend sections.

Insert:

```gdscript
# ─── Cleaning (Aug 2026) ─────────────────────────────────────────────────
const CLEANING_BASE_SCORE: float = 5.5

func has_cleaning_target_available() -> bool:
	if not JobBoard.get_trash_items().is_empty():
		return true
	return not JobBoard.get_organizable_items().is_empty()

## Nearest eligible item across BOTH lists — trash and organizable are
## mutually exclusive per JobBoard's own scan, so no double-counting risk.
func find_cleaning_target() -> Dictionary:
	var best_item: Node = null
	var best_d: float = INF
	var best_is_trash: bool = false
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = true
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = false
	if best_item == null:
		return {}
	return {"item": best_item, "is_trash": best_is_trash}

## Nearest member of the matching destination group. For trash, returning
## null here (no receptacle exists) is expected and handled gracefully by
## CleaningActivity — it just abandons and sets the item back down.
func find_cleaning_destination(is_trash: bool) -> Node:
	var group_name: String = "trash_receptacle" if is_trash else "shelving"
	var best: Node = null
	var best_d: float = INF
	for candidate: Node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best

## Used by the stuck-recovery hook to decide whether a forced grab should
## be logged/treated as "threw away" vs "put away" once delivered — the
## grab itself always bypasses eligibility per your answer, this is just
## classification, not a gate.
func is_trash_item(item: Node) -> bool:
	return JobBoard._is_trash_item(item) if JobBoard.has_method("_is_trash_item") else false
```

---

## Part D — `scripts/npc/NPCBrain.gd`: `CleaningActivity`

**Anchor:** add as a new top-level class near `GiveToFriendActivity`;
register `CleaningActivity.new()` in `setup()`'s `_candidates` list.

```gdscript
class CleaningActivity extends NPCActivity:
	## Cleaning (Aug 2026) — trash disposal + shelf organizing under one
	## job, mirroring GiveToFriendActivity's fetch→travel→deliver shape
	## (three locations: current position, item, destination — not
	## JobActivity's single-destination shape). Counts as a JOB for Work
	## Ethic purposes (get_work_ethic_job_mult(), not the passive
	## multiplier) per explicit instruction that Lazy NPCs should clean
	## less and Hard Workers more, same as every other job.
	##
	## forced_item/bypass_eligibility (non-null/true) is the stuck-recovery
	## path — grabs whatever caused the stuck NPC to stall, skipping the
	## normal trash/idle-time eligibility checks entirely, since it's
	## unstuck-worthy by definition regardless of what it technically is.
	var _item: RigidBody3D = null
	var _destination: Node = null
	var _is_trash: bool = false
	var _forced_item: RigidBody3D = null

	func _init(forced_item: RigidBody3D = null) -> void:
		_forced_item = forced_item

	func label() -> String:
		if _item == null:
			return "Cleaning"
		return "Cleaning (carrying)" if npc_holding() else "Cleaning (fetching)"

	## Small helper avoiding a stored npc reference just for label() —
	## approximated via _destination being set (only happens once actually
	## holding the item, see tick()). Fine if this feels imprecise; not
	## load-bearing anywhere else.
	func npc_holding() -> bool:
		return _destination != null

	func score(npc: NPC) -> float:
		if _forced_item != null:
			return 0.0   ## forced-only instance, never auto-selected
		if not npc.has_cleaning_target_available():
			return 0.0
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult()

	func interruptible() -> bool:
		return _item == null   ## once actually carrying something, commit to delivering it

	func enter(npc: NPC) -> void:
		if _forced_item != null:
			_item = _forced_item
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
		else:
			var result: Dictionary = npc.find_cleaning_target()
			if result.is_empty():
				return
			_item = result.get("item")
			_is_trash = result.get("is_trash", false)
		if _item == null or not is_instance_valid(_item):
			_item = null
			return
		if not NPCItemUser.claim_item(_item, npc):
			_item = null
			return
		npc.set_nav_target(_item.global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _item == null or not is_instance_valid(_item):
			_item = null
			return

		if npc.held_item == null:
			## Fetch phase
			if "is_held" in _item and _item.is_held:
				NPCItemUser.release_item(_item)
				_item = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _item.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _item):
					_destination = npc.find_cleaning_destination(_is_trash)
					if _destination == null:
						## No valid destination (expected for trash until a
						## receptacle exists; shouldn't normally happen for
						## organizing) — abandon cleanly, don't carry forever.
						NPCItemUser.drop_held(npc)
						_item = null
				else:
					NPCItemUser.release_item(_item)
					_item = null
			return

		## Travel phase — carrying the item to its destination
		if _destination == null or not is_instance_valid(_destination):
			_item = null
			return
		npc.set_nav_target((_destination as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			var item_name: String = _item.get_display_name() if _item.has_method("get_display_name") else "an item"
			if _is_trash:
				if _destination.has_method("npc_deposit_trash"):
					_destination.npc_deposit_trash(npc, _item)
				npc.log_action("Threw away %s" % item_name)
			else:
				if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
					npc.log_action("Put away %s" % item_name)
				else:
					NPCItemUser.drop_held(npc)   ## shelf filled up before arrival — just set it down
			_item = null

	func done(npc: NPC) -> bool:
		return _item == null

	func exit(npc: NPC) -> void:
		if _item != null:
			NPCItemUser.release_item(_item)
		_item = null
```

**Note on `npc_deposit_trash()`:** this method doesn't exist yet since
no receptacle scene exists — this call is written defensively
(`has_method()` guarded) so it's a safe no-op today and simply needs
that method added to whatever the eventual receptacle scene's script
turns out to be. The log line still fires either way, which is
harmless/cosmetic until a real receptacle exists (this whole branch is
unreachable today regardless, per Part B's self-gating).

---

## Part E — Stuck-recovery integration

**Anchor:** `NPC.gd`'s `_recover_from_stuck()`:

```gdscript
func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0
```

Replace with:

```gdscript
func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0
	if stuck_item != null and brain != null:
		## Always fair game when it caused a stuck NPC — bypasses the
		## normal trash/idle-time eligibility entirely, per design.
		brain.force_command(NPCBrain.CleaningActivity.new(stuck_item))

## Best-effort — mirrors _handle_physics_pushes()'s own collision
## detection. Not guaranteed to find the TRUE cause of the stall (could be
## a nav-mesh issue, another NPC, geometry) — if nothing found here,
## _recover_from_stuck() just falls back to its existing stop-and-clear
## behavior, unchanged from before.
func _find_stuck_obstruction() -> RigidBody3D:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is RigidBody3D and not (("is_held" in body) and body.is_held) and not body.is_in_group("shelved"):
			return body as RigidBody3D
	return null
```

---

## Documentation

`docs/systems/npc/README.md` — new "Cleaning" subsection: trash items
(EmptyBagItem, empty FoodCan, empty WaterBottle — fuel cans not
included yet, easy future addition once its public empty-check API is
confirmed), the 90s idle-time gate for organizing and why, the
self-gating trash-receptacle mechanism (works the instant something
occupies the `"trash_receptacle"` group, no code changes needed then),
Work Ethic's job-tier treatment, and the stuck-recovery integration
(always-eligible forced grab).

**Testing Checklist:**

```
69. Drop an empty FoodCan and an empty WaterBottle on the floor — confirm
    NPCs do NOT try to clean them up (no receptacle exists yet) but DO
    correctly identify them as trash internally (check via debug/log if
    you add temporary visibility) rather than treating them as
    organizable clutter.
70. Drop a Crate (or TestCrate) on the floor and leave it alone — confirm
    nothing happens for the first ~90 seconds, then an NPC picks it up
    and carries it to the nearest shelf with room.
71. Drop a Crate, then pick it up and move it again RIGHT as the 90s
    mark approaches — confirm the idle clock resets and it doesn't get
    organized until it's been genuinely untouched for the full duration
    again.
72. Confirm a Lazy NPC cleans up noticeably less often than a Hard Worker
    NPC under otherwise identical conditions.
73. Deliberately create a stuck scenario (cluster loose items in a
    doorway/chokepoint) — confirm the NPC picks up the obstruction and
    carries it away rather than just aborting and standing there.
74. Once a "trash_receptacle" group member exists in a later pass,
    confirm trash items start appearing in JobBoard.get_trash_items()
    and get carried there with zero code changes needed beyond adding
    npc_deposit_trash() to that scene's script.
```
