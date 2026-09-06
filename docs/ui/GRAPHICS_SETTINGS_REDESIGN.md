# Graphics Settings Redesign

## Approved design contract

Graphics Settings is a direct visual child of the approved pause workspace. It
uses the same 1240 × 760 desktop shell, charcoal surfaces, ivory type, worn brass
dividers, blue focus states, generous controls, and persistent footer hints.

The screen is intentionally split into two stable regions:

- A 284 px left rail provides BUNKER / SETTINGS identity, immediate navigation
  between Display, Rendering, Effects, and Camera, a live-apply status card, and
  a clear return to the Pause Menu.
- The right workspace keeps the Quality Preset prominent and puts every detailed
  control inside one bounded scroll viewport. This prevents the panel from ever
  growing below a 1080p display.

## Behavior preserved

- Low, Medium, High, and Ultra presets still call the existing
  `GraphicsSettings.apply_preset()` backend.
- Custom is now visible as a disabled/read-only preset state when individual
  quality settings differ from a preset.
- Window mode, resolution, VSync, FPS cap, rendering driver, anti-aliasing,
  anisotropic filtering, shadow quality, render scale, every advanced effect,
  dynamic resolution, flashlight volumetrics, and camera FOV remain connected to
  their existing backend methods.
- Rendering-driver changes retain the existing restart confirmation and relaunch
  flow.
- Settings continue to apply live. Slider values are also persisted when the
  panel closes, covering controller and keyboard adjustments that do not emit a
  mouse `drag_ended` signal.
- The mouse mode that existed before opening the submenu is restored on close,
  so returning to the Pause Menu keeps its cursor usable.

## Input contract

- Mouse: click controls, drag sliders/scrollbar, click outside or Back to close.
- Keyboard: arrows navigate or adjust focused ranges; Enter selects; Escape
  returns to Pause.
- Controller: D-pad and right stick navigate; A selects; focused sliders adjust
  horizontally; the visible scrollbar is focusable and scrolls vertically; B
  returns to Pause.

No gameplay, rendering, or save-system backend was replaced by this pass.
