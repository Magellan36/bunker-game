extends NPCActivity
class_name PutAwayHeldItemActivity
## Aug 2026 — safety net for a held item left over with nothing
## actually using it. Concretely: _recover_from_stuck() can
## stop_current() a CleaningActivity that's already mid-carry (e.g.
## a second stuck event fires while still holding the item) —
## CleaningActivity.exit() only releases the item's CLAIM, since a
## claim release was always meant to mean "never picked it up," not
## "was holding it and gave up." Without this, that item stays in
## the NPC's hand through Wander/Relax/Sit/Lie/Talk indefinitely,
## since none of those have any concept of held items.
##
## Deliberately a flat, modest score — comfortably above Wander/
## Relax/Sit/Lie/Talk's own ranges plus the interrupt margin, but far
## below any activity with a genuine, real hold on the item (Drink/
## Eat/GiveToFriend/Cleaning/Refuel all score based on real urgency
## while they're the ones holding something, and none of those are
## ever _current at the same time this activity would be scored
## against them anyway — this only ever competes against activities
## that don't hold anything).
const SCORE: float = 20.0

var _item: RigidBody3D = null
var _destination: Node = null
var _settled: bool = false   ## delivered, dropped, or lost — done() flips true

func label() -> String:
	return "Putting away %s" % (_item.get_display_name() if _item != null and _item.has_method("get_display_name") else "an item")

func score(npc: NPC) -> float:
	return SCORE if npc.held_item != null else 0.0

func interruptible() -> bool:
	return false   ## short and self-contained — always let it finish rather than get preempted mid-delivery

func enter(npc: NPC) -> void:
	_item = npc.held_item
	_settled = false
	if _item == null or not is_instance_valid(_item):
		_settled = true
		return
	var is_trash: bool = NPCJobQueries.is_trash_item(npc, _item)
	_destination = NPCJobQueries.find_cleaning_destination(npc, is_trash, _item)
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away held item", "%s -> %s" % [
			(_item.get_display_name() if _item.has_method("get_display_name") else str(_item.name)),
			(_destination.name if _destination != null else "(no destination — dropping in place)")])
	if _destination == null:
		NPCItemUser.drop_held(npc)
		npc.velocity = Vector3.ZERO   ## Aug 2026 — don't leave the NPC coasting in whatever direction it was last walking
		_settled = true
		return
	npc.set_nav_target((_destination as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _settled:
		return
	if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
		_settled = true   ## lost it somehow (dropped elsewhere, freed) — nothing left to do
		return
	if _destination == null or not is_instance_valid(_destination):
		NPCItemUser.drop_held(npc)
		npc.velocity = Vector3.ZERO   ## Aug 2026 — same as enter()'s drop branch
		_settled = true
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
		## Aug 2026 fix — same root cause as CleaningActivity's matching
		## fix: npc_deposit_trash() was never defined anywhere, so the
		## is_trash branch here could never succeed and always fell
		## through to dropping the item on the ground right next to
		## whatever destination it had just walked to — which is what
		## actually broke the loop each time (drop_held() does clear
		## npc.held_item), just onto the floor instead of into the can,
		## so a fresh Cleaning session immediately found the same loose
		## item again. npc_try_place_item() already works correctly for
		## both cases — no is_trash branching needed here at all now.
		var item_name: String = _item.get_display_name() if _item.has_method("get_display_name") else "an item"
		if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
			## Aug 2026 — this activity never logged its actual outcome
			## before, only the initial "heading to X" line in enter() —
			## meaning a silent failure here (the exact shape the trash
			## bug took) had no log trace at all on this side.
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "put away delivered", "%s stored in %s (held_item_after=%s)" % [
					item_name, _destination.name,
					(npc.held_item.get_display_name() if npc.held_item != null and npc.held_item.has_method("get_display_name") else "none")])
		else:
			NPCItemUser.drop_held(npc)   ## destination filled/changed since the initial check — just set it down rather than loop
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "put away failed", "%s dropped on the ground — %s had no room" % [item_name, _destination.name])
		_settled = true

func done(_npc: NPC) -> bool:
	return _settled

func exit(_npc: NPC) -> void:
	pass   ## nothing claimed via NPCItemUser — this only ever acts on what's already physically held, never a JobBoard/claim-tracked target
