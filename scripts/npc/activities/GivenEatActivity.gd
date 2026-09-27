extends EatActivity
class_name GivenEatActivity
## GivenEatActivity.gd — eat the food someone just handed over (player Give,
## NPC Give-to-Friend, or a successful snatch). Force-started only; the item
## is already in hand, which EatActivity.tick() eats first.

func score(_npc: NPC) -> float:
	return 0.0

func enter(_npc: NPC) -> void:
	_eating = 0.0

func backoff_on_futile() -> bool:
	return false
