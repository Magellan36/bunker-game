# Main Menu + Surface Backdrop

**Read this before opening `scripts/ui/main_menu/*` or
`scripts/world/menu_backdrop/*`.** Covers the boot menu, the 3D "surface"
scene behind it, the asset slots waiting for human-made art, and the release
gates that keep AI-generated content out of the shipped game.

## Purpose

The game now boots into `scenes/ui/main_menu/MainMenu.tscn` (project
`run/main_scene`). A minimal, text-only menu column sits in the left third of
the screen over a live 3D view of the ruined surface above the bunker: grey
irradiated overcast, drifting ash, sheet lightning with delayed thunder,
rushing wind. The single warm light in the scene is the lamp over the bunker
entrance.

**Concept: the background is the bunker's exterior camera feed.** That is why
there is subtle film grain and a vignette over the 3D view (never over the
text), a small "SURFACE FEED · CAM 02" readout with live wind speed and the
system clock, and why the image briefly re-exposes after each lightning flash
the way a real camera would.

## Files

| File | Role |
|---|---|
| `scenes/ui/main_menu/MainMenu.tscn` | Boot scene: `BackdropHost`, `Interface/Screen`, `Curtain`. |
| `scripts/ui/main_menu/MainMenu.gd` | Orchestrator: threaded backdrop load, curtain, New Game / Continue / Load / Settings / Quit hand-offs, optional music. |
| `scripts/ui/main_menu/MainMenuScreen.gd` | All presentation: column layout, views (Home/Load/Credits), intro/outro, input, feed readout, UI sounds. |
| `scripts/ui/main_menu/MainMenuItem.gd` | Text-only `Button` with animated offset/brightness/arrow and optional caption. |
| `scripts/ui/common/FocusRail.gd` | The one focus indicator: rail + wash that glides with an elastic lead/trail (shared with Settings). |
| `scripts/ui/main_menu/MainMenuCredits.gd` | Credits view rendered live from `credits and attribution for bunkergame.txt`. |
| `assets/shaders/surface_feed_grain.gdshader` | Grain + vignette over the 3D view only. |
| `scenes/world/menu_backdrop/MenuBackdrop.tscn` | The surface scene: environment, lights, camera rig, storm, wind, ash, **asset slots**. |
| `scripts/world/menu_backdrop/MenuBackdrop.gd` | Backdrop root and its small public API (below). |
| `scripts/world/menu_backdrop/MenuCameraRig.gd` | Opening dolly, slow drift, pointer parallax, exit push-in. **No screen shake** (user decision, Sep 2026); `drift_degrees = 0` locks the camera. |
| `scripts/world/menu_backdrop/LightningStorm.gd` | Strike timing, flash envelope, sky/fog/ambient lift, re-exposure, thunder delay by distance. |
| `scripts/world/menu_backdrop/WindAmbience.gd` | Wind bed + gust layer; `gust` also drives ash speed and the feed readout's wind value. |
| `scripts/world/menu_backdrop/FlickerLamp.gd` | Waver and brown-out stutter for the entrance lamp. |
| `scripts/world/menu_backdrop/BackdropAssetSlot.gd` | One placement for one real asset; greybox in editor/debug only. |
| `assets/menu_backdrop/provenance.json` | Author/source/licence for every non-code asset the menu uses. |
| `tools/tests/main_menu_ui_smoke.gd` | Headless structure/behaviour smoke. |
| `tools/tests/check_menu_backdrop_slots.py` | Slot + provenance gate (`--release` blocks shipping). |

Touched elsewhere: `WorldManager.pending_load_slot`; `SaveManager` writes the
player body (`gender`) into save `_meta` and returns it from
`get_slot_info()`; `LoadingScreen` restores a pending slot after
`startup_ready`; character creation returns to the menu on Esc/B;
`GraphicsSettingsPanel.back_button_text`; the Linux export preset includes the
credits file.

## Public API

`MenuBackdrop` (any replacement backdrop scene must expose the same):
`set_pointer(v: Vector2)`, `skip_intro()`, `play_exit(seconds)`,
`get_flash() -> float`, `get_gust() -> float`, `signal struck(distance_km)`.

