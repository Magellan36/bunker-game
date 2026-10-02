# Bunker Game — Quiet UI Design System

**Status: governing visual language for every player-facing UI (approved by
Brannon, 2026-09-26).** Established by the main menu and the Graphics Settings
pass. Every redesign pass reads this file first and ends by checking the
Definition of Done at the bottom.

Where this document and an older `docs/ui/*.md` disagree **about looks**, this
document wins. Where an older doc defines **behaviour** (dimensions of docked
inspectors, input ownership, lifecycles, data contracts), that behaviour
stays unless a pass explicitly changes it with approval.

Reference implementations (open these, copy their patterns):

| Surface | Files |
|---|---|
| Full workspace | `scripts/ui/menus/GraphicsSettingsPanel.gd` |
| Hero/menu column | `scripts/ui/main_menu/MainMenuScreen.gd`, `MainMenuItem.gd` |
| Control skin + tokens | `scripts/ui/common/QuietControls.gd` |
| Focus indicator | `scripts/ui/common/FocusRail.gd` |
| Switch | `scripts/ui/common/SwitchGlyph.gd` |
| Scrolling | `scripts/ui/common/SmoothScroll.gd` |
| Row list behaviour (rail, hover, reveal, hint, Saved) | `scripts/ui/common/QuietFocusController.gd` |
| Segmented control / text tabs | `scripts/ui/common/QuietSegmented.gd` |
| Footer (hint · Saved · key hints) | `scripts/ui/common/QuietFooter.gd` |
| Input hook | `ControllerUINavigation._adjust_focused_range()` → `ui_cycle` meta |
| Design lint | `tools/tests/quiet_ui_lint.gd` (register every migrated screen) |

---

## 1. Principles

1. **Dark and quiet.** The bunker is the subject; UI is a calm instrument
   panel laid over it. Near-black charcoal, warm ivory text, worn brass for
   structure, one muted steel-blue for "you are here".
2. **Text first.** Hierarchy comes from type size, weight, letter-spacing and
   brightness. Icons are the exception and must earn their place (§8).
3. **State is brightness, not fill.** Resting things are muted; the current
   thing is ivory. No filled blue buttons, no pills, no glowing outlines.
4. **Hairlines, not boxes.** Group with space, a tracked heading and 1 px
   hairlines. A bordered card is almost always the wrong answer.
5. **One accent, used sparingly.** `ACCENT` marks focus, selection and "on".
   Semantic colours (warning/critical/good) appear only when something
   deviates from normal, and always with words.
6. **Motion explains change.** Things glide to where they are going, ease
   out, and never loop for decoration. Everything obeys reduced motion.
7. **Every input device is first-class.** Mouse hover, keyboard, and
   controller share one focus; Left/Right adjust any value; Esc/B backs out.
8. **Confirm quietly.** Changes apply live and say "✓ Saved"; destructive
   actions ask twice in place.

---

## 2. Tokens

All values live in code; never hand-type a colour in a screen.

### Colour (`QuietControls.gd` + `BunkerDesign.gd`)

| Token | Value | Use | Never |
|---|---|---|---|
| `Q.SURFACE` | `#0d1110` @ 97% | Shell/panel background | Behind text in HUD |
| `Q.POPUP` | `#111615` @ 99% | Dropdowns, tooltips, dialogs | |
| `Q.TEXT` (`BunkerDesign.IVORY`) | `#f2e8cf` | Titles, focused/active text, values | Large bright fills |
| `Q.MUTED` | `#aaa596` | Resting labels/values, body copy | |
| `Q.FAINT` | MUTED @ 45% | Disabled only | Readable information |
| `Q.HEADING` | `#a8946c` | Tracked-caps eyebrows, section headings, cost tags | Body text |
| `Q.HAIRLINE` | brass `#88734e` @ 20% | Row separators, dividers, shell edge (30%) | Thick borders |
| `Q.ACCENT` | `#86a9bf` | Focus rail, selected underline, switch-on, slider fill, "Saved" | Large fills, body text |
| `Q.ACCENT_DIM` | `#2b3b44` | Hovered popup item, primary-action fill | |
| `BunkerDesign.WARNING` | `#f0b861` | Warning **text** + meter fill when warning | Decoration |
| `BunkerDesign.RED` | `#df7669` | Critical text, destructive confirm | Decoration |
| `BunkerDesign.GREEN` | `#75d48a` | Only where "good" must be distinguished from neutral (e.g. health recovering) | "Online/OK" defaults — use MUTED text |
| `BunkerDesign.BLUE` | `#66bfff` | **Main-menu hero rail/arrow only** (approved look) | Anywhere in-game |

