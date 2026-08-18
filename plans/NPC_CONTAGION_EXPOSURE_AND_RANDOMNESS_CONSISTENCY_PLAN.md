# Exposure-Weighted Mood Contagion + Randomness Consistency Pass (Aug 2026)

**File:** `scripts/npc/NPC.gd` only.

---

## Part A — Mood contagion weighted by exposure time

### Design

Currently `_tick_mood()`'s contagion component averages ALL other NPCs'
moods equally, regardless of distance or history — an NPC clear across
the bunker pulls exactly as hard as one they've been standing next to
all day. This adds a per-pair **exposure score**: builds up while two
NPCs are near each other (same proximity range the Relationships system
already uses, for one consistent "what counts as together" definition
across both systems), decays back down while apart. The contagion target
becomes an exposure-*weighted* average instead of a flat one — someone
you've spent a lot of recent time near pulls your mood much harder than
someone you've barely crossed paths with, even if both are technically
"in the bunker."

Deliberately NOT extended to the time-skip catch-up's contagion
calculation — that one already uses a single pre-skip bunker-wide
snapshot as an accepted simplification, and weighting it by exposure
would require snapshotting every NPC's exposure map too, adding real
complexity to something already explicitly treated as an approximation.
Live contagion only.

### 1. `scripts/npc/NPC.gd` — exposure tracking

**Anchor:** near the Relationships section (exposure reuses
`RELATIONSHIP_PROXIMITY_RANGE`, so keeping it nearby makes that shared
dependency obvious).

Insert:

```gdscript
# ─── Mood Contagion Exposure Weighting (Aug 2026) ───────────────────────────
const CONTAGION_EXPOSURE_GAIN_PER_GAME_HOUR: float = 0.5
const CONTAGION_EXPOSURE_DECAY_PER_GAME_HOUR: float = 0.2
const CONTAGION_EXPOSURE_MAX: float = 5.0
var _contagion_exposure: Dictionary = {}   ## other npc_id -> 0..CONTAGION_EXPOSURE_MAX

## Same 5s tick cadence and the SAME proximity range the Relationships
## system already uses (RELATIONSHIP_PROXIMITY_RANGE) — one consistent
## definition of "together" across both systems, not a second threshold.
func _tick_contagion_exposure(h: float) -> void:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		var id: String = other.npc_id
		var current: float = float(_contagion_exposure.get(id, 0.0))
		if NPCItemUser.flat_distance(global_position, other.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			current = minf(CONTAGION_EXPOSURE_MAX, current + CONTAGION_EXPOSURE_GAIN_PER_GAME_HOUR * h)
		else:
			current = maxf(0.0, current - CONTAGION_EXPOSURE_DECAY_PER_GAME_HOUR * h)
		_contagion_exposure[id] = current

## Weighted average of every other NPC's mood, weighted by this NPC's
## accumulated exposure to them. Someone with zero recent exposure
## contributes nothing at all, not a diluted "everyone counts a little."
## Returns this NPC's own current mood (a no-op target) if nobody has any
## exposure yet — e.g. a freshly-spawned NPC with no history.
func _compute_weighted_contagion_target() -> float:
	var weighted_sum: float = 0.0
	var weight_total: float = 0.0
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("mood" in other) or not ("npc_id" in other):
			continue
		var exposure: float = float(_contagion_exposure.get(other.npc_id, 0.0))
		if exposure <= 0.0:
			continue
		weighted_sum += float(other.mood) * exposure
		weight_total += exposure
	if weight_total <= 0.0:
		return mood
	return weighted_sum / weight_total
```

### 2. `scripts/npc/NPC.gd` — wire it into `_tick_mood()`

**Anchor:** the exact current contagion block:

```gdscript
	before = mood
	var others: Array = get_tree().get_nodes_in_group("npc")
	var total: float = 0.0
	var count: int = 0
	for other: Node in others:
		if other == self or not is_instance_valid(other) or not ("mood" in other):
			continue
		total += float(other.mood)
		count += 1
	if count > 0:
		var avg_other: float = total / float(count)
		mood = clampf(mood + (avg_other - mood) * MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * get_contagion_sociability_mult() * h, 0.0, 100.0)
	_mood_contagion_delta = mood - before
```

Replace with:

```gdscript
	before = mood
	var contagion_target: float = _compute_weighted_contagion_target()
	mood = clampf(mood + (contagion_target - mood) * MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * get_contagion_sociability_mult() * h, 0.0, 100.0)
	_mood_contagion_delta = mood - before
```

### 3. `scripts/npc/NPC.gd` — tick the exposure tracker

**Anchor:** inside `_tick_mood_and_irritability(delta)`, alongside the
other 5s-cadence calls (`_tick_relationships(h)`, `_tick_relax_day(h)`,
etc. — exact surrounding lines depend on which prior plans landed; add
this call anywhere in that same chain):

```gdscript
	_tick_contagion_exposure(h)
```

---

## Part B — Randomness consistency pass

### What's actually inconsistent (and what isn't)

Looked through every randomness mechanic built so far. Two genuine
duplications worth consolidating:

1. **Coinflip-sign selection** — inlined as `randf() < 0.5` differently
   in personality trait generation and the Talk relationship swing,
   rather than one shared helper.
