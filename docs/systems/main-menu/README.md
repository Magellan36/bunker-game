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
| `scripts/world/menu_backdrop/MenuCameraRig.gd` | Opening dolly, pointer parallax, exit push-in. **No screen shake and no idle drift** (user decision, Sep 2026: the old noise drift read as shake and was removed). |
| `scripts/world/menu_backdrop/LightningStorm.gd` | Strike timing, flash envelope, sky/fog/ambient lift, re-exposure, thunder delay by distance. |
| `scripts/world/menu_backdrop/WindAmbience.gd` | Wind bed + gust layer; `gust` also drives ash speed and the feed readout's wind value. |
| `scripts/world/menu_backdrop/FlickerLamp.gd` | Waver and stutter for the entrance lantern's light; drives the glass glow (`glow_material`). |
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

1. `MainMenu._ready()` starts a threaded load of the backdrop (parallel
   sub-threads, **v-sync off until it is ready**) and plays the intro
   immediately: the wordmark resolves from wide letter-spacing over black,
   the brass rule draws, items stagger in, focus lands on Continue (or New
   Game when there is no save).
2. When the backdrop is ready, v-sync goes back to the player's setting, two
   frames render behind the curtain (pipeline warm-up hitches), then the
   curtain (currently *under* the UI) fades out over 0.5 s while the camera
   finishes an 8 s dolly. Any key/click/button skips straight to the settled
   state. No backdrop within 8 s → menu shows anyway.

   Why v-sync is off during the load: with it on, every GPU texture upload
   waits for a displayed frame (~75 ms per texture on the RX 580; the
   backdrop has ~140 textures), so the load took 6–8+ s. With it off and
   sub-threads on it takes ~0.8–2.5 s depending on machine load. The screen
   is black during the load, so there's no visible tearing.
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

Buildings pass (2026-09-27): unique hero and skyline models, a sparser
street, the big Majadroid blocks deep in the fog. Clutter pass (same day):
the entrance is an industrial storage cart with a lantern on it (the only
warm light), two collapsed-structure ruins in the mid-ground, a second
skyline band 500–560 m out, the plain intact block replaced, the raised
shack removed, and ~160 pieces of thrown debris scattered across the whole
view. Only WreckedCar and LeaningPole are still greybox (no models yet).

```
 z      LEFT FLANK (low, dark: behind the menu)     RIGHT FLANK (carries the frame)
-560    FarTower01 (x −175)                FarTower05 (x 60)      FarTower02 (x 205)
-500  FarPancake (x −300)                                                FarTower06 (x 330)
-430      Skyline3 (leaning 03 ruin)
-420                                                   Skyline5 (06, 92 m, x 175)
-405   Skyline2 (05, 72 m, x −150)
-380                                    Skyline4 (02, 86 m, x 40)
-330                                                          Skyline6 (01, 86 m, x 245)
-320  Skyline1 (03, 66 m, x −235)                  SkylineTower ★ (07, 129 m, x 120)
-290            RuinCentreFar (04, 58 m, street vanishing point)
 -66  CollapseLeft (low)
 -52                                                    CollapseRight (columns, slab, stairs)
 -24                                          LeaningPole (diagonal, greybox)
 -17                WreckedCar (greybox)
 -15  RuinLeft1 (low shack)                                  HeroFacadeRight (Malik ruin, 18 m, cropped)
  -6  RubbleLeft                     BunkerEntrance ☼ (cart + lantern)  RubbleRight
  +9                    ▲ camera
       + MenuClutter: thrown debris 11–480 m out (see below)
```

