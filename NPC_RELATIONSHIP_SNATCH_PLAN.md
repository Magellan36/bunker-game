# NPC Relationship Snatch Mechanic + Debug Trigger (Aug 2026)

**Owner:** NPC Claude instance. Touches `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/NPCItemUser.gd`, and
`scripts/ui/menus/AdminMenu.gd` (flagging that last one — I'm not certain
it's mine; existing NPC debug rows already live there, but if it belongs
to a UI/menu-owning instance, coordinate before applying that one file).

**Prerequisite:** `NPC_GIVE_REAL_TRANSFER_AND_THEFT_FIX_PLAN.md` applied
first — this reuses `grab_loose()`'s new `is_held` guard reasoning, and
deliberately adds a SEPARATE function (`snatch_from_player()`) rather
than weakening that guard, since the guard's whole point was stopping
accidental theft — this feature is an intentional, gated exception.

**Also requires a small Player-side addition** — separate file,
`PLAYER_SUBSYSTEM_SNATCH_CONTRACT.md`.

## Design, per your answers

- **Chance scales with hostility.** Only ever considered at relationship
  ≤ -50. At exactly -50: 5% chance per attempt. At -100 (fully hostile):
  50%. Linear between. Evaluated once each time the NPC searches for a
  food/water target (same cadence as everything else in Eat/
  DrinkActivity — on activity entry and after finishing a previous item),
  not continuously.
- **Relationship-neutral.** A successful snatch does NOT further ding the
  relationship — it's already a consequence of an existing bad one, not a
  new event worth logging as its own relationship change.
- **Debug button targets the nearest NPC to the player**, bypasses both
  the relationship gate and the probability roll, but still requires the
  player to actually be holding a matching food/water item (nothing to
  test against otherwise).

---

## 1. `scripts/npc/NPC.gd` — chance formula + target-finding + debug hook

**Anchor:** the exact `receive_item_from_player()` function (leave it
unchanged, insert the new code immediately after it, before the
Takeaway-related functions that follow it).

Insert:

```gdscript
# ─── Relationship Snatch (Part 29) ──────────────────────────────────────────
## A badly-relationship'd NPC has a chance to target the PLAYER instead of
## a normal world item when searching for food/water — "snatching" a held
## item right out of their hands rather than asking or waiting. Gated
## entirely behind relationship <= SNATCH_RELATIONSHIP_THRESHOLD; the
## chance itself scales with how hostile the relationship actually is.
## Deliberately relationship-neutral on success — this is a CONSEQUENCE of
## an already-bad relationship, not a new event that further sours it.
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

## Called from EatActivity/DrinkActivity whenever they'd normally search
## for a new target. `need_filter` is NPCItemUser.is_edible or
## is_drinkable_bottle, matching whichever activity is calling. Returns
## the player node if a snatch should be attempted, else null.
##
## `_debug_force_snatch` (F7 test button) bypasses the relationship gate
## and the probability roll — but NOT the "player must actually be
## holding a matching item" check, since there'd be nothing to test
## against otherwise. It's consumed (reset to false) on this call
## regardless of whether a valid target was ultimately found, since it's
## meant to affect exactly one search attempt.
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

## F7 debug trigger. Forces THIS NPC into a snatch attempt against the
## player right now, regardless of relationship — but still requires the
## player to actually be holding a giveable food/water item. Reuses the
## normal EatActivity/DrinkActivity classes (same pattern as
## NPCTalkMenuUI's "Go eat something"/"Go drink something" command
## buttons) rather than a dedicated debug activity — the one-shot
## _debug_force_snatch flag above is what makes the normal activity
## attempt a snatch instead of (or before) its usual search.
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
```

---

## 2. `scripts/npc/NPCItemUser.gd` — the actual grab, deliberately separate from `grab_loose()`

**Anchor:** end of file, after the `find_holder()`/`is_giveable()` block
added by an earlier plan.

Append:

```gdscript

# ─── Relationship Snatch (Part 29) ──────────────────────────────────────────
## Deliberately NOT a path through grab_loose() — that function's is_held
## guard (added specifically to STOP accidental item theft) is correct and
## should stay strict. This is the one intentional, narrowly-gated
## exception: an NPC forcibly taking something the player is actively
## holding, only ever reached via NPC.find_player_snatch_target()'s
## relationship/chance gate (or the debug override).
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

---

## 3. `scripts/npc/NPCBrain.gd` — wire into EatActivity and DrinkActivity

### 3a. `EatActivity`

**Anchor:** the `enter()` function:

```gdscript
	func enter(npc: NPC) -> void:
		_eating = 0.0
		_loose = _find(npc)
		if _loose != null and not NPCItemUser.claim_item(_loose, npc):
			_loose = null   ## lost the race between scoring and entering
		_shelf_pick = {}
		if _loose == null:
			_shelf_pick = _find_shelf(npc)
			if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
				_shelf_pick = {}
		var tgt: Node3D = _loose if _loose != null \
			else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
		if tgt != null:
			npc.set_nav_target(tgt.global_position)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_eating = 0.0
		_snatch_player = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _snatch_player != null:
			npc.set_nav_target((_snatch_player as Node3D).global_position)
			return
		_loose = _find(npc)
		if _loose != null and not NPCItemUser.claim_item(_loose, npc):
			_loose = null   ## lost the race between scoring and entering
		_shelf_pick = {}
		if _loose == null:
			_shelf_pick = _find_shelf(npc)
			if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
				_shelf_pick = {}
		var tgt: Node3D = _loose if _loose != null \
			else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
		if tgt != null:
			npc.set_nav_target(tgt.global_position)
```

**Anchor:** the var declarations at the top of the class:

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
	var _snatch_player: Node = null   ## Part 29
```

**Anchor:** the `tick()` function's held-item check, immediately before
the `_loose` branch:

```gdscript
		if npc.held_item != null:
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see DrinkActivity 3b note)
			_eating = CONSUME_TIME
			return

		if _loose != null and is_instance_valid(_loose):
```

Replace with:

```gdscript
		if npc.held_item != null:
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see DrinkActivity 3b note)
			_eating = CONSUME_TIME
			return

		if _snatch_player != null and is_instance_valid(_snatch_player):
			var held: Node = _snatch_player.get_held_item() if _snatch_player.has_method("get_held_item") else null
			if held == null or not is_instance_valid(held) or not NPCItemUser.is_edible(held):
				_snatch_player = null   ## player dropped/used/gave it away — abandon
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_snatch_player as Node3D).global_position) <= USE_RANGE:
				NPCItemUser.snatch_from_player(npc, _snatch_player)   ## sets npc.held_item on success
				_snatch_player = null   ## either way — success falls through to the held_item branch above next tick
			return
		_snatch_player = null

		if _loose != null and is_instance_valid(_loose):
```

**Anchor:** `done()`:

```gdscript
	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty()
```

Replace with:

```gdscript
	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty() and _snatch_player == null
```

**Anchor:** `_reacquire_or_finish()`:

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
		_snatch_player = null
		if npc.hunger >= 55.0:
			return
		_snatch_player = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _snatch_player != null:
			npc.set_nav_target((_snatch_player as Node3D).global_position)
			return
		_loose = _find(npc)
```

### 3b. `DrinkActivity`

**Anchor:** `enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		_drinking = 0.0
		var pick: Dictionary = _pick_target(npc)
		_mode = pick.get("mode", "")
		_target = pick.get("node", null)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_drinking = 0.0
		var snatch: Node = npc.find_player_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
		if snatch != null:
			_mode = "snatch"
			_target = snatch
			npc.set_nav_target((snatch as Node3D).global_position)
			return
		var pick: Dictionary = _pick_target(npc)
		_mode = pick.get("mode", "")
		_target = pick.get("node", null)
```

**Anchor:** `tick()`:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _target == null or not is_instance_valid(_target):
			_target = null
			return
		if _mode == "bottle":
			_tick_bottle(npc, delta)
		else:
			_tick_dispenser(npc, delta)
```

Replace with:

