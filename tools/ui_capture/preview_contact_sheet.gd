extends SceneTree
## Renders every PreviewStudio catalog entry (build + shop) to PNGs so poses
## can be reviewed in one sheet. Usage (isolate user data first):
##   godot --path . --windowed --script res://tools/ui_capture/preview_contact_sheet.gd -- /tmp/sheet
## Writes <out>/<key>.png and <out>/index.txt ("key<TAB>name").

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/preview_sheet"
	DirAccess.make_dir_recursive_absolute(out)
	var world: Node = (load("res://scenes/world/MainWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	if world.has_signal("startup_ready"):
		await world.startup_ready
	var studio: Node = root.get_node("PreviewStudio")
	await studio.wait_idle(20.0)
	var hud: Node = world.get("_build_hud")
	var index: PackedStringArray = []
	for item: Dictionary in hud.get("CONSTRUCT_ITEMS"):
		var key: String = hud.call("preview_key", int(item["tile_id"]), false)
		_save(studio, key, out)
		index.append("%s\t%s" % [key, item["name"]])
	for shop_id: int in (hud.get("PREVIEW_SOURCES") as Dictionary).keys():
		var key: String = hud.call("preview_key", shop_id, true)
		_save(studio, key, out)
		var helper: GDScript = load("res://scripts/world/build/FarmingShopHelper.gd")
		var info: Dictionary = (helper.get_script_constant_map()["SHOP_ITEM_INFO"] as Dictionary).get(shop_id, {})
		index.append("%s\t%s" % [key, info.get("name", key)])
	var f := FileAccess.open(out.path_join("index.txt"), FileAccess.WRITE)
	f.store_string("\n".join(index))
	f.close()
	print("CONTACT_SHEET %d entries" % index.size())
	quit()


func _save(studio: Node, key: String, out: String) -> void:
	var tex: Texture2D = studio.call("texture", key)
	if tex != null:
		tex.get_image().save_png(out.path_join(key.replace(":", "_") + ".png"))
