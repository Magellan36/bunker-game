# Plan — Storage UI: Shared Item Preview Kit + Icon/Row-Label Redesign (Aug 2026)

## Summary
Three independent fixes/changes, all inside the UI thread's existing scope:

1. **Fix broken 3D item previews in `StorageUI.gd`** (Shelving/Basket/End
   Table/Dresser) by extracting `InventoryHUD.gd`'s proven-working preview
   code into a new shared static utility, `scripts/ui/common/ItemPreviewKit.gd`,
   and migrating both `InventoryHUD.gd` and `StorageUI.gd` onto it. Root
   cause: `StorageUI._add_pool_slot()` used `cam.size = 1.2` and mesh
   rotation `(-20°, 45°, 0°)`; `InventoryHUD` (the correct reference) uses
   `cam.size = 0.4` and `(-45°, -45°, 0°)` — Storage's camera is 3x more
   zoomed out on top of a totally different angle, which is why most item
   meshes render as a near-invisible speck. Build Mode's previews
   (`BuildModeHUD.gd`) are **deliberately left untouched** this pass — they
   already share the same resting rotation but have their own hover-spin
   behavior layered on top; folding them onto this kit is a reasonable
   future pass, not part of this one.
2. **Replace the "↑"/"↓"/"⊕" text-glyph buttons with real icon textures**
   across every `StorageUI` consumer (Shelving, End Table, Dresser, Basket)
   — this is a single change in `StorageUI.gd` since all storage panels
   already funnel through its one shared button-builder.
3. **Remove the "Top shelf"/"Middle drawers"/etc. row-label text** from
   every storage panel, and **tighten row spacing by 18px** (half the
   36px primary/carry button height): `ROW_GAP` goes from `22` to `4`.

Everything here is inside files already owned by the UI thread per the
handoff doc (`scripts/ui/*`, `scripts/world/furniture/*`,
`scripts/world/items/*`) — no cross-thread hand-off needed.

## Assets — add these 3 files to the repo first
Files are attached to this plan. Copy them into the repo at exactly these
paths (binary copy, no processing needed — the rotated cross icon is
already pre-rotated 45° with an expanded, non-clipped canvas):

- `assets/icons/arrow_decorative_n.png` (north-facing decorative arrow —
  becomes the "Carry" button icon)
- `assets/icons/arrow_decorative_s.png` (south-facing decorative arrow —
  becomes the "Drop" button icon)
- `assets/icons/icon_plus.png` (your `icon_cross.png`, pre-rotated 45° —
  becomes the "Add to inventory" button icon)

No `.import` files need to be hand-authored — Godot auto-generates them on
first import, same as the existing `assets/icons/close_x.png`. All three
source images carry their own gray/silver shading (not a plain white
alpha mask like `close_x.png`), so they render un-tinted — no `modulate`
color override needed anywhere.

---

## Part 1 — New file: `scripts/ui/common/ItemPreviewKit.gd`

Create this new file with the following full content:

```gdscript
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
```

---

## Part 2 — `scripts/ui/inventory/InventoryHUD.gd`

### 2a. Remove now-unnecessary per-slot tracking arrays
`ItemPreviewKit.set_item()`/`clear()` self-manage by scanning the
SubViewport's children, so the old `_previews` tracking array is no
longer needed (mirrors the pattern `StorageUI.gd` already used, which
never needed one). `_cameras` is also dead — confirmed via repo-wide grep
that nothing outside `_build_viewports()` ever reads it.

**old_str:**
```
var _viewports:  Array[SubViewport]    = []
var _cameras:    Array[Camera3D]       = []
var _previews:   Array[MeshInstance3D] = []   ## Currently displayed mesh copy
var _vp_textures: Array[ViewportTexture] = []
```
**new_str:**
```
var _viewports:  Array[SubViewport]    = []
var _vp_textures: Array[ViewportTexture] = []
```

### 2b. Replace `_build_viewports()` body

