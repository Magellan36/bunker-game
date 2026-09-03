# UI System

**Read this before opening any `scripts/ui/*` file.** Covers every UI
subfolder — power panels, inventory, HUD, menus, build-mode HUD, debug
overlay, and the shared `common/` helpers. Only open the actual source for
the one panel you're changing.

## Purpose
All player-facing UI: the always-on HUD (stats/cash/clock), every
interaction-triggered panel (power devices, shelves, pause/settings, admin
spawn menu), the build-mode HUD, and the debug overlay.

**September 2026 — opt-in redesign first pass:** character creation now uses
`assets/ui/themes/BunkerRedesignTheme.tres` and native containers/buttons.
Read `docs/systems/character-creation/README.md` and
`plans/ui-redesign-first-pass.md` for approved values and scope. Existing UIKit
consumers and `BunkerTheme.tres` are unchanged. All new icon artwork is explicitly
temporary; the final game must not ship AI-authored artwork.

**September 2026 — generator inspector pass:** `GeneratorInspectUI.gd` now
instantiates the native `scenes/ui/power/GeneratorInspectPanel.tscn`, using that
same opt-in theme plus additive inspector-specific type variations. Its existing
CanvasLayer, open/refresh arguments and action signals are preserved.
`scripts/ui/common/BunkerInspectorLayout.gd` owns only local sizing.
Read `plans/ui-redesign-generator-pass.md` before extending it. This is an
explicitly approved migration of the generator inspector; other legacy panels
remain unchanged. Initial character-creation focus no longer scrolls its heading
out of view.

## Redesign rule: in-world inspectors are not full-screen menus

The September 2026 generator review established a standing user preference for
future device panels (including water and farm trays): retain the approved
warm-charcoal/ivory/worn-brass/project-blue identity, but use compact PC-game
density, not character-creation or mobile/tablet proportions.

- At a 1920×1080 UI viewport, the generator is **500×740 px**, vertically
  centered and **24 px from the right edge**. Similar device inspectors should
  start from this slender, right-docked pattern, adapting height to content.
- **No screen-wide dimming, blur or opaque backdrop** for ordinary device
  inspection. Keep the bunker and HUD visible. The panel consumes mouse input
  within its bounds; its full-viewport root ignores it. This does not change
  the owning game's existing movement/pause/input policy.
- Base type: 24 px device title, 16–18 px status/body/action text, 14 px help,
  13 px eyebrow/navigation. Actions remain robust at 44–48 px high, not 80 px.
- At smaller desktop resolutions, reduce available details height and scroll
  rather than shrinking this text baseline. Keep actions and focus visible.
  Above 1080p, local growth is capped at 1.25×; ultrawide must not widen the panel.
- Character creation is deliberately a full-screen workflow: **leave its
  approved proportions intact**. A category/cart shop is also a distinct
  workflow, not something to force into a 500 px inspector.

