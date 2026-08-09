# Stuck-Recovery Deadlock Fix + Reachability-Aware Cleaning Target Selection (Aug 2026)

**Files:** `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Context — reading the debug output

Confirmed first: the 43 organizable items in `[JobBoard] Cleaning scan: 0
trash, 43 organizable, 0 tracked-but-not-yet-idle` means every item that
fell when you deleted the shelf **is** being recognized as cleanable —
that part already works correctly (items join the `"pickup"` group in
their own `_ready()` regardless of how they ended up loose in the
world, shelf-sourced or not). No fix needed there.

The actual bug is in stuck-recovery, and the log makes the mechanism
traceable end to end:

1. `_tick_stuck_recovery()` fires because the NPC hasn't moved 0.15m in
   1 second.
2. `_recover_from_stuck()` finds an obstruction (the Crate, via real
   physics slide-collision), stops whatever the NPC was doing, and
   force-starts a `CleaningActivity` targeting exactly that item.
3. **That forced activity never logs "picked up," "no destination," or
   "pickup failed"** — meaning it never even got the NPC within
   `PICKUP_RANGE`. In a genuine pile of clutter, the NPC can be
   completely wedged — touching the Crate (which is why it registers as
   the "stuck obstruction" in the first place) but physically unable to
   move *at all*, in any direction, because it's boxed in by other
   items' colliders on every side.
4. One second later, `_tick_stuck_recovery()` fires again (the NPC still
   hasn't moved, because it *can't*), which aborts the forced
   `CleaningActivity` and force-starts a brand new one — often on the
   same item again, sometimes finding no obstruction that particular
   frame (slide-collision data is only valid for the frame it happened),
   in which case `_current` is left `null` and the next normal
   `_think()` cycle picks `RelaxActivity` instead — which is what
   produces the "Idle -> Relaxing" lines interleaved with the stuck
   cycles in your log.

So the recovery mechanism was never actually broken in the sense of
picking the wrong response — it correctly identifies the obstruction and
correctly tries to clean it up. The bug is that **it has no memory of
having already tried this and failed**, so it retries the exact same
doomed action forever instead of ever concluding "I physically cannot
reach this right now" and doing something else. Part A fixes that.

Part B is the separate "shouldn't target the item buried in the center
of a pile" request — `find_cleaning_target()` currently only ever
considers straight-line distance, with zero concept of whether anything
is physically in the way. Mechanically, "prefer the item on the outside
of the pile" means: given several nearby candidates, prefer one with a
roughly clear line to it over one where another piece of clutter sits
directly between the NPC and the target.

---

## Part A — Break the stuck-recovery deadlock

### Design

Track how many times in a row `_recover_from_stuck()` has targeted the
*same* obstruction (or found none identifiable — also a signal something
is wrong, not just bad luck). Once that streak crosses a small
threshold, stop trying to force-clean it — a repeat is proof the item is
not actually reachable right now — and instead physically nudge the NPC
a short distance away from the obstruction (a direct position
adjustment, not a movement command, since movement is exactly what's not
working) to break the physical wedge, then let a completely fresh
`_think()` cycle decide what to do next with no forced target at all.
The streak resets the moment the NPC successfully moves again, so a
*new*, unrelated stuck event later still gets the normal two tries
before escalating.

### Fix

**Anchor:**

```gdscript
var _stuck_timer: float = 0.0
var _stuck_ref_pos: Vector3 = Vector3.ZERO
var _stuck_recoveries: int = 0   ## exposed for the Part 7 debug dump

func _tick_stuck_recovery(delta: float) -> void:
	## Part 18 — gate on _movement_locked, not nav_finished(). Drink/Eat/
	## Job-work all stop the NPC via their OWN range checks (PICKUP_RANGE,
	## USE_RANGE, WORK_RANGE), completely decoupled from the nav_agent's own
	## arrival threshold — an NPC can correctly halt for a totally
	## legitimate reason while nav_finished() still reports false, because
	## nothing ever told the nav_agent navigation was "done." That mismatch
	## was firing false stuck-aborts mid-drink/mid-eat/mid-work, which is
	## what was actually causing the drop-and-repeat loop (exit() drops
	## whatever's held). _movement_locked is raised by every halt_movement()/
	## lock_movement() call — i.e., every legitimate stationary reason — and
	## cleared only when nav_steer() next runs to resume real travel, so
	## it's a direct read of "an activity wants me still" instead of an
	## indirect, frequently-wrong guess from the navigation layer.
	if nav_agent == null or _movement_locked:
		_stuck_timer = 0.0
		_stuck_ref_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	var moved: float = global_position.distance_to(_stuck_ref_pos)
	_stuck_timer = 0.0
	_stuck_ref_pos = global_position
	if moved < STUCK_MIN_DISPLACEMENT:
		_recover_from_stuck()

func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0
	if stuck_item != null and brain != null:
		## Always fair game when it caused a stuck NPC — bypasses the
		## normal trash/idle-time eligibility entirely, per design.
		brain.force_command(NPCBrain.CleaningActivity.new(stuck_item))
