extends SceneTree
## tools/menu_terrain/bake_menu_terrain.gd — bakes the main-menu terrain mesh.
##
##   godot --headless --path . --script res://tools/menu_terrain/bake_menu_terrain.gd
##
## Loads MenuBackdrop.tscn, measures every BackdropAssetSlot's footprint
## (real asset or greybox), gives each a level pad, runs MenuTerrainBuilder
## and saves assets/menu_backdrop/terrain/menu_terrain.res. Re-run after
## moving, resizing or filling slots. Deterministic; nothing here is AI.

const BACKDROP := "res://scenes/world/menu_backdrop/MenuBackdrop.tscn"
const SLOT_SCRIPT := "res://scripts/world/menu_backdrop/BackdropAssetSlot.gd"
const OUT := "res://assets/menu_backdrop/terrain/menu_terrain.res"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backdrop: Node3D = (load(BACKDROP) as PackedScene).instantiate()
	root.add_child(backdrop)
	await process_frame
	var builder_script: GDScript = load("res://scripts/world/menu_backdrop/MenuTerrainBuilder.gd")
	var builder: RefCounted = builder_script.new()
	for slot: Node in backdrop.find_children("*", "Node3D", true, false):
		var script: Script = slot.get_script()
		if script == null or script.resource_path != SLOT_SCRIPT or slot.name == "Ground":
			continue
		## Footprint = geometry only (lights and particles have huge AABBs).
		## Spawned slot content is an internal child, so walk get_children(true).
		var box := AABB()
		var first := true
		var stack: Array[Node] = [slot]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children(true))
			if node is GeometryInstance3D and not (node is GPUParticles3D or node is CPUParticles3D):
				var gi := node as GeometryInstance3D
				var wb: AABB = gi.global_transform * gi.get_aabb()
				box = wb if first else box.merge(wb)
				first = false
		if first:
			continue
		var centre := Vector2(box.get_center().x, box.get_center().z)
		var radius: float = maxf(box.size.x, box.size.z) * 0.5 * 0.8
		var falloff: float = clampf(radius * 0.35, 2.5, 18.0)
		builder.call("add_pad", centre, radius, falloff)
		print("pad %-16s centre=(%.1f, %.1f) r=%.1f falloff=%.1f" % [slot.name, centre.x, centre.y, radius, falloff])
	var t := Time.get_ticks_msec()
	var mesh: ArrayMesh = builder.call("build")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(mesh, OUT, ResourceSaver.FLAG_COMPRESS)
	print("baked %s in %d ms: %d vertices, err=%d" % [OUT, Time.get_ticks_msec() - t,
		mesh.surface_get_array_len(0), err])
	quit(0 if err == OK else 1)
