# Power System — Proposed Design vs. Actual Implementation Audit
**For:** the AI working on `bunker-game`. **Method:** read the proposed design as written in `PROJECT_SUMMARY.md` §6.2 ("Grid mechanics") — the only place in the repo that states how the power/zone system is *supposed* to behave — then traced each claim directly through `PowerManager.gd`, `PowerSolver.gd`, `PowerGraph.gd`, `WireSegment.gd`, and `WireGraphBuilder.gd` to check whether the code actually does what the doc says. No other design doc exists in the repo for this system (checked `PROJECT_SETUP.md`, `BUNKER_LAYOUT_SETUP.md`, `INTERACTION_SETUP.md`, `HUD_SETUP.md`, `HANDOVER.md` — none describe grid behavior, only setup/refactor history).

**Confirmed by Brannon:** the doc's stated state order is wrong. **The correct, intended flow is `ONLINE → OVERLOADED → BROWNOUT → TRIPPED → OFFLINE`.** This matches what the code actually does (see Finding 1) — so this is a **documentation bug, not a behavior bug**. Fix `PROJECT_SUMMARY.md`, not the code.

---

## Finding 1 — Confirmed: doc's state-order is wrong, code is correct

`PROJECT_SUMMARY.md` §6.2 states:
> **States:** `ONLINE → BROWNOUT → OVERLOADED → TRIPPED → OFFLINE`.

This transposes `BROWNOUT` and `OVERLOADED`. Traced every `grid_state = GridState.X` assignment in `PowerManager.gd` to confirm the real order:

- `PowerManager.gd:2972` — transition **into `OVERLOADED`** happens first, when demand exceeds capacity (guarded by `if bat_old != GridState.OVERLOADED`, i.e. this is the entry point from `ONLINE`).
- `PowerManager.gd:2797` — transition **into `BROWNOUT`** happens later, specifically once batteries covering the `OVERLOADED` deficit start running critically low ("Transition to BROWNOUT briefly so the HUD can show the right state").
- `PowerManager.gd:2859` (`_trip_main_grid()`) — transition **into `TRIPPED`**, and `PowerManager.gd:513-533`'s `_process()` shows this fires the very next frame after `grid_state == BROWNOUT` is observed (see Finding 2 — this part of the doc is accurate).
- `PowerManager.gd:2983` / `3456` — transition **into `OFFLINE`**, reached when there's no battery reserve left at all.

This also matches the enum's own inline doc-comments (`PowerManager.gd:153-159`), which the prose in §6.2 apparently wasn't cross-checked against:
```gdscript
enum GridState {
    ONLINE,       ## all reachable consumers powered, draw ≤ capacity
    OVERLOADED,   ## grid overloaded — managed via shedding / batteries
    BROWNOUT,     ## severe deficit after shedding — imminent total blackout
    TRIPPED,      ## main breaker blown — manual reset required
    OFFLINE,      ## no generators + no battery — true blackout
}
```
`BROWNOUT`'s own comment ("severe deficit **after shedding**") only makes sense as something that happens *after* `OVERLOADED` (which is the state where shedding actively happens), not before it. The enum declaration order itself (`ONLINE, OVERLOADED, BROWNOUT, TRIPPED, OFFLINE`) already matches the real behavior — the doc's prose is simply out of sync with the enum it's describing.

**Fix:** update `PROJECT_SUMMARY.md` §6.2's first bullet to `ONLINE → OVERLOADED → BROWNOUT → TRIPPED → OFFLINE`. No code changes needed — confirmed the implementation is the source of truth here.

---

## Finding 2 — Confirmed correct: "no grace period" claim holds up exactly as stated

Not in the summary doc directly, but embedded in a code comment citing an external design source (see Finding 4) — worth confirming since it's a specific, testable behavioral claim: *"BROWNOUT → instant trip (no grace period)."*

