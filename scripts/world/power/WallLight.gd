extends Node3D
## WallLight.gd
## Wall-mounted industrial lamp using the industrial_wall_lamp GLB model.
##
## Light: a very wide SpotLight3D aimed from the wall into the room. A wall
## fixture cannot physically emit through the concrete behind it; modelling
## that hemisphere directly avoids back-wall light halos and needs one shadow
## map instead of an OmniLight3D cubemap's six.
##
## NO COLLISION — purely visual + light-emitting Node3D.
## Called from BuildModeController._spawn_placed_object() for TILE_LIGHT = 5.
##
## POWER GRID
##   Registers with PowerManager on _ready() using power_watts.
##   PowerManager calls set_powered(bool) to toggle the light on/off.
##   PowerManager calls set_shed(true) when load-shedding — light dims to a
##   faint orange glow rather than going fully dark.

# ─── Debug ────────────────────────────────────────────────────────────────────
## Gated by DebugOutput.enabled (F7 "Disable All Debug Outputs").
func _wdbg(msg: String) -> void:
	if DebugOutput.enabled:
		print(msg)

# ─── Model path ───────────────────────────────────────────────────────────────
const MODEL_PATH: String = "res://assets/models/industrial_wall_lamp.glb"

# ─── Fixture geometry constants (match GLB bounds exactly) ───────────────────
const LAMP_W: float = 0.2735
const LAMP_H: float = 0.4300
const LAMP_D: float = 0.1404

## Vertical offset from node origin to lamp centre (~3/4 wall height).
const LAMP_Y_OFFSET: float = 1.5

# ─── Room-facing light constants ─────────────────────────────────────────────
## Warm industrial amber — noticeably warm, not clinical white
const LIGHT_COLOR:  Color = Color(1.0, 0.82, 0.50, 1.0)
## Lowered from 4.5 (July 2026 lighting-blowout fix) — 4.5 was tuned before
## glow/SDFGI/volumetric fog existed in the project; once those post-process
## systems came online they amplified the same raw value well past what
## looked right originally. Let glow/bloom sell "bright at the source"
## instead of flooding the whole room via raw light energy.
const LIGHT_ENERGY: float = 2.0
const LIGHT_RANGE:  float = 10.0
## Godot's spot_angle is the half-angle. 78° produces a broad 156° room-side
## hemisphere without spending shadow work behind or parallel to the wall.
const LIGHT_SPOT_ANGLE: float = 78.0
## Conservative contact offsets for closed bunker geometry. Godot's much
## larger defaults visibly detach a thin wall's shadow from the floor/wall,
## reading as a bright bubble around player-built BoxMesh walls.
const SHADOW_BIAS: float = 0.025
const SHADOW_NORMAL_BIAS: float = 0.20
## Emissive bulb energy (Aug 2026) — intentionally LOW: the warm amber bulb
## should read as a subtle glow, not a bright blob (the GLB's emissive asset
## was authored as a generic white glow; see _apply_matte_override).
const BULB_EMISSION_ENERGY: float = 0.4
## Per-light volumetric-fog contribution (July 2026 lighting-blowout fix).
## Godot's default is 1.0 (full contribution) — left at default, every wall
## light was scattering its full warm glow through the whole fog volume,
## turning "distinct pools of light with dark corners between" into
## "uniformly hazy room." Reserves the visible fog-shaft look specifically
## for the flashlight (the intended showcase per the graphics plan's design
## thesis), not ambient room lights.
const LIGHT_VOLUMETRIC_FOG_ENERGY: float = 0.2

## Shed (overloaded grid) state — faint orange glow, barely visible
const SHED_COLOR:   Color = Color(1.0, 0.45, 0.0, 1.0)
const SHED_ENERGY:  float = 0.15   ## very low — just enough to suggest the filament is warm

# ─── Power grid ───────────────────────────────────────────────────────────────
## Rated power draw in watts. Matches DeviceDatabase.WATT_RATINGS["wall_light"].
var power_watts: float = 40.0

## Internal reference to the room-facing light — needed for power state.
var _light: SpotLight3D = null

## Emissive bulb (Aug 2026) — the GLB's authored emissive texture is preserved
## through the matte override so the bulb itself glows (1:1 with the model's
## look), driven by the same power/shed state as the omni. Null until the
## emissive surface is found during _apply_matte_override().
var _bulb_material: StandardMaterial3D = null
## Authored emission tint/energy — what "lit" looks like per the model.
var _bulb_lit_color:  Color = Color(1, 1, 1, 1)
var _bulb_lit_energy: float = 1.0

## Priority tier: 1 (critical) … 5 (luxury). Wall lights default to 1
## (critical/never-shed) — both pregen level-start lights and player-placed
## lights use this same default since they're the same WallLight.gd scene
## either way. Player can still change it per-instance via the priority
## panel (E to interact) same as any other consumer.
var power_priority: int = 1

