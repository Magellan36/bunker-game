# Fix: Gardening/Refuel Getting Interrupted Mid-Carry by PutAwayHeldItemActivity (Aug 2026)

**Files:** `scripts/npc/NPCBrain.gd`, `docs/systems/npc/README.md`,
`HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify both anchors below
against the live file before editing.

---

## Root cause (confirmed against live code)

`PutAwayHeldItemActivity` scores a flat `SCORE = 20.0` any time
`npc.held_item != null` — it can't distinguish "this item was abandoned"
from "some activity is legitimately carrying it right now." Both
`GardeningActivity` and `RefuelActivity` only report themselves as
non-interruptible during their *final* sub-phase (`"apply"` /
`"refuel"`) — while actually walking the item to its destination
(fetch-complete through travel), they're still interruptible:

```gdscript
# GardeningActivity
func interruptible() -> bool:
	return _phase != "apply"   ## mid-application, commit; between tasks, fine to interrupt

# RefuelActivity
func interruptible() -> bool:
	return _phase != "refuel"   ## mid-pour, commit; between generators/fetching, fine to interrupt
```

Do the math: Gardening's max score is
`6.0 × 1.3 × 0.8 ≈ 6.2`, plus the 8.0 `SWITCH_MARGIN` = ~14.2.
Refuel's max is `8.0 × 1.3 × 1.0 = 10.4`, plus margin = ~18.4. Both lose
to PutAwayHeldItemActivity's flat 20.0. NPCs re-evaluate every
`THINK_INTERVAL` (~1s), which is exactly why this happens "after about a
second" — the very next think-cycle after picking the item up
interrupts the carry.

`CleaningActivity` was never affected — it's already non-interruptible
for the *entire* held-item lifecycle (`return _item == null`), not just
one sub-phase, which is why this never showed up there and is the
pattern to match.

The "drop it, go idle, walk in a straight line into a wall" part:
PutAwayHeldItemActivity takes over, finds no valid destination for a
soil bag/seed packet/fuel can (they were never meant for
Shelving/LightStorage), drops it immediately — but nothing zeroes the
NPC's velocity when that happens, so it coasts in whatever direction it
was last walking until the next think-cycle picks something new
(explains the "idle" gap and the straight-line drift).

---

## Fix

**File:** `scripts/npc/NPCBrain.gd`

**Anchor:** `GardeningActivity.interruptible()`:

```gdscript
	func interruptible() -> bool:
		return _phase != "apply"   ## mid-application, commit; between tasks, fine to interrupt
```

Replace with:

```gdscript
	func interruptible() -> bool:
		## Aug 2026 — was `_phase != "apply"`, which only protected the
		## final sub-phase. That left the NPC interruptible for the whole
		## fetch-complete-through-travel window while physically CARRYING
		## the soil bag/seed packet — long enough for
		## PutAwayHeldItemActivity's flat score (20.0) to beat Gardening's
		## own (max ~6.2 + the 8.0 switch margin) on the very next think-
		## cycle (~1s later), interrupting the carry and (since neither
		## item has a real Shelving/LightStorage destination) getting
		## dropped in place almost immediately. Matches CleaningActivity's
		## existing pattern instead: non-interruptible for the item's
		## ENTIRE held lifecycle, not just the last sub-phase.
		return _item == null
```

**Anchor:** `RefuelActivity.interruptible()`:

```gdscript
	func interruptible() -> bool:
		return _phase != "refuel"   ## mid-pour, commit; between generators/fetching, fine to interrupt
```

Replace with:

```gdscript
	func interruptible() -> bool:
		## Aug 2026 — same fix as GardeningActivity, same root cause: was
		## only protected during the final "refuel" sub-phase, leaving the
		## whole fetch-complete-through-travel window (physically carrying
		## the fuel can) vulnerable to PutAwayHeldItemActivity's flat
		## score interrupting mid-carry. Not yet reported for Refuel
		## specifically, but the exact same math applies (max score ~10.4
		## + margin = ~18.4, still under PutAwayHeldItemActivity's flat
		## 20.0) — fixed alongside Gardening rather than waiting for it to
		## show up separately.
		return _can == null
