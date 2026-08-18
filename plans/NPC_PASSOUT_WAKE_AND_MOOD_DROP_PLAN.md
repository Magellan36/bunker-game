# Pass-Out: Wake at 15 Energy + Neuroticism-Scaled Mood Drop (Aug 2026)

**File:** `scripts/npc/NPCBrain.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCDebug.gd`.

**Implementation note:** `neuroticism_trait_mult()` doesn't exist in the
live file yet (checked directly) — this plan creates it fresh, as a
public function (no underscore, since `PassedOutActivity` in
`NPCBrain.gd` needs to call it cross-file). If you separately already
added a private `_neuroticism_trait_mult()` version, rename it to the
public form below and update its one call site in `_tick_mood()` instead
of creating a duplicate.

---

## 1. Wake at 15 energy instead of 100

**Anchor:** `PassedOutActivity`'s constants and `done()`:

```gdscript
	const REGEN_PER_GAME_HOUR: float = 15.0   ## slower than SitActivity (25) and LieActivity (45) on purpose
```

Replace with:

```gdscript
	const REGEN_PER_GAME_HOUR: float = 15.0   ## slower than SitActivity (25) and LieActivity (45) on purpose
	## Wakes at 15, not full — deliberately leaves them still needing real
	## rest afterward. Also the intended hook for a future "administer an
	## energy item to wake them faster" player action: something reaching
	## into this state and pushing energy toward 15 should end this the
	## same way natural regen does, no separate code path needed.
	const WAKE_ENERGY: float = 15.0
```

**Anchor:**

```gdscript
	func done(npc: NPC) -> bool:
		return npc.energy >= 100.0
```

Replace with:

```gdscript
	func done(npc: NPC) -> bool:
		return npc.energy >= WAKE_ENERGY
```

---

## 2. Mood drop on collapse, scaled by Neuroticism

**Anchor:** `PassedOutActivity.enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		_orig_rotation = npc.rotation
		npc.lock_movement()
		npc.rotation = Vector3(_orig_rotation.x, _orig_rotation.y,
			_orig_rotation.z + deg_to_rad(90.0))
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_orig_rotation = npc.rotation
		npc.lock_movement()
		npc.rotation = Vector3(_orig_rotation.x, _orig_rotation.y,
			_orig_rotation.z + deg_to_rad(90.0))
		## Mood hit on collapse — lower bound fixed at 1%, upper bound is
		## 10% scaled by Neuroticism (baseline 10%, Neurotic 15%,
		## Easygoing 5%). One-time, applied here at the moment of
		## collapse, not repeated per-tick while passed out.
		var mood_drop: float = randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())
		npc.mood = clampf(npc.mood - mood_drop, 0.0, 100.0)
		if NPCDebug.enabled:
			NPCDebug.log_mood_event(npc, -mood_drop, "passed out")
```

---

## 3. `scripts/npc/NPC.gd` — the multiplier function

**Anchor:** a sensible spot near the other trait multiplier functions
(e.g. right after `_sociability_trait_mult()`).

Insert:

```gdscript
## Neuroticism — scales mood's random per-tick drift AND the one-time
## mood drop on passing out. 0.5x (Easygoing) to 1.5x (Neurotic), 1.0x
## at baseline/absent. Public (no underscore) — called from NPCBrain.gd's
## PassedOutActivity, not just internally.
func neuroticism_trait_mult() -> float:
	return lerp(0.5, 1.5, float(personality.get("neuroticism", 0.5)))
```

If you're also wiring Neuroticism's mood-drift effect from an earlier
plan, its one call site in `_tick_mood()` should read
`npc.neuroticism_trait_mult()`/`neuroticism_trait_mult()` (same public
name) — don't leave two separate functions doing the same thing.

---

## 4. `scripts/npc/NPCDebug.gd` — discrete mood event logging

**Anchor:** near `log_relationship_event()`, or end of file.

Insert:

```gdscript
## Discrete mood events (Aug 2026) — one-time mood changes tied to a
## specific cause (currently just passing out), as opposed to
## log_mood()'s continuous per-tick needs/contagion/drift breakdown.
static func log_mood_event(npc: Node, delta: float, reason: String) -> void:
	if not enabled:
		return
	print("%s mood event (%s): %+.1f -> %.1f" % [_fmt(npc), reason, delta, npc.mood])
```

---

## 5. Documentation — comprehensive Trait Effects Reference

