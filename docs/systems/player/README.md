# Player System

**Read this before opening `Player.gd`, `PlayerStats.gd`, or `InteractionSystem.gd`.**
Only open the actual source for the specific function you're changing.

## Purpose
Owns the player character's movement/stamina, survival needs + game clock, and
all pickup/drop/store/scroll interaction logic. These three scripts are
separate but tightly coupled (all live under `scripts/player/`, all wired
together by `MainWorld`).

## Responsibilities
- `Player.gd`: WASD movement (camera-relative), sprint + stamina drain/regen,
  facing rotation, the `interacted` input signal, and the movement-lock used
  by the pause menu.
- `PlayerStats.gd`: food/water/sleep/health drain over a real-time-to-game-time
  clock, starvation/dehydration health damage, the `H:MM AM/PM` game clock +
  day counter, and save/load support for elapsed time.
- `InteractionSystem.gd` (~686 lines): the ONLY place pickup/drop/store/scroll
  logic lives. Owns `held_item`, inventory slot activation/deactivation, and
  the floating interact prompt (built each frame from whatever's held or
  nearby). E is a pure instant tap (use/interact fires on press, no hold
  behavior); G is the separate instant store/put-away key (see Jul 2026 entry
  below).

## Non-responsibilities
- **Does not own inventory slot storage itself** — `InventoryManager.gd`
  (`scripts/ui/inventory/`, see `docs/systems/ui/README.md`) holds the actual
  4-slot array; `InteractionSystem` only calls its `activate_item`/
  `deactivate_item`/`add_item`/`remove_item` API.
- **Does not own item pickup/drop physics logic itself** — each item script
  (`PickupItem.gd` base + its subclasses, see `docs/systems/furniture-items/`)
  implements its own `pickup()`/`drop()`/`place()`; `InteractionSystem` only
  calls those methods and tracks which slot/hand an item currently occupies.
- **Does not own HUD rendering** — `InteractionSystem` calls
  `prompt.set_prompts(...)`/`hide_prompt()` and `inventory_hud.set_selected(...)`,
  it never touches Control nodes directly (see `docs/systems/ui/README.md`).
- **Does not own build-mode input** — both `Player._handle_interaction_input()`
  and `InteractionSystem._unhandled_input()` early-return whenever
  `build_mode_active` is true; `BuildModeController` owns all input then.

## Files
| File | Lines | Role |
|---|---|---|
| `Player.gd` | ~170 | `CharacterBody3D` — movement, sprint/stamina, facing, movement-lock, seated-chair input, NPC-facing Give/Snatch contract |
| `PlayerStats.gd` | ~200 | Survival needs (food/water/sleep/health) + game clock |
| `InteractionSystem.gd` | ~1,245 | Pickup/drop/store/scroll, interact prompt builder, NPC Give/Takeaway/Snatch transfer, shelf/basket/cookpot E-dispatch fairness |

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

## Signals produced
| File | Signal | Params | Fires when |
|---|---|---|---|
| `Player.gd` | `interacted` | — | Player presses the "interact" action (only used when NOT holding an item — see `InteractionSystem`, which owns the actual E-key logic once an item's in hand) |
| `Player.gd` | `stamina_changed` | `new_value: float` | Every physics frame stamina changes |
| `PlayerStats.gd` | `food_changed` / `water_changed` / `sleep_changed` / `health_changed` | `value: float` | Every `_process()` tick (needs) or on `replenish_*()` |
| `PlayerStats.gd` | `time_changed` | `hour, minute, is_pm, display` | Game clock minute ticks over |
| `PlayerStats.gd` | `day_changed` | `day: int` | Game day rolls over |

`InteractionSystem.gd` produces no signals of its own — it reaches directly
into whatever it's holding (`held_item.knocked_out`, `held_item.picked_up`,
etc.) and calls methods on `prompt`/`inventory_hud` instead of emitting.

