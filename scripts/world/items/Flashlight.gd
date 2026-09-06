extends PickupableItem
## Flashlight.gd
## Pickupable flashlight. Toggle on/off with [E] while held.
## Auto-aims the beam in the direction the player is facing.
## Battery drains over time; recharging not yet implemented.

# ─── Config ───────────────────────────────────────────────────────────────────
const BATTERY_DRAIN:    float = 0.8    ## % per real second while on
const CONE_ANGLE:       float = 22.0   ## SpotLight3D inner angle
const CONE_OUTER:       float = 30.0   ## SpotLight3D outer angle
const LIGHT_RANGE:      float = 14.0   ## metres
const LIGHT_ENERGY:     float = 2.8

## Slight downward tilt so beam hits the floor ahead, not the horizon.
const BEAM_PITCH_DEG:   float = -12.0

## Shelf config
var shelf_stack_limit: int  = 1
var shelf_item_type:   String = "flashlight"

# ─── State ────────────────────────────────────────────────────────────────────
var _player:           Node3D = null   ## CharacterBody3D — set on pickup

var _on:         bool  = false
var _battery:    float = 100.0  ## 0–100
var _is_dead:    bool  = false

# ─── Node refs ────────────────────────────────────────────────────────────────
var _spot:       SpotLight3D        = null
var _dust:       GPUParticles3D     = null   ## beam dust motes, see DustMotes.gd
var _body_mesh:  MeshInstance3D     = null
var _lens_mat:   StandardMaterial3D = null
var _model:      Node3D             = null   ## flipped visual-model container, see _build_mesh

# ─── Colours ──────────────────────────────────────────────────────────────────
const COL_ON:   Color = Color(1.0,  0.98, 0.88, 1.0)   ## warm white
const COL_LOW:  Color = Color(0.95, 0.75, 0.20, 1.0)   ## orange-yellow
const COL_DEAD: Color = Color(0.30, 0.30, 0.32, 0.55)  ## gray

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")

	## Excluded from CTRL manual-upright (see PickupableItem.
	## _physics_process()'s CTRL branch) — this item's rotation IS its aim
	## direction (auto-aimed along the player's facing, per the header
	## comment above), so forcing it upright while held would fight the
	## entire point of holding one. Set here rather than as a var
	## redeclaration — GDScript doesn't allow shadowing a var that already
	## exists on the parent class (PickupableItem already declares
	## allow_manual_upright), even to override its default value.
	allow_manual_upright = false

	_build_mesh()
	_build_light()
	_build_collision()
	_refresh_state()

# ─── Visual Construction ──────────────────────────────────────────────────────
func _build_mesh() -> void:
	## Flashlight body: cylinder (handle) + wider cylinder (head) + lens cap.
	## Everything lies along local +Z so the light points forward naturally.
	##
	## Aug 2026 — the whole model sits under a "Model" container that is
	## reversed 180° around Y, so the head/lens visually point the correct
	## way in the player's hand. Only the model is flipped — the
	## SpotLight3D, dust, collision, and auto-aim logic are unchanged.
	var model: Node3D = Node3D.new()
	model.name = "Model"
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(model)
	_model = model

	## Handle — thin long cylinder along +Z
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	var handle_mesh: CylinderMesh = CylinderMesh.new()
	handle_mesh.top_radius      = 0.040
	handle_mesh.bottom_radius   = 0.038
	handle_mesh.height          = 0.24
	handle_mesh.radial_segments = 10
	handle_mi.mesh = handle_mesh
	## CylinderMesh is Y-up by default; rotate 90° on X so it lies along Z.
	handle_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	handle_mi.position         = Vector3(0.0, 0.0, 0.0)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	body_mat.roughness    = 0.75
	body_mat.metallic     = 0.6
	handle_mi.set_surface_override_material(0, body_mat)
	## Aug 2026 — the earlier flashlight self-shadow fix only excluded the
	## PLAYER's own body from this light's shadow; it never addressed the
	## flashlight's own housing meshes (this one, head_mi, lens_mi below),
	## which sit essentially touching the SpotLight3D itself (_spot is at
	## local Z=0.20; this handle's own geometry extends right up near it).
	## That's almost certainly the actual dome — the flashlight casting a
	## shadow of its own housing directly into the center of its own beam,
	## independent of the player entirely. Global cast_shadow=OFF here
	## rather than another light_cull_mask exclusion — nothing would ever
	## want a shadow from a tiny handheld prop anyway, from any light, so
	## there's no reason to scope this to the flashlight's own spot only.
	handle_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(handle_mi)
	_body_mesh = handle_mi

	## Head — wider, shorter, pushed forward along +Z
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius      = 0.045
	head_mesh.bottom_radius   = 0.055
	head_mesh.height          = 0.06
	head_mesh.radial_segments = 10
	head_mi.mesh = head_mesh
	head_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	head_mi.position         = Vector3(0.0, 0.0, 0.15)

	var head_mat: StandardMaterial3D = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.15, 0.15, 0.18, 1.0)
	head_mat.roughness    = 0.65
	head_mat.metallic     = 0.7
	head_mi.set_surface_override_material(0, head_mat)
	## Aug 2026 — see handle_mi's comment above. This one sits even closer
	## to the light (local Z=0.15 vs. the spot's own Z=0.20).
	head_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(head_mi)

	## Lens cap — thin glowing disk at the very tip
	var lens_mi: MeshInstance3D = MeshInstance3D.new()
	var lens_mesh: CylinderMesh = CylinderMesh.new()
	lens_mesh.top_radius      = 0.044
	lens_mesh.bottom_radius   = 0.044
	lens_mesh.height          = 0.005
	lens_mesh.radial_segments = 14
	lens_mi.mesh = lens_mesh
	lens_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	lens_mi.position         = Vector3(0.0, 0.0, 0.182)

	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color               = COL_DEAD
	_lens_mat.emission_enabled           = true
	_lens_mat.emission                   = COL_DEAD
	_lens_mat.emission_energy_multiplier = 0.0
	_lens_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mi.set_surface_override_material(0, _lens_mat)
	## Aug 2026 — see handle_mi's comment above. This is the closest of the
	## three to the light (local Z=0.182 vs. the spot's own Z=0.20, just
	## 0.018 apart — essentially touching) and the most likely single
	## biggest contributor to the dome.
	lens_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(lens_mi)

