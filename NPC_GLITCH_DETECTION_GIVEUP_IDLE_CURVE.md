# Cleaning: Glitch Detection, Scoped Give-Up System, Exponential Idle Gate (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Context — summary of what we settled on

Three things, matching the clarified scope exactly:

1. **Detect genuinely glitched items directly, at the source** — don't
   infer it from repeated failures. Your own debug dump had a strong
   clue: two NPCs (Nolan, Kwame) were sitting at `Y ≈ -140373` and
   `Y ≈ -57898` — clearly fallen/ejected far outside the bunker, not a
   real position. It's very likely the Bag of Soil/Fertilizer items (I
   confirmed separately: those **only** ever spawn through a Farming
   Shop purchase — no other spawn path exists anywhere in the code, so
   their presence isn't a leftover debug artifact) suffered the same
   kind of glitch. A pure distance-based target-picking metric can't
   catch this on its own — `NPCItemUser.flat_distance()` deliberately
   ignores Y entirely (used everywhere else for walking, where that's
   correct), so an item that fell straight through the floor would
   still look "nearby" by that metric alone. This gets a real,
   Y-bounds sanity check at the point items are scanned into the
   cleaning system in the first place — nothing this obviously wrong
   is ever offered to any NPC as a cleaning target, so it doesn't need
   to be "given up on" at all.
2. **A narrowly-scoped, permanent-per-NPC give-up system** — exactly two
   independent counters, exactly as discussed:
   - **Stuck-recovery failures** on the *same specific item* (already
     tracked) — give up after 2, not 3.
   - **Genuine pickup failures** — NPC got within `PICKUP_RANGE` and
     `grab_loose()` still refused — give up after 2.
   - Everything else (another NPC claimed it first, it became
     held/shelved before arrival) stays infinitely retryable, exactly
     as it works today. That's routine contention during busy cleaning,
     not evidence of anything wrong with the item.
   - Once given up on, an item is permanently skipped by that specific
     NPC (persists for its lifetime, cleared only on despawn/reload)
     — other NPCs are unaffected and can still try it.
3. **Exponential idle-gate scaling** — 90s at zero clutter, reaching
   exactly 0s at 20 clutter items, staying close to 90s for a while
   before dropping sharply as it nears 20 (per your answer).

---

## Part A — Glitch detection at the JobBoard scan (the direct fix)

### Design

`JobBoard._scan_cleaning()` is where every loose item first becomes
visible to the cleaning system. Adding the sanity check here means a
glitched item is excluded for **every** NPC at once, at the source —
not something any individual NPC has to "learn" by failing against it.
Bounds are based on real observed coordinates across every log you've
sent (everything from actual play sits within roughly -2 to +15 on Y) —
generous margin on both sides so nothing legitimate is ever caught by
this, while the extreme values seen in testing (tens of thousands off)
are rejected outright.

### Fix

**File:** `scripts/npc/JobBoard.gd`

**Anchor:**

```gdscript
const CLEANING_IDLE_MIN_SEC: float = 90.0
## Debug-only override (F7 → NPCDebug.enabled) so idle-gate timing can be
## tested in seconds instead of minutes. Never changes real gameplay —
## only takes effect while NPCDebug.enabled is true.
const CLEANING_IDLE_MIN_SEC_DEBUG: float = 5.0

func _effective_cleaning_idle_min_sec() -> float:
	return CLEANING_IDLE_MIN_SEC_DEBUG if NPCDebug.enabled else CLEANING_IDLE_MIN_SEC
```

Replace with:

```gdscript
const CLEANING_IDLE_MIN_SEC: float = 90.0
## Debug-only override (F7 → NPCDebug.enabled) so idle-gate timing can be
## tested in seconds instead of minutes. Never changes real gameplay —
## only takes effect while NPCDebug.enabled is true.
const CLEANING_IDLE_MIN_SEC_DEBUG: float = 5.0

## Aug 2026 — exponential clutter scaling. 90s at zero clutter, dropping
## to exactly 0s once total clutter reaches CLUTTER_IDLE_ZERO_AT (20).
## The exponent (4.0) is what gives it the "stays close to 90s, then
## drops sharply near the cap" shape you asked for — try tuning this one
## constant first if the curve ever feels off, before touching the
## formula itself. Debug override still always wins over this — it's for
## fast iteration, not meant to reflect real clutter-scaled timing.
const CLUTTER_IDLE_ZERO_AT: int = 20
const CLUTTER_IDLE_CURVE_POWER: float = 4.0

func _effective_cleaning_idle_min_sec() -> float:
	if NPCDebug.enabled:
		return CLEANING_IDLE_MIN_SEC_DEBUG
	var clutter: int = get_total_clutter_count()
	if clutter >= CLUTTER_IDLE_ZERO_AT:
		return 0.0
	var fraction: float = float(clutter) / float(CLUTTER_IDLE_ZERO_AT)
	return CLEANING_IDLE_MIN_SEC * (1.0 - pow(fraction, CLUTTER_IDLE_CURVE_POWER))
```

