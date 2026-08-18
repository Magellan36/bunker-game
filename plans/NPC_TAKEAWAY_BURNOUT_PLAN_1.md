# NPC Universal Takeaway + Gift Burnout & Anti-Repeat (Aug 2026)

**Owner:** NPC Claude instance (this plan).

**Prerequisite:** requires `RELATIONSHIPS_GROUNDWORK_PLAN.md`,
`NPC_NAMES_ASK_ABOUT_PLAN.md`, and
`NPC_GIVE_TAKEAWAY_VISUALIZER_PLAN.md` already applied — this plan edits
functions those three created. Anchors below are written against the file
**as those three plans leave it**.

**⚠️ Cross-subsystem coordination flag:** same as the prior plan — Section
2 edits `scripts/player/InteractionSystem.gd` (Player subsystem). Flag it
before applying.

## What this pass changes

1. **Takeaway, unrestricted.** The previous need-triggered gate on WHICH
   items can be picked up from an NPC is removed — any item an NPC holds,
   for any reason, is now a valid `[F] Pick up` target. The relationship
   ding stays narrow, though: it still only fires when the item taken was
   a genuine need-triggered food/water consumption, exactly as before —
   only the pickup *permission* is broadening, not the *consequence*
   trigger.
2. **Gift burnout.** Repeated gifts in a short window give progressively
   smaller relationship boosts, decaying back to full strength over
   roughly 5 in-game days. Stops the "stand there feeding them nonstop"
   exploit.
