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
		_analyze(player, "frame16")
		for i in 10:
			await process_frame
		_analyze(player, "frame26")
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

func _analyze(player: Node, tag: String) -> void:
	var skel := _find_skeleton(player)
	var outfit_verts: Array[PackedVector3Array] = []
	var body_verts: PackedVector3Array = PackedVector3Array()
	for mi in _all(player):
		if mi.name.begins_with("Outfit_"):
			outfit_verts.append(_deform(mi, skel))
		elif String(mi.name).to_lower().contains("superhero"):
			body_verts = _deform(mi, skel)
	var op := _profile(outfit_verts)
	var bp := _profile([body_verts])
	var worst := 0.0
	var pokes := 0
	for band in bp.keys():
		if not op.has(band):
			continue
		var gap: float = bp[band] - op[band]
		if gap > 0.012:
			pokes += 1
			worst = maxf(worst, gap)
	print("[RESULT] ", tag, " body_verts=", body_verts.size(), " pokes=", pokes, " worst=", worst)
	for band in bp.keys():
		if not op.has(band):
			continue
		var gap: float = bp[band] - op[band]
		if gap > 0.012:
			print("   y=", band * 0.02, " body_r=", bp[band], " outfit_r=", op[band], " gap=", gap)

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

func _profile(all_verts: Array[PackedVector3Array]) -> Dictionary:
	var prof := {}
	for verts in all_verts:
		for v in verts:
			var band := int(v.y / 0.02)
			var r: float = sqrt(v.x * v.x + v.z * v.z)
			if not prof.has(band):
				prof[band] = r
			else:
				prof[band] = maxf(prof[band], r)
	return prof