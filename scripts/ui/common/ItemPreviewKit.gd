extends RefCounted
class_name ItemPreviewKit
## ItemPreviewKit.gd
## Shared static 3D item-preview builder (Aug 2026) — the ONE formula every
## panel that shows a live-rendered 3D preview of an inventory-style item
## must use. Extracted from InventoryHUD.gd's proven-working preview code
## (the reference implementation) so InventoryHUD and StorageUI render
## identically, and so any future adjustment (camera angle, zoom, lighting,
## mesh-fetch fallback) is made ONCE here and cascades to every consumer.
## Same static-function RefCounted convention as UIFade.gd/UIKit.gd — no
## instance state, no autoload.
##
## Deliberately NOT adopted by BuildModeHUD.gd yet — Build's construct/shop
## previews have their own hover-spin-on-cursor behavior (a pivot node
## rotated live in _process()) that this kit doesn't attempt to generalize.
## Build's resting pose (PREVIEW_ROTATION_DEFAULT) already matches this
## kit's ROTATION_DEFAULT by design — folding Build onto this kit is a
## reasonable future pass, not done here.
##
## THE FORMULA (do not diverge per-consumer — a mismatch here is exactly
## the bug this file fixes): camera is a fixed-angle orthographic look at
## the origin from Vector3(0.8, 0.8, 0.8); zoom (`cam.size`) scales
## linearly with the viewport's pixel size via CAM_SIZE_PER_PIXEL so
## different-sized preview slots (Inventory's 64px vs Storage's 96px) show
## an item at the SAME real-world scale, not a different zoom level. Mesh
## rotation is fixed (no spin) at ROTATION_DEFAULT, matching
## BuildModeHUD.PREVIEW_ROTATION_DEFAULT's resting pose exactly. Mesh
## source: item.get_inventory_mesh() first, else every MeshInstance3D
## descendant of item at any nesting depth, duplicated (see
## _duplicate_visual_tree()). Centering + scale: combined AABB of every
## duplicated mesh, normalized so the largest dimension fills a fixed
## fraction of the camera frame regardless of the item's real size (see
## PREVIEW_FILL_FRACTION) — both ported from BuildModeHUD.gd's construct/
## shop preview code, which solved this exact problem first.

## Reference values proven correct by InventoryHUD.gd (SLOT_SIZE=64,
## cam.size=0.4) — every consumer derives its own cam.size from this ratio
## so zoom stays visually consistent across different preview pixel sizes.
const CAM_SIZE_PER_PIXEL: float = 0.4 / 64.0   # 0.00625

## Matches BuildModeHUD.PREVIEW_ROTATION_DEFAULT exactly (45° left, 45°
## down) — the one shared resting pose for every static item preview.
const ROTATION_DEFAULT: Vector3 = Vector3(-45.0, -45.0, 0.0)

const CAM_POSITION: Vector3   = Vector3(0.8, 0.8, 0.8)
const LIGHT_POSITION: Vector3 = Vector3(1.0, 1.5, 1.0)
const LIGHT_ENERGY: float     = 2.5
const LIGHT_RANGE: float      = 8.0

## Aug 2026 — fraction of the camera's orthographic frame a preview's
## largest AABB dimension should fill, regardless of the item's real
## size (a Crate and a Seed Packet read as the same on-screen size).
## Ported from BuildModeHUD.PREVIEW_TARGET_SIZE / _preview_normalize_scale()
## (its own comment: "~0.85 leaves a small margin so a rotating/spinning
## object doesn't clip the viewport edge"). Expressed as a FRACTION of
## cam.size here rather than Build's fixed meters constant — Build only
## ever serves one fixed pixel size (52px) so a fixed-meters value and a
## fixed fraction were equivalent there; this kit serves multiple pixel
## sizes (Inventory's 64px vs Storage's 96px) via CAM_SIZE_PER_PIXEL, so
## the target has to scale with each call's own cam.size or it would
## overflow the smaller slot size and look tiny in the larger one.
const PREVIEW_FILL_FRACTION: float = 0.85

## Computes the combined AABB of every MeshInstance3D descendant of
## `root`, correctly expressed in root's OWN local coordinate space —
## i.e. accounting for each mesh's position/rotation/nesting-depth
## relative to root, not just merging each mesh's raw local-space AABB as
## if every child sat exactly at root's own origin. Ported verbatim from
## BuildModeHUD._combined_local_aabb() (see that function's header for
## the full "rotates around its feet instead of spinning in place"
## backstory). Requires `root` to already be inside the SceneTree
## (global_transform must be valid) — call this AFTER add_child(), never
## before.
static func _combined_local_aabb(root: Node3D) -> Dictionary:
	var combined: AABB = AABB()
	var found_any: bool = false
	var root_inverse: Transform3D = root.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = n as MeshInstance3D
			var relative_transform: Transform3D = root_inverse * mi.global_transform
			var mesh_aabb: AABB = relative_transform * mi.mesh.get_aabb()
			if not found_any:
				combined = mesh_aabb
				found_any = true
			else:
				combined = combined.merge(mesh_aabb)
		for c in n.get_children():
			stack.append(c)
	return { "aabb": combined, "found_any": found_any }

## Returns the uniform scale factor that makes `aabb`'s single largest
## dimension fill PREVIEW_FILL_FRACTION of `cam_size` (the calling
## preview's own orthographic camera size — see PREVIEW_FILL_FRACTION's
## header for why this is a fraction of cam_size and not a fixed meters
## constant like BuildModeHUD's version). Apply this to a preview's PIVOT
## node (never the mesh/wrapper child) — composes cleanly with the
## pivot's rotation and the wrapper's own `-aabb.get_center()` centering
## offset with zero extra math needed (a uniform scale on an
## already-centered child stays centered regardless of the scale factor).
static func _preview_normalize_scale(aabb: AABB, cam_size: float) -> float:
	var largest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if largest < 0.0001:
		return 1.0
	return (PREVIEW_FILL_FRACTION * cam_size) / largest