**old_str:**
```
func _build_viewports() -> void:
	for i in 4:
		var vp := SubViewport.new()
		vp.size = Vector2i(int(SLOT_SIZE), int(SLOT_SIZE))
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		vp.transparent_bg = true
		vp.disable_3d = false
		# CRITICAL: own world so the preview light doesn't leak into the main scene
		# and so the main scene's lights don't corrupt the preview render.
		vp.own_world_3d = true
		add_child(vp)

		# Camera at a fixed iso angle looking at origin.
		# IMPORTANT: add to tree BEFORE calling look_at() — look_at() requires
		# the node to be inside the scene tree to compute global transforms.
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.4   ## Jul 2026 — 1.2 / 3.0, previews 3x bigger in the same 64px slot
		vp.add_child(cam)   ## Must be in tree first
		cam.position = Vector3(0.8, 0.8, 0.8)
		cam.look_at(Vector3.ZERO, Vector3.UP)

		# Soft fill light so mesh isn't pitch black
		var light := OmniLight3D.new()
		light.position = Vector3(1.0, 1.5, 1.0)
		light.light_energy = 2.5
		light.omni_range = 8.0
		vp.add_child(light)

		_viewports.append(vp)
		_cameras.append(cam)
		_previews.append(null)

		# Grab the texture handle once — stays valid
		_vp_textures.append(vp.get_texture())
```
**new_str:**
```
func _build_viewports() -> void:
	for i in 4:
		var vp: SubViewport = ItemPreviewKit.build_viewport(self, int(SLOT_SIZE))
		_viewports.append(vp)

		# Grab the texture handle once — stays valid
		_vp_textures.append(vp.get_texture())
```

### 2c. Replace `_set_preview()` body

**old_str:**
```
func _set_preview(slot_idx: int, item) -> void:
	var vp: SubViewport = _viewports[slot_idx]

	# Remove old preview mesh
	if _previews[slot_idx] != null:
		_previews[slot_idx].queue_free()
		_previews[slot_idx] = null

	if item == null:
		return

	# Get mesh from the item — try get_inventory_mesh() first, fallback to child scan
	var mesh_inst: MeshInstance3D = null

	if item.has_method("get_inventory_mesh"):
		var m: Mesh = item.get_inventory_mesh()
		if m != null:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = m
	
	if mesh_inst == null:
		# Fallback: duplicate the first MeshInstance3D child of the item
		for child in item.get_children():
			if child is MeshInstance3D:
				mesh_inst = child.duplicate() as MeshInstance3D
				break

	if mesh_inst == null:
		return

	# Jul 2026 — matches BuildModeHUD.gd's PREVIEW_ROTATION_DEFAULT resting
	# pose exactly (45° left, 45° down) so construct/shop previews and
	# inventory previews read as the same angled look. Deliberately static
	# — no hover-spin here, unlike BuildModeHUD's pool.
	mesh_inst.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	mesh_inst.position = Vector3.ZERO

	# Add to viewport FIRST — node must be in the scene tree before we can
	# read its world-space AABB (get_aabb() needs a valid global transform).
	vp.add_child(mesh_inst)

	# Now read the AABB in the node's LOCAL space but transformed by its basis
	# so rotation is accounted for. mesh.get_aabb() is pre-rotation and gives
	# the wrong center; instead we transform it manually with the node's basis.
	if mesh_inst.mesh != null:
		var local_aabb: AABB  = mesh_inst.mesh.get_aabb()
		# Transform each corner through the rotation basis to get the true
		# rotated extents, then rebuild the AABB from the transformed center.
		var basis: Basis      = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center
	# else position stays Vector3.ZERO — nothing to center

	_previews[slot_idx] = mesh_inst
```
**new_str:**
```
func _set_preview(slot_idx: int, item) -> void:
	## Delegates to the shared kit (Aug 2026) — see ItemPreviewKit.gd for
	## the mesh-fetch/rotation/centering formula. Every other preview
	## consumer (StorageUI) uses this exact same call.
	ItemPreviewKit.set_item(_viewports[slot_idx], item)
```

---

## Part 3 — `scripts/ui/inventory/StorageUI.gd`

### 3a. Update the file's top header comment
Remove the stale "row labels" mention from the contract description.

**old_str:**
```
## That's the whole contract. Grid shape, row labels, capacity, stacking,
## and the primary button's icon/label/color/hands-empty-requirement are
## ALL read from get_ui_config() at open() time — nothing type-specific is
## hardcoded in this file. Adding a new storage type needs ZERO changes
## here, just a world-object script implementing the contract above.
```
**new_str:**
```
## That's the whole contract. Grid shape, capacity, stacking, and the
## primary button's icon/label/color/hands-empty-requirement are ALL read
## from get_ui_config() at open() time — nothing type-specific is
## hardcoded in this file. Adding a new storage type needs ZERO changes
## here, just a world-object script implementing the contract above.
##
## primary_button_icon (Aug 2026 — no longer a literal glyph): must be one
## of the keys in _ICON_TEXTURES below ("carry" or "drop"). The secondary
## "Add to inventory" button's icon is fixed (not config-driven) — same
## icon for every storage type, see _INV_ICON_TEXTURE.
```

### 3b. Remove `row_labels` from the default config

