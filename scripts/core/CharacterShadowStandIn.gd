class_name CharacterShadowStandIn
## CharacterShadowStandIn.gd
## Aug 2026 — real shadow-casting via a shortened, invisible stand-in mesh,
## replacing the CharacterShadowDecal fake-shadow system entirely (see
## docs/systems/graphics/README.md "Character shadow stand-in" and
## "Character shadow decal" for the prior system's postmortem). The
## character's actual visible mesh keeps cast_shadow = OFF (still doesn't
## cast its own — see Player.gd/NPC.gd); this stand-in casts a REAL
## shadow in its place, using Godot's native shadow-only mode. Because
## it's genuinely shorter geometry, its shadow is proportionally shorter
## at every light angle automatically — no custom direction/length/
## opacity logic, no per-frame script. Real shadow mapping does all of it.
##
## Static utility, not a Node subclass — there is nothing to update per
## frame. Call attach() once from Player._ready()/NPC._ready(); the
## resulting mesh moves with its parent automatically via normal
## scene-tree transform inheritance.

## Stand-in height as a fraction of the character's own real height.
## Shorter = a shorter, less dramatic shadow at any light angle (this is
## the actual "make the shadow less long" control) — single number with
## no other coupled effects, adjust freely.
## Lowered to 0.3 (Aug 2026) — a further step down from the earlier 0.35
## pass, per continued request for a shorter shadow at any given light
## angle. If still too long/short after in-editor review, retune this
## value alone — nothing else in this file or its callers needs to change.
const HEIGHT_FACTOR: float = 0.3

## Fallbacks if the character's own CollisionShape3D/CapsuleShape3D can't
## be found — matches Player.tscn's own defaults (Godot's default capsule:
## height 2.0, radius 0.5) so a structural change elsewhere degrades
## gracefully instead of erroring.
const FALLBACK_HEIGHT: float = 2.0
const FALLBACK_RADIUS: float = 0.5

## Builds and attaches the stand-in mesh as a child of owner_char. Call
## once from _ready(), after `mesh` (the character's own visible
## MeshInstance3D) and its layers/cast_shadow are already set up, since
## this reads Player.PLAYER_SELF_LIGHT_LAYER_BIT to match it.
static func attach(owner_char: Node3D) -> void:
	var real_height: float = FALLBACK_HEIGHT
	var real_radius: float = FALLBACK_RADIUS
	var collision_node: Node = owner_char.get_node_or_null("CollisionShape3D")
	if collision_node is CollisionShape3D:
		var shape: Shape3D = (collision_node as CollisionShape3D).shape
		if shape is CapsuleShape3D:
			var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
			real_height = capsule_shape.height
			real_radius = capsule_shape.radius

	var stand_in_height: float = real_height * HEIGHT_FACTOR

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "ShadowStandIn"
	var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
	capsule_mesh.height = stand_in_height
	capsule_mesh.radius = real_radius
	mesh_instance.mesh = capsule_mesh

	## Never rendered to camera, fully participates in real shadow
	## mapping — Godot's purpose-built mode for an invisible shadow-only
	## proxy. `visible` stays true; SHADOWS_ONLY is what makes it
	## camera-invisible, not node visibility (setting visible=false would
	## skip it from the shadow pass too). VERIFY IN-EDITOR: this is a
	## standard, documented Godot behavior but hasn't been visually
	## confirmed in this project specifically.
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

	## Same render-layer tag as the character's own visible mesh, so
	## Flashlight.gd's existing self-shadow exclusion (established long
	## before this whole saga, still working) applies here too — without
	## this, the flashlight's old self-shadow-dome problem would
	## reappear, just from the stand-in instead of the visible mesh.
	## Confirmed against current Player.gd: PLAYER_SELF_LIGHT_LAYER_BIT is
	## a class-level const (not inside _ready()), so a direct property
	## access works for the Player case. NPCs have no such override (see
	## NPC.gd's _ready() — no mesh.layers line at all), so the "in"
	## check below simply falls through to the default layers for them,
	## matching how their visible mesh is already treated.
	if "PLAYER_SELF_LIGHT_LAYER_BIT" in owner_char:
		mesh_instance.layers = owner_char.PLAYER_SELF_LIGHT_LAYER_BIT

	## Position the stand-in's OWN base at the exact same floor contact
	## point the character's real feet are at — not just shrunk from the
	## character's own center, which would lift its base off the ground.
	## Both capsules are centered on their own local origin: the real
	## character's floor is at local Y = -real_height/2 (origin is the
	## capsule's center); solving for the stand-in's center Y so ITS base
	## lands at that same floor level gives this offset. This is what
	## makes the result "the same shadow, just from shorter geometry
	## standing in the same spot" rather than an arbitrarily
	## repositioned shape.
	var y_offset: float = -(real_height * 0.5) * (1.0 - HEIGHT_FACTOR)
	mesh_instance.position = Vector3(0.0, y_offset, 0.0)

	owner_char.add_child(mesh_instance)