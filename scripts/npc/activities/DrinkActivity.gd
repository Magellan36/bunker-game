extends NPCActivity
class_name DrinkActivity
## DrinkActivity.gd — find water and drink until sated.
##
## Source tiers: snatch from a disliked person holding a bottle → nearest of
## (filled dispenser, loose bottle) → shelved bottle → open a Water Case
## (NPCCaseFetch). Dispenser sips deduct real water; bottle sips use the
## bottle's own take_drink().
##
## Sep 2026: smooth urgency curve; a bottle is sipped repeatedly while held
## (the old flow grabbed, sipped once, dropped, and re-grabbed the same
## bottle over and over); a bottle with water left is put away afterwards
## (hand-off to PutAwayHeldItemActivity) instead of being left on the floor.

const DRINK_ML: float = 375.0        ## == WaterBottle.STANDARD_DRINK_ML
const HYDRATION: float = 21.5        ## == WaterBottle.STANDARD_HYDRATION
const CONSUME_TIME: float = 2.0
const USE_RANGE: float = 1.4
const DRINK_START: float = 68.0
const DRINK_FULL: float = 10.0

var _mode: String = ""        ## "dispenser" | "bottle" | "shelf_bottle" | "case"
var _target: Node = null
var _shelf_pick: Dictionary = {}
var _drinking: float = 0.0
var _pending_snatch: Node = null
var _handoff: NPCActivity = null
var _case_fetch: NPCCaseFetch = null
var _finished: bool = false
var _retries: int = 0
const MAX_RETRIES: int = 3

func label() -> String:
	return "Drinking" if _drinking > 0.0 else "Getting water"

func is_need() -> bool:
	return true

func accepts_held_item(_npc: NPC, item: Node) -> bool:
	return NPCItemUser.is_drinkable_bottle(item)

func score(npc: NPC) -> float:
	var u: float = NPC.urgency(npc.thirst, DRINK_START, DRINK_FULL)
	if u <= 0.0:
		return 0.0
	if not (NPCItemUser.hands_full(npc) and NPCItemUser.is_drinkable_bottle(npc.held_item)) \
			and _pick_target(npc).is_empty() \
			and not npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_drinkable_bottle")):
		return 0.0
	return 104.0 * u   ## thirst edges out equal hunger

func _pick_target(npc: NPC) -> Dictionary:
	var best_d: float = INF
	var out: Dictionary = {}
	for d: Node in npc.get_tree().get_nodes_in_group("water_dispenser"):
		if not is_instance_valid(d) or d.current_fill_mL < DRINK_ML:
			continue
		var dist: float = NPCItemUser.flat_distance((d as Node3D).global_position, npc.global_position)
		if dist < best_d:
			best_d = dist
			out = {"mode": "dispenser", "node": d}
	var bottle: RigidBody3D = NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_drinkable_bottle"))
	if bottle != null and NPCItemUser.flat_distance(bottle.global_position, npc.global_position) < best_d:
		out = {"mode": "bottle", "node": bottle}
	if not out.is_empty():
		return out
	var shelf: Dictionary = NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_drinkable_bottle"))
	if not shelf.is_empty():
		return {"mode": "shelf_bottle", "node": shelf.get("shelf"), "shelf_pick": shelf}
	if not NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_stocked_water_case")).is_empty():
		return {"mode": "case"}
	return {}

func enter(npc: NPC) -> void:
	_drinking = 0.0
	_finished = false
	if NPCItemUser.hands_full(npc) and NPCItemUser.is_drinkable_bottle(npc.held_item):
		_mode = "bottle"
		_target = npc.held_item
		return
	_acquire(npc)

func _acquire(npc: NPC) -> void:
	_mode = ""
	_target = null
	_shelf_pick = {}
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
	if _pending_snatch != null:
		return
	var pick: Dictionary = _pick_target(npc)
	_mode = pick.get("mode", "")
	_target = pick.get("node", null)
	_shelf_pick = pick.get("shelf_pick", {})
	match _mode:
		"bottle":
			if not NPCItemUser.claim_item(_target, npc):
				_target = null
		"shelf_bottle":
			if not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
				_target = null
		"case":
			_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_water_case"), Callable(NPCItemUser, "is_drinkable_bottle"))
			return
	if _target != null:
		npc.set_nav_target((_target as Node3D).global_position)
	else:
		_finished = true