3. **Per-item gift marking.** Each item instance can only ever produce a
   relationship boost once. This is currently unreachable in practice
   (single-serving Give items are destroyed on their first successful
   gift, so there's no surviving instance to re-offer) — it's here to
   close the exploit path in advance for whenever Give expands to
   multi-charge items, where the same physical item genuinely could
   survive to be re-offered. Flagging this reasoning explicitly in case
   the intent was something else — happy to adjust if so.

**Honest caveat, not silently swept under the rug:** broadening takeaway
to job materials (fuel cans, purifier filters, harvest fetches) means a
player can now interrupt a job mid-carry. I checked `JobActivity` in
`NPCBrain.gd` — every `held_item` reference there is already null-checked,
so this can't crash or double-consume anything. But it does mean a stolen
fuel can/filter lets that job silently "complete" without its actual
effect landing (no fuel added, no filter replaced) rather than erroring
or visibly failing. Not fixed in this pass — noted as Future Work since
fixing it properly means JobActivity detecting the theft and aborting,
which is Brain-side logic outside a quick patch.

---

## 1. `scripts/npc/NPC.gd`

### 1a. Give — burnout + per-item marking

**Anchor:** the exact `receive_item_from_player()` function as left by the
Give/Takeaway plan:

```gdscript
## Give (player → player-initiated hand-off). Called by InteractionSystem
## when the player presses E on this NPC while holding a giveable item.
## Consumed immediately rather than added to held_item — no queue, no
## "what if they're already full/mid-task" edge cases; this can fire even
## while the NPC is separately mid-Eat/DrinkActivity with something else
## in hand, since it never touches `held_item`.
func receive_item_from_player(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not NPCItemUser.is_giveable(item):
		return false
	if item is DishItem or item is FarmProduceItem:
		hunger = minf(100.0, hunger + item.consume_as_food())   ## frees the node
	_adjust_relationship("player", GIVE_RELATIONSHIP_BONUS)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", GIVE_RELATIONSHIP_BONUS, "received gift")
	return true
```

Replace with:

```gdscript
## Give (player → player-initiated hand-off). Called by InteractionSystem
## when the player presses E on this NPC while holding a giveable item.
## Consumed immediately rather than added to held_item — no queue, no
## "what if they're already full/mid-task" edge cases; this can fire even
## while the NPC is separately mid-Eat/DrinkActivity with something else
## in hand, since it never touches `held_item`.
##
## Gift burnout (Part 25): repeated gifts in a short window give
## progressively smaller boosts (`gift_saturation`, 0..1, decays back to 0
## over ~5 game-days via _tick_relationships()) — closes the "stand there
## feeding them nonstop" exploit. Never fully zero (GIFT_BONUS_FLOOR_MULT)
## so a burned-out gift still visibly does *something*, not a dead click.
##
## Per-item marking: each item instance can only ever produce a boost
## ONCE (`npc_gift_used` meta flag, checked/set here). Currently
## unreachable for V1's single-serving scope — the item is destroyed on
## its first successful give (consume_as_food() frees the node), so
## there's no surviving instance to re-offer — but closes the exploit in
## advance for whenever Give expands to multi-charge items (FoodCan/
## WaterBottle — see Future Work), where the same physical item COULD
## otherwise survive to be given again.
const GIFT_SATURATION_MAX: float = 1.0
const GIFT_SATURATION_PER_GIFT: float = 0.25          ## ~4 gifts in a row reaches full burnout
const GIFT_SATURATION_DECAY_PER_GAME_HOUR: float = 1.0 / (5.0 * 24.0)   ## full recovery over ~5 game-days
const GIFT_BONUS_FLOOR_MULT: float = 0.15             ## fully burned out still does *something*
var gift_saturation: float = 0.0

func receive_item_from_player(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not NPCItemUser.is_giveable(item):
		return false
	if item.has_meta("npc_gift_used"):
		return false
	item.set_meta("npc_gift_used", true)
	if item is DishItem or item is FarmProduceItem:
		hunger = minf(100.0, hunger + item.consume_as_food())   ## frees the node
	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
	return true
```

### 1b. Takeaway — ding stays narrow even though pickup no longer does

**Anchor:** the exact `on_item_taken_by_player()` function:

```gdscript
## Called by InteractionSystem the instant the player successfully grabs
## an item this NPC was mid-consumption of. Clears the stale held_item
## reference and releases its claim; EatActivity/DrinkActivity's
## tick()/eat_held_step()/_finish_bottle() already no-op cleanly on a
## null/mismatched held_item (verified against both classes — this was
## checked, not assumed, given how much debugging already went into their
## state machines). One accepted cosmetic gap: if the takeaway happens
## mid-bite (during the ~2s CONSUME_TIME countdown), the NPC visibly
## keeps "eating" empty-handed for the rest of that countdown before the
## activity notices and re-scores — no crash, no double-consumption, just
## a beat of odd animation. A real interrupt/flinch reaction belongs in
## the later visuals pass, not this one.
func on_item_taken_by_player() -> void:
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	_adjust_relationship("player", -TAKEAWAY_RELATIONSHIP_PENALTY)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -TAKEAWAY_RELATIONSHIP_PENALTY, "item taken mid-consumption")
```

Replace with:

```gdscript
## Called by InteractionSystem the instant the player successfully grabs
## ANY item this NPC was holding (Part 25 — takeaway is no longer limited
## to need-triggered consumption; see InteractionSystem's _try_pickup()).
## Clears the stale held_item reference and releases its claim regardless
## of what it was — EatActivity/DrinkActivity's tick()/eat_held_step()/
## _finish_bottle() and JobActivity's fetch/work/complete paths were all
## checked and already no-op cleanly on a null/mismatched held_item (see
## docs/systems/npc/README.md for the one accepted quirk this leaves: a
## stolen job material lets that job silently "complete" without its
## actual effect landing).
##
## The relationship ding, however, still only applies when the item taken
## was a genuinely need-triggered food/water consumption — evaluated
## BEFORE clearing held_item, since is_consuming_from_need() needs it
## still set. Taking a job material away has no relationship consequence.
func on_item_taken_by_player() -> void:
	var was_need_triggered: bool = is_consuming_from_need()
	var item: Node = held_item
	held_item = null
	if item != null:
		NPCItemUser.release_item(item)
	if not was_need_triggered:
		return
	_adjust_relationship("player", -TAKEAWAY_RELATIONSHIP_PENALTY)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", -TAKEAWAY_RELATIONSHIP_PENALTY, "item taken mid-consumption")
```

### 1c. Gift burnout decay tick

**Anchor:** the exact `_tick_relationships()` function (from the
Relationships plan):

```gdscript
func _tick_relationships(h: float) -> void:
	var gain: float = RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR * h
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if NPCItemUser.flat_distance(global_position, other.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship(other.npc_id, gain)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if NPCItemUser.flat_distance(global_position, player.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship("player", gain)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_tick(self)
```

Replace with:

```gdscript
func _tick_relationships(h: float) -> void:
	var gain: float = RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR * h
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if other == self or not is_instance_valid(other) or not ("npc_id" in other):
			continue
		if NPCItemUser.flat_distance(global_position, other.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship(other.npc_id, gain)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if NPCItemUser.flat_distance(global_position, player.global_position) <= RELATIONSHIP_PROXIMITY_RANGE:
			_adjust_relationship("player", gain)
	if gift_saturation > 0.0:   ## Part 25 — same tick cadence as everything else here
		gift_saturation = maxf(0.0, gift_saturation - GIFT_SATURATION_DECAY_PER_GAME_HOUR * h)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_tick(self)
```

### 1d. F7 visualizer — show burnout too

**Anchor:** the exact `_update_relationship_debug_label()` function (from
the Give/Takeaway plan):

```gdscript
	_relationship_debug_label.visible = true
	var lines: Array[String] = []
	for target_id: String in relationships.keys():
		var display: String = "You" if target_id == "player" else _name_for_relationship_id(target_id)
		lines.append("%s: %+.0f (%s)" % [display, relationships[target_id], get_relationship_label(target_id)])
	_relationship_debug_label.text = "\n".join(lines) if not lines.is_empty() else "(no relationships yet)"
```

Replace with:

```gdscript
	_relationship_debug_label.visible = true
	var lines: Array[String] = []
	for target_id: String in relationships.keys():
		var display: String = "You" if target_id == "player" else _name_for_relationship_id(target_id)
		lines.append("%s: %+.0f (%s)" % [display, relationships[target_id], get_relationship_label(target_id)])
	if gift_saturation > 0.0:   ## Part 25
		lines.append("Gift burnout: %d%%" % int(round(gift_saturation * 100.0)))
	_relationship_debug_label.text = "\n".join(lines) if not lines.is_empty() else "(no relationships yet)"
```

---

## 2. `scripts/player/InteractionSystem.gd` — ⚠️ Player subsystem, coordinate before applying

Removes the need-triggered gate from all three places the Give/Takeaway
plan added it, restoring the first two to their pre-existing form and
simplifying the third.

### 2a. CASE 2 prompt loop — drop the gate entirely

**Anchor:**

```gdscript
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		# Currently held — Case 1 handles it, UNLESS it's an NPC mid-
		# consumption of a genuinely low-need food/water item (Part 24
		# takeaway). That case needs its own carve-out here since the
		# player isn't holding anything, so Case 1 never runs for it.
		if "is_held" in body and body.is_held:
			var holder: Node = NPCItemUser.find_holder(body, get_tree())
			if holder == null or not holder.is_consuming_from_need():
				continue
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue
```

Replace with:

```gdscript
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		# Currently held (Part 25 — no longer skipped at all; any item an
		# NPC holds is a valid takeaway target now). Case 2 only ever runs
		# with the player's own hands empty, so any is_held item found
		# here can only belong to an NPC, never the player.
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue
```

### 2b. `_try_pickup()` — drop the gate, keep the notify

**Anchor:**

```gdscript
			## NPC-held items (Part 24) — normally excluded like shelved/
			## frozen items, UNLESS the holding NPC is mid-consumption of a
			## genuinely low-need food/water item. Same gate as the prompt
			## loop above (5d) — kept in sync deliberately.
			if "is_held" in body and body.is_held:
				var holder: Node = NPCItemUser.find_holder(body, get_tree())
				if holder == null or not holder.is_consuming_from_need():
					continue
			var d: float = body.global_position.distance_to(player.global_position)
```

Replace with:

```gdscript
			## NPC-held items (Part 25) — any item an NPC holds, for any
			## reason, can now be taken. The old need-triggered gate here
			## is gone; NPC.is_consuming_from_need() still exists and
			## still decides whether taking it dings the relationship
			## (see NPC.on_item_taken_by_player()) — it just no longer
			## decides whether the pickup is ALLOWED.
			var d: float = body.global_position.distance_to(player.global_position)
```

(`taken_from`/`on_item_taken_by_player()` call further down in this same
function are unchanged — still needed to clear the NPC's stale reference
and let it decide the ding.)

### 2c. `_nearest_pickup_distance()` — revert to its pre-existing form

**Anchor:**

```gdscript
			## Same Part 24 gate as _try_pickup() — keeps this fairness
			## peek consistent with what _try_pickup() would actually grab.
			if "is_held" in body and body.is_held:
				var holder: Node = NPCItemUser.find_holder(body, get_tree())
				if holder == null or not holder.is_consuming_from_need():
					continue
			var d: float = body.global_position.distance_to(player.global_position)
```

Replace with:

```gdscript
			var d: float = body.global_position.distance_to(player.global_position)
```

---

## 3. Documentation updates (required — do not skip)

### `docs/systems/npc/README.md`

**3a.** In the **Give / Takeaway** section (from the prior plan), find the
Takeaway paragraph:

```
**Takeaway.** An item an NPC is holding is normally pickup-blocked for the
player (`is_held` excludes it). That block now has one narrow exception:
while the NPC is actually mid-Eat/DrinkActivity because hunger or thirst
is genuinely below 55 (`NPC.is_consuming_from_need()` — the exact same
threshold EatActivity/DrinkActivity themselves auto-trigger on), the
normal `[F] Pick up` prompt reappears on that item. Taking it applies a
flat -15 relationship penalty
(`NPC.on_item_taken_by_player()`/`TAKEAWAY_RELATIONSHIP_PENALTY`) and
clears the NPC's stale `held_item` reference. A player-forced "Go eat
something" command issued while the NPC wasn't actually hungry does NOT
make the held item takeable — the gate is live need level, not which
activity path triggered the hold.
```

Replace with:

```
**Takeaway.** Any item an NPC is holding, for any reason, is now a valid
`[F] Pick up` target for the player — the earlier need-triggered pickup
gate (Aug 2026) was removed (Part 25) in favor of relying only on the
relationship consequence, not access, to keep this fair. Taking it clears
the NPC's stale `held_item` reference always
(`NPC.on_item_taken_by_player()`); the -15 relationship penalty
(`TAKEAWAY_RELATIONSHIP_PENALTY`) still only fires when the item was a
genuinely need-triggered food/water consumption
(`NPC.is_consuming_from_need()`, hunger/thirst < 55, the same threshold
Eat/DrinkActivity themselves auto-trigger on) — taking a job material
(fuel can, purifier filter, harvest fetch) away has no relationship
consequence. A player-forced "Go eat something" command issued while the
NPC wasn't actually hungry still doesn't count as need-triggered.

Known accepted quirk: stealing a job material mid-carry doesn't abort the
job — `JobActivity`'s `held_item` references are all null-checked, so it
can't crash, but the job silently "completes" without its actual effect
landing (no fuel added, no filter replaced). Not fixed this pass — see
Future Work.
```

**3b.** In the same section, find the Give paragraph's last sentence:

```
Deliberately single-serving only —
`FoodCan`/`WaterBottle` are multi-charge items and what happens to a
partially-given can/bottle is a real open question, not silently decided
here.
```

Replace with:

```
Deliberately single-serving only —
`FoodCan`/`WaterBottle` are multi-charge items and what happens to a
partially-given can/bottle is a real open question, not silently decided
here.

**Gift burnout (Aug 2026, Part 25).** Repeated gifts in a short window
give progressively smaller boosts: each NPC tracks `gift_saturation`
(0..1), +0.25 per successful gift, decaying back to 0 over ~5 game-days
(`GIFT_SATURATION_DECAY_PER_GAME_HOUR`, same `game_hours()` clock every
other NPC system uses — day-scale, matching Mood). The actual boost is
`GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)`
— never fully zero (floor 0.15x) so a burned-out gift still visibly does
something rather than feeling broken. Stacks with (multiplies against)
the Sociability multiplier `_adjust_relationship()` already applies.
Closes the "stand there feeding them nonstop" exploit.

**Per-item gift marking.** Each item instance can only ever produce a
boost once (`item.set_meta("npc_gift_used", true)`, checked before
allowing a repeat). Currently unreachable in practice — a single-serving
Give item is destroyed on its first successful gift
(`consume_as_food()` frees the node), so no instance survives to be
re-offered — but this closes the exploit path in advance for whenever
Give expands to multi-charge items, where the same bottle/can genuinely
could otherwise be re-given after a refill or after being taken back.
```

