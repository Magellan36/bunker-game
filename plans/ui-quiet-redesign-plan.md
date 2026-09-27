# Quiet UI redesign — multi-pass plan (all in-game UI)

Approved direction: Brannon, 2026-09-26 — "take that same degree of polish
… across the entire game … keep that design." The design itself is fixed in
`docs/ui/QUIET_DESIGN_SYSTEM.md`; the per-surface baseline is
`docs/ui/QUIET_UI_AUDIT.md`. This file is the schedule and the memory.

## Ground rules for every pass (so the design is never forgotten)

1. **Start** by reading `QUIET_DESIGN_SYSTEM.md` in full, this file's pass
   section, the audit rows it covers, and each screen's prior
   `docs/ui/*.md` / system README for behaviour contracts.
2. **Visual rebuild, behaviour kept.** Public APIs, signals, data flow,
   lifecycles, docking/walk-away rules and the "deliberately immediate" list
   stay unless the pass lists an approved change.
3. **Shared first.** New look lives in `QuietControls` / `scripts/ui/common/`.
   A screen that needs something new adds it there and documents it in the
   design system. No per-screen colours or one-off styleboxes.
4. **Prove it.** Register the screen in `tools/tests/quiet_ui_lint.gd`, keep
   or update its smoke test, run the existing suite (`godot_check.sh` steps,
   relevant `*_smoke.gd`), and review **live captures** at 720p, 1080p,
   1440p and 21:9 (`tools/ui_capture/`).
5. **Review gate.** Each pass ends with before/after captures for Brannon.
   Nothing is committed unless he asks.
6. **Close the loop.** Tick the pass checklist below, update the audit row,
   the icon ledger, and the screen's doc. Carry any new pattern back into the
   design system in the same pass.

## Pass overview (condensed to five passes — Brannon, 2026-09-26)

Order: foundations and shared pieces → full-screen moments → always-visible
HUD and side panels → large workspaces → build mode and cleanup. Each pass is
bigger than before, so each is split into **parts** that can be reviewed
separately inside the pass; the review gate is still at the end of the pass.

| Pass | Scope | Size | Risk | Decisions applied |
|---|---|---|---|---|
| 1 | **Foundations + shared surfaces** — component kit, extracted focus/row controller, segmented control, footer, global scrollbar/tooltip/keycap quieting, lint baseline; confirm dialog; notification toasts moved top-right | L | Medium | D2 |
| 2 | **Menus + full-screen moments** — pause (+ save/load, log), loading, sleep, game over, **character creation full redesign** | L | Low–Medium | D3 |
| 3 | **HUD + docked panels** — needs gauge, clock/cash, hotbar, status effects, prompts; device inspectors; storage | XL | **High** | D1 |
| 4 | **Workspaces** — power terminal + zones, status, NPC profile, research station | XL | Medium | D5 |
| 5 | **Build mode + shop, dev tools, cleanup** — build HUD/toolbar/catalog/cursor, supply shop, admin/debug skin, dead-code removal, release gates | XL | **High** | D4 |

## Pass details

### Pass 1 — Foundations + shared surfaces
#### Part A — Foundations
Goal: every later pass is assembly, not invention.
- `QuietControls`: add **primary action**, **destructive action** (with inline
  arm helper), **meter** (quiet `BunkerSmoothProgressBar` styling),
  **stat block**, **status line** (dot + word), **tile** (preview card),
  **inspector header**, **dialog shell**, **toast style**.
- Extract from `GraphicsSettingsPanel` into `common/`:
  `QuietSegmented.gd` (segmented/tabs with sliding underline, LB/RB via
  `ui_tab`), `QuietFocusController.gd` (row metas → FocusRail target, hover =
  focus, reveal, hint line + cost tag, Saved pulse, row click), and
  `QuietFooter.gd` (hint · Saved · key hints). Settings becomes their first
  consumer; its tests must stay green.
- Global quieting that is safe everywhere: default scrollbar skin in
  `ControllerUINavigation`/`BunkerControlTheme` → `Q.scrollbar` look; tooltip
  panel → quiet popup; key-hint keycaps → hairline edge.
- Capture tooling already lives in `tools/ui_capture/` (done with the
  audit); extend `capture_world.gd` as passes need new UI states.
- Lint `--baseline` mode that prints per-screen debt for unmigrated screens.
- Done when: settings unchanged visually, all tests green, baseline recorded.

