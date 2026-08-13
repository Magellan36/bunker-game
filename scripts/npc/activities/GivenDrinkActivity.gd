extends DrinkActivity
class_name GivenDrinkActivity
## Same reasoning as GivenEatActivity, but DrinkActivity's tick()
## checks `_target` (not held_item) first — begin_with_item() has to
## populate that explicitly.
func score(_npc: NPC) -> float:
	return 0.0
func enter(_npc: NPC) -> void:
	_drinking = 0.0
	_mode = ""
	_target = null
func begin_with_item(_npc: NPC, item: Node) -> void:
	_mode = "bottle"
	_target = item