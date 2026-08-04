# Implementation Plan: Player Contract for NPC Relationship Snatch (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** NPC subsystem contract request
(`PLAYER_SUBSYSTEM_SNATCH_CONTRACT.md`), verified against the current
on-disk state of `scripts/player/Player.gd` and
`scripts/player/InteractionSystem.gd` on 2026-08-04.
**Files touched:** `scripts/player/Player.gd`,
`scripts/player/InteractionSystem.gd`.
**Docs touched:** `docs/systems/player/README.md`, `HANDOVER.md`.

**Feature ownership note:** the Snatch feature itself (when/why an NPC
snatches, relationship math, cooldowns, etc.) is fully NPC-owned and
already implemented on that side — this plan only adds the two-method
public contract the NPC subsystem needs to call on the `Player` node.
Nothing here changes Player-side gameplay behavior on its own.

---

## Verified current state

- `Player.gd` has **no reference** to its `InteractionSystem` child today
  — confirmed by direct read, only `mesh`, `collision`, and
  `interaction_area` are `@onready`-wired.
- `InteractionSystem` is a direct child of `Player`
  (`parent="."` in `Player.tscn`, node name `InteractionSystem`) — so
  `$InteractionSystem` resolves correctly from `Player.gd`.
- `Player.gd` already calls `add_to_group("player")` in `_ready()` (line
  60), so `get_tree().get_first_node_in_group("player")` on the NPC side
  already resolves to this node — no group wiring needed.
- `InteractionSystem.gd` already has the exact cleanup sequence this
  needs, in the just-landed `_try_give_to_nearest_npc()` bugfix (verified
  current lines 855–857): `held_item = null`, `_held_from_slot = -1`,
  `_is_holding_e = false`, with a `knocked_out` disconnect guard just
  above it.
- Unlike the Give-stuck bug, this contract does **not** need the
  `is_instance_valid(item)` branch that `_try_give_to_nearest_npc()`
  uses. Per the NPC subsystem's spec, by the time `on_item_snatched()`
  is called the item has *already* been physically reassigned
  (`item.pickup(npc.hold_point)`, `npc.held_item = item`) regardless of
  item type — so on this side the clear is unconditional every time,
  there's no "did it survive" branch to make.

---

## Change 1 — `InteractionSystem.gd`: add `clear_held_item_external()`

**Anchor:** insert directly after `_try_give_to_nearest_npc()` ends,
before the `_try_pickup_pot_from_stove()` doc comment. Verified current
lines 857–859.

```gdscript
old_str:
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot
## bookkeeping, set_player call) — the only difference is the item comes from
## Stove.try_remove_pot() instead of a detect_area scan.
func _try_pickup_pot_from_stove(stove: Node) -> void:

new_str:
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## External clear — called by Player.on_item_snatched() when an NPC has
## just taken the held item away entirely outside this system's own
## input handling (relationship Snatch feature, NPC-owned). Unlike
## _try_give_to_nearest_npc()'s conditional clear, this is unconditional:
## by the time the caller reaches this, the item has already been
## physically reassigned to the NPC (item.pickup(npc.hold_point),
## npc.held_item = item) regardless of item type, so there's no
## "did it survive" branch to make — it's simply gone from this side.
func clear_held_item_external() -> void:
	if held_item != null and held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot
## bookkeeping, set_player call) — the only difference is the item comes from
## Stove.try_remove_pot() instead of a detect_area scan.
func _try_pickup_pot_from_stove(stove: Node) -> void:
```

---

## Change 2 — `Player.gd`: add `interaction_system` ref + the two contract methods

**Anchor A — node ref, verified current lines 19–21:**

```gdscript
old_str:
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea

new_str:
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_system: Node = $InteractionSystem
```

**Anchor B — public contract methods, verified current lines 121–124
(end of file, right after `_handle_interaction_input()`):**