`MainMenuScreen`: `play_intro()`, `skip_intro()`, `is_intro_running()`,
`play_outro(seconds)`, `set_overlay_active(bool)`, `set_flash(f)`,
`set_gust(g)`, `refresh_saves()`, `release()`,
`signal action_requested(action: StringName, slot: int)` with actions
`new_game`, `continue`, `load_slot`, `settings`, `quit`.

## Runtime flow

1. `MainMenu._ready()` starts a threaded load of the backdrop and plays the
   intro immediately: the wordmark resolves from wide letter-spacing over
   black, the brass rule draws, items stagger in, focus lands on Continue
   (or New Game when there is no save).
2. When the backdrop is ready the curtain (currently *under* the UI) fades out
   over ~2.6 s while the camera finishes an 8 s dolly. Any key/click/button
   skips straight to the settled state. No backdrop within 8 s → menu shows
   anyway.
3. Leaving: the column falls away, camera pushes in and narrows, wind fades,
   the curtain moves *over* everything and fades to black, then the scene
   changes. Quit is two-step ("Press again to quit", 3 s window).
4. Continue/Load: restores `CharacterCreationData.gender` from the slot, sets
   `WorldManager.pending_load_slot`, goes to `LoadingScreen`, which loads the
   save into the fresh world before revealing it.

## Design rules (standing)

- **Text-only menu, no icons.** Hierarchy comes from type, spacing, alpha and
  one blue selection rail. Keeps the menu free of artwork entirely.
- The game is called **Bunker Game**. The wordmark auto-fits the column
  (`wordmark_max_size`, `WORDMARK_TRACKING`), so any title length works.
- Palette is `BunkerDesign`: ivory text, blue selection, brass structure,
  red only for the Quit confirmation. Font is the project's Iosevka Charon.
- One current item for all devices: hover moves focus. Focus wraps.
- Every motion reads `UIMotion.reduced()`; reduced motion removes intro, dolly,
  drift, parallax, grain animation, restrokes and lamp stutter.
- Lightning is capped at 3 flashes/second (WCAG 2.3.1); reduced motion turns
  a strike into one slow swell.
- Small type has floors (12 px captions) so 720p stays legible.
- The menu honours the player's graphics settings live (volumetric fog, SSAO,
  glow) but never enables SDFGI/SSIL for the exterior.

Layout knobs (Inspector on `Interface/Screen`): `column_left_fraction`
(0.085 = column starts 8.5% in, occupies the left third), `column_width`,
`title_top_fraction`, `wordmark`, `tagline` (empty on purpose), feed label,
grain amount, UI sounds.

## Scene map (top-down, metres; camera at x −1.5, z +9 looking −Z)

```
 z      LEFT FLANK (low, dark: behind the menu)     RIGHT FLANK (carries the frame)
-350                 Skyline1..7  (silhouettes, x −230 … +260, 28–88 m tall)
-160          RuinCentreFar (street vanishing point)
-125                                                         SkylineTower ★ (x 48, 64 m)
 -76  RuinLeft3 (13 m)                               RuinRight3 (9 m)
 -42  RuinLeft2 (8 m)                                RuinRight2 (12 m)
 -24                                          LeaningPole (diagonal)
 -17                WreckedCar
 -15  RuinLeft1 (4.5 m)                                      HeroFacadeRight (17 m, cropped)
  -6  RubbleLeft                     BunkerEntrance ☼ (warm lamp)  RubbleRight
  +9                    ▲ camera
```

Composition intent: the street leads the eye from the menu into the fog; the
snapped tower sits on the right-third line against the brightest sky; the
entrance lamp is the only warm value, low right. Keep the left flank low and
low-contrast so the menu text never fights architecture. Lightning comes from
behind the right-hand skyline (backlit silhouettes).

## Asset intake: replacing a greybox

1. Model in Blender at real scale (1 unit = 1 m). **Origin at ground contact,
   bottom-centre. Front faces +Z (towards the camera).** Apply transforms.
2. Export glTF 2.0 (`.glb`) into `assets/models/menu_backdrop/`.
3. In Godot: select the slot node → Inspector → `asset_scene` = your `.glb`
   (or a wrapper `.tscn`). Its `greybox_size` shows the massing you are
   replacing; `brief` says what the slot is for. Move/rotate the slot freely.
