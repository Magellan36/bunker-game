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
**3 selectable tabs** (Bunker Upgrades / Player Skills / NPC Skills), each
with its own separate (empty) progress-state stub. **No buttons, no
timers, no feed logic yet** — next pass. `InteractionSystem.research_ui`
gates E/F while open (same as shelf/basket).

## UpgradeDef (stub)

`scripts/core/UpgradeDef.gd` — the data shape for a single upgrade
(`id`, `display_name`, `tree`, `duration_seconds`, `material_costs` — keys
match `get_trash_material()` return values, `completed`). NOT instantiated
anywhere yet; expect it to grow.

## Next-pass roadmap (explicitly deferred)

- Actual upgrade definitions, buttons, timers, progress UI.
- Feed/consumption logic (spending trash material on an upgrade).
- `SeedItem`'s material category (pending your input).
- `BagOfSoilItem` threshold confirmation (strict-full vs any-charge).
- True room-center verification for both singleton stations (visual check).