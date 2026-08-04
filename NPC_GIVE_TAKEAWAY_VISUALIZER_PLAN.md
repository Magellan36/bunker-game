# NPC Item Give/Takeaway + F7 Relationship Visualizer (Aug 2026)

**Owner:** NPC Claude instance (this plan).


**⚠️ Cross-subsystem coordination flag:** Section 6 of this plan edits
`scripts/player/InteractionSystem.gd`, which is Player subsystem, not NPC
subsystem. I'm providing exact patches because there's no way to implement
Give/Takeaway without touching where the player's E/F prompts and pickup
logic live, but this section specifically should be flagged to whichever
Claude instance owns Player scripts before it's applied, to keep that
subsystem's own conventions/consistency intact. Everything else in this
plan is fully inside NPC subsystem files.

## What this pass builds

1. **Giving** — player holds a single-serving food item (cooked dish or
   farm produce), walks up to an NPC, gets "[E] Give `<item>` to
   `<name>`", presses E. NPC eats it immediately, relationship goes up.
2. **Taking away** — an NPC who's currently eating/drinking because their
   hunger or thirst is genuinely low (not player-commanded busywork) can
   have that item taken right out of their hands: normal "[F] Pick up"
   prompt reappears on the held item (items an NPC holds are normally
   pickup-blocked — this is a deliberate, narrow exception), player
   presses F, item transfers to the player, NPC's relationship toward the
   player drops.
3. **F7 relationship visualizer** — piggybacks on the existing "Toggle NPC
   Debug Logging" row (no new F7 row) per your framing: when
   `NPCDebug.enabled` is on, every NPC gets a floating text readout above
   their head listing their current relationships and bands. Debug-only
   stand-in for the real thing later.

**Explicitly out of scope, called out below too:** multi-use items
(FoodCans, water bottles) for Give — a single give-action fully draining a
multi-charge item is a real design call I didn't want to make silently,
so V1 only covers items that resolve in one atomic bite (`DishItem`,
`FarmProduceItem`). The floating "-15" loss-pulse visual above an NPC's
head is explicitly deferred to a real visuals pass, per your note — the F7
persistent readout is the stand-in until then.

---

## 1. `scripts/npc/NPCItemUser.gd` — two small classifiers

**Anchor:** end of file, after the existing `eat_held_step()` function
(the file currently ends with its closing `return true`).

Append:

```gdscript

# ─── Give/Takeaway helpers (Part 24) ────────────────────────────────────────
## Give (player → NPC) V1 scope: single-serving items only — DishItem and
## FarmProduceItem both resolve fully in one consume_as_food() call, so
## there's no leftover-charge bookkeeping to handle. FoodCan/WaterBottle
## are multi-use (take_bite()/take_drink() are partial) — deliberately
## excluded rather than silently deciding what happens to the remainder.
static func is_giveable(item: Node) -> bool:
	return item is DishItem or item is FarmProduceItem

## Takeaway (player steals mid-consumption). Which live NPC (if any) is
## currently holding this exact item — used both to gate the pickup
## prompt/action and to notify the right NPC once it's taken. A plain
## Node scan of the "npc" group; cheap at bunker-sized NPC counts.
static func find_holder(item: Node, tree: SceneTree) -> Node:
	if item == null:
		return null
	for npc: Node in tree.get_nodes_in_group("npc"):
		if is_instance_valid(npc) and ("held_item" in npc) and npc.held_item == item:
			return npc
	return null
```

---

## 2. `scripts/npc/NPC.gd` — Give (receive from player)

**Anchor:** the exact block added by the Relationships plan:

```gdscript
## FUTURE WORK — see docs/systems/npc/README.md's Relationships section for
## the full list (item giving/taking, crisis-response helping behavior,
## command-compliance feel, personal-space avoidance scaling by
## relationship, unprompted gift-dropping, dialogue tone reflecting
## relationship, a Player→NPC reciprocal value). None of that is built —
## proximity is the only live driver this pass.

```

Insert immediately after it (still before `# ─── Skills (Part 4)`):

