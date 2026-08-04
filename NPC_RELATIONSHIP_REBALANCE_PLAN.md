# Relationship Magnitude Rebalance (Aug 2026)

**Owner:** NPC Claude instance. Fully contained to `scripts/npc/NPC.gd`,
three constant values. No other files touched.

**Prerequisite:** all five prior NPC plans applied (Relationships
groundwork through Give multi-charge).

## Why

Relationships need to read as built from many interactions and habits
over a 100+ in-game-day playthrough, not a handful of events. Two
problems with the current numbers:

1. **Give/Takeaway (±15) are too heavy for single events.** Halving both,
   symmetrically, per your instruction.
2. **Passive proximity (2.0/game-hour) is far too strong on its own,
   even though you didn't ask about it directly.** At 2.0/hour, two
   NPCs (or an NPC and the player) who are simply in the same room
   reach the relationship cap in about 50 game-hours — roughly 2
   in-game days of ordinary cohabitation. That's the opposite of "many
   interactions and consistent habits over 100+ days" — it means
   ambient presence alone maxes out a relationship almost immediately,
   making Give/Takeaway (and Sociability, and everything else layered on
   top) nearly irrelevant background noise by comparison. This needed
   reeling in as part of the same "how drastic should changes be" pass,
   not just the two numbers you named.

## The new numbers, and the reasoning behind them

- **Proximity gain: 2.0 → 0.15 per game-hour** (~13x reduction). At a
  generous estimate of ~4 hours/day of actual overlapping proximity
  between two cohabitants (NPCs wander, they're not glued together),
  that's roughly 0.6/day, or about 60 points — solidly into "Friendly"
  territory — after a full 100-day playthrough of consistent
  cohabitation. Reaching "Close" (60+) this way now requires either a
  longer playthrough or unusually constant proximity, which feels right
  for a slow-burn relationship built on habit rather than presence alone.
- **Give bonus: 15.0 → 7.5.** At the new proximity rate, one gift is now
  worth roughly 50 game-hours (~2 days) of ambient closeness — a real,
  noticeable moment, not a instant relationship reset.
- **Takeaway penalty: 15.0 → 7.5**, symmetric with Give as you asked.

Gift burnout (saturation curve, ~5-day decay) and the per-item/per-NPC
repeat-boost gating from the last two passes are untouched — those
mechanisms already exist specifically to prevent spamming either number
into irrelevance, and they still apply correctly to the new smaller base
values.

Band thresholds (-60/-20/20/60 for Hostile/Cold/Neutral/Friendly/Close)
are unchanged — only the speed of getting there changed, not where the
bands sit.

---

## `scripts/npc/NPC.gd`

### 1. Give / Takeaway constants

**Anchor:**

```gdscript
# ─── Give / Takeaway (Part 24) ──────────────────────────────────────────────
const GIVE_RELATIONSHIP_BONUS: float = 15.0
const TAKEAWAY_RELATIONSHIP_PENALTY: float = 15.0
```

Replace with:

```gdscript
# ─── Give / Takeaway (Part 24) ──────────────────────────────────────────────
## Halved (Aug 2026, Part 27) — relationships should build from many
## interactions over a long playthrough (100+ in-game days), not swing on
## a handful of events. Kept symmetric between Give and Takeaway.
const GIVE_RELATIONSHIP_BONUS: float = 7.5
const TAKEAWAY_RELATIONSHIP_PENALTY: float = 7.5
```

### 2. Passive proximity gain

**Anchor:**

```gdscript
const RELATIONSHIP_PROXIMITY_RANGE: float = 4.0   ## meters, XZ-only
const RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR: float = 2.0
```

Replace with:

```gdscript
const RELATIONSHIP_PROXIMITY_RANGE: float = 4.0   ## meters, XZ-only
## Reduced 2.0 → 0.15 (Aug 2026, Part 27) — the original value maxed a
## relationship out from ordinary cohabitation alone in ~2 in-game days,
## making every other relationship driver (Give/Takeaway, Sociability)
## irrelevant by comparison. At 0.15/hour, ~4 hrs/day of realistic
## overlap lands around "Friendly" (not maxed) after a full 100-day
## playthrough — see the plan doc for the full reasoning.
const RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR: float = 0.15
```

---

## Documentation update

### `docs/systems/npc/README.md`

In the **Relationships** section, find the sentence describing the
baseline driver:

```
Ticks on the same 5s cadence as mood/irritability
(`_tick_relationships()`, called from `_tick_mood_and_irritability()`),
nudging affinity up toward every other NPC and the player within 4m
(XZ-only, `NPCItemUser.flat_distance`) by
`RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR = 2.0` per game-hour, scaled
by sociability.
```

Replace with:

```
Ticks on the same 5s cadence as mood/irritability
(`_tick_relationships()`, called from `_tick_mood_and_irritability()`),
nudging affinity up toward every other NPC and the player within 4m
(XZ-only, `NPCItemUser.flat_distance`) by
`RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR = 0.15` per game-hour (reduced
from an initial 2.0, Aug 2026 — see Testing Checklist item 17 and the
Give/Takeaway paragraph below for the rebalanced ±7.5 event magnitudes),
scaled by sociability. Deliberately slow — relationships here are meant
to read as built from consistent habit over a long (100+ day)
playthrough, not from a handful of interactions.
```

In the **Give / Takeaway** section, find every occurrence of `+15` and
`-15`/`15` referring to `GIVE_RELATIONSHIP_BONUS`/
`TAKEAWAY_RELATIONSHIP_PENALTY` and update to `+7.5`/`-7.5`/`7.5`
respectively (appears in the Give paragraph, the Takeaway paragraph, and
possibly the Testing Checklist items referencing these values — update
all of them for consistency).

In the **Testing Checklist**, add:

```
17. Confirm relationship pacing feels appropriately slow: stand an NPC
    and the player together continuously and use F7 admin fast-forward —
    relationship should NOT reach "Close" within the first several
    in-game days from proximity alone. A single Give/Takeaway should move
    the number by 7.5 (pre-Sociability-scaling), not 15.
```

### `HANDOVER.md`

Add a new top section once applied:

```markdown
# Handover — Relationship Magnitude Rebalance (Aug 2026)

## What changed this session
- **NPC.gd**: `GIVE_RELATIONSHIP_BONUS` and `TAKEAWAY_RELATIONSHIP_PENALTY`
  halved (15.0 → 7.5, kept symmetric). `RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR`
  reduced 2.0 → 0.15 (~13x) — the original rate maxed a relationship out
  from ordinary cohabitation alone within ~2 in-game days; the new rate
  targets "Friendly" after ~100 days of realistic daily overlap, not
  "Close" within the first week.
- No mechanism changes — burnout, per-item/per-NPC repeat gating, band
  thresholds, and Sociability scaling are untouched, just the base
  numbers they operate on.

## Files Modified
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist
See `docs/systems/npc/README.md` Testing Checklist item 17.
```

---

## Summary

| File | Change |
|---|---|
| `scripts/npc/NPC.gd` | 3 constant value changes (halved Give/Takeaway, ~13x-reduced proximity gain) |
| `docs/systems/npc/README.md` | Updated values throughout, new Testing Checklist item |
| `HANDOVER.md` | New session entry |

No other files touched — this pass is pure numeric tuning, no logic
changes.
