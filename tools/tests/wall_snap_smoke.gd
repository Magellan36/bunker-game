extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path: String in [
		"res://scripts/world/power/WireDrawMode.gd",
		"res://scripts/world/water/WaterPipeDrawMode.gd",
	]:
		var draw_script: GDScript = load(path)
		if draw_script == null or not draw_script.can_instantiate():
			push_error("Draw mode failed to compile: " + path)
			quit(1)
			return
	var fixture: GDScript = load("res://tools/tests/fixtures/wall_snap_fixture.gd")
	if fixture == null or not fixture.can_instantiate():
		quit(1)
		return
	root.add_child(fixture.new())