## Signals/events consumed
- `InteractionSystem` connects to `detect_area.body_entered/body_exited`
  (its own `Area3D`) to maintain `_tracked_bodies` — the authoritative set of
  nearby interactables (StaticBody3D nodes are tracked separately in
  `_static_in_range` since Jolt's `Area3D` signals never fire for them).
- `InteractionSystem` connects to each held item's `knocked_out` signal
  (`_on_item_knocked_out`) while it's held, to detect the item being yanked
  out of the player's hand (obstruction/distance check owned by the item
  itself, e.g. `WaterBottle.gd`'s `KNOCK_DISTANCE`/`KNOCK_LINGER_TIME`).

## Ownership
None of these three are autoloads. `Player.tscn`'s root node runs
`Player.gd`; `InteractionSystem.gd` is a child node under the player scene
(`@onready var player: CharacterBody3D = get_parent()`). `PlayerStats` is
instantiated/wired by `MainWorld` and found elsewhere via
`get_tree().get_first_node_in_group("player_stats")`.

## Persistence
`PlayerStats.get_elapsed()`/`set_elapsed()` back the `game_elapsed`
`SaveManager` field (see `docs/systems/world-core/README.md`) — saving the
single raw elapsed-seconds float is sufficient; day/hour/minute recompute
automatically next frame. `player_position` is also a registered
`SaveManager` field but its getter/setter live on `MainWorld`, not `Player`
itself. **Not persisted:** stamina, food/water/sleep/health values,
held/inventory item state (tracked gap, not scheduled — see
`docs/systems/world-core/README.md` Known tradeoffs).

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

## Common edits
- **New player stat/need:** add the field + drain rate + signal to
  `PlayerStats.gd` following the `food`/`water`/`sleep` pattern; add a
  `replenish_*()` method; wire `HUD.gd` to the new signal (see
  `docs/systems/ui/README.md`).
- **New item interaction verb (beyond use/store/pickup/drop):** add the input
  branch in `InteractionSystem._unhandled_input()`. E and G are both plain
  one-shot `is_action_pressed()` taps — there is no tap-vs-hold
  disambiguation anymore. If a new verb needs continuous per-frame behavior
  while a key is held (like `FuelCan.refuel_tick()` or `WaterBottle.
  bottle_refill_tick()`), follow the `_is_holding_e` +
  `_tick_continuous_refuel()`/`_tick_continuous_bottle_refill()` pattern
  instead (Jul 2026 — both ticks now run side by side in `_process()`; a
  held item only reacts to whichever tick its own `has_method()` check
  matches).
- **Store/put-away key (Jul 2026):** store is bound to `store_item` (G), not
  E. The old "hold E to store" hold-and-progress-bar mechanic was retired
  entirely in favor of an instant, no-progress-bar G tap — see
  `_store_hold_t`/`_use_pending`/`_tick_store_hold()` removal in the source.
- **New prompt line for an item/object:** implement
  `get_use_prompt()`/`get_interact_prompt()`/`get_f_prompt()`/`get_e_prompt()`
  on the item/object itself (duck-typed via `has_method()`) —
  `InteractionSystem._update_prompt()` already calls these generically, no
  central registry to update.
- **Prompt cap + E-target fix (Jul 2026):** Case 2 (empty-handed) prompts are
  capped at `MAX_VISIBLE_PROMPTS` (3) - candidates are sorted by distance to
  the player first, then sliced to the closest 3, so a crowded room never
  shows more than 3 floating prompts at once. Separately, `_try_interact()`
  now filters BOTH passes (RigidBody3D overlap + StaticBody3D group scan) to
  only consider bodies where `has_method("on_interact")` is true before
  comparing distances. Some items (e.g. `FuelCan`) sit in the `"interactable"`
  group only so their `get_prompt_text()`/`get_use_prompt()` lines show up
  while held - they have no `on_interact()` of their own. Previously they
  could still win the closest-node comparison and silently swallow the E
  press (nothing implements `on_interact()` on the "closest" node -> no
  fallback to the next-closest thing that actually responds). Any new
  interactable-only item that intentionally has no `on_interact()` will
  correctly be skipped and never block E for something further away.
- **NPC Give/Takeaway support (Aug 2026):** `InteractionSystem` gained a
  Give prompt/dispatch (CASE 1, mirrors the Basket/Cooking-Pot pattern —
  `NPCItemUser.is_giveable(held_item)` gates a `[E] Give <item> to
  <name>` prompt over each nearby NPC, `_find_nearest_npc()`/
  `_try_give_to_nearest_npc()` handle dispatch) and Takeaway (the CASE 2
  `is_held` exclusion was removed entirely — NPC-held items are now
  normal `[F] Pick up` targets, and `_try_pickup()` looks up
  `NPCItemUser.find_holder()` before reassigning `held_item` so it can
  call `on_item_taken_by_player()` on the NPC that lost the item). All
  relationship/consequence logic and item-lifetime handling (destroy vs.
  reduced-charge) is entirely owned by `NPC.gd`/`NPCItemUser.gd` on the
  NPC subsystem side — `InteractionSystem` just calls
  `receive_item_from_player()`/`on_item_taken_by_player()` and trusts the
  return value.
  **Bugfix follow-up (Aug 2026):** two gaps in the original spec, both
  fixed. (1) `_try_give_to_nearest_npc()` was clearing `held_item` even
  when the given item survives the call (FoodCan/WaterBottle aren't
  destroyed by `receive_item_from_player()`, only Dish/Produce are) —
  now only clears bookkeeping when `is_instance_valid(item)` is false.
  (2) Takeaway was silently unreachable — `DetectArea` (`Player.tscn`)
  had no explicit `collision_mask` and defaulted to layer 1 only, so it
  could never see layer-2 (currently-held) bodies regardless of any
  GDScript `is_held` check; `collision_mask` widened to `3` (1|2) fixes
  this. Widening the mask also means `DetectArea` now sees the player's
own held item while CASE 1 scans for a different target — guarded with
   `if body == held_item: continue` in `_try_add_nearest_to_basket()` and
   `_try_add_nearest_to_cookpot()`.
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
- **Give/Snatch inventory-slot clear fix (Aug 2026):** Both
  `_try_give_to_nearest_npc()`'s destroyed-item cleanup and
  `clear_held_item_external()` (Snatch) previously only nulled local
  `held_item`/`_held_from_slot` bookkeeping, never touching
  `InventoryManager.slots[]` — so an item pulled from an inventory slot
  and given/snatched away kept showing in that slot forever. Both now
  route through a new shared `_release_item_to_npc()` helper, which
  calls a new `InventoryManager.clear_slot()` when the item came from a
  slot. Deliberately does NOT use `InventoryManager.remove_item()` —
  that method is documented/implemented as world-drop-only (forces
  collision_layer back to 1, re-adds the `"pickup"` group, repositions
  via `drop()`), which would fight an NPC's already-completed
  `item.pickup(npc.hold_point)` reassignment on Snatch, or error on an
  already-freed item on a destroyed-item Give. `clear_slot()` only nulls
  the slot array entry — it's additive to `InventoryManager.gd`
  (UI/menu-subsystem-owned; flagged for their visibility, not a change
  to any of their existing methods).
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
- **Bulky held-item head-clearance arc (Aug 2026, `PickupableItem.gd`
  — flagged: `scripts/world/items/`, not one of the three core files,
  but the hold-follow mechanic itself is Player-subsystem scope).**
  Fixes Crate/Can Case/Water Case visibly getting stuck against the
  player's head during a fast 180° turn while held. Root cause: held
  items are real `RigidBody3D`s with `collision_mask = 1`, the same
  layer as the player's own `CapsuleShape3D` — during a fast turn, the
  straight-line chase path from one side of the player to the other
  passes through that capsule, and large enough items physically
  collide with it instead of passing through cleanly. Gated by a
  lazily-computed real collision-shape radius
  (`_carry_bulk_radius`, `BULKY_CARRY_RADIUS_THRESHOLD = 0.30`) rather
  than a hardcoded item list or mass — mass doesn't correlate (Basket/
  Cooking Pot are heavier by mass than Can Case/Water Case but have a
  smaller footprint, and are correctly unaffected). While a bulky
  item's actual position and its target are far enough apart
  angularly (`CARRY_ARC_START_ANGLE_DEG`), the CHASE target's height
  (never the true hold point used for the knockout check) ramps
  upward continuously, driving the physics body up and over the
  player's capsule instead of through it, and back down as the item
  catches up — one continuous formula, no state machine.
