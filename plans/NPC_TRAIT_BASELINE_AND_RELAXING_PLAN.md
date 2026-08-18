# Trait-Absence-Is-Baseline + Relaxing Activity (Aug 2026)

Two independent changes. Files: `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`.

---

## Part A — Traits only exist when they matter

### Design

Every multiplier function already defaults to `personality.get(key, 0.5)`,
and every one of those lerps to exactly 1.0 at 0.5 — so mechanically,
"trait absent" and "trait present at exactly baseline" are ALREADY
identical. The only real change needed: generation should stop storing
values that land in the neutral middle band at all, and the word-display
functions need to treat an absent key as "nothing to show" instead of
defaulting to the mid-band word ("Even-Tempered", etc.).

An NPC can now end up with anywhere from 0 to 5 personality words —
most will land somewhere in between.

### 1. `scripts/npc/NPC.gd` — generation

**Anchor:**

```gdscript
func randomize_personality() -> void:
	for k: String in PERSONALITY_TRAIT_KEYS:
		personality[k] = randf()
```

Replace with:

```gdscript
## Chance any given trait slot is actually present (a notable quirk) at
## all, rather than baseline/absent. Not guaranteed per-NPC — an NPC
## could rarely end up with 0 traits or all 5, most land in between.
const TRAIT_PRESENCE_CHANCE: float = 0.55

func randomize_personality() -> void:
	personality = {}
	for k: String in PERSONALITY_TRAIT_KEYS:
		if randf() >= TRAIT_PRESENCE_CHANCE:
			continue   ## absent entirely — every _*_trait_mult()'s .get(key, 0.5) default already means baseline
		## A PRESENT trait is by definition not neutral — skew into the
		## low or high band, never the dead middle.
		personality[k] = randf_range(0.0, TRAIT_BAND_LOW) if randf() < 0.5 \
			else randf_range(TRAIT_BAND_HIGH, 1.0)
```

### 2. `scripts/npc/NPC.gd` — word display

**Anchor:**

```gdscript
func get_trait_word(key: String) -> String:
	var v: float = float(personality.get(key, 0.5))
	var bands: Dictionary = TRAIT_WORDS.get(key, {})
	if bands.is_empty():
		return ""
	if v < TRAIT_BAND_LOW:
		return bands["low"]
	elif v > TRAIT_BAND_HIGH:
		return bands["high"]
	return bands["mid"]
```

Replace with:

```gdscript
func get_trait_word(key: String) -> String:
	if not personality.has(key):
		return ""   ## baseline — no notable trait, nothing to show
	var v: float = float(personality[key])
	var bands: Dictionary = TRAIT_WORDS.get(key, {})
	if bands.is_empty():
		return ""
	if v < TRAIT_BAND_LOW:
		return bands["low"]
	elif v > TRAIT_BAND_HIGH:
		return bands["high"]
	return bands["mid"]   ## shouldn't be reachable given generation above; kept as a safe fallback
```

**Anchor:**

```gdscript
func get_personality_words() -> Array[String]:
	var out: Array[String] = []
	for k: String in PERSONALITY_TRAIT_KEYS:
		out.append(get_trait_word(k))
	return out
```

Replace with:

```gdscript
func get_personality_words() -> Array[String]:
	var out: Array[String] = []
	for k: String in PERSONALITY_TRAIT_KEYS:
		var w: String = get_trait_word(k)
		if w != "":
			out.append(w)
	return out
```

`has_irritable_trait()` and every `_*_trait_mult()` function need **no
changes** — they already use `.get(key, 0.5)`, which now correctly means
"absent → baseline" automatically.

### 3. `scripts/ui/npc/NPCTalkMenuUI.gd` — empty-list fallback

**Anchor:**

```gdscript
	if _npc != null and _npc.has_method("get_personality_words"):
		personality_label.text = ", ".join(_npc.get_personality_words())
```

Replace with:

```gdscript
	if _npc != null and _npc.has_method("get_personality_words"):
		var words: Array[String] = _npc.get_personality_words()
		personality_label.text = ", ".join(words) if not words.is_empty() else "Nothing stands out"
```

---

## Part B — Relaxing

### Design

A new activity, distinct from Wander/Idle: the NPC sits in a chair or
lies in bed if one's free (delegating entirely to `SitActivity`/
`LieActivity` for the actual arrival/seating mechanics — same
composition pattern `CommandRestActivity` already uses, not a
reimplementation), or just stands in place if neither's available.

