extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	for i in 16:
		await process_frame
	for mi in _all(player):
		var nm := String(mi.name)
		if nm.to_lower().contains("superhero") or nm.begins_with("Outfit_"):
			var surf := 0
			var tot := 0
			if mi.mesh != null:
				surf = mi.mesh.get_surface_count()
				for s in surf:
					tot += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("[SURF] ", nm, " surfaces=", surf, " total_verts=", tot)
	player.free()
	quit()

func _all(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c))
	return out