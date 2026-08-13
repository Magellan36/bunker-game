extends NPCActivity
class_name GiveToFriendActivity
## NPC→NPC Give (Aug 2026). Fetch phase mirrors JobActivity's fetch
## exactly (find/claim/grab a loose item); travel phase mirrors
## SnatchActivity's continuous re-aim at a moving target; hand-off
## reuses can_receive_item()/on_item_given() unchanged in spirit
## (just told who the giver actually is). Interruptible throughout —
## unlike Snatch, this is a low-stakes altruistic errand, fine to
## abandon if something more pressing comes up.
var _friend: Node = null
var _loose: RigidBody3D = null

func label() -> String:
	return "Bringing %s something" % _friend.npc_name if _friend != null and _loose == null and npc_holds_nothing() else "Getting an item for a friend"

## Small helper avoiding a direct `npc` reference in label() (label()
## has no npc param) — see note below if your NPCActivity base differs;
## simplest fallback if this causes issues is just a flat "Helping a friend" label.
func npc_holds_nothing() -> bool:
	return true

func score(npc: NPC) -> float:
	if not npc.has_needy_friend():
		return 0.0
	return NPC.GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()

func interruptible() -> bool:
	return true

func enter(npc: NPC) -> void:
	var result: Dictionary = npc.find_friend_to_help()
	if result.is_empty():
		return
	_friend = result.get("friend")
	_loose = result.get("item")
	if not NPCItemUser.claim_item(_loose, npc):
		_friend = null
		_loose = null
		return
	npc.set_nav_target(_loose.global_position)

func tick(npc: NPC, delta: float) -> void:
	if _friend == null or not is_instance_valid(_friend):
		_friend = null
		_loose = null
		return

	if npc.held_item == null:
		## Fetch phase
		if _loose == null or not is_instance_valid(_loose):
			_friend = null
			_loose = null
			return
		if "is_held" in _loose and _loose.is_held:
			NPCItemUser.release_item(_loose)
			_friend = null
			_loose = null
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.grab_loose(npc, _loose):
				_loose = null   ## fetched — travel phase starts next tick
			else:
				NPCItemUser.release_item(_loose)
				_friend = null
				_loose = null
		return

	## Travel phase — friend may have moved, or no longer needs it
	if not (float(_friend.hunger) < 90.0 or float(_friend.thirst) < 90.0):
		_friend = null   ## already fed some other way — no longer needed
		return
	npc.set_nav_target((_friend as Node3D).global_position)
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_friend as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
		if _friend.has_method("can_receive_item") and _friend.can_receive_item(npc.held_item, npc.npc_id):
			var item: Node = npc.held_item
			var friend_name: String = _friend.npc_name
			npc.held_item = null
			item.pickup((_friend as Node3D).hold_point)
			_friend.held_item = item
			_friend.on_item_given(item, npc.npc_id, npc.npc_name)
			npc.log_action("Gave %s to %s" % [item.get_display_name(), friend_name])
		_friend = null

func done(npc: NPC) -> bool:
	return _friend == null and _loose == null and npc.held_item == null

func exit(npc: NPC) -> void:
	if _loose != null:
		NPCItemUser.release_item(_loose)
		_loose = null
	if npc.held_item != null:
		## Interrupted mid-errand while actually carrying the item —
		## just let them keep it; they'll finish delivering (or eat it
		## themselves if truly needed) next time this activity re-enters,
		## since held_item persisting is harmless and re-searching from
		## scratch would waste a perfectly good fetched item.
		pass
	_friend = null