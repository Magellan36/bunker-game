class_name Player
extends CharacterBody3D
## Player.gd
## Handles WASD movement, animation state, and basic interaction input.
## Attach to: res://scenes/player/Player.tscn (CharacterBody3D root)

# ─── Exports (tweak in Inspector) ────────────────────────────────────────────
@export var move_speed: float = 4.0        ## Base walk speed (20% slower than original 5.0)
@export var sprint_speed: float = 5.625    ## Sprint speed (0.75× the old 7.5, Brannon 2026-10-01; ~1.4× walk)
@export var acceleration: float = 12.0
@export var friction: float = 16.0

## Stamina drained per second while sprinting (0–100 scale)
@export var sprint_stamina_drain: float = 18.0
## Stamina recovered per second while not sprinting
@export var stamina_regen: float = 8.0
## Stamina drained per second while holding a Heavy item (Aug 2026 — see
## PickupableItem.is_heavy_item() for the classification). Passive: applies
## regardless of sprint state. Deliberately set ABOVE stamina_regen so
## simply standing still holding something heavy still drains rather than
## idles — see _handle_movement()'s drain block, which sums this with
## sprint_stamina_drain when both are active at once rather than letting
## one fight the other. PlayerMedical.get_medical_carry_stamina_drain_
## multiplier() (previously unwired, see its own comment) multiplies this.
@export var heavy_carry_stamina_drain: float = 12.0

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_system: Node = $InteractionSystem

## Local-avoidance presence consumed by every NPC NavigationAgent3D. Keep a
## field reference so its velocity can be refreshed every physics frame;
## moving a radius obstacle without publishing velocity makes avoidance react
## late because it can only infer the player's new position after the move.
var _navigation_obstacle: NavigationObstacle3D = null

## Per-item shove cooldowns for PickupableItem.shove_small_items_near()
## (Sep 2026) — one dict per character so the player and each NPC shove
## independently. See PickupableItem.gd for the one-sided walk-through logic.
var _shove_cooldown_by_item: Dictionary = {}

## Resolved lazily via group lookup (same pattern PlayerStats/PowerManager
## use elsewhere) rather than a direct $-path, since PlayerMedical is a
## sibling node rather than a child of Player — see
## scripts/player/medical/PlayerMedical.gd and
## docs/systems/medical/README.md. May be null if the Medical system's
## node hasn't been added to the scene yet; every use below goes through
## _get_player_medical() rather than reading this directly.
var _player_medical: PlayerMedical = null

## Aug 2026 fix — previously resolved ONCE in _ready() and never
## revisited. PlayerMedical adds itself to the "player_medical" group in
## ITS OWN _ready(), so if node/scene-tree order ever had Player._ready()
## run first, that one-shot lookup silently returned null and stayed null
## for the entire session — every medical multiplier below (speed,
## sprint-drain, carry-drain) quietly no-op'd forever even though
## PlayerMedical's own data was correct (exactly why the HUD/tooltips
## could show a real effect while gameplay didn't feel it at all). Mirrors
## the lazy-resolve-with-validity-check pattern PlayerMedical.gd itself
## already uses for its own _player ref, and InteractionSystem.gd uses for
## _player_medical_for_job — self-heals the moment PlayerMedical actually
## exists, regardless of init order.
func _get_player_medical() -> PlayerMedical:
	if _player_medical == null or not is_instance_valid(_player_medical):
		_player_medical = get_tree().get_first_node_in_group("player_medical") as PlayerMedical
	return _player_medical

## Stamina must recover to this before exertion returns to normal.
@export var sprint_recover_threshold: float = 20.0

