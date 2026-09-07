# UI consistency pass — September 2026

Approved scope: all 35 recommendations from the consistency audit. Baseline
`038ae2981179177a417118af46f2f8b6609250cf`. Work belongs on `testing`; `main`
remains the player-tested baseline until explicit promotion. No force pushes.

## Recoverable checkpoints

1. **Shared foundations**: authoritative palette, native control skin, motion
   preference/timings, interruptible fades, preview updates, bounded layout,
   controller ownership and range/scroll helpers. Device-family integration.
   Validation: Godot 4.7.2; isolated motion/layout contracts passed;
   device UI/owner contracts passed 2,396 checks over six resolutions.
2. **Screen-family integration**: bounded layouts across Build, Storage, Pause,
   Graphics, Confirmation, Zone Customization, Power, Research, Status and NPC;
   Build's approved 440 x 760 left rail; input-aware recurring hints; restrained
   interruptible tab/detail transitions; retained Shop cart rows with exact
   focus/scroll restoration; Reduced UI Motion in Graphics; and immediate logical
   close with a short visual exit that a reopen can cancel. Validation: the full
   Godot 4.7.2 UI screen-smoke set passes.
3. **Final verification and documentation** (pending): UI reference, screen
   coverage, integration/visual checks, approval checklist and remaining limits.

Checkpoints are incremental, not a claim that the entire pass is already done.

## Locked contracts

- Keep the approved warm charcoal/ivory/worn brass/blue design and UI families.
- Ordinary device inspectors: right rail, no backdrop, live world movement,
  real host binding and walk-away close. Full-screen/specialist menus differ.
- Keep gameplay state, purchases, treatments, storage mappings and jobs with
  their current owners. No simulation/save schema changes.
- Build: one-click placement, catalog stays open, left rail matching Storage
  dimensions; virtual pointer remains the deliberate right-stick exception.
- Needs: approved original colors/look, midpoint icons, 45-degree rotation,
  balanced caps and directional depletion. Medical healing layers stay intact.
- Inventory: four light-item slots, original meter/pip meanings, name-only
  transient plates no wider than a tile. Fuel/container prompt meters deferred.
- Low-health vignette, cash transaction feedback and hold-progress complete.
  NPC debug labels preserved. No new asset replacement or gameplay design pass.
- Preview pools/prewarming stay intact. Animation must never delay state or
  replay on unchanged data, nor allow a stale exit to hide a reopened screen.

## Validation environment

The current project declares Godot **4.7**; 4.6 lacks the already-used
`Control.custom_maximum_size` property. Use 4.7.2 for this pass. Isolated
contracts use real UI sources with explicit simulation doubles; they do not
claim to validate the full game, GPU appearance, or physical controller feel.
