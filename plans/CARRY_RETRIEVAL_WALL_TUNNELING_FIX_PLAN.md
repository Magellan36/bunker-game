# Fix Plan — Storage "Carry" Retrieval Can Fall Through the World Near Walls

## Root Cause (confirmed against current source, both storage types)

**Neither `Shelving.retrieve_to_carry()` nor `LightStorage.take_for_carry()` repositions the item onto the player's side before handing it off.** `PickupableItem.pickup()` (`PickupableItem.gd:210-227`) never moves the item — it just flips `is_held = true`, sets `freeze_mode = KINEMATIC`, `gravity_scale = 0`, `collision_layer/mask = 2/1`, and hands off to `_physics_process()`, which drives the item toward the hold point via **raw velocity**: `linear_velocity = (chase_target - global_position) * speed` (`PickupableItem.gd:154`). That's a real physics body pushed at high force through anything on layer 1 (world/walls) between its start point and the player.

- **Shelving:** `retrieve_to_carry()` calls `item.pickup(isys.hold_point)` (`Shelving.gd:642`) while the item's `global_position` is **still wherever it was left inside the shelf's slot marker** — for a shelf backed against a wall, that's routinely on the far/wall side of the unit relative to the player. The very next physics frame slams the item through the shelf's own collision (and possibly the wall behind it) at whatever velocity `(target - start) * speed` works out to for that distance — the exact mechanism for tunneling through thin/adjacent colliders and, per the report, sometimes clean through the floor.
- **LightStorage (End Table / Dresser):** `take_for_carry()` DOES reposition the item via `_reparent_to_world()` (`LightStorage.gd:214-221`) — but to `global_position + Vector3(0, 0.6, 0)`, i.e. **the furniture's own center**, not the player's position. That's an improvement over Shelving's "leave it wherever" but still not guaranteed clear of the wall the furniture is pushed against, and doesn't depend on where the player is actually standing.

**Basket is out of scope** — its primary button is "Drop" (`Basket.gd get_ui_config()`), not "Carry"; `take_for_carry()` places the item near the basket rather than handing it directly into the player's grip, a different code path than the one reported.

## Fix — Spawn on the Player, Let the Existing Follow System Do the Rest

Exactly the approach suggested: reposition the item onto the player before `pickup()` runs, then let `PickupableItem._physics_process()`'s existing per-frame velocity-chase — which is already built to smoothly close ANY start-to-hold-point gap — carry it the last short distance into the hold position. No new motion system needed; this reuses what's already there, just starting it from a safe point instead of an unsafe one.

**Why "at the player's own origin" is the safe choice, not just "near" it:** the player's own position is, by construction, never inside solid geometry (their own collision volume occupies it) — so there is categorically no shelf, furniture, or wall for the item to tunnel through starting from there, regardless of which direction the storage unit is facing or how it's positioned against a wall. The remaining travel to the actual hold point (typically well under 1 m — `hold_point.position = Vector3(0, 0.8, -1.0)`, `InteractionSystem.gd:62`) is short enough that the existing chase system closes it in a few frames, giving the small "pop then settle into hand" feel without any collision risk.

### Edit 1 — `scripts/world/furniture/Shelving.gd`

Add a small reusable static helper (near the top of the file, in the Interaction section, ~line 20):
```gdscript
## Aug 2026 — safe spawn point for any item about to be handed to the player
## via pickup(). The player's own position is guaranteed clear of solid
## world geometry (their own collision volume occupies it), so starting a
## carried item here — rather than at its old storage-slot position, which
## can be behind a shelf/furniture unit pressed against a wall — eliminates
## the tunnel-through-wall/floor bug entirely. The short remaining distance
## to the real hold point is closed by PickupableItem._physics_process()'s
## existing per-frame chase, so this still gets a small natural "pop into
## hand" motion instead of an instant teleport onto the hold point itself.
## Shared by Shelving.retrieve_to_carry() and LightStorage.take_for_carry().
static func carry_spawn_position(isys: Node) -> Vector3:
	const SPAWN_HEIGHT: float = 1.0   ## Roughly chest height on the player
	return isys.global_position + Vector3(0.0, SPAWN_HEIGHT, 0.0)
```

In `retrieve_to_carry()` (~line 638-642), directly before the `pickup()` call, add one line:
```gdscript
	if "from_inventory" in item:
		item.from_inventory = false

	item.global_position = Shelving.carry_spawn_position(isys)   ## Aug 2026 fix — was left at the shelf slot, could tunnel through a wall on the way to the player

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)
```

### Edit 2 — `scripts/world/furniture/LightStorage.gd`

In `take_for_carry()` (~line 251-274), the item currently gets its position set by `_reparent_to_world(item)` (furniture-center-based). Override it with the same safe player-side point directly before `pickup()`:
```gdscript
	if "from_inventory" in item:
		item.from_inventory = false

	## Aug 2026 fix — _reparent_to_world() above positions the item at the
	## FURNITURE's own center, which can still be near/behind a wall the
	## unit is pushed against. Override with the same player-side safe spot
	## Shelving uses right before handing off to pickup().
	item.global_position = Shelving.carry_spawn_position(isys)

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)
```
(`_reparent_to_world()` itself is untouched — `take_for_inventory()` still uses its furniture-center placement, which is fine there since that path doesn't send the item flying toward the player via physics.)

## Out of scope
- `_reparent_to_world()`'s positioning for the inventory-retrieval path — not implicated in this bug (item goes straight into pocket inventory, no physics chase).
- Basket's `take_for_carry()` / "Drop" behavior — different action, different code path, not the reported symptom.
- `PickupableItem._physics_process()` itself — the chase logic is correct and reused as-is; only the starting position was wrong.

## Documentation Updates (same commit)
1. `docs/systems/furniture-items/README.md` — Shelf family + Light Storage sections: note the carry-retrieval safe-spawn fix and why (players are never inside solid geometry, storage units next to walls can be).
2. `HANDOVER.md` — entry: "Storage Carry-Retrieval Wall Tunneling Fix — Aug 2026": symptom (items falling out of the world when retrieved from wall-adjacent storage), root cause (item's `global_position` never repositioned before `pickup()`'s physics-driven chase begins), fix (shared `Shelving.carry_spawn_position()` static helper, called from both Shelving and LightStorage before `pickup()`).

## Verification Checklist (Brannon, in-editor)
1. **Reported repro:** place a Medium Shelf flush against a wall, store an item in a back/wall-side slot, retrieve via Carry — item appears near the player and settles into hand normally; no clipping through the wall, no falling out of the world.
2. **Repeat on End Table/Dresser** pushed flush against a wall — same result.
3. **Repeat on Large Shelf** with an item in a far-column slot, and on a shelf in a tight corner (two walls) — worst-case geometry.
4. **Normal case unaffected:** retrieve from a shelf out in the open, away from any wall — still feels like a natural pickup, no jarring teleport-to-hand snap (confirm the brief pop-then-settle motion still reads fine).
5. **No regression:** stacked items (Can Case 2-stack), TestCrate, and inventory-retrieval (⊕ button) all unaffected — only the Carry path changed.