## Render layer 12 (bit index 11) — reserved EXCLUSIVELY for tagging the
## player's own mesh so specific lights can exclude it from their
## light_cull_mask without affecting anything else in the scene.
## Restored here (Aug 2026) after a brief detour where this was
## relocated to GraphicsSettings.CHARACTER_SHADOW_LAYER_BIT and
## generalized to exclude the player from every real light — that
## approach was reverted (see docs/systems/graphics/README.md
## "Aggregated character shadows" for the postmortem); this constant is
## back to its original, narrower purpose: excluding the player ONLY
## from Flashlight.gd's own beam, so the handheld light doesn't
## self-shadow a dome into the center of its own cone (see
## docs/systems/graphics/README.md "Flashlight self-shadow exclusion").
## Referenced from other files by class name —
## Player.PLAYER_SELF_LIGHT_LAYER_BIT. Layer 11 is already reserved by
## InteractionFocusGlow.gd's HIGHLIGHT_LAYER; check
## docs/systems/player/README.md before reusing layer 12 elsewhere.
const PLAYER_SELF_LIGHT_LAYER: int = 12
const PLAYER_SELF_LIGHT_LAYER_BIT: int = 1 << (PLAYER_SELF_LIGHT_LAYER - 1)

## Controller facing (Aug 2026): the right stick steers where the model
## faces. Exponential smoothing rate for lerp_angle (rad/s) — higher = more
## snappy, lower = floatier. Tune to taste; 12.0 reads smooth but responsive.
const TURN_SMOOTH_SPEED: float = 12.0
## Squared length threshold below which the right stick is considered idle
## (falls back to facing the movement direction). Input.get_vector already
## applies each action's 0.2 deadzone; this is a small extra guard against
## residual stick noise near center.
const AIM_DEADZONE_SQ: float = 0.01

## Set each frame by MainWorld to match the camera's current yaw.
## Movement input is rotated by this so controls always feel camera-relative.
var camera_yaw_rad: float = 0.0
var _is_moving: bool = false
var _is_sprinting: bool = false
const Exertion = preload("res://scripts/player/PlayerExertion.gd")
var exertion: Exertion = Exertion.new()
## Visual strength can be reduced to zero without removing the text warning.
@export_range(0.0, 1.0) var exertion_feedback_strength: float = 1.0
## Latched by a left-stick click (Aug 2026): while true, the player keeps
## running as long as they're moving. Cleared automatically when the player
## stops moving, or by clicking the stick again; zero stamina enters overdrive.
var _sprint_toggle: bool = false

## Current stamina 0–100. Drive this from PlayerStats if you have one,
## or use it standalone — HUD reads it via set_stamina().
var stamina: float = 100.0

## Set true while the pause menu (or any other full-screen modal) is open —
## blocks movement/interaction input without pausing the SceneTree, so the
## rest of the game (power grid, generators, etc.) keeps running per the
## "game continues while paused" decision. Velocity is zeroed on lock so the
## player doesn't keep sliding on residual momentum while the menu is open.
var _movement_locked: bool = false

## The chair the player is currently sitting in, or null if standing.
## Set/cleared by MainWorld's chair seat/stand wiring (_wire_chair).
var seated_chair: Node3D = null

## Sep 2026 — permanent death (game over). Set when PlayerStats health hits 0;
## the model controller plays the one-shot dying clip and freezes. A dead
## player is locked out of movement/input and the game-over overlay takes over.
var dead: bool = false

func is_dead() -> bool:
	return dead

func die() -> void:
	if dead:
		return
	dead = true
	set_movement_locked(true)
	## Let the shared AdventurerModelController play the dying clip (reads
	## is_dead()); the game-over overlay is opened by MainWorld on health 0.

## Aug 2026 — the bed the player is currently sitting ON (the animated sit-down
## sleep sequence), or null. Set/cleared by MainWorld's bed sleep/stand wiring
## (_wire_bed), mirroring seated_chair so the shared AdventurerModelController
## drives the sit sequence onto the bed.
var sleeping_bed: Node3D = null

func set_movement_locked(locked: bool) -> void:
	_movement_locked = locked
	if locked:
		velocity = Vector3.ZERO

