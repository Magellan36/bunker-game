# NPC Give Fix + Dedicated Snatch Activity + Relationship Debug Buttons (Aug 2026)

**Owner:** NPC Claude instance. Touches `scripts/npc/NPCActivity.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCItemUser.gd`, `scripts/npc/NPCDebug.gd`,
`scripts/ui/menus/AdminMenu.gd`. This is a complete, standalone
restatement of Give's transfer mechanism and a full redesign of the
Snatch mechanic — apply this document's code as the final state of these
functions, not as a diff against an assumed prior version.

**Also requires a Player-side fix** — separate file,
`PLAYER_SUBSYSTEM_INVENTORY_CLEAR_FIX.md` — Give and Snatch will keep
leaving the item in the player's inventory list without it.

---

## Part A: Give — real item transfer (restated in full)

The item must physically leave the player's hand, appear in the NPC's
hand, and get consumed over the NPC's normal eating/drinking duration —
not have its nutrition/hydration applied instantly while it stays with
the player.

### 1. `scripts/npc/NPCActivity.gd` — full file

Replace the entire file with:

```gdscript
extends RefCounted
class_name NPCActivity
## NPCActivity.gd  (NPC Pass 2, Part 2)
## Base class for one thing an NPC can be doing. Subclasses live inline in
## NPCBrain.gd (wander/sit) and later parts add more (eat/drink/jobs).
## Lifecycle, driven by NPCBrain:
##   score(npc)     — static-ish utility score; higher wins. Called on think
##                    ticks for every candidate. Return <= 0.0 for "not now".
##   enter(npc)     — begin (set nav target etc).
##   tick(npc, dt)  — called every physics frame while active.
##   done(npc)      — return true when finished; brain then re-scores.
##   interruptible()— may a higher-scoring candidate cancel this mid-run?
##   exit(npc)      — cleanup (always called, on finish OR interrupt).
##   label()        — short display string ("Wandering", "Sitting"...), used
##                    by UI in Part 5.
##   begin_with_item(npc, item) — Part 28 — optional; only Given* activities
##                    (a player Give hand-off) implement this. Called once,
##                    right after enter(), whenever this activity is
##                    reached either via NPC.receive_item_from_player()'s
##                    force_command() sequence, or via a take_handoff()
##                    transition (Part 30) from another activity.
##   take_handoff()  — Part 30 — optional. Return a specific NPCActivity
##                    to switch to immediately (checked every tick, right
##                    after tick() runs), instead of finishing via done()
##                    and leaving the choice to normal think-cycle
##                    scoring. Used for SnatchActivity handing off to
##                    GivenEatActivity/GivenDrinkActivity on a successful
##                    grab. Returning non-null MUST be a one-shot — clear
##                    your own reference before returning it, so it never
##                    fires twice.

func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null
```

### 2. `scripts/npc/NPCBrain.gd` — core `tick()` loop gains handoff support

**Anchor:** the exact current `tick(delta)` function:

```gdscript
## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	## Pass-out (Part 14) preempts everything, checked every frame — an
	## empty energy bar collapses the NPC immediately, not on the next
	## think-cycle, and can't be interrupted by anything else.
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		if _current != null:
			NPCDebug.log_activity(_npc, _current.label(), "Passed Out")
			_current.exit(_npc)
		_current = PassedOutActivity.new()
		_current.enter(_npc)

	if _current != null:
		_current.tick(_npc, delta)
		if _current.done(_npc):
			_current.exit(_npc)
			_current = null

	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = THINK_INTERVAL
	_think()
```

Replace with:

```gdscript
## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	## Pass-out (Part 14) preempts everything, checked every frame — an
	## empty energy bar collapses the NPC immediately, not on the next
	## think-cycle, and can't be interrupted by anything else.
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		if _current != null:
			NPCDebug.log_activity(_npc, _current.label(), "Passed Out")
			_current.exit(_npc)
		_current = PassedOutActivity.new()
		_current.enter(_npc)

	if _current != null:
		_current.tick(_npc, delta)
		## Part 30 — explicit handoff to a SPECIFIC successor. Calling
		## force_command() reentrantly from inside an activity's own
		## tick() is unsafe (this same block would immediately stomp
		## whatever force_command() had just set, at the `_current = null`
		## line below) — take_handoff() exists so an activity can request
		## an exact successor safely, from out here in the outer scope.
		var handoff: NPCActivity = _current.take_handoff()
		if handoff != null:
			_current.exit(_npc)
			_current = handoff
			_current.enter(_npc)
			_current.begin_with_item(_npc, _npc.held_item)   ## no-op unless the successor implements it
			_think_timer = THINK_INTERVAL   ## same reasoning as force_command() — don't immediately override this
		elif _current.done(_npc):
			_current.exit(_npc)
			_current = null

	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = THINK_INTERVAL
	_think()
```