```gdscript
old_str:
func _handle_interaction_input() -> void:
	if Input.is_action_just_pressed("interact"):
		interacted.emit()

func _unhandled_input(event: InputEvent) -> void:

new_str:
func _handle_interaction_input() -> void:
	if Input.is_action_just_pressed("interact"):
		interacted.emit()

# ─── NPC-facing contract (Relationship Snatch feature, Aug 2026) ──────────────
## Read-only. NPC-side code resolves this node via
## get_tree().get_first_node_in_group("player") and calls these two
## directly, the same way it already does for other player-facing calls.
## Feature logic (when/why a snatch happens) is entirely NPC-owned — this
## side only reports what's held and cleans up bookkeeping after a snatch.

## Returns whatever the player is currently holding, or null if
## empty-handed. Used by NPC-side code purely for detection/classification
## — it does not touch the returned item.
func get_held_item() -> Node:
	return interaction_system.held_item if interaction_system != null else null

## Called by NPC-side code the instant a snatch succeeds — by that point
## the item has already been physically reassigned to the NPC
## (item.pickup(npc.hold_point), npc.held_item = item). This only clears
## this side's own bookkeeping so it doesn't desync, same failure mode as
## the earlier Give-stuck bug.
func on_item_snatched() -> void:
	if interaction_system != null and interaction_system.has_method("clear_held_item_external"):
		interaction_system.clear_held_item_external()

func _unhandled_input(event: InputEvent) -> void:
```

---

## Verification checklist

1. Set up a bad relationship via F7 admin tools between an NPC and the
   player, hold a matching food/water item, let the NPC search for a
   need — confirm (via a temporary print or the NPC's own debug tooling)
   `player.get_held_item()` correctly returns the held item.
2. After a snatch succeeds — confirm the player's hand is empty
   afterward: item is droppable/storable/usable-state correctly cleared,
   nothing stuck, exactly like after a normal successful Give of a
   multi-charge item post-bugfix.
3. Confirm normal Give (E near an NPC) and Takeaway (F on an NPC-held
   item) still work exactly as before — this plan only adds new methods,
   doesn't touch either existing code path.
4. Confirm `get_held_item()` returns `null` when empty-handed (baseline
   sanity check before testing snatch detection itself).

---

## Documentation updates (apply alongside the code changes above)

### `docs/systems/player/README.md`

Add a new Common-edits entry, directly after the existing "NPC
Give/Takeaway support (Aug 2026)" entry and its bugfix follow-up:

```markdown
- **NPC-facing contract for Relationship Snatch (Aug 2026):** `Player.gd`
  now exposes `get_held_item() -> Node` (read-only passthrough to
  `InteractionSystem.held_item`) and `on_item_snatched() -> void` for the
  NPC subsystem's Snatch feature (bad-relationship NPCs occasionally take
  a food/water item straight from the player's hands). NPC-side code
  resolves the player via `get_tree().get_first_node_in_group("player")`
  and calls these directly — no group/signal wiring needed since
  `Player.gd` already registers into the `"player"` group.
  `on_item_snatched()` delegates to a new
  `InteractionSystem.clear_held_item_external()`, which does the same
  `held_item`/`_held_from_slot`/`_is_holding_e` cleanup (with
  `knocked_out` disconnect guard) as a successful Give — unconditionally
  here, since by the time this is called the item has always already
  been physically reassigned to the NPC regardless of item type. Snatch
  trigger logic, relationship math, and cooldowns are entirely NPC-owned;
  this file only reports state and cleans up after the fact.
```

### `HANDOVER.md`

Add a new entry at the top of the file:

```markdown
# Handover — Player Contract for NPC Relationship Snatch (Aug 2026)

## What changed this session
Added the two-method public contract the NPC subsystem needs for its
Relationship Snatch feature (bad-relationship NPCs occasionally take a
food/water item straight from the player's hands): `Player.get_held_item()`
and `Player.on_item_snatched()`. `Player.gd` gained an `interaction_system`
node ref (`$InteractionSystem`); `InteractionSystem.gd` gained
`clear_held_item_external()`, an unconditional version of the cleanup
`_try_give_to_nearest_npc()` already does on a successful give (item is
guaranteed already gone from this side by the time Snatch calls it,
unlike Give where multi-charge items can survive in hand). No existing
Give/Takeaway behavior changed.

### Files modified
- `scripts/player/Player.gd` — `interaction_system` ref,
  `get_held_item()`, `on_item_snatched()`.
- `scripts/player/InteractionSystem.gd` — `clear_held_item_external()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_SNATCH_CONTRACT_PLAN.md` for the full
4-item checklist)
```
