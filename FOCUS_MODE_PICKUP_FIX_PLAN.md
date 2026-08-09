# Follow-up Plan — Focus Mode: Include Pickup-Only Objects (Test Crate, Fuel Can, etc.)

## Root cause
Confirmed by inspecting both objects directly:
- **Fuel Can**: in the `"interactable"` group, but has no `on_interact()`
  (only `on_use()`, for while it's held) — the old
  `_resolve_current_e_target()` correctly never picked it, since E
  genuinely does nothing to it while it's on the ground.
- **Test Crate** (via `PickupableItem`): only in the `"pickup"` group, not
  `"interactable"` at all — the old resolver never even looked at that
  group.

Both already show up fine in the normal (Ctrl-released) prompt list —
this was purely a Focus Mode gap. The original design question was "what
would E do," which is the wrong question for objects E can't act on at
all; the fix broadens Focus Mode's definition to "what's the closest
object with any prompt (E or F)."

## What changed
Replaced `InteractionSystem._resolve_current_e_target()` (now deleted —
fully dead after this change, nothing else called it) with logic that
tags the focus target directly off `_update_prompt()`'s CASE-2
`candidates` list, which already includes pickups, interactables, and
shelving together, pre-sorted closest-first. The focus target is just
the first entry that actually produces a displayable prompt — with the
grow-light-over-tray override (from the previous session) still applied
on top, since raw distance sorting doesn't know about that deliberate
exception.

Renamed the tag `is_e_target` → `is_focus_target` throughout (both
files) since it's no longer specifically about E — a stale name would
have been misleading for the next person reading either file.

## Files modified
- `scripts/player/InteractionSystem.gd` — tagging logic replaced,
  `_resolve_current_e_target()` removed, 3 stale cross-reference
  comments updated.
- `scripts/ui/hud/InteractPrompt.gd` — key renamed, doc comments updated
  to describe the broadened definition.

---

## Part 1 — `scripts/player/InteractionSystem.gd`: retag the focus target

**old_str:**
```
	## Aug 2026 — Focus Mode support. Resolved once per frame, tagged onto
	## whichever entry below actually matches — see
	## _resolve_current_e_target()'s header for why this can never drift
	## from what E actually does.
	var e_target: Node3D = _resolve_current_e_target()

	var entries: Array = []
	for cand: Dictionary in candidates:
```
**new_str:**
```
	var entries: Array = []
	var entry_bodies: Array = []   ## Parallel to entries[] — Focus Mode below
	for cand: Dictionary in candidates:
```

**old_str:**
```
		entries.append({
			"text":         "\n".join(lines),
			"world_pos":    prompt_pos,
			"dist":         cand["dist"],
			"icons":        icons,
			"is_e_target":  body == e_target,
		})

	if entries.is_empty():
```
**new_str:**
```
		entries.append({
			"text":      "\n".join(lines),
			"world_pos": prompt_pos,
			"dist":      cand["dist"],
			"icons":     icons,
		})
		entry_bodies.append(body)

	## Aug 2026 v2 — Focus Mode, broadened. Previously only tagged whatever
	## E would fire on (_resolve_current_e_target(), now removed), which
	## meant pickup-only objects with no on_interact() at all — Test
	## Crate ("pickup" group only), Fuel Can ("interactable" group but no
	## on_interact(), only on_use() for while held) — never got a Focus
	## Mode prompt even though F still works on them and they show fine
	## normally. Focus target is now simply the CLOSEST entry with an
	## actual displayable prompt: entries[] is already built in
	## candidates' closest-first order, so that's just index 0 — with the
	## grow-light-over-tray override still applied on top, since raw
	## distance sorting doesn't know about that deliberate exception.
	var focus_idx: int = -1
	if not entries.is_empty():
		focus_idx = 0
		if entry_bodies[0].is_in_group("farming_tray"):
			for i: int in entry_bodies.size():
				if entry_bodies[i].is_in_group("grow_light"):
					focus_idx = i
					break
	for i: int in entries.size():
		entries[i]["is_focus_target"] = (i == focus_idx)

	if entries.is_empty():
```

## Part 2 — Remove the now-dead `_resolve_current_e_target()`

**old_str:**
```
## Distance-only twin of _nearest_shelf() — same flat-XZ metric (reach
## along the shelf's whole vertical face, not full 3D distance to its
## origin — see the header comment above). Used by the E-handler's
## shelf-fairness check and Focus Mode's _resolve_current_e_target().
## Returns INF if no shelf is in range.
func _nearest_shelf_distance() -> float:
	var shelf: Node3D = _nearest_shelf()
	if shelf == null:
		return INF
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var shelf_xz: Vector2  = Vector2(shelf.global_position.x, shelf.global_position.z)
	return shelf_xz.distance_to(player_xz)

## Resolves exactly which object E would trigger right now, empty-handed
## — the single source of truth for the UI thread's Focus Mode prompt
## tagging. Pure read-only peek, mirrors the empty-handed branch of
## _unhandled_input()'s "interact" handler exactly (shelf fairness check,
## then ready-dish fairness check, then the generic candidate). MUST be
## kept in sync with that branch if its priority order ever changes —
## kept as a light, clearly-cross-referenced duplication rather than a
## restructure of the input-handling hot path itself, same philosophy
## InteractionProximityScan.gd's header already uses for _nearest_shelf().
## Not valid while holding an item — CASE 1 in InteractPrompt.gd doesn't
## call this and isn't filtered by Focus Mode this pass. Returns null if
## nothing qualifies.
func _resolve_current_e_target() -> Node3D:
	var shelf: Node3D = _nearest_shelf()
	if shelf != null and shelf.has_method("on_e_interact"):
		var shelf_dist: float = _nearest_shelf_distance()
		var other: Dictionary = _nearest_generic_interactable()
		if shelf_dist <= float(other["dist"]):
			return shelf

	var ready_pot: Node = _find_nearest_ready_pot()
	if ready_pot != null:
		var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
		if pot_dist <= _nearest_interact_distance():
			return ready_pot as Node3D

	var other2: Dictionary = _nearest_generic_interactable()
	return other2["node"] as Node3D

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
```
**new_str:**
```
## Distance-only twin of _nearest_shelf() — same flat-XZ metric (reach
## along the shelf's whole vertical face, not full 3D distance to its
## origin — see the header comment above). Used by the E-handler's
## shelf-fairness check below.
## Returns INF if no shelf is in range.
func _nearest_shelf_distance() -> float:
	var shelf: Node3D = _nearest_shelf()
	if shelf == null:
		return INF
	var player_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var shelf_xz: Vector2  = Vector2(shelf.global_position.x, shelf.global_position.z)
	return shelf_xz.distance_to(player_xz)

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
```

## Part 3 — Two stale comment cross-references

**old_str:**
```
## with, without triggering it — the ONE shared scan used by
## _try_interact() itself, _nearest_interact_distance() (kept as a thin
## distance-only wrapper below, several callers only need the number),
## the shelf E-priority fairness check, and Focus Mode's
## _resolve_current_e_target(). Returns { "node": Node3D or null, "dist":
## float (INF if nothing eligible) }.
```
**new_str:**
```
## with, without triggering it — the ONE shared scan used by
## _try_interact() itself, _nearest_interact_distance() (kept as a thin
## distance-only wrapper below, several callers only need the number),
## and the shelf E-priority fairness check below. Returns { "node":
## Node3D or null, "dist": float (INF if nothing eligible) }.
```

**old_str:**
```
	## Aug 2026 — scan itself moved into _nearest_generic_interactable()
	## (shared with _nearest_interact_distance(), the shelf E-priority
	## fairness check, and Focus Mode's _resolve_current_e_target()) so
	## "what would fire" and "what actually fires" can never disagree.
```
**new_str:**
```
	## Aug 2026 — scan itself moved into _nearest_generic_interactable()
	## (shared with _nearest_interact_distance() and the shelf E-priority
	## fairness check) so "what would fire" and "what actually fires" can
	## never disagree.
```

---

## Part 4 — `scripts/ui/hud/InteractPrompt.gd`: rename the tag it reads

**old_str:**
```
	## Focus Mode (Aug 2026) — hold Ctrl to collapse every prompt down to
	## the single one E would actually trigger right now. Debugging aid
	## for prompt-priority bugs as well as a normal player-facing
	## decluttering option when several prompts compete for attention. A
	## HOLD, not a toggle — release Ctrl and everything returns to normal
	## immediately, no state to reset.
	##
	## Resolution is entirely Player-owned: InteractionSystem tags exactly
	## one CASE-2 (empty-handed) entry per frame with "is_e_target": true,
	## every other CASE-2 entry gets "is_e_target": false — see
	## InteractionSystem._resolve_current_e_target()'s header for why that
	## tag can never disagree with what E actually does. This file only
	## reads the tag, it never re-derives priority itself.
	##
	## Entries that never set the key at all (every CASE-1 held-item
	## entry — basket/cookpot/give-to-NPC/held-item's-own-action) default
	## to shown via the `true` fallback below: Focus Mode intentionally
	## has no effect while holding an item this pass (see this plan's
	## header for why).
	var focus_mode: bool = Input.is_key_pressed(KEY_CTRL)
	var display_list: Array = _active
	if focus_mode:
		display_list = _active.filter(func(e: Dictionary) -> bool: return bool(e.get("is_e_target", true)))
```
**new_str:**
```
	## Focus Mode (Aug 2026, broadened) — hold Ctrl to collapse every
	## prompt down to the single closest one, hiding the rest. Debugging
	## aid for prompt-priority bugs as well as a normal player-facing
	## decluttering option when several prompts compete for attention. A
	## HOLD, not a toggle — release Ctrl and everything returns to normal
	## immediately, no state to reset.
	##
	## Resolution is entirely Player-owned: InteractionSystem tags exactly
	## one CASE-2 (empty-handed) entry per frame with "is_focus_target":
	## true, every other CASE-2 entry gets "is_focus_target": false. This
	## file only reads the tag, it never re-derives priority itself.
	## v2 — originally tagged only whatever E would fire on, which meant
	## pickup-only objects (Test Crate, Fuel Can, etc. — no on_interact())
	## never got a Focus Mode prompt at all even though they show fine
	## normally; now it's simply the closest object with any prompt
	## (E or F), with the grow-light-over-tray override still applied.
	##
	## Entries that never set the key at all (every CASE-1 held-item
	## entry — basket/cookpot/give-to-NPC/held-item's-own-action) default
	## to shown via the `true` fallback below: Focus Mode intentionally
	## has no effect while holding an item this pass.
	var focus_mode: bool = Input.is_key_pressed(KEY_CTRL)
	var display_list: Array = _active
	if focus_mode:
		display_list = _active.filter(func(e: Dictionary) -> bool: return bool(e.get("is_focus_target", true)))
```

**old_str:**
```
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null), "is_e_target": bool (optional, Aug 2026 — Focus Mode: true
## for the one entry E would actually trigger right now, false for other
## empty-handed candidates, omitted entirely for held-item entries that
## haven't opted into Focus Mode filtering yet — a missing key defaults
## to shown) }. Pass [] to hide all panels.
```
**new_str:**
```
## "icons": Array (optional, up to 3 entries, each a descriptor Dictionary
## or null), "is_focus_target": bool (optional, Aug 2026 — Focus Mode:
## true for the single closest empty-handed candidate with any prompt
## (E or F), false for other empty-handed candidates, omitted entirely
## for held-item entries that haven't opted into Focus Mode filtering
## yet — a missing key defaults to shown) }. Pass [] to hide all panels.
```

## Verification checklist
1. Stand near a Fuel Can on the ground (not held), nothing else nearby —
   hold `Ctrl`: confirm its `[F] Pick up`-style prompt now stays visible.
2. Same for a Test Crate.
3. Stand near a Fuel Can AND a genuinely closer other interactable — hold
   `Ctrl`: confirm the closer one wins, Fuel Can's prompt disappears
   (still "closest wins," just now pickup-inclusive).
4. Re-run the previous session's full checklist (shelf-vs-closer-object,
   grow-light-vs-tray) to confirm no regression from the tagging rewrite.
