extends NPCActivity
class_name CommandJobActivity
## Generalized "can you complete this job?" command (Aug 2026) —
## CommandHarvestActivity's exact pattern, parameterized by job type,
## so adding a new JobBoard-routed job type later needs no new class
## here, just a new entry in NPCTalkMenuUI's job menu list.
var _job_type: String = ""
var _inner: NPCActivity = null

func _init(job_type: String) -> void:
	_job_type = job_type

func label() -> String:
	return _inner.label() if _inner != null else "Idle"

func score(_npc: NPC) -> float:
	return 0.0   ## command-only, never auto-selected

func interruptible() -> bool:
	return _inner == null or _inner.interruptible()

func enter(npc: NPC) -> void:
	for job: Dictionary in JobBoard.get_open_jobs():
		if job.get("type", "") == _job_type:
			_inner = JobActivity.new(job)
			_inner.enter(npc)
			return
	_inner = null

func tick(npc: NPC, delta: float) -> void:
	if _inner != null:
		_inner.tick(npc, delta)

func done(npc: NPC) -> bool:
	return _inner == null or _inner.done(npc)

func exit(npc: NPC) -> void:
	if _inner != null:
		_inner.exit(npc)
	_inner = null