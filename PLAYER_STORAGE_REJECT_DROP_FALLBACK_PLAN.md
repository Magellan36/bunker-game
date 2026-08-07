# Plan: Storage-Reject Fallback to Drop (Aug 2026)

**Owner:** Player subsystem (this plan) — two flagged files outside the
usual three (see note below).
**Files touched:** `scripts/world/furniture/LightStorage.gd`,
`scripts/world/furniture/Shelving.gd`.
**Docs touched:** `docs/systems/player/README.md`,
`docs/systems/furniture-items/README.md` (flagged, not mine — see
below), `HANDOVER.md`.

**Scope note:** both files are Furniture-thread territory, not one of
my three core files. Taking this the same way as the earlier
`InventoryManager.gd`/`InteractPrompt.gd`/`PickupableItem.gd` fixes this
session — you asked me to own this pass directly, so investigated and
fixed both files rather than writing a hand-off, flagged clearly for
that thread's visibility.

---

## What's actually happening today (verified against current code)

The F-key dispatch (`InteractionSystem._unhandled_input()`, current
lines 152–158) already has exactly the "secondary priority" structure
you're describing — it's just that the storage object's own logic
doesn't fall through to it correctly:

```gdscript
var shelf: Node3D = _nearest_shelf()
if held_item != null:
	## Holding something — try placing on nearby shelf first, else drop
	if shelf != null and shelf.has_method("on_f_interact"):
		shelf.on_f_interact()
	else:
		_quick_drop()
```

So the "priority" logic is already right: try to place first, drop
otherwise. The problem is entirely inside `on_f_interact()` → the
storage object's own place/store function, which today just shows a
warning and stops — it never tells `InteractionSystem` to fall back to
`_quick_drop()` on its own behalf:

**`LightStorage.gd._try_store_held()`** (Dresser/End Table — confirmed
current lines 123–132): checks `"inventory_item"` group membership
("too big") and `is_full()`, shows the correct distinct warning for
each, then `return`s — leaving the item stuck in the player's hand with
no fallback.

**`Shelving.gd._try_place_item()`** (regular shelves — confirmed current
lines 329–332): when `_find_slot_for(item)` returns `-1` (shelf full —
Shelving has no "too big" concept at all; any item type can go in any
empty slot, it only ever runs out of room), it just `return`s with
**no warning message at all** today. Worth fixing alongside the
Dresser/End Table case for the same reason you gave — a full shelf
should behave the same way, and right now it's actually worse (silent
block, not even an explanation).

---

## The fix

In both files: when the store/place attempt would be rejected (too big,
or full), show the existing warning as before, then call
`_interaction_system._quick_drop()` directly instead of just returning —
the exact same drop path F already uses when there's no shelf/storage in
range at all, so this isn't new drop logic, just wiring the existing one
in for this case too. (Both files already reach directly into
`InteractionSystem`'s internal state elsewhere in their own cleanup code
— e.g. `_interaction_system._is_holding_e`, `_interaction_system.
_held_from_slot` — so calling `_interaction_system._quick_drop()`
matches the established pattern already used in these exact files,
not a new convention.)

### Change 1 — `LightStorage.gd._try_store_held()`

**Anchor:** verified current lines 123–132.

```gdscript
old_str:
func _try_store_held(item: RigidBody3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not item.is_in_group("inventory_item"):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Too big for the %s" % display_name.to_lower())
		return
	if is_full():
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("%s is full" % display_name)
		return

new_str:
func _try_store_held(item: RigidBody3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not item.is_in_group("inventory_item"):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Too big for the %s" % display_name.to_lower())
		## Aug 2026 fix — don't leave the item stranded in the player's
		## hand. Fall through to the same drop F would do with nothing in
		## range at all (InteractionSystem._quick_drop(), the "secondary
		## priority" path already built into the F dispatch — see its own
		## comment). Bunkers get tight with furniture placed close
		## together; blocking F entirely here meant a player standing
		## near a Dresser/End Table couldn't drop OR pick anything else up
		## nearby without walking away first.
		_interaction_system._quick_drop()
		return
	if is_full():
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("%s is full" % display_name)
		_interaction_system._quick_drop()   ## Same fallback — see comment above.
		return
```

### Change 2 — `Shelving.gd._try_place_item()`

**Anchor:** verified current lines 329–332.

```gdscript
old_str:
func _try_place_item(item: RigidBody3D) -> void:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return

new_str:
func _try_place_item(item: RigidBody3D) -> void:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		## Aug 2026 fix — previously silent: no warning, and the item was
		## left stranded in the player's hand with no fallback. Shelving
		## has no "too big" concept (_find_slot_for() accepts any item
		## type into any empty slot) — -1 here always means genuinely
		## full. Now warns AND falls through to the same drop F would do
		## with nothing in range (InteractionSystem._quick_drop()),
		## matching LightStorage.gd's established too-big/full pattern —
		## bunkers get tight with furniture placed close together, so a
		## silent block here left players unable to drop OR pick up
		## anything near a full shelf without walking away first.
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Shelf is full")
		_interaction_system._quick_drop()
		return
```

---

## Why this is safe

