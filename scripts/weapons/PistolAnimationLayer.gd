extends RefCounted
## Weapon animation layer for the shared Adventurer controller (player only).
## Owned by the animation session (docs/systems/player-model/ANIMATIONS.md
## "Weapon layer"; contract in docs/systems/weapons/HANDOFF.md).
##
##   pistol locomotion  human-authored directional pistol clips, distance-driven
##                      timing (below, unchanged from the weapons session).
##   melee hold         "Baseball Idle" while a bat/crowbar/pipe/hatchet is held:
##                      full body standing still, upper body only while moving.
##   strikes            on WeaponItem.attack_started: "Baseball Swing" (variant 0)
##                      or "Baseball Swing adjust" (variant 1) for melee, "Pistol
##                      Whip" for an empty revolver, "Shooting Pistol" per shot.
##                      Swings start at the clip's measured top of backswing and
##                      play at the rate that lands its measured contact frame on
##                      the weapon's strike_delay, so the hit and the animation
##                      always agree. All clips human-made; timing is code.
##   fists              Fists (a child of the character named "Fists", same API
##                      as WeaponItem): "Punching Idle" guard while aiming,
##                      "Punch Jab"/"Punch Cross" on attack_started("punch", 0/1).
##   hit reactions      play_hit_reaction(ctx): head/rib/stomach hit by the hit
##                      height, or "Aiming Pistol Hit" while aiming a firearm.
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

## Melee + strike state.
const MELEE_KINDS: Array[String] = ["bat", "crowbar", "pipe", "hatchet"]
const STRIKE_FADE_IN: float = 0.07
const STRIKE_FADE_OUT: float = 0.25
const MELEE_FADE_RATE: float = 6.0
## Shots: play the recoil around the measured kick, briefly.
const SHOT_LEAD: float = 0.08
const SHOT_TAIL: float = 0.3
## Swing playback is clamped to a believable range of the authored speed.
const STRIKE_RATE_RANGE: Vector2 = Vector2(0.7, 2.2)
var weapons: AnimationLibrary
var _melee_basis := Basis.IDENTITY
var _melee_w: float = 0.0
var _melee_time: float = 0.0
var _strike_clip: StringName = &""
var _strike_time: float = 0.0
var _strike_end: float = 0.0
var _strike_rate: float = 1.0
var _strike_w: float = 0.0
var _strike_upper_only: bool = false
var _melee: bool = false
var _hold_clip: StringName = &"melee_idle"
var _signal_weapon: Node = null

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
	_install_melee(graph)
	graph.connect_node("out", 0, "strike_upper")
	grip = Marker3D.new()
	grip.name = "WeaponGrip"
	model.add_child(grip)
	_hand = model._skeleton.find_bone("RightHand")
	_grip_basis = library.get_animation("idle").get_meta("grip_basis", Basis.IDENTITY)
	# SkeletonModifier3D may change the wrists after the AnimationTree advances.
	# Attach on the final skeleton update, so the gun never lags the hand.
	model._skeleton.skeleton_updated.connect(sync_grip)

## pistol_mix → melee_full → melee_upper → strike_full → strike_upper → out.
## "full" blends every bone (never the armature root, so the body can't drift
## off the capsule); "upper" only spine, neck, head, arms and hands. Each
## overlay has its own seek-driven clip node so time never advances twice.
func _install_melee(graph: AnimationNodeBlendTree) -> void:
	weapons = load("res://assets/models/player/weapons/weapons_%s_lib.res" % model._gender)
	tree.add_animation_library("weapons", weapons)
	_melee_basis = weapons.get_animation("melee_idle").get_meta("melee_grip", Basis.IDENTITY)
	var previous: String = "pistol_mix"
	for layer: String in ["melee_full", "melee_upper", "strike_full", "strike_upper"]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = &"weapons/melee_idle"
		graph.add_node(layer + "_clip", clip)
		graph.add_node(layer + "_seek", AnimationNodeTimeSeek.new())
		graph.connect_node(layer + "_seek", 0, layer + "_clip")
		var blend := AnimationNodeBlend2.new()
		blend.filter_enabled = true
		for i: int in model._skeleton.get_bone_count():
			var bone: String = model._skeleton.get_bone_name(i)
			if layer.ends_with("_full") or _is_upper_bone(bone):
				blend.set_filter_path(NodePath("MaleModel/%GeneralSkeleton:" + bone), true)
		graph.add_node(layer, blend)
		graph.connect_node(layer, 0, previous)
		graph.connect_node(layer, 1, layer + "_seek")
		previous = layer