Retired for new work: `BunkerDesign.BLUE_DARK` fills, domain stripe colours,
`UIKit` domain themes, per-stat rainbow meter colours.

### Typography — Iosevka Charon (`assets/fonts/`)

| Role | Size @1080p | Weight | Colour | Notes |
|---|---|---|---|---|
| Workspace title | 40 | Regular | TEXT | Rail title ("Settings") |
| Inspector / dialog title | 24–28 | Regular | TEXT | |
| Stat value | 22–28 | Medium | TEXT | Units in MUTED at 60% size |
| Row label | 16 | Regular | TEXT @74% rest → 100% focused | |
| Value / control text | 15 | Regular | MUTED rest → TEXT hover/focus | |
| Body / hint line | 14 | Regular | MUTED | One line; ellipsis, never wrap in footers |
| Eyebrow / section heading | 12 | Regular | HEADING | UPPERCASE, `spacing_glyph = 3` |
| Cost / status tag | 11 | Regular | HEADING | UPPERCASE, spacing 2 |
| Key hint | 11–12 | — | existing `key_hint()` | |

Floors: nothing below **11 px** (12 for anything the player must read at
720p). Hero wordmarks may use Bold with `spacing ≈ 0.15 × size`.

### Space, shape, elevation

- Spacing scale (px @1080p): **2 · 4 · 6 · 8 · 14 · 16 · 22 · 30 · 48**.
  Row height 46. Section gap 30 above a heading, 6 below it. Shell insets
  30 (left) / 28 (top) / 22 (right) / 16 (bottom). Rail/content gap 30.
- Radii: shell **12**, popups/dialog **8**, controls/washes **6**, rows **0**.
- Borders: shell 1 px @ brass 30%; rows 1 px bottom hairline; controls **0**.
- Elevation: shells only — `shadow 36 px, offset (0,10), black 55%`.
- Scrollbars: `Q.scrollbar()` — 6 px grabber inside a 16 px hit area,
  ivory 13% → 26% hover.

### Motion (`UIMotion` + component constants)

| Motion | Value |
|---|---|
| Shell open | fade 0.22 s + rise 16 px, 0.36 s expo-out; content fade 0.28 s, delay 0.07 |
| Shell close | fade `UIMotion.EXIT` (0.10 s); backdrop fades with it |
| Backdrop | 0 → 1 over 0.22 s |
| FocusRail glide | lead response 30, trail 13 (elastic stretch), fade 10 |
| Hover/brightness | exponential response 14, label alpha tween 0.12 s |
| Segment/tab underline | 0.30 s cubic-out, position + width |
| Switch knob | response 16 |
| Wheel / jump scroll | `SmoothScroll` response 14, ≥ 1 px/frame |
| Saved confirmation | in 0.14 s, hold 1.4 s, out 0.6 s |
| View swap inside a column | old: fade 0.12 + slide 26 px; new: fade 0.24 (delay 0.1) + slide from 26 px 0.34 s |

**Deliberately immediate** (from `UI_MOTION_SYSTEM.md`, still binding):
confirmation/destructive decisions, controller focus *ownership*, cash and
shop arithmetic, build placement validity, treatment outcomes, inventory
ownership, power priorities/breaker state, warnings requiring action.
Live meters use `BunkerSmoothProgressBar` (first update snaps, then eases).

**Reduced motion** (`UIMotion.reduced()`): every duration → 0, rails snap,
no rise/slide, no idle animation. Test both modes.

---

## 3. Components

All created through `QuietControls` (preload as `Q`). Add a helper there
rather than restyling inline. If a pass needs a component not listed, add it
to `QuietControls`, document it here, and register a lint rule if it has one.