**old_str:**
```
	"display_order": [],                 ## [] = identity (visual pos i -> data slot i)
	"row_labels": [],                    ## [] = auto "Row N" labels
	"supports_stacking": false,
```
**new_str:**
```
	"display_order": [],                 ## [] = identity (visual pos i -> data slot i)
	"supports_stacking": false,
```

### 3c. Add the icon texture consts + tighten row gap

**old_str:**
```
# ─── Layout constants (unchanged from the old ShelfUI.gd/BasketUI.gd) ────────
const PREVIEW_SIZE:  int   = 96
const SLOT_GAP:      int   = 18
const BTN_SIZE:      float = 36.0
const BTN_GAP:       float = 8.0
const PANEL_PAD:     int   = 28
const PANEL_RADIUS:  float = 14.0
const ROW_GAP:        int   = 22
const ROW_LABEL_H:   int   = 18
```
**new_str:**
```
# ─── Layout constants (unchanged from the old ShelfUI.gd/BasketUI.gd) ────────
const PREVIEW_SIZE:  int   = 96
const SLOT_GAP:      int   = 18
const BTN_SIZE:      float = 36.0
const BTN_GAP:       float = 8.0
const PANEL_PAD:     int   = 28
const PANEL_RADIUS:  float = 14.0
## Aug 2026 — reduced from 22 to 4 (18px, half of BTN_SIZE) per the row-
## label removal below; this is now the ONLY vertical gap between rows.
const ROW_GAP:        int   = 4

# ─── Icon textures (Aug 2026 — replaces the old "↑"/"↓"/"⊕" text glyphs).
## primary_button_icon in get_ui_config() must be one of these keys.
## Sources carry their own gray/silver shading — do not modulate/tint.
const _ICON_TEXTURES: Dictionary = {
	"carry": preload("res://assets/icons/arrow_decorative_n.png"),
	"drop":  preload("res://assets/icons/arrow_decorative_s.png"),
}
## Fixed for every storage type — not config-driven.
const _INV_ICON_TEXTURE: Texture2D = preload("res://assets/icons/icon_plus.png")
## Caps rendered icon size inside the 36px button (all 3 source PNGs are
## square, so this scales them uniformly with no distortion).
const ICON_MAX_WIDTH: int = 22
```

### 3d. Remove the now-dead `C_ROW_LABEL` color const

**old_str:**
```
const C_EMPTY_TEXT:  Color = Color(0.35, 0.35, 0.35, 1.00)
const C_ROW_LABEL:   Color = Color(0.45, 0.43, 0.40, 1.00)
const C_BADGE_TEXT:  Color = Color(0.80, 1.00, 0.85, 1.00)
```
**new_str:**
```
const C_EMPTY_TEXT:  Color = Color(0.35, 0.35, 0.35, 1.00)
const C_BADGE_TEXT:  Color = Color(0.80, 1.00, 0.85, 1.00)
```

### 3e. Replace the viewport/camera/light block in `_add_pool_slot()`

**old_str:**
```
func _add_pool_slot() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.transparent_bg = true
	vp.own_world_3d    = true
	vp.disable_3d      = false
	_root.add_child(vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.2
	vp.add_child(cam)
	cam.position = Vector3(0.8, 0.8, 0.8)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var light := OmniLight3D.new()
	light.position = Vector3(1.0, 1.5, 1.0)
	light.light_energy = 2.5
	light.omni_range = 8.0
	vp.add_child(light)

	var slot_bg: Panel = Panel.new()
```
**new_str:**
```
func _add_pool_slot() -> void:
	## Aug 2026 — delegates to the shared kit; was previously hand-rolled
	## here with cam.size=1.2 and no rotation match to Inventory/Build,
	## which is why most item meshes rendered as a near-invisible speck.
	## See ItemPreviewKit.gd for the formula every preview consumer shares.
	var vp: SubViewport = ItemPreviewKit.build_viewport(_root, PREVIEW_SIZE)

	var slot_bg: Panel = Panel.new()
```

### 3f. Convert `_make_icon_button()` from text glyphs to icon textures