4. Add an entry to `assets/menu_backdrop/provenance.json`.

Budgets (the menu is one static view; spend where the camera looks):

| Tier | Slots | Triangles | Textures |
|---|---|---|---|
| Hero | HeroFacadeRight, BunkerEntrance, WreckedCar, RubbleLeft/Right | 30–80k | 2K, 2–3 materials |
| Mid | RuinRight2/3, RuinLeft1–3, LeaningPole, RuinCentreFar | 8–25k | 1K or shared trims |
| Silhouette | SkylineTower, Skyline1–7 | 1–6k | 512 / flat or vertex colour |
| Ground | Ground | tiling | 2K tiling set + a few decals |

Texturing approach that suits the look: a concrete **trim sheet** for facades
(slab edges, window reveals, spalled corners), tiling broken concrete and
asphalt, and vertex-colour masks for soot/ash so one material covers many
buildings. Keep albedo mid-dark and roughness high; the fog and overcast do the
mood. Leave windows dark (a dead city); interior depth reads better than any
light. Enable "Generate LODs" on import; add visibility ranges to the skyline
if it grows heavy. Photo-sourced CC0 libraries (Poly Haven, ambientCG) are
human-made scans, but verify each asset page, since some sites now also host
generated content.

**Sky:** assign an equirectangular overcast image (photographed HDRI or your
own paint-over) to `MenuBackdrop.sky_panorama`. It replaces the procedural
gradient and drifts via `cloud_drift_deg_per_sec`.

**Audio** (all optional; the scene is complete but silent without them):
`Wind.bed_stream` (seamless 30–90 s stereo OGG, loop on), `Wind.gust_stream`
(howl layer, loop on), `Storm.thunder_streams` (3–6 one-shots near to far;
pitch/volume are distance-scaled automatically), `Interface/Screen`
move/confirm/back sounds, `MainMenu.music`. The credits file already lists
suitable CC0 freesound recordings (e.g. BlueDelta's thunder), which still need
adding to the repo.

## Compliance: Steam AI disclosure

Goal: the shipped game contains **no AI-generated content** (art, models,
textures, audio, voice, narrative/marketing text).

- This system's code (GDScript, one canvas shader, scene files) was written
  with an AI coding assistant. As of Valve's early-2026 wording, the Steam
  content survey concerns AI-generated *content* shipped to players, not
  development tools such as code assistants. Confirm against the live
  Steamworks form before submitting; Valve can change it.
- No images, models, textures or sounds were generated. Everything visible is
  rendered at runtime by engine features (lights, fog, particles, gradients,
  text) configured in code. The greybox blocks exist only in the editor and
  debug builds; **release exports never build them**.
- Player-facing text written here is functional (menu labels) plus two flavour
  strings you may want to rewrite yourself: `feed_label`
  ("SURFACE FEED · CAM 02") and the "Press again to quit" prompt. `tagline` is
  intentionally empty.
- Gates before any release build:
  `python3 tools/tests/check_menu_backdrop_slots.py --release` (all slots
  filled with provenance) and `python3 tools/tests/check_ui_placeholders.py
  --release` (existing AI placeholder icons removed).

## Validation

```bash
godot --headless --path . --script res://tools/tests/main_menu_ui_smoke.gd
python3 tools/tests/check_menu_backdrop_slots.py
```

The smoke covers the backdrop API, slot briefs, the lightning flash-rate cap,
Continue visibility, focus wrap, Load/Esc navigation, two-step Quit, credits
parsing and column placement at 720p/1440p/ultrawide. Visual sign-off still
needs the real renderer.

## Known tradeoffs / future work

- There is no "Exit to Main Menu" in the pause menu yet: returning needs a
  clean MainWorld teardown (autoload state, registered save fields). Scope it
  separately.
- Settings reuses `GraphicsSettingsPanel` as an overlay; audio/controls
  settings do not exist yet.
- The ash uses an engine gradient sprite; swap in a hand-made flake texture
  later if desired.
- Scripts deliberately have no `class_name` (the project's class-cache gotcha);
  they are referenced by path.
