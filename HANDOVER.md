# Handover — BunkerGame

## Status (latest, Jul 2026): Toast format reworked back to old look/position — NOT YET in-editor confirmed

### Toast format rework (this session — Brannon disliked the top-right domain-tinted card look)
Brannon wanted the LIVE toast look/position reverted to the old
pre-`NotificationManager` `HUD.show_soft_warning()` style (long rectangle
centered above the inventory bar, filled with the severity color) — same
underlying queue/severity logic as steps 1-4, just a visual/position
rework, confirmed via 4 clarifying questions before writing code:
- **Shape/position:** back to a rectangle centered above the inventory bar
  (matches `show_soft_warning()`'s old position), NOT the old top-right
  stack.
- **Fill:** solid severity color, semi-transparent (not fully opaque) —
  `TOAST_FILL_ALPHA = 0.62`, using the existing `SEVERITY_COLOR_INFO/
  WARNING/CRITICAL` hexes directly as the fill instead of a thin accent
  bar.
- **Border:** every toast also gets a dark semi-transparent border —
  `TOAST_BORDER_COLOR = rgba(0,0,0,0.55)`, `TOAST_BORDER_WIDTH = 2.0`.
- **Stacking:** kept the real queue (not a one-at-a-time replace like the
  old system) — stacks vertically above the inventory bar, newest toast
  closest to the bar, older ones pushed upward.
- Text stays the same 13px size via `UIKit.draw_shadowed_text()`, just a
  new fixed light `TOAST_TEXT_COLOR` for contrast against the colored fill
  (domain no longer tints the toast itself — severity is the only signal
  a toast needs now).

**Implementation (`NotificationManager.gd`):**
- `_on_draw()` rewritten: no more `STACK_MARGIN`/top-right math. Toasts are
  centered horizontally; vertical anchor comes from looking up
  `get_first_node_in_group("hud")` and reading its public `inventory_hud`
  Control's `get_global_rect().position.y` (`GAP_ABOVE_BAR = 12.0` above
  it). Falls back to `FALLBACK_BOTTOM_MARGIN = 140.0` from the bottom of
  the viewport if no HUD is in the current scene. Iterates `_queue` in
  reverse (newest first) so the newest toast lands closest to the bar.
