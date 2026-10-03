extends RelaxSitActivity
## LeisureSitActivity.gd (Sep 2026, human-likeness pass) — free time: take a
## seat and stay a while, the way people actually spend idle time.
##
## Before this, sitting only happened when tired (SitActivity) or as a
## rationed work break (RelaxActivity), so idle residents mostly wandered,
## switching activity 3–4 times a real minute. Durations here are REAL
## seconds (a game hour is a real minute — "40 game minutes" is 40 seconds
## on screen), and anything that matters (a job, a need) still gets them up:
## free time is interruptible.
##
## Chair choice (NPC.leisure_spot_penalty): not next to a body when there's
## any other seat, not near the player when afraid of them, and somewhere
## alone when mourning.

const BASE_SCORE: float = 7.0
const SIT_SECONDS: Vector2 = Vector2(120.0, 300.0)      ## real seconds
const COOLDOWN_SECONDS: Vector2 = Vector2(20.0, 60.0)   ## before sitting down again
const MAX_DISTANCE: float = 25.0

var _left: float = 0.0

func label() -> String:
	match _state:
		SState.SEEK: return "Finding a seat"
		SState.STANDING: return "Getting up"
		_: return "Sitting"

func is_need() -> bool:
	return false

func score(npc: NPC) -> float:
	if npc.is_night_for_me() or NPCItemUser.hands_full(npc) or npc.crash.active() or npc.social.drive() >= 0.4:
		return 0.0
	if _state == SState.SEATED and _chair != null:
		## Already sitting (the running one): worth what sitting is worth, so
		## only a job that beats it ends it (NPCBrain wrap-up), not any job.
		return BASE_SCORE * npc.get_work_ethic_passive_mult() * npc.leisure_bias("sit")
	if Time.get_ticks_msec() < int(npc.get_meta("_leisure_sit_cooldown_msec", 0)):
		return 0.0
	if pick_chair(npc) == null:
		return 0.0
	return BASE_SCORE * npc.get_work_ethic_passive_mult() * npc.leisure_bias("sit")

## Free time gives way to anything that matters.
func interruptible() -> bool:
	return true

func can_yield_to_need(_npc: NPC) -> bool:
	return true

func enter(npc: NPC) -> void:
	_chair = pick_chair(npc)
	_state = SState.SEEK
	_seek_time = 0.0
	_left = randf_range(SIT_SECONDS.x, SIT_SECONDS.y)
	if _chair != null:
		NPCItemUser.claim_item(_chair, npc)
		npc.set_nav_target(_approach_point(_chair))

func tick(npc: NPC, delta: float) -> void:
	super.tick(npc, delta)
	if _state == SState.SEATED:
		_left -= delta
		if _left <= 0.0:
			_stand(npc)

func exit(npc: NPC) -> void:
	npc.set_meta("_leisure_sit_cooldown_msec", Time.get_ticks_msec() + int(randf_range(COOLDOWN_SECONDS.x, COOLDOWN_SECONDS.y) * 1000.0))
	super.exit(npc)

## The free, reachable chair that's best to settle in: near, but not next
## to a body / the feared player / (mourning) other people.
static func pick_chair(npc: NPC) -> Node:
	var best: Node = null
	var best_cost: float = INF
	for c: Node in npc.get_tree().get_nodes_in_group("chair"):
		if not (c is Node3D) or (c.has_method("is_seat_free") and not c.is_seat_free()) or NPCItemUser.is_claimed_by_other(c, npc):
			continue
		var pos: Vector3 = (c as Node3D).global_position
		var d: float = NPCItemUser.flat_distance(npc.global_position, pos)
		if d > MAX_DISTANCE:
			continue
		var cost: float = d + 4.0 * npc.leisure_spot_penalty(pos)
		if cost < best_cost and NPCItemUser.is_reachable(npc, _approach_point(c), 0.6):
			best_cost = cost
			best = c
	return best

func is_leisure() -> bool:
	return true   ## gives way to work after a short wrap-up (NPCBrain)
