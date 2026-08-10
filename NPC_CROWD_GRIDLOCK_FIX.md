# NPC-vs-NPC Crowd Gridlock Fix (Aug 2026)

**Files:** `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## What "everything's still settling" means

It's the `STILL_SETTLING` value from `NPC.get_cleaning_unavailable_reason()`.
Loose items don't become eligible for Cleaning the instant they hit the
floor — `JobBoard` tracks each one and only marks it organizable once
it's sat within a small movement tolerance, undisturbed, for
`CLEANING_IDLE_MIN_SEC` (90 seconds in real gameplay; a debug-only
override drops this to 5 seconds while NPC Debug Logging is on). "Still
settling" means JobBoard sees the clutter and is actively tracking it,
it just hasn't cleared that idle timer yet — as opposed to "nothing to
clean," which means there's genuinely no clutter at all. It's an
intentional design choice (avoids NPCs snatching things mid-play or
right as they're dropped), not a bug, and it's exactly what you saw
resolve itself once the items had sat long enough.

---

## What the debug output shows

Confirmed by tracing this directly against live code, not just reading
the log: every single `STUCK ESCALATION` line in your capture shows
`?` as the obstruction — meaning `_find_stuck_obstruction()` found
**nothing**. That function only ever looks for `RigidBody3D` colliders:

```gdscript
func _find_stuck_obstruction() -> RigidBody3D:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is RigidBody3D and not (("is_held" in body) and body.is_held) and not body.is_in_group("shelved"):
			return body as RigidBody3D
	return null
```

NPCs are `CharacterBody3D`, not `RigidBody3D` — so when what's actually
blocking an NPC's movement is **another NPC**, this function has no way
to ever detect it, and always returns `null`. That's the entire
explanation for the `?`.

Cross-referencing the item names in the log (Jerry Can, Normal
Fertilizer, Basket, Water Case, Cooking Pot — the same handful, over and
over, at similar 3.8–6.5m distances, with no NPC ever logging "picked
up") with the escalation pattern makes the full picture clear: several
NPCs converged on the same clutter hotspot at roughly the same time
(the urgency change from last plan makes this more likely, not less —
more NPCs decide to clean at once when clutter is high). Once enough of
them piled into the same tight space, they started physically blocking
*each other*, not any item. Since that's invisible to
`_find_stuck_obstruction()`, the recovery system always fell straight to
the "nothing identifiable" branch — which nudges in a **random**
direction when there's no known obstruction. In a tight crowd, a random
nudge has real odds of pushing an NPC straight into someone else, which
is exactly "shuffling around each other constantly."

---

## Fix

Teach the stuck-recovery system to recognize an NPC as a distinct kind
of obstruction, and respond to it correctly: nudge directly away from
the *specific* NPC that's actually in the way (not randomly), and if
that keeps happening (a real, ongoing crowd, not a one-off bump), do a
larger, decisive displacement to actually clear the hotspot instead of
lots of small ineffective shuffles.

**Anchor:** the existing stuck-tracking member variables (just above
`_tick_stuck_recovery()`):

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

## Aug 2026 — separate streak for "blocked by ANOTHER NPC," not an item.
## _find_stuck_obstruction() only ever detects RigidBody3D colliders, so
## it never identifies another NPC (CharacterBody3D) as the cause —
## several NPCs converging on the same clutter hotspot and physically
## boxing each other in showed up as an unidentifiable ("?") obstruction
## every single time, which meant the old fallback (a RANDOM-direction
## nudge) had real odds of shoving an NPC straight into someone else —
## exactly the reported "shuffling around each other" behavior. This
## streak lets a repeated NPC-on-NPC jam escalate to a bigger, more
## decisive displacement instead of a lot of small ineffective ones.
const STUCK_NPC_BACKOFF_AFTER: int = 2
const STUCK_NPC_BACKOFF_DISTANCE: float = 2.5
var _stuck_npc_streak: int = 0
```

**Anchor:** inside `_tick_stuck_recovery()`, the "moved fine" branch:

```gdscript
	else:
		## Real progress was made — a fresh, unrelated stuck event later
		## deserves its own full STUCK_ESCALATE_AFTER tries, not whatever
		## was left over from an old, now-resolved streak.
		_stuck_streak_obstruction_id = -1
		_stuck_streak_count = 0
```

Replace with:

```gdscript
	else:
		## Real progress was made — a fresh, unrelated stuck event later
		## deserves its own full STUCK_ESCALATE_AFTER tries, not whatever
		## was left over from an old, now-resolved streak.
		_stuck_streak_obstruction_id = -1
		_stuck_streak_count = 0
		_stuck_npc_streak = 0
```

**Anchor:** the entire existing `_recover_from_stuck()` and
`_nudge_free_of_obstruction()`:

```gdscript
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

Replace with:

```gdscript
func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
	var stuck_npc: CharacterBody3D = null
	if stuck_item == null:
		stuck_npc = _find_stuck_obstruction_npc()
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0

	if stuck_npc != null:
		## Aug 2026 — blocked by ANOTHER NPC, not an item. Forcing a
		## CleaningActivity here would do nothing useful — the problem
		## isn't a target to pick up, it's a crowd to get out of. Nudge
		## directly away from the SPECIFIC NPC that's in the way (not a
		## random direction — a directed nudge actually creates
		## separation instead of a coin-flip chance of shoving into
		## someone else). A repeated jam (STUCK_NPC_BACKOFF_AFTER in a
		## row) escalates to a bigger, more decisive displacement rather
		## than a lot of small ineffective ones.
		_stuck_npc_streak += 1
		_stuck_streak_obstruction_id = -1
		_stuck_streak_count = 0
		if NPCDebug.enabled:
			NPCDebug.log_stuck_escalation(self, stuck_npc, _stuck_npc_streak)
		var backoff: float = STUCK_NPC_BACKOFF_DISTANCE if _stuck_npc_streak >= STUCK_NPC_BACKOFF_AFTER else STUCK_NUDGE_DISTANCE
		_nudge_free_of_obstruction(stuck_npc, backoff)
		if _stuck_npc_streak >= STUCK_NPC_BACKOFF_AFTER:
			_stuck_npc_streak = 0
		return
	_stuck_npc_streak = 0

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
	_nudge_free_of_obstruction(stuck_item, STUCK_NUDGE_DISTANCE)
	_stuck_streak_obstruction_id = -1
	_stuck_streak_count = 0

## Direct position nudge away from whatever's blocking the NPC — bypasses
## normal collision-respecting movement entirely, which is the point: a
## wedged NPC can't walk itself out, so this moves it out instead. Falls
## back to a random horizontal direction if no obstruction is known
## (e.g. the last few recoveries found nothing specific). Aug 2026 —
## `distance` param (was always STUCK_NUDGE_DISTANCE before) and the
## type widened from RigidBody3D to Node3D so this can also be called
## with another NPC (CharacterBody3D) as the obstruction.
func _nudge_free_of_obstruction(obstruction: Node3D, distance: float = STUCK_NUDGE_DISTANCE) -> void:
	var away: Vector3
	if obstruction != null and is_instance_valid(obstruction):
		away = global_position - obstruction.global_position
	else:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1.0, 0.0, 0.0)
	global_position += away.normalized() * distance
```

**Anchor:** immediately after the existing `_find_stuck_obstruction()`:

```gdscript
func _find_stuck_obstruction() -> RigidBody3D:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is RigidBody3D and not (("is_held" in body) and body.is_held) and not body.is_in_group("shelved"):
			return body as RigidBody3D
	return null
```

Add immediately after it:

```gdscript
## Aug 2026 — the NPC counterpart to _find_stuck_obstruction() above.
## Only ever checked when that function finds nothing, so an item
## obstruction still always takes priority when both happen to be
## present.
func _find_stuck_obstruction_npc() -> CharacterBody3D:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is CharacterBody3D and body != self and body.is_in_group("npc"):
			return body as CharacterBody3D
	return null
```

Stop and report on anchor mismatch — no improvisation.

**File:** `scripts/npc/NPCDebug.gd`

**Anchor:** the existing `log_stuck_escalation()`:

```gdscript
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