This is worth its own clearly-delineated section rather than scattered
mentions, since it'll be the source material for an eventual player-
facing tutorial. Add this as a new top-level section in
`docs/systems/npc/README.md`, replacing/consolidating any trait-effect
mentions currently scattered across the Personality, Relationships,
Give/Takeaway, and Work Ethic sections (leave brief pointers there if you
like, but this should be the canonical, complete list):

```markdown
### Trait Effects Reference (living document — update this whenever a trait gains or changes a mechanical effect)

All 5 traits are continuous 0.0-1.0 values; a trait is only ever
GENERATED for an NPC when it lands outside the neutral middle band
(below `TRAIT_BAND_LOW`=0.35 or above `TRAIT_BAND_HIGH`=0.65) — see
Personality section above. Every multiplier below reads
`personality.get(key, 0.5)`, so an absent trait always behaves as if the
NPC scored a perfectly neutral 0.5 — no separate "is this trait present"
branching needed anywhere the multipliers are used.

**Resilience** (Irritable / — / Level-Headed)
- `_irritability_trait_mult()`, 1.5x (Irritable) to 0.5x (Level-Headed).
  Scales how fast irritability rises from need/mood pressure.
- Same multiplier also scales `get_forgetfulness_chance()` — an
  Irritable NPC is both quicker to anger AND more likely to "forget"
  (wander instead of) a job they were about to start.

**Optimism** (Pessimistic / — / Optimistic)
- `_mood_recovery_trait_mult()`, 0.5x to 1.5x. Scales ONLY how fast mood
  recovers back toward 100 when needs are fine — does not affect how
  fast mood falls in the first place.

**Sociability** (Distant / — / Open)
- `_sociability_trait_mult()`, 0.5x to 1.5x. Scales the magnitude of
  EVERY relationship change in both directions, via
  `_adjust_relationship()`'s single mutation point: passive proximity
  drift, Give's bonus, Takeaway's penalty, and the -3 penalty for
  pulling an NPC off a relax session to do a job. (Relationship Snatch's
  outcome is deliberately relationship-NEUTRAL and untouched by this.)
  A high-Sociability NPC's relationship with you moves faster in BOTH
  directions — quicker to warm up, quicker to sour.

**Work Ethic** (Lazy / — / Hard Worker)
- `get_work_ethic_job_mult()`, 0.7x-1.3x, applied directly to
  `JobActivity.score()`.
- `get_work_ethic_passive_mult()`, the mirror image (1.3x-0.7x), applied
  to Wander/Sit/Lie/Eat/Drink/Relax's scores.
- Lazy specifically (not Hard Worker) gets DOUBLE the daily Relaxing
  budget (2hr vs the 1hr baseline) — this is a deliberate asymmetry, not
  an oversight: Hard Worker does NOT get a reduced relax budget, only
  the score bias above.

**Neuroticism** (Easygoing / — / Neurotic)
- `neuroticism_trait_mult()`, 0.5x to 1.5x. Scales mood's random
  per-tick drift (`MOOD_DRIFT_MAX_PER_GAME_HOUR`) — bigger/smaller
  swings, not a different average.
- Same multiplier scales the ONE-TIME mood drop applied the instant an
  NPC passes out: `randf_range(1.0, 10.0 * neuroticism_trait_mult())`.
  Baseline range 1-10%, Neurotic 1-15%, Easygoing 1-5%. Lower bound is
  always 1% regardless of trait.

### Non-Trait NPC Mechanics Worth Noting Alongside Traits

- **Passing out** (0 Energy): forces `PassedOutActivity`, non-
  interruptible, energy regenerates at 15/game-hour (slower than a chair
  at 25 or a bed at 45 — passing out is a bad outcome, not a rest
  strategy). Wakes at 15 Energy (not full) — deliberately leaves them
  still needing real rest afterward, and is the intended hook for a
  future "administer an energy item" player action. Applies the
  Neuroticism-scaled mood drop above once, at the moment of collapse.
```

**Testing Checklist:**

```
30. Drop an NPC's energy to 0 (F7) and let them pass out — confirm they
    wake up once energy reaches 15, not 100, and remain passed out (still
    lying there, energy climbing) below that.
31. Compare a Neurotic NPC's collapse to an Easygoing one's (same F7
    energy-drain test) — confirm the Neurotic one's mood drop is
    noticeably larger on average (up to 15%) than the Easygoing one's (up
    to 5%), with F7 debug logging showing the exact roll each time.
```