**3c.** In the same section's Future Work list, find:

```
- Multi-use item Give (FoodCan/WaterBottle) — needs a decision on what
  happens to the remaining charge.
```

Replace with:

```
- Multi-use item Give (FoodCan/WaterBottle) — needs a decision on what
  happens to the remaining charge. The gift-marking and burnout
  infrastructure is already in place for whenever this lands.
- JobActivity doesn't detect or react to a stolen job material — the job
  silently "completes" without its effect (see the Takeaway paragraph
  above). A real fix means JobActivity checking for the theft and
  aborting instead of completing.
```

**3d.** In the **Testing Checklist**, add after the items added by the
Give/Takeaway plan (renumber as needed):

```
14. Confirm an NPC holding a non-need item (job material, or food/water
    while hunger/thirst are both above 55) is now ALSO takeable via F —
    and confirm F7's relationship dump shows NO relationship change for
    that specific takeaway (only need-triggered takeaways should ding).
15. Give the same NPC 4-5 dishes/produce in quick succession — confirm
    each successive relationship gain is visibly smaller than the last in
    the F7 debug dump/visualizer, bottoming out around 15% of the base
    +15. Stop giving and watch (or fast-forward via F7's admin tools) —
    confirm "Gift burnout: NN%" in the visualizer decays back toward 0
    over multiple in-game days, not minutes.
```

