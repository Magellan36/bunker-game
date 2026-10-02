# Run Phases: Pre-Apocalypse → Post-Apocalypse

**Read this before opening `BunkerPhase.gd`, `BuildEconomy.gd`,
`SalvageItem.gd`, `HatchLeaveUI.gd` or `SealTransition.gd`, or before
changing anything that spends or refunds cash.**

## Purpose

A run has two acts.

1. **Pre-Apocalypse (preparation).** The player spends cash in the shop,
   builds, wires and plumbs the bunker. The clock holds before Day 1, needs
   don't drain, and the survivors picked at New Game wait outside.
2. **Post-Apocalypse (sealed).** Started by pressing **Leave** at the
   Surface Hatch. The shop closes for good, nothing new can be built, the
   survivors come in, and Day 1 begins. The bunker runs on what was
   prepared. Demolishing drops salvage; wire and pipe cost Metal from the
   Research Station. The hatch can't be used for 10 days.

Design pillars served: Decisions over actions (1: one big preparation
decision), Lasting consequences (7), Readable cause and effect (3: the Leave
panel shows what you're taking in before you commit), Preserve hope (10:
salvage keeps repair possible).

## The three acts in code (`BunkerPhase.Phase`)

| Value | When | Rules |
|---|---|---|
| `LEGACY` (0) | Saves written before this feature, `MainWorld.tscn` run directly, test harnesses | Exactly the old game: cash economy, clock runs, construct allowed, hatch open. |
| `PRE_APOCALYPSE` (1) | A New Game (`WorldManager.pending_new_game` at MainWorld startup) | Cash economy, clock held, survivors queued, hatch shows Leave. |
| `POST_APOCALYPSE` (2) | After `BunkerPhase.seal()` | Salvage economy, build/duplicate/shop locked, hatch locked for `HATCH_LOCK_DAYS` (10). |

`LEGACY` exists so nothing that isn't a real New Game changes behaviour:
every NPC/build/power/hatch harness and every old save keeps working. F7 →
**PHASE** moves a dev world into either act.

## Files

| File | Role |
|---|---|
| `scripts/world/core/BunkerPhase.gd` | Owner. Phase, seal time, waiting survivors, supply snapshot, `seal()`, save data. Child of MainWorld, group `bunker_phase`. Static `BunkerPhase.preparing(tree)` / `sealed(tree)` read as LEGACY when no node exists. |
| `scripts/world/build/BuildEconomy.gd` | Static rules: Metal prices for wire/pipe, the reserve (Research Station), salvage tables, `drop_salvage()`, float text. |
| `scripts/world/items/SalvageItem.gd` | Placeholder salvage sphere (one per material, carries a unit count). |
| `scripts/ui/hatch/HatchLeaveUI.gd` | Pre-apocalypse hatch inspector: readiness check + **Leave** + confirm. |
| `scripts/ui/hatch/SealTransition.gd` | Full-screen seal moment (archetype D); calls `seal()` behind black. |
| `tools/tests/bunker_phase_smoke.gd` | Drives the whole flow (54 checks). |

Touched elsewhere (each change is commented `Oct 2026`):
`PlayerStats.clock_running` / `get_start_elapsed()`, `SaveManager.register_field(..., on_missing)`,
`MainWorld._setup_bunker_phase()` + `bunker_phase` save field + Leave panel prewarm,
`HUD.set_phase()` / `spawn_float_text()`, `BuildModeHUD` (`construction_locked`, `tool_available`, `refresh_phase`),
`BuildWorkspace.apply_phase()`, `BuildModeController` (locks + salvage refunds),
`BuildUndoStack` (currency-aware), `WireDrawMode` / `WaterPipeDrawMode` (Metal pricing),
`WaterManager.delete_and_refund_edge()` (pipe salvage), `FarmingShopHelper` (shop closed),
`ResearchStation` (`available_material`, `spend_material`, `_feed_salvage`, bag units),
`SurfaceHatch.on_interact()`, `SurvivorSelectScreen.spawn_selected()`, `AdminMenu` PHASE rows.

## Flow

```
New Game → character → loading (MainWorld: begin_preparation)
  → survivor selection → Confirm → BunkerPhase.queue_survivors()
  → "Survivors will join when the apocalypse begins." → bunker, PREPARATION
  … shop / build / wire / pipe with cash …
Surface Hatch [E] → HatchLeaveUI → Leave → "Are you certain you're ready?"
  → Leave → SealTransition: fade to black → pause → BunkerPhase.seal():
       close build mode, clear the undo stack, clock → Day 1 6:00 AM,
       spawn survivors at the ladder facing the player, phase_changed
     → "DAY 1 / The hatch is sealed. / Mara and Ode came in with you."
     → unpause → black lifts
Day 1–10: hatch [E] → toast "N days until it is safe to travel"
Day 11+: hatch [E] → expedition planning (HatchInspectUI, unchanged)
```