| Component | Helper | Spec |
|---|---|---|
| Shell | `Q.shell_box(12)` on a `PanelContainer` | SURFACE, brass 30% edge, shadow |
| Eyebrow / section heading | `Q.eyebrow(text)` | 12 px HEADING tracked caps |
| Row | `Q.row_box()` on `PanelContainer` → HBox(label, control) | 46 px, hairline under, label left (expand), control right |
| Nav link / text action | `Q.nav_button(b)` | Flat, MUTED → TEXT, focus wash `TEXT @5%`, 30 px |
| Segmented control / tabs | `Q.segment(b)` + sliding `ColorRect` underline (ACCENT, 2 px, text-width) | See preset row in Settings |
| Value dropdown | `Q.option(o)` | Right-aligned value, no box, `ui_cycle` Left/Right, quiet popup |
| Switch | `Q.switch(t)` | "On/Off" text + `SwitchGlyph`; `ui_cycle` Right=On Left=Off |
| Slider | `Q.slider(s)` | 3 px track, ACCENT fill, 14 px ivory disc; wheel scrolls page |
| Scrollbar | `Q.scrollbar(bar)` | See tokens; sets `shared_scrollbar_skin` |
| Focus indicator | `FocusRail` (require_focus / host-driven) | 2–3 px ACCENT rail + fading wash behind target |
| Hint line + cost tag | Footer `Label`s (see Settings `_show_hint`) | One line, updates on focus |
| Saved confirmation | Footer label "✓  Saved" in ACCENT | After every committed change |
| Key hints | `BunkerUIComponents.key_hint()` | Footer right; auto-swaps keyboard/controller |

**Added in Pass 1A** — helper in brackets; specs fixed here so every pass
builds the same:

| Component | Spec |
|---|---|
| Primary action [`Q.primary_action`] | One per surface. ACCENT_DIM @ 85% fill, radius 6, **no border**, TEXT 15–16 px, height 38–40; hover lighten 6%; focus = rail. |
| Destructive action [`Q.destructive_action` + `Q.confirm_twice`] | Text action in `RED` @ 85%; first press arms ("Press again to …", 3 s) or opens the quiet dialog for irreversible world actions. |
| Meter [`Q.meter` + `Q.set_meter_state`] | 3 px track `TEXT @9%`; fill ACCENT @70%; WARNING/RED fill only in warning/critical state; value right in MUTED; label left 14 px. Eases via `BunkerSmoothProgressBar`. No rainbow per-stat colours. |
| Stat [`Q.stat` + `Q.set_stat`] | Eyebrow label, value 22–28 Medium TEXT, unit MUTED; optional delta line 13 px. |
| Status line [`Q.status_line` + `Q.set_status`] | Dot + word. Nominal: MUTED text, ACCENT dot. Warning/critical: coloured text + dot. Replaces all pills/badges. |
| Group | Eyebrow heading + rows. Replaces bordered cards for information. |
| Tile [`Q.tile`] | Only for items with a 3D preview (build catalog, storage, shop). Flat `TEXT @3%`, radius 8, no border; hover `@6%`; selected = ACCENT underline + TEXT name; focus = rail. |
| Tabs [`QuietSegmented.setup(..., as_tabs=true)`] | Text tabs with the sliding underline; LB/RB cycle (`ui_tab` meta). |
| Dialog [`Q.dialog_box`] | Centered, max 520 wide, `Q.shell_box`, title 22, body 15 MUTED, actions right: text "Cancel" + primary/destructive. |
| Toast [`Q.toast_box`, `NotificationManager`] | 360 px cards **top-right under the cash readout**, newest on top: eyebrow (domain; `● DOMAIN · WARNING/CRITICAL` in amber/red), 15 px line, optional 13 px detail, ×N count. Slide in from the right, glide as the stack changes. No icon box, no stripe. Placement rules in §5. |
| Empty state | One MUTED 14 px sentence. No icon, no box. |
| Inspector header [`Q.inspector_header`] | Eyebrow domain (HEADING) + 24–28 px title + right-aligned text "Close" action with Esc keycap. No X box. |

**Added in Pass 3** — the docked-inspector vocabulary lives in
`BunkerInspectorWidgets.gd` (preload as `W`); every device inspector and the
generator's own scene use it, so a change there restyles the whole family.

