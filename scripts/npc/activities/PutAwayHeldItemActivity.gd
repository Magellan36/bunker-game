extends NPCActivity
class_name PutAwayHeldItemActivity
## PutAwayHeldItemActivity.gd — the tidy-up reflex: whenever a resident is
## holding something that no current activity is using (leftovers of a can,
## a bottle with water left, a tool from an interrupted job...), they take
## it to the right storage — trash to a trash can, light items preferably
## to an End Table/Dresser, heavy ones to a shelf — or set it down if
## there's nowhere for it.
##
## Scores above idle and most chores (a resident finishes what's in their
## hands before starting something new) but below real needs. Short and
## self-contained, so it's not interruptible.

const SCORE: float = 30.0

var _item: RigidBody3D = null
var _destination: Node = null
var _settled: bool = false
var _stall: float = 0.0
var _elapsed: float = 0.0
const GIVE_UP_SECONDS: float = 30.0

func label() -> String:
	return "Putting away %s" % NPCSessionActivity.display_name(_item) if _item != null else "Tidying up"

func score(npc: NPC) -> float:
	return SCORE if NPCItemUser.hands_full(npc) else 0.0

func interruptible() -> bool:
	return false

func can_yield_to_need(_npc: NPC) -> bool:
	return true   ## dropping the item to go eat is fine

func accepts_held_item(_npc: NPC, _item_in_hand: Node) -> bool:
	return true   ## the whole point

func backoff_on_futile() -> bool:
	return false

func enter(npc: NPC) -> void:
	_settled = false
	_elapsed = 0.0
	_item = npc.held_item
	if _item == null or not is_instance_valid(_item):
		_settled = true
		return
	var is_trash: bool = NPCJobQueries.is_trash_item(npc, _item)
	_destination = NPCJobQueries.find_cleaning_destination(npc, is_trash, _item)
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away held item", "%s -> %s" % [
			NPCSessionActivity.display_name(_item), _destination.name if _destination != null else "(nowhere — setting it down)"])
	if _destination == null:
		NPCItemUser.drop_held(npc)
		npc.lock_movement()
		_settled = true
		return
	npc.set_nav_target((_destination as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _settled:
		return
	if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
		_settled = true   ## lost it somehow — nothing left to do
		return
	if _destination == null or not is_instance_valid(_destination):
		NPCItemUser.drop_held(npc)
		_settled = true
		return
	## Sep 2026: never carry something round for minutes (a jerry can was
	## carried for 3 real minutes toward a shelf it couldn't reach). The
	## time is kept on the item, so restarts don't reset it.
	_elapsed += delta
	if NPCItemUser.add_carry_time(_item, delta) > NPCItemUser.CARRY_LIMIT_S:
		npc.job_state.mark_unreachable(_destination)
		npc.job_state.blacklist_cleaning_item(npc, _item, "couldn't reach its storage")
		NPCItemUser.clear_carry_time(_item)
		NPCItemUser.drop_held(npc)
		_settled = true
		return
	## Someone's using that storage: wait your turn a little way back.
	if NPCItemUser.wait_turn_at(npc, _destination, delta):
		return
	npc.nav_steer(delta)
	## Can't get there (a pocket the navmesh can't route out of, storage
	## walled in): set it down rather than stand holding it forever.
	if npc.nav_finished() and not NPCItemUser.in_reach(npc, (_destination as Node3D).global_position, NPCItemUser.SHELF_RANGE):
		_stall += delta
		if _stall > 2.0:
			NPCItemUser.drop_held(npc)
			_settled = true
		return
	_stall = 0.0
	if NPCItemUser.in_reach(npc, (_destination as Node3D).global_position, NPCItemUser.SHELF_RANGE):
		npc.lock_movement()
		var stored_item: Node = _item
		if not NPCItemUser.store_held(npc, _destination):
			NPCItemUser.drop_held(npc)   ## filled up since we set out — set it down rather than loop
		NPCItemUser.clear_carry_time(stored_item)
		_settled = true

func done(_npc: NPC) -> bool:
	return _settled

func exit(npc: NPC) -> void:
	pass