## Aug 2026 — true while the model's sit/lie animation is mid-play (the whole
## sequence is locked in and must play out before any input is accepted again).
## Forwards to the PlayerModel controller, which owns the sit-phase state
## machine (sitting_down/standing_up always locked; the bed's lying_down locked
## until its clip completes).
func is_animation_locked() -> bool:
	var model: Node = get_node_or_null("PlayerModel")
	return model != null and model.has_method("is_animation_locked") \
		and model.is_animation_locked()

## True while a timed "job" interaction (InteractionSystem.start_job(), Aug
## 2026 — see docs/systems/player/README.md's "Job Progress Bar" entry) is
## in progress. Deliberately a SEPARATE flag from _movement_locked
## (PauseMenuUI/other full-screen modals) rather than reusing it, so a job
## started mid-pause or a pause opened mid-job each unlock independently
## instead of one clearing the other's lock early.
var _job_locked: bool = false

func set_job_locked(locked: bool) -> void:
	_job_locked = locked
	if locked:
		velocity = Vector3.ZERO

# ─── Signals ──────────────────────────────────────────────────────────────────
signal interacted()
signal stamina_changed(new_value: float)   ## Emit so HUD / PlayerStats can react
## Compatibility event: entering exhaustion is a warning, never an injury.
signal exhausted(from_sprint: bool, from_heavy_carry: bool)
## Medical consumes the latest per-limb exposure after each stamina step.
signal exertion_updated

func _ready() -> void:
	## Register in "player" group so items (e.g. Flashlight) can resolve the
	## player ref via get_first_node_in_group("player") without needing a direct reference.
	add_to_group("player")

	## Aug 2026 fix (Brannon-requested) — the player previously had ZERO
	## avoidance presence: NPCs' NavigationAgent3D avoidance already routes
	## around every other NPC's own agent and (as of the same pass) every
	## loose item's NavigationObstacle3D, but nothing registered the player
	## as anything to avoid at all — confirmed directly, no NavigationAgent3D
	## or NavigationObstacle3D existed anywhere in this file. That's the
	## literal cause of NPCs pathing straight at/into the player specifically
	## and only noticing via physics collision after the fact. A plain
	## NavigationObstacle3D (not a full NavigationAgent3D — the player isn't
	## nav-driven) sized to the real collision capsule, added once and left
	## on permanently (no held/dropped lifecycle to manage, unlike an item).
	_navigation_obstacle = NavigationObstacle3D.new()
	_navigation_obstacle.name = "PlayerNavObstacle"
	_navigation_obstacle.radius = 0.4
	_navigation_obstacle.height = 1.8
	if collision != null and collision.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
		_navigation_obstacle.radius = capsule.radius
		_navigation_obstacle.height = capsule.height
	_navigation_obstacle.avoidance_enabled = true
	add_child(_navigation_obstacle)

	_player_medical = get_tree().get_first_node_in_group("player_medical") as PlayerMedical
	var feedback := preload("res://scripts/player/medical/ExertionFeedback.gd").new()
	feedback.player = self
	add_child(feedback)

	## Controller support guard (Aug 2026) — the Xbox gamepad bindings are
	## defined in project.godot's Input Map, but the editor rewrites that
	## file from its in-memory state and can silently drop hand-added
	## joypad events. Re-adding them here makes the pad work in-game
	## regardless of what project.godot currently contains. Idempotent
	## (no-ops when a binding is already present) and purely additive —
	## keyboard bindings and movement logic are untouched.
	_ensure_joypad_bindings()

	## Aug 2026 (Player-Model subsystem) — the visible mesh's self-light/
	## shadow-cast exclusion is now applied generically by
	## PlayerModelController.gd (scripts/player/PlayerModelController.gd,
	## attached to the PlayerModel child scene) instead of hardcoded here,
	## since the real character model can have more than one
	## MeshInstance3D. See docs/systems/player-model/README.md.
	##
	## Sep 2026 — the real visible Adventurer model casts its own full-height
	## shadow when Dynamic Shadows is enabled. The former second, squashed
	## PlayerModelShadow instance was removed to avoid duplicate animation and
	## skinning work and to restore physically correct shadow proportions.