| Component | Spec |
|---|---|
| Inspector shell [`W.quiet_shell(view, close)`] | Restyles `DeviceInspectPanel.tscn` / `GeneratorInspectPanel.tscn` in place (node contract unchanged): `Q.shell_box(12)`, Iosevka default font, padding 24, brass eyebrow + 26 px title + text **Close**, hairline dividers, `Q.scrollbar`, a `FocusRail` behind the content (hidden while Close holds focus — Close has its own wash), key hints `ENTER Select · ESC Close` replacing the sentence footer. |
| Group heading [`W.heading`] | 12 px tracked brass caps, 30 px tall and bottom-aligned (section air above, tight below). |
| Reading row [`W.stat`/`W.set_stat`] | Caption left MUTED 15, value right TEXT 15 (`Line/Caption`, `Line/Value`). |
| Status line [`W.status`/`W.set_status`] | 8 px disc + word; legacy tokens map to quiet states (`success`/`blue` = nominal ACCENT dot + MUTED word; `inactive` = FAINT dot; `warning`/`critical` colour both). Zone colours tint the dot only. |
| Meter [`W.meter`/`W.set_meter`] | `Q.meter` 3 px; caption TEXT 15 left, value MUTED right (WARNING/RED when low), 13 px hint. |
| Switch row [`W.switch_row`/`W.set_switch`] | Caption left, `Q.switch` right; press asks the owner, refresh re-syncs with the confirmed value (never invents state). 34 px target. |
| Priority row [`BunkerPriorityControl`] | "Priority" MUTED, then `−  3 · STANDARD  +`; Left/Right on either step nudges the tier (`ui_cycle`). |
| Power action [`W.set_power_button`] | "Power off" / "Power on" — always the surface's one primary. |
| Tile [`BunkerItemCard`] | `Q.tile`; flat preview well, caption MUTED → TEXT when selected/focused, count as plain `×N`, empty = faint dotted ring + "Empty". |

**Added in Pass 4** — workspaces and the legacy vocabulary:

| Component | Spec |
|---|---|
| Secondary action [`Q.secondary_action`] | Every non-primary action: TEXT @4 % wash, no border, radius 6, MUTED → TEXT, focus = ACCENT underline; `danger` = red text. |
| Tab / segment [`Q.tab_button`] | Text only; pressed = TEXT + 2 px ACCENT underline; focus = 1 px ivory @40 % underline (never reads as a second selection); no persistent borders. `C.style_segment` routes here. |
| Legacy style shim [`QuietLegacyStyle.gd`] | Drop-in for `const S := preload(BunkerPanelStyle)` in v1 screens: same names, quiet values (BLUE → ACCENT, BLUE_DARK → ACCENT_DIM, GREEN → sage `#9fb39c`, IVORY/MUTED → quiet text tokens). |
| Legacy components shim [`QuietLegacyComponents.gd`] | Drop-in for `const C := preload(BunkerUIComponents)`: `panel_box()` becomes a quiet group (TEXT @2.8 % wash, no border, radius ≤ 8, same padding); bright fills (luminance > 0.35: meter fills, swatches) are kept; a hero-blue border survives only as a 1 px ACCENT @60 % selection keyline. |
| Legacy helpers (all callers) | `BunkerPanelStyle.button/icon_button/field`, `BunkerUIComponents.shell/header/section_header/divider/icon_well/style_segment/status_style` now draw the quiet language: accent = primary, danger = red text, icons stripped once a button has a caption (icon-only buttons keep a MUTED glyph), header icon wells hidden, "Close" is text. |

Workspace recipe used in Pass 4: brass eyebrow + 28 px title, a status
**line** (`●  GRID ONLINE`, MUTED when nominal) instead of a pill, text
**Close**, text-only tabs, key-hint footer (`Q / R Tabs · ENTER Select · ESC
Close`, controller glyphs swap in), quiet 4 px meters in the calm need
identities, big numbers in TEXT (colour only for faults), research graph
nodes text-only (D5) with a 1 px keyline as the only state signal.

**Tool overlay (archetype E) specifics — Pass 5:** build mode is marked by
a still steel edge wash (`BuildModeHUD.EDGE_ALPHA` 0.09 over 110 px — never a
frame, never pulsing) and a `BUILD MODE` eyebrow + mode line under the clock.
The tool strip is a soft scrim with `Q.tab_button` tools: a small Iosevka
glyph over a 13 px caption, selection = ivory + ACCENT underline. Catalog and
shop tiles are `Q.tile`; prices MUTED, RED only when unaffordable (updated
immediately — arithmetic is never eased).