func _build_light() -> void:
	_spot = SpotLight3D.new()
	## Positioned at the lens tip, pointing along +Z (forward).
	## A small downward pitch (BEAM_PITCH_DEG) makes it illuminate the floor
	## ahead of the player rather than shooting into the far wall at eye level.
	_spot.position               = Vector3(0.0, 0.0, 0.20)
	_spot.rotation_degrees       = Vector3(BEAM_PITCH_DEG, 0.0, 0.0)
	_spot.spot_angle             = CONE_OUTER
	_spot.spot_angle_attenuation = 0.5
	_spot.spot_range             = LIGHT_RANGE
	_spot.light_energy           = LIGHT_ENERGY
	_spot.light_color            = COL_ON
	## Excludes the player's own mesh from this light's illumination/shadow
	## computation entirely — a handheld light this close to the player's
	## own body otherwise self-shadows a dome right into the center of its
	## own beam once shadow casting is on (see
	## docs/systems/graphics/README.md "Flashlight self-shadow exclusion").
	## Player.gd tags its mesh with ONLY this bit (see
	## Player.PLAYER_SELF_LIGHT_LAYER_BIT for why it's a replacement, not an
	## addition) specifically so THIS is the only light in the game that
	## stops seeing the player — every other light keeps its default cull
	## mask and still lights/shadows the player normally. (Aug 2026 —
	## reverted back to this narrower, original form after a brief detour
	## generalizing it to exclude all characters from every light; see
	## docs/systems/graphics/README.md "Aggregated character shadows" for
	## the postmortem on why that was reverted.)
	_spot.light_cull_mask = _spot.light_cull_mask & ~Player.PLAYER_SELF_LIGHT_LAYER_BIT
	_spot.visible                = false   ## off at spawn
	_apply_graphics_settings()
	add_child(_spot)

	## Dust motes drifting through the beam — dust-mote scope was flagged for
	## VFX priority #1 in the graphics plan. Emitting is toggled with the
	## beam in _refresh_state(); off at spawn to match _spot.
	## Parented to the flipped model container (not the spot) so the dust
	## reverses 180° WITH the model — position mirrors the original spot-
	## relative +0.35 into model-local +0.35, which the container's 180° Y
	## flip lands at the head side of the flashlight.
	_dust = DustMotes.create_beam_dust(CONE_OUTER)
	_dust.position = Vector3(0.0, 0.0, 0.35)
	_dust.emitting = false
	if _model != null:
		_model.add_child(_dust)
	else:
		_spot.add_child(_dust)
	## Live-update if the player flips a toggle while holding this flashlight.
	GraphicsSettings.settings_changed.connect(_apply_graphics_settings)

