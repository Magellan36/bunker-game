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
## source: item.get_inventory_mesh() first, else the item's first
## MeshInstance3D child, duplicated. Centering: local AABB center
## transformed through the mesh's rotation basis, so the rotated mesh
## sits visually centered in the viewport (not just origin-centered
## pre-rotation).

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

## Populates `vp` with a static preview of `item`'s mesh at
## ROTATION_DEFAULT, clearing any previous preview mesh first. No-op
## (mesh cleared, nothing added) if `item` is null or has no usable mesh
## source.
static func set_item(vp: SubViewport, item: Node) -> void:
	clear(vp)
	if item == null:
		return

	var mesh_inst: MeshInstance3D = null
	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = m
	if mesh_inst == null:
		for child in item.get_children():
			if child is MeshInstance3D:
				mesh_inst = child.duplicate() as MeshInstance3D
				break
	if mesh_inst == null:
		return

	mesh_inst.rotation_degrees = ROTATION_DEFAULT
	mesh_inst.position = Vector3.ZERO

	## Add to viewport FIRST — node must be in the scene tree before we can
	## read its world-space AABB.
	vp.add_child(mesh_inst)

	if mesh_inst.mesh != null:
		var local_aabb: AABB    = mesh_inst.mesh.get_aabb()
		var basis: Basis        = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center
	## else position stays Vector3.ZERO — nothing to center

## Removes any preview mesh(es) currently in `vp` (there should only ever
## be one, but clears defensively — same pattern StorageUI already used).
static func clear(vp: SubViewport) -> void:
	for child in vp.get_children():
		if child is MeshInstance3D:
			child.queue_free()
