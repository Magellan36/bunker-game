# Furniture / Items System

**Read this before opening any `scripts/world/furniture/*` or
`scripts/world/items/*` file.** Only open the actual source for the specific
item/behavior you're changing.

## Purpose
Every pickup-able item (water bottles, food cans, fuel cans, crates, cases,
flashlight) and every piece of interactable furniture (bed, shelving unit).
These are the "things the player can pick up, use, or interact with" as
opposed to build-mode-placeable power devices (`docs/systems/power/README.md`)
or the environment itself (`docs/systems/environment/README.md`).

## Responsibilities
- **Items** (`scripts/world/items/`): implement the pickup/drop/place contract
  (see Public API) so `InteractionSystem.gd` (`docs/systems/player/README.md`)
  can hold/store/drop them generically without knowing the concrete class.
  Each item also owns its own use-case logic (drinking a `WaterBottle`,
  refueling with `FuelCan`, toggling `Flashlight`, registering
  `HeavyConsumerTest` as a power consumer for load-testing).
- **Furniture** (`scripts/world/furniture/`): `Bed.gd` (sleep interaction,
  signals to `SleepOverlay` — see `docs/systems/ui/README.md`) and
  `Shelving.gd` (~890 lines — item storage slots, stacking, retrieval to
  hand/inventory).

## Non-responsibilities
- **Does not own the actual pickup/drop/store STATE MACHINE** — that's
  `InteractionSystem.gd`'s job. Items only implement the methods
  `InteractionSystem` calls; they never track "am I currently held" logic
  beyond their own `is_held`/`from_inventory` flags used for
  visual/physics state.
- **Does not own inventory slot storage** — `InventoryManager.gd`
  (`docs/systems/ui/README.md`) holds the actual 4-slot array. `Shelving.gd`
  has its OWN separate slot system (shelf storage, not inventory) — the two
  are unrelated storage systems that happen to share item scripts.
- **Does not own power-grid registration logic** for anything except
  `HeavyConsumerTest.gd` (a deliberate load-testing consumer device, not a
  "real" item) — actual power devices (generators, breakers, batteries,
  lights, terminals) live in `docs/systems/power/README.md`.

