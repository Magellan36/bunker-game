# Plan: Cooking Pot UI §1 Verification + Session Documentation Reconciliation (Aug 2026)

**Owner:** Player subsystem (this plan)
**Source:** `PLAN_cooking_pot_ui_fixes.md` (UI thread), §1 flagged as
touching `scripts/player/InteractionSystem.gd`.
**Code changes needed:** **none.** See finding below.
**Docs touched:** `docs/systems/player/README.md` (several sections),
`HANDOVER.md`.

---

## Finding: §1's InteractionSystem.gd changes are already applied

Before writing a diff, I pulled the repo fresh and checked. The uploaded
plan's §1 (CASE 1 held-item icons fix, `_quick_drop()` re-tracking fix)
is **already fully applied to `scripts/player/InteractionSystem.gd`**,
verified line-for-line identical to the plan's proposed `new_str`
blocks — `git log` confirms it landed in commit `f6f437c` ("Cooking pot
UI fixes... (PLAN_cooking_pot_ui_fixes.md)"), which applied the entire
uploaded plan in one pass, including the Player-thread-owned portion.
Confirmed both pieces are present exactly as specified:

- `_update_prompt()`'s CASE 1 held-item entry now builds `held_icons`
  via `get_slot_icon_descriptors()` and includes `"icons": held_icons`
  in its prompt entry — the fix for icons vanishing the instant an item
  with slot icons (Cooking Pot) is picked up.
- `_quick_drop()` now captures `dropped_item` before nulling `held_item`
  and re-adds it to `_tracked_bodies` at the end — the fix for a
  quick-dropped item's prompt staying invisible until a range
  leave/re-enter.

**Nothing further to hand the coding agent for §1.** You can give the
implementing agent §2–4 of the uploaded plan (all UI-thread-owned files)
alongside this plan's documentation updates below — no InteractionSystem.gd
work is pending.

---

## Documentation reconciliation — going forward, every plan from this
   thread will include this section

You asked for this to be standard practice from here on, so: below is a
full pass reconciling `docs/systems/player/README.md` against
everything that's actually landed in `scripts/player/` this session —
not just this cooking-pot item, but a genuine audit of the whole file
against current code, since I found it had drifted in a way worth
flagging clearly.

### What I found while auditing the docs against current code

Most of this session's individual fixes DID get their own Common-edits
entries already (Give/Takeaway, the Give-stuck/Takeaway-undetectable
bugfix, the Snatch contract, the inventory-slot-clear fix, the shelf
E-hijack fix — all present, confirmed via `git log`/`HANDOVER.md`). Good
hygiene there. But **one significant re-routing happened that the
Player README never caught up to**: a later plan (not from this thread —
`HANDOVER.md`'s "Unified Item Transfer Function for Give AND Snatch"
entry, owner listed as "Player + NPC subsystems") replaced the
`_release_item_to_npc()` / `clear_held_item_external()` path this
thread built with a new single function, `release_held_item_to_npc(npc)`,
and changed the NPC-side contract this file calls into
(`receive_item_from_player()` → `can_receive_item()` + `on_item_given()`).
I verified this against current code directly:

- `_try_give_to_nearest_npc()` now calls `target.can_receive_item(item)`
  then `release_held_item_to_npc(target)` then
  `target.on_item_given(item)` — NOT `receive_item_from_player()`,
  which the README's existing Common-edits entry still describes as the
  active path.
- `release_held_item_to_npc(npc)` is a new public
  `InteractionSystem` method (and a matching `Player.gd` forwarder) that
  does the full transfer itself — disconnect knocked_out, clear the
  inventory slot, clear held-item bookkeeping, `item.pickup(npc.hold_point)`,
  refresh HUD selection — undocumented in the README's Public API
  section entirely.
- `_release_item_to_npc()`, `clear_held_item_external()`,
  `Player.on_item_snatched()`, and `InventoryManager.clear_slot()` are
  now **dead code** — still present in the file, but nothing calls them
  anymore (Snatch was rewired to call `release_held_item_to_npc()`
  directly, same as Give). `HANDOVER.md`'s own entry already flags these
  as "candidates for deletion in a future cleanup pass" — the README
  should say the same, since right now it documents `_release_item_to_npc()`
  as if it's still the live mechanism.

This is exactly the kind of drift you'd want caught — the code is
correct and working, but the doc pointed at a superseded internal path.
Fixed below.

### Change 1 — `docs/systems/player/README.md`: Files table (stale line
   counts)

