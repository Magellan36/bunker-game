# Clutter-Driven Cleaning Urgency + "Put Away What's Already In Hand" Safety Net (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Context

Two changes, building directly on the scoring mechanics explained last
turn:

1. **Escalating urgency.** Cleaning's score should rise with total
   clutter in the bunker, crossing an average NPC's Wander score once
   there are about 11 loose physics objects on the ground anywhere in
   the level.
2. **Held-item safety net.** If an NPC has no job and is holding a loose
   item, it should go store/dispose of that item instead of wandering
   around with it forever. I traced why this happens: when
   `_recover_from_stuck()` force-exits a `CleaningActivity` via
   `stop_current()` — which can happen again mid-carry, e.g. a second
   stuck event hits while already holding the item — `CleaningActivity.
   exit()` only releases the item's *claim*, it never drops or re-queues
   the item itself, because that path was written assuming a successful
   claim-release always meant "never picked it up." It doesn't check
   whether the NPC is now standing there physically holding it. That's
   the concrete bug behind what you're seeing.

---

## Part A — Clutter escalation

### Design

`CLEANING_BASE_SCORE (5.5) × job_priority_weight("CLEANING") (0.5)` =
2.75 for an average-Work-Ethic NPC (job mult 1.0 at trait value 0.5).
Wander's average score is `5.0 × 1.0 (average passive mult)` = 5.0. So
the escalation multiplier needs to reach `5.0 / 2.75 ≈ 1.818` by the
time there are 11 clutter items, starting from 1.0 at zero clutter — a
straight linear ramp: `1.0 + count × (0.818 / 11)`, i.e. `1.0 + count ×
(9/121)`.

"Clutter" = every loose physics item JobBoard is currently tracking as
part of the cleaning system — ready trash, ready organizable items,
*and* the still-settling (not-yet-idle) ones. Using the settling ones
too means urgency starts building the moment things hit the floor, not
90 seconds later — matches "any loose physics objects sitting in the
room," not just the subset currently eligible to be picked up.

### A1 — `JobBoard.gd`: total clutter count getter

**Anchor:** immediately after the existing `get_pending_cleaning_count()`:

```gdscript
## Aug 2026 — cheap count for NPC.get_cleaning_unavailable_reason()'s
## "STILL_SETTLING" check. Same subtraction the periodic debug print
## already does, exposed as a real getter instead of duplicated inline.
func get_pending_cleaning_count() -> int:
	return maxi(0, _cleaning_idle_tracker.size() - _organizable_items_cache.size())
```

Add immediately after it:

```gdscript
## Aug 2026 — total loose clutter in the level right now, for
## CleaningActivity's escalating urgency score: ready trash + ready
## organizable + still-settling (not yet past the idle gate). Includes
## the settling ones deliberately — urgency should build from the
## moment something hits the floor, not only once it's individually
## eligible to be picked up 90s later.
func get_total_clutter_count() -> int:
	return _trash_items_cache.size() + _organizable_items_cache.size() + get_pending_cleaning_count()
```

Stop and report on anchor mismatch — no improvisation.

### A2 — `NPC.gd`: the urgency-ramp constant

**Anchor:**

```gdscript
const CLEANING_BASE_SCORE: float = 5.5
```

Replace with:

```gdscript
const CLEANING_BASE_SCORE: float = 5.5

## Aug 2026 — per-clutter-item urgency ramp. Derived so the AVERAGE
## Cleaning score (base 5.5 × job_priority_weight 0.5 = 2.75, at
## average Work Ethic) crosses the AVERAGE Wander score (5.0, at
## average Work Ethic) once total clutter reaches 11 items:
##   1.0 + 11 × CLUTTER_URGENCY_STEP == 5.0 / 2.75  ->  STEP = 9/121
## Actual per-NPC scores still use that NPC's own Work Ethic multiplier
## on top of this — this only fixes the BREAKEVEN POINT for the
## average case, exactly as asked. See CleaningActivity.score().
const CLUTTER_URGENCY_STEP: float = 9.0 / 121.0
```

Stop and report on anchor mismatch — no improvisation.

### A3 — `NPCBrain.gd`: `CleaningActivity.score()` uses it

**Anchor:**

