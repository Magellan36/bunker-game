# NPC Time-Skip Catch-Up Simulation (Aug 2026)

**Files:** `scripts/npc/NPC.gd` (bulk of it), `scripts/ui/menus/AdminMenu.gd`,
`scripts/ui/menus/SleepOverlay.gd` ⚠️ (one line, flagging in case this
isn't mine to touch — trivial addition, no logic change to existing sleep
behavior).

**Note on what this plan assumes exists:** several functions referenced
below (`get_relax_daily_budget()`, `_relax_time_used_today`,
`_tick_relax_day()`, `neuroticism_trait_mult()`) come from the Relaxing
and Work-Ethic/Neuroticism plans. If those haven't been applied to the
live file yet, apply them first — this plan's anchors won't resolve
without them. Not a ceremonial prerequisite note, just a fact about what
this code calls.

## What currently happens during a time-skip (confirmed by reading the code)

`skip_time_with_drain()` in `PlayerStats.gd` only touches the player's
own food/water. NPCs are completely frozen — same hunger, mood, energy —
while the clock jumps. Farming isn't hooked in either; `FarmPlant.gd`
grows via its own real-time accumulator, unrelated to the skip. This
plan closes the NPC gap. Farming stays exactly as it is — "ready before
the skip" just means whatever's already `is_ready()` at the moment the
skip is triggered, no special handling needed there.

## Design summary

- One new static entry point, `NPC.catch_up_all(hours)`, called once by
  each skip source, right alongside its existing `skip_time_with_drain()`
  call.