func _process(delta: float) -> void:
	# Chair/bed sequences disable physics; genuine rest must still recover.
	if not dead and not is_physics_processing() and (is_instance_valid(seated_chair) or is_instance_valid(sleeping_bed)):
		_update_exertion(delta, false, false)

func _physics_process(delta: float) -> void:
	if _movement_locked or _job_locked:
		_is_sprinting = false
		_is_moving = false
		_sprint_toggle = false
		# Actual sleep recovers exertion. Other movement locks suspend it:
		# opening a menu cannot hide an accident or reset accumulated strain.
		if not dead and sleeping_bed != null:
			_update_exertion(delta, false, false)
		else:
			exertion.suspend()
		## Still apply gravity/move_and_slide so the player doesn't float or
		## clip through the floor while the menu (or a job) is active — just
		## skip WASD/sprint/interact input handling.
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		velocity.x = 0.0
		velocity.z = 0.0
		_sync_navigation_obstacle_velocity()
		move_and_slide()
		PickupableItem.shove_small_items_near(self, _shove_cooldown_by_item)
		return
	_handle_movement(delta)
	_handle_interaction_input()

func _handle_movement(delta: float) -> void:
	# Apply gravity so the player falls when not on the floor
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	## Text entry owns WASD only while an actual LineEdit has focus. Ordinary
	## in-world inspectors still allow movement exactly as before.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		input_dir = Vector2.ZERO
	## Rotate raw input by camera yaw so W always means "away from camera"
	## regardless of which direction the camera is currently facing.
	var raw: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	var direction: Vector3 = raw.rotated(Vector3.UP, camera_yaw_rad)

	var wants_sprint: bool = (Input.is_action_pressed("sprint") or _sprint_toggle) \
		and direction.length_squared() > 0.0
	_is_sprinting = wants_sprint
	if direction.length_squared() <= 0.0:
		_sprint_toggle = false
	var carrying_heavy: bool = false
	if interaction_system != null:
		var held: Node = get_held_item()
		carrying_heavy = is_instance_valid(held) and held.has_method("is_heavy_item") and held.is_heavy_item()
	_update_exertion(delta, wants_sprint, carrying_heavy)

	var target_speed: float = sprint_speed if _is_sprinting else move_speed
	target_speed *= exertion.movement_multiplier(_is_sprinting)
	## Medical system (Aug 2026) — injuries/illness can slow the player.
	## PlayerMedical.get_medical_speed_multiplier() returns 1.0 (no effect)
	## when no conditions are active, so this is a no-op until Medical
	## actually sets a condition's speed_mult away from 1.0. See
	## docs/systems/medical/README.md.
	var pm_speed: PlayerMedical = _get_player_medical()
	if pm_speed != null:
		target_speed *= pm_speed.get_medical_speed_multiplier()

	if direction.length_squared() > 0.0:
		velocity = velocity.lerp(direction * target_speed, acceleration * delta)
		_is_moving = true
	else:
		velocity = velocity.lerp(Vector3.ZERO, friction * delta)
		_is_moving = false

	## Facing (Aug 2026 controller pass) — right stick (aim) steers the
	## facing angle and takes priority; otherwise the character faces its
	## movement direction as before. Both are rotated by camera yaw so they
	## stay camera-relative, matching the movement vector above. Turning
	## eases toward the target angle with frame-rate-independent exponential
	## smoothing (lerp_angle, see @GlobalScope.lerp_angle) instead of
	## snapping, which is the standard smooth-turning pattern for twin-stick
	## aiming in Godot.
	##
	## Aug 2026 build mode: the right stick is reserved for the build-mode
	## cursor / deconstruct / duplicate tools, so the look-steer is disabled
	## while in build mode — the character then faces its movement direction.
	var aim_dir: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var target_angle: float = rotation.y
	if aim_dir.length_squared() > AIM_DEADZONE_SQ and not _build_mode_active() \
			and not ControllerUINavigation.owns_directional_input(get_tree()):
		var aim_raw: Vector3 = Vector3(aim_dir.x, 0.0, aim_dir.y).rotated(Vector3.UP, camera_yaw_rad)
		target_angle = atan2(-aim_raw.x, -aim_raw.z)
	elif direction.length_squared() > 0.0:
		target_angle = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 1.0 - exp(-TURN_SMOOTH_SPEED * delta))

	_sync_navigation_obstacle_velocity()
	move_and_slide()
	PickupableItem.shove_small_items_near(self, _shove_cooldown_by_item)