```

Replace with:

```gdscript
var _stuck_timer: float = 0.0
var _stuck_ref_pos: Vector3 = Vector3.ZERO
var _stuck_recoveries: int = 0   ## exposed for the Part 7 debug dump

## Aug 2026 — how many CONSECUTIVE stuck-recoveries have targeted the
## same obstruction (or found none). This is what was missing: without
## it, a genuinely wedged NPC (boxed in by clutter on every side, unable
## to move toward ANYTHING, including the item touching it) would force
## the exact same doomed CleaningActivity over and over forever, once
## per second, since the item causing the stall correctly kept getting
## re-identified as the obstruction every time.
const STUCK_ESCALATE_AFTER: int = 2
const STUCK_NUDGE_DISTANCE: float = 0.6
var _stuck_streak_obstruction_id: int = -1
var _stuck_streak_count: int = 0

func _tick_stuck_recovery(delta: float) -> void:
	## Part 18 — gate on _movement_locked, not nav_finished(). Drink/Eat/
	## Job-work all stop the NPC via their OWN range checks (PICKUP_RANGE,
	## USE_RANGE, WORK_RANGE), completely decoupled from the nav_agent's own
	## arrival threshold — an NPC can correctly halt for a totally
	## legitimate reason while nav_finished() still reports false, because
	## nothing ever told the nav_agent navigation was "done." That mismatch
	## was firing false stuck-aborts mid-drink/mid-eat/mid-work, which is
	## what was actually causing the drop-and-repeat loop (exit() drops
	## whatever's held). _movement_locked is raised by every halt_movement()/
	## lock_movement() call — i.e., every legitimate stationary reason — and
	## cleared only when nav_steer() next runs to resume real travel, so
	## it's a direct read of "an activity wants me still" instead of an
	## indirect, frequently-wrong guess from the navigation layer.
	if nav_agent == null or _movement_locked:
		_stuck_timer = 0.0
		_stuck_ref_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	var moved: float = global_position.distance_to(_stuck_ref_pos)
	_stuck_timer = 0.0
	_stuck_ref_pos = global_position
	if moved < STUCK_MIN_DISPLACEMENT:
		_recover_from_stuck()
	else:
		## Real progress was made — a fresh, unrelated stuck event later
		## deserves its own full STUCK_ESCALATE_AFTER tries, not whatever
		## was left over from an old, now-resolved streak.
		_stuck_streak_obstruction_id = -1
		_stuck_streak_count = 0

func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0

	var obstruction_id: int = stuck_item.get_instance_id() if stuck_item != null else -1
	if obstruction_id != -1 and obstruction_id == _stuck_streak_obstruction_id:
		_stuck_streak_count += 1
	else:
		_stuck_streak_count = 1
	_stuck_streak_obstruction_id = obstruction_id

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
	_nudge_free_of_obstruction(stuck_item)
	_stuck_streak_obstruction_id = -1
	_stuck_streak_count = 0

## Direct position nudge away from whatever's blocking the NPC — bypasses
## normal collision-respecting movement entirely, which is the point: a
## wedged NPC can't walk itself out, so this moves it out instead. Falls
## back to a random horizontal direction if no obstruction is known
## (e.g. the last few recoveries found nothing specific).
func _nudge_free_of_obstruction(stuck_item: RigidBody3D) -> void:
	var away: Vector3
	if stuck_item != null and is_instance_valid(stuck_item):
		away = global_position - (stuck_item as Node3D).global_position
	else:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	global_position += away.normalized() * STUCK_NUDGE_DISTANCE
```

Stop and report on anchor mismatch — no improvisation.

**File:** `scripts/npc/NPCDebug.gd`

**Anchor:** immediately after the existing `log_stuck()`:

```gdscript
static func log_stuck(npc: Node) -> void:
	if not enabled:
		return
	print("%s STUCK — aborting current activity and re-scoring" % _fmt(npc))
```

Add immediately after it:

```gdscript
## Aug 2026 — logged when the same obstruction (or none identifiable)
## has kept an NPC stuck across multiple consecutive recovery attempts,
## and it's about to give up forcing a cleanup and nudge free instead.
static func log_stuck_escalation(npc: Node, obstruction: Node, streak: int) -> void:
	if not enabled:
		return
	var name: String = "?"
	if obstruction != null and obstruction.has_method("get_display_name"):
		name = obstruction.get_display_name()
	elif obstruction != null:
		name = str(obstruction.name)
	print("%s STUCK ESCALATION — %s failed to clear the stall %d times in a row, nudging free instead of retrying" \
		% [_fmt(npc), name, streak])
```

Stop and report on anchor mismatch — no improvisation.

---

## Part B — Prefer a reachable item over the nearest-by-distance one

### Fix

**Anchor:** the entire existing `find_cleaning_target()`:

```gdscript
## Nearest eligible item across BOTH lists — trash and organizable are
## mutually exclusive per JobBoard's own scan, so no double-counting
## risk. `exclude_ids` (Aug 2026) lets CleaningActivity skip items it's
## already tried and confirmed have nowhere to go THIS session, and
## skip momentary claim-clash items, without waiting on JobBoard's own
## 2s cache refresh — see CleaningActivity._pick_next_target().
func find_cleaning_target(exclude_ids: Dictionary = {}) -> Dictionary:
	var best_item: Node = null
	var best_d: float = INF
	var best_is_trash: bool = false
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = true
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = false
	if best_item == null:
		return {}
	return {"item": best_item, "is_trash": best_is_trash}