static func _is_upper_bone(bone: String) -> bool:
	if bone == "Hips" or bone == "Root":
		return false
	for leg: String in ["UpperLeg", "LowerLeg", "Foot", "Toes"]:
		if bone.contains(leg):
			return false
	return true

func update(delta: float) -> void:
	var held: Node = null
	if model._player != null and model._player.has_method("get_held_item"):
		held = model._player.get_held_item()
	var free: bool = model._stage == 0
	var kind: String = str(held.get("weapon_kind")) if held != null and "weapon_kind" in held else ""
	var active: bool = held != null and held.has_method("is_firearm") and held.is_firearm() and free
	var melee: bool = free and MELEE_KINDS.has(kind)
	var anchored: bool = active or melee
	if is_instance_valid(_weapon) and (_weapon != held or not anchored):
		_weapon.grip_anchor = null
	_weapon = held as Node3D if anchored else null
	_melee = melee
	if is_instance_valid(_weapon):
		_weapon.grip_anchor = grip
	## Empty hands: the character's Fists node (player or NPC) is the weapon.
	var fists: Node = model._player.get_node_or_null("Fists") if held == null else null
	var guard: bool = free and fists != null and bool(fists.get("aiming"))
	_watch_attacks(held if held != null and held.has_signal("attack_started") else fists)
	_set_hold_clip(&"punch_idle" if guard else &"melee_idle")
	_update_melee(delta, melee or guard, free)
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

## Connects to whichever weapon is in hand (and only that one).
func _watch_attacks(weapon: Node) -> void:
	if weapon == _signal_weapon:
		return
	if is_instance_valid(_signal_weapon) and _signal_weapon.attack_started.is_connected(_on_attack_started):
		_signal_weapon.attack_started.disconnect(_on_attack_started)
	_signal_weapon = weapon
	if weapon != null:
		weapon.attack_started.connect(_on_attack_started)

func _on_attack_started(kind: String, variant: int) -> void:
	if model._stage != 0:
		return
	var delay: float = float(_signal_weapon.get("strike_delay")) if is_instance_valid(_signal_weapon) \
		and "strike_delay" in _signal_weapon else 0.2
	match kind:
		"punch":
			var cross: bool = variant == 1
			var punch_delay: float = float(_signal_weapon.get("cross_strike_delay" if cross else "jab_strike_delay")) \
				if is_instance_valid(_signal_weapon) else 0.2
			_start_timed_strike(&"punch_cross" if cross else &"punch_jab", punch_delay)
		"revolver":
			var shot: Animation = weapons.get_animation("pistol_shoot")
			var kick: float = float(shot.get_meta("contact_time", 0.3))
			_start_strike(&"pistol_shoot", maxf(0.0, kick - SHOT_LEAD), 1.0, minf(shot.length, kick + SHOT_TAIL))
			## Rapid shots: recoil in the arms/torso only, legs stay on the
			## pistol locomotion instead of flicking into the clip's stance.
			_strike_upper_only = true
		"pistol_whip":
			_start_timed_strike(&"pistol_whip", delay)
		_:
			if MELEE_KINDS.has(kind):
				_start_timed_strike(&"melee_swing_alt" if variant == 1 else &"melee_swing", delay)

## Starts at the top of the backswing; the rate puts contact on `delay`.
func _start_timed_strike(clip: StringName, delay: float) -> void:
	var anim: Animation = weapons.get_animation(clip)
	var windup: float = float(anim.get_meta("windup_time", 0.0))
	var contact: float = float(anim.get_meta("contact_time", anim.length * 0.5))
	var rate: float = clampf((contact - windup) / maxf(delay, 0.01), STRIKE_RATE_RANGE.x, STRIKE_RATE_RANGE.y)
	_start_strike(clip, windup, rate, anim.length)

