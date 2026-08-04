# One Shared Transfer Function for Give AND Snatch (Aug 2026)

This replaces the separate patchwork (inventory-slot clearing, HUD
prompt staleness, the standalone `snatch_from_player()`) with a single
function that does what `_quick_drop()` already correctly does — the
only difference is the destination is an NPC's hands instead of the
floor. Both Give and Snatch now call the exact same function. This touches
both `scripts/player/InteractionSystem.gd`/`scripts/player/Player.gd`
(Player subsystem) and `scripts/npc/NPC.gd`/`scripts/npc/NPCItemUser.gd`
(NPC subsystem) — listed together here as one plan, since they're one
mechanism now.

## Why the prompt/inventory bug kept surviving small patches

`_update_prompt()` runs every frame and reactively rebuilds the held-item
prompt off `held_item` — it even has an existing self-healing guard for
`held_item` pointing at a freed object. But that guard only catches the
item being *destroyed*; it does nothing when the item is still alive,
just reassigned to someone else, which is exactly what Give/Snatch do.
There's no shortcut around explicitly clearing `held_item` (and the
inventory slot, and the HUD selection) at the moment of transfer — but
that's also exactly what `_quick_drop()` already does correctly for the
normal drop case. So: stop re-deriving a smaller version of that
cleanup by hand, just reuse it with a different destination.

---

## 1. `scripts/player/InteractionSystem.gd` — the one shared function

