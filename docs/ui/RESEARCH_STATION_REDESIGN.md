# Research Station Redesign

## Approved visual contract

The Research Station is a substantial desktop research workspace, not a
stretched device inspector. It uses a centered 1360 × 800 maximum panel with
the bunker retained behind a moderate backdrop. Charcoal surfaces, ivory
hierarchy, worn dark-brass edges, bunker-blue selection/data and restrained
green/amber states match the approved Generator, Power Terminal and Zone
Customization family.

The header, three progression tabs and four material reservoirs remain fixed.
The Bunker Upgrades page divides into a bounded scrollable dependency canvas
and a selected-upgrade inspector. Nodes show spatial progression and state;
the inspector owns description, real current/next effects, requirements,
stored amounts, duration, active progress, tier segments and the primary
action. This prevents research nodes from becoming miniature dashboards.

## Preserved gameplay contracts

- `ResearchStation` remains authoritative for stored materials, the 10-unit
  caps, incremental consumption, active research, pause state and tier
  progress.
- `WaterOutput2xUpgrade` remains the only functional upgrade. Its three real
  completions and `WaterHookup.TIER_DAILY_ML` values drive the inspector.
- Start, pause and resume call the existing station methods directly.
- Material counts and active progress update without rebuilding hovered or
  focused controls every frame.
- The material chute and trash-bag feed behavior are untouched.
- Player Skills and NPC Skills remain honest empty states until their data and
  effects exist.
- Locked downstream pathway cards are presentation scaffolding only.
- Every open returns to Bunker Upgrades, 100% tree zoom and top scroll.
- D-pad/right stick navigate, LB/RB change tabs, A/Enter select, and B/Escape/E
  close. The left stick remains player movement.
- Walking beyond interaction range closes the station through the shared
  proximity helper.

## File boundary

`ResearchStationModernUI.gd` owns the workspace and live bindings.
`ResearchPathCanvas.gd` only draws the blueprint grid and dependency lines.
The legacy `ResearchStationUI.gd` is retained untouched as a fallback.
`MainWorld.gd` instantiates the modern UI at the same lifecycle point and
continues injecting it into the existing station and interaction gate.
