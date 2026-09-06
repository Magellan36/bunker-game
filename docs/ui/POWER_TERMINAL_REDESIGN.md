# Power Terminal Redesign

## Approved visual contract

The Power Terminal is a specialized desktop dashboard, not a stretched device
inspector. It uses a centered 1360 × 800 maximum workspace with the bunker still
visible behind a moderate backdrop. The visual hierarchy follows the approved
generator, dispenser, and character-creation language: charcoal surfaces, ivory
type, worn dark-brass edges, bunker blue for selection/data, and reserved
green/amber/red system states.

The Overview mirrors the approved mockup:

- header identity, live grid-state pill, and a large close target;
- Overview, Devices, Load Priority, and Zone Network tabs;
- Current Load, Headroom, and Battery Reserve summary cards;
- a persistent live-load/capacity graph covering the last 60 seconds;
- power-source cards with generator fuel/condition and battery charge states;
- zone identity, color, topology, brownout and cross-zone-flow summaries;
- a compact active-consumer roster and direct route to priority management;
- a reset action that remains disabled while the relevant zone/grid is healthy.

Dense device rosters, priority controls, and cross-zone diagnostics are moved to
their own bounded scrollable tabs. This preserves all information without making
the first screen read like a debug dump.

## Preserved gameplay contracts

- The same `PowerManager.get_debug_snapshot()` and `get_zone_snapshot()` data
  remains authoritative.
- Terminal zone scoping, legacy reachable-grid fallback, local generators,
  batteries, consumers, shared batteries, remote consumers, import/export flow,
  brownout state, and wire topology are retained.
- Priority buttons still call `set_consumer_priority()` and preserve the focused
  controller target while the grid's existing grace period settles.
- Rename and color actions still open the existing `ZoneCustomizeUI`; that
  specialized UI is intentionally not redesigned here.
- Reset still targets the connected zone, falling back to the main breaker for
  an unscoped terminal.
- History persists across close/reopen because the terminal UI is reused rather
  than freed. Every new open starts on Overview and resets scroll positions.
- The player can still move while the terminal is open. D-pad and right stick
  navigate UI controls, while the left stick remains player movement. Walking
  away now closes the terminal consistently with other in-world inspectors.

The previous immediate-mode `PowerTerminalUI.gd` is retained in the project as a
reference/fallback; `PowerTerminal.gd` now loads `PowerTerminalModernUI.gd`.
