extends NPCActivity
class_name JobActivity
## Executes one JobBoard job: [optional fetch item] → travel → work timer
## with overhead banner → apply the SAME world effect a player action has.
const WORK_RANGE: float = 1.6

## Per-type work seconds and skill key.
const TYPE_CONF: Dictionary = {
	"HARVEST":        {"time": 4.0, "skill": "farming",    "base": 55.0, "verb": "HARVESTING"},
	"REPLACE_FILTER": {"time": 5.0, "skill": "plumbing",   "base": 65.0, "verb": "FITTING FILTER"},
}

var _job: Dictionary
var _phase: String = "fetch"   ## fetch → travel → work
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
		"travel": return "Heading to work"
		_: return "Working"

func score(npc: NPC) -> float:
	var conf: Dictionary = TYPE_CONF.get(_job.get("type", ""), {})
	if conf.is_empty():
		return 0.0
	var target: Node = _job.get("target")
	if target == null or not is_instance_valid(target):
		return 0.0
	var skill: float = float(npc.skills.get(conf["skill"], 1.0))
	var dist: float = NPCItemUser.flat_distance((target as Node3D).global_position, npc.global_position)
	var base_score: float = float(conf["base"]) * skill / (1.0 + dist * 0.08)
	## Irritability reduces willingness to work (Part 20) — distinct from
	## forgetfulness, which diverts AWAY from a job already chosen. This
	## instead makes an irritable NPC less likely to be picked as a job's
	## best candidate in the first place. Halves at max irritability (100%).
	## Not separately logged — it's a continuous scoring effect evaluated
	## every think-cycle for every open job, not a discrete event.
	var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
	return base_score * willingness * npc.get_work_ethic_job_mult() \
		* npc.get_job_priority_weight(_job.get("type", ""))

func interruptible() -> bool:
	return _phase != "work"

func enter(npc: NPC) -> void:
	_claimed = JobBoard.claim(_job, npc)
	if not _claimed:
		return
	var conf: Dictionary = TYPE_CONF[_job["type"]]
	_work_total = float(conf["time"])
	_work_left = _work_total

	var needs_fetch: bool = _job.get("fetch_filter") != null
	if needs_fetch and npc.held_item == null:
		_phase = "fetch"
		var filt: Callable = _job["fetch_filter"]
		_fetch_loose = NPCItemUser.find_loose_item(npc, filt)
		_fetch_shelf = {} if _fetch_loose != null \
			else NPCItemUser.find_shelved_item(npc, filt)
		var tgt: Node3D = _fetch_loose if _fetch_loose != null \
			else (_fetch_shelf.get("shelf") as Node3D if not _fetch_shelf.is_empty() else null)
		if tgt == null:
			_claimed = false   ## spare vanished between scan and now
			JobBoard.release(_job, npc)
			return
		npc.set_nav_target(tgt.global_position)
	else:
		_start_travel(npc)

const APPROACH_DISTANCE: float = 1.0   ## stand-off from the object's center —
                                       ## clear of its own collision footprint
                                       ## and therefore actually on the navmesh

func _start_travel(npc: NPC) -> void:
	_phase = "travel"
	var target: Node3D = _job.get("target") as Node3D
	if target != null and is_instance_valid(target):
		npc.set_nav_target(_approach_point(npc, target))

## A reachable point APPROACH_DISTANCE from the object's center, along the
## line from wherever the NPC currently is — not a hardcoded "front," so
## it adapts to whichever side the NPC is already approaching from. The
## raw center (what this replaces) sits inside the object's own collision
## footprint and off the navmesh entirely (Part 9's bake carves out every
## static obstacle's interior), which is why targeting it directly made
## the NPC walk into the object and get stuck fighting its collision.
func _approach_point(npc: NPC, target: Node3D) -> Vector3:
	var to_npc: Vector3 = npc.global_position - target.global_position
	to_npc.y = 0.0
	if to_npc.length() < 0.01:
		to_npc = Vector3(0.0, 0.0, 1.0)   ## degenerate case: npc exactly at center
	return target.global_position + to_npc.normalized() * APPROACH_DISTANCE

func tick(npc: NPC, delta: float) -> void:
	if not _claimed:
		return
	if not JobBoard.still_valid(_job):   ## player beat us to it
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
			## Flattened to XZ (Part 15) — target.global_position's Y can sit
			## anywhere depending on the object's own mesh pivot, and this
			## NPC's own origin is its capsule center (~1.4) — the same raw-
			## 3D-distance mismatch already fixed for SitActivity in Part 12.
			var t_pos: Vector3 = target.global_position
			var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
				.distance_to(Vector2(t_pos.x, t_pos.z))
			if flat_dist <= WORK_RANGE:
				npc.velocity = Vector3.ZERO
				_phase = "work"
				npc.show_work_banner()
		"work":
			npc.halt_movement(delta)
			_work_left -= delta
			var conf: Dictionary = TYPE_CONF[_job["type"]]
			npc.update_work_banner(String(conf["verb"]),
				1.0 - (_work_left / _work_total))
			if _work_left <= 0.0:
				_complete(npc)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if npc.held_item != null:
		_start_travel(npc)
		return
	if _fetch_loose != null and is_instance_valid(_fetch_loose):
		if "is_held" in _fetch_loose and _fetch_loose.is_held:
			_fetch_loose = null
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) \
				<= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.grab_loose(npc, _fetch_loose):
				_start_travel(npc)
			else:
				_fetch_loose = null
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_claimed = false
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) \
				<= NPCItemUser.SHELF_RANGE:
			if NPCItemUser.grab_from_shelf(npc, shelf,
					int(_fetch_shelf.get("slot", -1))):
				_start_travel(npc)
			else:
				_claimed = false
		return
	_claimed = false   ## nothing left to fetch

func _complete(npc: NPC) -> void:
	var target: Node = _job.get("target")
	var conf: Dictionary = TYPE_CONF[_job["type"]]
	match _job["type"]:
		"HARVEST":
			## target IS the plant now (Part 31 — one job per plant,
			## not per tray).
			if target != null and is_instance_valid(target) and target.has_method("is_ready") and target.is_ready():
				target.harvest()   ## spawns real produce, clears cell
			NotificationManager.notify(UIKit.Domain.NEUTRAL,
				NotificationManager.Severity.INFO,
				"%s harvested the crops" % npc.npc_name)
			npc.log_action("Job (Harvest)")
		"REPLACE_FILTER":
			if npc.held_item is PurifierFilterItem:
				var filt: PurifierFilterItem = npc.held_item
				npc.held_item = null      ## replace_filter consumes/frees it
				target.replace_filter(filt)
				NotificationManager.notify(UIKit.Domain.WATER,
					NotificationManager.Severity.INFO,
					"%s replaced the purifier filter" % npc.npc_name)
	NPCDebug.log_job("completed", _job, npc)
	npc.gain_skill(String(conf["skill"]))
	_claimed = false

func done(_npc: NPC) -> bool:
	return not _claimed

func exit(npc: NPC) -> void:
	npc.hide_work_banner()
	JobBoard.release(_job, npc)
	if npc.held_item != null:
		NPCItemUser.drop_held(npc)
	_claimed = false