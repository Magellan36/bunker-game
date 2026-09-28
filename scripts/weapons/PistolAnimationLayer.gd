extends RefCounted
## Additive tree extension for the shared Adventurer controller. Human-authored
## directional clips; distance-driven timing and blend weights are runtime code.
const KEYS: Array[String] = ["walk", "walk_backward", "strafe_left", "strafe_right"]
const POINTS: Array[Vector2] = [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]
var model: Node3D
var tree: AnimationTree
var library: AnimationLibrary
var weight: float = 0.0
var phase: float = 0.0
var direction := Vector2(0, 1)
var grip: Marker3D
var _weapon: Node3D
var _hand: int = -1
var _grip_basis := Basis.IDENTITY

func install(owner_model: Node3D) -> void:
	model = owner_model
	tree = model._tree
	library = load("res://assets/models/player/pistol/pistol_%s_lib.res" % model._gender)
	tree.add_animation_library("pistol", library)
	var graph: AnimationNodeBlendTree = tree.tree_root
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"pistol/idle"
	graph.add_node("pistol_idle", idle)
	for pace: String in ["walk", "run"]:
		var space := AnimationNodeBlendSpace2D.new()
		space.sync = true
		for i: int in KEYS.size():
			var clip: String = _key(pace, i)
			var branch := AnimationNodeBlendTree.new()
			var animation := AnimationNodeAnimation.new()
			animation.animation = StringName("pistol/" + clip)
			branch.add_node("clip", animation)
			branch.add_node("seek", AnimationNodeTimeSeek.new())
			branch.connect_node("seek", 0, "clip")
			branch.connect_node("output", 0, "seek")
			space.add_blend_point(branch, POINTS[i], -1, str(i))
		graph.add_node("pistol_" + pace, space)
	graph.add_node("pistol_gait", AnimationNodeBlend2.new())
	graph.connect_node("pistol_gait", 0, "pistol_walk")
	graph.connect_node("pistol_gait", 1, "pistol_run")
	graph.add_node("pistol_loco", AnimationNodeBlend2.new())
	graph.connect_node("pistol_loco", 0, "pistol_idle")
	graph.connect_node("pistol_loco", 1, "pistol_gait")
	graph.add_node("pistol_mix", AnimationNodeBlend2.new())
	graph.disconnect_node("out", 0)
	graph.connect_node("pistol_mix", 0, "carry")
	graph.connect_node("pistol_mix", 1, "pistol_loco")
	graph.connect_node("out", 0, "pistol_mix")
	grip = Marker3D.new()
	grip.name = "WeaponGrip"
	model.add_child(grip)
	_hand = model._skeleton.find_bone("RightHand")
	_grip_basis = library.get_animation("idle").get_meta("grip_basis", Basis.IDENTITY)
	# SkeletonModifier3D may change the wrists after the AnimationTree advances.
	# Attach on the final skeleton update, so the gun never lags the hand.
	model._skeleton.skeleton_updated.connect(sync_grip)

func update(delta: float) -> void:
	var held: Node = null
	if model._player != null and model._player.has_method("get_held_item"):
		held = model._player.get_held_item()
	var active: bool = held != null and held.has_method("is_firearm") and held.is_firearm() and model._stage == 0
	if is_instance_valid(_weapon) and (_weapon != held or not active):
		_weapon.grip_anchor = null
	_weapon = held as Node3D if active else null
	if is_instance_valid(_weapon):
		_weapon.grip_anchor = grip
	weight = move_toward(weight, 1.0 if active else 0.0, delta * 8.0)
	tree.set("parameters/pistol_mix/blend_amount", weight)
	if weight <= 0.0:
		return
	var velocity: Vector3 = model._player.get_real_velocity().rotated(Vector3.UP, -model._visual_yaw)
	var desired := Vector2(velocity.x, -velocity.z)
	if desired.length_squared() > 0.01:
		direction = direction.lerp(desired.normalized(), 1.0 - exp(-16.0 * delta))
	var blend_direction: Vector2 = direction / maxf(absf(direction.x) + absf(direction.y), 0.001)
	var speed: float = model._speed
	var walk_speed: float = _weighted_native_speed("walk", blend_direction)
	var run_speed: float = _weighted_native_speed("run", blend_direction)
	var run_weight: float = clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var stride: float = lerpf(_weighted_stride("walk", blend_direction), _weighted_stride("run", blend_direction), run_weight)
	var leg_speed: float = speed + absf(model._yaw_rate) * 0.18
	phase = fposmod(phase + leg_speed * delta / maxf(stride, 0.1), 1.0)
	for pace: String in ["walk", "run"]:
		tree.set("parameters/pistol_%s/blend_position" % pace, blend_direction)
		for i: int in KEYS.size():
			var clip: Animation = library.get_animation(_key(pace, i))
			var time: float = fposmod(float(clip.get_meta("phase_offset", 0.0)) + phase * clip.length, clip.length)
			tree.set("parameters/pistol_%s/%d/seek/seek_request" % [pace, i], time)
	tree.set("parameters/pistol_gait/blend_amount", run_weight)
	tree.set("parameters/pistol_loco/blend_amount", model._move_w)

func sync_grip() -> void:
	if not is_instance_valid(_weapon) or not _weapon.is_held or _hand < 0:
		return
	var hand: Transform3D = model._skeleton.global_transform * model._skeleton.get_bone_global_pose(_hand)
	var basis: Basis = (hand.basis.orthonormalized() * _grip_basis).orthonormalized()
	# Wrist -> palm, then place the Webley's actual grip center in that palm.
	var palm: Vector3 = hand.origin + hand.basis.y * 0.055
	grip.global_transform = Transform3D(basis, palm - basis * Vector3(0, 0.025, 0.055))
	_weapon.sync_held_pose()

func _key(pace: String, i: int) -> String:
	return KEYS[i].replace("walk", pace) if i < 2 else KEYS[i]

func _weighted_stride(pace: String, dir: Vector2) -> float:
	var forward: Animation = library.get_animation(_key(pace, 0 if dir.y >= 0 else 1))
	var side: Animation = library.get_animation(_key(pace, 3 if dir.x >= 0 else 2))
	return (absf(dir.y) * float(forward.get_meta("stride_length", 1.0)) + absf(dir.x) * float(side.get_meta("stride_length", 1.0))) * model._scale

func _weighted_native_speed(pace: String, dir: Vector2) -> float:
	var forward: Animation = library.get_animation(_key(pace, 0 if dir.y >= 0 else 1))
	var side: Animation = library.get_animation(_key(pace, 3 if dir.x >= 0 else 2))
	return (absf(dir.y) * float(forward.get_meta("stride_length", 1.0)) / forward.length + absf(dir.x) * float(side.get_meta("stride_length", 1.0)) / side.length) * model._scale
