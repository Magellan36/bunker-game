extends NPCCommandWrapperActivity
class_name CommandCleaningActivity
## Backs the "Clean the bunker" player request — see
## NPCCommandWrapperActivity.gd for the shared shape.
func _make_inner(_npc: NPC) -> NPCActivity:
	return CleaningActivity.new()
