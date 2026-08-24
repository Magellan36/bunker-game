extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for g in ["male", "female"]:
		var ccd: Node = root.get_node_or_null("CharacterCreationData")
		if ccd != null:
			ccd.set("gender", g)
		var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
		root.add_child(player)
		for i in 16:
			await process_frame
		var skel := _find_skeleton(player)
		var body_verts: PackedVector3Array = PackedVector3Array()
		for mi in _all(player):
			if String(mi.name).to_lower().contains("superhero"):
				body_verts = _deform(mi, skel)
		var bands := {}
		for v in body_verts:
			var band := int(v.y / 0.02)
			var r: float = sqrt(v.x * v.x + v.z * v.z)
			if not bands.has(band):
				bands[band] = [1, r, r]
			else:
				var e: Array = bands[band]
				e[0] += 1
				e[1] = minf(e[1], r)
				e[2] = maxf(e[2], r)
		print("[BARE] ", g, " body_verts=", body_verts.size(), " occupied_bands=", bands.size())
		var sorted_bands := bands.keys()
		sorted_bands.sort()
		var head_ok := false
		var hand_ok := false
		for band in sorted_bands:
			var y: float = band * 0.02
			var e: Array = bands[band]
			print("   y=", y, " count=", e[0], " r=", e[1], "..", e[2])
			if y >= 1.55 and y <= 1.70:
				head_ok = true
			if y >= 0.5 and y <= 0.95 and e[2] > 0.19:
				hand_ok = true
		print("[BARE] ", g, " head_present=", head_ok, " hand_side_present=", hand_ok)
		player.free()
	quit()

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

func _all(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c))
	return out

func _deform(mi: MeshInstance3D, skel: Skeleton3D) -> PackedVector3Array:
	var name_to_skel := {}
	for i in skel.get_bone_count():
		name_to_skel[skel.get_bone_name(i)] = i
	var bind_tf := {}
	for b in mi.skin.get_bind_count():
		var bn: String = mi.skin.get_bind_name(b)
		if bn == "":
			continue
		var idx: int = name_to_skel.get(bn, -1)
		if idx == -1:
			continue
		bind_tf[b] = skel.get_bone_global_pose(idx) * mi.skin.get_bind_pose(b)
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		for vi in verts.size():
			var acc := Vector3.ZERO
			var wsum := 0.0
			for w in 4:
				var bj: int = joints[vi * 4 + w]
				var bw: float = weights[vi * 4 + w]
				if bw <= 0.0 or not bind_tf.has(bj):
					continue
				acc += bind_tf[bj] * verts[vi] * bw
				wsum += bw
			out.append(acc / wsum if wsum > 0.0 else verts[vi])
	return out