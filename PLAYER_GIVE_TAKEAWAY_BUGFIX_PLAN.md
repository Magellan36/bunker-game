# Bugfix Plan: Give Item Stuck + Takeaway Not Working (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** NPC subsystem bugfix handoff
(`PLAYER_SUBSYSTEM_BUGFIX_GIVE_TAKEAWAY.md`), verified against the
current on-disk state of `scripts/player/InteractionSystem.gd` and
`scenes/player/Player.tscn` on 2026-08-04 — every anchor below matches
exactly what's currently on disk, so this is a direct diff, not a
reconstruction.
**Files touched:** `scripts/player/InteractionSystem.gd`,
`scenes/player/Player.tscn`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## Bug 1: Give leaves multi-charge items stuck

**Root cause (confirmed against current code):** `_try_give_to_nearest_npc()`
unconditionally clears `held_item`/`_held_from_slot`/`_is_holding_e` after
a successful `receive_item_from_player()` call. That's correct for
single-serving items (Dish/Produce — destroyed inside that call), but
wrong for FoodCan/WaterBottle, which survive the call untouched
(`is_held` stays true, item stays glued to `hold_point`). Clearing the
player's own bookkeeping in that case desyncs "what the player thinks
they're holding" (nothing) from "what's actually still attached"
(the can/bottle) — every other action (drop/store/use) checks
`held_item`, sees null, and does nothing, while the object just sits
there stuck.

**Anchor:** verified current lines 830–840.

```gdscript
old_str:
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("receive_item_from_player"):
		return
	if not target.receive_item_from_player(item):
		return
	if item.knocked_out.is_connected(_on_item_knocked_out):
		item.knocked_out.disconnect(_on_item_knocked_out)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

new_str:
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("receive_item_from_player"):
		return
	if not target.receive_item_from_player(item):
		return
	## Single-serving items (Dish/Produce) are destroyed inside
	## receive_item_from_player() — consume_as_food() frees the node.
	## Multi-charge items (can/bottle) persist and are STILL correctly
	## held by the player (is_held/hold_point tracking untouched by that
	## call) — only clear our own bookkeeping in the destroyed case.
	## Clearing it unconditionally was the bug: it desynced held_item
	## (null) from the surviving item's own is_held (still true), leaving
	## a can/bottle visually stuck in the player's hand but undroppable/
	## unstorable/unusable since every other action checks held_item,
	## which had already gone null.
	if not is_instance_valid(item):
		return
	if item.is_in_group("__never_true__"):
		pass
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false
```

**Correction to the NPC subsystem's own snippet:** their proposed
replacement checks `is_instance_valid(item)` but then only does the
disconnect+clear *inside* that same "if invalid" branch — which can
never execute, since `is_instance_valid()` on an already-freed node
returns false and you can't touch `item.knocked_out` on a freed node at
all. Use this instead (the actual correct fix — check validity first,
branch on it correctly, and keep the disconnect where it can safely
run):

```gdscript
new_str (use this instead of the block above):
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("receive_item_from_player"):
		return
	if not target.receive_item_from_player(item):
		return
	## Single-serving items (Dish/Produce) are destroyed inside
	## receive_item_from_player() — consume_as_food() frees the node, so
	## is_instance_valid(item) is false here and there is nothing left to
	## clean up on the item itself. Multi-charge items (can/bottle)
	## persist and are STILL correctly held by the player (is_held/
	## hold_point tracking untouched by that call) — only clear our own
	## bookkeeping in the destroyed case. Clearing it unconditionally was
	## the bug: it desynced held_item (null) from a surviving item's own
	## is_held (still true), leaving a can/bottle visually stuck in the
	## player's hand but undroppable/unstorable/unusable since every
	## other action checks held_item, which had already gone null.
	if is_instance_valid(item):
		return
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false
```

