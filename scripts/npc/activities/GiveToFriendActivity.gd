extends NPCActivity
class_name GiveToFriendActivity
## GiveToFriendActivity.gd — notice a friend is hungry/thirsty, fetch a
## matching loose item and bring it to them. Gated by a relationship-scaled
## roll (NPC.find_friend_to_help). The hand-over goes through the same
## on_item_given() path as the player's Give, so the friend eats/drinks it
## and the relationship and thoughts land on the right person.

var _friend: NPC = null
var _loose: RigidBody3D = null
var _finished: bool = false

func label() -> String:
	if _friend == null:
		return "Helping a friend"
	return "Bringing %s something" % _friend.npc_name if _loose == null else "Getting something for %s" % _friend.npc_name

func score(npc: NPC) -> float:
	if not npc.has_needy_friend():
		return 0.0
	return NPC.GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()

func enter(npc: NPC) -> void:
	_finished = false
	var result: Dictionary = npc.find_friend_to_help()
	if result.is_empty():
		_finished = true
		return
	_friend = result.get("friend")
	_loose = result.get("item")
	if not NPCItemUser.claim_item(_loose, npc):
		_finished = true
		return
	npc.set_nav_target(_loose.global_position)

func tick(npc: NPC, delta: float) -> void:
	if _finished:
		return
	if _friend == null or not is_instance_valid(_friend):
		_finished = true
		return
	if not NPCItemUser.hands_full(npc):
		if _loose == null or not is_instance_valid(_loose) or (("is_held" in _loose) and _loose.is_held) or _loose.is_in_group("shelved"):
			_finished = true
			return
		NPCItemUser.track_fetch_target(npc, _loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _loose.global_position, NPCItemUser.PICKUP_RANGE):
			if NPCItemUser.grab_loose(npc, _loose):
				_loose = null
			else:
				_finished = true
		return
	## Delivering.
	if _friend.hunger >= NPC.NEED_SATED and _friend.thirst >= NPC.NEED_SATED:
		_finished = true   ## fed some other way meanwhile; the brain's hands policy / PutAway deals with the item
		return
	npc.set_nav_target(_friend.global_position)
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, _friend.global_position, NPCItemUser.SNATCH_RANGE):
		npc.lock_movement()
		if _friend.can_receive_item(npc.held_item, npc.npc_id):
			var item: Node = NPCItemUser.hand_over(npc, _friend)
			if item != null:
				npc.log_action("Gave %s to %s" % [NPCSessionActivity.display_name(item), _friend.npc_name])
				npc.add_thought("helped_friend", _friend.npc_name)
				_friend.on_item_given(item, npc.npc_id, npc.npc_name)
		_finished = true

func done(_npc: NPC) -> bool:
	return _finished

## Keeps a fetched gift in hand for PutAway if the delivery didn't happen.
func accepts_held_item(_npc: NPC, _item: Node) -> bool:
	return false
