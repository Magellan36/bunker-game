extends SceneTree

func _init():
	var names := ["idle_lib", "walk_lib", "run_lib", "idle_carry_lib", "walk_carry_lib", "run_carry_lib"]
	for n in names:
		var lib: AnimationLibrary = load("res://assets/models/player/anims/" + n + ".res")
		print("=== ", n, " ===")
		for an in lib.get_animation_list():
			var anim: Animation = lib.get_animation(an)
			print("anim=", an, " tracks=", anim.get_track_count(), " len=", anim.length)
			var pos_tracks := 0
			for t in anim.get_track_count():
				if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
					pos_tracks += 1
			print("  pos_tracks=", pos_tracks)
			for t in range(mini(3, anim.get_track_count())):
				print("  track", t, " path=", anim.track_get_path(t))
			for t in range(anim.get_track_count()):
				if "Hips" in anim.track_get_path(t).get_concatenated_subnames():
					print("  hips track ", t, " type=", anim.track_get_type(t), " path=", anim.track_get_path(t))
					break
	quit(0)