## Radius-based NavigationObstacle3D motion is predictive only when its
## velocity is supplied regularly. Publish both movement and true stationary
## frames so NPC avoidance always sees the player's current intent.
func _sync_navigation_obstacle_velocity() -> void:
	if _navigation_obstacle == null or not is_instance_valid(_navigation_obstacle):
		return
	_navigation_obstacle.velocity = Vector3(velocity.x, 0.0, velocity.z)

## True while Build Mode is active (InteractionSystem.build_mode_active, set
## by MainWorld on enter/exit). Build mode reserves the right stick for the
## cursor / deconstruct / duplicate tools, so the player's look-steer is
## disabled then (see the facing block above).
func _build_mode_active() -> bool:
	return interaction_system != null and interaction_system.build_mode_active

func _handle_interaction_input() -> void:
	if Input.is_action_just_pressed("interact"):
		interacted.emit()

# ─── NPC-facing contract (Relationship Snatch feature, Aug 2026) ──────────────
## Read-only. NPC-side code resolves this node via
## get_tree().get_first_node_in_group("player") and calls these two
## directly, the same way it already does for other player-facing calls.
## Feature logic (when/why a snatch happens) is entirely NPC-owned — this
## side only reports what's held and cleans up bookkeeping after a snatch.

## Returns whatever the player is currently holding, or null if
## empty-handed. Used by NPC-side code purely for detection/classification
## — it does not touch the returned item.
func get_held_item() -> Node:
	if interaction_system == null:
		return null
	## Aug 2026 (hardened, twice): the local is deliberately UNTYPED and the
	## validity gate is is_instance_valid() ALONE. The original typed read
	## (`var item: Node = held_item`) threw "Trying to assign invalid
	## previously freed instance" before any guard could run; the first fix's
	## `item != null and not is_instance_valid(item)` guard then slipped
	## through because in Godot 4 a freed reference can compare EQUAL to
	## null, so the dangling ref still reached `return item` and threw
	## "Trying to return a previously freed instance". is_instance_valid()
	## is the only check that reliably sees through that.
	var item = interaction_system.held_item
	if is_instance_valid(item):
		return item
	## Freed or null. Clear any stale reference (a no-op when the player is
	## genuinely empty-handed) so the dangling ref self-heals exactly once
	## instead of erroring every frame.
	interaction_system.held_item       = null
	interaction_system._held_from_slot = -1
	return null

## Called by NPC-side code the instant a snatch succeeds — by that point
## the item has already been physically reassigned to the NPC
## (item.pickup(npc.hold_point), npc.held_item = item). This only clears
## this side's own bookkeeping so it doesn't desync, same failure mode as
## the earlier Give-stuck bug.
func on_item_snatched() -> void:
	if interaction_system != null and interaction_system.has_method("clear_held_item_external"):
		interaction_system.clear_held_item_external()

## Forwards to InteractionSystem.release_held_item_to_npc() — NPC-side
## code only has this Player node (via the "player" group), never
## InteractionSystem directly, so this is the reachable entry point for
## Snatch to use the exact same transfer path Give uses.
func release_held_item_to_npc(npc: Node) -> bool:
	return interaction_system.release_held_item_to_npc(npc) if interaction_system != null else false

