# Handover — Needs Gauge Redesign + Status Effect Skeleton + Worn-Look Pass (Jul 2026)

## What changed this session

### Phase 1: Needs Gauge Redesign (concentric ring HUD)
- Replaced the old rectangular health/stamina bars (`StatusBars.gd`) and 3
  separate food/water/sleep icon circles (`CircleFill.gd`) with one
  composite radial gauge (`NeedsGauge.gd`), styled after a Medieval-
  Dynasty-style concentric ring reference.
- 3 rings, center-out: Ring 1 = Health(L)/Food(R), Ring 2 =
  Stamina(L)/Water(R), Ring 3 = Sleep (originally both sides, see Phase 2).
- Each half-arc has a V-shaped gap at top/bottom and is bottom-anchored:
  fixed tip at the bottom gap, arc grows upward toward the top gap as the
  stat fills toward 100%.
- Blank dark center circle, no icons on the gauge itself.
- `HUD.gd`'s public API (`set_health/stamina/food/water/sleep`) unchanged —
  now forwards to `needs_gauge.set_*()`. `MainWorld.gd` required zero
  changes.
- Deleted: `StatusBars.gd`, `StatusBars.gd.uid`, `CircleFill.gd`,
  `CircleFill.gd.uid`. Kept the 3 now-unreferenced icon SVGs on disk for a
  possible future icon pass.

### Phase 2: Sleep Ring Trimmed to Right-Side Only
- Ring 3 (Sleep) originally mirrored on both halves — trimmed to draw the
  right half only, per Brannon's follow-up call after reviewing the first
  pass. Left half is never drawn (not just zeroed).

### Phase 3: Status Effect Skeleton + F7 Test Wiring
- `StatusEffectIcon.gd` — single reusable badge (icon or grey placeholder
  + a clockwise-depleting duration ring), ticks down via its own
  `_process()`, emits `expired(id)`.
- `StatusEffectsContainer.gd` — holds active badges in a fixed, hand-placed
  3-slot stagger (`SLOT_OFFSETS`) matching the reference image layout, not
  an auto-laying `VBoxContainer`. Oldest effect always in slot 0 (top);
  `_reflow()` re-assigns slots by order-index after every add/remove so
  remaining badges slide up. No cap on simultaneous effects, no
  placeholder for empty slots.
- New F7 admin menu button ("Add Test Status Effect (10s)") adds one test
  badge per press with a unique id, `icon = null`, 10s duration, default
  ring color. Skeleton only — no real gameplay effects wired in yet.

### Phase 4: Worn/Rugged Visual Pass
- No grunge texture asset exists in the project — built procedurally.
- `UIKit.draw_rugged_arc()`/`draw_rugged_circle()` — hand-inked wobbly
  border stroke (fixed per-angle hash, not per-frame random, so it never
  flickers), applied to every ring edge + center circle (`NeedsGauge`) and
  both badge ring edges (`StatusEffectIcon`).
- New `assets/shaders/grunge_overlay.gdshader` — subtle random-blotch
  darkening `CanvasItem` shader, applied as a `ShaderMaterial` on both
  `NeedsGauge` and `StatusEffectIcon`. Kept deliberately subtle per
  Brannon's explicit call.

### Phase 5: Bugfix — Duplicate Function in AdminMenu.gd
- An earlier implementation pass duplicated the
  `_get_status_effects()`/`_on_add_status_effect_pressed()` block (pasted
  twice), causing a "Function has the same name as a previously declared
  function" parser error on F7. Fixed by removing the second copy.

### Phase 6: Color Darkening + Status Badge Realignment
- All 5 `NeedsGauge` ring fill colors, `AdminMenu.TEST_EFFECT_COLOR`, and
  `StatusEffectIcon`'s default `_ring_color` darkened ~5% (each RGB
  channel × 0.95) to better match the rest of the theme's muted palette.
- `StatusEffectsContainer.SLOT_OFFSETS` corrected after pixel-measuring a
  screenshot: top (slot 0) and bottom (slot 2) now share the exact same X
  (a straight vertical column, were off by 16px); middle (slot 1) shifted
  further left, now 12.5px left of that shared column (25% of a badge's
  50px width) instead of sitting to the right of it.

## Files Modified
- `scripts/ui/hud/NeedsGauge.gd` — new file, then Sleep right-only trim,
  rugged border + grime shader, color darkening (multiple passes)
- `scripts/ui/hud/StatusEffectIcon.gd` — new file, then grey placeholder,
  rugged border + grime shader, default ring color darkening
- `scripts/ui/hud/StatusEffectsContainer.gd` — new file, then converted
  VBoxContainer → Control with fixed slot stagger, slot X-alignment fix
- `scripts/ui/menus/AdminMenu.gd` — new "STATUS" row + test-effect
  callback/getter, duplicate-function bugfix, color darkening
- `scripts/ui/hud/HUD.gd` — `@onready` refs + 5 setter functions
  repointed from old `bars`/`food_circle`/`water_circle`/`sleep_circle` to
  `needs_gauge`
- `scripts/ui/common/UIKit.gd` — added `draw_rugged_arc()` /
  `draw_rugged_circle()` / `_rugged_hash()`
- `scenes/ui/HUD.tscn` — `BottomLeft`/`LeftIcons` removed, `NeedsGauge` +
  `StatusEffects` nodes added; `StatusEffects` later changed from
  `VBoxContainer` to `Control`

## Files Created
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `assets/shaders/grunge_overlay.gdshader`

## Files Deleted
- `scripts/ui/hud/StatusBars.gd` + `.uid`
- `scripts/ui/hud/CircleFill.gd` + `.uid`

## Next Up
- Real gameplay status effects still need to be wired into
  `StatusEffectsContainer.add_effect()` — currently F7 test-only.
- `BuildModeHUD.gd`'s buttons/tabs/interactions are now in UI Claude's
  scope per Brannon's Jul 2026 note — not yet started, rest of
  `BuildModeHUD.gd` stays with the non-UI Claude instance.
- Worn-look shader defaults (`grit_strength = 0.14`, `grit_scale = 26.0`)
  are a first pass — confirm they read right in actual play, not just the
  single reviewed screenshot.