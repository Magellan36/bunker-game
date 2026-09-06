# UI Motion System

The needs gauge establishes the preferred motion language: live presentation
eases to authoritative state, structural transitions are brief, and animation
communicates change rather than decorating idle screens.

## Shared behavior

`BunkerSmoothProgressBar` supplies one response curve for live meters. Its
first update snaps to truthful state; later updates interpolate visually.
Simulation values, labels, warnings, and gameplay decisions are never delayed.

`UIPreviewMotion` cross-fades existing TextureRect surfaces. It does not create,
destroy, or duplicate SubViewports, so the project's preloaded preview strategy
and performance safeguards remain intact.

## Implemented consumers

- Generator, battery, breaker, water, farming, and other shared device meters
- Player Status summary, needs, condition severity, and recovery meters
- NPC needs, skills, and relationship marker
- Power Terminal load, reserve, source/device meters, numeric live readings,
  and newest history-graph samples
- Storage capacity and selected-item state meters
- Build, Shop, Storage, Status inventory, and other shared item cards
- Research materials and active research progress
- Medical and ordinary HUD status-effect rings and badge reflow

## Deliberately immediate

- Confirmation dialogs and destructive decisions
- Controller focus and button selection
- Shop quantity, cash, and checkout arithmetic
- Build placement validity and cursor feedback
- Treatment outcomes and inventory ownership
- Power priorities, breaker state, and warnings requiring immediate action

Easing these interactions would weaken responsiveness or briefly display a
misleading state, so they remain exact and instantaneous.