**Anchor:** verified current lines 42–46.

```markdown
old_str:
## Files
| File | Lines | Role |
|---|---|---|
| `Player.gd` | ~120 | `CharacterBody3D` — movement, sprint/stamina, facing, movement-lock |
| `PlayerStats.gd` | ~170 | Survival needs (food/water/sleep/health) + game clock |
| `InteractionSystem.gd` | ~686 | Pickup/drop/store/scroll, interact prompt builder |

new_str:
## Files
| File | Lines | Role |
|---|---|---|
| `Player.gd` | ~170 | `CharacterBody3D` — movement, sprint/stamina, facing, movement-lock, seated-chair input, NPC-facing Give/Snatch contract |
| `PlayerStats.gd` | ~200 | Survival needs (food/water/sleep/health) + game clock |
| `InteractionSystem.gd` | ~1,245 | Pickup/drop/store/scroll, interact prompt builder, NPC Give/Takeaway/Snatch transfer, shelf/basket/cookpot E-dispatch fairness |
```

### Change 2 — Public API section (missing the whole Give/Snatch
   contract surface)

**Anchor:** verified current lines 49–71.

```markdown
old_str:
## Public API
**`Player`** (`class_name Player`, extends `CharacterBody3D`):
`set_movement_locked(locked: bool)` — used by `PauseMenuUI`/any future
full-screen modal to block WASD/sprint/interact without pausing the
`SceneTree` (grid/generators keep running). Public vars: `stamina: float`
(0–100, read by HUD), `camera_yaw_rad: float` (set every frame by
`MainWorld`/`GameCamera` so input stays camera-relative).

**`PlayerStats`** (`class_name PlayerStats`, extends `Node`):
`replenish_food/water/sleep/health(amount: float)`, `get_time_display() ->
String`, `get_elapsed() -> float` / `set_elapsed(value: float)` (save/load —
see Persistence). Public vars: `food/water/sleep/health: float` (0–100),
`time_multiplier: float` (dev-tool time warp, F12), `current_day: int`.

**`InteractionSystem`** (`class_name InteractionSystem`, extends `Node3D`):
No public methods beyond `_ready()`/input handlers — it's driven entirely by
`_unhandled_input()` and `_process()`. External systems configure it by
setting its public vars directly (no setters): `inventory: Node`
(`InventoryManager` ref), `prompt: Node` (`InteractPrompt` ref),
`inventory_hud: Node`, `shelf_ui: Node`, `build_mode_active: bool`. Public
var `held_item: RigidBody3D` (currently held item, `null` if empty-handed) and
`selected_slot: int` (-1 = none) are read by other systems (e.g. HUD) but
never written externally.

new_str:
## Public API
**`Player`** (`class_name Player`, extends `CharacterBody3D`):
`set_movement_locked(locked: bool)` — used by `PauseMenuUI`/any future
full-screen modal to block WASD/sprint/interact without pausing the
`SceneTree` (grid/generators keep running). Public vars: `stamina: float`
(0–100, read by HUD), `camera_yaw_rad: float` (set every frame by
`MainWorld`/`GameCamera` so input stays camera-relative).
**NPC-facing contract (Aug 2026, see Common edits):** NPC-side code
resolves this node via `get_tree().get_first_node_in_group("player")`
and calls these directly — `get_held_item() -> Node` (read-only
passthrough to `InteractionSystem.held_item`), `release_held_item_to_npc
(npc: Node) -> bool` (forwards to `InteractionSystem`'s method of the
same name — the single shared transfer path for both Give and Snatch).
`on_item_snatched() -> void` also still exists but is currently
**dead code** — Snatch was rewired to call `release_held_item_to_npc()`
directly instead (see Common edits' "Unified Item Transfer" entry);
left in place, not yet removed.

**`PlayerStats`** (`class_name PlayerStats`, extends `Node`):
`replenish_food/water/sleep/health(amount: float)`, `get_time_display() ->
String`, `get_elapsed() -> float` / `set_elapsed(value: float)` (save/load —
see Persistence). Public vars: `food/water/sleep/health: float` (0–100),
`time_multiplier: float` (dev-tool time warp, F12), `current_day: int`.

**`InteractionSystem`** (`class_name InteractionSystem`, extends `Node3D`):
Driven mostly by `_unhandled_input()`/`_process()`, but now has one real
public method beyond that: **`release_held_item_to_npc(npc: Node) -> bool`**
(Aug 2026) — the single shared "held item leaves the player's hand for
an NPC" transfer path, used by both Give (`_try_give_to_nearest_npc()`)
and Snatch (`NPCItemUser.snatch_from_player()`, via `Player.gd`'s
forwarder above). Handles the full transfer: disconnects `knocked_out`,
clears the inventory slot if the item came from one, clears
`held_item`/`_held_from_slot`/`_is_holding_e`, refreshes HUD selection,
then `item.pickup(npc.hold_point)` + `npc.held_item = item`. External
systems otherwise configure this node by setting its public vars
directly (no setters): `inventory: Node` (`InventoryManager` ref),
`prompt: Node` (`InteractPrompt` ref), `inventory_hud: Node`,
`shelf_ui: Node`, `basket_ui: Node`, `build_mode_active: bool`. Public
var `held_item: RigidBody3D` (currently held item, `null` if empty-handed) and
`selected_slot: int` (-1 = none) are read by other systems (e.g. HUD) but
never written externally.
```