func tick(npc: NPC, delta: float) -> void:
	if _pending_snatch != null:
		_handoff = SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_drinkable_bottle"), false)
		_pending_snatch = null
		return
	if _case_fetch != null:
		if _case_fetch.is_done():
			if not _case_fetch.failed() and _case_fetch.get_ejected_item() != null:
				_target = _case_fetch.get_ejected_item()
				_mode = "bottle"
			else:
				_finished = true
			_case_fetch = null
			return
		_case_fetch.tick(npc, delta)
		return
	if _target == null or not is_instance_valid(_target):
		## Lost it (someone else took/tidied it) — look for another source
		## instead of wandering off still thirsty.
		if _retries < MAX_RETRIES and npc.thirst < NPC.NEED_SATED and not NPCItemUser.hands_full(npc):
			_retries += 1
			_acquire(npc)
		else:
			_finished = true
		return
	match _mode:
		"bottle":
			_tick_bottle(npc, delta)
		"shelf_bottle":
			_tick_shelf_bottle(npc, delta)
		_:
			_tick_dispenser(npc, delta)

func _tick_dispenser(npc: NPC, delta: float) -> void:
	if _drinking > 0.0:
		npc.halt_movement(delta)
		_drinking -= delta
		if _drinking <= 0.0:
			var ml: float = minf(DRINK_ML, _target.current_fill_mL)
			if ml > 0.0:
				_target.current_fill_mL -= ml
				if _target.has_method("_update_fill_visual"):
					_target._update_fill_visual()
				npc.thirst = minf(npc.thirst_cap, npc.thirst + HYDRATION * (ml / DRINK_ML))
				npc.morale_sys.note_drink(float(_target.get("stored_water_quality") if _target.get("stored_water_quality") != null else 100.0))
			if npc.thirst >= NPC.NEED_SATED or _target.current_fill_mL < DRINK_ML:
				_after_drinking(npc)
			else:
				_drinking = CONSUME_TIME   ## another cup
		return
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, (_target as Node3D).global_position, USE_RANGE):
		npc.lock_movement()
		_drinking = CONSUME_TIME

func _tick_bottle(npc: NPC, delta: float) -> void:
	if npc.held_item == _target:
		if _drinking <= 0.0:
			npc.lock_movement()
			_drinking = CONSUME_TIME
			return
		npc.halt_movement(delta)
		_drinking -= delta
		if _drinking <= 0.0:
			var q: float = float(_target.stored_water_quality) if "stored_water_quality" in _target else 100.0
			npc.thirst = minf(npc.thirst_cap, npc.thirst + _target.take_drink())
			npc.morale_sys.note_drink(q)
			if npc.thirst >= NPC.NEED_SATED or not NPCItemUser.is_drinkable_bottle(_target):
				_after_drinking(npc)
			else:
				_drinking = CONSUME_TIME   ## another sip
		return
	if (("is_held" in _target) and _target.is_held) or _target.is_in_group("shelved"):
		_target = null   ## someone else got it
		return
	NPCItemUser.track_fetch_target(npc, _target)
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, (_target as Node3D).global_position, NPCItemUser.PICKUP_RANGE):
		if not NPCItemUser.grab_loose(npc, _target):
			_target = null

func _tick_shelf_bottle(npc: NPC, delta: float) -> void:
	var shelf: Node3D = _shelf_pick.get("shelf")
	if shelf == null or not is_instance_valid(shelf):
		_target = null
		return
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
		if NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
			_mode = "bottle"
			_target = npc.held_item
		else:
			_target = null   ## slot emptied under us

## Sated or the source ran dry. Still thirsty → look for more; otherwise
## done — and a bottle with water left gets put away, not dropped.
func _after_drinking(npc: NPC) -> void:
	_drinking = 0.0
	if npc.thirst < NPC.NEED_SATED and (not NPCItemUser.hands_full(npc) or not NPCItemUser.is_drinkable_bottle(npc.held_item)):
		if NPCItemUser.hands_full(npc):
			NPCItemUser.drop_held(npc)   ## an empty bottle — set it down (Cleaning tidies it)
		_acquire(npc)
		return
	if NPCItemUser.hands_full(npc):
		if NPCItemUser.is_drinkable_bottle(npc.held_item):
			_handoff = PutAwayHeldItemActivity.new()
		else:
			NPCItemUser.drop_held(npc)
	_finished = true

func done(_npc: NPC) -> bool:
	return _finished and _handoff == null and _case_fetch == null and _pending_snatch == null

func interruptible() -> bool:
	return _drinking <= 0.0 and _case_fetch == null

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func exit(npc: NPC) -> void:
	if _case_fetch != null:
		_case_fetch.cleanup(npc)
		_case_fetch = null
	_target = null
	_shelf_pick = {}
	_drinking = 0.0
