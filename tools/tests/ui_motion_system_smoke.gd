extends SceneTree

const SMOOTH_BAR: GDScript = preload("res://scripts/ui/common/BunkerSmoothProgressBar.gd")
const RELATIONSHIP: GDScript = preload("res://scripts/ui/npc/NPCRelationshipMeter.gd")
const GRAPH: GDScript = preload("res://scripts/ui/power/PowerTerminalLoadGraph.gd")
const GENERATOR_SCENE: PackedScene = preload("res://scenes/ui/power/GeneratorInspectPanel.tscn")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bar: ProgressBar = SMOOTH_BAR.new() as ProgressBar
	root.add_child(bar)
	await process_frame
	SMOOTH_BAR.apply(bar, 20.0)
	_check(is_equal_approx(bar.value, 20.0), "first meter value snaps truthfully")
	SMOOTH_BAR.apply(bar, 80.0)
	bar.call("_process", 0.05)
	_check(bar.value > 20.0 and bar.value < 80.0, "later meter values ease")

	var relationship: NPCRelationshipMeter = RELATIONSHIP.new() as NPCRelationshipMeter
	root.add_child(relationship)
	await process_frame
	relationship.set_target_value(-40.0)
	_check(is_equal_approx(relationship.get("_display_value"), -40.0),
		"first relationship value snaps truthfully")
	relationship.set_target_value(60.0)
	relationship.call("_process", 0.05)
	var relationship_display: float = float(relationship.get("_display_value"))
	_check(relationship_display > -40.0 and relationship_display < 60.0,
		"relationship marker eases")

	var graph: Control = GRAPH.new() as Control
	root.add_child(graph)
	graph.call("set_history", PackedFloat32Array([100.0, 200.0]),
		PackedFloat32Array([500.0, 500.0]))
	graph.call("set_history", PackedFloat32Array([100.0, 400.0]),
		PackedFloat32Array([500.0, 700.0]))
	graph.call("_process", 0.05)
	var display_draw: PackedFloat32Array = graph.get("_display_draw_history")
	_check(display_draw[1] > 200.0 and display_draw[1] < 400.0,
		"newest graph sample eases without rewriting history")
	var phase: float = graph.get("_sample_phase")
	graph.call("set_history", PackedFloat32Array([100.0, 400.0]), PackedFloat32Array([500.0, 700.0]))
	_check(float(graph.get("_sample_phase")) == phase,
		"unchanged refresh preserves graph scroll phase")
	var straight := PackedVector2Array([Vector2.ZERO, Vector2(600, 0)])
	var dense := PackedVector2Array()
	for index: int in range(201):
		dense.append(Vector2(index * 3.0, 0))
	var lengths: Array[float] = []
	for points: PackedVector2Array in [straight, dense]:
		var dashes: PackedVector2Array = graph.call("_dash_segments", points)
		var covered: float = 0.0
		for index: int in range(0, dashes.size(), 2):
			var length: float = dashes[index].distance_to(dashes[index + 1])
			_check(length <= 6.01, "capacity dash never exceeds six pixels")
			covered += length
		lengths.append(covered)
	_check(is_equal_approx(lengths[0], 360.0) and is_equal_approx(lengths[0], lengths[1]),
		"capacity dash density is independent of sample count")
	graph.set("_sample_phase", 0.0)
	var plot := Rect2(0, 0, 600, 200)
	var history := PackedFloat32Array()
	history.resize(61)
	history.fill(100.0)
	var short_points: PackedVector2Array = graph.call("_series_points", PackedFloat32Array([100.0, 100.0]), plot, 1000.0)
	var full_points: PackedVector2Array = graph.call("_series_points", history, plot, 1000.0)
	_check(is_equal_approx(short_points[1].x - short_points[0].x, 10.0) \
		and is_equal_approx(full_points[1].x - full_points[0].x, 10.0),
		"history uses a fixed seconds-per-pixel scale from first samples onward")
	graph.set("_sample_phase", 0.5)
	var scrolling_points: PackedVector2Array = graph.call("_series_points", PackedFloat32Array([100.0, 100.0]), plot, 1000.0)
	_check(is_equal_approx(scrolling_points[0].x, short_points[0].x - 5.0),
		"history scrolls continuously between samples")

	var generator_panel: Control = GENERATOR_SCENE.instantiate() as Control
	root.add_child(generator_panel)
	await process_frame
	var fuel_bar: ProgressBar = generator_panel.get_node("%FuelBar") as ProgressBar
	_check(fuel_bar is BunkerSmoothProgressBar,
		"dedicated generator meters use the shared motion component")

	bar.queue_free()
	relationship.queue_free()
	graph.queue_free()
	generator_panel.queue_free()
	if _failures == 0:
		print("UI_MOTION_SYSTEM_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("UI_MOTION_SYSTEM_SMOKE_FAIL: %s" % message)
