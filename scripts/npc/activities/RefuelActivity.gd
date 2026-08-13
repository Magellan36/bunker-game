extends NPCSessionActivity
class_name RefuelActivity
## Refuel (Aug 2026, sustained session) — fetch ONE fuel can, then visit
## every generator below 100% in turn, refueling each until full (or the
## can runs dry) before moving to the next. Ends when the can empties or
## no generator remains below 100%. Never revisits a generator already
## topped off THIS session (_refueled_ids) — the loop-prevention this
## was built for. Consolidation pass (Aug 2026): rebuilt on
## NPCSessionActivity — interruptible()/approach-point math/exit
## velocity-zero now come from the shared base instead of being
## hand-copied.
const WORK_RANGE: float = 1.6

var _can: RigidBody3D = null
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _current_gen: Node = null
var _refueled_ids: Dictionary = {}   ## generator instance_id -> true, this session only
var _phase: String = "fetch"         ## fetch -> travel -> refuel
var _finished: bool = false

func label() -> String:
	match _phase:
		"fetch": return "Fetching fuel can"
		"travel": return "Heading to generator"
		_: return "Refueling"

func score(npc: NPC) -> float:
	if not NPCJobQueries.has_refuel_target_available(npc):
		return 0.0
	return NPC.REFUEL_BASE_SCORE * npc.get_work_ethic_job_mult() \
		* npc.get_job_priority_weight("REFUEL")

func enter(npc: NPC) -> void:
	_refueled_ids = {}
	_finished = false
	if npc.held_item != null and npc.held_item.has_method("refuel_tick"):
		_can = npc.held_item
		_pick_next_generator(npc)
		return
	_phase = "fetch"
	_start_fetch(npc)

func _start_fetch(npc: NPC) -> void:
	var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
	var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
	var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
	var tgt: Node3D = loose if loose != null \
		else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
	if tgt == null:
		_finished = true   ## no spare can anywhere — nothing to do
		return
	if loose != null:
		if not NPCItemUser.claim_item(loose, npc):
			_finished = true   ## momentary claim clash — try again next think-cycle
			return
		_fetch_loose = loose
	else:
		if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
			_finished = true
			return
		_fetch_shelf = shelf_pick
	npc.set_nav_target(tgt.global_position)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if npc.held_item != null:
		_can = npc.held_item
		_pick_next_generator(npc)
		return
	if _fetch_loose != null and is_instance_valid(_fetch_loose):
		if "is_held" in _fetch_loose and _fetch_loose.is_held:
			_fetch_loose = null
			_finished = true
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) <= NPCItemUser.PICKUP_RANGE:
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_finished = true
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_finished = true
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_finished = true
		return
	_finished = true   ## nothing left to fetch — spare can vanished between scan and now

func _pick_next_generator(npc: NPC) -> void:
	_current_gen = NPCJobQueries.find_next_refuel_target(npc, _refueled_ids)
	if _current_gen == null:
		_finished = true   ## every generator full — session complete
		return
	npc.set_nav_target(approach_point(npc, _current_gen))
	_phase = "travel"

func tick(npc: NPC, delta: float) -> void:
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			if _current_gen == null or not is_instance_valid(_current_gen):
				_pick_next_generator(npc)
				return
			npc.nav_steer(delta)
			var t_pos: Vector3 = (_current_gen as Node3D).global_position
			var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
				.distance_to(Vector2(t_pos.x, t_pos.z))
			if flat_dist <= WORK_RANGE:
				npc.velocity = Vector3.ZERO
				_phase = "refuel"
				npc.show_work_banner()
		"refuel":
			npc.halt_movement(delta)
			if _can == null or not is_instance_valid(_can) \
					or _current_gen == null or not is_instance_valid(_current_gen):
				npc.hide_work_banner()
				_pick_next_generator(npc)
				return
			var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
			if pm == null:
				_finished = true
				return
			var gid: String = str(_current_gen.get_instance_id())
			npc.update_work_banner("REFUELING", pm.get_generator_fuel(gid) / 100.0)
			_can.refuel_tick(delta)   ## REAL continuous pour, same mechanic as before
			var fuel_after: float = pm.get_generator_fuel(gid)
			var can_empty: bool = ("_fuel_remaining" in _can) and float(_can._fuel_remaining) <= 0.0
			if fuel_after >= 100.0 or can_empty:
				npc.hide_work_banner()
				_refueled_ids[_current_gen.get_instance_id()] = true
				NotificationManager.notify(UIKit.Domain.POWER, NotificationManager.Severity.INFO,
					"%s refueled the generator" % npc.npc_name)
				npc.log_action("Refueled a generator")
				npc.gain_skill("electrical")
				if can_empty:
					_finished = true   ## can is dry — session ends even if generators remain
				else:
					_pick_next_generator(npc)

func done(_npc: NPC) -> bool:
	return _finished

func debug_info() -> Dictionary:
	return {
		"activity": "refuel",
		"phase": _phase,
		"can_held": _can != null and is_instance_valid(_can),
		"current_generator": (_current_gen.name if _current_gen != null and is_instance_valid(_current_gen) else ""),
		"refueled_this_session": _refueled_ids.size(),
	}

func exit(npc: NPC) -> void:
	npc.hide_work_banner()
	var detail: String = "phase=%s can_held=%s generator=%s" \
		% [_phase, _can != null and is_instance_valid(_can),
			(_current_gen.name if _current_gen != null and is_instance_valid(_current_gen) else "none")]
	if _fetch_loose != null:
		NPCItemUser.release_item(_fetch_loose)
	if not _fetch_shelf.is_empty():
		NPCItemUser.release_item(_fetch_shelf.get("item"))
	if _finished and npc.held_item != null and npc.held_item == _can:
		NPCItemUser.drop_held(npc)   ## session truly over — set the (empty or spare) can down
	on_session_exit(npc, "refuel", _finished, detail)
