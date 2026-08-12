extends NPCCommandWrapperActivity
class_name CommandRefuelActivity
## Backs the "Refuel the generator" player request — see
## NPCCommandWrapperActivity.gd for the shared shape.
func _make_inner(_npc: NPC) -> NPCActivity:
	return RefuelActivity.new()