#### Part B — Confirm dialog and toasts
- **Confirm dialog** (`ConfirmDialogUI.gd`): quiet dialog, text Cancel +
  primary/destructive, no icon well. Keep `open(...)` signature, stacking
  layers, B-cancel behaviour.
- **Toasts** (`NotificationManager.gd`, `_draw` → native): eyebrow domain +
  one line, severity only as coloured text/dot for warning/critical, no icon
  box/stripe; stack of 3 with quiet overflow count. **Never overlap an open
  surface footer** (D2).
- Contracts: NOTIFICATION_PAUSE_OVERHAUL (queue, history, severities).
- D2 applied: toasts live **top-right under the cash readout**, right-aligned
  to the same 24 px edge; they step down below any docked inspector's header
  area and never cover a workspace footer, the SHOP button or the clock.

### Pass 2 — Menus + full-screen moments
#### Part A — Pause, loading, sleep, game over
- **Pause** becomes the Settings sibling: rail (brand eyebrow, "Paused", text
  actions Continue/Save/Load/Settings, Exit as destructive two-step), log on
  the right with text filter tabs (`QuietSegmented`) and hairline rows. Save/
  load slots as rows with captions ("Day 3 · 14:20 · 2 hours ago" like the
  main menu). Add "Exit to Main Menu" only if the MainWorld teardown work is
  approved separately.
- **Loading**: main-menu language (left-weighted wordmark, quiet indicator,
  tip as a single MUTED line). Keep threaded load + `startup_ready` handoff +
  pending save restore.
- **Sleep / game over**: curtain + typography. Fix GameOver loading slot 0.

#### Part B — Character creation (full redesign, D3)
- Main-menu language, Iosevka font, "BUNKER GAME", remove AI placeholder
  icons (text + selection underline), fix clipped Randomise. Keep preview
  viewport, gender data flow, loading handoff.
- D3: treat it as a new screen in the main-menu language, not a reskin —
  survivor presented as a lit subject in the same surface-feed mood, choices
  as a quiet text column with the gliding rail, live preview controls
  explained by the footer, curtain transitions to and from the menu.

### Pass 3 — HUD + docked panels
#### Part A — HUD
- **Needs gauge** (D1), **clock/cash** (text on shadow, no plates; day as
  eyebrow), **hotbar** (flat slots, number in HEADING, selected = ACCENT
  underline + name reveal), **status effects** (quiet rings or text chips per
  D1), **interaction prompts** (keycap + text, no shell; fix duplicate
  research prompt), hold/job glyphs restyled to ACCENT.
- Layout rule: HUD yields to open panels/rails (fixes gauge vs build catalog).
- `_draw` → native where practical so the lint can see it.
- Contracts: NEEDS_GAUGE_REDESIGN, HUD_TIME_CASH_POLISH,
  INVENTORY_HUD_REDESIGN, HUD_STATUS_ICON_POLISH, INTERACTION_PROMPT_POLISH.
- D1 applied: keep the five-ring compass; arcs neutral (ivory/brass) at
  rest, WARNING/RED only when a need is low; glyphs are placeholders per the
  icon ledger.