## Rules

### Preparation
- `PlayerStats.clock_running = false`: elapsed time, the clock and the
  player's needs all hold. The HUD eyebrow reads **PREPARATION** and the time
  is hidden.
- **Supplies can be bought and stored, not put to use; nothing wears out**
  (Brannon, 2026-10-02):
  - Generators run without burning fuel (`PowerManager._tick_generators`).
  - Hookup water quality doesn't drop (`WaterHookup._process`).
  - Purifier filters don't wear (`WaterPurifier._process`).
  - Flashlight batteries don't drain (`Flashlight._physics_process`).
  - **Held-item use is gated once** in `InteractionSystem` (the E dispatch)
    through `BunkerPhase.use_allowed()`: eating, drinking, adding to a pot
    (so no cooking), refuelling, filter swaps, medical items, soil, seeds,
    fertilizer and replanting all wait. The prompt ends in "· from Day 1"
    and pressing E shows "Supplies can't be used until the apocalypse
    begins". Items opt back in with `allows_use_before_day_one()`:
    **WaterBottle at a dispenser** (refilling; stockpiling water is fine),
    **Flashlight** (the switch), **WeaponItem** (reload only).
  - Firearms don't fire (no rounds spent) — `WeaponItem.try_attack`.
  - Trays also refuse soil, seeds and fertilizer themselves
    (`FarmingTray.fill_soil_at_cell`, `plant_seed_at_cell`,
    `fertilize_first_open_cell`), so no other caller can plant either.
  - Still allowed: dispensers filling from the hookup, batteries charging,
    unpacking cases, the stove switch and the chute.
- **Research is bought with cash** (Brannon, 2026-10-02): the whole price is
  charged when it begins (`UpgradeDef.get_cash_cost()` — `cash_cost`, or
  $150 per material unit when unset; Water Hookup Output = $1,500 a tier,
  a guess). No materials are drained or reserved. A cash-bought research
  that is still running at the seal finishes without materials. After the
  seal, new research uses materials as before. The research panel shows a
  Cash requirement row ("$1,500 required · $48,500 available") and "Not
  Enough Cash" instead of the material rows.
- **Materials can still be loaded:** the chute (F-hold, its own path, not
  the E-use gate) accepts shop-bought items, so cash → items → materials
  works before the apocalypse, and that Metal carries into the sealed act
  for wire and pipe.
- Save slots made now read **"Preparation · 2 hours ago"** instead of a day
  and time (`SaveManager` meta `preparation`, `SaveSlotFormat.describe`).
- Survivors picked at New Game are stored in `pending_survivors` (saved) and
  spawned by `seal()`. None exist in the world before then.
- The hatch opens `HatchLeaveUI` instead of expeditions.

### The seal (`BunkerPhase.seal()`)
Closes build mode, **sets cash to 0** (leftover cash is deleted; the Leave
panel warns "Unspent cash is lost when you leave."), clears the build undo stack (nothing bought with cash can
be refunded afterwards), resets the clock to Day 1 at the start time and
starts it, records `sealed_at_elapsed`, spawns the waiting survivors at the
foot of the ladder (side by side, navmesh-snapped, facing the player), emits
`phase_changed`, and logs "The hatch is sealed".

### Sealed build mode
- **Locked:** Build (construct catalog, wall draw), Duplicate, Shop, rock
  digging. Buttons are greyed (`Q.FAINT`), unfocusable, skipped by LB/RB,
  and explain themselves on hover: **"Shop is permanently closed"** and
  "Nothing new can be built after the hatch is sealed". Every entry point
  is also guarded in `BuildModeController`/`FarmingShopHelper`, not just the
  buttons.
- **Live:** Move, Demolish, Undo, Wire, Pipe. Build mode opens on **Move**.
- The HUD's cash slot shows **"N / 10 Metal"** (spendable / station cap)
  while in build mode and is hidden outside it.

### Metal for wire and pipe
- Wire: **1 Metal per 3 m** (`WIRE_METRES_PER_METAL`), rounded up per run.
  Pipe: **1 Metal per 1.5 m** (`PIPE_METRES_PER_METAL`). So each further
  length adds +1 Metal.
- Taken straight from the Research Station's reserve. Running research has
  first claim on what it still needs (`ResearchStation.reserved_material`),
  so building never starves a research in progress.
- The live cost label reads "3 Metal" and turns **red** when the reserve
  can't cover it. (Cash labels before the seal now turn red too.)
- Each placed segment stores its share of the run's Metal as
  `metal_paid` meta (largest-remainder split by length), so demolishing or
  undoing part of a run returns exactly what that part cost.

