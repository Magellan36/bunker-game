# Gardening: Log Cell-Claim Failures (Aug 2026)

**File:** `scripts/npc/NPCBrain.gd`.

**Re-clone the repo fresh before starting.**

---

## Context

Confirmed one small, real debug gap while investigating: when
`GardeningActivity._pick_next_task()` finds a cell that looks free
(per its own scan) but `claim_cell()` then fails — because another
NPC's Gardening session claimed it in the moment between the scan and
the claim attempt — it silently retries with no log line explaining
why. This is exactly why the debug output showed two identical
`"gardening target picked"` lines for the same tray/cell back to back
with nothing in between: harmless, expected contention (the same kind
`CleaningActivity` already logs clearly via its own `"claim failed"`
line), just not explained yet on the Gardening side.

## Fix

**Anchor:**

```gdscript
		if _current_task != "fertilize" and not NPCItemUser.claim_cell(_current_tray, _current_cell, npc):
			## Another NPC's Gardening session already has this cell —
			## try again fresh; a different cell (or nothing) will come up.
			_pick_next_task(npc)
			return
```

Replace with:

```gdscript
		if _current_task != "fertilize" and not NPCItemUser.claim_cell(_current_tray, _current_cell, npc):
			## Another NPC's Gardening session already has this cell —
			## try again fresh; a different cell (or nothing) will come up.
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening claim failed", "%s cell=%d already claimed by another NPC — retrying" \
					% [_current_tray.name, _current_cell])
			_pick_next_task(npc)
			return
```

Stop and report on anchor mismatch — no improvisation.

## Testing

1. Get two NPCs gardening the same double tray at once such that they
   briefly contend for the same cell — confirm the console now shows a
   `"gardening claim failed"` line explaining the retry, instead of two
   unexplained duplicate `"target picked"` lines.

## Important — please do this before anything else

Fully restart the game (not just re-enter a level — a genuine editor/
process restart) and re-run the exact scenario from your last capture.
If the `"Fetching soil -> Cleaning"` interruption still happens
afterward, send me that fresh log — at that point it's a real,
different bug (since the code I verified says it shouldn't be
possible), and worth digging into live rather than guessing further
from static reading. If it doesn't happen again after a clean restart,
that confirms it was a stale-build artifact from before the last fix
took effect.

## Documentation updates

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
101. Force two NPCs to briefly contend for the same farming cell —
     confirm a "gardening claim failed" log line explains the retry
     instead of an unexplained duplicate "target picked" line.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Gardening Claim-Failure Logging (Aug 2026)

- GardeningActivity._pick_next_task() now logs when a cell-claim
  attempt fails due to another NPC's contention, instead of silently
  retrying — matches CleaningActivity's existing "claim failed"
  pattern. Explains what previously showed as unexplained duplicate
  "target picked" lines for the same cell.
- Verified (not a new bug): the interrupt/stuck logging and Gardening/
  Refuel non-interruptibility fixes from the prior plan are correctly
  live in code. A reported "Fetching soil -> Cleaning" transition with
  no INTERRUPTED: line contradicts that code (the branch that could
  produce it should be unreachable with interruptible() now false) —
  most likely a stale build from before that fix took effect. Flagged
  for a fresh post-restart capture rather than assumed to be a new bug.

Files touched: `scripts/npc/NPCBrain.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