Checked `PowerManager._process()` (lines 513-540):
```gdscript
match grid_state:
    GridState.BROWNOUT:
        ## BROWNOUT → instant trip (no grace period).
        _trip_main_grid("overload")
```
This runs every frame; the very next `_process()` tick after `grid_state` becomes `BROWNOUT` calls `_trip_main_grid()` immediately. No accumulating timer gates this specific transition (the flicker system near line 2797 is a *different* mechanism tied to battery depletion, not this transition — see Finding 3 for why conflating the two is easy to do). **Genuinely instant, as documented.** No action needed — flagging only so it's not re-litigated later.

---

## Finding 3 — Real ambiguity: "BROWNOUT" names two different things in this codebase

This one isn't in the doc as a contradiction so much as an **underspecification** — §6.2 describes properties of "BROWNOUT" that actually belong to two distinct mechanisms sharing one name:

1. **Global `grid_state == GridState.BROWNOUT`** — a transient, single-frame waypoint on the way to `TRIPPED` (Finding 2). Lasts at most one `_process()` tick before `_trip_main_grid()` fires.
2. **Per-zone "sustained brownout"** (`PowerSolver._sustained_brownout_component()`, latched via `_owner._exhausted_brownout_keys`) — a **persistent, per-component** state that does *not* auto-resolve. Per its own comment: *"Latch so subsequent re-solves keep this component in brownout until a generator is manually restarted."* This is the mechanism that actually implements the doc's own later bullet — *"Standard breaker exhaustion: ALL feeding generators trip, BOTH shared zones go sustained-brownout. Recovery = manual generator restart only."*

These are two different things (one instantaneous and global, one persistent and per-zone) that both get called "brownout" in comments and doc prose, with nothing reconciling them. A reader taking §6.2's state-order bullet at face value could reasonably expect entering "BROWNOUT" to be a lingering, recoverable-without-a-trip state (since the doc's very next bullets talk about brownout *recovery* requiring manual generator restart) — when the global state by that name actually resolves in one frame, and the "recoverable, needs manual restart" behavior actually belongs to a separate, per-zone-scoped mechanism with its own latch.

**Fix suggestion:** in `PROJECT_SUMMARY.md` §6.2, split this into two explicitly named bullets — e.g. *"Global BROWNOUT state (transient, one-frame, always resolves to TRIPPED)"* vs. *"Per-zone sustained brownout (`_exhausted_brownout_keys`, persists until manual generator restart, used by breaker-exhaustion recovery)"* — rather than letting both live under one unqualified "BROWNOUT" heading.

---

## Finding 4 — `task.md`, cited in code as the source of core design decisions, does not exist in the repo

`PowerSolver.gd` line 625, directly above the 3-pass solver's docstring:
```gdscript
## Cross-zone SHARING RULES (from task.md decisions):
##   • Own-zone load served first — surplus is capacity MINUS own draw.
##   • Exporting zone stress: if (own_draw + exported_w) > capacity → overloaded.
##   • No grace periods — BROWNOUT → instant trip.
```
Searched the entire repo (`find . -iname "task.md"` and a broader filesystem search) — **no file named `task.md` exists anywhere in the project, past or present in git history that's part of this clone.** This means the actual origin/rationale for some fairly load-bearing design rules (the exact cross-zone stress formula, the no-grace-period decision) is only recoverable from this one comment block — if it's ever misremembered, edited, or the comment is moved without the context traveling with it, there's no committed document to check it against.

**Fix suggestion:** either commit whatever `task.md` was (if it still exists locally/in chat history somewhere) into the repo, or fold its decisions directly into `PROJECT_SUMMARY.md` §6.2 as the canonical source, and stop citing a file that isn't actually available to anyone auditing the repo from scratch (as this exercise just did).

---

## Finding 5 — "Priority 1, never shed" is true but narrower than it reads

§6.2: *"Load shedding: priority 1 (critical, never shed) → 5 (luxury, shed first)."*

Checked both shedding paths:

