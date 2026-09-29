extends "res://tools/anim_pipeline/bake_adventurer_anims.gd"
## bake_weapon_anims.gd — melee + pistol action clips for the Adventurer bodies.
##
## Same provenance rule as the parent tool: human-made source clips (the
## "Baseball Bat" set Brannon supplied, one per gender) are only re-expressed;
## timing adaptation happens at runtime in scripts/weapons/PistolAnimationLayer.gd.
## Writes assets/models/player/weapons/weapons_<gender>_lib.res and nothing else.
##
## Measured metadata (analysis numbers, not keys):
##   contact_time   swing/whip/punch: the moment of peak hand speed (either
##                  hand, so a lead-hand jab counts) = the strike.
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
	## Unarmed (Fists): guard loop, jab (lead hand), cross (rear hand).
	"punch_idle": "loop",
	"punch_jab": "action",
	"punch_cross": "action",
	## Hit reactions (played by AdventurerModelController.play_hit_reaction).
	"hit_head": "reaction",
	"hit_rib": "reaction",
	"hit_stomach": "reaction",
	"hit_aiming": "reaction",
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
		_analyse(rig, key, "action" if WEAPON_CLIPS[key] == "reaction" else WEAPON_CLIPS[key],
			"weapons/%s/%s.fbx" % [gender, key])
		if key == "melee_idle":
			_measure_grip(rig, library.get_animation(key))
		elif key.begins_with("punch_") and WEAPON_CLIPS[key] == "action":
			_measure_punch(rig, key, library.get_animation(key))
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
	var prev_left: Vector3
	for i: int in n + 1:
		var t: float = anim.length * float(i) / float(n)
		var sk: Skeleton3D = _pose(rig, key, t)
		var right: Vector3 = _bone_holder(rig, sk, "RightHand").origin
		var left: Vector3 = _bone_holder(rig, sk, "LeftHand").origin
		var step: float = maxf(right.distance_to(prev), left.distance_to(prev_left))
		speed.append(0.0 if i == 0 else step / (anim.length / float(n)))
		prev = right
		prev_left = left
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

## Punches: contact = the striking hand's furthest horizontal reach from the
## upper chest (peak speed lands mid-extension); windup = the last moment
## before it that the hand was still within 10% of its guard distance.
func _measure_punch(rig: Node3D, key: String, anim: Animation) -> void:
	var n: int = 90
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	for i: int in n + 1:
		var sk: Skeleton3D = _pose(rig, key, anim.length * float(i) / float(n))
		var chest: Vector3 = _bone_holder(rig, sk, "UpperChest").origin
		var dl: Vector3 = _bone_holder(rig, sk, "LeftHand").origin - chest
		var dr: Vector3 = _bone_holder(rig, sk, "RightHand").origin - chest
		left.append(Vector2(dl.x, dl.z).length())
		right.append(Vector2(dr.x, dr.z).length())
	## The striking hand is the one whose reach grows the most.
	var use_left: bool = _arr_max(left) - left[0] >= _arr_max(right) - right[0]
	var best_hand: String = "LeftHand" if use_left else "RightHand"
	var r: PackedFloat32Array = left if use_left else right
	var contact: int = 0
	for i: int in n + 1:
		if r[i] > r[contact]:
			contact = i
	var windup: int = 0
	for i: int in contact:
		if r[i] <= r[0] + 0.1 * (r[contact] - r[0]):
			windup = i
	var dt: float = anim.length / float(n)
	anim.set_meta("contact_time", contact * dt)
	anim.set_meta("windup_time", windup * dt)
	print("[weapons]   %-15s len=%.2fs windup=%.2fs contact=%.2fs (%s reach %.2f m)" % [
		key, anim.length, windup * dt, contact * dt, best_hand, r[contact]])

static func _arr_max(a: PackedFloat32Array) -> float:
	var m: float = -INF
	for v: float in a:
		m = maxf(m, v)
	return m

