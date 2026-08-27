extends SceneTree
## build_sit_female_curves.gd — Aug 2026.
## Samples the female stand_to_sit / sit_to_stand clips' vertical descent
## (the CharacterArmature ROOT position track) at 21 points and prints the
## normalized curve (standing=0, seated=1 for sit-down; seated=0, standing=1
## for stand-up) — the gender-specific pacing for _lerp_sit_position.

const F_STS_SCN := "res://.godot/imported/stand_to_sit_female.fbx-5e68536cbe7d5ab19ccd70b8ec054f9e.scn"
const F_S2S_SCN := "res://.godot/imported/sit_to_stand_female.fbx-5dc4c4e5d47efb478c0b1bd5a200cc56.scn"

func _sample_root_y(anim: Animation, t: float) -> float:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p: NodePath = anim.track_get_path(i)
		if p.get_subname_count() != 0:
			continue
		var kc: int = anim.track_get_key_count(i)
		if kc == 0:
			continue
		var prev_time: float = -INF
		var prev_val: Vector3 = Vector3.ZERO
		for k in kc:
			var kt: float = anim.track_get_key_time(i, k)
			var kv: Vector3 = anim.track_get_key_value(i, k)
			if kt >= t:
				if prev_time == -INF:
					return kv.y
				var f: float = (t - prev_time) / max(kt - prev_time, 0.0001)
				return lerpf(prev_val.y, kv.y, f)
			prev_time = kt
			prev_val = kv
		return prev_val.y
	return 0.0

func _init() -> void:
	for entry in [
		{"scn": F_STS_SCN, "down": true, "label": "FEMALE sit_down"},
		{"scn": F_S2S_SCN, "down": false, "label": "FEMALE stand_up"},
	]:
		var scene: PackedScene = load(entry["scn"])
		var inst: Node3D = scene.instantiate() as Node3D
		root.add_child(inst)
		var ap: AnimationPlayer = null
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			ap = n as AnimationPlayer
			break
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
		var samples: Array = []
		for i in 21:
			var t: float = float(i) / 20.0 * anim.length
			samples.append(_sample_root_y(anim, t))
		var lo: float = samples.min()
		var hi: float = samples.max()
		var norm: Array = []
		for y in samples:
			var v: float = (hi - y) / max(hi - lo, 0.0001) if entry["down"] else (y - lo) / max(hi - lo, 0.0001)
			norm.append(snappedf(v, 0.001))
		print(entry["label"], "  lo=", snappedf(lo, 0.001), " hi=", snappedf(hi, 0.001))
		print("   ", norm)
	quit()