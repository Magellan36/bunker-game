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

`ResearchStation.gd` — singleton, spawns once flush against the bunker's
north wall (confirmed: the wall nearer player spawn), offset +4 from the
wall's center, at game start, never purchasable, never deconstructable,
movable only (identical treatment to Build Station). `[E] Open Research
Station` opens the modal `ResearchStationModernUI`. See
`docs/systems/furniture-items/README.md` for the wiring summary, exact
placement formula, and the inherited save-position limitation.

**Material feed chute (Aug 2026):** the station is now 1.5x its original
width (3 units instead of 2) — the added left portion is a chute that
feeds `stored_materials` directly, replacing the F7 debug button as the
real player-facing way in. Hold any item that implements
`get_trash_material()` (nearly everything in `inventory_item` now does —
only `SeedItem` doesn't) and press F near the chute specifically (its own
`ResearchStationChute.gd` interaction proxy, separate from the main
station body) to feed it: the item is destroyed, 1 unit of its material is
added, or — if that material's already at the 10/10 cap — the feed is
rejected entirely and the item stays in hand. A held Trash Bag drains all
of its records at once; records that fit are consumed, records whose
material is capped stay behind in the same (shrunk) bag still in the
player's hand. See `ResearchStation.gd`'s `_feed_single_item()` /
`_feed_bag()` for the exact logic. The F7 debug button is unaffected —
still there for quick testing.

## Modern UI status (Sep 2026)

`ResearchStationModernUI` is the active player-facing workspace. It keeps
the three established tabs and moves the fixed material reservoirs into a
clear four-card header. Bunker research is split into a scrollable pathway
canvas on the left and a selected-upgrade inspector on the right, so node
cards communicate progression while the inspector owns effects, costs,
duration, tier progress, and the research action.

Only `Water Hookup Output` is a functional upgrade. `Basic Water Supply`
is a visual baseline and the locked downstream cards are clearly marked
future scaffolding; they do not invent gameplay state. Player Skills and
NPC Skills remain polished empty states until upgrade resources exist for
those trees.

The UI delegates start/pause/resume and all material/tier state to the
existing `ResearchStation`. Lightweight labels and progress bars update in
place; the pathway/detail structure rebuilds only when research state
changes. D-pad and right stick navigate while the left stick remains
available for movement, LB/RB cycle tabs, scrollbars are selectable, and
walking away closes the workspace through `UIProximityClose`. The former
`ResearchStationUI.gd` remains untouched as a fallback/reference.

## Upgrade system architecture (Aug 2026)

### Data model — `UpgradeDef` base + tiny subclasses

