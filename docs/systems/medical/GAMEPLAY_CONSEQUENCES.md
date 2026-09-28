# Medical gameplay consequences

September 2026 first playable pass. This is the current contract for exertion
and electrical hazards; historical README passages about automatic drops,
sprint lockout, deterministic fracture escalation or global-grid burn odds
are superseded here.

## Player contract

- Player owns stamina. `PlayerExertion` is a small value-state component owned
  by Player, not an autoload. It has no medical catalog, random rolls or clock.
- Normal running/heavy holding drains stamina at existing rates, summed when
  both occur. At zero, the action continues in overdrive. Controller sprint
  latching survives zero stamina and cancels on stopping/clicking again.
- Running alone slows from 78% toward 60% of sprint speed (still faster than
  walking at current base speeds). Carrying overdrive slows movement from 65%
  toward 45%; existing medical movement penalties then apply.
- Legs accumulate exposure only while overdrive sprinting; arms only while
  overdrive holding a heavy item, including standing still. Stopping either
  activity ends only that limb family's risk. Holding light items is safe.
- Each family gets 2 active seconds of grace. Exposure then ramps to full risk
  at 30 seconds. Inactive limbs recover 2 seconds of exposure per second.
  Brief sprint toggles/drop-pickups do not clear the accumulated exposure.
- Stamina must recover to 20 before normal exertion resumes. Starting again
  before then resumes overdrive even while some stamina remains.
- An accident suppresses further exertion accidents for 12 active simulation
  seconds, shared across arms/legs. Strain still accumulates while protected.
- Actual SceneTree pause freezes simulation. Ordinary movement/job locks
  suspend exposure and stamina (no hidden accidents or free recovery).
  Chair/bed rest recovers even when the animation system disables physics.

## Risk and injuries

`Player.exertion_updated` notifies Medical after each step. `exhausted` remains
as a compatibility warning event and no longer directly escalates fractures.
Medical rolls one combined accident, then weights the affected activity by its
exposure contribution and chooses one left/right limb. One mishap never rolls
four independent injuries.

Probability is `1 - exp(-dose)`. Dose integrates a per-limb linear ramp from
10% to 100% of its maximum rate after grace: 0.018/second for running and
0.026/second for carrying. Integration accounts for the fraction of a frame
actually spent beyond zero. The hazard is independent of physics FPS and
survival-clock fast-forward. Over 30 uninterrupted seconds beyond zero, the
first-accident chance is about 24% running alone or 33% carrying alone.
These are initial tuning values, not final playtest balance.

On a healthy limb, 70% of accidents cause a Strain. The remaining 30% cause a
fracture or severe break. A direct break requires at least 12 seconds exposure:
6% of carrying accidents, 2% of running accidents (included in that 30%).
A preexisting strain raises the combined fracture/break outcome share to 55%.

- Strain heals in 18 game hours at light duty, with 0.9 leg movement or 0.85
  arm work speed and 1.3 stamina drain for the relevant activity. Overdrive on
  that limb slows healing to 25%; no consumable is required.
- An existing fracture worsens using the existing bounded escalation/setback
  math. Reaching 100% converts it to Broken and removes its splint.
- An already-broken limb suffers a 15% setback to accrued healing, rather
  than another identical broken condition.
- Conditions with the same id/body part merge instead of stacking invisible
  duplicates behind a single HUD/status-screen key. Worst infection state is
  retained when legacy duplicate wounds merge.
- Movement/work aggregate multipliers have a 0.35 floor; sprint/carry drain
  aggregates have a 5x ceiling. These bounds currently apply to the player.
- Trauma Kit now splints Broken as well as Fractured limbs, using the existing
  treatment path. Its single-use consumption behavior is otherwise unchanged.

## Feedback and persistence

`ExertionFeedback` is medical-owned and instantiated by Player. Its CanvasLayer
0 draws above the world and below the existing HUD (layer 1); it does not modify
HUD, power-alarm, or critical-vignette state and ignores pointer input. Screen
edges darken smoothly with a capped 0.4 shader strength, leaving the center
clear. Text explains low stamina, the activity to stop, recovery, and accidents.
The exported `Player.exertion_feedback_strength` can disable/reduce the vignette
without removing warnings; settings-menu integration is future work. Panting,
stumbles, load-slip animation and controller vibration remain future work.

Condition data stores the latest `incident_description` and `incident_game_hour`.
The existing status-detail API and tooltips expose those fields, including after
save/load. Older/debug conditions without provenance keep their existing text.
This records a described mishap; no physics impulse or accident animation is
currently applied.

`player_survival.exertion` holds stamina, exhaustion, per-limb exposure and
accident cooldown. Loading a save cannot refresh the grace period or stamina.
Legacy saves default to 100 stamina and no exposure. Activity flags/controller
latches do not persist; current input/held item determines them next step.

## Electrical hazards

`MedicalRiskRules.electrical_chance()` is the shared probability source for
world prompts and Medical. Local tripped breaker: 4%. Tripped generator: 8%.
Generator condition below 50 adds linearly up to 8 percentage points. Healthy
untripped equipment has no burn roll with nonzero odds. Global OFFLINE or
ONLINE labels do not determine danger. This is still a simple trip/damage
proxy; energized conductors, deliberate isolation and persistent fault causes
are not simulated by this pass.

Breaker reset jobs verify they are still tripped at completion. Generator
callbacks exclude stops, already-running starts, and failed untripped starts.
A real main-breaker reset still qualifies even if the generator cannot start.
Electrical burns affect one arm and record the restart as their cause.
Cooking's existing 4%-per-served-dish behavior remains unchanged this pass.

## Verification

`python3 tools/tests/run_medical.py --godot /path/to/Godot4.7`

Runs actual Player, PlayerStats, PlayerMedical, MedicalCondition, exertion and
feedback code in an isolated temporary project. Only neighboring interaction,
UI badge, focus/input-navigation and item-shoving contracts are doubled. Tests
cover input continuation, held objects, grace, per-limb recovery, FPS invariance,
accident cooldown, symptom bounds, conversion/treatment, provenance and legacy
save compatibility. `--screenshot /tmp/overdrive.png` also renders an isolated
feedback fixture using the desktop display. Data/config/cache are isolated.

`python3 tools/tests/run_device_inspectors.py --godot /path/to/Godot4.7`

Existing real panel/device-owner contract suite, extended for the local hazard
API and duplicate reset completion. Uses simulation doubles for power policy.
Neither suite proves full-bunker feel, rendering/lighting composition in every
scene, controller hardware, or long-run balance. Gameplay playtesting should
exercise emergency fuel hauling, sprinting with a damaged leg, resting in a
chair, and resetting both kinds of power device with the real solver.

## Next implementation slices

1. Water-quality consumption exposure and delayed gastrointestinal illness;
   preserve dose/quality through the actual drink action and saves.
2. Heat-aware cooking with a cooling/protection option, replacing the flat
   plating lottery; add active burn care and revisit wound dressing roles.
3. Share condition simulation and tuning between player/NPC while keeping
   their independent state and decision-making. Coordinate with NPC owner.
4. Hands-on hazardous repair/salvage and meaningful recovery/light duties;
   never injure players for remote build-menu operations.
5. Air hazards and spoiled food only after their upstream exposure/freshness
   systems exist. Add panting, exertion/mishap animations and feedback settings.

Keep these slices separate from the first pass: they need their own resource,
UI and behavior contracts and should not be silently approximated by unrelated
random injury rolls.
