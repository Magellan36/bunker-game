# Implementation Plan: NPC Give/Takeaway Support in InteractionSystem.gd

**Owner:** Player subsystem (this plan)
**Source:** Consolidated handoff from NPC subsystem
(`PLAYER_SUBSYSTEM_HANDOFF_GIVE_TAKEAWAY.md`), verified against the
current on-disk state of `scripts/player/InteractionSystem.gd` on
2026-08-04.
**File touched:** `scripts/player/InteractionSystem.gd` only.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md` (both
updated as part of this plan, per standing instruction — see bottom).

---

## ⚠️ BLOCKING PREREQUISITE — read before applying anything

This plan's code calls four methods that **do not yet exist anywhere in
the repo**:

- `NPCItemUser.is_giveable(item)` — not present in
  `scripts/npc/NPCItemUser.gd` (verified by direct read, 2026-08-04).
- `NPCItemUser.find_holder(item, tree)` — not present.
- `NPC.receive_item_from_player(item)` — not present in `scripts/npc/NPC.gd`.
- `NPC.on_item_taken_by_player()` — not present.

The NPC subsystem's handoff doc describes these as "already implemented
per my plans," but that means implemented **in that Claude instance's own
plan documents**, not yet executed on disk — no coding-agent run has
applied them yet. `NPCItemUser.gd` as it stands today only has the
claim/carry/consume helpers (`claim_item`, `grab_loose`, `is_edible`,
`is_drinkable_bottle`, etc.) — none of the four Give/Takeaway contract
methods.

**Brannon: this plan is safe to hand to the coding agent, but it must be
applied together with (or after) whichever NPC-subsystem plan actually
adds those four methods to `NPC.gd`/`NPCItemUser.gd`.** If this plan runs
first in isolation, the game will fail to compile (`is_giveable` etc.
will be unresolved identifiers). Please confirm the NPC-side plan is
queued before/alongside this one, or let me know if you'd like me to
hold this plan until it's confirmed applied.

Everything below assumes those four methods will exist with the exact
signatures the NPC handoff doc specifies.

---

## Change 1 — Give prompt (CASE 1, held-item prompt builder)

**File:** `scripts/player/InteractionSystem.gd`
**Anchor:** insert immediately after the Cooking Pot prompt block, before
the `if entries.is_empty():` line that closes CASE 1. Verified current
line numbers: insert between line 506 (`entries.append({...})` closing
the stove-prompt append) and line 508 (`if entries.is_empty():`).

```gdscript
old_str:
			entries.append({
					"text":      "[E] Place Cooking Pot",
					"world_pos": (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0),
					"dist":      0.0
				})

		if entries.is_empty():

new_str:
			entries.append({
					"text":      "[E] Place Cooking Pot",
					"world_pos": (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0),
					"dist":      0.0
				})

		# Give to NPC — holding a giveable item (dish, produce, can, or
		# bottle) → "[E] Give <item> to <name>" over each nearby NPC.
		# Mirrors the basket/cookpot blocks above exactly.
		if NPCItemUser.is_giveable(held_item):
			for npc: Node in get_tree().get_nodes_in_group("npc"):
				if not is_instance_valid(npc):
					continue
				var nd: float = (npc as Node3D).global_position.distance_to(player.global_position)
				if nd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Give %s to %s" % [held_item.get_display_name(), String(npc.npc_name)],
					"world_pos": (npc as Node3D).global_position + Vector3(0.0, 1.8, 0.0),
					"dist":      nd
				})

		if entries.is_empty():
```

Note for the coding agent: match indentation exactly to the surrounding
block (tabs, same depth as the `if "is_cookpot_container" in held_item:`
body).

---

## Change 2 — E-key dispatch (Give takes priority over normal item use)

**File:** `scripts/player/InteractionSystem.gd`
**Anchor:** insert between the existing Cooking Pot dispatch block and
the generic `if held_item != null:` fallback. Verified current lines
185–189.

```gdscript
old_str:
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:

new_str:
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable item held + an NPC in range → E gives it instead of
		## normal item use.
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
```

---

## Change 3 — New helper functions

**File:** `scripts/player/InteractionSystem.gd`
**Anchor:** insert after `_find_nearest_stove_with_pot()` ends, before
the `_try_pickup_pot_from_stove()` doc comment. Verified current lines
790–792.

```gdscript
old_str:
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot

new_str:
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Same group-scan/range reasoning as _find_nearest_open_stove(), reused
## by both the Give prompt (Change 1) and its dispatch (Change 2).
func _find_nearest_npc() -> Node:
	var closest: Node       = null
	var closest_dist: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Give dispatch. NPC.receive_item_from_player() may free `item`
## internally (single-serving items are consumed and destroyed on the
## spot) — do not touch `item` after a true return, same caution this
## file already applies around consume_as_food()-adjacent calls elsewhere.
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

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot
```

**Item lifetime note (no code follows from this, just context for
review):** for multi-charge items (FoodCan/WaterBottle),
`receive_item_from_player()` does not free the item — it stays in the
player's hand with reduced charge. For single-serving items
(Dish/Produce) it is destroyed internally. `_try_give_to_nearest_npc()`
doesn't need to distinguish the two cases — it just avoids touching
`item` after a true return, since it can't know from this side which
happened.

---

## Change 4 — Takeaway: remove `is_held` exclusion from CASE 2 prompt loop

**File:** `scripts/player/InteractionSystem.gd`
**Anchor:** verified current lines 533–539.

```gdscript
old_str:
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		# Currently held — Case 1 handles it
		if "is_held" in body and body.is_held:
			continue
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue

