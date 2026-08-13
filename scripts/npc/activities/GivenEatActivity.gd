extends EatActivity
class_name GivenEatActivity
## Player Give hand-off (Part 28). Reuses EatActivity's tick()/done()/
## exit()/label()/interruptible()/_reacquire_or_finish() completely
## unchanged — they already key off npc.held_item being set, which is
## exactly what a gift (or a successful Snatch) produces. Only
## enter()/score() differ: no search, no claim, never auto-selected.
func score(_npc: NPC) -> float:
	return 0.0
func enter(_npc: NPC) -> void:
	_eating = 0.0
func begin_with_item(_npc: NPC, _item: Node) -> void:
	pass   ## tick() already reads held_item directly — nothing else needed