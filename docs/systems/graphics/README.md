# Graphics / Camera System

**Read this before opening `GameCamera.gd` or `GraphicsSettings.gd`.** See
`docs/systems/ui/README.md` for `GraphicsSettingsPanel.gd` (the settings UI
that reads/writes this system) and `docs/systems/environment/README.md` for
the closely-related world-atmosphere systems (`LightingDirector`,
`DustMotes`) kept in a separate doc since they're about world geometry/fog,
not the viewport/camera itself.

## Purpose
Owns the isometric-style camera (follow, build-mode top-down transition,
DOF/shake/FOV) and the player's device-level rendering/quality preferences
(SDFGI/SSAO/SSIL/volumetric fog/glow/DOF/MSAA/AA/FXAA/TAA/anisotropic filtering/
shadow quality/render scale/FOV, persisted independently of game saves).

## Responsibilities
- `GameCamera.gd`: follows a target (the player) at a fixed iso pitch, lerps
  between normal-mode and build-mode (top-down) camera params, handles the
  90°-snap rotate-view input, screen-shake ("trauma"), and applies DOF/FOV
  live from `GraphicsSettings`.
- `GraphicsSettings.gd` (autoload): the single source of truth for every
  graphics/quality toggle in the game. 5 presets (Low/Medium/High/Ultra/
  Custom) plus individually-settable fields; persists to
  `user://graphics_settings.cfg`, completely separate from
  `SaveManager`'s save-slot system (device preference, not game state).

## Non-responsibilities
- **Does not own game-save persistence** — `GraphicsSettings` deliberately
  does NOT go through `SaveManager`'s field-registry (see
  `docs/systems/world-core/README.md`); it's a hardware/device preference
  that should survive independently of — and not be reset by — loading a
  different save slot.
- **Does not own per-light dimming/atmosphere reactions** — that's
  `LightingDirector.gd` (`docs/systems/environment/README.md`); this system
  only owns raw rendering quality toggles and camera framing, not gameplay-
  driven lighting state.
- **Does not draw its own settings UI** — `GraphicsSettingsPanel.gd`
  (`docs/systems/ui/README.md`) is the Control-node panel that calls into
  this system's setters/getters; `GraphicsSettings.gd` itself never touches
  a Control node.