**old_str:**
```
func _make_icon_button(slot_idx: int, is_primary: bool) -> Button:
	var btn: Button = Button.new()
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.add_theme_color_override("font_color", C_BTN_TEXT)
	btn.add_theme_font_size_override("font_size", 16)

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
	btn.add_theme_stylebox_override("normal", ss)
	btn.add_theme_stylebox_override("hover", ss.duplicate())
	btn.add_theme_stylebox_override("pressed", ss.duplicate())

	if is_primary:
		btn.pressed.connect(func() -> void: _on_primary_pressed(slot_idx))
	else:
		btn.text = "⊕"
		btn.tooltip_text = "Add to inventory"
		var inv_ss: StyleBoxFlat = ss.duplicate()
		inv_ss.bg_color = C_BTN_INV
		btn.add_theme_stylebox_override("normal", inv_ss)
		var inv_hover: StyleBoxFlat = inv_ss.duplicate()
		inv_hover.bg_color = C_BTN_INV.lightened(0.2)
		btn.add_theme_stylebox_override("hover", inv_hover)
		var inv_pressed: StyleBoxFlat = inv_ss.duplicate()
		inv_pressed.bg_color = C_BTN_INV.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", inv_pressed)
		btn.pressed.connect(func() -> void: _on_inv_pressed(slot_idx))

	return btn
```
**new_str:**
```
func _make_icon_button(slot_idx: int, is_primary: bool) -> Button:
	var btn: Button = Button.new()
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.text = ""
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH)

	var ss: StyleBoxFlat = StyleBoxFlat.new()
	ss.set_corner_radius_all(int(BTN_SIZE * 0.25))
	btn.add_theme_stylebox_override("normal", ss)
	btn.add_theme_stylebox_override("hover", ss.duplicate())
	btn.add_theme_stylebox_override("pressed", ss.duplicate())

	if is_primary:
		btn.pressed.connect(func() -> void: _on_primary_pressed(slot_idx))
	else:
		btn.icon = _INV_ICON_TEXTURE
		btn.tooltip_text = "Add to inventory"
		var inv_ss: StyleBoxFlat = ss.duplicate()
		inv_ss.bg_color = C_BTN_INV
		btn.add_theme_stylebox_override("normal", inv_ss)
		var inv_hover: StyleBoxFlat = inv_ss.duplicate()
		inv_hover.bg_color = C_BTN_INV.lightened(0.2)
		btn.add_theme_stylebox_override("hover", inv_hover)
		var inv_pressed: StyleBoxFlat = inv_ss.duplicate()
		inv_pressed.bg_color = C_BTN_INV.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", inv_pressed)
		btn.pressed.connect(func() -> void: _on_inv_pressed(slot_idx))

	return btn
```
Note: `C_BTN_TEXT` const (still used nowhere else — confirm via grep before
final apply; if truly unused after this change, remove its declaration too
as a small follow-on cleanup, same convention as the other dead-code
removals in this plan).

### 3g. Convert `_apply_primary_button_style()` to use the icon lookup

**old_str:**
```
func _apply_primary_button_style() -> void:
	var icon: String = String(_cfg("primary_button_icon"))
	var tip: String  = String(_cfg("primary_button_tooltip"))
	var color: Color  = _cfg("primary_button_color")

	for btn: Button in _primary_btns:
		btn.text = icon
		btn.tooltip_text = tip
```
**new_str:**
```
func _apply_primary_button_style() -> void:
	var icon_key: String    = String(_cfg("primary_button_icon"))
	var tip: String         = String(_cfg("primary_button_tooltip"))
	var color: Color        = _cfg("primary_button_color")
	var texture: Texture2D  = _ICON_TEXTURES.get(icon_key)

	for btn: Button in _primary_btns:
		btn.icon = texture
		btn.tooltip_text = tip
```
(The rest of the function — the stylebox color block below this — is
unchanged, leave it exactly as-is.)

### 3h. Remove row-label rendering from `_layout_panel()`

**old_str:**
```
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size     = Vector2(panel_w, panel_h)
	_panel.position = (vp_size - _panel.size) * 0.5

	var title: Label = _panel.get_node("Title")
	title.position = Vector2(0, PANEL_PAD * 0.5)
	title.size = Vector2(panel_w, title_h)

	for child in _panel.get_children():
		if child.name.begins_with("RowLabel_"):
			child.queue_free()

	var row_labels: Array = _cfg("row_labels")
	var slot_count: int = int(_cfg("slot_count"))
```
**new_str:**
```
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.size     = Vector2(panel_w, panel_h)
	_panel.position = (vp_size - _panel.size) * 0.5

	var title: Label = _panel.get_node("Title")
	title.position = Vector2(0, PANEL_PAD * 0.5)
	title.size = Vector2(panel_w, title_h)

	var slot_count: int = int(_cfg("slot_count"))
```

### 3i. Update the panel-height formula (drop `ROW_LABEL_H`)

