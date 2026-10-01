extends NPCActivity
## KeepAwayActivity.gd (Sep 2026, human-likeness pass) — someone frightened
## of the player (a killing, threats — NPC.fears_player) doesn't let them
## get close: when the player walks up, they move off to a few metres away
## (a walk, not a run — they're wary, not fleeing), now and then saying so.
## Their leisure spots already keep their distance too
## (NPC.leisure_spot_penalty). The frightened-but-furious are excluded
## (fears_player is false mid hostile crash-out): those confront instead.

const TRIGGER_RANGE: float = 2.8
const SAFE_RANGE: float = 6.5
const SAMPLES: int = 10
const GIVE_UP_SECONDS: float = 8.0

var _timer: float = 0.0
var _target: Vector3 = Vector3.ZERO

func score(npc: NPC) -> float:
	if npc.combat.dead or npc.crash.active() or not npc.fears_player() or npc.is_passed_out():
		return 0.0
	if npc.brain != null and npc.brain.is_sleeping():
		return 0.0
	var pl: Node3D = npc.get_tree().get_first_node_in_group("player") as Node3D
	if pl == null or NPCItemUser.flat_distance(pl.global_position, npc.global_position) > TRIGGER_RANGE:
		return 0.0
	return 30.0

func label() -> String:
	return "Keeping away from you"

func enter(npc: NPC) -> void:
	_timer = 0.0
	_target = _away_point(npc)
	npc.set_nav_target(_target)
	if randf() < 0.5:
		npc.bark(NPCDialogue.bark_line("keep_away"))

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	npc.nav_steer(delta)

func done(npc: NPC) -> bool:
	return _timer > GIVE_UP_SECONDS or npc.nav_finished() or NPCItemUser.flat_distance(npc.global_position, _target) < 0.6

func attention_target(_npc: NPC) -> Node3D:
	return null

func _away_point(npc: NPC) -> Vector3:
	var pl: Node3D = npc.get_tree().get_first_node_in_group("player") as Node3D
	var from: Vector3 = pl.global_position if pl != null else npc.global_position
	var best: Vector3 = npc.global_position + (npc.global_position - from).normalized() * SAFE_RANGE
	var best_cost: float = INF
	for i: int in SAMPLES:
		var a: float = randf() * TAU
		var p: Vector3 = npc.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, SAFE_RANGE + 2.0)
		var snapped: Vector3 = npc.stuck.snap_to_navmesh(p) if npc.stuck != null else p
		if snapped == Vector3.INF:
			continue
		var away: float = NPCItemUser.flat_distance(snapped, from)
		if away < SAFE_RANGE * 0.8:
			continue
		## Close by, but properly away from the player (and not next to a body).
		var cost: float = NPCItemUser.flat_distance(npc.global_position, snapped) + 4.0 * npc.leisure_spot_penalty(snapped) - away * 0.5
		if cost < best_cost and NPCItemUser.is_reachable(npc, snapped, 0.6):
			best_cost = cost
			best = snapped
	return best