**Anchor:** the header comment above `_scan_cleaning()` and the constant
block right before it:

```gdscript
# ─── Cleaning discovery (Aug 2026) ──────────────────────────────────────────
## Idle-time gating for organizing — an item must sit untouched/unclaimed
## for this long before it's eligible, so NPCs don't sweep away something
## the player just set down to use in a moment. Trash items skip this
## entirely (they're unambiguously "done," not "in active use").
```

Add immediately after it (still before `CLEANING_IDLE_MIN_SEC`):

```gdscript
## Aug 2026 — sanity bounds for "is this thing actually still in the
## bunker." Not a general physics constraint — every real in-play
## position seen across testing sits within roughly -2..+15 on Y; an
## item outside this generous range (two NPCs were observed at
## Y≈-140000 and Y≈-58000 in one session — clearly fallen/ejected far
## outside the level, not a real placement) is excluded from the
## cleaning system entirely at scan time, for every NPC at once, rather
## than discovered per-NPC through repeated failed attempts.
## flat_distance() (used for normal target-picking) deliberately ignores
## Y — this is the check that actually catches a pure vertical
## fall-through, which flat_distance alone never would.
const CLEANING_SANITY_Y_MIN: float = -20.0
const CLEANING_SANITY_Y_MAX: float = 30.0
```

**Anchor:** inside `_scan_cleaning()`'s main loop:

```gdscript
	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not ("is_held" in item):
			continue
		if item.is_held or item.is_in_group("shelved"):
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
```

Replace with:

```gdscript
	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not ("is_held" in item):
			continue
		if item.is_held or item.is_in_group("shelved"):
			continue
		var item_y: float = (item as Node3D).global_position.y
		if item_y < CLEANING_SANITY_Y_MIN or item_y > CLEANING_SANITY_Y_MAX:
			## Glitched/out-of-bounds — never enters the cleaning system
			## at all, for any NPC. See CLEANING_SANITY_Y_MIN's comment.
			if NPCDebug.enabled:
				print("[JobBoard] Cleaning scan: excluding %s — Y=%.1f is outside sane bunker bounds (glitched/out-of-bounds)" \
					% [(item.get_display_name() if item.has_method("get_display_name") else str(item.name)), item_y])
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
```

Stop and report on anchor mismatch — no improvisation.

---

## Part B — Scoped give-up counters (permanent per-NPC)

### B1 — `NPC.gd`: the blacklist + two counters

**Anchor:** immediately after the existing `find_cleaning_target()` (right
before `_has_clear_approach()` begins):

```gdscript
	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}
```

Replace with:

```gdscript
	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}

## Aug 2026 — permanent-for-this-NPC give-up list. Deliberately NARROW in
## scope: only two things ever add to it — a stuck-recovery streak on the
## exact same item reaching CLEANING_GIVEUP_STUCK_LIMIT (see
## _recover_from_stuck()), and a genuine in-range pickup failure reaching
## CLEANING_GIVEUP_PICKUP_LIMIT (see record_cleaning_pickup_failure()).
## Routine contention — another NPC claiming it first, it becoming held/
## shelved before arrival — never touches this and stays infinitely
## retryable exactly as before. Persists for this NPC's lifetime; never
## cleared (despawn/reload naturally resets it by removing the NPC).
const CLEANING_GIVEUP_STUCK_LIMIT: int = 2
const CLEANING_GIVEUP_PICKUP_LIMIT: int = 2
var _cleaning_blacklist: Dictionary = {}          ## item instance_id -> true
var _cleaning_pickup_failures: Dictionary = {}    ## item instance_id -> consecutive genuine-pickup-failure count

func _blacklist_cleaning_item(item: Node, reason: String) -> void:
	if item == null:
		return
	var id: int = item.get_instance_id()
	if _cleaning_blacklist.has(id):
		return
	_cleaning_blacklist[id] = true
	if NPCDebug.enabled:
		var name: String = item.get_display_name() if item.has_method("get_display_name") else str(item.name)
		NPCDebug.log_cleaning(self, "gave up permanently", "%s — %s" % [name, reason])

## Called by CleaningActivity when grab_loose() refuses an item the NPC
## is already standing within PICKUP_RANGE of — a genuine, repeatable
## failure to physically pick something up, not contention with another
## NPC (that's a separate, infinitely-retryable case — see
## find_cleaning_target()'s claim check).
func record_cleaning_pickup_failure(item: Node) -> void:
	if item == null:
		return
	var id: int = item.get_instance_id()
	var count: int = int(_cleaning_pickup_failures.get(id, 0)) + 1
	_cleaning_pickup_failures[id] = count
	if count >= CLEANING_GIVEUP_PICKUP_LIMIT:
		_blacklist_cleaning_item(item, "pickup refused %d times in a row while in range" % count)
```

