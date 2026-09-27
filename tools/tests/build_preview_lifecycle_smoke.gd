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

	var construct_viewports: Array = hud.get("_sub_viewports") as Array
	var shop_viewports: Array = hud.get("_shop_viewports") as Array
	_check(not construct_viewports.is_empty() and not shop_viewports.is_empty(),
		"preview pools are created")
	_check(_all_viewports_match(construct_viewports + shop_viewports, Vector2i(2, 2),
		SubViewport.UPDATE_DISABLED), "closed pools start hibernated")

	hud.call("show_hud")
	_check(_all_viewports_match(construct_viewports + shop_viewports, Vector2i(192, 192),
		SubViewport.UPDATE_DISABLED), "opening restores render-target dimensions")
	hud.call("hide_hud")
	_check(_all_viewports_match(construct_viewports + shop_viewports, Vector2i(2, 2),
		SubViewport.UPDATE_DISABLED), "closing releases render targets")

	## Re-enter before the deferred close cleanup runs. This models fast
	## controller tab switching and must leave the newly-opened pool active.
	hud.call("show_hud")
	_check(bool(hud.get("_preview_pool_active")), "immediate reopen survives deferred cleanup")
	_check(_all_viewports_match(construct_viewports + shop_viewports, Vector2i(192, 192),
		SubViewport.UPDATE_DISABLED), "immediate reopen keeps active dimensions")
	await process_frame
	for _frame: int in 180:
		if bool(hud.get("_submenu_previews_ready")):
			break
		await process_frame
	_check(bool(hud.get("_submenu_previews_ready")),
		"staggered preview population completes after cancellation and reopen")
	hud.call("hide_hud")
	_check(not bool(hud.get("_preview_build_in_progress")),
		"closing leaves no active preview builder")

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


func _all_viewports_match(viewports: Array, expected_size: Vector2i, expected_mode: int) -> bool:
	for viewport_value: Variant in viewports:
		var viewport: SubViewport = viewport_value as SubViewport
		if not is_instance_valid(viewport) or viewport.size != expected_size \
				or viewport.render_target_update_mode != expected_mode:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BUILD_PREVIEW_LIFECYCLE_SMOKE_FAIL: %s" % message)
