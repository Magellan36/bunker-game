# Wire Up Work Ethic + Neuroticism (Aug 2026)

**File:** `scripts/npc/NPC.gd` and `scripts/npc/NPCBrain.gd` only.

## Design

**Work Ethic** — translated "30% more/less likely" into a ±30% score
multiplier, applied symmetrically: `JobActivity` gets the multiplier
directly, every passive/need activity named (Wander, Sit, Lie, Eat,
Drink) gets its inverse. This mirrors how Irritability already discourages
job-taking in `JobActivity.score()` (a direct multiplier, not a random
roll) — kept the pattern consistent rather than introducing a second kind
of trait mechanism. Flagging this translation explicitly: this is a
continuous score bias, not a literal "30% of the time" dice roll like
Forgetfulness uses — let me know if you actually wanted the latter.

- Hard Worker (work_ethic → 1.0): jobs ×1.3, passive activities ×0.7
- Steady (0.5): ×1.0 both ways (no change from current behavior)
- Lazy (0.0): jobs ×0.7, passive activities ×1.3

**Neuroticism** — mood already has a random per-tick "drift" component
(`MOOD_DRIFT_MAX_PER_GAME_HOUR`, ±1.0/game-hour) sitting right there,
unscaled by anything — the natural hook rather than inventing a new
mechanism. Same 0.5x–1.5x spread as Sociability's multiplier, for
consistency across traits.

- Neurotic (1.0): drift range ×1.5 — bigger, more erratic swings
- Composed (0.5): ×1.0 — unchanged from current behavior
- Easygoing (0.0): drift range ×0.5 — calmer, steadier

---

## 1. `scripts/npc/NPC.gd` — two new trait multiplier functions

**Anchor:** immediately after `_sociability_trait_mult()`.

Insert:

```gdscript

## Work Ethic (Aug 2026) — ±30% score multiplier on JobActivity, applied
## directly. Passive/need activities (Wander, Sit, Lie, Eat, Drink) use
## get_work_ethic_passive_mult() below, its mirror image — so a Lazy NPC
## doesn't just work less, it visibly prefers wandering/relaxing/eating
## over an available job by the same margin, and Hard Worker is the
## opposite.
func get_work_ethic_job_mult() -> float:
	return lerp(0.7, 1.3, float(personality.get("work_ethic", 0.5)))

func get_work_ethic_passive_mult() -> float:
	return lerp(1.3, 0.7, float(personality.get("work_ethic", 0.5)))

## Neuroticism (Aug 2026) — scales mood's random per-tick drift
## (MOOD_DRIFT_MAX_PER_GAME_HOUR in _tick_mood()) — NOT the needs-driven
## or contagion components, just the noise. Same 0.5x-1.5x spread as
## Sociability, for consistency.
func _neuroticism_trait_mult() -> float:
	return lerp(0.5, 1.5, float(personality.get("neuroticism", 0.5)))
```

---

## 2. `scripts/npc/NPC.gd` — apply Neuroticism to the drift tick

**Anchor:** inside `_tick_mood()`:

```gdscript
	before = mood
	mood = clampf(mood + randf_range(-MOOD_DRIFT_MAX_PER_GAME_HOUR, MOOD_DRIFT_MAX_PER_GAME_HOUR) * h, 0.0, 100.0)
	_mood_drift_delta = mood - before
```

Replace with:

```gdscript
	before = mood
	mood = clampf(mood + randf_range(-MOOD_DRIFT_MAX_PER_GAME_HOUR, MOOD_DRIFT_MAX_PER_GAME_HOUR) * _neuroticism_trait_mult() * h, 0.0, 100.0)
	_mood_drift_delta = mood - before
```

---

## 3. `scripts/npc/NPCBrain.gd` — apply Work Ethic to all six activities

**Anchor:** `JobActivity.score()`'s return line:

```gdscript
		var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
		return base_score * willingness
```

Replace with:

```gdscript
		var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
		return base_score * willingness * npc.get_work_ethic_job_mult()
```

**Anchor:** `WanderActivity.score()`:

```gdscript
	func score(_npc: NPC) -> float:
		return 5.0   ## constant baseline — always available, loses to any need
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		return 5.0 * npc.get_work_ethic_passive_mult()   ## constant baseline — always available, loses to any need
```

**Anchor:** `SitActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_chair(npc) == null:
			return 0.0
		return (100.0 - npc.energy)   ## 40..100 as energy falls 60→0
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_chair(npc) == null:
			return 0.0
		return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()   ## 40..100 as energy falls 60→0
```

**Anchor:** `LieActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_bed(npc) == null:
			return 0.0
		return (100.0 - npc.energy)
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_bed(npc) == null:
			return 0.0
		return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()
```

**Anchor:** `EatActivity.score()` — checked against the live file directly
(it does not currently have any snatch-related check in it, regardless of
what an earlier plan assumed):

```gdscript
	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty():
			return 0.0
		return (100.0 - npc.hunger) * 1.15
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty():
			return 0.0
		return (100.0 - npc.hunger) * 1.15 * npc.get_work_ethic_passive_mult()
```

**Anchor:** `DrinkActivity.score()`'s final return line — also checked
against the live file:

```gdscript
		return (100.0 - npc.thirst) * 1.2   ## thirst outranks equal-level energy
```

Replace with:

```gdscript
		return (100.0 - npc.thirst) * 1.2 * npc.get_work_ethic_passive_mult()   ## thirst outranks equal-level energy
```

---

## Documentation

`docs/systems/npc/README.md` — move Work Ethic and Neuroticism from
"generated/displayed only" to wired, describing the ±30%/±50% multipliers
above. Update the Personality section's trait table.

**Testing Checklist:**

```
25. Spawn two NPCs, force one to Lazy and one to Hard Worker (F7 or
    respawn until you get the words you want in the E-panel). With an
    open job and normal needs on both, confirm the Hard Worker picks the
    job noticeably more often/faster, and the Lazy one prefers wandering/
    sitting/eating over it.
26. Watch mood drift over several in-game hours on a Neurotic vs an
    Easygoing NPC with stable needs — confirm the Neurotic one's mood
    visibly swings more per tick (F7 debug mood log) than the Easygoing
    one, without either trending toward a different average.
```
