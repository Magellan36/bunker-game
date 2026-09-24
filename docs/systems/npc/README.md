# NPC System

Last reconciled with the implementation: September 23, 2026.

This is the canonical overview of the resident NPC system. Historical “pass”
and “part” comments in source files explain why code was introduced; they are
not a reliable statement of current scope. When this document and source ever
disagree, update this document in the same change that updates the source.

## Runtime architecture

Each resident is an instance of `res://scenes/npc/NPC.tscn`:

- `NPC.gd` owns identity, needs, relationships, personality, movement,
  navigation helpers, stuck recovery, player interaction, and time skipping.
- `NPCBrain.gd` runs the utility decision loop and owns the current activity.
- `NPCActivity.gd` defines the activity lifecycle. Concrete activities live in
  `scripts/npc/activities/`.
- `NPCMedical.gd` owns that resident's medical conditions and derived caps.
- `NPCJobState.gd` owns per-resident job exclusions and cleaning blacklists.
- `NPCItemUser.gd`, `NPCCaseFetch.gd`, and `NPCJobQueries.gd` provide shared
  item, container, and world-query operations.
- `JobBoard.gd` is the global source of claimable harvest and purifier-filter
  jobs.
- `BunkerNavMesh.gd` owns the runtime navigation region and asynchronous
  rebakes.
- `NPCAttentionController.gd` is a presentation-only child that arbitrates
  short-lived gaze stimuli without participating in utility scoring.
- `NPCMetrics.gd` provides disabled-by-default aggregate counters,
  histograms, and a bounded recent-event ring.
- `NPCDebug.gd` centralizes optional NPC diagnostics.

The scene uses `AdventurerModel.tscn` for both the visible model and its
shadow-only counterpart. The physical capsule is explicitly 0.4m radius and
1.8m height. The navigation bake uses a 0.5m agent radius to retain a 0.1m
wall/corner clearance; dynamic avoidance uses the physical 0.4m radius.

## Decision model

`NPCBrain` thinks once per second. Initial think times are staggered so the
population does not evaluate on the same frame.

The persistent autonomous candidates are:

- Wander
- Sit and lie down for low energy
- Drink and eat
- Relax
- Talk
- Give an item to a friend
- Clean and organize
- Refuel generators
- Put away an item already being held
- Garden
- Cook and serve food

The brain also creates a temporary `JobActivity` for every open `JobBoard`
job. Currently those jobs are one job per harvestable plant and purifier
filter replacement.

The highest positive score wins when there is no current activity. A running
activity can switch only when it is interruptible and the challenger exceeds
its score by its `switch_margin()`:

- Wander uses 0.25 so nearby social opportunities and ordinary useful work
  can readily replace aimless movement.
- Relax uses 0.75 so actual work can replace a break without near-tied passive
  activities constantly swapping.
- Other activities default to 2.0. Sustained sessions are non-interruptible by
  default, with explicit safe-window exceptions such as Cleaning between
  items.

Player commands bypass utility scoring. Passing out also bypasses scoring and
preempts the current activity immediately.

Forgetfulness is only rolled when a `JobActivity` is about to start. A
successful roll substitutes a 20-second non-interruptible wander. It does not
apply to needs, social activity, or the sustained cleaning/refuel/garden/cook
sessions.

## Activity lifecycle

Every activity implements some subset of:

- `score(npc)` — current utility; zero means unavailable.
- `enter(npc)` — acquire claims and establish the initial target.
- `tick(npc, delta)` — advance navigation or work.
- `done(npc)` — report natural completion.
- `interruptible()` — whether utility selection may preempt it now.
- `switch_margin()` — score advantage required to preempt it.
- `exit(npc)` — release claims, seats, and temporary state.
- `take_handoff()` — request an exact successor without a fresh utility pick.
- `debug_info()` — structured state for diagnostics.

`NPCSessionActivity` is the base for sustained fetch/travel/apply loops. Its
default is non-interruptible because interrupting a claimed or carried task is
rarely safe. Command wrapper activities are also non-interruptible.

## Navigation and locomotion

`BunkerNavMesh` builds a `NavigationMesh` from static colliders on physics bit
1 and supplements the source geometry with cleared bunker floor cells. It
rebakes after excavation/restoration signals and after its placed-object
fingerprint changes. Rebakes are debounced and asynchronous.

Every NPC creates a `NavigationAgent3D` at runtime. `set_nav_target()` first
projects the requested position to the closest point on the current navigation
map. This is important because many interactable transforms are at the center
of a collider rather than on walkable floor.

