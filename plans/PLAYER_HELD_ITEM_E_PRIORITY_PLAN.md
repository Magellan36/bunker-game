# Plan: Held-Item E Priority Is Unconditional (Aug 2026)

**Owner:** Player subsystem (this plan)
**File touched:** `scripts/player/InteractionSystem.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

---

## Verified: the rule wasn't actually being enforced — here's the gap

I audited the full E-dispatch chain in `_unhandled_input()` against your
stated rule rather than assuming it already held. It mostly does, but
there's a real, confirmed gap.

**What already works correctly:** `_try_interact()` (world objects —
stove, generators, breakers) only ever runs in the `else` branch of
`if held_item != null:` — it's structurally impossible for it to fire
while holding anything. Your stove example was already safe; nothing to
fix there.

**What doesn't:** the shelf check runs **first**, before any held-item
check, and only wins or loses based on a distance comparison
(`_nearest_e_rival_distance()`) — the "distance fairness" rule from
earlier this session (fixing a *closer* basket target losing to a
*farther* shelf). That comparison only accounts for Basket/Cooking
Pot/giveable items. For **every other held item that has its own E
action**, `_nearest_e_rival_distance()` returns `INF` by design — meaning
the shelf wins automatically whenever it's in range (2.5 m), regardless
of what's in the player's hand. I confirmed this actually affects real
items: **10 different item scripts implement `on_use()`**
(`Flashlight`, `FuelCan`, `WaterBottle`, `FoodCan`, `DishItem`,
`FarmProduceItem`, `SeedItem`, `FertilizerItem`, `BagOfSoilItem`,
`PurifierFilterItem`). Today, standing within 2.5 m of a Shelf/Dresser/
End Table while holding any of these means E opens the shelf instead of
toggling your flashlight, refueling, drinking, eating, etc. — exactly
the bug you're describing, just not limited to storage-vs-storage; it's
storage-vs-*anything held*.

**One thing worth preserving, not "fixing":** `TestCrate.gd` (the
Crate) implements **neither** `on_use()` nor `on_interact()` — it
genuinely has no E action at all. Per your own phrasing ("that *can be*
interacted with via E"), a held item with nothing for E to do should
still let a nearby shelf capture E normally — the alternative (E doing
literally nothing near a shelf while holding a Crate) would be worse,
not more correct, and directly undercuts the storage-fallback work from
earlier this session aimed at exactly this "tight bunker" scenario.
Can Case/Water Case do implement `on_interact()` (case-opening), so
they're correctly included in the "always wins" set, not the Crate's
carve-out.

---

## The fix

Reorder the dispatch so every held-item E-action check (Basket, Cooking
Pot, Give, and now the generic `on_use()`/`on_interact()` case) runs
**before** the shelf check, each returning immediately if it applies.
The shelf check moves to being a pure fallback, reached only when
nothing in the player's hand claims E for itself — and since the held
item now always wins by construction rather than by distance, the
distance comparison itself is no longer needed and is removed along
with the two helper functions that existed only to support it.

**Anchor:** verified current lines 173–227 (the entire E-dispatch
block).

```gdscript
old_str:
	# E — use held item (instant tap) / shelf open / world interact.
	# Pure tap: fires immediately on press, no hold-to-store behavior.
	if event.is_action_pressed("interact"):
		## Distance fairness (Aug 2026, third instance of the stove-pot /
		## ready-dish pattern): a nearby shelf no longer unconditionally
		## captures E. If the held item has its own E action with a target
		## in range (basket stash, cookpot stove/stash, NPC give), the
		## shelf only wins when it is STRICTLY closer than that target.
		## Empty-handed or holding an ordinary item → behavior unchanged:
		## rival distance is INF, shelf always wins within its 2.5 m reach.
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			var shelf_d: float = shelf.global_position.distance_to(player.global_position)
			if shelf_d < _nearest_e_rival_distance():
				shelf.on_e_interact()
				get_viewport().set_input_as_handled()
				return
		## Basket held → E stashes nearest "basket_storable" item instead of item use
		if held_item != null and ("is_basket_container" in held_item):
			_try_add_nearest_to_basket(held_item)
			get_viewport().set_input_as_handled()
			return
		## Cooking Pot held → E either places it on a nearby open Stove, or
		## (if no open stove in range) stashes the nearest "cookpot_storable"
		## item into it. Mirrors the basket branch immediately above exactly.
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable item held + an NPC in range → E gives it instead of
		## normal item use.
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
			# _is_holding_e stays true only to drive per-frame continuous
			# actions (e.g. FuelCan.refuel_tick / bottle refill) — it no
			# longer gates a store action.
			_is_holding_e = true
			if held_item.has_method("on_use"):
				held_item.on_use()
			elif held_item.has_method("on_interact"):
				held_item.on_interact()
		else:
			## A ready dish takes priority over other interactables ONLY if
			## it's truly the closest one — same distance-fairness fix
			## already applied to the [F] stove-pot pickup case.
			var ready_pot: Node = _find_nearest_ready_pot()
			if ready_pot != null:
				var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
				if pot_dist <= _nearest_interact_distance():
					_try_take_dish(ready_pot)
					return
			_try_interact()