Self-limiting to "once or twice a day, ~1hr total" (2hr for Lazy) via a
**daily time budget** rather than precise scheduling — it scores a flat
baseline similar to Wander whenever budget remains, burns the budget
down while active in ~20-40 minute sessions, and naturally produces a
handful of sessions per day without hardcoded timing. Fully
interruptible, so a genuine need (hunger/thirst/energy/forgetfulness)
still preempts it normally.

Asking an NPC to do a job (currently: the "Harvest the plants" command)
while relaxing gets refused the first time that relax session, and
complied-with (at a small relationship cost) the second time.

### 1. `scripts/npc/NPC.gd` — daily budget, job-refusal state, dialogue

**Anchor:** immediately after `get_relationship_dialogue_line()`'s
closing (or any convenient spot in the Relationships/Dialogue area).

Insert:

```gdscript
# ─── Relaxing (Aug 2026) ─────────────────────────────────────────────────
const RELAX_BUDGET_BASELINE: float = 1.0   ## game-hours/day
const RELAX_BUDGET_LAZY: float = 2.0

var _relax_time_used_today: float = 0.0
var _relax_day_clock: float = 0.0   ## game-hours since the last daily reset; wraps at 24
var _relax_job_request_count: int = 0

func has_lazy_trait() -> bool:
	return float(personality.get("work_ethic", 0.5)) < TRAIT_BAND_LOW

func get_relax_daily_budget() -> float:
	return RELAX_BUDGET_LAZY if has_lazy_trait() else RELAX_BUDGET_BASELINE

func get_relax_time_remaining_today() -> float:
	return maxf(0.0, get_relax_daily_budget() - _relax_time_used_today)

func spend_relax_time(h: float) -> void:
	_relax_time_used_today += h

func is_relaxing() -> bool:
	return brain != null and brain.is_relaxing()

func reset_relax_job_requests() -> void:
	_relax_job_request_count = 0

## Called by NPCTalkMenuUI before forcing a job-type command on an NPC
## that's currently relaxing. First call this relax session refuses
## (returns false — caller shows the refusal line, job does NOT happen).
## Second+ call complies, but costs the player -3 relationship.
func request_job_while_relaxing() -> bool:
	_relax_job_request_count += 1
	if _relax_job_request_count <= 1:
		return false
	_adjust_relationship("player", -3.0)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -3.0, "pulled from relaxing to do a job")
	return true

const RELAXING_REFUSAL_LINES: Array[String] = [
	"\"I'm relaxing right now.\"",
	"\"Can it wait? I'm on a break.\"",
	"\"Give me a minute, I'm resting.\"",
]
func get_relaxing_refusal_line() -> String:
	return RELAXING_REFUSAL_LINES[randi() % RELAXING_REFUSAL_LINES.size()]
```

### 2. `scripts/npc/NPC.gd` — daily reset tick

**Anchor:** inside `_tick_mood_and_irritability(delta)`, the exact call
sequence:

```gdscript
	_tick_mood(h)
	_tick_irritability(h)
	_tick_relationships(h)
```

Replace with:

```gdscript
	_tick_mood(h)
	_tick_irritability(h)
	_tick_relationships(h)
	_tick_relax_day(h)
```

Add the function itself nearby (e.g. right after `_tick_relationships()`):

```gdscript
## Resets the daily relax budget once a full in-game day (24 game-hours)
## has elapsed. Same 5s tick cadence as everything else in this function.
func _tick_relax_day(h: float) -> void:
	_relax_day_clock += h
	if _relax_day_clock >= 24.0:
		_relax_day_clock = fmod(_relax_day_clock, 24.0)
		_relax_time_used_today = 0.0
```

### 3. `scripts/npc/NPCBrain.gd` — register the candidate + brain-level check

**Anchor:** `setup()`'s candidate list:

```gdscript
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
	]
```

Replace with:

```gdscript
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
		RelaxActivity.new(),
	]
```

**Anchor:** `current_label()`:

```gdscript
func current_label() -> String:
	return _current.label() if _current != null else "Idle"
```

Insert immediately after it:

```gdscript

func is_relaxing() -> bool:
	return _current is RelaxActivity
```

### 4. `scripts/npc/NPCBrain.gd` — the `RelaxActivity` class

**Anchor:** add anywhere among the other top-level activity classes —
e.g. right after `WanderActivity`'s closing.

