extends NPCActivity
class_name SnatchActivity
## Relationship Snatch — player or another NPC (Aug 2026), target-
## force_command(), never scored/auto-selected.
##
## Continuously re-aims at the target every tick while the item is
## still in their hands — the previous version only set the nav
## target once, at enter(), so it just walked to wherever the player
## happened to be standing when the attempt started and never
## adjusted if they moved.
##
## If the target drops the tracked item (still that same item, now
## loose) rather than putting it away/using it/giving it away, this
## switches to chasing the dropped item on the ground instead of
## giving up.
##
## MAX_CHASE_TIME is a safety valve beyond what was asked —
## without it, a victim who simply keeps walking away would leave
## this NPC stuck chasing forever (interruptible() is false, so
## nothing else could ever interrupt it either). Remove this if
## indefinite pursuit is actually what you want.
const MAX_CHASE_TIME: float = 20.0

var _target: Node = null
var _need_filter: Callable
var _is_edible: bool = false
var _handoff: NPCActivity = null
var _outcome_label: String = "Hostile"
var _tracked_item: Node = null
var _chase_timer: float = 0.0

func _init(target: Node, need_filter: Callable, is_edible: bool) -> void:
	_target = target
	_need_filter = need_filter
	_is_edible = is_edible

func label() -> String:
	return _outcome_label

func score(_npc: NPC) -> float:
	return 0.0

func interruptible() -> bool:
	return false

func enter(npc: NPC) -> void:
	NPCDebug.log_snatch(npc, "started",
		"targeting %s, relationship=%.1f" % [
			"player" if _target != null and _target.is_in_group("player") else (_target.npc_name if _target != null and ("npc_name" in _target) else "unknown"),
			npc.get_relationship("player" if _target != null and _target.is_in_group("player") else (_target.npc_id if _target != null and "npc_id" in _target else "player"))])
	if npc.has_method("start_hostile_log"):
		npc.start_hostile_log()
	_tracked_item = _target.get_held_item() if _target != null and _target.has_method("get_held_item") else null
	if _target != null and is_instance_valid(_target):
		npc.set_nav_target((_target as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	_chase_timer += delta
	if _target != null and is_instance_valid(_target):
		var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
		if npc.has_method("start_snatch_cooldown_against"):
			npc.start_snatch_cooldown_against(target_id)
		if npc.has_method("update_hostile_log"):
			npc.update_hostile_log()
		if not _target.is_in_group("player"):
			if npc.has_method("start_npc_snatch_pair_cooldown"):
				npc.start_npc_snatch_pair_cooldown(target_id)
			if _target.has_method("start_npc_snatch_pair_cooldown"):
				_target.start_npc_snatch_pair_cooldown(npc.npc_id)   ## bidirectional
	if _chase_timer > MAX_CHASE_TIME:
		NPCDebug.log_snatch(npc, "aborted", "gave up after %.0fs of pursuit" % MAX_CHASE_TIME)
		_target = null
		_tracked_item = null
		return

	## Still in the target's hands — chase them, re-aiming every
	## tick since they can move.
	if _target != null and is_instance_valid(_target):
		var held: Node = _target.get_held_item() if _target.has_method("get_held_item") else null
		if held != null and is_instance_valid(held) and _need_filter.call(held):
			_tracked_item = held
			npc.set_nav_target((_target as Node3D).global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
				if NPCItemUser.snatch_from(npc, _target):
					NPCDebug.log_snatch(npc, "success", "grabbed item, handing off to consume")
					var target_desc: String = "the player" if _target.is_in_group("player") else _target.npc_name
					npc.log_action("Snatched an item from %s" % target_desc)
					_handoff = GivenEatActivity.new() if _is_edible else GivenDrinkActivity.new()
					_outcome_label = "Snatched!"
					_target = null
					_tracked_item = null
				## else: still out of range this frame — keep chasing, no abort
			return

	## Target no longer holding a matching item. If it's the SAME item
	## we were tracking and it's now loose nearby (dropped, not used/
	## stored/given away), chase it down on the ground instead of
	## giving up.
	## Only chase it if it's GENUINELY loose in the world
	## (collision_layer 1, set by an actual drop) — not just
	## "not is_held", which is also true for an item the target
	## swapped away to a different inventory slot (deactivate_item()
	## sets is_held=false too, but leaves it frozen/hidden in
	## storage, collision_layer 0). Without this distinction the NPC
	## would walk to the stored item's stale last position and grab
	## it straight out of the inventory slot array.
	if _tracked_item != null and is_instance_valid(_tracked_item) \
			and "is_held" in _tracked_item and not _tracked_item.is_held \
			and "collision_layer" in _tracked_item and _tracked_item.collision_layer == 1 \
			and _need_filter.call(_tracked_item):
		npc.set_nav_target((_tracked_item as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_tracked_item as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.grab_loose(npc, _tracked_item):
				NPCDebug.log_snatch(npc, "success", "picked up the dropped item, handing off to consume")
				_handoff = GivenEatActivity.new() if _is_edible else GivenDrinkActivity.new()
				_outcome_label = "Snatched!"
			else:
				NPCDebug.log_snatch(npc, "failed", "dropped item grab rejected at range")
			_tracked_item = null
			_target = null
		return

	NPCDebug.log_snatch(npc, "aborted", "item is gone — not held by the target, not sitting loose nearby")
	_tracked_item = null
	_target = null

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func done(npc: NPC) -> bool:
	return _target == null and _tracked_item == null and _handoff == null

func exit(npc: NPC) -> void:
	if npc.has_method("end_hostile_log"):
		npc.end_hostile_log()
	_target = null
	_tracked_item = null
	_handoff = null