`nav_steer()` submits preferred horizontal velocity. Godot avoidance returns a
safe velocity through `velocity_computed`; that safe velocity is accelerated
into the `CharacterBody3D` velocity. Animation is driven by achieved physical
velocity, not requested velocity. The agent's `max_speed` and the callback's
final horizontal clamp both use the resident's status-adjusted requested speed.
Avoidance may redirect a resident but cannot accelerate one during congestion
or a task retarget.

Stationary activity transitions clamp their deceleration interpolation to the
physical `0..1` range. A one-shot hard stop may reach zero immediately, but it
can never extrapolate through zero, reverse direction, or create a speed spike.

Returned path points receive a `-0.9m` `path_height_offset` so they align with
the NPC root. Godot subtracts this property from path-point Y, so the negative
sign raises floor-level points; a positive value puts them below the floor and
prevents the agent from ever satisfying its 3D waypoint tolerance. Waypoint
tolerance is therefore a tight 0.35m instead of a large value that permits
corner cutting. The final target tolerance remains 1.1m, and activities
additionally use flat/XZ interaction ranges. Furniture activities temporarily
request a precise 0.2m final tolerance and navigate to the animation's actual
approach anchor.

Stationary interactions use runtime slot leases. Chairs and beds provide
authored approach transforms; other work and observation targets currently
receive four orientation-stable generated candidates that are projected onto
the navigation map. Candidates are ranked by complete navigation-path length,
not straight-line distance, so a point on the far side of a wall cannot win
merely because it is geometrically close. A full NPC-capsule physics query
also rejects standing space currently occupied by moved furniture or loose
objects that are not part of the latest navmesh bake. A lease records
position, facing, action, target, and capacity group, prevents two residents
from committing to the same final space, uses weak ownership, and is released
on retarget, interruption, despawn, or target removal. Leases and live Node
references are never saved.

Open bunker doors expose a narrow-passage portal. Within the immediate
approach, at most two residents may enter in one direction during a short
batch; opposing residents wait outside the opening, and the oldest waiter
selects the next direction after the passage clears. This arbitration sits
above `NavigationAgent3D` avoidance and reserves only the doorway—not paths or
rooms. Closed-door route planning and NPC door operation remain separate
future decisions.

Bulky loose pickup items register dynamic navigation obstacles while they are
in the world and disable them while held or stored. Soft clutter below the
three-kilogram threshold—including food cans, water bottles, purifier filters,
medicine, and similar inventory-sized objects—does not participate in RVO and
is ignored by corridor-blocker recovery. Characters can walk straight through
these objects; a bounded foot-level query applies small repeated impulses in
the character's travel direction so even a large pile visibly parts without
slowing or rerouting the resident. NPCs and the player otherwise participate
in dynamic avoidance.

NPC activities and stuck recovery never assign the resident root's
`global_position`. Normal displacement comes from `move_and_slide()`.
Chair and bed use navigate precisely to their authored approach point, then
the shared sit/lie/stand animation moves to the furniture and returns to that
same captured point. Save/load restoration, developer spawning, and the
below-world abyss rescue are the only intentional out-of-band placement paths.

### Wandering

Free time is shaped by a deterministic behavior profile derived from the
resident's saved generation seed and personality. The profile supplies a stable
sitting preference, patience, restlessness, novelty tendency, social distance,
and favored landmark category. These values alter leisure timing and selection;
they do not bypass needs, job priority, or navigation safety.

Wandering alternates between an observation pause and a bounded ambient agenda
of two to four coherent intentions.
A resident may visit another currently available resident (weighted by
Sociability), walk to a built kitchen/garden/storage/power/common-area
landmark, or deliberately cross the cleared bunker. Landmark categories reuse
existing scene groups instead of maintaining a separate room graph. Each
resident has a deterministic preferred landmark category, avoids its three most
recent targets, and reserves a destination while
travelling or observing so several residents do not converge on one object.

The intention retains its target through travel, follows a moving social
target, times out cleanly, and exposes its purpose, phase, target, destination,
and remaining time through `debug_info()`. It remains the low-score Wander
candidate in utility terms, so needs and work readily preempt it. These are
semantic free-time destinations, not a daily schedule or a room simulation.

If free travel is interrupted at a safe travel checkpoint, the brain may retain
one semantic intention for up to two game-hours. It stores only destination,
purpose, and an optional target path—not a Node reference, navigation path,
claim, item-transfer state, or animation phase. Resumption happens only after
the interrupting activity finishes, revalidates/reclaims the target, and still
competes normally against real needs and work.

### Sitting around

