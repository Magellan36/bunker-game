# UI redesign — generator inspector pass

## Scope and approved anchor

The in-engine character-creation screen is the approved visual anchor: solid
warm charcoal, ivory type, project-blue interactions, worn darker brass for
structure, robust controls and clear wording. Keep that identity, not its
full-screen menu scale. The subsequent generator review explicitly requested
a slender right-docked PC inspector with the game visible and no dimming.

This pass migrates only the generator inspector and fixes initial scroll
position on character creation. It does not restyle the other menus, change
power simulation, introduce shop behavior or enable parked character options.
The compact follow-up changes generator presentation only; character creation
and the original generator owner/action implementation remain unchanged.

## Files and ownership

| File | Responsibility |
|---|---|
| `scripts/ui/power/GeneratorInspectUI.gd` | CanvasLayer adapter preserving open/refresh/close and the existing action signals. |
| `scenes/ui/power/GeneratorInspectPanel.tscn` | Native header, status cards, rated output, fuel/condition meters, backup button and persistent action footer. |
| `scripts/ui/common/BunkerInspectorLayout.gd` | Right-docked, screen-local sizing and metadata-driven metrics using a private theme; no gameplay state. |
| `assets/ui/themes/BunkerRedesignTheme.tres` | Existing character theme unchanged in its original entries; additive inspector styles/tokens. |
| `scripts/world/power/GeneratorObject.gd` | Existing action owner; small signal/callback adapter keeps the visible inspector current. |
| `tools/tests/GeneratorInspectUITest.tscn` | Multi-resolution and native-input/state regression entry point. |

## Layout specification

- Base panel: **500×740 at a 1920×1080 UI viewport**, right-docked with a
  **24 px right margin**, vertically centered. This supersedes the original
  centered 820×950 first-pass layout.
- Local scale: 1.0–1.25 based on the smaller viewport/design ratio. Maintain
  base text sizes at 720p; reduce the scroll region instead. Scale the safe
  margin with the panel. Ultrawide cannot inflate it beyond 625 px wide.
- Solid charcoal surface, 12 px radius, thin worn-brass outline. **No full-screen
  darkening or blur**: the Backdrop node and opacity token are removed. The
  full-viewport root ignores mouse input; the panel stops it within its bounds.
- Base spacing: 20 px panel inset, 10 px section gaps, 6 px scroll-focus inset.
  Body/actions 18 px, state labels 16 px, help 14 px, navigation/eyebrow 13 px,
  title 24 px and rated wattage 28 px. Backup is 44 px high, main action 48 px,
  Close 40 px. Bars are 12 px high; state icons 24 px. Keep the approved visual
  hierarchy at desktop density rather than making everything a touch target.
- Button content margins are 16×8 px in the inspector's private theme. Do not
  shrink the shared character-creation button styles or scene.
- Header: blue power icon, small POWER SYSTEM eyebrow, large actual device name,
  native Close button. No generated background image.
- Two equal status cards: running/stopped/standby/offline, and global grid state.
  Text and icons supplement colour; Running and Grid online use green.
- Details: rated wattage, fuel and condition bars with explicit percentages and
  severity wording, then a full-width Backup mode: On/Off toggle and explanation.
- Normal 1080p content fits without scrolling. The details region may scroll at
  smaller sizes or with longer text; header, states and main action stay visible.
- Main action: blue Start generator, warm-red Shut down generator, or
  Reset grid & start when stopped after a trip. Wording explains the consequence.
- Warm ivory focus ring stays separate from selection. Initial focus is on
  Close, so opening the panel never primes an accidental shutdown.
- Opening uses the existing 150 ms UIFade on the whole control tree. No
  decorative loops or additional animation system.

## Data and behavior contract

The existing open/refresh signatures are unchanged. Buttons only emit requested
values; confirmed state comes back from the owner. The panel neither changes
PowerManager nor predicts success.

- Watts are rated capacity, not measured output. Do not display fabricated live
  generation, fuel runtime or efficiency.
- Grid is the existing global PowerManager state. A tooltip explicitly says
  this does not prove the selected generator is wired into it.
- Fuel warnings retain the original 50% / 20% thresholds; condition retains
  50% / 25%. A textual warning supplements the bar colour.
- Start remains actionable with zero fuel/condition, preserving the existing
  reset-attempt flow. The explanation makes the unmet needs clear.
- GeneratorObject forwards fuel/running callbacks and draw/grid signals as one
  deferred refresh per frame only while the panel is visible. Every refresh
  reads the current manager getters. No new poller, solver, or autoload.
- Existing restart medical-hazard logic and backup policy are untouched.
- Mouse, Enter/Space, Tab/arrows, D-pad and A/B work through native controls and
  the existing controller helper. Left-stick gameplay policy is unchanged.
- Escape/E respect higher-layer menus; B closes only the topmost controller UI.
- Reopening resets details to the top; close is idempotent.

## Artwork provenance

Six added SVG masks are AI-authored development placeholders: running, stopped,
grid, fuel, condition and power. Every filename and embedded SVG comment is
marked AI_PLACEHOLDER and every asset is in the existing manifest. The final
game still requires zero AI-authored artwork. Water-fill artwork remains for
the next water-panel pass.

## Validation and handoff

- Run `tools/tests/GeneratorInspectUITest.tscn`.
- Run `tools/tests/CharacterCreationUITest.tscn`.
- Run `python3 tools/tests/check_ui_placeholders.py`.
- Release mode (`--release`) must fail while any placeholder remains.

Headless verification uses actual 1280×720, 1366×768, 1600×900, 1920×1080,
2560×1440 and 3440×1440 viewports, not stretched versions of a single viewport.
Tests cover compact dimensions/right docking, exposed-world click-through,
panel click containment, absent dimming layer, readable text/control floors,
all grid-state label bounds, persistent actions, live resizing, scrolling/focus, state
labels, clamping, preserved warning thresholds, signal-only actions, native
mouse/keyboard/controller input, higher-menu cancellation, independent instances
and reopen. Character tests verify top-of-scroll opening for both saved genders
while later focus navigation still scrolls correctly.

An additional isolated bridge check used the real GeneratorObject and UI with
a test-double power manager to verify callback/signal forwarding and the
existing reset/start path. This is not a full solver or world-integration test.
Validation was performed with portable Godot 4.6.1. The user's target
Godot 4.7/.NET project remains the required visual/full-world review.

Review in game: Generator S/M/L; start, stop and backup; tripped-grid restart;
fuel depletion; condition changes; keyboard/controller; 720p and native desktop
resolution. Preserve the compact revision as a separate reversible commit over
the original generator pass; keep both previous UI commits available.