- **Does not own Flashlight.gd's SpotLight3D itself** — that's
  `docs/systems/furniture-items/README.md`'s file; this doc only tracks the
  *design* of the render-layer self-shadow-exclusion scheme (see "Flashlight
  self-shadow exclusion" above) since it's a lighting/shadow decision, the
  same boundary reasoning as the DOF/camera settings this doc otherwise owns.

## Files
| File | Lines | Role |
|---|---|---|
| `GameCamera.gd` | ~180 | `Camera3D` — follow/build-mode transition/DOF/shake/FOV |
| `GraphicsSettings.gd` | ~280 | Autoload — quality presets + individual toggles, own `.cfg` persistence |
| `GraphicsSettingsPanel.gd` | ~575 | Settings UI panel — sectioned layout, live preview, full preset + individual control |
| `TiltShiftDOF.gd` | ~45 | Screen-space tilt-shift DOF — ColorRect + shader material, dumb forwarder driven by GameCamera |
| `tilt_shift_dof.gdshader` (`assets/shaders/`) | ~40 | Vertical-band screen-space blur — sharp band + soft ramp, no 3D depth read |

## Public API
**`GameCamera`** (`class_name GameCamera`, extends `Camera3D`):
`enter_build_mode()` / `exit_build_mode()` (top-down transition),
`add_trauma(amount: float)` (screen shake, e.g. on `grid_tripped`),
`rotate_view_left()` / `rotate_view_right()` (90° snap). Exported tuning
vars: `follow_speed`, `height`, `pitch_degrees`, `z_offset`, `build_height`,
`build_z_offset`, `transition_speed`, `yaw_lerp_speed`,
`dof_focus_center_y`, `dof_focus_band_half_height`, `dof_transition_height`,
`dof_max_blur_px` (screen-space tilt-shift DOF tuning, Aug 2026 — replaced
the old CameraAttributesPractical distance-based fields), plus
`tilt_shift: TiltShiftDOF` (injected by
`MainWorld._setup_tilt_shift_dof()`),
`trauma_decay_per_sec`, `max_shake_offset`, `max_shake_rotation_deg`,
`target_path: NodePath`.

**`GraphicsSettings`** (autoload — see Ownership for why it's NOT yet
registered in committed `project.godot`): `apply_preset(preset: int)` (LOW=0/
MEDIUM=1/HIGH=2/ULTRA=3/CUSTOM=4 — plain `int`, NOT the `Preset` enum type,
see Forbidden edits), `set_setting(field: String, value: Variant)` (persists
to disk immediately), `set_setting_live(field: String, value: Variant)`
(applies live WITHOUT a disk write — for continuous-drag UI like the FOV
slider, see Known tradeoffs), `save_now()` (explicit disk write, pairs with
`set_setting_live`). Public vars (read directly, e.g.
`GraphicsSettings.camera_fov`): `current_preset`, `sdfgi_enabled`,
`ssao_enabled`, `ssil_enabled`, `volumetric_fog_enabled`,
`flashlight_volumetrics`, `shadow_casting_enabled` (preset-driven Aug 2026:
LOW/MEDIUM off, HIGH/ULTRA on — see "Unified dynamic shadow casting" below),
`glow_enabled`, `dof_enabled`, `msaa: int`, `camera_fov: float` (NOT part of
any preset — a comfort/motion-sickness setting, defaults to Godot's
`Camera3D` default of 75.0), `vsync_enabled`, `window_mode`, `fps_cap`,
`screen_space_aa`, `use_taa`, `anisotropic_filtering`, `shadow_quality`,
`render_scale`.

## Signals produced
| File | Signal | Params | Fires when |
|---|---|---|---|
| `GraphicsSettings.gd` | `settings_changed` | — | Any setting changes (preset applied, individual field changed via `set_setting`/`set_setting_live`) |

`GameCamera.gd` produces no signals of its own.

## Signals/events consumed
- `GameCamera._apply_dof_setting()`/`_apply_fov_setting()` connect to
  `GraphicsSettings.settings_changed` to react live — same pattern
  `Flashlight.gd` uses for its own volumetrics/shadow settings (see
  `docs/systems/furniture-items/README.md`).
- `GameCamera.add_trauma()` is called by `MainWorld`'s
  `PowerManager.grid_tripped` handler (see `docs/systems/world-core/README.md`
  Signals/events consumed) — not a direct signal connection on `GameCamera`
  itself, `MainWorld` is the intermediary.

## Ownership
`GameCamera` is a scene node (not an autoload) — a `Camera3D` under the main
world/player scene, `target_path` pointed at the player. `GraphicsSettings`
**IS registered as an autoload directly in the committed `project.godot`**
(`GraphicsSettings="*res://scripts/core/GraphicsSettings.gd"`, since repo
HEAD `00938b5`) — a one-off, deliberate exception to the usual "Brannon adds
new autoloads himself via Project Settings > Autoload" rule (he hit trouble
adding it manually that one time; verified with a clean headless boot before
committing — see `HANDOVER.md`/`PROJECT_SUMMARY.md` §9 gotcha). This is NOT
a new standing rule — any future new autoload should still default to
editor-side registration unless Brannon explicitly asks for the same
workaround again. **Doc-drift note:** `GraphicsSettings.gd`'s own header
comment still says "NOT YET REGISTERED AS AN AUTOLOAD" — that comment is
stale as of this doc's writing (July 2026) and should be corrected in
source next time that file is touched for an unrelated change.

## Persistence
`GraphicsSettings` persists itself to `user://graphics_settings.cfg` via its
own `_save()`/`_load()` — entirely independent of `SaveManager`'s
save-slot JSON files (see `docs/systems/world-core/README.md`). This is by
design: graphics preferences are a device setting, not part of a specific
save game, and must survive across different save slots untouched.