Add this function (structure mirrors `_quick_drop()` line for line,
destination changed from the floor to an NPC's hand):

```gdscript
## Give/Snatch transfer — the one correct way to move the held item into
## an NPC's hands, for any reason other than a normal world-drop.
## Deliberately mirrors _quick_drop(): disconnect knocked_out, clear the
## inventory slot via remove_item() if the item came from one (this is
## what actually empties the inventory list — deactivate_item() does
## NOT, it's for knockouts, which intentionally keep the item in
## inventory), clear held_item/_held_from_slot/_is_holding_e, refresh the
## HUD selection. The only difference from a real drop: item.pickup(npc.
## hold_point) instead of item.drop(world, floor_position).
func release_held_item_to_npc(npc: Node) -> bool:
	if held_item == null:
		return false
	if npc == null or not is_instance_valid(npc):
		return false
	if not ("hold_point" in npc) or not ("held_item" in npc):
		return false

	_is_holding_e = false
	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	if _held_from_slot != -1 and inventory != null:
		inventory.remove_item(_held_from_slot, held_item.global_position)

	var item: RigidBody3D = held_item
	held_item       = null
	_held_from_slot = -1
	_update_hud_selection()

	item.pickup(npc.hold_point)
	npc.held_item = item
	return true
```

**Anchor:** replace the entire body of `_try_give_to_nearest_npc()` with:

```gdscript
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("can_receive_item") or not target.can_receive_item(item):
		return
	if not release_held_item_to_npc(target):
		return
	if target.has_method("on_item_given"):
		target.on_item_given(item)
```

(This replaces whatever `_try_give_to_nearest_npc()` currently does —
the item transfer itself is now entirely handled by
`release_held_item_to_npc()` above, not duplicated here.)

---

## 2. `scripts/player/Player.gd`

Ensure these exist (add/update as needed — the group `"player"` node is
what NPC-side code looks up, so these need to be reachable from here,
not just from `InteractionSystem.gd`):

```gdscript
@onready var interaction_system: Node = $InteractionSystem   ## adjust path if your actual scene structure differs

## Read-only peek at what the player is holding — used by NPCs deciding
## whether/what to snatch.
func get_held_item() -> Node:
	return interaction_system.held_item if interaction_system != null else null

## Forwards to InteractionSystem.release_held_item_to_npc() — NPC-side
## code only has this Player node (via the "player" group), never
## InteractionSystem directly, so this is the reachable entry point for
## Snatch to use the exact same transfer path Give uses.
func release_held_item_to_npc(npc: Node) -> bool:
	return interaction_system.release_held_item_to_npc(npc) if interaction_system != null else false
```

---

## 3. `scripts/npc/NPC.gd` — split into a pure check + consequence wiring

**Anchor:** replace the entire `receive_item_from_player()` function
with these two functions:

```gdscript
## Pure check, no side effects — called by InteractionSystem BEFORE it
## attempts the physical transfer, for Give.
func can_receive_item(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if held_item != null:
		return false   ## hands full
	return NPCItemUser.is_giveable(item)

## Called AFTER the item has already been physically transferred into
## held_item (by InteractionSystem.release_held_item_to_npc(), via
## Give's _try_give_to_nearest_npc()) — wires up the consumption activity
## and relationship/burnout bookkeeping. Does NOT touch held_item/pickup
## itself anymore; that's entirely the Player side's job now, since it's
## the only side with the inventory-slot context needed to clear it
## correctly.
func on_item_given(item: Node) -> void:
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
	activity.begin_with_item(self, item)

	if already_boosted:
		if NPCDebug.enabled:
			NPCDebug.log_relationship_event(self, "player", 0.0,
				"re-gift, already boosted by this item — fed only, no bonus")
		return

	var effective_bonus: float = GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)
	_adjust_relationship("player", effective_bonus)
	gift_saturation = minf(GIFT_SATURATION_MAX, gift_saturation + GIFT_SATURATION_PER_GIFT)
	if NPCDebug.enabled:
		NPCDebug.log_relationship_event(self, "player", effective_bonus,
			"received gift (saturation %.2f)" % gift_saturation)
```

Note the sequencing is still safe here even though the physical transfer
now happens BEFORE `on_item_given()` runs (previously it was
force_command-then-transfer, now it's transfer-then-force_command): the
`held_item != null` guard in `can_receive_item()` is checked first and
nothing can change `held_item` between that check and `on_item_given()`
running — this is all synchronous, no frame passes in between, so the
outgoing activity's `exit()` (inside `force_command()`) still can't
mistake the just-given item for something it already had.

---

## 4. `scripts/npc/NPCItemUser.gd` — `snatch_from_player()` now routes through the same shared transfer

**Anchor:** replace the entire `snatch_from_player()` function with:

```gdscript
## Snatch now goes through the exact same transfer path Give uses
## (Player.release_held_item_to_npc(), which wraps InteractionSystem's
## release_held_item_to_npc()) — no more separate pickup/inventory logic
## duplicated here. This is deliberately still a SEPARATE function from
## grab_loose() (whose is_held guard should stay strict) — this is the
## one intentional exception, reached only via SnatchActivity, itself
## only ever entered through NPC.find_player_snatch_target()'s gate (or
## the F7 debug override).
static func snatch_from_player(npc: NPC, player: Node) -> bool:
	if npc.held_item != null:
		return false   ## hands already full
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var item: Node = player.get_held_item()
	if item == null or not is_instance_valid(item):
		return false
	if flat_distance(npc.global_position, (player as Node3D).global_position) > PICKUP_RANGE:
		return false
	if not player.has_method("release_held_item_to_npc"):
		return false
	return player.release_held_item_to_npc(npc)
```

`SnatchActivity` in `NPCBrain.gd` doesn't need any changes — it already
just calls `NPCItemUser.snatch_from_player(npc, _player)` and checks the
boolean result; the fact that the internals now route through the shared
transfer function instead of doing it locally is invisible to the caller.

---

## If "the NPC bumps into the player and the item just drops" still happens after this

That specific symptom (item ends up on the floor rather than in the
NPC's hands) doesn't match anything in the new shared path — it sounds
like the pre-existing, unrelated knockout system: an item gets knocked
out of the player's hand automatically if it's ever displaced more than
`KNOCK_DISTANCE` from the hold point (see `PickupableItem._physics_process()`).
If the NPC's own collision body physically shoves into the player while
approaching (rather than stopping cleanly at `PICKUP_RANGE`), that could
jostle the held item hard enough to trigger a knockout — a completely
separate mechanic from Snatch, just accidentally triggered by the
approach. If this keeps happening after the fix above, it's worth
checking whether the NPC's navigation is actually stopping at
`PICKUP_RANGE` (1.2m) before attempting the grab, or overshooting into
the player's actual collision body first — but that's a distinct issue
from what this plan fixes, not something to chase blindly right now.

---

## Documentation

Update the Give and Relationship Snatch sections in
`docs/systems/npc/README.md` to describe the single shared
`release_held_item_to_npc()` transfer path, and that `NPC.
receive_item_from_player()` no longer exists — replaced by
`can_receive_item()` (check) + `on_item_given()` (consequence wiring).
Add a Testing Checklist item: give an item, immediately check the HUD —
no lingering eat/drop prompt, scrolling the inventory does not
re-populate the now-empty slot. Add `HANDOVER.md` entry summarizing the
unification.

## Summary of files touched

| File | Change |
|---|---|
| `scripts/player/InteractionSystem.gd` | New `release_held_item_to_npc()`; `_try_give_to_nearest_npc()` simplified to use it |
| `scripts/player/Player.gd` | `get_held_item()`, `release_held_item_to_npc()` forwarding |
| `scripts/npc/NPC.gd` | `receive_item_from_player()` replaced by `can_receive_item()` + `on_item_given()` |
| `scripts/npc/NPCItemUser.gd` | `snatch_from_player()` simplified to route through the shared transfer |
| `docs/systems/npc/README.md`, `HANDOVER.md` | Updated accordingly |