- `HUD.gd`: added `add_to_group("hud")` in `_ready()` specifically so this
  global autoload (outside HUD's own scene tree) can find `inventory_hud`
  without a hardcoded node path.
- `_draw_toast()` rewritten: draws a solid severity-color fill rect
  (`TOAST_FILL_ALPHA`), a dark border rect, and the message text — deleted
  the old `UIKit.draw_panel()`/domain-theme call and the thin left accent
  bar. Removed the now-dead `_theme_with_alpha()` helper (only existed to
  fade the old domain-tinted panel).
- `NotificationHistoryUI.gd` (pause-menu history rows) updated to **match**
  the new toast look — each row is now a `PanelContainer` styled with the
  same `TOAST_FILL_ALPHA` severity fill + `TOAST_BORDER_COLOR`/
  `TOAST_BORDER_WIDTH` border + `TOAST_TEXT_COLOR` text (constants reused
  directly from `NotificationManager`, not redefined), replacing the old
  thin accent-bar + domain-tinted-text row style. Removed the now-unused
  `ACCENT_W` const.
- Verified via `tools/godot_check.sh` → `PASS`. `docs/systems/ui/README.md`
  updated same commit (toast look/position + history row style sections
  rewritten).
- **Next when resumed:** get Brannon's in-editor visual confirmation —
  not yet tested in the actual game, only parse-verified.

### Toast dimensions/corners/font follow-up (this session)
Brannon's next round of visual feedback on the reworked toast: half the
toast height, 1.5x the width, rounded corners, and match the shared
UI-system font — applied to both the live toast AND the pause-menu
history rows.
- `NotificationManager.gd`: `TOAST_WIDTH` 340 -> 510, `TOAST_HEIGHT` 48 ->
  24, new `TOAST_CORNER_RADIUS: int = 8` const added as the single source
  of truth for corner radius (reused by history rows too).
- `_draw_toast()` rewritten again: plain `draw_rect()` has no
  corner-radius support, so it now builds a `StyleBoxFlat`
  (bg_color/border_color/border_width/corner_radius) and calls
  `sb.draw(_canvas.get_canvas_item(), rect)` instead of the old two
  `draw_rect()` calls.
- `NotificationHistoryUI.gd`: added
  `add_theme_font_override("font", UIKit.font())` to both `text_lbl` and
  `time_lbl` (previously used the plain theme default font, unlike the
  live toast which already went through `UIKit.draw_shadowed_text()`).
  Row `StyleBoxFlat` corner radius changed from a hardcoded `3` to
  `NotificationManager.TOAST_CORNER_RADIUS`.
- Verified via `tools/godot_check.sh` -> `PASS`. `docs/systems/ui/
  README.md` updated same commit (toast look/position bullet + history
  row-style bullet).
- **Next when resumed:** get Brannon's in-editor visual confirmation —
  not yet tested in the actual game, only parse-verified.

## Status (prior, Jul 2026): UI Kit + Notifications plan steps 1-4 DONE, plus new notification history panel (pause menu) DONE — NOT YET in-editor confirmed
Implementing `PLAN_ui_kit_and_notifications` (shared `UIKit.gd` + central
`NotificationManager` toast system), per the plan's own Part 3 order of
operations. Steps 1-4 done, parse-verified via `tools/godot_check.sh`, NOT
yet in-editor/visually confirmed by Brannon. Next paused checkpoint is
still §1.5 step 5 (neutral theme sign-off, already locked in — see below)
and remaining WATER/POWER file migrations + water signals (Part 3 steps
5-6) — not started.

### Step 4 — Power signal wiring (this session)
`NotificationManager.connect_power_signals()` added — thin adapter, all
detection logic stays in `PowerManager`, this just translates 10 of its
signals into `notify()` calls:
- CRITICAL: `grid_tripped`, `grid_offline`
- WARNING: `overloaded_started`, `breaker_tripped`, `battery_drained`,
  `generator_stopped`
- INFO: `grid_restored`, `overloaded_ended`, `generator_started`,
  `breaker_reset`, `generator_fuel_low`, `battery_low`
Generator/battery/breaker toasts include the specific id in the text
(e.g. `"Generator gen_2 fuel low (18%)"`), per Brannon's explicit call.
`generator_stopped`'s free-text `reason` param is appended to the toast.

**Severity colors are FIXED across all domains** (Brannon's explicit call,
overrides the plan's original theme.warn/theme.crit approach): `INFO =
#878787`, `WARNING = #8f940d`, `CRITICAL = #94302b` — same hex regardless
of whether the toast is POWER/WATER/NEUTRAL. `SEVERITY_COLOR_INFO/WARNING/
CRITICAL` consts in `NotificationManager.gd`. CRITICAL toasts use the same
flat `DEFAULT_DURATION` as everything else — no special persistence/manual-
dismiss behavior added (Brannon confirmed: keep it simple for now, revisit
later if needed).

Since `PowerManager` is a per-scene instance (group `"power_manager"`), not
an autoload, `NotificationManager._ready()` (fires once at game boot) can't
reach it. `MainWorld._setup_power_manager()` now calls
`call_deferred("_connect_power_notification_signals")` right alongside its
existing `_connect_power_hud_signals` deferred call — new
`_connect_power_notification_signals()` just calls
`NotificationManager.connect_power_signals()`. Guarded with `is_connected()`
checks in `NotificationManager`, safe to call more than once.

**Removed a duplicate notification path:** `grid_tripped`/`grid_restored`/
`grid_offline` previously ALSO surfaced via `HUD.show_soft_warning()` from
`MainWorld._on_grid_tripped/restored/offline()` — that text is removed from
those three functions (camera-trauma shake on `grid_tripped` stays) so the
toast is the only place these three events show a message now, not two
overlapping notifications for one event.

Verified via `tools/godot_check.sh` — `PASS` after this change.
`docs/systems/ui/README.md`'s NotificationManager section updated same
commit with the full signal-mapping + duplicate-removal note.

**Next when resumed:** confirm with Brannon whether to proceed straight
into Part 3 steps 5-7 (PowerTerminalUI migration, remaining WATER/POWER
file migrations + new water alert signals, player-stats ThresholdWatcher)
or pause again for review first.

### Notification history panel (this session, follow-on feature, not part of the plan doc)
New scrollable **notification history** window — last 20 notifications,
minimized/condensed rows, visible ONLY inside the pause menu, positioned
in the upper-right quadrant (~3/4 right, 3/4 up the screen).

- `NotificationManager.gd`: added a second, independent
  `_history: Array[Dictionary]` (separate from the fading `_queue`), capped
  at `MAX_HISTORY_LEN = 20` (own eviction, `_queue`'s fade/expire logic
  untouched). Each entry: `{domain, severity, text, fired_at_msec}` (via
  `Time.get_ticks_msec()`, not a mutated destructive `age` like `_queue`
  uses). `notify()` appends to both `_queue` and `_history` and emits new
  `history_changed` signal. New `get_history() -> Array[Dictionary]`
  accessor returns **newest-first** for direct UI consumption.
- New file `scripts/ui/notifications/NotificationHistoryUI.gd` (extends
  `Control`) — real `ScrollContainer` + `VBoxContainer` of rows (per this
  project's standing "no immediate-mode for new panels" convention). Row =
  severity-colored accent bar (reuses `SEVERITY_COLOR_*` consts) +
  domain-tinted text (`UIKit.theme_for(domain).header`) + "Xs/Xm/Xh ago"
  timestamp, refreshed every frame while `visible` via its own lightweight
  `_process()` (safe — pause menu doesn't set `SceneTree.paused`). Listens
  to `history_changed` to rebuild rows live while the pause menu is open.
- `PauseMenuUI.gd`: instantiated as a **sibling** of `_panel`/`_blur_rect`
  (own `_history_ui` var), added at the end of `_build_ui()` — NOT nested
  inside either, so it shows/hides for free with the CanvasLayer's own
  `visible` toggle. Also fades in via `UIFade.fade_in(_history_ui)` in
  `open()`, alongside the existing `_panel` fade-in.
- Confirmed decisions (Brannon Q&A, all 5 answered before writing code):
  newest-at-TOP (opposite of live toast stack), live-updating while open,
  condensed single-line rows with severity dot + timestamp, no header/
  title/close button (closes automatically with the pause menu), ~380×480px
  panel anchored at (0.75×vp width, 0.25×vp height) top-left, clamped to
  viewport, cap of 20 (separate array from the toast queue).
- Docs: `docs/systems/ui/README.md`'s NotificationManager section extended
  with a "Notification history panel" subsection, same commit.
- Verified via `tools/godot_check.sh` → `PASS` after these edits.
- **Next when resumed:** get Brannon's in-editor visual confirmation
  (position, row look, live-update behavior while pause menu is open) —
  not yet tested in the actual editor/game, only parse-verified.

1. **`UIKit.gd`** (`scripts/ui/common/UIKit.gd`, new) — shared theme/drawing
   kit for the hand-drawn immediate-mode panels. `class_name UIKit`, pure
   `static func`s, `RefCounted`-style (no instance state), same convention
   as `WaterQualityColor.gd`. `enum Domain { WATER, POWER, NEUTRAL }` +
   `class UITheme` (bg/border/header/text/dim/ok/warn/crit `Color`s).
   Water/power theme colors copied **verbatim** from
   `WaterDispenserUI.gd`/`PowerTerminalUI.gd`'s old consts — refactor, not
   redesign, zero visual drift. `NEUTRAL` (steel-gray) is new, no prior
   precedent, used by `NotificationManager`.
   - **Class named `UITheme`, not `Theme`** — bare `Theme` collided with
     Godot's built-in `Theme` (Control theme resource) class and produced a
     cross-script `"argument should be Theme but is Theme"` parse error.
     Do not rename this back.
   - Primitives: `font()`, `theme_for()`, `draw_backdrop()`, `draw_panel()`,
     `draw_close_button()`, `draw_bar()`, `draw_header()`,
     `draw_shadowed_text()`, `button_stylebox()`.
2. **`WaterDispenserUI.gd` migration** (reference migration, must look
   visually IDENTICAL to before) — local const palette replaced with
   `var _theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.WATER)`; all
   `_draw()` calls for backdrop/panel/close-button/bar/shadowed-text/arrow
   button styling now delegate to the matching `UIKit` primitive.
   `QUALITY_GOOD_COLOR`/`OFF_COLOR`/`ACCENT_TOGGLE`/`PRIO_COLORS`
   deliberately stayed as local consts (domain-specific, not structural).
   **Other hand-drawn panels (`PowerTerminalUI`, etc.) are NOT migrated
   yet** — do the same mechanical migration next time one of those files is
   touched, not as an unrelated drive-by.
3. **`NotificationManager.gd`** (`scripts/ui/notifications/`, new) — real
   project-level autoload (registered in `project.godot` after
   `GraphicsSettings`), matching `SaveManager`/`WorldManager`/
   `DeviceDatabase`/`GraphicsSettings`'s pattern (NOT the group-lookup
   pattern `WaterManager`/`PowerManager`/`PlayerStats` use — a toast has no
   save-specific world state).
   - **No `class_name`** on this script — a `class_name` matching its own
     autoload name causes a `"hides an autoload singleton"` parse error.
     Same no-`class_name` convention every other autoload in this project
     already follows.
   - `notify(domain: UIKit.Domain, severity: Severity, text: String,
     duration: float = 4.0)`, `enum Severity { INFO, WARNING, CRITICAL }`.
     Queue: newest at bottom of stack, each toast fades independently over
     its last 20% of lifetime. `MAX_QUEUE_LEN = 20` (this pass's own
     default, not yet explicitly confirmed by Brannon). Own `CanvasLayer`
     at `layer = 220` (above every existing panel layer, previous highest
     was `GraphicsSettingsPanel`=210), top-right stack, drawn via
     `UIKit.draw_panel()`.
   - Nothing calls `notify()` automatically yet — skeleton + rendering
     only, no signal wiring. That's step 4, paused.
- Verified via `tools/godot_check.sh` (Godot 4.6.3 headless binary) —
  `PASS — no script parse/compile errors` after all three steps + the two
  parse-error fixes above.
- Full detail in `docs/systems/ui/README.md`'s "UIKit shared kit" and
  "NotificationManager" sections (added this session, same commit).
- **Next step when resumed:** confirm step 4 scope/go-ahead with Brannon,
  then wire `PowerManager`'s `grid_tripped`/`grid_restored`/`brownout_started`
  /etc. (and water/player-stats signals per the plan's §2.3) to
  `NotificationManager.notify()` calls.

## Status (Jul 2026): arrow-texture audit plan fully implemented (`40b9e32`), NOT YET CONFIRMED in-editor
Brannon attached a full audit + fix plan (arrows read as kinked "M" shapes,
and weren't touching within/between pairs). Implemented in full, as two
separate commits per the plan's own recommendation:

1. **Spacing fix (`41f442e`)** — two real sub-causes, both fixed:
   - Texture content sub-range: `pipe_flow_arrow.png`'s two baked chevrons
     each have heavy transparent padding within their own `0..0.5` half
     (confirmed via direct alpha-channel pixel inspection — opaque content
     only spans columns 15-50 of 128px, i.e. `0.1172-0.3906`). Tile-boundary
     math was already correct; the FULL padded half was being sampled per
     tile, so "touching" tiles still had a visible gap between the actual
     chevron shapes. Fixed: shader now samples only the measured content
     sub-range.
   - `gap_world_length` (between-pair gap) default lowered `0.5 -> 0.18`,
     now also surfaced as an explicit `WaterPipeSegment.ARROW_PAIR_GAP`
     tunable pushed via `set_shader_parameter()`.
2. **Kinked-arrow-shape fix (`40b9e32`)** — root cause: the ceiling-strip
   band's cross-section coordinate was a raw normal·up dot product (a
   COSINE of the angle, non-linear), made much worse by only ~2-3 of the
   pipe's 10 flat faces falling within the visible band (per-vertex value
   linearly interpolated across a couple of large flat panels). Fixed by
   REPLACING the wrap-around CylinderMesh + up-facing discard mask with a
   small flat ribbon mesh — perfectly linear UV by construction, no cosine
   term, no faceting. Mounted via a plain world-space `+Y` offset above the
   pipe, oriented with the same `look_at()`+90°-rotate trick the main pipe
   mesh already uses. `v_up_dot`/`UP_BAND_DOT`/`MODEL_NORMAL_MATRIX` are
   gone from the shader entirely; `cull_disabled` kept deliberately (a flat
   ribbon's visible face depends on winding, and this shader has already
   been bitten twice by wrong-side-culling assumptions).

**Playtest checklist (see the attached plan's §2.4 for the full version):**
1. Look at a straight pipe run from below (normal play camera) — confirm
   each arrow is now a clean, undistorted chevron, not kinked/zigzag.
2. Confirm quality and purity arrows within one pair sit directly adjacent,
   no visible gap.
3. Confirm the gap between pairs is visibly smaller than before but still
   reads as a clear break — flag back if `0.18` needs retuning either way.
4. Check a pipe run with at least one elbow/corner — confirm the arrow
   overlay still follows the bend and phase/continuity across the joint
   still reads as one continuous crawl (don't regress prior continuity fixes).
5. **Ribbon-specific check:** confirm normal gameplay camera angles
   (including any top-down/isometric build-mode view) still show the ribbon
   clearly — a flat quad facing one fixed direction could theoretically read
   worse from some angles than the old wrap-around cylinder did for free.
6. Known unchanged limitation: purely vertical pipe risers still show no
   arrows (not in scope, flagged only).

Verified via BOTH `tools/godot_check.sh` AND a targeted headless
render/shader-compile harness (instantiating the actual `WaterPipeSegment`,
confirming zero `SHADER ERROR` output) for every commit this round — per the
standing lesson from the earlier shader-compile-failure incident. See
`docs/systems/water/README.md`'s "Arrow shape distortion (kinked 'M' shapes)
+ spacing fixes + flat ribbon rewrite" section for full detail. `origin/main`
at `40b9e32`.

## Follow-up (same day) — arrows stretched out lengthwise, FIXED (`5aad027`)
After the ribbon rewrite + spacing fixes above, Brannon reported arrows
still read as oversized/stretched along the pipe's length. Root cause: the
earlier texture-content-sub-range fix correctly cropped each chevron to its
real ~35px content width, but `tile_world_length` was never shrunk to
match — it was still the old `0.8`, a leftover arbitrary value from the
pre-redesign wrap-around-cylinder era with no relation to this texture's
actual proportions. That narrow content was being stretched across the
full `0.8` world-units, ~7.4x its natural size (confirmed by direct
calculation: `0.8 / 0.108 ≈ 7.4`). Fixed by deriving `tile_world_length`
AND `gap_world_length` from the ribbon's actual current width/aspect
(`WaterPipeSegment.ARROW_CONTENT_ASPECT = 35/64`, `ARROW_PAIR_GAP_RATIO =
0.225`) instead of hardcoded numbers — both now pushed explicitly via
`set_shader_parameter()` every rebuild, so they can't silently drift out of
sync with the ribbon's own dimensions again. Verified via the same headless
shader-compile harness (confirmed correct computed values: `tile_world_length
≈ 0.108`, `gap_world_length ≈ 0.024`) plus `godot_check.sh`. **Please
pull and confirm arrows now read as correctly-sized, not stretched.**

## Status (latest, Jul 2026): filter wear now scales with incoming water quality, pushed `f5d0886`
Follow-up to the QoL pass below — Brannon wanted filter depletion RATE to
vary with incoming (raw, pre-purification) water quality instead of always
running at a fixed max: max rate at incoming quality <=50%, linear scale
down to 25% of max at 100% incoming, and 0 (no wear at all) when the
purifier isn't connected to any water source. New
`WaterPurifier._compute_wear_multiplier()` (reads
`WaterManager.get_upstream_raw_quality()` — same value the purifier's own
info panel shows as INPUT) multiplies into the existing max-rate tick in
`_process()`. `_ready()`'s debug print relabeled `max_depletion_per_second`
since the live rate now varies below it.

Verified via a headless functional test — confirmed clamped 1.0 at
incoming<=50, exact linear values at 75/90/100 (0.625/0.4/0.25), and 0.0
when disconnected — plus `tools/godot_check.sh`. **Needs in-editor
playtest**: let a purifier run with clean (near-100%) incoming water and
confirm its filter lasts noticeably longer than with dirty (<=50%)
incoming water at the same elapsed time.

## Status (prior, Jul 2026): Purifier QoL pass (6 items) implemented in full, NOT YET CONFIRMED in-editor
Follow-up plan to the base Purifier Filter system below (that plan's own
mechanics — `filter_quality`/`get_output_quality()`/`replace_filter()` —
were a hard dependency, already shipped). All 6 items done:
1. **Passive mesh tint** — `WaterPurifier._band_mat` (promoted to a member)
   re-tints every `_process()` tick via `WaterQualityColor.get_color(filter_quality)`.
2. **Prompt swap delta** — folded into item 3's prompt color-coding.
3. **Downgrade confirmation** — new `ConfirmDialogUI.gd`
   (`scripts/ui/common/`), a reusable parameterized Yes/No dialog modeled
   on `BuildModeHUD`'s "EXPAND BUNKER" dialog (**that file itself was
   deliberately left untouched — NOT migrated to the new shared component**,
   flagged as a follow-up idea only). Downgrade swaps now require
   Yes/No confirmation; equal-or-better swaps proceed immediately as
   before. `PurifierFilterItem.get_use_prompt()` colors the `(X% -> Y%)`
   suffix green/red via BBCode.
4. **Low-filter warning at 50%** — new `TransientNotice.gd`
   (`scripts/ui/hud/`), this project's first toast/notification component
   (none existed before). Fires once per crossing, re-arms above 50%.
5. **Inventory badge** — `PurifierFilterItem.get_charge_info()`, verified
   against `InventoryHUD`'s actual size-2-array-or-nothing handling first.
6. **Aggregate query** — `WaterManager.get_purifiers_needing_attention()`,
   built as groundwork only; deliberately NO dedicated HUD element wired up
   yet (plan's own recommendation — a typical base has too few purifiers
   for it to matter yet).

Verified via a functional headless test harness exercising all 6 items
together (band tint color, warn/re-arm sequence, aggregate query
before/after a fix, prompt color+delta text both directions, and the full
downgrade-confirm-then-swap flow including the dialog's `confirmed` signal
actually completing the swap) — not just parse-check. Plus
`tools/godot_check.sh`. **Full in-editor playtest still needed** — see the
plan's own checklist (7 items) reproduced in
`docs/systems/water/README.md`'s new "Purifier QoL pass" section.

## Status (prior, Jul 2026): Purifier Filter system implemented in full, NOT YET CONFIRMED in-editor
Full attached audit/design plan implemented in one pass — new
`PurifierFilterItem.gd` (fresh/used states, one script), `WaterPurifier.gd`
filter depletion (10 in-game days) + `get_output_quality() = 50 +
filter_quality*0.5` + `replace_filter()`/`spawn_starting_filters()`,
`WaterInfoUI.gd`'s purifier panel gets a live FILTER QUALITY bar and no
longer hardcodes output at 100%, and every place that used to flatten
purified water to `100.0` (`WaterManager.get_received_rate_mL()`, the
per-edge dual-arrow color push, the periodic quality-color refresh tick)
now resolves the real graduated number via a new shared
`_resolve_output_quality()` helper + `WaterGraph.get_purifiers_on_path()`.

**Two deliberate deviations from the plan, both documented in
`docs/systems/water/README.md`'s new Purifier Filter section:**
1. Multi-purifier resolution uses a fresh, un-cached `WaterGraph` BFS every
   call instead of the plan's suggested cached-directed-adjacency reuse —
   avoids a second staleness class on top of the already-known "quality
   arrow stuck green" lesson (a purifier's own output changes continuously,
   independent of when the graph topology last changed).
2. Shelf storage: checked `Shelving.gd`'s ACTUAL current code (it already
   stores real node references, not a plain count, per the plan's own
   instruction to verify before assuming) and found the plan's stated
   data-loss risk doesn't apply — so BOTH fresh and Used filters are
   shelf-storable, not just fresh ones.

Verified via headless functional test harnesses (not just parse-check) —
confirmed the exact formula values (`75.0`/`50.0`/`100.0` at filter
`50/0/100`), `get_purifiers_on_path()` correctly finding the purifier on a
constructed hookup->purifier->endpoint graph, `_resolve_output_quality()`
returning the correct worst-case number, and `replace_filter()` correctly
ejecting a Used item with the old quality, installing the new one, and
freeing the consumed item. Plus `godot_check.sh` (parse/type only).
**Full in-editor playtest still needed** — see the plan's §6 checklist
(reproduced in the README section) before starting anything else on this
system.

## Follow-up (same day) — spacing tuned, pushed `3172537`
Brannon asked for more space between quality/purity PAIRS, and the quality
and purity arrows WITHIN one pair pulled closer together. Shipped:
- `ARROW_PAIR_GAP_RATIO` (between pairs) raised `0.225 -> 0.7`.
- New `intra_pair_gap` shader uniform + `ARROW_INTRA_PAIR_GAP_RATIO = 0.3`
  (WaterPipeSegment.gd) — pulls the purity tile's start earlier so it
  sits closer to / slightly overlapping the quality tile instead of just
  flush. **One tradeoff worth knowing:** in that small overlap zone, the
  quality tile's own content always wins (checked first in the shader) —
  only the purity arrow's leading edge tucks in behind it. If the overlap
  ever looks wrong (e.g. purity looks visibly clipped), that ratio is the
  first thing to turn back down.
Verified via the headless shader-compile harness (confirmed computed
values: `gap_world_length ≈ 0.076`, `intra_pair_gap ≈ 0.032`) plus
`godot_check.sh`. **Please pull and confirm the new spacing feels right.**

## Prior status (superseded by above, kept for context)

Brannon reported three issues after the purifier-pulse/dispenser-fill features
above: (1) dispenser UI fill meter missing, (2) both arrow lanes should sit
on the ceiling-facing strip as touching sequential pairs instead of wrapped
around the pipe's circumference, (3) quality arrows only ever showed green.
All three root-caused and fixed this session — **do the playtest checklist
below before touching anything else in the water system.**

1. **Quality arrow "always green" — FIXED.** Root cause:
   `WaterManager.set_quality_color()` was only ever pushed from inside
   `recompute_flow_directions()` (graph-mutation-triggered only), but
   `WaterHookup.water_quality` decays continuously every frame — the color
   got set once near 100% and never touched again. Fix: new
   `WaterManager._process(delta)` + `_refresh_quality_colors()`, ticking
   every `QUALITY_REFRESH_INTERVAL=0.5s`, re-pushes just the quality tint
   from the CURRENT live hookup quality (cheap, no graph re-walk). **Playtest:**
   let a hookup's water quality decay below 75%/50% over real time (or use
   the F7 admin quality cheat if faster) and confirm the pipe arrows'
   FRONT (quality) lane actually shifts yellow/red within ~0.5s, not just at
   the moment a pipe was placed.
2. **Arrow layout redesign — ceiling strip, sequential pairs.** Both quality
   and purity lanes now render ONLY on the pipe's top (ceiling-facing) strip
   (world-normal `v_up_dot` test, `pipe_flow.gdshader`), as a repeating
   along-pipe sequence: quality tile touching a purity tile, then a blank
   gap, then repeat (`gap_world_length` uniform, default 0.5). **Playtest:**
   confirm both arrow types are visible on top of the pipe only (not wrapped
   around the sides/bottom), reading as touching pairs with a visible gap
   before the next pair. **Known limitation, not fixed:** a purely vertical
   pipe run (straight up/down) has no face that ever points "up" — expect NO
   arrows on vertical risers. Flag back if this needs a different treatment.
3. **Dispenser UI fill bar — added (was simply missing, not a regression).**
   `WaterDispenserUI.gd`'s panel only ever had the numeric "STORAGE: X / 5000
   mL" text — no bar/gauge graphic existed in the panel itself (separate from
   the 3D dispenser body's own `tank_fill.gdshader` tint, which is a
   different, world-space visual and already existed). Added a drawn fill
   bar directly under the STORAGE text; `PANEL_H` bumped 430->454 to fit.
   **Playtest:** open a dispenser's panel and confirm a bar/gauge (not just
   text) now shows fill level, filling proportionally to STORAGE's numeric
   readout.

