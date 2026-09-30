extends Node3D
## Behavior checks in a fresh Godot process with real physics and player systems.
const Weapon = preload("res://scripts/weapons/WeaponItem.gd")
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("WEAPONS: " + label)

## Physics ticks until a melee/whip strike has landed (strike_delay is tuned
## to animation contact frames by the animation session, so never hard-code).
func strike_ticks(weapon: Node) -> int:
	return ceili(float(weapon.strike_delay) * Engine.physics_ticks_per_second) + 4

func ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame

func _run() -> void:
	var room: Node3D = preload("res://tools/tests/WeaponsTest.tscn").instantiate()
	add_child(room)
	await ticks(8)
	var player: Player = room._player
	var interaction: InteractionSystem = player.interaction_system
	var controller: Node = interaction.get_node("WeaponController")
	var gun: Weapon = room.get_node("Webley")
	player.position = Vector3(-1.8, 1.0, 1.5)
	await ticks(8)
	interaction._try_pickup()
	check(interaction.held_item == gun, "normal pickup selects Webley")
	check(gun.is_held and gun.freeze, "held weapon has stable pose")
	await ticks(2)
	controller.set_physics_process(false)
	gun.set_aiming(true)
	player.position = Vector3(0, 1, -2)
	player.rotation = Vector3.ZERO
	gun.sync_held_pose()
	# Explicit receiver high enough to catch the held muzzle's horizontal ray.
	var target: StaticBody3D = preload("res://scripts/weapons/WeaponTestTarget.gd").new()
	target.position = Vector3(0, 1.8, -5)
	room.add_child(target)
	await ticks(3)
	var start_ammo: int = gun.ammo
	check(gun.try_attack(Vector3.FORWARD), "aimed shot commits")
	check(gun.ammo == start_ammo - 1, "one round spent")
	check(target.hits == 1, "ray reaches opt-in damage receiver")
	check(gun._flash.visible, "shot illuminates muzzle")
	check(get_tree().get_nodes_in_group("weapon_cases").size() == 1, "one case ejected")
	check(not gun.try_attack(Vector3.FORWARD), "cooldown prevents duplicate shot")
	await ticks(5)
	check(not gun._flash.visible, "flash is brief")
	gun._cooldown = 0.0
	gun.ammo = 0
	var cases_before: int = get_tree().get_nodes_in_group("weapon_cases").size()
	var whips: Array = []
	gun.attack_started.connect(func(kind: String, _variant: int) -> void: whips.append(kind))
	target.position = Vector3(0, 1.8, -5)
	await ticks(2)
	var whip_hits: int = target.hits
	check(gun.try_attack(Vector3.FORWARD), "empty revolver attack becomes a pistol whip")
	check(whips == ["pistol_whip"], "whip announces its own attack kind")
	check(gun.ammo == 0 and get_tree().get_nodes_in_group("weapon_cases").size() == cases_before, "whip spends no ammo, ejects no case")
	await ticks(strike_ticks(gun))
	check(target.hits == whip_hits, "whip reach is short (target 3 m away untouched)")
	gun.reserve_ammo = 2
	gun.on_use()
	check(gun._reload_left > 0, "reload starts")
	gun._reload_left = 0.001
	await ticks(2)
	check(gun.ammo == 2 and gun.reserve_ammo == 0, "partial reload conserves ammunition")
	gun.reserve_ammo = 10
	gun.on_use()
	gun.cancel_action()
	await ticks(2)
	check(gun.ammo == 2 and gun.reserve_ammo == 10 and gun._reload_left == 0, "cancelled reload consumes nothing")
	gun.ammo = 3
	var spec: Dictionary = ItemSaveData.capture(gun)
	var restored: Weapon = ItemSaveData.spawn(spec, room)
	check(restored.ammo == 3 and restored.reserve_ammo == 10 and restored.magazine_capacity == 6, "save round trip preserves rounds and reserve")
	restored.queue_free()
	# Put a thin wall between chest and the muzzle; muzzle alone is beyond it.
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 0.08)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector3(0, 1.5, -2.5)
	room.add_child(wall)
	await ticks(3)
	gun._cooldown = 0
	gun.set_aiming(true)
	var hits_before: int = target.hits
	gun.try_attack(Vector3.FORWARD)
	check(target.hits == hits_before, "holder-to-muzzle wall blocks shot")
	gun.set_aiming(false)
	gun._cooldown = 0
	check(not gun.try_attack(Vector3.FORWARD), "un-aimed attacks rejected")
	wall.queue_free()
	await ticks(2)
	# Pistol whip lands at close range with its own damage.
	gun.ammo = 0
	gun._cooldown = 0
	gun.set_aiming(true)
	target.position = Vector3(0, 1.8, -3)
	player.position = Vector3(0, 1, -2)
	await ticks(3)
	var whip_before: int = target.hits
	var hit_log: Array = []
	gun.hit_resolved.connect(func(hit: Dictionary) -> void: hit_log.append(hit))
	check(gun.try_attack(Vector3.FORWARD), "close whip commits")
	await ticks(strike_ticks(gun))
	check(target.hits == whip_before + 1 and hit_log.size() == 1 and hit_log[0].kind == "pistol_whip" and is_equal_approx(hit_log[0].damage, gun.whip_damage), "whip hits once for whip damage")
	gun.ammo = 3
	# Melee: one hit, no ammo, no hit through wall, cancellation before contact.
	gun.drop(room, Vector3(5, 0.5, 0))
	var knife: Weapon = room.get_node("Knife")
	interaction.held_item = knife
	knife.pickup(interaction.hold_point)
	knife.set_aiming(true)
	target.position = Vector3(0, 1.8, -3)
	await ticks(3)
	hits_before = target.hits
	check(knife.try_attack(Vector3.FORWARD), "melee starts")
	await ticks(strike_ticks(knife))
	check(target.hits == hits_before + 1, "melee hits once during strike")
	check(knife.ammo == 6, "melee does not spend ammunition")
	var variants: Array = []
	knife.attack_started.connect(func(_kind: String, variant: int) -> void: variants.append(variant))
	knife.attack_variant_chance = 1.0
	knife._last_variant = 0   ## the earlier swing may have rolled the alternate
	for i: int in 4:
		knife._cooldown = 0
		knife.try_attack(Vector3.FORWARD)
	knife.cancel_action()
	check(variants == [1, 0, 1, 0], "alternate swing never repeats back to back")
	await ticks(10)
	knife._cooldown = 0
	knife.try_attack(Vector3.FORWARD)
	knife.cancel_action()
	await ticks(strike_ticks(knife))
	check(target.hits == hits_before + 1, "interrupted melee has no delayed hit")
	# Lock gates and cancellation exercised through the real controller.
	controller.set_physics_process(true)
	await ticks(2)
	check(interaction.can_use_weapon(), "normal gameplay permits weapon")
	player.set_movement_locked(true)
	await ticks(2)
	check(not interaction.can_use_weapon() and not knife.aiming, "modal lock cancels aim")
	player.set_movement_locked(false)
	interaction.build_mode_active = true
	check(not interaction.can_use_weapon(), "build mode blocks weapon")
	interaction.build_mode_active = false
	player.set_job_locked(true)
	check(not interaction.can_use_weapon(), "job blocks weapon")
	player.set_job_locked(false)
	player.seated_chair = wall if is_instance_valid(wall) else room
	check(not interaction.can_use_weapon(), "seated player cannot attack")
	player.seated_chair = null
	# Simulated pad aim is camera-relative; a trigger press commits only once.
	interaction.held_item = gun
	knife.drop(room, Vector3(4, 0.4, 0))
	gun.pickup(interaction.hold_point)
	gun.ammo = 3
	gun._cooldown = 0
	Input.action_press("aim_right", 1.0)
	await ticks(6)
	check(gun.aiming, "right stick enables weapon aim")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	controller._unhandled_input(trigger)
	await ticks(2)
	check(gun.ammo == 2, "right trigger fires one round")
	controller._unhandled_input(trigger)
	await ticks(2)
	check(gun.ammo == 2, "held trigger does not repeat")
	var release := InputEventJoypadMotion.new()
	release.axis = JOY_AXIS_TRIGGER_RIGHT
	release.axis_value = 0.0
	controller._input(release)
	gun._cooldown = 0.1
	controller._unhandled_input(trigger)
	await ticks(1)
	check(gun.ammo == 2, "press during recovery waits")
	await ticks(9)
	check(gun.ammo == 1, "buffered press fires once recovery ends")
	Input.action_release("aim_right")
	await ticks(2)
	check(not gun.aiming, "release stick returns to carry")
	# Mouse aim: the OS cursor is captured at screen centre in gameplay, so
	# aiming must follow raw motion from a virtual point, not the cursor.
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.button_mask = MOUSE_BUTTON_MASK_RIGHT
	rmb.pressed = true
	Input.parse_input_event(rmb)
	await ticks(2)
	var start_point: Vector2 = controller._mouse_point
	var yaw_before: float = player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-20, -18)   ## headless viewport is only 64 px
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(motion)
	await ticks(12)
	check(controller._mouse_point.distance_to(start_point + Vector2(-20, -18)) < 1.0, "mouse motion moves the aim point")
	check(absf(angle_difference(player.rotation.y, yaw_before)) > 0.2, "mouse aim turns the player toward the aim point")
	rmb.pressed = false
	rmb.button_mask = 0
	Input.parse_input_event(rmb)
	await ticks(2)
	controller._reset()
	gun.drop(room, Vector3(5, 0.4, 0))
	interaction.held_item = null
	check(not gun.aiming and gun._reload_left == 0 and not gun.freeze, "drop clears actions and restores loose physics")
	# Empty hands: the controller swaps in Fists; punches alternate jab/cross.
	await ticks(2)
	var fists: Node = controller._fists
	check(fists != null and controller._weapon == fists, "empty hands use fists")
	controller.set_physics_process(false)
	player.position = Vector3(0, 1, -2)
	player.rotation = Vector3.ZERO
	target.position = Vector3(0, 1.0, -2.8)
	await ticks(3)
	var punches: Array = []
	fists.attack_started.connect(func(kind: String, variant: int) -> void: punches.append([kind, variant]))
	var punch_hits: Array = []
	fists.hit_resolved.connect(func(hit: Dictionary) -> void: punch_hits.append(hit))
	fists.set_aiming(true)
	var before_punch: int = target.hits
	check(fists.try_attack(Vector3.FORWARD), "punch commits")
	await ticks(strike_ticks(fists))
	fists._cooldown = 0
	fists.try_attack(Vector3.FORWARD)
	await ticks(strike_ticks(fists))
	check(punches == [["punch", 0], ["punch", 1]], "jab then cross")
	check(target.hits == before_punch + 2 and punch_hits.size() == 2 and punch_hits[1].kind == "punch" and is_equal_approx(punch_hits[1].damage, fists.cross_damage), "both punches land with their own damage")
	fists._since_last = 5.0
	fists._cooldown = 0
	fists.try_attack(Vector3.FORWARD)
	fists.cancel_action()
	check(punches[-1] == ["punch", 0], "combo resets to jab after a pause")
	room.queue_free()
	await ticks(4)
	print("WEAPONS_SMOKE: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
