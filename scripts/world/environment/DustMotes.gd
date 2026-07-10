class_name DustMotes
extends RefCounted
## DustMotes.gd
## Small reusable factory for the graphics-overhaul's dust-mote GPUParticles3D
## systems (graphics plan Section 4, VFX priorities #1/#2). Two flavors:
## - create_beam_dust(): local-space, meant as a child of a SpotLight3D (e.g.
##   Flashlight.gd) — drifts slowly through the beam cone.
## - create_ambient_dust(bounds_size): world-space, sparse, covers a room/
##   bunker volume — mostly invisible except where something else lights it.
##
## Uses a procedurally-generated placeholder texture
## (assets/textures/vfx/soft_glow_dot.png) — swap for real art in the Phase 4
## materials pass without touching any of this file's particle logic.
##
## Pure factory functions (RefCounted, no instance state) — call
## DustMotes.create_beam_dust(...) directly, no .new() needed.

const DUST_TEXTURE_PATH: String = "res://assets/textures/vfx/soft_glow_dot.png"


static func create_beam_dust(spread_deg: float) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount       = 24
	p.lifetime     = 3.0
	p.local_coords = true   ## drifts with the light/beam rather than staying in world space
	p.draw_pass_1  = _dust_quad_mesh(0.012, Color(1.0, 0.95, 0.85, 0.35))

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction            = Vector3(0.0, 0.0, 1.0)
	mat.spread               = spread_deg
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.18
	mat.gravity              = Vector3.ZERO
	mat.damping_min          = 0.05
	mat.damping_max          = 0.15
	mat.scale_min            = 0.6
	mat.scale_max            = 1.4
	mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.08
	p.process_material = mat
	return p


static func create_ambient_dust(bounds_size: Vector3) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount       = 40
	p.lifetime     = 8.0
	p.local_coords = false   ## world space — stays put as the player walks through it
	p.draw_pass_1  = _dust_quad_mesh(0.01, Color(0.85, 0.85, 0.8, 0.12))

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction            = Vector3(0.0, 1.0, 0.0)
	mat.spread               = 180.0
	mat.initial_velocity_min = 0.01
	mat.initial_velocity_max = 0.04
	mat.gravity              = Vector3.ZERO
	mat.scale_min            = 0.5
	mat.scale_max            = 1.2
	mat.emission_shape       = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = bounds_size * 0.5
	p.process_material = mat
	return p


static func _dust_quad_mesh(size: float, tint: Color) -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(size, size)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture   = load(DUST_TEXTURE_PATH)
	mat.albedo_color     = tint
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode       = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode   = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	return mesh