**HUD (archetype C) specifics — Pass 3:** clock = brass `DAY N` eyebrow over
20 px time; cash 21 px right on the 24 px safe margin; all HUD text carries
`shadow (0,1) black 70% + shadow_outline 6`. Needs gauge (D1): five rings,
calm identity tints (health `#b8746a`, food `#c49a62`, stamina `#93a97f`,
water `#7c9db5`, sleep `#9a8db3`) → WARNING below 25 %, RED below 12 %,
blended over a 4 % band (`NeedsGauge.need_color`). Hotbar: scrim slots, brass
number, selection = lift + wash + ACCENT underline, name reveal as shadowed
text. An occupied slot sits its 3D preview in a soft warm light pool (IVORY
radial falloff, 16 %, 22 % when selected, no edge) so dark items read; the
preview and pool fade in over 0.22 s, and the dotted ring marks empty slots
only. Prompts: scrim (no border), nominal states `● WORD` with a steel dot
and muted word, warnings/faults coloured. The HUD's needs/effects fade out in
build mode (the HUD yields to tool panels).

---

## 4. Layout archetypes

| Archetype | Used by | Rules |
|---|---|---|
| **A. Workspace** | Settings, Pause, Status, Power Terminal, Research, NPC, Shop | Shell ≤ 1240×760 (≤ 1420×820 where an older contract allows), margins 56/42, modal blur backdrop, left rail (brand eyebrow, 40 px title, text sections, Back at bottom) **or** top text tabs, scrolling content with `SmoothScroll`, footer = hint line · Saved · key hints. |
| **B. Docked inspector** | Generator, battery, breaker, priority, water, farm tray, storage, trash bag | Keep approved behaviour: 500 px @1080p (storage 440), right margin 24, no backdrop, player can move, walk-away close, height by content. Quiet shell, inspector header, groups + rows, one primary action at the bottom. |
| **C. HUD** | Needs, clock/cash, hotbar, status effects, prompts, toasts | No shells. Text with a soft shadow directly over the world, 24 px safe margins, never covers the centre third. Only deviation gets colour. |
| **D. Full-screen moment** | Loading, sleep, game over, character creation, new-game survivor selection (`docs/systems/new-game/README.md`) | Main-menu language: black/scrim, left-weighted typography, one accent, curtain transitions. |
| **E. Tool overlay** | Build mode toolbar, catalog, cursor | Minimal edge strips; the world stays the focus; toolbar = segmented text control with optional glyphs (§8). |
| **F. Dev tools** | Admin menu, debug overlay | Functional quiet skin only; lowest priority; never shipped as player UI. |

---

## 5. Interaction contract (all surfaces)

- **One focus.** Hover moves focus (keyboard/mouse mode only); rails show it.
  Programmatic/hover focus never scrolls; keyboard/controller focus
  `reveal()`s with a 56 px margin.
- **Left/Right adjust** the focused value (`ui_cycle` meta or native Range).
  Up/Down move between rows. LB/RB switch tabs/sections. Esc/B back or close.
- **Big targets.** Clicking a row's label acts on its control.
- **Live + confirmed.** Settings-like changes apply immediately and show
  "✓ Saved". Refresh paths use no-signal setters.
- **Destructive = two-step** (inline arm or quiet dialog).
- **No overlap.** Every surface registers with `Q.avoid_toasts(panel,
  modal)` at build time. Toasts step below top strips (build SHOP) and slide
  left of docked panels. While a **modal** workspace/dialog is open, ordinary
  toasts wait (they are already in the Log) and appear on close; critical ones
  break through at top-centre. The HUD never overlaps a docked panel or rail.
- **Walk-away, movement, and world-input gates** from the device-pass
  contracts stay exactly as they are.

---

## 6. Accessibility (non-negotiable)

- Contrast: TEXT on SURFACE ≈ 14:1; MUTED ≈ 7:1; FAINT is for disabled only.
- Colour is never the only signal; every state has a word.
- Keyboard/controller focus always visible (rail) — never rely on hover.
- Reduced motion honoured everywhere; flashing ≤ 3/s (WCAG 2.3.1).
- Minimum type 11 px (12 px for must-read text at 720p); targets ≥ 30 px tall.
- Test at 1280×720, 1920×1080, 2560×1440 and 21:9.

---