```gdscript
class RelaxActivity extends NPCActivity:
	## Relaxing (Aug 2026) — scheduled break, distinct from Wander/Idle.
	## Delegates entirely to SitActivity/LieActivity for the actual
	## arrival/seating mechanics (same composition CommandRestActivity
	## already uses) — falls back to just standing in place if neither a
	## chair nor a bed is free. Self-limiting via a daily time budget
	## (NPC.get_relax_time_remaining_today()) rather than precise
	## scheduling — see NPC.gd's Relaxing section for the budget/reset
	## logic and Work Ethic's effect on it.
	const BASE_SCORE: float = 6.0   ## edges out Wander's flat 5.0 when both are otherwise idle
	const SESSION_MIN: float = 0.33   ## game-hours (~20 min)
	const SESSION_MAX: float = 0.67   ## game-hours (~40 min)

	var _inner: NPCActivity = null
	var _session_length: float = 0.0
	var _session_elapsed: float = 0.0

	func label() -> String:
		return "Relaxing" if _inner == null else "Relaxing (%s)" % _inner.label()

	func score(npc: NPC) -> float:
		if npc.get_relax_time_remaining_today() <= 0.0:
			return 0.0
		return BASE_SCORE * npc.get_work_ethic_passive_mult()

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		npc.reset_relax_job_requests()
		_session_length = randf_range(SESSION_MIN, SESSION_MAX)
		_session_elapsed = 0.0
		_inner = SitActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):   ## no free chair — try a bed instead
			_inner.exit(npc)
			_inner = LieActivity.new()
			_inner.enter(npc)
			if _inner.done(npc):   ## no free bed either — just stand in place
				_inner.exit(npc)
				_inner = null

	func tick(npc: NPC, delta: float) -> void:
		var h: float = npc.game_hours(delta)
		_session_elapsed += h
		npc.spend_relax_time(h)
		if _inner != null:
			_inner.tick(npc, delta)
		else:
			npc.halt_movement(delta)

	func done(npc: NPC) -> bool:
		if _session_elapsed >= _session_length:
			return true
		if _inner != null:
			return _inner.done(npc)
		return false

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
			_inner = null
```

### 5. `scripts/ui/npc/NPCTalkMenuUI.gd` — job command interception

**Anchor:**

```gdscript
func _on_command_harvest_pressed() -> void:
	_issue_command(NPCBrain.CommandHarvestActivity.new(), "heading to harvest", "nothing ready to harvest")
```

Replace with:

```gdscript
func _on_command_harvest_pressed() -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("is_relaxing") and _npc.is_relaxing():
		if _npc.has_method("request_job_while_relaxing") and not _npc.request_job_while_relaxing():
			if _dialogue_label != null and _npc.has_method("get_relaxing_refusal_line"):
				_dialogue_label.text = _npc.get_relaxing_refusal_line()
				_dialogue_label.visible = true
			return
	_issue_command(NPCBrain.CommandHarvestActivity.new(), "heading to harvest", "nothing ready to harvest")
```

(Apply the same guard to any future job-type command buttons that get
added later — Eat/Drink/Rest are needs/leisure, not jobs, and
deliberately stay ungated.)

---

## Documentation

`docs/systems/npc/README.md`:
- Update the Personality section: traits are now presence-based (0-5
  shown per NPC), absence = baseline, generation skews any present trait
  away from the neutral band. Update the trait table's "wired" status
  note accordingly (mechanism unchanged, just how it's populated/shown).
- Add a **Relaxing** subsection: scheduled break activity, chair/bed
  delegation, daily budget (1hr baseline / 2hr Lazy) via
  `get_relax_time_remaining_today()`, job-refusal-then-comply-with-cost
  mechanic (-3 relationship on the second ask).

**Testing Checklist:**

```
27. Spawn several NPCs — confirm the E-panel shows anywhere from 0 to 5
    personality words per NPC (not always exactly 5), and "Nothing
    stands out" for the rare 0-trait case.
28. Watch an NPC over a full in-game day (F7 fast-forward) — confirm it
    enters "Relaxing" roughly once or twice, ~20-40 min each, sitting/
    lying if a chair/bed is free. Confirm a Lazy NPC's relax budget is
    roughly double a non-Lazy NPC's over the same period.
29. While an NPC is Relaxing, press "Harvest the plants" — confirm the
    first press gets a refusal line and does NOT start the job. Press
    again in the same relax session — confirm the job now starts AND
    relationship drops by 3. Confirm a fresh relax session later resets
    back to a first-press refusal.
```