```

Stop and report on anchor mismatch — no improvisation.

### Defensive polish — stop the "coast into a wall" artifact regardless of cause

Even with the fix above, it's worth eliminating the visual artifact
itself for any OTHER legitimate interruption of PutAwayHeldItemActivity
(e.g. a genuinely abandoned item with no destination) — nothing should
leave residual velocity behind when an activity ends and hands off to
nothing.

**Anchor:** the first `drop_held` call in `PutAwayHeldItemActivity.enter()`:

```gdscript
		if _destination == null:
			NPCItemUser.drop_held(npc)
			_settled = true
			return
```

Replace with:

```gdscript
		if _destination == null:
			NPCItemUser.drop_held(npc)
			npc.velocity = Vector3.ZERO   ## Aug 2026 — don't leave the NPC coasting in whatever direction it was last walking
			_settled = true
			return
```

**Anchor:** the second `drop_held` call in `PutAwayHeldItemActivity.tick()`:

```gdscript
			if _destination == null or not is_instance_valid(_destination):
				NPCItemUser.drop_held(npc)
				_settled = true
				return
```

Replace with:

```gdscript
			if _destination == null or not is_instance_valid(_destination):
				NPCItemUser.drop_held(npc)
				npc.velocity = Vector3.ZERO   ## Aug 2026 — same as enter()'s drop branch
				_settled = true
				return
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

1. Reproduce exactly what was reported: request "Add soil to all trays"
   (or let it trigger autonomously), watch an NPC pick up a Bag of Soil
   — confirm it now carries it the whole way to the tray and applies it,
   with no drop/idle/straight-line-drift around the 1-second mark.
2. Same for planting (seed packet) and — even though not autonomous —
   confirm a "Fertilize the trays" command also isn't affected (it uses
   the same class).
3. Refuel: fetch a fuel can from far enough away that travel takes
   several seconds — confirm it's no longer interruptible mid-carry
   either, even under conditions that would previously have let
   PutAwayHeldItemActivity win (e.g. NO other legitimate need pulling
   focus, just the raw score comparison).
4. Confirm PutAwayHeldItemActivity itself still works correctly for its
   actual intended case — force an NPC into a genuinely abandoned held
   item (e.g. via the stuck-recovery interruption scenario from an
   earlier plan) and confirm it still gets picked up and put away/
   dropped, just without any residual drift afterward.
5. Confirm Cleaning is completely unaffected (its own interruptibility
   logic wasn't touched).

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
97. Watch an NPC carry a Bag of Soil (or seed packet, or fuel can) the
    entire way to its destination — confirm it's never interrupted
    mid-carry by the "put away held item" safety net, which previously
    could win the very next think-cycle (~1s later) and cause a
    drop/idle/straight-line-drift.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Fixed Gardening/Refuel Getting Interrupted Mid-Carry (Aug 2026)

- Root-caused the reported "picks up soil, carries it ~1s, drops it,
  goes idle, walks into a wall" bug: GardeningActivity/RefuelActivity
  only protected their FINAL sub-phase ("apply"/"refuel") from
  interruption, leaving the whole fetch-complete-through-travel window
  (physically carrying the item) vulnerable to
  PutAwayHeldItemActivity's flat score (20.0) beating their own
  (Gardening max ~6.2+margin=~14.2, Refuel max ~10.4+margin=~18.4) on
  the very next think-cycle (~1s later per THINK_INTERVAL).
- Both now mirror CleaningActivity's already-correct pattern:
  non-interruptible for the item's ENTIRE held lifecycle
  (interruptible() now checks _item == null / _can == null), not just
  one sub-phase. Refuel had the identical latent bug, not yet reported
  separately — fixed alongside Gardening rather than waiting for it to
  surface.
- Added a small defensive fix regardless of cause: PutAwayHeldItemActivity
  now zeroes NPC velocity when it drops an item in place, eliminating
  the "coasts in a straight line until it hits a wall" artifact for any
  future legitimate interruption too.

Files touched: `scripts/npc/NPCBrain.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
