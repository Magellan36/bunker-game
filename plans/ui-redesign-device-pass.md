# Approved device inspector family pass — September 2026

Base: compact generator commit `1a8680a6741a355aaa8006263c43abafb7c6fa5a`.
This is a separate reversible local pass; earlier character/generator commits
remain intact. No GitHub publication is required to install it.

## Scope and review gates

| Family | This pass |
|---|---|
| Generator S/M/L | Preserve approved design; add live-host walk-away closing, native functional icons, layout settling fix |
| Water dispenser | Compact native port; real stored fill/quality, request slider, receiving rate, priority and on/off |
| Water hookup/sink/purifier | Shared native port; all existing modes/metrics, conditional warnings and sink priority |
| Single/double farming trays | Shared native port; cell cards, growth/health, shortage warnings, NPC seed locks and priority |
| Consumer priority (wall/grow lights/load test) | Native port; original priority and optional load toggle contracts |
| Battery S/M/L | Extracted inspector; live charge/state/enable; retain Health at the existing 100% stub |
| Standard/smart breaker | Extracted shared inspector; zones, authoritative sharing state, locked trip state and existing restart job |
| Character creation | No redesign or sizing change |
| HUD and all held/unique workflows | No changes; review before implementation |

## Visual specification

Keep the approved warm charcoal, ivory, darker worn-brass framing and project
blue. Semantic green/warning/critical states always include text, not colour
alone. No fullscreen dimmer or modal takeover for these panels.

The shared width is 500 px at 1080p; right margin 24 px; height is 740 px for
generator/dispenser/purifier/farm, 600 for hookup/sink, 540 for consumer priority,
620 for battery and 660 for breaker. Smaller viewports clamp height and scroll
details. Font size never shrinks below the desktop baseline; growth above
1080p is capped at 1.25×. Typography/controls match the generator: title24,
body18, state16, help14, hint13; normal actions44, primary48, Close40.

Header/status/footer stay visible; long details (especially double trays)
scroll. A deferred refit on minimum-size changes handles initial word-wrapping
and changing warnings without leaving an oversized panel behind.

## Organization and behavior

See `scripts/ui/README.md` for exact edit points. Common native widgets are
shared; domain files contain readable layout composition plus thin adapters.
Battery and breaker world files no longer own screen drawing, input hit boxes,
fonts or panel palette. They keep state and action ownership.

- All new inspectors bind the actual device to `UIProximityClose`. The helper
  follows moving hosts, closes beyond the existing 3 m distance, closes when
  the host disappears, and safely re-resolves a replaced player. Returning to
  range does not reopen anything. Existing position-only callers still work.
- WASD/left stick remain movement; D-pad navigates UI. Generator inspection no
  longer misuses `InteractionSystem.build_mode_active`. Existing controller-nav
  gating prevents confirm input falling through to world interactions.
- Escape/E/B and Close share idempotent dismissal. Native popup menus take
  their own input while open, without disabling the world-interaction gate.
- Reopen starts at the top. Confirmed state is shown after actions; a refresh
  never emits slider/toggle writes. The dispenser world's existing per-frame
  request clamp is unchanged; the UI does not add a second clamp-write path.
- Water allocation remains demand/priority based, never equal-split. Quality
  boundaries stay <=50 critical, <=75 warning, above75 good. Purifier flow
  display bands stay below2500/below4000/4000+, separate from filter wear.
- Farms preserve ready/dormant/stalled/countdown, plant health thresholds,
  fertilizer and missing-soil states. Seed locks remain NPC-only; exhausted
  stock retains the chosen lock and labels it unavailable. Open dropdowns are
  not reordered beneath the selection.
- Battery Health is deliberately visible at 100%, with a not-yet-active note.
  Future integration: change the owner snapshot's `health` and
  `health_implemented`, not the panel layout. No battery-health sim is added.
- Breaker restart still calls the owner's existing `_request_restart()` timed
  job and `_finish_restart()` hazard roll. PowerManager retains all reset policy,
  including smart-group pre-trip sharing restoration and possible retripping.
  Panel snapshots use `get_breakers()` for authoritative sharing, since
  `set_tripped()` does not synchronize the world's cached sharing fields.
  Changing one toggle preserves the manager's other flag.
- World banners, physical meshes, HUD, simulation and save/load formats stay
  outside this presentation pass.

## Artwork and disclosure

No new raster or SVG artwork is added. Status/play/stop/grid/fuel/shield/power,
water-fill, battery, plant and warning symbols are drawn by
`BunkerSymbolTexture.gd` using Godot rendering primitives and used as normal
Button/TextureRect resources. Cards, dividers, progress bars, focus, hover,
buttons and fade use native Godot controls/styles/tweens.

The six older generator SVG placeholders are no longer runtime dependencies
of these inspectors. Their original files and provenance remain tracked, marked
retired in the manifest. Character-creation imagery is unchanged and still
labeled. `check_ui_placeholders.py --release` must still fail while these
development files remain; no release-clean claim is made.

Steam's current [Content Survey guidance](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)
distinguishes productivity use of AI tools from AI-created shipped content
consumed by players. This pass is a maintainability/asset-dependency improvement,
not a ruling that code-drawn visuals automatically escape disclosure. Keep
provenance honest and confirm borderline content with Valve before release.

## Tests and installation review

- `python3 tools/tests/run_device_inspectors.py --godot /path/to/godot`
- `tools/tests/GeneratorInspectUITest.tscn`
- `tools/tests/CharacterCreationUITest.tscn`
- `python3 tools/tests/check_ui_placeholders.py` (development pass)
- `python3 tools/tests/check_ui_placeholders.py --release` (expected blocker)
- `git diff --check`

The device runner copies real migrated UI and generator/battery/breaker owners
into an isolated temporary project with explicit test doubles for simulation
and water/farming device data. Fixtures use `.fixture` suffixes to avoid global
class-name conflicts in the real game. No game project, save, autoload or asset
is overwritten. Six actual viewport sizes: 1280×720, 1366×768, 1920×1080,
2560×1440, 3440×1440 and 3840×2160. Headless Godot4.6.1 validation is not the
target Godot4.7/.NET renderer or a full-world solver test.

Recorded result: **2,396 device assertions passed**, including exposed-world
click-through, panel click containment, higher-layer cancel ownership, seed-popup
walk-away dismissal, and controller-driven movement triggering closure. The
existing generator six-resolution/input suite, character-creation six-resolution
suite, and generator owner bridge also passed. Development provenance check
passed; release provenance check correctly failed on retained placeholders.

In the real game, verify:

1. Open each listed device at native1080p and720p. Check icons, margins, readable
   text, focus, scrolling, no backdrop, and world visibility/click boundaries.
2. Walk away using WASD and controller left stick, return, then explicitly
   reopen. Repeat with a seed popup open. Deconstruct a host while inspected.
3. Toggle generator/battery/consumer/dispenser state; change priorities and flow.
   Observe live changes from depletion, repairs, graph edits and power shedding.
4. Test purifier disconnected/low-quality/high-flow states and both warnings.
5. Test one/two trays, missing soil, partial water, growing/stalled/ready crops,
   fertilizer, per-cell NPC seed locks and out-of-stock labels.
6. Test standard and smart trips; locked controls, timed restart cancellation
   and completion, injury behavior, smart-group restored intent/retripping,
   and zone rename/recolour updates. Simulation behavior must remain unchanged.
7. Stack pause/settings over an inspector. Closing the top menu must not close
   the inspector beneath it. Check controller A/B/D-pad and keyboard Enter/Esc/E.
