# Bugfix Plan: Give/Snatch Leave the Item in the Inventory List (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** NPC subsystem bug report
(`PLAYER_SUBSYSTEM_INVENTORY_CLEAR_FIX.md`), verified against the
current on-disk state of `scripts/player/InteractionSystem.gd` and
`scripts/ui/inventory/InventoryManager.gd` on 2026-08-04.
**Files touched:** `scripts/player/InteractionSystem.gd`,
`scripts/ui/inventory/InventoryManager.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

**Coordination note:** `InventoryManager.gd` lives under
`scripts/ui/inventory/` and is UI/menu-subsystem-owned territory, not
mine. The change below is a single small, additive, non-breaking method
(no existing method touched) needed to correctly fix a Player-subsystem
bug, so I'm including it in this plan rather than bouncing it back and
forth — but flagging it here in case the UI/menu thread wants visibility
into it landing in their file.

---

## Root cause — confirmed, and one correction to the reported diagnosis

The NPC subsystem correctly diagnosed *that* the wrong cleanup path is
being used (a bare `held_item = null` / `_held_from_slot = -1` never
touches `inventory.slots[]`, so the slot keeps showing the item forever).
Confirmed against the actual code — `_try_give_to_nearest_npc()` and
`clear_held_item_external()` (added for Snatch) both do exactly this.

**However, their proposed fix — routing through `inventory.remove_item()`
— is itself unsafe for both call sites it's meant to fix, for two
different reasons. Do not use `remove_item()` here.** I checked
`InventoryManager.gd` directly:

```gdscript
# ─── Retrieve (removes from slot — use for world-drop only) ──────────────────
## Remove item from slot entirely and restore world state.
## Use only when dropping to the world, not when bringing to hand.
...
## Drop item from slot back into the world at drop_position.
func remove_item(slot: int, drop_position: Vector3) -> void:
	...
	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.add_to_group("pickup")
	if item.has_method("drop"):
		item.drop(_world_root, drop_position)
	...
```

`remove_item()` is explicitly documented and implemented as **world-drop
only** — it forces the item back into loose-world-pickup state
(collision layer 1, `"pickup"` group) and repositions it via `drop()`.
Neither Give nor Snatch is a world-drop; ownership is transferring to an
NPC, not the ground. Concretely:

- **Snatch:** per the contract this thread wrote in
  `PLAYER_SNATCH_CONTRACT_PLAN.md`, the NPC has *already* called
  `item.pickup(npc.hold_point)` (collision layer → 2, hold-point
  reassigned) **before** `on_item_snatched()`/`clear_held_item_external()`
  runs. Calling `remove_item()` at that point would immediately fight
  that — resetting collision layer back to 1, re-adding the `"pickup"`
  group tag, and calling `drop()`, which repositions the item and would
  visually rip it back out of the NPC's hand the instant after the NPC
  took it.
- **Give (destroyed-item branch):** by the time
  `_try_give_to_nearest_npc()` reaches its cleanup (the
  `if is_instance_valid(item): return` branch falling through, i.e. item
  was NOT valid), `consume_as_food()` has already freed the node. Calling
  `remove_item()` here would call `.freeze = false` etc. on an
  already-freed `RigidBody3D` — a hard runtime error
  ("previously freed instance"), not a silent no-op.

The actual minimal, safe fix: add a method that **only clears the slot
reference**, touching nothing on the item itself. The item's physical/
ownership state is already correct in every case that reaches this
cleanup — either the NPC just set it (Snatch), or it no longer exists
(destroyed Give) — so nothing here should be resetting collision layers,
groups, or positions at all.

---

## Change 1 — `InventoryManager.gd`: add `clear_slot()`

**Anchor:** append at end of file (verified current file is 156 lines,
ending with `remove_item()`'s closing `inventory_changed.emit()`).

```gdscript
old_str:
	if item.has_method("drop"):
		item.drop(_world_root, drop_position)

	inventory_changed.emit()

new_str:
	if item.has_method("drop"):
		item.drop(_world_root, drop_position)

	inventory_changed.emit()

## Clears a slot's reference without touching the item's own state at
## all — for the "something else already correctly handled this item,
## I just need to stop tracking it" case (an NPC's own pickup() call
## already reassigned it — Snatch; or it's already been freed elsewhere
## — a destroyed single-serving Give). remove_item()/retrieve_item() both
## force the item into world-pickup state (collision_layer = 1, "pickup"
## group; remove_item() also repositions via drop()) and are documented
## world-drop-only — using either here would fight an NPC's already-
## completed pickup() reassignment, or error outright on an already-freed
## item. This touches only the slot array itself.
func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	slots[slot] = null
	inventory_changed.emit()
```

---

## Change 2 — `InteractionSystem.gd`: shared `_release_item_to_npc()` helper

**Anchor:** insert after `_find_nearest_npc()` ends, before the
`_try_give_to_nearest_npc()` doc comment. Verified current lines 830–836.

```gdscript
old_str:
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Give dispatch. NPC.receive_item_from_player() may free `item`

new_str:
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Shared cleanup for "this item just left my possession entirely, and
## an NPC now has (or had) ownership of it" — used by both a destroyed-
## item Give and a Snatch. Deliberately does NOT call
## InventoryManager.remove_item()/retrieve_item() — see
## InventoryManager.clear_slot()'s own doc comment for why; in short,
## both of those force the item into world-pickup state and would fight
## an NPC's already-completed item.pickup(npc.hold_point) reassignment
## (Snatch) or error on an already-freed item (destroyed-item Give).
## is_instance_valid(held_item) gates the knocked_out-disconnect the same
## way — a freed item has no live signal to disconnect from.
func _release_item_to_npc() -> void:
	if is_instance_valid(held_item) and held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)
	if _held_from_slot != -1 and inventory != null:
		inventory.clear_slot(_held_from_slot)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## Give dispatch. NPC.receive_item_from_player() may free `item`
