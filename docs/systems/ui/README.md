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
| `inventory/` | `InventoryHUD.gd` (~444 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `ShelfUI.gd` (~475), `BasketUI.gd` (~470) | Slot HUD, inventory state, shelf storage panel, basket contents panel |
| `hud/` | `HUD.gd` (~290), `NeedsGauge.gd` (~130 — 3-ring concentric stat gauge, replaces old `StatusBars.gd`/`CircleFill.gd`), `StatusEffectIcon.gd` (~70), `StatusEffectsContainer.gd` (~85), `InteractPrompt.gd` (~107 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text) | Always-on needs gauge (health/stamina/food/water/sleep), status-effect badge skeleton, interact prompt |
| `menus/` | `PauseMenuUI.gd` (~340), `GraphicsSettingsPanel.gd` (~575), `SleepOverlay.gd` (~145), `AdminMenu.gd` (~400) | ESC pause menu, graphics settings, sleep fade, admin cheats |
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
- `BasketUI`: `open(basket: Node3D)`, `close()`, `is_open() -> bool`.
- `HUD`: `set_health/stamina/food/water/sleep(value)`, `set_cash(amount)`,
  `set_clock(display)`, `set_day(day)`, `set_build_mode(enabled)`,
  `spawn_float_label(...)`, `show_cash_delta(...)`, `show_soft_warning(text)`.
  Also exposes `needs_gauge: NeedsGauge` and `status_effects:
  StatusEffectsContainer` as public properties (same pattern as
  `inventory_hud`) — see "Needs Gauge Redesign (Jul 2026)" below.
- `NeedsGauge`: `set_health/stamina/food/water/sleep(frac)` — all take a
  0.0-1.0 fraction (HUD converts from the raw 0-100 values it receives).
- `StatusEffectsContainer`: `add_effect(id, icon, duration, ring_color)`,
  `remove_effect(id)`.
- `PauseMenuUI`: `toggle()`, `open()`, `close()`, `is_open()`.
- `GraphicsSettingsPanel`: `open()`, `close()`.
- `SleepOverlay`: `begin_sleep()`, `request_wake()`.
- `AdminMenu`: `toggle()`, `open()`, `close()`, `is_open()`.
- `BuildModeHUD`: `get_item_price(tile_id)`, `show_hud()`/`hide_hud()`,
  `set_active_tool(tool_id)`, `set_ghost_active(active)`,
  `open_construct_menu()`/`close_construct_menu()`,
  `open_dig_confirm()`/`close_dig_confirm()`.
- `UIFade` (static, `scripts/ui/common/UIFade.gd`): `UIFade.fade_in(target:
  CanvasItem, duration: float = 0.15)`.
- `UIKit` (static, `scripts/ui/common/UIKit.gd`): `font()`, `theme_for(domain)`,
  `draw_backdrop(canvas, vp_size, alpha)`, `draw_panel(canvas, rect, theme, border_width)`,
  `draw_close_button(canvas, panel_rect, theme)`, `draw_bar(canvas, rect, fill_pct, theme, ...)`,
  `draw_header(canvas, pos, text, theme, ...)`, `draw_shadowed_text(canvas, pos, text, size, color)`,
  `button_stylebox(theme, enabled, hover)`, `settings_controls_theme()`,
  `draw_rugged_arc(...)`, `draw_rugged_circle(...)`.

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
   `BatteryBank`, `ShelfUI`, `PauseMenuUI`,
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

**Jul 2026 — Graphics Settings Panel Rewrite:** `GraphicsSettingsPanel.gd` was
completely rewritten as part of the graphics overhaul (Phase 5). The new
implementation uses a sectioned layout with a `ScrollContainer` (max height
520px), section headers matching `PauseMenuUI` style, and a
`UIKit.settings_controls_theme()` for consistent CheckBox/OptionButton/HSlider
styling. Sections: Quality Preset, Display (Window Mode/Resolution/VSync/FPS
Cap), Rendering (AA combo, Anisotropic/Shadow Quality/Render Scale), Advanced
Quality (SDFGI/SSAO/SSIL/Volumetric Fog/Glow/DOF), Flashlight (Volumetrics/
Shadows), Camera (FOV). All controls use `GraphicsSettings.set_setting()`/
`set_setting_live()`/`save_now()` pattern. Hover-spin reverted to 2-pool
(construct vs shop) since procedural previews now share the construct pool.
`UIKit.settings_controls_theme()` provides shared CheckBox/OptionButton/HSlider
styling — apply once via `_panel.theme = UIKit.settings_controls_theme()` and
all child controls inherit automatically.

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
  `button_stylebox(theme, enabled, hover)`, `settings_controls_theme()`,
  `draw_rugged_arc(canvas, center, radius, start_angle, end_angle, color,
  width, seed_offset)`, `draw_rugged_circle(canvas, center, radius, color,
  width, seed_offset)` (Jul 2026 — hand-inked wobble border helper, see
  "Needs Gauge Redesign" below).
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
  `enum Severity { INFO, WARNING, CRITICAL }` — `domain` still tags the
  entry (used by `NotificationHistoryUI`'s row text/consumers, and future
  filtering) but as of the Jul 2026 toast-format rework it no longer tints
  the live toast itself. `severity` drives the toast's actual look via
  **fixed colors, the same across all domains** (Brannon's explicit call —
  a WARNING toast reads identically whether it's water or power):
  `SEVERITY_COLOR_INFO = #878787`, `SEVERITY_COLOR_WARNING = #8f940d`,
  `SEVERITY_COLOR_CRITICAL = #94302b`.
- Queue: newest toast appended at the bottom of the internal `_queue`
  array (oldest at top of the array), each toast fades independently over
  its own last 20% (`FADE_TAIL_RATIO`) of `duration`. `MAX_QUEUE_LEN = 20`
  defensive cap (drops oldest first) — this is this pass's own default,
  not yet explicitly confirmed by Brannon; revisit if it ever needs tuning.
- **Toast look/position (reworked Jul 2026 — Brannon's explicit call to go
  back to the old pre-`NotificationManager` look):** each toast is a
  rounded rectangle (`TOAST_CORNER_RADIUS = 8`, drawn via a `StyleBoxFlat`
  + `.draw()` rather than a plain `draw_rect()` so the corners actually
  round — flat `draw_rect()` has no corner-radius support) filled with its
  severity color at partial opacity (`TOAST_FILL_ALPHA = 0.62`), plus a
  dark semi-transparent border on every toast (`TOAST_BORDER_COLOR =
  rgba(0,0,0,0.55)`, `TOAST_BORDER_WIDTH = 2.0`) — no more domain-tinted
  `UIKit.draw_panel()` background or thin left accent bar; text is a
  fixed light color (`TOAST_TEXT_COLOR`) at the original 13px size via
  `UIKit.draw_shadowed_text()` (already renders with `UIKit.font()`, so
  toast text has always matched the shared UI font — no change needed
  there), and **centered horizontally within the toast** (Jul 2026 —
  measured via `UIKit.font().get_string_size()`; history rows stay
  left-aligned, this only affects the live floating toast). Size:
  `TOAST_WIDTH = 561` (510 × 1.1, itself 1.5× the original 340),
  `TOAST_HEIGHT = 24` (half the original 48) — Brannon's Jul 2026
  follow-up calls, a shorter/wider bar than the initial rework. This
  matches the shape/position of the old `HUD.show_soft_warning()`
  single-message toast (see below), just extended to a real stacked queue
  instead of one-at-a-time replace.
  - Spacing: `TOAST_GAP = 4.0` between stacked toasts (Jul 2026 — halved
    from the original 8.0).
  - Fadeout duration: per-severity now, not one shared default. INFO
    still uses `DEFAULT_DURATION = 4.0`; `WARNING_DURATION = 6.0` and
    `CRITICAL_DURATION = 8.0` (Jul 2026 — previously ALL severities used
    the same 4.0s `DEFAULT_DURATION`). `notify()`'s `duration` param
    defaults to `DURATION_SENTINEL = -1.0`, resolved to the right
    per-severity constant in `_default_duration_for_severity()` unless a
    caller passes an explicit duration.
  - Position: centered horizontally, stacked directly **above the
    inventory bar** (not the old top-right corner stack) — newest toast
    sits closest to the bar (`GAP_ABOVE_BAR = 12.0`), older toasts push
    upward above it as more queue up. `NotificationManager` finds the bar
    by looking up `get_first_node_in_group("hud")` (HUD.gd calls
    `add_to_group("hud")` in its own `_ready()` specifically so this
    global autoload — outside HUD's scene — can find it) and reading its
    public `inventory_hud` Control's `get_global_rect()`. Falls back to a
    fixed bottom-of-viewport margin (`FALLBACK_BOTTOM_MARGIN = 140.0`) if
    no HUD is present in the current scene (e.g. a menu/preview context).
  - Rendering: own `CanvasLayer` at `layer = 220` (above every other panel
    layer in the project — `PauseMenuUI`=200 and `GraphicsSettingsPanel`=210
    were previously the highest).
- **Power signal wiring (Jul 2026, done):**
  `NotificationManager.connect_power_signals()` is a thin adapter —
  `PowerManager` already does all detection, this just translates 10 of
  its signals into `notify()` calls: `grid_tripped`/`grid_offline`→CRITICAL,
  `overloaded_started`/`breaker_tripped`/`battery_drained`/
  `generator_stopped`→WARNING, `grid_restored`/`overloaded_ended`/
  `generator_started`/`breaker_reset`/`generator_fuel_low`/`battery_low`
  →INFO. Generator/battery/breaker toasts include the specific id in the
  text (e.g. `"Generator gen_2 fuel low (18%)"`). Since `PowerManager` is a
  per-scene instance (group `"power_manager"`), not an autoload, this can't
  be connected from `NotificationManager._ready()` — `MainWorld` calls
  `connect_power_signals()` once, deferred, right after it creates
  `PowerManager` for that scene (`_setup_power_manager()` →
  `_connect_power_notification_signals()`), mirroring the pre-existing
  `_connect_power_hud_signals()` pattern. Guarded with `is_connected()`
  checks, safe to call more than once.
- **Notification history panel (Jul 2026, done):** in addition to the
  fading live toast stack (`_queue`), `NotificationManager` now keeps a
  second, independent `_history: Array[Dictionary]` capped at
  `MAX_HISTORY_LEN = 20` (own eviction, never touched by `_queue`'s
  fade/expire logic). Every `notify()` call appends `{domain, severity,
  text, fired_at_msec}` (via `Time.get_ticks_msec()`) and emits
  `history_changed`. `get_history() -> Array[Dictionary]` returns the
  history **newest-first** (reversed from internal append order) for
  direct UI consumption.
  - New panel: `scripts/ui/notifications/NotificationHistoryUI.gd`
    (extends `Control`, real `ScrollContainer` + `VBoxContainer` of rows —
    not hand-drawn immediate-mode, per this project's standing convention).
    Each row is a `PanelContainer` styled to **match the live toast look**
    (Jul 2026 rework) instead of the old thin accent bar: solid severity
    fill at the same `NotificationManager.TOAST_FILL_ALPHA`, same dark
    `TOAST_BORDER_COLOR`/`TOAST_BORDER_WIDTH` border, same
    `TOAST_CORNER_RADIUS` rounded corners, fixed light `TOAST_TEXT_COLOR`
    text, and the shared `UIKit.font()` on both the message and timestamp
    Labels (all four constants/helper reused directly from
    `NotificationManager`/`UIKit`, not redefined) — plus a single-line
    message and
    a right-aligned "Xs ago"/"Xm ago"/"Xh ago" timestamp refreshed every
    frame while the panel is `visible` (its own lightweight `_process()` —
    safe because the pause menu does NOT set `SceneTree.paused`).
  - Visible ONLY inside the pause menu: instantiated as a direct child of
    `PauseMenuUI` (a `CanvasLayer`, `layer = 200`) — a **sibling** of
    `_panel`/`_blur_rect`, not nested inside either — so it shows/hides for
    free with that `CanvasLayer`'s own `visible` toggle in `open()`/
    `close()`. Also gets `UIFade.fade_in()` in `open()`, matching the
    project's standing "every panel fades in" convention.
  - No header, no title, no close button by design — it's a passive
    sub-panel that lives and dies with the pause menu, not its own modal.
  - Position: anchored so its top-left sits at roughly
    (0.75 × viewport width, 0.25 × viewport height) — "3/4 right, 3/4 up"
    (upper-right quadrant, inset from the corner) — clamped so the
    380×480px panel never overflows the viewport on any resolution;
    recalculated on `size_changed`.
  - Newest entry at the **TOP** of this list — the opposite convention
    from the live toast stack (which appends newest at the bottom) — per
    Brannon's explicit call for the history view.
  `grid_tripped`/`grid_restored`/`grid_offline` previously ALSO surfaced via
  `HUD.show_soft_warning()` from `MainWorld._on_grid_tripped/restored/
  offline()` — that duplicate ad-hoc text was removed from those three
  functions in this same pass (the camera-trauma shake on `grid_tripped`
  stays) so the toast is the one place these three events show a message,
  not two overlapping notifications for one event.
- **Still out of scope (paused, needs explicit go-ahead before starting):**
  new water-system alert signals (`WaterPurifier`/`WaterManager`/
  `WaterDispenser` currently expose none — see plan §2.3), and `PlayerStats`
  threshold watching (food/water/sleep/health crossing a threshold, needs a
  shared `ThresholdWatcher` helper per the plan, not yet built).

## Graphics Settings Panel Rewrite (Jul 2026)
`GraphicsSettingsPanel.gd` was completely rewritten as part of the graphics
overhaul (Phase 5). Key changes:
- **Sectioned layout**: Quality Preset, Display, Rendering, Advanced Quality,
  Flashlight, Camera — each with a header and separator.
- **Display section**: Window Mode (Windowed/Borderless/Exclusive), Resolution
  (windowed only), VSync checkbox, FPS Cap dropdown (Uncapped/30/60/90/120/144/240).
- **Rendering section**: Anti-Aliasing combo (6 options → 3 raw fields:
  Off/Fast/Balanced/Sharp/Smooth/Max), Anisotropic Filtering (Off/2x/4x/8x/16x),
  Shadow Quality (Low/Medium/High/Ultra), Render Scale slider (50%-100%).
- **Advanced Quality**: SDFGI, SSAO, SSIL, Volumetric Fog, Glow, DOF checkboxes.
- **Flashlight**: Beam Volumetrics, Shadow Casting checkboxes.
- **Camera**: FOV slider (60-100°).
- **ScrollContainer** with max height (520px), section headers matching
  `PauseMenuUI`, `ScrollContainer` with max height so it never runs off-screen.
- **UIKit.settings_controls_theme()**: applied to root panel so all
  CheckBox/OptionButton/HSlider controls inherit dark-panel styling
  automatically — no per-control styling needed.
- **Hover-spin**: reverted to 2-pool (construct vs shop) since procedural
  previews now live in the same `_sub_` arrays as MeshLibrary items.
- **Duplicate declaration fix**: removed duplicate `interaction_system` var
  declaration and fixed `nil` → `null` typos.

The panel uses `UIKit.settings_controls_theme()` for consistent CheckBox,
OptionButton, and HSlider styling across all controls — no per-control
styling code needed.

## Needs Gauge Redesign (Jul 2026)
Replaces the old rectangular health/stamina bars (`StatusBars.gd`, deleted)
and the 3 separate food/water/sleep icon circles (`CircleFill.gd`, deleted)
with one composite radial gauge, styled after a Medieval-Dynasty-style
concentric ring reference, plus a status-effect badge skeleton. Three files
now live in `scripts/ui/hud/`:

- **`NeedsGauge.gd`** — 3 concentric rings, center-out:
  - Ring 1 (innermost): Health (left, red) / Food (right, orange)
  - Ring 2 (middle): Stamina (left, green) / Water (right, blue)
  - Ring 3 (outermost): Sleep — **right half only** (Jul 2026 follow-up call;
    originally mirrored both sides, trimmed after Brannon's review)
  - Blank dark center circle, no icons anywhere on this gauge (explicit
    design call — icons may return in a future pass).
  - Each half-arc has a **V-shaped gap** at top and bottom (doesn't reach
    true 12/6 o'clock) and is **bottom-anchored**: the tip nearest the
    bottom gap is always fully drawn above 0%, and the arc grows UPWARD
    toward the top gap as the stat fills toward 100% — the opposite of a
    typical bottom-up fill bar. See the file's own header comment for the
    exact angle math (`GAP_ANGLE_DEG`, `_draw_left_half`/`_draw_right_half`).
  - `HUD.gd`'s public API (`set_health/stamina/food/water/sleep(value)`) is
    unchanged — it now forwards to `needs_gauge.set_*(value / 100.0)`
    instead of the old `bars`/`food_circle`/etc. child nodes. `MainWorld.gd`
    required zero changes.
  - Fill colors (Jul 2026, darkened 5% from initial pass) — `COLOR_HEALTH`
    `(0.81,0.17,0.17)`, `COLOR_FOOD` `(0.90,0.52,0.14)`, `COLOR_STAMINA`
    `(0.29,0.81,0.24)`, `COLOR_WATER` `(0.24,0.52,0.90)`, `COLOR_SLEEP`
    `(0.57,0.33,0.81)`.

- **`StatusEffectIcon.gd`** — single reusable badge: an icon (or a plain
  grey placeholder circle if `icon` is `null` — no real icon art exists
  yet) centered inside a ring that depletes clockwise as `_remaining`
  ticks down via its own `_process()`. Emits `expired(effect_id)` when it
  hits 0; the container is responsible for freeing it. **Skeleton only** —
  nothing in gameplay calls `setup()` yet except the F7 admin test button
  (below).

- **`StatusEffectsContainer.gd`** — holds active badges in a **fixed,
  hand-placed 3-slot stagger** (`SLOT_OFFSETS`, a `Control`, not an
  auto-laying `VBoxContainer`) matching the reference image: top and bottom
  slots share the same X (a straight column), middle slot sits 12.5px left
  of that column (Jul 2026 fix — originally all 3 slots' X values didn't
  line up correctly, corrected after pixel-measuring a screenshot). Oldest
  effect always occupies slot 0 (top); `_reflow()` re-assigns every active
  badge to its slot by current order-index after every add/remove, so
  remaining badges slide up when one expires or is removed early. **No
  cap** on simultaneous effects (explicit call — behavior past 3 is
  untested/deferred) and **no placeholder for empty slots** (nothing drawn
  until a badge actually occupies that position). Public API:
  `add_effect(id, icon, duration, ring_color)` (re-calling with an existing
  id restarts that badge in place rather than duplicating it),
  `remove_effect(id)`.

- **F7 Admin Menu test button (`AdminMenu.gd`):** a "STATUS" section with
  an "Add Test Status Effect (10s)" row. Each press calls
  `status_effects.add_effect()` with a unique incrementing id
  (`test_effect_N`), `icon = null` (grey placeholder), a fixed 10-second
  duration (`TEST_EFFECT_DURATION`), and the shared default ring color
  (`TEST_EFFECT_COLOR`, darkened 5% to match the rest of the gauge). Looks
  up the HUD via `get_tree().get_first_node_in_group("hud")` then its
  public `status_effects` property, same pattern `NotificationManager`
  already uses to find `inventory_hud`.

- **ECONOMY section:** "+ $100,000 Cash" row calls `MainWorld.add_cash()`
  via injected `world_node` — updates HUD immediately.

- **WATER section:** "Hookup Output x2 (Tier +1)" row increments
  `WaterHookup.tier` (doubling output via existing tier system:
  3000→6000→12000→24000 mL/day). Clamped at max tier with warning.

- **FARMING section:** "Spawn Potato", "Spawn Blueberry", "Spawn Tomato"
  rows use `FarmProduceItem.spawn_at()` — same pop-in tween, jitter,
  and charges as harvested produce. No cash cost (cheat menu).

- **NPC section:** "Spawn NPC" row calls `NPC.tscn` instantiation 2m in
  front of player via injected `world_node` — same pattern as other
  admin spawns.

- **Worn/rugged visual pass:** no grunge/scratch texture asset exists
  anywhere in the project — this is entirely procedural, two shared
  pieces:
  1. `UIKit.draw_rugged_arc(canvas, center, radius, start_angle, end_angle,
     color, width, seed_offset)` / `UIKit.draw_rugged_circle(...)` — draws
     a hand-inked, slightly wobbly stroke instead of a perfectly smooth
     `draw_arc`/`draw_circle` line. The wobble is a **fixed hash of each
     point's angle** (not per-frame randomness) so it's identical every
     redraw — no flicker, just reads as rough/hand-drawn. Applied to every
     ring edge + the center circle in `NeedsGauge`, and both ring edges in
     `StatusEffectIcon`.
  2. `assets/shaders/grunge_overlay.gdshader` — a small `CanvasItem`
     shader (`grit_strength`/`grit_scale` uniforms, defaults `0.14`/`26.0`)
     that darkens random blotches across whatever the node draws (works on
     `draw_arc`/`draw_circle`/`draw_texture_rect` alike, since it operates
     on `COLOR` per-fragment, not on a sampled texture). Applied as a
     `ShaderMaterial` on both `NeedsGauge` and `StatusEffectIcon` in their
     `_ready()`. Deliberately kept subtle per Brannon's explicit call —
     "worn metal," not visible static.

- **Deleted:** `scripts/ui/hud/StatusBars.gd`, `StatusBars.gd.uid`,
  `scripts/ui/hud/CircleFill.gd`, `CircleFill.gd.uid`. The 3 icon assets
  they referenced (`steak.svg`, `water-drop.svg`, `night-sleep.svg`) were
  deliberately NOT deleted — no longer referenced anywhere, kept on disk
  for a possible future icon pass.

- **Known past bug (fixed):** an early implementation pass duplicated the
  `_get_status_effects()`/`_on_add_status_effect_pressed()` functions in
  `AdminMenu.gd` (same block inserted twice, causing a "Function has the
  same name as a previously declared function" parser error). Fixed by
  removing the second copy — if you ever see this exact error again on a
  future AdminMenu edit, check for a duplicated block first.

## BasketUI Panel (Jul 2026)
`scripts/ui/inventory/BasketUI.gd` — 12-slot container contents panel opened via
G-key while holding a Basket. Features:
- 3×4 grid of 3D preview viewports (SubViewport, orthographic camera, 45° angle)
- Per-slot Drop (↓) and Add-to-inventory (⊕) buttons — inventory button only
  shows for pocket-sized items (`inventory_item` group: Water Bottle, Food Can)
- Empty slots show `—` placeholder; occupied slots show 3D mesh preview
- Backdrop click-to-close, ESC/G/Interact to close
- Reuses `UIFade.fade_in()` convention; blocks game input while open
- `_refresh_slot()` reads basket slots directly (single items, not arrays like
  Shelving) — fixed type error where slot value was assigned to `Array` var

## BuildModeHUD Preview Fixes (Jul 2026)
- **Preview Scale Normalization**: `PREVIEW_TARGET_SIZE = 0.5667` (1.5× zoom out
  from 0.85) + `_preview_normalize_scale(aabb)` helper applied to all 3 preview
  pools (MeshLibrary, procedural, shop) — seed packets and Generator L now
  render at identical on-screen size.
- **Combined-AABB Calculation Fix**: Added static helper
  `_combined_local_aabb(root: Node3D)` that correctly transforms each
  MeshInstance3D's AABB into root's local coordinate space using global
  transforms (`root_inverse * mi.global_transform`). Replaced duplicated buggy
  logic in both construct-tab procedural preview (`_refresh_submenu_previews`)
  and shop-tab imported model preview (`_refresh_shop_previews`). Fixes
  "orbits around feet instead of spinning in place" rotation bug caused by
  merging raw local-space AABBs ignoring each mesh's offset from root
  (most procedural devices position body mesh above root so root = floor contact).
- MeshLibrary-mesh branch untouched (single mesh, no parent-imposed offset).

## Extension points
- Any new shared cross-panel utility (like `UIFade`, `UIKit`) belongs in
  `scripts/ui/common/`, written as a small static-function `RefCounted`
  utility — not duplicated inline per-panel.