2. **Threshold-scaled probability curves** — Snatch and Give-to-Friend
   independently reimplement the exact same "chance ramps linearly from
   a threshold value up to an extreme" formula, just in opposite
   directions and with slightly different variable names.

**Deliberately NOT touched:** trait multiplier ranges (0.5x-1.5x vs.
0.67x-1.33x vs. 0.7x-1.3x) are intentionally different per your explicit
percentage requests for each trait — not a bug, don't unify these.
Random *range* picks (session lengths, cooldown windows) already
consistently use `randf_range(MIN, MAX)` everywhere — no change needed
there either.

### 1. `scripts/npc/NPC.gd` — the two shared helpers

**Anchor:** anywhere near the top-level utility functions.

Insert:

```gdscript
# ─── Shared Randomness Helpers (Aug 2026 consistency pass) ──────────────────
## Centralizes two patterns that were being reimplemented slightly
## differently in multiple places — existing per-mechanic constants
## (SNATCH_CHANCE_AT_THRESHOLD, etc.) are unchanged, only the FORMULA
## itself is now shared instead of duplicated.

func _random_sign() -> float:
	return 1.0 if randf() < 0.5 else -1.0

## direction = +1.0 for "chance increases as value rises above threshold"
## (Give-to-Friend), -1.0 for "chance increases as value falls below
## threshold" (Snatch). Handles both with one formula.
func _threshold_scaled_chance(value: float, threshold: float, extreme: float,
		chance_at_threshold: float, chance_at_extreme: float, direction: float) -> float:
	if direction > 0.0 and value < threshold:
		return 0.0
	if direction < 0.0 and value > threshold:
		return 0.0
	var span: float = extreme - threshold
	if absf(span) < 0.0001:
		return chance_at_threshold
	var t: float = clampf((value - threshold) / span, 0.0, 1.0)
	return lerp(chance_at_threshold, chance_at_extreme, t)
```

### 2. `scripts/npc/NPC.gd` — `randomize_personality()` uses `_random_sign()`

**Anchor:**

```gdscript
		personality[k] = randf_range(0.0, TRAIT_BAND_LOW) if randf() < 0.5 \
			else randf_range(TRAIT_BAND_HIGH, 1.0)
```

Replace with:

```gdscript
		personality[k] = randf_range(0.0, TRAIT_BAND_LOW) if _random_sign() > 0.0 \
			else randf_range(TRAIT_BAND_HIGH, 1.0)
```

### 3. `scripts/npc/NPC.gd` — `get_snatch_chance_toward()` uses the shared curve

**Anchor:**

```gdscript
func get_snatch_chance_toward(target_id: String) -> float:
	var rel: float = get_relationship(target_id)
	if rel > SNATCH_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(SNATCH_RELATIONSHIP_THRESHOLD - rel) / (SNATCH_RELATIONSHIP_THRESHOLD - RELATIONSHIP_MIN),
		0.0, 1.0)
	return lerp(SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, t)
```

Replace with:

```gdscript
func get_snatch_chance_toward(target_id: String) -> float:
	return _threshold_scaled_chance(get_relationship(target_id), SNATCH_RELATIONSHIP_THRESHOLD,
		RELATIONSHIP_MIN, SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, -1.0)
```

### 4. `scripts/npc/NPC.gd` — `get_give_to_friend_chance()` uses the shared curve

**Anchor:**

```gdscript
func get_give_to_friend_chance(rel: float) -> float:
	if rel < GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(rel - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD) / (RELATIONSHIP_MAX - GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD),
		0.0, 1.0)
	return lerp(GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD, GIVE_TO_FRIEND_CHANCE_AT_MAX, t)
```

Replace with:

```gdscript
func get_give_to_friend_chance(rel: float) -> float:
	return _threshold_scaled_chance(rel, GIVE_TO_FRIEND_RELATIONSHIP_THRESHOLD,
		RELATIONSHIP_MAX, GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD, GIVE_TO_FRIEND_CHANCE_AT_MAX, 1.0)
```

### 5. `scripts/npc/NPC.gd` — `apply_talk_relationship_swing()` uses `_random_sign()`

**Note:** this function comes from the mutual-relationship/swing plan,
which hasn't landed in the live file yet as of this writing — apply that
one first, or this anchor won't exist yet to edit.

**Anchor:**

```gdscript
	var base_delta: float = magnitude if randf() < 0.5 else -magnitude
```

Replace with:

```gdscript
	var base_delta: float = magnitude * _random_sign()
```

## Testing

```
63. Have NPC A spend a long stretch near NPC B and barely any time near
    NPC C (all three moods different) — confirm A's mood contagion pulls
    noticeably harder toward B than toward C, not an equal blend of both.
64. Confirm a freshly-spawned NPC with zero exposure to anyone doesn't
    get pulled by contagion at all until they've actually spent some time
    near someone.
65. Spot-check Snatch and Give-to-Friend chances at a few relationship
    values (25, 60, 100 for Give-to-Friend; -50, -75, -100 for Snatch) —
    confirm the numbers match exactly what they did before this
    refactor (this should be a pure behavior-preserving consolidation,
    not a tuning change).
```