```gdscript
	func tick(npc: NPC, delta: float) -> void:
		if _target == null or not is_instance_valid(_target):
			_target = null
			return
		if _mode == "bottle":
			_tick_bottle(npc, delta)
		elif _mode == "snatch":
			_tick_snatch(npc, delta)
		else:
			_tick_dispenser(npc, delta)

	## Part 29. Once the snatch succeeds, hands off to the normal "bottle"
	## mode/_tick_bottle() for the rest of the drink — _target gets
	## reassigned from the player to the actual bottle so
	## _finish_bottle()'s `npc.held_item == _target` check (which compares
	## against the bottle, never the player) keeps working unmodified.
	func _tick_snatch(npc: NPC, delta: float) -> void:
		var held: Node = _target.get_held_item() if _target != null and _target.has_method("get_held_item") else null
		if held == null or not is_instance_valid(held) or not NPCItemUser.is_drinkable_bottle(held):
			_target = null
			_mode = ""
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.snatch_from_player(npc, _target):
				_target = npc.held_item
				_mode = "bottle"
			else:
				_target = null
				_mode = ""
```

---

## 4. `scripts/ui/menus/AdminMenu.gd` — debug button (⚠️ verify ownership before applying)

**Anchor:** the NPC section's row list:

```gdscript
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
			["Drain NPC Needs -40", _on_drain_npc_needs_pressed],
			["Drain NPC Mood -40", _on_drain_npc_mood_pressed],
```

Add a new row (position doesn't matter much — appending near the other
single-purpose NPC test buttons is fine):

```gdscript
		{ "name": "NPC", "rows": [
			["Spawn NPC", _on_spawn_npc_pressed],
			["Drain NPC Needs -40", _on_drain_npc_needs_pressed],
			["Drain NPC Mood -40", _on_drain_npc_mood_pressed],
			["Force Nearest NPC to Snatch Player Item", _on_npc_force_snatch_pressed],
```

**Anchor:** end of the NPC-related handler functions (e.g. right after
`_on_npc_print_debug_pressed()`).

Insert:

```gdscript

## Part 29 — forces the NEAREST spawned NPC to attempt a snatch against
## the player right now, bypassing relationship/probability (still
## requires the player to actually be holding a matching food/water
## item). Nearest-to-player, not nearest-to-camera or first-spawned.
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

## Documentation updates

### `docs/systems/npc/README.md`

Add a new subsection under Give/Takeaway, "Relationship Snatch (Aug
2026)": describe the -50 threshold, the 5%→50% linear chance scaling
with hostility (-50 to -100), relationship-neutral outcome, that it only
ever targets a currently player-HELD item (never inventory/stored items),
and the F7 debug button (bypasses gating, still requires a real matching
held item). Note the deliberate separation between `grab_loose()` (guarded,
for legitimate item-finding) and `snatch_from_player()` (the one
intentional exception, reached only through the gated finder function).

**Testing Checklist**, add:

```
20. Use F7 admin tools to push an NPC's relationship with the player to
    -60 or lower (or wait for enough negative interactions). Drain that
    NPC's hunger or thirst below 55, hold a matching item, stay nearby —
    over several attempts, confirm the NPC sometimes paths to the player
    and snatches instead of finding a normal item; confirm relationship
    does NOT change from a successful snatch.
21. Press F7 "Force Nearest NPC to Snatch Player Item" while holding a
    matching item near an NPC with a perfectly fine relationship —
    confirm it snatches anyway. Press it while NOT holding anything (or
    holding a non-food/water item) — confirm it fails gracefully (console
    message, no crash, nothing happens).
```

### `HANDOVER.md`

New top section summarizing: `NPC.get_snatch_chance()`/
`find_player_snatch_target()`/`debug_force_snatch()`,
`NPCItemUser.snatch_from_player()`, EatActivity/DrinkActivity snatch-mode
wiring, the new AdminMenu debug row. Note the Player-side contract
dependency (`get_held_item()`/`on_item_snatched()`).

---

## Summary of files touched

| File | Change |
|---|---|
| `scripts/npc/NPC.gd` | Chance formula, `find_player_snatch_target()`, `debug_force_snatch()` |
| `scripts/npc/NPCItemUser.gd` | `snatch_from_player()` |
| `scripts/npc/NPCBrain.gd` | EatActivity/DrinkActivity snatch-mode integration |
| `scripts/ui/menus/AdminMenu.gd` ⚠️ | New debug row + handler |
| `docs/systems/npc/README.md` | New subsection, 2 Testing Checklist items |
| `HANDOVER.md` | New session entry |

**Separate file, Player subsystem:** `PLAYER_SUBSYSTEM_SNATCH_CONTRACT.md`
— required before this plan can actually work end-to-end.
