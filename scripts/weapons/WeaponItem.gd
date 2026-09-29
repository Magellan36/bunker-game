extends PickupableItem
## Pickup/inventory-compatible weapon. Webley, bat and crowbar use supplied models; knife/hatchet/pipe are graybox.
## Forward is local -Z. Replace Model and keep Muzzle for authored assets.
## kind: weapon_kind, or "pistol_whip" for an empty revolver's strike.
## variant: 0 = regular attack, 1 = occasional alternate (melee flavor, see
## attack_variant_chance). Animation plays the matching clip; the hit lands
## strike_delay later regardless of animation.
signal attack_started(kind: String, variant: int)
signal hit_resolved(hit: Dictionary)
signal dry_fired
signal aim_changed(aiming: bool)

const KINDS: Array[String] = ["revolver", "knife", "hatchet", "pipe", "bat", "crowbar"]
@export_enum("revolver", "knife", "hatchet", "pipe", "bat", "crowbar") var weapon_kind: String = "revolver"
@export var magazine_capacity: int = 6
@export var ammo: int = 6
@export var reserve_ammo: int = 12
@export var damage: float = 24.0
@export var attack_interval: float = 0.26
@export var reach: float = 35.0
@export var melee_half_angle: float = 50.0
@export var recoil_strength: float = 0.13
@export var reload_duration: float = 1.25
## Melee contact delay after the press (seconds).
@export var strike_delay: float = 0.10
## Chance a melee attack uses the alternate swing (never twice in a row).
@export var attack_variant_chance: float = 0.3
## Empty revolver: each attack becomes a pistol whip.
@export var whip_damage: float = 14.0
@export var whip_reach: float = 1.3
@export var whip_interval: float = 0.55
@export var attack_sound: AudioStream
@export var empty_sound: AudioStream
@export var reload_sound: AudioStream
## Animation integration: supply the hand/bone anchor later without changing input.
var grip_anchor: Node3D
var _audio: AudioStreamPlayer3D

var shelf_stack_limit: int = 1
var shelf_item_type: String = "weapon"
var aiming: bool = false
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _strike_left: float = 0.0
var _strike_direction: Vector3 = Vector3.FORWARD
var _strike_kind: String = ""
var _last_variant: int = 0
var _kick: float = 0.0
var _model: Node3D
var _muzzle: Marker3D
var _flash: OmniLight3D
var _flash_left: float = 0.0
const Effects = preload("res://scripts/weapons/WeaponEffects.gd")

func _ready() -> void:
	super._ready()
	if not _is_preview_only:
		add_to_group("inventory_item")
	allow_manual_upright = false
	mass = 0.9
	shelf_item_type = "weapon_" + weapon_kind
	_build_proxy()
	process_physics_priority = 20
	_audio = AudioStreamPlayer3D.new()
	_audio.max_distance = 20.0
	add_child(_audio)

func is_firearm() -> bool:
	return weapon_kind == "revolver"

func get_display_name() -> String:
	return {"revolver": "Webley Mk II", "knife": "Knife", "hatchet": "Hatchet", "pipe": "Steel Pipe",
		"bat": "Baseball Bat", "crowbar": "Crowbar"}.get(weapon_kind, "Weapon")

func get_use_prompt() -> String:
	if not is_firearm():
		return "Hold RMB / Right stick: Aim · LMB / RT: Swing"
	if _reload_left > 0.0:
		return "Reloading…"
	if ammo <= 0:
		return "Hold RMB / Right stick: Aim · LMB / RT: Pistol whip · [E] Reload  0 / %d" % reserve_ammo
	return "Hold RMB / Right stick: Aim · LMB / RT: Fire · [E] Reload  %d / %d" % [ammo, reserve_ammo]

func get_inventory_hud_state() -> Dictionary:
	return {"kind": "charges", "current": ammo, "maximum": magazine_capacity} if is_firearm() else {}

func get_item_save_state() -> Dictionary:
	return {"weapon_kind": weapon_kind, "ammo": ammo, "reserve_ammo": reserve_ammo}

func apply_item_save_state(state: Dictionary) -> void:
	var kind: String = str(state.get("weapon_kind", weapon_kind))
	if kind in KINDS:
		weapon_kind = kind
	ammo = clampi(int(state.get("ammo", ammo)), 0, magazine_capacity)
	reserve_ammo = maxi(0, int(state.get("reserve_ammo", reserve_ammo)))

func set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	if not aiming:
		_strike_left = 0.0
	aim_changed.emit(aiming)

