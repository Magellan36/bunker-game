# Plan: Farming Shop Seed Bugfix + Documentation Catch-Up

**Owner of this plan:** UI Claude instance (HUD/menus/Build Mode placement)
**Scope:** `scripts/ui/build/BuildModeHUD.gd` (one data fix), plus
`docs/systems/ui/README.md`, `HANDOVER.md`, and
`docs/systems/farming/README.md` (documentation only).

---

## 1. Root cause — found it, and it's isolated

**Not a menu-size/scroll bug.** I traced the actual purchase path:
`BuildModeHUD.gd`'s `FARMING_SHOP_ITEMS["Seeds"]` array (what builds the
buttons you click) assigns each seed a `tile_id`, which gets passed to
`FarmingShopHelper.spawn_purchased_item(item_id)` — that function looks
`item_id` up in `FarmingShopHelper.SHOP_ITEM_INFO` (the actual authoritative
name→type mapping) and spawns whatever THAT says, ignoring the button's own
label entirely. **`SHOP_ITEM_INFO` itself is correct** — I read it fully,
every id 2-13 maps to the right species, no bugs there.

The bug is a single **copy-paste typo** in `FARMING_SHOP_ITEMS["Seeds"]`:
"Carrot Seeds" and "Chili Pepper Seeds" were both given `tile_id: 6`
instead of Chili Pepper getting `7`. That one duplicate shifts every seed
listed below it in the array back by one id — each subsequent button
ended up carrying the PREVIOUS seed's correct id:

| Button label | Its (wrong) tile_id | What tile_id actually resolves to |
|---|---|---|
| Carrot Seeds | 6 | Carrot ✅ (correct — first half of the list, unaffected) |
| Chili Pepper Seeds | 6 | Carrot ❌ (duplicate) |
| Bell Pepper Seeds | 7 | Chili Pepper ❌ |
| Garlic Seeds | 8 | Bell Pepper ❌ *(matches what you saw: garlic → bell pepper)* |
| Potato Seeds | 9 | Garlic ❌ |
| Blueberry Seeds | 10 | Potato ❌ |
| Corn Seeds | 11 | Blueberry ❌ *(matches what you saw: corn → blueberry)* |
| Pumpkin Seeds | 12 | Corn ❌ |
| *(nothing)* | *(13 never used)* | Pumpkin — orphaned, no button ever produces it |

This matches both examples you gave exactly, which is how I confirmed it
rather than just guessing.

**Checked for the same bug elsewhere, per your "may be an issue for other
systems" note — didn't find it anywhere else.** I read every other category
in both `FARMING_SHOP_ITEMS` (Soil, Resources, Miscellaneous) and the
entire separate `CATEGORIES` dict (Structure, Furniture, Lighting, Power,
Water, Farming, Cooking — the Construct Menu's own tile list) checking for
duplicate ids within each list. Every one of them is clean — Seeds is the
only place this typo happened.

**Why this is worth a follow-up note, not just a patch:** the farming
docs' own "add a new plant species" checklist (step 2 and 3) requires
manually keeping two separate lists — `FarmingShopHelper.SHOP_ITEM_INFO`
and `BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]` — in sync by hand, entry by
entry. That's exactly the kind of duplication that produces this class of
bug, and it'll happen again the next time someone adds or reorders a seed.
I'm not proposing a structural fix in this pass (that's a bigger,
separate refactor — e.g. generating the submenu list's ids from
`SHOP_ITEM_INFO` instead of hand-duplicating them), just flagging it in
the docs below so it's a known risk, not a surprise next time.

---

## 2. Fix `scripts/ui/build/BuildModeHUD.gd`

Find this exact block:

```gdscript
"Seeds": [
		{ "tile_id": 2, "name": "Tomato Seeds", "price": 25 },
		{ "tile_id": 3, "name": "Onion Seeds",  "price": 25 },
		{ "tile_id": 4,  "name": "Basil Seeds",        "price": 25 },
		{ "tile_id": 5,  "name": "Strawberry Seeds",   "price": 25 },
		{ "tile_id": 6,  "name": "Carrot Seeds",       "price": 25 },
		{ "tile_id": 6,  "name": "Chili Pepper Seeds", "price": 25 },
		{ "tile_id": 7,  "name": "Bell Pepper Seeds",  "price": 25 },
		{ "tile_id": 8,  "name": "Garlic Seeds",       "price": 25 },
		{ "tile_id": 9,  "name": "Potato Seeds",       "price": 25 },
		{ "tile_id": 10, "name": "Blueberry Seeds",    "price": 25 },
		{ "tile_id": 11, "name": "Corn Seeds",         "price": 25 },
		{ "tile_id": 12, "name": "Pumpkin Seeds",      "price": 25 },
	],
```

