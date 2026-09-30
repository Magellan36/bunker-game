extends NPCActivity
## TreatActivity.gd (Sep 2026, Brannon) — residents patch themselves up,
## and look after friends, with the bunker's basic medical supplies:
## Bandage (bleeding), Splint (fractures/breaks), Antibiotics (open wounds).
## Never Trauma Kits — those are rare and left to the player.
##
## Picks the most urgent patient it can help (itself first, then anyone it
## likes enough, FRIEND_MIN), fetches a matching item (loose or on a shelf),
## walks over and treats them (NPC.receive_treatment with a resident giver:
## a thank-you, a memory, a relationship boost, "patched me up" feelings).
## Bleeding is urgent; a splint or antibiotics can wait for a quiet moment.
## Leftover charges go back into storage (PutAwayHeldItemActivity).

const TREAT_TIME: float = 3.0
const USE_RANGE: float = 1.3
const FRIEND_MIN: float = 30.0       ## how much they must like someone to look after them
const FRIEND_RANGE: float = 25.0
const GIVE_UP_SECONDS: float = 45.0
## Urgency per treatment kind (self, other).
const URGENCY: Dictionary = {"bleeding": [90.0, 75.0], "splint": [45.0, 35.0], "antibiotics": [40.0, 30.0]}

static var _patients: Dictionary = {}   ## patient instance id -> helper instance id

enum Phase { FETCH, GO, TREAT, DONE }

var _phase: Phase = Phase.DONE
var _patient: NPC = null
var _kind: String = ""
var _loose: RigidBody3D = null
var _shelf_pick: Dictionary = {}
var _working: float = 0.0
var _timer: float = 0.0
var _handoff: NPCActivity = null

func label() -> String:
	if _phase == Phase.FETCH:
		return "Getting %s" % {"bleeding": "a bandage", "splint": "a splint", "antibiotics": "antibiotics"}.get(_kind, "supplies")
	if _patient == null or _patient == _npc_self:
		return "Patching themselves up"
	return "Looking after %s" % _patient.npc_name

var _npc_self: NPC = null

func is_need() -> bool:
	return true

## Basic medical supplies only (Trauma Kits have no NPC_TREATMENT).
static func is_basic_medical(item: Node) -> bool:
	if item == null or not is_instance_valid(item) or not ("NPC_TREATMENT" in item):
		return false
	return not item.has_method("has_charges_left") or item.has_charges_left()

static func _filter(kind: String) -> Callable:
	return func(it: Node) -> bool: return is_basic_medical(it) and String(it.NPC_TREATMENT) == kind

func score(npc: NPC) -> float:
	var pick: Dictionary = _choose(npc)
	return float(pick.get("score", 0.0))

## {patient, kind, score} for the most urgent patient this resident can help.
func _choose(npc: NPC) -> Dictionary:
	var best: Dictionary = {}
	var candidates: Array[NPC] = [npc]
	for o: Node in npc.get_tree().get_nodes_in_group("npc"):
		var on: NPC = o as NPC
		if on == null or on == npc or on.is_dead() or on.crash.active():
			continue
		if npc.get_relationship(on.npc_id) < FRIEND_MIN or npc.global_position.distance_to(on.global_position) > FRIEND_RANGE:
			continue
		candidates.append(on)
	for p: NPC in candidates:
		var claimed_by: int = int(_patients.get(p.get_instance_id(), 0))
		if claimed_by != 0 and claimed_by != npc.get_instance_id():
			continue   ## someone's already on it
		var kind: String = p.most_urgent_treatment()
		if kind == "" or not _item_available(npc, kind):
			continue
		var u: float = float(URGENCY[kind][0 if p == npc else 1])
		if p.health < 40.0:
			u *= 1.2
		if best.is_empty() or u > float(best["score"]):
			best = {"patient": p, "kind": kind, "score": u}
	return best

func _item_available(npc: NPC, kind: String) -> bool:
	var f: Callable = _filter(kind)
	if npc.held_item != null and f.call(npc.held_item):
		return true
	return NPCItemUser.find_loose_item(npc, f) != null or not NPCItemUser.find_shelved_item(npc, f).is_empty()

