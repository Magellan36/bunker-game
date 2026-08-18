# Plan — Preview Scale Normalization + CanCase/WaterCase Blank Preview Fix

## Root causes, both traced in `BuildModeHUD.gd` and `ItemPreviewKit.gd`

**"Crate too large":** `ItemPreviewKit.set_item()` never normalized scale
at all — every item rendered at its raw authored mesh size, with only
camera zoom (uniform across all items) controlling apparent size. A
physically large mesh like the Crate fills/overflows the frame while a
small item looks tiny, entirely dependent on how each mesh happened to
be authored. `BuildModeHUD.gd` solved exactly this already —
`_preview_normalize_scale()` (its own comment: "Seed packets (~0.14m)
and Generator L (~1.85m) both end up reading as the same on-screen size
in every preview pool") — so this plan ports that logic in rather than
reinventing it.

**CanCase/WaterCase blank:** both are `PickupableItem` with NO
`get_inventory_mesh()`, and their actual visuals are 12 separate can/
bottle meshes nested two-plus levels deep (`VisualRoot/Can_01..Can_12`,
`VisualRoot/Bottle_01..Bottle_12`). `ItemPreviewKit.set_item()`'s
fallback only scanned `item`'s DIRECT children for a single
`MeshInstance3D` — `VisualRoot` is a plain `Node3D`, so the scan found
nothing and left the preview blank. `BuildModeHUD.gd` already solved
this too — `_combined_local_aabb()` walks the FULL descendant tree at
any depth (its own header explains why: procedural devices routinely
nest meshes below their root).

## What changed
Ported both pieces of `BuildModeHUD.gd` logic into `ItemPreviewKit.gd`,
adapted for this kit's multi-consumer pixel sizes:

1. **`_combined_local_aabb()`** — ported near-verbatim. Walks every
   `MeshInstance3D` descendant of a root node at any nesting depth,
   correctly expressed in the root's own local space via global-transform
   math. Fixes the blank-preview bug directly.
2. **`_preview_normalize_scale()`** — ported the LOGIC (uniform scale so
   an object's largest AABB dimension fills a fixed fraction of the
   frame) but NOT the literal constant. Build Mode's `PREVIEW_TARGET_SIZE`
   is a fixed 0.5667 **meters** value, which only works because Build
   serves exactly one fixed pixel size (52px) everywhere. This kit serves
   two different pixel sizes (Inventory's 64px, Storage's 96px) via
   `CAM_SIZE_PER_PIXEL`, so a fixed-meters target would overflow the
   smaller slot and look tiny in the larger one. Re-derived as
   `PREVIEW_FILL_FRACTION = 0.85` (same ~85% BuildModeHUD targets, just
   expressed as a fraction of each call's own `cam.size` instead of a
   flat constant) — this generalizes correctly across both consumers
   instead of copying a number that only happened to work for one
   pixel size.
3. **New `_duplicate_visual_tree()`** — not a direct Build Mode port,
   needed because Build's construct/shop previews instantiate a whole
   fresh scene from a resource path (menu items that don't exist in the
   world yet), while this kit previews an ALREADY-LIVE item reference
   (something currently held/stored). Walks `item`'s full descendant
   tree and duplicates just the mesh geometry (plus material overrides,
   so colored variants like seed species still render correctly) into a
   flat wrapper — never the live node tree itself, so no scripts,
   physics bodies, or collision shapes come along regardless of what the
   source item's own `_ready()`/`_process()` does.
4. **Bonus correctness, free with the above:** `_duplicate_visual_tree()`
   skips any `MeshInstance3D` currently `visible = false` — so a
   partially-emptied CanCase/WaterCase (cans/bottles already taken)
   previews as partially empty too, matching the in-world model instead
   of always showing a full case. Wasn't explicitly asked for, but it's
   a natural consequence of walking real node state and costs nothing
   extra — flagging so it's not a surprise.
5. **`set_item()` restructured** to a pivot+wrapper split (pivot rotates
   in place, wrapper only translates to center the AABB) — the same
   two-node pattern `BuildModeHUD.gd` uses, needed because a single
   `Transform3D` can't cleanly do "rotate around the true visual center"
   and "translate to compensate for an off-center AABB" at once. Both
   the `get_inventory_mesh()` path and the deep-walk fallback now funnel
   through this one shared centering/scaling code, unlike
   `BuildModeHUD.gd` itself, which repeats a version of this same logic
   three separate times (its MeshLibrary-item, construct-item, and
   shop-item paths) — small de-duplication bonus from unifying the two
   paths in this kit.
6. **`clear()` fixed to match** — it used to specifically look for
   `MeshInstance3D` children, which was fine when `set_item()` added a
   bare mesh directly to the viewport. Now that content is wrapped in a
   `Node3D` pivot, the old check would silently stop matching anything
   at all (a real bug I caught while making this change, not something
   already live) — updated to match any `Node3D` that isn't the camera
   or light, same pattern `BuildModeHUD.gd`'s own preview cleanup uses.

Applies uniformly to every `ItemPreviewKit` consumer — Inventory bar and
every `StorageUI` panel (Shelving, End Table, Dresser, Basket) — since
they all already funnel through this one file.

## Files modified
- `scripts/ui/common/ItemPreviewKit.gd`

## Verification checklist
1. Open the inventory bar and any storage panel — Test Crate no longer
   overflows its slot; small items (seeds, cans) no longer look
   tiny relative to it. Spot-check a few items across the size range.
2. Open a Basket/Shelf/End Table/Dresser containing a Can Case — its
   preview now shows the actual 12-can model instead of a blank slot.
3. Same for Water Case.
4. Eject a few cans from a Can Case (`E` in the world), then open its
   storage/inventory preview again — confirm the preview shows fewer
   visible cans, matching the depleted state.
5. Confirm no other item's preview regressed — spot-check a few more
   items across different types (FuelCan, WaterBottle, seeds, cooking
   pot) to confirm they still render, still centered, still at the
   resting `-45°, -45°` angle.
6. Confirm `clear()`'s fix didn't break anything — swap between two
   different items in the same slot quickly (e.g. re-roll a shelf slot)
   and confirm the old preview is actually gone, not left stacked
   underneath the new one.

## Documentation updates

### `docs/systems/ui/README.md` — update the `ItemPreviewKit.gd` note
Find the line count/description added when `ItemPreviewKit.gd` was first
introduced (in the `common/` files table row) and update it to reflect
the added scale-normalization/deep-walk logic — the file grew from ~90
to ~235 lines this pass. Also add a short new subsection (e.g. right
after "Shared Item Preview Kit") along these lines:

```markdown
### Preview Scale Normalization + Deep Mesh Walk (Aug 2026)
`ItemPreviewKit.gd` ported two pieces of `BuildModeHUD.gd`'s preview
logic it was missing: `_combined_local_aabb()` (walks every
MeshInstance3D descendant at any nesting depth, not just direct
children — fixes CanCase/WaterCase, whose 12 can/bottle meshes sit under
`VisualRoot/Can_XX`/`Bottle_XX`, previously rendering blank) and
`_preview_normalize_scale()` (uniform scale so every item's largest AABB
dimension fills the same fraction of its preview frame — fixes large
items like the Crate overflowing while small items looked tiny).
The scale target is expressed as `PREVIEW_FILL_FRACTION` (a fraction of
each call's own `cam.size`) rather than Build Mode's fixed-meters
constant, since this kit serves multiple preview pixel sizes (Inventory
64px, Storage 96px) and a flat meters value doesn't generalize across
them the way BuildModeHUD's single-pixel-size version could get away
with. New `_duplicate_visual_tree()` duplicates only mesh geometry (with
material overrides preserved) from an already-live item reference,
skipping currently-hidden meshes — so a partially-emptied CanCase/
WaterCase previews as partially empty too.
```

### `HANDOVER.md` — new top section
```markdown
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
```

---

## Full diff

```diff
diff --git a/scripts/ui/common/ItemPreviewKit.gd b/scripts/ui/common/ItemPreviewKit.gd
index b60819d..c2dddfe 100644
--- a/scripts/ui/common/ItemPreviewKit.gd
+++ b/scripts/ui/common/ItemPreviewKit.gd
@@ -25,11 +25,13 @@ class_name ItemPreviewKit
 ## an item at the SAME real-world scale, not a different zoom level. Mesh
 ## rotation is fixed (no spin) at ROTATION_DEFAULT, matching
 ## BuildModeHUD.PREVIEW_ROTATION_DEFAULT's resting pose exactly. Mesh
-## source: item.get_inventory_mesh() first, else the item's first
-## MeshInstance3D child, duplicated. Centering: local AABB center
-## transformed through the mesh's rotation basis, so the rotated mesh
-## sits visually centered in the viewport (not just origin-centered
-## pre-rotation).
+## source: item.get_inventory_mesh() first, else every MeshInstance3D
+## descendant of item at any nesting depth, duplicated (see
+## _duplicate_visual_tree()). Centering + scale: combined AABB of every
+## duplicated mesh, normalized so the largest dimension fills a fixed
+## fraction of the camera frame regardless of the item's real size (see
+## PREVIEW_FILL_FRACTION) — both ported from BuildModeHUD.gd's construct/
+## shop preview code, which solved this exact problem first.
 
 ## Reference values proven correct by InventoryHUD.gd (SLOT_SIZE=64,
 ## cam.size=0.4) — every consumer derives its own cam.size from this ratio
@@ -45,6 +47,102 @@ const LIGHT_POSITION: Vector3 = Vector3(1.0, 1.5, 1.0)
 const LIGHT_ENERGY: float     = 2.5
 const LIGHT_RANGE: float      = 8.0
 
+## Aug 2026 — fraction of the camera's orthographic frame a preview's
+## largest AABB dimension should fill, regardless of the item's real
+## size (a Crate and a Seed Packet read as the same on-screen size).
+## Ported from BuildModeHUD.PREVIEW_TARGET_SIZE / _preview_normalize_scale()
+## (its own comment: "~0.85 leaves a small margin so a rotating/spinning
+## object doesn't clip the viewport edge"). Expressed as a FRACTION of
+## cam.size here rather than Build's fixed meters constant — Build only
+## ever serves one fixed pixel size (52px) so a fixed-meters value and a
+## fixed fraction were equivalent there; this kit serves multiple pixel
+## sizes (Inventory's 64px vs Storage's 96px) via CAM_SIZE_PER_PIXEL, so
+## the target has to scale with each call's own cam.size or it would
+## overflow the smaller slot size and look tiny in the larger one.
+const PREVIEW_FILL_FRACTION: float = 0.85
+
+## Computes the combined AABB of every MeshInstance3D descendant of
+## `root`, correctly expressed in root's OWN local coordinate space —
+## i.e. accounting for each mesh's position/rotation/nesting-depth
+## relative to root, not just merging each mesh's raw local-space AABB as
+## if every child sat exactly at root's own origin. Ported verbatim from
+## BuildModeHUD._combined_local_aabb() (see that function's header for
+## the full "rotates around its feet instead of spinning in place"
+## backstory). Requires `root` to already be inside the SceneTree
+## (global_transform must be valid) — call this AFTER add_child(), never
+## before.
+static func _combined_local_aabb(root: Node3D) -> Dictionary:
+	var combined: AABB = AABB()
+	var found_any: bool = false
+	var root_inverse: Transform3D = root.global_transform.affine_inverse()
+	var stack: Array = [root]
+	while not stack.is_empty():
+		var n: Node = stack.pop_back()
+		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
+			var mi: MeshInstance3D = n as MeshInstance3D
+			var relative_transform: Transform3D = root_inverse * mi.global_transform
+			var mesh_aabb: AABB = relative_transform * mi.mesh.get_aabb()
+			if not found_any:
+				combined = mesh_aabb
+				found_any = true
+			else:
+				combined = combined.merge(mesh_aabb)
+		for c in n.get_children():
+			stack.append(c)
+	return { "aabb": combined, "found_any": found_any }
+
+## Returns the uniform scale factor that makes `aabb`'s single largest
+## dimension fill PREVIEW_FILL_FRACTION of `cam_size` (the calling
+## preview's own orthographic camera size — see PREVIEW_FILL_FRACTION's
+## header for why this is a fraction of cam_size and not a fixed meters
+## constant like BuildModeHUD's version). Apply this to a preview's PIVOT
+## node (never the mesh/wrapper child) — composes cleanly with the
+## pivot's rotation and the wrapper's own `-aabb.get_center()` centering
+## offset with zero extra math needed (a uniform scale on an
+## already-centered child stays centered regardless of the scale factor).
+static func _preview_normalize_scale(aabb: AABB, cam_size: float) -> float:
+	var largest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
+	if largest < 0.0001:
+		return 1.0
+	return (PREVIEW_FILL_FRACTION * cam_size) / largest
+
+## Duplicates every MeshInstance3D descendant of `item` (any nesting
+## depth) into a single flat wrapper Node3D, each copy keeping its
+## correct transform relative to item's own origin (same global-transform
+## math as _combined_local_aabb()), plus its material overrides so
+## per-item color variants (e.g. seed species colors) still render
+## correctly. Deliberately copies only mesh geometry, never the live node
+## tree itself — no scripts, physics bodies, or collision shapes come
+## along, so this is always safe to drop into an isolated preview
+## SubViewport regardless of what `item`'s own _ready()/_process() does
+## in the real world. Skips any MeshInstance3D that's currently
+## `visible = false` (e.g. CanCase/WaterCase hide individual can/bottle
+## meshes as they're depleted — the preview should match, not always show
+## a full case). Returns an empty (childless) wrapper if `item` has no
+## visible MeshInstance3D descendants at all.
+static func _duplicate_visual_tree(item: Node3D) -> Node3D:
+	var wrapper := Node3D.new()
+	var root_inverse: Transform3D = item.global_transform.affine_inverse()
+	var stack: Array = [item]
+	while not stack.is_empty():
+		var n: Node = stack.pop_back()
+		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
+			var src: MeshInstance3D = n as MeshInstance3D
+			var copy := MeshInstance3D.new()
+			copy.mesh = src.mesh
+			copy.material_override = src.material_override
+			## Count comes from the mesh resource, not MeshInstance3D
+			## itself — matches the get_surface_count() pattern already
+			## used elsewhere in this codebase (BuildMaterials.gd,
+			## MoveDuplicateTool.gd, BunkerPregen.gd).
+			for surf_i in src.mesh.get_surface_count():
+				copy.set_surface_override_material(surf_i, src.get_surface_override_material(surf_i))
+			copy.transform = root_inverse * src.global_transform
+			wrapper.add_child(copy)
+		for c in n.get_children():
+			stack.append(c)
+	return wrapper
+
 ## Builds one preview slot (SubViewport + orthographic Camera3D +
 ## OmniLight3D) sized for `pixel_size` px square, added as a child of
 ## `parent`. Returns the SubViewport — callers keep their own array of
@@ -73,46 +171,68 @@ static func build_viewport(parent: Node, pixel_size: int) -> SubViewport:
 
 	return vp
 
-## Populates `vp` with a static preview of `item`'s mesh at
-## ROTATION_DEFAULT, clearing any previous preview mesh first. No-op
-## (mesh cleared, nothing added) if `item` is null or has no usable mesh
-## source.
+## Populates `vp` with a static preview of `item`'s full visual geometry
+## at ROTATION_DEFAULT, normalized to PREVIEW_FILL_FRACTION, clearing any
+## previous preview first. No-op (cleared, nothing added) if `item` is
+## null or has no usable mesh source.
 static func set_item(vp: SubViewport, item: Node) -> void:
 	clear(vp)
 	if item == null:
 		return
 
-	var mesh_inst: MeshInstance3D = null
+	## get_inventory_mesh() tried first — cheaper for the common
+	## single-mesh case, and some items intentionally return a stand-in
+	## mesh that differs from their literal world geometry. Falls back to
+	## walking item's full descendant tree (any nesting depth) via
+	## _duplicate_visual_tree() — see that function's header for why a
+	## single-level direct-child scan (the old behavior here) left
+	## CanCase/WaterCase blank.
+	var wrapper: Node3D = null
 	if item.has_method("get_inventory_mesh"):
 		var m: Mesh = item.get_inventory_mesh()
 		if m != null:
-			mesh_inst = MeshInstance3D.new()
-			mesh_inst.mesh = m
-	if mesh_inst == null:
-		for child in item.get_children():
-			if child is MeshInstance3D:
-				mesh_inst = child.duplicate() as MeshInstance3D
-				break
-	if mesh_inst == null:
+			wrapper = Node3D.new()
+			var mi := MeshInstance3D.new()
+			mi.mesh = m
+			wrapper.add_child(mi)
+	if wrapper == null and item is Node3D:
+		wrapper = _duplicate_visual_tree(item as Node3D)
+	if wrapper == null or wrapper.get_child_count() == 0:
 		return
 
-	mesh_inst.rotation_degrees = ROTATION_DEFAULT
-	mesh_inst.position = Vector3.ZERO
+	## Pivot rotates in place; wrapper (its child) only translates to
+	## center the combined AABB. Two separate nodes because a single
+	## Transform3D can't cleanly do both "rotate around the true visual
+	## center" and "translate to compensate for an off-center AABB" at
+	## once — same split BuildModeHUD's preview code uses, same reason.
+	var pivot := Node3D.new()
+	pivot.rotation_degrees = ROTATION_DEFAULT
+	vp.add_child(pivot)   ## Must be in tree before reading global_transform below
+	pivot.add_child(wrapper)
 
-	## Add to viewport FIRST — node must be in the scene tree before we can
-	## read its world-space AABB.
-	vp.add_child(mesh_inst)
+	var aabb_result: Dictionary = _combined_local_aabb(wrapper)
+	if aabb_result["found_any"]:
+		var combined: AABB = aabb_result["aabb"]
+		wrapper.position = -combined.get_center()
 
-	if mesh_inst.mesh != null:
-		var local_aabb: AABB    = mesh_inst.mesh.get_aabb()
-		var basis: Basis        = mesh_inst.transform.basis
-		var rot_center: Vector3 = basis * local_aabb.get_center()
-		mesh_inst.position = -rot_center
-	## else position stays Vector3.ZERO — nothing to center
+		var cam: Camera3D = null
+		for c in vp.get_children():
+			if c is Camera3D:
+				cam = c as Camera3D
+				break
+		if cam != null:
+			pivot.scale = Vector3.ONE * _preview_normalize_scale(combined, cam.size)
+	## else: no meshes found (shouldn't happen — wrapper.get_child_count()
+	## was already checked above) — pivot stays at origin, scale 1.0.
 
-## Removes any preview mesh(es) currently in `vp` (there should only ever
-## be one, but clears defensively — same pattern StorageUI already used).
+## Removes any preview content currently in `vp` (the wrapping pivot from
+## set_item() — there should only ever be one, cleared defensively).
+## Matches any Node3D that isn't the camera or light rather than
+## MeshInstance3D specifically — set_item() now wraps its content in a
+## pivot Node3D (needed for the rotate+scale composition above), so a
+## MeshInstance3D-only check (the old behavior here) would silently stop
+## matching anything at all.
 static func clear(vp: SubViewport) -> void:
 	for child in vp.get_children():
-		if child is MeshInstance3D:
+		if child is Node3D and child is not Camera3D and child is not OmniLight3D:
 			child.queue_free()
```