## Snap key returned by PowerManager.register_wire_node() — needed to
## unregister the wire node in _exit_tree(). Empty until registered.
var _pm_node_key: String = ""
var _wire_attachment: WallWireAttachment = null

## Set TRUE by preview systems (GhostModelBuilder.build_real_instance)
## BEFORE add_child(), so a preview thumbnail still builds its fixture
## visuals but skips joining the "wall_lights" group AND skips registering a
## real PowerManager wire node/consumer. Previously missing this guard while
## being registered in PROCEDURAL_PREVIEW_SOURCES, so every Build Mode
## Construct-menu preview created a live phantom power node at the preview
## instance's ~world-origin position (underground, NE of the bunker). Same
## convention as Stove.gd/GeneratorObject.gd — see GhostModelBuilder.gd's
## build_real_instance() doc.
var _is_preview_only: bool = false

## Track shed state so set_powered(true) knows to restore full brightness.
var _is_shed: bool = false

## Lazily-created shared priority panel (PowerPriorityUI). Reused across opens.
var _prio_ui: CanvasLayer = null
## Tracks whether the player is currently powered (for the interact prompt).
var _is_powered: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_meta("tile_id", 5)
	if not _is_preview_only:
		add_to_group("wall_lights")
		## Defer power registration so global_position is correct.
		## add_child() sets position AFTER _ready() runs, so calling
		## register_wire_node() here would snap to Vector3.ZERO.
		call_deferred("_register_wire_deferred")
	_build_fixture()

func _exit_tree() -> void:
	## Unregister from the power graph when removed from the scene.
	## Wire node FIRST — that triggers the network re-solve.
	## Consumer SECOND — graph no longer references this device.
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if _pm_node_key != "":
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))

# ─── Power grid API ──────────────────────────────────────────────────────────

## Called by PowerManager when the grid trips or restores power.
## When turning off via this call it means a hard power-cut (not shedding),
## so the light goes fully dark.
func set_powered(on: bool) -> void:
	_is_powered = on
	if on:
		## Restore full brightness — clear shed state.
		_is_shed = false
	if _light != null:
		if on:
			_light.light_color  = LIGHT_COLOR
			_light.light_energy = LIGHT_ENERGY
			_light.visible      = true
		else:
			## Hard power-cut — always go fully dark regardless of shed state.
			_light.visible = false
	_apply_bulb_state()


## Called by PowerManager._apply_shed_to_consumer() when this light is
## load-shed during an overloaded grid. Shows a faint orange glow instead of going dark.
## The player can see the light is "on" but starved for power.
func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on
	if _light != null:
		if shed_on:
			_light.light_color  = SHED_COLOR
			_light.light_energy = SHED_ENERGY
			_light.visible      = true   ## dimly visible — not off
	_apply_bulb_state()


## Mirrors the omni's power/shed state onto the emissive bulb material so the
## bulb itself glows: full warmth when powered, faint orange when shed, dark
## on a hard power-cut. The emission color/energy are the model's authored
## values (texture carries the warmth), overridden to orange for shed.
func _apply_bulb_state() -> void:
	if _bulb_material == null:
		return
	if _is_powered:
		_bulb_material.emission = _bulb_lit_color
		_bulb_material.emission_energy_multiplier = _bulb_lit_energy
	elif _is_shed:
		_bulb_material.emission = SHED_COLOR
		_bulb_material.emission_energy_multiplier = _bulb_lit_energy * 0.2
	else:
		_bulb_material.emission_energy_multiplier = 0.0


# ─── Priority interaction (forwarded by PowerPriorityInteractable proxy) ─────
## Opens the shared PowerPriorityUI for this light. No load toggle — lights are
## always "on" when wired; their visibility is driven by the grid/shed state.
func on_priority_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _prio_ui == null or not is_instance_valid(_prio_ui):
		var ui_script: GDScript = load("res://scripts/ui/power/PowerPriorityUI.gd")
		if ui_script == null:
			push_warning("WallLight: PowerPriorityUI.gd not found")
			return
		_prio_ui = CanvasLayer.new()
		_prio_ui.set_script(ui_script)
		_prio_ui.name = "PowerPriorityUI"
		get_tree().get_root().add_child(_prio_ui)
		if _prio_ui.has_signal("closed"):
			_prio_ui.closed.connect(_on_prio_closed)
		if _prio_ui.has_signal("priority_changed"):
			_prio_ui.priority_changed.connect(_on_prio_changed)

	if _prio_ui.has_method("open"):
		_prio_ui.call("open", str(get_instance_id()), "Wall Light", false, global_position, self)

