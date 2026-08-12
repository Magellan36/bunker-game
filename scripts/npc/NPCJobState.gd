extends RefCounted
class_name NPCJobState
## NPCJobState.gd (Aug 2026) — per-NPC cross-session job state, composed
## onto NPC.gd as `npc.job_state` instead of living as loose instance
## vars directly on the NPC class. Currently just the Cleaning give-up/
## blacklist system, but this is the natural home for any future
## per-NPC "remembers this specific thing didn't work" state a new job
## type needs — one place to look, not another few hundred lines added
## straight into NPC.gd.
const CLEANING_GIVEUP_STUCK_LIMIT: int = 2
const CLEANING_GIVEUP_PICKUP_LIMIT: int = 2

var _cleaning_blacklist: Dictionary = {}          ## item instance_id -> true
var _cleaning_pickup_failures: Dictionary = {}    ## item instance_id -> consecutive genuine-pickup-failure count

func is_cleaning_blacklisted(item_instance_id: int) -> bool:
	return _cleaning_blacklist.has(item_instance_id)

func blacklist_cleaning_item(npc: Node, item: Node, reason: String) -> void:
	if item == null:
		return
	var id: int = item.get_instance_id()
	if _cleaning_blacklist.has(id):
		return
	_cleaning_blacklist[id] = true
	if NPCDebug.enabled:
		var name: String = item.get_display_name() if item.has_method("get_display_name") else str(item.name)
		NPCDebug.log_cleaning(npc, "gave up permanently", "%s — %s" % [name, reason])

func record_cleaning_pickup_failure(npc: Node, item: Node) -> void:
	if item == null:
		return
	var id: int = item.get_instance_id()
	var count: int = int(_cleaning_pickup_failures.get(id, 0)) + 1
	_cleaning_pickup_failures[id] = count
	if count >= CLEANING_GIVEUP_PICKUP_LIMIT:
		blacklist_cleaning_item(npc, item, "pickup refused %d times in a row while in range" % count)