### 3. `scripts/npc/NPCBrain.gd` — `GivenEatActivity` / `GivenDrinkActivity`

**Anchor:** immediately after `EatActivity`'s closing `exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _loose != null:
			NPCItemUser.release_item(_loose)
		if not _shelf_pick.is_empty():
			NPCItemUser.release_item(_shelf_pick.get("item"))
		if npc.held_item != null:
			NPCItemUser.release_item(npc.held_item)
			NPCItemUser.drop_held(npc)
```

Insert immediately after (this is the whole class — insert once, it
doesn't need to change if it already exists from an earlier attempt):

```gdscript

class GivenEatActivity extends EatActivity:
	## Player Give hand-off (Part 28). Reuses EatActivity's tick()/done()/
	## exit()/label()/interruptible()/_reacquire_or_finish() completely
	## unchanged — they already key off npc.held_item being set, which is
	## exactly what a gift (or a successful Snatch) produces. Only
	## enter()/score() differ: no search, no claim, never auto-selected.
	func score(_npc: NPC) -> float:
		return 0.0
	func enter(_npc: NPC) -> void:
		_eating = 0.0
	func begin_with_item(_npc: NPC, _item: Node) -> void:
		pass   ## tick() already reads held_item directly — nothing else needed
```

**Anchor:** immediately after `DrinkActivity`'s closing `exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _target != null:
			NPCItemUser.release_item(_target)
		if npc.held_item != null:
			NPCItemUser.release_item(npc.held_item)
			NPCItemUser.drop_held(npc)
		_target = null
		_drinking = 0.0
```

Insert immediately after:

```gdscript

class GivenDrinkActivity extends DrinkActivity:
	## Same reasoning as GivenEatActivity, but DrinkActivity's tick()
	## checks `_target` (not held_item) first — begin_with_item() has to
	## populate that explicitly.
	func score(_npc: NPC) -> float:
		return 0.0
	func enter(_npc: NPC) -> void:
		_drinking = 0.0
		_mode = ""
		_target = null
	func begin_with_item(_npc: NPC, item: Node) -> void:
		_mode = "bottle"
		_target = item
