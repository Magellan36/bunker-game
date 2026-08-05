# Handover — Fix: Relaxing In a Chair/Bed Loops When Energy Is Already Full (Aug 2026)

## What changed this session
Root cause: `LieActivity.done()` returns `_lying and energy >= 100`
(`SitActivity` the same at 90). `RelaxActivity` delegates to these via
`enter()` — correct, since score() being blocked at high energy should
not stop a scheduled relax — but `done()` doesn't care HOW it was
entered: at already-full energy, `done()` is true the instant seated,
stand back up, loop.

Fix: two new delegation-only activities in `NPCBrain.gd`:
- `RelaxSitActivity extends SitActivity`, `RelaxLieActivity extends
  LieActivity`. Same arrival/seating mechanics, but `done()` no longer
  checks energy at all (chair/bed-null only) — RelaxActivity's session
  timer is the only thing that ends them. Energy regen runs at **1/4**
  normal rate (a break, not full rest/sleep). `score()` returns 0.0 so
  they can never be auto-selected.
- `RelaxActivity.enter()` now composes the Relax-prefixed classes, so the
  `done()`-right-after-`enter()` fallback chain now means "no chair/bed
  found", never "energy already full".

Normal Sit/Lie behavior untouched.

### Files modified
- `scripts/npc/NPCBrain.gd` — two new classes + `RelaxActivity.enter()`
  swap.
- `docs/systems/npc/README.md` — testing items 42–44 appended.
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_RELAX_ENERGY_LOOP_FIX.md` (3 steps). No Godot CLI available —
recommend opening the project to compile-check.

---

# Handover — Trait Absence Is Baseline + Relaxing Activity (Aug 2026)

## What changed this session
Two independent changes in the NPC subsystem.

### Part A — Traits only exist when they matter
- `NPC.randomize_personality()` no longer fills all 5 trait slots with a
  flat 0.0–1.0 roll. Each slot is now present with 55% chance
  (`TRAIT_PRESENCE_CHANCE`), and a *present* trait is skewed into the low
  or high band (never the neutral middle). Absent = baseline: every
  `_*_trait_mult()` uses `.get(key, 0.5)`, which already meant baseline —
  no multiplier changes were needed.
- `get_trait_word()` returns "" for an absent key; `get_personality_words()`
  filters empties, so an NPC shows anywhere from 0–5 personality words.
- `NPCTalkMenuUI` falls back to "Nothing stands out" for the 0-trait case.

### Part B — Relaxing
- New `RelaxActivity` (NPCBrain) — a scheduled break distinct from
  Wander/Idle. Composes `SitActivity`/`LieActivity` for the actual
  seating mechanics (same pattern as `CommandRestActivity`), or stands in
  place if neither a chair nor a bed is free. Flat baseline score (6.0,
  above Wander's 5.0) × Work Ethic passive mult, gated by a daily time
  budget.
- Daily budget: 1 game-hour/day baseline, 2 for Lazy
  (`NPC.get_relax_daily_budget()`), tracked via `spend_relax_time()` and
  reset by `_tick_relax_day()` on the same 5s tick as mood. Sessions run
  ~20–40 game-minutes.
- Job-refusal while relaxing: first "Harvest the plants" command during a
  relax session is refused with a flavor line
  (`get_relaxing_refusal_line()`); the second ask complies at -3
  relationship (`request_job_while_relaxing()`). Counter resets each
  relax session via `reset_relax_job_requests()`.

### Files modified
- `scripts/npc/NPC.gd` — presence-based personality generation; trait-word
  display; Relaxing section (budget, refusal state, dialogue).
- `scripts/npc/NPCBrain.gd` — `RelaxActivity` registered in `setup()`'s
  candidate list; `is_relaxing()`; the new class.
- `scripts/ui/npc/NPCTalkMenuUI.gd` — personality empty-list fallback;
  harvest-command relaxation interception.
- `docs/systems/npc/README.md` — Personality section updated (presence-
  based); new Relaxing subsection; testing items 39–41 (renumbered from
  the plan's 27–29 to avoid colliding with the existing checklist).
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_TRAIT_BASELINE_AND_RELAXING_PLAN.md` items 27–29 (39–41 in the
README). No Godot CLI available — recommend opening the project to
compile-check.

---

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

---

# Handover — NPC Meter Colors: Match Player HUD Palette (Aug 2026)

**Owner:** UI Claude instance (HUD/menus).

