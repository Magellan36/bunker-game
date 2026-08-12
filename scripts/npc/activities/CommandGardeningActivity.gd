extends NPCCommandWrapperActivity
class_name CommandGardeningActivity
## Backs all Gardening player requests ("Tend the farm", "Fertilize the
## trays") — see NPCCommandWrapperActivity.gd for the shared shape.
var mode: String = "auto"
var forced_seed_type: String = ""

func _make_inner(_npc: NPC) -> NPCActivity:
	var g: GardeningActivity = GardeningActivity.new()
	g.mode = mode
	g.forced_seed_type = forced_seed_type
	return g