## Call graph (brief)
```
GraphicsSettingsPanel.gd (UI)
  → GraphicsSettings.apply_preset(preset) / set_setting(field, value) /
    set_setting_live(field, value) → save_now()
  → GraphicsSettings.settings_changed emitted
  → GameCamera._apply_dof_setting() / _apply_fov_setting()
  → Flashlight.gd's own settings_changed listener (docs/systems/furniture-items/)
  → GraphicsSettings._apply_to_environment() / _apply_to_viewport() / _apply_to_display() (self)

GameCamera._physics_process()
  → _lerp_camera_params(delta) (normal ↔ build-mode transition)
  → _follow_target(delta)
  → _apply_shake(delta) (trauma decay)
```

```
MainWorld._setup_tilt_shift_dof() (startup, dynamic instantiation)
  → TiltShiftDOF.gd created + added, camera.tilt_shift assigned
  → GameCamera._apply_dof_setting() called once immediately (initial sync)
  → thereafter driven by GraphicsSettings.settings_changed / enter_build_mode() / exit_build_mode()
```

## Common edits
- **New graphics toggle:** add the field to `GraphicsSettings.gd`, add its
  default to each entry in `PRESETS` (or explicitly leave it out of every
  quality preset if it's a comfort setting like `camera_fov`/
  `vsync_enabled`/`window_mode`/`fps_cap`/`render_scale` rather than a quality
  tier), wire the panel in `GraphicsSettingsPanel.gd`
  (`docs/systems/ui/README.md`), and connect the consuming system
  (`GameCamera`, `Flashlight`, `LightingDirector`, etc.) to
  `settings_changed` the same way existing consumers do.
- **New camera behavior/mode:** follow `enter_build_mode()`/
  `exit_build_mode()`'s lerp-transition shape rather than snapping camera
  params instantly.

## Forbidden edits
- **Don't cast `Preset` enum values with `as`.** Enums are plain ints in
  GDScript — `as` doesn't support enum casts (hit twice already, in `msaa`/
  `_apply_to_viewport()` and the preset dropdown — see
  `HANDOVER.md`/`PROJECT_SUMMARY.md` §10 gotcha list). `apply_preset()`
  deliberately takes a plain `int`, not `Preset`, to avoid the ambiguity at
  the call boundary entirely — don't retype it back to `Preset`.
- **Don't hand-edit `project.godot`'s `[autoload]` section** for any FUTURE
  new autoload — the editor owns that section and can silently revert
  hand-edits. `GraphicsSettings` itself is already a committed one-off
  exception (see Ownership above) — don't treat that as license to hand-edit
  autoloads generally going forward.
- **Don't route `camera_fov`/`vsync_enabled`/
  `window_mode`/`fps_cap`/`render_scale` through a preset** — all are
  deliberately preset-independent comfort/gameplay choices, not quality
  tiers (see their doc-comments in source).
- **Don't reintroduce point/distance-based DOF** (e.g. re-adding a
  `CameraAttributesPractical` with `dof_blur_far_distance`) without
  re-reading the Aug 2026 tilt-shift rework note above first — it was
  replaced for a structural reason (fixed iso pitch + flat floor don't
  generate enough true depth variation), not a tuning mistake.

## Known tradeoffs / tech debt
- No automated tests.
- `set_setting_live()`/`save_now()` split exists specifically to stop the FOV
  slider from disk-write-spamming on every drag frame — any other
  continuous-drag setting added in the future should use the same split
  rather than calling `set_setting()` every frame.
- `GraphicsSettings` not yet a committed autoload (see Ownership) — every
  fresh clone requires Brannon to manually register it once in the editor
  before the project will compile/run.

## Extension points
- New quality-tier-dependent systems should read `GraphicsSettings.<field>`
  directly and connect to `settings_changed` — don't poll `_process()` for
  changes.