func get_priority_prompt() -> String:
	return "[E] Wall Light"

func _on_prio_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false

func _on_prio_changed(_id: String, value: int) -> void:
	## Keep our local copy in sync (PowerManager is the source of truth, but this
	## keeps the interact prompt accurate without an extra query).
	power_priority = value

# ─── Interaction-system lookup (same pattern as GeneratorObject) ─────────────
func _get_interaction_system() -> Node:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			for sub: Node in (child as Node3D).get_children():
				if sub is CharacterBody3D:
					for s2: Node in sub.get_children():
						if s2.get_script() != null and str(s2.get_script().resource_path).contains("InteractionSystem"):
							return s2
	return null


## Called one frame after _ready() so global_position is fully resolved.
## After registration, schedule a second auto-connect attempt one more frame
## later — this guarantees the perimeter wire edges exist by the time we search,
## even if the perimeter build happened in the same frame as _ready().
func _register_wire_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	pm.begin_bulk()
	pm.register_consumer(str(get_instance_id()), power_watts, self, "wall_light", power_priority, true)
	_pm_node_key = pm.register_wire_node(global_position, "consumer", str(get_instance_id()), true)
	pm.end_bulk()
	_wire_attachment = WallWireAttachment.new()
	add_child(_wire_attachment)
	_wire_attachment.bind(self, pm, _pm_node_key)

func refresh_power_attachment() -> void:
	if is_instance_valid(_wire_attachment):
		_wire_attachment.request_refresh()

func get_wall_wire_connector() -> Vector3:
	return to_global(Vector3(0.0, LAMP_Y_OFFSET, 0.0))


func _build_fixture() -> void:
	# ── Load GLB model ────────────────────────────────────────────────────────
	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null

	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position        = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
			model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			_remove_collision_recursive(model)
			add_child(model)
			_apply_matte_override(model)
	else:
		# Fallback box if model missing
		var mi: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(LAMP_W, LAMP_H, LAMP_D)
		mi.mesh = bm
		mi.position = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
		mat.metallic     = 0.0
		mat.roughness    = 1.0
		mi.set_surface_override_material(0, mat)
		add_child(mi)

	# ── Wide SpotLight3D — one room-side shadow map, never lights wall rear ─────
	var light := SpotLight3D.new()
	light.light_color           = LIGHT_COLOR
	light.light_energy          = LIGHT_ENERGY
	light.spot_range            = LIGHT_RANGE
	light.spot_angle            = LIGHT_SPOT_ANGLE
	light.spot_angle_attenuation = 0.22
	light.spot_attenuation      = 0.6
	light.light_indirect_energy = 1.0
	light.light_volumetric_fog_energy = LIGHT_VOLUMETRIC_FOG_ENERGY
	## WallLight's local -Z is the room-facing normal used by placement. Offset
	## the source just beyond the shade/wall face so the caster starts cleanly.
	light.position              = Vector3(0.0, LAMP_Y_OFFSET, -LAMP_D * 0.65)
	## Aug 2026 — this fixture briefly excluded characters from its
	## light_cull_mask (Aggregated Character Shadows plan), reverted (see
	## docs/systems/graphics/README.md "Aggregated character shadows" for
	## the postmortem). Back to default cull mask — lights and shadows the
	## player/NPCs completely normally, same as any other object in the
	## room. get_shadow_weight() below is retained as dead code — its only
	## consumer was the fake-shadow decal system, replaced by the stand-in
	## system (see docs/systems/graphics/README.md "Character shadow
	## stand-in"); kept, not scheduled for removal.
	## START DARK — light only turns on when PowerManager calls set_powered(true).
	light.visible = false
	add_child(light)
	_light = light
	## Sep 2026 — ALWAYS-ON shadow casting (the "classic" two-layer split):
	## the room-facing spot always casts, so walls/pillars ALWAYS occlude it and the hard
	## shadow cutoff at walls/corners is present at every quality preset. This
	## is independent of GraphicsSettings.shadow_casting_enabled, which now
	## only gates the DYNAMIC (character/object) shadow layer — that gating is
	## applied per-mesh by GraphicsSettings._apply_dynamic_shadow_casting(),
	## not here.
	light.shadow_enabled = true
	light.shadow_bias = SHADOW_BIAS
	light.shadow_normal_bias = SHADOW_NORMAL_BIAS

	# ── Interaction proxy — lets the player press E to set power priority ──────
	## WallLight is a plain Node3D (no body), so we attach a small StaticBody3D
	## proxy that the InteractionSystem can pick up. It forwards on_interact()
	## back to this light's on_priority_interact().
	var proxy_script: GDScript = load("res://scripts/world/power/PowerPriorityInteractable.gd")
	if proxy_script != null:
		var proxy: StaticBody3D = StaticBody3D.new()
		proxy.set_script(proxy_script)
		proxy.position = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
		add_child(proxy)
		proxy.set("host", self)

