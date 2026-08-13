extends NPCActivity
class_name WanderActivity
var _idle_left: float = 0.0
var _walking: bool = false

func score(npc: NPC) -> float:
	return 5.0 * npc.get_work_ethic_passive_mult()   ## constant baseline — always available, loses to any need

func label() -> String:
	return "Wandering"

func enter(npc: NPC) -> void:
	_idle_left = randf_range(npc.idle_time_min, npc.idle_time_max)
	_walking = false

func tick(npc: NPC, delta: float) -> void:
	if _walking:
		npc.nav_steer(delta)
		if npc.nav_finished():
			_walking = false
			_idle_left = randf_range(npc.idle_time_min, npc.idle_time_max)
	else:
		npc.halt_movement(delta)
		_idle_left -= delta
		if _idle_left <= 0.0:
			var world: Node = npc.get_tree().get_first_node_in_group("main_world")
			if world != null and world.has_method("get_random_cleared_cell_center"):
				npc.set_nav_target(world.get_random_cleared_cell_center())
				_walking = true

func done(_npc: NPC) -> bool:
	return false   ## endless; only ends by interruption

func exit(npc: NPC) -> void:
	npc.halt_movement(1.0)