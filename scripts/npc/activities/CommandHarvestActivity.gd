extends NPCActivity
class_name CommandHarvestActivity
## "Harvest the plants" player command (Part 19). Finds the nearest
## open HARVEST job (bypassing the brain's normal skill/distance-scored
## competition among NPCs) and forces it via the SAME JobActivity the
## automatic system uses — real produce, real progress banner, real
## claim. If nothing is ready, done() is immediately true and does
## nothing further; NPCTalkMenuUI shows a toast either way.
var _inner: NPCActivity = null

func label() -> String:
	return _inner.label() if _inner != null else "Idle"

func score(_npc: NPC) -> float:
	return 0.0   ## never selected via normal scoring — command-only

func interruptible() -> bool:
	return _inner == null or _inner.interruptible()

func enter(npc: NPC) -> void:
	for job: Dictionary in JobBoard.get_open_jobs():
		if job.get("type", "") == "HARVEST":
			_inner = JobActivity.new(job)
			_inner.enter(npc)
			return
	_inner = null   ## nothing ready to harvest

func tick(npc: NPC, delta: float) -> void:
	if _inner != null:
		_inner.tick(npc, delta)

func done(npc: NPC) -> bool:
	return _inner == null or _inner.done(npc)

func exit(npc: NPC) -> void:
	if _inner != null:
		_inner.exit(npc)
	_inner = null