| Slot | Content | Source |
|---|---|---|
| HeroFacadeRight | `ruin_malik_facade.glb` (6k tris, 2K) | Daniyal Malik, Sketchfab |
| RuinLeft1 | `shack_low.glb` (1K) | SurvivalWood package |
| SkylineTower, RuinCentreFar, Skyline1/2/4/5/6 | `tower_majadroid_07/04/03/05/02/06/01.glb` | Majadroid, CC0 |
| Skyline3, FarPancake, FarTower01/02/05/06 | `scenes/world/menu_backdrop/ruins/*.tscn`: mirrored, turned, leaning or half-buried towers on wreckage mounds; a pancake of floor slabs | Majadroid, CC0 |
| CollapseRight / CollapseLeft | `ruins/ruin_collapse_*.tscn`: Destroyed City columns (scaled), debris, rocks, road slabs, a Majadroid floor slab and fire stairs | Destroyed City Assets + Majadroid |
| RubbleLeft / RubbleRight | `ruins/rubble_*.tscn` | as above, plus Poly Haven tyre / jerrycan |
| BunkerEntrance | `entrance_cart.tscn` (the cart, shadow casting off so the lantern pool reaches the ground) + `EntranceLantern` + `EntranceLight` | Poly Haven, CC0 |

Distant slots set `cast_shadows = false` (BackdropAssetSlot): fogged
silhouettes gain nothing from shadows but cost shadow-map draws.

**The lantern light** (`EntranceLight`) is the old wall lamp's light,
unchanged (colour, energy 2.6, range 9, attenuation 1.4, shadows,
volumetric fog 2.2), moved to the lantern's glass on the cart's top tray.
`FlickerLamp.glow_material` makes the glass (`lantern_glass_lit.tres`)
brighten and dim with it; the lantern mesh casts no shadow so its own frame
doesn't block the light.

**Clutter** (`MenuClutter.tscn`, baked by
`tools/menu_backdrop/bake_menu_clutter.gd`, fixed seed): Poly Haven props
and Destroyed City pieces thrown by the blast — upright with a lean, on
their sides, upside down, or tilted and half-buried, resting on the baked
terrain and following its slope. Small props sit 11–48 m out, medium
12–130 m, boulders and ruin pieces up to ~480 m (scaled up with distance so
they still read). 60% land in debris fields stretched along the blast
direction. It keeps clear of slot footprints, most of the near street, and
the area behind the menu text. Tune `ITEMS` (weights, allowed poses) and
`BANDS` (count, distance, scale), then re-run it. Pieces rest on the lowest
ground under their whole footprint. `OVERRIDES` hand-corrects named pieces
without changing the layout: the cash register by the cart lies on its back,
and a single concrete cat statue sits upright in the lantern's glow,
lower-left of the cart. It's an Easter egg; the other cats are left out.

Grounding: terrain pads cover each slot's full base diagonal. The Malik ruin
sits at y −1.25 because a few stray vertices hang 1.2 m below its real base.
Ground specular 0.08 (dry dust, no sheen). Fog: density 0.0046, volumetric
0.011, so the mid-ground ruins (55–75 m) keep their value.

Composition intent: the street leads the eye from the menu into the fog; the
snapped tower sits on the right-third line with its broken notch turned to
camera; the lantern is the only warm value, low right. Keep the left
flank low and low-contrast so the menu text never fights architecture.
Lightning comes from behind the right-hand skyline (backlit silhouettes).

Rebuilding after changes (in order):
1. `blender -b --factory-startup --python tools/menu_backdrop/export_buildings.py`
   (buildings; Blender 4.x is fine).
2. `~/blender-5.1.2-linux-x64/blender -b --factory-startup --python tools/menu_backdrop/export_clutter.py -- <dir with each clutter .blend.zip unzipped into <name>/>`
   (clutter + ruin pieces as glTF with JPEG textures; several Poly Haven
   files need Blender 5.1+).
3. `python3 tools/menu_backdrop/make_ruin_scenes.py` (ruin layouts).
4. `godot --headless --path . --script res://tools/menu_terrain/bake_menu_terrain.gd`
   (terrain pads follow the slots).
5. `godot --headless --path . --script res://tools/menu_backdrop/bake_menu_clutter.gd`.