- `GameCamera`'s trauma/shake system (`add_trauma()`) is generic — any future
  system wanting screen shake should call it the same way `MainWorld`'s grid-
  tripped handler does, rather than building a second shake mechanism.

## Recent changes (Jul 2026)

### DOF Blur Bug Fix (Phase 0)
**Root cause:** `dof_focus_distance = 9.0` was shorter than actual camera-to-player distance (~16.1m). DOF far blur transition at 13m meant player/midground was fully blurred.
**Fix:** `dof_focus_distance: 9.0 → 15.0` (matches actual camera-to-player distance). Added `@export var dof_blur_far_transition: float = 6.0` (was hardcoded 4.0). Removed duplicate declaration.

### Preset System Overhaul + New Fields (Phase 1)
- Updated `PRESETS` table with all Phase 2-4 fields: `anisotropic_filtering`, `shadow_quality`, `render_scale`, `screen_space_aa`, `use_taa`
- Added 8 new fields: `vsync_enabled`, `window_mode`, `fps_cap`, `screen_space_aa`, `use_taa`, `anisotropic_filtering`, `shadow_quality`, `render_scale`
- Added `_apply_to_display()` for VSync, window mode, FPS cap, anisotropic filtering, shadow quality
- Extended `_apply_to_viewport()` for `screen_space_aa`, `use_taa`, `render_scale`
- Extended `set_setting_live()`, `_save()`, `_load()` for all new fields
- Updated `PRESETS` table with complete Phase 2-4 values per graphics plan

### Display Settings (Phase 2)
- New fields: `vsync_enabled` (bool), `window_mode` (int enum), `fps_cap` (int, 0=uncapped)
- Added to `_apply_to_display()` and `PRESETS`
- Window mode enum: `WINDOWED`/`FULLSCREEN`/`EXCLUSIVE_FULLSCREEN`

### Anti-Aliasing Overhaul (Phase 3)
- New fields: `screen_space_aa` (int enum), `use_taa` (bool)
- AA combo dropdown in panel mapping 6 friendly options → 3 raw fields:
  - Off, Fast (FXAA), Balanced (MSAA 2x), Sharp (MSAA 2x+FXAA), Smooth (TAA), Max (MSAA 4x+TAA)

### Anisotropic Filtering, Shadow Quality, Render Scale (Phase 4)
- New fields: `anisotropic_filtering` (0/2/4/8/16), `shadow_quality` (atlas size: 1024/2048/4096), `render_scale` (0.5–1.0)
- Applied in `_apply_to_display()` and `_apply_to_viewport()`

### Settings Panel UI Rewrite (Phase 5)
- Full rewrite with sectioned layout: Quality Preset, Display, Rendering, Advanced Quality, Flashlight, Camera
- ScrollContainer with max height, section headers matching PauseMenuUI
- AA combo dropdown (6 options → 3 raw fields)
- Display: Window Mode, Resolution (windowed only), VSync, FPS Cap
- Rendering: AA combo, Anisotropic, Shadow Quality, Render Scale slider
- Advanced Quality: SDFGI, SSAO, SSIL, Volumetric Fog, Glow, DOF checkboxes
- Flashlight: Volumetrics, Shadows checkboxes
- Camera: FOV slider
- ScrollContainer with max height, section headers, PauseMenuUI-styled theme
- Uses `UIKit.settings_controls_theme()` for CheckBox/OptionButton/HSlider
- Reverted hover-spin to 2-pool (construct vs shop)

### Preview Scale Normalization & Zoom
- Added `PREVIEW_TARGET_SIZE = 0.5667` (0.85/1.5) + `_preview_normalize_scale()` helper
- Applied to all 3 preview pools (MeshLibrary, procedural, shop)
- Seed packets (~0.14m) and Generator L (~1.85m) now render at same on-screen size

## Verification
- `tools/godot_check.sh` → **PASS**
- Code compiles cleanly

---

## Recent changes (Aug 2026) — Tilt-shift DOF rework

