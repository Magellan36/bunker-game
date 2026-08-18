# Bugfix Plan: `get_held_item()` Returns a Freed Instance (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** NPC subsystem crash report
(`PLAYER_SUBSYSTEM_GET_HELD_ITEM_VALIDITY_FIX.md`), verified against the
current on-disk state of `scripts/player/Player.gd` and
`scripts/player/InteractionSystem.gd` on 2026-08-04.
**File touched:** `scripts/player/Player.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## Verified against current code

Confirmed `get_held_item()` is exactly as described — a bare passthrough
with no validity check:

```gdscript
func get_held_item() -> Node:
	return interaction_system.held_item if interaction_system != null else null
```

And confirmed the existing sibling guard in `InteractionSystem.
_update_prompt()` (current lines 413–416) that the report references:

```gdscript
# ── Guard: held_item freed externally (build mode deconstruct, etc.) ─────
if held_item != null and not is_instance_valid(held_item):
	held_item       = null
	_held_from_slot = -1
```

One thing the report's proposed snippet missed that I'm correcting: the
existing guard clears **both** `held_item` and `_held_from_slot` — the
NPC subsystem's proposed fix only nulls `held_item`. If `get_held_item()`
self-heals without also resetting `_held_from_slot`, that field is left
stale (still pointing at whatever inventory slot the freed item
supposedly came from), which could misdirect a later scroll/pickup
operation that reads it. Fixing both, matching the established pattern
exactly rather than a partial version of it.

---

## Investigated: is build-mode deconstruct actually the mechanism?

The report asked me to double-check whether build mode's deconstruct
path is itself the thing freeing a currently-held item without
awareness, or whether that's a separate issue. I read `_try_deconstruct()`
in `BuildModeController.gd` directly: it only operates on entries in
`_placed_objects` — world-placed constructions (furniture, walls,
generators, etc.) tracked via a build-mode placement registry — and
looks the hovered body up in that array before proceeding. A player's
currently-held pickupable item (Basket, Food Can, Crate, etc.) is never
a member of `_placed_objects`; it's a loose `RigidBody3D` on collision
layer 2 while held, not a build-mode placement.

So I can't confirm `_try_deconstruct()` is the actual mechanism from what
I read — it doesn't appear able to reach a currently-held item at all
under normal circumstances. The one path worth a closer look, which I
didn't chase further since it's Furniture/Build-Mode-thread territory:
`_try_deconstruct()` calls `body.eject_all_items()` on containers
(shelves, etc.) before freeing them — if a container's "contained item"
bookkeeping can ever end up referencing the same item the player is
separately holding (a stale/duplicate reference rather than a true
hand-off), that could be the real source. Not confirmed, not something
I dug into further given it's outside this file — flagging it as a
possible lead for that thread rather than asserting it as the answer.

**Either way, the fix below is correct regardless of what's upstream** —
`get_held_item()` should never hand back a dangling reference to a
caller, no matter what eventually turns out to be freeing it.

---

## The fix

**Anchor:** `Player.gd`, verified current lines 136–137.

```gdscript
old_str:
func get_held_item() -> Node:
	return interaction_system.held_item if interaction_system != null else null

new_str:
func get_held_item() -> Node:
	if interaction_system == null:
		return null
	if interaction_system.held_item != null and not is_instance_valid(interaction_system.held_item):
		## Freed externally without going through the normal drop/give
		## cleanup — self-heal the same way InteractionSystem._update_prompt()'s
		## existing guard already does for this exact scenario (see that
		## function's own comment), rather than handing back a dangling
		## reference to whatever NPC-side code called this. Clears both
		## fields, matching that guard exactly — held_item alone isn't
		## enough, or _held_from_slot is left stale.
		interaction_system.held_item       = null
		interaction_system._held_from_slot = -1
	return interaction_system.held_item
```

---

## Verification checklist

1. Enter build mode while holding an item, deconstruct whatever's
   causing this (reproduce the original crash scenario) — confirm no
   error, and confirm the player's hand correctly reads as empty
   afterward (both in `get_held_item()`'s return value and visually).
2. Confirm normal Give/Takeaway/Snatch interactions (all route through
   `get_held_item()` or the underlying `held_item` field it wraps) still
   work correctly in the non-crash case.
3. After a self-heal fires, confirm scrolling through inventory slots
   behaves normally afterward (regression check on the added
   `_held_from_slot` reset — confirms nothing is left pointing at a
   stale slot index).

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry:

```markdown
- **`get_held_item()` validity guard (Aug 2026).** Was a bare
  passthrough to `InteractionSystem.held_item` with no check — if that
  field ever ends up pointing at a freed object without going through
  the normal drop/give cleanup, any NPC-side caller crashed on
  "previously freed instance." Now self-heals the same way
  `InteractionSystem._update_prompt()`'s existing guard already handles
  this (see that function, "Guard: held_item freed externally"):
  validates with `is_instance_valid()`, and clears both `held_item` and
  `_held_from_slot` (not just the former) before returning. Investigated
  whether build-mode deconstruct is actually the upstream cause per the
  bug report's suggestion — `_try_deconstruct()` only operates on
  `_placed_objects` entries, which a currently-held item is never a
  member of, so that path doesn't appear able to reach a held item
  directly; not conclusively resolved, flagged as a possible Furniture/
  Build-Mode-thread lead (`eject_all_items()` on deconstructed
  containers) rather than chased further here.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — `get_held_item()` Validity Guard (Aug 2026)

## What changed this session
Fixed a crash ("Trying to return a previously freed instance") in
`Player.get_held_item()`, which was a bare passthrough to
`InteractionSystem.held_item` with no validity check. Added the same
self-heal guard `InteractionSystem._update_prompt()` already uses for
this exact scenario (held item freed externally without going through
normal drop/give cleanup) — validates with `is_instance_valid()`, clears
both `held_item` and `_held_from_slot` (the reported fix only cleared
the former; fixed to match the established pattern in full).

Investigated whether build-mode deconstruct is the actual upstream cause,
per the bug report's request — read `_try_deconstruct()` directly; it
only targets `_placed_objects` entries (world-placed constructions), and
a currently-held pickupable item is never a member of that array, so it
doesn't appear to be able to reach a held item under normal
circumstances. Not conclusively resolved either way; noted
`eject_all_items()` on deconstructed containers as a possible lead for
the Furniture/Build-Mode thread, not chased further here since it's
outside this file.

### Files modified
- `scripts/player/Player.gd` — `get_held_item()` validity guard.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GET_HELD_ITEM_VALIDITY_FIX_PLAN.md`
for the full 3-item checklist)
```