## Duplicates every MeshInstance3D descendant of `item` (any nesting
## depth) into a single flat wrapper Node3D, each copy keeping its
## correct transform relative to item's own origin (same global-transform
## math as _combined_local_aabb()), plus its material overrides so
## per-item color variants (e.g. seed species colors) still render
## correctly. Deliberately copies only mesh geometry, never the live node
## tree itself — no scripts, physics bodies, or collision shapes come
## along, so this is always safe to drop into an isolated preview
## SubViewport regardless of what `item`'s own _ready()/_process() does
## in the real world. Skips any MeshInstance3D that's currently
## `visible = false` (e.g. CanCase/WaterCase hide individual can/bottle
## meshes as they're depleted — the preview should match, not always show
## a full case). Returns an empty (childless) wrapper if `item` has no
## visible MeshInstance3D descendants at all.
static func _duplicate_visual_tree(item: Node3D) -> Node3D:
	var wrapper := Node3D.new()
	var root_inverse: Transform3D = item.global_transform.affine_inverse()
	var stack: Array = [item]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var src: MeshInstance3D = n as MeshInstance3D
			var copy := MeshInstance3D.new()
			copy.mesh = src.mesh
			copy.material_override = src.material_override
			## Count comes from the mesh resource, not MeshInstance3D
			## itself — matches the get_surface_count() pattern already
			## used elsewhere in this codebase (BuildMaterials.gd,
			## MoveDuplicateTool.gd, BunkerPregen.gd).
			for surf_i in src.mesh.get_surface_count():
				copy.set_surface_override_material(surf_i, src.get_surface_override_material(surf_i))
			copy.transform = root_inverse * src.global_transform
			wrapper.add_child(copy)
		for c in n.get_children():
			stack.append(c)
	return wrapper

## Builds one preview slot (SubViewport + orthographic Camera3D +
## OmniLight3D) sized for `pixel_size` px square, added as a child of
## `parent`. Returns the SubViewport — callers keep their own array of
## these, plus `vp.get_texture()` for whatever TextureRect displays it.
static func build_viewport(parent: Node, pixel_size: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(pixel_size, pixel_size)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.transparent_bg = true
	vp.own_world_3d    = true
	vp.disable_3d      = false
	parent.add_child(vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE_PER_PIXEL * float(pixel_size)
	vp.add_child(cam)   ## Must be in tree before look_at()
	cam.position = CAM_POSITION
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var light := OmniLight3D.new()
	light.position     = LIGHT_POSITION
	light.light_energy = LIGHT_ENERGY
	light.omni_range   = LIGHT_RANGE
	vp.add_child(light)

	return vp

## Populates `vp` with a static preview of `item`'s full visual geometry
## at ROTATION_DEFAULT, normalized to PREVIEW_FILL_FRACTION, clearing any
## previous preview first. No-op (cleared, nothing added) if `item` is
## null or has no usable mesh source.
static func set_item(vp: SubViewport, item: Node) -> void:
	clear(vp)
	if item == null:
		return

	## get_inventory_mesh() tried first — cheaper for the common
	## single-mesh case, and some items intentionally return a stand-in
	## mesh that differs from their literal world geometry. Falls back to
	## walking item's full descendant tree (any nesting depth) via
	## _duplicate_visual_tree() — see that function's header for why a
	## single-level direct-child scan (the old behavior here) left
	## CanCase/WaterCase blank.
	var wrapper: Node3D = null
	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			wrapper = Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = m
			wrapper.add_child(mi)
	if wrapper == null and item is Node3D:
		wrapper = _duplicate_visual_tree(item as Node3D)
	if wrapper == null or wrapper.get_child_count() == 0:
		return

	## Pivot rotates in place; wrapper (its child) only translates to
	## center the combined AABB. Two separate nodes because a single
	## Transform3D can't cleanly do both "rotate around the true visual
	## center" and "translate to compensate for an off-center AABB" at
	## once — same split BuildModeHUD's preview code uses, same reason.
	var pivot := Node3D.new()
	pivot.rotation_degrees = ROTATION_DEFAULT
	vp.add_child(pivot)   ## Must be in tree before reading global_transform below
	pivot.add_child(wrapper)

	var aabb_result: Dictionary = _combined_local_aabb(wrapper)
	if aabb_result["found_any"]:
		var combined: AABB = aabb_result["aabb"]
		wrapper.position = -combined.get_center()

		var cam: Camera3D = null
		for c in vp.get_children():
			if c is Camera3D:
				cam = c as Camera3D
				break
		if cam != null:
			pivot.scale = Vector3.ONE * _preview_normalize_scale(combined, cam.size)
	## else: no meshes found (shouldn't happen — wrapper.get_child_count()
	## was already checked above) — pivot stays at origin, scale 1.0.

## Removes any preview content currently in `vp` (the wrapping pivot from
## set_item() — there should only ever be one, cleared defensively).
## Matches any Node3D that isn't the camera or light rather than
## MeshInstance3D specifically — set_item() now wraps its content in a
## pivot Node3D (needed for the rotate+scale composition above), so a
## MeshInstance3D-only check (the old behavior here) would silently stop
## matching anything at all.
static func clear(vp: SubViewport) -> void:
	for child in vp.get_children():
		if child is Node3D and child is not Camera3D and child is not OmniLight3D:
			child.queue_free()
