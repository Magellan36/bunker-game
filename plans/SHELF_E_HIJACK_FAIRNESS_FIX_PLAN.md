# Fix Plan — Shelving Hijacks E From Closer Targets (Basket Stash etc.)

## Root Cause

In `scripts/player/InteractionSystem.gd`, the E dispatch (`event.is_action_pressed("interact")`, lines ~168–176) checks the shelf **first and unconditionally**:

```gdscript
	## Shelf nearby → E always opens shelf UI (overrides item use)
	var shelf: Node3D = _nearest_shelf()
	if shelf != null and shelf.has_method("on_e_interact"):
		shelf.on_e_interact()
		get_viewport().set_input_as_handled()
		return
```

`_nearest_shelf()` has a generous 2.5 m flat-XZ reach. So while holding a Basket and standing over a food can, any shelf within 2.5 m steals E and opens its UI before the basket-stash branch is ever reached. The same hijack applies to the held-Cooking-Pot branch and the give-to-NPC branch, which all sit below the shelf check.

This is the **third instance of an already-recognized bug class** in this file — two prior "distance fairness" fixes exist with comments: F-pickup ("previously the stove-pot case always won regardless of distance, so a pot across the room could beat a vegetable at the player's feet") and the ready-dish check ("takes priority ONLY if it's truly the closest one"). The shelf branch predates that pattern and was never converted. This plan converts it, using the exact same house style.

## Fix — Distance-Fair Shelf Priority

**File:** `scripts/player/InteractionSystem.gd` (all edits in this one file)

### Edit 1 — Replace the shelf-first block in the E dispatch

Replace the 7-line block quoted above (comment included) with:

```gdscript
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

Notes for the agent:
- The comparison uses full 3D `distance_to` on BOTH sides (shelf and rivals), matching the two existing fairness fixes. `_nearest_shelf()` itself is **unchanged** — its flat-XZ 2.5 m gate remains the "is a shelf in range at all" test.
- Everything below this block in the E dispatch is **unchanged**. When the shelf loses, execution simply falls through to the existing basket/cookpot/NPC/held-item branches.

### Edit 2 — New helper `_nearest_e_rival_distance()`

Add directly **below** `_nearest_shelf()` (after line ~701):

```gdscript
## Distance to the nearest competing E target for the CURRENTLY HELD item —
## used only by the E-dispatch shelf fairness check. Returns INF when the
## held item has no E action of its own (or nothing is held), which makes
## the shelf win by default, preserving pre-fix behavior for those cases.
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
```

### Edit 3 — New helper `_nearest_group_storable_distance()`

Add directly below Edit 2's function. This is the distance-only twin of the identical scan loops inside `_try_add_nearest_to_basket()` / `_try_add_nearest_to_cookpot()` — same DetectArea source, same three filters (held item itself, `shelved`, frozen), so the fairness check can never disagree with what the stash would actually pick:

```gdscript
## Distance-only twin of the candidate scan in _try_add_nearest_to_basket()
## / _try_add_nearest_to_cookpot(). Filters MUST stay in lockstep with
## those two functions — if a body wouldn't be stashable there, it must
## not count as a rival here.
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

### Explicitly out of scope
- Do NOT change `_nearest_shelf()`, its 2.5 m reach, or `Shelving.gd`'s groups/collision — the shelf's reach is correct; only its unconditional priority was wrong.
- Do NOT refactor `_try_add_nearest_to_basket()` / `_try_add_nearest_to_cookpot()` to call the new helper — keep this change additive and surgical.
- Do NOT touch the F-dispatch (`pickup`) shelf branch. F's "place held item on shelf, else drop" priority is intended behavior.
- Prompt/label text and CASE 1/CASE 2 prompt rendering: unchanged. (If the on-screen prompt should also reflect which target would win, that's a follow-up — flag it, don't build it.)

## Coordination Note
`InteractionSystem.gd` is owned by the Player-systems plan-writer thread. This change is confined to E-dispatch target selection where Shelving (furniture scope) intersects it, follows the file's own established fairness pattern, and adds two self-contained helpers. Note it in the commit message so the Player thread's context stays accurate: **"InteractionSystem E dispatch: shelf priority is now distance-fair vs held-item E targets (basket/cookpot/NPC-give); two new helpers `_nearest_e_rival_distance`, `_nearest_group_storable_distance`."**

## Documentation Updates (required, same commit)
1. **`docs/systems/player/README.md`** — interaction/E-dispatch section: update the shelf rule from "shelf nearby → E always opens shelf UI" to the distance-fair rule, and list the three fairness fixes (stove-pot F, ready-dish, shelf) together as the standing pattern for any future E/F priority additions.
2. **`docs/systems/furniture-items/README.md`** — Shelving section: update the E-interaction line to note shelf opening yields to a strictly-closer held-item target (basket stash, cookpot, NPC give).
3. **`HANDOVER.md`** — new entry: "Shelf E-Hijack Fix (Aug 2026)" — symptom (shelf within 2.5 m stole E from basket stash of an adjacent item), root cause (unconditional shelf-first dispatch predating the distance-fairness pattern), fix summary, files touched.

## Verification Checklist (Brannon, in-editor)
1. **Reported repro fixed:** Hold Basket, stand over a food can with a shelf ~2 m away → E stashes the can. Move so the shelf is closer than any storable → E opens the shelf.
2. **Cookpot:** Hold Cooking Pot next to a vegetable with a shelf slightly farther → E stashes the vegetable; walk right up to the shelf → E opens it. With an open stove closer than the shelf → E places the pot on the stove.
3. **NPC give:** Hold a giveable food item with an NPC (F7 spawn) closer than a shelf → E gives to the NPC; shelf closer → shelf opens.
4. **Unchanged paths:** Empty-handed near a shelf → E opens shelf as before. Holding an ordinary item (e.g. Fuel Can) near a shelf → E still opens shelf (rival = INF). F near a shelf while holding an item → still places onto the shelf. Shelf UI open → E/F still consumed by UI.
5. **No stale-candidate disagreement:** Put a can INSIDE a shelf (`shelved` group), stand between it and the shelf holding a basket → shelved can is ignored by both the fairness check and the stash; E opens the shelf.