**Anchor:** `find_cleaning_target()`'s two exclusion checks:

```gdscript
func find_cleaning_target(exclude_ids: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": true,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": false,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
```

Replace with:

```gdscript
func find_cleaning_target(exclude_ids: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": true,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": false,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
```

Stop and report on anchor mismatch — no improvisation.

### B2 — `NPC.gd`: stuck-recovery give-up (2 tries, not 3)

**Anchor:**

```gdscript
	if stuck_item != null and brain != null and _stuck_streak_count <= STUCK_ESCALATE_AFTER:
		## Always fair game when it caused a stuck NPC — bypasses the
		## normal trash/idle-time eligibility entirely, per design.
		brain.force_command(NPCBrain.CleaningActivity.new(stuck_item))
		return

	## Aug 2026 — same obstruction (or nothing identifiable) kept the NPC
	## stuck across multiple recovery attempts in a row. Trying to force-
	## clean it again just repeats the same failed loop — the NPC can't
	## even close the distance to something it's already touching, which
	## means it's genuinely wedged (boxed in by clutter on every side),
	## not just picking a bad target. Break the deadlock directly: nudge
	## the NPC a short distance away from the obstruction (a real
	## position change, not a movement command — movement is exactly
	## what isn't working) and let the NEXT think-cycle decide fresh,
	## with no forced target at all. The streak resets so a genuinely new
	## stuck event later still gets its own full set of tries.
	if NPCDebug.enabled:
		NPCDebug.log_stuck_escalation(self, stuck_item, _stuck_streak_count)
	_nudge_free_of_obstruction(stuck_item, STUCK_NUDGE_DISTANCE)
	_stuck_streak_obstruction_id = -1
	_stuck_streak_count = 0
```

Replace with:

```gdscript
	if stuck_item != null and brain != null and _stuck_streak_count < CLEANING_GIVEUP_STUCK_LIMIT:
		## Always fair game when it caused a stuck NPC — bypasses the
		## normal trash/idle-time eligibility entirely, per design.
		brain.force_command(NPCBrain.CleaningActivity.new(stuck_item))
		return

	## Aug 2026 — same obstruction kept the NPC stuck CLEANING_GIVEUP_
	## STUCK_LIMIT times in a row (2). Trying to force-clean it again
	## just repeats the same failed loop — the NPC can't even close the
	## distance to something it's already touching. Give up on it
	## permanently (see _blacklist_cleaning_item()) rather than retrying
	## forever, and break the immediate deadlock the same way as before:
	## nudge the NPC a short distance away (a real position change, not a
	## movement command — movement is exactly what isn't working) and let
	## the NEXT think-cycle decide fresh, with no forced target at all.
	if stuck_item != null:
		_blacklist_cleaning_item(stuck_item, "stuck-recovery failed %d times in a row" % _stuck_streak_count)
	if NPCDebug.enabled:
		NPCDebug.log_stuck_escalation(self, stuck_item, _stuck_streak_count)
	_nudge_free_of_obstruction(stuck_item, STUCK_NUDGE_DISTANCE)
	_stuck_streak_obstruction_id = -1
	_stuck_streak_count = 0
```

Stop and report on anchor mismatch — no improvisation.

---

## Part C — `NPCBrain.gd`: report genuine pickup failures

**Anchor:**

```gdscript
				else:
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "pickup failed", "grab_loose() refused %s" % _display_name(_item))
					NPCItemUser.release_item(_item)
					_item = null
			return
```