```gdscript
	func score(npc: NPC) -> float:
		if _is_forced_session:
			return 0.0
		if not npc.has_cleaning_target_available():
			return 0.0
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("CLEANING")

	func interruptible() -> bool:
		return _item == null   ## between items (or before the first), fine to interrupt; mid-carry, commit
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if _is_forced_session:
			return 0.0
		if not npc.has_cleaning_target_available():
			return 0.0
		## Aug 2026 — escalating urgency: the more clutter sits around,
		## the more Cleaning outcompetes Wander/Relax/etc. See
		## NPC.CLUTTER_URGENCY_STEP's own comment for the derivation.
		var urgency_mult: float = 1.0 + float(JobBoard.get_total_clutter_count()) * NPC.CLUTTER_URGENCY_STEP
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("CLEANING") * urgency_mult

	func interruptible() -> bool:
		return _item == null   ## between items (or before the first), fine to interrupt; mid-carry, commit
```

Stop and report on anchor mismatch — no improvisation.

Note: this only changes the SCORE ceiling that has to be crossed to
start/continue a cleaning session — it doesn't touch the destination-
first logic, the light-storage preference, the stale-cache fix, or
anything else from earlier plans. An NPC that starts Cleaning under
this higher urgency behaves identically once it's running.

---

## Part B — Put away whatever's already in hand when nothing else claims it

### Design

A small, self-contained new activity, not a change to `CleaningActivity`
itself — this keeps all of `CleaningActivity`'s existing (and recently
fixed) logic completely untouched, and isolates the new safety-net
behavior as its own clearly-scoped unit.