### Tilt-shift DOF rework
**Root cause of the old "blurs one random object, nothing else" look:**
`dof_focus_distance = 15.0` vs. actual camera→player distance
`sqrt(14² + 8²) ≈ 16.12` — the player was already 1.1m past the focus
point and inside the transition band, so blur landed on the tallest
nearby object's upper portion rather than reading as background/
foreground depth. More fundamentally: a fixed ~55° iso pitch over a
mostly-flat floor doesn't generate enough true depth-buffer variation for
point/distance DOF to look intentional.
**Fix:** replaced `CameraAttributesPractical`'s distance-based DOF with a
screen-space tilt-shift shader (`tilt_shift_dof.gdshader` +
`TiltShiftDOF.gd`) — a horizontal sharp band (`dof_focus_center_y` ±
`dof_focus_band_half_height`) with a soft blur ramp
(`dof_transition_height`) toward the top (ceiling/back wall) and bottom
(foreground) screen edges, up to `dof_max_blur_px`. Independent of true
3D depth, so it's immune to the FOV-slider-changes-perceived-distance
issue and can't blur through the middle of a single tall object.
`GameCamera.gd` remains the single source of truth (same
`GraphicsSettings.dof_enabled` gate, same build-mode-forces-off rule);
`TiltShiftDOF.gd` is a dumb forwarder instantiated dynamically by
`MainWorld` (same pattern as `LightingDirector`).

### Flashlight self-shadow exclusion
**Problem:** with `GraphicsSettings.shadow_casting_enabled` on, the player's own
mesh — extremely close to the handheld SpotLight3D's origin — cast a large
shadow straight back into the center of its own beam (a visible "dome").
**Fix:** `Player.gd` tags its mesh with an exclusive render layer bit
(`PLAYER_SELF_LIGHT_LAYER_BIT`, layer 12 — see `docs/systems/player/README.md`)
that REPLACES rather than adds to the default layer, and
`Flashlight.gd`'s SpotLight3D clears that one bit from its own
`light_cull_mask` at creation. Every other light in the game keeps its
default (all-layers) cull mask, so the player continues being lit/shadowed
normally by everything except the flashlight — this was a deliberate
choice, not a limitation: Godot has no per-light "lit but not a
shadow-caster" flag, only the combined light_cull_mask, and the flashlight
never visibly lit the player's own body in the first place (floor-aimed
beam, fixed iso pitch), so excluding it from both together costs nothing
visible while removing the self-shadow.
**Scope note:** only the player's own capsule mesh is excluded — furniture,
walls, and other objects still cast normal shadows into the flashlight
beam when `shadow_casting_enabled` is on. If the flashlight's own held-item
mesh (the flashlight body itself) turns out to cast a similar smaller
self-shadow, that's a separate, not-yet-observed issue — flag it before
extending this same layer-bit pattern to it.
**Restored to its original form (Aug 2026)** — see the
FLASHLIGHT_PLAYER_SELF_SHADOW_EXCLUSION_PLAN.md from earlier this
session. `Player.PLAYER_SELF_LIGHT_LAYER_BIT` excludes only the player's
own mesh from `Flashlight.gd`'s own beam. Not part of the "Aggregated
character shadows" detour below — that plan generalized this constant,
and reverting it moved the constant back here.

### Unified dynamic shadow casting
**What changed:** `GraphicsSettings.flashlight_shadows` renamed to
`shadow_casting_enabled` and generalized from flashlight-only opt-in to all
three dynamic lights — Flashlight, WallLight, GrowLight. Now preset-driven
(LOW/MEDIUM off, HIGH/ULTRA on) instead of opt-in-only; still individually
toggleable via the "Shadow Casting" checkbox (moved from the Flashlight
section to Advanced Quality in `GraphicsSettingsPanel.gd`, since it's a
normal preset-tier toggle now, not a flashlight-specific opt-in one).
**Per-light shape reasoning:**
- Flashlight (`SpotLight3D`) — no change, already directional.
- WallLight (`OmniLight3D`) — stays Omni (correct for a wall-mounted
  fixture with nothing behind it); just gets `shadow_enabled` wired to the
  setting. Side benefit: this also stops the fixture's light from bleeding
  through the wall mesh behind it into an adjacent room, since the wall now
  correctly self-occludes once shadows are on.