Replace it with exactly this (only the `tile_id` column changes, from
Chili Pepper onward — every `name`/`price` stays exactly as it was):

```gdscript
"Seeds": [
		{ "tile_id": 2, "name": "Tomato Seeds", "price": 25 },
		{ "tile_id": 3, "name": "Onion Seeds",  "price": 25 },
		{ "tile_id": 4,  "name": "Basil Seeds",        "price": 25 },
		{ "tile_id": 5,  "name": "Strawberry Seeds",   "price": 25 },
		{ "tile_id": 6,  "name": "Carrot Seeds",       "price": 25 },
		{ "tile_id": 7,  "name": "Chili Pepper Seeds", "price": 25 },   ## Aug 2026 fix — was 6 (duplicate of Carrot), cascaded every id below down by one
		{ "tile_id": 8,  "name": "Bell Pepper Seeds",  "price": 25 },   ## Aug 2026 fix — was 7
		{ "tile_id": 9,  "name": "Garlic Seeds",       "price": 25 },   ## Aug 2026 fix — was 8
		{ "tile_id": 10, "name": "Potato Seeds",       "price": 25 },   ## Aug 2026 fix — was 9
		{ "tile_id": 11, "name": "Blueberry Seeds",    "price": 25 },   ## Aug 2026 fix — was 10
		{ "tile_id": 12, "name": "Corn Seeds",         "price": 25 },   ## Aug 2026 fix — was 11
		{ "tile_id": 13, "name": "Pumpkin Seeds",      "price": 25 },   ## Aug 2026 fix — was 12 (13 was never used by anything before this fix)
	],
```

**Nothing else needs to change** — `PREVIEW_SOURCES` (the preview-render
lookup) already maps every id 2-13 generically to `SeedItem.gd`, so it
doesn't care which specific species owns which id; and
`FarmingShopHelper.SHOP_ITEM_INFO` was already correct and untouched.

---

## 3. Documentation updates

### Step 3.1 — `docs/systems/ui/README.md`

**Update the "Files by subfolder" table** — it's missing the `water/` and
`farming/` subfolders entirely (pre-existing gap, not something this pass
caused, but worth closing while catching everything else up), and a few
row line-counts/contents are stale after this whole arc of work. Find this
exact block:

```
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
```

Replace it with exactly this:

```
## Files by subfolder
| Subfolder | Files | Role |
|---|---|---|
| `power/` | `PowerTerminalUI.gd` (~1180), `PowerPriorityUI.gd` (~500), `GeneratorInspectUI.gd` (~440), `ZoneCustomizeUI.gd` (~225) | Power device panels — see `docs/systems/power/README.md` for what they read/write |
| `water/` | `WaterDispenserUI.gd` (~520), `WaterInfoUI.gd` (~625) | Water device panels — see `docs/systems/water/README.md` for what they read/write. Both fully on the shared `UIKit` palette as of the Jul 2026 "Power + Water UI Unification" pass — see that section below |
| `farming/` | `FarmingTrayUI.gd` (~440 — handles both the 1x1 and 2x1 tray sizes; panel height grows/shrinks with 0/1/2 plant slots), `PlantInfoUI.gd` | Farming tray panel (Jul 2026 "Rounded Corners" pass joined it onto `UIKit.Domain.FARMING`, green stripe) |
| `inventory/` | `InventoryHUD.gd` (~445 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `ShelfUI.gd` (~475), `BasketUI.gd` (~470) | Slot HUD, inventory state, shelf storage panel, basket contents panel |
| `hud/` | `HUD.gd` (~290), `NeedsGauge.gd` (~130 — 3-ring concentric stat gauge, replaces old `StatusBars.gd`/`CircleFill.gd`), `StatusEffectIcon.gd` (~70), `StatusEffectsContainer.gd` (~85), `InteractPrompt.gd` (~107 — world-space prompt panel; `Panel/Label` is a BBCode-enabled `RichTextLabel` so items like `WaterBottle` can colour part of their prompt text) | Always-on needs gauge (health/stamina/food/water/sleep), status-effect badge skeleton, interact prompt |
| `menus/` | `PauseMenuUI.gd` (~330 — rewritten onto `UIKit` menu builders, Jul 2026), `GraphicsSettingsPanel.gd` (~430 — same rewrite, also fixed a long-standing off-center bug, see below), `SleepOverlay.gd` (~145), `AdminMenu.gd` (~430 — rewritten with collapsible sections + a real `ScrollContainer`, Jul 2026, see below) | ESC pause menu, graphics settings, sleep fade, admin cheats |
| `build/` | `BuildModeHUD.gd` (~1010) | Build-mode toolbar/construct menu/undo/dig-confirm UI. Farming shop's `FARMING_SHOP_ITEMS["Seeds"]` had a duplicate-`tile_id` bug fixed Aug 2026 — see "Farming Shop Seed tile_id Bugfix" below |
| `debug/` | `DebugOverlay.gd` (~305) | F-key debug readouts |
| `common/` | `UIFade.gd` (~30), `UIKit.gd` (~530 — grew substantially across the Jul 2026 "UI Overhaul" arc: menu builders, rounded corners, domain stripes, the shared close-icon, a 4th `FARMING` domain) | Shared fade-in helper + shared theme/drawing kit (see "UIKit shared kit" below) — put any future cross-panel UI utility here |
| `notifications/` | `NotificationManager.gd` (~175) | Central toast/notification system (see "NotificationManager" below) |
```

