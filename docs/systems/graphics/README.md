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
(SDFGI/SSAO/SSIL/volumetric fog/glow/DOF/MSAA/FOV, persisted independently of
game saves).

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

## Files
| File | Lines | Role |
|---|---|---|
| `GameCamera.gd` | ~180 | `Camera3D` — follow/build-mode transition/DOF/shake/FOV |
| `GraphicsSettings.gd` | ~250 | Autoload — quality presets + individual toggles, own `.cfg` persistence |

## Public API
**`GameCamera`** (`class_name GameCamera`, extends `Camera3D`):
`enter_build_mode()` / `exit_build_mode()` (top-down transition),
`add_trauma(amount: float)` (screen shake, e.g. on `grid_tripped`),
`rotate_view_left()` / `rotate_view_right()` (90° snap). Exported tuning
vars: `follow_speed`, `height`, `pitch_degrees`, `z_offset`, `build_height`,
`build_z_offset`, `transition_speed`, `yaw_lerp_speed`,
`dof_focus_distance`, `dof_far_blur_amount`, `trauma_decay_per_sec`,
`max_shake_offset`, `max_shake_rotation_deg`, `target_path: NodePath`.

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
`flashlight_volumetrics`, `flashlight_shadows` (opt-in only, default OFF —
deliberate gameplay choice, not a perf fallback, see its own doc-comment),
`glow_enabled`, `dof_enabled`, `msaa: int`, `camera_fov: float` (NOT part of
any preset — a comfort/motion-sickness setting, defaults to Godot's
`Camera3D` default of 75.0).

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
  → GraphicsSettings._apply_to_environment() / _apply_to_viewport() (self)

GameCamera._physics_process()
  → _lerp_camera_params(delta) (normal ↔ build-mode transition)
  → _follow_target(delta)
  → _apply_shake(delta) (trauma decay)
```

## Common edits
- **New graphics toggle:** add the field to `GraphicsSettings.gd`, add its
  default to each entry in `PRESETS` (or explicitly leave it out of every
  preset if it's a comfort setting like `camera_fov`/`flashlight_shadows`
  rather than a quality tier), wire the panel in `GraphicsSettingsPanel.gd`
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
- **Don't route `camera_fov`/`flashlight_shadows` through a preset** — both
  are deliberately preset-independent comfort/gameplay choices, not quality
  tiers (see their doc-comments in source).

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
