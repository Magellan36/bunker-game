extends NPCCommandWrapperActivity
class_name CommandHarvestActivity
## "Harvest the plants" player command (Part 19). Finds the nearest
## open HARVEST job (bypassing the brain's normal skill/distance-scored
## competition among NPCs) and forces it via the SAME JobActivity the
## automatic system uses — real produce, real progress banner, real
## claim. If nothing is ready, the base's enter() finds done() true on
## the returned placeholder and clears _inner to null immediately;
## NPCTalkMenuUI shows a toast either way. See
## NPCCommandWrapperActivity.gd for the shared shape.
func _make_inner(_npc: NPC) -> NPCActivity:
	for job: Dictionary in JobBoard.get_open_jobs():
		if job.get("type", "") == "HARVEST":
			return JobActivity.new(job)
	return NPCActivity.new()   ## nothing ready to harvest — base NPCActivity.done() defaults to true