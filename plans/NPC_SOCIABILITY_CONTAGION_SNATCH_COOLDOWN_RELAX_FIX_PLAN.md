# Sociability→Contagion, Snatch/Gift Cooldown + Live Log, Relax Spacing Fix (Aug 2026)

**Files:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`. No Player-subsystem changes —
`can_receive_item()`'s new parameter defaults to `"player"`, so
`InteractionSystem.gd`'s existing call site needs zero changes.

---

## Part A — Sociability scales mood contagion (±33%)

### `scripts/npc/NPC.gd`

**Anchor:** near `_sociability_trait_mult()`.

Insert:

```gdscript
## Separate from _sociability_trait_mult() (0.5x-1.5x, relationship
## magnitude) — this is its own smaller-range multiplier specifically for
## mood contagion receptivity: how much THIS NPC's own mood gets pulled
## toward the group average, not how much they influence others. 0.67x
## (Distant) to 1.33x (Open), 1.0x at baseline/absent.
func get_contagion_sociability_mult() -> float:
	return lerp(0.67, 1.33, float(personality.get("sociability", 0.5)))
```

**Anchor:** inside `_tick_mood()`, the contagion line:

```gdscript
		mood = clampf(mood + (avg_other - mood) * MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * h, 0.0, 100.0)
```

Replace with:

```gdscript
		mood = clampf(mood + (avg_other - mood) * MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * get_contagion_sociability_mult() * h, 0.0, 100.0)
```

**Anchor:** inside `_catch_up_mood()` (time-skip catch-up), the contagion
blend line:

```gdscript
	var blend: float = clampf(MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * h, 0.0, 1.0)
```

Replace with:

```gdscript
	var blend: float = clampf(MOOD_CONTAGION_STRENGTH_PER_GAME_HOUR * get_contagion_sociability_mult() * h, 0.0, 1.0)
```

(`_mood_contagion_delta`, used by the Action Log's threshold-based
contagion logging, is computed AFTER this line already — it automatically
reflects the Sociability-scaled value with no changes needed there.)

---

## Part B — Snatch → Gift cooldown (per attacker↔victim pair)

Blocks specifically the NPC or player who was JUST snatched from, from
gifting back to that SAME attacker, for 60 seconds — not a general
"this NPC is scary" flag. An uninvolved third party's ability to gift
the attacker is completely unaffected (they were never in the
attacker's cooldown list to begin with).

### 1. `scripts/npc/NPC.gd` — cooldown tracking + gate

**Anchor:** near the Snatch section.

Insert:

```gdscript
# ─── Snatch → Gift Cooldown (Aug 2026) ──────────────────────────────────────
const SNATCH_GIFT_COOLDOWN_SEC: float = 60.0
var _snatch_cooldown_from: Dictionary = {}   ## victim_id (npc_id or "player") -> msec of last snatch attempt against them

## Called by SnatchActivity every tick while actively pursuing a specific
## target — refreshes so the 60s always counts from the LAST moment of
## active pursuit against that victim, not just the initial decision.
func start_snatch_cooldown_against(victim_id: String) -> void:
	_snatch_cooldown_from[victim_id] = Time.get_ticks_msec()

func is_gift_blocked_from(giver_id: String) -> bool:
	if not _snatch_cooldown_from.has(giver_id):
		return false
	var last: int = _snatch_cooldown_from[giver_id]
	return (Time.get_ticks_msec() - last) < int(SNATCH_GIFT_COOLDOWN_SEC * 1000.0)