```

---

## Change 3 — `_try_give_to_nearest_npc()`: use the shared helper

**Anchor:** verified current lines 853–857 (the destroyed-item branch
only — the `if is_instance_valid(item): return` above this is
unchanged, still gating multi-charge survivors out entirely).

```gdscript
old_str:
	if is_instance_valid(item):
		return
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

new_str:
	if is_instance_valid(item):
		return
	_release_item_to_npc()
```

---

## Change 4 — `clear_held_item_external()`: use the shared helper

**Anchor:** verified current lines 867–872.

```gdscript
old_str:
func clear_held_item_external() -> void:
	if held_item != null and held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

new_str:
func clear_held_item_external() -> void:
	_release_item_to_npc()
```

---

## Confirmed unaffected

- **`_on_item_knocked_out()`** — still calls `inventory.deactivate_item()`
  exclusively, untouched by this plan. Knockout keeps the item in
  inventory, just inactive, exactly as before.
- **`_quick_drop()`** — still calls `inventory.remove_item()` exclusively
  (genuine world-drop, the case that method is actually for), untouched.
- **Multi-charge Give (can/bottle survives)** — `_try_give_to_nearest_npc()`
  still returns early via `if is_instance_valid(item): return` before
  ever reaching `_release_item_to_npc()`. The inventory slot correctly
  keeps showing the item, since it's still genuinely in the player's
  hand — this was never part of the reported bug and stays as-is.

---

## Verification checklist

1. Pull a single-serving item (dish/produce) from an inventory slot, give
   it to an NPC — confirm the inventory slot shows empty immediately,
   from every angle / after walking away.
2. Pull a food can or water bottle from an inventory slot, give it to an
   NPC — confirm the slot still correctly shows the item (reduced
   charge), since it never left the player's hand. This should be
   unchanged from before this plan.
3. Get a hostile/bad-relationship NPC to Snatch a slotted item (F7
   force-snatch if available) — confirm the slot clears the same way as
   #1, AND confirm the item visually stays correctly attached to the
   NPC's hand afterward (this is the case the naive `remove_item()` fix
   would have broken — watch for the item briefly flashing back to the
   ground/world state).
4. Confirm a normal knockout still correctly keeps the item in inventory,
   just inactive — `_on_item_knocked_out()` path is untouched by this
   plan.
5. Confirm a normal quick-drop (world drop) of a slotted item still works
   exactly as before — `_quick_drop()` path is untouched.

---

## Documentation updates (apply alongside the code changes above)

### `docs/systems/player/README.md`

Add a new Common-edits entry, directly after the existing "NPC-facing
contract for Relationship Snatch (Aug 2026)" entry:

```markdown
- **Give/Snatch inventory-slot clear fix (Aug 2026):** Both
  `_try_give_to_nearest_npc()`'s destroyed-item cleanup and
  `clear_held_item_external()` (Snatch) previously only nulled local
  `held_item`/`_held_from_slot` bookkeeping, never touching
  `InventoryManager.slots[]` — so an item pulled from an inventory slot
  and given/snatched away kept showing in that slot forever. Both now
  route through a new shared `_release_item_to_npc()` helper, which
  calls a new `InventoryManager.clear_slot()` when the item came from a
  slot. Deliberately does NOT use `InventoryManager.remove_item()` —
  that method is documented/implemented as world-drop-only (forces
  collision_layer back to 1, re-adds the `"pickup"` group, repositions
  via `drop()`), which would fight an NPC's already-completed
  `item.pickup(npc.hold_point)` reassignment on Snatch, or error on an
  already-freed item on a destroyed-item Give. `clear_slot()` only nulls
  the slot array entry — it's additive to `InventoryManager.gd`
  (UI/menu-subsystem-owned; flagged for their visibility, not a change
  to any of their existing methods).
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Give/Snatch Inventory-Slot Clear Fix (Aug 2026)

## What changed this session
Fixed a bug where giving or having an item Snatched by an NPC left it
showing forever in its original inventory slot. Root cause: the cleanup
in `_try_give_to_nearest_npc()` (destroyed-item branch) and
`clear_held_item_external()` (Snatch) only cleared local `held_item`/
`_held_from_slot` bookkeeping, never touching
`InventoryManager.slots[]`. Fix routes both through a new shared
`_release_item_to_npc()` helper calling a new
`InventoryManager.clear_slot()`. Deliberately did NOT use the originally
proposed `InventoryManager.remove_item()` — that method is documented
world-drop-only (resets collision_layer to 1, re-adds `"pickup"` group,
repositions via `drop()`), which would have fought an NPC's
already-completed `item.pickup(npc.hold_point)` reassignment on Snatch
(visually yanking the item back out of the NPC's hand) or errored
outright on an already-freed item on a destroyed-item Give.
`clear_slot()` only nulls the slot array entry, nothing else.

### Files modified
- `scripts/player/InteractionSystem.gd` — new `_release_item_to_npc()`
  helper; `_try_give_to_nearest_npc()` and `clear_held_item_external()`
  both now delegate to it.
- `scripts/ui/inventory/InventoryManager.gd` — new `clear_slot()` method
  (additive only, no existing method changed).
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_SNATCH_INVENTORY_CLEAR_FIX_PLAN.md`
for the full 5-item checklist)
```