### Change 3 — Call graph (missing Give/Takeaway/Snatch entirely)

**Anchor:** verified current lines 113–131.

```markdown
old_str:
## Call graph (brief)
```
Player._physics_process() → _handle_movement() (WASD/sprint/stamina)
                           → _handle_interaction_input() → interacted.emit()
                             (only relevant when InteractionSystem.held_item == null)

InteractionSystem._unhandled_input()
  → scroll wheel  → _scroll_slot(dir) → _put_item_back_to_slot()/_bring_item_to_hand_from_slot()
  → F (pickup)    → _try_pickup() / _quick_drop() / shelf.on_f_interact()
  → E (tap)       → held_item.on_use() / _try_interact() (world objects: generators, breakers, etc.)
                    (fires instantly on press; `_is_holding_e` stays true only
                    to drive per-frame continuous-hold actions like
                    `FuelCan.refuel_tick()` — it no longer gates a store action)
  → G (tap)       → _store_item() / _put_item_back_to_slot() (instant, no hold/progress bar)
InteractionSystem._process() → _update_prompt() → prompt.set_prompts(...)/hide_prompt()

PlayerStats._process() → _tick_needs() → food/water/sleep drain, starvation health drain
                        → _tick_clock() → time_changed/day_changed
```

new_str:
## Call graph (brief)
```
Player._physics_process() → _handle_movement() (WASD/sprint/stamina)
                           → _handle_interaction_input() → interacted.emit()
                             (only relevant when InteractionSystem.held_item == null)