func cancel_action() -> void:
	set_aiming(false)
	_reload_left = 0.0
	_strike_left = 0.0
	_flash_left = 0.0
	if is_instance_valid(_flash):
		_flash.visible = false

func _on_pickup_extra() -> void:
	cancel_action()
	## Stable held transform; collision/occlusion is resolved by attack queries.
	freeze = true
	collision_layer = 0
	collision_mask = 0

func _on_drop_extra() -> void:
	cancel_action()

func on_use() -> void:
	if is_firearm() and is_held and ammo < magazine_capacity and reserve_ammo > 0 and _reload_left <= 0.0:
		_reload_left = reload_duration
		_play_sound(reload_sound)
		_strike_left = 0.0

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	_flash.visible = _flash_left > 0.0
	_kick = move_toward(_kick, 0.0, delta * 8.0)
	if not is_held or not is_instance_valid(_hold_point):
		cancel_action()
		super._physics_process(delta)
		return
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		if _reload_left == 0.0:
			var transfer: int = mini(magazine_capacity - ammo, reserve_ammo)
			ammo += transfer
			reserve_ammo -= transfer
			charge_changed.emit()
	sync_held_pose()
	if _strike_left > 0.0:
		_strike_left = maxf(0.0, _strike_left - delta)
		if _strike_left == 0.0 and aiming:
			_melee_hit(_strike_direction)
	var swing: float = sin(clampf(_cooldown / attack_interval, 0.0, 1.0) * PI) if not is_firearm() else 0.0
	if grip_anchor != null:
		swing = 0.0   ## a real hand animation carries the swing
	_model.rotation = Vector3(_kick * 0.12, swing * 1.4, 0.0)
	_model.position.z = _kick * 0.045

func sync_held_pose() -> void:
	if is_held and is_instance_valid(_hold_point):
		global_transform = grip_anchor.global_transform if is_instance_valid(grip_anchor) else _hold_point.global_transform
		global_basis = global_basis.orthonormalized()

## Returns true only for a committed attack. Call from a physics tick.
func try_attack(direction: Vector3) -> bool:
	if not is_held or not aiming or _cooldown > 0.0 or _reload_left > 0.0 or direction.length_squared() < 0.001:
		return false
	_cooldown = attack_interval
	if is_firearm() and ammo > 0:
		_kick = 1.0
		_play_sound(attack_sound)
		attack_started.emit(weapon_kind, 0)
		ammo -= 1
		charge_changed.emit()
		_fire(direction.normalized())
		return true
	if is_firearm():
		## Out of rounds: the revolver becomes a club. dry_fired still tells
		## audio/UI the chamber is empty; no ammo or case is involved.
		_cooldown = whip_interval
		_strike_kind = "pistol_whip"
		dry_fired.emit()
		attack_started.emit(_strike_kind, 0)
	else:
		_strike_kind = weapon_kind
		_last_variant = 1 if _last_variant == 0 and randf() < attack_variant_chance else 0
		_play_sound(attack_sound)
		attack_started.emit(_strike_kind, _last_variant)
	_kick = 1.0
	_strike_direction = direction.normalized()
	_strike_left = strike_delay
	return true

func _exclusions() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	var holder: CharacterBody3D = _get_holder()
	if holder != null:
		excluded.append(holder.get_rid())
	return excluded

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | ITEM_LAYER_SMALL, _exclusions())
	return get_world_3d().direct_space_state.intersect_ray(query)

func _attack_origin() -> Vector3:
	var holder: CharacterBody3D = _get_holder()
	return Vector3(holder.global_position.x, _muzzle.global_position.y if is_firearm() else global_position.y, holder.global_position.z) if holder != null else global_position

func _fire(direction: Vector3) -> void:
	var muzzle_position: Vector3 = _muzzle.global_position
	## A muzzle beyond a thin wall must hit that wall, never shoot through it.
	var hit: Dictionary = _ray(_attack_origin(), muzzle_position)
	if hit.is_empty():
		hit = _ray(muzzle_position, muzzle_position + direction * reach)
	_flash_left = 0.045
	_flash.visible = true
	Effects.eject_case(self, global_transform)
	if not hit.is_empty():
		_deliver_hit(hit, direction)
		Effects.impact(self, hit.position, hit.normal)
	_shake_camera()

