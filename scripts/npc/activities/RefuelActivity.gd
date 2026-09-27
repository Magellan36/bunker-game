extends NPCSessionActivity
class_name RefuelActivity
## RefuelActivity.gd — fetch ONE fuel can, then visit every generator below
## 100% in turn, pouring until each is full (or the can runs dry). Never
## revisits a generator already topped off this session.
##
## Scoring (Sep 2026): starts when any generator drops under
## NPC.REFUEL_URGENT_BELOW and grows as the lowest one approaches empty —
## a generator about to cut out outranks most chores and a mild appetite.
##
## Sep 2026 fixes: the fetch phase adopted ANY held item as "the can" (a
## food can, a basket...) and then called refuel_tick() on it; pouring now
## respects the resident's work speed (age, injuries, skill); the can is put
## away (not dropped) when the session ends with fuel left in it.

const WORK_RANGE: float = 2.0

var _can: RigidBody3D = null
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _current_gen: Node = null
var _refueled_ids: Dictionary = {}
var _phase: String = "fetch"         ## fetch -> travel -> refuel
var _finished: bool = false
var _handoff: NPCActivity = null

func label() -> String:
	match _phase:
		"fetch": return "Fetching a fuel can"
		"travel": return "Heading to the generator"
		_: return "Refueling"

func score(npc: NPC) -> float:
	if not NPCJobQueries.has_refuel_target_available(npc):
		return 0.0
	var lowest: float = NPCJobQueries.lowest_generator_fuel(npc)
	var u: float = NPC.urgency(lowest, NPC.REFUEL_URGENT_BELOW, 3.0)
	return npc.work_score("REFUEL", 1.0 + 2.0 * u)

func accepts_held_item(_npc: NPC, item: Node) -> bool:
	return NPCItemUser.is_spare_fuel_can(item)

func enter(npc: NPC) -> void:
	_refueled_ids = {}
	_finished = false
	if NPCItemUser.hands_full(npc) and NPCItemUser.is_spare_fuel_can(npc.held_item):
		_can = npc.held_item
		_pick_next_generator(npc)
		return
	_phase = "fetch"
	var pick: Dictionary = NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_spare_fuel_can"))
	_fetch_loose = pick.get("loose")
	_fetch_shelf = pick.get("shelf", {})
	var tgt: Node3D = _fetch_loose if _fetch_loose != null \
		else (_fetch_shelf.get("shelf") as Node3D if not _fetch_shelf.is_empty() else null)
	var claim_target: Node = _fetch_loose if _fetch_loose != null else _fetch_shelf.get("item")
	if tgt == null or not NPCItemUser.claim_item(claim_target, npc):
		_finished = true
		return
	npc.set_nav_target(tgt.global_position)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if NPCItemUser.hands_full(npc):
		if NPCItemUser.is_spare_fuel_can(npc.held_item):
			_can = npc.held_item
			_pick_next_generator(npc)
		else:
			NPCItemUser.drop_held(npc)   ## not a fuel can — never pour from the wrong thing
		return
	if _fetch_loose != null:
		if not is_instance_valid(_fetch_loose) or (("is_held" in _fetch_loose) and _fetch_loose.is_held):
			_finished = true
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _fetch_loose.global_position, NPCItemUser.PICKUP_RANGE):
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_finished = true
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_finished = true
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_finished = true
		return
	_finished = true

func _pick_next_generator(npc: NPC) -> void:
	_current_gen = NPCJobQueries.find_next_refuel_target(npc, _refueled_ids)
	if _current_gen == null:
		_end_session(npc)
		return
	npc.set_nav_target(approach_point(npc, _current_gen))
	_phase = "travel"

func tick(npc: NPC, delta: float) -> void:
	if _finished:
		return
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			if _current_gen == null or not is_instance_valid(_current_gen):
				_pick_next_generator(npc)
				return
			if npc.held_item != _can:
				_finished = true   ## lost the can (taken away, knocked out of hand)
				return
			npc.nav_steer(delta)
			if NPCItemUser.in_reach(npc, (_current_gen as Node3D).global_position, WORK_RANGE):
				npc.lock_movement()
				npc.face_toward((_current_gen as Node3D).global_position, 1.0)
				_phase = "refuel"
				npc.show_work_banner()
		"refuel":
			npc.halt_movement(delta)
			if _can == null or not is_instance_valid(_can) or npc.held_item != _can \
					or _current_gen == null or not is_instance_valid(_current_gen):
				npc.hide_work_banner()
				_finished = true
				return
			var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
			if pm == null:
				_finished = true
				return
			var gid: String = str(_current_gen.get_instance_id())
			npc.update_work_banner("REFUELING", pm.get_generator_fuel(gid) / 100.0)
			_can.refuel_tick(delta * npc.get_work_speed_mult("electrical"))
			var can_empty: bool = float(_can._fuel_remaining) <= 0.0
			if pm.get_generator_fuel(gid) >= 100.0 or can_empty:
				npc.hide_work_banner()
				_refueled_ids[_current_gen.get_instance_id()] = true
				NotificationManager.notify(UIKit.Domain.POWER, NotificationManager.Severity.INFO,
					"%s refueled the generator" % npc.npc_name)
				npc.log_action("Refueled a generator")
				npc.on_work_done("electrical")
				if can_empty:
					NPCItemUser.drop_held(npc)   ## an empty can is trash — Cleaning takes it out
					_finished = true
				else:
					_pick_next_generator(npc)

## Every generator is full. A can with fuel left goes back into storage.
func _end_session(npc: NPC) -> void:
	if NPCItemUser.hands_full(npc) and npc.held_item == _can:
		_handoff = PutAwayHeldItemActivity.new()
	_finished = true

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func done(_npc: NPC) -> bool:
	return _finished and _handoff == null

func debug_info() -> Dictionary:
	return {
		"activity": "refuel",
		"phase": _phase,
		"can_held": _can != null and is_instance_valid(_can),
		"current_generator": (_current_gen.name if _current_gen != null and is_instance_valid(_current_gen) else ""),
		"refueled_this_session": _refueled_ids.size(),
	}

func exit(npc: NPC) -> void:
	var detail: String = "phase=%s can_held=%s" % [_phase, _can != null and is_instance_valid(_can)]
	on_session_exit(npc, "refuel", _finished, detail)
