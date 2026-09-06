# Needs Gauge Redesign

The survival gauge keeps its compact five-arc silhouette while adopting the shared 2026 bunker UI language.

## Presentation

- The whole arc composition is rotated 45 degrees counter-clockwise.
- Health and stamina face into the lower-left screen corner.
- Food, water, and sleep fan outward into the playable view.
- Each need has a small, code-rendered symbol centered on its own semicircle.
- The original HUD colors, rugged arc rendering, tracks, and center are preserved.
- Value and cap changes ease into place without changing the established bar treatment.

## Medical need caps

Caps and ordinary depletion are intentionally separate visual concepts.

- Ordinary depletion remains directional from the established zero end toward the full end.
- A cap removes half of its unavailable range from each end of the semicircle.
- A 90% cap therefore locks 5% at the zero end and 5% at the full end.
- The remaining value is drawn directionally inside the usable interval.
- As an infection worsens, both locked ends close toward the middle of the arc.

This makes reduced maximum capacity readable without changing the player's learned direction of normal need loss.

## Asset policy

All shapes, symbols, tracks, and animation are rendered by Godot code. The visual mockup is not shipped as an asset.