InteractionSystem._unhandled_input()
  → scroll wheel  → _scroll_slot(dir) → _put_item_back_to_slot()/_bring_item_to_hand_from_slot()
  → F (pickup)    → _try_pickup() / _quick_drop() / shelf.on_f_interact()
                    (_try_pickup() also checks NPCItemUser.find_holder() —
                    picking up an NPC-held item is "Takeaway", see below)
  → E (tap)       → shelf.on_e_interact() (distance-fair vs. any held-item
                      E target, Aug 2026 — see Common edits) / basket-stash /
                      cookpot-stash-or-stove / NPC-give / held_item.on_use() /
                      _try_interact() (world objects: generators, breakers, etc.)
                    (fires instantly on press; `_is_holding_e` stays true only
                    to drive per-frame continuous-hold actions like
                    `FuelCan.refuel_tick()` — it no longer gates a store action)
  → G (tap)       → _store_item() / _put_item_back_to_slot() (instant, no hold/progress bar)
InteractionSystem._process() → _update_prompt() → prompt.set_prompts(...)/hide_prompt()

NPC Give   → _try_give_to_nearest_npc() → NPC.can_receive_item() →
             InteractionSystem.release_held_item_to_npc(npc) → NPC.on_item_given()
NPC Snatch → NPCItemUser.snatch_from_player() → Player.release_held_item_to_npc(npc)
             → InteractionSystem.release_held_item_to_npc(npc)   (same function as Give)
NPC Takeaway → player presses F on an NPC-held item → _try_pickup() finds it via
               NPCItemUser.find_holder() → normal pickup + NPC.on_item_taken_by_player()

PlayerStats._process() → _tick_needs() → food/water/sleep drain, starvation health drain
                        → _tick_clock() → time_changed/day_changed
```
```

### Change 4 — Common edits: mark the superseded Give/Takeaway path
   clearly, add the cooking-pot fix entry

**Anchor:** verified current lines 231–241 (end of the existing
Common-edits list, the shelf-fairness entry).

```markdown
old_str:
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

## Basket Prompt Fix (Jul 2026)

new_str:
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
- **⚠️ Superseded (Aug 2026): Give/Snatch transfer unified into
  `release_held_item_to_npc()`.** The two entries above
  ("NPC Give/Takeaway support" and its bugfix, "Give/Snatch
  inventory-slot clear fix") describe `_release_item_to_npc()` /
  `clear_held_item_external()` as the live cleanup path — that's no
  longer accurate. A later cross-thread plan ("Unified Item Transfer
  Function for Give AND Snatch", see `HANDOVER.md`) replaced both with
  a single `release_held_item_to_npc(npc: Node) -> bool` method (see
  Public API above), used by Give (`_try_give_to_nearest_npc()`, now via
  `NPC.can_receive_item()`/`on_item_given()`, NOT the old
  `receive_item_from_player()`) AND Snatch
  (`NPCItemUser.snatch_from_player()` → `Player.release_held_item_to_npc()`
  → here). **`_release_item_to_npc()`, `clear_held_item_external()`,
  `Player.on_item_snatched()`, and `InventoryManager.clear_slot()` are
  now dead code** — still present, nothing calls them — flagged as
  cleanup candidates in Known tradeoffs below rather than removed here,
  since no removal was part of the plan that superseded them.
- **Cooking Pot UI: held-item icons + quick-drop re-tracking (Aug
  2026, UI-thread plan, InteractionSystem.gd portion only).** Two small
  fixes, both generic (not cooking-specific): (1) CASE 1's held-item
  prompt entry now includes an `"icons"` key built from
  `get_slot_icon_descriptors()` if the held item implements it — CASE 2
  already did this for nearby (not held) interactables, CASE 1 never
  did, which is why a held Cooking Pot's 3 ingredient-preview circles
  vanished the instant it was picked up. (2) `_quick_drop()` now
  re-adds the dropped item to `_tracked_bodies` immediately instead of
  waiting for Jolt's `Area3D.body_entered` to refire — a quick-dropped
  item usually lands well inside the same detection volume it was
  picked up from, so that signal never naturally refires, leaving the
  item's prompt (and icon row, if any) invisible until an actual range
  leave/re-enter.

## Basket Prompt Fix (Jul 2026)
```

### Change 5 — Known tradeoffs: note the dead code found above

