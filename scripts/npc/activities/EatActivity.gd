extends NPCActivity
class_name EatActivity
## EatActivity.gd — find food and eat it.
##
## Source tiers, in order: snatch from a disliked person holding food (a
## relationship-gated roll, see NPC.find_snatch_target) → nearest loose
## food → nearest shelved food → open a Can Case (NPCCaseFetch) as a last
## resort. Multi-bite cans are eaten bite by bite; single servings (dishes,
## produce) in one go. Keeps going for another item while still hungry.
##
## Sep 2026: smooth urgency curve instead of a hard 55 threshold (see
## score()); held food is accepted directly (a Give or a snatch hands the
## item over already in hand); reservations are released by the brain.

const CONSUME_TIME: float = 2.0
const USE_RANGE: float = 1.2
## A little peckish (≈50) only wins when nothing else is going on; hungry
## (≈30) beats most chores; starving beats everything. Starts at 58 so a
## typical item (~45 hunger) is rarely wasted by eating when nearly full.
const EAT_START: float = 58.0
const EAT_FULL: float = 8.0
const EAT_AGAIN_BELOW: float = 60.0

var _loose: RigidBody3D = null
var _shelf_pick: Dictionary = {}
var _eating: float = 0.0
var _pending_snatch: Node = null
var _handoff: NPCActivity = null
var _case_fetch: NPCCaseFetch = null
var _retries: int = 0

func label() -> String:
	return "Eating" if _eating > 0.0 else "Getting food"

func is_need() -> bool:
	return true

## Already holding something edible (a Give, a snatch, a can mid-meal).
func accepts_held_item(_npc: NPC, item: Node) -> bool:
	return NPCItemUser.is_edible(item)

func score(npc: NPC) -> float:
	var u: float = NPC.urgency(npc.hunger, EAT_START, EAT_FULL)
	if u <= 0.0 or not _any_food(npc):
		return 0.0
	return 100.0 * u

func _any_food(npc: NPC) -> bool:
	if NPCItemUser.hands_full(npc) and NPCItemUser.is_edible(npc.held_item):
		return true
	return _find(npc) != null or not _find_shelf(npc).is_empty() \
		or not NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_stocked_can_case")).is_empty() \
		or npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_edible"))

func _find(npc: NPC) -> RigidBody3D:
	return NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))

func _find_shelf(npc: NPC) -> Dictionary:
	return NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))

func enter(npc: NPC) -> void:
	_eating = 0.0
	if NPCItemUser.hands_full(npc):
		return   ## eat what's in hand first (tick picks it up)
	_acquire(npc)

## Picks the next food source. Leaves everything empty if there is none —
## done() then ends the activity.
func _acquire(npc: NPC) -> void:
	_loose = null
	_shelf_pick = {}
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_edible"))
	if _pending_snatch != null:
		return
	_loose = _find(npc)
	if _loose != null and not NPCItemUser.claim_item(_loose, npc):
		_loose = null
	if _loose == null:
		_shelf_pick = _find_shelf(npc)
		if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
			_shelf_pick = {}
	if _loose != null:
		npc.set_nav_target(_loose.global_position)
	elif not _shelf_pick.is_empty():
		npc.set_nav_target((_shelf_pick.get("shelf") as Node3D).global_position)
	elif not NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_stocked_can_case")).is_empty():
		_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_can_case"), Callable(NPCItemUser, "is_edible"))

func tick(npc: NPC, delta: float) -> void:
	if _pending_snatch != null:
		_handoff = SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_edible"), true)
		_pending_snatch = null
		return
	if _case_fetch != null:
		if _case_fetch.is_done():
			if not _case_fetch.failed():
				_loose = _case_fetch.get_ejected_item()
			_case_fetch = null
			return
		_case_fetch.tick(npc, delta)
		return

	if _eating > 0.0:
		npc.halt_movement(delta)
		_eating -= delta
		if _eating <= 0.0:
			if NPCItemUser.eat_held_step(npc):
				if NPCItemUser.hands_full(npc):
					_handoff = PutAwayHeldItemActivity.new()   ## full — store the rest of the can
				elif npc.hunger < EAT_AGAIN_BELOW:
					_acquire(npc)
			else:
				_eating = CONSUME_TIME   ## next bite of the same can
		return

	if NPCItemUser.hands_full(npc):
		npc.lock_movement()
		_eating = CONSUME_TIME
		return

	if _loose != null:
		if not is_instance_valid(_loose) or (("is_held" in _loose) and _loose.is_held) or _loose.is_in_group("shelved"):
			_loose = null   ## someone else got it — try another source
			if _retries < 3:
				_retries += 1
				_acquire(npc)
			return
		NPCItemUser.track_fetch_target(npc, _loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _loose.global_position, USE_RANGE):
			NPCItemUser.grab_loose(npc, _loose)
			_loose = null
		return

	if not _shelf_pick.is_empty():
		var shelf: Node3D = _shelf_pick.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_shelf_pick = {}
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1)))
			_shelf_pick = {}

func done(npc: NPC) -> bool:
	return _eating <= 0.0 and not NPCItemUser.hands_full(npc) \
		and _loose == null and _shelf_pick.is_empty() and _pending_snatch == null \
		and _case_fetch == null and _handoff == null

func interruptible() -> bool:
	return _eating <= 0.0 and _case_fetch == null

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func exit(npc: NPC) -> void:
	if _case_fetch != null:
		_case_fetch.cleanup(npc)
		_case_fetch = null
	## Interrupted mid-meal: keep food in hand only if the next activity
	## wants it (the brain's hands policy sets it down otherwise).
	_loose = null
	_shelf_pick = {}
	_eating = 0.0