```

### 2. `scripts/npc/NPC.gd` — `can_receive_item()` gains a giver

**Anchor:** the current function:

```gdscript
func can_receive_item(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if held_item != null:
		return false
	return NPCItemUser.is_giveable(item)
```

Replace with:

```gdscript
## giver_id defaults to "player" — InteractionSystem.gd's existing call
## site (target.can_receive_item(item)) needs zero changes.
func can_receive_item(item: Node, giver_id: String = "player") -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if held_item != null:
		return false
	if is_gift_blocked_from(giver_id):
		return false
	return NPCItemUser.is_giveable(item)
```

### 3. `scripts/npc/NPCBrain.gd` — `SnatchActivity` starts/refreshes the cooldown

**Anchor:** inside `tick()`, the "still targeting" branch, right after
the chase-timer increment (near the top of `tick()`):

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		_chase_timer += delta
```

Insert immediately after, still inside `tick()` before the early-return
checks:

```gdscript
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			npc.start_snatch_cooldown_against(target_id)
```

(Placed before the abandonment/success checks so it fires every active
tick regardless of what happens later in the same frame — an attempt
that fails or gets abandoned still counts as "just tried to snatch from
them," matching your framing of "attempting to snatch.")

### 4. `scripts/npc/NPCBrain.gd` — `GiveToFriendActivity` identifies itself as giver

**Anchor:** the hand-off line:

```gdscript
			if _friend.has_method("can_receive_item") and _friend.can_receive_item(npc.held_item):
```

Replace with:

```gdscript
			if _friend.has_method("can_receive_item") and _friend.can_receive_item(npc.held_item, npc.npc_id):
```

---

## Part C — Live "HOSTILE for Ns" log entry

One entry, created once per Hostile episode, mutated in place while
active (never spammed), frozen to a final static line the moment it ends.

### 1. `scripts/npc/NPC.gd` — hostile log lifecycle

**Anchor:** near the Action Log section.

Insert:

```gdscript
# ─── Live Hostile Log Entry (Aug 2026) ──────────────────────────────────────
var _hostile_log_entry: Dictionary = {}   ## reference to the live entry dict (shared with _action_log), or {} if none active
var _hostile_start_msec: int = 0

## Called once, from SnatchActivity.enter(), the moment this NPC commits
## to a target. Appends ONE entry and keeps mutating it in place for the
## duration (see update_hostile_log()) — never a new entry per tick.
func start_hostile_log() -> void:
	_hostile_start_msec = Time.get_ticks_msec()
	var entry: Dictionary = {
		"text": "%s HOSTILE for 0s" % npc_name,
		"fired_at_msec": _hostile_start_msec,
		"game_time": _current_game_time_string(),
		"is_live_hostile": true,
	}
	_action_log.append(entry)
	if _action_log.size() > ACTION_LOG_MAX_LEN:
		_action_log.pop_front()
	_hostile_log_entry = entry
	action_logged.emit()   ## structural change (new row) — needs the UI to rebuild once

## Called every tick while SnatchActivity is active. Deliberately does
## NOT emit action_logged — the UI polls and refreshes this specific
## row's text directly each frame (same pattern already used for "Xs
## ago" timestamps), avoiding a full log rebuild 60x/second.
func update_hostile_log() -> void:
	if _hostile_log_entry.is_empty():
		return
	var elapsed_sec: int = int((Time.get_ticks_msec() - _hostile_start_msec) / 1000.0)
	_hostile_log_entry["text"] = "%s HOSTILE for %ds" % [npc_name, elapsed_sec]

## Called once, from SnatchActivity.exit() — freezes the final text and
## clears the live marker. From this point it's a normal static entry.
func end_hostile_log() -> void:
	if not _hostile_log_entry.is_empty():
		var elapsed_sec: int = int((Time.get_ticks_msec() - _hostile_start_msec) / 1000.0)
		_hostile_log_entry["text"] = "%s was HOSTILE for %ds" % [npc_name, elapsed_sec]
		_hostile_log_entry["is_live_hostile"] = false
	_hostile_log_entry = {}
```

### 2. `scripts/npc/NPCBrain.gd` — wire into `SnatchActivity`

**Anchor:** `enter()`, right after the target is confirmed (end of the
function):

```gdscript
	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		if _target != null and is_instance_valid(_target):
			npc.set_nav_target((_target as Node3D).global_position)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		npc.start_hostile_log()
		if _target != null and is_instance_valid(_target):
			npc.set_nav_target((_target as Node3D).global_position)
```

**Anchor:** `tick()` — right after the `start_snatch_cooldown_against()`
call added in Part B, add:

```gdscript
			npc.update_hostile_log()
```

**Anchor:** `exit()`:

```gdscript
	func exit(_npc: NPC) -> void:
		_target = null
		_handoff = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		npc.end_hostile_log()
		_target = null
		_handoff = null
```

### 3. `scripts/ui/npc/NPCTalkMenuUI.gd` — live text refresh

**Anchor:** var declarations — add alongside `_log_time_labels`:

```gdscript
var _log_text_labels: Array[Label] = []
```

**Anchor:** `_make_log_row()` — after `row.add_child(text_lbl)`:

```gdscript
	row.add_child(text_lbl)
```

Add immediately after:

```gdscript
	_log_text_labels.append(text_lbl)
```

**Anchor:** `_rebuild_log_rows()` — where `_log_time_labels.clear()` is
called, add:

```gdscript
	_log_time_labels.clear()
```

Replace with:

```gdscript
	_log_time_labels.clear()
	_log_text_labels.clear()
```

**Anchor:** `_process()`:

```gdscript
func _process(_delta: float) -> void:
	if not visible or not _log_expanded:
		return
	for i: int in range(_log_time_labels.size()):
		if i >= _log_entries.size():
			continue
		_log_time_labels[i].text = _format_log_age(_log_entries[i]["fired_at_msec"] as int)
```

Replace with:

```gdscript
func _process(_delta: float) -> void:
	if not visible or not _log_expanded:
		return
	for i: int in range(_log_time_labels.size()):
		if i >= _log_entries.size():
			continue
		_log_time_labels[i].text = _format_log_age(_log_entries[i]["fired_at_msec"] as int)
	## Live hostile entry — always the newest, so always index 0 if
	## present. get_action_log()'s shallow duplicate means _log_entries[0]
	## is the SAME dictionary NPC.gd keeps mutating in update_hostile_log()
	## — just re-read its current text, no extra query needed.
	if not _log_entries.is_empty() and bool(_log_entries[0].get("is_live_hostile", false)) \
			and not _log_text_labels.is_empty():
		_log_text_labels[0].text = str(_log_entries[0]["text"])
```

---

## Part D — Fix Relaxing clustering at spawn

### `scripts/npc/NPC.gd`

**Anchor:** near the Relaxing constants:

```gdscript
const RELAX_BUDGET_BASELINE: float = 1.0   ## game-hours/day
const RELAX_BUDGET_LAZY: float = 2.0
```

Add nearby:

```gdscript
## Minimum game-hours between the end of one relax session and the next
## becoming eligible — without this, a fresh NPC (full needs, nothing else
## competing) wins the very first think-cycle and can chain sessions
## back-to-back until the whole daily budget is gone in one sitting.
## Randomized per-cooldown (not a fixed value) so sessions don't fall
## into a predictable rhythm across NPCs or across a single NPC's day.
const RELAX_MIN_GAP_HOURS: float = 3.0
const RELAX_MAX_GAP_HOURS: float = 6.0
var _relax_cooldown_hours: float = 0.0
```

**Anchor:** `_ready()` — add somewhere in the NPC's initial setup (e.g.
near where `_overhead_timer` or similar initial randomized state is
seeded):

```gdscript
	_relax_cooldown_hours = randf_range(1.0, RELAX_MIN_GAP_HOURS)   ## staggered head-start — never eligible to relax the instant they spawn
```

**Anchor:** `_tick_relax_day()`:

```gdscript
func _tick_relax_day(h: float) -> void:
	_relax_day_clock += h
	if _relax_day_clock >= 24.0:
		_relax_day_clock = fmod(_relax_day_clock, 24.0)
		_relax_time_used_today = 0.0
```

Replace with:

```gdscript
func _tick_relax_day(h: float) -> void:
	_relax_day_clock += h
	if _relax_day_clock >= 24.0:
		_relax_day_clock = fmod(_relax_day_clock, 24.0)
		_relax_time_used_today = 0.0
	_relax_cooldown_hours = maxf(0.0, _relax_cooldown_hours - h)
```

**Anchor:** near `get_relax_time_remaining_today()` — add:

```gdscript
func is_relax_on_cooldown() -> bool:
	return _relax_cooldown_hours > 0.0

func start_relax_cooldown() -> void:
	_relax_cooldown_hours = randf_range(RELAX_MIN_GAP_HOURS, RELAX_MAX_GAP_HOURS)
```

### `scripts/npc/NPCBrain.gd`

**Anchor:** `RelaxActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if npc.get_relax_time_remaining_today() <= 0.0:
			return 0.0
		return BASE_SCORE * npc.get_work_ethic_passive_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if npc.get_relax_time_remaining_today() <= 0.0:
			return 0.0
		if npc.is_relax_on_cooldown():
			return 0.0
		return BASE_SCORE * npc.get_work_ethic_passive_mult()
```

**Anchor:** `RelaxActivity.exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _session_elapsed > 0.01:
			npc.log_action("Relaxed for %d min" % int(round(_session_elapsed * 60.0)))
		if _inner != null:
			_inner.exit(npc)
			_inner = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if _session_elapsed > 0.01:
			npc.log_action("Relaxed for %d min" % int(round(_session_elapsed * 60.0)))
			npc.start_relax_cooldown()   ## spaces sessions apart — see NPC.gd's Relaxing section
		if _inner != null:
			_inner.exit(npc)
			_inner = null
```

(Cooldown only starts if a session actually happened — an `enter()` that
immediately found no chair/bed/session shouldn't itself trigger a
multi-hour cooldown before trying again.)

---

## Documentation

`docs/systems/npc/README.md`:
- Trait Effects Reference — update Sociability's entry to include the
  new contagion multiplier, worded plainly for future tutorial use, e.g.:
  *"Sociability: 0.5x-1.5x on how fast this NPC's relationships change
  (both directions); separately, 0.67x-1.33x on how much this NPC's own
  mood gets pulled by the room's average mood (mood contagion)."*
- New subsection on the Snatch→Gift cooldown: per-pair (attacker↔specific
  victim), 60s, refreshed continuously while actively pursuing, frozen at
  the last active moment — explicitly note it does NOT block gifts from
  anyone else, only the specific party just snatched from.
- Relaxing section — note the inter-session cooldown and spawn stagger,
  and why (prevents front-loading the whole daily budget at once).

**Testing Checklist:**

```
51. Compare an Open vs a Distant NPC's mood swings while sitting near
    NPCs with very different moods — confirm the Open one's mood visibly
    moves more per contagion tick (F7 log) than the Distant one's.
52. Have NPC A snatch from NPC B (or the player) — confirm B specifically
    cannot gift to A for 60s afterward (Give prompt/action fails), while
    an uninvolved NPC C can still gift A normally the entire time.
53. Watch the log during a Hostile episode — confirm ONE entry appears
    and its text visibly counts up ("HOSTILE for 1s", "2s"...) without
    creating new rows, then freezes to "was HOSTILE for Ns" the moment it
    ends.
54. Spawn several fresh NPCs and watch them for the first in-game hour —
    confirm none of them immediately relax, and confirm relax sessions
    across a full day now land as a handful of separated sessions rather
    than one long block.
```