## What changed
`NPCTalkMenuUI.gd`'s 5 need bars (Health/Energy/Hunger/Thirst/Mood) used
to recolor by VALUE (theme.ok/warn/crit — blue/amber/red by fill level),
the opposite convention from the player's own `NeedsGauge` rings, which
use ONE fixed identity color per stat. Now the NPC bars match the player
HUD: fixed per-stat colors, fill LENGTH is the only value feedback.
- Health: `Color(0.81, 0.17, 0.17)` — exact copy of `NeedsGauge.COLOR_HEALTH`.
- Energy: `Color(0.57, 0.33, 0.81)` — exact copy of `NeedsGauge.COLOR_SLEEP`.
- Thirst: `Color(0.24, 0.52, 0.90)` — exact copy of `NeedsGauge.COLOR_WATER`.
- Mood: `Color8(188, 160, 220, 255)` — exact `#bca0dc` (Brannon's spec),
  via `Color8` so no float rounding.
- Hunger: `Color(0.90, 0.80, 0.20)` — the player HUD has no yellow stat
  to copy, so this reuses the project's other established yellow (Power
  panels' stripe color). One-line swap if a specific yellow was wanted.

Added `NEED_COLORS` table (`fallback = theme.ok` via `.get()`); the
refresh loop's per-value recolor line is now just the fixed color.

## Files Modified
`scripts/ui/npc/NPCTalkMenuUI.gd` (one const table + two color lines).

## Next Up
- None — verification checklist in the plan: reopen an NPC talk panel and
  confirm the 5 colors, drain needs and confirm bars don't recolor
  (only fill length shrinks), no console errors.

---

# Handover — Wire Up Work Ethic + Neuroticism (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
Work Ethic and Neuroticism moved from "generated/displayed only" to
fully wired mechanics (the last two of the five traits — all five now
drive behavior).

- **Work Ethic** — ±30% score multiplier applied symmetrically:
  `JobActivity.score()` × `get_work_ethic_job_mult()`
  (`lerp(0.7, 1.3, work_ethic)`), and every passive/need activity —
  Wander, Sit, Lie, Eat, Drink — × `get_work_ethic_passive_mult()`
  (`lerp(1.3, 0.7, work_ethic)`, the mirror image). Hard Worker: jobs
  ×1.3 / passive ×0.7. Lazy: jobs ×0.7 / passive ×1.3. Steady: ×1.0 both.
  Same continuous score-bias pattern Irritability already uses — not a
  discrete roll.
- **Neuroticism** — scales mood's random per-tick drift
  (`MOOD_DRIFT_MAX_PER_GAME_HOUR`) via `_neuroticism_trait_mult()`
  (`lerp(0.5, 1.5, neuroticism)`, same 0.5x-1.5x spread as Sociability).
  Neurotic: ×1.5 (wilder swings). Composed: ×1.0. Easygoing: ×0.5
  (calmer). Only the noise component — needs and contagion unaffected.

## Files Modified
`scripts/npc/NPC.gd` (two new multiplier functions +
`get_work_ethic_job_mult()`/`get_work_ethic_passive_mult()`, one drift-tick
line), `scripts/npc/NPCBrain.gd` (six activity `score()`s).

## Next Up
- None specific — testing items 37-38 in `docs/systems/npc/README.md`
  cover both traits.

---

# Handover — Trait Word Fix: "Kind" → "Open" (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
`NPC.TRAIT_WORDS["sociability"]["high"]` was still `"Kind"` — the
agreed-upon rename to `"Open"` (better captures fast relationship
reactivity in both directions without the value judgment) had never
actually landed. Fixed in `scripts/npc/NPC.gd`, and cleaned up the stale
`FUTURE WORK` comment a few lines up that still described Sociability as
unwired — it's now wired via `_sociability_trait_mult()`. No code depends
on the old string (`get_personality_words()`, the E-panel, and `NPCDebug`
all read from the dictionary); `docs/systems/npc/README.md`'s trait-word
band listing updated to match.

## Files Modified
`scripts/npc/NPC.gd` (one dictionary value + one comment),
`docs/systems/npc/README.md` (trait-word band listing).

## Next Up
- None.

---

# Handover — Snatch: Distinguish "Dropped" from "Swapped Away in Inventory" (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
`SnatchActivity.tick()`'s "did they drop it, chase it on the ground"
branch only tested `not _tracked_item.is_held`. But
`InventoryManager.deactivate_item()` (player scrolling to another slot)
also sets `is_held = false`, so a swapped-away, frozen-in-place stored
item was treated as a genuine drop — the NPC walked to its stale last
position and grabbed it straight out of the inventory slot array.

The two states are distinguishable by `collision_layer`:
- genuinely dropped (`remove_item()`) → `collision_layer == 1`
- swapped away/stored (`deactivate_item()`) → `collision_layer == 0`
- actively held (`activate_item()`/`pickup()`) → `collision_layer == 2`

Added `"collision_layer" in _tracked_item and _tracked_item.collision_layer
== 1` to the chase condition. If it now correctly fails (stored, not
dropped), the code falls through to the existing fallback, which already
logs `"aborted"` and ends the activity cleanly. Genuine drops still pass.

## Files Modified
`scripts/npc/NPCBrain.gd` (one condition in `SnatchActivity.tick()`).

## Next Up
- None specific — testing items 35-36 in `docs/systems/npc/README.md`
  cover both branches (swap-abort and genuine-drop-divert).

---

# Handover — Snatch Root-Cause Fixes: Scoring Blind Spot, Wrong Inventory Function, Grab Distance (Aug 2026)

**Owner:** NPC Claude instance, plus one function fix in Player-owned
`InteractionSystem.gd`.

## What changed
1. **Scoring blind spot fixed** — `EatActivity.score()`/`DrinkActivity.score()`
   returned 0 (activity never selected) whenever no normal world target
   existed, even if the player was holding the only matching item and the
   relationship was hostile. Added `NPC.is_player_snatch_eligible()` — a
   deterministic, roll-free check mirroring `find_player_snatch_target()`'s
   gates minus the probability roll — and both `score()`s now fall through
   to it, so the activity gets selected and `enter()` runs (where the real
   roll happens).
2. **Snatched item no longer drops** — `InteractionSystem.release_held_item_to_npc()`
   called `inventory.remove_item()`, whose internal `item.drop()` unfroze
   physics/gravity and emitted `dropped` one line before the transfer
   `pickup()`. Reordered: physically `pickup()` first, then clear the slot
   via `inventory.clear_slot()` (the function whose own doc comment says
   it's meant to run AFTER an NPC's pickup() reassignment — Snatch).
   Item now visibly transfers to and stays in the NPC's hand.
3. **Grab distance** — new `NPCItemUser.SNATCH_RANGE = 1.6` (vs the
   loose-item `PICKUP_RANGE = 1.2`) used by both `SnatchActivity.tick()`'s
   player-chase branch and `snatch_from_player()`'s range check, so the
   NPC stops at a visible gap instead of walking into physical contact
   with the player. The dropped-item ground-chase branch keeps
   `PICKUP_RANGE` (loose item, no collision body) unchanged.

## Files Modified
`scripts/npc/NPC.gd` (new `is_player_snatch_eligible()`),
`scripts/npc/NPCBrain.gd` (two `score()`s, `SnatchActivity` range),
`scripts/npc/NPCItemUser.gd` (`SNATCH_RANGE` + range check),
`scripts/player/InteractionSystem.gd` (`release_held_item_to_npc()`).

## Next Up
- None specific — testing items 32-34 in `docs/systems/npc/README.md`
  cover the three fixes; the scoring-blind-spot fix is the one most worth
  re-verifying in-editor (it changes what `_think()` picks).

---

# Handover — Storage UI Unification: ShelfUI + BasketUI → StorageUI (Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode/Furniture).

## What changed
- New `scripts/ui/inventory/StorageUI.gd` — one generic, config-driven
  storage overlay replacing `ShelfUI.gd`/`BasketUI.gd` (476/470 lines, 17
  of 18 duplicated). Any storage object implements a 4-method contract
  (`get_ui_config`, `get_slot_display`, `take_for_carry`,
  `take_for_inventory`) and needs zero new UI code.
- `Shelving.gd`/`Basket.gd` (furniture-items scope) implement that
  contract as thin wrappers over their existing retrieval logic —
  `retrieve_to_carry()`/`retrieve_to_inventory()` gained bool return
  values, nothing else about their behavior changed (NPC-facing
  `npc_retrieve()` and existing signals untouched).
- `MainWorld.gd`'s `_setup_shelf_ui()`/`_setup_basket_ui()` collapsed into
  one `_setup_storage_ui()`. `InteractionSystem.gd` (Player-thread-owned)
  needed ZERO changes — its `shelf_ui`/`basket_ui` properties both now
  point at the same shared instance.
- Deliberately built with room for planned future storage types (lockable
  storage, freezers/fridges, lockers, larger shelving units) — see
  `docs/systems/ui/README.md`'s "Storage UI Unification" section for how
  each fits without touching `StorageUI.gd` again.

## Files Created
`scripts/ui/inventory/StorageUI.gd`

## Files Deleted
`scripts/ui/inventory/ShelfUI.gd` + `.uid`,
`scripts/ui/inventory/BasketUI.gd` + `.uid`

## Files Modified
`scripts/world/furniture/Shelving.gd`, `scripts/world/items/Basket.gd`,
`scripts/world/core/MainWorld.gd`,
`scripts/world/build/BuildModeController.gd`

## Next Up
- Visual styling (`UIKit` domain-stripe system) not applied to
  `StorageUI.gd` in this pass — flagged as a deliberate, deferrable
  choice, not an oversight.
- First planned future storage type (lockable storage / freezer / locker
  / larger shelving) will be the real test of the contract — implement it
  by adding the 4 contract methods to that object's own script, nothing
  else.

---

# Handover — UI Overhaul Arc: Menu Unification, Rounded Corners, Admin Menu Rework, Bugfixes (Jul-Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode placement).

## What changed across this arc
1. **Pause Menu + Graphics Settings Unification** — both rewritten onto
   new shared `UIKit` menu-builder helpers; fixed `GraphicsSettingsPanel`'s
   real off-center bug (centered itself before its content was added, so
   the baked offset never matched its final size); fixed a corrupted-bytes
   issue isolated to `PauseMenuUI.gd`.
2. **Power + Water UI Unification** — `WATER`/`POWER` domains collapsed
   onto one identical palette, differing only in a new `theme.accent` used
   for a top stripe; brought `PowerTerminalUI` in line with the other 3
   power panels it didn't match before.
3. **Rounded Corners + Stripe Recolor + Farming Domain + Top Padding** —
   one shared corner radius everywhere via a new `UIKit.draw_rounded_rect()`;
   power's stripe green→yellow; new `Domain.FARMING` (green) for
   `FarmingTrayUI`; a uniform +6px top-padding pass across every panel.
4. **F7 Admin Menu rework** — was rendering ~1,250px tall (24 rows across
   7 sections, mostly NPC rows folded in from the deleted F10 menu); now a
   fixed height with collapsible sections + a real `ScrollContainer`
   (native mouse-wheel + scrollbar).
5. **Shared close-button icon** — one new icon asset
   (`assets/icons/close_x.png`) replacing 2 different hand-drawn × forms
   spread across 7 files, centralized behind `UIKit.draw_close_icon()`.
6. **InventoryHUD preview fixes** — rotation now matches
   `BuildModeHUD`'s 45°/45° resting pose, 3x camera zoom, and a real fix
   for a "choppy translucent background" bug (6 overlapping alpha shapes
   double-blending at their seams, replaced with one unified
   `UIKit.draw_rounded_rect()` call — same technique used throughout this
   whole arc).
7. **Farming Shop seed bugfix** — `BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]`
   had a duplicate `tile_id` (copy-paste typo) that shifted several seeds
   onto the wrong species when purchased (e.g. "Corn Seeds" spawned
   Blueberry). Root-caused via `FarmingShopHelper.SHOP_ITEM_INFO` (the
   actual authoritative mapping, which was correct) and fixed the display
   list to match it.

## Files Modified (representative, not exhaustive — see
`docs/systems/ui/README.md`'s per-pass sections above for full detail)
`UIKit.gd`, `PauseMenuUI.gd`, `GraphicsSettingsPanel.gd`,
`PowerTerminalUI.gd`, `PowerPriorityUI.gd`, `GeneratorInspectUI.gd`,
`ZoneCustomizeUI.gd`, `WaterInfoUI.gd`, `WaterDispenserUI.gd`,
`FarmingTrayUI.gd`, `AdminMenu.gd`, `InventoryHUD.gd`,
`BuildModeHUD.gd` (one data fix only).

## Files Created
`assets/icons/close_x.png`

## Next Up
- The power/water/farming palette merge and rounded-corner/stripe system
  hasn't touched `ShelfUI.gd`/`BasketUI.gd` (still their own look, and
  ~17 of 18 functions duplicated between the two files) or
  `BuildModeHUD.gd`'s own toolbar/construct-menu chrome — logical next
  candidates for this same treatment if requested.
