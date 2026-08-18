# Bugfix Plan: Shelf Hijacks E From Closer Held-Item Targets (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** Cross-thread handoff from the Furniture/Build-Mode/Objects
plan-writer (`HANDOFF_TO_PLAYER_THREAD_SHELF_E_HIJACK.md`), verified
against the current on-disk state of `scripts/player/InteractionSystem.gd`
on 2026-08-04 (pulled fresh — repo has since picked up the Storage UI
unification pass, `NPCItemUser.is_giveable()`/`_find_nearest_npc()` from
earlier Give/Takeaway work, and several other subsystems' plans; none of
that touches the code this plan edits, confirmed by direct read below).
**Files touched:** `scripts/player/InteractionSystem.gd` only.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`, and —
per the furniture thread's request to land in the same commit —
`docs/systems/furniture-items/README.md` (one line; flagged below since
that file isn't mine).

---

## Verification against current code

Every anchor and every function this plan depends on was checked
directly, not assumed from the handoff doc:

- E-dispatch block: confirmed shelf check fires first and unconditionally
  (verified current lines 171–176), before the basket/cookpot/give
  branches (178–194), exactly as reported.
- `_nearest_shelf()` (lines 686–701): confirmed 2.5 m flat-XZ reach,
  unchanged, out of scope for this fix.
- `_try_add_nearest_to_basket()` / `_try_add_nearest_to_cookpot()`
  (lines 705–781): confirmed current filters are `body == held_item` →
  skip, `is_in_group(group_name)`, then `shelved` → skip, then
  `freeze` → skip, then closest-by-`distance_to`. The furniture thread's
  proposed `_nearest_group_storable_distance()` (Edit 3) matches this
  filter chain exactly, term for term — no drift to correct here.
- `_try_use_held_cookpot()` (lines 738–748): confirmed stove-first,
  else-nearest-cookpot_storable priority, matching the rival-distance
  logic proposed for cookpot in Edit 2.
- `NPCItemUser.is_giveable()` and `_find_nearest_npc()`: both exist and
  are already wired into the E-dispatch (lines 191, 517) from the
  earlier Give/Takeaway plans — the prerequisite that plan flagged as
  blocking is now resolved, so Edit 2's NPC branch is safe to add as-is.

No corrections needed to the furniture thread's proposed diffs — this is
a straight adopt, only line numbers below are re-verified against
current file state.

---

## Change 1 — Replace unconditional shelf-first dispatch with distance fairness

**Anchor:** verified current lines 171–176.

```gdscript
old_str:
		## Shelf nearby → E always opens shelf UI (overrides item use)
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			shelf.on_e_interact()
			get_viewport().set_input_as_handled()
			return

new_str:
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
```

When the shelf loses, execution falls through to the existing basket/
cookpot/NPC/held-item branches immediately below (lines 178+), unchanged.

---

## Change 2 — New helper: `_nearest_e_rival_distance()`

**Anchor:** insert directly after `_nearest_shelf()` ends, before the
`_try_add_nearest_to_basket()` doc comment. Verified current lines
701–703.

```gdscript
old_str:
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:

new_str:
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

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

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
```

---

## Change 3 — New helper: `_nearest_group_storable_distance()`

**Anchor:** insert directly below `_nearest_e_rival_distance()` (i.e.
immediately after Change 2's insertion, same location).

```gdscript
## Distance-only twin of the candidate scan in _try_add_nearest_to_basket()
## / _try_add_nearest_to_cookpot(). Filters MUST stay in lockstep with
## those two functions — if a body wouldn't be stashable there, it must
## not count as a rival here. (Verified identical to both as of Aug 2026.)
func _nearest_group_storable_distance(group_name: String) -> float:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body == held_item:
			continue
		if body.is_in_group(group_name):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist
```

---

## Out of scope (confirmed untouched)

- `_nearest_shelf()` itself and its 2.5 m flat-XZ reach.
- `scripts/world/furniture/Shelving.gd` — furniture thread confirms
  shelf-side behavior is correct; no changes needed there.
- F-dispatch shelf behavior (place-held-item / drop onto shelf) — a
  separate code path (verified around line 147), not touched by this
  plan.
- `_try_add_nearest_to_basket()` / `_try_add_nearest_to_cookpot()` — not
  refactored onto the new helper; this fix is additive only.
- CASE 1 / CASE 2 prompt rendering — unchanged. Prompts won't yet reflect
  which target E would actually resolve to when a shelf and a held-item
  target are both in range; that's a follow-up if Brannon wants it, not
  part of this fix.

**Note on distance metric:** `_nearest_shelf()`'s own 2.5 m cutoff stays
flat-XZ (unchanged, per scope above), but the fairness comparison itself
(`shelf_d` in Change 1, and every rival distance in Changes 2–3) uses
full 3D `distance_to()`, matching the furniture thread's explicit
requirement and matching how every rival candidate (basket/cookpot
items, stove, NPC) is already measured elsewhere in this file. On
flat ground this is a non-issue; worth knowing if a shelf is ever placed
at a meaningfully different height than the player in the future.

---

## Verification checklist

1. Hold Basket over a food can, shelf ~2 m away → E stashes the can.
   Shelf closer than every storable → E opens the shelf.
2. Hold Cooking Pot next to a vegetable, shelf slightly farther → E
   stashes; at the shelf → opens it; open stove closer than shelf → pot
   placed on stove.
3. Hold giveable food, NPC (F7) closer than shelf → gives to NPC; shelf
   closer → shelf opens.
4. Unchanged paths: empty-handed near shelf → opens; ordinary held item
   (Fuel Can) near shelf → opens (rival distance is INF, shelf always
   wins); F with held item near shelf → still places onto shelf; shelf
   UI open → input still consumed by UI.
5. A can INSIDE a shelf (`shelved` group), player between it and the
   shelf, holding a Basket → shelved can ignored by both the fairness
   check and the stash itself; E opens the shelf.

---

## Documentation updates (apply alongside the code changes above)

### `docs/systems/player/README.md`

Replace the existing "shelf nearby → E always opens shelf UI" description
(wherever the E-dispatch section currently states this) with:

```markdown
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
```

### `docs/systems/furniture-items/README.md`

Add one line to the Shelving section (this file belongs to the
Furniture/Build-Mode subsystem — flagging for their visibility, not
claiming ownership):

```markdown
- Shelf E-open now yields to a strictly-closer held-item E target
  (Basket stash / Cooking Pot stove-or-stash / NPC give) — see Player
  subsystem's `docs/systems/player/README.md` for the fairness rule.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Shelf E-Hijack Fix (Aug 2026)

## What changed this session
Fixed a bug (reported by Brannon, root-caused by the Furniture/Build-Mode
thread, fix implemented here): holding a Basket and pressing E near both
a food can and a shelf always opened the shelf, even when the can was
closer — the shelf's E-dispatch check ran first and unconditionally, so
it hijacked E from the basket-stash, cookpot, and NPC-give branches
alike. Added `_nearest_e_rival_distance()` (returns the distance to
whatever the held item's own E action would target, or INF if it has
none) and `_nearest_group_storable_distance()` (distance-only twin of the
basket/cookpot candidate scan, filters kept in lockstep). The shelf check
now only wins when strictly closer than the rival distance. Third
instance of the same fairness pattern as the earlier F-dispatch
stove-pot-vs-pickup fix and the ready-dish check.

### Files modified
- `scripts/player/InteractionSystem.gd` — shelf E-dispatch check now
  distance-gated; two new helper functions.
- `docs/systems/player/README.md` — E-dispatch section updated.
- `docs/systems/furniture-items/README.md` — one-line cross-reference
  (Furniture-subsystem-owned file, flagged for their visibility).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_SHELF_E_HIJACK_FIX_PLAN.md` for the
full 5-item checklist)
```
