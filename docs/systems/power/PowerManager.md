# PowerManager.gd — per-script detail

Read `README.md` in this folder first — this doc only covers what that one
doesn't: `PowerManager.gd`'s internal structure and the grid mechanics in
enough detail to safely change them without opening the 3600-line file.

## Role
Orchestrator for the whole power system. Owns the public API + all signals
(see README's tables — not repeated here). Owns the grid state machine, the
`_solve_network()` entry point, reachability (adjacency/BFS), and the
generator/battery tick simulation. Delegates wire-graph CRUD to
`PowerGraph.gd`, consumer/generator/battery CRUD to `PowerRegistry.gd`, and
the actual shed/unshed zone evaluation to `PowerSolver.gd` — all three hold a
plain `_owner: PowerManager` back-reference and reach into `PowerManager`'s
own dicts (`_wire_nodes`, `_wire_edges`, `_consumers`, `_generators`,
`_batteries`, `_breakers`) rather than owning copies. `PowerManager` keeps
identical-signature forwarding wrapper methods for every function it
delegates, so none of the ~64 external call sites across the repo needed to
change when the split happened.

## Grid state machine
`ONLINE → BROWNOUT → OVERLOADED → TRIPPED → OFFLINE`
- **BROWNOUT** — load-shed active (priority 5→2 items cut), grid still running.
- **OVERLOADED** — 5s grace period (`OVERLOAD_GRACE_SECS`), then auto-escalates
  to TRIPPED if not resolved.
- **TRIPPED** — manual reset only via `reset_main_breaker()`
  (`MAIN_AUTO_RESET_SECS = -1` means no auto-reset).
- **OFFLINE** — no generators AND no battery charge. Requires repair/refuel
  before a reset attempt can succeed.

## Standard vs. smart/upgraded breaker exhaustion
- **Standard breaker (`BreakerBox.gd`):** at exhaustion, ALL generators
  feeding the exhausted component trip; BOTH zones sharing that component go
  into sustained brownout (shed/orange, lights keep a dim glow — no tier-1
  limp power). Recovery is manual generator restart ONLY — no timer, no
  auto-recovery. Latched via `_exhausted_brownout_keys`
  (`_component_sig_key`/`_sustained_brownout_component` track which
  component is latched; `clear_exhausted_brownout()` is called by
  `set_generator_running(id, true)` before the next solve).
- **Upgraded/"smart" breaker (`UpgradedBreakerBox.gd`):** self-trips
  REACTIVELY at exhaustion to isolate zones instead — generator side STAYS
  UP, only the offending/load-only side goes into brownout (not full
  offline). Shows a TRIPPED banner + RESTART button in the shared breaker
  settings panel; pass-through toggles lock while tripped. Resetting one
  smart breaker resets ALL breakers in the same `trip_group_key` (same
  exhaustion event) — the solver then re-evaluates fresh: re-trips
  automatically if still overpowering, resumes normally if load dropped
  enough.

## Priority-change grace period
`set_consumer_priority(id, priority)` no longer resets shed state and
resolves immediately — it queues the id into `_pending_priority_reset_ids`
and a `PRIORITY_CHANGE_GRACE_SECS` (0.5s) timer in `_process()` fires the
actual `_reset_shed_for_consumer_component()` + `_solve_network()` once it
elapses. Multiple priority changes inside the window collapse into one
resolve. Exists because an immediate reset+resolve could visibly flash the
grid through a transient state before settling. The displayed priority value
(`_consumers[id]["priority"]`) still updates instantly for UI — only the
grid-affecting part is delayed.

## Cross-zone sharing & batteries
Breakers with `pass_battery`/`pass_generator = true` let load/generation flow
between zones via `PowerSolver`'s 3-pass evaluator (see `README.md`'s call
graph). Battery charge/discharge correctly flows across such breakers via
`_flood_gen_component_keys()` BFS component flooding — NOT a single-zone
lookup (a single-zone lookup was the exact root cause of the July 2026
"batteries on shared zones don't charge from neighboring generators" bug;
fixed by swapping in the same BFS the rest of the system already used).

## Bulk operations
`begin_bulk()` / `end_bulk()` — wrap multiple register/unregister calls (e.g.
during a chunk expansion's wire graph patch) so `_solve_network()` doesn't
re-run after every single mutation; `end_bulk()` triggers one solve at the
end. `request_solve()` forces a solve (or defers it if still inside a bulk
block, i.e. `_bulk_depth > 0`) — added specifically because
`register_wire_edge()`'s existing-edge early-return used to skip marking
`_needs_resolve`, causing `active_draw` to go stale after some rebuilds (see
`HANDOVER.md`/repo history for the postmortem if ever needed — fixed, not
currently a live bug).

## Data tables
`WATT_RATINGS`, `DEFAULT_PRIORITY_BY_TYPE`, `GENERATOR_TIERS`,
`STATE_EMISSION_COLORS` all live on the `DeviceDatabase` autoload (not on
`PowerManager` itself) — access from anywhere as `DeviceDatabase.WATT_RATINGS`
etc., no `PowerManager` dependency needed.
