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
  signals to `SleepOverlay` â€” see `docs/systems/ui/README.md`) and the
  shelf family — `Shelving.gd` base (~800 lines â€” item storage slots,
  stacking, retrieval to hand/inventory) plus `SmallShelf.gd`/`LargeShelf.gd`
  subclasses (6 and 15 slots respectively).

## Non-responsibilities
- **Does not own the actual pickup/drop/store STATE MACHINE** â€” that's
  `InteractionSystem.gd`'s job. Items only implement the methods
  `InteractionSystem` calls; they never track "am I currently held" logic
  beyond their own `is_held`/`from_inventory` flags used for
  visual/physics state.
- **Does not own inventory slot storage** â€” `InventoryManager.gd`
  (`docs/systems/ui/README.md`) holds the actual 4-slot array. `Shelving.gd`
  has its OWN separate slot system (shelf storage, not inventory) â€” the two
  are unrelated storage systems that happen to share item scripts.
- **Does not own power-grid registration logic** for anything except
  `HeavyConsumerTest.gd` (a deliberate load-testing consumer device, not a
  "real" item) â€” actual power devices (generators, breakers, batteries,
  lights, terminals) live in `docs/systems/power/README.md`.

## Files
| File | Lines | Role |
|---|---|---|
| `items/PickupableItem.gd` | ~153 | **NEW (Jul 2026)** Base class for all physics-based pickup items â€” eliminates ~800 lines of duplicated scaffolding (pickup/drop/place/knockout/culling/hold-follow physics) that previously lived inline in every item script. All 12 items now extend this.
| `items/PickupItem.gd` | ~65 | Legacy minimal base pickup contract â€” some items extend behavior inline instead of subclassing this directly. Being phased out in favor of `PickupableItem.gd`.
| `items/WaterBottle.gd` | ~265 | Continuous mL-fill + blended quality drinkable (750mL cap, Jul 2026 rework â€” replaced the old fixed 2-sip model); also refills continuously near a `WaterDispenser` via `bottle_refill_tick(delta)` (see `InteractionSystem._tick_continuous_bottle_refill()`); `charge_changed` signal for HUD badge |
| `items/FoodCan.gd` | ~215 | Similar to WaterBottle, food-based |
| `items/FuelCan.gd` | ~260 | Continuous-refuel item â€” `refuel_tick(delta)` called every frame E is held near a generator (see `InteractionSystem._tick_continuous_refuel()`) |
| `items/Flashlight.gd` | ~460 | Battery-powered light, `on_use()` toggles on/off, dust-mote beam VFX (see `docs/systems/environment/README.md`) |
| `items/TestCrate.gd` | ~150 | Simple non-storable pickup (always drops, never goes in inventory) |
| `items/WaterCase.gd` / `items/CanCase.gd` | ~215 each | Multi-unit cases (shelf-stackable, see `Shelving.gd`'s case-stacking constants). **Jul 2026 fix:** Ejected items (`FoodCan`/`WaterBottle`) now spawn with `freeze=true` + `call_deferred("_unfreeze_after_spawn")` (one-frame kinematic freeze) instead of `freeze=false` + deferred `freeze=false` â€” prevented floor fall-through on spawn. Removed the now-dead `_unfreeze_after_spawn()` stubs from `FoodCan.gd`/`WaterBottle.gd`.
| `items/HeavyConsumerTest.gd` | ~280 | StaticBody3D load-test device â€” registers/unregisters as a power consumer via `PowerManager`, not a real pickup item |
| `furniture/Bed.gd` | ~45 | Sleep interaction trigger â€” `sleep_requested`/`wake_requested` signals |
| `furniture/Shelving.gd` | ~800 | Shelf family base (Medium 10 slots; Small/Large subclass it): slot markers, item stacking/placement, retrieval to hand or inventory |
| `furniture/SmallShelf.gd` | ~15 | Shelf-family variant: 6 slots as 3 tiers × 2, TILE 34, $45 — overrides `_init()` only |
| `furniture/LargeShelf.gd` | ~15 | Shelf-family variant: 15 slots as 5 tiers × 3, TILE 35, $180 — overrides `_init()` only |
| `furniture/LightStorage.gd` | ~300 | **NEW (Aug 2026)** Shared base for hidden-children light-item storage furniture (End Table / Dresser). Implements the StorageUI 4-method contract (see `docs/systems/ui/README.md`) + the `"shelving"`-group E/F duck-type contract; fixed-size `stored` slot array; `eject_all_items()` reparents hidden children to the world root on deconstruct/build-undo |
| `furniture/EndTable.gd` | ~95 | **NEW (Aug 2026)** 1×1 side table, capacity 2 light storage (drawer), TILE 32, $60 |
| `furniture/Dresser.gd` | ~95 | **NEW (Aug 2026)** 2×1 dresser, capacity 6 light storage (2×3 drawers), TILE 33, $150 |

## Public API
**Shared item contract** (duck-typed â€” `InteractionSystem`/`Shelving` call
these via `has_method()`, no common base class is strictly required, though
`PickupItem.gd` provides the reference implementation):
`pickup(hold_point: Node3D)`, `drop(world_parent: Node3D, drop_position:
Vector3)`, `place(world_parent, place_position, place_rotation)`,
`get_display_name() -> String`, `get_prompt_text() -> String`,
`get_use_prompt() -> String` (optional â€” omit if item has no "use" verb),
`get_interact_prompt() -> String` (optional), `on_use()` (optional, called on
E-tap), `set_player(p: Node3D)` (optional â€” only `Flashlight.gd` needs the
player ref, for facing direction).

**Shared item vars convention** (see `docs/systems/power/README.md`'s sibling
pattern â€” this one predates it): `from_inventory: bool` (set by
`InteractionSystem`, disables the world-knockout check while true),
`follow_speed`/`inv_follow_speed: float` (dual hand-follow speeds â€” 18
world-held / 40 inventory-held, inventory snaps instantly through turns),
`pickup_grace: float` (0.6s grace before knockout checks start after
pickup). Signals: `picked_up()`, `dropped()`, `knocked_out()` (fires when
yanked too far from the player while world-held), `charge_changed()`
(`WaterBottle`/`FoodCan`/`Flashlight` â€” HUD badge; `WaterBottle`'s badge is
fill%/quality via its own `get_bottle_badge_info()` contract, `FoodCan`'s is
the generic bites-remaining fallback â€” see `docs/systems/ui/README.md`'s
`InventoryHUD._draw()` badge dispatch).

**Shelf family** — `Shelving` (`class_name Shelving`, extends `StaticBody3D`)
is the base class; `SmallShelf` and `LargeShelf` are ~15-line subclasses that
override `_init()` only (dimensions, `slots_per_tier`, `shelf_y`). All
storage/stacking/retrieval/NPC/StorageUI/eject logic is inherited unchanged,
and the procedural mesh scales to each variant's own dimensions.

| Variant     | Script            | Slots | Layout   | Tile | Price |
|-------------|-------------------|-------|----------|------|-------|
| Small Shelf | `SmallShelf.gd`   | 6     | 3 tiers × 2 | 34 | $45 |
| Medium Shelf| `Shelving.gd`     | 10    | 5 tiers × 2 | 3  | $75 |
| Large Shelf | `LargeShelf.gd`   | 15    | 5 tiers × 3 | 35 | $180 |

**Dimensions (Aug 2026 — resized so Test Crate, the largest carriable item,
fits on every tier):** Medium defines the base values — tier spacing **0.60**
(interior clear height 0.582 vs the crate's 0.48 H), bottom tier lowered to
**0.12**, unit depth **0.85** (vs the crate's 0.73 D), unit height **3.55**.
Large inherits all of these unchanged (no override). Small has its own 3-tier
values at the same 0.60 spacing / 0.12 floor (`shelf_y [0.12, 0.72, 1.32]`,
`unit_h 2.35`); it inherits the depth fix from the base `unit_d` with no
override.

**Large Shelf columns (Aug 2026):** Large overrides the base `multi_col_spacing`
to **0.62** (= TestCrate width 0.54 + 0.08 clearance) and widens `unit_w` to
**2.00** so 3 crates sit snug side-by-side with no overlap — columns at x
= ±0.62/0, crate edges at ±0.89, 0.08 gap between neighbours, 0.11 margin
inside the frame. `multi_col_spacing` is a base export (default 0.30, the old
hardcoded value) used only by the N-column marker path.

**Item pivot sink pattern (Aug 2026):** `TestCrate`'s mesh uses a centered
pivot (bottom plate at -0.231 below the item origin), so marker-based
placement sinks ~0.23m into the shelf platform without a compensating lift
`_place_item_in_slot()`'s `extra_lift`. The crate now gets `extra_lift = 0.18`.
`CanCase`/`WaterCase` are `.tscn`-based models that may share the centered-pivot
convention — watch for the same symptom if their upright standing (below)
looks sunken in-editor, and fix with the same per-type `extra_lift` pattern.

**Cases now stand upright (Aug 2026):** CanCase/WaterCase no longer lay flat
in a 2×2 grid. Both stand upright (`_stack_rotation` returns `(0, 90, 0)` —
Y=90 keeps the label facing the player). CanCase stacks 2 vertically per slot
(`shelf_stack_limit` 2; `_stack_offset` lifts idx 1 by `CASE_H_UPRIGHT` +
gap, provisional 0.34 — tune in-editor); WaterCase is 1 per slot
(`shelf_stack_limit` 1, no offset).

API (base class, inherited by all variants): `set_player_in_range(in_range:
bool)`, `get_f_prompt/get_e_prompt/get_interact_prompt() -> String`,
`on_f_interact()` / `on_e_interact()` / `on_interact()`,
`retrieve_to_carry(slot_idx, isys)`, `retrieve_to_inventory(slot_idx, inv)`,
`eject_all_items()`, `is_slot_full_for(item)`, `slot_count(slot_idx)`,
`slot_top_item(slot_idx)`, `slot_is_empty(slot_idx)`.
Signals: `item_placed(slot_index, item)`, `item_retrieved(slot_index, item)`.

- Slot count = `shelf_y.size() * slots_per_tier`, sized in `_ready()`. Slot
  markers, `get_ui_config()`, and the mesh are all parametric — 2-column
  marker math and the 10-slot UI `display_order` are reproduced exactly for
  Medium, and generalize to N columns/tiers for the variants.
- Shelf E-open now yields to a strictly-closer held-item E target
  (Basket stash / Cooking Pot stove-or-stash / NPC give) — see Player
  subsystem's `docs/systems/player/README.md` for the fairness rule.
- **Facing (Aug 2026):** the shelf mesh is procedural (no GLB), generated
  Z-symmetric so it meets the project's +Z-front convention without any
  model rotation — slot markers (z=0), collision, and stack offsets are all
  Z-symmetric. See `docs/systems/build/README.md`'s "Facing convention".
- **Carry-retrieval safe spawn (Aug 2026):** `retrieve_to_carry()` now
  repositions the item onto the player (`Shelving.carry_spawn_position()`,
  `isys.global_position + (0, 1.0, 0)` — chest height) BEFORE calling
  `pickup()`. Previously the item was left at its shelf-slot position, so
  for a shelf backed against a wall that meant starting on the far/wall
  side of the unit and being physics-chased to the player straight through
  it — the tunnel-through-wall/floor bug. The player's own position is
  guaranteed clear of solid geometry (their own collision occupies it), so
  no shelf/furniture/wall can be in the way; the short remaining gap to the
  hold point is closed by `PickupableItem._physics_process()`'s existing
  per-frame chase, preserving the natural pop-then-settle feel.
- **Corner post height now derived from `shelf_y` (Aug 2026):** the post
  formula in `_build_mesh()` was previously `unit_h - 0.2375`, tuned
  against the pre-resize 0.45 tier spacing and never recomputed when the
  crate-fit pass raised spacing to 0.60 (and `unit_h` independently to
  3.55) — so posts drifted to reaching ~0.57 m above the top shelf.
  Posts now extend exactly 1/6 of the tier spacing above the TOP shelf
  (0.10 m at current 0.60 spacing), derived live from `shelf_y` so it
  tracks future spacing changes automatically. **`unit_h` deliberately
  stays taller than the visible posts** — it still sizes the collision
  box (headroom for a crate-height item on the top shelf) and the
  E-prompt height; that gap between visual post height and unit_h-based
  collision height is intentional, not a leftover bug.


**`Bed`** (extends `StaticBody3D`): `on_interact()`, `get_prompt_text() ->
String`, `set_player_in_range(in_range)`, `set_sleeping(sleeping: bool)`.
Signals: `sleep_requested()`, `wake_requested()` â€” consumed by
`SleepOverlay.gd` (`docs/systems/ui/README.md`).

**`LightStorage`** (`class_name LightStorage`, extends `StaticBody3D`):
shared base for furniture with hidden internal storage of LIGHT items
(End Table capacity 2, Dresser capacity 6). Eligibility = exactly the
`"inventory_item"` group (same set as pocket inventory) â€” crates/cases
etc. get no F prompt and are rejected with a HUD soft warning. No
stacking, no slot geometry, no visible stored meshes.

- **Storage model:** fixed-size `stored` slot array (length `capacity`,
  null = empty), initialized in `_ready()` via `stored.resize(capacity)`.
  Indices stay stable when a middle slot is emptied (StorageUI addresses
  slots positionally). Storing fills the first null slot.
- **UI:** opens the SHARED `StorageUI` (`_storage_ui.open(self)`) via the
  4-method contract (`get_ui_config` / `get_slot_display` /
  `take_for_carry` / `take_for_inventory`) â€” zero UI code of its own.
  `get_ui_config()` is built from `grid_cols`/`grid_rows`/`row_labels`
  exports set by the subclass in `_init()`.
- **`"shelving"` group** = the generic E/F container contract
  (`on_e_interact`/`on_f_interact`/`get_e_prompt`/`get_f_prompt`/
  `get_prompt_world_pos`) that InteractionSystem duck-types against, NOT
  "is literally a shelf". MainWorld's `_setup_storage_ui()` injects
  `_storage_ui`/`_interaction_system` into every member that declares
  those properties; BuildModeController's spawn branch does the same for
  mid-session placement.
- **Hidden-children gotcha:** stored items are frozen, invisible,
  collision-off children of the furniture node. Any retrieval path must
  reparent to the world root + restore visibility before handing off;
  `eject_all_items()` does this and is REQUIRED (deconstruct/build-undo
  duck-call it â€” without it the stored items are silently freed with the
  node). No metadata layer-saving: restoration uses canonical values.
- **Carry-retrieval safe spawn (Aug 2026):** `take_for_carry()` overrides
  `_reparent_to_world()`'s furniture-center placement
  (`global_position + (0, 0.6, 0)` — fine for `take_for_inventory()`, which
  goes straight into the pocket, but the furniture center can still be
  near/behind a wall the unit is pushed against) with the same
  `Shelving.carry_spawn_position()` player-side point before `pickup()`, so
  the item is never physics-chased from a wall-side start into the player.
  See the Shelf family section above for the full reasoning.
- **`EndTable.gd` / `Dresser.gd`:** mesh-only subclasses; `_init()` sets
  capacity / display_name / prompt_height / grid_cols / grid_rows /
  row_labels. Both expose `static func build_ghost_mesh()` for the build
  ghost + procedural preview.

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
saved via `SaveManager` â€” a fresh load resets all of it (same known gap as
the power system â€” see `docs/systems/world-core/README.md` Persistence).

## Common edits
- **New pickup item type:** implement the shared item contract above
  (Public API), copy the `from_inventory`/dual-follow-speed/culling pattern
  from `WaterBottle.gd` (the cleanest reference implementation) rather than
  `PickupItem.gd` if you need world-vs-inventory dual behavior â€” most real
  items in this repo diverge from the minimal `PickupItem.gd` base to add
  that pattern inline. Add a new file in `scripts/world/items/`, don't bolt
  it onto an existing item script.
- **New `PickupableItem` subclass:** create `scripts/world/items/YourItem.gd` extending `PickupableItem`. Override the 7 hook methods listed above. Only add item-specific physics/state in `_ready()` â€” the base handles follow-physics, knockout, pickup/drop/place, culling, and group registration.
- **New shelf-stackable item:** add its stacking offset/rotation logic to
  `Shelving._stack_offset()`/`_stack_rotation()` and a case in
  `_get_item_type()`/`_get_stack_limit()` â€” don't create a second shelf
  storage system.
- **New furniture interaction (beyond Bed's sleep):** follow `Bed.gd`'s
  minimal `on_interact()`/`get_prompt_text()`/`set_player_in_range()` shape
  for a new `StaticBody3D` furniture piece.
- Storage-full/too-big rejection (Dresser/End Table/Shelf) now falls
  back to a normal drop instead of blocking F entirely — see Player
  subsystem's `docs/systems/player/README.md` for the fallback mechanism
  (`InteractionSystem._quick_drop()`).
- **Aug 2026 fix**: `LightStorage.gd` only joined the `"shelving"` group,
  never `"interactable"` (unlike `Shelving.gd`, which joins both) — this
  meant Dresser/End Table never showed an empty-handed prompt at all, they
  fell into a gap between `InteractionSystem`'s two candidate-gathering
  passes. Fixed with one `add_to_group("interactable")` call in
  `LightStorage._ready()`. Also fixed `get_f_prompt()` returning `""`
  (nothing) when full — now returns `"<name> Full"`, matching
  `Shelving.gd`'s existing `"[F] Shelf full"` pattern. Full detail in
  `docs/systems/ui/README.md`'s "Storage UI Unification" section.

## StorageUI Contract Config Updates (Aug 2026)
UI-thread pass touching `get_ui_config()` on every `StorageUI`-contract
object (`Basket.gd`, `Shelving.gd`, `LightStorage.gd` and its subclasses
`Dresser.gd`/`EndTable.gd`): `primary_button_icon` values changed from
literal glyph strings to icon-texture lookup keys (`"carry"`/`"drop"`),
and the `row_labels` config key/export was removed entirely (row-label
text no longer renders anywhere). See
`docs/systems/ui/README.md`'s "Storage UI Icon + Row Label Redesign" for
the full change — this note exists so a furniture-thread reader isn't
surprised by the config value change if they touch these files next.

## Forbidden edits
- **Don't skip the `from_inventory` flag when adding a new item.** Every
  item needs it set correctly by `InteractionSystem` (world pickup vs.
  inventory activation) or its knockout-distance check will misfire.
- **Don't give `HeavyConsumerTest.gd` a `pickup()` â€” it's a placed
  StaticBody3D power-load device, not a pickup item; despite living in
  `items/` for historical reasons, it belongs conceptually with
  `docs/systems/power/README.md`'s consumer devices.**

## Known tradeoffs / tech debt
- No automated tests.
- Item/shelf/furniture state isn't saved (see Persistence).
- `Shelving.gd` (~890 lines) is the largest file in this system and mixes
  mesh-building, slot markers, stacking math, and retrieval logic â€” a
  plausible future split candidate (e.g. extract stacking math into an
  `_owner`-pattern helper) but not currently scheduled.
- `HeavyConsumerTest.gd` living in `scripts/world/items/` instead of
  `scripts/world/power/` is a folder-organization inconsistency (it's really
  a power-system test device) â€” noted here rather than moved, since moving
  it isn't a "new feature" that would normally trigger a reorg per the
  standing folder-hygiene rule.

## Extension points
- Any new item needing continuous-frame interaction (like `FuelCan`'s
  `refuel_tick()`) should follow that same duck-typed
  `has_method("refuel_tick")` pattern rather than adding a new special case
  to `InteractionSystem._process()`.
- Farming System (Jul 2026) added 4 new pickup items â€” `BagOfSoilItem.gd`,
  `EmptyBagItem.gd`, `SeedItem.gd`, `FarmProduceItem.gd` â€” all following this
  same duck-typed contract with zero `InteractionSystem.gd` changes.
`FarmProduceItem.gd` deliberately does NOT copy `FoodCan.gd`'s multi-bite
  charge system (1-charge, fully consumed in one `on_use()`); it copies only
  `FoodCan`'s physics/pickup/drop/knockout scaffolding. See
  `docs/systems/farming/README.md`.

**Also:** `TestCrate.gd` / `FuelCan.gd` — also go through `FarmingShopHelper.
spawn_scene_settled()` (see `docs/systems/build/README.md`) for their Shop-purchase
spawn; `continuous_cd = true` set on both `.tscn` files as tunneling insurance.

