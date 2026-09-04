class_name PreviewPresentation
extends RefCounted

## Premium, static preview treatment.  It keeps ItemPreviewKit's isolated,
## pooled SubViewports and UPDATE_ONCE lifecycle, then adds a studio fill and
## a neutral environment.  Existing gameplay nodes are never instantiated.
static func configure(vp: SubViewport) -> void:
	if vp == null:
		return
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var world_env := WorldEnvironment.new()
	world_env.name = "PreviewEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BunkerPanelStyle.SURFACE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5dcf0")
	env.ambient_light_energy = 0.7
	world_env.environment = env
	vp.add_child(world_env)
	var fill := OmniLight3D.new()
	fill.name = "PreviewFill"
	fill.position = Vector3(-1.6, 1.0, -1.2)
	fill.light_color = Color("79bce6")
	fill.light_energy = 0.75
	fill.omni_range = 10.0
	vp.add_child(fill)
	for child in vp.get_children():
		if child is OmniLight3D and child != fill:
			child.light_color = Color("f4dca8")
			child.light_energy = 1.7

static func set_item(vp: SubViewport, item: Node) -> void:
	ItemPreviewKit.set_item(vp, item)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