The current compact revision changes only the generator presentation and tests.
Do not silently migrate unrelated screens. See
`plans/ui-redesign-generator-pass.md` for implementation and behavior contracts.

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
| `power/` | `PowerTerminalUI.gd` (~1180), `PowerPriorityUI.gd` (~500), `GeneratorInspectUI.gd` (~440), `ZoneCustomizeUI.gd` (~225) | Power device panels — see `docs/systems/power/README.md` for what they read/write |
| `water/` | `WaterDispenserUI.gd` (~520), `WaterInfoUI.gd` (~625) | Water device panels — see `docs/systems/water/README.md` for what they read/write. Both fully on the shared `UIKit` palette as of the Jul 2026 "Power + Water UI Unification" pass — see that section below |
| `farming/` | `FarmingTrayUI.gd` (~440 — handles both the 1x1 and 2x1 tray sizes; panel height grows/shrinks with 0/1/2 plant slots), `PlantInfoUI.gd` | Farming tray panel (Jul 2026 "Rounded Corners" pass joined it onto `UIKit.Domain.FARMING`, green stripe) |
| `inventory/` | `InventoryHUD.gd` (~400 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback; 3D preview building/populating delegated to `ItemPreviewKit.gd` as of Aug 2026), `InventoryManager.gd` (~155, see Non-responsibilities), `StorageUI.gd` (~360 — Aug 2026, generic shared storage overlay, replaces the former `ShelfUI.gd`/`BasketUI.gd`, see "Storage UI Unification" below; icon-texture buttons + preview delegated to `ItemPreviewKit.gd`, row labels removed, see "Shared Item Preview Kit" and "Storage UI Icon + Row Label Redesign" below) | Slot HUD, inventory state, shared storage-container panel |
| `hud/` | `HUD.gd` (~290), `NeedsGauge.gd` (~130 — 3-ring concentric stat gauge, replaces old `StatusBars.gd`/`CircleFill.gd`), `StatusEffectIcon.gd` (~70), `StatusEffectsContainer.gd` (~85), `InteractPrompt.gd` (~170 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text; grew substantially Aug 2026 — real styling, an icon-preview row, and general pairwise overlap avoidance, see "Cooking Pot UI Fixes + Prompt Overlap Avoidance" below) | Always-on needs gauge (health/stamina/food/water/sleep), status-effect badge skeleton, interact prompt |
| `menus/` | `PauseMenuUI.gd` (~330 — rewritten onto `UIKit` menu builders, Jul 2026), `GraphicsSettingsPanel.gd` (~430 — same rewrite, also fixed a long-standing off-center bug, see below), `SleepOverlay.gd` (~145), `AdminMenu.gd` (~430 — rewritten with collapsible sections + a real `ScrollContainer`, Jul 2026, see below) | ESC pause menu, graphics settings, sleep fade, admin cheats |
| `build/` | `BuildModeHUD.gd` (~1010) | Build-mode toolbar/construct menu/undo/dig-confirm UI. Farming shop's `FARMING_SHOP_ITEMS["Seeds"]` had a duplicate-`tile_id` bug fixed Aug 2026 (see "Farming Shop Seed tile_id Bugfix" below) and a SEPARATE bug where `PREVIEW_SOURCES` never set `seed_type` per-id, so every seed preview looked identical — fixed Aug 2026, see "Cooking Pot UI Fixes + Prompt Overlap Avoidance" below |
| `debug/` | `DebugOverlay.gd` (~305) | F-key debug readouts |
| `common/` | `UIFade.gd` (~30), `UIKit.gd` (~530 — grew substantially across the Jul 2026 "UI Overhaul" arc: menu builders, rounded corners, domain stripes, the shared close-icon, a 4th `FARMING` domain), `ItemPreviewKit.gd` (~235 — Aug 2026, shared static 3D item-preview builder used by `InventoryHUD`/`StorageUI`, see "Shared Item Preview Kit" and "Preview Scale Normalization + Deep Mesh Walk" below), `TrashBagInfoPanel.gd` (~200 — Aug 2026, first AMBIENT hover panel — a NEW panel category, see "Ambient Hover Panels (Aug 2026)" below) | Shared fade-in helper + shared theme/drawing kit + shared 3D item-preview builder — put any future cross-panel UI utility here |
| `notifications/` | `NotificationManager.gd` (~175) | Central toast/notification system (see "NotificationManager" below) |
| `medical/` | `StatusScreenUI.gd` (Aug 2026 — see "Medical Status Screen" below) | Medical Layer-3 deep-dive status screen |
| `npc/` | `NPCTalkMenuUI.gd` | NPC E-panel (needs bars, status, skills, personality) — see `docs/systems/npc/README.md` for full detail; fixed per-stat bar colors as of Aug 2026, see "Cooking Pot UI Fixes..." below is unrelated — see the NPC doc directly for the color table |

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
- `StorageUI`: `open(target: Node3D)`, `close()`, `is_open: bool` — shared
  storage overlay (Aug 2026, replaces `ShelfUI`/`BasketUI`), see "Storage
  UI Unification" below.
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
- `ItemPreviewKit` (static, `scripts/ui/common/ItemPreviewKit.gd`, Aug
  2026): `build_viewport(parent, pixel_size) -> SubViewport`,
  `set_item(vp, item)`, `clear(vp)` — shared 3D item-preview builder used
  by `InventoryHUD` and `StorageUI`, see "Shared Item Preview Kit" below.
