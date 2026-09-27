extends NPCCommandWrapperActivity
class_name CommandRestActivity
## CommandRestActivity.gd — "Go get some rest": sleep now, whatever the time
## (bed → chair → floor, handled by LieActivity), waking at 90% energy.

func _make_inner(_npc: NPC) -> NPCActivity:
	var lie: LieActivity = LieActivity.new()
	lie.forced = true
	return lie