### Salvage
- Demolishing anything after the seal drops `SalvageItem` spheres instead of
  refunding cash: one sphere per material, each carrying a count, with a
  small pop and a "+2 Metal · +1 Plastic" float. Amounts per tile are in
  `BuildEconomy.TILE_SALVAGE` (walls scale with run length; unlisted tiles
  fall back to Metal by price).
- Wire/pipe give back their `metal_paid`; segments laid with cash before the
  seal give back `floor(length / metres-per-Metal)` — never more than laying
  would cost, so there is no salvage loop.
- Carry a sphere to the Research Station chute and press **F**: the chute
  takes as many units as fit under the cap; any remainder stays in the
  sphere in your hand. Trash Bags carrying spheres feed the same way.
- Spheres save/load like any loose item.

### Undo after the seal
- The undo stack starts empty at the seal.
- Wire/pipe undo puts the Metal of the segments still standing back in the
  reserve (overflow over the cap drops as salvage).
- Demolish undo takes the **same spheres** back and restores the object. If
  any sphere was fed or destroyed it says "The salvage was used, so this
  can't be undone" and the entry is dropped; if one is carried or in the
  inventory it says "Put the salvage back down to undo this" and keeps the
  entry.

### Hatch lock
`hatch_days_remaining() = ceil(10 − days since seal)`. Pressing E shows the
toast "N days until it is safe to travel" ("1 day" singular) and opens
nothing. At 10 full days (Day 11, 6:00 AM) the normal expedition panel opens.

## Persistence
SaveManager field **`bunker_phase`** (phase 4, `on_missing`):
`{phase, sealed_at, pending_survivors}`. A save without the key (older than
this feature) restores as `LEGACY` instead of keeping the current session's
act. `register_field(..., on_missing = true)` is the generic hook for that.

## Copy (functional; flagged for Brannon to rewrite)
Brannon's own words, kept verbatim: "Shop is permanently closed", "X days
until it is safe to travel", "Leave", and the confirm's meaning (are you
certain you're ready / no major changes after this).

Written here and open to rewriting: `HatchLeaveUI.BODY_TEXT`,
`CONFIRM_TITLE`/`CONFIRM_TEXT`, "Not yet", "Cash can't be spent after you
leave.", the readiness captions, `SealTransition` "Day 1" / "The hatch is
sealed." / `arrival_text()`, "Nothing new can be built after the hatch is
sealed", "Sealed bunker" (build subtitle), the seal log line, and the undo
salvage messages.

## Liberties taken (for review)
1. **LEGACY act** so old saves, dev scenes and every existing harness keep
   the old rules. Only the New Game route enters preparation; F7 → PHASE
   switches dev worlds.
2. **Needs freeze with the clock** during preparation (time hasn't started).
3. **Readiness check on the Leave panel**: survivors, food/water days for
   everyone, fuel, unspent cash. Low supply is amber, none is red.
4. **Confirm buttons** "Leave" / "Not yet" in the danger tone; focus starts
   on "Not yet" (shared dialog rule).
5. **Seal moment**: full-screen fade with "Day 1 / The hatch is sealed." and
   who came in, while the world is paused; survivors arrive at the ladder.
6. **Duplicate and rock digging are locked** with Build: both create new
   structure.
7. **Salvage spheres carry counts** (one per material, not one per unit), and
   the chute feeds partially. Fewer trips (pillar 1).
8. **Running research reserves its Metal** before wire/pipe can spend it.
9. **Metal readout** replaces cash in sealed build mode; cash hides after the
   seal.
10. **Undo after the seal** reclaims the exact salvage spheres.
11. **Red cost labels for cash too** before the seal (it was always yellow).
12. Sealed build mode opens on **Move**; its subtitle reads "Sealed bunker".

## Decided (2026-10-02)
- **Research storage** will be upgradeable later. Until then the 10-unit cap
  stands and extra salvage stays as physical spheres in storage.
- **Wire/pipe cost is linear:** a short run is 1 Metal, a run N lengths long
  is N Metal (as implemented).
- **Salvage amounts** stay as guesses until playtesting.
- **No entropy before Day 1** and no using supplies (bottle refills excepted) — see Preparation above.
- **Leftover cash is deleted** at the seal.
- **Preparation saves** read "Preparation".
- **Pipe undo fixed:** Undo refunds only the legs still standing (cash or
  Metal), and every leg records an exact share of its run's price
  (`BuildEconomy.split`), so demolish-then-undo returns exactly what was
  paid. It used to refund the whole run again — a free-cash loop.

## Open questions (pinned)
- **Salvage visuals** are tinted spheres. They need real models (and
  provenance) before release.
- **Moving the water hookup after the seal** drops its attached pipes as
  salvage (same rule as demolishing them).
- **Controller hint for locked tools:** hover tooltips need a pointer;
  controller players get a toast if they try a locked tool via the cursor.