## Full recoil shake only for the player's own shots. Someone else's shot nearby
## gives a faint, distance-faded jolt (none beyond NEARBY_SHOT_RANGE).
const NEARBY_SHOT_RANGE: float = 8.0
const NEARBY_SHOT_SCALE: float = 0.35
func _shake_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.has_method("add_trauma"):
		return
	var holder: CharacterBody3D = _get_holder()
	if holder != null and holder.is_in_group("player"):
		camera.call("add_trauma", recoil_strength)
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var shooter: Node3D = holder if holder != null else self
	var falloff: float = 1.0 - player.global_position.distance_to(shooter.global_position) / NEARBY_SHOT_RANGE
	if falloff > 0.0:
		camera.call("add_trauma", recoil_strength * NEARBY_SHOT_SCALE * falloff)

func _melee_hit(direction: Vector3) -> void:
	var origin: Vector3 = _attack_origin()
	var whip: bool = _strike_kind == "pistol_whip"
	var range_: float = whip_reach if whip else reach
	var shape := SphereShape3D.new()
	shape.radius = range_
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = origin
	query.collision_mask = 1 | ITEM_LAYER_SMALL
	query.exclude = _exclusions()
	var delivered: Dictionary = {}
	for candidate: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body: Node3D = candidate.collider as Node3D
		if body == null or delivered.has(body.get_instance_id()):
			continue
		var target: Vector3 = body.global_position
		if body is CharacterBody3D:
			target.y = origin.y
		var offset: Vector3 = target - origin
		if offset.length_squared() < 0.001 or offset.length() > range_:
			continue
		if direction.dot(offset.normalized()) < cos(deg_to_rad(melee_half_angle)):
			continue
		var hit: Dictionary = _ray(origin, target)
		if hit.is_empty() or hit.collider != body:
			continue
		delivered[body.get_instance_id()] = true
		_deliver_hit(hit, direction, whip_damage if whip else damage, _strike_kind)
		Effects.impact(self, hit.position, hit.normal)

func _deliver_hit(hit: Dictionary, direction: Vector3, amount: float = damage, kind: String = weapon_kind) -> void:
	var context: Dictionary = {"damage": amount, "position": hit.position, "direction": direction,
		"kind": kind, "source": _get_holder(), "collider": hit.collider}
	var receiver: Node = hit.collider as Node
	while receiver != null and not receiver.has_method("receive_weapon_hit"):
		receiver = receiver.get_parent()
	if receiver != null:
		receiver.call("receive_weapon_hit", context)
	hit_resolved.emit(context)

func _build_proxy() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.19, 0.22, 0.25)
	metal.metallic = 0.75
	metal.roughness = 0.35
	var handle := StandardMaterial3D.new()
	handle.albedo_color = Color(0.25, 0.13, 0.07)
	var size := Vector3(0.10, 0.12, 0.34)
	if is_firearm():
		var authored: Node3D = preload("res://assets/models/weapons/webley/webley_mkii.glb").instantiate()
		authored.position = Vector3(0, 0.08, -0.06)
		_model.add_child(authored)
	elif weapon_kind == "bat":
		_model.add_child(preload("res://assets/models/weapons/bat/bat.glb").instantiate())
		size = Vector3(0.075, 0.075, 0.84)
	elif weapon_kind == "crowbar":
		var crowbar: Node3D = preload("res://assets/models/weapons/crowbar/crowbar.glb").instantiate()
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.16, 0.17, 0.18)
		steel.metallic = 0.8
		steel.roughness = 0.4
		for mesh: MeshInstance3D in crowbar.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = steel
		_model.add_child(crowbar)
		size = Vector3(0.05, 0.09, 0.60)
	else:
		size = Vector3(0.065, 0.065, 0.65 if weapon_kind != "knife" else 0.32)
		_box(size, Vector3(0, 0, -size.z * 0.35), metal)
		_box(Vector3(0.075, 0.075, 0.18), Vector3(0, 0, 0.08), handle)
		if weapon_kind == "hatchet":
			_box(Vector3(0.26, 0.08, 0.15), Vector3(0.08, 0, -0.40), metal)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	if weapon_kind == "bat":
		collision.position.z = -0.34
	elif weapon_kind == "crowbar":
		collision.position.z = -0.19
	add_child(collision)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0, 0.145, -0.212)
	add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.76, 0.39)
	_flash.light_energy = 5.0
	_flash.omni_range = 3.5
	_flash.shadow_enabled = true
	_flash.visible = false
	_muzzle.add_child(_flash)

func _box(size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	_model.add_child(mesh)

func _play_sound(stream: AudioStream) -> void:
	if stream != null and is_instance_valid(_audio):
		_audio.stream = stream
		_audio.play()

func get_aim_origin() -> Vector3:
	return _muzzle.global_position if is_instance_valid(_muzzle) else global_position