- `FARMING_SHOP_ITEMS["Seeds"]`'s manual two-list sync with
  `FarmingShopHelper.SHOP_ITEM_INFO` is flagged as fragile (see
  `docs/systems/farming/README.md`) but not yet hardened.

---

# Handover — Re-applied Dropped Fixes + Continuous Snatch Pursuit (Aug 2026)

**Owner:** NPC instance. All NPC-side; no Player changes.

## What changed this session
- `scripts/npc/NPCItemUser.gd` — `grab_loose()` gained the missing
  `is_held` guard (an item claimed by this NPC can still have been
  physically picked up by the player — claims only block other NPCs'
  `claim_item()` calls, never the player's pickup path).
- `scripts/npc/NPCBrain.gd` — three early-abort additions: `EatActivity`
  tick()'s `_loose` branch (abandons + releases claim when the item is
  now held; also releases claim on a failed grab), `DrinkActivity`
  `_tick_bottle()` (abandons when the target bottle is held), and
  `JobActivity._tick_fetch()` (abandons when the fetch item is held).
- `scripts/npc/NPCBrain.gd` — `SnatchActivity` rewritten: continuously
  re-aims at the player every tick (was: target set once at enter());
  chases the dropped tracked item on the ground instead of giving up if
  the player drops it; new `MAX_CHASE_TIME` (20s) safety valve so a
  player who just keeps walking doesn't leave the NPC chasing forever
  (interruptible() is false, so nothing else could interrupt it);
  `done()` also requires `_tracked_item == null`.
- `scripts/npc/NPC.gd` — `find_player_snatch_target()` decision path now
  explicitly logged via `NPCDebug.log_snatch()` ("not considered" with
  reason, roll attempt, roll success/failure) when debug logging is on.
- `docs/systems/npc/README.md` — Snatch section updated for continuous
  pursuit + dropped-item follow + MAX_CHASE_TIME; Testing Checklist
  items 26-31 added.
- `HANDOVER.md` — this entry.