## Files
| File | Lines | Role |
|---|---|---|
| `items/PickupItem.gd` | ~65 | Minimal base pickup contract (`pickup`/`drop`/`place`) — some items extend behavior inline instead of subclassing this directly (see below) |
| `items/WaterBottle.gd` | ~265 | Continuous mL-fill + blended quality drinkable (750mL cap, Jul 2026 rework — replaced the old fixed 2-sip model); also refills continuously near a `WaterDispenser` via `bottle_refill_tick(delta)` (see `InteractionSystem._tick_continuous_bottle_refill()`); `charge_changed` signal for HUD badge |
| `items/FoodCan.gd` | ~215 | Similar to WaterBottle, food-based |
| `items/FuelCan.gd` | ~260 | Continuous-refuel item — `refuel_tick(delta)` called every frame E is held near a generator (see `InteractionSystem._tick_continuous_refuel()`) |
| `items/Flashlight.gd` | ~460 | Battery-powered light, `on_use()` toggles on/off, dust-mote beam VFX (see `docs/systems/environment/README.md`) |
| `items/TestCrate.gd` | ~150 | Simple non-storable pickup (always drops, never goes in inventory) |
| `items/WaterCase.gd` / `items/CanCase.gd` | ~215 each | Multi-unit cases (shelf-stackable, see `Shelving.gd`'s case-stacking constants) |
| `items/HeavyConsumerTest.gd` | ~280 | StaticBody3D load-test device — registers/unregisters as a power consumer via `PowerManager`, not a real pickup item |
| `furniture/Bed.gd` | ~45 | Sleep interaction trigger — `sleep_requested`/`wake_requested` signals |
| `furniture/Shelving.gd` | ~890 | Shelf storage: slot markers, item stacking/placement, retrieval to hand or inventory |

## Public API
**Shared item contract** (duck-typed — `InteractionSystem`/`Shelving` call
these via `has_method()`, no common base class is strictly required, though
`PickupItem.gd` provides the reference implementation):
`pickup(hold_point: Node3D)`, `drop(world_parent: Node3D, drop_position:
Vector3)`, `place(world_parent, place_position, place_rotation)`,
`get_display_name() -> String`, `get_prompt_text() -> String`,
`get_use_prompt() -> String` (optional — omit if item has no "use" verb),
`get_interact_prompt() -> String` (optional), `on_use()` (optional, called on
E-tap), `set_player(p: Node3D)` (optional — only `Flashlight.gd` needs the
player ref, for facing direction).

**Shared item vars convention** (see `docs/systems/power/README.md`'s sibling
pattern — this one predates it): `from_inventory: bool` (set by
`InteractionSystem`, disables the world-knockout check while true),
`follow_speed`/`inv_follow_speed: float` (dual hand-follow speeds — 18
world-held / 40 inventory-held, inventory snaps instantly through turns),
`pickup_grace: float` (0.6s grace before knockout checks start after
pickup). Signals: `picked_up()`, `dropped()`, `knocked_out()` (fires when
yanked too far from the player while world-held), `charge_changed()`
(`WaterBottle`/`FoodCan`/`Flashlight` — HUD badge; `WaterBottle`'s badge is
fill%/quality via its own `get_bottle_badge_info()` contract, `FoodCan`'s is
the generic bites-remaining fallback — see `docs/systems/ui/README.md`'s
`InventoryHUD._draw()` badge dispatch).

**`Shelving`** (`class_name Shelving`, extends `StaticBody3D`):
`set_player_in_range(in_range: bool)`, `get_f_prompt/get_e_prompt/
get_interact_prompt() -> String`, `on_f_interact()` / `on_e_interact()` /
`on_interact()`, `retrieve_to_carry(slot_idx, isys)`, `retrieve_to_inventory
(slot_idx, inv)`, `eject_all_items()`, `is_slot_full_for(item)`,
`slot_count(slot_idx)`, `slot_top_item(slot_idx)`, `slot_is_empty(slot_idx)`.
Signals: `item_placed(slot_index, item)`, `item_retrieved(slot_index, item)`.

**`Bed`** (extends `StaticBody3D`): `on_interact()`, `get_prompt_text() ->
String`, `set_player_in_range(in_range)`, `set_sleeping(sleeping: bool)`.
Signals: `sleep_requested()`, `wake_requested()` — consumed by
`SleepOverlay.gd` (`docs/systems/ui/README.md`).

## Signals/events consumed
- `InteractionSystem` connects to every held item's `knocked_out` signal
  while held (see `docs/systems/player/README.md`).
- `Shelving.gd` resolves `InteractionSystem` at runtime via
  `_resolve_interaction_system()`/`_find_node_by_class()` (group/tree walk,
  not a signal) to call back into it for retrieve-to-carry.

## Ownership
None of these are autoloads. Items are scene instances spawned by
`BunkerPregen.gd` (starting bunker loot, see `docs/systems/environment/`),
`BuildModeController` (build-menu placeable items like `TestCrate`), or
`Shelving.gd`'s own retrieval methods. `Bed`/`Shelving` are placed directly
in the pregen bunker scene or via build mode.

## Persistence
**None currently.** Item positions/inventory contents/shelf contents are not
saved via `SaveManager` — a fresh load resets all of it (same known gap as
the power system — see `docs/systems/world-core/README.md` Persistence).

## Common edits
- **New pickup item type:** implement the shared item contract above
  (Public API), copy the `from_inventory`/dual-follow-speed/culling pattern
  from `WaterBottle.gd` (the cleanest reference implementation) rather than
  `PickupItem.gd` if you need world-vs-inventory dual behavior — most real
  items in this repo diverge from the minimal `PickupItem.gd` base to add
  that pattern inline. Add a new file in `scripts/world/items/`, don't bolt
  it onto an existing item script.
- **New shelf-stackable item:** add its stacking offset/rotation logic to
  `Shelving._stack_offset()`/`_stack_rotation()` and a case in
  `_get_item_type()`/`_get_stack_limit()` — don't create a second shelf
  storage system.
- **New furniture interaction (beyond Bed's sleep):** follow `Bed.gd`'s
  minimal `on_interact()`/`get_prompt_text()`/`set_player_in_range()` shape
  for a new `StaticBody3D` furniture piece.

## Forbidden edits
- **Don't skip the `from_inventory` flag when adding a new item.** Every
  item needs it set correctly by `InteractionSystem` (world pickup vs.
  inventory activation) or its knockout-distance check will misfire.
- **Don't give `HeavyConsumerTest.gd` a `pickup()` — it's a placed
  StaticBody3D power-load device, not a pickup item; despite living in
  `items/` for historical reasons, it belongs conceptually with
  `docs/systems/power/README.md`'s consumer devices.**

## Known tradeoffs / tech debt
- No automated tests.
- Item/shelf/furniture state isn't saved (see Persistence).
- `Shelving.gd` (~890 lines) is the largest file in this system and mixes
  mesh-building, slot markers, stacking math, and retrieval logic — a
  plausible future split candidate (e.g. extract stacking math into an
  `_owner`-pattern helper) but not currently scheduled.
- `HeavyConsumerTest.gd` living in `scripts/world/items/` instead of
  `scripts/world/power/` is a folder-organization inconsistency (it's really
  a power-system test device) — noted here rather than moved, since moving
  it isn't a "new feature" that would normally trigger a reorg per the
  standing folder-hygiene rule.

## Extension points
- Any new item needing continuous-frame interaction (like `FuelCan`'s
  `refuel_tick()`) should follow that same duck-typed
  `has_method("refuel_tick")` pattern rather than adding a new special case
  to `InteractionSystem._process()`.
- Farming System (Jul 2026) added 4 new pickup items — `BagOfSoilItem.gd`,
  `EmptyBagItem.gd`, `SeedItem.gd`, `FarmProduceItem.gd` — all following this
  same duck-typed contract with zero `InteractionSystem.gd` changes.
  `FarmProduceItem.gd` deliberately does NOT copy `FoodCan.gd`'s multi-bite
  charge system (1-charge, fully consumed in one `on_use()`); it copies only
  `FoodCan`'s physics/pickup/drop/knockout scaffolding. See
  `docs/systems/farming/README.md`.