- **`_quick_drop()` is fully self-contained** — reads `held_item`,
  `player`, `inventory`, `_held_from_slot`, `_world_root`,
  `_tracked_bodies`, all internal `InteractionSystem` state, with no
  dependency on being called from the input-dispatch context
  specifically. At the point either fix calls it, `_interaction_system.
  held_item` is still exactly `item` (neither file has touched it yet),
  so it operates on the correct object.
- **The success path (item actually fits) is completely untouched** in
  both files — only the rejection branches gained a fallback call.
- **The existing warning text is unchanged**, per your instruction to
  keep the block/message as-is — this only adds what happens *after* the
  warning, not the warning itself, with the one exception of Shelving.gd
  gaining a warning it previously didn't have at all (flagged clearly
  above as a genuine gap, not a change to existing behavior).
- **Empty-handed pickup near storage was never blocked** in the first
  place — the F-dispatch only calls `on_f_interact()` at all when
  `held_item != null`; empty-handed F always goes straight to
  `_try_pickup()` regardless of nearby shelves. Nothing to fix there.

---

## Verification checklist

1. Hold a Crate, walk up to a Dresser/End Table, press F — confirm
   "Too big for the dresser/end table" still shows, AND the Crate now
   drops in front of the player instead of staying stuck in-hand.
2. Fill a Dresser/End Table to capacity, hold any storable item, press
   F — confirm "[Dresser/End Table] is full" still shows, AND the item
   drops.
3. Fill a Shelf to capacity (all 6 slots occupied by non-matching or
   full stacks), hold any item, press F near it — confirm "Shelf is
   full" now shows (previously nothing), AND the item drops.
4. Normal case: Dresser/End Table/Shelf with room, holding a storable
   item, press F — confirm it still stores normally, no warning, no
   drop (regression check on the success path).
5. Confirm the dropped item in each case above lands correctly in front
   of the player and its prompt/icon row appears immediately (this
   reuses `_quick_drop()`'s existing re-tracking fix from earlier this
   session — should already work, just confirming no interaction between
   the two fixes).
6. Empty-handed near a full Dresser/Shelf, press F on a nearby loose
   item — confirm pickup still works normally (unaffected by this
   change, per the "why this is safe" note above).

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **Storage-reject fallback to drop (Aug 2026,
  `LightStorage.gd`/`Shelving.gd` — flagged: `scripts/world/furniture/`,
  not one of the three core files, but the F-dispatch fallback these
  hook into is `InteractionSystem._quick_drop()`).** Previously,
  pressing F to store a held item into a full or size-ineligible
  Dresser/End Table/Shelf just showed a warning (or, for a full Shelf,
  nothing at all) and left the item stuck in the player's hand — no
  fallback to the normal drop F already does when nothing's in range.
  Both `LightStorage._try_store_held()` and `Shelving._try_place_item()`
  now call `_interaction_system._quick_drop()` directly in their
  rejection branches after showing the warning, reusing the exact same
  drop path rather than adding new drop logic. Matters in practice
  because bunkers get tight with furniture placed close together —
  without this, standing near a full/ineligible storage object could
  leave a player unable to drop (or, transitively, pick anything else
  up) without first walking out of that storage object's ~2.5 m reach.
```

### `docs/systems/furniture-items/README.md`

One line, flagged the same way as the earlier shelf-fairness
cross-reference (this file belongs to the Furniture subsystem):

```markdown
- Storage-full/too-big rejection (Dresser/End Table/Shelf) now falls
  back to a normal drop instead of blocking F entirely — see Player
  subsystem's `docs/systems/player/README.md` for the fallback mechanism
  (`InteractionSystem._quick_drop()`).
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Storage-Reject Fallback to Drop (Aug 2026)

## What changed this session
Fixed pressing F to store a held item into a full or size-ineligible
Dresser/End Table/Shelf leaving the item stuck in the player's hand.
Both `LightStorage._try_store_held()` (Dresser/End Table — "too big"/
"full" checks) and `Shelving._try_place_item()` (Shelf — full only, no
"too big" concept there) now call `InteractionSystem._quick_drop()`
directly in their rejection branches, after showing the existing
warning (Shelving previously showed no warning at all in this case —
added one, matching LightStorage's established pattern). Reuses the
exact drop path F already falls back to when there's no storage object
in range at all — no new drop logic. Purpose: bunkers get tight with
furniture placed close together, and blocking F entirely near a full/
ineligible storage object could strand a player unable to drop (or pick
up) anything nearby without first walking out of range.

### Files modified
- `scripts/world/furniture/LightStorage.gd` — `_try_store_held()`
  rejection branches now fall back to `_quick_drop()`.
- `scripts/world/furniture/Shelving.gd` — `_try_place_item()`'s full
  branch gained a warning message (previously silent) and the same
  `_quick_drop()` fallback.
- `docs/systems/player/README.md` — new Common-edits entry.
- `docs/systems/furniture-items/README.md` — one-line cross-reference
  (Furniture-subsystem-owned file, flagged for their visibility).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_STORAGE_REJECT_DROP_FALLBACK_PLAN.md`
for the full 6-item checklist)
```