**old_str:**
```
	var panel_w: int = PANEL_PAD * 2 + cols * col_w + (cols - 1) * SLOT_GAP
	var panel_h: int = PANEL_PAD * 2 + title_h + rows * row_h + (rows - 1) * (ROW_GAP + ROW_LABEL_H)
```
**new_str:**
```
	var panel_w: int = PANEL_PAD * 2 + cols * col_w + (cols - 1) * SLOT_GAP
	var panel_h: int = PANEL_PAD * 2 + title_h + rows * row_h + (rows - 1) * ROW_GAP
```

### 3j. Remove the row-label `Label` node and reposition slots directly

**old_str:**
```
	for row: int in rows:
		var row_y_base: int = PANEL_PAD + title_h + row * (row_h + ROW_GAP + ROW_LABEL_H)

		var label_text: String = row_labels[row] if row < row_labels.size() else "Row %d" % (row + 1)
		var row_lbl: Label = Label.new()
		row_lbl.name = "RowLabel_%d" % row
		row_lbl.text = label_text
		row_lbl.add_theme_color_override("font_color", C_ROW_LABEL)
		row_lbl.add_theme_font_size_override("font_size", 10)
		row_lbl.position = Vector2(PANEL_PAD, row_y_base)
		row_lbl.size     = Vector2(panel_w - PANEL_PAD * 2, ROW_LABEL_H)
		_panel.add_child(row_lbl)

		for col: int in cols:
			var visual_idx: int = row * cols + col
			if visual_idx >= slot_count:
				continue
			var sx: float = PANEL_PAD + col * (col_w + SLOT_GAP)
			var sy: float = row_y_base + ROW_LABEL_H + 4
			_position_slot_visuals(visual_idx, sx, sy)
```
**new_str:**
```
	for row: int in rows:
		var row_y_base: int = PANEL_PAD + title_h + row * (row_h + ROW_GAP)

		for col: int in cols:
			var visual_idx: int = row * cols + col
			if visual_idx >= slot_count:
				continue
			var sx: float = PANEL_PAD + col * (col_w + SLOT_GAP)
			var sy: float = row_y_base
			_position_slot_visuals(visual_idx, sx, sy)
```

### 3k. Simplify `_populate_viewport()` / `_clear_viewport()`

**old_str:**
```
func _populate_viewport(visual_idx: int, item: Node) -> void:
	var vp: SubViewport = _viewports[visual_idx]

	var to_free: Array = []
	for child in vp.get_children():
		if child is MeshInstance3D:
			to_free.append(child)
	for c in to_free:
		c.queue_free()

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

	mesh_inst.rotation_degrees = Vector3(-20.0, 45.0, 0.0)
	mesh_inst.position = Vector3.ZERO
	vp.add_child(mesh_inst)

	if mesh_inst.mesh != null:
		var local_aabb: AABB    = mesh_inst.mesh.get_aabb()
		var basis: Basis        = mesh_inst.transform.basis
		var rot_center: Vector3 = basis * local_aabb.get_center()
		mesh_inst.position = -rot_center

func _clear_viewport(visual_idx: int) -> void:
	var vp: SubViewport = _viewports[visual_idx]
	for child in vp.get_children():
		if child is MeshInstance3D:
			child.queue_free()

func _clear_all_viewports() -> void:
	for i: int in _pool_size:
		_clear_viewport(i)
```
**new_str:**
```
func _populate_viewport(visual_idx: int, item: Node) -> void:
	## Aug 2026 — delegates to the shared kit; the old body here used
	## rotation (-20°, 45°, 0°) with no matching cam.size fix, which was
	## the root cause of most item previews rendering as a near-invisible
	## speck. See ItemPreviewKit.gd.
	ItemPreviewKit.set_item(_viewports[visual_idx], item)

func _clear_viewport(visual_idx: int) -> void:
	ItemPreviewKit.clear(_viewports[visual_idx])

func _clear_all_viewports() -> void:
	for i: int in _pool_size:
		_clear_viewport(i)
```

---

## Part 4 — Storage-object config updates

### 4a. `scripts/world/items/Basket.gd`

**old_str:**
```
		"display_order": [],    ## [] = identity (visual position i -> data slot i)
		"row_labels": [],       ## [] = auto "Row N" labels
		"supports_stacking": false,
		"primary_button_icon": "↓",
		"primary_button_tooltip": "Drop",
```
**new_str:**
```
		"display_order": [],    ## [] = identity (visual position i -> data slot i)
		"supports_stacking": false,
		"primary_button_icon": "drop",
		"primary_button_tooltip": "Drop",
```

### 4b. `scripts/world/furniture/Shelving.gd`