```

### 4. `scripts/npc/NPC.gd` — `receive_item_from_player()`, final form

Find the current `receive_item_from_player()` function (wherever it
currently is) and replace its entire body with:

```gdscript
## Give — real transfer. The item physically leaves the player's hand,
## becomes this NPC's held_item, and gets consumed over the normal
## EatActivity/DrinkActivity duration via GivenEatActivity/
## GivenDrinkActivity — visually identical to the NPC having picked it up
## themselves. Consumption happens async inside those activities' tick(),
## not instantly here — this function's job is the hand-off itself plus
## relationship/burnout/marking bookkeeping.
##
## Sequencing matters: force_command() FIRST (held_item is confirmed null
## by the guard below, so the outgoing activity's exit() can't misfire
## against the incoming gift), THEN the physical pickup/held_item
## transfer, THEN begin_with_item() to finish wiring the new activity.
func receive_item_from_player(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if held_item != null:
		return false   ## hands full — can't receive a gift right now
	if not NPCItemUser.is_giveable(item):
		return false

	var recipients: Array = item.get_meta("npc_gift_recipients", [])
	var already_boosted: bool = recipients.has(npc_id)
	if not already_boosted:
		recipients.append(npc_id)
		item.set_meta("npc_gift_recipients", recipients)

	var activity: NPCActivity
	if NPCItemUser.is_edible(item):
		activity = NPCBrain.GivenEatActivity.new()
	else:
		activity = NPCBrain.GivenDrinkActivity.new()
	brain.force_command(activity)
	item.pickup(hold_point)
	held_item = item
	activity.begin_with_item(self, item)

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, "player", 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		return true

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
	return true
```

---

## Part B: Snatch — dedicated activity, not folded into Eat/DrinkActivity

### Why the previous version almost never worked

Folding the snatch pursuit into EatActivity/DrinkActivity as an internal
"mode" meant it was still, as far as `NPCBrain` was concerned, an
ordinary interruptible `EatActivity`/`DrinkActivity` — `interruptible()`
on both only returns `false` once `_eating`/`_drinking` is actively
counting down, which never happens during the walk-over. That meant the
NORMAL think-cycle (`_think()`, every 1 second) could and did cancel the
pursuit mid-approach the moment anything re-scored competitively — this
is exactly the "walks toward the player, then midway just wanders off"
behavior. It's now a separate, `interruptible() -> false` activity that
can't be preempted once committed to, entered via `force_command()` so
it bypasses normal scoring entirely (same mechanism the "Go eat
something" command buttons already use).

### 5. `scripts/npc/NPCItemUser.gd`

**Anchor:** end of file (after `find_holder()`/`is_giveable()` if those
already exist; otherwise, end of the file as it currently stands).

Ensure this function exists (add it if missing, leave unchanged if it's
already there from an earlier attempt):

```gdscript
## Deliberately NOT a path through grab_loose() — that function's is_held
## guard exists specifically to STOP accidental item theft and should
## stay strict. This is the one intentional, narrowly-gated exception:
## an NPC forcibly taking something the player is actively holding, only
## ever reached via SnatchActivity (itself only ever entered through
## NPC.find_player_snatch_target()'s relationship/chance gate, or the F7
## debug override).
static func snatch_from_player(npc: NPC, player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var item: Node = player.get_held_item()
	if item == null or not is_instance_valid(item) or not item.has_method("pickup"):
		return false
	if flat_distance(npc.global_position, (player as Node3D).global_position) > PICKUP_RANGE:
		return false
	item.pickup(npc.hold_point)
	npc.held_item = item
	if player.has_method("on_item_snatched"):
		player.on_item_snatched()
	return true
```

### 6. `scripts/npc/NPCDebug.gd` — dedicated snatch logging

**Anchor:** end of file, or right after `log_relationship_event()` if
that already exists.

Add:

```gdscript
## Snatch (Part 30) — every stage gets its own line, specifically because
## the earlier version was hard to debug when it silently failed. Always
## logs when enabled, distinct from the continuous relationship tick log.
static func log_snatch(npc: Node, stage: String, detail: String) -> void:
	if not enabled:
		return
	print("%s SNATCH [%s]: %s" % [_fmt(npc), stage, detail])
```

### 7. `scripts/npc/NPCBrain.gd` — `SnatchActivity`, new dedicated class

**Anchor:** add this as a new top-level class in the file — a sensible
location is right after `GivenDrinkActivity` (from Part A above).

```gdscript
class SnatchActivity extends NPCActivity:
	## Player Relationship Snatch (Part 30). Dedicated, non-interruptible
	## activity — see this plan's "why the previous version almost never
	## worked" note for why that matters. Entered via
	## npc.brain.force_command() (never scored/auto-selected). On a
	## successful grab, hands off to GivenEatActivity/GivenDrinkActivity
	## via take_handoff() to actually consume what was grabbed.
	var _player: Node = null
	var _need_filter: Callable
	var _is_edible: bool = false
	var _handoff: NPCActivity = null
	var _outcome_label: String = "Hostile"

	func _init(player: Node, need_filter: Callable, is_edible: bool) -> void:
		_player = player
		_need_filter = need_filter
		_is_edible = is_edible

	func label() -> String:
		return _outcome_label

	func score(_npc: NPC) -> float:
		return 0.0   ## command-only, never auto-selected

	func interruptible() -> bool:
		return false   ## commit once started — this is the actual fix

	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		if _player != null and is_instance_valid(_player):
			npc.set_nav_target((_player as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _player == null or not is_instance_valid(_player):
			NPCDebug.log_snatch(npc, "aborted", "player no longer exists")
			_player = null
			return
		var held: Node = _player.get_held_item() if _player.has_method("get_held_item") else null
		if held == null or not is_instance_valid(held) or not _need_filter.call(held):
			NPCDebug.log_snatch(npc, "aborted", "player no longer holding a matching item")
			_player = null
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_player as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.snatch_from_player(npc, _player):
				NPCDebug.log_snatch(npc, "success", "grabbed item, handing off to consume")
				_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
				_outcome_label = "Snatched!"
			else:
				NPCDebug.log_snatch(npc, "failed", "grab rejected at range (out of PICKUP_RANGE or item invalid)")
			_player = null

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func done(npc: NPC) -> bool:
		return _player == null and _handoff == null

	func exit(_npc: NPC) -> void:
		_player = null
		_handoff = null
```

### 8. `scripts/npc/NPCBrain.gd` — `EatActivity`/`DrinkActivity` request the handoff instead of walking it themselves

**Anchor:** `EatActivity`'s var declarations:

```gdscript
	var _loose: RigidBody3D = null
	var _shelf_pick: Dictionary = {}
	var _eating: float = 0.0
```

Replace with:

```gdscript
	var _loose: RigidBody3D = null
	var _shelf_pick: Dictionary = {}
	var _eating: float = 0.0
	var _pending_snatch: Node = null   ## Part 30 — set in enter()/_reacquire_or_finish(), consumed on first tick()
	var _handoff: NPCActivity = null
```

**Anchor:** `EatActivity.enter()` (its full current body):

```gdscript
	func enter(npc: NPC) -> void:
		_eating = 0.0
		_loose = _find(npc)
```

Replace the START of the function (leave everything after `_loose = _find(npc)` unchanged):

```gdscript
	func enter(npc: NPC) -> void:
		_eating = 0.0
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _pending_snatch != null:
			return   ## handled on first tick() below, via take_handoff()
		_loose = _find(npc)
```

**Anchor:** the very first line of `EatActivity.tick()`:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _eating > 0.0:
```

Replace with:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _pending_snatch != null:
			_handoff = NPCBrain.SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_edible"), true)
			_pending_snatch = null
			return
		if _eating > 0.0:
```

**Anchor:** add `take_handoff()` to `EatActivity` — insert anywhere inside
the class, e.g. right after `interruptible()`:

```gdscript
	func interruptible() -> bool:
		return _eating <= 0.0
```

Replace with:

```gdscript
	func interruptible() -> bool:
		return _eating <= 0.0

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h
```

**Anchor:** `EatActivity._reacquire_or_finish()`:

```gdscript
	func _reacquire_or_finish(npc: NPC) -> void:
		_loose = null
		_shelf_pick = {}
		if npc.hunger >= 55.0:
			return
		_loose = _find(npc)
```

Replace with:

```gdscript
	func _reacquire_or_finish(npc: NPC) -> void:
		_loose = null
		_shelf_pick = {}
		_pending_snatch = null
		if npc.hunger >= 55.0:
			return
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _pending_snatch != null:
			return   ## picked up by tick() next frame
		_loose = _find(npc)
```

**Anchor:** `EatActivity.done()`:

```gdscript
	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty()
```

Replace with:

```gdscript
	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty() and _pending_snatch == null
```

---

Now the same set of changes for `DrinkActivity`:

**Anchor:** `DrinkActivity`'s var declarations:

```gdscript
	var _mode: String = ""        ## "dispenser" | "bottle"
	var _target: Node = null
	var _drinking: float = 0.0
```

Replace with:

```gdscript
	var _mode: String = ""        ## "dispenser" | "bottle"
	var _target: Node = null
	var _drinking: float = 0.0
	var _pending_snatch: Node = null   ## Part 30
	var _handoff: NPCActivity = null
```

**Anchor:** `DrinkActivity.enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		_drinking = 0.0
		var pick: Dictionary = _pick_target(npc)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_drinking = 0.0
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
		if _pending_snatch != null:
			return   ## handled on first tick() below
		var pick: Dictionary = _pick_target(npc)
```

**Anchor:** the very first line of `DrinkActivity.tick()`:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _target == null or not is_instance_valid(_target):
```

Replace with:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _pending_snatch != null:
			_handoff = NPCBrain.SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_drinkable_bottle"), false)
			_pending_snatch = null
			return
		if _target == null or not is_instance_valid(_target):
```

**Anchor:** `DrinkActivity.interruptible()`:

```gdscript
	func interruptible() -> bool:
		return _drinking <= 0.0
```

Replace with:

```gdscript
	func interruptible() -> bool:
		return _drinking <= 0.0

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h
```

**Anchor:** `DrinkActivity._reacquire_or_finish()`:

```gdscript
	func _reacquire_or_finish(npc: NPC) -> void:
		_target = null
		_mode = ""
		if npc.thirst >= 90.0:
			return   ## satisfied — done() ends us next tick
		var pick: Dictionary = _pick_target(npc)
```

Replace with:

```gdscript
	func _reacquire_or_finish(npc: NPC) -> void:
		_target = null
		_mode = ""
		_pending_snatch = null
		if npc.thirst >= 90.0:
			return   ## satisfied — done() ends us next tick
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
		if _pending_snatch != null:
			return   ## picked up by tick() next frame
		var pick: Dictionary = _pick_target(npc)
```

**Anchor:** `DrinkActivity.done()`:

```gdscript
	func done(npc: NPC) -> bool:
		return _target == null or npc.thirst >= 90.0
```

Replace with:

```gdscript
	func done(npc: NPC) -> bool:
		return (_target == null or npc.thirst >= 90.0) and _pending_snatch == null
```

---

## Part C: `scripts/npc/NPC.gd` — chance formula + target-finding + debug hooks

Find/replace the entire block covering `SNATCH_*` constants,
`get_snatch_chance()`, `find_player_snatch_target()`, and
`debug_force_snatch()` with this final version (add it fresh if none of
this exists yet):

```gdscript
# ─── Relationship Snatch (Part 29/30) ───────────────────────────────────────
const SNATCH_RELATIONSHIP_THRESHOLD: float = -50.0
const SNATCH_CHANCE_AT_THRESHOLD: float = 0.05   ## at exactly -50
const SNATCH_CHANCE_AT_MIN: float = 0.5          ## at -100 (fully hostile)

var _debug_force_snatch: bool = false   ## F7 test button only — one-shot

func get_snatch_chance() -> float:
	var rel: float = get_relationship("player")
	if rel > SNATCH_RELATIONSHIP_THRESHOLD:
		return 0.0
	var t: float = clampf(
		(SNATCH_RELATIONSHIP_THRESHOLD - rel) / (SNATCH_RELATIONSHIP_THRESHOLD - RELATIONSHIP_MIN),
		0.0, 1.0)
	return lerp(SNATCH_CHANCE_AT_THRESHOLD, SNATCH_CHANCE_AT_MIN, t)

## Called from EatActivity/DrinkActivity's enter()/_reacquire_or_finish().
## Returns the player node if a snatch should be attempted this search,
## else null. _debug_force_snatch bypasses the relationship gate AND the
## probability roll, but not the "player must actually be holding a
## matching item" check.
func find_player_snatch_target(need_filter: Callable) -> Node:
	var forced: bool = _debug_force_snatch
	_debug_force_snatch = false
	if not forced and get_relationship("player") > SNATCH_RELATIONSHIP_THRESHOLD:
		return null
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return null
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return null
	if not need_filter.call(held):
		return null
	if not forced and randf() > get_snatch_chance():
		return null
	return player

## F7 debug trigger — forces THIS NPC to attempt a snatch against the
## player right now via the normal EatActivity/DrinkActivity entry path
## (same "Go eat something"-style force_command pattern), bypassing
## relationship/chance but still requiring a real matching held item.
func debug_force_snatch() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var held: Node = player.get_held_item()
	if held == null or not is_instance_valid(held):
		return false
	if NPCItemUser.is_edible(held):
		_debug_force_snatch = true
		brain.force_command(NPCBrain.EatActivity.new())
		return true
	if NPCItemUser.is_drinkable_bottle(held):
		_debug_force_snatch = true
		brain.force_command(NPCBrain.DrinkActivity.new())
		return true
	return false

## F7 debug — sets relationship-with-player directly, bypassing the
## Sociability multiplier _adjust_relationship() normally applies, so the
## F7 buttons produce an exact, predictable ±25 for testing.
func debug_adjust_player_relationship(delta: float) -> void:
	var current: float = get_relationship("player")
	relationships["player"] = clampf(current + delta, RELATIONSHIP_MIN, RELATIONSHIP_MAX)
```

---

## Part D: F7 debug — relationship ±25 buttons (all NPCs)

### `scripts/ui/menus/AdminMenu.gd`

**Anchor:** the NPC section's row list — add two new rows anywhere in
that list, e.g.:

```gdscript
			["Force Nearest NPC to Snatch Player Item", _on_npc_force_snatch_pressed],
```

Add immediately after (or anywhere in the NPC rows list):

```gdscript
			["Relationship -25 (All NPCs ↔ Player)", _on_npc_relationship_down_pressed],
			["Relationship +25 (All NPCs ↔ Player)", _on_npc_relationship_up_pressed],
```

**Anchor:** add these handler functions near the other NPC handlers
(e.g. near `_adjust_all_npc_need`):

```gdscript
func _on_npc_relationship_down_pressed() -> void: _adjust_all_npc_relationship(-25.0)
func _on_npc_relationship_up_pressed() -> void:   _adjust_all_npc_relationship(25.0)

func _adjust_all_npc_relationship(delta: float) -> void:
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(npc) and npc.has_method("debug_adjust_player_relationship"):
			npc.debug_adjust_player_relationship(delta)

func _on_npc_force_snatch_pressed() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		push_warning("[AdminMenu] No player found — cannot force snatch")
		return
	var nearest: Node = null
	var nearest_d: float = INF
	for npc: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		var d: float = (npc as Node3D).global_position.distance_to((player as Node3D).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = npc
	if nearest == null:
		push_warning("[AdminMenu] No NPCs spawned — cannot force snatch")
		return
	if nearest.has_method("debug_force_snatch") and not nearest.debug_force_snatch():
		print("[AdminMenu] Force snatch failed — player isn't holding a matching food/water item")
```

---

## Documentation

### `docs/systems/npc/README.md`

Update the Give paragraph to describe real transfer (item leaves the
player's hand, appears in the NPC's, consumed over the normal duration
via `GivenEatActivity`/`GivenDrinkActivity`). Rewrite the Relationship
Snatch section to describe `SnatchActivity` as its own dedicated,
non-interruptible activity (not a mode inside Eat/DrinkActivity), the
`take_handoff()` mechanism, and the new `NPCDebug.log_snatch()` staged
logging. Document the two new F7 relationship buttons.

**Testing Checklist**, add:

```
22. Give any item type to an NPC — confirm it visibly leaves your hand,
    appears in the NPC's, and gets "eaten"/"drunk" over the normal
    duration (overhead label shows "Eating"/"Drinking"), not instantly.
23. With debug logging on, use F7 "Force Nearest NPC to Snatch Player
    Item" repeatedly while holding a matching item near an NPC — confirm
    it succeeds reliably now (not ~1-in-many), and confirm the console
    shows staged SNATCH log lines (started/success, or a specific
    aborted/failed reason) every time, never silent.
24. Confirm F7 relationship ±25 buttons move every spawned NPC's
    relationship with the player by exactly 25 (check via the F7
    relationship visualizer), regardless of Sociability.
```

### `HANDOVER.md`

New top section summarizing: Give's real-transfer restatement,
`NPCActivity.take_handoff()`, dedicated non-interruptible
`SnatchActivity`, `NPCDebug.log_snatch()`, and the two new F7 relationship
buttons.

---

## Summary of files touched

| File | Change |
|---|---|
| `scripts/npc/NPCActivity.gd` | New `take_handoff()` virtual (full file replacement shown) |
| `scripts/npc/NPCBrain.gd` | Core `tick()` handoff support; `GivenEatActivity`/`GivenDrinkActivity`; new `SnatchActivity`; `EatActivity`/`DrinkActivity` request handoff instead of walking snatch themselves |
| `scripts/npc/NPC.gd` | `receive_item_from_player()` final form; snatch chance/finder/debug functions; relationship debug adjuster |
| `scripts/npc/NPCItemUser.gd` | `snatch_from_player()` |
| `scripts/npc/NPCDebug.gd` | `log_snatch()` |
| `scripts/ui/menus/AdminMenu.gd` | Snatch button (if not already present) + two relationship ±25 buttons |
| `docs/systems/npc/README.md` | Updated Give/Snatch sections, 3 new Testing Checklist items |
| `HANDOVER.md` | New session entry |

**Separate file, Player subsystem:**
`PLAYER_SUBSYSTEM_INVENTORY_CLEAR_FIX.md` — Give/Snatch will keep failing
to clear the player's inventory list without it.