- GrowLight — **converted from `OmniLight3D` to a downward-facing
  `SpotLight3D`** (`rotation_degrees.x = -90`, `spot_angle = 35.0`),
  because the fixture only ever shines down onto its tray and Spot shadows
  are dramatically cheaper than Omni's cubemap — relevant since a farm room
  can hold far more of these than a base has wall lights. Confirmed this is
  visual-only: `GrowLight.get_active_growth_speed()` (read by
  `FarmPlant.gd`) is a pure XZ position match, independent of the light
  node's shape/range.
**Cross-thread note:** `WallLight.gd`/`GrowLight.gd` are Power-thread
files; this session's edits there are limited to the light node
construction/shadow wiring, no power-grid logic touched.

### Aggregated character shadows — REVERTED, see "Character shadow decal" below
Built Aug 2026: one aggregated fake Light3D per character, replacing real
per-light shadow reception, to fix visual clutter from multiple real
lights each casting their own shadow onto a character. Reverted the same
session after three hotfix rounds (pitch-black characters, then
severely-underlit characters, then harsh "flash photo" lighting) — the
structural problem was that Godot's light_cull_mask ties a light's
illumination and its shadow-casting together as one switch, so excluding
characters from real shadows meant excluding them from real light too,
which forced the fake proxy light to take over 100% of character
illumination. That's a much bigger surface area than the actual complaint
(which was specifically about the shadow CAST BY the character, never
about how the character itself was lit), and every subsequent bug came
from that one light being asked to simultaneously illuminate correctly,
shadow correctly, stay bright, and look natural. See git history for the
full three-hotfix arc if useful context for a future similar decision.

### Character shadow decal
Replaces the above. Two independent, much narrower pieces instead of one
light doing everything:
1. **`GeometryInstance3D.cast_shadow = SHADOW_CASTING_SETTING_OFF`** on the
   player/NPC mesh (see Player.gd/NPC.gd) — a native per-object property
   that stops a mesh from casting any real shadow onto anything, while it
   keeps receiving light/shadow completely normally from every real light.
   This alone is what fixes the original multi-shadow complaint. Real
   character illumination is fully untouched/default again.
2. **`CharacterShadowDecal.gd`** — a purely cosmetic, non-lit flat mesh
   (no Light3D involved anywhere) faking one blended "cone" shadow shape,
   using the same weighted-light-aggregate direction math the old proxy
   used (`WallLight.gd`/`GrowLight.gd`'s `get_shadow_weight()`, kept from
   the reverted system). Length is clipped by a raycast against
   furniture/walls (`collision_mask = 4`) so it doesn't stretch through
   solid objects — only length is clipped, not per-pixel shape, so it
   still visually crosses over low obstacles up to the clip point.
Because there's no Light3D in this system, it structurally cannot cause
the class of bug the previous system did — worst case is a misshapen or
misoriented decorative mesh, not a lighting regression.

**Aug 2026 follow-up fix:** the decal originally placed itself at the
character's own origin (capsule center, not the floor) and lerped its
direction the same way opacity fades, which read as visible lag rather
than matching real shadow movement. Fixed: floor offset is now read from
each character's own CapsuleShape3D height (Player and NPC use different
capsule heights) instead of assumed; direction now snaps instantly, no
lerp, matching how real shadows track light position with zero lag.

**Aug 2026 shape fix:** the original vertex-color trapezoid only faded
alpha along its length — the left/right edges were a hard, unblended
straight cut, reading as a "flat wall" rather than something sourced from
the character. Replaced with a procedurally-generated soft alpha texture
(_get_shared_texture()) mapped onto a plain rectangle: a tight, contained
core right at the character's feet, widening into a soft cone tail, fully
soft-edged in every direction. The mesh itself simplified to a plain
UV-mapped rectangle — all shape/softness logic now lives in the texture.

