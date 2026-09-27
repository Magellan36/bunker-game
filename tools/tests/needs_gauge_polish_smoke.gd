extends SceneTree

const NEEDS_GAUGE: GDScript = preload("res://scripts/ui/hud/NeedsGauge.gd")


func _init() -> void:
	var gauge: NeedsGauge = NEEDS_GAUGE.new()
	root.add_child(gauge)
	await process_frame
	_assert_true(is_equal_approx(gauge.GAUGE_ROTATION, -PI / 4.0), "gauge is rotated counter-clockwise")
	_assert_true(gauge.custom_minimum_size == Vector2(180.0, 180.0), "compact HUD footprint is preserved")
	var segments: PackedFloat32Array = gauge.symmetric_cap_segments(0.90)
	var full_lock: float = segments[1] - segments[0]
	var zero_lock: float = segments[3] - segments[2]
	_assert_true(is_equal_approx(full_lock, zero_lock), "medical cap is divided equally across both ends")
	var total_sweep: float = segments[3] - segments[0]
	var usable_sweep: float = segments[2] - segments[1]
	_assert_true(absf(usable_sweep / total_sweep - 0.90) < 0.001, "a 90 percent cap leaves 90 percent usable arc")
	gauge.set_food_cap(0.70)
	gauge.set_food(0.35)
	_assert_true(is_equal_approx(gauge._food_cap, 0.70), "existing cap API remains functional")
	_assert_true(is_equal_approx(gauge._food, 0.35), "existing value API remains functional")
	## D1 quiet palette: calm identity at rest, WARNING/RED only when low,
	## and no discontinuity across either threshold.
	_assert_true(NeedsGauge.need_color(NeedsGauge.COLOR_WATER, 0.8) == NeedsGauge.COLOR_WATER, "calm identity at rest")
	_assert_true(NeedsGauge.need_color(NeedsGauge.COLOR_WATER, 0.2) == BunkerDesign.WARNING, "low need reads as warning")
	_assert_true(NeedsGauge.need_color(NeedsGauge.COLOR_WATER, 0.05) == BunkerDesign.RED, "critical need reads as red")
	var previous: Color = NeedsGauge.need_color(NeedsGauge.COLOR_HEALTH, 0.4)
	for step: int in range(400):
		var value: float = 0.4 - float(step) * 0.001
		var next: Color = NeedsGauge.need_color(NeedsGauge.COLOR_HEALTH, value)
		_assert_true(absf(next.r - previous.r) + absf(next.g - previous.g) + absf(next.b - previous.b) < 0.08,
			"need colour changes continuously at %.3f" % value)
		previous = next
	_assert_true(gauge.material is ShaderMaterial, "worn grime overlay restored (Brannon review)")
	gauge.queue_free()
	print("needs_gauge_polish_smoke: PASS")
	quit(0)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("needs_gauge_polish_smoke: " + message)
	quit(1)