```gdscript
# ─── Give / Takeaway (Part 24) ──────────────────────────────────────────────
const GIVE_RELATIONSHIP_BONUS: float = 15.0
const TAKEAWAY_RELATIONSHIP_PENALTY: float = 15.0
## Matches EatActivity/DrinkActivity's own auto-trigger threshold
## (`npc.hunger >= 55.0`/`npc.thirst >= 55.0` → score 0) intentionally —
## "needs it" means the same thing everywhere in the NPC system.
const TAKEAWAY_NEED_THRESHOLD: float = 55.0

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

## Takeaway gate. True only while genuinely hungry/thirsty AND actually
## holding a food/drink item right now — recomputed live rather than
## captured at the moment of pickup. Functionally identical to a captured
## flag for the few-second holding window (need doesn't recover until the
## bite/sip actually lands, which is the exact moment this gate exists to
## intercept), and it correctly excludes a player-forced "Go eat
## something" command issued while the NPC wasn't actually hungry —
## `_talk_menu`'s command buttons use this SAME EatActivity/DrinkActivity
## class, so there's no separate "forced" flag to check; live need level
## is the only signal that's actually true either way.
func is_consuming_from_need() -> bool:
	if held_item == null or not is_instance_valid(held_item):
		return false
	if hunger >= TAKEAWAY_NEED_THRESHOLD and thirst >= TAKEAWAY_NEED_THRESHOLD:
		return false
	return NPCItemUser.is_edible(held_item) or NPCItemUser.is_drinkable_bottle(held_item)

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

---

## 3. `scripts/npc/NPC.gd` — F7 relationship visualizer

**Anchor:** the existing overhead name/activity label block:

```gdscript
# ─── Overhead name/activity label (Part 5) ─────────────────────────────────
## Always-on small billboard: "Name — Activity". Sits ABOVE the Part-4 work
## banner (which shows only during job work phases, below this).
var _overhead_label: Label3D = null
var _overhead_timer: float = 0.0

func _process(delta: float) -> void:
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	_overhead_timer = 0.5
	if _overhead_label == null:
		_overhead_label = Label3D.new()
		_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_overhead_label.fixed_size = true
		_overhead_label.pixel_size = 0.0007
		_overhead_label.font_size = 34
		_overhead_label.outline_size = 8
		_overhead_label.position = Vector3(0.0, 1.85, 0.0)
		_overhead_label.modulate = Color(0.88, 0.90, 0.92, 0.95)
		add_child(_overhead_label)
	var activity: String = brain.current_label() if brain != null else "Idle"
	_overhead_label.text = "%s — %s" % [npc_name, activity]
```

Replace with (adds the visualizer update inside the same 0.5s cadence,
right after the existing label update):

```gdscript
# ─── Overhead name/activity label (Part 5) ─────────────────────────────────
## Always-on small billboard: "Name — Activity". Sits ABOVE the Part-4 work
## banner (which shows only during job work phases, below this).
var _overhead_label: Label3D = null
var _overhead_timer: float = 0.0

func _process(delta: float) -> void:
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	_overhead_timer = 0.5
	if _overhead_label == null:
		_overhead_label = Label3D.new()
		_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_overhead_label.fixed_size = true
		_overhead_label.pixel_size = 0.0007
		_overhead_label.font_size = 34
		_overhead_label.outline_size = 8
		_overhead_label.position = Vector3(0.0, 1.85, 0.0)
		_overhead_label.modulate = Color(0.88, 0.90, 0.92, 0.95)
		add_child(_overhead_label)
	var activity: String = brain.current_label() if brain != null else "Idle"
	_overhead_label.text = "%s — %s" % [npc_name, activity]
	_update_relationship_debug_label()

# ─── Debug relationship visualizer (Part 24) ────────────────────────────────
## Piggybacks the existing "Toggle NPC Debug Logging" F7 row (NPCDebug.
## enabled) rather than adding a 13th row — floating readout above each
## NPC's head of who they know and how they feel. Deliberately plain text;
## this is a debug stand-in for the real in-fiction relationship UI that
## belongs in a later pass once relationships are baked into the game for
## good, not the final thing.
var _relationship_debug_label: Label3D = null