## 7. Implementation recipe (new or migrated screen)

1. Read this file, the screen's prior `docs/ui/*.md` contract and its system
   README. List every behaviour/data contract you must keep.
2. Keep the screen's public API (`open/close/is_open/refresh/signals`) and
   handlers. Replace **build code only**; move reusable pieces into
   `QuietControls`/`common/`.
3. Structure: shell (`Q.shell_box`) → header (eyebrow + title) → content
   (groups of `Q.row_box` rows, or tiles) → footer (hint line, Saved, key
   hints). Put a `FocusRail` behind rows inside a clipping `Control` next to
   the `ScrollContainer`; attach `SmoothScroll`.
4. Build rows with `QuietFocusController.make_row()` (or `register_row()`
   for custom layouts) and non-row focusables with `describe()`; wire its
   `surface/rail/smooth/footer/is_active`. Use `QuietFooter` and
   `QuietSegmented` rather than rebuilding them. Settings is the example.
5. Remove icons unless §8 allows them; remove pills, stripes, bordered cards.
6. Motion: copy `_play_open()`; wrap every tween duration in
   `UIMotion.duration()`/`weight()`.
7. Register the screen in `tools/tests/quiet_ui_lint.gd` and update or add
   its smoke test. Capture it live (§10) at 720p and 1080p.
8. Update the screen's `docs/ui/*.md` (mark visuals superseded, keep
   behaviour), `docs/systems/ui/README.md`, and the pass checklist in
   `plans/ui-quiet-redesign-plan.md`.

---

## 8. Icons and artwork

- Default: **no icon**. Text says it better and ships zero artwork.
- Allowed only where glanceability is gameplay-critical and text alone fails
  at a distance: HUD needs, status effects, build tool strip, item previews
  (3D, not icons). Each surviving icon is listed in the icon ledger in the
  plan with its provenance.
- `BunkerSymbolTexture` (code-drawn, AI-authored geometry) and the tracked
  `*_AI_PLACEHOLDER` SVGs are development stand-ins. **AI-authored symbols are
  acceptable as placeholders only** (Brannon, 2026-09-26): every one that
  survives a pass is listed in the plan's icon ledger and must be replaced by
  human-authored/licensed art (or removed) before release. Every pass that
  removes one updates the ledger. Never add new raster/SVG artwork.
- UI copy that is flavour (not functional labels) is flagged for Brannon to
  write.

---

## 9. Anti-patterns found in the audit (do not reintroduce)

Filled blue selected tabs/buttons · ivory focus outlines around boxes ·
icon on every header/tab/button · bordered cards for plain information ·
status pills/badges · domain colour stripes · multicolour stat meters as
decoration · bright ivory scrollbars · blue top-edge bars · red X close boxes
· full-width filled footers · toasts over panel footers · hand-drawn `_draw()`
layouts for anything that is really a list of controls · emoji/triangles as
disclosure glyphs.

---

## 10. Verification tooling

- `tools/tests/quiet_ui_lint.gd` — structural design lint for registered
  screens (no bordered buttons, no saturated-blue fills/text in game UI,
  quiet scrollbars, type floors, no stray icons).
- Screen smoke tests in `tools/tests/*_smoke.gd`.
- Live captures: `tools/ui_capture/` (`capture_scene.gd`,
  `capture_world.gd`, see its README): renders a scene or every in-world UI
  to PNG, any size via `CAPTURE_VIEWPORT` (the GraphicsSettings autoload
  forces the saved window mode, so window resizing is not reliable).

---

## Definition of Done (copy into each pass)

- [ ] No bordered buttons/cards/pills/stripes; icons only per §8.
- [ ] Tokens only from `QuietControls`/`BunkerDesign`; no hand-typed colours.
- [ ] Shell/header/groups/rows/footer match the archetype.
- [ ] FocusRail on every focusable list; hover = focus; Left/Right adjust.
- [ ] SmoothScroll on every scroll region; quiet scrollbar.
- [ ] Open/close/view motion per §2; reduced motion verified.
- [ ] All prior behaviour contracts kept; handlers untouched or tested.
- [ ] 720p / 1080p / 1440p / 21:9 captures reviewed live.
- [ ] Registered in `quiet_ui_lint.gd`; smoke test updated; both pass.
- [ ] Docs updated; icon ledger and plan checklist updated.