### `HANDOVER.md`

Add a new top section once this plan has actually been executed:

```markdown
# Handover — NPC Universal Takeaway + Gift Burnout/Anti-Repeat (Aug 2026)

## What changed this session

### Takeaway, unrestricted
- **InteractionSystem.gd** (Player subsystem): removed the
  need-triggered `is_held` gate from the CASE 2 prompt loop and
  `_nearest_pickup_distance()` entirely; `_try_pickup()` keeps the
  `NPCItemUser.find_holder()`/`on_item_taken_by_player()` notify call but
  drops its gating condition. Any NPC-held item is now a valid `[F] Pick
  up` target.
- **NPC.gd**: `on_item_taken_by_player()` now always clears `held_item`,
  but only applies the -15 relationship ding when
  `is_consuming_from_need()` was true at the moment of taking (evaluated
  before clearing). Verified `JobActivity`'s held_item references are all
  null-safe — a stolen job material can't crash, but the job silently
  completes without its effect (accepted quirk, see docs).

### Gift burnout + per-item marking
- **NPC.gd**: `gift_saturation` (0..1, +0.25/gift, decays to 0 over ~5
  game-days via `_tick_relationships()`), `GIFT_BONUS_FLOOR_MULT` (0.15x
  floor), applied as a multiplier on `GIVE_RELATIONSHIP_BONUS` in
  `receive_item_from_player()`. Each item can only produce one boost ever
  (`npc_gift_used` meta flag) — currently unreachable given Give's
  destroy-on-give V1 scope, forward-looking for multi-charge items later.
- F7 relationship visualizer now shows "Gift burnout: NN%" per NPC when
  above 0.

### Docs
`docs/systems/npc/README.md` — Give/Takeaway section rewritten for the
unrestricted-pickup + burnout/marking behavior, Future Work updated, two
new Testing Checklist items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/player/InteractionSystem.gd` ⚠️ Player subsystem
- `docs/systems/npc/README.md`

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 14–15.
```

---

## Summary of files touched

| File | Change |
|---|---|
| `scripts/npc/NPC.gd` | Gift burnout + per-item marking, takeaway ding narrowed to need-triggered only, `_tick_relationships()` decay hook, F7 visualizer burnout line |
| `scripts/player/InteractionSystem.gd` ⚠️ | Removed need-triggered pickup gate (3 spots) |
| `docs/systems/npc/README.md` | Give/Takeaway section rewrite, Future Work update, Testing Checklist additions |
| `HANDOVER.md` | New session entry (add after execution, wording above) |

No `NPCItemUser.gd`, `NPCDebug.gd`, `NPCBrain.gd`, `NPCTalkMenuUI.gd`,
`AdminMenu.gd`, or `MainWorld.gd` changes in this pass.
