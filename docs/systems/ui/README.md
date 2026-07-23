# UI System

**Read this before opening any `scripts/ui/*` file.** Covers every UI
subfolder — power panels, inventory, HUD, menus, build-mode HUD, debug
overlay, and the shared `common/` helpers. Only open the actual source for
the one panel you're changing.

## Purpose
All player-facing UI: the always-on HUD (stats/cash/clock), every
interaction-triggered panel (power devices, shelves, pause/settings, admin
spawn menu), the build-mode HUD, and the debug overlay.

## Responsibilities
- Render and handle input for every panel/HUD element.
- React to game-state signals (power grid, stats, inventory) and re-draw.
- Call back into the owning system's public API on player input (e.g.
  `PowerPriorityUI` calls `PowerManager.set_consumer_priority(...)`).
- Own the shared `UIFade` fade-in convention (see below) and any other
  small cross-panel UI utilities added to `scripts/ui/common/`.

## Non-responsibilities
- **No panel computes game logic itself** — every panel is a thin
  view+input layer over whatever system it's attached to (`PowerManager`,
  `InventoryManager`, `PlayerStats`, `SaveManager`, etc.). If you find game
  logic creeping into a `_draw()`/`_process()` in a UI file, that's a bug —
  move it to the owning system.
- **`InventoryManager.gd`** (despite living in `scripts/ui/inventory/` for
  historical/folder reasons) is closer to a player-system data manager than
  a view — it holds the actual 4-slot inventory state (`activate_item`/
  `deactivate_item`/`add_item`/`remove_item`), not just drawing. Treat it as
  player-system state that happens to sit in this folder, not a "pure UI"
  file — don't assume it's safe to move/rename lightly, check external
  callers first (mainly `InteractionSystem.gd`).