**old_str:**
```
		"display_order": [4, 5, 2, 3, 0, 1],   ## visual position -> data slot (top row shows data slots 4/5, etc.)
		"row_labels": ["Top shelf", "Middle shelf", "Bottom shelf"],
		"supports_stacking": true,
		"primary_button_icon": "↑",
		"primary_button_tooltip": "Carry",
```
**new_str:**
```
		"display_order": [4, 5, 2, 3, 0, 1],   ## visual position -> data slot (top row shows data slots 4/5, etc.)
		"supports_stacking": true,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
```

Also update the stale comment referencing the old glyph:

**old_str:**
```
# ─── Retrieve to inventory (from StorageUI's secondary "⊕" button) ───────────
```
**new_str:**
```
# ─── Retrieve to inventory (from StorageUI's secondary "Add to inventory" button) ─
```

### 4c. `scripts/world/furniture/LightStorage.gd`

Remove the now-dead `row_labels` export:

**old_str:**
```
@export var capacity: int          = 2
@export var display_name: String   = "End Table"
@export var prompt_height: float   = 1.2   ## get_prompt_world_pos Y offset
@export var grid_cols: int         = 2
@export var grid_rows: int         = 1
@export var row_labels: Array[String] = []
```
**new_str:**
```
@export var capacity: int          = 2
@export var display_name: String   = "End Table"
@export var prompt_height: float   = 1.2   ## get_prompt_world_pos Y offset
@export var grid_cols: int         = 2
@export var grid_rows: int         = 1
```

Remove it from `get_ui_config()` and update the icon key:

**old_str:**
```
		"display_order": [],                  ## identity — visual pos i = stored index i
		"row_labels": row_labels,
		"supports_stacking": false,
		"primary_button_icon": "↑",
		"primary_button_tooltip": "Carry",
```
**new_str:**
```
		"display_order": [],                  ## identity — visual pos i = stored index i
		"supports_stacking": false,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
```

Also update the stale comment referencing the old glyph:

**old_str:**
```
## Secondary "⊕" button — mirrors Shelving.retrieve_to_inventory()
```
**new_str:**
```
## Secondary "Add to inventory" button — mirrors Shelving.retrieve_to_inventory()
```

### 4d. `scripts/world/furniture/Dresser.gd`

**old_str:**
```
	grid_cols     = 2
	grid_rows     = 3
	row_labels    = ["Top drawers", "Middle drawers", "Bottom drawers"]
```
**new_str:**
```
	grid_cols     = 2
	grid_rows     = 3
```

### 4e. `scripts/world/furniture/EndTable.gd`

**old_str:**
```
	grid_cols     = 2
	grid_rows     = 1
	row_labels    = ["Drawer"]
```
**new_str:**
```
	grid_cols     = 2
	grid_rows     = 1
```

---

