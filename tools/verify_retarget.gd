extends SceneTree

func _init():
	check_clip("idle")
	check_clip("walk")
	check_clip("run")
	check_clip("idle_carry")
	check_clip("walk_carry")
	check_clip("run_carry")
	check_model("Superhero_Male_FullBody")
	check_model("Superhero_Female_FullBody")
	quit(0)

func dest_scn(import_path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return ""
	var dests: Array = cfg.get_value("deps", "dest_files", [])
	if dests.is_empty():
		return ""
	return String(dests[0])

func check_clip(name: String):
	var scn := dest_scn("res://assets/models/player/" + name + ".fbx.import")
	if scn.is_empty():
		print(name, " NO SCN")
		return
	var ps: PackedScene = load(scn)
	var root := ps.instantiate()
	print("=== ", name, " (", scn.get_file(), ") ===")
	var sk := _find_skeleton(root)
	if sk:
		var first8 := []
		for i in range(mini(8, sk.get_bone_count())):
			first8.append(sk.get_bone_name(i))
		print("skeleton=", sk.name, " bones=", sk.get_bone_count(), " first8=", first8)
	var anims := root.find_children("*", "AnimationPlayer", true, false)
	for a in anims:
		for lib_name in a.get_animation_list():
			var anim: Animation = a.get_animation(lib_name)
			print("anim=", lib_name, " tracks=", anim.get_track_count())
			for t in range(mini(4, anim.get_track_count())):
				print("  track", t, " path=", anim.track_get_path(t))
	root.free()

func check_model(name: String):
	var scn := dest_scn("res://assets/models/player/" + name + ".gltf.import")
	if scn.is_empty():
		print(name, " NO SCN")
		return
	var ps: PackedScene = load(scn)
	var root := ps.instantiate()
	print("=== ", name, " (", scn.get_file(), ") ===")
	_dump_node(root, 0)
	var sk := _find_skeleton(root)
	if sk:
		var first8 := []
		for i in range(mini(8, sk.get_bone_count())):
			first8.append(sk.get_bone_name(i))
		print("skeleton=", sk.name, " bones=", sk.get_bone_count(), " first8=", first8)
	root.free()

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _dump_node(n: Node, depth: int):
	var extra := ""
	if n is Skeleton3D:
		extra = " [Skeleton3D]"
	if n is MeshInstance3D:
		extra = " [MeshInstance3D]"
	print(" ".repeat(depth * 2), n.get_name(), " :: ", n.get_class(), extra)
	for c in n.get_children():
		_dump_node(c, depth + 1)