- **`get_held_item()` validity guard (Aug 2026).** Was a bare
  passthrough to `InteractionSystem.held_item` with no check — if that
  field ever ends up pointing at a freed object without going through
  the normal drop/give cleanup, any NPC-side caller crashed on
  "previously freed instance." Now self-heals the same way
  `InteractionSystem._update_prompt()`'s existing guard already handles
  this (see that function, "Guard: held_item freed externally"):
  validates with `is_instance_valid()`, and clears both `held_item` and
  `_held_from_slot` (not just the former) before returning. Investigated
  whether build-mode deconstruct is actually the upstream cause per the
  bug report's suggestion — `_try_deconstruct()` only operates on
  `_placed_objects` entries, which a currently-held item is never a
  member of, so that path doesn't appear able to reach a held item
  directly; not conclusively resolved, flagged as a possible Furniture/
  Build-Mode-thread lead (  `eject_all_items()` on deconstructed
  containers) rather than chased further here.
- **Storage-reject fallback to drop (Aug 2026,
  `LightStorage.gd`/`Shelving.gd` — flagged: `scripts/world/furniture/`,
  not one of the three core files, but the F-dispatch fallback these
  hook into is `InteractionSystem._quick_drop()`).** Previously,
  pressing F to store a held item into a full or size-ineligible
  Dresser/End Table/Shelf just showed a warning (or, for a full Shelf,
  nothing at all) and left the item stuck in the player's hand — no
  fallback to the normal drop F already does when nothing's in range.
  Both `LightStorage._try_store_held()` and `Shelving._try_place_item()`
  now call `_interaction_system._quick_drop()` directly in their
  rejection branches after showing the warning, reusing the exact same
  drop path rather than adding new drop logic. Matters in practice
  because bunkers get tight with furniture placed close together —
  without this, standing near a full/ineligible storage object could
  leave a player unable to drop (or, transitively, pick anything else
  up) without first walking out of that storage object's ~2.5 m reach.