## Files by subfolder
| Subfolder | Files | Role |
|---|---|---|
| `power/` | `PowerTerminalUI.gd` (~1010), `PowerPriorityUI.gd` (~495), `GeneratorInspectUI.gd` (~434) | Power device panels — see `docs/systems/power/README.md` for what they read/write |
| `inventory/` | `InventoryHUD.gd` (~444 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `ShelfUI.gd` (~475) | Slot HUD, inventory state, shelf storage panel |
| `hud/` | `HUD.gd` (~280), `StatusBars.gd` (~50), `InteractPrompt.gd` (~107 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text), `CircleFill.gd` (~80) | Always-on stat bars, interact prompt, radial fill widget |
| `menus/` | `PauseMenuUI.gd` (~340), `GraphicsSettingsPanel.gd` (~180), `AdminSpawnMenu.gd` (~215), `SleepOverlay.gd` (~145) | ESC pause menu, graphics settings, dev spawn menu, sleep fade |
| `build/` | `BuildModeHUD.gd` (~1010) | Build-mode toolbar/construct menu/undo/dig-confirm UI |
| `debug/` | `DebugOverlay.gd` (~305) | F-key debug readouts |
| `common/` | `UIFade.gd` (~30), `UIKit.gd` (~200) | Shared fade-in helper + shared theme/drawing kit (see "UIKit shared kit" below) — put any future cross-panel UI utility here |
| `notifications/` | `NotificationManager.gd` (~175) | Central toast/notification system (see "NotificationManager" below) |

## Public API (representative — not exhaustive, see each panel's own header)
Every interaction panel follows the same shape: `open(...)` / `close()` /
sometimes `toggle()` / `is_open() -> bool`, plus panel-specific setters
(`refresh(...)`, `set_selected(slot)`, etc.). Notable ones:
- `PowerTerminalUI`: `open()`, `close()`.
- `PowerPriorityUI`: `open(device_id, display_name, ...)`, `close()`, `is_open()`.
- `GeneratorInspectUI`: `open(display_name, watts, fuel, ...)`, `refresh(fuel,
  health, is_backup, is_running, ...)`, `close()`.
- `InventoryManager`: `is_full()`, `has_item(item)`, `first_empty_slot()`,
  `slot_of(item)`, `add_item(item)`, `add_item_to_slot(item, slot)`,
  `activate_item(slot)`, `deactivate_item(slot)`, `retrieve_item(slot)`,
  `remove_item(slot, drop_position)`.
- `InventoryHUD`: `show_error_message(text)`, `set_selected(slot)`,
  `refresh_previews()`.
- `ShelfUI`: `open(shelf: Node3D)`, `close()`.
- `HUD`: `set_health/stamina/food/water/sleep(value)`, `set_cash(amount)`,
  `set_clock(display)`, `set_day(day)`, `set_build_mode(enabled)`,
  `spawn_float_label(...)`, `show_cash_delta(...)`, `show_soft_warning(text)`.
- `PauseMenuUI`: `toggle()`, `open()`, `close()`, `is_open()`.
- `GraphicsSettingsPanel`: `open()`, `close()`.
- `AdminSpawnMenu`: `toggle()`.
- `SleepOverlay`: `begin_sleep()`, `request_wake()`.
- `BuildModeHUD`: `get_item_price(tile_id)`, `show_hud()`/`hide_hud()`,
  `set_active_tool(tool_id)`, `set_ghost_active(active)`,
  `open_construct_menu()`/`close_construct_menu()`,
  `open_dig_confirm()`/`close_dig_confirm()`.
- `UIFade` (static, `scripts/ui/common/UIFade.gd`): `UIFade.fade_in(target:
  CanvasItem, duration: float = 0.15)`.

## Signals produced
| File | Signal | Params |
|---|---|---|
| `GeneratorInspectUI` | `closed`, `backup_toggled(enabled)`, `power_toggled(running)` |
| `PowerPriorityUI` | `closed`, `priority_changed(id, value)`, `load_toggled(id, on)` |
| `PowerTerminalUI` | `closed` |
| `InventoryManager` | `inventory_changed()` |
| `SleepOverlay` | `sleep_started()`, `sleep_ended()` |
| `BuildModeHUD` | `tool_selected(tool_id)`, `construct_item_chosen(tile_id)`, `cancel_requested()`, `undo_requested()`, `dig_confirmed()`, `dig_cancelled()` |

## Signals/events consumed
Each power panel connects to the relevant `PowerManager` signals for live
updates while open (e.g. `draw_changed`, `grid_state_changed`,
`consumer_priority_changed`) — see `docs/systems/power/README.md` for the
full signal list. `HUD` listens to `PlayerStats`/`Player` signals
(`stamina_changed`, etc.) and `PowerManager.grid_tripped/restored/offline`
(forwarded via `MainWorld`, not directly).

## Ownership
Panels are lazy-instantiated by whichever system/device opens them (e.g.
`MainWorld` lazy-instantiates `PauseMenuUI` the same way it later
lazy-instantiates `GraphicsSettingsPanel`; each power device instantiates its
own panel on first interact). None of these are autoloads.

## UI conventions (standing rules — apply to every new panel)
1. **Fade-in on open (July 2026 standing convention):** every panel that
   opens via player interaction calls `UIFade.fade_in(target)` right after
   `visible = true` in its `open()`/`toggle()`. Applied to ALL current
   interaction panels (`PowerTerminalUI`, `PowerPriorityUI`,
   `GeneratorInspectUI`, `BreakerBox`/`UpgradedBreakerBox` via inheritance,
   `BatteryBank`, `ShelfUI`, `AdminSpawnMenu`, `PauseMenuUI`,
   `GraphicsSettingsPanel`, `BuildModeHUD`). **Every new panel must call
   this too.** Deliberately NOT applied to `HUD.gd` (already has its own
   fade-in system — don't add a second one) or `SleepOverlay.gd` (own
   custom zzz-fade, not an interaction-opened panel). `target` must be a
   `CanvasItem` (a `Control`/`Panel`), never the `CanvasLayer` itself (no
   `modulate` property there).
2. **New panels should use real `Control`/`Container` node trees + a theme
   resource**, not hand-rolled immediate-mode `_draw()`. Most existing
   panels (`PowerTerminalUI`, `BuildModeHUD`, `PowerPriorityUI`,
   `GeneratorInspectUI`) ARE hand-drawn immediate-mode — a deliberate past
   style choice, not a pattern to keep repeating. `GraphicsSettingsPanel` is
   the first panel built with real `Control` nodes — follow its lead for
   anything new, don't retrofit the older ones.

## Common edits
- **New interaction panel:** put it in the matching subfolder from the table
  above (extend the map with a new subfolder if nothing fits), build it with
  real `Control` nodes, call `UIFade.fade_in()` on open, connect to its
  owning system's signals for live updates rather than polling in
  `_process()`.
- **New HUD stat/indicator:** add a setter to `HUD.gd` following the
  `set_health/set_stamina/...` pattern; wire the owning system to call it
  once on a signal, not every frame.

## Forbidden edits
- **Don't add game logic to a UI file's `_draw()`/`_process()`.** Compute
  state in the owning system, pass already-computed values into the panel's
  `open()`/`refresh()` call.
- **Don't skip `UIFade.fade_in()`** on a new interaction panel — it's a
  standing convention, not optional polish.
- **Don't add a full-screen blur backdrop to small floating panels**
  (`PowerTerminalUI`/`PowerPriorityUI`/etc.) — those stay mouse-pass-through
  over still-interactive gameplay by design, unlike `PauseMenuUI`'s
  full-screen takeover. Changing that is a design call, not a simple fix.

## Known tradeoffs / tech debt
- Most existing panels are hand-drawn immediate-mode (500–1000+ lines of
  manual layout bookkeeping each) — explicitly not being retrofitted, only
  new panels use real Control trees (see UI conventions #2).
- `BuildModeHUD.gd` (~1010 lines) is a possible future god-object cleanup
  candidate, not currently scheduled.

## UIKit shared kit (Jul 2026)
`scripts/ui/common/UIKit.gd` — `class_name UIKit`, pure static-function
`RefCounted` helper (no instance state, no autoload), same convention as
`WaterQualityColor.gd`. Introduced to stop the hand-drawn immediate-mode
panels (`WaterDispenserUI`, `PowerTerminalUI`, etc.) from each hand-rolling
their own palette consts + `_draw_str()`/backdrop/panel/bar boilerplate.
- **`enum Domain { WATER, POWER, NEUTRAL }`** — picks a color scheme.
  `WATER`/`POWER` theme colors are copied **verbatim** from
  `WaterDispenserUI.gd`'s/`PowerTerminalUI.gd`'s pre-existing consts (this
  was a refactor, not a redesign — no visual drift). `NEUTRAL` (steel-gray)
  has no prior precedent — introduced for `NotificationManager`'s
  non-water/power toasts. All three domains reuse the same ok/warn/crit
  status hues; only bg/border/header/text/dim vary by domain.
- **`class UITheme`** — plain data holder (`bg`, `border`, `header`, `text`,
  `dim`, `ok`, `warn`, `crit` — all `Color`). Named `UITheme`, not `Theme`,
  specifically to avoid colliding with Godot's built-in `Theme` (Control
  theme resource) class — using bare `Theme` caused a
  `"argument should be Theme but is Theme"` parse error when referenced
  from a different script as `UIKit.Theme`. **Never rename this back to
  `Theme`.**
- **Static API:** `font()`, `theme_for(domain)`, `draw_backdrop(canvas,
  vp_size, alpha)`, `draw_panel(canvas, rect, theme, border_width)`,
  `draw_close_button(canvas, panel_rect, theme)`, `draw_bar(canvas, rect,
  fill_pct, theme, ...)`, `draw_header(canvas, pos, text, theme, ...)`,
  `draw_shadowed_text(canvas, pos, text, size, color)`,
  `button_stylebox(theme, enabled, hover)`.
- `draw_backdrop()`'s alpha is a caller-supplied param, deliberately NOT
  unified across callers (`WaterDispenserUI` used 0.60, `PowerTerminalUI`
  uses 0.65) — unifying it would be an unrequested visual change.
- **Migration status:** `WaterDispenserUI.gd` fully migrated (reference
  migration — visually identical, only internals changed:
  `var _theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.WATER)` replaces
  the old local const palette; `QUALITY_GOOD_COLOR`, `OFF_COLOR`,
  `ACCENT_TOGGLE`, `PRIO_COLORS` intentionally stayed as local file consts —
  domain-specific, not structural, not part of the shared kit).
  `PowerTerminalUI.gd`/other hand-drawn panels are NOT yet migrated — do it
  the same mechanical way (replace local palette consts with
  `UIKit.theme_for(UIKit.Domain.POWER)`, swap `_draw()` calls for the
  matching `UIKit` primitive) when next touching one of those files, don't
  do it as a drive-by unless asked.
- Still applies convention #2 above: this is for the *existing*
  hand-drawn-immediate-mode panels, not an invitation to start new panels
  in immediate-mode — new panels still use real `Control` nodes.

## NotificationManager (Jul 2026)
`scripts/ui/notifications/NotificationManager.gd` — real project-level
**autoload** (`project.godot` `[autoload]`, registered after
`GraphicsSettings`), NOT the group-lookup pattern `WaterManager`/
`PowerManager`/`PlayerStats` use — a toast has no save-specific world state,
it's a global "show this text for a while" service reachable from any scene.
- **No `class_name`** on this script — a `class_name` matching the autoload's
  own name causes a `"hides an autoload singleton"` parse error. Every other
  autoload in this project (`SaveManager`, `GraphicsSettings`, etc.) follows
  the same no-`class_name` pattern; keep doing that for any future autoload.
- Call `NotificationManager.notify(domain: UIKit.Domain, severity:
  Severity, text: String, duration: float = 4.0)` from anywhere.
  `enum Severity { INFO, WARNING, CRITICAL }` — `domain` picks WHERE it's
  from (water/power/neutral color scheme via `UIKit`), `severity` picks HOW
  urgent within that scheme (tints text + left accent bar: INFO→`theme.text`,
  WARNING→`theme.warn`, CRITICAL→`theme.crit`).
- Queue: newest toast appended at the bottom of the on-screen stack (oldest
  at top), each toast fades independently over its own last 20%
  (`FADE_TAIL_RATIO`) of `duration`. `MAX_QUEUE_LEN = 20` defensive cap
  (drops oldest first) — this is this pass's own default, not yet
  explicitly confirmed by Brannon; revisit if it ever needs tuning.
- Rendering: own `CanvasLayer` at `layer = 220` (above every other panel
  layer in the project — `PauseMenuUI`=200 and `GraphicsSettingsPanel`=210
  were previously the highest), top-right stack, drawn via
  `UIKit.draw_panel()`/`theme_for(entry.domain)` same as any other panel.
- **Out of scope so far (paused, needs explicit go-ahead before starting):**
  wiring real alert sources — `PowerManager`'s `grid_tripped`/
  `grid_restored`/etc. signals, new water-system signals, `PlayerStats`
  threshold watching. This pass is the skeleton + manual `notify()` call
  only; nothing in the game calls it automatically yet.

## Extension points
- Any new shared cross-panel utility (like `UIFade`, `UIKit`) belongs in
  `scripts/ui/common/`, written as a small static-function `RefCounted`
  utility — not duplicated inline per-panel.