## Verification checklist
1. `godot_check.sh` (and headless shader check) passes clean.
2. Open Shelving, End Table, Dresser, and Basket in-game — every occupied
   slot shows a clearly visible, correctly-scaled, correctly-angled item
   mesh (same resting angle as the inventory bar's previews).
3. Open the pocket inventory bar — previews still render exactly as
   before (no visual regression from the `ItemPreviewKit` migration).
4. No "Top shelf"/"Middle drawers"/"Row N"/etc. text appears in any
   storage panel; panels are visually tighter between rows but not
   cramped.
5. Shelving's Carry button and End Table/Dresser's Carry button show the
   north-facing decorative arrow; Basket's Drop button shows the
   south-facing decorative arrow; every storage type's "Add to inventory"
   button shows the plus-shaped icon, right-side-up, not tilted.
6. Confirm `C_BTN_TEXT` in `StorageUI.gd` is genuinely unused after 3f
   (repo-wide grep) before removing its declaration.
7. Confirm no other file references `row_labels` on `LightStorage`,
   `Dresser`, or `EndTable` before/after removal (repo-wide grep).
8. Basket's grid (3 cols × 4 rows, no `display_order` remap) and
   Shelving's remapped grid both still show the correct item in the
   correct visual slot — the row-label removal only touches vertical
   layout math, never `display_order`/`_data_slot_for()`.

## Files modified
- `scripts/ui/common/ItemPreviewKit.gd` — **NEW**.
- `scripts/ui/inventory/InventoryHUD.gd` — preview build/populate
  delegated to `ItemPreviewKit`; `_cameras`/`_previews` arrays removed.
- `scripts/ui/inventory/StorageUI.gd` — preview build/populate delegated
  to `ItemPreviewKit`; icon buttons converted from text glyphs to
  textures; row-label rendering removed; `ROW_GAP` 22→4; `ROW_LABEL_H`/
  `C_ROW_LABEL` removed.
- `scripts/world/items/Basket.gd` — `primary_button_icon` "↓"→"drop";
  `row_labels` key removed.
- `scripts/world/furniture/Shelving.gd` — `primary_button_icon` "↑"→
  "carry"; `row_labels` key removed; stale comment updated.
- `scripts/world/furniture/LightStorage.gd` — `row_labels` export and
  config key removed; `primary_button_icon` "↑"→"carry"; stale comment
  updated.
- `scripts/world/furniture/Dresser.gd` — `row_labels` assignment removed.
- `scripts/world/furniture/EndTable.gd` — `row_labels` assignment
  removed.
- `assets/icons/arrow_decorative_n.png`, `arrow_decorative_s.png`,
  `icon_plus.png` — **NEW** (attached to this plan).
- `docs/systems/ui/README.md` — see Part 5.
- `docs/systems/furniture-items/README.md` — see Part 5.
- `HANDOVER.md` — new top section, see Part 5.

---

## Part 5 — Documentation updates

### 5a. `docs/systems/ui/README.md` — update the `common/` files table row

**old_str:**
```
| `common/` | `UIFade.gd` (~30), `UIKit.gd` (~530 — grew substantially across the Jul 2026 "UI Overhaul" arc: menu builders, rounded corners, domain stripes, the shared close-icon, a 4th `FARMING` domain) | Shared fade-in helper + shared theme/drawing kit (see "UIKit shared kit" below) — put any future cross-panel UI utility here |
```
**new_str:**
```
| `common/` | `UIFade.gd` (~30), `UIKit.gd` (~530 — grew substantially across the Jul 2026 "UI Overhaul" arc: menu builders, rounded corners, domain stripes, the shared close-icon, a 4th `FARMING` domain), `ItemPreviewKit.gd` (~90 — Aug 2026, shared static 3D item-preview builder used by `InventoryHUD`/`StorageUI`, see "Shared Item Preview Kit" below) | Shared fade-in helper + shared theme/drawing kit + shared 3D item-preview builder — put any future cross-panel UI utility here |
```

### 5b. `docs/systems/ui/README.md` — update the `inventory/` files table row

**old_str:**
```
| `inventory/` | `InventoryHUD.gd` (~445 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback), `InventoryManager.gd` (~155, see Non-responsibilities), `StorageUI.gd` (~380 — Aug 2026, generic shared storage overlay, replaces the former `ShelfUI.gd`/`BasketUI.gd`, see "Storage UI Unification" below) | Slot HUD, inventory state, shared storage-container panel |
```
**new_str:**
```
| `inventory/` | `InventoryHUD.gd` (~400 — badge dispatch: `WaterBottle`-style items draw a two-line "Xml/750ml"/"(Q%)" quality badge via `get_bottle_badge_info()`, or a single dim "EMPTY" badge at 0mL, checked ahead of the generic charge-count fallback; 3D preview building/populating delegated to `ItemPreviewKit.gd` as of Aug 2026), `InventoryManager.gd` (~155, see Non-responsibilities), `StorageUI.gd` (~360 — Aug 2026, generic shared storage overlay, replaces the former `ShelfUI.gd`/`BasketUI.gd`, see "Storage UI Unification" below; icon-texture buttons + preview delegated to `ItemPreviewKit.gd`, row labels removed, see "Shared Item Preview Kit" and "Storage UI Icon + Row Label Redesign" below) | Slot HUD, inventory state, shared storage-container panel |
```

### 5c. `docs/systems/ui/README.md` — add `ItemPreviewKit` to the Public API list

Insert this new bullet right after the existing `UIFade` bullet (find the
`- **UIFade** (static, ...)` line and add immediately below it):

**old_str:**
```
- `UIFade` (static, `scripts/ui/common/UIFade.gd`): `UIFade.fade_in(target:
  CanvasItem, duration: float = 0.15)`.
```
**new_str:**
```
- `UIFade` (static, `scripts/ui/common/UIFade.gd`): `UIFade.fade_in(target:
  CanvasItem, duration: float = 0.15)`.
- `ItemPreviewKit` (static, `scripts/ui/common/ItemPreviewKit.gd`, Aug
  2026): `build_viewport(parent, pixel_size) -> SubViewport`,
  `set_item(vp, item)`, `clear(vp)` — shared 3D item-preview builder used
  by `InventoryHUD` and `StorageUI`, see "Shared Item Preview Kit" below.
```

### 5d. `docs/systems/ui/README.md` — add two new sections

Insert these two new sections right after the existing "## Farming Shop
Seed tile_id Bugfix (Aug 2026)" section (i.e. as the new last sections,
before "## Extension points"):

