extends Node3D
class_name InteractionFocusGlow
## InteractionFocusGlow.gd  —  Focus Mode target highlight (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Rim-light outline + soft halo on whatever object Focus Mode (hold Ctrl)
## is currently highlighting. Driven by InteractionSystem calling
## set_target(node_or_null) once per _update_prompt() call — this node
## owns its own _process() for the pulse/position animation, so it stays
## correct regardless of exactly how often the caller updates the target.
##
## Rim outline: a single shared Fresnel ShaderMaterial applied via
## GeometryInstance3D.material_overlay to every MeshInstance3D found
## (recursively) under the target. This is an EXTRA render pass on top of
## each mesh's existing material — nothing about the target's own
## appearance, material, or geometry is touched or duplicated, which is
## what makes this safe to apply to any object regardless of how its mesh
## was authored (procedural primitives, GLB imports, multi-part
## assemblies like Can Case's dozen individual can visuals).
##
## Soft halo: one Sprite3D, procedurally-generated radial gradient
## texture (no external asset), billboarded to always face the camera,
## repositioned to the target's global_position every frame.
##
## Defensively coded against a freed target — is_instance_valid() checked
## every frame before touching the target or any mesh instance under it;
## clearing state on invalidity rather than assuming set_target(null)
## will always be called first (a target can be picked up, stored, or
## otherwise removed out from under Focus Mode mid-highlight).

const PULSE_SPEED:     float = 2.0    ## radians/sec — one full breath ~3.1s
const PULSE_AMPLITUDE: float = 0.22   ## +/-22% — "slightly more intense"
const RIM_BASE_INTENSITY: float = 0.6    ## drives emission_energy_multiplier directly
const RIM_BASE_ALPHA:     float = 0.6    ## drives the rim material's own albedo alpha
const HALO_BASE_ALPHA:    float = 0.75   ## more opaque
const HALO_WORLD_DIAMETER: float = 1.0   ## metres — tune in-editor per feel

var _target: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _rim_material: StandardMaterial3D = null
var _halo: Sprite3D = null
var _pulse_time: float = 0.0

func _ready() -> void:
	_rim_material = _build_rim_material()
	_halo = _build_halo_sprite()
	add_child(_halo)
	_halo.visible = false

## Aug 2026 (rethought) — replaced the hand-rolled Fresnel ShaderMaterial
## with Godot's own BUILT-IN rim/emission/transparency properties on a
## StandardMaterial3D. The custom shader produced no visible change when
## its render_mode was switched from blend_add to blend_mix, which points
## at an assumption about how material_overlay composites a custom
## shader's render_mode that I can't fully verify without the engine in
## front of me — rather than guess at more shader code, this uses
## engine-native, GUI-inspectable properties whose behavior is documented
## and predictable. rim_enabled/rim/rim_tint IS Godot's own fresnel/edge-
## highlight implementation — this is the actual "cell-shading style
## edge glow" originally asked for, using the engine's own version of it
## instead of reimplementing the math by hand.
func _build_rim_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color                = Color(1.0, 1.0, 1.0, 0.6)   ## direct opacity control
	mat.rim_enabled                 = true
	mat.rim                         = 1.0
	mat.rim_tint                    = 0.0   ## 0 = pure light color (white), ignores albedo tint
	mat.emission_enabled            = true
	mat.emission                    = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier  = 0.6   ## baseline visibility regardless of scene lighting
	mat.cull_mode                   = BaseMaterial3D.CULL_DISABLED
	return mat

func _build_halo_sprite() -> Sprite3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient   = gradient
	tex.width      = 128
	tex.height     = 128
	tex.fill       = GradientTexture2D.FILL_RADIAL
	tex.fill_from  = Vector2(0.5, 0.5)
	tex.fill_to    = Vector2(1.0, 0.5)

	var sprite := Sprite3D.new()
	sprite.texture     = tex
	sprite.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded      = false
	sprite.transparent = true
	sprite.double_sided = true
	sprite.pixel_size  = HALO_WORLD_DIAMETER / float(tex.width)
	sprite.modulate    = Color(1.0, 1.0, 1.0, 0.0)
	return sprite

## Called once per InteractionSystem._update_prompt() invocation with the
## resolved Focus Mode target (or null — no highlight this frame). Only
## rediscovers mesh instances when the target actually changes; cheap to
## call every frame regardless.
func set_target(node: Node3D) -> void:
	if node == _target:
		return
	_clear_current_overlay()
	_target = node
	if _target != null and is_instance_valid(_target):
		_mesh_instances = _find_mesh_instances(_target)
		for mi: MeshInstance3D in _mesh_instances:
			mi.material_overlay = _rim_material
	else:
		_target = null

func _clear_current_overlay() -> void:
	if _target != null and is_instance_valid(_target):
		for mi: MeshInstance3D in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = null
	_mesh_instances.clear()

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_find_mesh_instances(child))
	return result

func _process(delta: float) -> void:
	## Defensive: target freed externally (picked up, stored, deconstructed,
	## etc.) without set_target(null) ever being called — self-heal rather
	## than touch a dangling reference. Same discipline established
	## elsewhere in this file's history for held_item.
	if _target != null and not is_instance_valid(_target):
		_mesh_instances.clear()
		_target = null

	if _target == null:
		_halo.visible = false
		return

	_pulse_time += delta
	var pulse: float = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE

	## No shader uniform to drive any more — pulse the native material's
	## own properties directly. emission_energy_multiplier for the
	## baseline glow strength, albedo alpha for the rim's own opacity.
	_rim_material.emission_energy_multiplier = RIM_BASE_INTENSITY * pulse
	_rim_material.albedo_color.a = clampf(RIM_BASE_ALPHA * pulse, 0.0, 1.0)

	_halo.visible = true
	_halo.global_position = _target.global_position
	_halo.modulate.a = HALO_BASE_ALPHA * pulse