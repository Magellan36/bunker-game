# Handover — Player Model: Male Body + Idle/Walk/Run Import (Aug 2026)

## What changed this session
New Player-Model subsystem: the player's visual body is no longer the
placeholder `CapsuleMesh` but a real Mixamo-rigged male character with
idle/walk/run locomotion animation. `assets/models/WIP/FINAL/Male
Locomotion Pack/`'s `male.fbx` + `idle.fbx` / `walking.fbx` / `standard
run.fbx` were moved to `assets/models/player/` (renamed walk.fbx/run.fbx)
— the only WIP assets this pass touched; the rest of WIP is untouched.
Verified against the two other male candidates in WIP (Farming Pack male
is a different retarget session, Quaternius Superhero rig is non-Mixamo).
New `scenes/player/PlayerModel.tscn` (instances male.fbx + an
`AnimationPlayer` with three `AnimationLibrary` resources under
`assets/models/player/anims/`) + `scripts/player/PlayerModelController.gd`
(layer/shadow-cast exclusion for all meshes, root-motion fallback,
idle/walk/run selection from real velocity). `Player.gd` lost 3 lines
(mesh onready var + layer/shadow-cast setup) — now owned by the
controller; `CharacterShadowStandIn.attach(self)` unaffected (only reads
$CollisionShape3D).

## Things to know / flags
- The animation libraries were generated headlessly (clip animations are
  named `mixamo_com` inside the FBX; the extraction/rebasing/loop baking
  lives in `tools/build_player_model.gd`). Animation names in the wrapper
  are `idle_lib/idle`, `walk_lib/walk`, `run_lib/run` (separate
  AnimationLibrary files force the prefix) — `PlayerModelController.gd`
  maps plain state names to these. Track paths were rebased to the
  wrapper hierarchy (`MaleModel/Skeleton3D:...`) since AnimationMixer
  resolves tracks relative to the AnimationPlayer's parent, and the
  wrapper's AnimationPlayer must stay the FIRST child of PlayerModel (the
  imported FBX scene carries its own internal AnimationPlayer — see
  `docs/systems/player-model/README.md`).
- In-editor verification checklist (plan's Part 9) still to run: model
  visible + scaled, feet on floor, idle/walk/run track correctly, shadow
  stand-in intact, flashlight no longer self-shadows.

# Handover — Dish Item: Random Model Pool + Soup-Name Override (Aug 2026)

## What changed this session
DishItem now picks one of 5 real models at spawn: `plate-dinner.glb` /
`plate-sauerkraut.glb` (always eligible), `skewer.glb` /
`skewer-vegetables.glb` (no-water dishes only), and `bowl-soup.glb`
(forced whenever `dish_name` contains "Soup"/"Broth"/"Stew"/"Chowder" —
checked BEFORE and independent of the water/no-water pool, since several
Soup-named recipes don't actually use a water_bottle ingredient; also a
random 3rd option in the water pool for the currently-unreached case of
a hydrating dish that isn't liquid-named). The spawn-ordering bug that
the previous DishItem session fixed (dish_name/hydration_value set after
add_child(), which fires _ready() synchronously) was already resolved at
all 3 spawn sites in that prior commit — this session verified it's in
place and built the soup override on top; if it had been left unfixed it
would have broken BOTH the water-pool logic AND the new soup-name
override. Two separate scale constants: `MODEL_SCALE` (0.4261) for the
plate/skewer pack (confirmed shared source units via matching radii),
`BOWL_SOUP_SCALE` (0.7024) computed independently for bowl-soup.glb
since it wasn't confirmed to share those units.

### Files modified
- `assets/models/bowl-soup.glb` — new asset (texture NOT yet provided —
  see note below). (The 4 plate/skewer assets landed in the prior Dish
  Item session.)
- `scripts/world/items/DishItem.gd` — `_build_dish_visual()` rewritten
  with the soup-name override + per-model scale selection; new
  `BOWL_SOUP_SCALE`, `MODEL_BOWL_SOUP`, `SOUP_LIKE_NAME_KEYWORDS`
  constants; `bowl-soup.glb` added to `MODELS_WITH_WATER`.
- `docs/systems/build/README.md` — Dish Item subsection updated for the
  soup override + 5th model.
- `HANDOVER.md` — this entry.

### ⚠️ Outstanding — textures needed
All 5 `.glb` files reference `Textures/colormap.png` by external
relative path, same as `can.glb`. No texture file was provided this
session for any of them. Models will render broken/missing-texture
until Brannon supplies them and they're placed correctly under
`assets/models/`.

### Verification checklist
1. `tools/godot_check.sh` passes.
2. Cook and take any Soup/Broth/Stew/Chowder-named dish (e.g. "Tomato
   Basil Soup", which has NO water ingredient) — always shows
   `bowl-soup.glb`, never a plate or skewer, confirming the override
   beats the water/no-water pool rather than being subsumed by it.
3. Cook and take a non-liquid-named dish WITH water (if the recipe table
   ever adds one) — random among plate-dinner/plate-sauerkraut/bowl-soup.
4. Cook and take a non-liquid-named dish WITHOUT water — random among
   all 4 plate/skewer variants across repeated tries, never bowl-soup.
5. NPC-cooked dishes (`CookingActivity`) — same override + pool behavior
   as the player path.
6. Collision/pickup radius unchanged regardless of which model rendered.
7. Once textures are supplied: visually confirm no pink-checkerboard/
   missing-texture material on any of the 5.

# Handover — Dish Item: Procedural Mesh → Random GLB Model Pool (Aug 2026)

## What changed this session
`DishItem.gd`'s placeholder plate+mound (procedural `CylinderMesh` +
`SphereMesh`) is gone. `_ready()` now builds collision (unchanged
`SphereShape3D` radius 0.12 at (0, 0.05, 0)) and calls a new
`_build_dish_visual()` that randomly picks ONE of 4 real models based on
`hydration_value`: dishes WITH water → the 2 plates (`plate-dinner.glb`,
`plate-sauerkraut.glb`); dishes WITHOUT water → all 4 (both plates PLUS
`skewer.glb` and `skewer-vegetables.glb`). Skewers are ADDITIONAL
no-water options, not a replacement set. Uniform scale `0.4261`
(plate radius 0.4459, so one factor fits all axes). All 4 assets were
verified by direct GLB inspection (identity top-level MeshInstance3D,
plate radius/heights, skewer multi-part children with intentional
offsets) — `_recenter_glb_mesh()`'s stop-after-first-match is what keeps
the multi-part skewers' artist-positioned "meat"/"vegetables" children
intact; do not generalize it.

### Critical bug fixed (same session) — spawn-ordering
The visual pick reads `hydration_value` in `_ready()`, which Godot fires
synchronously inside `add_child()` — but all 3 dish-spawn sites assigned
`hydration_value`/`fill_value`/`bonus_pct`/`dish_name` AFTER the
`add_child()` call, so `_ready()` always saw the default `0.0` and every
dish would have rendered as a plate (the old code had no visual
dependence on these values, which is why the latent bug went unnoticed
until now). Fixed by moving the 4 assignments before `add_child()` at
all 3 sites: `InteractionSystem._try_take_dish()`,
`InteractionSystem._try_take_dish_from_held_pot()`, and
`CookingActivity._take_dish()` (mirrors the player flow exactly).

### ⚠️ Textures outstanding (NOT blocked, but unverified)
All 4 GLBs reference `Textures/colormap.png` externally — the same
shared swatch atlas the pot/food-can use, already committed under
`assets/models/Textures/`. The dish pack shipped without per-model
texture files, so imports resolve against the shared atlas. Whether the
shared atlas' swatch layout matches the plates'/skewers' UVs must be
confirmed in-editor (checklist item 7) — the plan author expected these
to render broken; if they look wrong, provide the pack's own
`colormap.png` (or re-swatched copies) and re-import.

### Files modified
- `assets/models/plate-dinner.glb`, `plate-sauerkraut.glb`,
  `skewer.glb`, `skewer-vegetables.glb` — new assets (copied from
  `F:\Bunker Game\models\GLB format\`, no generation performed).
- `scripts/world/items/DishItem.gd` — `_ready()` rewritten; new
  `MODEL_SCALE` const + `MODELS_WITH_WATER`/`MODELS_WITHOUT_WATER`
  pools + `_model_node` var; new `_build_dish_visual()`,
  `_build_collision()`, `_strip_model_collision()`,
  `_recenter_glb_mesh()`; `_build_placeholder_mesh()` removed.
- `scripts/player/InteractionSystem.gd` — `_try_take_dish()` and
  `_try_take_dish_from_held_pot()`: property assignments moved before
  `add_child()`.
- `scripts/npc/activities/CookingActivity.gd` — `_take_dish()`: same
  reordering.
- `docs/systems/build/README.md` — new "Dish Item" subsection.

### Verification
Import + headless parse clean. In-game checklist items 2–7 (model
variety, water/no-water weighting, eat/drop flows) are Brannon's.

# Handover — Food Can: Procedural Mesh → can.glb / can-empty.glb (Aug 2026)

## What changed this session
Replaced FoodCan's `.tscn`-authored `CylinderMesh` with two real models,
swapped in code based on `_is_empty`: `can.glb` (full) and
`can-empty.glb` (empty). The empty variant didn't exist as a separate
source file — it was generated by tracing the mesh's actual UV
coordinates to identify exactly which texture swatch is the red label
(a flat swatch-atlas texture, not a painted label — see
`docs/systems/models/glb-swatch-texture-editing.md`), then replacing
that swatch with an already-unused grey gradient from elsewhere in the
same texture column, so the new grey is sourced from the can's own
existing palette rather than invented. `_become_empty()` changed from a
`material_override` tint hack to swapping the whole model. Scale is
constrained non-uniform — uniform on X/Z (keeps the can circular),
separate on Y. Confirmed via code trace (not just assumed) that the
CookingPot ingredient-icon preview still works with the mesh now built
in `_ready()` rather than authored in the `.tscn` — that preview path
was previously broken for a DIFFERENT reason (`is_script` mode
bypassing the `.tscn` file entirely), which doesn't apply to this
change.

### Files modified
- `assets/models/can.glb`, `can-empty.glb` — new/generated assets.
- `scripts/world/items/FoodCan.gd` — `_ready()`, `_become_empty()`
  replaced; new `_update_can_visual()`, `_strip_model_collision()`,
  `_recenter_glb_mesh()`.
- `scenes/world/FoodCan.tscn` — `MeshInstance3D`/`CylinderMesh` removed,
  `CollisionShape3D` unchanged.
- `docs/systems/models/glb-swatch-texture-editing.md` — new.
- `docs/systems/build/README.md` — new Food Can subsection.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes.
2. Pick up a full Food Can — renders `can.glb`, label visible, correct
   size (matches old placeholder's footprint).
3. Eat both bites — on the 2nd, visual swaps to `can-empty.glb` (grey,
   no label), no material-tint flash beforehand.
4. Shelf stacking (6 per slot, two rows of 3) — still looks correct at
   the new model's scale, nothing overlapping/floating.
5. Add a Food Can to the Cooking Pot as an ingredient — the pot's
   ingredient icon slot shows the can correctly (verifies the
   `InteractPrompt.gd` scene-mode preview path still works with the
   code-built mesh).
6. Trash/Cleaning system — `get_trash_material()` still correctly reports
   "metal" once empty (unaffected by this change, sanity check only).

---

# Handover — Cooking Pot: 90° Model Rotation Fix (Aug 2026)

## What changed this session
Added a 90° Y-axis rotation to the Cooking Pot's swapped visual model
(`_update_pot_visual()` in `CookingPot.gd`) — the imported model's
handles were facing the wrong way relative to the game's expected
orientation. Single-line fix, applied once in the shared model-load
function so it automatically covers all 4 fill-state models (empty +
3 stew levels) rather than needing repeating per state.

### Files modified
- `scripts/world/items/CookingPot.gd` — `_update_pot_visual()`.
- `docs/systems/build/README.md` — correction note appended.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes.
2. Pick up a pot — handles now face the correct direction relative to
   however "front" is read in-game (matches what Brannon confirmed
   visually).
3. Cycle through all 4 fill states (add/remove ingredients) — rotation
   is consistent across every state, not just the empty one.

---

# Handover — Cooking Pot: Procedural Mesh → 4-State GLB Model (Aug 2026)

## What changed this session
Replaced CookingPot.gd's static procedural placeholder mesh with 4 real
models swapped live based on ingredient count: `pot.glb` (empty),
`pot-stew-1/2/3.glb` (1/2/3 ingredients, stew level visibly rising).
The 3 stew-level variants didn't exist as separate source files — they
were generated by diffing the provided `pot.glb`/`pot-stew.glb` pair at
the vertex level (234 vertices exist only in the stew version — a fused
liquid disc) and translating just those vertices to 3 interpolated
heights, leaving the pot body/UVs/material/texture completely untouched.
Technique documented at
`docs/systems/models/glb-stew-level-generation.md` for reuse if
CAPACITY ever changes or another container needs the same treatment.
Scale is uniform (`0.8315`) — the pot's collision is a
`CylinderShape3D`, so unlike Table/Chair there's no axis-aligned
footprint forcing a non-uniform fit, and uniform scaling avoids
distorting the asset for no reason. Collision itself is unchanged
(same radius/height as before), now built once and decoupled from the
swappable visual child.

### Files modified
- `assets/models/pot.glb`, `pot-stew-1.glb`, `pot-stew-2.glb`,
  `pot-stew-3.glb` — new/generated assets.
- `scripts/world/items/CookingPot.gd` — `_build_placeholder_mesh()`
  removed; new `_build_collision()`, `_update_pot_visual()`,
  `_strip_model_collision()`, `_recenter_glb_mesh()`; visual-update call
  added to `try_add_item()` (both branches), `remove_item()`,
  `serve_dish()`, `restore_saved_state()`.
- `docs/systems/models/glb-stew-level-generation.md` — new.
- `docs/systems/build/README.md` — new Cooking Pot subsection.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes.
2. Pick up an empty pot — renders `pot.glb`, no stew visible.
3. Add 1 ingredient — visual swaps to `pot-stew-1.glb`, stew visible low
   in the pot.
4. Add a 2nd — swaps to level 2, stew visibly higher.
5. Add a 3rd (full) — swaps to level 3, stew near the rim.
6. Remove an ingredient (if a removal path is exercised anywhere) — visual
   drops back down a level.
7. Cook and take the dish (`serve_dish()`) — pot visually empties back to
   `pot.glb`.
8. Save/load mid-fill (e.g. 2 ingredients in the pot) — reloaded pot shows
   the level-2 model immediately, not empty (`restore_saved_state()`'s
   new call).
9. Ingredient icon row (`get_slot_icon_descriptors()`) still renders
   correctly — unaffected by this change, sanity check only.
10. Collision still blocks/pickup-range still works identically to before
    (same CylinderShape3D, now just built at a different point in
    `_ready()`).

---

# Handover — Chair: Procedural Mesh → wooden_chair.glb (Aug 2026)

## What changed this session
Replaced Chair.gd's procedural leg+seat+backrest mesh with
`assets/models/wooden_chair.glb`. Non-uniform scale
`(0.8946, 0.7102, 0.7667)` applied (source proportions didn't match the
0.625×1.125×0.625 target closely enough for uniform). Facing verified via
raw vertex inspection (backrest-height vertices are on the source's own
-Z side, matching Chair.gd's actual convention) — no rotation applied.
Same glTF-import wrapper-node fix as the Medium Table
(`_recenter_glb_mesh()`) applied here too — this source file also had a
stray node-level translation, `(-4.1, 0, 0.8)`. The model's raw bounding
box is asymmetric on Z (backrest extends further one way than the seat
front) — this is normal chair geometry, not corrected, don't "fix" it if
revisiting this file.

### Files modified
- `assets/models/wooden_chair.glb` — new asset.
- `scripts/world/furniture/Chair.gd` — `_build_mesh()` replaced, new
  `_strip_model_collision()` + `_recenter_glb_mesh()`.
- `docs/systems/build/README.md` — Furniture section updated.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes.
2. Construct → Furniture → Chair: preview shows the real wooden chair,
   centered, not offset.
3. Place a Chair, sit (E) — player faces the same direction the backrest
   implies (away from the backrest, over the open +Z front) same as
   before the swap.
4. Multiple chairs placed at different rotations — backrest orientation
   rotates correctly with the object (sanity check that no fixed-world
   rotation was accidentally baked in instead of relying on the object's
   own transform).
5. Collision still blocks at the same 0.625×0.625 footprint.

---

# Handover — Storage Preview Zoom-Out Fix (Aug 2026)

## What changed this session
Storage UI previews (Shelving/Basket/End Table/Dresser — all share one
call site in StorageUI.gd) were clipping the viewport edge, especially
on larger items. Added an optional `cam_size_multiplier` parameter to
`ItemPreviewKit.build_viewport()` (default 1.0, so Inventory's proven
zoom is untouched) and set StorageUI's call to 1.25 — a 25% zoom-out
applied uniformly across every storage type from this one change.

### Files modified
- `scripts/ui/common/ItemPreviewKit.gd` — new optional parameter.
- `scripts/ui/inventory/StorageUI.gd` — one call-site update.
- `docs/systems/ui/README.md` — addendum to the preview kit section.

### Verification checklist
(see `STORAGE_PREVIEW_ZOOM_OUT_PLAN.md` for the full checklist)

---

# Handover — Character Shadow Stand-In: Shorter — HEIGHT_FACTOR 0.3 (Aug 2026)

## What changed this session
`CharacterShadowStandIn.HEIGHT_FACTOR` lowered to `0.3` — a further step
down from the `0.35` pass earlier this session (the full arc is now
`0.5 → 0.35 → 0.3`) — per direct request for a shorter character shadow
at any given light angle. Single-constant change — no structural or
logic changes, no other file touched besides docs.

### Files modified
- `scripts/core/CharacterShadowStandIn.gd` — `HEIGHT_FACTOR` constant
  and its doc-comment.
- `docs/systems/graphics/README.md` — "Character shadow stand-in"
  section updated to reflect the new value.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Load a scene with a character near a light (WallLight or Flashlight),
   observe the shadow — should be visibly shorter than the `0.35` pass
   at the same light angle/distance.
3. Confirm the shadow's base still lands at the character's actual floor
   contact point (no floating/detached shadow) — the `y_offset` math is
   unchanged, only `HEIGHT_FACTOR` itself moved, so this should hold
   automatically, but visually confirm.
4. Confirm no other visual regression on the character's own mesh
   (`cast_shadow = OFF` on the real mesh is untouched by this change).

---

# Handover — wooden_table.glb Off-Center Fix (Aug 2026)

## What changed this session
Fixed the Medium Table / Build Station's new wooden_table.glb model
rendering ~1m off-center (reported: "shifted about half a table-width to
the left"). Root cause: Godot's glTF importer wraps an imported scene in
a generated root node representing the file's "Scene" — the file's real
node (here, the mesh-bearing `table01` node, which carries a stray
`(-1.7, 0, 0.7)` scene-placement translation unrelated to the mesh's own
shape) is nested one level BELOW that wrapper. The prior session's fix
zeroed the wrapper's position (`packed.instantiate()`'s return value) —
already zero, a no-op — leaving the inner node's real offset untouched,
which then got multiplied through by the applied scale. New
`_recenter_glb_mesh()` (duplicated in both `Table.gd` and
`BuildStation.gd`, matching the existing `_strip_model_collision()`
duplication convention) walks down to the actual `MeshInstance3D` and
zeros its local position directly.

### Files modified
- `scripts/world/furniture/Table.gd` — new `_recenter_glb_mesh()`, call
  added in `_build_mesh_from_model()`.
- `scripts/world/furniture/BuildStation.gd` — same, in `_build_mesh()`.
- `docs/systems/build/README.md` — correction note appended.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Place a Medium Table — model renders centered on the placement
   position/ghost, no left/forward offset.
3. Build Station — table portion centered; blueprint rolls/toolbox still
   sit correctly on top of it (unaffected by this fix, sanity-check only).
4. Small Table (1×1) — still unaffected (procedural, never touched this
   code path).

---

# Handover — Medium Table + Build Station: Procedural Mesh → wooden_table.glb (Aug 2026)

## What changed this session
Replaced the procedural leg+tabletop mesh in `Table.gd` (Medium/2×1 table
only — Small/1×1 table is unchanged, still fully procedural) and
`BuildStation.gd` (tabletop only — blueprint rolls/toolbox unchanged) with
a real imported model, `assets/models/wooden_table.glb`. The source
asset's raw dimensions (3.0m × 1.29m × 1.94m) didn't match either script's
authored footprint (1.90 × 0.77 × 0.90) closely enough for a uniform
scale, so a non-uniform per-axis scale (`0.6333, 0.5946, 0.4638`) was
applied in code to hit the exact target footprint/height — flagged as a
deviation from a "clean" uniform-scale import; recommend an in-editor
visual check for distortion. The source file's single glTF node also
carries a baked scene-placement translation `(-1.7, 0, 0.7)` unrelated to
the mesh's own shape — every instantiation site now explicitly zeroes
`model.position` after `instantiate()` rather than trusting the import
transform (same defensive pattern `WallLight._build_fixture()` already
uses). Collision on both objects is now a separate invisible
`BoxShape3D` at the same dimensions/position the old procedural
`create_trimesh_collision()` produced, since the model's own imported
collision is stripped unconditionally.

### Files modified
- `assets/models/wooden_table.glb` — new asset.
- `scripts/world/furniture/Table.gd` — `cell_count == 2` branch in
  `_build_mesh()`, new `_build_mesh_from_model()`, new
  `_strip_model_collision()`.
- `scripts/world/furniture/BuildStation.gd` — tabletop/legs block in
  `_build_mesh()` replaced, new `_strip_model_collision()`.
- `docs/systems/build/README.md` — Furniture section updated.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Construct → Furniture → Medium Table: spinning preview shows the real
   wooden table model, not a grey box.
3. Place a Medium Table — model renders centered on the ghost/placement
   position, no visible offset (checks the `model.position = Vector3.ZERO`
   fix actually took).
4. Model's footprint visually matches the placement ghost/ghost tint box
   (1.90 × 0.90) reasonably closely — some proportion distortion from the
   non-uniform scale is expected and OK, a wildly wrong footprint is not.
5. Walk into the table from multiple sides — collision blocks at the same
   1.90×0.90 footprint the old procedural table did (invisible collision
   box, not the visual mesh).
6. Small Table (1×1, tile 27) — completely unaffected, still renders the
   old procedural metal legs+top.
7. Build Station — table portion shows the same wooden model; blueprint
   rolls and toolbox still render in their same relative positions on top
   of it (checks `top_y` still resolves correctly for the code below the
   replaced block).
8. Save/load a level with a placed Medium Table — model reloads correctly
   (uses the same `_spawn_placed_object()` path as before, no save-format
   changes were made, so this should be a non-issue, but worth a quick
   check).

---

# Handover — Character Shadow Stand-In: Shorter (Aug 2026)

## What changed this session
`CharacterShadowStandIn.HEIGHT_FACTOR` lowered from `0.5` to `0.35` per
direct request for a shorter character shadow at any given light angle.
Single-constant change — no structural or logic changes, no other file
touched besides docs.

### Files modified
- `scripts/core/CharacterShadowStandIn.gd` — `HEIGHT_FACTOR` constant
  and its doc-comment.
- `docs/systems/graphics/README.md` — "Character shadow stand-in"
  section updated to reflect the new value.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Load a scene with a character near a light (WallLight or Flashlight),
   observe the shadow — should be visibly shorter than before at the
   same light angle/distance.
3. Confirm the shadow's base still lands at the character's actual floor
   contact point (no floating/detached shadow) — the `y_offset` math is
   unchanged, only `HEIGHT_FACTOR` itself moved, so this should hold
   automatically, but visually confirm.
4. Confirm no other visual regression on the character's own mesh
   (`cast_shadow = OFF` on the real mesh is untouched by this change).

---

# Handover — Flashlight Self-Shadow Dome, Actual Fix (Aug 2026)

## What changed this session
The original flashlight self-shadow fix (way earlier this project) never
actually worked — confirmed via playtesting feedback, then confirmed via
source inspection that its player-body exclusion was still correctly
wired, just not addressing the real cause. Flashlight.gd builds its own
housing meshes (handle, head, lens) essentially touching the SpotLight3D
itself (lens at local Z=0.182, light at Z=0.20) — none of them were ever
excluded from casting a shadow. That's almost certainly the actual dome.

Fixed with cast_shadow = SHADOW_CASTING_SETTING_OFF on all three prop
meshes, globally (not scoped to just the flashlight's own light via
light_cull_mask, unlike the player-body approach) — there's no scenario
where any light needs a shadow from a tiny handheld prop, so a flat
exclusion is both simpler and guaranteed correct. The existing
player-body light_cull_mask exclusion is unchanged and stays in place
alongside this.

### Files modified
- `scripts/world/items/Flashlight.gd` — cast_shadow = OFF added to
  handle_mi, head_mi, lens_mi in `_build_mesh()`.
- `docs/systems/graphics/README.md`,
  `docs/systems/furniture-items/README.md` — correction notes.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Turn on Shadow Casting in Settings, equip and turn on the flashlight —
   the dome/shadow blob that used to sit in the center of the beam should
   now actually be gone (previous fix attempt did not resolve this).
3. Confirm the flashlight's visual appearance (handle/head/lens) is
   otherwise unchanged — this only affects shadow-casting, not rendering/
   lighting/materials.
4. Confirm furniture/walls/other objects still cast normal shadows into
   the beam when Shadow Casting is on (unaffected by this fix).
5. Re-verify the player-body exclusion is still doing something useful on
   its own — with the housing fix in place, walk the player's own body
   through the beam at an angle where their body (not the flashlight
   prop) would be the near occluder, and confirm no separate dome
   reappears from that.

---

# Handover — Character Shadow Stand-In (Real Shadows, Aug 2026)

## What changed this session
Replaced the fake shadow decal system (`CharacterShadowDecal.gd` — custom
direction/length/opacity logic approximating a shadow) with real
shadow-casting via a shortened, invisible stand-in mesh
(`CharacterShadowStandIn.gd`). The character's actual visible mesh still
doesn't cast its own shadow (`cast_shadow = OFF`, unchanged); a separate
capsule roughly half their real height, positioned with its own base at
the same floor contact point their real feet are at, casts a genuine
shadow in its place via `SHADOW_CASTING_SETTING_SHADOWS_ONLY`. Because
it's real shadow-map geometry, direction/falloff/multi-light response are
all handled by the engine automatically — no per-frame script, no custom
math, none of the tuning surface the decal system needed across many
rounds.

Per direct instruction: no lights are excluded from casting shadows on
characters this round. Characters can still show multiple real shadows
near multiple lights — only the shadow's *length* (via the stand-in's
reduced height) was addressed. If that's not enough on its own,
excluding WallLight from character shadows specifically (via the same
light_cull_mask mechanism already used for Flashlight's self-shadow fix)
is the documented next step, not started here.

**Small deviation (flagged):** `WallLight.gd`/`GrowLight.gd` each had
two comment blocks claiming `get_shadow_weight()` was "consumed by the
CharacterShadowDecal.gd system" — stale after this deletion (that system
was its only consumer; the methods are now dead code). Updated those four
comments to say so; the methods themselves were left in place (out of
plan scope to remove).

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — deleted.
- `scripts/core/CharacterShadowStandIn.gd` — new.
- `scripts/player/Player.gd` — decal instantiation replaced with a single
  `CharacterShadowStandIn.attach(self)` call.
- `scripts/npc/NPC.gd` — same.
- `scripts/world/power/WallLight.gd` — stale decal-consumer comments
  updated (dead-code note only; deviation, see above).
- `scripts/world/power/GrowLight.gd` — same.
- `docs/systems/graphics/README.md` — new "Character shadow stand-in"
  entry, decal entry marked replaced.
- `docs/systems/player/README.md`, `docs/systems/npc/README.md` —
  updated Common-edits pointers.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Confirm zero references to `CharacterShadowDecal` remain
   (`grep -r CharacterShadowDecal scripts/`) — comment mentions of the
   removed system in the new file/Player.gd are historical context, no
   runtime references remain.
3. Characters now cast a real shadow from every real light (WallLight,
   GrowLight) — confirm it's visibly shorter/less dramatic than before
   the decal system existed, not just present.
4. Confirm the stand-in mesh is never visible to the camera directly,
   from any angle.
5. Confirm the stand-in's shadow base lines up with the character's own
   feet — no visible gap or float between the character and where their
   shadow starts.
6. Confirm Flashlight's self-shadow-dome fix still holds — no dome
   reappearing in the beam from the (now real-shadow-casting) stand-in.
7. Confirm real shadows correctly respond to `GraphicsSettings.
   shadow_casting_enabled` and quality presets exactly as they already
   did for every other object — this system doesn't add any new toggle,
   it rides entirely on existing real-shadow infrastructure.
8. If shadow length still feels too dramatic, `HEIGHT_FACTOR` in
   `CharacterShadowStandIn.gd` is the single value to lower.

---

# Handover — Root Cause Fixed: `held_item` Freed-Instance Crashes (Aug 2026)

## What changed this session
Root-caused two reported crashes ("Trying to assign invalid previously
freed instance" in `TrashCan.get_f_prompt()` and
`ResearchStation.get_chute_f_prompt()`, on unrelated objects in separate
play sessions) to a single source, rather than patching either read
site: `GardeningActivity.gd` caches the item it's working with once
(`_tick_fetch()`, into `_item`), then never re-syncs that cache against
`npc.held_item` for the rest of a multi-frame travel/apply sequence. Its
only safety check before acting (`is_instance_valid(_item)`) confirms
the object still exists, not that the NPC still owns it. Confirmed via
`NPC.on_item_taken_by_player()` (the Takeaway handler) that Takeaway
correctly nulls the NPC's own `held_item` when the player takes an item
mid-job — but has no way to know about the activity's separate cached
copy, and doesn't touch it. The activity then keeps calling
`apply_at_cell()`/`on_use()` on an item now sitting in the player's
hand; if that call depletes the item's last charge, it `queue_free()`s
the exact object the player is currently holding, leaving
`player.held_item` dangling with no error at that moment. The crash
only surfaces later, in whichever of the ~20+ files that read
`held_item` directly without a validity guard happens to run next —
which is why the two reports pointed at completely unrelated objects
(a Trash Can, a Research Station chute) rather than anything obviously
connected to gardening.

Fixed at the source rather than patching symptom sites: the activity now
checks `npc.held_item == _item` immediately before acting, in addition
to the existing `is_instance_valid()` check, and gracefully abandons the
task (same fallback already used elsewhere in this function) if the
player has taken the item away. Protects both the fertilize (`on_use()`)
and seed/soil (`apply_at_cell()`) branches with one guard. Every one of
the ~20+ unguarded `held_item` read sites across the codebase is
protected by this fix without touching any of them individually, since
the corruption can no longer happen in the first place.

### Files modified
- `scripts/npc/activities/GardeningActivity.gd` — added ownership
  re-validation before acting on the cached item reference.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_HELD_ITEM_ROOT_CAUSE_FIX_PLAN.md` for the full 5-item checklist)

---

## [Aug 2026] Research Station — icon size correction

Follow-up to the material/clock icon pass: `MATERIAL_ICON_SIZE` shrunk
16→9px, `CLOCK_ICON_SIZE` shrunk 12→8px. The original sizes nearly
filled the materials-grid button height (~20px), reading as
oversized/"full-sized" rather than a small accent next to the text.
No other change — same textures, same positioning/alignment code.

---

## [Aug 2026] Research Station — material icon sizing bug, real fix

Correction to the previous "shrink icon sizes" pass: that fix changed
the wrong thing. Material icons were rendering at full 100x100 texture
size regardless of `MATERIAL_ICON_SIZE`'s value, because `icon_rect.size`
was being assigned *before* `icon_rect.expand_mode` — Godot clamps a
`.size` assignment to the control's minimum size at that moment, and a
TextureRect's minimum size is its native texture size until expand_mode
is changed off the default. Reordered so expand_mode/stretch_mode are
set before `.size`; this is the real fix, not a size-constant change.
`CLOCK_ICON_SIZE` reverted 8->12 (it was never buggy — the previous
shrink was an unnecessary side effect of misdiagnosing the material icon
issue). `MATERIAL_ICON_SIZE` set to 12 (matches the clock icon's
confirmed-good scale) now that it will actually take effect on screen.

---

## [Aug 2026] Research Station — moved to spawn against the north wall

`MainWorld._spawn_initial_research_station()` now places the station
flush against the bunker's north wall (confirmed with the person: north
= the wall nearer player spawn, OFFSET_Z=4.5 boundary) instead of 2m off
the Build Station's center. X centered along the wall's run, Z = wall
coordinate + the object's own half-depth (0.48) — same "wall + inset"
formula BunkerPregen.gd already uses for its pregen lights on that same
wall. Angle unchanged (0.0 — front already faces into the room at that
angle). No other Research Station behavior changed.

---

## [Aug 2026] Research Station — widened + material feed chute + reposition