When little else needs doing, leisure planning can select a free chair for a
prolonged 45–120 game-minute sitting session. Session length and selection
frequency are stable per-resident tendencies, so some residents visibly sit
more while others roam. This is distinct from low-energy `SitActivity`: it uses
the same authored sit/stand animation and exclusive chair claim but regenerates
energy slowly and consumes the existing daily leisure budget. Leisure sitting
is passive and utility-interruptible; a higher-priority need or job requests the
normal stand-up transition and takes over without teleporting the resident.

### Stuck recovery

Stuck checks run only while an unfinished navigation request is actively being
steered. Expected progress scales with the NPC's requested speed, avoiding
false positives for elderly, exhausted, or injured residents.

Recovery escalates:

1. Re-project and request a fresh path without cancelling the intention.
2. If another grace window also fails, stop the activity cleanly and identify
   a loose item, another NPC, or static collision when possible.
3. Congestion with another resident or an unidentified stall yields the
   current intention and re-scores without changing the resident's position.
4. A blocking loose item may be handled by a forced one-item cleaning session.
5. Repeated item jams blacklist that item for the resident; static-geometry
   jams yield and re-score. No recovery branch directly relocates a resident.

The debug event includes the current activity label and its structured state.

## Needs, health, age, and medical state

Residents have Energy, Hunger, Thirst, Health, and Mood in the range 0–100,
plus Irritability. Energy, Hunger, and Thirst drain on the compressed game
clock. Health drains when Hunger or Thirst reaches zero; both sources stack.
Health reaching zero currently has no death or crisis behavior.

Low Energy, Hunger, Thirst, Mood, age 65+, and medical conditions multiply
movement speed. Elder residents also perform timed work at 0.75 speed where
the activity applies `get_age_work_mult()`.

Energy at zero causes `PassedOutActivity`. It is non-interruptible and restores
energy until the 15-point wake threshold. This is currently a functional
pose rather than a complete bespoke collapse/wake animation.

`NPCMedical` supports the same six acute conditions currently implemented for
the player: open wound, bleeding, infection, fracture, broken bone, and burn.
It applies healing, treatment, speed, and needs-cap effects. Most normal-world
NPC injury triggers are not implemented yet. The medical work-speed aggregate
is also not consistently consumed by every NPC activity.

## Personality and social behavior

Personality contains optional values for resilience, sociability, work ethic,
neuroticism, and optimism. Missing traits behave as neutral values.

- Resilience affects irritability and forgetfulness resistance.
- Sociability affects relationship movement and talk scoring.
- Work ethic biases job scores against passive/need scores.
- Neuroticism affects mood volatility.
- Optimism affects mood recovery.

Relationships use stable `npc_id` keys and include the player under `player`.
Talking is available when a compatible NPC is already nearby. A talk session
faces the pair toward one another, runs for a bounded duration, then applies a
small relationship outcome and cooldown. Dialogue content is selected for the
player UI; autonomous conversations do not yet simulate topics or memories.

Friendly NPCs can fetch and give food or water to a resident in need. Hostile
relationships can cause snatching. Gifts from the player affect relationships
and use a decaying saturation value so repeated gifts have diminishing impact.

Personality and the deterministic behavior profile now create recognizable
leisure timing and preferred landmark habits. They do not yet create authored
daily schedules, semantic room ownership, or durable multi-day goals.

## Work and item behavior

### JobBoard jobs

- `HARVEST`: per-ready-plant job, Farming skill, no supply fetch.
- `REPLACE_FILTER`: purifier job, Plumbing skill, fetches a filter.

The board polls the world, validates jobs, arbitrates claims, and releases
claims when an NPC or target disappears.

### Sustained autonomous sessions

- Cleaning handles trash disposal, storage organization, produce baskets, and
  emergency obstruction clearing. `TrashCan.gd` provides the current
  `trash_receptacle` implementation. Pickup and delivery navigate to a
  reachable interaction side rather than an object's collider-center origin.
  Moving targets refresh that approach, each fetch/delivery leg has an
  18-second hard timeout, and failed/invalid routes release their item and slot
  claims before the session continues. The pickup-side inset includes the
  precise navigation arrival tolerance, so a completed path is still inside
  the actual item pickup range.
- Refueling fetches a fuel can and visits eligible generators.
- Gardening fills soil and plants cells autonomously. Harvesting remains a
  higher-priority JobBoard job. Player farming commands may also harvest and
  fertilize.
- Cooking handles pots, ingredients, powered stoves, cooking, plating,
  serving, and storage. It is available to autonomous utility selection as
  well as player commands.

Items and work cells use claims to reduce duplicate work. Activities must
release every claim in `exit()`. A held item left after an interruption is
handled by `PutAwayHeldItemActivity` when normal selection resumes.