## Notes
- `MAX_CHASE_TIME` is a plan-author addition beyond the original ask —
  flagged in the code comment ("Remove this if indefinite pursuit is
  actually what you want") — kept per the plan.
- No Godot CLI available — no compile check ran; recommend opening the project.

---
---

# Handover — Unified Item Transfer Function for Give AND Snatch (Aug 2026)

**Owner:** Player + NPC subsystems (one mechanism now, listed as one plan).

## What changed this session
Replaced the separate patchwork (inventory-slot clearing,
HUD prompt staleness, standalone snatch pickup logic) with a single
shared transfer function mirroring `_quick_drop()` — the only difference
is the destination is an NPC's hands instead of the floor.

- `scripts/player/InteractionSystem.gd` — new `release_held_item_to_npc(npc)`
  (disconnect knocked_out, clear inventory slot via `remove_item()` if it
  came from one, clear held_item/_held_from_slot/_is_holding_e, refresh
  HUD selection, then `item.pickup(npc.hold_point)`/`npc.held_item = item`).
  `_try_give_to_nearest_npc()` simplified to: `can_receive_item()` →
  `release_held_item_to_npc()` → `on_item_given()`.
- `scripts/player/Player.gd` — `release_held_item_to_npc(npc)` forwarding
  to `InteractionSystem` (reachable via the `"player"` group node for
  NPC-side code); `get_held_item()` already existed.
- `scripts/npc/NPC.gd` — `receive_item_from_player()` removed, replaced by
  `can_receive_item()` (pure check) + `on_item_given()` (consequence
  wiring: consumption activity via force_command + begin_with_item, gift
  burnout/relationship bookkeeping). The physical transfer is now entirely
  the Player side's job since it's the only side with inventory-slot context.
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player()` simplified to route
  through `player.release_held_item_to_npc(npc)` (still separate from
  strict `grab_loose()`, still only reached via SnatchActivity's gate).
  `SnatchActivity` unchanged — it just calls `snatch_from_player()` and
  checks the boolean.
- `docs/systems/npc/README.md` — Give/Snatch sections updated for the
  unified transfer path; Testing Checklist item 25 added.
- `HANDOVER.md` — this entry.

## Notes / dead code
- `Player.on_item_snatched()` / `InteractionSystem.clear_held_item_external()` /
  `_release_item_to_npc()` / `InventoryManager.clear_slot()` are now
  UN-CALLED by Snatch (the shared `release_held_item_to_npc()` handles
  everything). Left in place per the plan (no removal instructed);
  candidates for deletion in a future cleanup pass.
- Plan's "item bumps out and drops" post-script: that symptom is the
  pre-existing knockout system (item displaced > KNOCK_DISTANCE from the
  hold point by physical shoving), not the transfer path — flagged for
  investigation only if it recurs after this.
- No Godot CLI available — no compile check ran; recommend opening the project.

---
---

# Handover — Give/Snatch Inventory-Slot Clear Fix (Aug 2026)

## What changed this session
Fixed a bug where giving or having an item Snatched by an NPC left it
showing forever in its original inventory slot. Root cause: the cleanup
in `_try_give_to_nearest_npc()` (destroyed-item branch) and
`clear_held_item_external()` (Snatch) only cleared local `held_item`/
`_held_from_slot` bookkeeping, never touching
`InventoryManager.slots[]`. Fix routes both through a new shared
`_release_item_to_npc()` helper calling a new
`InventoryManager.clear_slot()`. Deliberately did NOT use the originally
proposed `InventoryManager.remove_item()` — that method is documented
world-drop-only (resets collision_layer to 1, re-adds `"pickup"` group,
repositions via `drop()`), which would have fought an NPC's
already-completed `item.pickup(npc.hold_point)` reassignment on Snatch
(visually yanking the item back out of the NPC's hand) or errored
outright on an already-freed item on a destroyed-item Give.
`clear_slot()` only nulls the slot array entry, nothing else.

### Files modified
- `scripts/player/InteractionSystem.gd` — new `_release_item_to_npc()`
  helper; `_try_give_to_nearest_npc()` and `clear_held_item_external()`
  both now delegate to it.
- `scripts/ui/inventory/InventoryManager.gd` — new `clear_slot()` method
  (additive only, no existing method changed).
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_SNATCH_INVENTORY_CLEAR_FIX_PLAN.md`
for the full 5-item checklist)

---
---

# Handover — NPC Give Real-Transfer Fix + Dedicated Snatch Activity + Relationship Debug Buttons (Aug 2026)

**Owner:** NPC instance. Restates Give as a real transfer and redesigns
the Snatch mechanic as a dedicated non-interruptible activity.

## What changed this session
- `scripts/npc/NPCActivity.gd` — full-file replacement adding the
  `begin_with_item()` (Part 28) and `take_handoff()` (Part 30) virtuals.
