# HUD Time and Cash Polish

## Scope

This is a light presentation pass over the existing always-on HUD counters.
Their corner placement, update APIs, underlying clock/economy systems, and
cash-change feedback remain intact.

## Time and day

The top-center clock is consolidated into a compact 152 × 42 px instrument
plate at the 1920 × 1080 reference resolution. This is deliberately smaller
than the approved concept so it does not claim unnecessary screen space.

- `6:00 AM` remains the primary value in warm ivory.
- `DAY 1` becomes a small blue-gray secondary value inside the same plate.
- A 22 px clock pictogram is supplied by the existing code-rendered
  `BunkerSymbolTexture` system.
- A thin worn-brass divider separates icon and data.
- The charcoal plate uses the approved worn-brass border and grounded shadow.
- A restrained blue top notch ties the clock to the wider bunker UI language.

There is no continuous animation. The blue notch receives one short brightness
settle only when the displayed day changes.

## Cash

The top-right cash display is a 154 × 40 px bordered balance plate.

- It contains only the formatted cash value.
- There is no currency icon.
- There is no `AVAILABLE FUNDS` label.
- There is no blue accent notch.
- The warm brass-ivory value is right-aligned inside the shared charcoal and
  worn-brass frame.

The existing `set_cash`, thousands-separator formatting, world-space purchase
labels, and green/red cash delta behavior remain unchanged. The corner delta is
simply aligned to the right edge of the newly bounded cash plate.

## Preserved contracts

- `HUD.set_clock(display)` still accepts the final display string.
- `HUD.set_day(day)` still accepts an integer day.
- `HUD.set_cash(amount)` still accepts an integer and formats `$` plus commas.
- Save/load and `MainWorld` call sites require no changes.
- The counters remain mouse-pass-through HUD elements.

## Verification

```text
godot --headless --path . --script res://tools/tests/hud_time_cash_smoke.gd
```