```markdown
## Shared Item Preview Kit (Aug 2026)
Fixed StorageUI's 3D item previews (Shelving/Basket/End Table/Dresser),
where most items rendered as a near-invisible speck: `_add_pool_slot()`
used `cam.size = 1.2` and mesh rotation `(-20°, 45°, 0°)`, while
`InventoryHUD.gd` (the correct, working reference) uses `cam.size = 0.4`
and `(-45°, -45°, 0°)` — Storage's camera was 3x more zoomed out on top of
a completely different angle. Extracted `InventoryHUD.gd`'s preview code
into a new shared static utility, `scripts/ui/common/ItemPreviewKit.gd`
(`build_viewport()`, `set_item()`, `clear()`), and migrated both
`InventoryHUD.gd` and `StorageUI.gd` onto it — any future adjustment to
camera angle, zoom, lighting, or the mesh-fetch fallback now happens ONCE
and cascades to every consumer automatically, instead of needing to be
hand-copied per file. `ItemPreviewKit.CAM_SIZE_PER_PIXEL` scales `cam.size`
linearly with each consumer's preview pixel size (derived from
`InventoryHUD`'s proven 64px/0.4 ratio) so different-sized preview slots
(Inventory's 64px vs Storage's 96px) show items at the same real-world
scale rather than a different zoom level per file.

**Deliberately NOT adopted by `BuildModeHUD.gd`** — Build's construct/shop
previews layer a continuous hover-spin (a rotated pivot node in
`_process()`) on top of the same resting pose (`PREVIEW_ROTATION_DEFAULT`
already matches `ItemPreviewKit.ROTATION_DEFAULT` exactly, by design, and
always has). Folding Build onto the shared kit is a reasonable future
pass, scoped out of this one to avoid touching a working, more complex
implementation.

## Storage UI Icon + Row Label Redesign (Aug 2026)
Two changes to `StorageUI.gd`, both applying automatically to every
current and future storage type through the shared panel:
- **Icon buttons, not text glyphs.** The "↑" Carry, "↓" Drop, and "⊕" Add-
  to-inventory buttons were `Button.text` glyphs; replaced with real icon
  textures (`assets/icons/arrow_decorative_n.png`,
  `arrow_decorative_s.png`, `icon_plus.png` — the last is `icon_cross.png`
  pre-rotated 45° so its × reads as a +) via `Button.icon` +
  `expand_icon` + a shared `icon_max_width` cap (`ICON_MAX_WIDTH = 22`).
  All three source PNGs carry their own gray/silver shading and are NOT
  tinted via `modulate`, unlike `UIKit`'s white-mask `close_x.png`.
  **Contract change:** `get_ui_config()`'s `primary_button_icon` is no
  longer a literal glyph string — it must be one of `StorageUI`'s
  `_ICON_TEXTURES` keys (`"carry"` or `"drop"`). The secondary button's
  icon is fixed, not config-driven — identical for every storage type.
- **Row-label text removed entirely** ("Top shelf"/"Middle drawers"/etc,
  and the auto "Row N" fallback) — deleted the `Label` node creation in
  `_layout_panel()` along with the now-dead `ROW_LABEL_H` constant,
  `C_ROW_LABEL` color, and every storage object's `row_labels`
  config/export. `ROW_GAP` (the only remaining vertical gap between rows)
  reduced `22 → 4` (18px, half of `BTN_SIZE`) as a separate, deliberate
  tightening — not a side effect of removing the labels.
```

### 5e. `docs/systems/furniture-items/README.md` — small cross-reference note

Add this note near wherever `Shelving.gd`/`LightStorage.gd`/`Dresser.gd`/
`EndTable.gd`/`Basket.gd` are already documented (check first — if a
"Common edits" or changelog-style section already exists, add there
instead of creating a new one):

```markdown
## StorageUI Contract Config Updates (Aug 2026)
UI-thread pass touching `get_ui_config()` on every `StorageUI`-contract
object (`Basket.gd`, `Shelving.gd`, `LightStorage.gd` and its subclasses
`Dresser.gd`/`EndTable.gd`): `primary_button_icon` values changed from
literal glyph strings to icon-texture lookup keys (`"carry"`/`"drop"`),
and the `row_labels` config key/export was removed entirely (row-label
text no longer renders anywhere). See
`docs/systems/ui/README.md`'s "Storage UI Icon + Row Label Redesign" for
the full change — this note exists so a furniture-thread reader isn't
surprised by the config value change if they touch these files next.
```

### 5f. `HANDOVER.md` — new top section

Insert this as the new FIRST section of the file (above everything
currently there — never delete another thread's existing content):

```markdown
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
```