**Aug 2026 fix v2 (width-opacity decoupling):** the shadow's width was
getting visually distorted by its own opacity — multiplying a soft
gradient's fade by a bigger weight (more nearby lights) makes more of that
fade stay visible, so the apparent edge sits farther out (reads wider);
a smaller weight (one light) does the opposite (reads narrower). Same
underlying shape, different APPARENT size, purely from the opacity
multiplier. Fixed by tightening the edge transition close to the
character (EDGE_SOFTNESS_NEAR, much crisper than the far tail) so the
visible boundary there is far less sensitive to the weight multiplier.
Also: near-width now calibrated per-character from their actual
CapsuleShape3D.radius (Player/NPC differ) instead of one guessed constant
for both, via a new _shadow_width_scale applied to the mesh's X scale in
_process(). A brief tip ease-in was added to soften the near cap's start,
though a true circular/radial cap was deliberately not attempted this
round (flagged as a bigger, riskier rewrite for later if still needed).

**Aug 2026 fix v3 (true cone):** v2's width tightening/calibration still
left a flat line at the character's end (narrower, softer, but still a
finite-width boundary — exactly what kept showing up as "two connected
points defining a line" in playtesting). Replaced the two-stage "solid
core then edge fade" formula with a single continuous smoothstep fade
starting at the centerline itself, widening toward the far end — a true
cone/wedge shape that genuinely converges to a point at the character
rather than a narrow band. Width scaling simplified to plain proportional
sizing (Player's radius as baseline) since there's no longer a specific
near-width to calibrate to a footprint.

**Aug 2026 fix v4 (direction-dependent length/width bug):** shadows from
north-south lights read long and thin; east-west lights read stubby and
stretched perpendicular. Ruled out camera-projection foreshortening by
tracing GameCamera.gd's actual offset/pitch math — it would compress the
opposite axis from what was observed, and wouldn't swap length/width.
Root cause was most likely in how the shadow's transform composed a
rotation (Basis(Vector3.UP, yaw)) with a subsequent non-uniform scale
(.scaled(...)) — not fully provable by hand without running the engine.
Fixed by replacing that composition with an explicit transform built
directly from two independently-scaled direction vectors (forward and its
90°-rotated perpendicular), removing any step where an axis mix-up could
occur.

### Flashlight self-shadow exclusion
(Restored to its original form — see the FLASHLIGHT_PLAYER_SELF_SHADOW_EXCLUSION_PLAN.md
from earlier this session. Player.PLAYER_SELF_LIGHT_LAYER_BIT excludes
only the player's own mesh from Flashlight.gd's own beam. Not part of the
"Aggregated character shadows" detour above — that plan generalized this
constant, and reverting it moved the constant back here.)

### Rendering driver switch
Origin: DXGI_ERROR_DEVICE_REMOVED crash on an RX 580 under D3D12 — the
D3D12 backend died on the first scene-shader pipeline before any game
script ran. Fixed at the project level by pinning
`rendering_device/driver.windows="vulkan"` in `project.godot` (committed
default, unchanged by this feature). This adds a player-facing "Rendering
Driver" option (Vulkan/D3D12) in Settings > Rendering, for hardware where
D3D12 works fine and may perform better.

**Hard constraint:** the driver is selected at engine startup, before any
script runs — cannot change mid-session, full stop. This is a
restart-based setting, not a live one:
`GraphicsSettings.rendering_driver`/`set_rendering_driver()` are
deliberately NOT part of PRESETS or `set_setting_live()`.

**Two-tier apply mechanism** (`GraphicsSettingsPanel.gd`):
1. **Tier 1 (relaunch now):** `OS.create_process()` spawns a new instance
   with `--rendering-driver <value>` on the command line, then quits the
   current one — only after the player confirms via a restart-required
   dialog. High confidence — same override mechanism this bug's own fix
   already proved works.
2. **Tier 2 (durability):** best-effort writes an `override.cfg` next to
   the executable (Godot reads this before rendering device selection,
   without touching the tracked project.godot) so the choice also survives
   a future PLAIN relaunch, not just the in-app button. Lower confidence —
   flagged for verification against a real exported build. Failure here
   never blocks Tier 1.

`GraphicsSettings.session_start_rendering_driver` is captured once, at the
end of `_load()` — it's what the engine is actually running under this
session (by construction of the relaunch flow above), and is the correct
comparison point for "does this new choice actually require a restart,"
not `rendering_driver` itself (which may already have been overwritten by
the time the comparison runs).

**Known limitation:** if the player picks a new driver and dismisses the
restart prompt ("Later"), then later closes the game through any means
other than actually restarting, the NEXT launch only reflects the new
choice if Tier 2's override.cfg write succeeded and Godot's override.cfg
loading behaves as expected for this project's export — see the
confidence note above. Tier 1 (the explicit in-app button) always works
regardless.

---

## Common edits
- **New graphics toggle:** add the field to `GraphicsSettings.gd`, add its
  default to each entry in `PRESETS` (or explicitly leave it out of every
  quality preset if it's a comfort setting like `camera_fov`/
  `vsync_enabled`/`window_mode`/`fps_cap`/`render_scale` rather than a quality
  tier), wire the panel in `GraphicsSettingsPanel.gd`
  (`docs/systems/ui/README.md`), and connect the consuming system
  (`GameCamera`, `Flashlight`, `LightingDirector`, etc.) to
  `settings_changed` the same way existing consumers do.
- **New camera behavior/mode:** follow `enter_build_mode()`/
  `exit_build_mode()`'s lerp-transition shape rather than snapping camera
  params instantly.

## Forbidden edits
- **Don't cast `Preset` enum values with `as`.** Enums are plain ints in
  GDScript — `as` doesn't support enum casts (hit twice already, in `msaa`/
  `_apply_to_viewport()` and the preset dropdown — see
  `HANDOVER.md`/`PROJECT_SUMMARY.md` §10 gotcha list). `apply_preset()`
  deliberately takes a plain `int`, not `Preset`, to avoid the ambiguity at
  the call boundary entirely — don't retype it back to `Preset`.