#### Part B — Docked device inspectors
- First restyle the shared shell (`DeviceInspectPanel.tscn`,
  `BunkerDeviceInspector.gd`, `BunkerInspectorWidgets.gd`,
  `BunkerPriorityControl.gd`): inspector header, groups + rows, quiet meters,
  status lines, one primary action. Then each device adapter
  (generator's dedicated scene last).
- Keep: 500 px / 24 px right dock, heights, no backdrop, movement allowed,
  walk-away close, 10 Hz refresh, no-signal refresh setters, all device
  thresholds and wording rules (ui-redesign-device-pass).

#### Part C — Storage
- Docked 440 px rail; item **tiles** with 3D previews (keep
  `ItemPreviewKit` pooling), quiet capacity meter, actions as text/primary.
- Contracts: BUILD_SHOP_STORAGE_REHAUL (storage section), SHARED_UTILITY.

### Pass 4 — Workspaces
#### Part A — Power terminal + zone customize
- Workspace archetype with text tabs (Overview, Devices, Load order, Zone
  network), stat blocks instead of icon cards, quiet load graph (ACCENT line,
  hairline grid, MUTED axes), priority as a segmented/value control, grid
  state as a status line.
- Contracts: POWER_TERMINAL_REDESIGN, ZONE_CUSTOMIZATION_REDESIGN.

#### Part B — Status workspace
- Text tabs; overview as stat blocks + quiet meters; health conditions as
  rows with status lines; NPC list as rows with portrait tiles; inventory
  tiles.
- Contracts: STATUS_SCREEN_REDESIGN, medical system README.

#### Part C — NPC profile / talk
- Keep persistent left portrait column; quiet tabs; needs as quiet meters
  (colour only when low); relationship meter restyled (single ACCENT marker
  on a hairline scale); traits as text; "Talk" as the single primary action.
- NPC overhead `Label3D` text restyled to the HUD rules.
- Contracts: NPC_MENU_REDESIGN, npc README.

#### Part D — Research station
- Materials as stat rows; pathway graph with quiet nodes (D5); detail pane
  with groups/rows and one primary action; quiet scrollbars.
- Contracts: RESEARCH_STATION_REDESIGN.
- D5 applied: text-only graph nodes; category as an eyebrow.

### Pass 5 — Build mode + shop, dev tools, cleanup
#### Part A — Build mode + shop
- Split the 2k-line `BuildModeHUD.gd` presentation into native components as
  part of the port (no gameplay changes). Remove the full-screen blue frame
  (replace with a subtle edge vignette + "BUILD" eyebrow). Toolbar as a
  segmented control (D4). Catalog as docked rail with category text tabs and
  preview tiles; price in MUTED, unaffordable in RED text. Fix blank
  Half/Quarter-wall previews.
- Shop: workspace with department tabs, tiles, cart as rows; arithmetic stays
  immediate.
- Contracts: BUILD_SHOP_STORAGE_REHAUL, CONSISTENCY_PASS (build exclusivity,
  cursor ownership), build README.
- D4 applied: toolbar is text + a few small symbols; any AI-authored symbol
  is a placeholder, logged in the icon ledger and the release-blocking
  manifest.

#### Part B — Dev tools
- Admin (F7) and debug overlay: quiet skin via shared helpers only; no
  polish investment. Never player-facing.

#### Part C — Cleanup and release gates
- Delete `PowerTerminalUI.gd`, `ZoneCustomizeUI.gd`, `ResearchStationUI.gd`
  (after confirming zero references). Retire unused `UIKit` and
  `BunkerRedesignTheme` pieces. Remove replaced AI placeholders and update the
  manifest. All live screens registered in the lint; full suite green;
  `check_ui_placeholders.py --release` status reported.

## Decisions (answered by Brannon, 2026-09-26 — binding)

| ID | Question | Decision |
|---|---|---|
| D1 | Needs gauge form | **Keep the five-ring compass**, calmer palette: neutral arcs, colour only when a need is low. No mockup round needed. |
| D2 | Toast position | **Top-right, under the cash readout.** Must look good and never clash with other UI (cash/clock, docked inspectors on the right, workspaces, build SHOP button). |
| D3 | Reopen character creation | **Yes — full redesign expected** ("I bet you can do a LOT better"). Not just a reskin. |
| D4 | Build toolbar | **Text + a few small symbols.** AI-authored symbols are acceptable as placeholders only; each is logged in the icon ledger and in a release-blocking manifest for replacement. |
| D5 | Research graph nodes | **Text only**; category as an eyebrow. |

## Icon ledger (keep current every pass)

| Icon source | Where used now | Plan |
|---|---|---|
| `BunkerSymbolTexture.gd` (code-drawn) | Inspectors, terminal, status, NPC, research, pause, loading, HUD (no longer: toasts, confirm dialog — Pass 1) | Removed per pass unless §8 allows; survivors (e.g. HUD needs glyphs, build toolbar symbols — D1/D4) listed here as placeholders |
| `assets/ui/placeholders/redesign/*_AI_PLACEHOLDER.svg` (tracked) | Nothing (all 12 retired 2026-09-27; manifest empty) | Done — add new ones only under §8 rules |
| `assets/icons/*.png|svg` (close_x, clock, materials, needs) | Legacy UIKit only (HUD clock pictogram removed in Pass 3) | 5C: remove with UIKit leftovers; confirm provenance of any survivor |
| `BunkerSymbolTexture` needs glyphs (health, food, stamina, hydration, sleep) | HUD needs gauge (D1) | **Placeholder** (AI-authored geometry) — replace with human-made glyphs before release |
| `BunkerSymbolTexture` status glyphs (bleeding, fracture, burn, infection, bandage, medical, temperature, sleep, warning, status) | HUD status badges | **Placeholder** — replace before release |
| `assets/ui/prompts/*.png` (E/F/G, 0–9, Xbox A/B/X/Y/LB/RB key glyphs, ~175-byte PNGs, added 2026-08-24) | Interaction prompts | **Provenance unconfirmed** — Brannon to confirm source/licence or replace (text keycaps are a drop-in fallback) |
| Quiet UI (main menu, settings) | None; glyphs are font characters (→ ✓ ←) | — |
| Build toolbar glyphs `+ ✥ ⧉ × ↶ ⌁ ≈` (D4) | Build tool strip | Characters of the shipped Iosevka Charon font — no artwork, nothing to replace |
| `assets/icons/*` (12 files: arrows, close_x, clock, materials, plus, night-sleep/steak/water-drop SVGs) | **Nothing** (no reference after Pass 3–5) | Brannon: confirm provenance or delete before release — unreferenced files still export |

## Progress checklist

- [x] Main menu (reference)
- [x] Graphics settings (reference)
- [x] Audit + design system + lint (2026-09-26)
- [x] Decisions D1–D5 answered (2026-09-26)
- [x] Pass 1 — Foundations + shared surfaces (2026-09-26)
  - [x] A. Foundations — QuietControls kit (primary/destructive + confirm_twice, meter, stat, status line, tile, inspector header, dialog/toast boxes, focus underline, avoid_toasts); QuietSegmented, QuietFooter, QuietFocusController extracted (Settings is first consumer, unchanged); global quiet scrollbars/tooltips/keycaps; lint `--baseline`
  - [x] B. Confirm dialog (quiet, fits content, danger-tinted confirm) + toasts (native, top-right under cash, avoid docked panels/SHOP, held behind modal workspaces, critical breaks through)
- [x] Pass 2 — Menus + full-screen moments (2026-09-27)
  - [x] A. Pause (rail + Log/slot workspace, never-lose-progress exit), loading (wordmark column, retry, cached-world fallback), sleep (centred readout), game over (main-menu language, fixed slot-0 load, `WorldManager.leave_world`)
  - [x] B. Character creation — new `SurvivorScreen` (text left / lit survivor right, key light ramps on, cross-fade swaps, idle sway, reserved caption line); strict lint; all 12 AI placeholder SVGs retired (release gate green)
- [x] Pass 3 — HUD + docked panels (2026-09-27)
  - [x] A. HUD — shadowed clock/cash (no plates, 24 px margins), D1 gauge (calm tints → WARNING/RED when low), quiet hotbar + item meters, quiet status badges, prompt scrim + quiet state words, hold/job glyphs in ACCENT, HUD yields in build mode; **duplicate research prompt fixed** (chute defers to the station)
  - [x] B. Device inspectors — shared `W.quiet_shell` + widget vocabulary (status lines, rows, 3 px meters, switch rows, priority row, one primary), generator scene migrated; device-contract harness repaired (2869 checks green)
  - [x] C. Storage — quiet header/tiles/selection line/one primary; trash-bag card quiet
- [x] Pass 4 — Workspaces (2026-09-27)
  - [x] Shared: legacy S/C vocabulary quieted in place + `QuietLegacyStyle`/`QuietLegacyComponents` shims; `Q.secondary_action`, `Q.tab_button`; icon stripping
  - [x] A. Power terminal + zones — status line, text Close/tabs, key-hint footer, TEXT numbers, quiet pills/meters; zone dialog header/footer
  - [x] B. Status — calm need identities, text tabs, status line, key hints; **NPC tab empty state never rendered (signature bug) — fixed**
  - [x] C. NPC profile — calm need bars, status lines, text tabs, key hints
  - [x] D. Research station — D5 text-only nodes with keyline state, text zoom controls, key hints
- [x] Pass 5 — Build mode + shop, dev tools, cleanup (2026-09-27)
  - [x] A. Build mode + shop — pulsing full-screen frame → still edge wash; BUILD eyebrow under the clock (no plate); D4 toolbar = text + Iosevka glyphs (+ ✥ ⧉ × ↶ ⌁ ≈); quiet tiles with MUTED price → RED when unaffordable; text-only categories; shop header/cash/search/rows/cards quieted; **blank Half/Quarter-wall previews fixed** (scaled wall mesh, as placed)
  - [x] B. Dev tools — admin + debug overlay on the quiet palette (text Close, no borders, quiet scrollbar)
  - [x] C. Cleanup — removed `PowerTerminalUI.gd`, `ZoneCustomizeUI.gd`, `ResearchStationUI.gd`, `LoadingBackdropArt.gd` (+ .uid; zero runtime references), 20 dead `UIKit` drawing helpers; placeholder release gate green (0 AI placeholders)