new_str:
	# E — use held item (instant tap) / shelf open / world interact.
	# Pure tap: fires immediately on press, no hold-to-store behavior.
	if event.is_action_pressed("interact"):
		## Held-item E priority (Aug 2026) — an item's own E action ALWAYS
		## wins over a nearby shelf/dresser/end table, unconditionally,
		## whenever it has one. Supersedes the earlier "distance fairness"
		## rule (shelf won only if farther than a basket/cookpot/give
		## target) — that covered those three cases but left every OTHER
		## held item with its own E action (Flashlight, FuelCan, Water
		## Bottle, Food Can, Dish, produce, seeds, fertilizer, soil, filter
		## — anything implementing on_use()) losing E to any shelf within
		## 2.5 m, since the old distance check returned INF — "shelf
		## always wins" — for all of them. The player's own hands take
		## priority full stop; shelf/stove/world-interact are the
		## fallback, reached only once nothing in the player's hand claims
		## E for itself. A held item with genuinely no E action at all
		## (Crate — implements neither on_use() nor on_interact())
		## deliberately still falls through to the shelf check below: E
		## doing nothing at all near a shelf while holding a Crate would
		## be worse, not more correct, especially given how close together
		## furniture gets placed in a bunker.

		## Basket held → E stashes nearest "basket_storable" item instead of item use
		if held_item != null and ("is_basket_container" in held_item):
			_try_add_nearest_to_basket(held_item)
			get_viewport().set_input_as_handled()
			return
		## Cooking Pot held → E either places it on a nearby open Stove, or
		## (if no open stove in range) stashes the nearest "cookpot_storable"
		## item into it. Mirrors the basket branch immediately above exactly.
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable item held + an NPC in range → E gives it instead of
		## normal item use.
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		## Any other held item with its own E action (Flashlight toggle,
		## FuelCan refuel, WaterBottle drink, FoodCan/Dish/produce eat,
		## seed/fertilizer/soil/filter use, etc.) — also takes unconditional
		## priority. This is the branch that previously ran AFTER the shelf
		## check and could lose to it; moved ahead of the shelf check and
		## given an explicit return so it can't fall through into it.
		if held_item != null and (held_item.has_method("on_use") or held_item.has_method("on_interact")):
			# _is_holding_e stays true only to drive per-frame continuous
			# actions (e.g. FuelCan.refuel_tick / bottle refill) — it no
			# longer gates a store action.
			_is_holding_e = true
			if held_item.has_method("on_use"):
				held_item.on_use()
			elif held_item.has_method("on_interact"):
				held_item.on_interact()
			return

		## Shelf nearby — reached only if empty-handed, or holding
		## something with no E action of its own (Crate, etc. — see
		## header comment). No distance comparison needed any more: if
		## execution reaches here, nothing in the player's hand claimed E,
		## so the shelf is free to.
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			shelf.on_e_interact()
			get_viewport().set_input_as_handled()
			return

		if held_item != null:
			## Holding something with no E action and no shelf in range —
			## E is a no-op here, matching prior behavior exactly (this
			## was already a no-op via a different code path before this
			## fix — just preserving _is_holding_e's per-frame-continuous-
			## action bookkeeping regardless of whether this item uses it).
			_is_holding_e = true
		else:
			## A ready dish takes priority over other interactables ONLY if
			## it's truly the closest one — same distance-fairness fix
			## already applied to the [F] stove-pot pickup case.
			var ready_pot: Node = _find_nearest_ready_pot()
			if ready_pot != null:
				var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
				if pot_dist <= _nearest_interact_distance():
					_try_take_dish(ready_pot)
					return
			_try_interact()
