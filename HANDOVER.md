# Handover — Farming: 10 New Plant Species

## What happened
Implemented `FARMING_NEW_PLANTS_PLAN` in one pass — a purely data-addition
task (plus one real bug fix) adding 10 new farmable species on top of the
existing Tomato/Onion. No new files, no manager class — the existing
`PlantDatabase.gd` table-driven design absorbed all 10 species with zero
changes needed to `FarmPlant.gd`, `FarmingTray.gd`, or `FarmingTrayUI.gd`.

Committed and pushed to `origin/main` as `158e199`:
> Farming: add 10 new plant species (Basil, Strawberry, Carrot, Chili
> Pepper, Bell Pepper, Garlic, Potato, Blueberry, Corn, Pumpkin)

`tools/godot_check.sh` ran clean (PASS, no parse/compile errors) before
pushing.

## Files changed
- **`scripts/world/farming/PlantDatabase.gd`** — `PLANT_CONFIG` grew from 2
  to 12 entries. Every entry (including the original Tomato/Onion) now also
  carries `category` (Vegetable/Fruit/Herb — cosmetic only, not read by any
  gameplay logic) and `seed_packet_color`. Added `get_category()` and
  `get_seed_packet_color()` static accessors.
- **`scripts/world/items/SeedItem.gd`** — **bug fix**: `_build_placeholder_mesh()`
  had a hardcoded `seed_type == "tomato" ? color_a : color_b` ternary, so
  every non-tomato seed packet (Onion, and would've been all 10 new species)
  rendered with the identical fallback tint. Now reads
  `PlantDatabase.get_seed_packet_color(seed_type)` directly — every species
  gets its own distinct packet color automatically.
- **`scripts/world/build/FarmingShopHelper.gd`** — 10 new `SHOP_ITEM_INFO`
  entries (item_ids 4–13), same $25/4-seed-bundle pricing as Tomato/Onion.
- **`scripts/ui/build/BuildModeHUD.gd`** — mirrored the same 10 entries into
  `FARMING_SHOP_ITEMS["Seeds"]` so they appear in the submenu list.
- **`docs/systems/farming/README.md`** — new "Species roster" section
  documenting the 12-species table and the seed-color bug fix, plus a new
  "Common edits — adding a new plant species" section (4-step recipe for
  the *next* batch of species, matching this project's per-system README
  convention).

## Species added (name / category / grow_days)
| Species | Category | grow_days |
|---|---|---|
| Basil | Herb | 5 |
| Strawberry | Fruit | 7 |
| Carrot | Vegetable | 8 |
| Chili Pepper | Herb | 9 |
| Bell Pepper | Vegetable | 12 |
| Garlic | Vegetable | 14 |
| Potato | Vegetable | 16 |
| Blueberry | Fruit | 18 |
| Corn | Vegetable | 22 |
| Pumpkin | Fruit | 30 |

All 10 use the same placeholder `SphereMesh` produce convention Tomato/Onion
already established (color/metallic/roughness only, no new mesh code).

## Deliberately deferred (flagged in the plan, not oversights)
- **Seed bundle pricing**: all 12 species cost the same $25/4-seed bundle
  regardless of `grow_days` (a 30-day Pumpkin costs the same as a 5-day
  Basil). Flat default on purpose — a grow-days-scaled pricing curve is a
  real balance decision that needs your numbers, not something to invent
  silently.
- **`FarmProduceItem.FOOD_RESTORE`**: still a single flat `20.0` shared by
  all 12 species (Tomato and Pumpkin restore identical hunger today). Same
  reasoning — open this up as its own follow-up if/when you want
  per-species hunger values.
- Tabbed/paginated shop UI was explicitly **not** built — 12 Seeds entries
  is in line with the existing Power category's proven 10-item precedent,
  not past it. Worth a one-time visual eyeball in-engine since it's a new
  high-water mark for list length, but no code changes proposed for it now.

## Next steps for you
1. Pull `origin/main` and playtest: buy each of the 10 new seed bundles from
   the Farming shop's Seeds submenu, plant them, confirm distinct seed
   packet colors on the shelf/floor and correct produce colors at harvest.
2. Eyeball the 12-item Seeds submenu list for visual cramping (flagged as
   worth checking, not a known bug).
3. Decide whenever you're ready: differentiated seed pricing and/or
   per-species `FOOD_RESTORE` values, both deferred above pending your
   actual numbers.