`scripts/core/UpgradeDef.gd` (extends `Resource`) holds the shared data
fields (`id`, `display_name`, `tree` — "bunker"/"player_skills"/
"npc_skills", `duration_seconds`, `material_costs` whose keys match
`get_trash_material()`'s return values, `max_tier`). The EFFECT is a
virtual `apply_effect(tier_reached: int)` each subclass overrides —
called once per tier completion with the tier number JUST reached
(1-indexed). **Direct-set semantics:** effects SET the external system to
match `tier_reached` rather than incrementing relative to unknown prior
state — the station is the authoritative progress tracker, effects just
sync external systems to it. `get_max_tier()` defaults to the static
`max_tier` export; override it when a chain's true tier count is computed
from the system it drives. "Mass-producible": a new upgrade is a tiny
subclass + a `.tres` resource instance under `res://data/upgrades/` —
the runtime/UI code has zero per-upgrade special-casing.

- `scripts/core/upgrades/WaterOutput2xUpgrade.gd` — the first **tiered**
  upgrade. `get_max_tier()` is computed from
  `WaterHookup.TIER_DAILY_ML.size() - 1` — **3 real completions** (index
  0→1, 1→2, 2→3), NOT the illustrative "4" from the reference sketch
  (that was showing the UI pattern generically, not water output's real
  number). `apply_effect(tier_reached)` direct-sets `hookup.tier` to the
  reached tier (clamped at the array top), replacing the old "+1" debug
  logic. Resource: `res://data/upgrades/bunker_water_output_2x.tres`
  (`{"metal": 5, "plastic": 5}`, 10s, tree "bunker") — no `max_tier`
  export needed, computed live via the override.
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
eligibility (nothing else running, not fully maxed — `tier_progress`
reached `get_max_tier()` — enough materials to start) and returns false
otherwise. `_process()` then drains storage in small floor()-quantized
steps as `elapsed` advances, so at 60% completion a
`{"plastic": 5, "metal": 5}` research has consumed exactly 3 of each —
the station's stored count visibly ticks down. Progress is tracked per
chain as `tier_progress: Dictionary` — chain id → tiers completed so far
(0 = not started) — on the station (NOT on the shared Resource, which
would be a correctness footgun). `_complete_research()` increments the
tier, passes it to `apply_effect(tier_reached)`, clears state, and posts
a toast via `NotificationManager` ("...Tier N research completed").

### The station joins the `"research_station"` group

One line in `_ready()` — this is how `AdminMenu` (F7) and future code find
the singleton.

### Node-tree content area + connector canvas

The Bunker tab's content area is a `ScrollContainer` (vertical only)
wrapping one fixed-size canvas `Control`; every node box and connector
line is absolutely positioned on it. Connections render on a dedicated
`_connector_canvas` (a full-size `Control` behind the node boxes) whose
`draw` signal calls `draw_line()` once per connection — simpler/cheaper
than per-connection `Line2D` nodes for a static diagram. Layout: row-0 is
the single tiered detail node (`_build_tiered_node`, centered); rows 1-4
are 3 blank `NODE_W×NODE_H` boxes each, all three row-1 boxes connecting
upward to the same top node, then vertical lines per column; two side
branch pairs (2 blank boxes each) connect internally with one vertical
line and to the main grid with one diagonal. `_build_tiered_node` stacks
name (no tier prefix — the tier bar communicates status) → materials
(auto-expanding to a new line per 2 materials, growing only that box) →
time → full-width progress bar → 3-state Research/Stop Research/Resume
button → full-width tier-segment bar (one segment per tier, evenly
filling the tile, accent-filled for completed tiers), with the
"COMPLETED" banner only at full max. Layout polish pass: the canvas is
now `NODE_W + COL_GAP` wider (the left branch pair mirrors the right,
both beside the grid), the right branch's diagonal anchors to row 1
(was row 2), the panel height is computed from the materials grid size,
and `PANEL_W` is 1024 so both branches stay on-canvas with horizontal
scroll disabled.

### Polish pass (Aug 2026) — pause/resume, hover fix, material sizing

- **3-state button model.** `ResearchStation.gd` gained
  `is_paused`, `pause_research()`, `resume_research()`; `_process()` now
  gates on `active_upgrade == null or is_paused`, so pausing freezes both
  elapsed time and material drain. **No refund on pause — confirmed.**
  The card's button is three-state: "Research" (idle, disabled when
  maxed or unaffordable), "Stop Research" (active — dark-red style,
  calls `pause_research()`), "Resume" (paused — default accent style,
  flagged for visual tuning if it should differ). Resuming continues
  from exactly where it froze.
- **Hover-bug fix — structural vs. tick split.** `_process()` previously
  called `_refresh_content()` every `REFRESH_INTERVAL`, which destroyed
  and rebuilt every node (including the Research button) each tick —
  Godot never retro-marks a freshly-created Control as hovered, so the
  highlight flickered. Now the passive tick only mutates cached refs in
  place (`_tick_active_progress()`: `_active_progress_bar`,
  `_active_time_label`, both nulled whenever the active card isn't the
  one displayed). Full rebuilds still happen on real state changes
  (start/pause/resume/stop/tab switch); the tick also detects in-station
  completion and triggers one rebuild then. Useful precedent for any
  future UI that periodically refreshes.
- **Material buttons.** `_build_materials_grid()` switched from
  `PanelContainer` (auto-resizes to its child Label, so long words
  stretched their cell) to plain `Panel` with a manually-positioned
  Label, sized once via `_compute_material_btn_size()` from the widest
  of the four label strings + small fixed padding — all four cells now
  identical and short/tight. Panel height is derived from that size.
  (Aug 2026 icon pass: the Label was split into a `TextureRect` icon +
  a right-aligned count-only Label; `_compute_material_btn_size()`
  itself was left untouched on purpose so the cell footprint didn't
  change.)
- **Tier bar.** Full-width `_build_tier_bar()` (segments fill the tile
  edge-to-edge; `max_tier == 1` reads as one toggle-colored strip).
- **Titles/durations.** Titles are bare `display_name` (toasts keep the
  tier number); durations use shared `_format_duration()` ("10 Seconds",
  "Time left: X" only for active research — no "Time to completion:"
  prefix).

### F7 debug — `AdminMenu.gd`

New `RESEARCH` section with one row, `"+10 Each Material Type"`, calling
`_on_add_research_materials_pressed()` — clamped at the same `STORAGE_CAP`
as everything else (uniform cap this pass; bypasses deferred).

## Deferred (explicitly out of scope this pass)

- **Material reallocation/refund on pause** — explicitly NOT happening
  (confirmed); pausing just freezes `_elapsed`/consumption with no
  refund.
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

## Controller support

The research UI selects the real Water Hookup Output node on open. A/Enter
select the focused node or action, LB/RB cycle tabs, D-pad/right stick move
focus, selectable scrollbars own scrolling, and B/Escape/E close. The left
stick remains available for player movement while the station is open.
Details in `docs/systems/controller/README.md` (§ Per-UI matrix — Research
station).
