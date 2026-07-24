# Farming System (Jul 2026)

**Read this before opening any `scripts/world/farming/*`,
`scripts/world/power/GrowLight.gd`, or Farming-related
`scripts/world/items/*` file.** Only open the actual source for the specific
function you're changing.

## Purpose
Trays + soil + seeds + grow lights → produce, sold/bought via a dedicated
Farming toolbar tool and a Farming Construct-menu category. Reuses the Water
and Power systems' existing consumer-registration patterns end to end —
**no `FarmingManager` singleton exists or is needed** (see §0.1 below).

Terminology note: this is **Farming**, not "hydroponics." Trays hold real
soil (a physical `Bag of Soil` item is poured into them) — there is no
nutrient-solution/hydroponic framing anywhere in this system.

## 0.1 — Why no central "FarmingManager"
The water/power systems have managers because they solve a *shared graph*
(pipe/wire topology, multi-consumer allocation). Farming has no graph — each
`FarmingTray` is an independent `WaterManager` demand consumer and each
`GrowLight` is an independent `PowerManager` consumer, exactly like
`HeavyConsumerTest.gd`. There is nothing for a new manager to own.

## 0.2 — Three distinct "Farming" UI surfaces (deliberate, not a bug)
1. **Toolbar tool** ("Farming", next to Construct/Deconstruct/Move/
   Duplicate/Undo/Wire/Pipe) — buys and spawns *carryable items* (Bag of
   Soil, Seeds) above the player's head. No ghost-preview placement at all —
   see `FarmingShopHelper.gd`.
2. **Construct-menu category** ("Farming", alongside Structure/Furniture/
   Lighting/Power/Water) — places the two tray tiles via the normal
   ghost-preview/`spawn_structure()` flow.
3. Grow lights are **not** in either of the above — they live in Construct →
   **Lighting**, since structurally they're just another light fixture to
   the build system.

## Responsibilities
- **Trays** (`FarmingTray.gd`, `scripts/world/farming/`) — single (1×1,
  $150, `TILE_TRAY_SINGLE`) or double (2×1, $275, `TILE_TRAY_DOUBLE`).
  Registers as a `WaterManager` "endpoint" demand consumer (fixed 1000/2000
  mL/day, tier-adjustable `priority`, default 3) exactly like
  `WaterTestSink`/`WaterDispenser`. **Water quality is deliberately
  irrelevant** — only `get_water_fraction()` (received / demand, 0..1)
  matters, fed into plant growth every hour. Per-cell state:
  `soil_filled[]` / `planted_type[]` / `plant_refs[]`.
- **Plants** (`FarmPlant.gd`) — one instance per planted cell, ticks once per
  in-game hour (`PlayerStats._seconds_per_game_hour`, same compressed-clock
  convention as `WaterHookup`'s quality decay). Growth:
  `growth_per_hour = light_speed * water_fraction / (grow_days * 24)`.
  Health: -5%/hr whenever `water_fraction == 0`, and an independent -5%/hr
  once unlit for more than 24 consecutive hours (both can apply the same
  hour). 0% health kills the plant (wasted seed, no harvest, cell reverts to
  soil-filled/empty). Health does NOT gate readiness — a low-health plant
  still shows READY once `progress >= 1.0`. **READY plants harvest instantly
  on E** — no info-panel step. Per-species `grow_days`/produce look lives in
  `PlantDatabase.gd` (Tomato = 10 days, Onion = 20 days — confirmed with
  Brannon, not the plan's own 10/10 placeholder default).
- **Grow lights** (`GrowLight.gd`, `scripts/world/power/` — NOT
  `scripts/world/farming/`, since structurally it's a `PowerManager`
  consumer device like `WallLight`) — `tier` export ("normal"/"pro"),
  75W/100W, both default priority 3. Auto-connects to the nearest wire node
  within 0.75m exactly like `WallLight._auto_connect_to_nearby_wires()`.
  Growth contract read by `FarmPlant` via a **pure XZ position match** (no
  parent/child relationship, no registration handshake):
  `get_active_growth_speed() -> float` (0.0 unpowered/shed, 0.5 normal,
  1.0 pro). Not wall-snapped, not required to sit above a tray — placeable
  anywhere in the bunker, fixed height `GROW_LIGHT_PLACEMENT_Y = 2.75`
  (below the 2.9m pipe layer, above wall-light height).
- **Items** (`scripts/world/items/`) — `BagOfSoilItem.gd` (on_use() fills
  the nearest tray's first open soil cell, drops an `EmptyBagItem.gd` near
  it), `SeedItem.gd` (one script, `seed_type` export; on_use() plants into
  the nearest tray's first open plantable cell), `FarmProduceItem.gd` (one
  script, `produce_type` export; 1-charge food, fully consumed in one
  `on_use()` — deliberately NOT `FoodCan.gd`'s multi-bite charge model).
- **UI** (`scripts/ui/farming/`) — `FarmingTrayUI.gd` (connection status,
  demand vs. received, priority ◄►) and `PlantInfoUI.gd` (name, Health %,
  READY/NOT READY) — both UIKit `Domain.NEUTRAL` hand-drawn panels, same
  convention as `WaterDispenserUI.gd`/`GeneratorInspectUI.gd`.
- **Build mode** — `FarmingShopHelper.gd` (`scripts/world/build/`) owns the
  Farming toolbar tool's buy → spawn-near-player logic entirely separately
  from `spawn_structure()`/ghost-preview (no grid-snap cursor at all).
  `BuildModeHUD.gd`'s two-level submenu machinery is shared between
  Construct (`CATEGORIES`) and the Farming shop (`FARMING_SHOP_ITEMS`) via
  `_current_categories()`/`_submenu_source` — see that file's own comments.

## Interaction flow (bare-handed E vs. held-item E)
- **Bare-handed E on a tray needing soil** → INFO-level error banner ("Tray
  needs soil"), same `InventoryHUD.show_error_message()` convention every
  other hard error in this project uses.
- **Bare-handed E on a fully-soiled tray** → opens `FarmingTrayUI`.
- **E while holding a Bag of Soil / Seed** → `on_use()` on the held item
  (InteractionSystem's existing `held_item.on_use()` dispatch — no changes
  needed there).
- **E on the plant itself** → harvest instantly if READY, else opens
  `PlantInfoUI`.

## Known gaps (explicitly out of scope for this pass)
- **Persistence**: trays/grow lights themselves save/restore fine as
  ordinary `BuildModeController._placed_objects` entries, but per-cell
  `soil_filled`/`planted_type`/plant `progress`/`health` state is NOT wired
  into the save `extra` dict — a reload shows trays present but empty/
  unsoiled. Same category of gap this project already carries for Purifier
  filter state; add to the future save/load overhaul list.
- **Ten polish items** (wilting tint, soil-fill VFX/sound, real
  `OmniLight3D` grow-light illumination, harvest pop tween, connectable-dot
  color consistency, low-health toast, seed/bag visual distinction beyond
  the current flatter/lighter EmptyBagItem silhouette, double-tray seam,
  grow-light ghost floor decal, `*_DEBUG` readout) — deliberately deferred
  to a later pass per the implementation plan's own §10.
