# Loading Screen Redesign

## Approved direction

The loading screen follows the same visual family as the approved character
creation screen: a quiet blue-black bunker backdrop, worn brass separators,
large ivory branding, clear blue functional accents, and a single substantial
information card.

At 1920x1080 the presentation is centered inside a 760x720 design area. It
scales down as one unit on smaller viewports rather than allowing its contents
to bleed off screen.

## Runtime contract

- `MainWorld.tscn` still loads on a background thread.
- MainWorld is instantiated beneath the loading layer so its dynamic setup and
  preloaded build/shop preview pools complete before the bunker is revealed.
- The handoff still waits for MainWorld's `startup_ready` signal.
- The indicator is intentionally indeterminate. Threaded resource progress and
  MainWorld's asynchronous warmup are not one reliable percentage, so the UI
  does not claim a false `100%` before the world is usable.
- The stage copy changes only at truthful milestones: resource preparation,
  bunker-system startup, and ready.
- A single survival tip remains stable for each short load instead of changing
  before it can be read.
- Failed resource requests expose a visible, focusable **Try again** action.

## Asset provenance

The shelter mark, lightbulb, architectural linework, ornaments, background,
and loading animation are all drawn with Godot code. No generated or imported
bitmap was added for this screen. The original approved mockup remains the
visual reference only.

## Files

- `scripts/ui/loading/LoadingScreen.gd` — composition and loading lifecycle
- `scripts/ui/loading/LoadingBackdropArt.gd` — responsive architectural art
- `scripts/ui/loading/LoadingIndicator.gd` — indeterminate activity indicator
- `scripts/ui/common/BunkerSymbolTexture.gd` — reusable shelter and tip symbols
