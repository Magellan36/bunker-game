extends SceneTree

func _init():
	var pm := Node3D.new()
	pm.name = "PlayerModel"
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	pm.add_child(ap)
	for lib_name in ["idle_lib", "walk_lib", "run_lib", "idle_carry_lib", "walk_carry_lib", "run_carry_lib"]:
		ap.add_animation_library(lib_name, load("res://assets/models/player/anims/" + lib_name + ".res"))
	var body_scene: PackedScene = load("res://assets/models/player/Superhero_Male_FullBody.gltf")
	var body: Node3D = body_scene.instantiate()
	body.name = "MaleModel"
	pm.add_child(body)
	root.add_child(pm)

	var sk: Skeleton3D = null
	for n in body.find_children("*", "Skeleton3D", true, false):
		sk = n as Skeleton3D
		break
	print("SKELETON=", sk.name, " unique=", sk.is_unique_name_in_owner(), " bones=", sk.get_bone_count())
	print("BONES0_3=", [sk.get_bone_name(0), sk.get_bone_name(1), sk.get_bone_name(2), sk.get_bone_name(3)])

	var anim: Animation = ap.get_animation("idle_lib/idle")
	var unresolved := 0
	for t in anim.get_track_count():
		var p: NodePath = anim.track_get_path(t)
		if pm.get_node_or_null(NodePath(str(p.get_concatenated_names()))) == null:
			unresolved += 1
	print("UNRESOLVED_TRACK_NODES=", unresolved, " tracks=", anim.get_track_count())

	var h0 := sk.get_bone_global_pose(sk.find_bone("Hips"))
	var l0 := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg"))
	ap.play("idle_lib/idle")
	for f in range(60):
		await process_frame
	var l_a := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg"))
	for f in range(60):
		await process_frame
	var l_b := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg"))
	print("HIPS_POSE_DELTA=", h0.origin.distance_to(sk.get_bone_global_pose(sk.find_bone("Hips")).origin))
	print("IDLE_LEG_ROT_1s_SWEEP=", l_a.basis.get_euler().distance_to(l_b.basis.get_euler()))
	print("IS_PLAYING=", ap.is_playing())

	ap.play("run_lib/run")
	for f in range(30):
		await process_frame
	var l2 := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg"))
	print("RUN_LEG_ROT_DELTA=", l0.basis.get_euler().distance_to(l2.basis.get_euler()))

	var female: Node3D = (load("res://assets/models/player/Superhero_Female_FullBody.gltf") as PackedScene).instantiate()
	female.name = "FemaleBody"
	pm.add_child(female)
	var fsk: Skeleton3D = null
	for n in female.find_children("*", "Skeleton3D", true, false):
		fsk = n as Skeleton3D
		break
	print("FEMALE_SKELETON=", fsk.name, " unique=", fsk.is_unique_name_in_owner(), " bones=", fsk.get_bone_count())
	quit(0)