**Anchor:** verified current lines 291–299.

```markdown
old_str:
## Known tradeoffs / tech debt
- No automated tests.
- Survival stat/inventory state isn't saved (see Persistence above).
- `InteractionSystem.gd` is a single ~686-line file covering pickup, drop,
  store, scroll, AND prompt-building — a plausible future split candidate
  (e.g. extract prompt-building into its own `_owner`-pattern helper the same
  way `BuildModeController`'s Stage 10 extraction did) but not currently
  scheduled; only split it if a genuinely self-contained new feature needs
  its own file (see repo-wide "no god files" rule in `HANDOVER.md`).

new_str:
## Known tradeoffs / tech debt
- No automated tests.
- Survival stat/inventory state isn't saved (see Persistence above).
- `InteractionSystem.gd` is a single ~1,245-line file covering pickup,
  drop, store, scroll, prompt-building, AND the NPC Give/Takeaway/Snatch
  transfer path — see the Player subsystem's cleanup assessment plan
  (`PLAYER_SUBSYSTEM_CLEANUP_ASSESSMENT_AND_PLAN.md`) for a scoped,
  phased extraction plan following the same `_owner`-pattern precedent
  `BuildModeController`'s Stage 10 and the Power system's
  `PowerGraph`/`PowerRegistry`/`PowerSolver` split already established —
  not yet executed, awaiting sign-off on Phase 1.
- **Dead code (Aug 2026):** `_release_item_to_npc()`,
  `clear_held_item_external()`, `Player.on_item_snatched()`, and
  `InventoryManager.clear_slot()` were superseded by the unified
  `release_held_item_to_npc()` transfer path (see Common edits above)
  but were left in place rather than removed. Safe to delete in a future
  pass; not currently scheduled.
```

---

## Change 6 — `HANDOVER.md`: doc-reconciliation entry

**Anchor:** insert at the very top of the file.

```markdown
new content to prepend:
# Handover — Player Docs Reconciliation + Cooking Pot UI §1 Verification (Aug 2026)

## What changed this session
No code changes — verified `PLAN_cooking_pot_ui_fixes.md`'s §1
(`scripts/player/InteractionSystem.gd` portion: CASE 1 held-item icons
fix, `_quick_drop()` re-tracking fix) is already fully applied, exactly
matching spec (landed in commit `f6f437c`, which the UI thread applied
in full including the Player-owned portion). Nothing further needed for
the implementing agent on that front.

Used this as the trigger for a full audit of
`docs/systems/player/README.md` against current code — going forward,
every plan from the Player subsystem thread will include a
documentation-reconciliation pass, not just append a note for its own
change. Found and fixed: a stale Files-table line count, a missing
Public API entry for `release_held_item_to_npc()` (Player + Interaction-
System), a Call graph with no mention of Give/Takeaway/Snatch at all,
and — the significant one — the existing Common-edits entries for Give/
Takeaway still described `_release_item_to_npc()`/
`clear_held_item_external()` as the live mechanism, when a later
cross-thread plan ("Unified Item Transfer Function for Give AND Snatch")
had already superseded both with a single `release_held_item_to_npc()`
method and rewired the NPC-side contract from `receive_item_from_player()`
to `can_receive_item()`/`on_item_given()`. Marked the superseded entries
clearly, documented the current mechanism, and flagged the now-dead code
(`_release_item_to_npc()`, `clear_held_item_external()`,
`Player.on_item_snatched()`, `InventoryManager.clear_slot()`) in Known
tradeoffs as a cleanup candidate rather than removing it (no removal was
in scope here).

### Files modified
- `docs/systems/player/README.md` — Files table, Public API, Call graph,
  Common edits (superseded-path flag + new cooking-pot entry), Known
  tradeoffs.
- `HANDOVER.md` — this entry.

---
---

```

(Two trailing `---` lines match this file's existing entry-separator
convention, confirmed against the current top of the file.)