```

Replace with:

```gdscript
## Eligible item across BOTH lists — trash and organizable are mutually
## exclusive per JobBoard's own scan, so no double-counting risk.
## `exclude_ids` (Aug 2026) lets CleaningActivity skip items it's already
## tried and confirmed have nowhere to go THIS session, and skip
## momentary claim-clash items, without waiting on JobBoard's own 2s
## cache refresh — see CleaningActivity._pick_next_target().
##
## Aug 2026 — no longer purely nearest-by-distance. Candidates are
## checked in distance order, but the first one with a roughly clear
## approach (see _has_clear_approach()) wins over a nominally-nearer one
## that's actually buried behind other clutter — this is the mechanical
## meaning of "go to the item on the outside of a pile, not the one
## wedged in the center." Falls back to the plain nearest item if every
## candidate looks equally blocked (better to try SOMETHING than return
## nothing).
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
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])

	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}

## Cheap line-of-sight estimate (Aug 2026): raycast from roughly chest
## height toward the candidate item. If something ELSE in the "pickup"
## group is hit first, the item is buried behind other clutter rather
## than a clean, direct pickup target — exactly the "shelf's worth of
## items dumped in one spot" case. Best-effort, not real pathfinding
## cost; a raycast miss or a hit on the item itself both count as clear.
func _has_clear_approach(item: Node) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0.0, 0.9, 0.0)
	var to: Vector3 = (item as Node3D).global_position + Vector3(0.0, 0.2, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var hit: Object = result.get("collider")
	if hit == item:
		return true
	return not (hit is Node and (hit as Node).is_in_group("pickup"))
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

1. Reproduce the original scenario: place a shelf loaded with several
   items, delete the shelf so they drop into a dense pile, ask an NPC to
   clean. Confirm items ARE recognized (unchanged — already worked).
   Confirm the NPC now prefers an item on the outside of the pile over
   one buried in the middle, when both are similar distances away.
2. Deliberately wedge an NPC (surround it tightly with several heavy
   items so it can't move in any direction) and let it get stuck.
   Confirm: it tries the forced cleanup up to `STUCK_ESCALATE_AFTER`
   (2) times, then the console shows a `STUCK ESCALATION` line, the NPC
   visibly relocates a short distance, and it stops looping — it should
   pick up normally afterward (or at minimum stop retrying the exact
   same dead end every second).
3. Confirm a normal, resolvable stuck event (bumped into one item that's
   easy to route around) still recovers exactly as before — one
   recovery, successful pickup, no escalation triggered.
4. Confirm the streak resets correctly: get an NPC stuck, let it
   escalate and nudge free, then separately get it stuck on a totally
   different, later occasion — confirm that new event gets its own full
   set of tries rather than escalating immediately.
5. With `_has_clear_approach()`'s raycast: place one item directly
   behind another (from the NPC's position) and one item off to the
   side at a similar distance — confirm the NPC goes for the side item
   first.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
82. Wedge an NPC tightly inside a pile of items so it can't move at
    all — confirm it tries the forced cleanup at most twice before a
    STUCK ESCALATION log line appears and the NPC visibly relocates,
    rather than looping the same forced grab forever.
83. Drop a dense pile of items (e.g. by deleting a loaded shelf) and ask
    an NPC to clean — confirm it prefers an outer, reachable item over
    one buried in the center when both are similar distances away.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Stuck-Recovery Deadlock Fix + Reachability-Aware Target Selection (Aug 2026)

- Root-caused a real infinite loop: _recover_from_stuck() had no memory
  of repeated failures, so a genuinely wedged NPC (boxed in by clutter
  on every side, unable to move toward anything — including the item
  touching it) would force the identical doomed CleaningActivity every
  ~1s forever. Now tracks a same-obstruction streak
  (_stuck_streak_obstruction_id/_stuck_streak_count); after
  STUCK_ESCALATE_AFTER (2) consecutive failures on the same target, it
  stops retrying and directly nudges the NPC's position away from the
  obstruction instead (movement commands don't work on a wedged NPC, so
  this bypasses movement entirely), then lets the next think-cycle
  decide fresh. Added NPCDebug.log_stuck_escalation() for visibility.
- find_cleaning_target() no longer picks purely by straight-line
  distance — candidates are checked in distance order, but a
  _has_clear_approach() raycast now deprioritizes an item that's
  directly behind another piece of clutter in favor of a similarly-close
  one with a clear line to it. This is what "prefer the item on the
  outside of a pile over the one buried in the center" means
  mechanically. Falls back to plain-nearest if every candidate looks
  equally blocked.
- Confirmed (no fix needed): items freed from a deleted shelf are
  already correctly picked up by JobBoard's cleaning scan — they join
  the "pickup" group in their own _ready() regardless of how they ended
  up loose.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