**Update the UIKit line in "Public API"** — it's missing everything added
since the "rugged" pass. Find this exact block:

```
- `UIKit` (static, `scripts/ui/common/UIKit.gd`): `font()`, `theme_for(domain)`,
  `draw_backdrop(canvas, vp_size, alpha)`, `draw_panel(canvas, rect, theme, border_width)`,
  `draw_close_button(canvas, panel_rect, theme)`, `draw_bar(canvas, rect, fill_pct, theme, ...)`,
  `draw_header(canvas, pos, text, theme, ...)`, `draw_shadowed_text(canvas, pos, text, size, color)`,
  `button_stylebox(theme, enabled, hover)`, `settings_controls_theme()`,
  `draw_rugged_arc(...)`, `draw_rugged_circle(...)`.
```

Replace it with exactly this:

```
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
```

**Add new sections** documenting everything from this arc that isn't
covered yet. Find this exact line (the start of the "Extension points"
section, near the end of the file):

```
## Extension points
```

Insert the following **immediately before** that line (pure insertion —
does not modify "Extension points" or anything after it):

```
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
```

### Step 3.2 — `docs/systems/farming/README.md`

Find this exact block:

```
3. Mirror that same entry into `BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]`
   so it shows up in the submenu list.
4. That's it — no changes needed to `FarmPlant.gd`, `FarmingTray.gd`, or
   `FarmingTrayUI.gd`; every one of those is already generic across
   `plant_type`.
```

Replace it with exactly this:

```
3. Mirror that same entry into `BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]`
   so it shows up in the submenu list. **Double-check the `tile_id` you
   type here against the `item_id` you just used in step 2 — these two
   lists are kept in sync by hand, and a copy-paste slip here (e.g.
   reusing the previous entry's id) silently shifts every seed listed
   below it onto the wrong species.** This exact bug happened once
   already (Aug 2026, "Carrot"/"Chili Pepper" both got `tile_id: 6`,
   cascading through the rest of the list) — see
   `docs/systems/ui/README.md`'s "Farming Shop Seed tile_id Bugfix" for
   the full trace. Worth hardening this in a future pass (e.g. generating
   `FARMING_SHOP_ITEMS["Seeds"]`'s ids from `SHOP_ITEM_INFO` instead of
   hand-duplicating them) rather than relying on manual care indefinitely.
4. That's it — no changes needed to `FarmPlant.gd`, `FarmingTray.gd`, or
   `FarmingTrayUI.gd`; every one of those is already generic across
   `plant_type`.
```

### Step 3.3 — `HANDOVER.md`

