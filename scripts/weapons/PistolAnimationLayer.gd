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
const HOLD_CLIPS: Array[StringName] = [&"melee_idle", &"punch_idle"]
const STRIKE_FADE_IN: float = 0.1
## Hit reactions start from wherever the body is; a slightly longer blend
## keeps the snap in the clip itself rather than in the blend.
const REACTION_FADE_IN: float = 0.12
## Colony sim, not an action game: hit reactions are a flinch in the torso,
## head and arms at partial weight, never a full-body stagger.
const REACTION_WEIGHT: float = 0.65
const STRIKE_FADE_OUT: float = 0.25
## A strike that starts while another is still showing cross-fades against
## it (combo, interrupt, hit reaction) instead of swapping the clip in place.
const STRIKE_XFADE: float = 0.12
const HOLD_FADE_RATE: float = 4.0
## Shots: play the recoil around the measured kick, briefly.
const SHOT_LEAD: float = 0.08
const SHOT_TAIL: float = 0.3
## Two-hand handle grip in RIGHT-hand bone space (skeleton units; world is
## ×1.25). A power grip runs the handle diagonally across the palm, from the
## pinky side (knob) to the index side (+X) and slightly towards the fingers
## (+Y); the fist centre sits FIST_LOCAL from the wrist. The right fist holds
## the handle RIGHT_ON_HANDLE up from the weapon origin (models: grip at the
## origin, tip along -Z) and the left wrist sits LEFT_BELOW further down,
## towards the knob, placed by the support-hand IK.
const HANDLE_LOCAL: Vector3 = Vector3(0.958, 0.287, 0.0)
const FIST_LOCAL: Vector3 = Vector3(0.0, 0.055, 0.0)
const RIGHT_ON_HANDLE: float = 0.024
const LEFT_BELOW: float = 0.068
## Pistol support hand in right-hand space, measured from the male "Pistol
## Idle" (hand cupped under the grip). The female export crosses her hands
## over; the IK puts her support hand here instead. Runtime only.
const PISTOL_SUPPORT: Vector3 = Vector3(-0.004, 0.027, 0.05)
const SUPPORT_FADE_RATE: float = 6.0
## Swing playback is clamped to a believable range of the authored speed.
const STRIKE_RATE_RANGE: Vector2 = Vector2(0.7, 2.2)

class Strike:
	var clip: StringName = &""
	var time: float = 0.0
	var end: float = 0.0
	var rate: float = 1.0
	var w: float = 0.0
	var upper_only: bool = false
	var retiring: bool = false   ## being replaced: fade out over STRIKE_XFADE
	var fade_in: float = STRIKE_FADE_IN
	var max_w: float = 1.0

var weapons: AnimationLibrary
var _hold_w: Dictionary = {}        ## hold clip -> weight
var _hold_time: Dictionary = {}     ## hold clip -> loop time
var _strikes: Array[Strike] = [Strike.new(), Strike.new()]
var _melee: bool = false
var _support_w: float = 0.0
var _signal_weapon: Node = null
var _chain_end: String = ""

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
	graph.connect_node("out", 0, _chain_end)
	grip = Marker3D.new()
	grip.name = "WeaponGrip"
	model.add_child(grip)
	_hand = model._skeleton.find_bone("RightHand")
	_grip_basis = library.get_animation("idle").get_meta("grip_basis", Basis.IDENTITY)
	# SkeletonModifier3D may change the wrists after the AnimationTree advances.
	# Attach on the final skeleton update, so the gun never lags the hand.
	model._skeleton.skeleton_updated.connect(sync_grip)

## pistol_mix → hold_<clip>_full/_upper (melee stance, fist guard) →
## strike_a_full/_upper → strike_b_full/_upper → out.
## "full" blends every bone (never the armature root, so the body can't drift
## off the capsule); "upper" only spine, neck, head, arms and hands. Each
## overlay has its own seek-driven clip node so time never advances twice.
func _install_melee(graph: AnimationNodeBlendTree) -> void:
	weapons = load("res://assets/models/player/weapons/weapons_%s_lib.res" % model._gender)
	tree.add_animation_library("weapons", weapons)
	var layers: Array[String] = []
	for hold: StringName in HOLD_CLIPS:
		_hold_w[hold] = 0.0
		_hold_time[hold] = 0.0
		layers.append_array(["hold_%s_full" % hold, "hold_%s_upper" % hold])
	layers.append_array(["strike_a_full", "strike_a_upper", "strike_b_full", "strike_b_upper"])
	var previous: String = "pistol_mix"
	for layer: String in layers:
		var clip := AnimationNodeAnimation.new()
		clip.animation = StringName("weapons/" + (layer.trim_prefix("hold_").trim_suffix("_full").trim_suffix("_upper")
			if layer.begins_with("hold_") else "melee_idle"))
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
	_chain_end = previous

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
	_update_holds(delta, &"melee_idle" if melee else (&"punch_idle" if guard else &""))
	_update_strikes(delta, free)
	_update_support_hand(delta, melee, active)
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
			## Rapid shots: recoil in the arms/torso only, legs stay on the
			## pistol locomotion instead of flicking into the clip's stance.
			_start_strike(&"pistol_shoot", maxf(0.0, kick - SHOT_LEAD), 1.0, minf(shot.length, kick + SHOT_TAIL), true)
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

