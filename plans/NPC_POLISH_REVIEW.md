# NPC Polish / Cleanup Review (Sep 2026)

> **Status (implemented on `claude/gifted-planck-32j7ii`):** every item in
> sections 1–4 is addressed, plus the extras below; see
> `docs/systems/npc/README.md` → "Architecture & guarantees (Sep 2026)" for
> how the system works now. Section 5's NPC.gd split was done as components
> (`scripts/npc/components/`) rather than moving existing state out of NPC.gd,
> to keep every external caller (UI, admin menu, save system) unchanged.
> Additional issues found while testing with the new simulation harness
> (`tools/tests/run_npc_sim.sh`) and rendered captures, all fixed:
> NPC capsule wider than the navmesh agent (wedging in corners); furniture
> stand points assigning a floor-level Y to the capsule centre (NPCs sinking
> through the floor); arrive-but-out-of-reach freezes at bulky objects;
> straight-line target picking choosing unreachable items (starvation loop);
> Cooking/Gardening availability checks that `enter()` couldn't act on;
> Gardening soil/seed mismatch infinite loop; Cleaning basket flow; the bed
> lie-down turning the wrong way from one side of the bed; gender not saved.


Full read-through of `scripts/npc/**` (NPC.gd, NPCBrain, all activities,
NPCItemUser, NPCCaseFetch, JobBoard, NPCJobQueries, NPCMedical, NPCDebug,
BunkerNavMesh) plus the NPC save/restore in `MainWorld.gd`. No code was
changed in this pass. Findings are grouped by how sure/serious they are:

1. **Confirmed bugs**: verified by reading the code path end to end.
2. **Save/load gaps**: state the player would notice being lost.
3. **Decision-making (brain/scoring)**: structural issues in the utility AI.
4. **Human-likeness**: behavior polish for more natural NPCs.
5. **Architecture/cleanup**: debt that will slow down new jobs.
6. **Performance**: fine at today's NPC counts, but worth knowing about.

A suggested order of work is at the bottom.

---

## 1. Confirmed bugs

### 1.1 Wander exit throws the NPC backwards (velocity extrapolation)
`WanderActivity.exit()` calls `npc.halt_movement(1.0)`
(`activities/WanderActivity.gd:35`). `halt_movement()` does
`lerp(velocity, 0, acceleration * delta)` = `lerp(v, 0, 8.0)`. GDScript's
`lerp` does **not** clamp the weight, so the result is `v + (0 - v) * 8 = -7v`.
Every time Wander is preempted mid-walk, the NPC's velocity flips to about
7× its walking speed, backwards. `move_and_slide()` runs the same frame, and
the next activity's `nav_steer()` only lerps back about 13% per frame. You see
a visible backward lurch/slide, and it can feed the stuck-recovery and wall
wedging.
**Fix:** use `npc.lock_movement()` in `WanderActivity.exit()`, and make
`halt_movement()` / `nav_steer()` / `_on_velocity_computed()` clamp their weight
with `minf(acceleration * delta, 1.0)` so this can't come back.

### 1.2 Beds are almost never used while any chair is free
`SitActivity.score()` and `LieActivity.score()` use the **identical** formula
`(100 - energy) * passive_mult` (`SitActivity.gd:45`, `LieActivity.gd:24`).
`NPCBrain._think()` keeps the first candidate on ties (`s > best_score`), and
`SitActivity` is listed before `LieActivity` (`NPCBrain.gd:32-33`). So a tired
NPC always picks a chair when one is free. It naps there to 90 energy at the
slower 25/h regen, and only uses a bed when every chair is taken.
**Fix (quick):** give Lie a multiplier (for example ×1.15) or a flat bonus.
**Fix (better):** see 4.1 (sleep schedule). Sleep should be a Lie-first
behavior, and chairs should be for short rests.

