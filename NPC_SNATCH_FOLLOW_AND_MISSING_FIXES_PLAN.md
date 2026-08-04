# Re-apply Dropped Fixes + Continuous Snatch Pursuit (Aug 2026)

All changes in `scripts/npc/NPCItemUser.gd` and `scripts/npc/NPCBrain.gd`
and `scripts/npc/NPC.gd`. No Player-side changes.

## Part A — grab_loose() guard + early-abort (re-applying; confirmed missing from the live file)

### 1. `scripts/npc/NPCItemUser.gd`

**Anchor:** the current `grab_loose()`:

```gdscript
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	if flat_distance(npc.global_position, item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false
```

Replace with:

```gdscript
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	## The actual missing guard: an item claimed by this NPC can still
	## have been physically picked up by the player between the claim and
	## now. Claims only block other NPCs' claim_item() calls; they were
	## never consulted by the player's own pickup path.
	if "is_held" in item and item.is_held:
		return false
	if flat_distance(npc.global_position, item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false
```

### 2. `scripts/npc/NPCBrain.gd` — three early-abort additions

**Anchor:** `EatActivity.tick()`'s `_loose` branch:

```gdscript
		if _loose != null and is_instance_valid(_loose):
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= USE_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null
			return
		_loose = null
```

Replace with:

```gdscript
		if _loose != null and is_instance_valid(_loose):
			if "is_held" in _loose and _loose.is_held:
				NPCItemUser.release_item(_loose)
				_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= USE_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null
				else:
					NPCItemUser.release_item(_loose)
					_loose = null
			return
		_loose = null
```

**Anchor:** `DrinkActivity._tick_bottle()`:

```gdscript
	func _tick_bottle(npc: NPC, delta: float) -> void:
		if _drinking > 0.0:
			npc.halt_movement(delta)
			_drinking -= delta
			if _drinking <= 0.0:
				_finish_bottle(npc)
			return
		if npc.held_item == _target:
			## Grabbed — start the visible holding/drinking wait.
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see 3b note)
			_drinking = CONSUME_TIME
			return
		npc.nav_steer(delta)
```

Replace with:

```gdscript
	func _tick_bottle(npc: NPC, delta: float) -> void:
		if _drinking > 0.0:
			npc.halt_movement(delta)
			_drinking -= delta
			if _drinking <= 0.0:
				_finish_bottle(npc)
			return
		if npc.held_item == _target:
			## Grabbed — start the visible holding/drinking wait.
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see 3b note)
			_drinking = CONSUME_TIME
			return
		if "is_held" in _target and _target.is_held:
			NPCItemUser.release_item(_target)
			_target = null
			return
		npc.nav_steer(delta)
```

**Anchor:** `JobActivity._tick_fetch()`:

```gdscript
	func _tick_fetch(npc: NPC, delta: float) -> void:
		if npc.held_item != null:
			_start_travel(npc)
			return
		if _fetch_loose != null and is_instance_valid(_fetch_loose):
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) \
					<= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _fetch_loose):
					_start_travel(npc)
				else:
					_fetch_loose = null
			return
```

Replace with:

```gdscript
	func _tick_fetch(npc: NPC, delta: float) -> void:
		if npc.held_item != null:
			_start_travel(npc)
			return
		if _fetch_loose != null and is_instance_valid(_fetch_loose):
			if "is_held" in _fetch_loose and _fetch_loose.is_held:
				_fetch_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) \
					<= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _fetch_loose):
					_start_travel(npc)
				else:
					_fetch_loose = null
			return
```

---

## Part B — SnatchActivity: chase the player continuously, chase a dropped item, give up cleanly

**Anchor:** the entire current `SnatchActivity` class — replace it in full
with:

