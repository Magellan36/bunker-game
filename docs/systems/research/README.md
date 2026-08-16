# Research System

**Read this before adding or changing any item's `get_trash_material()` or
working on the Research Station.** This is the material-type contract that
future Research Station feed/consumption logic will read.

## Material type contract

Any item eligible for the `inventory_item` group MAY implement:

```gdscript
func get_trash_material() -> String:
	return "metal"   ## one of: "metal", "plastic", "paper", "organic" (this pass)
```

- **Duck-typed via a method, not a bare property** — several items'
  category depends on live state (charges/fill) at throw-away time.
- `TrashCan.extract_trash_record()` checks `item.has_method(
  "get_trash_material")` and, when present, stores `"material": <value>`
  inside the record's `data` dict (so the Trash Bag hover panel's
  `_relevant_field()` surfaces it). Items WITHOUT the method get no
  `"material"` key at all — silently uncategorized, by design.
- Untagged = unusable for research until explicitly categorized.

## The four categories (this pass)

`"metal"`, `"plastic"`, `"paper"`, `"organic"`. Room left for 1–2 more later.

## Mapping (verified against actual property names in each script)

| Item | Material | Note |
|---|---|---|
| `BagOfSoilItem` | organic if `_charges >= _max_charges` (truly full), else plastic | **Flagged for confirmation** — implemented as strict-full; if you meant "any charge left" (`_charges > 0`) like FoodCan/WaterBottle, say so and the threshold changes. |
| `Basket` | organic (static) | |
| `CookingPot` | metal (static) | |
| `DishItem` | organic (static) | |
| `EmptyBagItem` | plastic (static) | Empty-drop of `BagOfSoilItem`. |
| `EmptyFertilizerBottleItem` | plastic (static) | Empty container of `FertilizerItem`. |
| `EmptySeedBagItem` | paper (static) | NEW (Aug 2026) — empty-drop of `SeedItem`. |
| `FarmProduceItem` | organic (static) | |
| `FertilizerItem` | organic (static) | The full/charged bottle itself — distinct from its empty container (plastic). |
| `Flashlight` | metal (static) | |
| `FoodCan` | organic if `not _is_empty`, else metal | Uses the item's own `_is_empty` flag directly. |
| `FuelCan` | metal (static, always) | Deliberately does NOT check `_fuel_remaining`. |
| `PurifierFilterItem` | plastic (static) | |
| `WaterBottle` | organic if `current_fill_mL > 0.0`, else plastic | |
| `SeedItem` | **left untagged, no method added** | Deliberate — pending your input; stays unusable-for-research until specified. |

## Research Station object (TILE 38)

`ResearchStation.gd` — singleton, spawns once near world-center at game
start, never purchasable, never deconstructable, movable only (identical
treatment to Build Station). `[E] Open Research Station` opens the modal
`ResearchStationUI`. See `docs/systems/furniture-items/README.md` for the
wiring summary and the inherited save-position limitation.

## UI shell status (this pass)

`ResearchStationUI` — modal chrome (StorageUI/WaterInfoUI conventions),
**3 selectable tabs** (Bunker Upgrades / Player Skills / NPC Skills). The
Bunker tab now shows real upgrade buttons (data-driven off the tree's
`UpgradeDef` list); Player Skills / NPC Skills stay empty/placeholder this
pass. A persistent materials header spans all three tabs
(`Metal: 0/10  Plastic: 0/10  ...`), refreshed on open and on a repeating
timer while the panel is open (background drain keeps running regardless
of which tab is showing). `InteractionSystem.research_ui` gates E/F while
open (same as shelf/basket).

## Upgrade system architecture (Aug 2026)

### Data model — `UpgradeDef` base + tiny subclasses

`scripts/core/UpgradeDef.gd` (extends `Resource`) holds the shared data
fields (`id`, `display_name`, `tree` — "bunker"/"player_skills"/
"npc_skills", `duration_seconds`, `material_costs` whose keys match
`get_trash_material()`'s return values). The EFFECT is a virtual
`apply_effect()` each subclass overrides. "Mass-producible": a new upgrade
is a tiny subclass + a `.tres` resource instance under
`res://data/upgrades/` — the runtime/UI code has zero per-upgrade
special-casing.

- `scripts/core/upgrades/WaterOutput2xUpgrade.gd` — the first real
  upgrade; `apply_effect()` copies `AdminMenu._on_hookup_output_double_pressed()`
  verbatim (tier + 1, clamped at `WaterHookup.TIER_DAILY_ML` top).
  Resource: `res://data/upgrades/bunker_water_output_2x.tres`
  (`{"metal": 5, "plastic": 5}`, 10s, tree "bunker").
- Resources have no SceneTree of their own, so `apply_effect()` gets the
  running tree injected via `set_tree_ref()` right before being called.

### Material storage — `ResearchStation.gd`

`stored_materials: Dictionary` per the four `MATERIAL_TYPES`
(`{"metal": 0, "plastic": 0, "paper": 0, "organic": 0}`), each capped at
`STORAGE_CAP = 10`. `add_material(material, amount)` clamps at the cap and
returns the actual amount added. **No `remove_material` or
deposit-trash-into-station logic yet** — the reservoir/dump mechanic is
explicitly deferred; this storage math is ready to be called by whatever
it becomes.

### Incremental consumption model (matches "60% done = 3/5 used")

Nothing is deducted at click-time; `start_research()` only checks
eligibility (nothing else running, not already completed, enough materials
to start) and returns false otherwise. `_process()` then drains storage in
small floor()-quantized steps as `elapsed` advances, so at 60% completion
a `{"plastic": 5, "metal": 5}` research has consumed exactly 3 of each —
the station's stored count visibly ticks down. `completed_upgrade_ids` on
the station (NOT on the shared Resource, which would be a correctness
footgun) is the source of truth for "already done"; `_complete_research()`
fires `apply_effect()`, clears state, and posts a toast via
`NotificationManager`.

### The station joins the `"research_station"` group

One line in `_ready()` — this is how `AdminMenu` (F7) and future code find
the singleton.

### F7 debug — `AdminMenu.gd`

New `RESEARCH` section with one row, `"+10 Each Material Type"`, calling
`_on_add_research_materials_pressed()` — clamped at the same `STORAGE_CAP`
as everything else (uniform cap this pass; bypasses deferred).

## Deferred (explicitly out of scope this pass)

- **Pause/resume UI + material reallocation on pause** — deferred; the
  incremental model already stores everything pause would need
  (`_elapsed`, `_consumed`) without rearchitecture.
- **Reservoir/dump-trash-into-station mechanic** — not this pass;
  `add_material()` is ready to be called from whatever it turns out to be.
- **Multi-concurrent research** — `start_research()` rejects a second
  research while one is active, globally (not per-tree). Revisit once
  Player Skills / NPC Skills have actual upgrades. The double-spend edge
  case only becomes real with concurrency or pause/reallocate — neither
  exists yet, so reservation-locking is deliberately not built.
- **Storage-cap upgrade/bypass exceptions** — flat 10 this pass.
- **Player Skills / NPC Skills tab content** — empty/placeholder.

## Next-pass roadmap (explicitly deferred)

- Player Skills / NPC Skills upgrade definitions + buttons (add a `.tres`
  + tiny subclass to `_tree_upgrades`).
- `SeedItem`'s material category (pending your input).
- `BagOfSoilItem` threshold confirmation (strict-full vs any-charge).
- True room-center verification for both singleton stations (visual check).