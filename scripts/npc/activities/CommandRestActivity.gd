extends NPCActivity
class_name CommandRestActivity
## "Take a load off" player command (Part 19). Tries a bed first
## (better rest, per LieActivity), falls back to a chair (SitActivity)
## if no bed is free/reachable. Delegates entirely to whichever inner
## activity is chosen, so arrival/occupancy/energy-regen behavior is
## identical to the needs-driven versions — this only decides which one
## to try, and does so regardless of current Energy (a player command
## should work even if Energy is high, unlike the automatic versions
## which only compete for selection below 60).
var _inner: NPCActivity = null

func label() -> String:
	return _inner.label() if _inner != null else "Resting"

func score(_npc: NPC) -> float:
	return 0.0   ## never selected via normal scoring — command-only

func interruptible() -> bool:
	return _inner == null or _inner.interruptible()

func enter(npc: NPC) -> void:
	_inner = LieActivity.new()
	_inner.enter(npc)
	if _inner.done(npc):   ## no bed available/reachable — fall back to a chair
		_inner.exit(npc)
		_inner = SitActivity.new()
		_inner.enter(npc)

func tick(npc: NPC, delta: float) -> void:
	if _inner != null:
		_inner.tick(npc, delta)

func done(npc: NPC) -> bool:
	return _inner == null or _inner.done(npc)

func exit(npc: NPC) -> void:
	if _inner != null:
		_inner.exit(npc)
	_inner = null