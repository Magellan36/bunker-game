extends NPCActivity
class_name ForgetfulWanderActivity
## 20 seconds of ordinary wandering, forced in place of a job the brain
## was about to start (Part 14's forgetfulness roll). Non-interruptible
## for its full duration so the SAME job (or a new one) can't just steal
## it right back on the next think-tick — it has to actually run its
## course, matching "opt to wander... as opposed to working a job."
## Delegates the actual walking behavior to a plain WanderActivity
## instance rather than duplicating it.
const FORGET_DURATION: float = 20.0

var _timer: float = 0.0
var _inner: NPCActivity = null

func label() -> String:
	return "Wandering (forgot what they were doing)"

func score(_npc: NPC) -> float:
	return 0.0   ## never selected via normal scoring — force-started only

func interruptible() -> bool:
	return false

func enter(npc: NPC) -> void:
	_timer = FORGET_DURATION
	_inner = WanderActivity.new()
	_inner.enter(npc)

func tick(npc: NPC, delta: float) -> void:
	_timer -= delta
	_inner.tick(npc, delta)

func done(_npc: NPC) -> bool:
	return _timer <= 0.0

func exit(npc: NPC) -> void:
	_inner.exit(npc)