func enter(npc: NPC) -> void:
	_npc_self = npc
	_timer = 0.0
	_working = 0.0
	_loose = null
	_shelf_pick = {}
	var pick: Dictionary = _choose(npc)
	if pick.is_empty():
		_phase = Phase.DONE
		return
	_patient = pick["patient"]
	_kind = String(pick["kind"])
	_patients[_patient.get_instance_id()] = npc.get_instance_id()
	var f: Callable = _filter(_kind)
	if npc.held_item != null and f.call(npc.held_item):
		_phase = Phase.GO
		return
	if npc.held_item != null:
		NPCItemUser.drop_held(npc)   ## hands free for the supplies
	_loose = NPCItemUser.find_loose_item(npc, f)
	if _loose != null and not NPCItemUser.claim_item(_loose, npc):
		_loose = null
	if _loose == null:
		_shelf_pick = NPCItemUser.find_shelved_item(npc, f)
		if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
			_shelf_pick = {}
	if _loose == null and _shelf_pick.is_empty():
		_phase = Phase.DONE
		return
	_phase = Phase.FETCH
	npc.set_nav_target(_loose.global_position if _loose != null else (_shelf_pick.get("shelf") as Node3D).global_position)
	NPCCombatDebug.trace(npc, "going to treat %s (%s)" % ["themselves" if _patient == npc else _patient.npc_name, _kind])

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	if _timer > GIVE_UP_SECONDS or _patient == null or not is_instance_valid(_patient) or _patient.is_dead():
		_finish(npc, "gave up / patient gone")
		return
	match _phase:
		Phase.FETCH:
			_tick_fetch(npc, delta)
		Phase.GO:
			if _patient == npc:
				_start_treating(npc)
				return
			npc.set_nav_target(_patient.global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _patient.global_position) <= USE_RANGE:
				_start_treating(npc)
		Phase.TREAT:
			npc.halt_movement(delta)
			if _patient != npc:
				npc.face_toward(_patient.global_position, minf(8.0 * delta, 0.99))
				if NPCItemUser.flat_distance(npc.global_position, _patient.global_position) > USE_RANGE + 0.8:
					_phase = Phase.GO   ## they wandered off mid-treatment — follow
					return
			_working -= delta
			if _working > 0.0:
				return
			var item: Node = npc.held_item
			if item == null or not is_instance_valid(item) or not _patient.receive_treatment(item, npc):
				_finish(npc)
				return
			## More of the same to treat (bleeding in two places) and charges left?
			item = npc.held_item
			if item != null and is_instance_valid(item) and is_basic_medical(item) and _patient.most_urgent_treatment() == _kind:
				_working = TREAT_TIME
				return
			_finish(npc)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if npc.held_item != null and _filter(_kind).call(npc.held_item):
		_phase = Phase.GO
		return
	if _loose != null:
		if not is_instance_valid(_loose) or (("is_held" in _loose) and _loose.is_held) or _loose.is_in_group("shelved"):
			_finish(npc, "someone else took the item")
			return
		NPCItemUser.track_fetch_target(npc, _loose)
		npc.nav_steer(delta)
		## Pick-up has its own (shorter) range; a near miss just keeps them walking.
		if NPCItemUser.in_reach(npc, _loose.global_position, NPCItemUser.PICKUP_RANGE) and NPCItemUser.grab_loose(npc, _loose):
			_loose = null
		return
	if not _shelf_pick.is_empty():
		var shelf: Node3D = _shelf_pick.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_finish(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
				_finish(npc)
			_shelf_pick = {}
		return
	_finish(npc)

func _start_treating(npc: NPC) -> void:
	_phase = Phase.TREAT
	_working = TREAT_TIME
	npc.lock_movement()
	npc.bark(NPCDialogue.bark_line("treat_self" if _patient == npc else "treat_other"))

## Leftover charges go back into storage; an empty bottle is set down.
func _finish(npc: NPC, why: String = "done") -> void:
	if _phase != Phase.DONE:
		NPCCombatDebug.trace(npc, "treatment ends: %s" % why)
	_phase = Phase.DONE
	var item: Node = npc.held_item
	if item != null and is_instance_valid(item) and "NPC_TREATMENT" in item:
		if is_basic_medical(item):
			_handoff = PutAwayHeldItemActivity.new()
		else:
			NPCItemUser.drop_held(npc)
	_release()

func _release() -> void:
	if _patient != null and is_instance_valid(_patient):
		_patients.erase(_patient.get_instance_id())
	_patient = null
	## Reservations on supplies they never picked up.
	if _loose != null and is_instance_valid(_loose):
		NPCItemUser.release_item(_loose)
	_loose = null
	if not _shelf_pick.is_empty():
		var it: Node = _shelf_pick.get("item")
		if it != null and is_instance_valid(it):
			NPCItemUser.release_item(it)
		_shelf_pick = {}

func done(_npc: NPC) -> bool:
	return _phase == Phase.DONE and _handoff == null

func interruptible() -> bool:
	return _phase != Phase.TREAT

func can_yield_to_need(_npc: NPC) -> bool:
	return _phase != Phase.TREAT

func exit(_npc: NPC) -> void:
	_release()

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func attention_target(_npc: NPC) -> Node3D:
	return null