```

---

## Cleanup: remove the now-fully-unused distance-fairness helpers

`_nearest_e_rival_distance()` had exactly one call site — the shelf-
distance comparison just removed above. Confirmed via repo-wide grep it
has no other callers anywhere. Its own only internal dependency,
`_nearest_group_storable_distance()`, likewise has no other callers once
this one is gone. Both become genuinely dead code as a direct result of
this change, so removing them now rather than leaving them for a future
cleanup pass to rediscover.

**Anchor:** verified current lines 777–806.

```gdscript
old_str:
## Distance to the nearest competing E target for the CURRENTLY HELD item —
## used only by the E-dispatch shelf fairness check above. Returns INF
## when the held item has no E action of its own (or nothing is held),
## which makes the shelf win by default, preserving pre-fix behavior for
## those cases.
func _nearest_e_rival_distance() -> float:
	if held_item == null:
		return INF
	if "is_basket_container" in held_item:
		return _nearest_group_storable_distance("basket_storable")
	if "is_cookpot_container" in held_item:
		## Mirrors _try_use_held_cookpot()'s own priority: an open stove
		## in range is the pot's E target; otherwise the nearest storable.
		var stove: Node = _find_nearest_open_stove()
		if stove != null:
			return (stove as Node3D).global_position.distance_to(player.global_position)
		return _nearest_group_storable_distance("cookpot_storable")
	if NPCItemUser.is_giveable(held_item):
		var npc: Node = _find_nearest_npc()
		if npc != null:
			return (npc as Node3D).global_position.distance_to(player.global_position)
	return INF

## Distance-only twin of the candidate scan in _try_add_nearest_to_basket()
## / _try_add_nearest_to_cookpot(). Filters MUST stay in lockstep with
## those two functions — if a body wouldn't be stashable there, it must
## not count as a rival here. (Verified identical to both as of Aug 2026.)
func _nearest_group_storable_distance(group_name: String) -> float:
	return _proximity.nearest_distance_in_group(group_name)

new_str:
```

(Empty `new_str` — this deletes both functions entirely. The blank line
structure before `## E while holding a Basket...` and after
`return closest` above should end up as a single blank line separating
`_find_nearest_npc()` from `_try_add_nearest_to_basket()`, matching the
file's normal spacing convention elsewhere — the coding agent should
verify this visually after the deletion rather than trust exact
whitespace from this diff.)

---

## Why this is safe

- **Basket/Cooking Pot/Give behavior is unchanged in content** — same
  three checks, same functions called, just running unconditionally
  instead of after a since-removed distance gate they never actually
  needed to win by (they already always won against a farther shelf;
  now they always win regardless of distance, which is the stated goal).
- **World-interact (stove, generators, breakers) is completely
  untouched** — still strictly gated to the empty-handed `else` branch,
  confirmed unaffected by this change.
- **Ready-dish priority logic is untouched** — still exactly where it
  was, still only reachable when empty-handed.
- **The Crate carve-out is deliberate, not an oversight** — confirmed
  directly against `TestCrate.gd`'s actual methods, not assumed.
- **`_is_holding_e`'s bookkeeping is preserved in every case** — set
  `true` whenever `held_item != null` on an E-press, matching the
  original unconditional behavior exactly, just relocated to whichever
  branch actually ends up handling that press.

---

## Verification checklist

1. Hold a Flashlight, stand within 2.5 m of a Shelf/Dresser/End Table,
   press E — confirm it toggles the flashlight, the shelf does NOT open.
2. Same test with a Water Bottle (drink), Food Can (eat), Fuel Can
   (refuel tick) — confirm each fires its own action instead of opening
   the shelf.
3. Hold a Crate near a Shelf/Dresser/End Table, press E — confirm the
   shelf/storage still opens normally (this is the deliberate exception,
   worth confirming explicitly rather than assuming).
4. Hold a Basket/Cooking Pot/a giveable food item near a shelf that's
   CLOSER than the basket-storable/cookpot-storable/NPC target — confirm
   the basket/pot/give action still wins now (previously this exact case
   would have lost to the closer shelf under the old distance-fairness
   rule — confirms the policy actually changed, not just got reorganized).
5. Empty-handed, near a Shelf/Dresser/End Table, press E — confirm it
   still opens normally.
6. Empty-handed, near a ready Cooking Pot AND a normal world
   interactable at different distances — confirm the closest-wins logic
   is unaffected (regression check on the untouched `else` branch).
7. Confirm E near a stove (world interact) still only works empty-handed,
   never while holding anything (should already be true; confirming no
   regression from the restructuring around it).