**Follow-up (same day, two rounds):** Brannon reported the arrows/flow
indicator had gone COMPLETELY invisible after the ceiling-strip redesign.
Round 1 fix (`36b15ca`, `cull_back` -> `cull_disabled`) was real but NOT the
actual show-stopper — Brannon confirmed "changed nothing." Round 2 found the
REAL root cause via a headless render harness (see below): `const float
UP_BAND_DOT: float = 0.55;` used GDScript's typed-const colon syntax, which
is NOT valid Godot shading language — the shader failed to compile entirely,
the whole time, silently. **`tools/godot_check.sh`'s script-parse check does
NOT catch shader compile errors** — it stayed green through both rounds
while the shader was actually broken. Fixed to `const float UP_BAND_DOT =
0.55;`. Pushed as `5619ec0`. Verified this time by actually instantiating
the `ShaderMaterial` in a headless Godot script and confirming zero
`SHADER ERROR` output (previously reproduced the exact "Shader compilation
failed" error this way before the fix, confirming true root cause). Both
the cull fix and the syntax fix are needed together — please pull and
playtest for real this time.

**Standing lesson for future water/power shader work:** a shader-only syntax
error is invisible to `godot_check.sh` (GDScript parse only). If a shader
edit ships and something "goes completely invisible" with no console error
visible in-editor either, verify the shader itself actually compiles (a
small headless script instantiating the `ShaderMaterial` and printing any
`SHADER ERROR` output) before assuming the bug is in masking/culling/uniform
logic.

**Follow-up (same day, round 3):** Brannon confirmed arrows now show
centered on top as sequential pairs (redesign + shader-compile fix both
confirmed working), but each tile showed 2 arrows squished side by side
instead of 1. Root cause: `pipe_flow_arrow.png` bakes TWO chevrons within
its own 0..1 UV width (confirmed via pixel inspection — verified period is
exactly half the texture width), a leftover from the old full-circumference
single-lane layout. Fixed by scaling `tex_u` into the texture's own `0..0.5`
sub-range per arrow tile instead of `0..1` — no texture asset change needed.
Pushed as `5201475`.

Passed `tools/godot_check.sh` (parse/type only, not behavior) AND a targeted
headless shader-compile check this round. See
`docs/systems/water/README.md`'s "Quality arrow 'stuck green' fix +
ceiling-strip arrow redesign + dispenser fill bar" section for full detail.
`origin/main` at `5201475`.


**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## Status: purifier clean-pulse + dual quality/purity arrows, and dispenser fill visual — SHIPPED, NOT YET CONFIRMED in-editor

Both features from a plan doc ("Purifier clean-pulse + dual quality/purity
arrows, and dispenser fill animation") are implemented and pushed
(`562b251`). **Neither has been confirmed working in-editor by Brannon yet**
— do the playtest checklists below before touching anything else in the
water system.

> **Process note:** a prior session in this same arc ran out of credits
> between finishing Feature 1's code and actually committing/pushing it —
> Brannon reported "seeing neither feature" on a fresh pull, which traced
> back to exactly that (Feature 1 simply wasn't in the repo yet). If a
> similar "it's not there" report ever comes up again, check `git log`
> against `origin/main` before assuming a code bug.

### Feature 2 — Dispenser fill-level visual
`WaterDispenser.gd`'s body mesh uses a `ShaderMaterial`
(`assets/shaders/tank_fill.gdshader`) instead of a flat color — no new
geometry, the box itself is the gauge. Object-local `VERTEX.y` (works
regardless of placement/rotation) compared against a `fill_pct` uniform:
below the cutoff renders water-blue, above it renders the normal empty-tank
color, thin bright waterline band at the cutoff. Pushed every frame from
`_process()` via `_update_fill_visual()` — same cadence as the existing fill
tick, no new polling loop.

**IMPORTANT, easy to misread as "not working":** the empty-tank color is
deliberately identical to the OLD flat body color, so a fresh, never-filled
dispenser looks visually unchanged except for a barely-visible thin line at
the very base. **The dispenser must actually be connected to a hookup/pipe
and receiving water before the fill visual becomes obviously visible.**

**Playtest checklist:**
1. Build a dispenser, connect it to water, let it fill — confirm the body
   visibly tints blue from the bottom up in real time, matching the numeric
   UI panel.
2. Confirm empty (0%) and full (100%) both look correct at the extremes.
3. If it still reads as invisible/unclear even while actively filling, the
   fallback (a dedicated semi-transparent window panel instead of
   recoloring the whole box) is the next thing to try — flag back rather
   than tuning the current shader blind.

### Feature 1 — Purifier clean-pulse + dual quality/purity arrows
Confirmed design answers (Brannon): pulse EVERY purifier on a flipped
consumer's resolved path (not just the most-recently-mutated one); ONE
pulse total per recompute pass, deduped by purifier; tweened expanding flat
ring only (no particle accent); the two-lane arrow overlay is the PERMANENT
default for every pipe segment in every save, not just purified runs;
extract a shared `WaterQualityColor` helper (was duplicated in
`WaterInfoUI.gd`/`WaterDispenserUI.gd`).

Implemented — see `docs/systems/water/README.md`'s matching section for
full detail. Summary:
- `WaterQualityColor.gd` (new) — shared red/yellow/green threshold helper.
- `WaterManager._process_purity_and_dual_arrows()` — called once per
  `recompute_flow_directions()` pass; forward BFS over the already-resolved
  flow directions computes `is_purified` per edge; diffs current
  per-consumer purity against a persisted `_last_purity_state` to detect
  flips; walks backward from each flipped consumer collecting every
  purifier crossed (deduped set); pulses each once. `_purity_state_seeded`
  prevents a false pulse burst on the first recompute after a save load.
- `WaterManager._find_purifier_by_key()` (new) — purifier nodes have no
  `consumer_ref`, so this scans a new `"water_purifier"` group by `node_key`.
- `WaterPurifier.play_clean_pulse()` (new) — tweened `TorusMesh` ring,
  scale `0.3->2.5` + alpha `->0` over 0.4s.
- `pipe_flow.gdshader` — `quality_color`/`purity_color` uniforms; the
  existing scrolling arrow band splits into two adjacent half-width lanes,
  each remapped to a full 0..1 range so both sample a complete chevron.
- `WaterPipeSegment.gd` — `PURITY_COLOR_RAW`/`PURITY_COLOR_PURIFIED` consts,
  `set_quality_color()`/`set_purified()` setters.

**Playtest checklist:**
1. Place a purifier on a hookup with existing impure downstream consumers —
   confirm a ring pulse fires ONCE at the purifier's location, not once per
   consumer, not elsewhere.
2. Confirm every pipe segment shows two adjacent half-width arrow lanes:
   front lane matches the existing quality red/yellow/green thresholds
   (same colors/logic as the hookup/sink/purifier info panels); back lane is
   white upstream of any purifier, light-blue downstream of one.
3. Delete the purifier (or reintroduce a bypass) — confirm the back lane
   reverts to white and the front lane resumes tracking raw decayed
   quality.
4. Reload a save with an already-purified network — confirm NO false pulse
   burst fires on the first recompute after load.
5. Spot-check performance on a larger pipe network (the per-edge push is
   already O(edges) per mutation, shouldn't regress, but confirm on a real
   save).
6. Known scope note, not yet stress-tested: the forward-BFS purity
   propagation assumes each node has one resolved incoming edge (true for
   the common case) — a rare diamond-merge topology with two genuinely
   different-purity incoming edges takes whichever the BFS visits first.

## Git state
- Local clone: `/home/user/bunker-game-repo/repo`
- `origin/main` at `562b251` (both features pushed, nothing pending).
- Git identity used: `-c user.name="Brannon Henrie" -c user.email="brannon@magellan-apps.com"`
- Push command: `export $(cat ../.env | xargs) && git push https://${GITHUB_TOKEN}@github.com/Magellan36/bunker-game.git main`

## Standing rules (unchanged, still apply)
- Confirm root cause before writing fixes — one change at a time.
- No "god files" — split out new self-contained functionality into its own
  file/folder.
- Doc-update discipline: update the relevant `docs/systems/*/README.md` in
  the *same commit* as any code change touching that system. Treat doc
  drift as a bug.
- Keep all existing debug prints (`PIPE_DEBUG`/`[PipeDebug]`, `[FlowDebug]`,
  power system `[Reconciler:...]`/`[MW:DIAG]`, etc.) — do not strip them.
- No compiler in sandbox — always run
  `tools/godot_check.sh /home/user/godot-bin/Godot_v4.6.3-stable_linux.x86_64`
  before reporting a fix done (re-download the binary if a fresh sandbox
  doesn't have it — `godotengine/godot` GitHub releases, `4.6.3-stable`,
  linux.x86_64 build). This only catches parse/type/autoload errors, NOT
  logic/visual/shader bugs — Brannon still needs an in-editor test pass for
  actual behavior confirmation every time.
- Read `PROJECT_SUMMARY.md` and relevant `docs/systems/*/README.md` first
  before touching source, to keep credit usage down. Reference
  `architecture.json` for shape/signals/API before opening real source
  files.
- Any handover write must go to **this one file only** — `HANDOVER.md`
  (canonical case). Do not create a second lowercase copy.
- **Commit and push BEFORE reporting a feature done** — don't let a session
  end (credits or otherwise) with finished code sitting uncommitted; that's
  exactly what caused the "features missing" false alarm this session.

## Prior work this arc (closed out, kept brief — see docs/systems/water/README.md and docs/systems/structure/README.md for full technical detail on any of these)
- **Corner-pillar clipping / pipe-deconstruct-mode pass:** `PillarRegistry.register_single()` additive fix for the 4 pregen corner pillars; pipe segment deconstruct mode (hover/highlight/refund, mirrors wire deconstruct, reuses `WaterManager.delete_and_refund_edge()`).
- **Wall-locked routing notch/step-skip investigation (3 rounds):** `WallPerimeterRegistry` adjacency rewrite (cell-grid topology instead of raw Euclidean distance) to stop a false shortcut edge across notch/step boundaries; a sign-bug fix in the diagonal-corner adjacency formula (`cell_a + dir_a - dir_b`, not `+ dir_b`); a wrong-Manhattan-corner-choice fix in `_trace_wall_locked_path()`'s wall-to-wall chaining step. **Status: implemented and pushed, but never got an explicit final "confirmed working" from Brannon in this session's context — verify this is still solid before assuming it, especially if any new pillar/notch-routing report comes in.**
- **Water pipe routing (earlier arc, confirmed fixed):** wall-hugging clip fix, diagonal-detour fixes (2 rounds), backward-jog entry-leg fix — see `docs/systems/water/README.md`'s "Wall-locked pipe routing — three follow-up fixes" section.

## NEXT UP (unchanged, still pending — see `PROJECT_SUMMARY.md` §1 roadmap): Save/Load System Overhaul
Expand the existing `SaveManager` field-registry (phase-ordered: dug chunks
→ placed objects+extra state → player wires → water pipes → player
position/cash/clock) to cover:
- Bunker expansions (dug/cleared cells, current bunker footprint)
- Exact power setup: wiring graph, zones (incl. player rename/recolor),
  batteries, generators, breakers (tripped/upgraded state)
- Water system: pipe network graph, hookups, dispensers, sinks, water
  quality/flow state — **including the known purifier save gap**:
  `WaterManager.get_pipe_network_for_save()` only persists `"corner"`/
  `"pipe_joint"` roled nodes today; a `"purifier"` node (and both edges
  touching it) is silently dropped by save/load. Close this as part of the
  save/load pass. **Also add (Jul 2026, Purifier Filter plan):**
  `WaterPurifier.filter_quality` (float) and `PurifierFilterItem`'s
  `is_used`/`filter_quality` fields — same gap category, flagged not
  solved when the filter system shipped, per that plan's own §5.

**Before starting that session, read (in order):** `AI_CONTEXT.md` →
`PROJECT_SUMMARY.md` → `docs/systems/world-core/README.md` (existing
`SaveManager` pattern) → `docs/systems/power/README.md` Persistence section
→ `docs/systems/water/README.md` Persistence + Purification & Quality
sections. Ask Brannon to confirm scope before starting.
