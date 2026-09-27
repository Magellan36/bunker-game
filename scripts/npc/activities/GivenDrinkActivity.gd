extends DrinkActivity
class_name GivenDrinkActivity
## GivenDrinkActivity.gd — drink the bottle someone just handed over (player
## Give, NPC Give-to-Friend, or a successful snatch). Force-started only.

func score(_npc: NPC) -> float:
	return 0.0

func begin_with_item(_npc: NPC, item: Node) -> void:
	if item != null and is_instance_valid(item):
		_mode = "bottle"
		_target = item
		_finished = false

func backoff_on_futile() -> bool:
	return false
