extends SceneTree
## Regression smoke for BuildModeHUD's render-target/model preview lifecycle.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud_script: GDScript = load("res://scripts/ui/build/BuildModeHUD.gd") as GDScript
	var hud: CanvasLayer = hud_script.new() as CanvasLayer
	root.add_child(hud)
	await process_frame
	var gridmap := GridMap.new()
	gridmap.mesh_library = MeshLibrary.new()
	root.add_child(gridmap)
	hud.set("gridmap", gridmap)

	## Sep 2026: PreviewStudio owns every preview. Build Mode keeps no
	## per-item render targets, entering/leaving builds nothing, and the
	## catalog renders once into cached textures, with one shared spinner.
	var studio: Node = root.get_node("PreviewStudio")
	_check(hud.find_children("*", "SubViewport", true, false).is_empty(),
		"build mode owns no per-item preview viewports")
	hud.call("register_previews")
	var first_key: String = hud.call("preview_key", 1, false)
	var shop_key: String = hud.call("preview_key", 20, true)
	_check(int(studio.call("pending_count")) > 0, "catalog previews queue on registration")
	hud.call("show_hud")
	hud.call("hide_hud")
	hud.call("show_hud")
	_check(hud.find_children("*", "SubViewport", true, false).is_empty(),
		"opening and closing build mode creates no render targets")
	await studio.call("wait_idle", 30.0)
	_check(bool(studio.call("is_idle")), "studio drains the catalog queue")
	## Render assertions need a GPU; the headless dummy renderer has none.
	var can_render: bool = DisplayServer.get_name() != "headless"
	_check(not can_render or studio.call("texture", shop_key) != null, "shop products get a cached static render")
	var tex: Texture2D = studio.call("texture", shop_key)
	_check(not can_render or tex != null and tex.get_width() == 256 and tex.get_image().has_mipmaps(),
		"cached renders are 256 px and mipmapped for downscaled cards")
	var live: Texture2D = studio.call("start_spin", shop_key) if can_render else null
	_check(not can_render or live is ViewportTexture and studio.call("spinning_key") == shop_key,
		"hover spin uses the single shared spinner")
	studio.call("stop_spin", shop_key)
	_check(String(studio.call("spinning_key")).is_empty(), "spinner releases on hover end")
	var spinners: int = 0
	for node: Node in studio.find_children("*", "SubViewport", true, false):
		if (node as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			spinners += 1
	_check(spinners == 0, "no preview renders every frame while nothing is hovered")
	hud.call("hide_hud")
	if first_key.is_empty():
		_check(false, "construct keys resolve")

	## Load after autoload registration; Shelving references NotificationManager
	## and command-line SceneTree scripts otherwise compile it too early.
	var shelf_script: GDScript = load("res://scripts/world/furniture/Shelving.gd") as GDScript
	var shelf: StaticBody3D = shelf_script.new() as StaticBody3D
	shelf.set("_is_preview_only", true)
	root.add_child(shelf)
	var shelf_renderers: Array[Node] = shelf.find_children("*", "MultiMeshInstance3D", false, false)
	var shelf_instance_count: int = 0
	for renderer_node: Node in shelf_renderers:
		var renderer := renderer_node as MultiMeshInstance3D
		if renderer != null and renderer.multimesh != null:
			shelf_instance_count += renderer.multimesh.instance_count
	_check(shelf_renderers.size() == 4 and shelf_instance_count == 73,
		"medium shelf preserves 73 visual pieces in four renderer nodes")
	_check(shelf.find_children("*", "CollisionShape3D", false, false).size() == 1,
		"shelf collision remains independent from render instancing")
	var preview_bounds: Dictionary = hud.call("_combined_local_aabb", shelf) as Dictionary
	var bounds: AABB = preview_bounds.get("aabb", AABB())
	_check(bool(preview_bounds.get("found_any", false))
		and bounds.size.y > 2.5,
		"catalog bounds include instanced shelf geometry")
	GhostModelBuilder.apply_ghost_tint(shelf, true)
	_check(shelf_renderers.all(func(node: Node) -> bool:
		return (node as MultiMeshInstance3D).material_override != null),
		"build ghost tint reaches instanced shelf renderers")

	hud.free()
	gridmap.free()
	shelf.free()
	if _failures == 0:
		print("BUILD_PREVIEW_LIFECYCLE_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BUILD_PREVIEW_LIFECYCLE_SMOKE_FAIL: %s" % message)