- `UIKit` (static, `scripts/ui/common/UIKit.gd`): `font()`, `theme_for(domain)`
  (domains: `WATER`, `POWER`, `NEUTRAL`, `FARMING` — `WATER`/`POWER`/`FARMING`
  share one identical bg/border/header/text/dim/ok/warn/crit palette as of
  the Jul 2026 unification pass, differing only in `theme.accent`, used
  solely for each panel's top stripe), `draw_backdrop(canvas, vp_size, alpha)`,
  `draw_panel(canvas, rect, theme, border_width)`,
  `draw_rounded_rect(canvas, rect, bg_color, border_color, border_width,
  corner_radius)` (the shared `StyleBoxFlat.draw()` primitive every rounded
  panel/button in the project now goes through — `CORNER_RADIUS` constant
  is `4.0`, the one shared radius everywhere), `draw_close_button(canvas,
  panel_rect, theme)`, `draw_close_icon(canvas, rect, modulate)` (the
  shared × icon, `assets/icons/close_x.png` — a white/alpha mask tinted via
  `modulate`), `draw_domain_stripe(canvas, panel_rect, accent, gap, height)`
  / `add_domain_stripe(panel_width, accent, gap, height)` (Control-node
  variant, used by `ZoneCustomizeUI`), `draw_bar(canvas, rect, fill_pct,
  theme, ...)`, `draw_header(canvas, pos, text, theme, ...)`,
  `draw_shadowed_text(canvas, pos, text, size, color)`,
  `button_stylebox(theme, enabled, hover)`, `settings_controls_theme()`,
  `draw_rugged_arc(...)`, `draw_rugged_circle(...)`, and the real
  Control-node menu builders added for `PauseMenuUI`/`GraphicsSettingsPanel`:
  `build_modal_backdrop(alpha)`, `build_centered_panel(width, height, theme)`
  (always correctly centered regardless of content — see "off-center bug"
  note below), `make_button(text, cb, min_height)`, `make_section_label(text,
  theme)`, `make_row_label(text, theme)`, plus the shared font-size scale
  `FONT_SIZE_TITLE`/`FONT_SIZE_SECTION`/`FONT_SIZE_BODY` and shared width
  `MENU_PANEL_W`.

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
   `BatteryBank`, `StorageUI` (former `ShelfUI`/`BasketUI`), `PauseMenuUI`,
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
  new panels use real Control trees (see UI conventions #2). Exception:
  the explicitly approved September 2026 generator redesign now uses native
  controls; do not restore its old hand-drawn implementation.
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

## Storage UI Unification (Aug 2026)
Replaces the former separate `ShelfUI.gd`/`BasketUI.gd` (476/470 lines, 17
of 18 functions duplicated between them) with one generic, config-driven
`StorageUI.gd`. Any storage object — `Shelving.gd`, `Basket.gd`, and any
future type — implements a 4-method contract. Current implementers:
`Shelving.gd`, `Basket.gd`, and the light-storage furniture base
`LightStorage.gd` (`EndTable.gd` / `Dresser.gd`, Aug 2026):

- `get_ui_config() -> Dictionary` — grid shape, slot count, row labels,
  stacking, primary-button icon/label/color, close-vs-refresh-on-action.
  Every key optional, `StorageUI.gd`'s `_DEFAULT_CONFIG` fills in the rest.
- `get_slot_display(slot_idx) -> Array` — `[item_or_null, count]`.
- `take_for_carry(slot_idx, isys) -> bool` — the primary button. Concrete
  meaning is type-specific: `Shelving` hands the item to the player's hold
  point ("Carry"), `Basket` drops it on the ground ("Drop") — the method
  name is historical, not literal; treat it as "this type's primary
  retrieval action."
- `take_for_inventory(slot_idx, inv) -> bool` — secondary "⊕" button,
  always means "into the player's inventory pocket," same for every type.

`StorageUI.gd` keeps ONE dynamic slot-visual pool that only grows (never
rebuilds) — opening a 12-slot basket after a 10-slot shelf grows the pool
to 12; reopening the shelf afterward just hides the extra 2, nothing gets
destroyed. This is what makes adding a future storage type (lockable
storage, freezers/fridges, lockers, larger shelving units, all mentioned
as planned) free on the UI side — no fixed slot count anywhere in the
file, no new UI code needed, just a world-object script implementing the
4-method contract above. `LightStorage.gd` is the proof: capacity-2
(End Table) and capacity-6 (Dresser) containers with zero UI code of
their own, only the four methods + a `get_ui_config()` built from its
`grid_cols`/`grid_rows`/`row_labels` exports. Because its stored items are
hidden children of the furniture node, its `take_for_carry`/
`take_for_inventory`/`eject_all_items()` must reparent them to the world
root and restore visibility before handing off — see
`docs/systems/furniture-items/README.md`.

`MainWorld.gd`'s former `_setup_shelf_ui()`/`_setup_basket_ui()` collapsed
into one `_setup_storage_ui()`, which points BOTH of
`InteractionSystem.gd`'s existing `shelf_ui`/`basket_ui` properties at the
same `StorageUI` instance — `InteractionSystem.gd` itself (Player-thread-
owned) needed zero changes, every existing call there
(`shelf_ui.is_open`, `basket_ui.open(...)`, etc.) keeps working since both
names now just reference the same object.

Visual style deliberately NOT changed in this pass — `StorageUI.gd` kept
the existing look (14px corner radius, its own dark palette) rather than
moving onto the `UIKit` domain-stripe system Power/Water/Farming/Pause
use. That's a separate, not-yet-requested decision.

**Follow-up (Aug 2026) — prompt exclusivity rule + Dresser/End Table
fix.** Two real bugs found and fixed after the initial unification:

1. `LightStorage.gd` (the shared base `Dresser.gd`/`EndTable.gd` extend)
   only joined the `"shelving"` group, never `"interactable"`. Shelving.gd
   joins both — `InteractionSystem.gd`'s empty-handed candidate-gathering
   requires `"interactable"` membership for one of its two passes and
   explicitly excludes `"shelving"` members from the other, so Shelving
   slipped through via the first pass while Dresser/End Table fell into
   the gap between both and never got a prompt at all. Fixed with one
   `add_to_group("interactable")` call.
2. `LightStorage.get_f_prompt()` returned `""` (nothing) when full,
   unlike `Shelving.gd`'s existing `"[F] Shelf full"` — now returns
   `"<name> Full"` to match.

**New standing rule**: while the player holds a storable item near any
`"shelving"`-group object (Shelf, Dresser, End Table, and any future
storage furniture), only ONE prompt line shows — `get_f_prompt()`'s text
if it has something to say (Store or Full), falling back to
`get_e_prompt()` only when it doesn't. Previously both always showed
together, which was actively misleading: while anything is held, `E` is
bound to the held item's own action, never to a nearby shelf's
`on_e_interact()`.

This rule needed to be applied in TWO places —
`InteractionSystem._update_prompt()` has entirely separate code paths for
"holding something" (CASE 1) vs "empty-handed" (CASE 2), each with its own
copy of the shelving-prompt logic. An earlier pass only fixed CASE 2, which
is why the bug persisted for held items. Both are now fixed, along with a
second, unrelated bug in CASE 2 specifically: it discovered `"shelving"`
objects via `Area3D` signal tracking, which never fires for a body that
spawns already inside the player's trigger volume (exactly what happens
placing furniture via Build Mode while standing next to it) — CASE 2 now
also does a direct per-frame group scan, matching the timing-safe approach
CASE 1's `_nearest_shelf()` already used. All of this lives in
`InteractionSystem.gd` (Player-thread-owned) — handed off as a standalone
plan rather than applied directly by the UI thread.

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

## Pause Menu + Graphics Settings Unification (Jul 2026)
Both panels rewritten onto the new `UIKit` menu-builder helpers (see Public
API above) instead of each hand-rolling their own backdrop/panel/button/
label construction. Found and fixed the actual root cause of
`GraphicsSettingsPanel`'s long-standing off-center bug in the process: it
called the bare `set_anchors_preset(PRESET_CENTER)` (no explicit offsets)
*before* its ~15 settings rows were added to its VBox, so Godot baked the
centering math from the panel's near-zero size at that moment instead of
its real final size. `UIKit.build_centered_panel()` fixes this structurally
for every panel that uses it — always sizes to a FIXED width/height up
front, never relies on Godot recomputing centering from current content.
Also fixed real corrupted bytes (a stray UTF-8 BOM + mangled comment
dividers) isolated to `PauseMenuUI.gd`, found while rewriting the file.
Both panels now share one width (`MENU_PANEL_W = 380`, up from 360/340)
and one font-size scale.

## Power + Water UI Unification (Jul 2026)
Collapsed `UIKit.Domain.WATER` and `Domain.POWER` onto one identical
bg/border/header/text/dim/ok/warn/crit palette (previously blue vs green
throughout, including status colors) — the two domains now differ only in
`theme.accent`, used exclusively for a new thin colored stripe across the
top of each panel (`UIKit.draw_domain_stripe()`). `PowerTerminalUI.gd` was
also brought in line with the other 3 power panels, which already matched
each other but not it (different green, different close-button size).
Also unified backdrop dim alpha (was 0.55-0.65 depending on file, now 0.60
everywhere) and close-button background color across all 6 files.

## Rounded Corners + Domain Stripe Recolor + Farming Domain + Top Padding (Jul 2026)
- **Rounded corners everywhere, one shared radius** (`UIKit.CORNER_RADIUS =
  4.0`) — added `UIKit.draw_rounded_rect()` (the `StyleBoxFlat.draw()`
  trick — Godot's `CanvasItem` has no native rounded-rect draw call) for
  the 4 hand-drawn power/water panels, which previously had square corners
  only; `PauseMenuUI`/`GraphicsSettingsPanel` already matched this radius
  from the pass above.
- **Power's stripe: green → yellow** (`Color(0.90, 0.80, 0.20, 1.0)`),
  freeing up the old green for a new **`UIKit.Domain.FARMING`**, which
  `FarmingTrayUI.gd` (already a full `UIKit` consumer) joined for nearly
  free — it just needed the new domain and one `draw_domain_stripe()` call.
- **+6px top padding, uniformly, on every panel** — pushes the title/name
  text, the corner × close button, and (`PowerTerminalUI` specifically)
  the "LOAD Xw/Yw" readout down slightly. Centralized in
  `UIKit.draw_close_button()` where possible; called out per-file
  everywhere else, including 3 files that each separately position an
  invisible real `Button` node exactly on top of the drawn × for click
  handling — both the drawn and the real one need the identical shift or
  they drift apart.

## F7 Admin Menu — Collapsible Sections + Scroll (Jul 2026)
`AdminMenu.gd` had grown to 24 rows across 7 sections (the NPC section
alone added 12 rows when the old F10 "Admin Spawn Menu" was deleted and
folded into F7) and was rendering at roughly 1,250px tall — its height was
computed from total row count. Rewritten so the panel is a FIXED height
again (`PANEL_H = 480`) with every section now a collapsible header (▶
collapsed / ▼ expanded, click to toggle, all start collapsed on open,
multiple can be open at once) inside a real `ScrollContainer` — mouse
wheel scroll and the right-side scrollbar are both native `ScrollContainer`
behavior, same pattern `GraphicsSettingsPanel.gd` already used for its own
overflow content. The row DATA (`_sections`, restructured from the old flat
array-with-`""`-continuation-markers format into explicit
`{name, rows}` dictionaries) and every `_on_*_pressed()` callback are
unchanged by this — only layout/show/hide logic changed.

## Shared Close-Button Icon (Jul 2026)
Replaced the hand-drawn 2-line × (used in two different forms across 7
files — some via the old `UIKit.draw_close_button()`, 5 others each
duplicating the same 4-line draw code locally) with one shared icon,
`assets/icons/close_x.png` (a white shape with alpha, tinted via
`modulate` to the same light red every panel already used — a shape swap,
not a color change). Centralized behind `UIKit.draw_close_icon()`;
`draw_close_button()` calls it internally so `WaterDispenserUI`/
`FarmingTrayUI` needed zero local changes. `PauseMenuUI`,
`GraphicsSettingsPanel`, and `ZoneCustomizeUI` don't have a corner × today
(different close mechanisms) and were left alone.

## InventoryHUD Preview + Background Fixes (Jul 2026)
(Distinct from "BuildModeHUD Preview Fixes" above — that's the Construct/
Shop menu's own separate preview pool.) Three fixes: (1) preview rotation
now matches `BuildModeHUD.PREVIEW_ROTATION_DEFAULT` exactly
(`Vector3(-45, -45, 0)`, was Y-only `Vector3(0, 45, 0)`) — static, no
hover-spin, unlike `BuildModeHUD`'s pool; (2) preview camera zoomed in 3x
(`cam.size` 1.2 → 0.4); (3) the slot background's "choppy, uneven shades"
issue — root cause was `draw_rect_with_corners()` building each rounded
slot out of 6 SEPARATE overlapping translucent shapes (2 rects + 4
circles), so overlapping regions double-blended to a visibly different
alpha than single-layer regions. Fixed the same way as everywhere else in
this arc: `UIKit.draw_rounded_rect()`, a single unified `StyleBoxFlat`
draw. The 3 now-dead helper functions (`draw_rect_with_corners()`,
`draw_rect_with_corners_outline()`, `_draw_arc_corner()`) were deleted —
confirmed no other file called them.

## Farming Shop Seed tile_id Bugfix (Aug 2026)
`BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]` had a duplicate `tile_id: 6` on
both "Carrot Seeds" and "Chili Pepper Seeds" — a copy-paste typo that
shifted every seed below it in the list onto the PREVIOUS seed's correct
id (e.g. "Corn Seeds" carried `tile_id: 11`, which
`FarmingShopHelper.SHOP_ITEM_INFO` — the actual authoritative name→type
mapping — resolves to Blueberry). `SHOP_ITEM_INFO` itself was correct and
untouched; this was purely a display-list data bug. Checked every other
category in `FARMING_SHOP_ITEMS` and the entire separate `CATEGORIES` dict
for the same duplicate-id pattern — nowhere else has it. See
`docs/systems/farming/README.md`'s "Common edits — adding a new plant
species" checklist for the manual two-list-sync process this bug fell out
of, and a flagged note there about hardening it in a future pass.

## Cooking Pot UI Fixes + Prompt Overlap Avoidance (Aug 2026)
`CookingPot.gd` has no dedicated modal panel — it's driven entirely by the
shared `InteractPrompt.gd` floating prompt (text + up to 3 live 3D
ingredient icon previews), the same panel every interactable in the game
uses. Several real bugs found and fixed here, all traced to root cause
rather than patched by symptom:

- **Icons vanished on pickup**: `InteractionSystem._update_prompt()`'s
  held-item branch (CASE 1) never looked up `get_slot_icon_descriptors()`
  at all — only the empty-handed branch (CASE 2) did. Fixed generically
  (works for any held item implementing that method, not cooking-
  specific).
- **Icons/prompt vanished on drop until leaving and re-entering range**: a
  dropped item was never re-added to `InteractionSystem._tracked_bodies`
  (the `Area3D`-signal-tracked set CASE 2 scans) — same root cause as the
  Dresser/End Table timing bug above. Fixed in `_quick_drop()`.
- **"DONE — Take Dish" prompt went blank while the pot sat on a Stove**: a
  regression from the "Cooking recipe best-fit dish naming" commit added
  `if _host_stove != null: return ""` to `CookingPot.get_interact_prompt()`
  — but `Stove.get_interact_prompt()` delegates to that exact same
  function for its own ready-dish text, so the early-return silenced both
  objects' prompts at once whenever the pot was actually on a stove (the
  normal cooking setup). Removed the early-return.
- **Food Can preview rendered as an empty circle**: its descriptor used
  `is_script: true` (bare `Script.new()`, no children), but
  `FoodCan.gd`'s own `_ready()` expects a pre-built `MeshInstance3D` CHILD
  node (`get_node_or_null("MeshInstance3D")`) — unlike `FarmProduceItem`,
  which builds its mesh procedurally in code. Fixed by pointing the
  descriptor at `FoodCan.tscn` (packed-scene mode) instead of the script.
- **All 12 seed packets in the Build Mode Farming Shop preview looked
  identical**: `BuildModeHUD.PREVIEW_SOURCES` mapped every seed `tile_id`
  to the same generic `SeedItem.gd` script but never set its `seed_type`
  export var before instantiating — unlike produce, which already gets
  its `produce_type` set correctly nearby in the same file. Every seed
  silently defaulted to `seed_type`'s own `"tomato"` fallback.
  `PlantDatabase.get_seed_packet_color()` already supported all 12 species
  correctly; it just never received the right value. Fixed by adding
  `seed_type` to each of the 12 `PREVIEW_SOURCES` entries (matching
  `FarmingShopHelper.SHOP_ITEM_INFO`'s `"type"` field exactly) and setting
  it on the instance before it enters the tree.

**Layout**: middle ingredient icon sits 15% higher than the two flanking
it (a fixed pixel offset baked into the scene template, not computed at
runtime — `HBoxContainer`'s auto-layout can't offset one child, so
`IconRow` is a plain `Control` with each slot's position set explicitly).
Icon size and the outer panel's padding went through a few iterations —
final state is back to the original 32px icon size (a 2x-larger version
was tried and explicitly reverted per Brannon's call), with the panel's
top/bottom content margins symmetric (`10.0` each) so plain-text prompts
(the vast majority — "[F] Pick up crate," "[E] Wall Light," etc., which
have no icon row at all) read as properly vertically centered. Ingredient
previews render at the same 45°/45° resting rotation used everywhere else
in the project (`Vector3(-45, -45, 0)`, matching `BuildModeHUD`'s
`PREVIEW_ROTATION_DEFAULT` and `InventoryHUD`'s own previews) — static, no
hover-spin.

**Prompt overlap avoidance** (`InteractPrompt._resolve_overlaps()`): a
general, non-cooking-specific pairwise layout pass. When two visible
prompt panels would overlap on screen (e.g. a Cooking Pot placed on a
Stove — two separate objects, two separate panels, positioned very close
together), the one with a non-empty icon row outranks a plain-text one
(ties broken by whichever is closer to the player); the lower-priority
panel gets pushed directly below the higher one with a fixed gap. Panels
that don't overlap are completely unaffected — this only activates when
two real panels' rects actually intersect on screen. Runs a few passes so
a chain of 3+ overlapping panels all separate out.

**Panel styling** (this affects EVERY interactable's prompt in the game,
not just cooking — `InteractPrompt.tscn` is one shared template): the
outer panel had zero custom `StyleBoxFlat` at all before this pass — no
theme resource defines one, so it rendered with Godot's raw default
`PanelContainer` look the whole time. Now uses a dark/rounded style
matching the rest of the project's palette (8px corner radius — rounder
than the 4px modal-panel standard, intentionally, same "smaller-scale
identity" precedent as `StorageUI.gd`'s 14px). Confirmed with Brannon this
project-wide change is wanted, not something to scope down to cooking
only.

## Medical Status Screen (Aug 2026)
A third distinct panel category, alongside Modal and Ambient hover (see
"Ambient Hover Panels" below): a **non-modal, fully interactive** panel.
`scripts/ui/medical/StatusScreenUI.gd` (toggled with **[Tab]**, see
`docs/systems/medical/README.md`'s "Presentation" — Layer 3) is real
`Control`/`Button` nodes the player can click/focus and navigate with a
controller, like a modal panel — but unlike every modal panel in the
project, it does NOT set `SceneTree.paused`, does NOT lock player
movement, and has no full-screen backdrop dim; the game world stays fully
visible and running behind/around it. The one practical concession to
"modal-feeling": `Input.set_mouse_mode(MOUSE_MODE_VISIBLE)` while open (so
the body diagram/tabs are clickable), same as every other panel, restored
to `MOUSE_MODE_CAPTURED` on close.

| Category | Trigger | Blocks movement/pause? | Examples |
|---|---|---|---|
| Prompt line | proximity | no | `InteractPrompt.gd` E/F lines |
| Modal panel | explicit interaction (E) | yes | `StorageUI`, `PauseMenuUI`, `AdminMenu` |
| Ambient hover panel | proximity scan, no input | no | `TrashBagInfoPanel.gd` |
| **Non-modal interactive panel** | dedicated keybind ([Tab]) | **no** — real Controls, but world keeps running | **`StatusScreenUI.gd`** |

Still gets full standing-convention treatment otherwise: real `Control`/
`Container` node tree (built procedurally, no `.tscn`), `UIFade.fade_in()`
on open, and `ControllerUINavigation` attached exactly like every other
panel — d-pad/stick navigation crosses freely between this panel's two
sub-areas (a placeholder body diagram and a scrollable detail list) since
both are made of real focusable `Button`s in one Control tree, so
nearest-ahead scoring handles the pane-crossing for free.

## Ambient Hover Panels (Aug 2026)
A NEW panel category introduced by the Trash Can / Trash Bag feature —
deliberately distinct from the existing two:

| Category | Trigger | Input blocking | Examples |
|---|---|---|---|
| Prompt line | proximity (prompt dist) | none (text only) | `InteractPrompt.gd` E/F lines |
| Modal panel | explicit interaction (E) | yes (blocks gameplay) | `StorageUI`, `GeneratorInspectUI`, `PowerTerminalUI` |
| **Ambient hover panel** | proximity scan (3.0 m, every 0.15 s) | none (`MOUSE_FILTER_IGNORE`, no input) | **`TrashBagInfoPanel.gd`** |

`TrashBagInfoPanel.gd` (extends `CanvasLayer`, layer 50 — above prompts,
below modals): created once by `MainWorld._setup_trash_bag_panel()`,
injected with the player ref. No open/close state — a timer-driven scan
shows the panel next to whichever Trash Bag is nearest to the player (held
or on the ground/shelf), anchored to `bag.global_position + (0, 0.4, 0)`
projected via `camera.unproject_position()`. Top line = the bag's own
prompt line (`get_prompt_text()`, or `get_display_name()` when the player
is already holding it); below, one line per disposed item (`display_name`
+ a single most-relevant `data` field, or "Empty"). The per-item
`TrashBag.contents` records hold the full structured data that later
trash/recycling features consume programmatically — the panel only reads
for at-a-glance display. Panel built procedurally in `_build_panel()`.

## Shared Item Preview Kit (Aug 2026)
Fixed StorageUI's 3D item previews (Shelving/Basket/End Table/Dresser),
where most items rendered as a near-invisible speck: `_add_pool_slot()`
used `cam.size = 1.2` and mesh rotation `(-20°, 45°, 0°)`, while
`InventoryHUD.gd` (the correct, working reference) uses `cam.size = 0.4`
and `(-45°, -45°, 0°)` — Storage's camera was 3x more zoomed out on top of
a completely different angle. Extracted `InventoryHUD.gd`'s preview code
into a new shared static utility, `scripts/ui/common/ItemPreviewKit.gd`
(`build_viewport()`, `set_item()`, `clear()`), and migrated both
`InventoryHUD.gd` and `StorageUI.gd` onto it — any future adjustment to
camera angle, zoom, lighting, or the mesh-fetch fallback now happens ONCE
and cascades to every consumer automatically, instead of needing to be
hand-copied per file. `ItemPreviewKit.CAM_SIZE_PER_PIXEL` scales `cam.size`
linearly with each consumer's preview pixel size (derived from
`InventoryHUD`'s proven 64px/0.4 ratio) so different-sized preview slots
(Inventory's 64px vs Storage's 96px) show items at the same real-world
scale rather than a different zoom level per file.

`build_viewport()` also takes an optional `cam_size_multiplier` (default
1.0) for a consumer that needs to zoom out/in relative to the shared
CAM_SIZE_PER_PIXEL ratio without changing it for everyone else.
StorageUI passes 1.25 (Aug 2026) — its previews were clipping the
viewport edge at the standard ratio; Inventory stays at the default.

**Deliberately NOT adopted by `BuildModeHUD.gd`** — Build's construct/shop
previews layer a continuous hover-spin (a rotated pivot node in
`_process()`) on top of the same resting pose (`PREVIEW_ROTATION_DEFAULT`
already matches `ItemPreviewKit.ROTATION_DEFAULT` exactly, by design, and
always has). Folding Build onto the shared kit is a reasonable future
pass, scoped out of this one to avoid touching a working, more complex
implementation.

### Preview Scale Normalization + Deep Mesh Walk (Aug 2026)
`ItemPreviewKit.gd` ported two pieces of `BuildModeHUD.gd`'s preview
logic it was missing: `_combined_local_aabb()` (walks every
MeshInstance3D descendant at any nesting depth, not just direct
children — fixes CanCase/WaterCase, whose 12 can/bottle meshes sit under
`VisualRoot/Can_XX`/`Bottle_XX`, previously rendering blank) and
`_preview_normalize_scale()` (uniform scale so every item's largest AABB
dimension fills the same fraction of its preview frame — fixes large
items like the Crate overflowing while small items looked tiny).
The scale target is expressed as `PREVIEW_FILL_FRACTION` (a fraction of
each call's own `cam.size`) rather than Build Mode's fixed-meters
constant, since this kit serves multiple preview pixel sizes (Inventory
64px, Storage 96px) and a flat meters value doesn't generalize across
them the way BuildModeHUD's single-pixel-size version could get away
with. New `_duplicate_visual_tree()` duplicates only mesh geometry (with
material overrides preserved) from an already-live item reference,
skipping currently-hidden meshes — so a partially-emptied CanCase/
WaterCase previews as partially empty too.

## Storage UI Icon + Row Label Redesign (Aug 2026)
Two changes to `StorageUI.gd`, both applying automatically to every
current and future storage type through the shared panel:
- **Icon buttons, not text glyphs.** The "↑" Carry, "↓" Drop, and "⊕" Add-
  to-inventory buttons were `Button.text` glyphs; replaced with real icon
  textures (`assets/icons/arrow_decorative_n.png`,
  `arrow_decorative_s.png`, `icon_plus.png` — the last is `icon_cross.png`
  pre-rotated 45° so its × reads as a +) via `Button.icon` +
  `expand_icon` + a shared `icon_max_width` cap (`ICON_MAX_WIDTH = 22`).
  All three source PNGs carry their own gray/silver shading and are NOT
  tinted via `modulate`, unlike `UIKit`'s white-mask `close_x.png`.
  **Contract change:** `get_ui_config()`'s `primary_button_icon` is no
  longer a literal glyph string — it must be one of `StorageUI`'s
  `_ICON_TEXTURES` keys (`"carry"` or `"drop"`). The secondary button's
  icon is fixed, not config-driven — identical for every storage type.
- **Row-label text removed entirely** ("Top shelf"/"Middle drawers"/etc,
  and the auto "Row N" fallback) — deleted the `Label` node creation in
  `_layout_panel()` along with the now-dead `ROW_LABEL_H` constant,
  `C_ROW_LABEL` color, and every storage object's `row_labels`
   config/export. `ROW_GAP` (the only remaining vertical gap between rows)
   reduced `22 → 4` (18px, half of `BTN_SIZE`) as a separate, deliberate
   tightening — not a side effect of removing the labels.

## Focus Mode (Aug 2026, broadened same session)
Hold `Ctrl` to collapse every active interaction prompt down to the
single CLOSEST one, hiding the rest — a hold, not a toggle. Built as a
debugging aid for prompt-priority bugs (the shelf-unconditional-priority
bug and the grow-light-vs-tray issue were both diagnosed and fixed using
this) that's also a useful player-facing decluttering option.

Entirely a rendering concern in `InteractPrompt.gd` — it filters
`_active` down to whichever entry carries `"is_focus_target": true`
while `Ctrl` is held. Resolution stays Player-owned, in
`InteractionSystem._update_prompt()`'s CASE-2 block: the focus target is
the closest entry in the already-distance-sorted `candidates` list that
actually produces a displayable prompt, covering pickups AND
interactables AND shelving uniformly (originally scoped to "whatever E
would fire on," which excluded pickup-only objects like Test Crate and
interactable-but-no-on_interact() objects like Fuel Can — broadened same
session once that gap was reported), with the grow-light-over-tray
override still applied on top since raw distance sorting doesn't know
about that deliberate exception.

**Scope:** only empty-handed prompts (CASE 2) are tagged with a real
`true`/`false`. Held-item prompts (CASE 1) never set the key, and a
missing key defaults to shown — Focus Mode has no effect while holding
an item. Collapsing CASE 1's basket/cookpot/give-to-NPC multi-target
prompts down to one true target remains a possible future pass.

Shares the `Ctrl` key with the held-item "upright" feature by design —
this reads the key via passive per-frame `Input.is_key_pressed()`
polling rather than consuming an input event, so the two can't
functionally conflict regardless of how the other one is implemented.

## Extension points
- Any new shared cross-panel utility (like `UIFade`, `UIKit`) belongs in
  `scripts/ui/common/`, written as a small static-function `RefCounted`
  utility — not duplicated inline per-panel.

## Controller support

Every interactive panel attaches `ControllerUINavigation`
(`scripts/ui/common/ControllerUINavigation.gd`): d-pad + optional left-stick
focus (nearest-ahead scoring — vertical lists step one row at a time),
B-close (topmost-aware across stacked CanvasLayers), slider d-pad adjust
with hold-to-accelerate repeat, runtime A/B → `ui_accept`/`ui_cancel`, and
public `is_active()` used by `InteractionSystem` to gate all world input
while any nav UI is open. The per-UI wiring matrix, the mouse-motion
deadzone, and the OS-cursor hiding live in
`docs/systems/controller/README.md` — read it before adding controller
support to a new panel.
