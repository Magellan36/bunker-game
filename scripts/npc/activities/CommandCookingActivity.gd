extends NPCCommandWrapperActivity
class_name CommandCookingActivity
## "Cook a meal" player command (Aug 2026). Thin wrapper — all real logic
## lives in CookingActivity (a proper NPCSessionActivity), so this job is
## already shaped to gain autonomous scoring later with zero rework here;
## only CookingActivity.score() would need to change. See
## NPCCommandWrapperActivity.gd for the shared shape.
func _make_inner(_npc: NPC) -> NPCActivity:
	return CookingActivity.new()