**Coding agent: apply the second `new_str` block above (the corrected
version), not the first.** The disconnect-from-`knocked_out` line is
dropped entirely here because it's unreachable in the only case that
matters (item destroyed → node freed → can't touch its signals) and
unnecessary in the surviving case (item never left `held_item`, so its
`knocked_out` connection should stay exactly as it already is).

---

## Bug 2: Takeaway doesn't work at all

**Root cause (confirmed against current code):** `PickupableItem.pickup()`
sets `collision_layer = 2` on hold, `drop()`/`place()` set it back to 1.
`scenes/player/Player.tscn`'s `DetectArea` node has `collision_layer = 0`
and **no `collision_mask` line at all**, so it defaults to Godot's
default mask (`1`) — it has only ever been able to detect layer-1
(world/dropped) bodies. Layer-2 (currently NPC-held) items were never in
`detect_area.get_overlapping_bodies()`'s result set, so the earlier
GDScript-level `is_held` removals (in `_try_pickup()` and the CASE 2
prompt loop) were necessary but not sufficient — this is the actual gate,
upstream of any GDScript logic.

**Anchor:** verified current `scenes/player/Player.tscn` lines 42–44.

```
old_str:
[node name="DetectArea" type="Area3D" parent="InteractionSystem" unique_id=1188015658]
collision_layer = 0

new_str:
[node name="DetectArea" type="Area3D" parent="InteractionSystem" unique_id=1188015658]
collision_layer = 0
collision_mask = 3
```

`3` = layer 1 | layer 2 (bits 1 and 2 combined). This only widens what
`DetectArea` can *see* via its `Area3D` overlap query/signals — it does
not change physical collision response, so held items will not start
pushing against anything or behaving differently physically.

### Defensive follow-up — guard against self-detection while holding

Once `DetectArea` can see layer-2 bodies, it can also see the player's
own currently-held item (also layer 2) while CASE 1 code scans
`detect_area.get_overlapping_bodies()` for a *different* item. Only two
functions do that scan while `held_item != null`:
`_try_add_nearest_to_basket()` and `_try_add_nearest_to_cookpot()`. Add a
cheap guard to both.

**Anchor 1 — `_try_add_nearest_to_basket()`, verified current lines
705–711:**

```gdscript
old_str:
func _try_add_nearest_to_basket(basket: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("basket_storable"):

new_str:
func _try_add_nearest_to_basket(basket: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("basket_storable"):
```

**Anchor 2 — `_try_add_nearest_to_cookpot()`, verified current lines
750–756:**

```gdscript
old_str:
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("cookpot_storable"):

new_str:
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("cookpot_storable"):
```

**No change needed elsewhere:** `_try_pickup()`, `_nearest_pickup_distance()`,
and the CASE 2 prompt loop only ever run while `held_item == null`
(already verified in the original Give/Takeaway plan), so there's no
self-detection risk in any of those three — the mask widening is
strictly additive for them.

---

## Verification checklist

1. **Give — single-serving:** give a dish or produce item to an NPC —
   destroyed/gone from the player's hand, as before.
2. **Give — multi-charge (the actual bug):** give a food can or water
   bottle to an NPC — stays in the player's hand afterward with reduced
   charge, and remains fully interactive: droppable, storable in a
   shelf/basket, usable (E to take a bite/drink), give-able again.
3. **Takeaway — consumption:** get an NPC eating/drinking (F7 admin tools
   to drop hunger/thirst below trigger threshold if needed). Mid-
   consumption, walk up and press F — `[F] Pick up` prompt appears and
   works, item transfers, no console errors.
4. **Takeaway — job material:** an NPC mid-REFUEL or mid-REPLACE_FILTER
   is also takeable via F with no errors (job silently doesn't complete —
   known/accepted NPC-side behavior).
5. **Self-detection regression:** while holding a basket or cooking pot,
   confirm "add nearest item" still works correctly and never treats the
   basket/pot itself as a target.
6. **General regression:** normal (non-NPC) pickup, shelf/stove/interact
   prompts, and knockout-distance handling for held items all behave
   exactly as before — the mask widening is additive only.

---

## Documentation updates (apply alongside the code changes above)

### `docs/systems/player/README.md`

Append to the existing "NPC Give/Takeaway support (Aug 2026)" Common-edits
entry (added in the prior plan) — do not duplicate the whole entry, just
add this as a follow-up paragraph directly beneath it:

```markdown
  **Bugfix follow-up (Aug 2026):** two gaps in the original spec, both
  fixed. (1) `_try_give_to_nearest_npc()` was clearing `held_item` even
  when the given item survives the call (FoodCan/WaterBottle aren't
  destroyed by `receive_item_from_player()`, only Dish/Produce are) —
  now only clears bookkeeping when `is_instance_valid(item)` is false.
  (2) Takeaway was silently unreachable — `DetectArea` (`Player.tscn`)
  had no explicit `collision_mask` and defaulted to layer 1 only, so it
  could never see layer-2 (currently-held) bodies regardless of any
  GDScript `is_held` check; `collision_mask` widened to `3` (1|2) fixes
  this. Widening the mask also means `DetectArea` now sees the player's
  own held item while CASE 1 scans for a different target — guarded with
  `if body == held_item: continue` in `_try_add_nearest_to_basket()` and
  `_try_add_nearest_to_cookpot()`.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Give/Takeaway Bugfixes: Stuck Item + Undetectable NPC-Held Items (Aug 2026)

## What changed this session
Fixed two bugs reported after the initial Give/Takeaway implementation.

**Give stuck bug:** `_try_give_to_nearest_npc()` cleared the player's
`held_item`/bookkeeping unconditionally after a successful give, but
`receive_item_from_player()` only destroys single-serving items
(Dish/Produce) — FoodCan/WaterBottle survive with reduced charge, still
fully held. Clearing bookkeeping regardless left surviving cans/bottles
visually stuck (undroppable/unstorable/unusable, since every other
action gates on `held_item`). Fixed to only clear bookkeeping when
`is_instance_valid(item)` is false (i.e. it was actually destroyed).

**Takeaway silently broken:** root cause was a physics layer issue, not
GDScript logic. `PickupableItem.pickup()` sets `collision_layer = 2`
while held; `Player.tscn`'s `DetectArea` had no explicit
`collision_mask` and defaulted to layer 1 only, so it could never detect
NPC-held (layer 2) items regardless of the earlier `is_held` check
removals. Widened `DetectArea.collision_mask` to `3` (layer 1 | 2).
Added `body == held_item` self-detection guards to
`_try_add_nearest_to_basket()`/`_try_add_nearest_to cookpot()` since the
wider mask means the player's own held item is now visible to those
scans too.

### Files modified
- `scripts/player/InteractionSystem.gd` — `_try_give_to_nearest_npc()`
  conditional bookkeeping clear; self-detection guards in
  `_try_add_nearest_to_basket()`/`_try_add_nearest_to_cookpot()`.
- `scenes/player/Player.tscn` — `DetectArea.collision_mask = 3`.
- `docs/systems/player/README.md` — bugfix follow-up appended to the
  existing NPC Give/Takeaway entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_BUGFIX_PLAN.md` for the
full 6-item checklist)
```
