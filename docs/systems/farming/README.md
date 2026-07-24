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
  Growth contract read by `FarmPlant` via a **nearest-light-within-radius
  match** (no parent/child relationship, no registration handshake):
  `get_active_growth_speed() -> float` (0.0 unpowered/shed, 0.5 normal,
  1.0 pro). Not wall-snapped, not required to sit above a tray — placeable
  anywhere in the bunker, fixed height `GROW_LIGHT_PLACEMENT_Y = 2.625`
  (Polish Plan Group 0 item 20: derived as `WALL_HEIGHT_M * 7.0/8.0`, now
  sitting slightly *below* the 2.9m pipe layer — was `2.75` pre-revision,
  visual-only change). 4 thin unlit dark-grey `CylinderMesh` corner support
  wires run from the fixture up to the 3.0m ceiling
  (`WIRE_LENGTH = WALL_HEIGHT_M * 1.0/8.0 = 0.375m`, both constants live in
  `GrowLight.gd`/`BuildModeController.gd` mirroring each other, same
  "two independent constants, same value" pattern `WaterPipeDrawMode.
  WATER_CEILING_Y` already documents).
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

## Performance (Polish Plan Group 6, items 13 & 14)
- **Water lookup (item 13)** — `FarmingTray._process()` no longer calls
  `WaterManager.get_received_rate_mL()` directly per-tray per-frame. There is
  only ever one `WaterHookup` in this game (`WaterManager.get_the_hookup()`
  guards registration to a single instance), so "solve once per hookup" in
  practice means "solve once per Engine frame, shared by every tray" rather
  than a multi-hookup grouping problem. `WaterManager.solve_hookup_for_farming()`
  is a new additive method (existing `get_received_rate_mL()` callers —
  `WaterDispenser`, `WaterInfoUI` — are untouched) that each `FarmingTray`
  instance pulls from via a static per-Engine-frame cache
  (`FarmingTray._batch_frame` / `_batch_map`, populated lazily by
  `_get_batched_hookup_map()` on first access per frame, reused by every
  other tray that frame). Each tray still gates on its own
  `is_reachable_from_hookup()` (existing public method) for connectivity.
- **Grow-light lookup (item 14)** — `FarmPlant._compute_light_speed()` no
  longer scans every member of the `"grow_light"` group each hour tick.
  `GrowLight.gd` keeps a static spatial-hash bucket registry
  (`GrowLight._bucket_registry`, `CELL_BUCKET_SIZE = 0.6`) — each `GrowLight`
  appends itself to its bucket in `_ready()`/`_register_bucket()` and erases
  itself in `_exit_tree()`. **Important:** grow lights sit on the 0.25m
  build grid (`BuildModeController.grid_size`), NOT a whole-meter grid, so
  the bucket size is deliberately `>= LIGHT_MATCH_RADIUS` (0.55m, the exact
  tolerance the old O(n) distance scan used) and the lookup
  (`GrowLight.get_best_growth_speed_near(pos)`) scans the full 3x3
  neighborhood of buckets around a plant's position, applying the same
  exact distance check and `maxf()` best-speed pick the original scan used
  — behavior is unchanged, only the search space shrinks from every grow
  light in the game to a handful of nearby candidates. This registry's
  bucket-array shape (not a single ref per bucket) is intentionally reused
  by Group 7 item 15's future double-stack guard.

## Feedback & readability polish (Polish Plan Group 1, items 1–4)
- **Item 0 cleanup carried over here** — `FarmPlant.gd` now truly
  `extends Node3D` (no `StaticBody3D`, collider, or `interactable`/
  `farm_plant` group membership). The original Group 0 commit only deleted
  `on_interact()`/`get_interact_prompt()` and left the collider/groups
  underneath in place; this pass finished that cleanup while the file was
  already open for Group 1 work. `FarmingTray.on_interact()` already calls
  `plant.harvest()` directly, so nothing depended on the plant itself being
  interactable.
