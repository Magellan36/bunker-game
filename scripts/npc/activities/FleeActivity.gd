extends NPCActivity
class_name FleeActivity
## FleeActivity.gd (Sep 2026) — attacked and not fighting back: run for it.
## NPCCombat sets the flee window; this picks the reachable spot farthest
## from the attacker and runs there (NPC speed ×1.6 while fleeing), crying
## out now and then. Not interruptible until it's over.

const SAMPLES: int = 8

var _bark_timer: float = 0.0
var _retarget: float = 0.0

func score(npc: NPC) -> float:
	return 950.0 if npc.combat.is_fleeing() else 0.0

func label() -> String:
	return "Running away"

func interruptible() -> bool:
	return false

func backoff_on_futile() -> bool:
	return false

func enter(npc: NPC) -> void:
	_bark_timer = randf_range(2.0, 4.0)
	_retarget = 0.0

func tick(npc: NPC, delta: float) -> void:
	_retarget -= delta
	if _retarget <= 0.0 or npc.nav_finished():
		_retarget = 2.5
		npc.set_nav_target(_away_point(npc))
	npc.nav_steer(delta)
	_bark_timer -= delta
	if _bark_timer <= 0.0:
		_bark_timer = randf_range(3.0, 6.0)
		npc.bark_event("flee")

func done(npc: NPC) -> bool:
	return not npc.combat.is_fleeing()

func attention_target(npc: NPC) -> Node3D:
	return npc.combat.threat_node()

## The cleared floor cell farthest from the attacker (of a few samples).
func _away_point(npc: NPC) -> Vector3:
	var threat: Node3D = npc.combat.threat_node()
	var from: Vector3 = threat.global_position if threat != null else npc.global_position
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	var best: Vector3 = npc.global_position + (npc.global_position - from).normalized() * 6.0
	var best_d: float = -1.0
	if world == null or not world.has_method("get_random_cleared_cell_center"):
		return best
	for i: int in SAMPLES:
		var p: Vector3 = world.get_random_cleared_cell_center()
		var d: float = NPCItemUser.flat_distance(p, from)
		if d > best_d and NPCItemUser.is_reachable(npc, p, 1.0):
			best_d = d
			best = p
	return best
