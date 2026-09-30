# Surface Hatch & Expeditions

**Read this before opening `SurfaceHatch.gd`, `ExpeditionResolver.gd`,
`ExpeditionTables.gd` or `HatchInspectUI.gd`.** Tuning lives in
`ExpeditionTables.gd`; you rarely need the others to rebalance.

## Purpose
Gives the calm, stable stretches of a run something worth doing: residents
can be sent up through a ceiling hatch on timed scavenging runs. The player
decides **who** goes, **where** and **how hard they push**. The run feeds
every existing system (medical, water quality, farming, research materials,
fuel, NPC relationships) and puts a working resident out of the bunker for
hours, so each trip is a real tradeoff, not a free loot button.

Design pillars served: Decisions over actions (1), Interconnected systems (2),
Readable cause and effect (3: forecast before, plain-language report after),
Lasting consequences (7: depletion, lost residents, grudges), Emergence (8).

## Files
| File | Role |
|---|---|
| `scripts/world/hatch/SurfaceHatch.gd` | The fixture: procedural model, interaction, expedition state, departure/return hand-off, loot spawning, save data. |
| `scripts/world/hatch/ExpeditionResolver.gd` | Pure rules (no scene tree): eligibility, forecast, seeded trip resolution, loot specs, report text. |
| `scripts/world/hatch/ExpeditionTables.gd` | All data/tuning: destinations, approaches, hazards, loot, loyalty, depletion. |
| `scripts/ui/hatch/HatchInspectUI.gd` | Device inspector (BunkerDeviceInspector): topside list, plan-a-run form, forecast, reports. |
| `tools/tests/expedition_resolver_smoke.gd` | Headless rules contract (determinism, risk/haul direction, loyalty, discovery, loot ranges). |
| `tools/tests/surface_hatch_world_smoke.gd` | In-world: spawn, UI open, launch, save round-trip, forced return, injury, loot, reveal. |

## The player loop
1. **Open the hatch** (E): see who's topside, when they're due, and past reports.
2. **Plan a run.** Pick a resident (ineligible ones are listed with the reason:
   "too hurt to go topside", "too exhausted", "passed out"), a known
   destination and an approach. The forecast shows the round-trip time,
   injury risk as a word **and a percentage**, the chance they don't come
   back (when ≥ 1%), expected haul, how picked-over
   the site is, and a warning if the resident doesn't trust you.
3. **Send topside.** The resident leaves the bunker. The hatch lamp turns amber.
4. **Wait / manage the bunker short-handed.** An overdue notice fires if they
   pass their due time (a bad trip can make them late).
5. **Return.** They climb down at the foot of the ladder with the haul piled
   beside them, any injuries already on their medical record, and a report in
   the Bunker Log and the hatch panel. Or they don't come back.

## Rules

### Resolution happens at departure (seeded)
`launch()` calls `ExpeditionResolver.resolve(seed, ...)` once and stores the
outcome in the expedition record. It's in the save file, so reloading can't
re-roll a bad trip. The player only learns the outcome on return.

### Risk
Per-encounter danger = destination `danger` × approach `danger_mult`
+ low-health bonus + low-energy bonus ± personality (Level-Headed calmer,
Neurotic panics), clamped to `[0.02, 0.85]`. Each destination rolls
`encounters` times. The UI forecast calls the **same** function, so the shown
percentage is exactly the chance of at least one hazard.

### Hazards → existing medical conditions
| Hazard | Injury (NPCMedical) | Body parts | Extra |
|---|---|---|---|
| glass | Open Wound (66% bleed roll, infection race) | arms | |
| dog | Open Wound | legs | |
| scavengers | Open Wound | torso/arms | loses 50% of the haul |
| fall | Fractured | legs | |
| chemical | Burn | arms/head | |
| exposure | none | — | −30 energy, −20 thirst, −10 health |

No new condition types were added: returning residents flow into the existing
Bandage / Antibiotics / Splint treatment loop, and infection risk after an
untreated wound is the medical system's own curve.