func _unhandled_input(event: InputEvent) -> void:
	## Aug 2026 — the sit/lie animation is locked in: swallow ALL player-level
	## input until it plays out, so a keypress can't interrupt or shift the
	## sequence (e.g. WASD walking out of the chair mid-animation).
	if is_animation_locked():
		return
	## Right-stick click toggles Focus Mode (Aug 2026) — same interaction
	## highlighting Ctrl gives, latched instead of held. Ctrl still works
	## as a hold; see the FocusMode autoload.
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_STICK and event.pressed:
		if not ControllerUINavigation.owns_directional_input(get_tree()):
			FocusMode.toggle()
		get_viewport().set_input_as_handled()
		return
	## Left-stick click toggles sprint (Aug 2026) — a quick click latches
	## running until the player stops or clicks again, including during overdrive.
	## Only from a joypad so keyboard Shift keeps its hold-to-sprint feel.
	## Consumed even in menus (movement is locked there anyway, so the
	## toggle flip is guarded below).
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_STICK and event.pressed:
		if not _movement_locked:
			_sprint_toggle = not _sprint_toggle
		get_viewport().set_input_as_handled()
		return
	if seated_chair == null or not is_instance_valid(seated_chair):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	## Any of the four movement actions stands the player up immediately —
	## "walking out" of the chair rather than requiring a separate E press
	## first. No extra movement-injection needed: seated_chair.on_interact()
	## re-enables _physics_process() via the existing stand_requested wiring
	## above, and since the key that triggered this is still physically held
	## down, the very next _physics_process tick's Input.get_vector() read
	## picks it up naturally — movement starts on its own.
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") \
			or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down"):
		seated_chair.on_interact()

## ── Controller support guard (Aug 2026) ───────────────────────────────
## The gamepad bindings below mirror project.godot's [input] section so
## they can be re-applied at runtime if the editor's project.godot rewrite
## dropped them. All three helpers are idempotent — they only ADD an event
## when the exact binding is missing, and never touch the keyboard events.
func _ensure_joypad_bindings() -> void:
	_ensure_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_ensure_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_ensure_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_ensure_joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_ensure_joy_button("interact", JOY_BUTTON_A)
	_ensure_joy_button("pickup", JOY_BUTTON_X)
	_ensure_joy_button("store_item", JOY_BUTTON_Y)
	_ensure_joy_button("inv_slot_1", JOY_BUTTON_DPAD_UP)
	_ensure_joy_button("inv_slot_3", JOY_BUTTON_DPAD_DOWN)
	_ensure_joy_button("inv_cycle_next", JOY_BUTTON_DPAD_RIGHT)
	_ensure_joy_button("inv_cycle_prev", JOY_BUTTON_DPAD_LEFT)
	_ensure_joy_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_ensure_joy_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_ensure_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_ensure_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)

func _ensure_joy_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.axis == axis and is_equal_approx(ev.axis_value, value):
			return
	var ne := InputEventJoypadMotion.new()
	ne.axis = axis
	ne.axis_value = value
	InputMap.action_add_event(action, ne)

func _ensure_joy_button(action: String, idx: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == idx:
			return
	var ne := InputEventJoypadButton.new()
	ne.button_index = idx
	InputMap.action_add_event(action, ne)

## Stamina and exposure use active seconds, independent of the survival clock.
func _update_exertion(delta: float, sprinting: bool, carrying: bool) -> void:
	var medical: PlayerMedical = _get_player_medical()
	var drain: float = 0.0
	if sprinting:
		drain += sprint_stamina_drain * (medical.get_medical_sprint_stamina_drain_multiplier() if medical != null else 1.0)
	if carrying:
		drain += heavy_carry_stamina_drain * (medical.get_medical_carry_stamina_drain_multiplier() if medical != null else 1.0)
	stamina = exertion.advance(delta, stamina, sprinting, carrying, drain, stamina_regen, sprint_recover_threshold)
	if exertion.just_exhausted:
		exhausted.emit(sprinting, carrying)
	exertion_updated.emit()
	stamina_changed.emit(stamina)

func get_exertion_save_data() -> Dictionary:
	return exertion.get_save_data(stamina)

func restore_exertion_save_data(data: Dictionary) -> void:
	stamina = exertion.restore(data)
	_sprint_toggle = false
	stamina_changed.emit(stamina)