```gdscript
class SnatchActivity extends NPCActivity:
	## Player Relationship Snatch. Dedicated, non-interruptible activity,
	## entered via force_command(), never scored/auto-selected.
	##
	## Continuously re-aims at the player every tick while the item is
	## still in their hands — the previous version only set the nav
	## target once, at enter(), so it just walked to wherever the player
	## happened to be standing when the attempt started and never
	## adjusted if they moved.
	##
	## If the player drops the tracked item (still that same item, now
	## loose) rather than putting it away/using it/giving it away, this
	## switches to chasing the dropped item on the ground instead of
	## giving up.
	##
	## MAX_CHASE_TIME is a safety valve I added beyond what was asked —
	## without it, a player who simply keeps walking away would leave
	## this NPC stuck chasing forever (interruptible() is false, so
	## nothing else could ever interrupt it either). Remove this if
	## indefinite pursuit is actually what you want.
	const MAX_CHASE_TIME: float = 20.0

	var _player: Node = null
	var _need_filter: Callable
	var _is_edible: bool = false
	var _handoff: NPCActivity = null
	var _outcome_label: String = "Hostile"
	var _tracked_item: Node = null
	var _chase_timer: float = 0.0

	func _init(player: Node, need_filter: Callable, is_edible: bool) -> void:
		_player = player
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
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		_tracked_item = _player.get_held_item() if _player != null and _player.has_method("get_held_item") else null
		if _player != null and is_instance_valid(_player):
			npc.set_nav_target((_player as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		_chase_timer += delta
		if _chase_timer > MAX_CHASE_TIME:
			NPCDebug.log_snatch(npc, "aborted", "gave up after %.0fs of pursuit" % MAX_CHASE_TIME)
			_player = null
			_tracked_item = null
			return

		## Still in the player's hands — chase the player, re-aiming every
		## tick since they can move.
		if _player != null and is_instance_valid(_player):
			var held: Node = _player.get_held_item() if _player.has_method("get_held_item") else null
			if held != null and is_instance_valid(held) and _need_filter.call(held):
				_tracked_item = held
				npc.set_nav_target((_player as Node3D).global_position)
				npc.nav_steer(delta)
				if NPCItemUser.flat_distance(npc.global_position, (_player as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
					if NPCItemUser.snatch_from_player(npc, _player):
						NPCDebug.log_snatch(npc, "success", "grabbed item from player's hands, handing off to consume")
						_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
						_outcome_label = "Snatched!"
						_player = null
						_tracked_item = null
					## else: still out of range this frame — keep chasing, no abort
				return

		## Player no longer holding a matching item. If it's the SAME item
		## we were tracking and it's now loose nearby (dropped, not used/
		## stored/given away), chase it down on the ground instead of
		## giving up.
		if _tracked_item != null and is_instance_valid(_tracked_item) \
				and "is_held" in _tracked_item and not _tracked_item.is_held \
				and _need_filter.call(_tracked_item):
			npc.set_nav_target((_tracked_item as Node3D).global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_tracked_item as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _tracked_item):
					NPCDebug.log_snatch(npc, "success", "picked up the dropped item, handing off to consume")
					_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
					_outcome_label = "Snatched!"
				else:
					NPCDebug.log_snatch(npc, "failed", "dropped item grab rejected at range")
				_tracked_item = null
				_player = null
			return

		NPCDebug.log_snatch(npc, "aborted", "item is gone — not held by the player, not sitting loose nearby")
		_tracked_item = null
		_player = null

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func done(npc: NPC) -> bool:
		return _player == null and _tracked_item == null and _handoff == null

	func exit(_npc: NPC) -> void:
		_player = null
		_tracked_item = null
		_handoff = null
```

---

## Part C — `NPC.gd`: make the decision path visible

**Anchor:** the current `find_player_snatch_target()`:

```gdscript
func find_player_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	if not forced and get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		return null
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return null
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return null
	if not need_filter.call(held):
		return null
	if not forced and randf() > get_snatch_chance():
		return null
	return player
```

Replace with:

```gdscript
func find_player_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	if not forced and get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "relationship %.1f is above threshold %.1f" \
				% [get_relationship("player"), SNATCH_RELATIONSHIP_THRESHOLD])
		return null
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return null
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "player isn't holding anything")
		return null
	if not need_filter.call(held):
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "not considered", "player is holding something, but not a matching type")
		return null
	if not forced:
		var chance: float = get_snatch_chance()
		var roll: float = randf()
		if roll > chance:
			if NPCDebug.enabled:
				NPCDebug.log_snatch(self, "roll failed", "chance=%.2f roll=%.2f" % [chance, roll])
			return null
		if NPCDebug.enabled:
			NPCDebug.log_snatch(self, "roll succeeded", "chance=%.2f roll=%.2f" % [chance, roll])
	return player
```

---

## Testing

1. Repeat the "NPC pathing to an item, player grabs it first" test —
   confirm the NPC now visibly gives up (or grabs something else) well
   before reaching the item's last position, not after.
2. With debug logging on, drain an NPC's need and hold a matching item
   at a fine relationship — confirm the console explicitly shows "not
   considered" every search, with the actual reason, instead of nothing.
3. Push relationship to -60 or below (F7), drain the matching need, hold
   the item, stay still — confirm you now see roll attempts logged, and
   eventually a "roll succeeded" leading to a real chase.
4. Once a snatch attempt starts, walk away — confirm the NPC keeps
   adjusting course toward your CURRENT position, not a fixed point.
5. Drop the tracked item mid-chase instead of stowing it — confirm the
   NPC switches to walking to the dropped item and picks it up rather
   than giving up.
6. Keep running from a chasing NPC for over 20 seconds — confirm it
   eventually gives up cleanly (logged) rather than following forever.