- **Everyday shedding** (`PowerSolver._shed_in_component()`, used in the `OVERLOADED` state): genuinely hard-floored. `SHED_START_PRIORITY = 5`, `SHED_END_PRIORITY = 2` (`PowerManager.gd:208-209`) — the loop `while priority >= SHED_END_PRIORITY` structurally cannot reach priority 1. Confirmed correct, matches the doc.
- **Sustained-brownout exhaustion path** (`PowerSolver._sustained_brownout_component()`): priority-1 consumers are still explicitly excluded from ever being marked `"shed"` — but they **do** get cut to `powered = false` in this path, same as everything else. The function's own comment makes the distinction explicit and deliberate:
  > *"Priority 1 (critical) is NEVER shed — even in a sustained brownout... These items go fully OFF (`set_powered(false)`, no orange dim) rather than SHED. The semantic is: 'shed' = temporarily reduced load that could come back; a critical item going dark means the whole grid is dead, not just load-shedding."*

So the guarantee is real but precise: priority 1 is never soft-shed (dimmed, expected to recover on its own), but it **is** hard-cut in a genuinely dead-grid scenario, same as everything else. §6.2's one-line summary ("never shed") is technically accurate but easy to misread as "never loses power," which isn't the guarantee actually being made.

**Fix suggestion:** tighten the doc line to something like *"priority 1 (critical) is never soft-shed — it only loses power if the entire zone/grid is down, and even then it's cut outright rather than dimmed."* Not a code fix — the code's own comment already gets this exactly right; the summary doc's compression of it is what loses the nuance.

---

## Verified correct, no discrepancy — listed for completeness

- **Cross-zone sharing via `pass_battery`/`pass_generator` breakers, 3-pass solver** — `_evaluate_pass1_local_surplus` → `_evaluate_pass2_cross_zone_sharing` → `_evaluate_pass3_zone_resolution` exist exactly as named and are called in that order from `_evaluate_per_component()`.
- **Smart/upgraded breaker self-trip isolation** — `_self_trip_upgraded_breaker()` forces `pass_battery = false, pass_generator = false` on the specific breaker and flags `_needs_resolve = true`; since severing those flags structurally re-partitions `get_wire_zones()` on the next solve, the generator-side zone is naturally re-evaluated as an independent component with its own local capacity, with no special-case code needed to "protect" it. Matches the doc's claim that only the deficit zone goes offline while the generator side stays up.
- **Wires visible only in build mode** — `WireSegment.gd` defaults `visible = false` at spawn ("Hidden until BuildModeController shows it"), and `BuildModeController.gd` toggles the entire `"wire_segment"` group's visibility on enter/exit build mode (lines 238, 269, 1397); `MainWorld.gd` also force-hides on a reset path (line 626). Confirmed correct.
- **Battery flow via BFS component flooding, not single-zone lookups** — `_flood_gen_component_keys` is a distinct helper from simple zone lookup and is what `_tick_batteries()`'s cross-zone charge/discharge accounting actually uses, matching the doc's claim.

---

## Summary of actionable items

1. **Fix `PROJECT_SUMMARY.md` §6.2's state-order bullet** to `ONLINE → OVERLOADED → BROWNOUT → TRIPPED → OFFLINE` (confirmed by Brannon as the intended flow, and matches both the code's actual behavior and the enum's own inline comments).
2. **Split the "BROWNOUT" bullet** into the two distinct mechanisms (global transient state vs. per-zone sustained/latched state) so a future reader doesn't conflate them (Finding 3).
3. **Commit or fold in `task.md`'s decisions** somewhere durable — right now the cross-zone sharing formula and the no-grace-period rule only exist as a code comment citing a file nobody auditing the repo can actually find (Finding 4).
4. **Tighten the "priority 1, never shed" line** to reflect the real, narrower guarantee the code already correctly implements (Finding 5).

No code changes are required by this audit — every actual behavioral discrepancy found resolves in the code's favor; the fixes are all documentation corrections.
