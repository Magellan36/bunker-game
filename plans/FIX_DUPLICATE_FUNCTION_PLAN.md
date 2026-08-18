# Fix: Duplicate `_refresh_submenu_previews()` in BuildModeHUD.gd

## Error
```
Error at (839, 6): Function "_refresh_submenu_previews" has the same name as a previously declared function.
```

## Root Cause
`scripts/ui/build/BuildModeHUD.gd` has **two** definitions of `_refresh_submenu_previews()`:

1. **Lines 787–824** — the OLD version (pre-Part D). Loads MeshLibrary meshes only, uses a hardcoded `rotation_degrees = Vector3(0.0, 35.0, 0.0)`, does not populate `_sub_mesh_instances`, and does not call `_refresh_shop_previews()`.
2. **Lines 839–885** — the NEW version added in Part D (shop preview + hover-spin work). Uses `PREVIEW_ROTATION_DEFAULT`, fills `_sub_mesh_instances[i]` (required by the hover-spin logic in `_update_preview_hover_spin()`), and calls `_refresh_shop_previews()` at the end to also populate shop item previews.

When Part D was added, the new function was appended instead of replacing the old one, leaving both in the file. GDScript does not allow two functions with the same name — hence the parser error at the second declaration (line 839).

The OLD version (787–824) is dead code: it's missing the shop-preview call and the `_sub_mesh_instances` population that the rest of the Part D system (hover-spin, `_on_submenu_draw` shop lookup) depends on. It must be deleted; the NEW version (839–885) is the one to keep.

## Fix
In `scripts/ui/build/BuildModeHUD.gd`, delete the entire OLD `_refresh_submenu_previews()` function block — every line from:

```gdscript
func _refresh_submenu_previews() -> void:
	## Load meshes from MeshLibrary into the SubViewports
	if gridmap == null:
		return
	var lib: MeshLibrary = gridmap.mesh_library
	if lib == null:
		return

	for i in CONSTRUCT_ITEMS.size():
		if i >= _sub_viewports.size():
			break
		var tile_id: int  = CONSTRUCT_ITEMS[i]["tile_id"]
		## Guard: only fetch mesh if this tile_id actually exists in the MeshLibrary.
		## Procedural tiles (Shelving, Bed, Generators, etc.) have no MeshLibrary entry.
		if not lib.get_item_list().has(tile_id):
			continue
		var mesh: Mesh    = lib.get_item_mesh(tile_id)
		if mesh == null:
			## Procedural tile (e.g. Shelving) — no MeshLibrary entry; skip 3D preview,
			## the submenu row still draws with name + price as text.
			continue

		var vp: SubViewport = _sub_viewports[i]
		# Remove any old mesh
		for child in vp.get_children():
			if child is MeshInstance3D:
				child.queue_free()

		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation_degrees = Vector3(0.0, 35.0, 0.0)
		vp.add_child(mi)

		# Center mesh in viewport
		if mi.mesh != null:
			var aabb: AABB = mi.mesh.get_aabb()
			mi.position = -aabb.get_center()
```

up to (but NOT including) the line right after it:
```gdscript
## Returns the row index (0-based) within the current submenu level, or -1.
func _get_submenu_item_at(pos: Vector2) -> int:
```

Do **not** touch anything from `## Returns the row index...` onward, and do **not** touch the second (kept) `_refresh_submenu_previews()` definition — leave it exactly as-is, including its trailing call to `_refresh_shop_previews()`.

## Verification
1. Run `bash tools/godot_check.sh <headless Godot 4.6.3 binary>` — must show no parse errors, specifically no "has the same name as a previously declared function" error.
2. Confirm only one `_refresh_submenu_previews` remains: `grep -n "func _refresh_submenu_previews" scripts/ui/build/BuildModeHUD.gd` should return exactly one line.
3. In-editor: open Build Mode → Construct submenu — 3D previews should still render (this exercises the surviving function).