## Rest and relaxation

Low-energy Sit and Lie activities use free chairs and beds, including occupancy
claims and the shared adventurer sit animation sequence.

Relaxing is separate from low-energy rest. It consumes a daily budget of three
game-hours for ordinary residents and six for Lazy residents, in sessions of
roughly 20–40 game-minutes. Sessions receive a randomized 1.5–3 game-hour
cooldown. The first player work request during a relaxation session can be
refused; repeating it succeeds with a relationship cost.

## Dynamic navigation and doors

`BunkerNavMesh.gd` rebuilds navigation from live static collision and publishes
revisioned, detached bakes atomically. Door collision changes are announced at
the end of their physical panel animation, so an opening can no longer be
baked from a half-open frame and remain disconnected. The placed-object
fingerprint includes transforms and rotation as a defensive fallback.

Every movement request keeps its raw intention separate from its projected
navmesh point and validates that a complete path reaches that projection.
Partial paths are failures, never arrivals. Sit and Lie additionally require
physical approach proximity before starting their root-motion sequences.

Each `BunkerDoor` owns a bidirectional navigation portal. A route may therefore
choose a closed door; an approaching resident requests it open, waits for the
panel animation/topology revision, then enters through the shared fair queue.
NPC door-open requests are idempotent and a closing door can queue one reopen.

Loose and moving physics items use shape-derived avoidance radii and publish
their velocity. Floor-placed frozen rigid bodies retain their obstacle instead
of disappearing from both static baking and avoidance.

## Companionship overlay

`NPCCompanionship.gd` represents "spending time" as a mutual, expiring pair
session above the utility activity layer. Both residents expose the shared
state in their overhead activity label. Gardening, Cleaning, Sitting, Lying,
and ordinary idle behavior continue to run; their autonomous target selection
prefers work and furniture within the partner's vicinity. This lets one
resident keep tending a garden while the other helps, tidies nearby clutter,
or rests nearby instead of locking both into a stare animation.

Sessions end for both participants on expiry, removal, incapacity, or prolonged
separation. Urgent needs and work may temporarily own movement without leaving
a stale one-sided social label.

## Player interaction

The resident profile UI is implemented by `NPCTalkMenuUI.gd` and documented in
`docs/ui/NPC_MENU_REDESIGN.md`. It exposes Overview, Talk, Requests, Health,
and Activity Log tabs. Quick requests cover food, water, and rest. Work orders
cover cleaning, refueling, unified farm tending, fertilizing, cooking, and
purifier filters according to the menu's current entries.

Commands force a wrapper activity after checking availability. Pass-out is the
only normal brain state that may supersede a command.

## Presentation attention

Each resident creates an `NPCAttentionController` child at runtime. Activities
may expose a task target, while the controller independently considers the
conversation partner, nearby player, moving residents, and low-salience
ambient glances. Stimuli are short-lived and carry a weak source reference,
world position, category, salience, expiry time, and whether body turning is
allowed.

Attention uses profile-shaped reaction and glance timing, conversation glance
aversion, and bounded angular acceleration. The current Adventurer rig has no
animation-safe additive head/upper-body hook, so player, resident, and ambient
glances remain internal presentation state. Whole-body fallback is reserved
for conversations and explicit stationary task/interaction phases; navigation
retains sole ownership of facing while a route is active. Authored interaction
slot orientation wins over generic object-facing. It never snaps via
`look_at()`.

Companionship travel assigns one resident as the follower while the invited
resident remains the leader. A moving leader is followed from behind with
pace matching and a small catch-up allowance; separate settle/resume distances
prevent rapid arrived/traveling oscillation. The follower enters observation
only after the leader has actually stopped.

Opening a resident's UI creates a reversible player-conversation pause. The
resident stops, reports `Talking to player`, and immediately faces the player,
but the current activity object is not exited or replaced: its phase, claims,
held item, timers, and route remain live. Closing the UI resumes that exact
activity with a five-second anti-thrash grace. Needs continue to decay during
the pause, and critical hunger, thirst, or exhaustion may bypass the grace;
passing out also closes the interaction and takes normal emergency priority.
Committed NPC-to-NPC and player conversations use the same immediate heading
response as ordinary locomotion while movement is locked; they do not depend
on the lower-priority ambient attention arbitration.

## Physics-clutter navigation

Structural pathfinding remains owned by the baked navigation mesh, while
`NPCDynamicObstacleMap` supplies a local occupancy layer for loose rigid
bodies. When route progress stalls, recovery first requests one fresh path,
then inspects the next few metres of the route against the items' current
world-space collision footprints. Recovery never moves an NPC transform.