### Approach dial
| Approach | Time | Danger | Loot |
|---|---|---|---|
| Careful | ×1.25 | ×0.55 | ×0.65 |
| Balanced | ×1.0 | ×1.0 | ×1.0 |
| Greedy | ×1.15 | ×1.6 | ×1.55 |

### Bad trips
- 2+ hazards: chance (35% per extra hazard) to come back **late** (+40–90%
  of trip time). They show as OVERDUE in the meantime.
- 3+ hazards: 30% chance they're **lost**. The forecast shows this as
  "Chance they don't come back" (exact, via `trip_loss_chance()`). For a fit
  resident: Balanced Pharmacy <1%, Balanced Field Hospital ~6%, Greedy Field
  Hospital ~18%. Short Careful runs are effectively never fatal.
- Loyalty below −15: they **skim** 35% of the haul (the report says the haul
  looked light). Below −40: a chance to **desert** (up to 35% at −98), taking
  everything. Lost/deserted residents are written off 36 game hours after
  they were due, with a critical Bunker Log entry.

### Needs on return
Trip hours × normal NPC drain × 0.6 (they ration and forage), floored at 5.
Exposure adds its flat hit.

### Mood & relationship
- Clean trip: thought "Saw the sky again" (+4 mood, 16h) and +2 with the
  player ("trusted me with a supply run").
- Hurt: thought "Got hurt topside" (−6, 24h). If the player chose **Greedy**,
  also −6 with the player ("pushed me too hard out there"). Blame only lands
  where the player's choice plausibly caused the harm.
- Events are written into the resident's own action log.

### Destinations & discovery
| Site | Hours | Encounters | Danger | Known from | Leans toward |
|---|---|---|---|---|---|
| Gas Station | 6 | 2 | 0.16 | start | fuel, scrap, some food |
| Row Houses | 8 | 3 | 0.20 | start | food, water, seeds, paper |
| Hardware Store | 12 | 3 | 0.28 | first Gas Station visit | purifier filters, fertilizer, soil, metal |
| Pharmacy | 12 | 3 | 0.30 | first Row Houses visit | bandages, antibiotics, splints |
| Field Hospital | 20 | 4 | 0.42 | first Pharmacy visit | trauma kits, antibiotics |

