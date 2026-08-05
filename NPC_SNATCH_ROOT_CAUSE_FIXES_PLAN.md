# Snatch: Fix Scoring Blind Spot, Wrong Inventory Function, Grab Distance (Aug 2026)

Three separate, precisely diagnosed bugs. All in
`scripts/npc/NPCBrain.gd` and `scripts/npc/NPCItemUser.gd`, plus one
function fix in `scripts/player/InteractionSystem.gd`.

---

## Bug 1 — DrinkActivity/EatActivity never even get selected when the only matching item is in the player's hands

`score()` on both only returns nonzero if a *normal* world target exists
(`_pick_target()`/`_find()`). It has no idea snatching is even possible,
so if the player is holding the only bottle/food in the bunker, score()
returns 0, the activity never gets chosen by `_think()`, and `enter()` —
where the actual snatch attempt lives — never runs. This is why it just
wanders regardless of thirst/relationship.

### `scripts/npc/NPC.gd` — new deterministic (no roll) eligibility check

**Anchor:** immediately before `find_player_snatch_target()`.

Insert:

```gdscript
## Deterministic eligibility, no random roll — used by EatActivity/
## DrinkActivity's score() so they don't return 0 and get skipped
## entirely just because the player happens to be holding the only
## matching item in the bunker. The actual random roll only happens once
## the activity is entered, via find_player_snatch_target() below.
func is_player_snatch_eligible(need_filter: Callable) -> bool:
	if get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return false
	return need_filter.call(held)
```

### `scripts/npc/NPCBrain.gd` — both `score()` functions

**Anchor:** `EatActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty():
			return 0.0
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty() \
				and not npc.is_player_snatch_eligible(Callable(NPCItemUser, "is_edible")):
			return 0.0
```

**Anchor:** `DrinkActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if npc.thirst >= 55.0:
			return 0.0
		if _pick_target(npc).is_empty():
			return 0.0
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.thirst >= 55.0:
			return 0.0
		if _pick_target(npc).is_empty() \
				and not npc.is_player_snatch_eligible(Callable(NPCItemUser, "is_drinkable_bottle")):
			return 0.0
```

---

## Bug 2 — snatched item drops instead of transferring to the NPC

`InteractionSystem.release_held_item_to_npc()` calls
`inventory.remove_item(_held_from_slot, ...)`, which internally calls
`item.drop()` — unfreezing physics, enabling gravity, emitting `dropped`
— as an intermediate step before `item.pickup(npc.hold_point)` runs one
line later and overrides it. `InventoryManager.gd` already has exactly
the right function for this (`clear_slot()` — its own doc comment
literally says *"an NPC's own pickup() call already reassigned it —
Snatch"*), it just isn't being used at this call site.

### `scripts/player/InteractionSystem.gd`

**Anchor:** the current `release_held_item_to_npc()`:

```gdscript
func release_held_item_to_npc(npc: Node) -> bool:
	if held_item == null:
		return false
	if npc == null or not is_instance_valid(npc):
		return false
	if not ("hold_point" in npc) or not ("held_item" in npc):
		return false

	_is_holding_e = false
	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	if _held_from_slot != -1 and inventory != null:
		inventory.remove_item(_held_from_slot, held_item.global_position)

	var item: RigidBody3D = held_item
	held_item       = null
	_held_from_slot = -1
	_update_hud_selection()

	item.pickup(npc.hold_point)
	npc.held_item = item
	return true
```

Replace with:

```gdscript
func release_held_item_to_npc(npc: Node) -> bool:
	if held_item == null:
		return false
	if npc == null or not is_instance_valid(npc):
		return false
	if not ("hold_point" in npc) or not ("held_item" in npc):
		return false

	_is_holding_e = false
	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var item: RigidBody3D = held_item
	var slot: int = _held_from_slot
	held_item       = null
	_held_from_slot = -1

	## Physically transfer FIRST, then clear the slot — matches
	## clear_slot()'s own doc comment: it's meant to run AFTER an NPC's
	## pickup() has already reassigned the item, not before.
	## Deliberately clear_slot(), NOT remove_item() — remove_item() calls
	## item.drop() internally, which is the actual cause of the item
	## visibly dropping instead of transferring (it unfreezes physics/
	## enables gravity/emits `dropped` as an intermediate step, one line
	## before pickup() below would have overridden it anyway).
	item.pickup(npc.hold_point)
	npc.held_item = item

	if slot != -1 and inventory != null:
		inventory.clear_slot(slot)

	_update_hud_selection()
	return true
```

---

## Bug 3 — grab happens slightly too close, NPC bumps the player

**Anchor:** `NPCItemUser.gd`'s `PICKUP_RANGE` constant:

```gdscript
const PICKUP_RANGE: float = 1.2      ## must be this close to grab
```

Insert immediately after it:

```gdscript
## Snatch specifically needs more clearance than PICKUP_RANGE — that
## constant is tuned for loose items with near-zero collision footprint;
## the player has real collision geometry, so using the same tight
## distance walks the NPC into physical contact before the range check
## is satisfied.
const SNATCH_RANGE: float = 1.6
```

**Anchor:** `snatch_from_player()`'s range check:

```gdscript
	if flat_distance(npc.global_position, (player as Node3D).global_position) > PICKUP_RANGE:
		return false
```

Replace with:

```gdscript
	if flat_distance(npc.global_position, (player as Node3D).global_position) > SNATCH_RANGE:
		return false
```

### `scripts/npc/NPCBrain.gd` — `SnatchActivity`'s own distance check

**Anchor:** in `tick()`, the "still in the player's hands" branch:

```gdscript
				npc.nav_steer(delta)
				if NPCItemUser.flat_distance(npc.global_position, (_player as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
					if NPCItemUser.snatch_from_player(npc, _player):
```

Replace with:

```gdscript
				npc.nav_steer(delta)
				if NPCItemUser.flat_distance(npc.global_position, (_player as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
					if NPCItemUser.snatch_from_player(npc, _player):
```

(The "chase a dropped item on the floor" branch further down stays at
`PICKUP_RANGE` unchanged — that's a normal `grab_loose()` call against a
loose item with no collision body of its own, not the player.)

---

## Testing

1. Repeat your exact scenario: player holds the only water bottle, an
   NPC at -100 relationship with 0 thirst, standing still. Confirm the
   NPC now actually enters "Getting water"/pursues within a few seconds
   rather than wandering — debug log should show roll attempts, not
   silence.
2. Confirm a successful snatch now results in the item visibly
   transferring to and staying in the NPC's hand (followed by the normal
   ~2s "Drinking"/"Eating" hold), not falling to the floor.
3. Confirm the NPC now stops at a small but clearly visible gap before
   grabbing, rather than making contact with the player.
