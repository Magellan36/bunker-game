extends "res://tools/anim_pipeline/bake_adventurer_anims.gd"
## bake_weapon_anims.gd — melee + pistol action clips for the Adventurer bodies.
##
## Same provenance rule as the parent tool: human-made source clips (the
## "Baseball Bat" set Brannon supplied, one per gender) are only re-expressed;
## timing adaptation happens at runtime in scripts/weapons/PistolAnimationLayer.gd.
## Writes assets/models/player/weapons/weapons_<gender>_lib.res and nothing else.
##
## Measured metadata (analysis numbers, not keys):
##   contact_time   swing/whip: the moment of peak hand speed = the strike.
##                  shoot: the recoil kick (peak hand speed).
##   windup_time    swing/whip: the top of the backswing before contact (the
##                  slowest smoothed hand moment within 0.45 s of it). Runtime
##                  starts the clip there so a press strikes quickly.
##   melee_grip     melee_idle: weapon basis in RIGHT-hand space. Weapon -Z =
##                  from the lower (left) hand towards the upper (right) hand,
##                  i.e. along the handle towards the barrel of a two-hand grip.

const WEAPON_CLIPS: Dictionary = {
	"melee_idle": "loop",
	"melee_swing": "action",
	"melee_swing_alt": "action",
	"pistol_whip": "action",
	"pistol_shoot": "action",
}
const WINDUP_WINDOW: float = 0.45
var _weapon_frame: int = 0

func _process(_delta: float) -> bool:
	_weapon_frame += 1
	if _weapon_frame == 2:
		for gender: String in BODIES:
			_bake_weapons(gender)
		quit()
	return false

func _bake_weapons(gender: String) -> void:
	var body_scene: PackedScene = load(BODIES[gender])
	var body: Node3D = body_scene.instantiate()
	var skeleton: Skeleton3D = body.find_child("GeneralSkeleton", true, false)
	var library := AnimationLibrary.new()
	for key: String in WEAPON_CLIPS:
		var anim: Animation = _convert("res://assets/models/player/weapons/%s/%s.fbx" % [gender, key],
			skeleton, WEAPON_CLIPS[key] == "loop")
		if anim == null:
			quit(1)
			return
		library.add_animation(key, anim)
	body.free()
	var rig: Node3D = _make_rig(body_scene, library)
	for key: String in WEAPON_CLIPS:
		_analyse(rig, key, WEAPON_CLIPS[key], "weapons/%s/%s.fbx" % [gender, key])
		if key == "melee_idle":
			_measure_grip(rig, library.get_animation(key))
		elif WEAPON_CLIPS[key] == "action":
			_measure_strike(rig, key, library.get_animation(key))
	var path: String = "res://assets/models/player/weapons/weapons_%s_lib.res" % gender
	print("[weapons] saved %s: %s" % [path, ResourceSaver.save(library, path)])
	rig.queue_free()

func _measure_grip(rig: Node3D, anim: Animation) -> void:
	var sk: Skeleton3D = _pose(rig, "melee_idle", 0.0)
	var right: Transform3D = _bone_holder(rig, sk, "RightHand")
	var left: Vector3 = _bone_holder(rig, sk, "LeftHand").origin
	var along: Vector3 = (right.origin - left).normalized()
	var up: Vector3 = Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var weapon := Basis.looking_at(along, up)   ## -Z along the handle
	anim.set_meta("melee_grip", right.basis.orthonormalized().inverse() * weapon)
	print("[weapons]   grip: hands %.3f m apart, handle dir %s" % [right.origin.distance_to(left), along])

func _measure_strike(rig: Node3D, key: String, anim: Animation) -> void:
	var n: int = 90
	var speed := PackedFloat32Array()
	var prev: Vector3
	for i: int in n + 1:
		var t: float = anim.length * float(i) / float(n)
		var sk: Skeleton3D = _pose(rig, key, t)
		var hand: Vector3 = _bone_holder(rig, sk, "RightHand").origin
		speed.append(0.0 if i == 0 else hand.distance_to(prev) / (anim.length / float(n)))
		prev = hand
	var contact: int = 1
	for i: int in range(1, n + 1):
		if speed[i] > speed[contact]:
			contact = i
	## Top of the backswing / raise: the slowest (smoothed) hand moment in the
	## WINDUP_WINDOW seconds before contact.
	var dt: float = anim.length / float(n)
	var windup: int = contact
	var best: float = INF
	for i: int in range(maxi(2, contact - int(WINDUP_WINDOW / dt)), contact - 1):
		var smooth: float = (speed[i - 1] + speed[i] + speed[mini(i + 1, n)]) / 3.0
		if smooth < best:
			best = smooth
			windup = i
	anim.set_meta("contact_time", contact * dt)
	anim.set_meta("windup_time", windup * dt)
	print("[weapons]   %-15s len=%.2fs windup=%.2fs contact=%.2fs (peak hand %.1f m/s)" % [
		key, anim.length, windup * dt, contact * dt, speed[contact]])
