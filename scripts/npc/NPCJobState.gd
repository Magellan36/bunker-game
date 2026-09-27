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

# ─── Unreachable targets (Sep 2026) ────────────────────────────────────────
## Items / furniture this NPC recently couldn't get to (navmesh path ends
## out of reach). Skipped by target searches until the memory expires —
## the item may be kicked loose or the furniture moved in the meantime.
const UNREACHABLE_MEMORY_HOURS: float = 1.0
var _unreachable: Dictionary = {}   ## instance_id -> NPCClock hours when it expires

func mark_unreachable(node: Node, hours: float = UNREACHABLE_MEMORY_HOURS) -> void:
	if node != null:
		_unreachable[node.get_instance_id()] = NPCClock.now() + hours

func is_unreachable(node: Node) -> bool:
	if node == null:
		return false
	var id: int = node.get_instance_id()
	if not _unreachable.has(id):
		return false
	if NPCClock.now() >= float(_unreachable[id]):
		_unreachable.erase(id)
		return false
	return true

## Everything reservable within `radius` of `pos` (used by the stuck
## watchdog when it gives up on an approach: whatever was there is out of
## reach for now).
func mark_unreachable_near(tree: SceneTree, pos: Vector3, radius: float) -> void:
	for group: String in ["pickup", "shelving", "trash_receptacle", "stove", "farming_tray", "generator", "water_dispenser"]:
		for n: Node in tree.get_nodes_in_group(group):
			if n is Node3D and is_instance_valid(n) and NPCItemUser.flat_distance((n as Node3D).global_position, pos) <= radius:
				mark_unreachable(n)

