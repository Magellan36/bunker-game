extends SceneTree
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var surface: Control = Control.new()
	root.add_child(surface)
	var bar: BunkerSmoothProgressBar = BunkerSmoothProgressBar.new()
	surface.add_child(bar)
	bar.set_target_value(10.25)
	bar.set_target_value(10.55)
	for i: int in 120:
		bar._process(1.0 / 60.0)
	check(is_equal_approx(bar.value, 10.55), "fractional meter must converge")
	surface.hide()
	bar.set_target_value(85.5)
	surface.show()
	UIFade.fade_in(surface)
	check(is_equal_approx(bar.value, 85.5), "new host snapshot must snap")
	var callback_state: Array[bool] = [false]
	UIFade.fade_out(surface, 0.05, func() -> void: callback_state[0] = true)
	UIFade.fade_in(surface, 0.01)
	await create_timer(0.10).timeout
	check(not callback_state[0] and is_equal_approx(surface.modulate.a, 1.0), "reopen cancels stale close")
	var preview: TextureRect = TextureRect.new()
	surface.add_child(preview)
	var texture: GradientTexture1D = GradientTexture1D.new()
	UIPreviewMotion.swap(preview, null, texture)
	var tween: Variant = preview.get_meta(UIPreviewMotion.TWEEN_META)
	UIPreviewMotion.swap(preview, null, texture)
	check(preview.get_meta(UIPreviewMotion.TWEEN_META) == tween, "no-op preview refresh retains tween")
	var second: GradientTexture1D = GradientTexture1D.new()
	UIPreviewMotion.swap(preview, null, second)
	check(preview.texture == second, "preview reflects latest selection immediately")
	var panel: PanelContainer = PanelContainer.new()
	root.add_child(panel)
	for viewport: Vector2 in [Vector2(1920,1080), Vector2(1280,720), Vector2(2560,1440)]:
		UIPanelLayout.fit(panel, viewport, Vector2(440,760), Vector2(24,24), 1.0)
		check(panel.position.y >= 24 and panel.get_rect().end.y <= viewport.y - 24, "panel vertical bounds")
		check(is_equal_approx(panel.get_rect().end.x, viewport.x - 24), "panel right edge")
	var previous_reduced: bool = UIMotion.reduced()
	UIMotion.set_reduced(true)
	UIFade.fade_in(surface)
	check(is_equal_approx(surface.modulate.a, 1.0), "reduced motion is immediate")
	bar.set_target_value(40.4)
	bar._process(0.016)
	check(is_equal_approx(bar.value, 40.4), "reduced motion snaps meter")
	UIMotion.set_reduced(previous_reduced)
	print("UI_CONSISTENCY_FOUNDATIONS: %d failures" % failures)
	quit(failures)