Import settings: every texture under `assets/models/menu_backdrop/` is VRAM
compressed with mipmaps (normal maps flagged). Lossless textures made the
backdrop take 4.3 s to load; it now loads in about 1.6 s on a background
thread. The Destroyed City pieces have no textures of their own; their
materials are remapped in each `.gltf.import` to `materials/ruin_*.tres`
(triplanar CC0 concrete/rust from the Majadroid pack).

Performance (RX 580, 1080p, volumetric fog on): about 57 fps with
everything. The terrain doesn't cast shadows and its shader uses 16
texture samples per pixel.

## Terrain (Ground slot)

The ground is a baked heightfield, not a flat plane: a sunken gravel street
that curves gently toward the vanishing point, eroded ditches and low berms
along both sides, six craters with raised rims, mounds that rise into hills
away from the street, and a low far ridge (z ≈ −215) that hides the skyline's
feet. Every other slot gets a level pad, so buildings and props sit flat. The
foreground stays gentle near the camera.

| File | Role |
|---|---|
| `scripts/world/menu_backdrop/MenuTerrainBuilder.gd` | The shape rules (street, ditches, craters, hills, ridge, pads) and per-vertex layer weights. |
| `tools/menu_terrain/bake_menu_terrain.gd` | Measures every slot's footprint, runs the builder, and saves `assets/menu_backdrop/terrain/menu_terrain.res`. **Re-run after moving, resizing or filling slots.** |
| `tools/menu_terrain/pack_ground_textures.py` | Repacks the ambientCG zips into `assets/menu_backdrop/ground/<layer>/` (`albedo.jpg`, `normal.png`, `ord.png` = AO/roughness/height). |
| `assets/shaders/menu_ground.gdshader` | Weaves the four sets. |
| `scenes/world/menu_backdrop/MenuTerrain.tscn` | Mesh and material; the Ground slot's `asset_scene`. Authored in world space, so the Ground slot stays at the origin. |

How the four ground sets are woven:

| Layer | Set | Where it shows |
|---|---|---|
| earth | Ground067 | the base everywhere |
| gravel | Ground062S | the street bed, fraying at its edges; a little around pads |
| debris | Ground073 | ditches, crater bowls, hollows, slopes, wandering patches |
| brick | Ground111 | rings around ruins, crater rims, scattered patches |

Seams use each set's own height map, so stones poke through dirt rather than
cross-fading. A second, rotated, larger sample hides tiling, a slow value
drift breaks up the open ground, and settled ash dusts up-facing surfaces.
Grade knobs (`albedo_gain`, `saturation`, `ash_amount`, tile sizes) are
shader parameters on the material in `MenuTerrain.tscn`.

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
| Hero | HeroFacadeRight, WreckedCar | 30–80k | 2K, 2–3 materials |
| Mid | RuinLeft1–2, LeaningPole | 2–25k | 1K or shared trims |
| Distance | SkylineTower, RuinCentreFar, Skyline1–6 | 4–45k (fogged) | 1K |
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
- Ground (Sep 2026): the four ground texture sets are ambientCG materials
  (CC0 per their bundled metadata; the embedded XMP names Adobe Substance
  Designer as the authoring tool). They're recorded in `provenance.json`;
  confirm the creation method on each ambientCG page before release. The
  terrain *shape* is produced by project code from hand-written rules plus the
  engine's FastNoiseLite: deterministic procedural generation, not a
  generative-AI model. The same is true of the weave noise (`NoiseTexture2D`).
- Clutter (Sep 2026): 24 Poly Haven models (CC0; Poly Haven credits a human
  artist on every asset page), the Destroyed City Assets pack (author and
  licence unknown, marked CONFIRM so the release gate stays closed) and
  Majadroid ruin pieces (CC0). Placement is rule-based code with a fixed
  seed, not generative AI. The Majadroid billboards were not used: their
  texture shows real brand names ("Sunpower", "OCP"). Towers 03 and 06 carry
  small billboards in that texture, illegible at 300+ m in fog; swap that
  material before release if in doubt.
- No images, models, textures or sounds were produced by generative AI. Everything visible is
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
