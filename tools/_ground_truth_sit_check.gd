extends SceneTree
## Ground-truth diagnostic (3rd pass) — bypasses AdventurerModelController.gd
## entirely (it needs the CharacterCreationData autoload, unavailable in
## bare --script mode). Instead: load the Adventurer_Male body scene
## directly, manually build an AnimationPlayer wired to sit_lib.res (same
## library the real controller uses), seek to the seated pose, and read
## the ACTUAL Skeleton3D Hip bone world position — real Godot-side ground
## truth, no Blender-space assumptions.

func _init():
	var log_lines: Array[String] = []

	# Chair is at world origin, unrotated — get_seat_transform() reduces to
	# Vector3(0, SEAT_Y, 0) exactly in this configuration regardless of the
	# is_inside_tree() warning (identity global_transform either way).
	var chair := StaticBody3D.new()
	chair.set_script(load("res://scripts/world/furniture/Chair.gd"))
	var seat_y: float = chair.SEAT_Y
	log_lines.append("SEAT_Y=%.4f" % seat_y)

	# Load the body directly — same scene AdventurerModelController.gd
	# instantiates, same 180-degree flip and "MaleModel" rename it applies.
	var body_scene: PackedScene = load("res://assets/models/player/adventurer/Adventurer_Female.fbx")
	var body: Node3D = body_scene.instantiate()
	body.name = "MaleModel"
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	root.add_child(body)

	# Same floor-align offset the real controller applies (FALLBACK_CAPSULE_HEIGHT = 2.0)
	var capsule_height := 2.0
	var model_floor_offset_y := -(capsule_height * 0.5)
	body.position.y = model_floor_offset_y

	var skeleton: Node = _find_first(body, "Skeleton3D")
	if skeleton == null:
		log_lines.append("FAILED: no Skeleton3D found under body")
		_write_and_quit(log_lines)
		return

	# Load and attach the sit_lib animation library directly
	var sit_lib: AnimationLibrary = load("res://assets/models/player/anims/sit_lib.res")
	var anim_player := AnimationPlayer.new()
	body.add_child(anim_player)
	anim_player.add_animation_library("sit_lib", sit_lib)

	if not anim_player.has_animation("sit_lib/sit"):
		log_lines.append("FAILED: sit_lib/sit not found, has=%s" % str(anim_player.get_animation_list()))
		_write_and_quit(log_lines)
		return

	anim_player.current_animation = "sit_lib/sit"
	var anim: Animation = anim_player.get_animation("sit_lib/sit")
	anim_player.seek(anim.length * 0.5, true)

	var hip_idx: int = skeleton.find_bone("Hips")
	if hip_idx == -1:
		log_lines.append("FAILED: Hips bone not found, bones=%s" % str(_all_bone_names(skeleton)))
		_write_and_quit(log_lines)
		return

	var hip_global_pose: Transform3D = skeleton.get_bone_global_pose(hip_idx)
	var hip_world: Vector3 = skeleton.global_transform * hip_global_pose.origin

	# Simulate the REAL game's floor anchor: player.global_position.y stays
	# at floor level (y=0 here, matching how MainWorld never touches Y
	# during the sit sequence) for the whole sequence.
	var player_floor_y := 0.0
	var final_hip_world_y: float = player_floor_y + hip_world.y

	log_lines.append("body.position (floor-align offset)=%s" % str(body.position))
	log_lines.append("raw_hip_world_position=%s" % str(hip_world))
	log_lines.append("final_hip_world_y (player_floor_y=0 + hip_world.y)=%.4f" % final_hip_world_y)
	log_lines.append("SEAT_Y=%.4f" % seat_y)
	log_lines.append("DISCREPANCY (final_hip_world_y - SEAT_Y)=%.4f  <- positive means hip renders ABOVE the seat surface, by this many meters" % (final_hip_world_y - seat_y))

	_write_and_quit(log_lines)

func _write_and_quit(log_lines: Array[String]) -> void:
	var f := FileAccess.open("res://_dup_diag.log", FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()
	print("\n".join(log_lines))
	quit(0)

func _find_first(node: Node, class_name_str: String) -> Node:
	for child in node.get_children():
		if child.get_class() == class_name_str:
			return child
		var found = _find_first(child, class_name_str)
		if found != null:
			return found
	return null

func _all_bone_names(skeleton: Node) -> Array:
	var names: Array = []
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return names