- `scripts/npc/NPCBrain.gd` —
  - Core `tick()` now polls `_current.take_handoff()` right after
    `tick()` runs and switches to the returned successor (explicit
    handoff, avoiding reentrant `force_command()` from inside an
    activity's own tick). On handoff it also calls the successor's
    `begin_with_item(_npc, _npc.held_item)`.
  - New `GivenEatActivity extends EatActivity` and
    `GivenDrinkActivity extends DrinkActivity` — player-Give/snatch
    consumption hand-offs (score()=0, no search, keyed off held_item/`_target`).
  - New dedicated, non-interruptible `SnatchActivity` (entered via
    force_command, never scored), which walks to the player, grabs via
    `snatch_from_player()`, and hands off to Given* via `take_handoff()`.
  - `EatActivity`/`DrinkActivity` now stash a snatch target in
    `_pending_snatch` (from `find_player_snatch_target()` in
    enter()/_reacquire_or_finish()) and request the handoff to
    `SnatchActivity` on the next tick instead of walking the snatch
    themselves — the old in-activity snatch mode (Part 29) was
    interruptible and got cancelled mid-approach by the think-cycle.
- `scripts/npc/NPC.gd` — `receive_item_from_player()` rewritten as a
  real transfer: `force_command()` the Given* activity first, then
  `item.pickup(hold_point)`/`held_item = item`, then
  `activity.begin_with_item()`; consumption is async inside the
  activity's tick, not instant. Snatch block updated to final form
  (`find_player_snatch_target()`/`debug_force_snatch()`) plus new
  `debug_adjust_player_relationship(delta)` (writes `relationships["player"]`
  directly, bypassing Sociability, for exact ±25 F7 testing).
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player()` unchanged
  (verified present and matching).
- `scripts/npc/NPCDebug.gd` — new `log_snatch()` staged logging.
- `scripts/ui/menus/AdminMenu.gd` — two new F7 rows: "Relationship -25 /
  +25 (All NPCs ↔ Player)" with `_on_npc_relationship_down/up_pressed()`
  + `_adjust_all_npc_relationship()`.
- `docs/systems/npc/README.md` — Give paragraph rewritten for real
  transfer; Relationship Snatch section rewritten for `SnatchActivity` +
  `take_handoff()` + `log_snatch()`; Testing Checklist items 22-24.

## Dependencies / notes
- **Player-side inventory-clear fix required end-to-end**
  (`PLAYER_SUBSYSTEM_INVENTORY_CLEAR_FIX.md`, separate Player subsystem
  file): without it, Give/Snatch leave the transferred item stale in the
  player's inventory list. Not applied here — NPC side only.
- The `is_held` guard on `grab_loose()` referenced by the plan's
  commentary was never applied on disk (prerequisite theft-fix plan was
  never given) — the design intent is preserved via the strict
  `grab_loose()` vs `snatch_from_player()` separation regardless.

---
---

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

---
---

# Handover — NPC Relationship Snatch Mechanic + Debug Trigger (Aug 2026)

**Owner:** NPC instance. Adds a hostility-gated "snatch" where a
badly-relationship'd NPC forcibly takes a currently player-HELD food/
water item instead of finding a normal one.

## What changed this session
- `scripts/npc/NPC.gd` — `SNATCH_RELATIONSHIP_THRESHOLD` (-50),
  `SNATCH_CHANCE_AT_THRESHOLD` (5%), `SNATCH_CHANCE_AT_MIN` (50%),
  `_debug_force_snatch`; `get_snatch_chance()` (linear -50→-100 scaling),
  `find_player_snatch_target(need_filter)` (gate + chance + held-item
  check, consumes the one-shot debug flag), `debug_force_snatch()`
  (bypasses gate/roll, still requires matching held item; force-commands
  Eat/DrinkActivity).
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player(npc, player)`.
  Deliberately NOT routed through `grab_loose()` to keep that function's
  strict no-theft `is_held` guard intact; this is the one intentional
  gated exception.
- `scripts/npc/NPCBrain.gd` — EatActivity: new `_snatch_player` var,
  snatch check first in `enter()`, a `_tick`-time snatch branch
  (abandons if player's held item no longer matches), `done()` includes
  `_snatch_player == null`, `_reacquire_or_finish()` re-attempts the
  snatch before normal search. DrinkActivity: `enter()` picks a snatch
  target (`_mode = "snatch"`), `tick()` routes to new `_tick_snatch()`
  which hands off to normal `_tick_bottle()` mode on success.
- `scripts/ui/menus/AdminMenu.gd` — "Force Nearest NPC to Snatch Player
  Item" row + `_on_npc_force_snatch_pressed()` (nearest-to-player).
- `docs/systems/npc/README.md` — new "Relationship Snatch" subsection;
  Testing Checklist items 20-21.

## Dependencies / notes
- **Prerequisite** `NPC_GIVE_REAL_TRANSFER_AND_THEFT_FIX_PLAN.md` was
  NOT applied on disk before this (its `grab_loose()` `is_held` guard does
  NOT yet exist) — implemented as designed per user instruction anyway.
- **Player-side contract required end-to-end** (`PLAYER_SUBSYSTEM_SNATCH_CONTRACT.md`,
  separate Player subsystem file): `player.get_held_item()` and
  `player.on_item_snatched()`. All NPC-side callers guard these with
  `has_method()`, so this compiles and runs without them, but the snatch
  will not actually fire until those two Player methods exist.
- **AdminMenu.gd ownership flagged** in the plan (uncertain it belongs to
  the NPC instance) — applied since existing NPC debug rows live there.

---
---

# Handover — Give/Takeaway Bugfixes: Stuck Item + Undetectable NPC-Held Items (Aug 2026)

## What changed this session
Fixed two bugs reported after the initial Give/Takeaway implementation.

**Give stuck bug:** `_try_give_to_nearest_npc()` cleared the player's
`held_item`/bookkeeping unconditionally after a successful give, but
`receive_item_from_player()` only destroys single-serving items
(Dish/Produce) — FoodCan/WaterBottle survive with reduced charge, still
fully held. Clearing bookkeeping regardless left surviving cans/bottles
visually stuck (undroppable/unstorable/unusable, since every other
action gates on `held_item`). Fixed to only clear bookkeeping when
`is_instance_valid(item)` is false (i.e. it was actually destroyed).

**Takeaway silently broken:** root cause was a physics layer issue, not
GDScript logic. `PickupableItem.pickup()` sets `collision_layer = 2`
while held; `Player.tscn`'s `DetectArea` had no explicit
`collision_mask` and defaulted to layer 1 only, so it could never detect
NPC-held (layer 2) items regardless of the earlier `is_held` check
removals. Widened `DetectArea.collision_mask` to `3` (layer 1 | 2).
Added `body == held_item` self-detection guards to
`_try_add_nearest_to_basket()`/`_try_add_nearest_to_cookpot()` since the
wider mask means the player's own held item is now visible to those
scans too.

### Files modified
- `scripts/player/InteractionSystem.gd` — `_try_give_to_nearest_npc()`
  conditional bookkeeping clear; self-detection guards in
  `_try_add_nearest_to_basket()`/`_try_add_nearest_to_cookpot()`.
- `scenes/player/Player.tscn` — `DetectArea.collision_mask = 3`.
- `docs/systems/player/README.md` — bugfix follow-up appended to the
  existing NPC Give/Takeaway entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_BUGFIX_PLAN.md` for the
full 6-item checklist)

---

# Handover — Relationship Magnitude Rebalance (Aug 2026)

## What changed this session
- **NPC.gd**: `GIVE_RELATIONSHIP_BONUS` and `TAKEAWAY_RELATIONSHIP_PENALTY`
  halved (15.0 → 7.5, kept symmetric). `RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR`
  reduced 2.0 → 0.15 (~13x) — the original rate maxed a relationship out
  from ordinary cohabitation alone within ~2 in-game days; the new rate
  targets "Friendly" after ~100 days of realistic daily overlap, not
  "Close" within the first week.
- No mechanism changes — burnout, per-item/per-NPC repeat gating, band
  thresholds, and Sociability scaling are untouched, just the base
  numbers they operate on.

## Files Modified
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist
See `docs/systems/npc/README.md` Testing Checklist item 19 (renumbered
from the plan's "17" since the checklist already had items through 18).

---

# Handover — NPC Give/Takeaway Support in InteractionSystem.gd (Aug 2026)

## What changed this session
Player subsystem implemented the InteractionSystem.gd half of the NPC
Give/Takeaway feature, per a consolidated handoff from the NPC
subsystem. Give: holding a giveable item (dish/produce/can/bottle) near
an NPC shows `[E] Give <item> to <name>`; E calls
`NPC.receive_item_from_player()`. Takeaway: removed the CASE 2 `is_held`
prompt exclusion entirely (NPC-held items are now normal `[F] Pick up`
targets); `_try_pickup()` now looks up `NPCItemUser.find_holder()` before
reassigning `held_item` and calls `on_item_taken_by_player()` on the
losing NPC. All relationship/consequence/item-lifetime logic lives
NPC-side; this file only calls the contract methods and trusts their
return values.

### Files modified
- `scripts/player/InteractionSystem.gd` — Give prompt (CASE 1), Give
  dispatch (E-branch), `_find_nearest_npc()`/`_try_give_to_nearest_npc()`
  helpers, Takeaway `is_held` exclusion removed (CASE 2), Takeaway
  notify-on-grab in `_try_pickup()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_IMPLEMENTATION_PLAN.md`
for the full 6-item checklist)

---

# Handover — NPC Give: Multi-Charge Items (Aug 2026)

## What changed this session

- **NPCItemUser.gd**: `is_giveable()` widened to reuse `is_edible()`/
  `is_drinkable_bottle()` directly — now covers FoodCan and WaterBottle
  in addition to DishItem/FarmProduceItem.
- **NPC.gd**: `receive_item_from_player()` rewritten — per-(item, NPC)
  recipient tracking (`npc_gift_recipients` meta, an Array of npc_ids)
  replaces the earlier single global `npc_gift_used` flag. FoodCan/
  WaterBottle now take one bite/drink per gift and persist in the
  player's hand across multiple gifts (mirrors
  `NPCItemUser.eat_held_step()`'s exact per-type branching). A repeat
  gift of the same item to the same NPC still feeds them, just grants no
  further relationship reward; the same item can still boost different
  NPCs once each.
- Docs: `docs/systems/npc/README.md` — Give paragraph rewritten, Future
  Work item marked done, new Testing Checklist item.

## Files Modified
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist item 18.

---

# Handover — NPC Universal Takeaway + Gift Burnout/Anti-Repeat (Aug 2026)

## What changed this session

### Takeaway, unrestricted
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**;
  flagged for a later plan): would have removed the need-triggered `is_held`
  gate from the CASE 2 prompt loop and `_nearest_pickup_distance()` entirely,
  and dropped the gating condition in `_try_pickup()` (keeping its
  `NPCItemUser.find_holder()`/`on_item_taken_by_player()` notify call).
  Because this section was deferred, NPC-held items are still pickable only
  when need-triggered (Part 24 behavior) — the unrestricted-pickup portion
  of this pass is NOT live.
- **NPC.gd**: `on_item_taken_by_player()` now always clears `held_item`, but
  only applies the -15 relationship ding when `is_consuming_from_need()` was
  true at the moment of taking (evaluated before clearing). Verified
  `JobActivity`'s held_item references are all null-safe — a stolen job
  material can't crash, but the job silently completes without its effect
  (accepted quirk, see docs).

### Gift burnout + per-item marking
- **NPC.gd**: `gift_saturation` (0..1, +0.25/gift, decays to 0 over ~5
  game-days via `_tick_relationships()`), `GIFT_BONUS_FLOOR_MULT` (0.15x
  floor), applied as a multiplier on `GIVE_RELATIONSHIP_BONUS` in
  `receive_item_from_player()`. Each item can only produce one boost ever
  (`npc_gift_used` meta flag) — currently unreachable given Give's
  destroy-on-give V1 scope, forward-looking for multi-charge items later.
- F7 relationship visualizer now shows "Gift burnout: NN%" per NPC when
  above 0.

### Docs
`docs/systems/npc/README.md` — Give/Takeaway section updated for the
burnout/marking behavior and the narrowed relationship ding; Future Work
updated (multi-charge note + stolen-job-material quirk); two new Testing
Checklist items. Note the Takeaway paragraph describes the full
unrestricted-pickup behavior from deferred Section 2, which is not yet
live.

## Files Modified
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`
- ~~`scripts/player/InteractionSystem.gd`~~ ⚠️ Player subsystem — deferred
  (Section 2), expected in a later pass.

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 16–17 (gift
burnout). Item 16 (non-need takeaway) depends on the still-deferred
`InteractionSystem.gd` Section 2.

---

# Handover — NPC Give/Takeaway + F7 Relationship Visualizer (Aug 2026)

## What changed this session

### Give
- **NPC.gd**: `receive_item_from_player()` (V1 scope: DishItem/
  FarmProduceItem only), `GIVE_RELATIONSHIP_BONUS` (+15).
- **NPCItemUser.gd**: `is_giveable()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**;
  flagged for the later plan): new "[E] Give `<item>` to `<name>`" prompt
  block (mirrors Basket/Cooking Pot pattern) + dispatch, `_find_nearest_npc()`,
  `_try_give_to_nearest_npc()`. Deferred with the rest of section 5.

### Takeaway
- **NPC.gd**: `is_consuming_from_need()` (gated on the same 55.0 threshold
  Eat/DrinkActivity auto-trigger on), `on_item_taken_by_player()`,
  `TAKEAWAY_RELATIONSHIP_PENALTY` (-15).
- **NPCItemUser.gd**: `find_holder()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**):
  `_try_pickup()` and `_nearest_pickup_distance()` `is_held` carve-outs; the
  CASE 2 prompt-loop carve-out. Deferred with the rest of section 5.
  (Note: the latent gap this closes in `_try_pickup()` is likewise still open
  until that section lands.)

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
- `docs/systems/npc/README.md`
- ~~`scripts/player/InteractionSystem.gd`~~ ⚠️ Player subsystem — deferred
  (section 5), expected in a later pass.

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 13–15. Note items
13–14 (Give/Takeaway player prompts) depend on the still-deferred
`InteractionSystem.gd` section 5; the F7 visualizer (item 15) is fully
live now.

---

# Handover — Ghost Collision Regression Fix (Aug 2026)

## What changed this session

### Root cause — Ghost collision regression
The July "strip collision AFTER add_child" fix ran at the wrong tree level:
`GhostModelBuilder.strip_collision()` was called inside `_rebuild_ghost_mesh()`
**before** the ghost root entered the SceneTree. Since `add_child(real_inst)`
on an out-of-tree parent does **not** fire `_ready()`, the strip ran **before**
scripts' own `_ready()` ran — scripts that unconditionally set
`collision_layer = 5` in their `_ready()` silently re-enabled collision
on every ghost spawn. This is why Fix 2's strip "didn't take" — it ran at
the wrong lifecycle point.

**Consequences:** (1) Ghosts of every `PROCEDURAL_PREVIEW_SOURCES` tile
push the player/NPCs (live collision). (2) Grow lights always red/"space
occupied" — the ghost's own live collider sits exactly at the
`_is_position_occupied()` query position, so the ghost blocks itself.
Grow lights had no registry carve-out in `_is_position_occupied_for_tile()`
(unlike Purifier/Light/Shelving), so the physics query always ran for
them and always found the ghost's own collider at the query position.

### Fixes

**Fix 1 — Core: Reorder `_spawn_ghost()`** — `_spawn_ghost()` now:
1. Creates ghost root
2. Sets `visible = false` (prevents 1-frame flash)
2. **Adds ghost root to SceneTree** (`parent.add_child(_ghost)`)
3. **Then** calls `_rebuild_ghost_mesh()` → `build_real_instance()` →
   `strip_collision()` now runs AFTER `add_child(real_inst)` fires
   `_ready()`, so the strip sticks.

**Fix 2 — Hardening: Deferred re-strip + freed-node guard**
- `_rebuild_ghost_mesh()`: added `GhostModelBuilder.strip_collision.call_deferred(real_inst)`
  to catch any script that configures collision via `call_deferred` in
  its `_ready()`.
- `GhostModelBuilder.strip_collision()`: added `is_instance_valid(node)`
  guard so the deferred call is safe if the ghost was freed the same
  frame (tile switch / build-mode exit).

**Fix 3 — Grow Light bucket registry** — preview-only grow lights no
longer register into `GrowLight._bucket_registry`. Moved the
`_is_preview_only` guard **before** the `call_deferred("_register_bucket")`
call in `GrowLight._ready()` (same fix pattern as the chair ghost
invisibility bug).

### Files modified
- `scripts/world/build/GhostPreview.gd` — `_spawn_ghost()` reorder, deferred re-strip
- `scripts/world/build/GhostModelBuilder.gd` — `strip_collision()` freed-node guard
- `scripts/world/power/GrowLight.gd` — preview guard before bucket register
- `docs/systems/build/README.md` — `strip_collision()` bullet updated with
  precise lifecycle rule; Call graph updated with `_spawn_ghost()` order
- `docs/systems/farming/README.md` — note that preview-only grow lights
  no longer register into spatial bucket
- `HANDOVER.md` — this entry

### Verification checklist
1. Ghost collision gone — walk through any furniture ghost, no push.
2. Grow lights placeable — green over open floor, places correctly.
3. Occupancy still works — ghost red over existing object, green over open floor.
4. No flash/regression — rapid tile switching (Chair → Wall → Stove → Grow Light) shows no flash at origin.
5. Bucket fix — with a plant in a tray and NO real grow light, hover a grow-light ghost over tray — plant must NOT register as lit.

**Follow-up (Aug 2026):** a mis-ordered preview guard in `GrowLight._ready()` skipped `_build_fixture()` for preview instances, blanking the ghost and menu preview — fixed by moving the guard to sit after fixture construction, before side effects (groups, registration, power).

---

# Handover — NPC Names + Ask-About Relationship Dialogue (Aug 2026)

## What changed this session

### Names
- **NPC.gd**: `NPC_NAMES` (10-name pool), `_assign_random_name()`
  (collision-avoided against every live NPC), called from `_ready()` when
  `npc_name` is still its "Survivor" default. No persistence changes
  needed — `npc_name` was already saved.

### Ask About (relationship Q&A dialogue)
- **NPC.gd**: `get_relationship_dialogue_line(target_id)` (5 flavor-text
  pools keyed to `get_relationship_label()`), `get_other_npc_topics()`
  (every other live NPC, for building UI buttons).
- **NPCTalkMenuUI.gd**: new "ASK ABOUT" section revealed alongside
  dialogue/commands on Talk — "What do you think of me?" (player) + one
  button per other live NPC by name; answers render in the existing
  dialogue label. `PANEL_H` bumped 760 → 900.
- Docs: `docs/systems/npc/README.md` — new Names & Ask-About section,
  Relationships' dialogue Future Work item marked done (narrower scope),
  Responsibilities bullets updated, new Testing Checklist items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `docs/systems/npc/README.md`

---

# Handover — NPC Relationships Groundwork + Sociability Wiring (Aug 2026)

## What changed this session

### Relationships — data model + proximity baseline
- **NPC.gd**: new stable `npc_id` identity (auto-assigned, persisted,
  collision-safe across save/load via `NPC._register_id()`); new
  `relationships` Dictionary (directional, NPC's own perspective, keyed by
  target `npc_id` or `"player"`, -100..100); `get_relationship()`,
  `get_relationship_label()` (Hostile/Cold/Neutral/Friendly/Close),
  `_adjust_relationship()` (single mutation point — applies sociability
  multiplier + clamp); baseline driver this pass is passive proximity
  (`_tick_relationships()`, 4m XZ range, 5s cadence alongside mood/
  irritability).
- **Sociability trait wired** (previously generated/displayed only):
  `_sociability_trait_mult()`, 0.5x–1.5x, scales every relationship delta.
- **NPCDebug.gd**: `log_relationship_tick()`; `_dump_one()` now includes
  each NPC's relationships with labels.
- **MainWorld.gd**: `_get_npcs_for_save()`/`_restore_npcs()` persist
  `npc_id` and `relationships`.
- Docs: `docs/systems/npc/README.md` — new Relationships section, updated
  Personality/Non-responsibilities sections, new Testing Checklist items.

### Explicitly not done this pass (see README's Relationships → Future Work)
Item giving/taking, crisis-help behavior, command-compliance influence,
personal-space avoidance scaling, gift-dropping, relationship-aware
dialogue, Player→NPC reciprocal value.

---

# Handover — Build Mode Ownership Expansion, Furniture, Wall Draw Mode, Ghost Model System (Aug 2026)

## What changed this session

### Role expansion
This Claude instance's scope expanded from Furniture-only to ALL Build
Mode / Construct Menu object placement (spawning, ghost preview,
wall/floor snapping, height/spacing, general placement refinement) across
every object type.

### Furniture: Small/Medium Table, Chair, Poster
- New `scripts/world/furniture/Table.gd`, `Chair.gd`, `Poster.gd` — see
  `docs/systems/build/README.md`'s Furniture section for details.
- Chair sit/stand mechanic: `Player.gd` gained `seated_chair` state;
  `InteractionSystem.gd`'s `_try_interact()`/`_update_prompt()` both check
  it first, before any proximity scan, so E always means "stand" while
  seated regardless of what else is nearby; any WASD press while seated
  also stands the player up and lets movement continue immediately
  ("walk out of the chair").

### Wall Draw Mode — click-drag-click stretched walls
Full/Half/Quarter Wall placement rewritten from single-click discrete 1m
segments to one dynamically-stretched mesh per wall, free 360° angle,
grid-snapped endpoints, Q/E height-tier cycling, RMB/ESC exit. See
`docs/systems/build/README.md`'s Wall Draw Mode section. Went through
several fix rounds this session: floating half/quarter tiers (tier-aware
placement Y), bounds-check false positives on long walls (half-extent was
incorrectly scaled by run length), ghost sunk to half-height (a
`global_position` assignment was clobbering the mesh's own floor-flush
offset), minimum length matching the idle sliver instead of a full 1m cell.

### Ghost Model Master System — real-shaped previews, universal facing arrow
New `scripts/world/build/GhostModelBuilder.gd` — see
`docs/systems/build/README.md`'s Ghost Model System section for the full
writeup. Replaced generic box/rectangle ghost previews with translucent
real-model ghosts for every object already registered for a Construct-menu
preview, and gave every placeable object a facing arrow (previously only a
few hand-picked tiles had one).

Two rounds of follow-up fixes after the initial rollout:
- **Chair ghost was invisible** — `Chair.gd`'s `_ready()` returned before
  `_build_mesh()` when `_is_preview_only` was set (pre-existing bug, not
  introduced by the ghost system — the Construct-menu spinning preview was
  almost certainly blank too, before this).
- **Ghosts had live collision, pushed the player** — root cause was a
  lifecycle-order bug: collision was stripped *before* `add_child()`, i.e.
  before `_ready()` had run, so scripts that set `collision_layer`
  unconditionally in `_ready()` (most of them) silently undid the strip.
  Fixed by moving the strip to run after `add_child()`.
- **Grow Light placement was broken** (always red, "Space is already
  occupied," intermittently fixable by rapid mouse movement/clicking) —
  traced to the same collision bug: `_is_position_occupied()`'s physics
  query (`collision_mask = 1`) was detecting the ghost's own still-live
  collision shape at its own query position. Same fix resolved both.
- **Facing arrow was backward on most objects** — rather than continuing
  to add a hand-tuned override per newly-reported tile (Chair, Dispenser,
  Test Sink, then Battery ×3, Stove, Tables, Trays), recognized the
  pattern (every default-using tile was backward; only hand-tuned ones
  were correct) and flipped the *default* itself (180°), removing the
  now-redundant individual overrides.
- **Wall Lights failed to place in player-expanded bunker areas** despite
  a green ghost — `TILE_LIGHT` had no entry in `_tile_half_extents()`,
  inheriting the generic 0.40 floor-object fallback for the confirm-time
  bunker-bounds check, oversized for a thin wall-flush fixture. Same fix
  already applied to `TILE_POSTER` earlier in the session, now applied to
  Light too.

---

# Handover — NPC Basics + Cooking Fixes + UI Unification + NPC Basics (Aug 2026)

## What changed this session

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: New `CharacterBody3D` NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

### UI Unification — Pause Menu + Graphics Settings Panel (Jul 2026)

- **UIKit.gd**: Added shared menu builders (`build_modal_backdrop()`, `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`), font-size constants (`FONT_SIZE_TITLE=20`, `FONT_SIZE_SECTION=11`, `FONT_SIZE_BODY=13`), `MENU_PANEL_W=380`
- **PauseMenuUI.gd**: Complete rewrite using UIKit builders; fixed UTF-8 encoding (removed BOM/garbled comments); unified colors with NEUTRAL theme; confirm dialog now matches main panel gray
- **GraphicsSettingsPanel.gd**: Complete rewrite using UIKit builders; **FIXED off-center bug** (`build_centered_panel()` with fixed size); row labels now use `make_row_label()` with proper font/color; unified panel width (380), fonts, button styles with PauseMenuUI

### Fix: Removed invalid `custom_maximum_size` from `build_centered_panel()`

Control/Panel has no `custom_maximum_size` property in Godot 4 — that line always errored. The fixed anchor offsets + `custom_minimum_size` already fully lock the panel's size.

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: CharacterBody3D NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

---

## Files Modified

### NPC Basics
- `scripts/npc/NPC.gd` — new file
- `scripts/ui/npc/NPCTalkMenuUI.gd` — new file
- `scenes/npc/NPC.tscn` — new file
- `scripts/world/core/MainWorld.gd` — added `get_cleared_cell_bounds_world()`
- `scripts/ui/menus/AdminMenu.gd` — added "Spawn NPC" row + callback

### Cooking Fixes (Part 1/2)
- `scripts/world/items/CookingPot.gd` — added `get_use_prompt()`
- `scripts/world/cooking/Stove.gd` — added `_grid_connected` tracking, grid-aware `set_powered()`/`on_interact()`/`get_interact_prompt()`

### UI Unification
- `scripts/ui/common/UIKit.gd` — added `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`, font-size constants, `MENU_PANEL_W=380`
- `scripts/ui/menus/PauseMenuUI.gd` — complete rewrite using UIKit builders
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite using UIKit builders; fixed off-center bug
- `scripts/ui/common/UIKit.gd` — removed invalid `custom_maximum_size` from `build_centered_panel()`

### Admin Menu Additions (Part A)
- `scripts/ui/menus/AdminMenu.gd` — added `world_node`, `ADMIN_CASH_STEP`, `PRODUCE_SPAWN_HEIGHT`, new `_row_defs` rows, `_format_thousands()`, `_on_add_cash_pressed()`, `_on_hookup_output_double_pressed()`, `_spawn_produce()` + 3 callbacks

### Admin Spawn Menu Removal (Part B)
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid` — deleted
- `MainWorld.gd` — removed F10 handler, `_admin_menu` var, `_toggle_admin_spawn_menu()`
- `PauseMenuUI.gd` — layer comment fixed
- `PickupableItem.gd` — spawn helper comment updated
- `FarmingShopHelper.gd` — "Single source of truth" comment updated
- `AdminMenu.gd` — docstring F10 reference removed; layer comment fixed
- Docs updated across `PROJECT_SUMMARY.md`, `docs/systems/ui/README.md`, `docs/systems/build/README.md`, `docs/systems/water/README.md`, `docs/systems/farming/README.md`
- `architecture.json` regenerated

---

## Files Created
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `assets/shaders/grunge_overlay.gdshader`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`

---

## Files Deleted
- `scripts/ui/hud/StatusBars.gd` + `.uid`
- `scripts/ui/hud/CircleFill.gd` + `.uid`
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid`

---

## Next Up
- Real gameplay status effects still need to be wired into `StatusEffectsContainer.add_effect()` — currently F7 test-only.
- Cooking System Part 2: Cook timer + Dish item (Part G from `COOKING_SYSTEM_PLAN_PART3.md`)
- `BuildModeHUD.gd`'s buttons/tabs/interactions are now in UI Claude's scope per Brannon's Jul 2026 note — not yet started, rest of `BuildModeHUD.gd` stays with the non-UI Claude instance.
- Worn-look shader defaults (`grit_strength = 0.14`, `grit_scale = 26.0`) are a first pass — confirm they read right in actual play, not just the single reviewed screenshot.
- Admin Menu Part A: economy/water-tier/produce-spawn cheats (already done in this session)
- Admin Menu Part B: F10 Admin Spawn Menu removal + docs (already done in this session)
- NPC Basics (already done in this session)
- Cooking Fixes Part 1/2 (already done in this session)
- UI Unification (already done in this session)

---

## Verification Checklist (for Brannon's in-editor test)
1. **NPC**: F7 → Spawn NPC → NPC wanders, collides with walls/furniture, [E] Talk → popup → Talk → "..." → Close
2. **Cooking**: Pot near stove → [E] Place prompt appears; Stove requires grid connection; power loss auto-shuts-off; prompt shows "Stove Not Connected"
3. **UI**: Pause Menu (ESC) centered; Graphics Settings (F7→Settings) centered; row labels use project font; confirm dialog gray matches main panel
3. **Admin Menu (F7)**: 11 rows, 6 sections; +$100k Cash updates HUD; Hookup Output x2 increments tier (warns at max); Spawn Potato/Blueberry/Tomato drops items with pop-in
4. F10 does nothing (no menu, no errors)
5. F7 Admin Menu: 11 rows, 6 sections; all original buttons (Power, Time, Water, Economy, Farming, Status) + new rows work