A first **successful** visit reveals the next site ("Found a note pointing
to the Pharmacy") so the map opens up through play.

### Depletion (surface entropy)
Every run adds 18% depletion to that site (cap 75%), recovering 4% per game
day. Depletion scales the haul directly, so farming one site gets worse and
worse, pushing players to rotate sites or take on riskier ones.

### Loot
All loot spawns as **real items** through `ItemSaveData.spawn()`, so it's
immediately usable, storable, saveable and feedable into the Research chute.
Found water is untreated (15–60% quality), so the purifier matters. Fuel cans
are partly full, flashlights have weak batteries, seed packets hold a random
real seed type, and scrap maps to existing trash items (plastic/paper/metal)
for research.

## Hand-off model (why NPCs are serialized, not hidden)
A departing resident is captured with `NPC.get_save_dict()` and freed, using
the same stop-activity / drop-held / leave-group sequence as
`MainWorld._restore_npcs()`. On return the dict (with `pos` moved to the
ladder and needs adjusted) goes through `apply_save_dict()` + `add_child()`,
the exact save-load path. Consequences:
- No brain, job, reservation, door lease or navmesh state can leak while
  they're away. `JobBoard` auto-releases claims from freed NPCs.
- Personality, skills, relationships, memories, medical conditions and home
  bed all persist through the trip.
- Held items are dropped at departure (same as a reload).
- The resident's `npc_id` stays stable, so others' relationships with them
  survive.

## Persistence
`SaveManager` field **`surface_hatch`** (phase 4, registered in
`MainWorld._register_save_fields()` after `npcs`): active expeditions
(including each away resident's full NPC save dict and pre-rolled outcome),
reports, visited/discovered sites and depletion. Old saves without the key
load with defaults (only the starting sites known).

## Placement & model
`MainWorld._spawn_surface_hatch()` runs after the Research Station spawns.
It tries wall spots in order (east wall → south → north → west) and takes
the first where a physics box query (ladder + standing space) hits nothing
solid except characters/loose items. It's a fixed fixture: **not** a build
tile, not in `_placed_objects`, not movable or demolishable. The model is a
procedural placeholder (ladder, ceiling collar with hand wheel, hazard floor
plate, status lamp). Collision covers the ladder only, and the navmesh picks
it up from the physics world after `notify_navigation_topology_changed()`.

## Public API (SurfaceHatch)
`get_candidates() -> Array[Dictionary]`, `get_available_destinations()`,
`get_depletion(dest)`, `forecast(npc, dest, approach) -> Dictionary`,
`launch_block_reason() -> String`, `launch(npc, dest, approach) -> bool`,
`get_front_position()`, `get_save_data()` / `restore_save_data()`.
Signal: `expeditions_changed`.

## Non-responsibilities
- Medical owns condition behavior; the hatch only calls
  `spawn_open_wound/spawn_fractured/spawn_burn` on return.
- NPC owns identity/serialization; the hatch never edits NPC internals
  beyond the documented save-dict keys (`pos`, needs, `health`).
- NotificationManager owns presentation of notices/log entries.

## Known tradeoffs / tech debt
- Departure is instant: the resident vanishes rather than walking to the
  ladder and climbing. See recommendation 1.
- The model is a code-built placeholder, not an art asset.
- `MAX_ACTIVE_EXPEDITIONS = 2` and single-person teams keep the UI simple.
- The F7 time-skip works (all timing is `NPCClock` game hours), but the
  return check runs at 1 Hz real time, so a return can land up to a second
  after the skip.

## Recommendations (next passes, roughly in value order)
1. **Walk-out/walk-in.** A `GoTopsideActivity` via `NPCBrain.force_command()`:
   walk to the ladder, climb animation, then hand off. On return, climb down.
   This makes departures visible and lets the player change their mind.
2. **Packing supplies.** Let the player load items into the hatch's kit slot
   (food, water, bandage, flashlight). Food/water cut the trip drain; a
   bandage auto-treats the first bleed; a flashlight lowers `fall` weight.
   This gives crafting and storage a purpose and makes prep a decision.
3. **Radiation / sickness condition** (Medical-owned): "exposure" and long
   trips add a slow Radiation Sickness condition treated with a new item.
   This hooks straight into the future Radio/storm forecast system.
4. **Radio + surface weather.** Storm days raise `danger`, block the hatch
   or make found water worse. Forecasts come in over a powered radio.
5. **Two-person teams.** Friends lower danger (morale), rivals raise it, and a
   pair can carry the other home when one is hurt (turn "lost" into "carried
   back badly hurt"). Uses the existing relationship ledger.
6. **Grief & witnesses.** When someone is lost or deserts, close friends get
   a lasting thought, and the resident who "pushed them too hard" (the player)
   takes a witnessed relationship hit via `NPCBonds.witnessed()`.
7. **Visitors at the hatch.** A stranger follows a returning resident home:
   let them in (new resident, disease risk, extra mouth) or turn them away.
8. **Skill growth.** Survivors gain a new "scavenging" skill each trip that
   lowers danger slightly, so veterans become valuable and losing one hurts.
9. **Unique finds.** Rare decorations/keepsakes (photo, guitar, board game)
   that only come from the surface and feed the Home pillar.
10. **Map screen.** Once there are 8+ sites, replace the dropdown with a
    simple surface map showing distance, depletion and last-visited.

## Common edits
- **Rebalance:** edit `ExpeditionTables.gd` only, then run
  `expedition_resolver_smoke.gd` (it asserts directional properties like
  "careful is safer than greedy", not exact numbers).
- **New destination:** add to `DESTINATIONS` + `DESTINATION_ORDER`; set
  `requires` to reveal it from an existing site.
- **New loot:** add to `LOOT_ITEMS` with a real scene/script path (the smoke
  test checks it exists); `[min, max]` state values are rolled per item.
- **New hazard:** add to `HAZARDS` mapping onto an existing NPCMedical
  `spawn_*` call, and handle its `injury` string in
  `SurfaceHatch._apply_trip_effects()`.