- Needs (hunger/thirst): full drain applied for the duration, then an
  ESTIMATE of how many real meals/drinks would have been needed to
  offset that, actually consumed from real available world items (capped
  by what's actually there).
- Energy: full drain applied; if it would have crossed 0 mid-skip, the
  same neuroticism-scaled mood-drop `PassedOutActivity` uses fires once,
  and the remainder regens at `PassedOutActivity`'s own rate.
- Relaxing: today's budget gets proportionally reduced by how much of a
  day the skip covered — stops an NPC from "banking" untouched relax
  time and dumping it all right after waking.
- Mood: needs-driven pull and random drift are the same formulas
  `_tick_mood()` already uses, just evaluated once with a large `h`
  instead of accumulating over many small ticks. Contagion is a single
  blended pull toward the bunker's PRE-skip average mood, scaled by
  elapsed time — deliberately approximate, not a real per-NPC-pair
  simulation.
- Harvest: every plant that's `is_ready()` right now gets snapshotted
  once; each NPC harvests up to `floor(hours)` of them from that shared
  pool (not a per-tray job — a tray can hold several ready plants, and
  each harvested plant counts as one "job" here).
- Hard ceiling (`MAX_CATCHUP_HOURS`) on top of everything else, so no
  single call — buggy input or otherwise — can simulate an unbounded
  amount of consumption.

---

## 1. `scripts/npc/NPC.gd` — the static orchestrator

**Anchor:** anywhere near the top-level static helpers (e.g. right after
the `static var _next_npc_id`/`_register_id()` block).

Insert:

```gdscript
# ─── Time-Skip Catch-Up (Aug 2026) ──────────────────────────────────────────
## Called once by each skip source (F7 Fast-Forward, sleep) right next to
## its existing skip_time_with_drain() call — see AdminMenu.gd/
## SleepOverlay.gd. Any FUTURE skip source needs to call this too; nothing
## here happens automatically off the game clock.
const MAX_CATCHUP_HOURS: float = 72.0   ## hard sanity ceiling regardless of what's requested

static func catch_up_all(hours: float) -> void:
	var h: float = clampf(hours, 0.0, MAX_CATCHUP_HOURS)
	if h <= 0.0:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var npcs: Array = tree.get_nodes_in_group("npc")

	## Mood contagion snapshot — average taken BEFORE any catch-up changes
	## anyone's mood, so every NPC pulls toward the same pre-skip picture
	## of the bunker rather than a moving target as each one gets processed.
	var mood_total: float = 0.0
	var mood_count: int = 0
	for n: Node in npcs:
		if is_instance_valid(n) and ("mood" in n):
			mood_total += float(n.mood)
			mood_count += 1
	var avg_mood_before: float = (mood_total / mood_count) if mood_count > 0 else 50.0

	## Harvest — snapshot every plant ready RIGHT NOW, once, before any
	## NPC starts consuming from the pool. One harvested plant = one
	## "job," NOT one JobBoard tray-job (a tray can hold several ready
	## plants at once — see JobBoard._scan_harvest()).
	var ready_plants: Array = []
	for tray: Node in tree.get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray) or not ("plant_refs" in tray):
			continue
		for plant in tray.plant_refs:
			if plant != null and is_instance_valid(plant) and plant.has_method("is_ready") and plant.is_ready():
				ready_plants.append(plant)

	var jobs_per_npc: int = int(floor(h))
	var pool_index: int = 0
	for n: Node in npcs:
		if not is_instance_valid(n):
			continue
		var completed: int = 0
		while completed < jobs_per_npc and pool_index < ready_plants.size():
			var plant: Node = ready_plants[pool_index]
			pool_index += 1
			if is_instance_valid(plant) and plant.has_method("is_ready") and plant.is_ready() and plant.has_method("harvest"):
				plant.harvest()
				completed += 1
		if n.has_method("catch_up_time"):
			n.catch_up_time(h, avg_mood_before)
```

---

## 2. `scripts/npc/NPC.gd` — per-NPC catch-up

**Anchor:** a sensible spot near the Relationships/Relaxing sections —
anywhere consistent is fine.

Insert:

```gdscript
## Per-item restore estimates used ONLY to compute how many real items to
## consume during catch-up — the actual restore applied always comes from
## the real item's own consume_as_food()/take_bite()/take_drink() call,
## never this constant directly. Rough averages across the giveable item
## types (dish/produce/can-bite ≈ 45 hunger; STANDARD_HYDRATION = 21.5).
const CATCHUP_MEAL_RESTORE_ESTIMATE: float = 45.0
const CATCHUP_DRINK_RESTORE_ESTIMATE: float = 21.5
## Matches PassedOutActivity.REGEN_PER_GAME_HOUR (NPCBrain.gd) — duplicated
## here since that constant lives on a different class; keep these in sync
## if that value ever changes.
const CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR: float = 15.0

## Entry point called by NPC.catch_up_all() for each NPC. Order matters:
## needs/energy run first so mood's needs-driven target reflects the
## post-catch-up state, not stale pre-skip numbers.
func catch_up_time(h: float, avg_mood_before: float) -> void:
	if h <= 0.0:
		return
	var needs_avg_before: float = (energy + hunger + thirst) / 3.0
	_catch_up_hunger_and_thirst(h)
	_catch_up_energy(h)
	_catch_up_relax_budget(h)
	var needs_avg_after: float = (energy + hunger + thirst) / 3.0
	_catch_up_mood(h, avg_mood_before, (needs_avg_before + needs_avg_after) / 2.0)
	if NPCDebug.enabled:
		NPCDebug.log_catchup(self, h)

## Full drain for the duration, then an ESTIMATE of how many real meals/
## drinks would've been needed to offset that — actually consumed from
## real available world items (capped by whatever's actually there; an
## empty bunker just means the NPC goes hungry, same as it should). This
## is deliberately an approximation of WHEN — we don't simulate which
## specific hour they'd have eaten, only roughly how many real items
## would have been used.
func _catch_up_hunger_and_thirst(h: float) -> void:
	hunger = maxf(0.0, hunger - HUNGER_DRAIN_PER_GAME_HOUR * h)
	var meals_needed: int = int(floor((HUNGER_DRAIN_PER_GAME_HOUR * h) / CATCHUP_MEAL_RESTORE_ESTIMATE))
	for i in range(meals_needed):
		if hunger >= 90.0:
			break   ## already comfortably fed from what's been eaten so far
		var item: Node = NPCItemUser.find_loose_item(self, Callable(NPCItemUser, "is_edible"))
		if item == null:
			break   ## nothing available — stays hungry, same as reality
		if item is DishItem or item is FarmProduceItem:
			hunger = minf(100.0, hunger + item.consume_as_food())
		elif item.has_method("take_bite"):
			hunger = minf(100.0, hunger + item.take_bite())

	thirst = maxf(0.0, thirst - THIRST_DRAIN_PER_GAME_HOUR * h)
	var drinks_needed: int = int(floor((THIRST_DRAIN_PER_GAME_HOUR * h) / CATCHUP_DRINK_RESTORE_ESTIMATE))
	for i in range(drinks_needed):
		if thirst >= 90.0:
			break
		var item: Node = NPCItemUser.find_loose_item(self, Callable(NPCItemUser, "is_drinkable_bottle"))
		if item == null:
			break
		if item.has_method("take_drink"):
			thirst = minf(100.0, thirst + item.take_drink())

## Straight drain; if it would have crossed 0 partway through, applies
## the SAME neuroticism-scaled mood drop PassedOutActivity.enter() uses
## (once, not per-hour) and regenerates the remaining time at its rate —
## ties directly into the pass-out mechanic instead of inventing a
## separate energy-recovery model for catch-up specifically.
func _catch_up_energy(h: float) -> void:
	var drain: float = ENERGY_DRAIN_PER_GAME_HOUR * h
	if drain <= energy:
		energy -= drain
		return
	var hours_until_zero: float = energy / ENERGY_DRAIN_PER_GAME_HOUR
	var remaining_hours: float = h - hours_until_zero
	var mood_drop: float = randf_range(1.0, 10.0 * neuroticism_trait_mult())
	mood = clampf(mood - mood_drop, 0.0, 100.0)
	if NPCDebug.enabled:
		NPCDebug.log_mood_event(self, -mood_drop, "passed out (time-skip catch-up)")
	energy = minf(100.0, 0.0 + CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR * remaining_hours)

## Deducts today's relax budget proportionally to how much of a day the
## skip covered — a 6h skip removes 25% of the daily budget (baseline:
## 60min → 45min remaining), 12h removes 50% (→ 30min). This is what
## stops an NPC "banking" a full untouched hour across a skip and
## dumping it all in one greedy session right after waking. Runs
## _tick_relax_day() FIRST so a skip crossing a full day boundary resets
## to a fresh budget as it should, then applies the proportional
## deduction only to whatever fractional day remains after that.
func _catch_up_relax_budget(h: float) -> void:
	_tick_relax_day(h)
	var effective_hours: float = fmod(h, 24.0) if h >= 24.0 else h
	var budget: float = get_relax_daily_budget()
	var fraction: float = clampf(effective_hours / 24.0, 0.0, 1.0)
	_relax_time_used_today = clampf(_relax_time_used_today + budget * fraction, 0.0, budget)

## Needs-driven pull and random drift are _tick_mood()'s own formulas,
## evaluated once with a large h instead of accumulating over many small
## ticks — both are simple enough (move_toward, flat random range) that
## batching doesn't lose meaningful accuracy. `needs_avg_blend` is the
## average of pre- and post-catch-up needs, a rough stand-in for "how
## needs behaved across the whole window" rather than just the endpoint
## (needs dipped low mid-skip then got restored — using only the end
## value would understate how much that dip should have dragged mood).
## Contagion is a single blended pull toward the PRE-skip bunker average
## (avg_mood_before, snapshotted once in catch_up_all()), scaled by
## elapsed time and clamped so it can't overshoot past that average —
## deliberately approximate, not a real per-NPC-pair simulation.
func _catch_up_mood(h: float, avg_mood_before: float, needs_avg_blend: float) -> void:
	var mood_target: float = 100.0 if needs_avg_blend >= MOOD_FINE_THRESHOLD else needs_avg_blend
	var rate: float = MOOD_CHANGE_PER_GAME_HOUR
	if mood_target > mood:
		rate *= _mood_recovery_trait_mult()
	mood = move_toward(mood, mood_target, rate * h)

	var blend: float = clampf(MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * h, 0.0, 1.0)
	mood = clampf(mood + (avg_mood_before - mood) * blend, 0.0, 100.0)

	mood = clampf(mood + randf_range(-MOOD_DRIFT_MAX_PER_GAME_HOUR, MOOD_DRIFT_MAX_PER_GAME_HOUR)
		* neuroticism_trait_mult() * h, 0.0, 100.0)
```

---

## 3. `scripts/npc/NPCDebug.gd` — catch-up logging

**Anchor:** end of file, or near `log_relationship_event()`.

Insert:

```gdscript
## Time-skip catch-up (Aug 2026) — one summary line per NPC per skip, so
## it's visible what the estimate produced without stepping through it.
static func log_catchup(npc: Node, hours: float) -> void:
	if not enabled:
		return
	print("%s catch-up (%.1fh skip): hunger=%.1f thirst=%.1f energy=%.1f mood=%.1f" \
		% [_fmt(npc), hours, npc.hunger, npc.thirst, npc.energy, npc.mood])
```

---

## 4. Call sites

### `scripts/ui/menus/AdminMenu.gd`

**Anchor:** `_on_fast_forward_pressed()`:

```gdscript
func _on_fast_forward_pressed() -> void:
```

Find the line calling `stats.skip_time_with_drain(24.0)` inside this
function and add immediately after it:

```gdscript
	NPC.catch_up_all(24.0)
```

### `scripts/ui/menus/SleepOverlay.gd` ⚠️

**Anchor:** wherever `player_stats.skip_time_with_drain(SLEEP_SKIP_HOURS)`
is called.

Add immediately after it:

```gdscript
	NPC.catch_up_all(SLEEP_SKIP_HOURS)
```

---

## Documentation

`docs/systems/npc/README.md` — new section, "Time-Skip Catch-Up":
describe `NPC.catch_up_all()` as the single entry point, note that any
future skip source must call it explicitly (nothing hooks into the game
clock automatically), and summarize each piece (needs/energy estimate-
and-consume model, relax budget proportional deduction with the worked
6h/12h examples, mood's batched formulas + approximate contagion,
harvest's shared-pool/1-plant-per-hour-per-NPC model). Add to the Trait
Effects Reference: Neuroticism's multiplier now also scales the pass-out
mood-drop when triggered via catch-up, not just the live
`PassedOutActivity` path — same formula, just reachable two ways now.

**Testing Checklist:**

```
32. Set an NPC's hunger/thirst low, ensure real food/water exists nearby,
    fast-forward 24h — confirm hunger/thirst end up in a reasonable range
    (not maxed, not zeroed) and that real items in the world were
    actually consumed/depleted (check counts before/after).
33. Empty the bunker of food/water entirely, fast-forward — confirm the
    NPC's hunger/thirst just drain fully with no error, nothing crashes
    trying to consume items that don't exist.
34. Drain an NPC's energy most of the way down, fast-forward 24h — confirm
    if it crosses 0 during the estimate, mood drops once (F7 log shows
    it) and energy ends up partially recovered, not stuck at 0 or jumped
    to full.
35. Note an NPC's remaining relax budget, sleep 6 hours — confirm the
    remaining budget drops by ~25% of the daily total, not to zero and
    not unchanged.
36. Have 2+ ready-to-harvest plants across trays before a fast-forward —
    confirm they get harvested during the skip (real produce appears),
    and that plants which were NOT ready before the skip do NOT get
    auto-harvested even if the skip's growth would have made them ready
    (since growth isn't currently tied to skips at all, this should
    already hold true, but worth confirming directly).
```