- **New shared file `FarmingConstants.gd`** (`scripts/world/farming/`) —
  plain `RefCounted`/`class_name`, const-only, same shape as
  `WaterQualityColor.gd`/`PlantDatabase.gd`. Holds
  `HEALTH_WILT_THRESHOLD = 40.0` (item 1's cosmetic cutoff) and
  `HEALTH_WARNING_THRESHOLD = 25.0` (item 2's toast cutoff) so both
  thresholds are defined exactly once.
- **Item 1 — wilting visual**: `FarmPlant._refresh_visual()` lerps the
  spike mesh's `StandardMaterial3D.albedo_color` from healthy green
  (`SPIKE_COLOR`) toward wilted brown (`SPIKE_WILTED_COLOR`) as `health`
  drops below `FarmingConstants.HEALTH_WILT_THRESHOLD`, reaching full brown
  at `health == 0`. Purely visual — does not affect growth/harvest logic.
- **Item 2 — low-health toast**: `FarmPlant._tick_one_game_hour()`
  edge-triggers (via `_warned_low_health`, reset once health recovers back
  above the threshold) a call to
  `NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, ...)`
  when `health` first crosses below `FarmingConstants.HEALTH_WARNING_THRESHOLD`.
  **Deliberate deviation from the original plan doc**: the plan named the
  older standalone `TransientNotice.gd` toast, written before
  `NotificationManager` (the project's current central toast/history
  system) existed. `NotificationManager` is used instead — `NEUTRAL` domain
  since farming has no domain of its own, `WARNING` severity since this is
  a localized per-plant problem, not a total-system failure. Note:
  `WaterPurifier.gd`'s existing low-filter warning still uses the older
  `TransientNotice.gd` directly — left untouched, out of scope here.
- **Item 3 — `FARM_DEBUG` on-screen readout**: `FarmPlant.gd` follows the
  same per-file debug-const convention as `GrowLight.WIRE_DEBUG`/
  `WaterPipeDrawMode.PIPE_DEBUG` (no shared debug-flag file). When
  `FARM_DEBUG = true`, a billboarded `Label3D` is built once in `_ready()`
  and updated every hour tick with `health`, `water_fraction`,
  `light_speed`, and `hours_without_light`.
- **Item 4 — "Ready in ~X days" countdown**: `FarmPlant` now caches its
  latest computed growth rate each hour tick in a public
  (non-underscore) `growth_per_hour_current` field specifically so
  `FarmingTrayUI` can read a live rate without recomputing it.
  `FarmingTrayUI._draw_plant_block()` shows "Ready now" when already
  ready, "Ready in: stalled" when the current rate is 0 (no light/water),
  or "Ready in ~N days" otherwise (`ceil` of hours-remaining / 24),
  color-graded via `WaterQualityColor.get_color()` fed `progress * 100.0`
  — reusing the project's existing red/yellow/green step-function
  convention rather than a new one. `PLANT_BLOCK_H` grew from 92 to 108 to
  fit the extra line.

## Grow light illumination & placement guidance (Polish Plan Group 2, items 5–6)
- **Item 5 — real `OmniLight3D` illumination**: `GrowLight._build_fixture()`
  now calls `_build_omni_light()`, adding a real `OmniLight3D` child (same
  pattern `WallLight.gd` already uses), mirrored by `_refresh_tubes()`
  exactly following the 3 emissive tubes' powered/shed/off state. Values
  are deliberately budget-capped from day one, **not** copied from
  WallLight's own tuned figures (`OMNI_LIGHT_ENERGY = 1.1`,
  `OMNI_LIGHT_RANGE = 3.0` vs. WallLight's 2.0/10.0) — a dense farm room
  can plausibly hold far more grow lights than a base has wall lights.
  Also sets `distance_fade_enabled` (native Godot light culling, begin=18m/
  length=4m) proactively as a cheap perf guard for large farm layouts,
  rather than waiting for a playtest to reveal an FPS dip first — costs
  nothing to include now. The emissive tube mesh itself is unaffected by
  distance fade (only the real light node fades), matching the plan's
  explicit "keep the emissive mesh at all distances" requirement.
- **Item 6 — ghost-preview footprint decal**: `GhostPreview.gd`'s grow-light
  ghost branch now calls `_attach_grow_light_footprint_decal()`, adding a
  flat, light-blue, unshaded `QuadMesh` child laid on the floor directly
  below the ghost (dropped from `GROW_LIGHT_PLACEMENT_Y` down to
  `PLACEMENT_Y`, same floor height every other floor object sits at). Same
  no-depth-test/always-visible convention as the existing ghost direction
  arrow. This is the *only* placement guidance a player gets for this tile
  — the core plan's §4 deliberately doesn't require a light to sit above a
  tray, so treated as required polish rather than optional.

## Action-completion cues (Polish Plan Group 3, items 7–8)
- **Item 7 — soil-fill dust puff**: `FarmingTray.fill_first_open_soil_cell()`
  now calls `_play_soil_fill_puff(cell_index)` on success — a dusty-brown,
  unshaded, billboarded `QuadMesh` spawned just above the filled cell,
  scaling `0.2 → 1.4` while fading out over 0.35s (same
  create-tween/parallel-scale-and-fade/`queue_free` convention as
  `WaterPurifier.play_clean_pulse()`). **VFX only, no sound** — the
  codebase has zero audio infrastructure anywhere (no
  `AudioStreamPlayer` usage, no `.ogg`/`.wav` assets, no audio folders),
  and the plan's reference point ("same weight class as dig confirm,
  filter swap") doesn't hold up — neither of those existing actions has a
  sound cue in code either. Adding the project's first-ever audio system
  for one polish item was judged out of proportion; flagged to Brannon as
  a scope call, with a follow-up dedicated audio pass offered if wanted.
- **Item 8 — harvest pop-in**: `FarmProduceItem.spawn_at()` now starts each
  spawned item at `HARVEST_POP_START_SCALE = 0.1` and tweens to full scale
  over 0.28s with `TRANS_BACK`/`EASE_OUT` (a slight overshoot "pop" rather
  than a linear grow-in), applied to both of `FarmPlant.harvest()`'s two
  spawned items independently. Same no-sound rationale as item 7 above.

## Group 4 audit (items 9–11) — already satisfied, no code changes
All three Group 4 items were found already implemented by prior work when
audited this pass:
- **Item 9 — priority-pip / connectable-dot color parity**: both halves
  already shared. `FarmingTrayUI.PRIO_COLORS` is byte-identical to
  `WaterDispenserUI.PRIO_COLORS` (both cross-reference each other in
  comments). The connectable-dot half is even stronger than "parity" — it's
  a *single* shared system: `BuildModeController._refresh_connectable_dots()`
  builds one light-blue dot material and applies it to every wire-
  connectable tile (generators, terminal, wall lights, water hookup/sink/
  dispenser, and both farming tiles) from one `CONNECTABLE_TILES` list —
  there's no separate farming-specific dot to drift out of sync.
- **Item 10 — Bag of Soil vs. Empty Bag silhouette**: already distinct.
  `BagOfSoilItem._build_placeholder_mesh()` uses a bulkier
  `Vector3(0.26, 0.20, 0.16)` box vs. `EmptyBagItem`'s flatter
  `Vector3(0.24, 0.04, 0.16)`, with comments on both confirming the intent.
- **Item 11 — double-tray center seam**: already present.
  `FarmingTray._build_mesh()` adds a raised divider wall
  (`BASIN_WALL_H` tall, same basin material) down the exact center of the
  footprint whenever `cell_count == 2`, making the two independent cells
  visually obvious without any UI label.

## Targeting clarity (Polish Plan Group 5, item 12)
- **Nearest-valid-tray highlight**: `FarmingTray.set_target_highlighted(bool)`
  toggles a translucent green (`Color(0.35, 1.0, 0.45, ...)`), unshaded,
  no-depth-test `QuadMesh` laid flat over the tray's footprint, pulsing
  alpha between `0.14` and `0.40` on a looping 0.6s tween while active.
  `BagOfSoilItem` and `SeedItem` each recompute their existing "nearest in
  range" lookup (`_find_nearest_tray_needing_soil()` /
  `_find_nearest_plantable_tray()`) every `_physics_process` frame while
  held, and only toggle the highlight on the two tray objects involved when
  the nearest target actually changes (not every frame) — cleared
  immediately on drop, knockout, or successful `on_use()` consumption so no
  stale highlight can linger on a tray after the item holding it is gone.

## Known gaps (explicitly out of scope for this pass)
- **Persistence**: trays/grow lights themselves save/restore fine as
  ordinary `BuildModeController._placed_objects` entries, but per-cell
  `soil_filled`/`planted_type`/plant `progress`/`health` state is NOT wired
  into the save `extra` dict — a reload shows trays present but empty/
  unsoiled. Same category of gap this project already carries for Purifier
  filter state; add to the future save/load overhaul list.
- **Group 7 items** (double-stack grow-light guard, save schema pre-shape,
  tray deconstruct/refund rule, `get_trays_needing_attention()`) — the last
  remaining group, not yet started.