- **Don't hand-edit `project.godot`'s `[autoload]` section** for any FUTURE
  new autoload — the editor owns that section and can silently revert
  hand-edits. `GraphicsSettings` itself is already a committed one-off
  exception (see Ownership above) — don't treat that as license to hand-edit
  autoloads generally going forward.
- **Don't route `camera_fov`/`vsync_enabled`/
  `window_mode`/`fps_cap`/`render_scale` through a preset** — all are
  deliberately preset-independent comfort/gameplay choices, not quality
  tiers (see their doc-comments in source).
- **Don't reintroduce point/distance-based DOF** (e.g. re-adding a
  `CameraAttributesPractical` with `dof_blur_far_distance`) without
  re-reading the Aug 2026 tilt-shift rework note above first — it was
  replaced for a structural reason (fixed iso pitch + flat floor don't
  generate enough true depth variation), not a tuning mistake.

## Known tradeoffs / tech debt
- No automated tests.
- `set_setting_live()`/`save_now()` split exists specifically to stop the FOV
  slider from disk-write-spamming on every drag frame — any other
  continuous-drag setting added in the future should use the same split
  rather than calling `set_setting()` every frame.
- `GraphicsSettings` not yet a committed autoload (see Ownership) — every
  fresh clone requires Brannon to manually register it once in the editor
  before the project will compile/run.

## Extension points
- New quality-tier-dependent systems should read `GraphicsSettings.<field>`
  directly and connect to `settings_changed` — don't poll `_process()` for
  changes.
- `GameCamera`'s trauma/shake system (`add_trauma()`) is generic — any future
  system wanting screen shake should call it the same way `MainWorld`'s grid-
  tripped handler does, rather than building a second shake mechanism.

(End of file - total ~220 lines)