8. Confirm no console errors — specifically confirm nothing else in the
   file references `_nearest_e_rival_distance` or
   `_nearest_group_storable_distance` after their removal (grep before
   marking this step done, not just visual scan).

---

## Documentation updates

### `docs/systems/player/README.md`

Add a new Common-edits entry, after the most recent entry, and replace
the existing "E-dispatch shelf fairness (Aug 2026)" entry (now
inaccurate — describes the superseded distance-based rule) with an
updated one covering the actual current behavior:

```markdown
old entry (find and replace):
- **E-dispatch shelf fairness (Aug 2026):** a nearby shelf no longer
  unconditionally captures E. `_nearest_e_rival_distance()` returns the
  distance to whatever the currently-held item's own E action would
  target (nearest `basket_storable` for a Basket; nearest open stove,
  else nearest `cookpot_storable`, for a Cooking Pot; nearest NPC for a
  giveable item) — INF if the held item has no E action of its own. The
  shelf only wins when strictly closer than that rival distance. This is
  the third instance of the same fairness pattern already used for the
  F-dispatch stove-pot-vs-pickup case and the ready-dish check — future
  E/F priority additions should follow the same shape: compute a rival
  distance, compare strictly, let the closer one win.

new entry:
- **Held-item E priority is unconditional (Aug 2026, supersedes the
  distance-fairness rule below).** A held item's own E action
  (Basket stash, Cooking Pot stove-or-stash, NPC give, or any item
  implementing `on_use()`/`on_interact()` — Flashlight, FuelCan,
  WaterBottle, FoodCan, DishItem, FarmProduceItem, SeedItem,
  FertilizerItem, BagOfSoilItem, PurifierFilterItem) now ALWAYS wins
  over a nearby shelf/dresser/end table, regardless of distance. The
  earlier "distance fairness" rule (shelf wins only if farther than a
  basket/cookpot/give target — see superseded description below) only
  covered those three cases and still let a closer-than-2.5m shelf steal
  E from every other held item with its own action, since the old rival-
  distance check returned INF for anything outside those three. Removed
  `_nearest_e_rival_distance()`/`_nearest_group_storable_distance()`
  entirely — no longer needed once "held item always wins" replaced
  "held item wins if closer." One deliberate exception: a held item with
  genuinely no E action (Crate — implements neither method) still lets
  the shelf capture E normally, since E doing nothing at all would be
  worse given how tightly bunkers get furnished.
- ~~Superseded, kept for history — **E-dispatch shelf fairness (Aug
  2026)**: a nearby shelf no longer unconditionally captures E...~~ (see
  entry above for current behavior)
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Held-Item E Priority Is Unconditional (Aug 2026)

## What changed this session
Fixed the E-dispatch so a held item's own E action always takes priority
over a nearby shelf/dresser/end table, unconditionally — previously only
Basket/Cooking Pot/giveable items had any protection at all (a distance-
fairness rule from earlier this session), and even that only won if
strictly closer than the shelf. Every OTHER held item with its own
`on_use()`/`on_interact()` (Flashlight, FuelCan, WaterBottle, FoodCan,
DishItem, FarmProduceItem, SeedItem, FertilizerItem, BagOfSoilItem,
PurifierFilterItem — 10 item scripts, confirmed via direct grep) had
zero protection: any shelf within 2.5 m always won, full stop. Reordered
the dispatch so every held-item E-check runs before the shelf check,
each with an explicit early return, and removed the distance comparison
entirely — the held item always wins now, not just when closer. One
deliberate exception, confirmed against `TestCrate.gd` directly: a Crate
has neither method, so it still lets a nearby shelf capture E normally.
World-interact (stove/generators/breakers) and the ready-dish priority
check were already correctly gated to empty-handed only — confirmed
unaffected, not touched.

Removed `_nearest_e_rival_distance()` and
`_nearest_group_storable_distance()` — both became fully unused as a
direct result of this change (confirmed via repo-wide grep before
removal), so cleaned them up now rather than leaving fresh dead code.

### Files modified
- `scripts/player/InteractionSystem.gd` — E-dispatch reordered;
  `_nearest_e_rival_distance()`/`_nearest_group_storable_distance()`
  removed.
- `docs/systems/player/README.md` — Common-edits entry replaced (was
  describing the now-superseded distance-fairness rule).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_HELD_ITEM_E_PRIORITY_PLAN.md` for the
full 8-item checklist)
```