### 1.3 Item-claim leak in EatActivity (half-eaten cans become invisible)
After `grab_loose()` / `grab_from_shelf()` succeeds, EatActivity clears
`_loose` / `_shelf_pick` **without** `release_item()`
(`EatActivity.gd:98-99`, `113-114`). If the NPC fills up (≥95) before a
FoodCan is empty, `eat_held_step()` drops the can, and `exit()` only releases
`held_item`, which is already null. The claim stays in
`NPCItemUser._claims` forever. `find_loose_item()` and the cleaning queries
skip items `is_claimed_by_other`, so **no other NPC can ever eat or tidy that
can again.** `GiveToFriendActivity` has the same leak on hand-off (`:61`, `:80`).
**Fix:** release the claim inside `NPCItemUser.drop_held()` and when an item is
consumed or handed off. The more robust option: have `is_claimed_by_other()`
treat a claim as void when the claimant isn't holding the item and isn't
actively targeting it. You could also add an expiry timestamp to claims.

### 1.4 Stuck-recovery false-fires on slow NPCs
The stuck check needs 0.15 m of movement per 0.25 s (0.6 m/s) with a 0.5 s
grace (`NPC.gd` STUCK_* constants). The speed multipliers stack. For example,
an elder (×0.75) with a Broken leg (×0.25) moves at 2.2 × 0.19 ≈ 0.41 m/s, so
**they are "stuck" every half second**. Each recovery calls `stop_current()`,
**drops the held item** and position-teleports the NPC. Very tired, hungry and
low-mood NPCs (0.65 × 0.9 × 0.9 × 0.85 ≈ 0.45 → 0.99 m/s) are close to the
limit too, especially while avoidance slows them near others.
**Fix:** compare displacement to the NPC's *expected* travel
(`move_speed * get_status_speed_multiplier() * interval * 0.35`), not a fixed
0.15 m.

### 1.5 Stuck "nudge" teleports ignore collision
`_nudge_free_of_obstruction()` does `global_position += away * distance`
(`NPC.gd:2297`) with distances up to 2.5 m and no collision or navmesh check.
The comments already name this as the cause of "NPCs clipping through walls
and disappearing". It is capped now, but not prevented.
**Fix:** snap the destination with
`NavigationServer3D.map_get_closest_point(nav_map, candidate)`, and/or use
`test_move()` before committing. If both fail, don't move.

### 1.6 Talk initiator keeps "talking" to a partner who walked off
The partner's TalkActivity becomes interruptible when hungry or thirsty, and
the partner's `exit()` never tells the initiator. The initiator's `tick()` only
checks `is_instance_valid(_partner)`. It keeps facing an empty spot for up to
20 s, then logs "Talked to X" and applies a relationship swing for a
conversation that didn't happen.
**Fix:** in the initiator's `tick()`, end the session when
`not _partner.brain.is_talking()`. Also have the non-initiator's `exit()` call
back into the initiator.

### 1.7 Talk swing is rolled separately on each side
`apply_talk_relationship_swing()` is called independently for the initiator
and the partner, each with its own `_random_sign()`. The same conversation can
be "Good" for A and "Bad" for B. It also produces 4 action-log lines per talk:
"Talked to X" ×2 and "Relationship…" ×2. See 4.4 for the better model.

### 1.8 Double-wrapped Relax label
`RelaxActivity.label()` returns `"Relaxing (%s)" % _inner.label()`, and
`RelaxSitActivity.label()` already returns `"Relaxing (Sitting)"`. The overhead
label ends up reading **"Relaxing (Relaxing (Sitting))"**. `RelaxLieActivity`
does the same. Make the inner labels return just `"Sitting"` / `"Lying down"`.

### 1.9 Time-skip mood drift scales linearly instead of by √time
Live mood drift is a per-5 s random nudge. Summed over time it behaves like a
random walk, with spread ∝ √hours. `_catch_up_mood()` applies one
`randf_range(-1, 1) * h` (`NPC.gd:2816`), so a 24 h skip can swing mood by
±24 × 1.5 = **±36** from noise alone, while the same 24 h lived normally
rarely moves it more than a few points.
**Fix:** multiply by `sqrt(h)` in the catch-up path.

### 1.10 Medical work-speed penalty is never applied; age only partly
`NPCMedical.get_medical_job_speed_multiplier()` exists but nothing calls it.
`get_age_work_mult()` is applied in JobActivity and RefuelActivity only.
Cleaning, Gardening and Cooking ignore both. A Broken-armed 70-year-old
gardens at full speed.
**Fix:** one `npc.get_work_speed_mult(skill_key)` that combines
age × medical × skill (and optionally mood), called by every work timer.

