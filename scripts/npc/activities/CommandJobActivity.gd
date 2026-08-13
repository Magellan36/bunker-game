extends NPCCommandWrapperActivity
class_name CommandJobActivity
## Generalized "can you complete this job?" command (Aug 2026) —
## CommandHarvestActivity's exact pattern, parameterized by job type,
## so adding a new JobBoard-routed job type later needs no new class
## here, just a new entry in NPCTalkMenuUI's job menu list. See
## NPCCommandWrapperActivity.gd for the shared shape.
var _job_type: String = ""

func _init(job_type: String) -> void:
	_job_type = job_type

func _make_inner(_npc: NPC) -> NPCActivity:
	for job: Dictionary in JobBoard.get_open_jobs():
		if job.get("type", "") == _job_type:
			return JobActivity.new(job)
	return NPCActivity.new()