Three changes in one pass:
1. Repositioned +4 on X from the wall-run center (was literal X=4 first
   requested — that's outside the bunker; corrected to "+4 relative to
   center" = X=-0.5 after flagging the bounds problem). Still flush
   against the north wall, Z/Y/angle unchanged from the prior pass.
2. Footprint widened 1.5x (2 units → 3 units, width only) —
   `_tile_half_extents()`, `build_ghost_mesh()` both updated.
3. New material feed chute on the left side of the widened footprint —
   the real player-facing way to fill `stored_materials`, replacing the
   F7 debug button as the primary path (F7 still exists for testing).
   Hold an item with `get_trash_material()` (nearly everything now has
   it — only `SeedItem` doesn't), press F near the chute (its own
   `ResearchStationChute.gd` proxy, independent interaction range from
   the main station body) — item destroyed, 1 unit of its material
   added, or rejected entirely if that material's already at cap. A held
   Trash Bag drains all records at once with per-material partial-drain
   (capped-out records stay behind in the same, shrunk bag). Design
   confirmed across several rounds — key-press feed not physics drop-in,
   whole-bag drain, reject-at-cap for single items, partial-drain-with-
   leftover for bags. See `docs/systems/research/README.md`'s "Material
   feed chute" note for full logic.

**Deviation from the plan (Option A, approved):** the plan had the chute
proxy join only the `interactable` group and assumed that gave it F
dispatch. It doesn't — `InteractionSystem` only dispatched F (prompt +
press) to the `shelving` group. Instead of changing the proxy to the
dual-group Shelving/LightStorage pattern, `InteractionSystem.gd` gained
generic F dispatch for non-shelving `interactable` bodies (Aug 2026
Option A): `_nearest_f_interactable()` + `_f_interactable_distance()`,
wired into the held-item F branch (feed before drop), the empty-handed F
branch (distance-fair vs. pickup), and both prompt assembly paths. The
proxy file is exactly as the plan wrote it. Reach is the standard 2.5 m
flat-XZ shelf reach, so the feed prompt can appear up to 2.5 m around the
chute mouth (overlapping the widened station's left portion) rather than
being tightly gated to the chute itself — flagged for in-editor check.

### Files modified
- `scripts/world/build/BuildModeController.gd` — `_tile_half_extents()`
  widened for `TILE_RESEARCH_STATION`.
- `scripts/world/core/MainWorld.gd` — spawn X = wall-run-center + 4.
- `scripts/world/furniture/ResearchStation.gd` — `_build_mesh()`
  widened + chute visual + proxy spawn; `_interaction_system` resolver;
  `get_chute_f_prompt()`/`on_chute_f_interact()`/`_feed_single_item()`/
  `_feed_bag()`; `build_ghost_mesh()` widened.
- `scripts/world/furniture/ResearchStationChute.gd` — NEW host-forwarding
  proxy (interactable group only, per plan).
- `scripts/player/InteractionSystem.gd` — generic F dispatch for
  non-shelving interactables (Option A deviation).
- `docs/systems/research/README.md`, `docs/systems/furniture-items/
  README.md`, `HANDOVER.md` — this entry.

---

# Handover — Shadow Direction Turn-Rate Cap (Aug 2026)

## What changed this session
Replaced the instant direction snap in `CharacterShadowDecal.gd` (which
fixed an earlier lag complaint but had no protection against large sudden
angular swings) with a maximum turn-rate cap. In a bunker with several
lights contributing at once, the aggregate shadow direction could jump
through a wide arc very quickly whenever the lights' individual pulls
were competing rather than reinforcing each other — reported as visible
spinning as the player moved through multi-light areas.

Direction now moves toward its target at a capped degrees-per-second
rate rather than either an instant snap or a flat lerp. Small continuous
adjustments (ordinary walking) stay under the cap and still read as
instant, preserving the earlier lag fix; only a large sudden target
change gets visibly swept over a fraction of a second instead of
teleporting. The cap itself is scaled by a "confidence" value — the ratio
of the aggregate direction vector's magnitude to the plain sum of
contributing weights — so a single dominant light still turns fast, while
several competing lights (the actual spinning scenario) turn more calmly.
Uses `Vector3.slerp()` for the arc interpolation rather than manually
picking a rotation axis, avoiding the class of sign/axis bug from an
earlier fix in this same file.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — new
  `MAX_TURN_SPEED_HIGH_CONFIDENCE`/`MAX_TURN_SPEED_LOW_CONFIDENCE`
  constants, direction update in `_process()` replaced with the
  confidence-scaled turn-rate-capped version.
- `docs/systems/graphics/README.md` — fix v8 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Walk normally near a single light — direction should still feel
   immediate/responsive, no perceptible lag reintroduced.
3. Walk through an area with several lights at competing angles (the
   original spinning scenario) — shadow direction should sweep calmly
   rather than spin/flicker rapidly between directions.
4. Force a large sudden direction change (e.g. walk quickly past a light
   at close range) — shadow should visibly sweep to the new direction
   over a brief moment rather than teleporting instantly.
5. If ordinary movement now feels laggy, `MAX_TURN_SPEED_HIGH_CONFIDENCE`
   is too low — raise it. If multi-light areas still spin too fast,
   `MAX_TURN_SPEED_LOW_CONFIDENCE` is too high — lower it.

# Handover — Shadow Size Response Fix (Aug 2026)

## What changed this session
v6's opacity-saturation fix (recalibrating against OPACITY_REFERENCE_WEIGHT)
didn't produce a noticeable difference in practice — its reference value
(1.5) was still low enough that ordinary multi-light coverage in this
bunker kept weight past it most of the time, so opacity still read as
near-constant. Raised the reference substantially (1.5 → 4.0).

More significantly: shadow LENGTH was always the flat TARGET_LENGTH
regardless of how close or strong the nearby light was — only direction
ever visibly changed, which reads as mechanical/robotic no matter how well
opacity is tuned, since a fixed-size shape spinning around the character
is a much more obvious "this isn't reacting to anything" signal than a
subtle darkness gradient. Length now scales with the same aggregate
weight that drives opacity — shrinking toward ~30% of full length when
weak/far, stretching toward full length when close to a strong light —
layered underneath the existing raycast wall/furniture clip exactly as
before. Width is untouched.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — new `MIN_LENGTH_FACTOR`/
  `LENGTH_REFERENCE_WEIGHT` constants, `OPACITY_REFERENCE_WEIGHT` raised,
  `_process()` now computes a weight-scaled target length used by the
  raycast and clip.
- `docs/systems/graphics/README.md` — fix v7 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Walk from right next to a single wall light out to the edge of its
   range — shadow should now visibly SHRINK (not just fade) as you move
   away, well before it disappears entirely.
3. Stand near 2-3 overlapping lights — shadow should be at or near full
   length and full opacity (expected).
4. Confirm the raycast wall/furniture clip still works — a long
   (high-weight) shadow should still stop at an obstruction instead of
   passing through it.
5. If the size range feels too subtle or too extreme,
   `MIN_LENGTH_FACTOR`/`LENGTH_REFERENCE_WEIGHT` are the values to retune
   — lower `MIN_LENGTH_FACTOR` for a more dramatic minimum, adjust
   `LENGTH_REFERENCE_WEIGHT` for how much weight it takes to reach full
   length.
6. Overall movement should now read as more organic/less mechanical —
   this was the actual goal; if it still feels robotic, the next lever to
   check would be SMOOTH_RATE (how quickly weight itself responds to
   movement) rather than another size/opacity recalibration.

## [Aug 2026] Research Station — material icons + clock icon

`ResearchStationUI.gd`'s materials-header grid now shows an icon
(left-aligned) + `x/10` count (right-aligned) per material cell, instead
of `"Metal: 3/10"`-style text. Research cards show a clock icon to the
left of the duration/"Time left" text. Five new assets added under
`assets/icons/`: `icon_material_metal.png`, `icon_material_paper.png`,
`icon_material_organic.png`, `icon_material_plastic.png`, `icon_clock.png`
(clock's ring interior pre-filled opaque white, exterior transparent —
don't re-source this file from a plain outline version). No behavior
changes — display only. See `docs/systems/research/README.md`'s "Icon
pass" note for details.

---

## [Aug 2026] Cooking Pot — emptied containers eject; finished dish stays in pot

`CookingPot.gd`: adding a Food Can or Water Bottle as an ingredient now
EMPTIES it (Food Can `_become_empty()`; Water Bottle `current_fill_mL =
0.0` + `_update_empty_tint()`) and ejects the empty container into the
world beside the pot via the new `_eject_emptied_container()` helper —
only the abstract ingredient data (restore value, ingredient key, charge
badge) stays in the slot, with `node: null` (the same shape a
restored-from-save slot already has). Produce is unaffected (still
freeze/hide/reparent). `_finish_cooking()` no longer clears `slots[]` —
it only frees lingering produce node references and nulls them, keeping
the ingredient icons/badges visible — and `serve_dish()` is now where
`slots[]` actually empties. Result: a done-but-untaken dish keeps showing
its ingredient icons, `is_full()` stays true (player must take the dish),
and the prompt shows `DONE — [E] Take Dish (...)`; taking the dish clears
the icon row to empty circles. Save/load round-trips a done-but-untaken
pot with no changes (it just serializes whatever's in `slots[]`).

---

# Handover — Shadow Intensity-vs-Distance Fix (Aug 2026)

## What changed this session
The character shadow's opacity was computed as
clamp(_current_weight, 0, 1) — since a single nearby light's weight
easily exceeds 1.0 well before you're actually close to it, this clamp
saturated to full opacity across most of a light's practical range. The
underlying distance falloff was always there (each light's
get_shadow_weight() already reduces with distance), but it was invisible
in practice because opacity pegged to max almost immediately and only
dropped right at the extreme edge of a light's reach — reading as
constant-strength, more like a decal fixed to the character's feet than a
dynamic shadow.

Fixed by normalizing the weight against a tuned reference value via
smoothstep instead of a raw clamp, so opacity now visibly ramps across a
light's more typical range. Near multiple overlapping lights it can still
saturate to full opacity, which is correct — that's meant to read as
solidly shadowed.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — new `OPACITY_REFERENCE_WEIGHT`
  constant, opacity calculation changed from clamp to smoothstep.
- `docs/systems/graphics/README.md` — fix v6 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Walk from right next to a single wall light out to the edge of its
   range — shadow opacity should now visibly fade throughout that walk,
   not stay at full strength until suddenly disappearing.
3. Stand near 2-3 overlapping lights — shadow should still read as fully,
   solidly opaque (expected, not a bug).
4. Confirm the shadow still disappears entirely once genuinely out of
   range of everything (MIN_TOTAL_WEIGHT threshold, unchanged).
5. If the falloff still feels too abrupt or too gradual,
   OPACITY_REFERENCE_WEIGHT is the one value to retune — lower = saturates
   sooner (closer to old behavior), higher = fades more gradually across a
   wider range.

# Handover — Research UI Nub Fix + Title Plan (Aug 2026)

## What changed this session
Four small Research Station UI fixes, all confirmed against current code:
1. **Dangling connector nubs** — the two outer main columns' vertical
   connectors used to stop at the top node's bottom-edge height with
   nothing to meet (the top node is only NODE_W wide, centered over the
   middle column). They now run up to the top node's vertical center and
   jog horizontally into its left/right edge; the middle column's
   straight connector is unchanged.
2. **Tier bar centering** — wrapped in a CenterContainer within the tile's
   VBox (harmless even if the bar already fills the width).
3. **Bottom margin** — tile VBox `offset_bottom` tightened -8.0 → -4.0 to
   remove the gap beneath the tier bar. If any gap remains in-editor,
   `box`'s stylebox `content_margin_bottom` is the alternate source.
4. **Title center + rename** — title label centered (horizontal_alignment
   + SIZE_EXPAND_FILL); `bunker_water_output_2x.tres` display_name
   renamed "2x Water Output" → "2x Water Hookup Output". The tile title
   and completion toast both pull from this field, so the rename
   propagates with no code change.

### Files modified
- `scripts/ui/research/ResearchStationUI.gd`
- `data/upgrades/bunker_water_output_2x.tres`
- `HANDOVER.md` — this entry.

### Verification checklist (Brannon, in-editor)
1. Columns 2 and 4 connect into the top node's left/right sides — no
   dangling stubs.
2. Tier bar horizontally centered in the tile.
3. Gap beneath the tier bar noticeably tighter — flag if any gap remains.
4. Title reads "2x Water Hookup Output," centered, in tile and toast.

# Handover — Shadow Too-Thin Fix (Aug 2026)

## What changed this session
The character shadow's width used to grow across its entire length,
reaching full width only right at the far tip — which is also where the
length-based fade had already made it nearly invisible. The portion
actually visible/opaque never got close to full width, reading as much
thinner than the character. Fixed by giving width its own, faster growth
curve (CONE_WIDTH_GROWTH_END) independent of the length fade — it now
reaches full width early and holds there, so the solidly-opaque part of
the shadow is genuinely at full width. Also bumped the width ceiling
slightly (CONE_BASE_EXTENT 0.85 → 0.9).

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — new `CONE_WIDTH_GROWTH_END`
  constant, `CONE_BASE_EXTENT` bumped, texture generation loop updated.
- `docs/systems/graphics/README.md` — fix v5 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Shadow's body should now read at least as wide as the character through
   most of its visible length, not just briefly at the very tip.
3. Near-origin taper (the "true cone point" fix) should be unaffected —
   still converges to a point right at the character, not a line.
4. Far tip should still fade out smoothly, no hard cutoff.
5. If it now reads too wide, `CONE_BASE_EXTENT` is the value to dial back
   down; if the width ramps up too abruptly/late, `CONE_WIDTH_GROWTH_END`
   is the one to adjust (lower = faster ramp).

# Handover — Direction-Dependent Shadow Length/Width Fix (Aug 2026)

## What changed this session
Fixed a bug where the character shadow's apparent length and width
depended on which compass direction the contributing light(s) were in
relative to the character — long/thin for north-south lights, stubby/
perpendicular-stretched for east-west. Traced GameCamera.gd's actual
offset and pitch math to rule out camera-projection foreshortening (it
would compress the opposite axis, and wouldn't swap length/width) before
concluding this was a code bug rather than an inherent camera effect.

Most likely cause: the shadow's transform was built by rotating a
template shape and then applying a non-uniform scale to that same
rotated Basis — a composition I could not fully verify by hand without
running the engine. Replaced it with an explicit construction: two
independently-computed direction vectors (the shadow's own direction,
scaled to length; that direction rotated 90°, scaled to width) passed
directly into Basis's three-column constructor. No rotate-then-scale step
remains for an axis mix-up to hide in.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — `_process()`'s final transform
  construction rewritten.
- `docs/systems/graphics/README.md` — fix v4 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Recreate both screenshots' scenarios (light roughly north-south of
   character; light roughly east-west) — shadow length/width should now
   read consistently between them, not swapped.
3. Test a few other angles (not just the four cardinal directions) to
   confirm there's no residual angle-dependent distortion at intermediate
   directions.
4. Confirm shadow direction itself (which way it points) is unaffected —
   this was a length/width-only fix.
5. Rotate the camera view (Home/End keys, if accessible) and re-check —
   the shadow's actual world-space shape should be identical regardless
   of current camera yaw, since this fix operates entirely in world space
   independent of the camera.

# Handover — Research UI Polish Pass (Aug 2026)

## What changed this session
Applied `RESEARCH_UI_POLISH_PASS_PLAN.md` (all 7 parts) to
`ResearchStationUI.gd` + `ResearchStation.gd`:
1. **Material buttons** — `PanelContainer` → plain `Panel` (Panel doesn't
   auto-resize to its child Label, which is why "Plastic"/"Organic"
   stretched while "Metal"/"Paper" didn't); size now computed once from
   the widest of the 4 label strings + tight padding.
2. **Hover-bug fix (structural vs. tick split)** — `_process()` no longer
   calls `_refresh_content()` (which destroyed + rebuilt the Research
   button every 250ms, so Godot never re-applied hover). A new
   `_tick_active_progress()` mutates cached `_active_progress_bar` /
   `_active_time_label` refs in place, never touching Button/Panel nodes.
   Full rebuilds still happen on real state changes.
3. **Tier bar** — full-width `_build_tier_bar()` (segments fill the tile
   edge-to-edge; `max_tier == 1` = one toggle-colored strip).
4. **Titles** — bare `display_name` (no "Tier N -"); toasts keep the tier.
5. **Durations** — shared `_format_duration()` ("10 Seconds"); dropped the
   "Time to completion:" prefix.
6. **Pause/resume** — `is_paused` + `pause_research()`/`resume_research()`
   on the station, `_process` gate, and a 3-state button
   (Research/Stop Research/Resume). No refund.
7. **Branch mirror** — bottom-left branch (below row 4) replaced with a
   true mirror of the right branch beside the grid; right diagonal re-
   anchored to row 1. Canvas + PANEL_W grew so both fit with horizontal
   scroll disabled.

### Files modified
- `scripts/ui/research/ResearchStationUI.gd`
- `scripts/world/furniture/ResearchStation.gd`
- `docs/systems/research/README.md` — polish-pass section, branch
  topology, pause semantics.
- `HANDOVER.md` — this entry.

### Deviations flagged in the session report
- ProgressBar added back (redesign had dropped it; the tick + checklist #6
  need one).
- `is_paused` reset on start/complete (plan bug fix — stale true would
  stall the next research).
- `PANEL_W` 834→1024 so the mirrored left + right branches stay on-canvas.
- Panel height + content top now computed from the (much shorter) material
  grid instead of the fixed 756/288.
- Tick detects in-station completion and triggers the rebuild the plan
  assumes happens on "completion".
- `next_tier` local removed from the UI (was only used by the title).

### Verification checklist (Brannon, in-editor)
1. All 4 material buttons identical size, short/tight.
2. Hover stays lit over the Research button with the mouse still.
3. Tier bar fills the tile width edge-to-edge (3 segments for water).
4. Title reads "2x Water Output"; completion toast keeps the tier.
5. Not-started duration reads "10 Seconds".
6. Stop Research freezes the bar, becomes "Resume", no refund; Resume
   continues exactly from the frozen point.
7. Bottom-left branch sits left of the grid, mirroring the right branch.

# Handover — True Cone Shadow Shape (Aug 2026)

## What changed this session
The character shadow decal's near end was still reading as a flat line
even after two rounds of width tightening/calibration — because it was
still, structurally, a shape with nonzero width at the character's end,
just a narrower and softer one. Root cause: the "solid core, then a fade
band at its edge" formula inherently has SOME width at v=0 no matter how
tight the edge softness gets.

Replaced with a single continuous falloff starting at the centerline
itself and widening toward the far end — a genuine cone/wedge shape.
At the character's end the fade's extent is tiny, so nearly the entire
row is already fading out right from the center point, with no residual
width to read as a line. Width scaling simplified to plain proportional
sizing relative to Player's own capsule radius, since matching a specific
near-width to the character's footprint no longer applies once the near
end is a true point.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — shape constants replaced
  (CONE_TIP_EXTENT/CONE_BASE_EXTENT), texture generation rewritten to a
  single-stage falloff, width-scale calculation simplified.
- `docs/systems/graphics/README.md` — fix v3 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. The shadow's near end should now read as converging to a point
   directly under/behind the character — no discernible flat line or
   boundary at the origin, from any light configuration (single light,
   two lights at any angle).
3. The shape should still widen smoothly toward the far end (the cone
   body) and fade out at the tip — no hard edges anywhere.
4. Confirm this holds for both Player and NPC, with NPC's cone
   proportionally smaller.
5. Re-check the specific two-lights-at-±45° scenario from earlier
   screenshots — should no longer show the "connected line" artifact.

# Handover — Shadow Width/Opacity Decoupling Fix (Aug 2026)

## What changed this session
Root-caused why the character shadow read as wide/blocky near two lights
and narrow near one, even in open floor space with nothing clipping the
raycast: the opacity multiplier (driven by aggregate light weight) was
being applied across the whole soft gradient, which shifts how far out the
visible edge of a fade appears — higher weight (more lights) makes more of
the fade stay above the visibility threshold (reads wider), lower weight
does the opposite (reads narrower). Same shape, different apparent size,
purely a side effect of how opacity interacted with a gradual fade.

Fixed by tightening the edge transition specifically near the character
(a much crisper falloff there vs. the far tail, which stays soft/
atmospheric) so the visible boundary is far less sensitive to the weight
multiplier. Also added per-character width calibration — the shadow's
near width now matches each character's own actual CapsuleShape3D.radius
(Player and NPC are different sizes) instead of a single guessed constant
used for both. A brief ease-in was added at the very tip to soften the
near cap's start, though a fully round/radial cap was deliberately not
attempted — flagged as a larger, separate rewrite if still needed after
this pass.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — split edge softness into near/
  far, added tip ease-in, added per-character width-scale calibration
  (`_compute_character_dimensions()` replaces `_compute_floor_offset()`),
  applied width scale in `_process()`.
- `docs/systems/graphics/README.md` — fix v2 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Stand near two lights at roughly ±45° from facing, in open floor space
   (no obstruction) — shadow should no longer look noticeably
   wider/blockier than the single-light case.
3. Stand facing a single light directly — shadow should no longer look
   noticeably narrower than the two-light case; both should read close to
   the same physical width now.
4. Confirm the near width visually matches the character's own footprint
   — not clearly wider or narrower than their model.
5. Confirm an NPC's shadow is also correctly sized to ITS (smaller)
   footprint, not the player's.
6. The far end can still flare out somewhat (per your confirmation that's
   fine) — check it doesn't look zeroed-out or oddly cut off now.
7. Near cap should read at least somewhat rounder than before, though not
   a perfect circle — if it's still clearly a flat line, that's the
   flagged limitation (no true radial cap this round), not a regression.

# Handover — Research UI Redesign: Tiered Upgrades + Node Tree (Aug 2026)

## What changed this session
Redesigned the Research Station UI into a tiered-upgrade node tree and
made `2x Water Output` the first (only) tiered upgrade.

**Tiered data model:** `UpgradeDef` gained `@export max_tier` and changed
its effect signature to `apply_effect(tier_reached: int)` with
**direct-set semantics** — effects SET the external system to match the
tier just reached, they do NOT increment relative to unknown prior state
(the station is the authoritative progress tracker; effects just sync
external systems to it). Added `get_max_tier()`, overridable when a
chain's true tier count is computed from the system it drives.
`WaterOutput2xUpgrade` now computes `get_max_tier()` from
`WaterHookup.TIER_DAILY_ML.size() - 1` (**3 real completions** — the
sketch's "4" was illustrative, showing the UI pattern generically) and
direct-sets `hookup.tier` instead of the old "+1" debug logic.

**Tier-aware progress:** `ResearchStation.completed_upgrade_ids` →
`tier_progress: Dictionary` (chain id → tiers completed). `start_research()`
rejects at full max; `_complete_research()` increments the tier, passes it
to the effect, and the toast now reads "...Tier N research completed"
(minor self-extension beyond the ask — trivial to revert if you'd rather
keep the flat wording).

**Node-tree UI:** the old VBox of full-width cards is replaced by a
vertical `ScrollContainer` over one fixed-size canvas: a single tiered
detail node at top (`_build_tiered_node` — name → materials → time →
Research → tier-segment bar, box grows per extra material line) + a
3×4 grid of blank boxes + two side branch pairs, all connected by
`draw_line()` on a dedicated `_connector_canvas` behind the boxes. Grid/
branches are blank scaffolding this pass; only the top node is functional.
The materials header became a pinned **2×2 button grid** (Metal/Plastic
left, Paper/Organic right) that does NOT scroll with the tree; tabs and
header position unchanged, only the content area below them changed.

### Flagged deviations / tuning
- **`PANEL_W` 640→834, `PANEL_H` 620→756** — the plan's dims couldn't fit
  the 3 grid cols + right-side branch col (4 × `NODE_W`) and the 2-row
  materials grid + `SCROLL_VISIBLE_H` simultaneously; widened so the
  described layout actually fits. All `NODE_*`/`MATERIAL_*` sizing kept as
  specified. Expect visual tuning pass in-editor.
- Branch-pair positions/anchors are my best reading of the hand-drawn
  sketch (right pair beside rows 2-3, bottom-left pair below row 4) —
  approximate, adjust once rendered.

### Files modified
- `scripts/core/UpgradeDef.gd` — `max_tier` export, new `apply_effect(tier_reached)` signature, `get_max_tier()`.
- `scripts/core/upgrades/WaterOutput2xUpgrade.gd` — computed tier count, direct-set effect.
- `scripts/world/furniture/ResearchStation.gd` — `tier_progress`, tier-aware eligibility + completion.
- `scripts/ui/research/ResearchStationUI.gd` — node-tree canvas, connector canvas, `_build_tiered_node`, `_build_blank_box`, 2×2 materials grid, ScrollContainer.
- `docs/systems/research/README.md`, `HANDOVER.md` — this entry.

### Verification checklist (Brannon, in-editor)
1. **Materials grid:** Metal/Plastic left column, Paper/Organic right
   column, aligned left edges, small column gap, stays fixed while the
   tree below scrolls.
2. **Top node:** "Tier 1 - 2x Water Output" on a fresh station, correct
   cost line, "Time to completion: 10s", Research button, 3-segment tier
   bar all unfilled.
3. **Tier progression:** complete one research — toast "...Tier 1
   research completed", title advances to "Tier 2 - ...", segment bar 1/3
   filled, Water Hookup output matches the F7 debug doubler's effect.
4. **Full maxing:** complete all 3 tiers — "COMPLETED" banner, bar fully
   filled, further clicks do nothing.
5. **Tree layout:** top node connects visually to 3 child boxes; grid +
   branches roughly match the sketch; ~3 rows visible, rest scrolls.
6. **Scope check:** tabs and materials grid positions unchanged — only the
   content area below them changed.

# Handover — Soft Shadow Shape Fix (Aug 2026)

## What changed this session
`CharacterShadowDecal.gd`'s shape was a hard-edged vertex-color trapezoid
— alpha only faded along its length, leaving the left/right edges as an
unblended straight cut, which read as a "flat wall of shadow" rather than
something sourced from the character. Replaced with a procedurally-
generated soft alpha texture (64×128, no external asset) mapped onto a
plain rectangle: a tight, contained core right at the character's feet
(fixing "focal point needs to be more snugly underneath the player"),
widening into a soft cone tail, fading smoothly on every edge in every
direction (fixing both the "flat wall" look and "blurred and natural
looking" — including holding up without relying on the character mesh to
cover any hard boundary, since none exists anymore).

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — shape constants replaced,
  texture generation added, mesh simplified to a plain UV rectangle,
  material switched from vertex-color to texture-driven albedo.
- `docs/systems/graphics/README.md` — shape fix note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Shadow now reads as a soft, rounded shape anchored right under the
   character, not a flat-edged band.
3. No visible hard edges anywhere around the shape's silhouette — check
   all sides (near, far, left, right).
4. Direction/length/occlusion-clipping behavior unchanged from before —
   this was a shape-only fix.
5. If the shape still looks too wide or too subtle, `NEAR_WIDTH_FRAC`/
   `FAR_WIDTH_FRAC`/`EDGE_SOFTNESS` in `CharacterShadowDecal.gd` are the
   values to retune — each has a one-line comment explaining what it
   controls.

# Handover — Rendering Driver Switch, Vulkan/D3D12 (Aug 2026)

## What changed this session
Added a "Rendering Driver" option (Vulkan/D3D12) to Settings > Rendering,
addressing a DXGI_ERROR_DEVICE_REMOVED crash under D3D12 on an RX 580
(already project-level-fixed by pinning project.godot to Vulkan; this adds
a player-facing way to opt back into D3D12 on hardware where it works).

The driver can't change mid-session (Godot engine limitation) — this is a
restart-based setting. Two-tier apply: (1) an explicit "Restart Now"
confirm dialog relaunches the same executable via `OS.create_process()`
with `--rendering-driver <value>`, immediately applying the choice; (2) a
best-effort `override.cfg` written next to the executable makes the choice
durable across a future plain relaunch too, without ever touching the
tracked/committed `project.godot`. `GraphicsSettings.rendering_driver` is
deliberately excluded from PRESETS/`set_setting_live()` — it has its own
setter (`set_rendering_driver()`) since it can't apply live like everything
else in that file.

Flagged for follow-up verification: the `override.cfg` mechanism (Tier 2)
is based on documented Godot behavior, not tested against an actual
exported build of this project yet — if it doesn't pick up as expected,
Tier 1 (the in-app relaunch button) still fully covers the original ask.

### Files modified
- `scripts/core/GraphicsSettings.gd` — new `RENDERING_DRIVERS` const,
  `rendering_driver`/`session_start_rendering_driver` vars,
  `set_rendering_driver()`, persistence in `_save()`/`_load()`.
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — new Rendering Driver row,
  restart-required confirm dialog, `OS.create_process()` relaunch,
  `override.cfg` writer.
- `docs/systems/graphics/README.md` — new "Rendering driver switch" entry.
- `HANDOVER.md` — this entry.
- `project.godot` — NOT modified; committed default stays
  `rendering_device/driver.windows="vulkan"`.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Fresh install (no cfg, no override.cfg) — boots Vulkan, Settings shows
   "Vulkan" selected.
3. Switch to D3D12 in Settings — confirm dialog appears; "Later" leaves
   the game running unaffected on Vulkan for the rest of this session.
4. Switch to D3D12, click "Restart Now" — game relaunches; on hardware
   where D3D12 works, boots successfully; check for an `override.cfg` next
   to the executable containing the D3D12 override afterward.
5. **On the RX 580 (or equivalent) this bug originated on:** confirm
   selecting D3D12 and restarting actually reproduces the original crash —
   this is expected/correct (the option exists for OTHER hardware where
   D3D12 works; this card should stick with Vulkan). Confirms the option
   doesn't accidentally "fix" the underlying driver issue, just exposes
   the choice.
6. After a successful D3D12 relaunch, close the game via the normal exit
   flow (not Alt+F4) and reopen it via a plain double-click (not through
   any in-app button) — if override.cfg is working as expected, it should
   still boot D3D12. If it boots Vulkan instead, Tier 2 isn't behaving as
   assumed — note this and fall back to documenting that only the in-app
   restart button reliably applies the choice.
7. Switch back to Vulkan, confirm the relaunch flow works symmetrically.
8. Confirm `project.godot` is untouched by any of the above (diff against
   git — should show zero changes to that file after any amount of
   in-game driver switching).

# Handover — Shadow Decal Ground Level + Instant Snap Fix (Aug 2026)

## What changed this session
Two follow-up fixes to `CharacterShadowDecal.gd` from playtesting
feedback: (1) the shadow was rendering at the character's capsule center
instead of the floor — fixed by reading each character's own
`CapsuleShape3D.height` (Player and NPC differ: 2.0 vs 1.8) rather than
assuming a fixed offset, computed once in `setup()`. (2) shadow direction
was lerping into position the same way opacity fades, reading as lag —
fixed by snapping direction instantly on every frame; only opacity/weight
still smooths.

### Files modified
- `scripts/core/CharacterShadowDecal.gd` — floor-offset computation,
  instant direction snap, mesh placement uses floor position.
- `docs/systems/graphics/README.md` — follow-up note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Shadow now renders flat on the actual floor, not floating at
   torso/chest height.
3. Shadow direction changes immediately as the character moves between
   lights — no visible slide/lag.
4. Confirm this looks correct for both Player and an NPC (different
   capsule heights, both should land correctly at floor level).
5. Opacity fade near the edge of a light's range should still look smooth
   (unaffected by this change — only direction stopped smoothing).

# Handover — Generic Upgrade System + First Real Upgrade (2x Water Output) (Aug 2026)

## What changed this session
Turned the placeholder Research Station shell into a real, working upgrade
system end-to-end, with the first non-placeholder upgrade (2x water
output).

**Generic data model:** `UpgradeDef.gd` is now the real base class
(Resource) — shared data fields (`id`/`display_name`/`tree`/
`duration_seconds`/`material_costs`, keys matching `get_trash_material()`
return values) plus a virtual `apply_effect()` each subclass overrides.
New upgrades = tiny subclass + `.tres` resource; runtime/UI code has zero
per-upgrade special-casing. First real upgrade:
`WaterOutput2xUpgrade.gd` + `res://data/upgrades/bunker_water_output_2x.tres`
(`{"metal": 5, "plastic": 5}`, 10s, bunker tree) — effect copied verbatim
from the existing working F7 debug doubler (`_on_hookup_output_double_pressed`,
tier + 1 clamped at `WaterHookup.TIER_DAILY_ML` top).

**Material storage:** `ResearchStation` holds `stored_materials`
(metal/plastic/paper/organic), each capped at `STORAGE_CAP = 10`.
`add_material()` clamps + returns actual added. No deposit/remove logic yet
(reservoir mechanic deferred).

**Incremental consumption model (per the "60% complete = 3/5 used"
example):** nothing deducted at click-time — `start_research()` is a
pure eligibility check (nothing else running, not completed, enough
materials). `_process()` drains storage in floor()-quantized steps as
elapsed advances, so the station's stored count visibly ticks down over
the research. `completed_upgrade_ids` lives on the station (NOT the shared
Resource — a correctness footgun). `_complete_research()` calls
`apply_effect()` + posts a `NotificationManager` toast.

**UI:** `ResearchStationUI` Bunker tab now builds real data-driven upgrade
buttons (`_build_upgrade_button()`, one reusable routine): title, static
cost line, ProgressBar, time-left/to-completion label, disabled/greyed
when not affordable, "COMPLETED" banner overlay, click → `start_research()`
with a "Already researching something else" toast on refusal. Persistent
materials header spans all 3 tabs, refreshed on open + a repeating
in-panel timer (background drain runs regardless of tab).

**F7 debug:** new `RESEARCH` section — `+10 Each Material Type` via
`_get_research_station()` → `add_material()`, clamped at the same cap.
`ResearchStation` joins the `"research_station"` group for this lookup.

### Design decisions / deferred (explicit, not forgotten)
- **Incremental vs upfront deduction** — went with your incremental example
  exactly; the double-spend edge case only becomes real with concurrency
  or pause/reallocate (neither exists yet — one active research globally).
- **Pause** — deferred; incremental model already stores `_elapsed`/
  `_consumed`, so pause is later just UI + a "stop advancing time" flag.
- **Reservoir/dump-trash-into-station** — not this pass; `add_material()`
  is ready for whatever it becomes.
- **Multi-concurrent research** — `start_research()` rejects a second
  research globally. Revisit once Player Skills/NPC Skills have upgrades.
- **Storage-cap bypass** — flat 10 everywhere this pass.

### Files modified
- `scripts/core/UpgradeDef.gd` — stub → real base class.
- `scripts/core/upgrades/WaterOutput2xUpgrade.gd` — new subclass.
- `data/upgrades/bunker_water_output_2x.tres` — new resource.
- `scripts/world/furniture/ResearchStation.gd` — storage, active state,
  `_process()` incremental tick, `_complete_research()`, `"research_station"` group.
- `scripts/ui/research/ResearchStationUI.gd` — data-driven buttons,
  materials header, in-panel refresh timer, real content.
- `scripts/ui/menus/AdminMenu.gd` — RESEARCH section + handler.
- `docs/systems/research/README.md`, `HANDOVER.md` — this entry.

### Verification checklist (Brannon, in-editor)
1. With 0 stored materials, the "2x Water Output" button is greyed/
   disabled, cost reads "5x Plastic, 5x Metal".
2. F7 → RESEARCH → "+10 Each Material Type" — header across all 3 tabs
   shows 10/10 for all four materials; capped (no overflow on repeat).
3. Start research — progress bar fills, "Time left" counts down from 10s.
   Close UI, wait ~6s, reopen — ~60% progress, ~7/10 plastic + 7/10 metal
   in the header (background ticking + incremental drain both work).
4. Completion — toast "2x Water Output research completed"; "COMPLETED"
   banner sticks; Water Hookup output doubled (indistinguishable from the
   F7 debug doubler).
5. Re-clicking a completed button does nothing.
6. Double-start guard — `start_research()` refuses a second research
   (button path shows the "already researching something else" toast).

# Handover — Revert Aggregated Character Shadows → Cone Shadow Decal (Aug 2026)

## What changed this session
Fully reverted the Aggregated Character Shadows system (CharacterShadowProxy.gd
and all character-exclusion light_cull_mask changes across Flashlight.gd/
WallLight.gd/GrowLight.gd/Player.gd/NPC.gd/GraphicsSettings.gd, plus its
three hotfix rounds) after it caused three consecutive regressions
(pitch-black characters, underlit characters, harsh flash-photo lighting)
while never actually needing to touch character illumination at all — the
original complaint was specifically about the shadow the character casts,
not how the character itself is lit.

Replaced with two much narrower, independent pieces: (1)
`GeometryInstance3D.cast_shadow = OFF` on the player/NPC mesh — stops the
character from casting any real shadow, while leaving real illumination
completely untouched/default; this alone fixes the original multi-shadow
complaint. (2) `CharacterShadowDecal.gd` — a new, purely cosmetic flat mesh
(no Light3D anywhere) that fakes one blended "cone" shadow using the same
weighted-light-aggregate direction math the reverted proxy used, with
length clipped by a raycast against furniture/walls so it doesn't stretch
through solid objects.

Flashlight.gd's original, narrower self-shadow exclusion
(`Player.PLAYER_SELF_LIGHT_LAYER_BIT`, excluding only the player from the
flashlight's own beam) is restored — that was a correct, separate fix from
before this whole detour and was never the problem.

### Files modified
- `scripts/core/GraphicsSettings.gd` — removed relocated constant.
- `scripts/player/Player.gd` — restored original constants, removed
  CharacterShadowProxy, added CharacterShadowDecal.
- `scripts/npc/NPC.gd` — removed mesh.layers override + CharacterShadowProxy,
  added CharacterShadowDecal.
- `scripts/world/items/Flashlight.gd` — restored original exclusion +
  comment.
- `scripts/world/power/WallLight.gd` — removed character exclusion,
  kept get_shadow_weight().
- `scripts/world/power/GrowLight.gd` — removed character exclusion, kept
  get_shadow_weight().
- `scripts/core/CharacterShadowProxy.gd` — deleted.
- `scripts/core/CharacterShadowDecal.gd` — new.
- `docs/systems/graphics/README.md`, `docs/systems/player/README.md`,
  `docs/systems/npc/README.md`, `docs/systems/power/README.md` — reverted/
  updated notes.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile) — pay particular
   attention to the `const`-inside-`_ready()` flag in File 2's edit above.
2. Confirm zero references to `CharacterShadowProxy` remain anywhere
   (`grep -r CharacterShadowProxy` across `scripts/`).
3. Player/NPCs no longer cast multiple real shadows near several wall
   lights — the original complaint.
4. Player/NPC lighting/brightness looks completely normal again — same as
   before any of this session's work (no proxy, no exclusion beyond
   Flashlight's original one).
5. One soft, tapered shadow shape appears behind the character, direction
   sweeping smoothly as they walk between lights.
6. Walk the shadow toward a wall/piece of furniture — it should stop
   roughly at the obstruction rather than stretching through it.
7. Confirm the flashlight's own self-shadow-dome fix still works
   (unrelated to this session, but touched by the revert — verify it
   didn't regress).
8. Toggle Shadow Casting off — real per-light shadows AND the cone decal
   should both disappear; real character lighting is unaffected by this
   toggle either way (it never was, pre-this-whole-detour).

# Handover — Character Shadow Proxy Harsh-Lighting Hotfix v3 (Aug 2026)

## What changed this session
v2's fix for the "pitch black" bug (closer proxy light, higher energy)
introduced a new problem, visible in a playtesting screenshot: every
character read as hit by a hard camera flash — bright near-side, sharp
black far-side, same intensity regardless of actual distance to any real
light. Three compounding causes in `CharacterShadowProxy.gd`: a too-close
light produces hard Lambertian shading on a small object regardless of
energy tuning; the light was aimed level with the character rather than
from above like real room lighting; and every nearby real light's weight
summed together then hit a hard clamp, so most characters in a lit room
pegged to the same max brightness.

Fixed with a different approach than v1/v2's pure energy-number tuning:
raised the proxy to a ~45° overhead angle (PROXY_HEIGHT now exceeds
PROXY_DISTANCE), widened the cone (25°→50°), softened distance falloff
(spot_attenuation 0.5→0.3), added light_size for a soft shadow gradient
instead of a hard edge, and replaced the hard-clamped linear energy
formula with a smooth saturating curve so characters near different
numbers of lights actually read differently again.

### Files modified
- `scripts/core/CharacterShadowProxy.gd` — constant recalibration (angle/
  distance/falloff/light_size), energy formula changed from linear-clamp
  to saturating curve.
- `docs/systems/graphics/README.md` — hotfix v3 note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. In a room with several wall lights (like the playtesting screenshot) —
   characters should no longer look like they're hit by a flash; look for
   a visible brightness gradient depending on actual proximity to lights,
   not uniform intensity for everyone.
3. Character shading should read as a soft gradient front-to-back, not a
   hard bright/black split.
4. Confirm the shadow itself still reads clearly directional (the whole
   point of this system) — the softening changes shouldn't have made the
   shadow itself invisible or overly diffuse; if it has, that's
   SPOT_LIGHT_SIZE needing a reduction.
5. Character brightness overall should be in a reasonable middle ground —
   not dark like v1, not blown-out like v2. If still off in either
   direction, MAX_ENERGY/ENERGY_CURVE_RATE are the two values to retune.
6. Walk between lights — shadow direction should still sweep smoothly, no
   regression from the earlier smoothing work.

**Diagnostic logging improvements (Aug 2026):** Four additions from the trash-loop
> investigation, aimed at making a similarly-shaped bug visible from the log directly next time:
> a generic missing-method warning (`NPCDebug.log_missing_method()`, applied to `drop_held()`'s
> one other unguarded action call), `held_item_after=` on delivery logs, a suspicious-interrupt
> canary for "interruptible while still holding something," and a stalled-repick counter on
> Cleaning's target-picking log.

**Research Station Foundation + Trash Material Types + Empty Seed Bag (Aug 2026):** Three
> additions toward the Research Station feature. (1) **Trash material type system** — items may
> implement `get_trash_material() -> String` ("metal"/"plastic"/"paper"/"organic"); applied to 13
> item files (mechanical, one method each; no other logic touched). `TrashCan.extract_trash_record()`
> now stores `"material"` in the record's `data` when the method exists; untagged items get no key
> (unusable for research until explicitly categorized). `SeedItem` left untagged deliberately.
> **NEXT PASS:** actual upgrade definitions/buttons/timers/feed logic (spending trash material on
> upgrades); `UpgradeDef.gd` stub exists as the target shape. Two confirmation flags open: (a)
> `BagOfSoilItem` threshold implemented as strict-full (`_charges >= _max_charges`); say so if you
> meant any-charge-left, (b) `SeedItem` material. (2) **Research Station (TILE 38)** — singleton
> `ResearchStation.gd`, identical treatment to Build Station (spawns once near world-center, never
> purchasable/deconstructable, movable only); `[E] Open Research Station` opens the modal
> `ResearchStationUI` (shell only: 3 selectable tabs with per-tree separate state stubs). Opens a
> modal UI rather than toggling a game mode, so no prompt-ownership handoff — just the standard
> `InteractionSystem.research_ui` E/F gate (same as shelf/basket). Cross-thread item-file touches
> flagged per convention: Farming (`BagOfSoilItem`, `FarmProduceItem`, `FertilizerItem`,
> `EmptyFertilizerBottleItem`, `SeedItem`), Cooking (`CookingPot`, `DishItem`), general items
> (`Basket`, `Flashlight`, `FoodCan`, `FuelCan`, `PurifierFilterItem`, `WaterBottle`). (3) **Empty
> Seed Bag** — `EmptySeedBagItem.gd` mirrors `EmptyFertilizerBottleItem.gd`; `SeedItem` now drops
> one when its last charge is used, in BOTH `on_use()` and the NPC `apply_at_cell()` path
> (consistent with `BagOfSoilItem`'s both-paths spawn). Spawn position is +2m X off the Build
> Station's computed center — verify visually in-editor that the two don't overlap.

# Handover — Aggregated Character Shadows (Aug 2026)

## What changed this session
Replaced per-character real shadow reception (every nearby WallLight/
GrowLight casting its own shadow onto the player/NPCs — up to 6+ at once
around the starting bunker's perimeter lights) with one aggregated fake
shadow per character. Every real light now excludes characters from its
`light_cull_mask` entirely (via `GraphicsSettings.CHARACTER_SHADOW_LAYER_BIT`,
relocated from `Player.PLAYER_SELF_LIGHT_LAYER_BIT` and now shared with
NPCs too), and each character owns a `CharacterShadowProxy` — a single
SpotLight3D whose direction/brightness are a smoothed, weighted aggregate
of nearby real lights (`WallLight.get_shadow_weight()`/
`GrowLight.get_shadow_weight()`, new public methods). Proxy position is a
fixed distance/height from the character (art-directed for a consistently
dramatic long shadow) with only the *direction* driven by real nearby
lights.

Important consequence: since light_cull_mask can't separate illumination
from shadow contribution, characters now get 100% of their direct
lighting from this one proxy instead of the real room lights — GI/ambient
is unaffected. `CharacterShadowProxy.gd`'s `ENERGY_SCALE`/`MAX_ENERGY` are
first-pass eyeballed values, most likely thing to need retuning.

Flashlight is deliberately not part of the aggregate (self-referential for
its wielder) — see `docs/systems/graphics/README.md` "Aggregated character
shadows" / "Scope decisions" for the reasoning.

Cross-thread note: touched `Player.gd` (Player), `NPC.gd` (NPC),
`WallLight.gd`/`GrowLight.gd` (Power), `Flashlight.gd` (Furniture/Items) —
all small, mechanically-driven edits, design owned by Graphics.

### Files modified
- `scripts/core/GraphicsSettings.gd` — new `CHARACTER_SHADOW_LAYER`/
  `CHARACTER_SHADOW_LAYER_BIT` (relocated from Player.gd).
- `scripts/core/CharacterShadowProxy.gd` — new.
- `scripts/player/Player.gd` — removed old layer consts, updated mesh
  tagging, instantiates `CharacterShadowProxy`.
- `scripts/npc/NPC.gd` — same mesh tagging + proxy instantiation.
- `scripts/world/items/Flashlight.gd` — updated cull-mask reference.
- `scripts/world/power/WallLight.gd` — cull-mask exclusion added, new
  `get_shadow_weight()`.
- `scripts/world/power/GrowLight.gd` — cull-mask exclusion added, new
  `get_shadow_weight()`.
- `docs/systems/graphics/README.md` — new "Aggregated character shadows"
  entry, superseded-note on the earlier flashlight-only entry.
- `docs/systems/player/README.md`, `docs/systems/npc/README.md`,
  `docs/systems/power/README.md` — Common-edits notes.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Boot at High/Ultra (shadow_casting_enabled on) near the 6 starting
   perimeter lights — player should show exactly ONE shadow, not up to 6.
3. Walk/sprint between lights — the single shadow should sweep smoothly as
   you move, not pop/flip discretely between directions.
4. Stand roughly equidistant from several lights (the worst case for the
   old system) — shadow should shrink/fade toward faint rather than
   picking a jarring arbitrary direction.
5. Walk somewhere with zero nearby WallLight/GrowLight — proxy should
   switch off (character lit only by ambient/GI, no floating stray light).
6. Check a character's overall brightness near lights doesn't look
   noticeably dimmer/brighter than before this change — if it does,
   that's `ENERGY_SCALE`/`MAX_ENERGY` needing a tuning pass in
   `CharacterShadowProxy.gd`, not a bug.
7. Confirm NPCs show the same single-shadow behavior as the player.
8. Confirm furniture/walls are completely unaffected — they still receive
   normal per-light real shadows from every real light untouched by this
   change; only characters changed.
9. Toggle Shadow Casting off — both real per-object shadows AND the
   character proxy shadow should disappear together (proxy already gates
   on the same setting).
10. Confirm the flashlight still works exactly as before (still excludes
    its own wielder specifically, unaffected by this session beyond the
    constant's rename/relocation).

## Open items for Brannon

- `ENERGY_SCALE = 0.6` / `MAX_ENERGY = 3.0` in `CharacterShadowProxy.gd`
  are eyeballed, not derived — the first thing to check once characters
  are visible in-editor near real lights (see "Important side effect").
- `PROXY_DISTANCE = 6.0` / `PROXY_HEIGHT = 1.8` control how long/dramatic
  the fake shadow looks — pure art direction, adjust freely, no other
  system depends on these values.
- The "proxy lights aren't mutually exclusive between characters" edge
  case (see "Scope decisions") is accepted as-is given Godot's ~20-layer
  budget — flag if it turns out to be more visible in practice than
  expected, since a real fix would need a different approach (e.g.
  per-character-pair dynamic layer assignment) that's more involved than
  this plan's scope.
- Flashlight-highlighting-NPCs (shining the flashlight on an NPC and
  having that specifically brighten/shadow them) is explicitly not built
  here — flagged as a possible future ask, not started.

---

# Handover — Character Shadow Proxy Underlit Hotfix v2 (Aug 2026)

## What changed this session
Two bugs in `CharacterShadowProxy.gd` from the Aggregated Character
Shadows plan, both making players/NPCs read as far too dark:

1. The proxy light's *existence* (not just its shadow-casting) was gated
   on `GraphicsSettings.shadow_casting_enabled`, which defaults false at
   Medium — pitch black at default settings. Fixed: illumination is now
   unconditional; only `_spot.shadow_enabled` still follows that setting.
2. Even with the proxy active, `PROXY_DISTANCE = 6.0` was much farther
   than a real WallLight/GrowLight ever has to reach a character, so
   Godot's physically-based falloff ate almost all the light before it
   arrived — severe underlighting everywhere except right next to a
   strong real light (reported as "flickering to briefly reveal a small
   spot"). Fixed: `PROXY_DISTANCE` → 2.5m, `ENERGY_SCALE`/`MAX_ENERGY`
   recalibrated upward, and a new `SPOT_ATTENUATION` constant added
   (previously left at Godot's steeper default).

### Files modified
- `scripts/core/CharacterShadowProxy.gd` — constant recalibration, new
  `SPOT_ATTENUATION`, removed the shadow_casting_enabled gating bug.
- `docs/systems/graphics/README.md` — hotfix note.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Boot at the default preset (Medium) — player/NPCs should now be
   normally lit near WallLight/GrowLight.
3. Walk through a normally-lit room — character brightness should look
   reasonably consistent throughout the lit area, not spiking only right
   next to individual lights.
4. Switch to High/Ultra — character lit AND showing its one aggregated
   shadow.
5. If characters now look noticeably too bright, that's `ENERGY_SCALE`/
   `MAX_ENERGY` in `CharacterShadowProxy.gd` — safe to dial down, this was
   deliberately erred bright over dark.
6. Walk somewhere with zero nearby WallLight/GrowLight — character should
   still correctly dim/darken there (MIN_TOTAL_WEIGHT cutoff working as
   intended).

---

# Handover — Build Station (Aug 2026)

## What changed this session
Added the Build Station — a singleton furniture object (`BuildStation.gd`,
TILE 37) that spawns once at the starting bunker's geometric center at game
start and serves as the in-fiction entry point into Build Mode. Locked
decisions honored: F1 stays a dev/admin shortcut alongside it; permanently
non-deconstructable (guards mirror Water Hookup's exact two sites); never
purchasable; movable only via the Move tool; freestanding; simple primitives
model with rolled blueprints.

- Entering build mode: standard `"interactable"` contract
  (`get_interact_prompt()`/`on_interact()`), `[E] Enter Build Mode`.
- Exiting build mode: `InteractionSystem` is inert during build mode, so the
  exit prompt is `BuildModeController`-owned — `_process()` shows
  `[E] Close Build Mode` within `BUILD_STATION_EXIT_REACH` (2.5m), `E`
  (unclaimed by draw-mode tools) closes build mode. The station + prompt +
  `_main_world` refs are injected by `MainWorld` at spawn.
- Centralized held-item drop on build-mode entry in
  `MainWorld._toggle_build_mode()` — uniform across both entry paths.

### The InteractionSystem prompt-ownership handoff (why)
`InteractionSystem._process()` and `BuildModeController._process()` both run
every frame; during build mode they'd otherwise race on the same
prompt node. Fixed by having `InteractionSystem._process()` return
immediately when `build_mode_active` is true (no longer force-hides the
prompt), leaving `BuildModeController` the sole owner. `exit_build_mode()`
hides the prompt to hand ownership cleanly back.

### Files modified
- `scripts/world/furniture/BuildStation.gd` — new (verbatim from plan).
- `scripts/world/build/BuildModeController.gd` — `TILE_BUILD_STATION` const
  (37); `build_station`/`interact_prompt`/`_main_world` properties +
  `BUILD_STATION_EXIT_REACH`; save-list skip; deconstruct guard; occupancy
  + half-extents arms; `_spawn_placed_object()` branch; `_process()` exit
  prompt; `_unhandled_input()` E-exit; `exit_build_mode()` prompt handoff.
- `scripts/world/build/GhostModelBuilder.gd` — PROCEDURAL_PREVIEW_SOURCES
  entry 37.
- `scripts/world/build/GhostPreview.gd` — ghost branch +
  floor-snap height (0.5).
- `scripts/world/core/MainWorld.gd` — `_spawn_initial_build_station()`
  (true-center computation), call site, `_connect_world_objects()`
  injection, `_toggle_build_mode()` held-item drop.
- `scripts/player/InteractionSystem.gd` — build-mode prompt-ownership
  handoff.
- `docs/systems/build/README.md`, `docs/systems/furniture-items/README.md`,
  `docs/systems/player/README.md` — docs.
- `HANDOVER.md` — this entry.

### Verification checklist (in-editor)
1. New game — Build Station roughly centered in the starting room; if
   off-center, the Part 3 spawn-center computation needs a look (it derives
   from `rock_surround` constants, not a literal).
2. Approach it — `[E] Enter Build Mode` prompt (styled like every other);
   E enters build mode.
3. Held-item drop on entry — hold any item, enter via the station: drops
   first, exactly like F. Repeat via F1 — same behavior.
4. Exit mechanic — in build mode, away from the station: no prompt. Within
   ~2.5m: `[E] Close Build Mode` at the station's position. E exits
   cleanly (camera/HUD/interaction all return to normal).
5. Draw-mode E not shadowed — mid-wire/pipe-draw E still cancels the draw
   tool, does NOT close all of build mode.
6. Non-deconstructable — deconstruct attempt warns, nothing happens; absent
   from save lists.
7. Move tool — relocates normally, ghost preview correct, occupancy works.
8. F1 unchanged — enters/exits from anywhere regardless of proximity.

## Open items for Brannon
- **Spawn-center verification** — computed from `rock_surround` constants
  (OFFSET_X=-12.5, OFFSET_Z=4.5, depth=16, width=8 → center X=-4.5, Z=8.5,
  floor Y=0.5). Verify visually once in-editor.
- **Inherited save limitation (flagged, not silently):** like Water Hookup,
  the station's moved position isn't persisted across save/load — it
  respawns at world-center. Position-persistence for either object is a
  real but separate follow-up.
- **Plan-name deviation:** the plan referenced `_ghost_half_extents_for_tile()`;
  live code calls this `_tile_half_extents()` — the same function, applied
  as intended.

---

> **Trash delivery loop fix (Aug 2026):** Root cause of the reported back-and-forth
> dropping/carrying loop — `npc_deposit_trash()` was called in two places but never defined
> anywhere, so trash "delivery" always silently no-op'd while logging success. Fixed by reusing
> the already-correct `npc_try_place_item()` for trash too, in both `CleaningActivity.gd` and
> `PutAwayHeldItemActivity.gd`. Also ran a full sweep of every `has_method()` call from NPC code
> against every function defined anywhere in the repo — this was the only phantom method found.

---

> **Trash can excluded from general light-storage routing (Aug 2026):** Fixed NPCs organizing
> full/half-charge items (water bottles etc.) into the trash can — it was never a
> trash-classification bug, `TrashCan`'s inherited `"shelving"` membership just made it a valid
> ordinary light-storage destination too. Excluded `"trash_receptacle"`-group objects from
> organizable-item routing at the query layer; trash routing and `TrashCan.gd` itself untouched.

---

> **Trash Can F-dispatch fairness + full/inaccessible drop-fallback (Aug 2026):** two fixes in
> `InteractionSystem.gd`/`TrashCan.gd`. (1) The empty-handed F branch previously called
> `shelf.on_f_interact()` unconditionally whenever ANY shelving-group object was in range — a full
> trash can could win over a genuinely closer loose item on the ground. Now gated on
> `_nearest_shelf_distance() <= _nearest_pickup_distance()` (flat-XZ, reusing the existing
> helper), the identical head-to-head pattern the stove-pot-vs-pickup comparison already uses.
> (2) TrashCan's two full-capacity paths (throw-away; bag merge) previously only toasted and left
> the held item stranded in hand — both now also `_quick_drop()` it (the established
> `LightStorage._try_store_held()` never-strand fallback). Deliberately NOT applied to the
> unrelated-held-item case (existing "hands full" nudge). Parse error: could not be reproduced
> from the repo (Shelving.gd:282 is clean on main); earlier `LightStorage.gd:282` / Shelving.gd
> cascade was a stray uncommitted `A` in a local working-tree edit, since fixed — recommend a
> fresh pull if it resurfaces. Also cleaned TrashCan.gd's stale header comment (was still
> describing the pre-full-fidelity "Full (10/10) + empty hands → collect" behavior).

---

> **Trash collection wired up + made scalable (Aug 2026):** `TrashCan` is now in the
> `"trash_receptacle"` group — the entire trash-collection system was already built and waiting
> on this one line. Also fixed: full-receptacle handling (previously would still walk to a full
> can and fail), and `has_cleaning_target_available()` not accounting for receptacle fullness
> (same bug class as the original organizable-item fix). `_is_trash_item()` is now fully
> generic — see README's own "How to mark an item as trash" section, which is meant to be
> referenced directly by any thread adding new items, not just read once. Five existing item
> types migrated to the new convention: `EmptyBagItem`/`EmptyFertilizerBottleItem` (group tag),
> `FoodCan`/`WaterBottle`/`FuelCan` (method) — `FuelCan` is new coverage, wasn't trash-eligible
> at all before this pass.

---

# Handover — Unified Dynamic Shadow Casting (Aug 2026)

## What changed this session
Generalized `GraphicsSettings.flashlight_shadows` (opt-in-only, flashlight
exclusive) into `shadow_casting_enabled` — a single preset-driven toggle
(LOW/MEDIUM off, HIGH/ULTRA on, still manually overridable) that now gates
real-time shadow casting on all three dynamic lights: Flashlight,
WallLight, GrowLight. Settings panel's "Shadow Casting" checkbox moved from
the Flashlight section to Advanced Quality and dropped its "(opt-in)"
label.

Each light's shape was handled according to its actual geometry rather
than uniformly flipping a bool: Flashlight (SpotLight3D) needed no shape
change. WallLight stays OmniLight3D (correct for a wall fixture) — turning
its shadow on also fixes a latent bug where its light bled straight through
the wall mesh into whatever's behind it. GrowLight was converted from
OmniLight3D to a downward-facing SpotLight3D
(`rotation_degrees.x = -90`, `spot_angle = 35.0`) — both for physical
correctness (it only ever lights the tray below it) and because Spot
shadows are a single shadow map vs. Omni's 6-face cubemap, which matters
given a farm room can hold far more grow lights than a base has wall
lights. Confirmed visual-only: `GrowLight.get_active_growth_speed()` is a
pure XZ position match independent of the light node, so gameplay growth
logic is untouched.

Cross-thread note: `WallLight.gd`/`GrowLight.gd` are Power-thread files,
touched here for the light-node/shadow wiring only.

### Files modified
- `scripts/core/GraphicsSettings.gd` — field rename, PRESETS entries,
  `apply_preset()`/`set_setting()`/`set_setting_live()` comments and logic,
  `_save()`/`_load()`.
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — checkbox moved section +
  relabeled, `_refresh_from_settings()`/`_on_shadow_toggled()` renamed key.
- `scripts/world/items/Flashlight.gd` — renamed setting reference.
- `scripts/world/power/WallLight.gd` — shadow wiring + live-update
  connection, new `_apply_graphics_settings()`.
- `scripts/world/power/GrowLight.gd` — Omni→Spot conversion, `_omni`→
  `_spot` rename, `OMNI_*`→`SPOT_*` const rename, new
  `_apply_graphics_settings()`.
- `docs/systems/graphics/README.md` — new "Unified dynamic shadow casting"
  entry.
- `docs/systems/power/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Boot at Medium (default) — no shadows from any of the three lights,
   matches pre-change look at Medium.
3. Switch to High or Ultra in Settings — Flashlight, WallLight, and
   GrowLight should all now cast real shadows. Confirm:
   - Flashlight beam: no self-shadow dome from the player (separate fix,
     should still hold — this session doesn't touch that exclusion).
   - WallLight: objects near a wall light correctly cast shadows; check a
     wall light near a room boundary no longer visibly lights the room on
     the other side of the wall.
   - GrowLight: light now visibly points down at the tray only, not
     sideways/upward — sanity-check `spot_angle = 35.0` actually covers a
     real placed tray's footprint; adjust in Inspector if it's too
     narrow/wide.
4. Toggle "Shadow Casting" off manually while on High — all three should
   go shadowless immediately (live update, no re-equip/re-place needed);
   `current_preset` should flip to CUSTOM in the preset dropdown.
5. Switch to Low/Medium preset — shadows off, checkbox reflects it.
6. Confirm `GrowLight.get_active_growth_speed()` / plant growth is
   unaffected by the light-shape change (should be — logic doesn't touch
   the light node — but worth a quick sanity check in a farm room).
7. Performance sanity check in a room with several WallLights + GrowLights
   at Ultra — if FPS drops meaningfully more than expected, that's a real
   signal `shadow_quality`'s atlas size or the number of simultaneous
   shadow-casting lights needs a budget cap; report back rather than
   silently tuning further.

## Open items for Brannon

- `spot_angle = 35.0` on GrowLight is eyeballed, not measured against
  `FarmingTray.gd`'s actual footprint — first thing to check once you see
  it placed over a real tray in-editor.
- No hard cap was added on simultaneous shadow-casting lights. If a
  heavily-built-out base with many WallLights/GrowLights at Ultra causes a
  real framerate problem, that's a follow-up (e.g. limiting shadow casting
  to the N nearest lights to the camera) — flagged, not built, since it
  wasn't part of this ask and adding a budget system speculatively would be
  scope creep.

---

# Handover — Flashlight Player Self-Shadow Exclusion (Aug 2026)

## What changed this session
Fixed the "dome" artifact where the flashlight's own SpotLight3D
self-shadowed the player's own mesh back into the center of its beam when
`GraphicsSettings.flashlight_shadows` is on — the light origin sits
extremely close to the player's body (handheld, mounted at HoldPoint), so
the player was by far the closest/largest shadow-caster to its own light
source.

Added a new exclusive render layer (layer 12,
`Player.PLAYER_SELF_LIGHT_LAYER_BIT`) that the player's mesh is tagged with
(REPLACING its default layer, not adding to it) and that
`Flashlight.gd`'s SpotLight3D clears from its own `light_cull_mask` at
creation. Every other light in the game (DirectionalLight3D, WallLight,
future lights) keeps its default all-layers cull mask untouched, so the
player continues being lit/shadowed normally by everything except this one
light. Godot has no per-light "lit but not a shadow-caster" flag — only the
combined `light_cull_mask` — so full exclusion from this one light was the
correct trade, especially since the floor-aimed beam never visibly lit the
player's own body in the first place.

Cross-thread note: this touched `Player.gd` (Player thread) and
`Flashlight.gd` (Furniture/Items thread) from the Graphics thread, since
the design is a lighting/shadow decision — flagged in both files' doc
updates and this entry so neither thread is surprised by it.

### Files modified
- `scripts/player/Player.gd` — new `PLAYER_SELF_LIGHT_LAYER`/
  `PLAYER_SELF_LIGHT_LAYER_BIT` constants, mesh layer tagging in `_ready()`.
- `scripts/world/items/Flashlight.gd` — one `light_cull_mask` line in
  `_build_light()`.
- `docs/systems/graphics/README.md` — new "Flashlight self-shadow exclusion"
  entry, Non-responsibilities cross-reference.
- `docs/systems/player/README.md` — new Common-edits entry (layer 12 reuse
  rule).
- `docs/systems/furniture-items/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Turn on Flashlight Shadow Casting in Settings, turn the flashlight on,
   walk around — the dome/shadow blob that used to sit in the center of the
   beam should be gone; furniture/walls/other objects should still cast
   normal shadows into the beam.
3. Turn Shadow Casting back off — confirm no regression (should look
   exactly like it did before this change, since `shadow_enabled` still
   gates the whole feature the same as always).
4. Confirm the player's mesh still renders normally from the main camera
   (sanity check that `mesh.layers = PLAYER_SELF_LIGHT_LAYER_BIT` didn't
   accidentally make it invisible — camera `cull_mask` is untouched and
   defaults to all layers, but worth eyeballing after the change).
5. Confirm the player still casts/receives shadows normally from
   DirectionalLight3D (e.g. a visible shadow on the floor from the room's
   ambient/wall lighting) — this is the "everything else stays normal"
   check.

---

# Handover — Tilt-Shift Depth of Field Rework (Aug 2026)

## What changed this session
Replaced `GameCamera.gd`'s point/distance-based DOF
(`CameraAttributesPractical.dof_blur_far_*`) with a screen-space tilt-shift
shader. Root cause of the old "blurs one random object, nothing else" look:
`dof_focus_distance = 15.0` vs. actual camera→player distance
`sqrt(14² + 8²) ≈ 16.12` put the player 1.1m inside the transition band, so
blur landed on the tallest nearby object's upper portion instead of reading
as background/foreground depth — and more fundamentally, the fixed ~55° iso
pitch over a mostly-flat floor doesn't generate enough true depth-buffer
variation for point-based DOF to look intentional at all.

New: `assets/shaders/tilt_shift_dof.gdshader` (vertical sharp-band + soft
blur ramp toward top/bottom screen edges, screen-space only, no depth
buffer read) + `scripts/core/TiltShiftDOF.gd` (thin CanvasLayer/ColorRect
forwarder, dynamically instantiated by `MainWorld` the same way
`LightingDirector` is). `GameCamera.gd` keeps ownership of all DOF
decision-making — same `GraphicsSettings.dof_enabled` gate, same
build-mode-forces-off rule — just retuned to drive the new shader's
uniforms (`dof_focus_center_y`/`dof_focus_band_half_height`/
`dof_transition_height`/`dof_max_blur_px`) instead of the old
`CameraAttributesPractical` fields.

Two plan bugs caught during implementation (both fixed in this commit):
1. **`fragment()` can't `return` in Godot shaders** — the plan's shader
   used an early `return` for the blur_px < 0.05 case; restructured to an
   `if/else` with identical logic.
2. **`_tilt_shift_dof = CanvasLayer.new()` is a static-type error** in
   GDScript (CanvasLayer.new() is typed `CanvasLayer`, not `TiltShiftDOF`)
   — MainWorld's setup uses a temp `CanvasLayer` var + `as TiltShiftDOF`
   cast after `set_script()`, keeping the var typed `TiltShiftDOF` so
   `camera.tilt_shift = _tilt_shift_dof` stays type-safe.

### Files modified
- `assets/shaders/tilt_shift_dof.gdshader` — new.
- `scripts/core/TiltShiftDOF.gd` — new.
- `scripts/core/GameCamera.gd` — DOF export block, internal var, `_ready()`,
  `_apply_dof_setting()`.
- `scripts/world/core/MainWorld.gd` — new `_setup_tilt_shift_dof()`, call
  site, tracking var.
- `docs/systems/graphics/README.md` — Files table, Public API, Call graph,
  new "Recent changes (Aug 2026)" entry, Forbidden edits.
- `HANDOVER.md` — this entry.

### Verification checklist
1. `tools/godot_check.sh` passes (headless compile).
2. Boot the game, confirm no "Could not find type TiltShiftDOF" errors —
   if seen, it's the class-cache/.uid staleness gotcha (§9,
   PROJECT_SUMMARY.md) — quit Godot, delete `.godot/`, reopen.
3. With DOF enabled (Settings > Advanced Quality > Depth of Field) in
   normal (non-build) mode: back wall/ceiling area and the very close
   foreground should read visibly softer than a horizontal band roughly
   through the player/floor-object area, which should stay sharp. No
   single object should look randomly half-blurred.
4. Toggle DOF off in settings — effect should disappear immediately
   (strength → 0).
5. Enter Build Mode — effect should force off regardless of the DOF
   setting, same as before.
6. Confirm HUD/menus (inventory bar, pause menu, storage UI) never look
   blurred — only the 3D game view should ever be affected.
7. Sanity-check at a couple of different FOV slider positions that the
   sharp band still roughly tracks the floor/gameplay area (report back if
   it visibly drifts — the default `dof_focus_center_y = 0.55` was picked
   by eye from the reference screenshots at default FOV, not derived from
   FOV-dependent math, so it's a good first-pass value but not guaranteed
   perfect at every FOV extreme).

# Handover — Outline System: Proxy-Interactable Devices Fixed (Aug 2026)

## What changed this session
Investigated whether the Sobel outline system supports GLB-imported
models (asked directly) — the mechanism itself does (mesh discovery and
edge detection are both origin-agnostic), but a real, different bug was
surfacing on `WallLight` specifically: it extends `Node3D` (no physics
body), so it uses a small `StaticBody3D` proxy
(`PowerPriorityInteractable.gd`) purely so `InteractionSystem`'s
proximity scan can find it. That proxy has no visual children — the
actual model (the `industrial_wall_lamp.glb` fixture) lives under the
WallLight root as a *sibling* of the proxy, not a descendant.
`InteractionFocusGlow.set_target()` only ever searched downward from the
node it was handed (the proxy), so it found zero mesh instances and no
outline. Not GLB-specific — a proxy-architecture gap that any current or
future `Node3D`-based device using this same established pattern would
hit identically, regardless of whether its visuals are imported or
procedural. (`GrowLight` was NOT affected: it's a direct `StaticBody3D`
with its own `on_priority_interact()`, so it never used the proxy —
verified against `GrowLight.gd`'s own header, which states the proxy
exists only for Node3D-without-a-body hosts like WallLight.)

Fixed by having `set_target()` also search from `node.host` when
present — the exact hook `PowerPriorityInteractable.gd` already
documents for forwarding interaction, reused here for mesh discovery.
`TRANSLUCENT_FIX_GROUP` membership now also checks `host`, so a device
that's both proxy-interactable and translucent doesn't hit a second,
compounded gap later. No device file touched — the fix generalizes
automatically to any future device adopting the same proxy pattern.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — `set_target()` also
  searches `node.host` for mesh instances and translucent-group
  membership when present.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_OUTLINE_PROXY_HOST_FIX_PLAN.md` for the full 4-item checklist)

# Handover — Trash Bag Full-Fidelity Recovery Fix (Aug 2026)

## What changed this session
Root-caused a real item-loss risk in the Trash Can → bag → merge
round-trip and redesigned the merge path to reconstruct real items
instead of compacting them into a dead data side-channel.

Two compounding bugs, both fixed:

1. **The underscore filter dropped exactly the state that matters.**
   `TrashCan.extract_trash_record()` skipped any script property whose
   name started with `_`, assuming underscore = implementation noise
   (cached mesh refs, timers). But this codebase marks meaningful
   gameplay state private by convention too — confirmed directly:
   `FuelCan._fuel_remaining` and `Flashlight._battery` (the exact
   "69% fuel" / "1/2 charges" cases). The old filter would have silently
   captured `0` for them. Replaced with a principled base-class diff:
   `_base_property_names()` caches `PickupableItem`'s own bookkeeping
   vars (grace timers, hold-point ref, out-of-range tracking) and only
   those are excluded — everything declared on the actual subclass is
   captured regardless of naming.
2. **`merged_trash_data` was non-retrievable by construction.** Even with
   correct data capture, a merged-back item could never come out again as
   a real item — only a count burned against capacity. Dropped entirely.

The redesign: merging a bag now turns each data record back into a real,
physical item (`reconstruct_item()`) and absorbs it exactly like a
freshly-thrown item, so it's indistinguishable from any other `stored[]`
entry — full Carry/⊕ retrieval, full fidelity, and the can reverts to
LightStorage's stock `stored[]`/`is_full()` with no overrides.

**Scene-vs-script reconstruction bug caught in review before
implementation** (surfaced by the zero-ambiguity anchor verification): the
original plan reconstructed items as bare `script + add_child`, but the
eligible scene-based items (Flashlight, FoodCan, FuelCan,
PurifierFilterItem, WaterBottle) keep their collision shape — and for
some, their whole visual — in a companion `.tscn`, not in script. Bare
reconstruction would have produced collision-less, un-pickable FuelCans
and invisible items for 5 of the 12 eligible types. Now
`extract_trash_record()` also captures `scene_file_path` and
`reconstruct_item()` instantiates the item's own scene when one exists,
falling back to bare-script only for the genuinely scene-less procedural
items (BagOfSoilItem, DishItem, EmptyBagItem, EmptyFertilizerBottleItem,
FarmProduceItem, FertilizerItem, SeedItem).

Also fully closes the earlier-flagged "deconstructing a can with merged
data discards it" caveat: reconstructed items are real `stored[]` entries,
so `eject_all_items()` (inherited) covers them on deconstruct. A
should-never-happen failure net remains: records that can't be
reconstructed (script moved/renamed since bagging) fold into
`_unrecoverable_records` and ride along in the next bag rather than being
silently dropped.

### Files modified
- `scripts/world/furniture/TrashCan.gd` — `_base_property_names()` +
  base-class-diff `extract_trash_record()` (now captures `script_path` +
  `scene_path`); new `reconstruct_item()` (scene-prefer / script-fallback);
  `_merge_bag()` reconstructs into `stored[]`; `_empty_into_bag()` folds
  `_unrecoverable_records`; removed `merged_trash_data`, `_live_count()`,
  `_total_count()`, the `is_full()` override; added `_has_any_stored()`.
- `docs/systems/furniture-items/README.md` — Trash Can section updated.
- `HANDOVER.md` — this entry.

### Verification checklist
(see `TRASH_BAG_FULL_FIDELITY_RECOVERY_PLAN_2.md` for Brannon's full
in-editor checklist: ~69% FuelCan + ~50% Flashlight round-trip with
correct collision/pickable, scene-vs-script coverage, second bag hop,
capacity 8/10 + 3-item reject, deconstruct-after-merge, regression)

# Handover — Translucent-Object Outline Fix (Water Case) (Aug 2026)

## What changed this session
Fixed the Sobel outline system finding no edges on Water Case, confirmed
root-caused to its materials' real alpha transparency (case shell 0.35,
bottles 0.90 alpha, per `WaterCase.tscn`) — Forward+ alpha-blended
materials don't write depth/normal, which the Sobel pass depends on
entirely. Two separate problems, both needed fixing: the isolation
mask itself was weak (built from the same transparent material), and
even a perfect mask wouldn't help since the main-scene Sobel pass reads
buffers the transparent geometry never wrote to in the first place.

Added a per-object opt-in group (`outline_needs_opaque_stand_in`,
`InteractionFocusGlow.gd`) — members get a temporary, always-opaque
duplicate of each mesh instance (sharing the source mesh resource, no
geometry copy) rendered exclusively on the mask's render layer (11),
invisible to the main camera (now excludes layer 11 via a bitwise clear
in `_ready()`, computed rather than hardcoded so it can't silently drift).
This gives the mask viewport a guaranteed-correct solid silhouette
regardless of the real material's transparency. Paired with a new
mask-alpha edge detection term in the outline shader itself — comparing
each pixel's mask alpha against its neighbors, which is redundant/
harmless for ordinary opaque objects but becomes the only usable edge
signal for translucent ones, since the stand-ins never render in the
main scene and can't feed the main Sobel pass. `WaterCase.gd` is the
first (currently only) member of the new group.

Honest limitation documented, not silently glossed over: this recovers
a correct silhouette outline, not interior creases, for translucent
objects — the stand-ins aren't themselves Sobel-detected against their
own depth/normal. Flagged as the natural next step (a second Sobel pass
inside the mask viewport) if silhouette-only isn't enough once tested.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — stand-in spawn/track/
  cleanup system; main camera cull-mask exclusion; mask-alpha edge term
  added to the outline shader.
- `scripts/world/items/WaterCase.gd` — one-line group opt-in.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_TRANSLUCENT_OUTLINE_STANDIN_PLAN.md` for the full 6-item
checklist)

# Handover — Trash Can F-Dispatch Fix + Partial Collect + Bag Merge (Aug 2026)

## What changed this session
**Bug fixed (F did nothing):** `InteractionSystem.gd`'s F-dispatch only
called `shelf.on_f_interact()` inside the `held_item != null` branch —
the empty-handed branch never reached it. Historically fine (base
shelf `on_f_interact()` no-ops empty-handed), but TrashCan's collect
override lives exactly there, so it never fired ("no errors, just
nothing"). Fix is a small contract change + dispatch addition:
`shelving`-family `on_f_interact()` now returns `bool` (true = consumed
the press) and the F-dispatch's empty-handed branch checks it before
falling through to the stove-pot/pickup logic — a no-op for every
existing Shelving/EndTable/Dresser call. Legacy `on_interact()` shims
(Shelving.gd / LightStorage.gd) call it as a bare statement, unaffected;
grep confirmed InteractionSystem is the only external caller.

**Toast migration (this feature's messages only):** the old
`show_soft_warning` "hands full" dance is gone; TrashCan's own warnings
("Trash can is too full") now go through `NotificationManager.notify(
UIKit.Domain.NEUTRAL, Severity.WARNING, …)`. Not a project-wide
migration — Shelving/LightStorage's earlier `show_soft_warning` calls
are untouched (separate decision, per your earlier framing).

**Feature extension:** collect now works at ANY fill level (not gated to
10/10), and a Trash Bag held near a can merges its contents back in.
Data-model decision, stated plainly: bag contents are DATA-ONLY records
(`merged_trash_data`), not live nodes — merged records count toward
capacity (`is_full()` = live + merged) but are not individually
retrievable via Carry/⊕ (there's no node to hand back), and they fold
into the contents of the NEXT bag the can produces. Why: matching the
real-world behavior (once bagged and re-dumped you don't fish one item
back out) and because live-node reconstruction was explicitly out of
scope. Deconstruct trade-off, flagged not silent: deconstructing a can
with `merged_trash_data` present discards that data (no live nodes to
eject — `stored[]`'s live items still eject via `eject_all_items()`);
preserving it would be a small follow-up if wanted. StorageUI still
shows the 10 physical slots — when merged data eats into capacity, some
visually-empty slots simply won't accept items until the can is next
collected (known v1 simplification).

### Files modified
- `scripts/player/InteractionSystem.gd` — F-dispatch empty-handed branch
  now checks `shelf.on_f_interact()`'s bool return (Player-thread file,
  flagged per the cross-thread convention).
- `scripts/world/furniture/Shelving.gd` / `LightStorage.gd` —
  `on_f_interact()` returns bool (consumed/not).
- `scripts/world/furniture/TrashCan.gd` — `merged_trash_data` state,
  `_live_count()`/`_total_count()`, `is_full()` override (combined
  count), three-way F logic (throw away / collect at any fill / merge
  bag), `_merge_bag()`, toast-based warnings.
- `scripts/world/items/TrashBag.gd` — `is_trash_bag` duck-type marker.
- `docs/systems/furniture-items/README.md`, `docs/systems/player/README.md`
  — Trash Can mechanics + the `on_f_interact()` bool contract.

### Verification checklist
(see plan `TRASH_CAN_F_DISPATCH_FIX_AND_MERGE_PLAN.md` for the full 8-item
in-editor checklist)

# Handover — Sobel Outline System (Full Rebuild of the Focus Highlight) (Aug 2026)

## What changed this session
Rebuilt the Focus Mode highlight from scratch as a Sobel edge-detection
outline system, per direct instruction to go full-send and design it for
reuse (tutorials, quest pointers, any future "highlight this object"
need). Replaces the Fresnel material_overlay approach entirely — the
structural reason, not a tuning preference: Fresnel only brightens
grazing-angle surfaces, so front-facing corners/creases (sharp edges to
the eye) stay dark; Sobel over the NORMAL buffer catches exactly those,
and Sobel over DEPTH catches silhouettes — together, the full
cel-shaded "ink line on every edge" look that was the goal.

Architecture: fullscreen clip-space quad whose Forward+ spatial shader
reads the depth + normal-roughness screen textures directly
(hint_depth_texture / hint_normal_roughness_texture — the fact that made
this buildable WITHOUT RenderingDevice/CompositorEffect-level work),
runs 3×3 Sobel kernels over both, hard-thresholds to crisp lines, and
multiplies by a per-object mask. The mask — the critical isolation pass
so only the ONE focused object gets lines, not every edge on screen —
is a SubViewport camera mirroring the main camera per-frame with
cull_mask = render layer 11 (confirmed unused project-wide before
claiming it), while the target's meshes get that layer bit ADDED
(originals saved/restored — main view unaffected). Mask sampled with
one pixel of dilation so boundary lines aren't clipped in half. Line
pixels emit past the scene's existing glow threshold, keeping the soft
bloom halo and pulse from the prior design.

Public API unchanged (`set_target(node_or_null)`) — InteractionSystem.gd
needed zero changes. Known boundary documented: transparent-material
targets outline poorly (no depth/normal buffer writes); no current
object affected. Multi-target highlighting is the flagged extension
point (one instance + one layer per target), not yet built.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — full rewrite.
- `docs/systems/player/README.md` — glow entry replaced wholesale.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_SOBEL_OUTLINE_SYSTEM_PLAN.md` for the
full 8-item checklist)

# Handover — Focus Mode Glow Redesigned: Real Bloom Instead of a Sprite (Aug 2026)

## What changed this session
Removed the Sprite3D halo entirely from the Focus Mode glow feature —
it read as a flat, fixed-shape gradient decal stamped at the object's
center, unrelated to the object's actual size or silhouette, regardless
of tuning. Confirmed the project's `WorldEnvironment`
(`scenes/world/MainWorld.tscn`) already has real HDR bloom active
(`glow_enabled = true`, `glow_hdr_threshold = 1.4`, `glow_intensity =
0.55`) before building on it. The rim shader now outputs bright
`EMISSION` at the same fresnel-masked edges the outline's `ALPHA` already
uses, so once those edge pixels cross the scene's existing glow
threshold, Godot's own renderer generates the surrounding glow as a real
post-process — it follows whatever the object's actual rendered
silhouette is (tall/thin objects bloom tall/thin, wide/flat ones bloom
wide/flat), rather than a generic circle. Tuned tight/contained per
direct instruction: steep fresnel falloff (unchanged from the prior fix,
`rim_power = 5.0`) plus a modest, single internal `EMISSION_BOOST`
constant (`3.0`) rather than a wide atmospheric spread. No changes to
`MainWorld.tscn` or the `Environment` resource itself — this works
entirely within glow settings already active project-wide, so nothing
else in the scene is affected by this change.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — halo `Sprite3D` and its
  builder function removed entirely; rim shader gained an `EMISSION`
  output; `_process()`/`_ready()` simplified accordingly.
- `docs/systems/player/README.md` — redesign note appended to the
  existing glow entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_GLOW_BLOOM_REDESIGN_PLAN.md` for the full 6-item checklist)

> **Trash Can + Trash Bag (Aug 2026):** New buildable (tile 36, $50, Construct → Furniture):
> 10-slot Light Storage whose F empties a FULL can into a runtime-only `TrashBag.gd` handed
> straight to the player (same safe player-side spawn as carry-retrieval); E always opens the
> shared StorageUI, retrieval never disabled. Full per-item snapshot via the generic
> `TrashCan.extract_trash_record()` reflection capture (excludes `TYPE_OBJECT` props). Also the
> project's first AMBIENT hover panel (`TrashBagInfoPanel.gd` — new UI category: proximity
> scan, non-modal, non-input-blocking) showing the nearest bag's prompt + contents. Light
> Player-thread coordination: the panel only reads `player_ref` position + `get_held_item()`.
> Fix (same feature): `CylinderShape3D` has no top/bottom taper (only `CylinderMesh` does) —
> collision now uses a single uniform `radius` (0.24, the wider top) so it fully encloses the
> tapered visual instead of using the invalid top/bottom properties, caught on first
> build-mode entry.

> **Cooking pot cleaning immunity widened (Aug 2026):** Corrected from last pass — a pot on a
> stove is now untouchable by Cleaning the whole time it's hosted there, not just while actively
> cooking. `is_actively_cooking()` → `is_on_stove()`.

> **Stuck-detection core fixes + live re-targeting + cooking-pot immunity (Aug 2026):** Traced
> the "endless loop" report to two compounding bugs — obstruction detection blind to walls, and
> a streak counter that never reset — both now fixed, see README's own entry for the full
> mechanism. Also added live re-targeting for every job's loose-item fetch (items that roll away
> mid-approach are now actually followed, not walked-to-where-they-were), and made an
> actively-cooking pot immune to being cleaned up, both at the JobBoard scan level and as
> defense-in-depth in `grab_loose()` itself.

# Handover — Rim Outline Restricted to Edges (Reverted to Fresnel Shader) (Aug 2026)

## What changed this session
Fixed the Focus Mode glow rendering as a nearly-fully-white object
instead of an edge outline (confirmed via screenshot). Root cause:
`StandardMaterial3D.rim_enabled` (the native-material approach from the
prior session) is an ADDITIVE lighting-response term at grazing angles
— it does not mask or restrict the base material to the edges. The base
`albedo_color`/`emission` was rendering across the entire mesh surface
uniformly; `rim` only added a bit more brightness on top of that at the
silhouette. Reverted to a Fresnel `ShaderMaterial`, the only technique
that genuinely restricts color to the edges, by driving the shader's
ALPHA output directly from the fresnel term (near-zero facing the
camera, near-full at grazing angles) rather than layering a bonus on an
already-opaque surface. Used standard alpha blending (not additive) and
a steeper falloff (`rim_power = 5.0`, up from 2.5–3.0 in earlier
attempts) to also address the original "too intense" complaint in the
same pass, since both trace back to the same underlying "isn't actually
restricted to the edges, or is too broad" category of problem. Halo and
pulse logic confirmed correct throughout this whole investigation and
left completely untouched.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — rim material reverted to a
  Fresnel `ShaderMaterial`; `RIM_BASE_INTENSITY`/`RIM_BASE_ALPHA`
  consolidated back to a single constant.
- `docs/systems/player/README.md` — correction note appended to the
  existing glow entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_GLOW_RIM_SHADER_REVERT_PLAN.md` for the full 5-item checklist)

> **Stuck-recovery grace period + Cooking stove-power fix (Aug 2026):** Jobs no longer get
> aborted on a single 1-second snag — `_recover_from_stuck()` (still broken, separately
> tracked) now only fires after 4 continuous seconds of no progress, shared across all jobs.
> Cooking now correctly detects an unpowered stove, messages the player with an NPC-attributed
> error instead of silently assuming success, and — critically — a new target-finder tier means
> a fully-loaded, never-lit pot is no longer invisible to future "Cook a meal" commands once
> power comes back.

> **CleaningActivity indentation fix (Aug 2026):** Root cause of both the "items stacking" and
> "relocate fix doing nothing" reports — a one-tab transcription error in the previous plan
> unindented the pickup-attempt block out from under `if npc.held_item == null:`, making it run
> every tick unconditionally and making everything below it (Relocate phase, Travel phase)
> unreachable dead code. Fixed with a pure re-indentation, no logic changes.

> **Stuck-recovery held-item fix (Aug 2026):** Fixed both reported regressions from the
> previous stuck-recovery passes — obstructions not being picked up, and items stacking inside
> each other — with one fix: `_recover_from_stuck()` drops whatever's currently held before
> making any recovery decision, since `force_command()` bypasses the normal scoring
> `PutAwayHeldItemActivity` needs to clean up a leftover held item on its own. See README's own
> entry for the full mechanism.

> **Stuck-recovery relocate fix (Aug 2026):** Forced stuck-recovery grabs with no real
> destination now genuinely relocate the item (real pathed walk, `RELOCATE_DISTANCE` = 2.5m,
> random direction) instead of picking it up and setting it back down in the same spot. Closes
> the gap where the "last resort, pick it up to get unstuck" mechanism didn't actually move
> anything when no storage existed for that item.

> **Cooking job (Aug 2026):** New "Cook a meal" Talk-menu command. Command-only for now —
> `CookingActivity` is a full `NPCSessionActivity` underneath, so autonomous scoring is a
> follow-up that only touches its own `score()` (see the comment there for the exact formula
> shape) plus wiring `NPC.COOKING_BASE_SCORE`/`get_job_priority_weight("COOKING")`, nothing
> structural. One command = one target (nearest actionable stove, priority: serve ready dish >
> finish in-progress pot > start new pot) — does NOT sweep every stove in one session like
> Refuel does across generators; flagged as a natural, easy follow-up if a full sweep is
> wanted later. `Stove.gd`/`CookingPot.gd` untouched — both already had generic, NPC-ready
> APIs. If a "cooking" skill is ever added to `NPC.skills`, this job's `npc.log_action()` calls
> are the natural place to add matching `gain_skill("cooking")` calls (deliberately omitted
> this pass — see README entry).

> **Stuck-recovery fix (Aug 2026):** Fixed the reported "NPCs freeze then glitch-teleport
> through walls and disappear" bug — root cause was `has_cleaning_target_available()` not
> checking for destination existence (only clutter existence), which fed a false "stalled
> travel" signal into `_tick_stuck_recovery()` on levels with zero shelving. That cascaded into
> a second, independent bug: `_recover_from_stuck()`'s no-obstruction fallback had a streak
> counter that could never actually escalate, so it repeated an uncapped blind random-direction
> position teleport forever. Both fixed — see README's own entry for the full mechanism.
> **Not fixed, flagged for later:** the capped nudge (`_nudge_free_of_obstruction`) still has no
> actual collision/geometry check before committing a teleport — it can still theoretically
> land an NPC inside geometry within its now-limited `STUCK_UNKNOWN_GIVEUP_AFTER` attempts, just
> far less likely (3 rolls instead of infinite). A real fix would raycast/validate the
> destination before committing to it — out of scope for this pass, which specifically targeted
> the reported infinite-loop symptom.

> **Command-wrapper consolidation (Aug 2026):** `CommandRestActivity`/`CommandHarvestActivity`/
> `CommandJobActivity` now extend `NPCCommandWrapperActivity`, matching Cleaning/Refuel/
> Gardening's Command variants. All three now correctly delegate `debug_info()` — previously
> silent gaps in "Print NPC Job Debug State" for anything started via a player command through
> these three. No external call sites changed (`CommandJobActivity`'s `_init(job_type)`
> signature is preserved). `CommandRestActivity.enter()` is a documented override, not a bug —
> see its own file header for why.

# Handover — Grow Light Pass-1 Gap Fixed, Glow Rebuilt on Native Materials (Aug 2026)

## What changed this session
Both fixes from the prior plan had no visible effect in testing;
investigated and found real, different root causes for each rather than
re-tuning the same approach.

**Grow Light:** the Ctrl-gated exclusion only landed in Pass 2 of both
`_nearest_generic_interactable()` (real `E` dispatch) and CASE 2's
prompt-candidate builder — each of these functions runs two passes (an
Area3D-driven one, and a StaticBody3D group-scan fallback for when
Jolt's Area3D detection misses static bodies, which the file's own
long-standing comments already describe as "unreliable," not
"nonexistent"). Pass 1 had zero Grow Light awareness in either function,
and evidently catches it often enough in real testing that the Pass-2-
only fix never ran. Added the identical exclusion to Pass 1 in both.

**Glow:** switched entirely away from a hand-rolled Fresnel
`ShaderMaterial` to Godot's built-in `StandardMaterial3D` rim/emission/
transparency properties. The prior blend-mode change (`blend_add` →
`blend_mix`) produced zero visible difference in testing, which points
at an assumption about how `GeometryInstance3D.material_overlay`
composites a custom shader's `render_mode` declaration that isn't fully
verifiable without running the engine directly — rather than continue
tuning numbers on an approach that may not be behaving as modeled, this
uses engine-native, GUI-inspectable, documented material properties
instead: `rim_enabled`/`rim`/`rim_tint` (Godot's own fresnel/edge-glow
implementation), `transparency`/`albedo_color` alpha (direct opacity),
and `emission`/`emission_energy_multiplier` (baseline visibility
independent of scene lighting).

### Files modified
- `scripts/player/InteractionSystem.gd` — Grow Light exclusion added to
  Pass 1 of both affected functions.
- `scripts/player/InteractionFocusGlow.gd` — rim material rebuilt on
  `StandardMaterial3D`, replacing the custom `ShaderMaterial`/GLSL
  entirely.
- `docs/systems/player/README.md` — correction notes appended to both
  existing entries.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_GROWLIGHT_PASS1_AND_GLOW_REBUILD_PLAN.md` for the full 6-item
checklist)

> **Needs-activity relocation (Aug 2026):** Completed the deferred cleanup item from the prior
> consolidation handoff. All 19 Needs/Command activity classes (previously inner classes of
> `NPCBrain.gd`) are now standalone top-level scripts in `scripts/npc/activities/`, exactly
> matching the Cleaning/Refuel/Gardening pattern. `NPCBrain.gd` dropped from ~1682 lines to
> ~196 — state machine only. Zero behavior change; verify by diffing each new file's body
> against `NPCBrain.gd`'s git history if anything looks off. All external `NPCBrain.XActivity`
> call sites (`NPC.gd`, `NPCTalkMenuUI.gd`) updated to bare `XActivity`.

# Handover — Glow Tuning + Grow Light Fully Hidden Outside Focus Mode (Aug 2026)

## What changed this session
Two follow-ups to the Focus Mode glow feature. (1) Tuning: the rim
outline was using additive blending (`blend_add`), which has no real
concept of opacity — it just stacks brightness on top of whatever's
behind it, reading as too intense/washed-out rather than solid. Switched
to standard alpha blend (`blend_mix`) so its `ALPHA` output genuinely
controls opacity; raised halo alpha and pulse amplitude per direct
feedback ("less intense (more opaque)", "pulsing slightly more
intense"). (2) New: Grow Light is now fully hidden and non-interactable
outside Focus Mode — not just de-prioritized as before, genuinely absent
(no prompt, `E` does nothing to it) unless Ctrl is held. Purpose: a
standard farming setup with many trays and a grow light over each was
filling the view with hovering prompts; Focus Mode is now the sole
intended way to reach one. Needed the same exclusion in two places
(CASE 2's prompt-candidate scan and the real `E`-dispatch scan), both
gated behind the same Ctrl check already used elsewhere in this file.
Confirmed `GrowLight.gd` doesn't implement `set_player_in_range()`, so
that unrelated mechanism needed no changes. Water Hookup is deliberately
unaffected — far fewer per bunker, not part of this request.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — rim material blend mode,
  intensity, halo alpha, and pulse amplitude retuned.
- `scripts/player/InteractionSystem.gd` — Grow Light excluded from both
  the CASE 2 prompt-candidate scan and `_nearest_generic_interactable()`
  outside Focus Mode.
- `docs/systems/player/README.md` — tuning follow-up appended to the
  existing glow entry; new entry for the Grow Light visibility change.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_GLOW_TUNING_AND_GROWLIGHT_HIDDEN_PLAN.md` for the full 7-item
checklist)

---

# Handover — Focus Mode Target Glow: Rim Outline + Soft Halo (Aug 2026)

## What changed this session
Added a visual highlight for Focus Mode (hold Ctrl): whatever object is
currently the resolved focus target gets a white rim-light outline plus
a soft halo, both gently pulsing, so it's visually obvious which object
Ctrl is pointing at — especially useful for the Grow Light/Water Hookup
priority work from the last two sessions, where the highlighted object
is often not the closest/most obvious one in view.

New `scripts/player/InteractionFocusGlow.gd`, a self-contained `Node3D`
child of `InteractionSystem` (not the `_owner`/`RefCounted` pattern used
by `InteractionProximityScan.gd` — this one needs real scene presence).
Rim outline uses `GeometryInstance3D.material_overlay` (verified real
Godot 4 functionality before building on it) to add an extra Fresnel-
shader render pass to every `MeshInstance3D` found recursively under the
target — nothing about the target's own material or mesh is touched,
which is what makes this work uniformly across procedural meshes, GLB
imports, and multi-part assemblies without any item file needing
changes. Halo is a `Sprite3D` with a procedurally-generated radial
gradient texture (no external asset). Driven by the same Ctrl check
already established for the E-interact-parity fix, applies to whatever
`focus_idx` resolves to generically — no per-object special-casing.

Defensively checks `is_instance_valid()` on the target every frame in
its own `_process()`, learned directly from this session's earlier
freed-reference investigation — self-heals rather than risks touching a
dangling reference if the glowing object is removed mid-highlight.

### Files modified
- `scripts/player/InteractionFocusGlow.gd` — new file.
- `scripts/player/InteractionSystem.gd` — instantiates and drives the
  new node; clears it on every `_update_prompt()` early exit, sets it
  from the CASE 2 Focus Mode computation.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_FOCUS_MODE_GLOW_PLAN.md` for the full 7-item checklist)

---

# Handover — E-Interact Parity With Focus Mode's Highlight (Aug 2026)

## What changed this session
Fixed a gap in the Grow Light/Water Hookup Focus Mode work: the prior
plan made both unconditional #1 priority in what Focus Mode *displays*
(`_update_prompt()`'s `focus_idx`), but real `E` dispatch
(`_try_interact()`, via `_nearest_generic_interactable()`) had zero
awareness of Ctrl being held, so it kept resolving to whatever was
genuinely closest regardless — meaning `E` could interact with a
different object than the one being highlighted the entire time Ctrl
was held (reported: Water Hookup/Grow Light shown correctly as the sole
prompt, but pressing `E` still hit a nearer Wall Light or the tray).

`_nearest_generic_interactable()` now polls `Input.is_key_pressed
(KEY_CTRL)` directly (same passive-polling pattern already used
elsewhere in this file and in `InteractPrompt.gd`'s own Focus Mode
filter) and applies the identical "nearest Grow Light or Water Hookup
wins outright" rule `focus_idx` uses, but strictly gated behind Ctrl
being held — with Ctrl up, this is a proven no-op, plain `E` stays pure
fair distance. Since the shelf E-priority fairness check already reads
this same function, it correctly picks up consistent behavior too, with
no separate change needed there.

Noted one narrow pre-existing edge case rather than chasing it: CASE 2's
prompt list caps at `MAX_VISIBLE_PROMPTS` (3) before `focus_idx` is
computed, so in a spot with 4+ simultaneous interactables the display
and the real `E`-target could theoretically diverge — existing
characteristic of prompt-capping generally, out of scope here.

### Files modified
- `scripts/player/InteractionSystem.gd` — `_nearest_generic_interactable()`
  gains a Ctrl-gated Grow Light/Water Hookup priority override, mirroring
  `focus_idx`'s rule exactly.
- `docs/systems/player/README.md` — follow-up paragraph appended to the
  prior Grow Light + Water Hookup entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_FOCUS_MODE_E_INTERACT_PARITY_PLAN.md` for the full 5-item
checklist)

---

# Handover — Grow Light + Water Hookup Focus-Mode Priority: Re-Applied, Broadened, and a Merge-Revert Postmortem (Aug 2026)

## What changed this session
Discovered (via `git log`) that the prior "Water Hookup priority
corrected to Focus-Mode-only scope" fix (`3ccd877`) had been silently
reverted by a later merge commit (`f1b6c7e`, "Merge remote changes and
retain local GardeningActivity stack overflow fix...") — its conflict
resolution landed on the pre-fix version of the same `InteractionSystem.
gd` region (45 lines changed in both commits, same area). No revert
commit, no visible signal it happened; only surfaced because the
in-game behavior regressed and got reported. Re-applied the fix fresh
against current code rather than trusting the old diff blindly.

While re-applying, also fixed the same unscoped-priority problem for
Grow Light, which had never actually been Focus-Mode-scoped at all — it
always lived in `_nearest_generic_interactable()` (real `E` dispatch),
so it had been winning both in and out of Focus Mode this whole time.
Moved to `_update_prompt()`'s `focus_idx` computation alongside Water
Hookup, and broadened both from "only wins if the closest entry happens
to be [FarmingTray]" to "unconditional #1 whenever anywhere in the
current prompt set" — per direct instruction. Both `GrowLight` tiers
("normal"/"pro") are covered by the existing single `"grow_light"`
group regardless of tier, confirmed by reading `GrowLight.gd` directly.

Outside Focus Mode, both objects are now back to ordinary fair-distance
`E`-dispatch priority — `_nearest_generic_interactable()` has zero
special-casing for either group anymore.

### Files modified
- `scripts/player/InteractionSystem.gd` — both overrides removed from
  `_nearest_generic_interactable()`; both added (broadened, unconditional)
  to `_update_prompt()`'s `focus_idx` computation.
- `docs/systems/player/README.md` — Water Hookup entry replaced with a
  combined Grow Light + Water Hookup entry.
- `HANDOVER.md` — this entry.

### Process note for future sessions
Worth a heads-up for whoever's merging branches on this file going
forward — `InteractionSystem.gd` has now had at least one real bug fix
silently lost to a merge conflict resolution this session. Might be
worth a quick diff review against the pre-merge state specifically for
this file after any future merge touching it, given how much active
work keeps landing here across multiple threads.

### Verification checklist
(see Player subsystem plan
`PLAYER_GROWLIGHT_WATERHOOKUP_FOCUS_REAPPLY_PLAN.md` for the full
6-item checklist)

---

## NPC: Systems Consolidation Pass (Aug 2026)

Ran the consolidation pass Brannon asked for after flagging feature-
creep/backend-complexity concerns. Extracted the patterns that had been
independently hand-copied (and independently gone wrong) across
Cleaning/Refuel/Gardening into shared, reusable infrastructure, and
split both god-files (NPC.gd was 2,681 lines, NPCBrain.gd was 2,842)
along real seams.

New shared infrastructure:
- NPCSessionActivity.gd — base for every fetch->travel->apply->loop
  job. Non-interruptible by default (the bug found and fixed three
  separate times before this existed), a shared _skipped exclusion-set
  mechanism (the bug that caused Cleaning's frame-stall AND Gardening's
  stack-overflow crash — same root cause, fixed twice separately before
  this), shared approach-point math, shared display-name fallback,
  shared exit()-velocity-zero + early-exit logging.
- NPCCommandWrapperActivity.gd — base for the three "player pressed a
  Talk-menu button" wrappers. Found while writing this that ALL THREE
  were independently missing debug_info() delegation — a real,
  previously unnoticed gap (Print NPC Job Debug State showed nothing
  for any command-driven session) that this consolidation fixes by
  construction.
- NPCJobQueries.gd — every Cleaning/Refuel/Gardening "is a target
  available, and where" query, extracted from NPC.gd into a static
  utility class (mirrors NPCItemUser.gd's existing convention). NPC.gd
  keeps one-line delegating wrappers with identical names/signatures,
  so no external call site changed.
- NPCJobState.gd — the Cleaning give-up/blacklist system, composed onto
  NPC.gd as npc.job_state instead of living as loose instance vars —
  the natural home for any future per-NPC "remembers this didn't work"
  state a new job type needs.

Rebuilt on the new base (moved to scripts/npc/activities/, one file
each): CleaningActivity (relocated + adopted shared exit/display-name
only — its own proven-correct target-selection loop is UNCHANGED,
deliberately not forced into a rigid shared template), RefuelActivity,
GardeningActivity (also fixes the still-live recursion bug from the
last plan by construction), CommandCleaningActivity,
CommandRefuelActivity, CommandGardeningActivity, PutAwayHeldItemActivity.

Deliberately deferred to a later, purely-mechanical pass: relocating
the unrelated Needs-based activities (Wander/Sit/Drink/Eat/Talk/
GiveToFriend/JobActivity and their variants) that already lived in
NPCBrain.gd — none of this work ever touched them, so moving them is
zero-risk but adds no functional value to bundle into this pass.

Files touched/added: scripts/npc/activities/NPCSessionActivity.gd (new),
scripts/npc/activities/NPCCommandWrapperActivity.gd (new),
scripts/npc/activities/CleaningActivity.gd (new),
scripts/npc/activities/CommandCleaningActivity.gd (new),
scripts/npc/activities/RefuelActivity.gd (new),
scripts/npc/activities/CommandRefuelActivity.gd (new),
scripts/npc/activities/GardeningActivity.gd (new),
scripts/npc/activities/CommandGardeningActivity.gd (new),
scripts/npc/activities/PutAwayHeldItemActivity.gd (new),
scripts/npc/queries/NPCJobQueries.gd (new), scripts/npc/NPCJobState.gd
(new), scripts/npc/NPCBrain.gd, scripts/npc/NPC.gd,
scripts/ui/npc/NPCTalkMenuUI.gd, scripts/ui/menus/AdminMenu.gd,
scripts/npc/JobBoard.gd (doc comment only).

---

## NPC: Fixed Real Stack Overflow in GardeningActivity (Aug 2026)

- Root-caused and fixed a genuine crash: GardeningActivity._start_fetch()
  called _pick_next_task() recursively on failure, and _pick_next_task()
  recursed on itself on a cell-claim failure — neither had any exclusion
  tracking. If a soil/plant task's needed item type had zero instances
  anywhere in the level, nothing about the world changed between
  attempts, so it recursed identically forever, hitting Godot's call
  stack limit and crashing ("Stack overflow (stack size: 1024)").
  Checked RefuelActivity for the same pattern — it doesn't have this bug
  (it correctly ends the session on fetch failure instead of retrying).
- _pick_next_task() is now an iterative while-loop with a session-local
  _skipped_cells exclusion set (mirrors CleaningActivity's own
  _skipped_ids/_no_storage_categories for the identical class of
  problem) — bounded by the level's total cell count, guaranteed to
  terminate. _start_fetch() now returns bool instead of recursing.

Files touched: `scripts/npc/NPCBrain.gd`.

---

## NPC: Gardening Claim-Failure Logging (Aug 2026)

- GardeningActivity._pick_next_task() now logs when a cell-claim
  attempt fails due to another NPC's contention, instead of silently
  retrying — matches CleaningActivity's existing "claim failed"
  pattern. Explains what previously showed as unexplained duplicate
  "target picked" lines for the same cell.
- Verified (not a new bug): the interrupt/stuck logging and Gardening/
  Refuel non-interruptibility fixes from the prior plan are correctly
  live in code. A reported "Fetching soil -> Cleaning" transition with
  no INTERRUPTED: line contradicts that code (the branch that could
  produce it should be unreachable with interruptible() now false) —
  most likely a stale build from before that fix took effect. Flagged
  for a fresh post-restart capture rather than assumed to be a new bug.

Files touched: `scripts/npc/NPCBrain.gd`.

---

## NPC: Unified Farming Request, Full Interruption Fix, Comprehensive Debug (Aug 2026)

- Root-caused Sable's bug as a broader version of the earlier mid-carry
  interrupt fix: GardeningActivity/RefuelActivity were only non-
  interruptible during their FINAL sub-phase, leaving the walk-TOWARD a
  loose item (before ever picking it up) vulnerable to any high-scoring
  competitor (confirmed: clutter-escalated Cleaning) winning the next
  think-cycle (~1s) and aborting the approach — explaining why closer
  items succeeded and farther ones didn't. Both now return `false` from
  interruptible() (matching PutAwayHeldItemActivity's existing "short
  and self-contained" precedent) — non-interruptible for the whole
  session, with stuck-recovery's stop_current() unaffected since it
  never went through interruptible() in the first place.
- Unified Harvest/Plant/Soil into one "Tend the farm" Talk-menu request
  (GardeningActivity mode "farming"): strict priority harvest -> plant
  -> soil, ends when none apply anywhere. Autonomous Harvest (JobBoard)
  and autonomous soil/planting (mode "auto") are unchanged — this is a
  new command-only path only. Planting now always reads each cell's own
  seed lock/replant memory — the seed-type-selection popup
  (NPCSeedSelectMenuUI.gd) is retired/deleted, no longer needed.
  Fertilizer stays its own separate, command-only request.
- Comprehensive debug expansion: NPCBrain._think() now logs the exact
  score comparison behind every interrupt decision
  (NPCDebug.log_interrupt()); NPC._recover_from_stuck() now attaches
  the current activity's label + debug_info() to the stuck log
  (NPCDebug.log_stuck() signature expanded); added GardeningActivity/
  RefuelActivity debug_info() and early-exit logging (mirrors
  CleaningActivity's existing pattern); added a new generalized F7
  dump, "Print NPC Job Debug State"
  (NPCDebug.dump_job_state()), showing every NPC's current activity and
  full debug info regardless of activity type, complementing the
  existing Cleaning-specific dump.

Files touched: `scripts/npc/NPCBrain.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCDebug.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`; deleted
`scripts/ui/npc/NPCSeedSelectMenuUI.gd`.

---

# Handover — Water Hookup Priority Corrected to Focus-Mode-Only (Aug 2026)

## What changed this session
Corrected a bug in the prior "Water Hookup Unconditional E-Priority"
plan: it gave Water Hookup unconditional priority whenever in reach,
but implemented it inside `_nearest_generic_interactable()`, which
turned out to be reached only by real `E` dispatch (`_try_interact()`)
— Focus Mode had already been rewritten in a separate pass to compute
its own `is_focus_target` tag independently, no longer calling that
function at all. Net effect: the override was silently controlling
plain `E` presses (making a nearby Water Hookup always win, even
without Ctrl held) while having zero effect on Focus Mode itself — the
exact opposite of the intended scope.

Removed the override from `_nearest_generic_interactable()` (plain `E`
is back to fair-distance-only) and added the equivalent to
`_update_prompt()`'s `focus_idx` computation instead — the thing
`InteractPrompt.gd`'s Focus Mode filter actually reads, and which is
only ever consulted while `Ctrl` is held. Mirrors the existing
grow-light-over-tray swap already present in that same computation.

### Files modified
- `scripts/player/InteractionSystem.gd` — Water Hookup override moved
  from `_nearest_generic_interactable()` to `_update_prompt()`'s
  `focus_idx` computation.
- `docs/systems/player/README.md` — prior Common-edits entry corrected
  in place (not duplicated) to describe the current, correct behavior.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_WATER_HOOKUP_FOCUS_MODE_SCOPE_FIX_PLAN.md` for the full 5-item
checklist)

---

## NPC: Fixed Gardening/Refuel Getting Interrupted Mid-Carry (Aug 2026)

- Root cause: GardeningActivity.interruptible() only protected the final
  "apply" sub-phase, Refuel only "refuel" — both left the
  fetch-complete-through-travel window (physically carrying the soil
  bag/seed packet/fuel can) interruptible, and PutAwayHeldItemActivity's
  flat score (20.0) beat both (Gardening ~6.2 + 8.0 margin, Refuel ~10.4
  + margin) on the very next think-cycle (~1s later). Result: carry
  interrupted, item dropped in place almost immediately, then straight-
  line drift. (Not yet reported for Refuel, but same math — fixed
  alongside rather than waiting to see it separately.)
- interruptible() now checks `_item == null` (Gardening) /
  `_can == null` (Refuel) — non-interruptible for the item's ENTIRE held
  lifecycle, matching CleaningActivity's existing pattern.
- Defensive: both PutAwayHeldItemActivity drop branches (enter() and
  tick()) now zero `npc.velocity` when the item is dropped in place, so
  the NPC isn't left coasting in whatever direction it was last walking.

Files touched: `scripts/npc/NPCBrain.gd`.

---

## NPC: Fixed Cleaning Frame-Stall on No-Storage Levels (Aug 2026)

- Root-caused a real performance bug from a live debug capture:
  CleaningActivity._pick_next_target()'s retry loop re-evaluated every
  remaining organizable item from scratch on every failed attempt
  (including a fresh raycast-driven candidate search per item), even
  after a category was already confirmed hopeless this session. On a
  level with clutter but zero storage anywhere, this meant a
  synchronous burst of up to N full candidate scans in one frame,
  presenting as "1fps snapping" every time a Cleaning session started.
- find_cleaning_target() now takes an exclude_categories param
  (NPC.gd) — CleaningActivity passes its own _no_storage_categories in,
  so a confirmed-hopeless category's items are filtered out before ever
  being raycasted or re-selected. Bounded by category count (2), not
  item count, regardless of clutter volume.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`.

---

## NPC: Gardening Migrated to Per-Cell Farming API + Seed Locks (Aug 2026)

- Reconciled with the Farming thread's per-cell FarmingTray API
  (fill_soil_at_cell/plant_seed_at_cell/get_cell_seed_lock, replacing the
  old tray-wide fill_first_open_soil_cell/plant_first_open_cell).
  Removed my own now-redundant assigned_plant_type/
  get_next_plant_preference() (a placeholder for exactly the feature the
  Farming thread has now actually built) — last_planted_type (soft
  replant preference, distinct from a hard lock) stays.
- GardeningActivity rewritten to operate per-CELL, not per-tray, mirroring
  HARVEST's existing one-job-per-ready-plant shape — a double tray's two
  cells can now be worked by two different NPCs simultaneously. Added a
  matching per-cell claim system (NPCItemUser.claim_cell()/release_cell()/
  is_cell_claimed_by_other()) to prevent two NPCs targeting the same cell.
- Seed locks (get_cell_seed_lock()) are respected as an ABSOLUTE
  constraint by both autonomous planting and player-forced type
  requests — never substituted, cell skipped silently if the locked
  type isn't in stock, exactly per the Farming thread's own recommended
  discovery logic.
- Added BagOfSoilItem.apply_at_cell()/SeedItem.apply_at_cell() — thin,
  index-aware siblings to on_use(), needed because on_use() resolves the
  nearest cell to the ITEM's position, which is no longer guaranteed to
  be the specific cell an NPC claimed and walked to. Mirror on_use()'s
  charge/signal/cleanup logic exactly; nothing about consumption is
  duplicated elsewhere.
- Fertilizer intentionally NOT touched — stays tray-wide/on_use()-based,
  per the Farming thread's explicit note that FertilizerItem is likely to
  change shape in a follow-up pass.

Files touched: `scripts/npc/NPCItemUser.gd`,
`scripts/world/farming/FarmingTray.gd`, `scripts/world/items/BagOfSoilItem.gd`,
`scripts/world/items/SeedItem.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/JobBoard.gd`.

---

## NPC: Gardening (Soil/Plant/Fertilize) + Seed-Type Menu + Basket Produce Cleanup (Aug 2026)

- Added FarmingTray.last_planted_type (survives harvest, unlike
  planted_type) and assigned_plant_type (unused placeholder for a future
  gardening-side tray-assignment feature — already wired into
  get_next_plant_preference()'s priority order so no NPC code will need
  to change once that ships).
- Added NPCBrain.GardeningActivity/CommandGardeningActivity — session
  activity mirroring Cleaning/Refuel's shape. Mode "auto" (autonomous,
  soil+planting, replant-preference-aware) is the default; "soil_only",
  "plant_only" (with forced_seed_type, no fallback substitution), and
  "fertilize_only" back the three player commands. Fertilizing is
  reachable ONLY via command, never autonomous. Reuses each consumable
  item's own real on_use() (BagOfSoilItem/SeedItem/FertilizerItem) rather
  than duplicating charge/consumption logic — identical mechanic to the
  player by construction.
- Added NPCTalkMenuUI rows for "Add soil to all trays" and "Fertilize
  the trays" (direct commands), and "Plant seeds" (opens a new standalone
  popup, NPCSeedSelectMenuUI.gd, listing only currently-in-stock seed
  species — built on the same UIKit modal helpers every other popup in
  the project uses).
- CleaningActivity now special-cases FarmProduceItem: if a Basket is
  available, fetches it first and stashes produce into it (mirroring
  Basket.gd's real "E while holding basket" player mechanic) instead of
  hand-carrying each item individually, then delivers the basket to
  storage once done. All other item types are unaffected.

Files touched: `scripts/world/farming/FarmingTray.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/npc/NPCSeedSelectMenuUI.gd` (new).

---

## NPC: Glitch Detection, Scoped Give-Up System, Exponential Idle Gate (Aug 2026)

- JobBoard._scan_cleaning() now excludes any item outside sane Y bounds
  (CLEANING_SANITY_Y_MIN/MAX, -20..30) from the cleaning system entirely,
  at the source, for every NPC at once — root fix for NPCs targeting/
  huddling around items that had fallen/glitched far outside the bunker
  (two NPCs were observed at Y≈-140000/-58000 in one session).
  flat_distance() deliberately ignores Y, so this is the check that
  actually catches a pure vertical fall-through.
- Confirmed (no code change): Bag of Soil/Fertilizer/etc. only ever
  spawn via a Farming Shop purchase — no other spawn path exists, so
  their appearance was never a debug leftover.
- Added a narrowly-scoped, permanent-per-NPC give-up system
  (NPC._cleaning_blacklist): a stuck-recovery streak on the same item
  reaching 2, or 2 genuine in-range pickup failures
  (record_cleaning_pickup_failure()), permanently removes that item from
  that NPC's candidates. Routine contention (claim lost to another NPC,
  became held/shelved before arrival) is explicitly excluded and stays
  infinitely retryable — this only targets confirmed unreachability, not
  normal cleaning traffic.
- JobBoard._effective_cleaning_idle_min_sec() now scales with
  get_total_clutter_count(): 90s at 0 clutter, exactly 0s at 20
  (CLUTTER_IDLE_ZERO_AT), via an exponential curve
  (CLUTTER_IDLE_CURVE_POWER = 4.0) that stays close to 90s until nearing
  the cap, then drops sharply. Debug override (F7) still always wins.

Files touched: `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`.

---

---

# Handover — Water Hookup Unconditional E-Priority (Aug 2026)

## What changed this session
Fixed Water Hookup losing E-priority to nearby lower-mounted wall
objects (wall lights, breaker boxes, etc.) — being mounted high on the
wall meant it was almost always physically farther from a
ground-standing player than whatever else happened to share that wall,
so it kept losing the fair-distance comparison in
`_nearest_generic_interactable()`. Gave it a new `"water_hookup"`
duck-type marker group (`WaterHookup.gd`, mirrors the existing
`"grow_light"`/`"farming_tray"` pattern) and an unconditional top-
priority override in `_nearest_generic_interactable()` — unlike the
narrow grow-light-over-tray override (beats one specific named rival
only), this one is deliberately unscoped: a Water Hookup can end up near
any number of different wall-mounted objects depending on how a given
bunker is furnished, so there's no single fixed rival to name.

Worth noting explicitly: because both the real `E` dispatch
(`_try_interact()`) and Focus Mode's highlight
(`_resolve_current_e_target()`) share this same function by design, this
also makes a plain `E` press (not just Ctrl/Focus Mode) always resolve
to a nearby Water Hookup. Considered scoping the override to only affect
Focus Mode and leave real dispatch alone, but that would let the two
disagree — worse than the original bug, and against the entire point of
the shared-resolver design. Implemented as a genuine always-on priority
instead, per direct instruction.

### Files modified
- `scripts/world/water/WaterHookup.gd` — new `"water_hookup"` group
  registration.
- `scripts/player/InteractionSystem.gd` —
  `_nearest_generic_interactable()` gains the unconditional Water
  Hookup override, applied after the existing grow-light override.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_WATER_HOOKUP_E_PRIORITY_PLAN.md` for
the full 6-item checklist)

---

---

# Handover — Preview Scale Normalization + CanCase/WaterCase Blank Fix (Aug 2026)

## What changed this session
Ported `BuildModeHUD.gd`'s preview-normalization logic into
`ItemPreviewKit.gd`, fixing two reported bugs: the Crate rendering way
too large relative to other items in Shelf/Inventory previews (no scale
normalization existed at all before this), and Can Case/Water Case
rendering as a blank preview (their 12 can/bottle meshes sit nested
under `VisualRoot/Can_XX`/`Bottle_XX`, 2+ levels deep — the old preview
code only checked direct children). Added `_combined_local_aabb()` (deep
mesh walk) and `_preview_normalize_scale()` (uniform fill-fraction
scaling, re-derived as a fraction of each consumer's own `cam.size`
rather than Build's fixed-meters constant, since this kit serves two
different preview pixel sizes). New `_duplicate_visual_tree()` builds a
lightweight mesh-only copy of an item's full visual tree (material
overrides preserved, hidden meshes skipped) for the deep-walk case.
Also fixed `clear()`, which would have silently stopped matching
anything once `set_item()` started wrapping content in a pivot `Node3D`
instead of a bare `MeshInstance3D` — caught during this pass, not
previously live.

### Files modified
- `scripts/ui/common/ItemPreviewKit.gd` — see file for full diff.
- `docs/systems/ui/README.md` — `ItemPreviewKit.gd` note updated, new
  "Preview Scale Normalization + Deep Mesh Walk" subsection.

### Verification checklist
(see `PREVIEW_SCALE_NORMALIZATION_AND_BLANK_FIX_PLAN.md` for the full
6-item checklist)

---

---

## NPC: NPC-vs-NPC Crowd Gridlock Fix (Aug 2026)

- Root-caused the "NPCs huddle and shuffle forever" report: multiple
  NPCs converging on the same clutter hotspot (more likely now with the
  clutter-urgency change) physically block EACH OTHER, but
  _find_stuck_obstruction() only ever detects RigidBody3D colliders —
  another NPC (CharacterBody3D) was invisible to it, always logging "?"
  and falling back to a RANDOM-direction nudge, which had real odds of
  shoving an NPC straight into someone else.
- Added _find_stuck_obstruction_npc() and a separate NPC-blocking streak
  (_stuck_npc_streak). Now nudges directly away from the specific
  blocking NPC (not randomly), and escalates to a larger, more decisive
  displacement (STUCK_NPC_BACKOFF_DISTANCE, 2.5m) after
  STUCK_NPC_BACKOFF_AFTER (2) repeated jams instead of many small
  ineffective ones.
- _nudge_free_of_obstruction() now takes a distance parameter and a
  Node3D obstruction (was hardcoded to STUCK_NUDGE_DISTANCE and typed to
  RigidBody3D only).
- Known limitation, not addressed here: this is reactive (escape once
  crowded), not preventive (nothing stops multiple NPCs choosing the
  same hotspot in the first place). Flagged for a possible future
  target-selection-side pass if still an issue after this lands.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`.

---

---

## NPC: Clutter-Driven Cleaning Urgency + Held-Item Safety Net (Aug 2026)

- CleaningActivity.score() now scales with JobBoard.get_total_clutter_
  count() (ready trash + ready organizable + still-settling items) via
  NPC.CLUTTER_URGENCY_STEP, derived so an average-Work-Ethic NPC's
  Cleaning score crosses an average-Work-Ethic NPC's Wander score at
  ~11 total clutter items in the level.
- Added NPCBrain.PutAwayHeldItemActivity — a small, self-contained
  safety net that fires whenever an NPC is holding a loose item with
  nothing else claiming it (root cause: _recover_from_stuck() can
  stop_current() a CleaningActivity mid-carry, e.g. a second stuck event
  hitting while already holding something — CleaningActivity.exit()
  only ever released the item's CLAIM, never dropped/redirected a
  physically-held item, since that path assumed a claim release always
  meant "never picked it up"). Scores a flat, modest value (20.0) —
  enough to beat Wander/Relax/Sit/Lie/Talk, far below any genuine active
  need, so legitimate holds (Drink/Eat/GiveToFriend/Cleaning/Refuel) are
  unaffected.

Files touched: `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`.

---

---

## NPC: F7 "Make All NPCs Clean" (Aug 2026)

- Added a debug row that force_command()s every NPC in the "npc" group
  straight into CommandCleaningActivity at once, for fast test-clutter
  cleanup and to isolate job-picking issues from cleaning-behavior ones.

Files touched: `scripts/ui/menus/AdminMenu.gd`.

---

---

# Handover — Focus Mode Broadened to Cover Pickup-Only Objects (Aug 2026)

## What changed this session
Focus Mode (hold Ctrl, added earlier this session) wasn't showing
prompts for pickup-only objects like Test Crate (`"pickup"` group only)
or Fuel Can (`"interactable"` group but no `on_interact()`) — it was
built around "what would E do," which is the wrong question for objects
E can't act on. Redefined the focus target as "the closest object with
any prompt at all" (E or F), sourced directly from `_update_prompt()`'s
already-sorted CASE-2 candidates list instead of a separate E-only
resolver. Deleted `_resolve_current_e_target()` (fully dead after the
rewrite) and renamed the tag `is_e_target` → `is_focus_target` in both
`InteractionSystem.gd` and `InteractPrompt.gd` to match its broader
meaning.

### Files modified
- `scripts/player/InteractionSystem.gd` — CASE-2 tagging rewritten,
  `_resolve_current_e_target()` removed.
- `scripts/ui/hud/InteractPrompt.gd` — key renamed, doc comments updated.
- `docs/systems/ui/README.md` — "Focus Mode" section corrected.

### Verification checklist
(see `FOCUS_MODE_PICKUP_FIX_PLAN.md` for the full checklist)
---
---

# Handover — Shelf E-Priority Fairness + Grow Light Priority + Focus Mode Plumbing (Aug 2026)

## What changed this session
Fixed a shelf E-priority bug distinct from the held-item-priority fix
earlier this session: while empty-handed, a nearby shelf was winning E
unconditionally over any OTHER world interactable too (e.g. a generator
genuinely closer to the player), not just over held items. Fixed with
the same distance-fairness pattern already established in this handler
for stove-pot/ready-dish — "peek both, smaller wins." Centralized the
scan itself: `_try_interact()` and `_nearest_interact_distance()` were
two near-identical copies of the same RigidBody3D/StaticBody3D two-pass
scan; both now go through one shared `_nearest_generic_interactable()`.

Added a grow-light-over-tray override inside that same shared scan — a
`GrowLight` mounted directly above its `FarmingTray` was functionally
unreachable via E, since the tray sits almost exactly at the same
horizontal position and is essentially always the physically closer
candidate. Deliberately narrow: only overrides when a `FarmingTray`
specifically would otherwise win and a grow light is also in reach —
every other pairing resolves by genuine fair distance, unaffected.

Added `_resolve_current_e_target()`, a read-only empty-handed-only peek
mirroring the live dispatch's priority order exactly (shelf fairness →
ready-dish fairness → generic fallback), for a separate UI-thread Focus
Mode feature to tag which prompt E would actually fire — shares the
same underlying scan as the real dispatch, so the two can't drift apart.
Tagged onto CASE 2's prompt entries via a new `"is_e_target"` boolean key
(additive only, no existing entry keys touched).

### Files modified
- `scripts/player/InteractionSystem.gd` — new
  `_nearest_generic_interactable()` (absorbs `_try_interact()`'s and
  `_nearest_interact_distance()`'s scans, adds the grow-light override);
  `_try_interact()` simplified to use it; new `_nearest_shelf_distance()`;
  shelf E-dispatch now distance-fair against other interactables; new
  `_resolve_current_e_target()`; CASE 2 prompt entries gain
  `"is_e_target"`.
- `docs/systems/player/README.md` — new Common-edits entry.

### Cross-thread note
A separate UI-thread plan ("Focus Mode Prompt Filter") depends on this
one — order of application doesn't matter for crash-safety, but Focus
Mode only correctly highlights anything once this lands.

### Verification checklist
(see Player subsystem plan
`PLAYER_SHELF_FAIRNESS_GROWLIGHT_FOCUS_PLAN.md` for the full 6-item
checklist)

---

---

# Handover — Focus Mode (Hold Ctrl) for Interaction Prompts (Aug 2026)

## What changed this session
Added Focus Mode: holding `Ctrl` collapses every active interaction
prompt down to the single one `E` would actually trigger, filtering
`InteractPrompt.gd`'s `_active` list by a new `is_e_target` tag. Built
primarily as a debugging tool — used it to find and fix two real bugs in
`InteractionSystem.gd` (separate hand-off plan, Player thread): shelving
was winning `E` unconditionally over genuinely closer interactables, and
grow lights were unreachable because their tray sits directly beneath
them and always won on raw distance. Both fixed there; this prompt-side
change is purely rendering, no priority logic lives here.

Empty-handed only this pass — held-item prompts (baskets, cooking pots,
give-to-NPC, etc.) aren't filtered yet, by design (see
`docs/systems/ui/README.md`'s "Focus Mode" section for the reasoning).

### Files modified
- `scripts/ui/hud/InteractPrompt.gd` — Ctrl polling + `_active` filtering
  in `_process()`; `set_prompts()` doc comment updated for the new
  `is_e_target` key.
- (Companion Player-thread plan, applied separately) —
  `scripts/player/InteractionSystem.gd`: shelf E-priority fairness fix,
  grow-light-over-tray priority, new `_resolve_current_e_target()`.
- `docs/systems/ui/README.md` — new "Focus Mode" section.

### Verification checklist
(see `FOCUS_MODE_PROMPT_FILTER_PLAN.md` for the full checklist)
---
---

# Handover — Can Case / Water Case Scale Change (Aug 2026)

## What changed this session
Removed `CanCase.gd`/`WaterCase.gd`'s `scale = Vector3(0.75, 0.75, 0.75)`
downscale (both now sit at their full authored mesh size, `1.0`).
Follow-up to a bug found in the CTRL manual-upright feature: `Basis.
slerp()` (used by `PickupableItem.slerp_to_upright()`) decomposes and
interpolates BOTH rotation and scale toward its target — since the
target is always `Basis.IDENTITY` (scale `1.0`), holding CTRL on either
item was gradually growing them from their authored 0.75 scale toward
1.0 as an unintended side effect of what was meant to be a rotation-only
correction. Brannon preferred the resulting larger look over the
original 0.75 scale, so rather than fixing the slerp to leave scale
alone, made 1.0 the permanent authored scale instead. Confirmed via
direct read of `_compute_obstacle_radius()` that neither the bulky-
carry-arc gating nor the `NavigationObstacle3D` avoidance radius for
either item are affected — both are computed from each `CollisionShape3D`
child's own local transform, never from the parent `RigidBody3D`'s own
`scale`, so this was already independent of the 0.75 value one way or
the other.

### Files modified
- `scripts/world/items/CanCase.gd` — `scale` override removed.
- `scripts/world/items/WaterCase.gd` — same.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_CANCASE_WATERCASE_SCALE_PLAN.md` for the full 4-item checklist)

---

---

# Handover — Shelf Corner Post Height Fix (Aug 2026)

Symptom: shelf corner posts (all three sizes — Small/Medium/Large share
`_build_mesh()` from the `Shelving.gd` base) reached ~0.57 m above the
top shelf platform, towering over it visually.

Root cause: stale hardcoded offsets left over from the pre-resize 0.45
tier spacing. The post formula was `unit_h - 0.2375` with
`post_y_offset = 0.45 * 0.5`, tuned against the old 0.45 spacing and
never recomputed when the crate-fit pass raised spacing to 0.60 (and
raised `unit_h` 2.5→3.55 for unrelated crate headroom). Drift between
the two left the posts far too tall.

Fix: post height now derives directly from `shelf_y` — top shelf +
1/6 of the tier spacing + the unchanged `post_y_offset` (0.225). At the
current 0.60 spacing that's exactly 0.10 m above the top shelf on every
variant automatically (Small's top shelf sits lower so its excess is the
same ratio, shorter in absolute terms; Large inherits Medium's
`shelf_y`). The comment on the old constants was also removed/replaced.
`unit_h` is deliberately left unchanged — it still sizes the collision
box (headroom for a crate-height top-shelf item) and the E-prompt
height, so the visual-posts vs unit_h-collision gap is intentional.

Files touched: `scripts/world/furniture/Shelving.gd`,
`docs/systems/furniture-items/README.md`.

---

---

# Handover — Flashlight.gd Compile Error Fix (Aug 2026)

## What changed this session
Fixed a compile error introduced by the prior "Softened Upright Snap +
CTRL Manual-Upright Hold" plan: `Flashlight.gd`'s
`allow_manual_upright` exclusion was written as a fresh `var`
declaration, but GDScript doesn't allow a subclass to redeclare a `var`
already declared on its parent class (`PickupableItem.gd` already
declares this one) — hard compile error, script failed to load. Fixed
by removing the redeclaration and instead assigning
`allow_manual_upright = false` inside `Flashlight._ready()`, which is
the correct way to override an inherited var's default in GDScript. No
behavior change from what was originally intended — same end value,
just set the right way. Already applied and verified directly in this
session, not left as a pending plan.

### Files modified
- `scripts/world/items/Flashlight.gd` — redeclaration replaced with an
  assignment in `_ready()`.
- `docs/systems/player/README.md` — correction note appended to the
  prior entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_FLASHLIGHT_VAR_REDECLARATION_FIX_PLAN.md` for the full 3-item
checklist)

---

---

# Handover — Storage Carry-Retrieval Wall Tunneling Fix (Aug 2026)

Symptom: items retrieved via the StorageUI "Carry" button from a
wall-adjacent shelf / End Table / Dresser would sometimes tunnel through
the world — clipping through the unit and wall, occasionally the floor.

Root cause: neither `Shelving.retrieve_to_carry()` nor
`LightStorage.take_for_carry()` repositioned the item onto the player's
side before handing off. `PickupableItem.pickup()` never moves the item —
it just flips held state and lets `_physics_process()` drive it toward the
hold point via raw velocity (`linear_velocity = (chase_target -
global_position) * speed`). So the item was physics-chased from its old
storage position (behind the unit, against the wall) straight through any
layer-1 colliders between there and the player.

Fix: a shared `Shelving.carry_spawn_position(isys)` static helper
(`isys.global_position + (0, 1.0, 0)` — chest height) now positions the
item at the player's own origin before `pickup()`. The player's position
is by construction never inside solid geometry (their own collision
occupies it), so there is categorically no unit/wall/floor to tunnel
through; the remaining short gap to the hold point is closed by the
existing per-frame chase, preserving the pop-then-settle pickup feel.
Called from both `Shelving.retrieve_to_carry()` and
`LightStorage.take_for_carry()` before the `pickup()` call.
`LightStorage`'s `_reparent_to_world()` is untouched — its
furniture-center placement is fine for the inventory path
(`take_for_inventory()`, no physics chase).

Out of scope: `_reparent_to_world()` inventory-path positioning, Basket's
`take_for_carry()`/Drop behavior (different action/code path), and
`PickupableItem._physics_process()` itself (chase logic correct, reused
as-is).

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/LightStorage.gd`,
`docs/systems/furniture-items/README.md`.

---

---

# Handover — Softened Upright Snap + CTRL Manual-Upright Hold (Aug 2026)

## What changed this session
Softened Basket/Cooking Pot's always-on "never lean while carried"
behavior from an instant hard snap (`global_transform.basis =
Basis.IDENTITY` outright every physics tick) to a quick spherical-
interpolation ease, via a new shared `PickupableItem.slerp_to_upright
(delta, speed)` (Basis.slerp() toward identity, exponential-decay
convergence, `UPRIGHT_SLERP_SPEED = 10.0` — tunable, ~99% converged in
~⅓ second). Then layered a new feature on the same primitive: holding
CTRL now applies the same ease-to-upright to ANY held item, via a new
`allow_manual_upright: bool` on `PickupableItem` (default true,
overridden false only on `Flashlight.gd`, since its rotation is its own
aim direction). Basket/Cooking Pot are excluded from the CTRL branch
(checked via their existing container duck-type markers) since their own
override already keeps them upright regardless — avoids a harmless but
pointless double-call, not a bug fix. Used `Input.is_key_pressed
(KEY_CTRL)` polled directly rather than adding a new Input Map action —
avoided hand-transcribing a `physical_keycode` value into `project.godot`
with no way to verify it outside the Godot editor. Releasing CTRL needs
no explicit stop logic: the interpolation function holds no state
between calls, so the item simply holds still at whatever orientation it
last reached.

One open question flagged for Brannon rather than resolved
unilaterally: whether CTRL near a Shelf/Dresser/End Table should
interact with the held-item E-priority system from earlier this session
— currently doesn't, since CTRL isn't bound to any existing action, but
named explicitly in case something else was intended there.

### Files modified
- `scripts/world/items/PickupableItem.gd` — new
  `slerp_to_upright()`/`UPRIGHT_SLERP_SPEED`/`allow_manual_upright`; CTRL
  branch added to `_physics_process()`.
- `scripts/world/items/Basket.gd` — instant snap replaced with
  `slerp_to_upright()` call.
- `scripts/world/items/CookingPot.gd` — same replacement.
- `scripts/world/items/Flashlight.gd` — `allow_manual_upright = false`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_UPRIGHT_SLERP_AND_CTRL_HOLD_PLAN.md`
for the full 7-item checklist)

---

---

# Handover — NPC: Stuck-Recovery Deadlock Fix + Reachability-Aware Target Selection (Aug 2026)

- Root-caused a real infinite loop: _recover_from_stuck() had no memory
  of repeated failures, so a genuinely wedged NPC (boxed in by clutter
  on every side, unable to move toward anything — including the item
  touching it) would force the identical doomed CleaningActivity every
  ~1s forever. Now tracks a same-obstruction streak
  (_stuck_streak_obstruction_id/_stuck_streak_count); after
  STUCK_ESCALATE_AFTER (2) consecutive failures on the same target, it
  stops retrying and directly nudges the NPC's position away from the
  obstruction instead (movement commands don't work on a wedged NPC, so
  this bypasses movement entirely), then lets the next think-cycle
  decide fresh. Added NPCDebug.log_stuck_escalation() for visibility.
- find_cleaning_target() no longer picks purely by straight-line
  distance — candidates are checked in distance order, but a
  _has_clear_approach() raycast now deprioritizes an item that's
  directly behind another piece of clutter in favor of a similarly-close
  one with a clear line to it. This is what "prefer the item on the
  outside of a pile over the one buried in the center" means
  mechanically. Falls back to plain-nearest if every candidate looks
  equally blocked.
- Confirmed (no fix needed): items freed from a deleted shelf are
  already correctly picked up by JobBoard's cleaning scan — they join
  the "pickup" group in their own _ready() regardless of how they ended
  up loose.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCDebug.gd`,
`docs/systems/npc/README.md`.

---
---

# Handover — Large Shelf Spacing + Crate Sink Fix + Case Upright/Restack (Aug 2026)

Three independent fixes in `Shelving.gd` plus two item files:

1. **Large Shelf column overlap** — the N-column marker branch hardcoded
   0.30 spacing, so 3 Test Crates (W=0.54) overlapped by 0.24 each. New base
   export `multi_col_spacing` (default 0.30); Large overrides it to **0.62**
   (= 0.54 + 0.08 clearance) and widens `unit_w` 1.70 → **2.00** so the outer
   crates (edges ±0.89) sit inside the frame (half-width 1.00, 0.11 margin).
2. **Crate sink bug** — TestCrate's mesh pivot is centered (bottom plate at
   -0.231 below origin), and `_place_item_in_slot()`'s old `extra_lift`
   logic never lifted crates (the "slot_lift already handles it" comment was
   wrong). Added a `_get_item_type(item) == "test_crate"` branch →
   `extra_lift = 0.18`, so the crate rests visibly ON the platform.
   **Pattern to watch:** any future shelf-stackable item with a centered mesh
   pivot needs the same per-type `extra_lift` lift.
3. **Cases stand upright + new limits** — CanCase/WaterCase previously laid
   flat in a 2×2 grid (`limit == 4` rotation/offset branches). Now both stand
   upright (`_stack_rotation` → `(0, 90, 0)`, type-keyed off
   `can_case`/`water_case`; Y=90 keeps label facing player). CanCase
   `shelf_stack_limit` 4 → **2** (stacks vertically, `_stack_offset` lifts
   idx 1 by `CASE_H_UPRIGHT` 0.34 + gap — **provisional, tune in-editor**);
   WaterCase 4 → **1** (too large for two). Removed the now-unused
   `CASE_W`/`CASE_H_LAY`/`CASE_GAP_X` constants; added `CASE_H_UPRIGHT`.

**Required in-editor verification (not assumed done):** since CanCase/
WaterCase are `.tscn`-based and may share TestCrate's centered-pivot
convention, check both standing upright on a shelf for the same sink symptom
Part 2 fixed. If either sinks through the platform, add a matching
`can_case`/`water_case` `extra_lift` branch (half real standing height +
0.009 platform-top offset − 0.075 slot_lift).

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/LargeShelf.gd`,
`scripts/world/items/CanCase.gd`, `scripts/world/items/WaterCase.gd`,
`docs/systems/furniture-items/README.md`.

---
---

# Handover — Medium Shelf Resize for Test Crate Fit (Aug 2026)

- Symptom: the Test Crate (W=0.54, H=0.48, D=0.73 — the largest carriable
  item) couldn't visibly fit between shelf tiers, and the bottom shelf sat
  too high off the floor.
- Root causes (both fixed in the `Shelving.gd` base class, so Medium AND
  Large inherit them):
  1. Tier spacing was 0.45 → interior clear height 0.432, narrower than the
     crate's 0.48 H. Now 0.60 spacing → 0.582 clear, on every tier.
  2. Shelf depth `unit_d` was 0.625 — narrower than the crate's own 0.73 D,
     so it would clip through the front/back even with taller spacing
     (independent problem found during investigation). Now 0.85.
  Plus: bottom tier lowered 0.225 → 0.12 (closer to the floor), and `unit_h`
  2.5 → 3.55 so the posts (derived from `unit_h`) still clear the raised top
  tier (2.52) with crate-height headroom.
- Small Shelf: same 0.60 spacing / 0.12 floor applied to its own 3-tier
  values (`shelf_y [0.12, 0.72, 1.32]`, `unit_h 2.35`) so the crate fits
  there too; depth fix inherited from base `unit_d` automatically.
- No other changes: `_build_collision()` reads `unit_w/unit_h/unit_d` live
  and `_build_slot_markers()` derives Y from `shelf_y`, so collision and slot
  markers auto-adjust. `unit_w`/`slot_offset_x` untouched (not reported
  broken). Occupancy/overlap footprint unaffected (uses `unit_w`, unchanged).
- Large Shelf takes no action — inherits every base fix.

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/SmallShelf.gd`,
`docs/systems/furniture-items/README.md`.

---
---

# Handover — Shelf Family: Small/Medium/Large (Aug 2026, v2 corrected for current 10-slot Shelving)

- Added the shelf family: **Small Shelf (tile 34, $45, 6 slots as 3 tiers ×
  2)**, **Medium Shelf (tile 3, $75, 10 slots as 5 × 2 — the former
  "Shelving", renamed display-only)**, and **Large Shelf (tile 35, $180, 15
  slots as 5 × 3)**.
- Architecture: subclass, not file-copy. `Shelving.gd` stays the base class
  (file/class/group names unchanged); `SmallShelf.gd`/`LargeShelf.gd` are
  ~15-line subclasses overriding `_init()` only. All storage/stacking/NPC/
  StorageUI/eject logic inherited untouched.
- `Shelving.gd` generalizations: new exports `slots_per_tier` (2) and
  `display_name` ("Medium Shelf"); `slots` derived as
  `shelf_y.size() * slots_per_tier` in `_ready()` (was a hardcoded 10-element
  literal); `_build_slot_markers()` keeps the classic 2-column math
  bit-for-bit for `slots_per_tier == 2` (existing shelved items don't move)
  and spaces N columns evenly otherwise; `get_ui_config()` is now dynamic —
  verified to reproduce the current 10-slot values exactly (`slot_count` 10,
  `grid_cols` 2, `grid_rows` 5, `display_order` `[8,9,6,7,4,5,2,3,0,1]`),
  with `"title": display_name.to_upper()` so Medium reads "MEDIUM SHELF".
- Wiring: `BuildModeController` consts 34/35 + two spawn branches copied from
  the Shelving branch (incl. StorageUI + InteractionSystem injection);
  `BuildModeHUD` CATEGORIES lines (rename + 34/35); `GhostModelBuilder`
  `PROCEDURAL_PREVIEW_SOURCES` + `ARROW_OVERRIDES` `[0.6, 180.0]` for both;
  `GhostPreview`/`MoveDuplicateTool` shelf-family ghost-build and
  `SHELF_PLACEMENT_Y` snap-Y branches extended to all three tiles; occupancy
  carve-out now accepts all three shelf tiles and counts any shelf variant as
  occupying (Small/Large/Medium block each other, not just same-tile);
  `_tile_half_extents()` arms `(0.48, 0.18)` for Small and `(0.65, 0.18)` for
  Large (matched to Medium's `unit_w * ~0.384` ratio). Save/load and undo work
  automatically — both route through `_spawn_placed_object()`.
- **Note for the NPC thread:** shelf-seeking code iterates the `"shelving"`
  group, which Small/Large now join automatically (inherited `_ready()`).
  Inherited APIs are identical, so no action is expected — but NPCs can now
  also use Small/Large as storage destinations if desired.
- v1 of this plan was written against a stale clone (pre-10-slot rewrite) and
  is superseded; nothing from v1's model-rotation work applies.

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/SmallShelf.gd`, `scripts/world/furniture/LargeShelf.gd`,
`scripts/world/build/BuildModeController.gd`,
`scripts/world/build/GhostModelBuilder.gd`,
`scripts/world/build/GhostPreview.gd`, `scripts/world/build/MoveDuplicateTool.gd`,
`scripts/ui/build/BuildModeHUD.gd`, `docs/systems/furniture-items/README.md`,
`docs/systems/build/README.md`.

---
---

# Handover — NPC: Light Items Prefer Light Storage Over Shelving (Aug 2026)

- find_cleaning_destination() now does a two-pass search for "light"
  classified items: LightStorage (End Table/Dresser) only first, and
  only falls back to considering general Shelving objects once no
  LightStorage candidate has room. Heavy items and trash are unaffected.

Files touched: `scripts/npc/NPC.gd`.

---
---

# Handover — NPC: Cleaning Root-Cause Fixes + Refuel Errors + Neutral NPC Spawn (Aug 2026)

- Fixed generic "Item" naming: TestCrate.gd, CanCase.gd, WaterCase.gd
  were all missing get_display_name() entirely, falling back to
  PickupableItem's "Item" default despite already having a usable
  item_name field.
- CleaningActivity is now destination-first: confirms a viable
  destination for an organizable item BEFORE claiming/walking to it,
  not after already picking it up. An item with genuinely no viable
  destination for its whole classification (light/heavy) is skipped
  once and never retried for the rest of the session
  (_skipped_ids/_no_storage_categories), instead of being picked up and
  dropped on a loop every tick — this was the direct cause of the
  Test Crate repeat-loop seen in a live debug capture.
- Fixed a real stale-cache bug: JobBoard.get_trash_items()/
  get_organizable_items() only filtered is_instance_valid(), not
  shelved/held state, so a just-stored item stayed "organizable" in the
  cache for up to the full 2s SCAN_INTERVAL — and being physically
  nearest to the NPC that just used it, got endlessly re-picked and
  rejected until the next scan. This was the cause of the repeating
  "target picked / target lost: became shelved" bursts between
  otherwise-successful deliveries.
- Formalized "light" (inventory_item-gated) vs "heavy" as NPC.gd's real
  organizable-item classification (previously always "general"), with
  NPC.has_viable_destination_for_category() backing both the new
  destination-first check and specific unavailable-reason errors:
  NO_LIGHT_STORAGE_AVAILABLE / NO_HEAVY_STORAGE_AVAILABLE replace the
  old generic NO_STORAGE_AVAILABLE. Confirmed (no code change needed)
  that Water Bottle, Food Can, all seed packets, Bag of Soil, and both
  Fertilizer tiers were already inventory_item-gated and thus already
  "light"-eligible.
- Added NPC.get_refuel_unavailable_reason() — replaces the old blanket
  "nothing needs refueling" with ALL_GENERATORS_FULL / FUEL_CAN_CLAIMED
  / NO_FUEL_CAN, same pattern as Cleaning's reason system. This is now
  the standard going forward for every job's failure messaging.
- Added Shelving.has_free_space()/LightStorage.has_free_space() —
  generic "any room at all" checks used by the new category-availability
  logic without needing a specific item on hand yet.
- Added F7 "Spawn Neutral NPC (Testing)" — spawns via the same path as
  the existing Spawn NPC row, then overrides personality to fully
  baseline and every skill to exactly 1.0, for reproducible testing
  without trait-driven behavior variance.

Files touched: `scripts/world/items/TestCrate.gd`,
`scripts/world/items/CanCase.gd`, `scripts/world/items/WaterCase.gd`,
`scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`.

---
---

# Handover — NPC: Cleaning Debug Overhaul + Specific Unavailable-Reason Errors (Aug 2026)

- CleaningActivity now logs every meaningful decision point (target
  picked, claim failed, picked up, destination chosen, no destination,
  delivered, delivery failed, target lost, forced grab, session
  started/ended) via NPCDebug.log_cleaning() — previously only session-
  end was logged.
- Added NPCActivity.debug_info() (optional, empty by default) and wired
  it through NPCBrain.get_current_activity_debug_info(); CleaningActivity
  implements it with phase/item/destination/session-progress.
- Added a new F7 row, "Print NPC Cleaning Debug State"
  (NPCDebug.dump_cleaning_state()) — one-shot snapshot of JobBoard's
  ready/pending caches (with live per-item remaining idle-timer seconds),
  every "shelving"-group destination's occupancy, and every NPC currently
  mid-clean.
- JobBoard now tracks trash items blocked by the missing trash_receptacle
  separately (get_trash_blocked_by_no_receptacle_count()), and exposes
  get_pending_cleaning_count()/get_cleaning_debug_snapshot() for the
  above.
- Added NPC.get_cleaning_unavailable_reason() — replaces the blanket
  "nothing to clean right now" toast with a specific one: NOTHING_TO_
  CLEAN, NO_TRASH_RECEPTACLE, STILL_SETTLING, ALL_CLAIMED, NO_STORAGE_
  AVAILABLE, or STORAGE_FULL. Mapped to player-facing text in
  NPCTalkMenuUI.CLEANING_UNAVAILABLE_REASONS.

Files touched: `scripts/npc/NPCDebug.gd`, `scripts/npc/NPCActivity.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`, `scripts/ui/menus/AdminMenu.gd`.

---
---

# Handover — NPC Light Storage (End Table/Dresser) Cleanup + Refuel Session Redesign (Aug 2026)

- Fixed a dead group-name bug: NPCItemUser.find_shelved_item() and
  JobBoard._spare_exists() both searched group "shelf", which nothing in
  the project has ever joined (real shelves/storage join "shelving").
  NPCs could never find a spare item that had been put away on a shelf —
  affected Eat/Drink/Replace-Filter/Refuel fetch-from-shelf fallback.
- Added has_room_for()/npc_try_place_item() to LightStorage.gd (End
  Table/Dresser) so Cleaning can actually store eligible light items
  there — previously silently failed since only Shelving.gd had these.
  Eligibility reuses the player's own inventory_item group gate.
- Added an extensible item-classification → destination-group mapping
  to NPC.find_cleaning_destination() (currently everything still
  resolves to "shelving") so a future dedicated container (Fridge for
  food, etc.) is a one-line addition, not a rework.
- Pulled REFUEL out of JobBoard/JobActivity entirely (it never fit the
  single-target claim shape any better than Cleaning did) and rebuilt it
  as NPCBrain.RefuelActivity/CommandRefuelActivity: fetches one fuel can,
  sweeps every generator below 100% in one session, never revisits a
  generator already topped off, ends when the can empties or everything's
  full. Also fixes the old REFUEL_BELOW=40% gate that meant a mid-range
  generator was never even detectable as needing fuel.

Files touched: `scripts/npc/NPCItemUser.gd`, `scripts/npc/JobBoard.gd`,
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`.

---
---

# Handover — Shelving Facing + Default-South Selection Reset (Aug 2026)

- **Bug A — Shelving faced backwards (two independent causes).** The
  project's facing convention (see `GhostModelBuilder.gd`) is that every
  object's real "front" is local +Z; `DEFAULT_ARROW_Y_ROT = 180.0` rotates
  the arrow geometry to match. Shelving was the odd one out twice over:
  its loaded model (`MODEL_PATH`, `steel_frame_shelves_01_4k.glb`) has its
  open front baked facing local -Z, AND both arrow paths were hand-tuned
  to that backwards model instead of the convention
  (`ARROW_OVERRIDES[3] = [0.6, 0.0]` and the fallback
  `_attach_ghost_direction_arrow(0.6)`). Fixed at the source:
  `Shelving._load_mesh()` now rotates the visual instance 180°, and both
  arrow entries are updated to the standard `180.0`. Visual-only — slot
  markers (z=0), collision, and stack offsets are Z-symmetric.
- **Bug B — ghost rotation never reset on selection.** `_orient_index` /
  `_current_angle_deg` persisted across construct-menu clicks, so the
  previous object's rotation — or a wall-snapped tile's (poster/light/
  breaker) — carried into the next ghost. Every construct selection now
  resets to `BuildModeController.DEFAULT_ORIENT_INDEX` (0 → 0.0° → front
  +Z = world south). Scroll-wheel rotation still works (relative);
  wall-snapping tiles recompute their own angle each frame.
- **Accepted effect:** shelves placed in a RUNNING scene before this lands
  will visually rotate 180° on script reload (no persistent save — one-time
  blip, items stay put).

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/world/build/GhostModelBuilder.gd`,
`scripts/world/build/GhostPreview.gd`,
`scripts/world/build/BuildModeController.gd`.

---
---

# Handover — Storage UI Preview Fix + Icon/Row-Label Redesign (Aug 2026)

## What changed this session
Fixed StorageUI's broken 3D item previews (most items rendered as a
near-invisible speck in Shelving/Basket/End Table/Dresser) — root cause
was `_add_pool_slot()` using `cam.size = 1.2` and rotation `(-20°, 45°,
0°)` while the working reference, `InventoryHUD.gd`, uses `cam.size = 0.4`
and `(-45°, -45°, 0°)`. Extracted `InventoryHUD.gd`'s preview code into a
new shared static utility, `scripts/ui/common/ItemPreviewKit.gd`, and
migrated both `InventoryHUD.gd` and `StorageUI.gd` onto it so future
preview adjustments cascade automatically instead of needing to be
hand-copied per file. Deliberately did NOT migrate `BuildModeHUD.gd`'s
construct/shop previews this pass — they already share the same resting
angle but layer their own hover-spin on top; flagged as a reasonable
future pass.

Also replaced every storage panel's "↑"/"↓"/"⊕" text-glyph buttons with
real icon textures (two supplied decorative arrows + a 45°-pre-rotated
version of a supplied × icon so it reads as a +), and removed the
"Top shelf"/"Middle drawers"/etc. row-label text entirely from every
storage panel, tightening the now-label-free row gap from 22px to 4px.

### Files modified
- `scripts/ui/common/ItemPreviewKit.gd` — NEW shared 3D preview builder.
- `scripts/ui/inventory/InventoryHUD.gd` — preview logic delegated to
  `ItemPreviewKit`.
- `scripts/ui/inventory/StorageUI.gd` — preview logic delegated to
  `ItemPreviewKit`; icon buttons converted to textures; row-label
  rendering removed; row gap tightened.
- `scripts/world/items/Basket.gd`, `scripts/world/furniture/Shelving.gd`,
  `scripts/world/furniture/LightStorage.gd`,
  `scripts/world/furniture/Dresser.gd`,
  `scripts/world/furniture/EndTable.gd` — `primary_button_icon` values
  updated to the new lookup-key convention; `row_labels` config/export
  removed.
- `assets/icons/arrow_decorative_n.png`, `arrow_decorative_s.png`,
  `icon_plus.png` — NEW icon assets.
- `docs/systems/ui/README.md` — new "Shared Item Preview Kit" and
  "Storage UI Icon + Row Label Redesign" sections.
- `docs/systems/furniture-items/README.md` — cross-reference note.
- `HANDOVER.md` — this entry.

### Verification checklist
(see `UI_STORAGE_PREVIEW_ICON_REDESIGN_PLAN.md` for the full 8-item
checklist)
---
---

## NPC: Shelf Pop-Out Fix + Cleaning Investigation (Aug 2026)

- Root-caused and fixed shelf pop-out: `Shelving.npc_try_place_item()`
  never cleared the delivered item's `is_held`/`_hold_point`, so
  `PickupableItem`'s own knockout logic treated it as still being
  carried and ejected it once the NPC walked away. Now mirrors the
  player placement path's existing clear.
- Fixed a claim leak in `CleaningActivity` where a failed shelf
  placement (destination filled mid-delivery) dropped the item without
  releasing its `NPCItemUser` claim, permanently blocking other NPCs
  from it.
- Added an `NPCDebug`-gated fast idle-timer override
  (`CLEANING_IDLE_MIN_SEC_DEBUG`, 5s) to `JobBoard.gd` for testing the
  90s cleaning idle-gate's role in the "nothing to clean" / sporadic
  cleaning reports without waiting it out live.
- Confirmed: no object in the project currently occupies the
  `trash_receptacle` group, so trash-type cleaning cannot complete yet —
  pre-existing/by-design, not a regression, but relevant to interpreting
  cleaning test results until a receptacle object exists.

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`.

# Handover — Cleaning Follow-Up: Shelf Pop-Out + Sustained Session (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
- **`NPCItemUser.grab_loose()` now refuses shelved items.** It previously
  grabbed anything loose; if a `CleaningActivity` carried a reference to
  an item that got shelved mid-approach (or the `"shelved"` group was
  already set), the NPC could end up carrying/placing a shelved item —
  plausibly the shelf-pop-out symptom. Guard added so grab-any-loose
  callers (Give-to-Friend, Eat/Drink fetching, stuck-recovery forcing)
  can never take a shelved item.
- **`NPCBrain.gd` early-abort:** `CleaningActivity` aborts the moment
  its target becomes `"shelved"` while fetching (the grab would fail
  anyway per the above) instead of walking the full distance for
  nothing.
- **Cleaning is now a sustained session, not one-and-done.** `done()`
  was `_item == null`, which became true after every single delivery —
  the activity stopped after one item by design. Rewrote
  `CleaningActivity`: after each delivery it calls `_pick_next_target()`
  and keeps cleaning for **20–40 real seconds** (`SESSION_MIN_SEC`/
  `SESSION_MAX_SEC`, `randf_range()`, same convention as Talk/Relax
  session lengths) or until nothing's left to clean bunker-wide,
  whichever comes first. Session time is only checked between items so
  it always finishes the current carry. Interruptible only between
  items (`interruptible()` = `_item == null`). Stuck-recovery path
  (`forced_item`) stays exactly one grab. `done()` is now
  `_finished and _item == null`.
- **Diagnostics:** `NPCDebug.log_cleaning(npc, stage, detail)` (staged,
  like `log_snatch()`) + a `[JobBoard] Cleaning scan:` summary line
  (trash / organizable / tracked-not-yet-idle counts) under F7 debug.
- **`CommandCleaningActivity` delegates to a normal organic
  `CleaningActivity`** — inherits sustained-session behavior unchanged,
  deliberate.

## Files Modified
`scripts/npc/NPCItemUser.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/NPCDebug.gd`, `scripts/npc/JobBoard.gd`.

## Status: NOT VERIFIED FIXED
Both original complaints were re-investigated and root causes proposed,
but the field symptoms were **still reported after this fix attempt**:
- **Shelf pop-out** — a placed item occasionally popping back out of /
  unfreezing from a shelf. Not reproducibly traced to one remaining code
  path; suspected interaction between `_find_stuck_obstruction()` forcing
  `CleaningActivity` onto a shelved `RigidBody3D` and stale cached
  references, but unconfirmed.
- **"Nothing to clean" regression** — partly a timing false-alarm (90s
  idle gate on organize-ables + trash never posting because
  `_has_trash_receptacle()` is still false), but the pre-placed-item path
  is still open.
- **Sporadic timing** — the "randomly interrupted with brief Idles"
  symptom was traced to Talk's missing session cooldown (fixed in the
  Talking entry below), but the equivalent Cleaning timing remains
  unexplained.

**Investigation was interrupted by a tool outage mid-session.** A fresh
live-repo check is the stated next step.

## Next Up
- Run test checklist items 80–84 in
  `NPC_CLEANING_SHELF_POPOUT_AND_SESSION_PLAN.md` against a fresh pull
  (shelf pop-out with several items back-to-back; multi-item single
  session; clean session timeout mid-carry; empty-bunker graceful end;
  JobBoard scan line accuracy).
- If pop-out still reproduces, instrument `_find_stuck_obstruction()`
  and the shelving slot assignment specifically — that interaction was
  the leading unconfirmed suspect.

---

# Handover — Cleaning Job + 3 Root-Cause Fixes + Job Priority + Requests UI (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
- **Cleaning job** (`CleaningActivity`): trash disposal + shelf
  organizing under one job, mirroring `GiveToFriendActivity`'s
  fetch→travel→deliver shape (NOT routed through `JobBoard`'s claim
  system — those are single-location; Cleaning is three-location).
  `JobBoard._scan_cleaning()` (same 2s cadence) maintains cached trash /
  organize-able lists that `NPC.gd` reads via
  `has_cleaning_target_available()` / `find_cleaning_target()` /
  `find_cleaning_destination()`. Trash = `EmptyBagItem`, empty
  `FoodCan`, empty `WaterBottle`; gated behind `_has_trash_receptacle()`
  (false today — a `"trash_receptacle"` group member would self-activate
  it). Organize-ables = loose items idle **90s** (`CLEANING_IDLE_MIN_SEC`,
  idle clock resets if the item moves > 0.3 m). Counts as a JOB for Work
  Ethic (`get_work_ethic_job_mult()`).
- **Stuck-recovery integration:** a stall caused by a loose
  `RigidBody3D` forces `CleaningActivity` onto that specific item,
  bypassing eligibility by design. Future hook: `npc_deposit_trash()`
  is `has_method()`-guarded and ready.
- **Three root-caused fixes** (Part A):
  1. **Stale cache crash** — `get_trash_items()`/`get_organizable_items()`
     returned raw caches; freed references crashed typed iteration.
     Both `filter()` on `is_instance_valid()` before returning (same
     class as the earlier `get_open_jobs()` fix).
  2. **Heavy items unapproachable** — Crates (`mass 7.0` ≥
     `HEAVY_OBSTACLE_MASS`) get a `NavigationObstacle3D` with avoidance
     enabled, which prevents closing the final distance when an NPC
     wants to grab them. Added
     `PickupableItem.set_nav_obstacle_enabled(bool)` (⚠️ World Items
     file — additive only); `CleaningActivity` disables avoidance while
     approaching and restores it on abandoned drops.
  3. **The "just drops" cause** — `find_cleaning_destination()` picked
     the nearest shelf by distance with no capacity check; a full shelf
     meant the carry fails → drop. Added `Shelving.has_room_for()` and
     made destination selection skip shelves without room.
- **Job Priority system** (Part B): universal per-job-type weight,
     a separate axis from Work Ethic (multiplies into final score).
     `JOB_PRIORITY_WEIGHTS`: HARVEST 1.3, REPLACE_FILTER 1.0, REFUEL 1.0,
     CLEANING 0.5, default 1.0. Applies to `JobActivity.score()` and
     `CleaningActivity.score()`.
- **Requests/Jobs UI** (Part C): the NPC E-panel Command box became a
  **Requests** toggle (Go eat / Go drink / Take a load off / "Can you
  complete this job?") with a **Jobs** sub-list driven by
  `NPC_JOB_MENU_ENTRIES` (one entry per job type — add a job type later
  with just one dict entry). New generalized `CommandJobActivity`
  parameterized by job type; `CommandCleaningActivity` wraps an organic
  `CleaningActivity`. `REQUESTS_SECTION_H = 260` fixed panel bump.
- Cleaned: `docs/systems/npc/README.md` (Cleaning section: sustained
  session, diagnostics, and a **known-open-issues** block), Job Priority
  section, and the Action Log section.

## Files Modified
`scripts/npc/JobBoard.gd`, `scripts/world/furniture/Shelving.gd`,
`scripts/world/items/PickupableItem.gd` (⚠️ flagged, additive),
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`, `docs/systems/npc/README.md`.

## Verification
- Tests 70–79 in `NPC_CLEANING_FIXES_PRIORITY_REQUESTS_UI_PLAN.md` +
  full Cleaning test list in `NPC_CLEANING_JOB_PLAN.md`.
- Watch for the follow-up entry above — the sustained-session redesign
  landed separately and the shelf pop-out is **not** confirmed fixed.

---

# Handover — Exposure-Weighted Mood Contagion + Randomness Consistency (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
- **Mood contagion is now exposure-weighted.** Previously
  `_tick_mood()`'s contagion averaged ALL other NPCs' moods equally
  regardless of distance/history — someone across the bunker pulled as
  hard as someone stood next to all day. Added a per-pair **exposure
  score** (`_contagion_exposure`: `CONTAGION_EXPOSURE_GAIN_PER_GAME_HOUR`
  0.5, `DECAY` 0.2, `MAX` 5.0), built up while within
  `RELATIONSHIP_PROXIMITY_RANGE` (the SAME range the Relationships
  system uses — one consistent "what counts as together" definition),
  decaying while apart. Contagion target is now
  `_compute_weighted_contagion_target()` — an exposure-weighted average;
  zero exposure = zero influence (no diluted "everyone counts a little").
  Falls back to own mood if nobody has exposure (fresh spawn).
- **Deliberately NOT extended to time-skip catch-up** — that already
  uses a single pre-skip bunker-wide snapshot as an accepted
  approximation; weighting it would require snapshotting every NPC's
  exposure map too. Live contagion only.
- **Randomness consistency pass** (Part B): two duplicated formulas
  centralized in `NPC.gd`:
  - `_random_sign()` — shared coinflip helper (was inlined as
    `randf() < 0.5` in personality generation and the Talk swing).
  - `_threshold_scaled_chance(value, threshold, extreme,
    chance_at_threshold, chance_at_extreme, direction)` — one formula
    for both "chance rises above threshold" (Give-to-Friend) and
    "chance falls below threshold" (Snatch).
  Per-mechanic constants unchanged; range picks already consistently use
  `randf_range()`. Trait multiplier ranges (0.5x/0.67x/0.7x) deliberately
  left different — they were explicit per-trait percentage requests.

## Files Modified
`scripts/npc/NPC.gd` only.

## Verification
- Two NPCs near each other with divergent moods: close proximity should
  pull moods together strongly; after separating for a while, influence
  fades (F7 mood debug). A pair that only barely crossed paths should
  have near-zero contagion pull.
- Documented in `docs/systems/npc/README.md` (contagion section +
  skip-note rationale + new "Established Conventions" section).

---

# Handover — Sociability→Contagion, Snatch/Gift Cooldown + Live HOSTILE Log, Relax Spacing (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
- **Sociability now scales mood contagion ±33%** —
  `get_contagion_sociability_mult()` (0.67x Distant → 1.33x Open, 1.0x
  baseline/absent), applied to both the live `_tick_mood()` contagion
  line and `_catch_up_mood()`'s blend. Separate from
  `_sociability_trait_mult()` (relationship-magnitude) — this is
  receptivity, how much THIS NPC's mood gets pulled toward the group
  average.
- **Snatch → Gift 60s pair cooldown** — a victim (npc_id or "player")
  of a snatch attempt can't gift back to THAT SAME attacker for 60s
  (`SNATCH_GIFT_COOLDOWN_SEC`, refreshed every tick of active pursuit).
  Uninvolved third parties unaffected.
- **Live HOSTILE log entry** — during a pursuit, a single Action Log row
  "X HOSTILE for Ns" is created once (`start_hostile_log()`), mutated in
  place every tick (`update_hostile_log()`, counts "1s", "2s", ...), and
  frozen to "was HOSTILE for Ns" the instant pursuit ends
  (`end_hostile_log()`). `NPCTalkMenuUI._process()` refreshes just that
  one row's text per frame while expanded (relies on `get_action_log()`
  returning a shallow copy, so index 0 is the SAME dict NPC.gd mutates).
- **Relax clustering fix** — a fresh NPC (full needs, nothing competing)
  could win the first think-cycle and chain relax sessions until the
  whole daily budget was gone in one sitting. Added a randomized
  inter-session cooldown (`RELAX_MIN_GAP_HOURS` 3 / `MAX` 6,
  `is_relax_on_cooldown()`/`start_relax_cooldown()`,
  `RelaxActivity.score()` gates on it), plus a staggered 1–3h head-start
  at spawn so nobody's eligible the instant they spawn.
- Also part of this pass: NPC↔NPC snatch pair cooldown (10s,
  `NPC_SNATCH_PAIR_COOLDOWN_SEC`, bidirectional) and Talk session
  cooldown (30–90s) — see the Talking entry.

## Files Modified
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`. (No Player-subsystem changes —
`can_receive_item()`'s new param defaults to `"player"`.)

## Verification
- Snatched NPC vs the attacker: gifting back blocked ~60s, third-party
  NPCs unaffected. Pursuit shows one live "X HOSTILE for Ns" row that
  counts up and freezes on end. Two new spawns near each other with
  full needs no longer chain relax sessions back-to-back.
- Details: `NPC_SOCIABILITY_CONTAGION_SNATCH_COOLDOWN_RELAX_FIX_PLAN.md`;
  documented in `docs/systems/npc/README.md`.

---

# Handover — Cooking Pot UI Fixes, Storage Prompt Rules, NPC Colors (Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode/Furniture).

## What changed
- **Cooking Pot UI**: fixed the icon row disappearing on pickup (CASE 1
  never looked up icon descriptors) and on drop (items never got
  re-tracked after `_quick_drop()`); fixed the "DONE — Take Dish" prompt
  going blank while the pot sat on a Stove (a regression from the dish-
  naming commit); fixed Food Can rendering as an empty preview circle
  (wrong instantiation mode); fixed all 12 seed packets looking identical
  in the Build Mode shop preview (missing per-id `seed_type`). Layout:
  middle ingredient icon 15% higher, panel padding made symmetric, icon
  size settled back to original 32px after a 2x version was tried and
  reverted, previews now use the same 45°/45° resting rotation as
  everywhere else in the project.
- **Prompt overlap avoidance**: general pairwise layout pass in
  `InteractPrompt.gd` — any two overlapping prompt panels (e.g. Cooking
  Pot + the Stove it's sitting on) now stack instead of overlapping,
  icon-bearing prompts on top. Not cooking-specific, applies project-wide.
- **`InteractPrompt.tscn` panel styling**: gave the shared floating prompt
  (used by every interactable in the game) real dark/rounded styling for
  the first time — it had zero custom stylebox before this arc.
- **Storage prompt exclusivity rule**: while holding a storable item near
  a Shelf/Dresser/End Table, only one prompt line shows now (Store/Full,
  not also "Open"). Needed fixing in two separate code paths in
  `InteractionSystem.gd` (CASE 1 held-item vs CASE 2 empty-handed).
- **Dresser/End Table empty-handed prompt bug, fixed**: `LightStorage.gd`
  was missing `"interactable"` group membership — Shelving has it,
  Dresser/End Table didn't, so they never got a prompt.
- **Handed a separate plan to the Player thread** for the remaining
  `InteractionSystem.gd` half of the storage-prompt fix (CASE 1's
  un-fixed copy of the exclusivity logic, and a timing-safe group-scan
  for CASE 2, since `Area3D` signals don't fire for furniture that spawns
  already inside the player's trigger volume).
- **NPC meter colors**: `NPCTalkMenuUI.gd`'s 5 need bars now use fixed
  per-stat colors (Health red, Energy purple, Hunger yellow, Thirst blue,
  Mood `#bca0dc`) instead of recoloring by value — matches the player's
  own `NeedsGauge` convention.

## Files Modified
`scripts/ui/hud/InteractPrompt.gd`, `scenes/ui/InteractPrompt.tscn`,
`scripts/world/items/CookingPot.gd`, `scripts/ui/build/BuildModeHUD.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/player/InteractionSystem.gd` (partially — see handed-off plan for
the remainder)

## Next Up
- Confirm the Player thread has applied the handed-off
  `InteractionSystem.gd` fixes (CASE 1 exclusivity + CASE 2 timing-safe
  shelving scan) — until then, Dresser/End Table's empty-handed prompt and
  Shelving's held-item exclusivity remain broken.
- `ShelfUI`/`BasketUI`-era visual identity for `StorageUI.gd` still
  hasn't been brought onto the `UIKit` domain-stripe system — still a
  deliberate, deferred decision, not forgotten.

---

# Handover — Held-Item E Priority Is Unconditional (Aug 2026)

## What changed this session
Fixed the E-dispatch so a held item's own E action always takes priority
over a nearby shelf/dresser/end table, unconditionally — previously only
Basket/Cooking Pot/giveable items had any protection at all (a distance-
fairness rule from earlier this session), and even that only won if
strictly closer than the shelf. Every OTHER held item with its own
`on_use()`/`on_interact()` (Flashlight, FuelCan, WaterBottle, FoodCan,
DishItem, FarmProduceItem, SeedItem, FertilizerItem, BagOfSoilItem,
PurifierFilterItem — 10 item scripts, confirmed via direct grep) had
zero protection: any shelf within 2.5 m always won, full stop. Reordered
the dispatch so every held-item E-check runs before the shelf check,
each with an explicit early return, and removed the distance comparison
entirely — the held item always wins now, not just when closer. One
deliberate exception, confirmed against `TestCrate.gd` directly: a Crate
has neither method, so it still lets a nearby shelf capture E normally.
World-interact (stove/generators/breakers) and the ready-dish priority
check were already correctly gated to empty-handed only — confirmed
unaffected, not touched.

Removed `_nearest_e_rival_distance()` and
`_nearest_group_storable_distance()` — both became fully unused as a
direct result of this change (confirmed via repo-wide grep before
removal), so cleaned them up now rather than leaving fresh dead code.

### Files modified
- `scripts/player/InteractionSystem.gd` — E-dispatch reordered;
  `_nearest_e_rival_distance()`/`_nearest_group_storable_distance()`
  removed.
- `docs/systems/player/README.md` — Common-edits entry replaced (was
  describing the now-superseded distance-fairness rule).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_HELD_ITEM_E_PRIORITY_PLAN.md` for the
full 8-item checklist)
---
---

# Handover — Storage-Reject Fallback to Drop (Aug 2026)

## What changed this session
Fixed pressing F to store a held item into a full or size-ineligible
Dresser/End Table/Shelf leaving the item stuck in the player's hand.
Both `LightStorage._try_store_held()` (Dresser/End Table — "too big"/
"full" checks) and `Shelving._try_place_item()` (Shelf — full only, no
"too big" concept there) now call `InteractionSystem._quick_drop()`
directly in their rejection branches, after showing the existing
warning (Shelving previously showed no warning at all in this case —
added one, matching LightStorage's established pattern). Reuses the
exact drop path F already falls back to when there's no storage object
in range at all — no new drop logic. Purpose: bunkers get tight with
furniture placed close together, and blocking F entirely near a full/
ineligible storage object could strand a player unable to drop (or pick
up) anything nearby without first walking out of range.

### Files modified
- `scripts/world/furniture/LightStorage.gd` — `_try_store_held()`
  rejection branches now fall back to `_quick_drop()`.
- `scripts/world/furniture/Shelving.gd` — `_try_place_item()`'s full
  branch gained a warning message (previously silent) and the same
  `_quick_drop()` fallback.
- `docs/systems/player/README.md` — new Common-edits entry.
- `docs/systems/furniture-items/README.md` — one-line cross-reference
  (Furniture-subsystem-owned file, flagged for their visibility).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_STORAGE_REJECT_DROP_FALLBACK_PLAN.md`
for the full 6-item checklist)
---
---

# Handover — `get_held_item()` Validity Guard (Aug 2026)

## What changed this session
Fixed a crash ("Trying to return a previously freed instance") in
`Player.get_held_item()`, which was a bare passthrough to
`InteractionSystem.held_item` with no validity check. Added the same
self-heal guard `InteractionSystem._update_prompt()` already uses for
this exact scenario (held item freed externally without going through
normal drop/give cleanup) — validates with `is_instance_valid()`, clears
both `held_item` and `_held_from_slot` (the reported fix only cleared
the former; fixed to match the established pattern in full).

Investigated whether build-mode deconstruct is the actual upstream cause,
per the bug report's request — read `_try_deconstruct()` directly; it
only targets `_placed_objects` entries (world-placed constructions), and
a currently-held pickupable item is never a member of that array, so it
doesn't appear to be able to reach a held item under normal
circumstances. Not conclusively resolved either way; noted
`eject_all_items()` on deconstructed containers as a possible lead for
the Furniture/Build-Mode thread, not chased further here since it's
outside this file.

### Files modified
- `scripts/player/Player.gd` — `get_held_item()` validity guard.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GET_HELD_ITEM_VALIDITY_FIX_PLAN.md`
for the full 3-item checklist)

---
---

# Handover — End Table + Dresser (Light Storage, Shared StorageUI) (Aug 2026)

## What changed this session
Added two floor-standing hidden-storage furniture pieces to Construct →
Furniture: **End Table** (TILE 32, $60, capacity 2) and **Dresser**
(TILE 33, $150, capacity 6). Both share a new `LightStorage.gd` base and
are implemented **entirely against the shared `StorageUI` 4-method
contract** — no new UI file, no second CanvasLayer. This supersedes the
original plan's (v1) ShelfUI-copy approach, which was dead code after the
Aug 2026 Storage UI Unification pass deleted `ShelfUI.gd`/`BasketUI.gd`.

### Key decisions
- **UI via the shared StorageUI contract**, not a new `LightStorageUI.gd`.
  `LightStorage.gd` implements `get_ui_config` / `get_slot_display` /
  `take_for_carry` / `take_for_inventory`; `get_ui_config()` is built from
  `grid_cols`/`grid_rows`/`row_labels` exports set by each subclass in
  `_init()`.
- **`"shelving"` group = the generic E/F container contract**, reused
  deliberately (InteractionSystem duck-types `on_e_interact`/`on_f_interact`/
  `get_e_prompt`/`get_f_prompt`/`get_prompt_world_pos`). Both MainWorld's
  `_setup_storage_ui()` group loop and BuildModeController's spawn branch
  inject `_storage_ui`/`_interaction_system` into them — so **MainWorld and
  InteractionSystem needed zero changes**.
- **Fixed-size `stored` slot array** (length = capacity, null = empty) so
  StorageUI's positional addressing stays index-stable when a middle slot
  is emptied. No stacking. Eligibility = the `"inventory_item"` group.
- **Hidden-children storage model** (frozen, invisible, collision-off
  children) — reuse of the ecosystem-wide `"shelved"` exclusion group.
- **`eject_all_items()` is load-bearing**: deconstruct / build-undo
  duck-call it; stored items are children of the furniture node, so
  without it they'd be silently freed with the node. Any container whose
  items are children MUST implement it (same rule Shelving/Stove follow).

### Files modified
- `scripts/world/furniture/LightStorage.gd` — NEW shared base (~300 lines).
- `scripts/world/furniture/EndTable.gd` — NEW subclass (Table.gd legs+top,
  cabinet + drawer face/knob), capacity 2.
- `scripts/world/furniture/Dresser.gd` — NEW subclass (2×3 drawer grid),
  capacity 6.
- `scripts/world/build/BuildModeController.gd` — consts 32/33, spawn
  branch + StorageUI/InteractionSystem injection, occupancy block +
  inner filter, `_tile_half_extents()` arms.
- `scripts/ui/build/BuildModeHUD.gd` — two Furniture category lines
  (scoped exception, nothing else in the file).
- `scripts/world/build/GhostModelBuilder.gd` — 2 preview-source entries.
- `scripts/world/build/GhostPreview.gd` — 2 ghost branches + floor-Y elif.
- `docs/systems/furniture-items/README.md`, `docs/systems/build/README.md`
  (new "Light Storage" section + complete wiring checklist),
  `docs/systems/ui/README.md` (contract implementer list), `HANDOVER.md`.
- `END_TABLE_DRESSER_LIGHT_STORAGE_PLAN_V2.md` — plan copied into repo root.

### Verification checklist
(in-editor, Brannon)
1. Placement: both in Construct → Furniture at $60/$150; spinning
   previews; correctly-sized non-colliding ghosts + facing arrow; green/
   red overlap vs other furniture; flush at floor; drawers face the arrow
   direction after rotation.
2. Store: FoodCan + F → vanishes; fill to capacity → "… is full" warning;
   Crate → no F prompt, F drops normally.
3. Shared UI: E opens END TABLE / DRESSER grid (2×1 / 2×3) + row labels;
   ↑ Carry (blocked with full hands) / ⊕ to pocket; slot indices stable
   after emptying a middle drawer; panel blocks world E/F while open;
   shelf + basket UIs still work unchanged.
4. Injection both paths: mid-session-placed unit opens its UI with no
   "not injected" warning.
5. Eject: store 2 items in an End Table → deconstruct → both pop out
   visible + grabbable; repeat via build-undo on a Dresser.
6. Ecosystem: hidden stored can isn't stashed by a held Basket, gets no
   prompts, invisible to scans; E fairness unchanged; items resting on the
   End Table top behave normally; Move tool carries stored items and they
   stay retrievable.

---
---

# Handover — Bulky Held-Item Head-Clearance Arc (Aug 2026)

## What changed this session
Fixed Crate/Can Case/Water Case getting visibly stuck against the
player's head during a fast 180° turn while held. Root cause: held
items are real, fully-collidable `RigidBody3D`s (`collision_mask = 1`,
same layer as the player's own `CapsuleShape3D`) chasing `hold_point`
via a simple proportional-velocity controller in
`PickupableItem._physics_process()`. `hold_point` jumps to its new
position instantly on player rotation; the item's straight-line
physical path to catch up passes through the player's own capsule, and
large enough items collide with it instead of sliding past.

Traced the actual differentiator empirically rather than assuming mass:
computed each carriable item's real collision-shape horizontal radius —
Basket/Cooking Pot ~0.28 (unaffected, correctly so despite being
"heavier" by mass), Can Case/Water Case ~0.34, Crate ~0.46 (all three
reported-affected). Added a lazily-computed `_carry_bulk_radius`
(computed on first `pickup()`, not in `_ready()`, since Basket/
CookingPot build their `CollisionShape3D` procedurally AFTER their own
`_ready()` calls `super()` — computing it any earlier would've silently
fallen back to a generic minimum radius dangerously close to the new
threshold and misclassified both). Items at or above
`BULKY_CARRY_RADIUS_THRESHOLD` (0.30) get a continuous, angle-driven
upward boost applied only to their physics CHASE target (never the true
hold point the knockout-distance check measures against) whenever their
actual position and target are far enough apart angularly — ramping in
and back out smoothly as the item catches up, no separate settle step.

### Files modified
- `scripts/world/items/PickupableItem.gd` — new tuning consts, lazy
  `_carry_bulk_radius` computation in `pickup()`, chase-target height
  boost + new `_carry_arc_height_boost()` helper in `_physics_process()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan
`PLAYER_BULKY_HOLD_ARC_PLAN.md` for the full 8-item checklist)

---
---

# Handover — Player Docs Reconciliation + Cooking Pot UI §1 Verification (Aug 2026)

## What changed this session
No code changes — verified `PLAN_cooking_pot_ui_fixes.md`'s §1
(`scripts/player/InteractionSystem.gd` portion: CASE 1 held-item icons
fix, `_quick_drop()` re-tracking fix) is already fully applied, exactly
matching spec (landed in commit `f6f437c`, which the UI thread applied
in full including the Player-owned portion). Nothing further needed for
the implementing agent on that front.

Used this as the trigger for a full audit of
`docs/systems/player/README.md` against current code — going forward,
every plan from the Player subsystem thread will include a
documentation-reconciliation pass, not just append a note for its own
change. Found and fixed: a stale Files-table line count, a missing
Public API entry for `release_held_item_to_npc()` (Player + Interaction-
System), a Call graph with no mention of Give/Takeaway/Snatch at all,
and — the significant one — the existing Common-edits entries for Give/
Takeaway still described `_release_item_to_npc()`/
`clear_held_item_external()` as the live mechanism, when a later
cross-thread plan ("Unified Item Transfer Function for Give AND Snatch")
had already superseded both with a single `release_held_item_to_npc()`
method and rewired the NPC-side contract from `receive_item_from_player()`
to `can_receive_item()`/`on_item_given()`. Marked the superseded entries
clearly, documented the current mechanism, and flagged the now-dead code
(`_release_item_to_npc()`, `clear_held_item_external()`,
`Player.on_item_snatched()`, `InventoryManager.clear_slot()`) in Known
tradeoffs as a cleanup candidate rather than removing it (no removal was
in scope here).

### Files modified
- `docs/systems/player/README.md` — Files table, Public API, Call graph,
  Common edits (superseded-path flag + new cooking-pot entry), Known
  tradeoffs.
- `HANDOVER.md` — this entry.

---
---

# Handover — Player Subsystem Cleanup Phase 1: InteractionProximityScan extraction (Aug 2026)

## Synopsis
Extracted 9 duplicated proximity-scan loops out of `scripts/player/InteractionSystem.gd` into a new helper `scripts/player/InteractionProximityScan.gd`. Phase 1 only — Phases 2-4 are scoped in `PLAYER_SUBSYSTEM_CLEANUP_ASSESSMENT_AND_PLAN.md` but explicitly not yet diffed; they await in-editor confirmation and their own plan docs.

## Root cause
`InteractionSystem.gd` had grown ~1,250 lines with five near-identical "scan `detect_area.get_overlapping_bodies()`, skip held_item/shelved/frozen, take nearest" loops (Pattern A) and four "scene-tree group scan with `MAX_PROMPT_DIST`, optional predicate" loops (Pattern B). The two `_try_add_*` stash loops and `_nearest_group_storable_distance()` even had a documented "keep filters in lockstep" coupling.

## Change
- New file `scripts/player/InteractionProximityScan.gd`: `class_name InteractionProximityScan`, `extends RefCounted`, holds an `_owner: InteractionSystem` back-reference (same precedent as `WallSnapHelpers.gd`/`PowerGraph.gd`). Three helpers:
  - `nearest_body_in_group(group_name, predicate)` — Pattern A, returns nearest qualifying `RigidBody3D`.
  - `nearest_distance_in_group(group_name, predicate)` — Pattern A, distance-only twin.
  - `nearest_in_group(group_name, max_dist, predicate)` — Pattern B, StaticBody3D-safe group scan.
- `InteractionSystem.gd`:
  - Added `var _proximity: InteractionProximityScan = null` after the `@onready` block; instantiated in `_ready()`.
  - Converted 9 call sites to one-line forwarding calls (signatures preserved):
    - `_nearest_pickup_distance()` → `nearest_distance_in_group("pickup")`
    - `_try_pickup()` → `nearest_body_in_group("pickup")`
    - `_nearest_group_storable_distance()` → `nearest_distance_in_group(group_name)`
    - `_try_add_nearest_to_basket()` → `nearest_body_in_group("basket_storable")`
    - `_try_add_nearest_to_cookpot()` → `nearest_body_in_group("cookpot_storable")`
    - `_find_nearest_open_stove()` → `nearest_in_group("stove", MAX_PROMPT_DIST, <has_open_slot lambda>)`
    - `_find_nearest_stove_with_pot()` → `nearest_in_group("stove", MAX_PROMPT_DIST, <pot_ref lambda>)`
    - `_find_nearest_npc()` → `nearest_in_group("npc", MAX_PROMPT_DIST)` (no predicate)
    - `_find_nearest_ready_pot()` → `nearest_in_group("cooking_pot", MAX_PROMPT_DIST, <is_dish_ready lambda>)`
- Deliberately NOT touched (deferred to Phase 2):
  - `_nearest_shelf()` — flat-XZ outlier.
  - `_try_interact()` / `_nearest_interact_distance()` — two-pass shared-accumulator loop.
  - CASE 2 `_update_prompt()` static scan (~lines 583-620) — has `set_player_in_range()` side effects; moves verbatim into `InteractionPromptBuilder.gd` in Phase 2.

## Verification
1. Open project in Godot editor — new script registers, no parse errors.
2. `_proximity` initializes in `_ready()` before any prompt/pickup call.
3. Pickup, Basket-stash, Cookpot-add, open-stove, stove-with-pot, NPC Give, and ready-dish prompts all still behave as before.
4. Basket/Cookpot stash: "Nothing nearby to store" / "Pot full" paths unchanged (forwarding call preserves `closest == null` semantics).
5. `_nearest_group_storable_distance()` still locks step with the two stash functions (now guaranteed by shared helper).
6. No remaining inline Pattern A/B loops except the deferred Phase 2 sites.
7. Git diff contains only InteractionSystem.gd + the new InteractionProximityScan.gd + this entry.

## Follow-ups
- Phase 2: extract `_update_prompt()` (~290 lines) into `InteractionPromptBuilder.gd`.
- Phase 3: consolidate held-item bookkeeping (`_release_item_to_npc()` vs `release_held_item_to_npc()` divergence).
- Phase 4: constants gathering, PlayerStats doc-comment move, dispatch-chain docs, README Files-table line count (~686 stale; file is now ~1,144 lines).

---

# Handover — Fix: Unqualified NPC.gd Consts Referenced from NPCBrain.gd (Aug 2026)

## What changed this session
`TALK_BASE_SCORE` and `GIVE_TO_FRIEND_BASE_SCORE` are declared on
`NPC.gd`, but `TalkActivity`/`GiveToFriendActivity` are inner classes of
`NPCBrain.gd` and need the `NPC.` qualifier to see them — same reason
`NPCBrain.EatActivity.new()` needs the `NPCBrain.` prefix from outside
that file. Two one-word fixes:
- `TalkActivity.score()` → `NPC.TALK_BASE_SCORE`
- `GiveToFriendActivity.score()` → `NPC.GIVE_TO_FRIEND_BASE_SCORE`

No other lines reference either const (verified via grep — only the
declarations in NPC.gd remain unqualified).

### Files modified
- `scripts/npc/NPCBrain.gd` (2 const qualifiers).
- `HANDOVER.md` (this entry).

### Verification checklist
No behavioral change in values — `TALK_BASE_SCORE`/`GIVE_TO_FRIEND_BASE_SCORE`
are still 5.5; this only fixes the reference-qualification so the inner
classes resolve them. No Godot CLI — recommend opening the project to
compile-check.

---

# Handover — Cooking Pot UI: Persistence Fix, Layout, 2x Size, Rotation, Food Can (Aug 2026)

## What changed this session
Plan `PLAN_cooking_pot_ui_fixes.md` (copied to repo root), owned by the
UI instance. Two disappearing-UI bug fixes, a scene layout rework, a 2x
size + rotation change, and a Food Can preview fix.

### §1 — Two disappearing-icon bugs (root cause found + fixed)
`InteractionSystem._update_prompt()` builds prompt entries in two
branches: CASE 1 (holding something) and CASE 2 (empty-handed, nearby
interactables).
- **Bug 1** CASE 2 already computes `get_slot_icon_descriptors()` and
  sends `"icons"`; CASE 1 never did, so a held item's icon row (e.g.
  CookingPot's 3 ingredient circles) vanished the instant it was picked
  up. **Fix 1a** adds the same generic `"icons"` key to the CASE 1 held
  entry (works for any held item implementing
  `get_slot_icon_descriptors()`, not cooking-specific).
- **Bug 2** `_tracked_bodies` (the set CASE 2 scans) is fed by the
  player's Area3D `body_entered`. It's explicitly erased at pickup, but
  nothing re-adds on a quick-drop — a dropped item that lands back
  roughly where it was picked up never physically crosses the trigger
  boundary (reparented away and back), so `body_entered` never refires.
  **Fix 1b** re-adds the dropped item to `_tracked_bodies` in
  `_quick_drop()` so it reappears immediately (mirrors the pickup
  erase in reverse). Stove-placing path is unaffected (frozen bodies use
  a separate per-frame group scan, not `_tracked_bodies`).

### §2 — InteractPrompt.tscn replaced entirely
`IconRow` changed from HBoxContainer (positions auto-managed) to a plain
`Control` with each slot's `position`/`size` authored permanently in the
scene. Icons 32px→64px (2x), gap kept 8px, row 208×74px. Middle slot
(Slot1) sits at y=0, the flanking slots at y=10 — that's the "15%
higher" middle expressed in fixed pixels (~10px of 64). The Panel now
gets its FIRST real `StyleBoxFlat` (`PromptPanelStyle`): dark background
0.08/0.08/0.09@0.88, border 0.55/0.58/0.62@0.60, radius 8, content
margins 12/12/18/10 — this is what fixes the "icons touch the top edge"
padding complaint AND brings the panel onto the shared dark/bordered
palette. Blast radius: affects the floating prompt for EVERY interactable
in the game (flagged in the plan — the same shared panel, no cooking-only
way to touch it).

### §3 — InteractPrompt.gd
- `ICON_VP_SIZE` 40 → 80 (keeps ~1.25x oversample vs the 64px display
  slots); `ICON_CAM_SIZE` unchanged.
- The preview pivot now gets
  `rotation_degrees = Vector3(-45, -45, 0)` — matching
  BuildModeHUD's PREVIEW_ROTATION_DEFAULT / InventoryHUD previews; these
  previews previously rendered at each item's raw default orientation.

### §4 — CookingPot food_can preview fix
The `food_can` descriptor was `{"is_script": true, ... FoodCan.gd}`.
`is_script` instantiates a bare `Script.new()` with no child nodes, but
`FoodCan.gd._ready()` does `get_node_or_null("MeshInstance3D")`, expecting
an authored mesh child — so it rendered empty/invisible. Changed to point
at the actual scene `res://scenes/world/FoodCan.tscn` (verified: that
scene DOES author a `MeshInstance3D` child), which fixes it.

### Files modified
- `scripts/player/InteractionSystem.gd` (Fix 1a + Fix 1b — Player-thread
  file, edited per the plan's explicit, flagged §1 direction).
- `scenes/ui/InteractPrompt.tscn` (replaced entirely).
- `scripts/ui/hud/InteractPrompt.gd` (2 constants + pivot rotation).
- `scripts/world/items/CookingPot.gd` (food_can descriptor).
- `HANDOVER.md` (this entry).

### Verification checklist
Plan §5 items 1–10. All anchors matched; the fix path
`res://scenes/world/FoodCan.tscn` verified to exist (referenced by
`CanCase.gd` and the file authors the mesh child). No Godot CLI —
recommend opening the project to compile-check.

---

# Handover — Fix: JobBoardStale Target After Harvest + F7 NPC↔NPC Relationship Buttons (Aug 2026)

## What changed this session
Plan: `NPC_JOBBOARD_STALE_TARGET_FIX_AND_NPC_RELATIONSHIP_BUTTONS.md`
(copied to repo root).

### Part A — JobBoard stale-target bug fix
Symptom: a plant that was just harvested but its job's target already
freed could still be returned by `get_open_jobs()` and handed to a
DIFFERENT NPC's `JobActivity.score()` as if still open. Godot flags the
freed reference the moment it's assigned to a typed `Node` var — before
`score()`'s own `is_instance_valid()` even runs — so the typed var
raised "freed instance" errors.
- `get_open_jobs()` now iterates `_jobs.keys().duplicate()` and drops
  any job whose `target` is null/invalid immediately (`_jobs.erase(id)`),
  rather than waiting up to `SCAN_INTERVAL` for the next `_rescan()`.
- `still_valid()` now also checks the job's `target` is a valid live
  node — covers an NPC already mid-work on a job whose target got freed
  some other way before they finished (same class of gap, same fix).

### Part B — F7 NPC↔NPC relationship buttons
- `NPC.debug_adjust_relationship(target_id, delta)` — the generalized
  write (bypasses the Sociability multiplier, clamps to
  RELATIONSHIP_MIN/MAX); `debug_adjust_player_relationship(delta)` is
  now a thin wrapper.
- Two AdminMenu buttons: "NPC↔NPC Relationship -25/+25 (All Pairs)" →
  `_adjust_all_npc_npc_relationships(delta)`, which adjusts every
  DIRECTED pair independently (A→B and B→A as separate one-sided
  feelings), for every spawned NPC, skipping self.

### Files modified
- `scripts/npc/JobBoard.gd` — `get_open_jobs()` + `still_valid()`.
- `scripts/npc/NPC.gd` — `debug_adjust_relationship()` +
  thin player wrapper.
- `scripts/ui/menus/AdminMenu.gd` — 2 rows + 1 handler helper.
- `docs/systems/npc/README.md` — testing items 64–65.
- `HANDOVER.md` — this entry.

### Verification checklist
See plan items 49–50 (documented as 64–65 in README). No Godot CLI —
recommend opening the project to compile-check.

---

# Handover — NPC↔NPC Talking, Give-to-Friend, and Generalized Snatch (Aug 2026)

## What changed this session
Plan: `NPC_TO_NPC_TALK_GIVE_SNATCH_PLAN.md` (copied to repo root). Three
NPC↔NPC social systems, plus unified snatch targeting. No Player-subsystem
changes — `on_item_given()`'s new params default to player-Give, so
`InteractionSystem.gd`'s call site needed zero edits.

### Part A — Snatch generalized to any target (player + NPC)
- `NPC.gd`: added `get_held_item()` (duck-typed parity with Player, so
  targets are interchangeable). Split `get_snatch_chance()` into the
  generalized `get_snatch_chance_toward(id)` (kept the old name as a
  player-only wrapper for the F7 debug). Replaced
  `find_player_snatch_target()` with `find_snatch_target()` — one unified
  candidate pool (player + every NPC holding a matching item, relationship
  ≤ -50, ties → nearest), a single roll against the chosen target's own
  relationship. `_debug_force_snatch` still force only targets the player;
  new `_debug_force_npc_snatch` forces an NPC target (skips player, gates,
  and roll).
- `NPCItemUser.snatch_from_player()` → `snatch_from(&)`: player targets
  still go through `release_held_item_to_npc()` (inventory-slot context);
  NPC targets do a direct physical reassignment plus call the victim's new
  `on_item_snatched_by_npc()` (releases the victim's claim, logs "<thief>
  snatched an item from <victim>", relationship-neutral).
- `SnatchActivity` retargeted: `_player` → `_target` throughout (continuous
  re-aim, dropped-item chase, MAX_CHASE_TIME all unchanged, already written
  against a generic Node). Success log now "Snatched an item from {player
  name|npc name}".
- Generalized the score() snatch-trigger gate: `is_player_snatch_eligible`
  → `is_npc_snatch_eligible` (player OR any disliked NPC holding a matching
  item), so the "prefer snatch over a normal search" trigger also fires for
  NPC targets organically.

### Part B — NPC↔NPC Talking (groundwork only)
- `TalkActivity` (non-blocked; only when already within `TALK_RANGE=3.0`):
  score = `TALK_BASE_SCORE (5.5) × work-ethic passive mult`, then × a
  relationship curve flat 1.0x in the −15..+15 neutral band, up to 2.5x
  at +100, down to 0.2x at −100 (`get_talk_score_mult`).
  Non-interruptible once locked in; both `lock_movement()` and face each
  other (8–20 real seconds); both sides log "Talked to X".
- One partner-side instance `force_command`'d via `start_talk_session()`
  (is_initiator=false); `end_talk_session()` clears it so the partner never
  hangs. `exit()` also clears the partner on interruption. FUTURE WORK:
  conversation OUTCOMES deliberately not built.

### Part C — Give-to-Friend
- `on_item_given()` now takes `giver_id`/`giver_name` (defaults "player"/
  "Player") so the relationship boost lands on the ACTUAL donor, not always
  the player. Give log generalized to "{giver} gave {item} to
  {npc_name}".
- Added chance (`get_give_to_friend_chance`: 5% at +25 → 50% at +100),
  cheap determinist `has_needy_friend()`, and full `find_friend_to_help()`
  (nearest needy friend, matching loose item, one roll).
- `GiveToFriendActivity`: fetch (mirrors JobActivity), travel (mirrors
  Snatch re-aim), hand-off via `can_receive_item()` + `on_item_given(item,
  npc_id, npc_name)`. Interruptible throughout. If interrupted carrying the
  item, keeps it (finishes/uses on re-entry).

### Part D — AdminMenu debug buttons (nice-to-have, implemented)
"Force Nearest NPC to Talk to NPC", "Force Nearest NPC to Give to Friend",
"Force Nearest NPC to Snatch NPC Item" — one-shot flags mirroring
`_debug_force_snatch`, bypassing gates/roll but still requiring a valid
partner/friend/item. Added `_nearest_npc_to_player()` helper.

### Deviations from the plan
- `find_snatch_target` forced-branch: kept `_debug_force_snatch`
  player-only; added a separate `_debug_force_npc_snatch` flag instead of
  the plan's single forced path, so the two F7 buttons stay distinct.
- AdminMenu buttons: the plan's "nearest eligible PAIR" idea was simplified
  into a flag-based one (nearest NPC calls its own normal search with gates
  bypassed).

### Files modified
- `scripts/npc/NPC.gd` (talking + give constants/funcs, generalized snatch,
  `get_held_item`, debug flags, `on_item_snatched_by_npc`).
- `scripts/npc/NPCBrain.gd` (`TalkActivity`, `GiveToFriendActivity`, brain
  helpers, `SnatchActivity` retargeted, `snatch_from`, generalize gates).
- `scripts/npc/NPCItemUser.gd` (`snatch_from_player` → `snatch_from`).
- `scripts/ui/menus/AdminMenu.gd` (3 debug buttons).
- `docs/systems/npc/README.md` (new Talking/Give-to-Friend sections,
  generalized Snatch section + F7 buttons, trait ref, testing items 58–63).
- `HANDOVER.md` (this entry).

### Verification checklist
See plan items 43–48 (documented as 58–63 in README). No Godot CLI —
recommend opening the project to compile-check.

---

# Handover — Fix: Action Log Wording — "you/your" → NPC Name / "the player" (Aug 2026)

## What changed this session
Pure wording fix — the action log is a third-person, objective record
for a specific named NPC, so every "you"/"your" was replaced with either
the NPC's own name (when it referred to the NPC) or "the player" (when
it referred to the player). Six lines across two files:
- Give new-gift: "Player gave you X" → "Player gave X to {name}".
- Give repeat-gift: → "Player gave X to {name} (fed only...)".
- Takeaway: "Player took X from you" → "Player took X from {name}".
- Relax interruption: "interrupted your relaxation" → "{name}'s
  relaxation".
- Relationship band crossing: "Relationship with you" → "with the
  player".
- Snatch success (NPCBrain): "your hands" → "the player's hands".

No other lines needed changes (Relaxed/X min, Job (Harvest), Passed out,
Woke up, contagion/mood entries never used "you").

### Files modified
- `scripts/npc/NPC.gd` — 5 log lines (uses `npc_name`, a valid member).
- `scripts/npc/NPCBrain.gd` — 1 snatch line.
- `HANDOVER.md` — this entry.

### Verification checklist
Trivial wording change only — no behavioral change; verify by opening an
NPC's E-panel and checking the log reads naturally in third person. No
Godot CLI available — recommend opening the project to compile-check.

---

# Handover — Per-Plant Harvest Jobs + NPC Action Log (Aug 2026)

## What changed this session

### Part A — Harvest: one job per plant, not per tray
`JobBoard._scan_harvest()` now posts one HARVEST job per READY PLANT
(target = the plant, `harvest_<plant id>`), not one per tray — a 2x1
tray with both cells ready posts two independent, separately-claimable
jobs. `NPCBrain`'s HARVEST `_complete()` now harvests just its single
plant target (guarded with `is_ready()`), instead of looping every ready
plant in a tray.

### Part B — Action Log: data model (NPC.gd)
`NPC.log_action()`/`get_action_log()` — per-NPC, curated (NOT routine
activity switches), mirrors NotificationManager's capped-array + signal +
live-rebuild pattern. Captures both `fired_at_msec` and a `game_time`
HUD-clock snapshot. `_check_contagion_log()` (logs only after cumulative
mood-contagion drift crosses ±2%) and `_check_label_crossings()`
(irritability/relationship band crossings) hooked into the 5s mood tick.
`_adjust_relationship()` now RETURNS the actual post-Sociability,
post-clamp applied delta (all existing callers keep working, ignoring
the return).

### Part C — Log call sites
- Give: "Player gave you X (+N relationship)" using the applied delta;
  repeat-gift: "fed only, no relationship change".
- Takeaway (need-triggered only): "Player took X from you (+N
  relationship)". Non-need takeaways deliberately not logged.
- Relax interruption: "Player interrupted your relaxation (+N
  relationship)".
- `RelaxActivity.exit()`: "Relaxed for N min" (skipped if session never
  started).
- `PassedOutActivity`: "Passed out (0 energy)" on collapse, "Woke up" on
  exit.
- Snatch success: "Snatched an item from your hands" (aborted/failed/
  dropped-item-chase deliberately not logged).
- Job (Harvest) completion: "Job (Harvest)".

### Part D — UI log dropdown (NPCTalkMenuUI.gd)
"Show Activity Log ▾" toggle expands the panel by `LOG_SECTION_H` via
`_apply_panel_height()` (re-centering math mirrors
`UIKit.build_centered_panel()`), revealing a fixed-height scroll area
rebuilt live off `action_logged`; timestamps tick as "Xs/m/h ago".
Collapsed by default each open; signal disconnected in `_teardown()`.

### Files modified
- `scripts/npc/JobBoard.gd` — per-plant harvest jobs.
- `scripts/npc/NPCBrain.gd` — HARVEST `_complete()` per-plant + log
  calls (Relax exit, PassedOut enter/exit, Snatch success).
- `scripts/npc/NPC.gd` — Action Log data model, tick hooks,
  `_adjust_relationship()` return value, Give/Takeaway/Relax log calls.
- `scripts/ui/npc/NPCTalkMenuUI.gd` — log dropdown (constants, vars,
  build, merged `_process`, teardown disconnect, new functions).
- `docs/systems/npc/README.md` — new Action Log section; Skills & Jobs
  harvest note updated (per-plant); testing items 52–57 (renumbered from
  plan's 37–42).
- `HANDOVER.md` — this entry.

### Deviations from plan (both benign)
- The plan said "create a `_process` if this UI doesn't already have
  one" — NPCTalkMenuUI already had one driving `_refresh_live_values()`
  on a timer. Merged the log-timestamp refresh into it instead of
  replacing it (the plan's replacement would have broken the live need
  bar refresh).

### Verification checklist
See `NPC_HARVEST_PERPLANT_AND_ACTION_LOG_PLAN.md` items 37–42 (52–57 in
the README). No Godot CLI available — recommend opening the project to
compile-check.

---

# Handover — NPC Time-Skip Catch-Up Simulation (Aug 2026)

## What changed this session
Time-skips (F7 Fast-Forward, sleep) previously left NPCs completely
frozen — `skip_time_with_drain()` in PlayerStats only touched the player.
New static entry point `NPC.catch_up_all(hours)` simulates how NPCs spend
a skip, called explicitly by each skip source right next to its existing
`skip_time_with_drain()` call. Any FUTURE skip source must call it too —
nothing hooks the game clock automatically. Hard ceiling
`MAX_CATCHUP_HOURS` (72).

Per NPC, in order (`catch_up_time()`):
- **Needs:** full drain, then an estimate of how many real meals/drinks
  would have offset it, actually consumed from real world items via their
  own `consume_as_food()`/`take_bite()`/`take_drink()` calls (capped by
  what's there — empty bunker = NPC goes hungry).
- **Energy:** full drain; if it would cross 0 mid-skip, the same
  neuroticism-scaled mood drop `PassedOutActivity` uses fires once
  (logged via `log_mood_event`), remainder regens at 15/game-hour.
- **Relax budget:** proportionally deducted for the skip's fraction of a
  day (`_catch_up_relax_budget()`), after a day-boundary reset — 6h skip
  removes 25% of daily budget, 12h removes 50%.
- **Mood:** `_tick_mood()`'s own needs-pull + drift formulas evaluated
  once with a large h; contagion is one blended pull toward the PRE-skip
  bunker average (snapshotted once), scaled + clamped. Approximate by
  design.
- **Harvest:** every `is_ready()` plant snapshotted once; each NPC
  harvests up to `floor(hours)` from the shared pool (one plant = one
  "job", not one tray-job). Not-ready plants are never auto-harvested.

### Files modified
- `scripts/npc/NPC.gd` — static `catch_up_all()` + per-NPC
  `catch_up_time()` and helpers (`_catch_up_hunger_and_thirst`,
  `_catch_up_energy`, `_catch_up_relax_budget`, `_catch_up_mood`) +
  constants.
- `scripts/npc/NPCDebug.gd` — `log_catchup()`.
- `scripts/ui/menus/AdminMenu.gd` — `NPC.catch_up_all(24.0)` after
  fast-forward's `skip_time_with_drain(24.0)`.
- `scripts/ui/menus/SleepOverlay.gd` ⚠️ — one line
  (`NPC.catch_up_all(SLEEP_SKIP_HOURS)`) — flagged in the plan as
  possibly another thread's file; trivial addition, no change to existing
  sleep behavior. Caller of that thread should be aware.
- `docs/systems/npc/README.md` — new **Time-Skip Catch-Up** section;
  Trait Effects Reference Neuroticism note updated (mood-drop reachable
  via catch-up too); testing items 47–51 (renumbered from plan's 32–36
  to avoid collision).
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_TIMESKIP_CATCHUP_PLAN.md` items 32–36 (47–51 in the README). No
Godot CLI available — recommend opening the project to compile-check.

---

# Handover — Pass-Out: Wake at 15 Energy + Neuroticism-Scaled Mood Drop (Aug 2026)

## What changed this session
Two changes to the pass-out flow plus a documentation consolidation.

### Wake at 15, not 100
`PassedOutActivity` now has `WAKE_ENERGY = 15.0` and `done()` returns
`npc.energy >= WAKE_ENERGY` instead of `>= 100.0`. Deliberately leaves a
passed-out NPC still needing real rest afterward; also the intended hook
for a future "administer an energy item to wake them faster" player
action.

### Neuroticism-scaled mood drop on collapse
`PassedOutActivity.enter()` now applies a one-time mood drop the instant
an NPC collapses: `randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())`
(lower bound fixed at 1%, baseline upper 10%, Neurotic 15%, Easygoing
5%), clamped, logged via the new `NPCDebug.log_mood_event()`.

### Neuroticism multiplier made public
`_neuroticism_trait_mult()` (private, created by the earlier Work Ethic/
Neuroticism plan) was renamed to public `neuroticism_trait_mult()` and
its single call site in `_tick_mood()` updated — no duplicate function.

### Files modified
- `scripts/npc/NPCBrain.gd` — `WAKE_ENERGY` const, `done()` at 15,
  mood-drop block in `enter()`.
- `scripts/npc/NPC.gd` — `neuroticism_trait_mult()` (renamed public) +
  call site.
- `scripts/npc/NPCDebug.gd` — `log_mood_event()`.
- `docs/systems/npc/README.md` — new **Trait Effects Reference** section
  (canonical list of all 5 traits' effects) + **Non-Trait NPC Mechanics
  Worth Noting Alongside Traits** (pass-out wake-at-15); Personality
  bullets updated to point at the canonical section; testing items 45–46
  (renumbered from plan's 30–31 to avoid collision).
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_PASSOUT_WAKE_AND_MOOD_DROP_PLAN.md` items 30–31 (45–46 in the
README). No Godot CLI available — recommend opening the project to
compile-check.

---

# Handover — Fix: Relaxing In a Chair/Bed Loops When Energy Is Already Full (Aug 2026)

## What changed this session
Root cause: `LieActivity.done()` returns `_lying and energy >= 100`
(`SitActivity` the same at 90). `RelaxActivity` delegates to these via
`enter()` — correct, since score() being blocked at high energy should
not stop a scheduled relax — but `done()` doesn't care HOW it was
entered: at already-full energy, `done()` is true the instant seated,
stand back up, loop.

Fix: two new delegation-only activities in `NPCBrain.gd`:
- `RelaxSitActivity extends SitActivity`, `RelaxLieActivity extends
  LieActivity`. Same arrival/seating mechanics, but `done()` no longer
  checks energy at all (chair/bed-null only) — RelaxActivity's session
  timer is the only thing that ends them. Energy regen runs at **1/4**
  normal rate (a break, not full rest/sleep). `score()` returns 0.0 so
  they can never be auto-selected.
- `RelaxActivity.enter()` now composes the Relax-prefixed classes, so the
  `done()`-right-after-`enter()` fallback chain now means "no chair/bed
  found", never "energy already full".

Normal Sit/Lie behavior untouched.

### Files modified
- `scripts/npc/NPCBrain.gd` — two new classes + `RelaxActivity.enter()`
  swap.
- `docs/systems/npc/README.md` — testing items 42–44 appended.
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_RELAX_ENERGY_LOOP_FIX.md` (3 steps). No Godot CLI available —
recommend opening the project to compile-check.

---

# Handover — Trait Absence Is Baseline + Relaxing Activity (Aug 2026)

## What changed this session
Two independent changes in the NPC subsystem.

### Part A — Traits only exist when they matter
- `NPC.randomize_personality()` no longer fills all 5 trait slots with a
  flat 0.0–1.0 roll. Each slot is now present with 55% chance
  (`TRAIT_PRESENCE_CHANCE`), and a *present* trait is skewed into the low
  or high band (never the neutral middle). Absent = baseline: every
  `_*_trait_mult()` uses `.get(key, 0.5)`, which already meant baseline —
  no multiplier changes were needed.
- `get_trait_word()` returns "" for an absent key; `get_personality_words()`
  filters empties, so an NPC shows anywhere from 0–5 personality words.
- `NPCTalkMenuUI` falls back to "Nothing stands out" for the 0-trait case.

### Part B — Relaxing
- New `RelaxActivity` (NPCBrain) — a scheduled break distinct from
  Wander/Idle. Composes `SitActivity`/`LieActivity` for the actual
  seating mechanics (same pattern as `CommandRestActivity`), or stands in
  place if neither a chair nor a bed is free. Flat baseline score (6.0,
  above Wander's 5.0) × Work Ethic passive mult, gated by a daily time
  budget.
- Daily budget: 1 game-hour/day baseline, 2 for Lazy
  (`NPC.get_relax_daily_budget()`), tracked via `spend_relax_time()` and
  reset by `_tick_relax_day()` on the same 5s tick as mood. Sessions run
  ~20–40 game-minutes.
- Job-refusal while relaxing: first "Harvest the plants" command during a
  relax session is refused with a flavor line
  (`get_relaxing_refusal_line()`); the second ask complies at -3
  relationship (`request_job_while_relaxing()`). Counter resets each
  relax session via `reset_relax_job_requests()`.

### Files modified
- `scripts/npc/NPC.gd` — presence-based personality generation; trait-word
  display; Relaxing section (budget, refusal state, dialogue).
- `scripts/npc/NPCBrain.gd` — `RelaxActivity` registered in `setup()`'s
  candidate list; `is_relaxing()`; the new class.
- `scripts/ui/npc/NPCTalkMenuUI.gd` — personality empty-list fallback;
  harvest-command relaxation interception.
- `docs/systems/npc/README.md` — Personality section updated (presence-
  based); new Relaxing subsection; testing items 39–41 (renumbered from
  the plan's 27–29 to avoid colliding with the existing checklist).
- `HANDOVER.md` — this entry.

### Verification checklist
See `NPC_TRAIT_BASELINE_AND_RELAXING_PLAN.md` items 27–29 (39–41 in the
README). No Godot CLI available — recommend opening the project to
compile-check.

---

# Handover — Shelf E-Hijack Fix (Aug 2026)

## What changed this session
Fixed a bug (reported by Brannon, root-caused by the Furniture/Build-Mode
thread, fix implemented here): holding a Basket and pressing E near both
a food can and a shelf always opened the shelf, even when the can was
closer — the shelf's E-dispatch check ran first and unconditionally, so
it hijacked E from the basket-stash, cookpot, and NPC-give branches
alike. Added `_nearest_e_rival_distance()` (returns the distance to
whatever the held item's own E action would target, or INF if it has
none) and `_nearest_group_storable_distance()` (distance-only twin of the
basket/cookpot candidate scan, filters kept in lockstep). The shelf check
now only wins when strictly closer than the rival distance. Third
instance of the same fairness pattern as the earlier F-dispatch
stove-pot-vs-pickup fix and the ready-dish check.

### Files modified
- `scripts/player/InteractionSystem.gd` — shelf E-dispatch check now
  distance-gated; two new helper functions.
- `docs/systems/player/README.md` — E-dispatch section updated.
- `docs/systems/furniture-items/README.md` — one-line cross-reference
  (Furniture-subsystem-owned file, flagged for their visibility).
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_SHELF_E_HIJACK_FIX_PLAN.md` for the
full 5-item checklist)

---

# Handover — NPC Meter Colors: Match Player HUD Palette (Aug 2026)

**Owner:** UI Claude instance (HUD/menus).

## What changed
`NPCTalkMenuUI.gd`'s 5 need bars (Health/Energy/Hunger/Thirst/Mood) used
to recolor by VALUE (theme.ok/warn/crit — blue/amber/red by fill level),
the opposite convention from the player's own `NeedsGauge` rings, which
use ONE fixed identity color per stat. Now the NPC bars match the player
HUD: fixed per-stat colors, fill LENGTH is the only value feedback.
- Health: `Color(0.81, 0.17, 0.17)` — exact copy of `NeedsGauge.COLOR_HEALTH`.
- Energy: `Color(0.57, 0.33, 0.81)` — exact copy of `NeedsGauge.COLOR_SLEEP`.
- Thirst: `Color(0.24, 0.52, 0.90)` — exact copy of `NeedsGauge.COLOR_WATER`.
- Mood: `Color8(188, 160, 220, 255)` — exact `#bca0dc` (Brannon's spec),
  via `Color8` so no float rounding.
- Hunger: `Color(0.90, 0.80, 0.20)` — the player HUD has no yellow stat
  to copy, so this reuses the project's other established yellow (Power
  panels' stripe color). One-line swap if a specific yellow was wanted.

Added `NEED_COLORS` table (`fallback = theme.ok` via `.get()`); the
refresh loop's per-value recolor line is now just the fixed color.

## Files Modified
`scripts/ui/npc/NPCTalkMenuUI.gd` (one const table + two color lines).

## Next Up
- None — verification checklist in the plan: reopen an NPC talk panel and
  confirm the 5 colors, drain needs and confirm bars don't recolor
  (only fill length shrinks), no console errors.

---

# Handover — Wire Up Work Ethic + Neuroticism (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
Work Ethic and Neuroticism moved from "generated/displayed only" to
fully wired mechanics (the last two of the five traits — all five now
drive behavior).

- **Work Ethic** — ±30% score multiplier applied symmetrically:
  `JobActivity.score()` × `get_work_ethic_job_mult()`
  (`lerp(0.7, 1.3, work_ethic)`), and every passive/need activity —
  Wander, Sit, Lie, Eat, Drink — × `get_work_ethic_passive_mult()`
  (`lerp(1.3, 0.7, work_ethic)`, the mirror image). Hard Worker: jobs
  ×1.3 / passive ×0.7. Lazy: jobs ×0.7 / passive ×1.3. Steady: ×1.0 both.
  Same continuous score-bias pattern Irritability already uses — not a
  discrete roll.
- **Neuroticism** — scales mood's random per-tick drift
  (`MOOD_DRIFT_MAX_PER_GAME_HOUR`) via `_neuroticism_trait_mult()`
  (`lerp(0.5, 1.5, neuroticism)`, same 0.5x-1.5x spread as Sociability).
  Neurotic: ×1.5 (wilder swings). Composed: ×1.0. Easygoing: ×0.5
  (calmer). Only the noise component — needs and contagion unaffected.

## Files Modified
`scripts/npc/NPC.gd` (two new multiplier functions +
`get_work_ethic_job_mult()`/`get_work_ethic_passive_mult()`, one drift-tick
line), `scripts/npc/NPCBrain.gd` (six activity `score()`s).

## Next Up
- None specific — testing items 37-38 in `docs/systems/npc/README.md`
  cover both traits.

---

# Handover — Trait Word Fix: "Kind" → "Open" (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
`NPC.TRAIT_WORDS["sociability"]["high"]` was still `"Kind"` — the
agreed-upon rename to `"Open"` (better captures fast relationship
reactivity in both directions without the value judgment) had never
actually landed. Fixed in `scripts/npc/NPC.gd`, and cleaned up the stale
`FUTURE WORK` comment a few lines up that still described Sociability as
unwired — it's now wired via `_sociability_trait_mult()`. No code depends
on the old string (`get_personality_words()`, the E-panel, and `NPCDebug`
all read from the dictionary); `docs/systems/npc/README.md`'s trait-word
band listing updated to match.

## Files Modified
`scripts/npc/NPC.gd` (one dictionary value + one comment),
`docs/systems/npc/README.md` (trait-word band listing).

## Next Up
- None.

---

# Handover — Snatch: Distinguish "Dropped" from "Swapped Away in Inventory" (Aug 2026)

**Owner:** NPC Claude instance.

## What changed
`SnatchActivity.tick()`'s "did they drop it, chase it on the ground"
branch only tested `not _tracked_item.is_held`. But
`InventoryManager.deactivate_item()` (player scrolling to another slot)
also sets `is_held = false`, so a swapped-away, frozen-in-place stored
item was treated as a genuine drop — the NPC walked to its stale last
position and grabbed it straight out of the inventory slot array.

The two states are distinguishable by `collision_layer`:
- genuinely dropped (`remove_item()`) → `collision_layer == 1`
- swapped away/stored (`deactivate_item()`) → `collision_layer == 0`
- actively held (`activate_item()`/`pickup()`) → `collision_layer == 2`

Added `"collision_layer" in _tracked_item and _tracked_item.collision_layer
== 1` to the chase condition. If it now correctly fails (stored, not
dropped), the code falls through to the existing fallback, which already
logs `"aborted"` and ends the activity cleanly. Genuine drops still pass.

## Files Modified
`scripts/npc/NPCBrain.gd` (one condition in `SnatchActivity.tick()`).

## Next Up
- None specific — testing items 35-36 in `docs/systems/npc/README.md`
  cover both branches (swap-abort and genuine-drop-divert).

---

# Handover — Snatch Root-Cause Fixes: Scoring Blind Spot, Wrong Inventory Function, Grab Distance (Aug 2026)

**Owner:** NPC Claude instance, plus one function fix in Player-owned
`InteractionSystem.gd`.

## What changed
1. **Scoring blind spot fixed** — `EatActivity.score()`/`DrinkActivity.score()`
   returned 0 (activity never selected) whenever no normal world target
   existed, even if the player was holding the only matching item and the
   relationship was hostile. Added `NPC.is_player_snatch_eligible()` — a
   deterministic, roll-free check mirroring `find_player_snatch_target()`'s
   gates minus the probability roll — and both `score()`s now fall through
   to it, so the activity gets selected and `enter()` runs (where the real
   roll happens).
2. **Snatched item no longer drops** — `InteractionSystem.release_held_item_to_npc()`
   called `inventory.remove_item()`, whose internal `item.drop()` unfroze
   physics/gravity and emitted `dropped` one line before the transfer
   `pickup()`. Reordered: physically `pickup()` first, then clear the slot
   via `inventory.clear_slot()` (the function whose own doc comment says
   it's meant to run AFTER an NPC's pickup() reassignment — Snatch).
   Item now visibly transfers to and stays in the NPC's hand.
3. **Grab distance** — new `NPCItemUser.SNATCH_RANGE = 1.6` (vs the
   loose-item `PICKUP_RANGE = 1.2`) used by both `SnatchActivity.tick()`'s
   player-chase branch and `snatch_from_player()`'s range check, so the
   NPC stops at a visible gap instead of walking into physical contact
   with the player. The dropped-item ground-chase branch keeps
   `PICKUP_RANGE` (loose item, no collision body) unchanged.

## Files Modified
`scripts/npc/NPC.gd` (new `is_player_snatch_eligible()`),
`scripts/npc/NPCBrain.gd` (two `score()`s, `SnatchActivity` range),
`scripts/npc/NPCItemUser.gd` (`SNATCH_RANGE` + range check),
`scripts/player/InteractionSystem.gd` (`release_held_item_to_npc()`).

## Next Up
- None specific — testing items 32-34 in `docs/systems/npc/README.md`
  cover the three fixes; the scoring-blind-spot fix is the one most worth
  re-verifying in-editor (it changes what `_think()` picks).

---

# Handover — Storage UI Unification: ShelfUI + BasketUI → StorageUI (Aug 2026)

**Owner:** UI Claude instance (HUD/menus/Build Mode/Furniture).

## What changed
- New `scripts/ui/inventory/StorageUI.gd` — one generic, config-driven
  storage overlay replacing `ShelfUI.gd`/`BasketUI.gd` (476/470 lines, 17
  of 18 duplicated). Any storage object implements a 4-method contract
  (`get_ui_config`, `get_slot_display`, `take_for_carry`,
  `take_for_inventory`) and needs zero new UI code.
- `Shelving.gd`/`Basket.gd` (furniture-items scope) implement that
  contract as thin wrappers over their existing retrieval logic —
  `retrieve_to_carry()`/`retrieve_to_inventory()` gained bool return
  values, nothing else about their behavior changed (NPC-facing
  `npc_retrieve()` and existing signals untouched).
- `MainWorld.gd`'s `_setup_shelf_ui()`/`_setup_basket_ui()` collapsed into
  one `_setup_storage_ui()`. `InteractionSystem.gd` (Player-thread-owned)
  needed ZERO changes — its `shelf_ui`/`basket_ui` properties both now
  point at the same shared instance.
- Deliberately built with room for planned future storage types (lockable
  storage, freezers/fridges, lockers, larger shelving units) — see
  `docs/systems/ui/README.md`'s "Storage UI Unification" section for how
  each fits without touching `StorageUI.gd` again.

## Files Created
`scripts/ui/inventory/StorageUI.gd`

## Files Deleted
`scripts/ui/inventory/ShelfUI.gd` + `.uid`,
`scripts/ui/inventory/BasketUI.gd` + `.uid`

## Files Modified
`scripts/world/furniture/Shelving.gd`, `scripts/world/items/Basket.gd`,
`scripts/world/core/MainWorld.gd`,
`scripts/world/build/BuildModeController.gd`

## Next Up
- Visual styling (`UIKit` domain-stripe system) not applied to
  `StorageUI.gd` in this pass — flagged as a deliberate, deferrable
  choice, not an oversight.
- First planned future storage type (lockable storage / freezer / locker
  / larger shelving) will be the real test of the contract — implement it
  by adding the 4 contract methods to that object's own script, nothing
  else.

---

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

# Handover — Re-applied Dropped Fixes + Continuous Snatch Pursuit (Aug 2026)

**Owner:** NPC instance. All NPC-side; no Player changes.

## What changed this session
- `scripts/npc/NPCItemUser.gd` — `grab_loose()` gained the missing
  `is_held` guard (an item claimed by this NPC can still have been
  physically picked up by the player — claims only block other NPCs'
  `claim_item()` calls, never the player's pickup path).
- `scripts/npc/NPCBrain.gd` — three early-abort additions: `EatActivity`
  tick()'s `_loose` branch (abandons + releases claim when the item is
  now held; also releases claim on a failed grab), `DrinkActivity`
  `_tick_bottle()` (abandons when the target bottle is held), and
  `JobActivity._tick_fetch()` (abandons when the fetch item is held).
- `scripts/npc/NPCBrain.gd` — `SnatchActivity` rewritten: continuously
  re-aims at the player every tick (was: target set once at enter());
  chases the dropped tracked item on the ground instead of giving up if
  the player drops it; new `MAX_CHASE_TIME` (20s) safety valve so a
  player who just keeps walking doesn't leave the NPC chasing forever
  (interruptible() is false, so nothing else could interrupt it);
  `done()` also requires `_tracked_item == null`.
- `scripts/npc/NPC.gd` — `find_player_snatch_target()` decision path now
  explicitly logged via `NPCDebug.log_snatch()` ("not considered" with
  reason, roll attempt, roll success/failure) when debug logging is on.
- `docs/systems/npc/README.md` — Snatch section updated for continuous
  pursuit + dropped-item follow + MAX_CHASE_TIME; Testing Checklist
  items 26-31 added.
- `HANDOVER.md` — this entry.

## Notes
- `MAX_CHASE_TIME` is a plan-author addition beyond the original ask —
  flagged in the code comment ("Remove this if indefinite pursuit is
  actually what you want") — kept per the plan.
- No Godot CLI available — no compile check ran; recommend opening the project.

---
---

# Handover — Unified Item Transfer Function for Give AND Snatch (Aug 2026)

**Owner:** Player + NPC subsystems (one mechanism now, listed as one plan).

## What changed this session
Replaced the separate patchwork (inventory-slot clearing,
HUD prompt staleness, standalone snatch pickup logic) with a single
shared transfer function mirroring `_quick_drop()` — the only difference
is the destination is an NPC's hands instead of the floor.

- `scripts/player/InteractionSystem.gd` — new `release_held_item_to_npc(npc)`
  (disconnect knocked_out, clear inventory slot via `remove_item()` if it
  came from one, clear held_item/_held_from_slot/_is_holding_e, refresh
  HUD selection, then `item.pickup(npc.hold_point)`/`npc.held_item = item`).
  `_try_give_to_nearest_npc()` simplified to: `can_receive_item()` →
  `release_held_item_to_npc()` → `on_item_given()`.
- `scripts/player/Player.gd` — `release_held_item_to_npc(npc)` forwarding
  to `InteractionSystem` (reachable via the `"player"` group node for
  NPC-side code); `get_held_item()` already existed.
- `scripts/npc/NPC.gd` — `receive_item_from_player()` removed, replaced by
  `can_receive_item()` (pure check) + `on_item_given()` (consequence
  wiring: consumption activity via force_command + begin_with_item, gift
  burnout/relationship bookkeeping). The physical transfer is now entirely
  the Player side's job since it's the only side with inventory-slot context.
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player()` simplified to route
  through `player.release_held_item_to_npc(npc)` (still separate from
  strict `grab_loose()`, still only reached via SnatchActivity's gate).
  `SnatchActivity` unchanged — it just calls `snatch_from_player()` and
  checks the boolean.
- `docs/systems/npc/README.md` — Give/Snatch sections updated for the
  unified transfer path; Testing Checklist item 25 added.
- `HANDOVER.md` — this entry.

## Notes / dead code
- `Player.on_item_snatched()` / `InteractionSystem.clear_held_item_external()` /
  `_release_item_to_npc()` / `InventoryManager.clear_slot()` are now
  UN-CALLED by Snatch (the shared `release_held_item_to_npc()` handles
  everything). Left in place per the plan (no removal instructed);
  candidates for deletion in a future cleanup pass.
- Plan's "item bumps out and drops" post-script: that symptom is the
  pre-existing knockout system (item displaced > KNOCK_DISTANCE from the
  hold point by physical shoving), not the transfer path — flagged for
  investigation only if it recurs after this.
- No Godot CLI available — no compile check ran; recommend opening the project.

---
---

# Handover — Give/Snatch Inventory-Slot Clear Fix (Aug 2026)

## What changed this session
Fixed a bug where giving or having an item Snatched by an NPC left it
showing forever in its original inventory slot. Root cause: the cleanup
in `_try_give_to_nearest_npc()` (destroyed-item branch) and
`clear_held_item_external()` (Snatch) only cleared local `held_item`/
`_held_from_slot` bookkeeping, never touching
`InventoryManager.slots[]`. Fix routes both through a new shared
`_release_item_to_npc()` helper calling a new
`InventoryManager.clear_slot()`. Deliberately did NOT use the originally
proposed `InventoryManager.remove_item()` — that method is documented
world-drop-only (resets collision_layer to 1, re-adds `"pickup"` group,
repositions via `drop()`), which would have fought an NPC's
already-completed `item.pickup(npc.hold_point)` reassignment on Snatch
(visually yanking the item back out of the NPC's hand) or errored
outright on an already-freed item on a destroyed-item Give.
`clear_slot()` only nulls the slot array entry, nothing else.

### Files modified
- `scripts/player/InteractionSystem.gd` — new `_release_item_to_npc()`
  helper; `_try_give_to_nearest_npc()` and `clear_held_item_external()`
  both now delegate to it.
- `scripts/ui/inventory/InventoryManager.gd` — new `clear_slot()` method
  (additive only, no existing method changed).
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_SNATCH_INVENTORY_CLEAR_FIX_PLAN.md`
for the full 5-item checklist)

---
---

# Handover — NPC Give Real-Transfer Fix + Dedicated Snatch Activity + Relationship Debug Buttons (Aug 2026)

**Owner:** NPC instance. Restates Give as a real transfer and redesigns
the Snatch mechanic as a dedicated non-interruptible activity.

## What changed this session
- `scripts/npc/NPCActivity.gd` — full-file replacement adding the
  `begin_with_item()` (Part 28) and `take_handoff()` (Part 30) virtuals.
- `scripts/npc/NPCBrain.gd` —
  - Core `tick()` now polls `_current.take_handoff()` right after
    `tick()` runs and switches to the returned successor (explicit
    handoff, avoiding reentrant `force_command()` from inside an
    activity's own tick). On handoff it also calls the successor's
    `begin_with_item(_npc, _npc.held_item)`.
  - New `GivenEatActivity extends EatActivity` and
    `GivenDrinkActivity extends DrinkActivity` — player-Give/snatch
    consumption hand-offs (score()=0, no search, keyed off held_item/`_target`).
  - New dedicated, non-interruptible `SnatchActivity` (entered via
    force_command, never scored), which walks to the player, grabs via
    `snatch_from_player()`, and hands off to Given* via `take_handoff()`.
  - `EatActivity`/`DrinkActivity` now stash a snatch target in
    `_pending_snatch` (from `find_player_snatch_target()` in
    enter()/_reacquire_or_finish()) and request the handoff to
    `SnatchActivity` on the next tick instead of walking the snatch
    themselves — the old in-activity snatch mode (Part 29) was
    interruptible and got cancelled mid-approach by the think-cycle.
- `scripts/npc/NPC.gd` — `receive_item_from_player()` rewritten as a
  real transfer: `force_command()` the Given* activity first, then
  `item.pickup(hold_point)`/`held_item = item`, then
  `activity.begin_with_item()`; consumption is async inside the
  activity's tick, not instant. Snatch block updated to final form
  (`find_player_snatch_target()`/`debug_force_snatch()`) plus new
  `debug_adjust_player_relationship(delta)` (writes `relationships["player"]`
  directly, bypassing Sociability, for exact ±25 F7 testing).
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player()` unchanged
  (verified present and matching).
- `scripts/npc/NPCDebug.gd` — new `log_snatch()` staged logging.
- `scripts/ui/menus/AdminMenu.gd` — two new F7 rows: "Relationship -25 /
  +25 (All NPCs ↔ Player)" with `_on_npc_relationship_down/up_pressed()`
  + `_adjust_all_npc_relationship()`.
- `docs/systems/npc/README.md` — Give paragraph rewritten for real
  transfer; Relationship Snatch section rewritten for `SnatchActivity` +
  `take_handoff()` + `log_snatch()`; Testing Checklist items 22-24.

## Dependencies / notes
- **Player-side inventory-clear fix required end-to-end**
  (`PLAYER_SUBSYSTEM_INVENTORY_CLEAR_FIX.md`, separate Player subsystem
  file): without it, Give/Snatch leave the transferred item stale in the
  player's inventory list. Not applied here — NPC side only.
- The `is_held` guard on `grab_loose()` referenced by the plan's
  commentary was never applied on disk (prerequisite theft-fix plan was
  never given) — the design intent is preserved via the strict
  `grab_loose()` vs `snatch_from_player()` separation regardless.

---
---

# Handover — Player Contract for NPC Relationship Snatch (Aug 2026)

## What changed this session
Added the two-method public contract the NPC subsystem needs for its
Relationship Snatch feature (bad-relationship NPCs occasionally take a
food/water item straight from the player's hands): `Player.get_held_item()`
and `Player.on_item_snatched()`. `Player.gd` gained an `interaction_system`
node ref (`$InteractionSystem`); `InteractionSystem.gd` gained
`clear_held_item_external()`, an unconditional version of the cleanup
`_try_give_to_nearest_npc()` already does on a successful give (item is
guaranteed already gone from this side by the time Snatch calls it,
unlike Give where multi-charge items can survive in hand). No existing
Give/Takeaway behavior changed.

### Files modified
- `scripts/player/Player.gd` — `interaction_system` ref,
  `get_held_item()`, `on_item_snatched()`.
- `scripts/player/InteractionSystem.gd` — `clear_held_item_external()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_SNATCH_CONTRACT_PLAN.md` for the full
4-item checklist)

---
---

# Handover — NPC Relationship Snatch Mechanic + Debug Trigger (Aug 2026)

**Owner:** NPC instance. Adds a hostility-gated "snatch" where a
badly-relationship'd NPC forcibly takes a currently player-HELD food/
water item instead of finding a normal one.

## What changed this session
- `scripts/npc/NPC.gd` — `SNATCH_RELATIONSHIP_THRESHOLD` (-50),
  `SNATCH_CHANCE_AT_THRESHOLD` (5%), `SNATCH_CHANCE_AT_MIN` (50%),
  `_debug_force_snatch`; `get_snatch_chance()` (linear -50→-100 scaling),
  `find_player_snatch_target(need_filter)` (gate + chance + held-item
  check, consumes the one-shot debug flag), `debug_force_snatch()`
  (bypasses gate/roll, still requires matching held item; force-commands
  Eat/DrinkActivity).
- `scripts/npc/NPCItemUser.gd` — `snatch_from_player(npc, player)`.
  Deliberately NOT routed through `grab_loose()` to keep that function's
  strict no-theft `is_held` guard intact; this is the one intentional
  gated exception.
- `scripts/npc/NPCBrain.gd` — EatActivity: new `_snatch_player` var,
  snatch check first in `enter()`, a `_tick`-time snatch branch
  (abandons if player's held item no longer matches), `done()` includes
  `_snatch_player == null`, `_reacquire_or_finish()` re-attempts the
  snatch before normal search. DrinkActivity: `enter()` picks a snatch
  target (`_mode = "snatch"`), `tick()` routes to new `_tick_snatch()`
  which hands off to normal `_tick_bottle()` mode on success.
- `scripts/ui/menus/AdminMenu.gd` — "Force Nearest NPC to Snatch Player
  Item" row + `_on_npc_force_snatch_pressed()` (nearest-to-player).
- `docs/systems/npc/README.md` — new "Relationship Snatch" subsection;
  Testing Checklist items 20-21.

## Dependencies / notes
- **Prerequisite** `NPC_GIVE_REAL_TRANSFER_AND_THEFT_FIX_PLAN.md` was
  NOT applied on disk before this (its `grab_loose()` `is_held` guard does
  NOT yet exist) — implemented as designed per user instruction anyway.
- **Player-side contract required end-to-end** (`PLAYER_SUBSYSTEM_SNATCH_CONTRACT.md`,
  separate Player subsystem file): `player.get_held_item()` and
  `player.on_item_snatched()`. All NPC-side callers guard these with
  `has_method()`, so this compiles and runs without them, but the snatch
  will not actually fire until those two Player methods exist.
- **AdminMenu.gd ownership flagged** in the plan (uncertain it belongs to
  the NPC instance) — applied since existing NPC debug rows live there.

---
---

# Handover — Give/Takeaway Bugfixes: Stuck Item + Undetectable NPC-Held Items (Aug 2026)

## What changed this session
Fixed two bugs reported after the initial Give/Takeaway implementation.

**Give stuck bug:** `_try_give_to_nearest_npc()` cleared the player's
`held_item`/bookkeeping unconditionally after a successful give, but
`receive_item_from_player()` only destroys single-serving items
(Dish/Produce) — FoodCan/WaterBottle survive with reduced charge, still
fully held. Clearing bookkeeping regardless left surviving cans/bottles
visually stuck (undroppable/unstorable/unusable, since every other
action gates on `held_item`). Fixed to only clear bookkeeping when
`is_instance_valid(item)` is false (i.e. it was actually destroyed).

**Takeaway silently broken:** root cause was a physics layer issue, not
GDScript logic. `PickupableItem.pickup()` sets `collision_layer = 2`
while held; `Player.tscn`'s `DetectArea` had no explicit
`collision_mask` and defaulted to layer 1 only, so it could never detect
NPC-held (layer 2) items regardless of the earlier `is_held` check
removals. Widened `DetectArea.collision_mask` to `3` (layer 1 | 2).
Added `body == held_item` self-detection guards to
`_try_add_nearest_to_basket()`/`_try_add_nearest_to_cookpot()` since the
wider mask means the player's own held item is now visible to those
scans too.

### Files modified
- `scripts/player/InteractionSystem.gd` — `_try_give_to_nearest_npc()`
  conditional bookkeeping clear; self-detection guards in
  `_try_add_nearest_to_basket()`/`_try_add_nearest_to_cookpot()`.
- `scenes/player/Player.tscn` — `DetectArea.collision_mask = 3`.
- `docs/systems/player/README.md` — bugfix follow-up appended to the
  existing NPC Give/Takeaway entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_BUGFIX_PLAN.md` for the
full 6-item checklist)

---

# Handover — Relationship Magnitude Rebalance (Aug 2026)

## What changed this session
- **NPC.gd**: `GIVE_RELATIONSHIP_BONUS` and `TAKEAWAY_RELATIONSHIP_PENALTY`
  halved (15.0 → 7.5, kept symmetric). `RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR`
  reduced 2.0 → 0.15 (~13x) — the original rate maxed a relationship out
  from ordinary cohabitation alone within ~2 in-game days; the new rate
  targets "Friendly" after ~100 days of realistic daily overlap, not
  "Close" within the first week.
- No mechanism changes — burnout, per-item/per-NPC repeat gating, band
  thresholds, and Sociability scaling are untouched, just the base
  numbers they operate on.

## Files Modified
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist
See `docs/systems/npc/README.md` Testing Checklist item 19 (renumbered
from the plan's "17" since the checklist already had items through 18).

---

# Handover — NPC Give/Takeaway Support in InteractionSystem.gd (Aug 2026)

## What changed this session
Player subsystem implemented the InteractionSystem.gd half of the NPC
Give/Takeaway feature, per a consolidated handoff from the NPC
subsystem. Give: holding a giveable item (dish/produce/can/bottle) near
an NPC shows `[E] Give <item> to <name>`; E calls
`NPC.receive_item_from_player()`. Takeaway: removed the CASE 2 `is_held`
prompt exclusion entirely (NPC-held items are now normal `[F] Pick up`
targets); `_try_pickup()` now looks up `NPCItemUser.find_holder()` before
reassigning `held_item` and calls `on_item_taken_by_player()` on the
losing NPC. All relationship/consequence/item-lifetime logic lives
NPC-side; this file only calls the contract methods and trusts their
return values.

### Files modified
- `scripts/player/InteractionSystem.gd` — Give prompt (CASE 1), Give
  dispatch (E-branch), `_find_nearest_npc()`/`_try_give_to_nearest_npc()`
  helpers, Takeaway `is_held` exclusion removed (CASE 2), Takeaway
  notify-on-grab in `_try_pickup()`.
- `docs/systems/player/README.md` — new Common-edits entry.
- `HANDOVER.md` — this entry.

### Verification checklist
(see Player subsystem plan `PLAYER_GIVE_TAKEAWAY_IMPLEMENTATION_PLAN.md`
for the full 6-item checklist)

---

# Handover — NPC Give: Multi-Charge Items (Aug 2026)

## What changed this session

- **NPCItemUser.gd**: `is_giveable()` widened to reuse `is_edible()`/
  `is_drinkable_bottle()` directly — now covers FoodCan and WaterBottle
  in addition to DishItem/FarmProduceItem.
- **NPC.gd**: `receive_item_from_player()` rewritten — per-(item, NPC)
  recipient tracking (`npc_gift_recipients` meta, an Array of npc_ids)
  replaces the earlier single global `npc_gift_used` flag. FoodCan/
  WaterBottle now take one bite/drink per gift and persist in the
  player's hand across multiple gifts (mirrors
  `NPCItemUser.eat_held_step()`'s exact per-type branching). A repeat
  gift of the same item to the same NPC still feeds them, just grants no
  further relationship reward; the same item can still boost different
  NPCs once each.
- Docs: `docs/systems/npc/README.md` — Give paragraph rewritten, Future
  Work item marked done, new Testing Checklist item.

## Files Modified
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist item 18.

---

# Handover — NPC Universal Takeaway + Gift Burnout/Anti-Repeat (Aug 2026)

## What changed this session

### Takeaway, unrestricted
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**;
  flagged for a later plan): would have removed the need-triggered `is_held`
  gate from the CASE 2 prompt loop and `_nearest_pickup_distance()` entirely,
  and dropped the gating condition in `_try_pickup()` (keeping its
  `NPCItemUser.find_holder()`/`on_item_taken_by_player()` notify call).
  Because this section was deferred, NPC-held items are still pickable only
  when need-triggered (Part 24 behavior) — the unrestricted-pickup portion
  of this pass is NOT live.
- **NPC.gd**: `on_item_taken_by_player()` now always clears `held_item`, but
  only applies the -15 relationship ding when `is_consuming_from_need()` was
  true at the moment of taking (evaluated before clearing). Verified
  `JobActivity`'s held_item references are all null-safe — a stolen job
  material can't crash, but the job silently completes without its effect
  (accepted quirk, see docs).

### Gift burnout + per-item marking
- **NPC.gd**: `gift_saturation` (0..1, +0.25/gift, decays to 0 over ~5
  game-days via `_tick_relationships()`), `GIFT_BONUS_FLOOR_MULT` (0.15x
  floor), applied as a multiplier on `GIVE_RELATIONSHIP_BONUS` in
  `receive_item_from_player()`. Each item can only produce one boost ever
  (`npc_gift_used` meta flag) — currently unreachable given Give's
  destroy-on-give V1 scope, forward-looking for multi-charge items later.
- F7 relationship visualizer now shows "Gift burnout: NN%" per NPC when
  above 0.

### Docs
`docs/systems/npc/README.md` — Give/Takeaway section updated for the
burnout/marking behavior and the narrowed relationship ding; Future Work
updated (multi-charge note + stolen-job-material quirk); two new Testing
Checklist items. Note the Takeaway paragraph describes the full
unrestricted-pickup behavior from deferred Section 2, which is not yet
live.

## Files Modified
- `scripts/npc/NPC.gd`
- `docs/systems/npc/README.md`
- ~~`scripts/player/InteractionSystem.gd`~~ ⚠️ Player subsystem — deferred
  (Section 2), expected in a later pass.

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 16–17 (gift
burnout). Item 16 (non-need takeaway) depends on the still-deferred
`InteractionSystem.gd` Section 2.

---

# Handover — NPC Give/Takeaway + F7 Relationship Visualizer (Aug 2026)

## What changed this session

### Give
- **NPC.gd**: `receive_item_from_player()` (V1 scope: DishItem/
  FarmProduceItem only), `GIVE_RELATIONSHIP_BONUS` (+15).
- **NPCItemUser.gd**: `is_giveable()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**;
  flagged for the later plan): new "[E] Give `<item>` to `<name>`" prompt
  block (mirrors Basket/Cooking Pot pattern) + dispatch, `_find_nearest_npc()`,
  `_try_give_to_nearest_npc()`. Deferred with the rest of section 5.

### Takeaway
- **NPC.gd**: `is_consuming_from_need()` (gated on the same 55.0 threshold
  Eat/DrinkActivity auto-trigger on), `on_item_taken_by_player()`,
  `TAKEAWAY_RELATIONSHIP_PENALTY` (-15).
- **NPCItemUser.gd**: `find_holder()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**):
  `_try_pickup()` and `_nearest_pickup_distance()` `is_held` carve-outs; the
  CASE 2 prompt-loop carve-out. Deferred with the rest of section 5.
  (Note: the latent gap this closes in `_try_pickup()` is likewise still open
  until that section lands.)

### F7 Relationship Visualizer
- **NPC.gd**: `_update_relationship_debug_label()`, piggybacking
  `NPCDebug.enabled` (no new F7 row) — floating per-NPC relationship
  readout above the Part-5 name/activity label.
- **NPCDebug.gd**: `log_relationship_event()` for discrete Give/Takeaway
  events (separate from the existing continuous `log_relationship_tick`).

### Docs
`docs/systems/npc/README.md` — new Give/Takeaway section, Relationships'
Future Work item marked done/superseded, three new Testing Checklist
items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPCDebug.gd`
- `docs/systems/npc/README.md`
- ~~`scripts/player/InteractionSystem.gd`~~ ⚠️ Player subsystem — deferred
  (section 5), expected in a later pass.

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 13–15. Note items
13–14 (Give/Takeaway player prompts) depend on the still-deferred
`InteractionSystem.gd` section 5; the F7 visualizer (item 15) is fully
live now.

---

# Handover — Ghost Collision Regression Fix (Aug 2026)

## What changed this session

### Root cause — Ghost collision regression
The July "strip collision AFTER add_child" fix ran at the wrong tree level:
`GhostModelBuilder.strip_collision()` was called inside `_rebuild_ghost_mesh()`
**before** the ghost root entered the SceneTree. Since `add_child(real_inst)`
on an out-of-tree parent does **not** fire `_ready()`, the strip ran **before**
scripts' own `_ready()` ran — scripts that unconditionally set
`collision_layer = 5` in their `_ready()` silently re-enabled collision
on every ghost spawn. This is why Fix 2's strip "didn't take" — it ran at
the wrong lifecycle point.

**Consequences:** (1) Ghosts of every `PROCEDURAL_PREVIEW_SOURCES` tile
push the player/NPCs (live collision). (2) Grow lights always red/"space
occupied" — the ghost's own live collider sits exactly at the
`_is_position_occupied()` query position, so the ghost blocks itself.
Grow lights had no registry carve-out in `_is_position_occupied_for_tile()`
(unlike Purifier/Light/Shelving), so the physics query always ran for
them and always found the ghost's own collider at the query position.

### Fixes

**Fix 1 — Core: Reorder `_spawn_ghost()`** — `_spawn_ghost()` now:
1. Creates ghost root
2. Sets `visible = false` (prevents 1-frame flash)
2. **Adds ghost root to SceneTree** (`parent.add_child(_ghost)`)
3. **Then** calls `_rebuild_ghost_mesh()` → `build_real_instance()` →
   `strip_collision()` now runs AFTER `add_child(real_inst)` fires
   `_ready()`, so the strip sticks.

**Fix 2 — Hardening: Deferred re-strip + freed-node guard**
- `_rebuild_ghost_mesh()`: added `GhostModelBuilder.strip_collision.call_deferred(real_inst)`
  to catch any script that configures collision via `call_deferred` in
  its `_ready()`.
- `GhostModelBuilder.strip_collision()`: added `is_instance_valid(node)`
  guard so the deferred call is safe if the ghost was freed the same
  frame (tile switch / build-mode exit).

**Fix 3 — Grow Light bucket registry** — preview-only grow lights no
longer register into `GrowLight._bucket_registry`. Moved the
`_is_preview_only` guard **before** the `call_deferred("_register_bucket")`
call in `GrowLight._ready()` (same fix pattern as the chair ghost
invisibility bug).

### Files modified
- `scripts/world/build/GhostPreview.gd` — `_spawn_ghost()` reorder, deferred re-strip
- `scripts/world/build/GhostModelBuilder.gd` — `strip_collision()` freed-node guard
- `scripts/world/power/GrowLight.gd` — preview guard before bucket register
- `docs/systems/build/README.md` — `strip_collision()` bullet updated with
  precise lifecycle rule; Call graph updated with `_spawn_ghost()` order
- `docs/systems/farming/README.md` — note that preview-only grow lights
  no longer register into spatial bucket
- `HANDOVER.md` — this entry

### Verification checklist
1. Ghost collision gone — walk through any furniture ghost, no push.
2. Grow lights placeable — green over open floor, places correctly.
3. Occupancy still works — ghost red over existing object, green over open floor.
4. No flash/regression — rapid tile switching (Chair → Wall → Stove → Grow Light) shows no flash at origin.
5. Bucket fix — with a plant in a tray and NO real grow light, hover a grow-light ghost over tray — plant must NOT register as lit.

**Follow-up (Aug 2026):** a mis-ordered preview guard in `GrowLight._ready()` skipped `_build_fixture()` for preview instances, blanking the ghost and menu preview — fixed by moving the guard to sit after fixture construction, before side effects (groups, registration, power).

---

# Handover — NPC Names + Ask-About Relationship Dialogue (Aug 2026)

## What changed this session

### Names
- **NPC.gd**: `NPC_NAMES` (10-name pool), `_assign_random_name()`
  (collision-avoided against every live NPC), called from `_ready()` when
  `npc_name` is still its "Survivor" default. No persistence changes
  needed — `npc_name` was already saved.

### Ask About (relationship Q&A dialogue)
- **NPC.gd**: `get_relationship_dialogue_line(target_id)` (5 flavor-text
  pools keyed to `get_relationship_label()`), `get_other_npc_topics()`
  (every other live NPC, for building UI buttons).
- **NPCTalkMenuUI.gd**: new "ASK ABOUT" section revealed alongside
  dialogue/commands on Talk — "What do you think of me?" (player) + one
  button per other live NPC by name; answers render in the existing
  dialogue label. `PANEL_H` bumped 760 → 900.
- Docs: `docs/systems/npc/README.md` — new Names & Ask-About section,
  Relationships' dialogue Future Work item marked done (narrower scope),
  Responsibilities bullets updated, new Testing Checklist items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `docs/systems/npc/README.md`

---

# Handover — NPC Relationships Groundwork + Sociability Wiring (Aug 2026)

## What changed this session

### Relationships — data model + proximity baseline
- **NPC.gd**: new stable `npc_id` identity (auto-assigned, persisted,
  collision-safe across save/load via `NPC._register_id()`); new
  `relationships` Dictionary (directional, NPC's own perspective, keyed by
  target `npc_id` or `"player"`, -100..100); `get_relationship()`,
  `get_relationship_label()` (Hostile/Cold/Neutral/Friendly/Close),
  `_adjust_relationship()` (single mutation point — applies sociability
  multiplier + clamp); baseline driver this pass is passive proximity
  (`_tick_relationships()`, 4m XZ range, 5s cadence alongside mood/
  irritability).
- **Sociability trait wired** (previously generated/displayed only):
  `_sociability_trait_mult()`, 0.5x–1.5x, scales every relationship delta.
- **NPCDebug.gd**: `log_relationship_tick()`; `_dump_one()` now includes
  each NPC's relationships with labels.
- **MainWorld.gd**: `_get_npcs_for_save()`/`_restore_npcs()` persist
  `npc_id` and `relationships`.
- Docs: `docs/systems/npc/README.md` — new Relationships section, updated
  Personality/Non-responsibilities sections, new Testing Checklist items.

### Explicitly not done this pass (see README's Relationships → Future Work)
Item giving/taking, crisis-help behavior, command-compliance influence,
personal-space avoidance scaling, gift-dropping, relationship-aware
dialogue, Player→NPC reciprocal value.

---

# Handover — Build Mode Ownership Expansion, Furniture, Wall Draw Mode, Ghost Model System (Aug 2026)

## What changed this session

### Role expansion
This Claude instance's scope expanded from Furniture-only to ALL Build
Mode / Construct Menu object placement (spawning, ghost preview,
wall/floor snapping, height/spacing, general placement refinement) across
every object type.

### Furniture: Small/Medium Table, Chair, Poster
- New `scripts/world/furniture/Table.gd`, `Chair.gd`, `Poster.gd` — see
  `docs/systems/build/README.md`'s Furniture section for details.
- Chair sit/stand mechanic: `Player.gd` gained `seated_chair` state;
  `InteractionSystem.gd`'s `_try_interact()`/`_update_prompt()` both check
  it first, before any proximity scan, so E always means "stand" while
  seated regardless of what else is nearby; any WASD press while seated
  also stands the player up and lets movement continue immediately
  ("walk out of the chair").

### Wall Draw Mode — click-drag-click stretched walls
Full/Half/Quarter Wall placement rewritten from single-click discrete 1m
segments to one dynamically-stretched mesh per wall, free 360° angle,
grid-snapped endpoints, Q/E height-tier cycling, RMB/ESC exit. See
`docs/systems/build/README.md`'s Wall Draw Mode section. Went through
several fix rounds this session: floating half/quarter tiers (tier-aware
placement Y), bounds-check false positives on long walls (half-extent was
incorrectly scaled by run length), ghost sunk to half-height (a
`global_position` assignment was clobbering the mesh's own floor-flush
offset), minimum length matching the idle sliver instead of a full 1m cell.

### Ghost Model Master System — real-shaped previews, universal facing arrow
New `scripts/world/build/GhostModelBuilder.gd` — see
`docs/systems/build/README.md`'s Ghost Model System section for the full
writeup. Replaced generic box/rectangle ghost previews with translucent
real-model ghosts for every object already registered for a Construct-menu
preview, and gave every placeable object a facing arrow (previously only a
few hand-picked tiles had one).

Two rounds of follow-up fixes after the initial rollout:
- **Chair ghost was invisible** — `Chair.gd`'s `_ready()` returned before
  `_build_mesh()` when `_is_preview_only` was set (pre-existing bug, not
  introduced by the ghost system — the Construct-menu spinning preview was
  almost certainly blank too, before this).
- **Ghosts had live collision, pushed the player** — root cause was a
  lifecycle-order bug: collision was stripped *before* `add_child()`, i.e.
  before `_ready()` had run, so scripts that set `collision_layer`
  unconditionally in `_ready()` (most of them) silently undid the strip.
  Fixed by moving the strip to run after `add_child()`.
- **Grow Light placement was broken** (always red, "Space is already
  occupied," intermittently fixable by rapid mouse movement/clicking) —
  traced to the same collision bug: `_is_position_occupied()`'s physics
  query (`collision_mask = 1`) was detecting the ghost's own still-live
  collision shape at its own query position. Same fix resolved both.
- **Facing arrow was backward on most objects** — rather than continuing
  to add a hand-tuned override per newly-reported tile (Chair, Dispenser,
  Test Sink, then Battery ×3, Stove, Tables, Trays), recognized the
  pattern (every default-using tile was backward; only hand-tuned ones
  were correct) and flipped the *default* itself (180°), removing the
  now-redundant individual overrides.
- **Wall Lights failed to place in player-expanded bunker areas** despite
  a green ghost — `TILE_LIGHT` had no entry in `_tile_half_extents()`,
  inheriting the generic 0.40 floor-object fallback for the confirm-time
  bunker-bounds check, oversized for a thin wall-flush fixture. Same fix
  already applied to `TILE_POSTER` earlier in the session, now applied to
  Light too.

---

# Handover — NPC Basics + Cooking Fixes + UI Unification + NPC Basics (Aug 2026)

## What changed this session

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: New `CharacterBody3D` NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

### UI Unification — Pause Menu + Graphics Settings Panel (Jul 2026)

- **UIKit.gd**: Added shared menu builders (`build_modal_backdrop()`, `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`), font-size constants (`FONT_SIZE_TITLE=20`, `FONT_SIZE_SECTION=11`, `FONT_SIZE_BODY=13`), `MENU_PANEL_W=380`
- **PauseMenuUI.gd**: Complete rewrite using UIKit builders; fixed UTF-8 encoding (removed BOM/garbled comments); unified colors with NEUTRAL theme; confirm dialog now matches main panel gray
- **GraphicsSettingsPanel.gd**: Complete rewrite using UIKit builders; **FIXED off-center bug** (`build_centered_panel()` with fixed size); row labels now use `make_row_label()` with proper font/color; unified panel width (380), fonts, button styles with PauseMenuUI

### Fix: Removed invalid `custom_maximum_size` from `build_centered_panel()`

Control/Panel has no `custom_maximum_size` property in Godot 4 — that line always errored. The fixed anchor offsets + `custom_minimum_size` already fully lock the panel's size.

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: CharacterBody3D NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

---

## Files Modified

### NPC Basics
- `scripts/npc/NPC.gd` — new file
- `scripts/ui/npc/NPCTalkMenuUI.gd` — new file
- `scenes/npc/NPC.tscn` — new file
- `scripts/world/core/MainWorld.gd` — added `get_cleared_cell_bounds_world()`
- `scripts/ui/menus/AdminMenu.gd` — added "Spawn NPC" row + callback

### Cooking Fixes (Part 1/2)
- `scripts/world/items/CookingPot.gd` — added `get_use_prompt()`
- `scripts/world/cooking/Stove.gd` — added `_grid_connected` tracking, grid-aware `set_powered()`/`on_interact()`/`get_interact_prompt()`

### UI Unification
- `scripts/ui/common/UIKit.gd` — added `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`, font-size constants, `MENU_PANEL_W=380`
- `scripts/ui/menus/PauseMenuUI.gd` — complete rewrite using UIKit builders
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite using UIKit builders; fixed off-center bug
- `scripts/ui/common/UIKit.gd` — removed invalid `custom_maximum_size` from `build_centered_panel()`

### Admin Menu Additions (Part A)
- `scripts/ui/menus/AdminMenu.gd` — added `world_node`, `ADMIN_CASH_STEP`, `PRODUCE_SPAWN_HEIGHT`, new `_row_defs` rows, `_format_thousands()`, `_on_add_cash_pressed()`, `_on_hookup_output_double_pressed()`, `_spawn_produce()` + 3 callbacks

### Admin Spawn Menu Removal (Part B)
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid` — deleted
- `MainWorld.gd` — removed F10 handler, `_admin_menu` var, `_toggle_admin_spawn_menu()`
- `PauseMenuUI.gd` — layer comment fixed
- `PickupableItem.gd` — spawn helper comment updated
- `FarmingShopHelper.gd` — "Single source of truth" comment updated
- `AdminMenu.gd` — docstring F10 reference removed; layer comment fixed
- Docs updated across `PROJECT_SUMMARY.md`, `docs/systems/ui/README.md`, `docs/systems/build/README.md`, `docs/systems/water/README.md`, `docs/systems/farming/README.md`
- `architecture.json` regenerated

---

## Files Created
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `assets/shaders/grunge_overlay.gdshader`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`

---

## Files Deleted
- `scripts/ui/hud/StatusBars.gd` + `.uid`
- `scripts/ui/hud/CircleFill.gd` + `.uid`
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid`

---

## Next Up
- Real gameplay status effects still need to be wired into `StatusEffectsContainer.add_effect()` — currently F7 test-only.
- Cooking System Part 2: Cook timer + Dish item (Part G from `COOKING_SYSTEM_PLAN_PART3.md`)
- `BuildModeHUD.gd`'s buttons/tabs/interactions are now in UI Claude's scope per Brannon's Jul 2026 note — not yet started, rest of `BuildModeHUD.gd` stays with the non-UI Claude instance.
- Worn-look shader defaults (`grit_strength = 0.14`, `grit_scale = 26.0`) are a first pass — confirm they read right in actual play, not just the single reviewed screenshot.
- Admin Menu Part A: economy/water-tier/produce-spawn cheats (already done in this session)
- Admin Menu Part B: F10 Admin Spawn Menu removal + docs (already done in this session)
- NPC Basics (already done in this session)
- Cooking Fixes Part 1/2 (already done in this session)
- UI Unification (already done in this session)

---

## Verification Checklist (for Brannon's in-editor test)
1. **NPC**: F7 → Spawn NPC → NPC wanders, collides with walls/furniture, [E] Talk → popup → Talk → "..." → Close
2. **Cooking**: Pot near stove → [E] Place prompt appears; Stove requires grid connection; power loss auto-shuts-off; prompt shows "Stove Not Connected"
3. **UI**: Pause Menu (ESC) centered; Graphics Settings (F7→Settings) centered; row labels use project font; confirm dialog gray matches main panel
3. **Admin Menu (F7)**: 11 rows, 6 sections; +$100k Cash updates HUD; Hookup Output x2 increments tier (warns at max); Spawn Potato/Blueberry/Tomato drops items with pop-in
4. F10 does nothing (no menu, no errors)
5. F7 Admin Menu: 11 rows, 6 sections; all original buttons (Power, Time, Water, Economy, Farming, Status) + new rows work