Replace with:

```gdscript
static func log_stuck_escalation(npc: Node, obstruction: Node, streak: int) -> void:
	if not enabled:
		return
	var name: String = "?"
	if obstruction != null and obstruction.has_method("get_display_name"):
		name = obstruction.get_display_name()
	elif obstruction != null and "npc_name" in obstruction:
		name = "NPC:%s" % obstruction.npc_name   ## Aug 2026 — the new NPC-vs-NPC case, so this reads clearly instead of a raw Godot node name
	elif obstruction != null:
		name = str(obstruction.name)
	print("%s STUCK ESCALATION — %s failed to clear the stall %d times in a row, nudging free instead of retrying" \
		% [_fmt(npc), name, streak])
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

1. Spawn a cluster of several NPCs pointed at a dense, tightly-packed
   pile of clutter and let them converge. Confirm the console now shows
   `STUCK ESCALATION` lines naming the blocking NPC (`NPC:Whoever`)
   instead of `?` whenever the cause is another NPC, and confirm the
   crowd visibly disperses rather than shuffling in place indefinitely.
2. Confirm a genuine single-item obstruction (no crowding involved)
   behaves exactly as before — item-caused escalation, item-caused
   nudge, unaffected by this change.
3. Confirm the two streaks (`_stuck_streak_count` for items,
   `_stuck_npc_streak` for NPCs) don't interfere with each other — an
   NPC alternating between being blocked by an item once and another NPC
   once shouldn't wrongly escalate either streak prematurely.
4. Watch a few consecutive NPC-blocking events on the same NPC — confirm
   the first one or two use the smaller nudge, and the moment the streak
   reaches `STUCK_NPC_BACKOFF_AFTER` (2), the next one visibly moves the
   NPC much farther (`STUCK_NPC_BACKOFF_DISTANCE`, 2.5m) rather than
   another small shuffle.

### A known limitation worth flagging

This fixes the *reactive* side — recognizing and correctly escaping an
NPC pile-up once it happens. It doesn't stop multiple NPCs from
initially choosing the same crowded hotspot in the first place (target
selection has no concept of "how many other NPCs are already headed
here"). With clutter urgency now higher across the board, that's likely
to keep happening at least occasionally in a dense mess. If it's still
happening more than you'd like after this lands, the next lever would be
target-selection-side (e.g. weighting away from an item if another NPC
is already nearby/claimed something close to it) rather than another
recovery-side patch — flag it if you want that looked at separately.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
87. Force several NPCs to converge on the same tight clutter pile —
    confirm STUCK ESCALATION lines now name the blocking NPC instead of
    "?", and confirm the group actually disperses instead of shuffling
    in place indefinitely.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: NPC-vs-NPC Crowd Gridlock Fix (Aug 2026)

- Root-caused the "NPCs huddle and shuffle forever" report: multiple
  NPCs converging on the same clutter hotspot (more likely now with the
  clutter-urgency change) physically block EACH OTHER, but
  _find_stuck_obstruction() only ever detects RigidBody3D colliders —
  another NPC (CharacterBody3D) was invisible to it, always logging "?"
  and falling back to a RANDOM-direction nudge, which had real odds of
  shoving an NPC straight into someone else.
- Added _find_stuck_obstruction_npc() and a separate NPC-blocking streak
  (_stuck_npc_streak). Now nudges directly away from the specific
  blocking NPC (not randomly), and escalates to a larger, more decisive
  displacement (STUCK_NPC_BACKOFF_DISTANCE, 2.5m) after
  STUCK_NPC_BACKOFF_AFTER (2) repeated jams instead of many small
  ineffective ones.
- _nudge_free_of_obstruction() now takes a distance parameter and a
  Node3D obstruction (was hardcoded to STUCK_NUDGE_DISTANCE and typed to
  RigidBody3D only).
- Known limitation, not addressed here: this is reactive (escape once
  crowded), not preventive (nothing stops multiple NPCs choosing the
  same hotspot in the first place). Flagged for a possible future
  target-selection-side pass if still an issue after this lands.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