It scores a flat, modest value whenever `npc.held_item != null` — high
enough to reliably beat Wander/Relax/Sit/Lie/Talk (all scoring well
under 15 even at their own maximums, per last turn's numbers) plus the
interrupt margin, but deliberately far below any real active need. A
genuinely-thirsty/hungry NPC mid-`DrinkActivity`/`EatActivity` while
holding its bottle/food scores `(100 - need) × 1.2 × mult`, which even
at the weakest possible trigger point (need just under the 55 cutoff) is
comfortably in the high-30s to high-80s — this new activity's flat score
never gets close to threatening that, so a legitimate hold is never
interrupted. It only ever wins against activities that have no concept
of held items at all, which is exactly the gap being closed.

### B1 — `NPCBrain.gd`: the new activity

**Anchor:** register it in `setup()`'s candidate list:

```gdscript
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
		RelaxActivity.new(),
		TalkActivity.new(),
		GiveToFriendActivity.new(),
		CleaningActivity.new(),
		RefuelActivity.new(),
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
		TalkActivity.new(),
		GiveToFriendActivity.new(),
		CleaningActivity.new(),
		RefuelActivity.new(),
		PutAwayHeldItemActivity.new(),
```

**Anchor:** add the new class directly after `CleaningActivity`'s closing
(right before `class RefuelActivity extends NPCActivity:` begins):

```gdscript
class PutAwayHeldItemActivity extends NPCActivity:
	## Aug 2026 — safety net for a held item left over with nothing
	## actually using it. Concretely: _recover_from_stuck() can
	## stop_current() a CleaningActivity that's already mid-carry (e.g.
	## a second stuck event fires while still holding the item) —
	## CleaningActivity.exit() only releases the item's CLAIM, since a
	## claim release was always meant to mean "never picked it up," not
	## "was holding it and gave up." Without this, that item stays in
	## the NPC's hand through Wander/Relax/Sit/Lie/Talk indefinitely,
	## since none of those have any concept of held items.
	##
	## Deliberately a flat, modest score — comfortably above Wander/
	## Relax/Sit/Lie/Talk's own ranges plus the interrupt margin, but far
	## below any activity with a genuine, real hold on the item (Drink/
	## Eat/GiveToFriend/Cleaning/Refuel all score based on real urgency
	## while they're the ones holding something, and none of those are
	## ever _current at the same time this activity would be scored
	## against them anyway — this only ever competes against activities
	## that don't hold anything).
	const SCORE: float = 20.0

	var _item: RigidBody3D = null
	var _destination: Node = null
	var _settled: bool = false   ## delivered, dropped, or lost — done() flips true

	func label() -> String:
		return "Putting away %s" % (_item.get_display_name() if _item != null and _item.has_method("get_display_name") else "an item")

	func score(npc: NPC) -> float:
		return SCORE if npc.held_item != null else 0.0

	func interruptible() -> bool:
		return false   ## short and self-contained — always let it finish rather than get preempted mid-delivery

	func enter(npc: NPC) -> void:
		_item = npc.held_item
		_settled = false
		if _item == null or not is_instance_valid(_item):
			_settled = true
			return
		var is_trash: bool = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
		_destination = npc.find_cleaning_destination(is_trash, _item)
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "put away held item", "%s -> %s" % [
				(_item.get_display_name() if _item.has_method("get_display_name") else str(_item.name)),
				(_destination.name if _destination != null else "(no destination — dropping in place)")])
		if _destination == null:
			NPCItemUser.drop_held(npc)
			_settled = true
			return
		npc.set_nav_target((_destination as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _settled:
			return
		if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
			_settled = true   ## lost it somehow (dropped elsewhere, freed) — nothing left to do
			return
		if _destination == null or not is_instance_valid(_destination):
			NPCItemUser.drop_held(npc)
			_settled = true
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			var is_trash: bool = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
			if is_trash and _destination.has_method("npc_deposit_trash"):
				_destination.npc_deposit_trash(npc, _item)
			elif not is_trash and _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
				pass   ## stored successfully
			else:
				NPCItemUser.drop_held(npc)   ## destination filled/changed since the initial check — just set it down rather than loop
			_settled = true

	func done(_npc: NPC) -> bool:
		return _settled

	func exit(_npc: NPC) -> void:
		pass   ## nothing claimed via NPCItemUser — this only ever acts on what's already physically held, never a JobBoard/claim-tracked target
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

### Part A

1. With one NPC and zero clutter, confirm Cleaning's score stays at its
   normal baseline (Wander still wins as before).
2. Drop/spawn roughly 11 loose items across the level (mix of ready and
   still-settling is fine) and check via F7 → Print NPC Cleaning Debug
   State that `get_total_clutter_count()`-equivalent tracking looks
   right; confirm an average-Work-Ethic NPC now picks Cleaning over
   Wander at that count in the fair (no-incumbent) comparison.
3. With far more clutter (30-40+, matching your earlier playtest count),
   confirm Cleaning's score is now comfortably ahead and NPCs are
   picking it up much more readily, including in the no-margin window.
4. Confirm a very low-Work-Ethic NPC still needs somewhat more clutter
   to cross the same line than a high-Work-Ethic one — the ramp affects
   everyone, but the personality multiplier still applies on top.

### Part B

1. Manually give an NPC a held item with no active job (e.g. via F7 or
   by interrupting a stuck-recovery cleanup mid-carry) — confirm it
   immediately switches to "Putting away X" instead of continuing to
   Wander/Relax while holding it.
2. Confirm a legitimately-holding NPC (mid-Drink, mid-Eat, mid-
   GiveToFriend, mid-Cleaning's own carry phase, mid-Refuel) is
   completely unaffected — none of those should ever visibly flicker
   into "Putting away" while genuinely busy.
3. Reproduce the original wedged-NPC-with-abandoned-item scenario (get
   an NPC stuck twice in a row while carrying something, forcing
   `stop_current()` to hit mid-carry) — confirm this time the item
   actually gets stored or dropped in place, instead of being carried
   around indefinitely afterward.
4. Confirm the item still gets delivered correctly (goes to light
   storage if eligible per the existing preference, real shelving
   otherwise) rather than always just being dropped — dropping should
   only happen when no destination is available at all, or delivery
   fails.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
85. Spawn ~11 loose clutter items with an average-Work-Ethic NPC nearby
    with nothing else demanding attention — confirm Cleaning now wins
    over Wander in a fair (no-incumbent) comparison at roughly that
    count, not comfortably before or after it.
86. Force an NPC to hold an item with no active job (e.g. interrupt a
    stuck-recovery cleanup mid-carry) — confirm it immediately switches
    to "Putting away X" rather than wandering/relaxing while still
    holding it. Confirm a genuinely mid-Drink/mid-Eat/mid-GiveToFriend
    NPC is never affected.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Clutter-Driven Cleaning Urgency + Held-Item Safety Net (Aug 2026)

- CleaningActivity.score() now scales with JobBoard.get_total_clutter_
  count() (ready trash + ready organizable + still-settling items) via
  NPC.CLUTTER_URGENCY_STEP, derived so an average-Work-Ethic NPC's
  Cleaning score crosses an average-Work-Ethic NPC's Wander score at
  ~11 total clutter items in the level.
- Added NPCBrain.PutAwayHeldItemActivity — a small, self-contained
  safety net that fires whenever an NPC is holding a loose item with
  nothing else claiming it (root cause: _recover_from_stuck() can
  stop_current() a CleaningActivity mid-carry, e.g. a second stuck event
  hitting while already holding something — CleaningActivity.exit()
  only ever released the item's CLAIM, never dropped/redirected a
  physically-held item, since that path assumed a claim release always
  meant "never picked it up"). Scores a flat, modest value (20.0) —
  enough to beat Wander/Relax/Sit/Lie/Talk, far below any genuine active
  need, so legitimate holds (Drink/Eat/GiveToFriend/Cleaning/Refuel) are
  unaffected.

Files touched: `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