## Basket Prompt Fix (Jul 2026)
- **Root cause**: `_update_prompt()` split into CASE 1 (holding item, returns
  early) and CASE 2 (empty-handed). The "[E] Add to Basket" logic was placed
  in CASE 2 behind a `held_item != null` check that can never be true there
  (dead code). This is why nothing ever showed above water bottles/food cans
  while holding the basket — the only code that would show it was unreachable
  by construction.
- **Fix (3 parts)**:
  1. `Basket.get_interact_prompt()` added → shows "[G] Open Basket" while
     held (CASE 1 already calls this via `has_method("get_interact_prompt")`).
  2. Moved "[E] Add to Basket" logic from CASE 2 into CASE 1 (uses
     `_tracked_bodies`), so it runs while holding basket.
  3. Removed dead basket-check code from CASE 2.
- **Verification**: Pick up basket → "[G] Open Basket" appears. Walk near
  Water Bottle/Food Can/produce while holding basket → "[E] Add to Basket"
  appears over that item. Press E → item stashes. Fuel Can/Seed packets show
  no prompt (not `basket_storable`), E does nothing (matches original plan's
  intended behavior, now actually working).

**Also fixed since (Jul 2026):**
- **G/E to close BasketUI**: `BasketUI._unhandled_input()` only recognized
  `"ui_cancel"` (Escape) and `"interact"` (E) as close triggers — G
  (`"store_item"`) fell through to the `elif` branch and did nothing. Added
  `"store_item"` alongside the other two. No `InteractionSystem.gd` changes
  needed — it already returns immediately whenever
  `_basket_ui_open()`/`_shelf_ui_open()` is true ("ShelfUI/BasketUI owns all
  input while open"), so `BasketUI` was always the sole handler; it just
  wasn't listening for G.
- **Basket stays upright while held**: every other held item keeps whatever
  tilt it had at pickup (`PickupableItem._physics_process()` only zeroes
  `angular_velocity`, never corrects orientation — this is deliberate/correct
  for those items). `Basket.gd` now overrides `_physics_process()`, calls
  `super()` first so position-follow/knockout/grace-timer logic is untouched,
  then forces `global_transform.basis = Basis.IDENTITY` (the basket's authored
  resting orientation) every physics tick while `is_held`. Hard snap, not a
  spring/lerp — no wobble.
- **Softened upright snap + CTRL manual-upright hold (Aug 2026,
  `PickupableItem.gd`/`Basket.gd`/`CookingPot.gd`/`Flashlight.gd` —
  flagged: `scripts/world/items/`, not one of the three core files, but
  the hold-follow mechanic itself is Player-subsystem scope).** Basket/
  Cooking Pot's always-on upright lock (never lean while carried) was an
  instant hard snap (`global_transform.basis = Basis.IDENTITY` outright,
  every physics tick) — replaced with a new shared
  `PickupableItem.slerp_to_upright(delta, speed)` using spherical
  interpolation (`Basis.slerp()`, exponential-decay convergence via
  `UPRIGHT_SLERP_SPEED = 10.0`, ~99% converged in ~⅓ second), same
  visual result but eased rather than snapped. New feature layered on
  the same primitive: holding **CTRL** applies this to ANY held item
  (new `allow_manual_upright: bool` on `PickupableItem`, default true,
  overridden `false` only on `Flashlight.gd` — its rotation is its aim
  direction, forcing it upright would fight the point of holding one).
  Basket/Cooking Pot are excluded from the CTRL branch specifically
  (checked via their existing `is_basket_container`/`is_cookpot_container`
  duck-type markers) since their own override already keeps them
  upright unconditionally — redundant, not broken, to call it twice, so
  skipped for cleanliness. Deliberately uses `Input.is_key_pressed
  (KEY_CTRL)` polled directly in `_physics_process()` rather than adding
  a new Input Map action — avoids hand-transcribing a `project.godot`
  `physical_keycode` value with no way to verify it outside the editor.
  Releasing CTRL needs no cleanup code: the function holds no state
  between calls, so the item simply stops moving and holds its last
  orientation.
  (Correction, same session: `Flashlight.gd`'s exclusion was initially
  written as a fresh `var allow_manual_upright: bool = false`
  declaration, which is a GDScript compile error — subclasses can't
  redeclare a parent class's `var`, even to override its default. Fixed
  to a plain assignment inside `_ready()` instead.)
- **Can Case / Water Case: removed the 0.75 downscale (Aug 2026,
  `CanCase.gd`/`WaterCase.gd` — flagged: `scripts/world/items/`, not
  one of the three core files).** Both previously scaled themselves
  down to 0.75 on `_ready()`; removed after the CTRL manual-upright
  slerp (which targets `Basis.IDENTITY`, scale `1.0`) was found to drag
  their scale up toward `1.0` as an unintended side effect while CTRL
  was held (`Basis.slerp()` interpolates a decomposed scale component
  alongside rotation — not something `slerp_to_upright()`'s rotation-only
  intent accounted for). Brannon preferred the resulting larger look, so
  made it permanent instead of drifting there conditionally. Confirmed
  no effect on the bulky-carry-arc gating or the `NavigationObstacle3D`
  avoidance radius for either item — both are computed from each
  collision shape's own local transform, never from the `RigidBody3D`'s
  own `scale` property, so this change doesn't alter either.
- **Shelf E-priority fairness + grow-light-over-tray + Focus Mode
  plumbing (Aug 2026).** Fixed a second shelf E-priority bug distinct
  from the held-item fix earlier this session: a nearby shelf was
  winning E unconditionally over OTHER world interactables too (e.g. a
  closer generator) whenever empty-handed. Now fairly compared via the
  same "peek both, smaller wins" pattern already used for stove-pot/
  ready-dish, through a new shared `_nearest_generic_interactable()`
  (also absorbs `_try_interact()`'s own scan and
  `_nearest_interact_distance()`, previously two near-duplicate copies
  of the same two-pass RigidBody3D/StaticBody3D scan). Added a narrow
  grow-light-over-tray override inside that same shared scan — a
  `GrowLight` sitting directly above its `FarmingTray` was otherwise
  functionally unreachable since the tray is almost always physically
  closer; only overrides when a `FarmingTray` specifically would
  otherwise win, every other interactable pair still resolves by fair
  distance. New `_resolve_current_e_target()` (empty-handed only) gives
  a UI-thread Focus Mode feature a read-only peek at exactly what E
  would fire, sharing the same underlying scan so the two can never
  drift apart — tagged onto CASE 2 prompt entries via a new
  `"is_e_target"` key.
- **Water Hookup unconditional Focus Mode priority (Aug 2026,
  `WaterHookup.gd` — flagged: `scripts/world/water/`, not one of the
  three core files; corrected same session — see below).** Mounted high
  on the wall, so it's almost always farther than lower-mounted wall
  objects sharing the same wall and would rarely win on raw distance
  alone. Given a `"water_hookup"` duck-type marker group (mirrors
  `"grow_light"`/`"farming_tray"`). **Correction:** initially implemented
  inside `_nearest_generic_interactable()`, which at the time was shared
  by both real `E` dispatch and Focus Mode's target resolution — but
  Focus Mode had since been rewritten to compute its own
  `is_focus_target` independently (see `_update_prompt()`'s "Aug 2026 v2"
  comment) and no longer calls that function at all, so the override was
  silently affecting only plain `E` presses, never Focus Mode — the
  opposite of the intent. Moved to `_update_prompt()`'s `focus_idx`
  computation instead (mirrors the existing grow-light-over-tray swap
  already there), which is the thing that's actually gated behind
  `Input.is_key_pressed(KEY_CTRL)`. Plain `E` presses (`_try_interact()`)
  are back to fair-distance-only, unaffected by Water Hookup's presence.

## Forbidden edits
- **Don't let `held_item` bypass the `_held_from_slot` convention.**
  `_held_from_slot == -1` means "picked up fresh from the world" — every
  other piece of pickup/drop/store logic (dual follow-speeds, knockout
  checks, culling) keys off this. A new code path that sets `held_item`
  directly without also setting `_held_from_slot` correctly will desync the
  inventory HUD.
- **Don't add a second global light/stat dimmer or clock driver** — there is
  exactly one `PlayerStats` instance (found via group `"player_stats"|`) and
  one game clock; don't create a second timer elsewhere.

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

## Extension points
- New item types just need to implement the same duck-typed method surface
  existing items already do (see `docs/systems/furniture-items/README.md`'s
  Public API list) — `InteractionSystem` never special-cases a specific item
  class by name.
- New full-screen modals that should block player input: call
  `Player.set_movement_locked(true/false)` the same way `PauseMenuUI` does,
  and gate `InteractionSystem` the same way `build_mode_active`/`shelf_ui`
  already are (a new `Node`-typed "blocks input" flag if a third modal type
  is ever added, rather than hardcoding a 3rd special case inline).
