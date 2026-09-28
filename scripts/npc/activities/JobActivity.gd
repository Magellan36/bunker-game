extends NPCActivity
class_name JobActivity
## JobActivity.gd — one JobBoard job (HARVEST a ready plant, REPLACE_FILTER
## on a worn purifier). NPCBrain offers one throwaway JobActivity per open
## job each think; the job is claimed on JobBoard in enter().
## Phases: fetch (REPLACE_FILTER needs a spare filter) → travel → work.
##
## Sep 2026: scored on the shared scale via NPC.work_score() (a failing
## filter grows more urgent as its quality drops); work speed follows the
## resident's age/injuries/skill; the fetched item is reserved; the harvest
## notification only fires when a harvest actually happened.

const WORK_RANGE: float = 2.0
const APPROACH_DISTANCE: float = 1.0

const TYPE_CONF: Dictionary = {
	"HARVEST":        {"time": 4.0, "skill": "farming",  "verb": "HARVESTING"},
	"REPLACE_FILTER": {"time": 5.0, "skill": "plumbing", "verb": "FITTING FILTER"},
}

var _job: Dictionary
var _phase: String = "fetch"
var _work_left: float = 0.0
var _work_total: float = 1.0
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _claimed: bool = false

func _init(job: Dictionary) -> void:
	_job = job

func label() -> String:
	match _phase:
		"fetch": return "Fetching supplies"
		"travel": return "Heading to %s" % ("the garden" if _job.get("type", "") == "HARVEST" else "the purifier")
	return "Harvesting" if _job.get("type", "") == "HARVEST" else "Replacing a filter"

func is_work() -> bool:
	return true

func accepts_held_item(_npc: NPC, item: Node) -> bool:
	var filt: Variant = _job.get("fetch_filter")
	return filt is Callable and (filt as Callable).call(item)

func score(npc: NPC) -> float:
	var type: String = _job.get("type", "")
	if not TYPE_CONF.has(type):
		return 0.0
	var target: Node3D = _job.get("target") as Node3D
	if target == null or not is_instance_valid(target):
		return 0.0
	var urgency_mult: float = 1.0
	if type == "REPLACE_FILTER" and "filter_quality" in target:
		urgency_mult = 1.0 + 2.0 * NPC.urgency(float(target.filter_quality), JobBoard.FILTER_BELOW, 3.0)
	var dist: float = NPCItemUser.flat_distance(target.global_position, npc.global_position)
	## The Lazy don't go looking for work: only jobs close by appeal.
	var sloth: float = 0.0 if npc.is_passion_job(type) else npc.get_sloth()
	return npc.work_score(type, urgency_mult) / (1.0 + dist * (0.02 + 0.1 * sloth))

func interruptible() -> bool:
	return _phase != "work"

func can_yield_to_need(npc: NPC) -> bool:
	return _phase != "work" and not NPCItemUser.hands_full(npc)

func enter(npc: NPC) -> void:
	_claimed = JobBoard.claim(_job, npc)
	if not _claimed:
		return
	var conf: Dictionary = TYPE_CONF[_job["type"]]
	_work_total = float(conf["time"])
	_work_left = _work_total
	var filt: Variant = _job.get("fetch_filter")
	if filt is Callable and not (NPCItemUser.hands_full(npc) and (filt as Callable).call(npc.held_item)):
		_phase = "fetch"
		var pick: Dictionary = NPCItemUser.find_fetch_target(npc, filt)
		_fetch_loose = pick.get("loose")
		_fetch_shelf = pick.get("shelf", {})
		var tgt: Node3D = _fetch_loose if _fetch_loose != null else (_fetch_shelf.get("shelf") as Node3D if not _fetch_shelf.is_empty() else null)
		var claim_target: Node = _fetch_loose if _fetch_loose != null else _fetch_shelf.get("item")
		if tgt == null or not NPCItemUser.claim_item(claim_target, npc):
			_claimed = false
			return
		npc.set_nav_target(tgt.global_position)
	else:
		_start_travel(npc)

func _start_travel(npc: NPC) -> void:
	_phase = "travel"
	var target: Node3D = _job.get("target") as Node3D
	if target != null and is_instance_valid(target):
		npc.set_nav_target(NPCSessionActivity.approach_point(npc, target, APPROACH_DISTANCE))

func tick(npc: NPC, delta: float) -> void:
	if not _claimed:
		return
	if not JobBoard.still_valid(_job):   ## the player (or time) beat us to it
		_claimed = false
		return
	var target: Node3D = _job.get("target") as Node3D
	if target == null or not is_instance_valid(target):
		_claimed = false
		return
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			npc.nav_steer(delta)
			if NPCItemUser.in_reach(npc, target.global_position, WORK_RANGE):
				npc.lock_movement()
				npc.face_toward(target.global_position, 1.0)
				_phase = "work"
				npc.show_work_banner()
		"work":
			npc.halt_movement(delta)
			var conf: Dictionary = TYPE_CONF[_job["type"]]
			_work_left -= delta * npc.get_work_speed_mult(String(conf["skill"]))
			npc.update_work_banner(String(conf["verb"]), 1.0 - (_work_left / _work_total))
			if _work_left <= 0.0:
				_complete(npc)

func _tick_fetch(npc: NPC, delta: float) -> void:
	var filt: Callable = _job["fetch_filter"]
	if NPCItemUser.hands_full(npc):
		if filt.call(npc.held_item):
			_start_travel(npc)
		else:
			NPCItemUser.drop_held(npc)
		return
	if _fetch_loose != null:
		if not is_instance_valid(_fetch_loose) or (("is_held" in _fetch_loose) and _fetch_loose.is_held):
			_claimed = false
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _fetch_loose.global_position, NPCItemUser.PICKUP_RANGE):
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_claimed = false
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_claimed = false
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_claimed = false
		return
	_claimed = false

func _complete(npc: NPC) -> void:
	var target: Node = _job.get("target")
	var conf: Dictionary = TYPE_CONF[_job["type"]]
	var succeeded: bool = false
	match _job["type"]:
		"HARVEST":
			if target != null and is_instance_valid(target) and target.has_method("is_ready") and target.is_ready():
				target.harvest()   ## spawns real produce, clears the cell
				succeeded = true
				NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
					"%s harvested the crops" % npc.npc_name)
				npc.log_action("Harvested crops")
		"REPLACE_FILTER":
			if npc.held_item is PurifierFilterItem:
				var filt: PurifierFilterItem = npc.held_item
				NPCItemUser.release_item(filt)
				npc.held_item = null      ## replace_filter consumes/frees it
				target.replace_filter(filt)
				succeeded = true
				NotificationManager.notify(UIKit.Domain.WATER, NotificationManager.Severity.INFO,
					"%s replaced the purifier filter" % npc.npc_name)
				npc.log_action("Replaced the purifier filter")
	NPCDebug.log_job("completed" if succeeded else "no-op", _job, npc)
	if succeeded:
		npc.on_work_done(String(conf["skill"]))
	_claimed = false

func done(_npc: NPC) -> bool:
	return not _claimed

func exit(npc: NPC) -> void:
	JobBoard.release(_job, npc)
	_claimed = false