5. Holding an item near any of the above (CASE 1) — confirm still
   unaffected by Focus Mode, as before.

## Documentation updates
`docs/systems/ui/README.md`'s "Focus Mode" section (added last session)
needs a quick correction pass — it currently describes the old
E-only/`_resolve_current_e_target()` design. Replace with:

**Find the "Focus Mode (Aug 2026)" section and replace its body with:**
```markdown
## Focus Mode (Aug 2026, broadened same session)
Hold `Ctrl` to collapse every active interaction prompt down to the
single CLOSEST one, hiding the rest — a hold, not a toggle. Built as a
debugging aid for prompt-priority bugs (the shelf-unconditional-priority
bug and the grow-light-vs-tray issue were both diagnosed and fixed using
this) that's also a useful player-facing decluttering option.

Entirely a rendering concern in `InteractPrompt.gd` — it filters
`_active` down to whichever entry carries `"is_focus_target": true`
while `Ctrl` is held. Resolution stays Player-owned, in
`InteractionSystem._update_prompt()`'s CASE-2 block: the focus target is
the closest entry in the already-distance-sorted `candidates` list that
actually produces a displayable prompt, covering pickups AND
interactables AND shelving uniformly (originally scoped to "whatever E
would fire on," which excluded pickup-only objects like Test Crate and
interactable-but-no-on_interact() objects like Fuel Can — broadened same
session once that gap was reported), with the grow-light-over-tray
override still applied on top since raw distance sorting doesn't know
about that deliberate exception.

**Scope:** only empty-handed prompts (CASE 2) are tagged with a real
`true`/`false`. Held-item prompts (CASE 1) never set the key, and a
missing key defaults to shown — Focus Mode has no effect while holding
an item. Collapsing CASE 1's basket/cookpot/give-to-NPC multi-target
prompts down to one true target remains a possible future pass.

Shares the `Ctrl` key with the held-item "upright" feature by design —
this reads the key via passive per-frame `Input.is_key_pressed()`
polling rather than consuming an input event, so the two can't
functionally conflict regardless of how the other one is implemented.
```