This file is shared across every parallel Claude thread on this project
(UI, NPC, Player, etc.) — whoever finishes a big chunk of work writes the
current top section. The existing content (a Player/NPC "Unified Item
Transfer Function" session) is **not from this thread** and should not be
deleted — insert the new section above it instead of replacing the file,
so nothing gets lost for whichever thread needs that context next.

Find this exact line (the very first line of the file):

```
# Handover — Unified Item Transfer Function for Give AND Snatch (Aug 2026)
```

Insert the following **immediately before** that line:

```
# Handover — UI Overhaul Arc: Menu Unification, Rounded Corners, Admin Menu Rework, Bugfixes (Jul-Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode placement).

## What changed across this arc
1. **Pause Menu + Graphics Settings Unification** — both rewritten onto
   new shared `UIKit` menu-builder helpers; fixed `GraphicsSettingsPanel`'s
   real off-center bug (centered itself before its content was added, so
   the baked offset never matched its final size); fixed a corrupted-bytes
   issue isolated to `PauseMenuUI.gd`.
2. **Power + Water UI Unification** — `WATER`/`POWER` domains collapsed
   onto one identical palette, differing only in a new `theme.accent` used
   for a top stripe; brought `PowerTerminalUI` in line with the other 3
   power panels it didn't match before.
3. **Rounded Corners + Stripe Recolor + Farming Domain + Top Padding** —
   one shared corner radius everywhere via a new `UIKit.draw_rounded_rect()`;
   power's stripe green→yellow; new `Domain.FARMING` (green) for
   `FarmingTrayUI`; a uniform +6px top-padding pass across every panel.
4. **F7 Admin Menu rework** — was rendering ~1,250px tall (24 rows across
   7 sections, mostly NPC rows folded in from the deleted F10 menu); now a
   fixed height with collapsible sections + a real `ScrollContainer`
   (native mouse-wheel + scrollbar).
5. **Shared close-button icon** — one new icon asset
   (`assets/icons/close_x.png`) replacing 2 different hand-drawn × forms
   spread across 7 files, centralized behind `UIKit.draw_close_icon()`.
6. **InventoryHUD preview fixes** — rotation now matches
   `BuildModeHUD`'s 45°/45° resting pose, 3x camera zoom, and a real fix
   for a "choppy translucent background" bug (6 overlapping alpha shapes
   double-blending at their seams, replaced with one unified
   `UIKit.draw_rounded_rect()` call — same technique used throughout this
   whole arc).
7. **Farming Shop seed bugfix** — `BuildModeHUD.FARMING_SHOP_ITEMS["Seeds"]`
   had a duplicate `tile_id` (copy-paste typo) that shifted several seeds
   onto the wrong species when purchased (e.g. "Corn Seeds" spawned
   Blueberry). Root-caused via `FarmingShopHelper.SHOP_ITEM_INFO` (the
   actual authoritative mapping, which was correct) and fixed the display
   list to match it.

## Files Modified (representative, not exhaustive — see
`docs/systems/ui/README.md`'s per-pass sections above for full detail)
`UIKit.gd`, `PauseMenuUI.gd`, `GraphicsSettingsPanel.gd`,
`PowerTerminalUI.gd`, `PowerPriorityUI.gd`, `GeneratorInspectUI.gd`,
`ZoneCustomizeUI.gd`, `WaterInfoUI.gd`, `WaterDispenserUI.gd`,
`FarmingTrayUI.gd`, `AdminMenu.gd`, `InventoryHUD.gd`,
`BuildModeHUD.gd` (one data fix only).

## Files Created
`assets/icons/close_x.png`

## Next Up
- The power/water/farming palette merge and rounded-corner/stripe system
  hasn't touched `ShelfUI.gd`/`BasketUI.gd` (still their own look, and
  ~17 of 18 functions duplicated between the two files) or
  `BuildModeHUD.gd`'s own toolbar/construct-menu chrome — logical next
  candidates for this same treatment if requested.
- `FARMING_SHOP_ITEMS["Seeds"]`'s manual two-list sync with
  `FarmingShopHelper.SHOP_ITEM_INFO` is flagged as fragile (see
  `docs/systems/farming/README.md`) but not yet hardened.

---

```

(The trailing `---` above separates this new section from the existing
Player/NPC content, which continues immediately after it unchanged.)

---

## 4. Verification checklist

1. Open the Farming shop, buy each seed in the Seeds category one at a
   time, confirm the item that spawns and lands in your inventory matches
   the button you clicked — especially Chili Pepper, Bell Pepper, Garlic,
   Potato, Blueberry, Corn, and Pumpkin (everything from Chili Pepper
   onward was wrong before this fix).
2. Confirm Tomato, Onion, Basil, Strawberry, and Carrot still work
   correctly (they were already correct — this fix shouldn't touch their
   behavior at all).
3. Confirm no console errors referencing `BuildModeHUD` or
   `FarmingShopHelper`.
4. Read through the new `docs/systems/ui/README.md` sections and confirm
   nothing reads as contradicting an earlier section (e.g. no leftover
   references implying `GraphicsSettingsPanel` is still off-center).
5. Confirm `HANDOVER.md` still contains the full original Player/NPC
   "Unified Item Transfer Function" content below the new section — this
   was an insertion, not a replacement.