## Applies the player's GraphicsSettings toggles to this flashlight's
## SpotLight3D. Called once at build time and again on every
## GraphicsSettings.settings_changed (preset switch or individual toggle).
func _apply_graphics_settings() -> void:
	if _spot == null:
		return
	## Aug 2026 — generalized to GraphicsSettings.shadow_casting_enabled,
	## now preset-driven (HIGH/ULTRA on, LOW/MEDIUM off) and shared with
	## WallLight/GrowLight instead of flashlight-only opt-in (see
	## docs/systems/graphics/README.md "Unified dynamic shadow casting").
	## The player-mesh self-shadow dome this used to cause is handled
	## separately and still applies regardless of this setting — see
	## Player.PLAYER_SELF_LIGHT_LAYER_BIT / the earlier
	## FLASHLIGHT_PLAYER_SELF_SHADOW_EXCLUSION_PLAN.md. (Aug 2026 — this
	## constant briefly lived on GraphicsSettings as
	## CHARACTER_SHADOW_LAYER_BIT during the now-reverted Aggregated
	## Character Shadows detour; it's back on Player.gd.)
	_spot.shadow_enabled = GraphicsSettings.shadow_casting_enabled
	## Per-light volumetric-fog contribution (Light3D property, independent
	## of Environment.volumetric_fog_enabled) — lets the dust-mote beam-shaft
	## look be toggled off for performance without disabling ambient fog
	## everywhere else. 0.0 skips volumetric-fog computation for this light.
	_spot.light_volumetric_fog_energy = 1.0 if GraphicsSettings.flashlight_volumetrics else 0.0
	## Re-run so _dust.emitting picks up a live flashlight_volumetrics change
	## immediately instead of waiting for the next unrelated state refresh.
	_refresh_state()

## Adds a CapsuleShape3D collision body oriented along +Z (the flashlight's length axis).
## Without this the RigidBody3D has no shape and Jolt physics ignores it entirely.
func _build_collision() -> void:
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.045       ## slightly wider than handle radius
	cap.height = 0.28        ## spans handle + head (~0.24 + a bit)
	col_shape.shape = cap
	## Rotate 90° on X so the capsule's long axis aligns with +Z (forward)
	col_shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(col_shape)

func _refresh_state() -> void:
	var actually_on: bool = _on and not _is_dead

	if _spot != null:
		_spot.visible = actually_on

	if _dust != null:
		_dust.emitting = actually_on and GraphicsSettings.flashlight_volumetrics

	if _lens_mat != null:
		if actually_on:
			var col: Color = COL_LOW if _battery < 20.0 else COL_ON
			_lens_mat.albedo_color               = col
			_lens_mat.emission                   = col
			_lens_mat.emission_energy_multiplier = 1.8
		else:
			_lens_mat.albedo_color               = COL_DEAD
			_lens_mat.emission                   = COL_DEAD
			_lens_mat.emission_energy_multiplier = 0.0

	## Battery % is shown via the InventoryHUD badge (get_charge_info) — no 3D label needed.

# ─── Physics + orientation ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	## Auto-off when not held (stored in inventory or dropped) — the beam is
	## only meant to be on in the player's hand, and a stashed flashlight
	## shouldn't keep draining its battery (Aug 2026).
	if not is_held and _on:
		_on = false
		_refresh_state()

	## Battery drain
	if _on and not _is_dead:
		_battery -= BATTERY_DRAIN * delta
		if _battery <= 0.0:
			_battery = 0.0
			_is_dead  = true
			_on       = false
			_refresh_state()
			charge_changed.emit()
		elif fmod(_battery, 5.0) < (BATTERY_DRAIN * delta):
			_refresh_state()
			charge_changed.emit()

	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float     = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	## Move toward hold point
	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed

	## ── Aim toward player's facing direction ──────────────────────────────────
	if _player != null and is_instance_valid(_player):
		rotation = Vector3(0.0, _player.rotation.y, 0.0)
	angular_velocity = Vector3.ZERO

# ─── Inventory charge badge ───────────────────────────────────────────────────
## InventoryHUD calls this to show the battery % badge on the slot.
func get_charge_info() -> Array:
	return [int(_battery), 100]

func get_inventory_hud_state() -> Dictionary:
	return {
		"kind": "battery",
		"fraction": clampf(_battery / 100.0, 0.0, 1.0),
	}

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Flashlight"

func get_prompt_text() -> String:
	if _is_dead:
		return "[F] Pick up  Flashlight (Dead)"
	return "[F] Pick up  Flashlight (%d%%)" % int(_battery)

func get_trash_material() -> String:
	return "metal"

func get_use_prompt() -> String:
	if _is_dead:
		return ""
	return "[E] %s flashlight" % ("Turn Off" if _on else "Turn On")

# ─── Pickup / Drop ────────────────────────────────────────────────────────────
func set_player(p: Node3D) -> void:
	## Called by InteractionSystem when this item is picked up.
	_player = p

func _on_pickup_extra() -> void:
	## Self-healing player ref: if set_player() was never called (e.g. pregen
	## inventory path), find the player via group so facing still works.
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")

func _on_drop_extra() -> void:
	_player = null

# ─── Use: toggle light ────────────────────────────────────────────────────────
func on_use() -> void:
	if _is_dead:
		return
	_on = not _on
	_refresh_state()