### 1.11 Smaller confirmed issues
- `GiveToFriendActivity` never finishes if the hand-off is refused:
  `_friend = null`, but `done()` also needs `held_item == null`. It only
  self-heals because PutAwayHeldItem (score 20) eventually wins. Drop or put
  the item away explicitly. Also, `npc_holds_nothing()` is a stub that always
  returns true.
- `JobActivity` doesn't claim its fetch item, so two filter jobs can race for
  the same spare. `_complete()` for HARVEST sends the "harvested the crops"
  notification even when the plant wasn't ready.
- `JobActivity` sets `npc.velocity = Vector3.ZERO` directly instead of
  `lock_movement()` (`_movement_locked` isn't raised, so a late avoidance
  callback can overwrite the stop). `PutAwayHeldItemActivity` does the same.
- `PassedOutActivity` doesn't drop a held item, so an NPC can "pass out"
  still holding a can at chest height.
- `CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR` duplicates
  `PassedOutActivity.REGEN_PER_GAME_HOUR` "keep in sync" style. Reference the
  class constant directly (`PassedOutActivity.REGEN_PER_GAME_HOUR`).
- The `_catch_up_relax_budget()` comment still describes the old 60-min
  budget (it's 3 h now). The `catch_up_all()` header says sleep calls it, but
  SleepOverlay now fast-forwards via `Engine.time_scale` and only the F7
  button calls it.

---

## 2. Save/load gaps (high player impact)

`MainWorld._get_npcs_for_save()` persists only: position, name, needs,
skills, seed, mood, id and relationships. On load, `_ready()` runs first and
**re-randomizes** everything else. `generation_seed` is saved but nothing
derives personality from it; `randomize_personality()` uses the global RNG.
After every load:

| Lost / re-rolled on load | Effect |
|---|---|
| `personality` | **Every NPC gets new traits on each load** (Lazy becomes Hard Worker, etc.) |
| `age`, `_birthday_day_of_year` | New age every load |
| `health`, `irritability`, `*_cap` | Starvation damage and irritability reset |
| Medical conditions | Wounds, infections and fractures vanish |
| `gift_saturation`, snatch/talk cooldowns | Gift-spam exploit resets on reload |
| Relax budget / cooldown | Budget refills |
| `_action_log` | Player-facing history wiped |
| `_contagion_exposure`, `job_state` blacklist | Minor |

**Fix:**
- Either seed a local `RandomNumberGenerator` from `generation_seed` for
  personality, skills, age and birthday, so saving the seed is enough, or
  save those fields explicitly. Explicit saving is simpler and survives
  future tuning changes to the generators.
- Add `get_save_dict()` / `load_save_dict()` on NPC (and NPCMedical)
  so MainWorld stops reaching into fields.
- Set position **before** `add_child()` (via `position` on the unparented
  node), so `_ready()` and the first physics frame don't run at the origin.
- Store action-log timestamps as game time, not `Time.get_ticks_msec()`
  (msec restarts at 0 each launch, so "Xs ago" is wrong after a reload).

---

## 3. Decision-making (brain / scoring)

### 3.1 Scores live on three different scales
- Needs: 0 until the 55 threshold, then **jump straight to ~52** (Eat
  `(100-h)*1.15`, Drink `*1.2`, Sit/Lie `100-e` from 60 → 40).
- JobBoard jobs (HARVEST/REPLACE_FILTER): base 55–65 × skill × priority, so
  **~40–95**.
- Session jobs (Cleaning/Refuel/Gardening/Cooking) and idle activities:
  **~3–10**.

Consequences:
- An NPC at hunger 45 (Eat ≈ 63) will harvest (≈ 71 × 1.3 priority) before
  eating.
- A generator at 1% fuel (Refuel = 8) loses to any harvest.
- The 55 cliff means NPCs never eat opportunistically ("I'm walking past the
  shelf and I'm at 65, grab a snack"). Needs are either ignored or they
  override everything.
- Every job's base score has been hand-tuned against Wander/Relax by
  arithmetic in comments (see the long calibration notes on
  GARDENING_BASE_SCORE / CLUTTER_URGENCY_STEP). Each new job will need that
  same exercise again.

**Recommendation:** normalize every activity to
`score = weight × curve(input)`, with curves returning 0..1 (for example
`urgency = smoothstep(70, 10, hunger)`). Needs get weight ~100, jobs ~40–60,
idle ~5–10. Jobs get an urgency curve too: Refuel from fuel %, Cleaning from
clutter, Filter from quality, Harvest from time-since-ready. Then "starving
beats everything, a dying generator beats relaxing, a tidy bunker loses to
wandering" falls out of the curves instead of per-constant comments. It also
makes a new job a two-number decision: weight and curve.

### 3.2 Session jobs can't be interrupted by needs
Refuel, Gardening and Cooking inherit `interruptible() = false` for the whole
session, and nothing inside checks needs. Only pass-out (energy 0) breaks
them. A big gardening sweep keeps going while an NPC is starving or
dehydrated. Cleaning got a between-items safe window; the others didn't.
**Fix:** add a `_at_safe_checkpoint()` hook to `NPCSessionActivity` (called
between tasks, when nothing is claimed or held). At that point, end the
session if any need is below a "critical" line (for example 25), or if the
brain reports a candidate beating the session by a large margin. This keeps
the "never abort mid-carry" guarantee the base class was built for.

### 3.3 Two parallel job systems
HARVEST and REPLACE_FILTER use `JobBoard` + `JobActivity` (claim per job, one
throwaway `JobActivity` per open job per think). Everything newer uses
`NPCSessionActivity` + `NPCJobQueries`. Harvest also exists a second time
inside `GardeningActivity` (the "farming" command mode). Each new job has to
pick a pattern, and fixes land in one path but not the other.
**Recommendation:** migrate HARVEST and REPLACE_FILTER to session activities.
A HarvestActivity would sweep all ready plants like Refuel sweeps generators.
Keep JobBoard as the *discovery/caching* layer only (its cleaning scan is
already used that way).

### 3.4 Three separate reservation systems
Item claims (`NPCItemUser._claims`), cell claims (`_cell_claims`) and JobBoard
`claimed_by` behave differently. Two are keyed by instance ID and have no
validity check or expiry, and only JobBoard auto-releases a freed claimant.
**Recommendation:** use one `Reservations` helper keyed by
`(kind, id)` → `{npc, since}`. It would auto-drop an entry when the NPC is
invalid or the entry is older than N seconds without a refresh, and would
have a `release_all(npc)` that `NPCBrain.stop_current()` calls. That removes
the whole leak class in 1.3.

### 3.5 Hysteresis ignores commitment
`SWITCH_MARGIN = 8` is absolute. On the needs scale (~50–100) that's small;
on the idle/job scale (~3–10) it's larger than most scores, so a Relax at 6
can never be preempted by a Gardening at 8, and Talk at 5.5 can't lose to
Cleaning at 7. Once scores are normalized (3.1), use a relative margin (for
example 15%) plus a short "commitment" bonus that decays over the first few
seconds of an activity.

### 3.6 Nearest-by-straight-line target choice
Every `find_*` picks by `flat_distance`. Through walls, the "nearest" can is
often a long walk away while a slightly farther one sits in the same room.
For the top 2–3 candidates, compare path length
(`NavigationServer3D.map_get_path` and sum the segments). Cache the result for
the think tick.

---

## 4. Human-likeness improvements

### 4.1 A day/night routine (biggest "feels alive" win)
Energy drains 3/h and sleep only triggers below 60. That gives a roughly 13 h
awake / 1 h asleep cycle that drifts around the clock, with no relation to
day or night. People sleep at night. Suggested model:
- A sleep-pressure need (energy works), plus a **circadian term** from
  `PlayerStats` hour. The Lie score gets a large bonus from about 22:00–06:00
  and a penalty during the day.
- Lower bed regen (about 12–13/h, so a full night restores about 100) and
  wake on "morning + rested", not "energy == 100".
- Personality hook: an early-bird / night-owl offset of ±2 h (seeded).
- Lighting and noise could matter later (don't sleep under a lit grow light).

### 4.2 Wander should have intent
Wander targets are a uniformly random cleared cell anywhere in the bunker.
Replace them with weighted points of interest: near friends (relationship >
Friendly), lit rooms, seats, near food and water when mildly peckish, and the
NPC's own "home" bed or area. Add short micro-behaviors on arrival: look
around, turn toward the nearest person, idle 3–8 s. This also increases
chance encounters for Talk (4.4) in a believable way.

### 4.3 Mood needs events, not just needs
Mood currently depends only on the needs average (with a cliff at 70: 69.9
targets 69.9, 70.0 targets 100), plus contagion and noise. Nothing good or bad
that *happens* moves it, except pass-out.
- Replace the cliff with a smooth mapping (for example
  `target = lerp(needs_avg, 100, smoothstep(55, 85, needs_avg))`).
- Add short-lived **mood modifiers** ("moodlets") with a value and a decay:
  ate a cooked dish +5, ate cold canned food −1, slept in a bed +3, slept on
  the floor / passed out −8, good conversation +2, got snatched from −6,
  received a gift +4, relaxed +2, bunker dirty (clutter > N) −3, dark bunker
  −2. Show them in the E-panel ("Why is Mara unhappy?"). This gives the player
  levers and makes the Cooking and Cleaning jobs visibly matter.

### 4.4 Conversations with real outcomes
- Roll **one** quality per conversation, shared by both participants (see
  1.7), biased by: mutual relationship, both moods, both irritability, and
  trait compatibility (for example similar optimism +, sociability sum +, a
  Neurotic and Irritable pair −). The expected value becomes something the
  player can reason about, instead of today's 50/50 coin flip (expected
  value 0).
- Let NPCs *seek* a talk partner during Relax (walk over), instead of needing
  to randomly end up within 3 m.
- Log one line per conversation ("Talked with Dez — good chat (+2)").
- Cheap visual: alternate a "speaking" and "listening" idle, or a small
  speech-bubble glyph, so a talk looks like a talk.

### 4.5 Relationship-aware dialogue with the player
`get_dialogue_line()` ignores the relationship with the player. An NPC who is
**Hostile** toward the player but in a good mood says "Hey! Good to see you."
Pick the pool from relationship first, then tint it by mood and irritability.
The Hostile/Cold pools you already wrote for "Ask about" can be reused as-is.

### 4.6 Relationship proximity counts through walls
Proximity gain and contagion exposure use a 4 m XZ radius with no line of
sight. Neighbors on opposite sides of a wall "bond". Add a cheap raycast, or
compare room/cell connectivity, and only count people you can actually see.

### 4.7 Resting fallbacks look robotic
- Relax with no chair or bed → stands frozen in place for 20–40 game-min
  (20–40 real seconds). Fall back to "lean or sit on the floor" or a slow
  pace instead.
- Lie and pass-out are teleport-and-rotate (the README already names this).
  Pass-out rotates the whole CharacterBody3D 90° around Z, so the capsule
  collider goes sideways and can clip into walls. Rotate the visual model
  only, and keep the body upright.

### 4.8 Skills should be visible and matter
Skills are 0.6–1.4, grow by 0.01 per job, only bias JobActivity's score, and
`construction` is never used. Make skill scale work speed (see 1.10) and
maybe output (harvest yield, cook quality), show it in the E-panel, and
have Gardening, Cooking and Cleaning grant skill.

---

## 5. Architecture & cleanup

- **NPC.gd is 2,833 lines**, and roughly 40% of it is comments. Consider
  splitting into composed RefCounted components, following your own
  `NPCJobState` / `NPCMedical` precedent: `NPCNeeds` (needs, health,
  catch-up), `NPCPersonality` (traits, age, birthday, multipliers),
  `NPCSocial` (relationships, talk, give, snatch, cooldowns),
  `NPCStuckRecovery`, `NPCActionLog`. NPC.gd keeps locomotion, lifecycle and
  a thin facade.
- **Dead code:** `current_task`, `assign_task()`, `perform_task()`,
  `_state`/`NPCState`, `_enter_idle()`/`_enter_wandering()`,
  `_process_wander()`, `_check_stuck()` (all superseded by the brain). The
  duplicated two branches in `_physics_process()` exist only to carry this.
- **Pass-through wrappers:** about 12 `NPC.find_*` / `has_*_available` /
  `get_*_unavailable_reason` methods only forward to `NPCJobQueries`, each
  with a long comment. Callers can use `NPCJobQueries` directly.
  `is_trash_item()` calls `JobBoard._is_trash_item` (a private method).
- **Magic numbers:** the need-low threshold `55.0` is written out in Eat,
  Drink, Talk, GiveToFriend, CookingActivity and `has_needy_friend()` next to
  a named `TAKEAWAY_NEED_THRESHOLD` with the same value. Use one
  `NPC.NEED_LOW`, and likewise `NEED_SATED = 90`.
- **Duplicated code:** `JobActivity._approach_point` = `NPCSessionActivity.approach_point`;
  `_find_free_chair` / `_find_free_bed` are the same nearest-free-in-group
  loop; Eat's `enter()` and `_reacquire_or_finish()` are copy-pasted target
  acquisition.
- **Duck typing on typed nodes:** `has_method("get_relationship")`,
  `"npc_id" in other`, `npc.set("_pending_stand_pos", …)` on an `NPC`-typed
  value. Since `class_name NPC` exists, `if other is NPC` plus direct calls is
  faster, type-checked and easier to read. Add `NPC.request_stand_at(pos)`
  instead of `set()` on private fields.
- **Clocks:** there are three time sources: game-hours (needs, mood),
  physics delta (talk/eat/clean durations) and **wall-clock msec** (talk,
  snatch and gift cooldowns, cleaning idle gate, hostile log). Msec ignores
  pause, `Engine.time_scale` sleep fast-forward and reloads. At 4× sleep, a
  "60 s" snatch cooldown lasts 240 game-seconds. Also, `game_hours(delta)`
  ignores `PlayerStats.time_multiplier` (the F12 tool), so NPC needs don't
  speed up with the clock. Add one `GameClock.now_hours()` and express every
  cooldown in game time.
- **Comment density:** many comments are change-log history ("Aug 2026 fix
  (Brannon-requested) — raised 6.0→10.0 …"). Moving history into the plan
  docs and git, and keeping only the *why* in code, would roughly halve file
  sizes and make the real contracts easier to see.

---

## 6. Performance (fine now; matters at 10+ NPCs)

- Each hungry NPC's `EatActivity.score()` runs `find_loose_item`,
  `find_shelved_item`, `find_fetch_target` (which runs both again) and the
  snatch scan, all full group iterations, every think. `enter()` repeats
  them. Drink is similar. A per-frame shared cache ("nearest edible
  candidates this tick") or a small world index maintained by JobBoard would
  collapse this.
- Every NPC walks the `npc` group three times per 5 s mood tick
  (relationships, exposure, contagion target) plus once more in
  `_name_for_relationship_id` for the debug label. Merge the first three
  into one loop.
- `SnatchActivity.enter()` and a few other call sites build debug format
  strings before `NPCDebug.log_*` checks `enabled`. Gate them with
  `if NPCDebug.enabled`.
- `ProjectSettings.get_setting("physics/3d/default_gravity")` runs every
  physics frame per NPC. Cache it once.

---

## Suggested order of work

1. **Quick bug fixes (small, low risk):** 1.1, 1.2 (quick version), 1.3,
   1.6, 1.8, 1.9, and the 1.11 items.
2. **Save/load (section 2):** before any playtesting that involves
   reloading. Otherwise, every personality-driven tuning result is suspect.
3. **Stuck recovery (1.4 + 1.5):** speed-relative threshold and
   navmesh-snapped nudges.
4. **Unified work-speed multiplier (1.10)** and need checkpoints in session
   jobs (3.2).
5. **Score normalization (3.1) + relative hysteresis (3.5):** do this before
   adding more jobs, since every new job multiplies the retuning cost.
6. **Reservations unification (3.4)** and **HARVEST/FILTER → session
   activities (3.3).**
7. **Human-likeness layer:** day/night sleep (4.1), mood modifiers (4.3),
   conversation outcomes (4.4), purposeful wander (4.2), dialogue (4.5).
8. **NPC.gd split + dead-code removal (section 5):** easiest right after
   step 2, since save/load touches every component boundary.
