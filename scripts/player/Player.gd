class_name Player
extends CharacterBody3D
## Player.gd
## Handles WASD movement, animation state, and basic interaction input.
## Attach to: res://scenes/player/Player.tscn (CharacterBody3D root)

# ─── Exports (tweak in Inspector) ────────────────────────────────────────────
@export var move_speed: float = 4.0        ## Base walk speed (20% slower than original 5.0)
@export var sprint_speed: float = 7.5      ## Sprint speed (1.5× walk — feels punchy but not insane)
@export var acceleration: float = 12.0
@export var friction: float = 16.0

## Stamina drained per second while sprinting (0–100 scale)
@export var sprint_stamina_drain: float = 18.0
## Stamina recovered per second while not sprinting
@export var stamina_regen: float = 8.0

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var interaction_system: Node = $InteractionSystem

## Stamina must recover to this before sprinting is allowed again (prevents flicker)
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

## Set each frame by MainWorld to match the camera's current yaw.
## Movement input is rotated by this so controls always feel camera-relative.
var camera_yaw_rad: float = 0.0
var _is_moving: bool = false
var _is_sprinting: bool = false
var _sprint_locked: bool = false  ## true when exhausted, blocks sprint until threshold met

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

func set_movement_locked(locked: bool) -> void:
	_movement_locked = locked
	if locked:
		velocity = Vector3.ZERO

# ─── Signals ──────────────────────────────────────────────────────────────────
signal interacted()
signal stamina_changed(new_value: float)   ## Emit so HUD / PlayerStats can react

func _ready() -> void:
	## Register in "player" group so items (e.g. Flashlight) can resolve the
	## player ref via get_first_node_in_group("player") without needing a direct reference.
	add_to_group("player")

	## Aug 2026 (Player-Model subsystem) — the visible mesh's self-light/
	## shadow-cast exclusion is now applied generically by
	## PlayerModelController.gd (scripts/player/PlayerModelController.gd,
	## attached to the PlayerModel child scene) instead of hardcoded here,
	## since the real character model can have more than one
	## MeshInstance3D. See docs/systems/player-model/README.md.
	##
	## Aug 2026 — the capsule-based CharacterShadowStandIn system (still
	## used by NPC.gd, unaffected by this change) has been replaced for
	## the Player specifically by a second, scaled-down PlayerModel
	## instance ("PlayerModelShadow" in Player.tscn) that casts a real
	## shadow reflecting the actual animated silhouette instead of a
	## pill shape — see docs/systems/graphics/README.md "Player
	## model-based shadow". Nothing to call here: the shadow instance is
	## wired declaratively in the scene file and drives its own animation
	## state by reading this same Player node, same as the real model.

func _physics_process(delta: float) -> void:
	if _movement_locked:
		## Still apply gravity/move_and_slide so the player doesn't float or
		## clip through the floor while the menu is open — just skip WASD/
		## sprint/interact input handling.
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
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
	## Rotate raw input by camera yaw so W always means "away from camera"
	## regardless of which direction the camera is currently facing.
	var raw: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	var direction: Vector3 = raw.rotated(Vector3.UP, camera_yaw_rad)

	# Unlock sprint once stamina recovers past threshold
	if _sprint_locked and stamina >= sprint_recover_threshold:
		_sprint_locked = false

	# Sprint only while moving, shift held, not locked out
	var wants_sprint: bool = Input.is_action_pressed("sprint") and direction.length_squared() > 0.0
	_is_sprinting = wants_sprint and not _sprint_locked

	# Drain / regen stamina
	if _is_sprinting:
		stamina = maxf(0.0, stamina - sprint_stamina_drain * delta)
		if stamina == 0.0:
			_sprint_locked = true  ## exhausted — force walk until recovered
	else:
		stamina = minf(100.0, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina)

	var target_speed: float = sprint_speed if _is_sprinting else move_speed

	if direction.length_squared() > 0.0:
		velocity = velocity.lerp(direction * target_speed, acceleration * delta)
		_is_moving = true

		# Face movement direction
		var angle: float = atan2(-direction.x, -direction.z)
		rotation.y = angle
	else:
		velocity = velocity.lerp(Vector3.ZERO, friction * delta)
		_is_moving = false

	move_and_slide()

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
	## Aug 2026 (hardened) — read the field exactly once into a local
	## rather than up to three separate property accesses
	## (!=null check, is_instance_valid() argument, final return). Can't
	## fully verify from static analysis whether repeated access on a
	## just-freed reference is perfectly consistent across all three
	## reads, and there's no reason to take that risk when reading once
	## and reusing the local costs nothing.
	var item: Node = interaction_system.held_item
	if item != null and not is_instance_valid(item):
		## Freed externally without going through the normal drop/give
		## cleanup — self-heal the same way InteractionSystem._update_prompt()'s
		## existing guard already does for this exact scenario (see that
		## function's own comment), rather than handing back a dangling
		## reference to whatever NPC-side code called this. Clears both
		## fields, matching that guard exactly — held_item alone isn't
		## enough, or _held_from_slot is left stale.
		interaction_system.held_item       = null
		interaction_system._held_from_slot = -1
		return null
	return item

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
