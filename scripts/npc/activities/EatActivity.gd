extends NPCActivity
class_name EatActivity
## Hunger-driven. Priority: loose edible → shelved edible (via
## Shelving.npc_retrieve) → loose Can Case → shelved Can Case (Aug
## 2026 — the last two tiers via NPCCaseFetch: take the case out if
## shelved, eject one can, reshelve, then eat it like any other loose
## find — shared with DrinkActivity's WaterCase handling).
const CONSUME_TIME: float = 2.0
const USE_RANGE:    float = 1.2

var _loose: RigidBody3D = null
var _shelf_pick: Dictionary = {}
var _eating: float = 0.0
var _pending_snatch: Node = null   ## Part 30 — set in enter()/_reacquire_or_finish(), consumed on first tick()
var _handoff: NPCActivity = null
var _case_fetch: NPCCaseFetch = null   ## Aug 2026 — last-resort tier once loose+shelf both come up empty

func label() -> String:
	return "Eating" if _eating > 0.0 else "Getting food"

func score(npc: NPC) -> float:
	if npc.hunger >= 55.0:
		return 0.0
	## Aug 2026 — gate now covers all four fetch tiers (loose -> shelved food
	## already covered by _find()/_find_shelf(); loose/shelved CAN CASE now
	## covered too) plus snatch-eligibility, so Eating correctly stays
	## available when only a stocked Can Case exists anywhere.
	if _find(npc) == null and _find_shelf(npc).is_empty() \
			and NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_stocked_can_case")).is_empty() \
			and not npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_edible")):
		return 0.0
	return (100.0 - npc.hunger) * 1.15 * npc.get_work_ethic_passive_mult()

func _find(npc: NPC) -> RigidBody3D:
	return NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))

func _find_shelf(npc: NPC) -> Dictionary:
	return NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))

func enter(npc: NPC) -> void:
	_eating = 0.0
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_edible"))
	if _pending_snatch != null:
		return   ## handled on first tick() below, via take_handoff()
	_loose = _find(npc)
	if _loose != null and not NPCItemUser.claim_item(_loose, npc):
		_loose = null   ## lost the race between scoring and entering
	_shelf_pick = {}
	if _loose == null:
		_shelf_pick = _find_shelf(npc)
		if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
			_shelf_pick = {}
	if _loose == null and _shelf_pick.is_empty():
		## Aug 2026 — last-resort case tier. score() already confirmed one
		## exists somewhere if we got this far with nothing else found.
		_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_can_case"), Callable(NPCItemUser, "is_edible"))
		return
	var tgt: Node3D = _loose if _loose != null \
		else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
	if tgt != null:
		npc.set_nav_target(tgt.global_position)

func tick(npc: NPC, delta: float) -> void:
	if _pending_snatch != null:
		_handoff = SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_edible"), true)
		_pending_snatch = null
		return
	if _case_fetch != null:
		if _case_fetch.is_done():
			if not _case_fetch.failed():
				_loose = _case_fetch.get_ejected_item()   ## hand off to the normal loose branch below, next tick
			_case_fetch = null
			return
		_case_fetch.tick(npc, delta)
		return
	if _eating > 0.0:
		npc.halt_movement(delta)
		_eating -= delta
		if _eating <= 0.0:
			if NPCItemUser.eat_held_step(npc):
				_reacquire_or_finish(npc)   ## Part 17 — see DrinkActivity for the same fix
			else:
				_eating = CONSUME_TIME   ## next bite of the same can
		return

	if npc.held_item != null:
		npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see DrinkActivity 3b note)
		_eating = CONSUME_TIME
		return

	if _loose != null and is_instance_valid(_loose):
		if "is_held" in _loose and _loose.is_held:
			NPCItemUser.release_item(_loose)
			_loose = null
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= USE_RANGE:
			if NPCItemUser.grab_loose(npc, _loose):
				_loose = null
			else:
				NPCItemUser.release_item(_loose)
				_loose = null
		return
	_loose = null

	if not _shelf_pick.is_empty():
		var shelf: Node3D = _shelf_pick.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_shelf_pick = {}
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
			if NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
				_shelf_pick = {}
			else:
				_shelf_pick = {}   ## slot emptied under us — rescore
		return

func done(npc: NPC) -> bool:
	return _eating <= 0.0 and npc.held_item == null \
		and _loose == null and _shelf_pick.is_empty() and _pending_snatch == null \
		and _case_fetch == null

## Part 17 — mirrors DrinkActivity's. Finishing one item (a full can, or
## a single-bite item) no longer ends the activity outright if hunger is
## still low — it looks for another item and continues within the same
## run, only truly finishing once satisfied or nothing is left to eat.
func _reacquire_or_finish(npc: NPC) -> void:
	_loose = null
	_shelf_pick = {}
	_pending_snatch = null
	if npc.hunger >= 55.0:
		return
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_edible"))
	if _pending_snatch != null:
		return   ## picked up by tick() next frame
	_loose = _find(npc)
	if _loose != null and not NPCItemUser.claim_item(_loose, npc):
		_loose = null
	if _loose == null:
		_shelf_pick = _find_shelf(npc)
		if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
			_shelf_pick = {}
	if _loose == null and _shelf_pick.is_empty():
		_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_can_case"), Callable(NPCItemUser, "is_edible"))
		return
	var tgt: Node3D = _loose if _loose != null \
		else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
	if tgt != null:
		npc.set_nav_target(tgt.global_position)

func interruptible() -> bool:
	## Aug 2026 fix — a stocked-case fetch in progress (holding the case,
	## mid pre-eject/eject/post-eject/reshelve) previously left this true
	## the whole time (only _eating gates it), while score() simultaneously
	## drops to 0 the moment the case is held (find_loose_item excludes
	## held items, so nothing looks "available"). NPCBrain short-circuits
	## its own score comparison on interruptible() == false, so score()
	## never even gets consulted here — this is the actual fix, not a
	## defensive extra. Without it: brain interrupts mid-fetch -> exit()
	## drops the case -> still hungry -> re-enters -> picks the same
	## dropped case back up -> interrupted again — an endless pickup/drop
	## loop that never reaches eject. Same failure shape NPCDebug's own
	## log_suspicious_interrupt() was written to catch elsewhere.
	return _eating <= 0.0 and _case_fetch == null

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func exit(npc: NPC) -> void:
	if _case_fetch != null:
		_case_fetch.cleanup(npc)
		_case_fetch = null
	if _loose != null:
		NPCItemUser.release_item(_loose)
	if not _shelf_pick.is_empty():
		NPCItemUser.release_item(_shelf_pick.get("item"))
	if npc.held_item != null:
		NPCItemUser.release_item(npc.held_item)
		NPCItemUser.drop_held(npc)
	_loose = null
	_shelf_pick = {}
	_eating = 0.0