Replace with:

```gdscript
				else:
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "pickup failed", "grab_loose() refused %s" % _display_name(_item))
					npc.record_cleaning_pickup_failure(_item)   ## Aug 2026 — counts toward the give-up limit; claim/held/shelved misses elsewhere never call this
					NPCItemUser.release_item(_item)
					_item = null
			return
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

### Part A (glitch detection)
1. Manually place/teleport a loose item to an extreme Y (e.g. -5000) —
   confirm the periodic `[JobBoard] Cleaning scan:` print shows it being
   excluded by name, and confirm no NPC ever targets it.
2. Confirm every normal, real-position item is completely unaffected —
   this should never trigger for anything actually sitting in the
   bunker.
3. Reproduce (or wait for) the Farming Shop purchase → confirm normal
   Fertilizer/Bag of Soil/etc. at a REAL position are still picked up
   and cleaned normally; only genuinely out-of-bounds instances get
   excluded.

### Part B/C (give-up system)
4. Contrive a genuinely wedged item (surrounded so an NPC can never
   close distance) — confirm it force-cleans twice, then gives up
   permanently (console shows "gave up permanently"), and is never
   targeted by that NPC again for the rest of the play session. Confirm
   a DIFFERENT NPC can still target and successfully clean the same item
   if circumstances allow.
5. Confirm normal claim contention (two NPCs going for the same item,
   one loses the claim race) never triggers a give-up, no matter how
   many times it happens — this should be unaffected and infinitely
   retryable exactly as before.
6. Contrive a genuine repeated pickup failure if possible (or reason
   through the code path) — confirm 2 in a row triggers the give-up,
   not fewer, not more.
7. Confirm an item given up on by one NPC doesn't affect JobBoard's
   caches or any other NPC's ability to see and clean it.

### Idle-gate curve
8. With debug OFF, check the real idle timer at a few clutter counts
   (e.g. via temporarily logging `_effective_cleaning_idle_min_sec()`,
   or just observing pickup timing) — confirm it stays close to 90s
   through the low-to-mid range and drops sharply as clutter approaches
   20, hitting exactly 0s at 20 and beyond.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
88. Teleport a loose item to an extreme Y position — confirm JobBoard's
    scan excludes it by name and no NPC ever targets it, while normal
    items are completely unaffected.
89. Wedge an item so an NPC can never reach it — confirm it force-cleans
    exactly twice, then gives up permanently for that NPC only (console:
    "gave up permanently"), while claim contention with other NPCs never
    triggers a give-up no matter how often it happens.
90. Check the real (non-debug) idle-gate timing at a few clutter counts
    — confirm it stays close to 90s at low counts and drops sharply
    toward 0s as clutter approaches 20.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Glitch Detection, Scoped Give-Up System, Exponential Idle Gate (Aug 2026)

- JobBoard._scan_cleaning() now excludes any item outside sane Y bounds
  (CLEANING_SANITY_Y_MIN/MAX, -20..30) from the cleaning system entirely,
  at the source, for every NPC at once — root fix for NPCs targeting/
  huddling around items that had fallen/glitched far outside the bunker
  (two NPCs were observed at Y≈-140000/-58000 in one session).
  flat_distance() deliberately ignores Y, so this is the check that
  actually catches a pure vertical fall-through.
- Confirmed (no code change): Bag of Soil/Fertilizer/etc. only ever
  spawn via a Farming Shop purchase — no other spawn path exists, so
  their appearance was never a debug leftover.
- Added a narrowly-scoped, permanent-per-NPC give-up system
  (NPC._cleaning_blacklist): a stuck-recovery streak on the same item
  reaching 2, or 2 genuine in-range pickup failures
  (record_cleaning_pickup_failure()), permanently removes that item from
  that NPC's candidates. Routine contention (claim lost to another NPC,
  became held/shelved before arrival) is explicitly excluded and stays
  infinitely retryable — this only targets confirmed unreachability, not
  normal cleaning traffic.
- JobBoard._effective_cleaning_idle_min_sec() now scales with
  get_total_clutter_count(): 90s at 0 clutter, exactly 0s at 20
  (CLUTTER_IDLE_ZERO_AT), via an exponential curve
  (CLUTTER_IDLE_CURVE_POWER = 4.0) that stays close to 90s until nearing
  the cap, then drops sharply. Debug override (F7) still always wins.

Files touched: `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