func _update_relationship_debug_label() -> void:
	if not NPCDebug.enabled:
		if _relationship_debug_label != null:
			_relationship_debug_label.visible = false
		return
	if _relationship_debug_label == null:
		_relationship_debug_label = Label3D.new()
		_relationship_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_relationship_debug_label.fixed_size = true
		_relationship_debug_label.pixel_size = 0.0006
		_relationship_debug_label.font_size = 28
		_relationship_debug_label.outline_size = 6
		_relationship_debug_label.position = Vector3(0.0, 2.15, 0.0)
		_relationship_debug_label.modulate = Color(0.55, 0.85, 1.0, 0.95)   ## pale blue — visually distinct from the other two overhead labels
		add_child(_relationship_debug_label)
	_relationship_debug_label.visible = true
	var lines: Array[String] = []
	for target_id: String in relationships.keys():
		var display: String = "You" if target_id == "player" else _name_for_relationship_id(target_id)
		lines.append("%s: %+.0f (%s)" % [display, relationships[target_id], get_relationship_label(target_id)])
	_relationship_debug_label.text = "\n".join(lines) if not lines.is_empty() else "(no relationships yet)"

func _name_for_relationship_id(target_id: String) -> String:
	for other: Node in get_tree().get_nodes_in_group("npc"):
		if is_instance_valid(other) and ("npc_id" in other) and String(other.npc_id) == target_id:
			return String(other.npc_name)
	return target_id
```

---

## 4. `scripts/npc/NPCDebug.gd` — relationship event logging

**Anchor:** the exact block added by the Relationships plan:

```gdscript
## Relationship tick (Part 22) — logs the full current relationships dict
## every ~5s tick when enabled, same cadence as log_mood/log_irritability.
static func log_relationship_tick(npc: Node) -> void:
	if not enabled:
		return
	print("%s relationships: %s" % [_fmt(npc), str(npc.relationships)])

```

Insert immediately after it (still before `## One-shot full snapshot`):

```gdscript
## Discrete relationship events (Part 24) — Give/Takeaway, as opposed to
## log_relationship_tick's continuous background drift. Always worth a
## line since these are deliberate player actions, not ambient ticking.
static func log_relationship_event(npc: Node, target_id: String, delta: float, reason: String) -> void:
	if not enabled:
		return
	var after: float = npc.get_relationship(target_id) if npc.has_method("get_relationship") else 0.0
	print("%s relationship event (%s): %s %+.1f -> %.1f" % [_fmt(npc), reason, target_id, delta, after])

```

---

## 5. `scripts/player/InteractionSystem.gd` — ⚠️ Player subsystem, coordinate before applying

### 5a. Give — prompt (CASE 1, holding an item)

**Anchor:** the existing cooking-pot prompt block, ending with:

```gdscript
			var nearby_stove: Node = _find_nearest_open_stove()
			if nearby_stove != null:
				entries.append({
					"text":      "[E] Place Cooking Pot",
					"world_pos": (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0),
					"dist":      0.0
				})

		if entries.is_empty():
			prompt.hide_prompt()
```

Replace with (adds a new block between the cookpot block and the existing
`if entries.is_empty():`):

```gdscript
			var nearby_stove: Node = _find_nearest_open_stove()
			if nearby_stove != null:
				entries.append({
					"text":      "[E] Place Cooking Pot",
					"world_pos": (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0),
					"dist":      0.0
				})

		# Give to NPC (Part 24) — holding a giveable single-serving food item →
		# "[E] Give <item> to <name>" over each nearby NPC. Mirrors the
		# basket/cookpot blocks above exactly. V1 scope: DishItem/
		# FarmProduceItem only — see NPCItemUser.is_giveable().
		if NPCItemUser.is_giveable(held_item):
			for npc: Node in get_tree().get_nodes_in_group("npc"):
				if not is_instance_valid(npc):
					continue
				var nd: float = (npc as Node3D).global_position.distance_to(player.global_position)
				if nd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Give %s to %s" % [held_item.get_display_name(), String(npc.npc_name)],
					"world_pos": (npc as Node3D).global_position + Vector3(0.0, 1.8, 0.0),
					"dist":      nd
				})

		if entries.is_empty():
			prompt.hide_prompt()
```