new_str:
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue
```

Reasoning (context for the coding agent, not to be added as a comment):
CASE 2 only ever runs while the player's own `held_item` is null, so any
`is_held == true` body reached here can only belong to an NPC — deleting
this exclusion is what makes NPC-held items show a normal `[F] Pick up`
prompt.

---

## Change 5 — Takeaway: notify NPC on successful grab in `_try_pickup()`

**File:** `scripts/player/InteractionSystem.gd`
**Anchor:** verified current lines 984–1000.

```gdscript
old_str:
	if closest == null:
		return

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

new_str:
	if closest == null:
		return

	## NPC takeaway notification — look this up BEFORE reassigning
	## held_item below, since find_holder() checks each live NPC's own
	## held_item field for a match.
	var taken_from: Node = NPCItemUser.find_holder(closest, get_tree())

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

	if taken_from != null and taken_from.has_method("on_item_taken_by_player"):
		taken_from.on_item_taken_by_player()
```

**No change needed** to `_nearest_pickup_distance()` (lines 952–964) —
verified it has no `is_held` handling to remove; it stays consistent
with what `_try_pickup()` now actually grabs.

---

## Things this plan deliberately does NOT do

- Does not add any relationship/consequence logic — entirely internal to
  `NPC.gd`, not this file's concern.
- Does not add defensive handling for NPCBrain activities noticing a
  stolen item — `on_item_taken_by_player()` is the NPC-side signal for
  that; nothing further needed here.
- Does not gate Takeaway behind any new check — per the NPC handoff,
  "any held item is fair game" is intentional, and `_try_pickup()`
  already had no `is_held` gate of its own before this change.

---

## Verification checklist (for Brannon's in-editor test)

1. Confirm the NPC-side prerequisite methods (see blocking note above)
   are present before testing — otherwise the scene will fail to load.
2. Hold a dish/produce/can/bottle, walk up to an NPC — Give prompt
   appears with correct item name + NPC name; E transfers it
   (single-serving items vanish from hand; cans/bottles stay with
   reduced charge).
3. Hold a non-giveable item (e.g. Fuel Can) near an NPC — no Give prompt;
   E does its normal thing (or nothing, if Fuel Can has no `on_use`).
4. Watch an NPC pick up and start eating/drinking. Walk up mid-
   consumption, press F — normal `[F] Pick up` prompt/action works, no
   console errors.
5. Confirm a job-material item an NPC is carrying (mid-REFUEL, mid-
   REPLACE_FILTER) is also takeable via F with no errors — the job
   itself is expected to just quietly not complete (known/accepted
   NPC-side behavior, not a Player-subsystem bug).
6. Empty-handed CASE 2 prompts still behave correctly for every
   non-NPC-held interactable (regression check on Change 4 — nothing
   else should start double-prompting).

---

## Documentation updates (apply alongside the code changes above)

### `docs/systems/player/README.md`

Add a new dated entry under "Common edits" (after the existing "Prompt
cap + E-target fix (Jul 2026)" entry):

```markdown
- **NPC Give/Takeaway support (Aug 2026):** `InteractionSystem` gained a
  Give prompt/dispatch (CASE 1, mirrors the Basket/Cooking-Pot pattern —
  `NPCItemUser.is_giveable(held_item)` gates a `[E] Give <item> to
  <name>` prompt over each nearby NPC, `_find_nearest_npc()`/
  `_try_give_to_nearest_npc()` handle dispatch) and Takeaway (the CASE 2
  `is_held` exclusion was removed entirely — NPC-held items are now
  normal `[F] Pick up` targets, and `_try_pickup()` looks up
  `NPCItemUser.find_holder()` before reassigning `held_item` so it can
  call `on_item_taken_by_player()` on the NPC that lost the item). All
  relationship/consequence logic and item-lifetime handling (destroy vs.
  reduced-charge) is entirely owned by `NPC.gd`/`NPCItemUser.gd` on the
  NPC subsystem side — `InteractionSystem` just calls
  `receive_item_from_player()`/`on_item_taken_by_player()` and trusts the
  return value.
```

Update the "Non-responsibilities" section's `InventoryManager`/item-script
bullets are unaffected; no change needed there. Update the "Extension
points" section is also unaffected.

### `HANDOVER.md`

Add a new entry at the top of the file (above the current "Ghost
Collision Regression Fix" entry):

```markdown
# Handover — NPC Give/Takeaway Support in InteractionSystem.gd (Aug 2026)

## What changed this session
Player subsystem implemented the InteractionSystem.gd half of the NPC
Give/Takeaway feature, per a consolidated handoff from the NPC
subsystem. Give: holding a giveable item (dish/produce/can/bottle) near
an NPC shows `[E] Give <item> to <name>`; E calls
`NPC.receive_item_from_player()`. Takeaway: removed the CASE 2 `is_held`
prompt exclusion entirely (NPC-held items are now normal `[F] Pick up`
targets); `_try_pickup()` now looks up `NPCItemUser.find_holder()` before
reassigning `held_item` and calls `on_item_taken_by_player()` on the
losing NPC. All relationship/consequence/item-lifetime logic lives
NPC-side; this file only calls the contract methods and trusts their
return values.

### Files modified
- `scripts/player/InteractionSystem.gd` — Give prompt (CASE 1), Give
  dispatch (E-branch), `_find_nearest_npc()`/`_try_give_to_nearest_npc()`
  helpers, Takeaway `is_held` exclusion removed (CASE 2), Takeaway
  notify-on-grab in `_try_pickup()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_IMPLEMENTATION_PLAN.md`
for the full 6-item checklist)
```
