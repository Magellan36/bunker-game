extends Node3D
## Unarmed combat. Add as a child of any CharacterBody3D (player or NPC); it
## speaks the same API as WeaponItem (set_aiming / try_attack / signals), so
## WeaponController and NPC code drive it exactly like a held weapon.
## Punches alternate jab → cross; a pause longer than COMBO_RESET restarts at jab.
signal attack_started(kind: String, variant: int)   ## kind "punch"; variant 0 jab, 1 cross
signal hit_resolved(hit: Dictionary)
signal aim_changed(aiming: bool)
signal dry_fired   ## never emitted; API parity with WeaponItem

const Melee = preload("res://scripts/weapons/MeleeStrike.gd")
const COMBO_RESET: float = 0.9
const CHEST_HEIGHT: float = 0.35   ## above the holder's origin (capsule centre)

var weapon_kind: String = "fists"
@export var jab_damage: float = 5.0
@export var cross_damage: float = 8.0
@export var reach: float = 1.1
@export var melee_half_angle: float = 45.0
@export var jab_interval: float = 0.32
@export var cross_interval: float = 0.45
## Press-to-contact seconds; tuned to the punch clips by the animation session.
@export var jab_strike_delay: float = 0.2
@export var cross_strike_delay: float = 0.3
var aiming: bool = false
var is_held: bool = true
var grip_anchor: Node3D   ## unused (no object in hand); parity only
var ammo: int = 0
var reserve_ammo: int = 0
var _reload_left: float = 0.0
var strike_delay: float = 0.12   ## the delay of the punch in flight (read by tests)
var _cooldown: float = 0.0
var _since_last: float = INF
var _next_variant: int = 0
var _strike_left: float = 0.0
var _strike_variant: int = 0
var _strike_direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	name = "Fists"
	process_physics_priority = 20

func holder() -> CharacterBody3D:
	return get_parent() as CharacterBody3D

func is_firearm() -> bool:
	return false

func get_aim_origin() -> Vector3:
	return global_position

func sync_held_pose() -> void:
	var body: CharacterBody3D = holder()
	if body != null:
		global_position = body.global_position + Vector3.UP * CHEST_HEIGHT

func set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	if not aiming:
		_strike_left = 0.0
	aim_changed.emit(aiming)

func cancel_action() -> void:
	set_aiming(false)
	_strike_left = 0.0

func try_attack(direction: Vector3) -> bool:
	if not aiming or _cooldown > 0.0 or direction.length_squared() < 0.001:
		return false
	if _since_last > COMBO_RESET:
		_next_variant = 0
	_strike_variant = _next_variant
	_next_variant = 1 - _next_variant
	_cooldown = cross_interval if _strike_variant == 1 else jab_interval
	strike_delay = cross_strike_delay if _strike_variant == 1 else jab_strike_delay
	_strike_left = strike_delay
	_strike_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_since_last = 0.0
	attack_started.emit("punch", _strike_variant)
	return true

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_since_last += delta
	sync_held_pose()
	if _strike_left > 0.0:
		_strike_left = maxf(0.0, _strike_left - delta)
		if _strike_left == 0.0 and aiming:
			_punch()

func _punch() -> void:
	var body: CharacterBody3D = holder()
	var exclude: Array[RID] = []
	if body != null:
		exclude.append(body.get_rid())
	var amount: float = cross_damage if _strike_variant == 1 else jab_damage
	for hit: Dictionary in Melee.find(get_world_3d(), global_position, _strike_direction, reach,
			melee_half_angle, exclude, 1):
		var context: Dictionary = {"damage": amount, "position": hit.position, "direction": _strike_direction,
			"kind": "punch", "variant": _strike_variant, "source": body, "collider": hit.collider}
		Melee.deliver(context)
		hit_resolved.emit(context)