### 5b. Give — dispatch on E press

**Anchor:** the existing cookpot dispatch block in `_unhandled_input()`:

```gdscript
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
```

Replace with:

```gdscript
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable food held + an NPC in range → E gives it instead of
		## normal item use (Part 24).
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
```

### 5c. Give — helper functions

**Anchor:** the existing `_find_nearest_open_stove()` function:

```gdscript
func _find_nearest_open_stove() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("has_open_slot") or not node.has_open_slot():
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest
```

Insert immediately after it:

```gdscript

## Same group-scan/range reasoning as _find_nearest_open_stove(), used for
## both the Give prompt (5a) and its dispatch (5b) — same convention the
## stove/pot pair already uses (share one range-bounded finder for both).
func _find_nearest_npc() -> Node:
	var closest: Node       = null
	var closest_dist: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Give dispatch. NPC.receive_item_from_player() frees dish/produce items
## internally (consume_as_food()) — do not touch `item` after a true
## return, mirroring the existing caution around consume_as_food() calls
## elsewhere in this file.
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("receive_item_from_player"):
		return
	if not target.receive_item_from_player(item):
		return
	if item.knocked_out.is_connected(_on_item_knocked_out):
		item.knocked_out.disconnect(_on_item_knocked_out)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false
```

### 5d. Takeaway — prompt visibility (CASE 2, empty-handed)

**Anchor:** the existing candidate-filtering block:

```gdscript
		# Currently held — Case 1 handles it
		if "is_held" in body and body.is_held:
			continue
```

Replace with:

```gdscript
		# Currently held — Case 1 handles it, UNLESS it's an NPC mid-
		# consumption of a genuinely low-need food/water item (Part 24
		# takeaway). That case needs its own carve-out here since the
		# player isn't holding anything, so Case 1 never runs for it.
		if "is_held" in body and body.is_held:
			var holder: Node = NPCItemUser.find_holder(body, get_tree())
			if holder == null or not holder.is_consuming_from_need():
				continue
```

### 5e. Takeaway — actual F-press pickup (execution, not just prompt)

`_try_pickup()` currently has no `is_held` check at all (it's a separate
code path from the prompt loop above), which today means it would already
silently allow grabbing *any* NPC-held item, for *any* reason, any time —
harmless in practice only because the missing prompt keeps players from
ever trying it. This patch both fixes that latent gap and implements the
feature correctly: takeaway becomes possible **only** for the specific
need-triggered case, everywhere, not just in the prompt.

**Anchor:** the existing `_try_pickup()` function:

```gdscript
func _try_pickup() -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("pickup"):
			## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest == null:
		return

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)
```

Replace with:

```gdscript
func _try_pickup() -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("pickup"):
			## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			## NPC-held items (Part 24) — normally excluded like shelved/
			## frozen items, UNLESS the holding NPC is mid-consumption of a
			## genuinely low-need food/water item. Same gate as the prompt
			## loop above (5d) — kept in sync deliberately.
			if "is_held" in body and body.is_held:
				var holder: Node = NPCItemUser.find_holder(body, get_tree())
				if holder == null or not holder.is_consuming_from_need():
					continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest == null:
		return

	var taken_from: Node = NPCItemUser.find_holder(closest, get_tree())   ## Part 24 — look up BEFORE reassigning below

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

	if taken_from != null and taken_from.has_method("on_item_taken_by_player"):   ## Part 24
		taken_from.on_item_taken_by_player()
```

### 5f. Takeaway — keep the stove-pot fairness comparison consistent

**Anchor:** the existing `_nearest_pickup_distance()` function:

```gdscript
func _nearest_pickup_distance() -> float:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body.is_in_group("pickup"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist
```

Replace with:

```gdscript
func _nearest_pickup_distance() -> float:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body.is_in_group("pickup"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			## Same Part 24 gate as _try_pickup() — keeps this fairness
			## peek consistent with what _try_pickup() would actually grab.
			if "is_held" in body and body.is_held:
				var holder: Node = NPCItemUser.find_holder(body, get_tree())
				if holder == null or not holder.is_consuming_from_need():
					continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist
```

---

## 6. Documentation updates (required — do not skip)

### `docs/systems/npc/README.md`

**6a.** In the **Relationships** section's Future Work list (as left by
the Relationships plan), find:

```
- Player handing an NPC food/water directly (positive, stronger than
  passive proximity) vs. an NPC noticing it lost out on a scarce item to
  another NPC (negative).
```

Replace with:

```
- ~~Player handing an NPC food/water directly~~ — done (Give, Aug 2026),
  see the new Give/Takeaway section below. ~~An NPC noticing it lost out
  on a scarce item to another NPC~~ — deliberately NOT built this way in
  the end (see that section for why: no reliable "who wanted it" signal
  existed without inferring desire, which felt arbitrary). Takeaway
  shipped instead, a different and more legible mechanic covering
  overlapping ground.
```

**6b.** Add a brand-new section immediately after the **Names & "Ask
About" Dialogue** section (from the Names plan) and before **Skills &
Jobs**:

```markdown
### Give / Takeaway (Aug 2026)

**Give.** Player holds a single-serving food item (`DishItem` or
`FarmProduceItem` — see `NPCItemUser.is_giveable()`) and walks up to an
NPC: `[E] Give <item> to <name>` appears (mirrors the Basket/Cooking Pot
held-item prompt pattern in `InteractionSystem.gd` exactly). E consumes
the item into the NPC's hunger immediately
(`NPC.receive_item_from_player()`) and applies a flat +15 relationship
bonus (scaled by Sociability like everything else, via
`_adjust_relationship()`). Deliberately single-serving only —
`FoodCan`/`WaterBottle` are multi-charge items and what happens to a
partially-given can/bottle is a real open question, not silently decided
here.

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

As a side effect, this patch also closed a latent gap: `_try_pickup()`
had no `is_held` check at all before this pass (only the prompt did),
meaning any NPC-held item could technically already be silently grabbed
regardless of reason — just never surfaced because the prompt never
showed it. It's now correctly gated everywhere, not just the prompt.

Both directions log through `NPCDebug.log_relationship_event()`
(distinct from `log_relationship_tick`'s continuous proximity logging —
these are discrete, always-worth-a-line player actions).

**F7 relationship visualizer.** Piggybacks the existing "Toggle NPC Debug
Logging" row rather than adding a new one — while `NPCDebug.enabled` is
on, every NPC shows a floating pale-blue text readout above their head
(`NPC._update_relationship_debug_label()`, above the Part-5 name/activity
label) listing every relationship they've formed and its band. Debug-only
stand-in for a real in-fiction relationship UI later, per Brannon.

**`FUTURE WORK`:**
- Multi-use item Give (FoodCan/WaterBottle) — needs a decision on what
  happens to the remaining charge.
- A visible interrupt/flinch reaction when an item is taken mid-bite,
  instead of the NPC finishing its ~2s consumption animation
  empty-handed (a cosmetic gap, not a logic bug — see
  `on_item_taken_by_player()`'s comment).
- The floating "-15"/"+15" loss/gain pulse above an NPC's head — real
  visuals pass, explicitly deferred; the F7 readout is the placeholder.
- NPC-vs-NPC takeaway — structurally impossible right now (the item claim
  system already prevents one NPC from ever targeting another's claimed
  item), so this only ever fires against the player today.
```

**6c.** In the **Testing Checklist**, add three new items after the ones
added by the Names plan (renumber as needed):