## Starts a strike in the quieter slot; the other one (if still showing)
## fades out over STRIKE_XFADE underneath/over it — a cross-fade, never a pop.
func _start_strike(clip: StringName, from: float, rate: float, until: float, upper_only: bool = false,
		fade_in: float = STRIKE_FADE_IN, max_w: float = 1.0) -> void:
	var slot: int = 0 if _strikes[0].w <= _strikes[1].w else 1
	var other: Strike = _strikes[1 - slot]
	if other.clip != &"":
		other.retiring = true
	var s := Strike.new()
	s.clip = clip
	s.time = from
	s.rate = rate
	s.end = until
	s.upper_only = upper_only
	s.fade_in = fade_in
	s.max_w = max_w
	## Starts from zero: the slot picked is the quieter one, and inheriting its
	## weight would snap that much of the old clip to the new one.
	_strikes[slot] = s
	var graph: AnimationNodeBlendTree = tree.tree_root
	var name: String = "strike_a" if slot == 0 else "strike_b"
	for part: String in ["_full", "_upper"]:
		(graph.get_node(name + part + "_clip") as AnimationNodeAnimation).animation = StringName("weapons/" + clip)

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
	_start_strike(clip, 0.0, 1.0, weapons.get_animation(clip).length, true, REACTION_FADE_IN, REACTION_WEIGHT)

## Each hold stance has its own chain and fades on its own, so switching
## between the fist guard and a weapon stance cross-fades.
func _update_holds(delta: float, active: StringName) -> void:
	var moving: float = clampf(model._move_w, 0.0, 1.0)
	for hold: StringName in HOLD_CLIPS:
		var length: float = weapons.get_animation(hold).length
		_hold_time[hold] = fposmod(float(_hold_time[hold]) + delta, length)
		_hold_w[hold] = move_toward(float(_hold_w[hold]), 1.0 if hold == active else 0.0, delta * HOLD_FADE_RATE)
		var w: float = smoothstep(0.0, 1.0, float(_hold_w[hold]))
		for part: String in ["_full", "_upper"]:
			tree.set("parameters/hold_%s%s_seek/seek_request" % [hold, part], _hold_time[hold])
		tree.set("parameters/hold_%s_full/blend_amount" % hold, w * (1.0 - moving))
		tree.set("parameters/hold_%s_upper/blend_amount" % hold, w * moving)

## Strike envelopes: quick in, out over the clip's last STRIKE_FADE_OUT, or
## out over STRIKE_XFADE when replaced. Full body standing still, upper body
## while moving (or always for rapid shots), eased with smoothstep.
func _update_strikes(delta: float, free: bool) -> void:
	var moving: float = clampf(model._move_w, 0.0, 1.0)
	for slot: int in 2:
		var s: Strike = _strikes[slot]
		if s.clip != &"" and free and not s.retiring:
			s.time += delta * s.rate
			var left: float = (s.end - s.time) / maxf(s.rate, 0.01)
			s.w = minf(move_toward(s.w, 1.0, delta / s.fade_in), clampf(left / STRIKE_FADE_OUT, 0.0, 1.0))
			if s.time >= s.end:
				s.clip = &""
		else:
			if s.retiring:
				s.time = minf(s.time + delta * s.rate, s.end)
			s.w = move_toward(s.w, 0.0, delta / (STRIKE_XFADE if s.retiring else STRIKE_FADE_OUT))
			if s.w <= 0.0:
				s.retiring = false
				s.clip = &""
		var name: String = "strike_a" if slot == 0 else "strike_b"
		var w: float = smoothstep(0.0, 1.0, s.w) * s.max_w
		var upper: float = 1.0 if s.upper_only else moving
		for part: String in ["_full", "_upper"]:
			tree.set("parameters/%s%s_seek/seek_request" % [name, part], minf(s.time, s.end))
		tree.set("parameters/%s_full/blend_amount" % name, w * (1.0 - upper))
		tree.set("parameters/%s_upper/blend_amount" % name, w * upper)

## Left hand on the handle below the right (melee), or cupped under the
## pistol grip; eased out during the one-handed whip and punches.
func _update_support_hand(delta: float, melee: bool, pistol: bool) -> void:
	var whip: float = 0.0
	for s: Strike in _strikes:
		if s.clip == &"pistol_whip" or s.clip.begins_with("hit_"):
			whip = maxf(whip, smoothstep(0.0, 1.0, s.w))
	var want: float = 1.0 if melee or pistol else 0.0
	_support_w = move_toward(_support_w, want, delta * SUPPORT_FADE_RATE)
	var pose: Node = model._pose_mod
	if pose == null:
		return
	pose.support_offset = -HANDLE_LOCAL * LEFT_BELOW if melee else PISTOL_SUPPORT
	pose.support_weight = smoothstep(0.0, 1.0, _support_w) * (1.0 - whip)

func sync_grip() -> void:
	if not is_instance_valid(_weapon) or not _weapon.is_held or _hand < 0:
		return
	var hand: Transform3D = model._skeleton.global_transform * model._skeleton.get_bone_global_pose(_hand)
	if _melee:
		## Power grip across the right fist (see HANDLE_LOCAL); the palm normal
		## (+Z) orients the head of a crowbar/hatchet.
		var along: Vector3 = (hand.basis * HANDLE_LOCAL).normalized()
		var palm: Vector3 = (hand.basis * Vector3.BACK).normalized()
		var melee_basis := Basis.looking_at(along, palm.cross(along).cross(along) if absf(palm.dot(along)) > 0.99 else palm)
		grip.global_transform = Transform3D(melee_basis, hand * (FIST_LOCAL - HANDLE_LOCAL * RIGHT_ON_HANDLE))
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