## Aug 2026 — returns this fixture's current contribution weight for the
## removed fake-shadow decal system's aggregate shadow-direction
## calculation, or 0.0 if currently off/out of range. Dead code since that
## system was replaced by the stand-in approach (see
## docs/systems/graphics/README.md "Character shadow stand-in"); kept, not
## scheduled for removal. Deliberately simple falloff — this only needs to
## rank/blend multiple lights sensibly relative to each other, not match
## the GPU's real attenuation curve exactly.
func get_shadow_weight(from_pos: Vector3) -> float:
	if _light == null or not _light.visible:
		return 0.0
	var dist: float = global_position.distance_to(from_pos)
	if dist >= LIGHT_RANGE:
		return 0.0
	var t: float = 1.0 - (dist / LIGHT_RANGE)
	return LIGHT_ENERGY * t * t


# ─── Override all GLB mesh materials to be fully matte, no shadows ───────────
## Aug 2026 — surfaces that carry the model's authored EMISSIVE texture keep
## it (the bulb region glows, 1:1 with the authored look); everything else is
## flattened to flat matte exactly as before. The emissive surface is stored
## in _bulb_material so _apply_bulb_state() can drive its glow from the power
## / shed state.
func _apply_matte_override(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode     = GeometryInstance3D.GI_MODE_DISABLED
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for s: int in range(mesh.get_surface_count()):
				var orig: Material = mesh.surface_get_material(s)
				var sm: StandardMaterial3D = null
				if orig is StandardMaterial3D:
					sm = orig as StandardMaterial3D
				var base_color: Color = Color(0.15, 0.15, 0.18, 1.0)
				if sm != null:
					base_color = sm.albedo_color

				## GLASS SHADE (Aug 2026, Option 3) — the model's translucent
				## shade/cage. Preserve its authored transparency + textures so
				## the warm bulb glows through it, instead of flattening it to
				## an opaque matte like the body. Checked FIRST so any surface
				## the import marked transparent is never bulb/matte.
				if sm != null and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					var glass := StandardMaterial3D.new()
					glass.albedo_color    = base_color
					glass.albedo_texture  = sm.albedo_texture
					glass.transparency    = sm.transparency
					glass.alpha_scissor_threshold = sm.alpha_scissor_threshold
					glass.normal_enabled  = sm.normal_enabled
					glass.normal_texture  = sm.normal_texture
					glass.roughness_texture = sm.roughness_texture
					glass.roughness       = sm.roughness
					glass.metallic        = 0.0
					glass.specular_mode   = sm.specular_mode
					glass.shading_mode    = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					glass.cull_mode       = BaseMaterial3D.CULL_DISABLED   ## shade visible from both sides
					mi.set_surface_override_material(s, glass)
					continue

				## Bulb surface — solid WARM amber emission (the model's emissive
				## texture is a generic white blob that reads as a bright white
				## paste; a solid warm emission on the bulb surface reads as a
				## lit lamp and stays subtle). Energy starts dark, driven by
				## _apply_bulb_state().
				if sm != null and sm.emission_enabled and sm.emission_texture != null:
					var mat := StandardMaterial3D.new()
					mat.albedo_color = base_color
					mat.metallic     = 0.0
					mat.roughness    = 1.0
					mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					mat.shading_mode  = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mat.emission = LIGHT_COLOR
					mat.emission_energy_multiplier = 0.0
					mat.emission_enabled = true
					_bulb_material  = mat
					_bulb_lit_color = LIGHT_COLOR
					_bulb_lit_energy = BULB_EMISSION_ENERGY
					mi.set_surface_override_material(s, mat)
					continue

				## Plain matte body — everything else, exactly as before.
				var mat2 := StandardMaterial3D.new()
				mat2.albedo_color = base_color
				mat2.metallic     = 0.0
				mat2.roughness    = 1.0
				mat2.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat2.shading_mode  = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mi.set_surface_override_material(s, mat2)
	for child in node.get_children():
		_apply_matte_override(child)


# ─── Strip collision nodes from GLB import ───────────────────────────────────
func _remove_collision_recursive(node: Node) -> void:
	var children: Array = []
	for child in node.get_children():
		children.append(child)
	for child in children:
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.queue_free()
		elif child is StaticBody3D or child is RigidBody3D or child is Area3D:
			child.queue_free()
		else:
			_remove_collision_recursive(child)


# ─── Static helper: ghost mesh for BuildModeController ───────────────────────
static func build_ghost_mesh() -> Mesh:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.2735, 0.4300, 0.1404)
	return bm