func _start_strike(clip: StringName, from: float, rate: float, until: float) -> void:
	_strike_clip = clip
	_strike_time = from
	_strike_rate = rate
	_strike_end = until
	_strike_upper_only = false
	var graph: AnimationNodeBlendTree = tree.tree_root
	for layer: String in ["strike_full", "strike_upper"]:
		(graph.get_node(layer + "_clip") as AnimationNodeAnimation).animation = StringName("weapons/" + clip)

## Hit reaction chosen from the hit height on this body (or the aiming
## flinch while holding a firearm up). Called via
## AdventurerModelController.play_hit_reaction(ctx).
func play_hit_reaction(ctx: Dictionary) -> void:
	if model._stage != 0:
		return
	var held: Node = model._player.get_held_item() if model._player.has_method("get_held_item") else null
	var clip: StringName = &"hit_stomach"
	if held != null and held.has_method("is_firearm") and held.is_firearm() and bool(held.get("aiming")):
		clip = &"hit_aiming"
	else:
		var sk: Skeleton3D = model._skeleton
		var y: float = (ctx.get("position", model._visual.global_position) as Vector3).y
		var neck: float = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Neck")).origin).y
		var chest: float = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Chest")).origin).y
		if y >= neck - 0.05:
			clip = &"hit_head"
		elif y >= chest:
			clip = &"hit_rib"
	_start_strike(clip, 0.0, 1.0, weapons.get_animation(clip).length)

func _set_hold_clip(clip: StringName) -> void:
	if clip == _hold_clip:
		return
	_hold_clip = clip
	var graph: AnimationNodeBlendTree = tree.tree_root
	for layer: String in ["melee_full", "melee_upper"]:
		(graph.get_node(layer + "_clip") as AnimationNodeAnimation).animation = StringName("weapons/" + clip)

func _update_melee(delta: float, melee: bool, free: bool) -> void:
	var idle: Animation = weapons.get_animation(_hold_clip)
	_melee_time = fposmod(_melee_time + delta, idle.length)
	_melee_w = move_toward(_melee_w, 1.0 if melee else 0.0, delta * MELEE_FADE_RATE)
	var moving: float = clampf(model._move_w, 0.0, 1.0)
	## Strike envelope: quick in, out over the clip's last STRIKE_FADE_OUT.
	var striking: bool = _strike_clip != &"" and free
	if striking:
		_strike_time += delta * _strike_rate
		var left: float = (_strike_end - _strike_time) / maxf(_strike_rate, 0.01)
		var target: float = clampf(left / STRIKE_FADE_OUT, 0.0, 1.0)
		_strike_w = minf(move_toward(_strike_w, 1.0, delta / STRIKE_FADE_IN), target)
		if _strike_time >= _strike_end:
			_strike_clip = &""
	else:
		_strike_w = move_toward(_strike_w, 0.0, delta / STRIKE_FADE_OUT)
	for layer: String in ["melee_full", "melee_upper"]:
		tree.set("parameters/%s_seek/seek_request" % layer, _melee_time)
	tree.set("parameters/melee_full/blend_amount", _melee_w * (1.0 - moving))
	tree.set("parameters/melee_upper/blend_amount", _melee_w * moving)
	var strike_t: float = minf(_strike_time, _strike_end)
	for layer: String in ["strike_full", "strike_upper"]:
		tree.set("parameters/%s_seek/seek_request" % layer, strike_t)
	var upper: float = 1.0 if _strike_upper_only else moving
	tree.set("parameters/strike_full/blend_amount", _strike_w * (1.0 - upper))
	tree.set("parameters/strike_upper/blend_amount", _strike_w * upper)

func sync_grip() -> void:
	if not is_instance_valid(_weapon) or not _weapon.is_held or _hand < 0:
		return
	var hand: Transform3D = model._skeleton.global_transform * model._skeleton.get_bone_global_pose(_hand)
	if _melee:
		## Two-hand handle grip measured from Baseball Idle: the weapon origin
		## (its grip) sits in the right palm, the handle runs towards the left.
		var melee_basis: Basis = (hand.basis.orthonormalized() * _melee_basis).orthonormalized()
		grip.global_transform = Transform3D(melee_basis, hand.origin + hand.basis.y * 0.055)
		_weapon.sync_held_pose()
		return
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
