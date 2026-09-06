# UI Motion Audit

The needs gauge establishes the preferred motion language: live values ease to
their new state, structural transitions are brief, and animation communicates
change rather than decorating idle screens.

## Included in this pass

- Medical severity rings
- Medical healing rings
- Infection outer rings
- Ordinary status-effect timer refreshes
- Status badge reflow after an effect is removed

Badge arrival, dismissal, healing sheen, critical breathing, and expiration
feedback remain intact.

## Strong candidates for later passes

1. **Device inspector meters** — fuel, condition, charge, water quantity, and
   crop growth should ease between simulation ticks just like the needs gauge.
2. **Status and NPC overview meters** — health and needs can ease without
   delaying the underlying values or treatment controls.
3. **Power Terminal live data** — load totals, battery charge, and graph traces
   would benefit from interpolation while breaker and priority changes remain
   immediate.
4. **Storage and item preview details** — selection changes can cross-fade the
   preview and detail card, while inventory transfers remain immediate.
5. **Research progress** — active research fill and completion-state changes
   can ease; locked/unlocked state must remain unambiguous.

## Areas that should remain immediate

- Confirmation dialogs and destructive decisions
- Controller focus and button selection
- Shop quantity and checkout arithmetic
- Build placement validity and cursor feedback
- Warnings requiring immediate player action

These interactions depend on exact, instantaneous feedback. Adding easing to
them would make the interface feel less responsive rather than more polished.