The bounded response order is:

1. Take a verified left/right detour that rejoins the existing route.
2. If no detour is clear and one reachable loose item is responsible, pause
   the live activity and run `NPCClearPathActivity` as an overlay.
3. Move that one item to a navigation-reachable, physics-clear position
   outside the blocked corridor, restore the original target, then continue
   the exact same activity object.
4. Briefly yield to another resident, or report the route failed for static
   or unidentified blockage so the owning activity can choose another
   authored approach.

The overlay is separate from household Cleaning: it does not discard utility
intent, claims, phase timers, held-task state, or interaction-slot ownership,
and it has a hard duration limit. A critical need or pass-out may still abort
it. Residents already carrying an activity item may detour but will not stack
a second object into their hands. When a staging pocket has an open route, the
resident carries and places the blocker normally. When surrounding clutter
would deadlock that carrying route, the resident visibly lifts the blocker and
gives it one controlled, mass-scaled shove toward the verified empty pocket
before resuming. Ordinary contact pushes remain throttled per item rather than
firing every physics frame.

Stuck detection measures reduction in remaining route length, not arbitrary
body displacement, so sideways shuffling around clutter is not mistaken for
forward progress. The avoidance callback applies Godot's safe velocity
directly; blending an older unsafe velocity back into it would continue
pushing into an object after avoidance had asked the NPC to stop.

## Persistence

`MainWorld.gd` registers NPC data in save phase 4. The persisted baseline is:

- Position, name, and stable `npc_id`
- Energy, Hunger, Thirst, Health, and Mood
- Skills and personality
- Age, birthday, and resolved model gender
- Irritability, relationships, and gift saturation
- Relaxation budget/cooldown state
- Generation seed

Active activity, path, job claims, held items, short real-time social
cooldowns, and medical conditions are not persisted. On load, residents start
empty-handed and choose a fresh activity. Those omissions are deliberate
current limitations and must not be described as persisted behavior.

## Debugging

`NPCDebug.enabled` gates console diagnostics. `NPCMetrics.enabled` separately
gates aggregate counters, histograms, and a 64-entry recent-event ring; it is
disabled by default and can be toggled with `NPCMetrics.set_enabled()`. The
admin NPC tools can toggle logging, dump resident state or metrics,
spawn/despawn residents, adjust needs, randomize skills, and request a
navmesh rebake.

Available diagnostics include activity transitions and interrupt score
comparisons, forgetfulness rolls, jobs, cleaning/session state, mood,
irritability, relationships, and contextual stuck recovery.

The F7 admin menu also exposes a separate, disabled-by-default navigation
flight recorder. While enabled it retains a bounded recent sample ring per NPC
containing preferred, avoidance-safe, applied, and achieved velocity; route
target/waypoint state; and slide contacts. Its on-demand dump adds the current
stuck-recovery stage and nearby physics items with their avoidance footprint
and body state. Enabling or dumping it is observational and does not alter
movement, scoring, avoidance, or recovery.

Recovery metrics include stuck events, dynamic detours, clear attempts, and
clear success/failure. The navigation debug dump also reports active detour
and yield state, the recovery overlay and paused activity, and the verified
drop/resume targets.

Debugging is not yet a complete decision trace. It does not continuously emit
every candidate score or avoidance neighbor. Avoid adding gameplay gates that
depend on either debug switch; observation must not change NPC behavior.

## Current limitations and next architectural work

The implemented system is a utility-driven collection of capable activities,
not yet a full life simulation. Known missing layers include:

- Authored semantic rooms and object-specific slots beyond the current
  chair/bed anchors and generated workstation fallback
- Richer room-level traffic semantics beyond door portals and narrow-door arbitration
- Authored daily schedules and resumable work intentions
- Suspension/resumption for item-carrying or mid-application work phases
- Persistent semantic room ownership and multi-day habits
- Rich autonomous conversation content and memory
- Normal gameplay injury/crisis response
- Additive head/upper-body gaze once the character rig supports it safely

These are future improvements, not claims about current behavior.

## Change checklist

When changing NPC behavior:

1. Update this document if the candidate list, score contract, persistence,
   navigation contract, commands, or limitations changed.
2. Confirm claims and held items are released on every completion,
   interruption, target invalidation, and command path.
3. Test at least two NPCs approaching the same target and one target removed
   during travel.
4. Test an elderly/injured slow NPC so stuck recovery does not false-trigger.
5. Test a save/load cycle for any new identity-defining state.
6. Keep debug-only code observational; it must not alter scoring or timing.