```
11. Get an NPC's hunger or thirst below 55 (F7 "Drain NPC Needs -40"),
    let them start eating/drinking, then walk up mid-consumption and
    press F — confirm the normal "[F] Pick up" prompt appears and taking
    it works, the NPC doesn't error or double-consume, and F7 "Print NPC
    Debug State" / the relationship dump shows -15 toward "player".
    Separately, confirm an NPC holding an item for a non-need reason
    (full hunger/thirst, forced via "Go eat something" while not hungry,
    or a job material) is NOT takeable.
12. Hold a cooked dish or piece of produce, walk up to an NPC — confirm
    "[E] Give <item> to <name>" appears and works, hunger rises, and
    relationship goes up +15. Confirm a FoodCan or water bottle does NOT
    show a Give prompt (out of scope this pass).
13. Toggle F7 "Toggle NPC Debug Logging" on — confirm every NPC shows a
    floating relationship readout above their head; toggle off — confirm
    it disappears.
```

### `HANDOVER.md`

Add a new top section once this plan has actually been executed:

```markdown
# Handover — NPC Give/Takeaway + F7 Relationship Visualizer (Aug 2026)

## What changed this session

### Give
- **NPC.gd**: `receive_item_from_player()` (V1 scope: DishItem/
  FarmProduceItem only), `GIVE_RELATIONSHIP_BONUS` (+15).
- **NPCItemUser.gd**: `is_giveable()`.
- **InteractionSystem.gd** (Player subsystem — coordinate before merging):
  new "[E] Give `<item>` to `<name>`" prompt block (mirrors Basket/
  Cooking Pot pattern) + dispatch, `_find_nearest_npc()`,
  `_try_give_to_nearest_npc()`.

### Takeaway
- **NPC.gd**: `is_consuming_from_need()` (gated on the same 55.0 threshold
  Eat/DrinkActivity auto-trigger on), `on_item_taken_by_player()`,
  `TAKEAWAY_RELATIONSHIP_PENALTY` (-15).
- **NPCItemUser.gd**: `find_holder()`.
- **InteractionSystem.gd**: `_try_pickup()` and `_nearest_pickup_distance()`
  gained an `is_held` carve-out for need-triggered NPC holds (this also
  closes a latent gap — `_try_pickup()` previously had no `is_held` check
  at all); the CASE 2 prompt loop gained the matching carve-out.

### F7 Relationship Visualizer
- **NPC.gd**: `_update_relationship_debug_label()`, piggybacking
  `NPCDebug.enabled` (no new F7 row) — floating per-NPC relationship
  readout above the Part-5 name/activity label.
- **NPCDebug.gd**: `log_relationship_event()` for discrete Give/Takeaway
  events (separate from the existing continuous `log_relationship_tick`).

### Docs
`docs/systems/npc/README.md` — new Give/Takeaway section, Relationships'
Future Work item marked done/superseded, three new Testing Checklist
items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPCDebug.gd`
- `scripts/player/InteractionSystem.gd` ⚠️ Player subsystem
- `docs/systems/npc/README.md`

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 11–13.
```

---

## Summary of files touched

| File | Change |
|---|---|
| `scripts/npc/NPC.gd` | Give/Takeaway functions, F7 relationship visualizer |
| `scripts/npc/NPCItemUser.gd` | `is_giveable()`, `find_holder()` |
| `scripts/npc/NPCDebug.gd` | `log_relationship_event()` |
| `scripts/player/InteractionSystem.gd` ⚠️ | Give prompt/dispatch, Takeaway prompt/pickup gating |
| `docs/systems/npc/README.md` | New Give/Takeaway section, Future Work update, Testing Checklist additions |
| `HANDOVER.md` | New session entry (add after execution, wording above) |

No `AdminMenu.gd`, `NPCTalkMenuUI.gd`, `MainWorld.gd`, `NPCBrain.gd`, or
`NPC.tscn` changes in this pass — Eat/DrinkActivity's state machines are
deliberately untouched (their existing null-checks already absorb a
mid-consumption takeaway cleanly, verified by reading both classes rather
than assumed).