**`HANDOVER.md` — new top section:**
```markdown
# Handover — Focus Mode Broadened to Cover Pickup-Only Objects (Aug 2026)

## What changed this session
Focus Mode (hold Ctrl, added earlier this session) wasn't showing
prompts for pickup-only objects like Test Crate (`"pickup"` group only)
or Fuel Can (`"interactable"` group but no `on_interact()`) — it was
built around "what would E do," which is the wrong question for objects
E can't act on. Redefined the focus target as "the closest object with
any prompt at all" (E or F), sourced directly from `_update_prompt()`'s
already-sorted CASE-2 candidates list instead of a separate E-only
resolver. Deleted `_resolve_current_e_target()` (fully dead after the
rewrite) and renamed the tag `is_e_target` → `is_focus_target` in both
`InteractionSystem.gd` and `InteractPrompt.gd` to match its broader
meaning.

### Files modified
- `scripts/player/InteractionSystem.gd` — CASE-2 tagging rewritten,
  `_resolve_current_e_target()` removed.
- `scripts/ui/hud/InteractPrompt.gd` — key renamed, doc comments updated.
- `docs/systems/ui/README.md` — "Focus Mode" section corrected.

### Verification checklist
(see `FOCUS_MODE_PICKUP_FIX_PLAN.md` for the full checklist)
---
---
```
